import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_archive/flutter_archive.dart';
import '../models/firmware_release.dart';
import 'manifest.dart';

/// Service for managing firmware updates from GitHub releases
class FirmwareUpdateService {
  static const String _repoOwner = 'Protocentral';
  static const String _repoName = 'healthypi-move-fw';
  static const String _apiBase = 'https://api.github.com';

  /// Fetch the latest firmware release from GitHub
  static Future<FirmwareRelease?> getLatestRelease() async {
    try {
      final url = Uri.parse('$_apiBase/repos/$_repoOwner/$_repoName/releases/latest');
      print('[FirmwareUpdateService] Fetching latest release from: $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final release = FirmwareRelease.fromGitHubJson(json);
        print('[FirmwareUpdateService] Latest release: ${release.version}');
        return release;
      } else {
        print('[FirmwareUpdateService] Failed to fetch latest release: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[FirmwareUpdateService] Error fetching latest release: $e');
      return null;
    }
  }

  /// Check if an update is available by comparing versions
  static bool isUpdateAvailable(String currentVersion, String latestVersion) {
    try {
      // Remove 'v' prefix if present
      final current = currentVersion.trim().toLowerCase();
      final latest = latestVersion.trim().toLowerCase();

      final currentClean = current.startsWith('v') ? current.substring(1) : current;
      final latestClean = latest.startsWith('v') ? latest.substring(1) : latest;

      // Parse version parts (major.minor.patch)
      final currentParts = currentClean.split('.').map((p) {
        try {
          return int.parse(p);
        } catch (e) {
          return 0;
        }
      }).toList();

      final latestParts = latestClean.split('.').map((p) {
        try {
          return int.parse(p);
        } catch (e) {
          return 0;
        }
      }).toList();

      // Ensure we have at least 3 parts
      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      // Compare major.minor.patch
      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) {
          print('[FirmwareUpdateService] Update available: $currentClean -> $latestClean');
          return true;
        }
        if (latestParts[i] < currentParts[i]) {
          print('[FirmwareUpdateService] Current version is newer: $currentClean > $latestClean');
          return false;
        }
      }

      print('[FirmwareUpdateService] Versions are equal: $currentClean == $latestClean');
      return false; // Versions are equal
    } catch (e) {
      print('[FirmwareUpdateService] Version comparison error: $e');
      return false;
    }
  }

  /// Download firmware to cache directory
  static Future<File?> downloadFirmware(
    FirmwareRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final cacheDir = await _getFirmwareCacheDir();
      final fileName = 'healthypi_move_update_v${release.version}.zip';
      final file = File('${cacheDir.path}/$fileName');

      // Check if already cached
      if (await file.exists()) {
        final fileSize = await file.length();
        print('[FirmwareUpdateService] Using cached firmware: ${file.path} ($fileSize bytes)');
        // Simulate progress callback for cached file
        if (onProgress != null && release.fileSize != null) {
          onProgress(release.fileSize!, release.fileSize!);
        }
        return file;
      }

      // Validate download URL
      if (release.downloadUrl.isEmpty) {
        print('[FirmwareUpdateService] No download URL in release');
        return null;
      }

      // Download firmware
      print('[FirmwareUpdateService] Downloading firmware from: ${release.downloadUrl}');
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(release.downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        print('[FirmwareUpdateService] Download failed: ${streamedResponse.statusCode}');
        client.close();
        return null;
      }

      final contentLength = streamedResponse.contentLength ?? release.fileSize ?? 0;
      int received = 0;
      final sink = file.openWrite();

      await for (var chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, contentLength > 0 ? contentLength : received);
      }

      await sink.close();
      client.close();

      final finalSize = await file.length();
      print('[FirmwareUpdateService] Firmware downloaded: ${file.path} ($finalSize bytes)');
      return file;
    } catch (e) {
      print('[FirmwareUpdateService] Download error: $e');
      return null;
    }
  }

  /// Extract firmware and load manifest
  static Future<({Directory extractedDir, Manifest manifest})?> extractFirmware(File zipFile) async {
    try {
      final cacheDir = await _getFirmwareCacheDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extractedDir = Directory('${cacheDir.path}/extracted_$timestamp');

      // Clean up directory if it exists
      if (await extractedDir.exists()) {
        await extractedDir.delete(recursive: true);
      }
      await extractedDir.create(recursive: true);

      print('[FirmwareUpdateService] Extracting firmware to: ${extractedDir.path}');

      // Extract ZIP
      await ZipFile.extractToDirectory(
        zipFile: zipFile,
        destinationDir: extractedDir,
      );

      // Read manifest.json
      final manifestFile = File('${extractedDir.path}/manifest.json');
      if (!await manifestFile.exists()) {
        throw Exception('manifest.json not found in firmware package');
      }

      final manifestString = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestString) as Map<String, dynamic>;
      final manifest = Manifest.fromJson(manifestJson);

      print('[FirmwareUpdateService] Firmware extracted with ${manifest.files.length} images');

      // Validate that all firmware files exist
      for (final file in manifest.files) {
        final firmwareFile = File('${extractedDir.path}/${file.file}');
        if (!await firmwareFile.exists()) {
          throw Exception('Firmware file not found: ${file.file}');
        }
      }

      return (extractedDir: extractedDir, manifest: manifest);
    } catch (e, stackTrace) {
      print('[FirmwareUpdateService] Extraction error: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Get firmware cache directory
  static Future<Directory> _getFirmwareCacheDir() async {
    final cacheDir = await getTemporaryDirectory();
    final firmwareDir = Directory('${cacheDir.path}/firmware_cache');
    if (!await firmwareDir.exists()) {
      await firmwareDir.create(recursive: true);
    }
    return firmwareDir;
  }

  /// Clear old cached firmware files
  static Future<void> clearCache() async {
    try {
      final cacheDir = await _getFirmwareCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create();
      }
      print('[FirmwareUpdateService] Cache cleared');
    } catch (e) {
      print('[FirmwareUpdateService] Cache clear error: $e');
    }
  }

  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getFirmwareCacheDir();
      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('[FirmwareUpdateService] Cache size error: $e');
      return 0;
    }
  }

  /// Format cache size for display
  static String formatCacheSize(int bytes) {
    if (bytes == 0) return 'Empty';

    final sizeInMB = bytes / (1024 * 1024);
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(2)} MB';
    } else {
      final sizeInKB = bytes / 1024;
      return '${sizeInKB.toStringAsFixed(0)} KB';
    }
  }
}
