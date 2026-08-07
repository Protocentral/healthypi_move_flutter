// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:path_provider/path_provider.dart';

import '../globals.dart';
import '../models/hs_recording.dart';
import 'connection_manager.dart';
import 'database_helper.dart';
import 'healthy_store_client.dart';
import 'hrv_analysis.dart';
import 'signal_view.dart';

/// On-demand list / download / CRC / ack for HPI_HS **RECORDS** (episodic
/// raw-signal sessions: ECG, GSR, PPG, HRV, IMU).
///
/// Replaces the legacy `/lfs/{ecg,gsr,…}` `FsMgmt` pulls for the redesigned
/// Recordings library. Download is **never** eager — the user taps a session.
///
/// ## Safety
///
/// - Claims the SMP wire via [HealthyStoreClient] (same lock as sample sync / DFU).
/// - Persists the payload **before** `recordsAck`.
/// - Acks only when [HsRecordDownload.crcOk] is true.
/// - PARTIAL-flagged headers are stored and shown, not discarded.
class HealthyStoreRecordsManager {
  HealthyStoreRecordsManager(this.deviceId);

  /// Platform BLE id (CoreBluetooth UUID / Android MAC).
  final String deviceId;

  final ConnectionManager _conn = ConnectionManager.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  HealthyStoreClient? _client;

  /// HELLO store key (`uid`, else `dev`) once connected.
  String? get storeKey => _client?.hello?.storeKey;

  bool get isOpen => _client != null && _client!.hasHealthyStore;

  /// Connect the shared link if needed, open an SMP Healthy Store session.
  ///
  /// Throws [SmpBusyException] if sync/DFU holds the wire, or [StateError] if
  /// the device has no HPI_HS group.
  Future<void> open() async {
    if (isOpen) return;

    if (!_conn.isConnected || _conn.deviceId != deviceId) {
      await _conn.connect(deviceId);
    }

    final client = HealthyStoreClient(
      deviceId,
      // Large RECORDS chunks can be slow on a cold flash read.
      requestTimeout: const Duration(seconds: 40),
    );
    await client.connect();

    if (!client.hasHealthyStore) {
      await client.disconnect();
      throw StateError(
          'This watch does not expose the Healthy Store (HELLO failed). '
          'Update firmware to use RECORDS.');
    }

    _client = client;
    debugPrint('[HS-Records] open dev=${client.hello!.storeKey} '
        'mtu=${client.maxWriteLength}');
  }

  Future<void> close() async {
    final c = _client;
    _client = null;
    await c?.disconnect();
  }

  /// List records on the watch (full inventory, `since: 0`) and merge with
  /// anything already stored on the phone.
  Future<List<HsRecording>> list() async {
    await open();
    final hs = _client!.hs!;
    final device = _client!.hello!.storeKey;

    // Full inventory for the library UI — recordsList pages internally until the
    // device's `total`, so this is every header still on the watch, not the
    // first six.
    final headers = await hs.recordsList();
    debugPrint('[HS-Records] list → ${headers.length} header(s)');

    // Advance the list cursor to the highest id we have *seen* (not necessarily
    // downloaded). Preserves the sample-tier cursor in the same row.
    if (headers.isNotEmpty) {
      final maxId = headers.map((h) => h.id).reduce((a, b) => a > b ? a : b);
      await _db.setLastRecordId(device, maxId);
    }

    final local = await _db.getHsRecordIndex(device);
    final out = <HsRecording>[
      for (final h in headers)
        HsRecording(
          header: h,
          localPath: local[h.id]?['file_path'] as String?,
          crcOk: local[h.id] == null
              ? null
              : (local[h.id]!['crc_ok'] as int? ?? 0) == 1,
          acked: (local[h.id]?['acked'] as int? ?? 0) == 1,
        ),
    ];

    // Local-only rows (acked off the watch but still on the phone).
    final seen = {for (final r in out) r.id};
    for (final e in local.entries) {
      if (seen.contains(e.key)) continue;
      final row = e.value;
      out.add(HsRecording(
        header: _headerFromRow(row),
        localPath: row['file_path'] as String?,
        crcOk: (row['crc_ok'] as int? ?? 0) == 1,
        acked: true,
      ));
    }

    out.sort((a, b) => b.startTs.compareTo(a.startTs));
    return out;
  }

  /// List only what is already on the phone (no BLE).
  Future<List<HsRecording>> listLocalOnly(String storeDeviceKey) async {
    final local = await _db.getHsRecordIndex(storeDeviceKey);
    final out = <HsRecording>[
      for (final row in local.values)
        HsRecording(
          header: _headerFromRow(row),
          localPath: row['file_path'] as String?,
          crcOk: (row['crc_ok'] as int? ?? 0) == 1,
          acked: (row['acked'] as int? ?? 0) == 1,
        ),
    ];
    out.sort((a, b) => b.startTs.compareTo(a.startTs));
    return out;
  }

  /// Download one record on demand. CRC-verifies, persists, then acks when safe.
  Future<HsRecordingDownloadResult> download(
    HsRecordHeader header, {
    void Function(int done, int total)? onProgress,
  }) async {
    await open();
    final hs = _client!.hs!;
    final device = _client!.hello!.storeKey;

    // Chunk off the live ATT MTU (minus a little headroom for SMP/CBOR), capped
    // at the device's own per-chunk limit (HS_REC_GET_MAX = 512). Asking for
    // more just wastes a round-trip's worth of expectation.
    final mtu = _client!.maxWriteLength ?? 512;
    final chunk = (mtu - 32).clamp(64, 512);

    final dl = await hs.downloadRecord(
      header,
      chunk: chunk,
      onProgress: onProgress,
    );

    final file = await _savePayload(device, header, dl.data);
    final status = header.isPartial ? 'partial' : 'complete';

    await _db.upsertHsRecord(
      device: device,
      header: header,
      filePath: file.path,
      crcOk: dl.crcOk,
      acked: false,
      status: dl.crcOk ? status : 'error',
    );

    // Legacy research_* tables kept as a parallel index for any older readers.
    await _mirrorResearchTables(device, header, file.path, dl);

    var acked = false;
    if (dl.crcOk) {
      try {
        await hs.recordsAck(header.id);
        acked = true;
        await _db.markHsRecordAcked(device, header.id);
        debugPrint('[HS-Records] ack id=${header.id} ok');
      } catch (e) {
        // Non-fatal: payload is durable; device may still hold the session.
        debugPrint('[HS-Records] recordsAck(${header.id}) failed: $e');
      }
    } else {
      debugPrint('[HS-Records] CRC mismatch id=${header.id} — not acking');
    }

    final recording = HsRecording(
      header: header,
      localPath: file.path,
      crcOk: dl.crcOk,
      acked: acked,
    );

    return HsRecordingDownloadResult(
      recording: recording,
      data: dl.data,
      crcOk: dl.crcOk,
      acked: acked,
    );
  }

  /// Delete the phone's copy of a downloaded recording: index rows, payload
  /// file, and any CSV exported from it.
  ///
  /// **Phone-side only.** RECORDS has no delete/erase op — its verbs are list /
  /// get / ack (docs/HPI_HS_API.md), and `ACK` is a no-op on current firmware
  /// because flash is reclaimed by size-based retention. So a session still held
  /// by the watch reappears on the next [list] as `ON WATCH`, which is honest:
  /// the data was freed here, not there. Only a session the watch has already
  /// dropped disappears for good.
  ///
  /// Never throws on a file it cannot unlink — the rows are gone by then, and a
  /// half-finished delete that reports failure is worse than an orphaned byte
  /// range the wipe sweep will collect later.
  Future<void> deleteLocal(HsRecording recording) async {
    final device = _client?.hello?.storeKey ??
        await _db.getHsRecordDeviceKey(recording.id) ??
        await _db.getHealthyStoreDeviceKey();
    if (device == null) {
      throw StateError('No Healthy Store device key — nothing to delete under.');
    }

    final paths = await _db.deleteHsRecord(device, recording.id);
    final local = recording.localPath;
    if (local != null && local.isNotEmpty) paths.add(local);

    // Exported CSVs sit loose in the documents root and no table indexes them.
    try {
      final dir = await getApplicationDocumentsDirectory();
      paths.add(
          '${dir.path}/hs_record_${recording.id}_${recording.kindLabel.toLowerCase()}.csv');
    } catch (e) {
      debugPrint('[HS-Records] could not resolve export path: $e');
    }

    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[HS-Records] could not delete $p: $e');
      }
    }
    debugPrint('[HS-Records] deleted local copy of #${recording.id}');
  }

  /// Load a previously downloaded payload from disk.
  Future<Uint8List?> loadLocal(HsRecording recording) async {
    final path = recording.localPath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// CSV export for a RECORDS payload (channel columns + timestamps).
  ///
  /// Each channel gets a raw column **and** a `_detrended` column (raw minus a
  /// centred moving average, ~1 s wide). The raw counts stay the record of
  /// truth, but plotting them directly in a spreadsheet gives a flat line: wrist
  /// PPG rides a DC pedestal thousands of times larger than its pulsatile
  /// component, so a min/max autoscale spends the whole axis on the offset and
  /// the session's settling transient. The detrended column is what a user
  /// actually wants to chart.
  Future<File> exportCsv(HsRecording recording, Uint8List payload) async {
    // R-R records are irregularly spaced by construction, so the fixed-rate
    // timebase and the moving-average detrend below are both meaningless for
    // them — `sampleRate` is not a real Hz on an HRV record. They get their own
    // writer.
    if (recording.kind == HsRecordingKind.hrv) {
      return exportHrvCsv(recording, payload);
    }

    final samples = HsRecordSamples.decode(recording.header, payload);
    final sr = recording.sampleRate <= 0 ? 1 : recording.sampleRate;
    final start = recording.startTime.toUtc();

    final detrended = [
      for (final ch in samples.data) detrend(ch, window: sr.clamp(3, 512)),
    ];

    final rows = <List<dynamic>>[
      [
        'timestamp_utc',
        't_ms',
        for (var c = 0; c < samples.channels; c++) ...['ch$c', 'ch${c}_detrended'],
      ],
    ];
    final n = samples.sampleCount;
    for (var i = 0; i < n; i++) {
      final tMs = i * 1000 / sr;
      final ts = start.add(Duration(microseconds: (i * 1e6 / sr).round()));
      rows.add([
        ts.toIso8601String(),
        tMs.toStringAsFixed(1),
        for (var c = 0; c < samples.channels; c++) ...[
          samples.data[c][i].toString(),
          detrended[c][i].toStringAsFixed(2),
        ],
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final name =
        'hs_record_${recording.id}_${recording.kindLabel.toLowerCase()}.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(csv);
    return file;
  }

  /// CSV export for an **R-R interval** record (`HsSignal.hrvRr`, uint16 ms).
  ///
  /// A tachogram, not a waveform: each row is one beat-to-beat interval, so the
  /// time axis is the *cumulative sum* of the intervals rather than `i / sr`.
  /// `rr_accepted` carries the artifact verdict instead of silently dropping
  /// rows — a researcher validating the watch needs to see the beats the filter
  /// rejected, not a quietly shortened file.
  Future<File> exportHrvCsv(HsRecording recording, Uint8List payload) async {
    final samples = HsRecordSamples.decode(recording.header, payload);
    final raw = samples.data.isEmpty ? const <double>[] : samples.data.first;
    final start = recording.startTime.toUtc();
    final accepted = RrSeries.filtered(raw).rrMs.toList();

    // Walk the accepted list in step with the raw one to label each row.
    var next = 0;
    var elapsedMs = 0.0;

    final rows = <List<dynamic>>[
      [
        'beat_index',
        'timestamp_utc',
        't_ms',
        'rr_ms',
        'instant_hr_bpm',
        'rr_accepted',
      ],
    ];
    for (var i = 0; i < raw.length; i++) {
      final rr = raw[i];
      final isAccepted = next < accepted.length && accepted[next] == rr;
      if (isAccepted) next++;
      elapsedMs += rr;
      rows.add([
        i,
        start.add(Duration(microseconds: (elapsedMs * 1000).round()))
            .toIso8601String(),
        elapsedMs.toStringAsFixed(1),
        rr.toStringAsFixed(1),
        rr > 0 ? (60000 / rr).toStringAsFixed(2) : '',
        isAccepted ? 1 : 0,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/hs_record_${recording.id}_hrv.csv');
    await file.writeAsString(csv);
    return file;
  }

  /// CSV export of the R-R intervals **derived from an ECG record** — the
  /// reference series for an HRV spot check.
  ///
  /// Sits alongside [exportHrvCsv] with the same columns on purpose: validating
  /// the watch's own HRV means diffing two files, and that is only meaningful if
  /// they are the same shape.
  Future<File> exportEcgRrCsv(HsRecording recording, Uint8List payload) async {
    final samples = HsRecordSamples.decode(recording.header, payload);
    final channel = samples.data.isEmpty ? const <double>[] : samples.data.first;
    final sr = recording.sampleRate;
    final peaks = detectRPeaks(channel, sampleRate: sr);
    final raw = rrIntervalsMs(peaks, sr);
    final accepted = RrSeries.filtered(raw).rrMs.toList();
    final start = recording.startTime.toUtc();

    var next = 0;
    final rows = <List<dynamic>>[
      [
        'beat_index',
        'r_peak_sample',
        'timestamp_utc',
        't_ms',
        'rr_ms',
        'instant_hr_bpm',
        'rr_accepted',
      ],
    ];
    for (var i = 0; i < raw.length; i++) {
      final rr = raw[i];
      final isAccepted = next < accepted.length && accepted[next] == rr;
      if (isAccepted) next++;
      // Time of the R peak that *closes* this interval, off the ECG's own clock
      // — exact, unlike a cumulative sum, because the sample index is known.
      final sample = peaks[i + 1];
      final tMs = sr > 0 ? sample * 1000 / sr : 0.0;
      rows.add([
        i,
        sample,
        start.add(Duration(microseconds: (tMs * 1000).round())).toIso8601String(),
        tMs.toStringAsFixed(1),
        rr.toStringAsFixed(1),
        rr > 0 ? (60000 / rr).toStringAsFixed(2) : '',
        isAccepted ? 1 : 0,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/hs_record_${recording.id}_ecg_rr.csv');
    await file.writeAsString(csv);
    return file;
  }

  Future<File> _savePayload(
    String device,
    HsRecordHeader header,
    Uint8List data,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
        '${appDir.path}/HealthyPiRecordings/$device/hs_records');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/${header.id}.bin');
    await file.writeAsBytes(data, flush: true);
    return file;
  }

  Future<void> _mirrorResearchTables(
    String device,
    HsRecordHeader header,
    String path,
    HsRecordDownload dl,
  ) async {
    final duration = header.sampleRate > 0 && header.nSamples > 0
        ? (header.nSamples / header.sampleRate).round()
        : 0;
    final mask = _signalMask(header.signal);
    await _db.insertResearchSession(
      deviceMac: device,
      sessionTimestamp: header.id,
      startTime: header.startTime.toLocal(),
      endTime: header.startTime
          .toLocal()
          .add(Duration(seconds: duration)),
      durationSeconds: duration,
      signalMask: mask,
      status: header.isPartial
          ? 'partial'
          : (dl.crcOk ? 'complete' : 'error'),
      totalSizeBytes: dl.data.length,
      syncStatus: dl.crcOk ? 'synced' : 'error',
    );
    await _db.insertResearchFile(
      sessionTimestamp: header.id,
      signalType: header.signalName,
      filePath: path,
      sampleCount: header.nSamples,
      sampleRateHz: header.sampleRate,
      fileSizeBytes: dl.data.length,
    );
  }

  /// Map an [HsSignal] into the legacy research bit mask (research UI filters).
  ///
  /// Keyed off the firmware's **1-based** enum. The literals here used to be
  /// 0-based, so a GSR session was mirrored as PPG-wrist and so on.
  static int _signalMask(int signal) {
    switch (signal) {
      case HsSignal.bioz:
        return hPi4Global.SIGNAL_GSR;
      case HsSignal.ppgWrist:
        return hPi4Global.SIGNAL_PPG_WRIST;
      case HsSignal.ppgFinger:
        return hPi4Global.SIGNAL_PPG_FINGER;
      case HsSignal.acc:
        return hPi4Global.SIGNAL_ACCEL | hPi4Global.SIGNAL_GYRO;
      default:
        // ECG and HRV have no bit in the legacy research mask.
        return 0;
    }
  }

  static HsRecordHeader _headerFromRow(Map<String, Object?> row) {
    return HsRecordHeader(
      id: row['record_id'] as int? ?? 0,
      startTs: row['start_ts'] as int? ?? 0,
      signal: row['signal'] as int? ?? 0,
      sampleFormat: row['sample_format'] as int? ?? 0,
      channels: row['channels'] as int? ?? 1,
      sampleRate: row['sample_rate'] as int? ?? 0,
      nSamples: row['n_samples'] as int? ?? 0,
      byteLen: row['byte_len'] as int? ?? 0,
      crc32: row['crc32'] as int? ?? 0,
      flags: row['flags'] as int? ?? 0,
    );
  }
}
