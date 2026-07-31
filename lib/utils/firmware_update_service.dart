// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/firmware_release.dart';
import '../ble/device_generation.dart';
import 'manifest.dart';

/// Service for managing firmware updates from GitHub releases
class FirmwareUpdateService {
  static const String _repoOwner = 'Protocentral';
  static const String _repoName = 'healthypi-move-fw';
  static const String _apiBase = 'https://api.github.com';

  /// Last release payload we successfully fetched, and when. Persisted so a
  /// startup check does not have to hit the network on every cold start.
  static const String _cachedReleaseKey = 'fw_latest_release_json';
  static const String _cachedReleaseAtKey = 'fw_latest_release_fetched_at';

  /// Fetch the latest firmware release from GitHub.
  ///
  /// [cacheTtl] serves the persisted copy without a network call while it is
  /// younger than that. The GitHub releases API is unauthenticated here and
  /// therefore rate-limited to 60 requests/hour **per IP** — shared by every
  /// user behind one NAT — so the periodic background check must not poll it
  /// freshly each time. Pass `null` (the default) for a user-initiated check,
  /// which should always try the network.
  ///
  /// Whatever the TTL, a failed fetch falls back to the cached copy at **any**
  /// age: a stale version number is strictly more useful than "could not check",
  /// and the DFU flow re-validates against the device before flashing anything.
  static Future<FirmwareRelease?> getLatestRelease({Duration? cacheTtl}) async {
    if (cacheTtl != null) {
      final cached = await _readCachedRelease(maxAge: cacheTtl);
      if (cached != null) {
        print('[FirmwareUpdateService] Using cached release: ${cached.version}');
        return cached;
      }
    }

    try {
      final url = Uri.parse('$_apiBase/repos/$_repoOwner/$_repoName/releases/latest');
      print('[FirmwareUpdateService] Fetching latest release from: $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final release = FirmwareRelease.fromGitHubJson(json);
        print('[FirmwareUpdateService] Latest release: ${release.version}');
        await _writeCachedRelease(response.body);
        return release;
      } else {
        print('[FirmwareUpdateService] Failed to fetch latest release: ${response.statusCode}');
        return await _readCachedRelease();
      }
    } catch (e) {
      print('[FirmwareUpdateService] Error fetching latest release: $e');
      return await _readCachedRelease();
    }
  }

  /// The cached release, or null when absent, unparseable, or older than
  /// [maxAge]. Omit [maxAge] to accept it at any age (the offline fallback).
  static Future<FirmwareRelease?> _readCachedRelease({Duration? maxAge}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_cachedReleaseKey);
      if (body == null || body.isEmpty) return null;

      if (maxAge != null) {
        final at = prefs.getInt(_cachedReleaseAtKey);
        if (at == null) return null;
        final age = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(at));
        // A negative age means the phone's clock moved backwards; treat that as
        // expired rather than trusting a cache that claims to be from the future.
        if (age.isNegative || age > maxAge) return null;
      }

      return FirmwareRelease.fromGitHubJson(
          jsonDecode(body) as Map<String, dynamic>);
    } catch (e) {
      print('[FirmwareUpdateService] Cached release unreadable: $e');
      return null;
    }
  }

  static Future<void> _writeCachedRelease(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedReleaseKey, body);
      await prefs.setInt(
          _cachedReleaseAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('[FirmwareUpdateService] Could not cache release: $e');
    }
  }

  /// Check if [latestVersion] is strictly newer than [currentVersion].
  ///
  /// Both strings are parsed with [FirmwareVersion], which strips MCUboot build
  /// metadata and pre-release suffixes (`"3.0.2+0"`, `"v3.0.2"`, `"3.0.2-rc1"`
  /// all compare as `3.0.2`). The `+0` is the MCUboot image build number and is
  /// present on every device's DIS firmware-revision string — comparing it
  /// literally makes every equal-version release look like an upgrade, which
  /// nags the user forever and then fails the re-flash (MCUboot rejects an image
  /// that is not strictly higher than the running one). See the note on the
  /// `3.0.2+0` wire format in device_generation.dart.
  static bool isUpdateAvailable(String currentVersion, String latestVersion) {
    final current = FirmwareVersion.tryParse(currentVersion);
    final latest = FirmwareVersion.tryParse(latestVersion);

    // Unparseable input tells us nothing — do not nag on nothing.
    if (current == null || latest == null) {
      print('[FirmwareUpdateService] Unparseable version '
          '(current: "$currentVersion", latest: "$latestVersion") — treating as up to date');
      return false;
    }

    final available = latest > current; // strictly newer only; equal ⇒ false
    print('[FirmwareUpdateService] $current vs $latest -> '
        '${available ? "update available" : "up to date"}');
    return available;
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
