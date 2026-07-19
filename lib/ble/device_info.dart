// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// The transport a [DeviceInfoReader] needs: read one GATT characteristic by
/// (service, characteristic) short-UUID. Deliberately narrow and plugin-
/// agnostic — an adapter binds it to the device's live connection; the reader
/// below never sees `universal_ble`, so it stays pure Dart and unit-tests
/// without a radio.
///
/// A read that can't happen (link down, characteristic absent, GATT error)
/// returns `null` rather than throwing — DIS is best-effort metadata, never a
/// hard dependency.
abstract class DisTransport {
  /// Raw bytes of [characteristic] under [service], or `null` if unreadable.
  Future<List<int>?> readCharacteristic(String service, String characteristic);
}

/// A snapshot of the standard Bluetooth Device Information Service (`0x180A`).
/// Every field is nullable: the firmware need not expose all of them, and any
/// single read can flake. `null` means "not reported", never a placeholder.
class DeviceInfo {
  const DeviceInfo({
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.hardwareRevision,
    this.firmwareRevision,
    this.softwareRevision,
  });

  final String? manufacturer; // 0x2A29
  final String? model; // 0x2A24
  final String? serialNumber; // 0x2A25
  final String? hardwareRevision; // 0x2A27
  final String? firmwareRevision; // 0x2A26
  final String? softwareRevision; // 0x2A28

  /// True when the device reported nothing at all (every field null).
  bool get isEmpty =>
      manufacturer == null &&
      model == null &&
      serialNumber == null &&
      hardwareRevision == null &&
      firmwareRevision == null &&
      softwareRevision == null;

  @override
  String toString() => 'DeviceInfo(manufacturer: $manufacturer, model: $model, '
      'serial: $serialNumber, hw: $hardwareRevision, fw: $firmwareRevision, '
      'sw: $softwareRevision)';
}

/// Reads the standard Device Information Service (`0x180A`).
///
/// Reconstitutes the DIS read that `lib/utils/device_info_service.dart` used to
/// own (deleted with the legacy screens) and widens it from firmware-revision-
/// only to the full standard set, behind a [DisTransport] seam so it's pure
/// Dart and testable. The firmware-revision read used to be reimplemented in
/// sync, update-check, and DFU, each with its own error handling — centralised
/// here so "unknown" means one thing everywhere.
///
/// Pure Dart (no Flutter), so it moves into the `healthypi_move` SDK package
/// unchanged when that lands (Phase 8).
class DeviceInfoReader {
  DeviceInfoReader(
    this._transport, {
    void Function(String message)? log,
  }) : _log = log;

  final DisTransport _transport;
  final void Function(String message)? _log;

  /// Device Information Service.
  static const String disService = '180a';

  // Standard DIS characteristic short-UUIDs.
  static const String manufacturerChar = '2a29';
  static const String modelChar = '2a24';
  static const String serialNumberChar = '2a25';
  static const String hardwareRevisionChar = '2a27';
  static const String firmwareRevisionChar = '2a26';
  static const String softwareRevisionChar = '2a28';

  /// Read the firmware revision string (`0x2A26`), or `null` if unreadable.
  ///
  /// `null` means "we don't know" — not "old". Callers must not treat an
  /// unreadable version as a failed version check; see [isAtLeast].
  Future<String?> readFirmwareVersion() => _readString(firmwareRevisionChar);

  /// Read the whole DIS in one pass. Each characteristic is read independently
  /// and tolerated on failure, so one absent field never sinks the rest.
  Future<DeviceInfo> readAll() async {
    return DeviceInfo(
      manufacturer: await _readString(manufacturerChar),
      model: await _readString(modelChar),
      serialNumber: await _readString(serialNumberChar),
      hardwareRevision: await _readString(hardwareRevisionChar),
      firmwareRevision: await _readString(firmwareRevisionChar),
      softwareRevision: await _readString(softwareRevisionChar),
    );
  }

  /// Read a UTF-8/ASCII string characteristic, trimmed; `null` if unreadable or
  /// empty. DIS strings are plain text, so `String.fromCharCodes` is enough.
  Future<String?> _readString(String characteristic) async {
    try {
      final bytes = await _transport.readCharacteristic(disService, characteristic);
      if (bytes == null) return null;
      final value = String.fromCharCodes(bytes).trim();
      return value.isEmpty ? null : value;
    } catch (e) {
      _log?.call('DeviceInfo: read $characteristic failed: $e');
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
    void Function(String message)? log,
  }) {
    if (version == null || version.isEmpty || version == 'unknown') {
      log?.call('DeviceInfo: version unknown — assuming supported');
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
      log?.call('DeviceInfo: could not parse version "$version": $e');
      return onUnknown;
    }
  }
}
