/// Device information model for paired HealthyPi Move devices
/// Provides structured storage for device metadata, connection history,
/// and hardware information.
class DeviceInfo {
  final String macAddress;
  final String deviceName;        // e.g., "healthypi move"
  final String nickname;          // User-assigned name
  final DateTime firstPaired;
  final DateTime? lastConnected;
  final String? firmwareVersion;  // Optional, fetched on connection
  final int? batteryLevel;        // Optional, fetched on connection
  
  DeviceInfo({
    required this.macAddress,
    required this.deviceName,
    this.nickname = '',
    required this.firstPaired,
    this.lastConnected,
    this.firmwareVersion,
    this.batteryLevel,
  });
  
  /// Convert DeviceInfo to JSON for storage
  Map<String, dynamic> toJson() => {
    'macAddress': macAddress,
    'deviceName': deviceName,
    'nickname': nickname,
    'firstPaired': firstPaired.toIso8601String(),
    'lastConnected': lastConnected?.toIso8601String(),
    'firmwareVersion': firmwareVersion,
    'batteryLevel': batteryLevel,
  };
  
  /// Create DeviceInfo from JSON
  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    macAddress: json['macAddress'] as String,
    deviceName: json['deviceName'] as String,
    nickname: (json['nickname'] as String?) ?? '',
    firstPaired: DateTime.parse(json['firstPaired'] as String),
    lastConnected: json['lastConnected'] != null 
        ? DateTime.parse(json['lastConnected'] as String)
        : null,
    firmwareVersion: json['firmwareVersion'] as String?,
    batteryLevel: json['batteryLevel'] as int?,
  );
  
  /// Create a copy with updated fields
  DeviceInfo copyWith({
    String? macAddress,
    String? deviceName,
    String? nickname,
    DateTime? firstPaired,
    DateTime? lastConnected,
    String? firmwareVersion,
    int? batteryLevel,
  }) {
    return DeviceInfo(
      macAddress: macAddress ?? this.macAddress,
      deviceName: deviceName ?? this.deviceName,
      nickname: nickname ?? this.nickname,
      firstPaired: firstPaired ?? this.firstPaired,
      lastConnected: lastConnected ?? this.lastConnected,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }
  
  /// Get display name (nickname if set, otherwise device name)
  String get displayName => nickname.isEmpty ? deviceName : nickname;
  
  @override
  String toString() => 'DeviceInfo(mac: $macAddress, name: $displayName)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          macAddress == other.macAddress;
  
  @override
  int get hashCode => macAddress.hashCode;
}
