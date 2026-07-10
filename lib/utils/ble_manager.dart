import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// A device discovered by [BleManager.scanResults]. A plain DTO so the rest of
/// the app never touches `universal_ble` types.
class BleScanResult {
  const BleScanResult({
    required this.deviceId,
    required this.name,
    required this.rssi,
    this.services = const [],
    this.isSystemDevice = false,
  });

  final String deviceId;
  final String? name;
  final int? rssi;
  final List<String> services;
  final bool isSystemDevice;

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : deviceId;
}

/// **The single point of contact with the BLE stack** for the whole app.
///
/// This is the *only* app file that imports `universal_ble` (the SMP subsystem's
/// `smp_ble_transport.dart` is the other, self-contained one). Everything —
/// scan/pair, live streaming, legacy commands — goes through here, so the plugin
/// stays swappable and connection/subscription lifecycle lives in one place.
/// Mirrors OpenView 3's `lib/transport/ble_service.dart`.
///
/// `universal_ble` is a static/singleton API keyed by **deviceId** (the same
/// platform identifier FBP exposed as `remoteId.str`: a CoreBluetooth UUID on
/// Apple, a MAC on Android). This facade keeps that model and exposes a
/// stream-per-characteristic view that fits the Move's several streaming
/// characteristics (ECG/PPG/GSR/HR/SpO₂/temp) plus command writes.
class BleManager {
  BleManager._();
  static final BleManager instance = BleManager._();

  bool _logQuiet = true;

  /// Call once at startup. Silences verbose native logging.
  Future<void> init() async {
    await UniversalBle.setLogLevel(
        _logQuiet ? BleLogLevel.none : BleLogLevel.verbose);
  }

  set verbose(bool v) {
    _logQuiet = !v;
    UniversalBle.setLogLevel(v ? BleLogLevel.verbose : BleLogLevel.none);
  }

  // --- Adapter -------------------------------------------------------------

  Future<bool> isBluetoothOn() async =>
      (await UniversalBle.getBluetoothAvailabilityState()) ==
      AvailabilityState.poweredOn;

  /// `true`/`false` as the adapter powers on/off.
  Stream<bool> get bluetoothOnStream => UniversalBle.availabilityStream
      .map((s) => s == AvailabilityState.poweredOn);

  Stream<AvailabilityState> get availabilityStream =>
      UniversalBle.availabilityStream;

  // --- Scan ----------------------------------------------------------------

  /// Broadcast of discovered peripherals (unfiltered — filter by name at the
  /// call site). Start/stop with [startScan]/[stopScan].
  Stream<BleScanResult> get scanResults => UniversalBle.scanStream.map(
        (d) => BleScanResult(
          deviceId: d.deviceId,
          name: d.name,
          rssi: d.rssi,
          services: d.services,
        ),
      );

  Future<void> startScan() => UniversalBle.startScan();
  Future<void> stopScan() => UniversalBle.stopScan();

  /// Already-connected/bonded system devices (won't appear in a scan on macOS/iOS).
  Future<List<BleScanResult>> systemDevices({List<String>? withServices}) async {
    final list = await UniversalBle.getSystemDevices(withServices: withServices);
    return [
      for (final d in list)
        BleScanResult(
          deviceId: d.deviceId,
          name: d.name,
          rssi: d.rssi,
          services: d.services,
          isSystemDevice: true,
        ),
    ];
  }

  // --- Connection ----------------------------------------------------------

  Future<void> connect(String deviceId,
          {Duration timeout = const Duration(seconds: 15)}) =>
      UniversalBle.connect(deviceId, timeout: timeout);

  /// Connect to a device by id, **scanning to (re)discover it first**.
  ///
  /// On iOS, `UniversalBle.connect(id)` fails with `deviceNotFound` for a stored
  /// id the plugin hasn't seen this session (its `retrievePeripherals` fallback
  /// is unreliable). A brief scan puts the peripheral in the plugin's cache so
  /// the connect resolves — this is how the app reconnects to a *paired* device
  /// (Live View, sync, DFU, records) without the user re-scanning. If the scan
  /// doesn't surface it (device off/not advertising) we still attempt a direct
  /// connect as a last resort.
  Future<void> connectResolved(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
    Duration scanTimeout = const Duration(seconds: 8),
  }) async {
    if (await isConnected(deviceId)) return;
    await _discoverById(deviceId, scanTimeout);
    await UniversalBle.connect(deviceId, timeout: timeout);
  }

  /// Scan until [deviceId] appears (so universal_ble caches the peripheral),
  /// then stop. Returns true if seen within [timeout].
  Future<bool> _discoverById(String deviceId, Duration timeout) async {
    final completer = Completer<bool>();
    StreamSubscription<BleDevice>? sub;
    sub = UniversalBle.scanStream.listen((d) {
      if (d.deviceId == deviceId && !completer.isCompleted) {
        completer.complete(true);
      }
    });
    try {
      await UniversalBle.startScan();
      return await completer.future
          .timeout(timeout, onTimeout: () => false);
    } catch (e) {
      debugPrint('[BleManager] _discoverById scan error: $e');
      return false;
    } finally {
      await sub.cancel();
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
  }

  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  /// Connection-state changes for a device (`true` = connected). Subscribe only
  /// after a successful connect to avoid a replayed `disconnected` (macOS gotcha).
  Stream<bool> connectionStream(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  Future<bool> isConnected(String deviceId) async =>
      (await UniversalBle.getConnectionState(deviceId)) ==
      BleConnectionState.connected;

  /// Discover services (returns raw UUID strings; the plugin's service objects
  /// are not leaked). Call after connect; universal_ble caches them internally.
  Future<List<String>> discoverServiceUuids(String deviceId) async {
    final services = await UniversalBle.discoverServices(deviceId);
    return [for (final s in services) s.uuid];
  }

  Future<void> discoverServices(String deviceId) =>
      UniversalBle.discoverServices(deviceId);

  /// Request a larger MTU (best-effort; OS-managed on Apple). Returns the
  /// negotiated value or null. MTU settles just after connect on Apple, so
  /// call again shortly after connecting if you need the real value.
  Future<int?> requestMtu(String deviceId, [int mtu = 512]) async {
    try {
      return await UniversalBle.requestMtu(deviceId, mtu);
    } catch (_) {
      return null;
    }
  }

  // --- Characteristics -----------------------------------------------------

  /// Enable notifications on a characteristic. Its values arrive on
  /// [notifications].
  Future<void> subscribe(String deviceId, String service, String characteristic) =>
      UniversalBle.subscribeNotifications(deviceId, service, characteristic);

  Future<void> unsubscribe(
          String deviceId, String service, String characteristic) =>
      UniversalBle.unsubscribe(deviceId, service, characteristic);

  /// Raw notification values for a characteristic (call [subscribe] first).
  Stream<Uint8List> notifications(String deviceId, String characteristic) =>
      UniversalBle.characteristicValueStream(deviceId, characteristic);

  /// Convenience: subscribe + return the value stream in one call.
  Stream<Uint8List> subscribeStream(
      String deviceId, String service, String characteristic) {
    // Fire-and-forget the subscribe; the stream is broadcast so values flow once
    // notifications are enabled.
    unawaited(subscribe(deviceId, service, characteristic)
        .catchError((Object e) => debugPrint('[BleManager] subscribe failed: $e')));
    return notifications(deviceId, characteristic);
  }

  /// Write to a characteristic. Defaults to write-without-response (the Move's
  /// command characteristic uses it).
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value, {
    bool withoutResponse = true,
  }) =>
      UniversalBle.write(deviceId, service, characteristic, value,
          withoutResponse: withoutResponse);

  Future<Uint8List> read(
          String deviceId, String service, String characteristic) =>
      UniversalBle.read(deviceId, service, characteristic);

  // --- Pairing -------------------------------------------------------------

  Future<void> pair(String deviceId) => UniversalBle.pair(deviceId);
  Future<bool?> isPaired(String deviceId) => UniversalBle.isPaired(deviceId);
}
