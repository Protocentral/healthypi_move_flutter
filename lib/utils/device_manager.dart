// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../device/device_profile.dart';
import '../models/device_info.dart';

/// Unified device management utility for HealthyPi Move pairing
/// Handles device storage, retrieval, and migration from legacy format
class DeviceManager {
  static const String _deviceInfoKey = 'paired_device_info';
  static const String _legacyPairedStatusKey = 'pairedStatus';
  static const String _legacyDeviceNameKey = 'paired_device_name';
  static const String _legacyMacFileName = 'paired_device_mac.txt';

  /// Bumped whenever the paired device changes (pair, update, unpair).
  ///
  /// Pairing state is read once in `initState` by long-lived screens (the shell
  /// keeps its tabs alive in an IndexedStack), so without this they'd keep
  /// showing "No watch paired" after a pair completed on another screen. Screens
  /// listen and re-read; the value itself is just a revision counter.
  static final ValueNotifier<int> pairingRevision = ValueNotifier<int>(0);

  /// Which product is paired, and therefore which features exist.
  ///
  /// Deliberately **not** derived from the live connection. The app is
  /// foreground-sync only, so the BLE link is down most of the time the user is
  /// looking at the UI; keying layout off connection state would make Home's row
  /// list reflow every time a sync finished. Pairing is persistent and available
  /// at first frame, which is what the UI needs.
  ///
  /// Same read-once-then-listen contract as [pairingRevision]: the shell keeps
  /// its tabs alive in an `IndexedStack`, so screens read this in `initState`
  /// and listen for changes.
  ///
  /// Defaults to the Move profile rather than `unknown` — see
  /// [DeviceProfile.forStoredModel] for why null must not mean "unknown device".
  static final ValueNotifier<DeviceProfile> activeProfile =
      ValueNotifier<DeviceProfile>(DeviceProfile.moveNext);

  static void _notifyPairingChanged() => pairingRevision.value++;

  /// Keep [activeProfile] in step with what is stored. Cheap and idempotent —
  /// `ValueNotifier` only notifies when the value actually changes, and the
  /// profiles are const singletons, so an unchanged device is a no-op.
  static void _applyProfile(DeviceInfo? deviceInfo) {
    activeProfile.value = deviceInfo == null
        ? DeviceProfile.moveNext
        : DeviceProfile.forStoredModel(deviceInfo.model);
  }

  /// Record the product this device reported in its HPI_HS `HELLO`.
  ///
  /// Called on every sync, so it must be a no-op when nothing changed: writing
  /// unconditionally would bump [pairingRevision] each time and trigger a
  /// needless reload on every screen listening to it.
  ///
  /// [dev] is the raw `HELLO.dev` wire string. An unrecognised value is still
  /// stored — a support log wants the actual string, and
  /// [DeviceProfile.forStoredModel] maps anything it cannot place to
  /// [DeviceProfile.unknown], which is the conservative profile.
  static Future<void> updateModel(String? dev) async {
    final trimmed = dev?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final deviceInfo = await getPairedDevice();
    if (deviceInfo == null) return;
    if (deviceInfo.model == trimmed) return; // unchanged — do not churn

    await savePairedDevice(deviceInfo.copyWith(model: trimmed));
    print('DeviceManager: device model resolved to "$trimmed"');
  }

  /// Save paired device information
  static Future<void> savePairedDevice(DeviceInfo deviceInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(deviceInfo.toJson());
    await prefs.setString(_deviceInfoKey, jsonString);
    _applyProfile(deviceInfo);

    // Also maintain legacy format for backward compatibility during transition
    await prefs.setString(_legacyPairedStatusKey, 'paired');
    await prefs.setString(_legacyDeviceNameKey, deviceInfo.deviceName);

    print('DeviceManager: Saved device info for ${deviceInfo.displayName}');
    _notifyPairingChanged();
  }
  
  /// Get paired device information
  static Future<DeviceInfo?> getPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Try new format first
    final jsonString = prefs.getString(_deviceInfoKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final info = DeviceInfo.fromJson(json);
        // Keep the profile fresh without needing every caller to remember to.
        // This is the app's most-called device read, and it is a pure setter on
        // a ValueNotifier that no-ops when unchanged.
        _applyProfile(info);
        return info;
      } catch (e) {
        print('DeviceManager: Error parsing device info: $e');
        // Fall through to migration logic
      }
    }
    
    // Migration: Try to import from old format
    return await _migrateFromLegacyFormat();
  }
  
  /// Migrate device info from old storage format
  static Future<DeviceInfo?> _migrateFromLegacyFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final pairedStatus = prefs.getString(_legacyPairedStatusKey);
    
    if (pairedStatus != 'paired') {
      return null;
    }
    
    try {
      // Read MAC address from file
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final File macFile = File('${appDocDir.path}/$_legacyMacFileName');
      
      if (!await macFile.exists()) {
        return null;
      }
      
      final macAddress = (await macFile.readAsString()).trim();
      final deviceName = prefs.getString(_legacyDeviceNameKey) ?? 'healthypi move';
      
      // Create new format device info
      final deviceInfo = DeviceInfo(
        macAddress: macAddress,
        deviceName: deviceName,
        nickname: '',
        firstPaired: DateTime.now(), // Approximate - we don't have historical data
        lastConnected: DateTime.now(),
      );
      
      // Save in new format
      await savePairedDevice(deviceInfo);
      
      print('DeviceManager: Migrated legacy device to new format');
      
      return deviceInfo;
    } catch (e) {
      print('DeviceManager: Migration failed: $e');
      return null;
    }
  }
  
  /// Update last connected timestamp
  static Future<void> updateLastConnected() async {
    final deviceInfo = await getPairedDevice();
    if (deviceInfo != null) {
      final updated = deviceInfo.copyWith(
        lastConnected: DateTime.now(),
      );
      await savePairedDevice(updated);
      print('DeviceManager: Updated last connected time');
    }
  }
  
  /// Update device nickname
  static Future<void> updateNickname(String nickname) async {
    final deviceInfo = await getPairedDevice();
    if (deviceInfo != null) {
      final updated = deviceInfo.copyWith(nickname: nickname);
      await savePairedDevice(updated);
      print('DeviceManager: Updated nickname to "$nickname"');
    }
  }
  
  /// Update firmware version
  static Future<void> updateFirmwareVersion(String version) async {
    final deviceInfo = await getPairedDevice();
    if (deviceInfo != null) {
      final updated = deviceInfo.copyWith(firmwareVersion: version);
      await savePairedDevice(updated);
      print('DeviceManager: Updated firmware version to $version');
    }
  }
  
  /// Update battery level
  static Future<void> updateBatteryLevel(int level) async {
    final deviceInfo = await getPairedDevice();
    if (deviceInfo != null) {
      final updated = deviceInfo.copyWith(batteryLevel: level);
      await savePairedDevice(updated);
      print('DeviceManager: Updated battery level to $level%');
    }
  }
  
  /// Unpair device (remove all stored information)
  static Future<void> unpairDevice() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Remove new format
    await prefs.remove(_deviceInfoKey);
    
    // Remove legacy format
    await prefs.remove(_legacyPairedStatusKey);
    await prefs.remove(_legacyDeviceNameKey);
    
    // Remove legacy MAC file
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final File macFile = File('${appDocDir.path}/$_legacyMacFileName');
      if (await macFile.exists()) {
        await macFile.delete();
        print('DeviceManager: Deleted legacy MAC file');
      }
    } catch (e) {
      print('DeviceManager: Error deleting MAC file: $e');
    }
    
    print('DeviceManager: Device unpaired successfully');
    _applyProfile(null);
    _notifyPairingChanged();
  }
  
  /// Check if a device is currently paired
  static Future<bool> isDevicePaired() async {
    final deviceInfo = await getPairedDevice();
    return deviceInfo != null;
  }
  
  /// Get MAC address of paired device (convenience method)
  static Future<String?> getPairedDeviceMac() async {
    final deviceInfo = await getPairedDevice();
    return deviceInfo?.macAddress;
  }
  
  /// Get display name of paired device (convenience method)
  static Future<String?> getPairedDeviceDisplayName() async {
    final deviceInfo = await getPairedDevice();
    return deviceInfo?.displayName;
  }
  
  /// Clean up any inconsistent state
  static Future<void> cleanupInconsistentState() async {
    final deviceInfo = await getPairedDevice();
    
    if (deviceInfo == null) {
      // No device paired, make sure all legacy data is removed
      await unpairDevice();
    }
  }
}
