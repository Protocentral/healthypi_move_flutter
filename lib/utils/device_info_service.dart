// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';

import 'ble_manager.dart';

/// Reads the standard Device Information Service.
///
/// The firmware-revision read (DIS `0x180A` → `0x2A26`) was implemented three
/// separate times — in `BackgroundSyncManager`, in `UpdateChecker`, and inline
/// in the DFU screen — each with its own error handling and its own idea of what
/// "unknown" means. Same two magic strings, three behaviours.
class DeviceInfoService {
  /// Device Information Service.
  static const String disService = '180a';

  /// Firmware Revision String characteristic.
  static const String firmwareRevisionChar = '2a26';

  /// Read the firmware revision from [deviceId], or null if it can't be read.
  ///
  /// Null means "we don't know" — not "old". Callers must not treat an
  /// unreadable version as a failed version check; see [isAtLeast].
  static Future<String?> readFirmwareVersion(String deviceId) async {
    try {
      if (!await BleManager.instance.isConnected(deviceId)) return null;
      final value =
          await BleManager.instance.read(deviceId, disService, firmwareRevisionChar);
      final version = String.fromCharCodes(value).trim();
      return version.isEmpty ? null : version;
    } catch (e) {
      debugPrint('[DeviceInfo] firmware version read failed: $e');
      return null;
    }
  }

  /// Whether [version] is at least [major].[minor].
  ///
  /// An unreadable or unparseable version returns [onUnknown] (default true —
  /// permit the operation). Blocking a sync because a characteristic read
  /// flaked is worse than running it: the sync itself will fail cleanly if the
  /// firmware really is too old, whereas a false "unsupported firmware" sends
  /// the user to a firmware update they don't need.
  static bool isAtLeast(
    String? version, {
    required int major,
    required int minor,
    bool onUnknown = true,
  }) {
    if (version == null || version.isEmpty || version == 'unknown') {
      debugPrint('[DeviceInfo] version unknown — assuming supported');
      return onUnknown;
    }
    try {
      final clean =
          version.toLowerCase().startsWith('v') ? version.substring(1) : version;
      final parts = clean.split('.');
      if (parts.length < 2) return onUnknown;

      final gotMajor = int.tryParse(parts[0]) ?? 0;
      final gotMinor = int.tryParse(parts[1].split('-').first) ?? 0;

      if (gotMajor != major) return gotMajor > major;
      return gotMinor >= minor;
    } catch (e) {
      debugPrint('[DeviceInfo] could not parse version "$version": $e');
      return onUnknown;
    }
  }
}
