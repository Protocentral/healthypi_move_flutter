import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_manager.dart';

enum LinkState { disconnected, connecting, connected, disconnecting, error }

/// Thrown by [ConnectionManager.acquireSmp] when another flow already holds the
/// SMP characteristic. Health-store sync, records and DFU all speak SMP over the
/// same characteristic and must never interleave on the wire — a background sync
/// firing mid-DFU would corrupt the image upload.
class SmpBusyException implements Exception {
  SmpBusyException(this.currentOwner, this.requestedBy);

  /// The flow currently holding the SMP wire (e.g. `dfu`).
  final String currentOwner;

  /// The flow that tried to start (e.g. `background-sync`).
  final String requestedBy;

  @override
  String toString() =>
      'SMP busy: "$currentOwner" holds the SMP characteristic; '
      '"$requestedBy" cannot start.';
}

/// Owns **the** BLE connection to the paired HealthyPi Move — the one place that
/// connects/holds the device, so screens no longer each call `connect()` /
/// `disconnect()` independently (which caused the old connect/disconnect races).
/// Mirrors OpenView 3's `ConnectionController`.
///
/// The single physical link carries two logical modes that must not overlap:
///
/// - **Streaming** — live ECG/PPG/HR/SpO₂/temp over the custom GATT
///   characteristics, via [subscribe] / [write] here.
/// - **SMP** — healthy-store sync, records and firmware DFU over the SMP
///   characteristic, via `SmpBleTransport(id, manageConnection: false)` riding
///   this link.
///
/// Every SMP flow must bracket its session with [acquireSmp] / [releaseSmp] (or
/// [runSmp]); the lock is what keeps sync, records and DFU off each other's
/// wire. Nothing else should call `BleManager.connect` directly.
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

  /// Non-null while some flow holds the SMP wire. See [acquireSmp].
  String? _smpOwner;
  Object? _smpToken;

  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  LinkState get state => _state;
  String? get error => _error;
  bool get isConnected => _state == LinkState.connected;

  // --- SMP arbitration ------------------------------------------------------

  /// True while an SMP session (sync / records / DFU) holds the wire.
  bool get isSmpBusy => _smpOwner != null;

  /// Name of the flow currently holding the SMP wire, or null.
  String? get smpOwner => _smpOwner;

  /// Claim exclusive use of the SMP characteristic for [owner].
  ///
  /// Throws [SmpBusyException] if another flow already holds it. Returns an
  /// opaque token that must be handed back to [releaseSmp]; a token from a
  /// superseded session is ignored, so a late teardown can't free somebody
  /// else's lock.
  Object acquireSmp(String owner) {
    final current = _smpOwner;
    if (current != null) throw SmpBusyException(current, owner);
    final token = Object();
    _smpOwner = owner;
    _smpToken = token;
    notifyListeners();
    return token;
  }

  /// Release the SMP wire. Safe to call with a stale token (no-op) or twice.
  void releaseSmp(Object? token) {
    if (token == null || !identical(_smpToken, token)) return;
    _smpOwner = null;
    _smpToken = null;
    notifyListeners();
  }

  /// Run [body] holding the SMP wire, releasing it even if [body] throws.
  /// Use this when the whole session fits in one call; otherwise pair
  /// [acquireSmp] / [releaseSmp] around the session's lifetime.
  Future<T> runSmp<T>(String owner, Future<T> Function() body) async {
    final token = acquireSmp(owner);
    try {
      return await body();
    } finally {
      releaseSmp(token);
    }
  }

  /// Drop the lock regardless of holder — the link is gone, so whoever held it
  /// is dead. Called on disconnect and on an unexpected drop.
  void _forceReleaseSmp() {
    if (_smpOwner == null) return;
    debugPrint('[ConnectionManager] link lost; force-releasing SMP lock held '
        'by "$_smpOwner"');
    _smpOwner = null;
    _smpToken = null;
  }

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
      // Scan-assisted connect: on iOS a stored deviceId must be (re)discovered
      // before connect resolves it.
      await _ble.connectResolved(deviceId);
      // REQUIRED before any subscribe/write: CoreBluetooth (and Android GATT)
      // only expose characteristics after service discovery. Without this,
      // connect succeeds but notify/write silently fail.
      await _ble.discoverServices(deviceId);
      await _connSub?.cancel();
      _connSub = _ble.connectionStream(deviceId).listen((connected) {
        if (!connected && !_intentional && _state == LinkState.connected) {
          // The link dropped under whoever held the SMP wire; free it so the
          // next sync/DFU isn't locked out by a dead session.
          _forceReleaseSmp();
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
    _forceReleaseSmp();
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
