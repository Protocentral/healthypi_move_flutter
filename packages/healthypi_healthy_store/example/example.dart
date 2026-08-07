// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// A complete, **runnable** Healthy Store session — `dart run example/example.dart`.
///
/// No watch and no BLE stack required: [_FakeMoveTransport] below is an
/// in-memory HealthyPi Move that speaks the real wire format, so this file
/// exercises the same code path a real device does. Swap that one class for a
/// BLE/serial/TCP [SmpTransport] and the rest is unchanged — that seam is the
/// whole design.
///
/// It walks the four things every integration needs:
///
///  1. `HELLO`  — handshake and capability probe.
///  2. `TYPES`  — the self-describing metric registry. **Never hard-code it.**
///  3. `SYNC`   — the resumable, cursor-based sample stream.
///  4. `ACK`    — the retention hint, which is **destructive**.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

Future<void> main() async {
  final transport = _FakeMoveTransport();
  await transport.connect();
  final hs = HpiHs(SmpClient(transport));

  // 1. HELLO — the capability probe. A *successful* HELLO is what tells you the
  //    device speaks HPI_HS; never gate on a firmware version string.
  final hello = await hs.hello();
  print('device ${hello.storeKey}  schema=${hello.schema}  '
      'head=${hello.head}  oldest=${hello.oldest}');

  // 2. TYPES — resolve metric ids at runtime. Ids are assigned by firmware and
  //    differ across builds, so a hard-coded table silently mislabels data.
  final types = await hs.types();
  print('registry: ${types.length} metrics — '
      '${types.values.map((t) => t.key).join(", ")}');

  // 3. SYNC — page until `more` is false. `seq` is both the resume cursor and
  //    the dedup key, so this loop is safe to interrupt and re-run.
  var cursor = 0; // 0 = everything the device still retains
  var total = 0;
  while (true) {
    final page = await hs.sync(since: cursor, max: 64);
    for (final s in page.samples) {
      final t = types[s.type];
      if (t == null) continue; // unknown id from newer firmware — skip, never throw
      if (!s.isValid) continue; // honour the quality flags
      final value = s.value / (t.scale == 0 ? 1 : t.scale);
      print('  seq=${s.seq}  ${t.key} = $value ${t.unit}');
    }
    total += page.samples.length;

    // Persist BEFORE advancing the cursor: a crash here must re-deliver the
    // page, not skip it.
    cursor = page.next;
    if (!page.more) break;
  }
  print('synced $total sample(s), cursor now $cursor');

  // 4. ACK — **destructive**. The device may drop every sample at or below this
  //    seq. Only ever ack a cursor you have already committed to durable
  //    storage, and never `hello.head` (you have not read up to it).
  await hs.ackDurablyStored(cursor);
  print('acked through $cursor — the device may now reclaim that space');

  await transport.disconnect();
}

// ---------------------------------------------------------------------------
// A fake HealthyPi Move. Everything below stands in for hardware.
// ---------------------------------------------------------------------------

/// An in-memory device that answers HELLO / TYPES / SYNC / ACK on the real wire
/// format, so the example above is exercising genuine encode/decode rather than
/// a mock that agrees with itself.
///
/// A real transport does the same job over GATT: frame in via [write], frames
/// out on [notifications]. See `SmpBleTransport` in the HealthyPi Move app for a
/// production BLE implementation.
class _FakeMoveTransport implements SmpTransport {
  final _rx = StreamController<Uint8List>.broadcast();
  final _states = StreamController<SmpConnectionState>.broadcast();
  var _state = SmpConnectionState.disconnected;

  /// The registry this device reports. Deliberately served two-at-a-time to
  /// exercise the client's TYPES paging.
  static const _registry = [
    {'id': 1, 'key': 'hr', 'unit': 'bpm', 'scale': 1, 'class': 'D'},
    {'id': 2, 'key': 'spo2', 'unit': '%', 'scale': 1, 'class': 'D'},
    {'id': 3, 'key': 'temp', 'unit': 'degC', 'scale': 100, 'class': 'D'},
  ];

  /// Packed 18-byte sample records, oldest first.
  late final List<Uint8List> _samples = [
    _packSample(seq: 1, type: 1, value: 72),
    _packSample(seq: 2, type: 2, value: 98),
    _packSample(seq: 3, type: 3, value: 3665), // 36.65 °C at scale 100
    _packSample(seq: 4, type: 1, value: 75),
  ];

  @override
  String? get deviceLabel => 'Fake HealthyPi Move';

  @override
  SmpConnectionState get state => _state;

  @override
  Stream<SmpConnectionState> get stateChanges => _states.stream;

  @override
  Stream<Uint8List> get notifications => _rx.stream;

  @override
  int? get maxWriteLength => 244; // what a real Move settles on after connect

  @override
  Future<void> connect() async {
    _state = SmpConnectionState.connected;
    _states.add(_state);
  }

  @override
  Future<void> disconnect() async {
    _state = SmpConnectionState.disconnected;
    _states.add(_state);
    await _rx.close();
    await _states.close();
  }

  @override
  Future<void> write(Uint8List frame) async {
    final req = SmpMessage.fromBytes(frame);
    final payload = _handle(req);
    // Answer asynchronously, like a real notification would arrive.
    scheduleMicrotask(() {
      if (_rx.isClosed) return;
      _rx.add(SmpMessage(
        op: req.op == SmpOp.readReq ? SmpOp.readRsp : SmpOp.writeRsp,
        group: req.group,
        id: req.id,
        seq: req.seq,
        payload: payload,
      ).toBytes());
    });
  }

  Map<String, Object?> _handle(SmpMessage req) {
    switch (req.id) {
      case HpiHs.cmdHello:
        return {
          'schema': 1,
          'group': HpiHs.group,
          'dev': 'move-fake',
          'uid': 'a1b2c3d4e5f60789',
          'head': _samples.length,
          'oldest': 1,
          'types': _registry.length,
        };

      case HpiHs.cmdTypes:
        // Paged two at a time, as the firmware does.
        final from = (req.payload['from'] as num?)?.toInt() ?? 0;
        final page = _registry.skip(from).take(2).toList();
        return {
          'types': page,
          'next': from + page.length,
          'total': _registry.length,
        };

      case HpiHs.cmdSync:
        final since = (req.payload['since'] as num?)?.toInt() ?? 0;
        final max = (req.payload['max'] as num?)?.toInt() ?? 256;
        // `since` is exclusive: samples are keyed by seq starting at 1.
        final page = _samples.skip(since).take(max).toList();
        final next = since + page.length;
        return {
          'recs': CborBytes(page.expand((s) => s).toList()),
          'n': page.length,
          'next': next,
          'more': next < _samples.length,
        };

      case HpiHs.cmdAck:
        return {'rc': 0};

      default:
        // Unknown command: answer like firmware would rather than hanging.
        return {'rc': 8}; // MGMT_ERR_ENOTSUP
    }
  }

  /// seq u32 @0 · ts_utc i64 @4 · type u8 @12 · quality u8 @13 · value i32 @14
  static Uint8List _packSample({
    required int seq,
    required int type,
    required int value,
  }) {
    final b = ByteData(HsSample.wireSize);
    b.setUint32(0, seq, Endian.little);
    b.setInt64(4, 1751932800 + seq * 60, Endian.little);
    b.setUint8(12, type);
    b.setUint8(13, HsQuality.valid | HsQuality.onSkin);
    b.setInt32(14, value, Endian.little);
    return b.buffer.asUint8List();
  }
}
