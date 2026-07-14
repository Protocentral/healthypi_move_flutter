// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:path_provider/path_provider.dart';

import '../models/hs_recording.dart';
import 'connection_manager.dart';
import 'database_helper.dart';
import 'healthy_store_client.dart';

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

  /// Load a previously downloaded payload from disk.
  Future<Uint8List?> loadLocal(HsRecording recording) async {
    final path = recording.localPath;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// CSV export for a RECORDS payload (channel columns + timestamps).
  Future<File> exportCsv(HsRecording recording, Uint8List payload) async {
    final samples = HsRecordSamples.decode(recording.header, payload);
    final sr = recording.sampleRate <= 0 ? 1 : recording.sampleRate;
    final start = recording.startTime.toUtc();
    final rows = <List<dynamic>>[
      [
        'timestamp_utc',
        for (var c = 0; c < samples.channels; c++) 'ch$c',
      ],
    ];
    final n = samples.sampleCount;
    for (var i = 0; i < n; i++) {
      final ts = start.add(Duration(microseconds: (i * 1e6 / sr).round()));
      rows.add([
        ts.toIso8601String(),
        for (var c = 0; c < samples.channels; c++)
          samples.data[c][i].toString(),
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

  static int _signalMask(int signal) {
    // Best-effort map into the legacy bit mask (research UI filters).
    switch (signal) {
      case 1:
        return 0x10; // GSR
      case 2:
        return 0x01; // PPG wrist
      case 3:
        return 0x02; // PPG finger
      case 5:
        return 0x04 | 0x08; // accel|gyro
      default:
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
