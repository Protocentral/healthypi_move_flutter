import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/firmware_release.dart';
import 'firmware_update_service.dart';

/// Background update checker for firmware updates
/// Checks for updates when device connects and caches results
class UpdateChecker {
  static const String _prefKeyAutoCheck = 'auto_check_updates';
  static const String _prefKeyLastCheck = 'last_update_check';
  static const String _prefKeyLastRelease = 'last_release_data';
  static const String _prefKeyCurrentVersion = 'device_current_version';
  static const String _prefKeyUpdateAvailable = 'update_available';

  // Cache duration - only check once per day
  static const Duration _cacheValidDuration = Duration(hours: 24);

  /// Check if auto-check is enabled (default: true)
  static Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyAutoCheck) ?? true; // Default to enabled
  }

  /// Enable or disable auto-check
  static Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAutoCheck, enabled);

    if (!enabled) {
      // Clear cached data when disabled
      await _clearCache();
    }
  }

  /// Check for updates in background when device connects
  /// Returns true if update is available
  static Future<bool> checkForUpdatesInBackground(BluetoothDevice device) async {
    try {
      // Check if auto-check is enabled
      if (!await isAutoCheckEnabled()) {
        print('[UpdateChecker] Auto-check disabled');
        return false;
      }

      // Check if we have a valid cached result
      if (await _hasCachedResult()) {
        print('[UpdateChecker] Using cached result');
        return await _getCachedUpdateStatus();
      }

      print('[UpdateChecker] Running background update check...');

      // Read current firmware version from device
      final currentVersion = await _readFirmwareVersion(device);
      if (currentVersion == null || currentVersion == 'Unknown') {
        print('[UpdateChecker] Could not read firmware version');
        return false;
      }

      // Fetch latest release from GitHub
      final latestRelease = await FirmwareUpdateService.getLatestRelease();
      if (latestRelease == null) {
        print('[UpdateChecker] Could not fetch latest release');
        return false;
      }

      // Check if update is available
      final updateAvailable = FirmwareUpdateService.isUpdateAvailable(
        currentVersion,
        latestRelease.version,
      );

      // Cache the result
      await _cacheResult(currentVersion, latestRelease, updateAvailable);

      print('[UpdateChecker] Update available: $updateAvailable (current: $currentVersion, latest: ${latestRelease.version})');

      return updateAvailable;
    } catch (e) {
      print('[UpdateChecker] Error during background check: $e');
      return false;
    }
  }

  /// Get cached update status without checking again
  static Future<bool> getCachedUpdateStatus() async {
    if (!await _hasCachedResult()) {
      return false;
    }
    return await _getCachedUpdateStatus();
  }

  /// Get cached firmware release info
  static Future<FirmwareRelease?> getCachedRelease() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final releaseJson = prefs.getString(_prefKeyLastRelease);

      if (releaseJson == null) {
        return null;
      }

      final releaseData = jsonDecode(releaseJson) as Map<String, dynamic>;
      return FirmwareRelease.fromGitHubJson(releaseData);
    } catch (e) {
      print('[UpdateChecker] Error reading cached release: $e');
      return null;
    }
  }

  /// Get cached current version
  static Future<String?> getCachedCurrentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyCurrentVersion);
  }

  /// Clear cached update check data (force re-check on next connection)
  static Future<void> clearCache() async {
    await _clearCache();
  }

  /// Read firmware version from connected device
  static Future<String?> _readFirmwareVersion(BluetoothDevice device) async {
    try {
      if (device.isDisconnected) {
        return null;
      }

      final services = await device.discoverServices();

      // Look for Device Information Service (0x180A)
      for (var service in services) {
        if (service.uuid == Guid("180a")) {
          // Look for Firmware Revision String characteristic (0x2A26)
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid("2a26")) {
              final value = await characteristic.read();
              return String.fromCharCodes(value).trim();
            }
          }
        }
      }

      return null;
    } catch (e) {
      print('[UpdateChecker] Error reading firmware version: $e');
      return null;
    }
  }

  /// Check if we have a valid cached result
  static Future<bool> _hasCachedResult() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckStr = prefs.getString(_prefKeyLastCheck);

    if (lastCheckStr == null) {
      return false;
    }

    try {
      final lastCheck = DateTime.parse(lastCheckStr);
      final now = DateTime.now();
      final age = now.difference(lastCheck);

      return age < _cacheValidDuration;
    } catch (e) {
      return false;
    }
  }

  /// Get cached update status
  static Future<bool> _getCachedUpdateStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyUpdateAvailable) ?? false;
  }

  /// Cache update check result
  static Future<void> _cacheResult(
    String currentVersion,
    FirmwareRelease latestRelease,
    bool updateAvailable,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Store the raw GitHub API response for the release
    // We'll need to get this from the service, but for now we'll reconstruct it
    final releaseData = {
      'tag_name': latestRelease.tagName,
      'name': latestRelease.name,
      'body': latestRelease.body,
      'published_at': latestRelease.publishedAt.toIso8601String(),
      'assets': [
        {
          'name': 'healthypi_move_update_v${latestRelease.version}.zip',
          'browser_download_url': latestRelease.downloadUrl,
          'size': latestRelease.fileSize,
        }
      ],
    };

    await prefs.setString(_prefKeyLastCheck, DateTime.now().toIso8601String());
    await prefs.setString(_prefKeyLastRelease, jsonEncode(releaseData));
    await prefs.setString(_prefKeyCurrentVersion, currentVersion);
    await prefs.setBool(_prefKeyUpdateAvailable, updateAvailable);
  }

  /// Clear cached data
  static Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyLastCheck);
    await prefs.remove(_prefKeyLastRelease);
    await prefs.remove(_prefKeyCurrentVersion);
    await prefs.remove(_prefKeyUpdateAvailable);
  }
}
