import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_manager.dart';

enum LinkState { disconnected, connecting, connected, disconnecting, error }

/// Owns the **live streaming** connection to the paired HealthyPi Move — the one
/// place that connects/holds the device for live-view screens, so screens no
/// longer each call `connect()`/`disconnect()` independently (which caused the
/// old connect/disconnect races). Mirrors OpenView 3's `ConnectionController`.
///
/// **Health-store sync + firmware DFU use a separate `HealthStoreClient`** (its
/// own SMP connection), matching OpenView's decoupled-SMP model — the streaming
/// and SMP flows are distinct user actions and are not run concurrently. Route
/// all live-streaming BLE through this; route sync/DFU through `HealthStoreClient`.
class ConnectionManager extends ChangeNotifier {
  ConnectionManager._();
  static final ConnectionManager instance = ConnectionManager._();

  final BleManager _ble = BleManager.instance;

  String? _deviceId;
  String? _deviceName;
  LinkState _state = LinkState.disconnected;
  String? _error;
  bool _intentional = false;
  StreamSubscription<bool>? _connSub;

  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  LinkState get state => _state;
  String? get error => _error;
  bool get isConnected => _state == LinkState.connected;

  /// Connect the streaming link to [deviceId] (the paired MAC / platform id).
  /// Idempotent when already connected to the same device.
  Future<void> connect(String deviceId, {String? name}) async {
    if (_state == LinkState.connected && _deviceId == deviceId) return;
    _deviceId = deviceId;
    _deviceName = name;
    _error = null;
    _intentional = false;
    _setState(LinkState.connecting);
    try {
      await _ble.connect(deviceId);
      // REQUIRED before any subscribe/write: CoreBluetooth (and Android GATT)
      // only expose characteristics after service discovery. Without this,
      // connect succeeds but notify/write silently fail.
      await _ble.discoverServices(deviceId);
      await _connSub?.cancel();
      _connSub = _ble.connectionStream(deviceId).listen((connected) {
        if (!connected && !_intentional && _state == LinkState.connected) {
          _setState(LinkState.disconnected);
        }
      });
      _setState(LinkState.connected);
    } catch (e) {
      _error = e.toString();
      _setState(LinkState.error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _intentional = true;
    _setState(LinkState.disconnecting);
    await _connSub?.cancel();
    _connSub = null;
    final id = _deviceId;
    if (id != null) {
      try {
        await _ble.disconnect(id);
      } catch (_) {}
    }
    _setState(LinkState.disconnected);
  }

  /// Request a larger MTU on the current link (best-effort).
  Future<int?> requestMtu([int mtu = 512]) async {
    final id = _deviceId;
    return id == null ? null : _ble.requestMtu(id, mtu);
  }

  // --- Streaming helpers (delegate to BleManager with the owned deviceId) ---

  /// Subscribe to a characteristic on the current link and get its value stream.
  Stream<Uint8List> subscribe(String service, String characteristic) {
    final id = _deviceId;
    if (id == null) {
      throw StateError('ConnectionManager: not connected');
    }
    return _ble.subscribeStream(id, service, characteristic);
  }

  Future<void> unsubscribe(String service, String characteristic) async {
    final id = _deviceId;
    if (id != null) await _ble.unsubscribe(id, service, characteristic);
  }

  /// Write a command/payload to a characteristic on the current link.
  Future<void> write(String service, String characteristic, Uint8List value,
      {bool withoutResponse = true}) async {
    final id = _deviceId;
    if (id == null) throw StateError('ConnectionManager: not connected');
    await _ble.write(id, service, characteristic, value,
        withoutResponse: withoutResponse);
  }

  Future<Uint8List> read(String service, String characteristic) {
    final id = _deviceId;
    if (id == null) throw StateError('ConnectionManager: not connected');
    return _ble.read(id, service, characteristic);
  }

  void _setState(LinkState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
