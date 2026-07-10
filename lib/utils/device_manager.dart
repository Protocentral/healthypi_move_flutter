import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_info.dart';

/// Unified device management utility for HealthyPi Move pairing
/// Handles device storage, retrieval, and migration from legacy format
class DeviceManager {
  static const String _deviceInfoKey = 'paired_device_info';
  static const String _legacyPairedStatusKey = 'pairedStatus';
  static const String _legacyDeviceNameKey = 'paired_device_name';
  static const String _legacyMacFileName = 'paired_device_mac.txt';
  
  /// Save paired device information
  static Future<void> savePairedDevice(DeviceInfo deviceInfo) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(deviceInfo.toJson());
    await prefs.setString(_deviceInfoKey, jsonString);
    
    // Also maintain legacy format for backward compatibility during transition
    await prefs.setString(_legacyPairedStatusKey, 'paired');
    await prefs.setString(_legacyDeviceNameKey, deviceInfo.deviceName);
    
    print('DeviceManager: Saved device info for ${deviceInfo.displayName}');
  }
  
  /// Get paired device information
  static Future<DeviceInfo?> getPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Try new format first
    final jsonString = prefs.getString(_deviceInfoKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return DeviceInfo.fromJson(json);
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
