import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mcumgr/fs_mgmt.dart';
import '../mcumgr/hpi_hs.dart';
import '../mcumgr/img_mgmt.dart';
import '../mcumgr/os_mgmt.dart';
import '../smp/smp_ble_transport.dart';
import '../smp/smp_client.dart';
import '../smp/smp_transport.dart';

/// A single SMP session to a HealthyPi Move over the SMP GATT service, on
/// `universal_ble`. This is the app-to-device backbone for the redesigned
/// architecture: **one** BLE plugin and **one** SMP client for health-store sync
/// (HPI_HS group `0x1000`) *and* firmware DFU (image group), replacing the old
/// dual-channel (custom cmd/data service + MCUmgr-FS) path.
///
/// See `docs/HEALTH_STORE_SYNC_DESIGN.md`. The SMP core (`lib/smp`, `lib/mcumgr`,
/// `lib/models/hs_*`) is ported verbatim from the hardware-verified OpenView 3
/// client and is transport-agnostic; only [SmpBleTransport] is BLE-specific.
class HealthStoreClient {
  HealthStoreClient(this.deviceId, {this.name});

  /// BLE device id (universal_ble deviceId — the platform address/UUID).
  final String deviceId;
  final String? name;

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
  Future<void> connect({Duration? mtuSettle}) async {
    final transport = SmpBleTransport(deviceId, name: name);
    _transport = transport;
    _stateSub = transport.stateChanges.listen((s) => _state = s);

    await transport.connect(); // throws SmpTransportException if no SMP service
    final client = SmpClient(transport);
    _client = client;
    os = OsMgmt(client);
    img = ImgMgmt(client, maxWriteLength: () => _transport?.maxWriteLength);
    fs = FsMgmt(client, maxWriteLength: () => _transport?.maxWriteLength);
    hs = HpiHs(client);

    await _settleMtu(mtuSettle ?? const Duration(seconds: 3));
    await _probeHello();
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
        await t.disconnect();
      } catch (_) {}
      await t.dispose();
    }
    _state = SmpConnectionState.disconnected;
  }
}
