import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:hpi_health_store/hpi_health_store.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';
import '../smp/smp_ble_transport.dart';
import 'connection_manager.dart';

/// A single SMP session to a HealthyPi Move over the SMP GATT service, on
/// `universal_ble`. This is the app-to-device backbone for the redesigned
/// architecture: **one** BLE plugin and **one** SMP client for health-store sync
/// (HPI_HS group `0x1000`) *and* firmware DFU (image group), replacing the old
/// dual-channel (custom cmd/data service + MCUmgr-FS) path.
///
/// **Connection ownership.** By default this session *rides* the link owned by
/// [ConnectionManager] (`manageConnection: false`), which is how every other SMP
/// flow in the app works (background sync, records, DFU). Connect the
/// `ConnectionManager` first, then construct this. Pass `manageConnection: true`
/// only for a standalone session that owns its own BLE link — and only when the
/// `ConnectionManager` is *not* already connected to the same device, or the two
/// would open two OS-level connections to one peripheral.
///
/// [connect] claims the SMP wire via [ConnectionManager.acquireSmp] and throws
/// [SmpBusyException] if sync/records/DFU is already running; [disconnect]
/// releases it.
///
/// See `docs/HEALTH_STORE_SYNC_DESIGN.md`. The SMP core (`lib/smp`, `lib/mcumgr`,
/// `lib/models/hs_*`) is ported verbatim from the hardware-verified OpenView 3
/// client and is transport-agnostic; only [SmpBleTransport] is BLE-specific.
class HealthStoreClient {
  HealthStoreClient(
    this.deviceId, {
    this.name,
    this.manageConnection = false,
    this.requestTimeout,
  });

  /// BLE device id (universal_ble deviceId — the platform address/UUID).
  final String deviceId;
  final String? name;

  /// Per-request SMP timeout. The default (10 s) is fine for HELLO/TYPES, but a
  /// catch-up SYNC page makes the device scan its flash segments, which can take
  /// far longer than that on a device with a long backlog.
  final Duration? requestTimeout;

  /// When false (default) this session rides the [ConnectionManager] link and
  /// [disconnect] leaves that link up. When true it owns its own BLE link.
  final bool manageConnection;

  final ConnectionManager _conn = ConnectionManager.instance;

  /// Token for the SMP lock held between [connect] and [disconnect].
  Object? _smpToken;

  /// Label used for the SMP lock and its error messages.
  static const String smpOwnerLabel = 'health-store';

  SmpBleTransport? _transport;
  SmpClient? _client;
  StreamSubscription<SmpConnectionState>? _stateSub;

  /// MCUmgr group facades — non-null only while connected.
  OsMgmt? os;
  ImgMgmt? img;
  FsMgmt? fs;

  /// ProtoCentral Health Store (group 0x1000) — present once [hello] succeeds.
  HpiHs? hs;
  HsHello? hello;

  SmpConnectionState _state = SmpConnectionState.disconnected;
  SmpConnectionState get state => _state;
  bool get isConnected => _state == SmpConnectionState.connected;

  /// True once a HELLO handshake succeeds (i.e. the device implements HPI_HS).
  bool get hasHealthStore => hs != null && hello != null;

  int? get maxWriteLength => _transport?.maxWriteLength;

  /// Connect, bring up the SMP client + group facades, settle the MTU, and probe
  /// HELLO. Throws if the device is not SMP-enabled or the link fails.
  ///
  /// Throws [SmpBusyException] if another SMP flow (sync / records / DFU) holds
  /// the wire, and [StateError] if the requested connection ownership conflicts
  /// with the [ConnectionManager]'s current link (see [manageConnection]).
  Future<void> connect({Duration? mtuSettle}) async {
    _assertOwnershipIsCoherent();

    // Claim the SMP wire before touching it. Released in [disconnect].
    final token = _conn.acquireSmp(smpOwnerLabel);
    _smpToken = token;

    try {
      final transport = SmpBleTransport(deviceId,
          name: name, manageConnection: manageConnection);
      _transport = transport;
      _stateSub = transport.stateChanges.listen((s) => _state = s);

      await transport.connect(); // throws SmpTransportException if no SMP service
      final client = SmpClient(transport);
      if (requestTimeout != null) client.timeout = requestTimeout!;
      _client = client;
      os = OsMgmt(client);
      img = ImgMgmt(client, maxWriteLength: () => _transport?.maxWriteLength);
      fs = FsMgmt(client, maxWriteLength: () => _transport?.maxWriteLength);
      // The package is pure Dart; route its diagnostics into Flutter's logger.
      hs = HpiHs(client, log: (m) => debugPrint(m));

      await _settleMtu(mtuSettle ?? const Duration(seconds: 3));
      await _probeHello();
    } catch (_) {
      // Never strand the lock on a failed bring-up.
      await disconnect();
      rethrow;
    }
  }

  /// Guard the two ways connection ownership can go wrong. Riding a link that
  /// isn't there yields a transport that silently can't write; owning a second
  /// link to a device the ConnectionManager already holds opens two OS-level
  /// connections to one peripheral.
  void _assertOwnershipIsCoherent() {
    final connHoldsThisDevice = _conn.isConnected && _conn.deviceId == deviceId;
    if (manageConnection) {
      if (connHoldsThisDevice) {
        throw StateError(
            'HealthStoreClient(manageConnection: true) would open a second BLE '
            'connection to $deviceId, which ConnectionManager already holds. '
            'Use manageConnection: false to ride the existing link.');
      }
    } else if (!connHoldsThisDevice) {
      throw StateError(
          'HealthStoreClient(manageConnection: false) rides the '
          'ConnectionManager link, but it is not connected to $deviceId '
          '(current: ${_conn.deviceId ?? 'none'}). Call '
          'ConnectionManager.instance.connect(deviceId) first, or pass '
          'manageConnection: true to own the link.');
    }
  }

  /// The MTU is negotiated just after connect on iOS/macOS, so poll it briefly
  /// so DFU/record chunking uses the real value (see OpenView gotcha §5.5).
  Future<void> _settleMtu(Duration budget) async {
    final deadline = budget.inMilliseconds ~/ 400;
    for (var i = 0; i < deadline; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final t = _transport;
      if (t == null) return;
      await t.refreshMtu();
      if ((t.maxWriteLength ?? 0) > 20) return;
    }
  }

  /// HELLO handshake; sets [hello]/[hasHealthStore] on success, else leaves the
  /// Health Store unavailable (device firmware predates HPI_HS).
  Future<void> _probeHello() async {
    try {
      hello = await hs!.hello();
    } catch (e) {
      debugPrint('[HealthStore] HELLO failed (no HPI_HS group?): $e');
      hs = null;
      hello = null;
    }
  }

  /// Re-query the negotiated MTU (call before a large DFU / record transfer).
  Future<void> refreshMtu() async => _transport?.refreshMtu();

  /// Tear the SMP session down and release the SMP wire. When
  /// [manageConnection] is false the underlying BLE link is left up for
  /// whoever owns it. Idempotent.
  Future<void> disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _client?.dispose();
    _client = null;
    os = null;
    img = null;
    fs = null;
    hs = null;
    hello = null;
    final t = _transport;
    _transport = null;
    if (t != null) {
      try {
        // manageConnection:false → unsubscribes only, keeps the shared link.
        await t.disconnect();
      } catch (_) {}
      await t.dispose();
    }
    _state = SmpConnectionState.disconnected;
    _conn.releaseSmp(_smpToken);
    _smpToken = null;
  }
}
