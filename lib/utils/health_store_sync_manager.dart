import 'dart:async';

import 'package:flutter/foundation.dart';

import 'background_sync_manager.dart';
import 'connection_manager.dart';
import 'database_helper.dart';
import 'health_store_client.dart';

/// Sync over the ProtoCentral **Health Store** (HPI_HS group 0x1000).
///
/// This replaces the legacy dual-channel sync (custom `0x50`/`0x54` cmd/data
/// packets + `FsMgmt` pulls of whole `/lfs/tr*` files). Firmware 2.1.x no longer
/// exposes the legacy command characteristic at all, so on current devices the
/// old path fails with `characteristicNotFound` — this is the path that works.
///
/// Selection is by capability, not version string: `HELLO` **is** the probe
/// (design doc §6). If it answers we sync here; if it doesn't, we delegate to
/// [BackgroundSyncManager] so older firmware keeps working.
///
/// Keeps the [SyncProgress] / [SyncResult] / [progressStream] surface of the
/// legacy manager, so the Home and Device screens are unchanged.
///
/// ## The destructive part
///
/// `ackDurablyStored(seq)` tells the device it may **drop** everything up to
/// `seq`. The loop below therefore only ever acks a cursor that
/// [DatabaseHelper.insertSamplesPage] has already committed to SQLite — that
/// method writes the rows and advances the persisted cursor in one transaction
/// and returns the highest seq it actually stored. We never ack `hello.head`,
/// and we never use `syncAll()` (it buffers pages in memory, so its cursor is
/// not durable).
class HealthStoreSyncManager {
  HealthStoreSyncManager._();
  static final HealthStoreSyncManager instance = HealthStoreSyncManager._();

  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Samples requested per SYNC page.
  static const int _pageSize = 256;

  void _emit(double progress, SyncState state, String message) {
    if (!_progressController.isClosed) {
      _progressController.add(SyncProgress(
        metric: 'all',
        progress: progress,
        state: state,
        message: message,
      ));
    }
  }

  /// Sync [deviceMacAddress] (the platform device id). Routes to the Health
  /// Store when the device supports it, otherwise to the legacy path.
  Future<SyncResult> syncData({
    required String deviceMacAddress,
    required Function(String metric, double progress) onProgress,
    required Function(String message) onStatus,
  }) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
        recordCounts: const {},
        duration: Duration.zero,
      );
    }
    _isSyncing = true;
    final started = DateTime.now();

    final conn = ConnectionManager.instance;
    HealthStoreClient? client;

    try {
      onStatus('Connecting…');
      _emit(0.02, SyncState.connecting, 'Connecting…');
      if (!conn.isConnected || conn.deviceId != deviceMacAddress) {
        await conn.connect(deviceMacAddress);
      }

      // Claims the SMP wire (acquireSmp), settles the MTU, probes HELLO.
      client = HealthStoreClient(deviceMacAddress);
      await client.connect();

      if (!client.hasHealthStore) {
        // Older firmware: hand off to the legacy path. Release our SMP session
        // first — the legacy manager opens its own.
        await client.disconnect();
        client = null;
        _isSyncing = false;
        onStatus('Using legacy sync…');
        final legacySub = BackgroundSyncManager.instance.progressStream
            .listen(_progressController.add);
        try {
          return await BackgroundSyncManager.instance.syncData(
            deviceMacAddress: deviceMacAddress,
            onProgress: onProgress,
            onStatus: onStatus,
          );
        } finally {
          await legacySub.cancel();
        }
      }

      final result = await _syncHealthStore(
          client, started, onProgress, onStatus);
      return result;
    } catch (e) {
      debugPrint('[HS-Sync] failed: $e');
      _emit(0, SyncState.error, '$e');
      return SyncResult(
        success: false,
        message: '$e',
        recordCounts: const {},
        duration: DateTime.now().difference(started),
      );
    } finally {
      // Always release the SMP wire, even on an early return or throw.
      await client?.disconnect();
      _isSyncing = false;
    }
  }

  Future<SyncResult> _syncHealthStore(
    HealthStoreClient client,
    DateTime started,
    Function(String metric, double progress) onProgress,
    Function(String message) onStatus,
  ) async {
    final db = DatabaseHelper.instance;
    final hs = client.hs!;
    final hello = client.hello!;

    // The device serial is the key for the raw store — stable across OSes,
    // unlike the BLE id (a CoreBluetooth UUID on Apple, a MAC on Android).
    final device = hello.dev;

    onStatus('Reading registry…');
    _emit(0.06, SyncState.downloading, 'Reading registry…');

    // TYPES: the self-describing registry. Cache it — deriveTrends needs each
    // type's key (hr/spo2/skin_temp/steps) and scale to convert fixed-point.
    final types = await hs.types();
    if (types.isNotEmpty) {
      await db.upsertTypes(device, [
        for (final t in types.values)
          {
            'id': t.id,
            'key': t.key,
            'unit': t.unit,
            'scale': t.scale,
            'class': t.klass.name,
            'derived': t.derived ? 1 : 0,
            'hk': t.healthKit,
            'hc': t.healthConnect,
          }
      ]);
    }

    // Resume from the highest seq we have durably stored.
    var cursor = await db.getSyncCursor(device);
    final head = hello.head;
    debugPrint('[HS-Sync] dev=$device cursor=$cursor head=$head '
        'types=${types.length}');

    var totalStored = 0;
    int? earliestTs;
    var pages = 0;

    onStatus('Syncing samples…');
    var emptyPage = false;
    while (true) {
      final since = cursor < 0 ? 0 : cursor;
      final page = await hs.sync(since: since, max: _pageSize);

      if (page.samples.isEmpty) {
        // Distinguish "nothing new" from "the device has data but we decoded
        // none" — the latter is a wire-shape mismatch and must not be reported
        // as a successful, up-to-date sync.
        emptyPage = cursor < head;
        break;
      }

      // Commit the page AND advance the persisted cursor in one transaction.
      // Re-inserting a seq is a no-op (PRIMARY KEY (device, seq)), so a retried
      // page can never double-count.
      final newCursor = await db.insertSamplesPage(
        device,
        [
          for (final s in page.samples)
            {
              'seq': s.seq,
              'ts_utc': s.tsUtc,
              'type': s.type,
              'quality': s.quality,
              'value': s.value,
            }
        ],
        head: head,
        schema: hello.schema,
      );

      for (final s in page.samples) {
        if (earliestTs == null || s.tsUtc < earliestTs) earliestTs = s.tsUtc;
      }
      totalStored += page.samples.length;
      pages++;

      // ── Only now is it safe to let the device drop this data. ──
      if (newCursor > cursor) {
        await hs.ackDurablyStored(newCursor);
        cursor = newCursor;
      } else {
        // No forward progress: stop rather than spin.
        debugPrint('[HS-Sync] cursor did not advance ($cursor) — stopping');
        break;
      }

      final progress = (head > 0)
          ? (cursor / head).clamp(0.05, 0.9).toDouble()
          : 0.5;
      onProgress('all', progress);
      _emit(progress, SyncState.downloading,
          'Synced $totalStored samples…');

      if (!page.more) break;
    }

    // Aggregate the raw samples into the derived health_trends cache the trend
    // screens read. Incremental: only the hours we just touched.
    if (totalStored > 0 && earliestTs != null) {
      onStatus('Deriving trends…');
      _emit(0.95, SyncState.parsing, 'Deriving trends…');
      final rows = await db.deriveTrends(device, sinceUtc: earliestTs);
      debugPrint('[HS-Sync] derived $rows trend rows');
    }

    // The device says it holds samples up to `head`, we hold up to `cursor`, and
    // yet SYNC handed back nothing decodable. That is a wire-shape mismatch, not
    // an up-to-date store — say so instead of reporting a green success.
    if (totalStored == 0 && emptyPage) {
      final msg = 'Device reports samples up to seq $head but SYNC returned '
          'none we could decode (stored up to $cursor). Wire shape mismatch — '
          'see the [HPI_HS] SYNC log line for the payload keys.';
      debugPrint('[HS-Sync] $msg');
      _emit(0, SyncState.error, 'Sync returned no samples');
      return SyncResult(
        success: false,
        message: msg,
        recordCounts: const {},
        duration: DateTime.now().difference(started),
      );
    }

    await db.updateLastSyncTime();
    _emit(1.0, SyncState.completed, 'Synced $totalStored samples');

    return SyncResult(
      success: true,
      message: totalStored > 0
          ? 'Synced $totalStored samples in $pages page${pages == 1 ? "" : "s"}'
          : 'Already up to date',
      recordCounts: {'samples': totalStored},
      duration: DateTime.now().difference(started),
    );
  }
}
