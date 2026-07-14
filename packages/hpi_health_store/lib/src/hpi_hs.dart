import 'dart:typed_data';

import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'crc32.dart';
import 'models/hs_record.dart';
import 'models/hs_sample.dart';
import 'models/hs_summary.dart';
import 'models/hs_type.dart';

/// Sink for diagnostics. Pure Dart by design — pass `print`, a `Logger`, or
/// Flutter's `debugPrint` from the calling app.
typedef HpiHsLog = void Function(String message);

/// Result of a `HELLO` handshake.
class HsHello {
  const HsHello({
    required this.schema,
    required this.group,
    required this.dev,
    required this.uid,
    required this.head,
    required this.oldest,
    required this.types,
  });

  final int schema; // HPI_HS_SCHEMA_VERSION
  final int group; // HPI_HS_GROUP_VERSION

  /// Model string — always `"healthypi-move"`. **Not** unique per unit, so it
  /// must not key a local store (two watches on one phone would collide on
  /// seq). Kept for display and diagnostics.
  final String dev;

  /// Per-unit device id. This is the stable key for a local sample store.
  /// Empty on firmware that predates the field.
  final String uid;

  final int head; // newest seq available

  /// Oldest seq still retrievable. Samples below this have aged out of the
  /// device's retention window and are **gone** — a cursor below `oldest - 1`
  /// must jump forward rather than loop asking for data that no longer exists.
  /// 0 on firmware that predates the field (permissive: nothing aged out).
  final int oldest;

  final int types; // number of registry entries

  /// Key to store samples under: the per-unit [uid] when the firmware provides
  /// one, else the model string (single-device installs only).
  String get storeKey => uid.isNotEmpty ? uid : dev;

  /// `oldest > head` means the store holds nothing.
  bool get isEmpty => oldest > head;

  /// The cursor to resume from, given what we already hold. Clamps a stale
  /// cursor up to the start of the retention window — the samples in between are
  /// gone, and asking for them forever would spin.
  int resumeCursor(int stored) =>
      (oldest > 0 && stored < oldest - 1) ? oldest - 1 : stored;
}

/// One page of a `SYNC` pull.
class HsSyncPage {
  const HsSyncPage({
    required this.samples,
    required this.next,
    required this.more,
  });

  final List<HsSample> samples;
  final int next; // cursor to resume from
  final bool more; // whether further pages remain
}

/// Result of a full record download.
class HsRecordDownload {
  const HsRecordDownload({required this.data, required this.crcOk});
  final Uint8List data;

  /// True if the reassembled payload's CRC-32 matched the header's `crc32`
  /// (or the header carried no crc, i.e. `crc32 == 0`).
  final bool crcOk;
}

/// Client for the **custom HPI_HS MCUmgr group** (id `0x1000`) — the ProtoCentral
/// Health Store. Full contract in the HealthyPi Move `docs/HPI_HS_API.md`.
/// Gated: only surfaced when [hello] succeeds against a device that implements it.
class HpiHs {
  HpiHs(this.client, {HpiHsLog? log}) : _log = log;

  final SmpClient client;

  /// Optional diagnostics sink; silent when null.
  final HpiHsLog? _log;

  void _logMsg(String m) => _log?.call(m);

  /// Vendor-range group id for the Health Store.
  static const int group = 0x1000;

  // Command ids (§6).
  static const int cmdHello = 0;
  static const int cmdTypes = 1;
  static const int cmdSync = 2;
  static const int cmdSummary = 3;
  static const int cmdRecords = 4;
  static const int cmdAck = 5;
  static const int cmdSynth = 6;

  SmpMessage _check(SmpMessage rsp) {
    final code = rsp.rc;
    if (code != null) {
      throw SmpException(rsp.errorLabel ?? 'rc=$code', rsp.group, rsp.id,
          rsp.seq,
          rc: code);
    }
    return rsp;
  }

  /// `HELLO` — handshake; check schema/group and note `head` (newest seq).
  Future<HsHello> hello() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdHello,
    ));
    final p = rsp.payload;
    // `uid` may arrive as a string or as a byte string / int on some builds —
    // normalise to a stable hex/text key rather than assuming one encoding.
    final rawUid = p['uid'];
    final uid = switch (rawUid) {
      null => '',
      String s => s,
      List<int> b =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
      num n => n.toInt().toRadixString(16),
      _ => rawUid.toString(),
    };
    return HsHello(
      schema: (p['schema'] as num?)?.toInt() ?? 0,
      group: (p['group'] as num?)?.toInt() ?? 0,
      dev: p['dev'] as String? ?? '',
      uid: uid,
      head: (p['head'] as num?)?.toInt() ?? 0,
      // Oldest seq still retrievable. Absent on older firmware → 0, which is
      // the permissive default (nothing has aged out).
      oldest: (p['oldest'] as num?)?.toInt() ?? 0,
      types: (p['types'] as num?)?.toInt() ?? 0,
    );
  }

  /// `TYPES` — fetch the whole registry and cache by id. Never hard-code it.
  ///
  /// **Paged, 5 entries per call.** The registry is 19 entries, so a single call
  /// returns only the first page — loop `from := next` until `next == total` or
  /// the page comes back empty, or ids like `hr_min`/`hr_max` are never seen.
  Future<Map<int, HsType>> types({int from = 0}) async {
    final out = <int, HsType>{};
    var cursor = from;
    var guard = 0;

    while (true) {
      final page = await _typesPage(cursor, out);
      final next = page.next;
      final total = page.total;

      // Stop on: no forward progress, page empty, or the registry is complete.
      if (page.count == 0 || next <= cursor) break;
      cursor = next;
      if (total > 0 && cursor >= total) break;
      if (++guard > 20) break; // registry is 19 entries; never loop forever
    }

    _logMsg('[HPI_HS] TYPES: ${out.length} entries '
        '(${out.values.map((t) => t.key).join(", ")})');
    return out;
  }

  /// Fetch one TYPES page into [out]; returns its paging fields.
  Future<({int next, int total, int count})> _typesPage(
      int from, Map<int, HsType> out) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdTypes,
      payload: {'from': from},
    ));
    final arr = (rsp.payload['types'] as List?) ?? const [];
    if (from == 0 && arr.isNotEmpty) {
      // One-time diagnostic: dump the raw shape of the first entry so wire-key
      // / value-type surprises are visible in the console.
      _logMsg('[HPI_HS] TYPES[0] raw = ${arr.first}');
    }
    for (final e in arr) {
      if (e is Map) {
        try {
          final t = HsType.fromMap(e.map((k, v) => MapEntry(k.toString(), v)));
          out[t.id] = t;
        } catch (err) {
          _logMsg('[HPI_HS] skipped a TYPES entry: $err  raw=$e');
        }
      }
    }
    return (
      next: (rsp.payload['next'] as num?)?.toInt() ?? from,
      total: (rsp.payload['total'] as num?)?.toInt() ?? 0,
      count: arr.length,
    );
  }

  /// `SYNC` — the workhorse. Pull one page of samples from [since].
  ///
  /// Request/response shape is pinned against the firmware handler
  /// (`hpi_hs_mgmt.c: hs_h_sync`): `{since, max} -> {recs: bstr(n*18), n, next,
  /// more}`. `max` is clamped device-side to a 40-sample batch.
  ///
  /// `more` is now `n > 0 && next < head` (HS-2), so it is never true on an empty
  /// page and is safe to loop on. Older firmware set it to just `next < head`.
  Future<HsSyncPage> sync({required int since, int max = 256}) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdSync,
      payload: {'since': since, 'max': max},
    ));

    final bytes = _extractRecs(rsp.payload);
    final samples = HsSample.listFromBytes(bytes);

    if (samples.isEmpty) {
      _logMsg('[HPI_HS] SYNC(since=$since, max=$max) -> 0 samples. '
          'n=${rsp.payload['n']} next=${rsp.payload['next']} '
          'more=${rsp.payload['more']} bytes=${bytes.length}');
    }

    return HsSyncPage(
      samples: samples,
      next: (rsp.payload['next'] as num?)?.toInt() ?? since,
      more: (rsp.payload['more'] as bool?) ?? false,
    );
  }

  /// Pull the packed record blob out of a SYNC response. The CBOR decoder hands
  /// back a `Uint8Buffer` (a `List<int>`), not a `Uint8List`.
  Uint8List _extractRecs(Map<String, Object?> payload) {
    final recs = payload['recs'];
    if (recs is Uint8List) return recs;
    return Uint8List.fromList(((recs as List?) ?? const []).cast<int>());
  }

  /// Convenience: fully drain from [since] to head, page by page.
  Future<List<HsSample>> syncAll({
    int since = 0,
    int max = 256,
    void Function(int fetched)? onProgress,
  }) async {
    final all = <HsSample>[];
    int cursor = since;
    while (true) {
      final page = await sync(since: cursor, max: max);
      all.addAll(page.samples);
      onProgress?.call(all.length);
      cursor = page.next;
      if (!page.more) break;
    }
    return all;
  }

  /// `SUMMARY` — today's card plus the device's own baselines (resting HR,
  /// temp Δ, HRV, steps, and the P3 HRV-derived stress score).
  ///
  /// Returns the typed [HsSummary]; its [HsSummary.raw] is the response exactly
  /// as sent, for callers that want to persist or dump it.
  Future<HsSummary> summary() async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdSummary,
    ));
    return HsSummary(rsp.payload);
  }

  /// `RECORDS list` — every episodic raw-signal session on the device.
  ///
  /// **Paged, and the cursor is an INDEX, not a record id.** The device serves
  /// `HS_REC_LIST_PAGE` (6) headers per call and answers
  /// `{next: from + n, total: <record count>, recs: [...]}`; loop `from := next`
  /// until `next >= total`.
  ///
  /// This previously sent `{'op':'list','since':…}` and read a single page. The
  /// firmware decodes `from`, not `since`, so the cursor was silently ignored —
  /// and without the loop only the first 6 records were ever visible, no matter
  /// how many the watch held.
  ///
  /// [from] is the index to start at; the default walks the whole list.
  Future<List<HsRecordHeader>> recordsList({int from = 0}) async {
    final out = <HsRecordHeader>[];
    var cursor = from;

    // The device bounds the page, so the loop is bounded too — but guard anyway
    // rather than trust a device to terminate our loop for us.
    for (var guard = 0; guard < 512; guard++) {
      final rsp = _check(await client.send(
        op: SmpOp.readReq,
        group: group,
        id: cmdRecords,
        payload: {'op': 'list', 'from': cursor},
      ));

      final recs = (rsp.payload['recs'] as List?) ?? const [];
      for (final e in recs.whereType<Map>()) {
        out.add(HsRecordHeader.fromMap(e.cast<Object?, Object?>()));
      }

      final total = (rsp.payload['total'] as num?)?.toInt() ?? out.length;
      final next = (rsp.payload['next'] as num?)?.toInt() ?? cursor;

      // Terminate on an empty page or a cursor that didn't advance, before
      // trusting `total` — a device that answers oddly must not spin us forever.
      if (recs.isEmpty || next <= cursor) break;
      cursor = next;
      if (cursor >= total) break;
    }

    _logMsg('RECORDS list → ${out.length} header(s)');
    return out;
  }

  /// `RECORDS get` — fetch a chunk of a record's raw payload.
  Future<({Uint8List data, bool eof})> recordsGet({
    required int id,
    required int off,
    required int len,
  }) async {
    final rsp = _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdRecords,
      payload: {'op': 'get', 'id': id, 'off': off, 'len': len},
    ));
    final data = rsp.payload['data'];
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList(((data as List?) ?? const []).cast<int>());
    return (data: bytes, eof: (rsp.payload['eof'] as bool?) ?? false);
  }

  /// Download a full record: loop `RECORDS get` by offset until `eof`,
  /// reassemble the payload, and CRC-32 verify it against the header `crc32`.
  Future<HsRecordDownload> downloadRecord(
    HsRecordHeader header, {
    int chunk = 512,
    void Function(int done, int total)? onProgress,
  }) async {
    final out = BytesBuilder(copy: false);
    int off = 0;
    final total = header.byteLen;
    onProgress?.call(0, total);
    while (true) {
      final res = await recordsGet(id: header.id, off: off, len: chunk);
      out.add(res.data);
      off += res.data.length;
      onProgress?.call(off, total);
      if (res.eof || res.data.isEmpty || (total > 0 && off >= total)) break;
    }
    final bytes = out.toBytes();
    final crcOk = header.crc32 == 0
        ? true
        : Crc32.compute(bytes) == (header.crc32 & 0xFFFFFFFF);
    return HsRecordDownload(data: bytes, crcOk: crcOk);
  }

  /// `RECORDS ack` — **destructive.** Tells the device it may drop record [id].
  ///
  /// Call only after the record's payload is durably stored on your side and
  /// its CRC verified ([HsRecordDownload.crcOk]). There is no undo.
  Future<void> recordsAck(int id) async {
    _check(await client.send(
      op: SmpOp.readReq,
      group: group,
      id: cmdRecords,
      payload: {'op': 'ack', 'id': id},
    ));
  }

  /// `ACK` — **destructive.** Tells the device that every sample with
  /// `seq <= [seq]` is durably stored by the client, permitting it to drop them
  /// from its retention window. There is no undo, and no error is returned if
  /// you lied.
  ///
  /// Pass the highest sequence number you have **committed to durable storage**
  /// — never the `head` from [hello], and never a cursor from an in-memory
  /// [syncAll] that has not been persisted. Doing so silently discards data.
  ///
  /// The correct shape is: page with [sync], commit each page, persist the
  /// cursor, and only then ack the persisted cursor.
  Future<void> ackDurablyStored(int seq) async {
    _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: cmdAck,
      payload: {'acked': seq},
    ));
  }

  /// Renamed to [ackDurablyStored], whose name states the precondition: the
  /// device drops everything at or below [seq], so it must already be persisted.
  @Deprecated('Use ackDurablyStored(seq). This is destructive: the device may '
      'drop all samples with seq <= the acked value. Will be removed in 1.0.0.')
  Future<void> ack(int seq) => ackDurablyStored(seq);

  /// `SYNTH` — **generate fabricated data on the device. TEST BUILDS ONLY.**
  ///
  /// Backdates [days] of synthetic samples so trends, the 7-day skin-temp
  /// baseline and sync-at-scale can be exercised without wearing the watch for a
  /// week. Every sample it writes carries `quality & (1<<6)`
  /// ([HsQuality.synthetic]) and **must be filtered out of anything user-facing**
  /// — on a health device, test data must never render as a measurement.
  ///
  /// **This is destructive by default.** [wipe] discards the existing durable log
  /// first, so a re-run does not stack a second dataset on the first. Real
  /// measurements on the watch that the phone has not yet synced are **gone**.
  /// (`seq` is never rewound by it, so the phone's `(device, seq)` dedup stays
  /// safe.) Pass `wipe: false` to append instead.
  ///
  /// **Returns immediately.** Generation runs on its own device thread and takes
  /// roughly 100 s per week of data — blocking the SMP thread would stall the BLE
  /// link and trip the watchdog. Poll [hello] and watch `head` grow to track it.
  ///
  /// Throws [SmpException] with `rc = -EBUSY` if a generation is already running,
  /// and with an unknown-command `rc` on a **release build**, where the command
  /// does not exist at all (`CONFIG_HPI_HS_SYNTH=n`). Callers should treat that
  /// second case as "this watch is not a test build", not as a failure.
  ///
  /// Returns the device's echo of what it accepted: `{rc, days, wipe}`.
  Future<Map<String, Object?>> synth({int days = 7, bool wipe = true}) async {
    final rsp = _check(await client.send(
      op: SmpOp.writeReq,
      group: group,
      id: cmdSynth,
      payload: {'days': days, 'wipe': wipe},
    ));
    _logMsg('SYNTH days=$days wipe=$wipe → ${rsp.payload}');
    return rsp.payload;
  }
}
