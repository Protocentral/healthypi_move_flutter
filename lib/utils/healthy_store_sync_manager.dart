import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_sync_manager.dart';
import 'connection_manager.dart';
import 'database_helper.dart';
import 'healthy_store_client.dart';

/// Sync over the ProtoCentral **Healthy Store** (HPI_HS group 0x1000).
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
/// ## ACK
///
/// **On current firmware `hpi_hs_ack()` is a no-op** — it does *not* free flash.
/// Retention is size-based only (H4, as designed). So do not expect ACK to
/// reclaim space, and do not treat a successful ACK as "the device dropped it".
///
/// We still ack strictly *after* the data is durable, and we keep that
/// discipline deliberately: the API contract says an ack may drop data, and a
/// future firmware could start honouring it. The loop only ever acks a cursor
/// that [DatabaseHelper.insertSamplesPage] has already committed to SQLite —
/// that method writes the rows and advances the persisted cursor in one
/// transaction and returns the highest seq it actually stored. We never ack
/// `hello.head`, and we never use `syncAll()` (it buffers pages in memory, so
/// its cursor is not durable).
class HealthyStoreSyncManager {
  HealthyStoreSyncManager._();
  static final HealthyStoreSyncManager instance = HealthyStoreSyncManager._();

  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Samples requested per SYNC page.
  static const int _pageSize = 256;

  /// Version of the `deriveTrends` logic. `health_trends` is a derived cache, so
  /// changing what derivation *means* invalidates every row it ever wrote.
  /// **Bump this whenever deriveTrends changes semantics** — the next sync then
  /// replays derivation over the stored raw samples automatically.
  ///
  /// v2: cumulative metrics (steps) are differenced into per-hour increments, and
  ///     HR extremes come from the hr_min/hr_max types rather than a
  ///     peak-of-means over the hr series.
  /// v3: firmware P3 — continuous HRV (hrv_rmssd, gated on hrv_coverage) is
  ///     derived into a trend, and the two `stress` metrics are split apart by
  ///     the MANUAL quality bit instead of being averaged onto one axis.
  static const int _deriveVersion = 3;
  static const String _deriveVersionKey = 'derive_version';

  /// Developer opt-in: admit firmware-fabricated (SYNTHETIC) samples into the
  /// derived trends. Off in production. See [ScrSettingsNew].
  static const String includeSyntheticPrefKey = 'include_synthetic_data';
  static const String _syntheticModeKey = 'derive_included_synthetic';

  /// Mirrors [includeSyntheticPrefKey] for the UI, so the app can say so on
  /// screen whenever it is charting fabricated data.
  ///
  /// The firmware handoff is explicit that a synthetic sample must never be
  /// *silently* mistaken for a measurement — that is the entire point of the
  /// quality bit. Filtering it out satisfies that; charting it behind a
  /// developer opt-in with no label does not. `HpiSyntheticBanner` watches this.
  final ValueNotifier<bool> syntheticIncluded = ValueNotifier<bool>(false);

  /// Prime [syntheticIncluded] from storage. Call once during startup, before
  /// the first frame, so the banner is correct on the very first paint rather
  /// than appearing after the first sync.
  Future<void> loadSyntheticFlag() => _includeSynthetic();

  Future<bool> _includeSynthetic() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(includeSyntheticPrefKey) ?? false;
    syntheticIncluded.value = v;
    return v;
  }

  /// How many of the newest samples to fetch up-front, ahead of the backlog, so
  /// the UI has current data immediately. Sized to sit inside the device's RAM
  /// ring (HS_RING_N = 512) — a cursor that close to `head` is served from RAM
  /// rather than a flash scan, so this pass is cheap even on a big backlog.
  static const int _recentWindow = 400;

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
  /// [budget] caps one sync's wall-clock time. The default keeps "Sync now"
  /// snappy; a deliberate "catch up history" run passes a longer one. Either way
  /// the sync is resumable and cancellable, so a long budget can't strand the UI.
  Future<SyncResult> syncData({
    required String deviceMacAddress,
    required Function(String metric, double progress) onProgress,
    required Function(String message) onStatus,
    Duration? budget,
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
    _cancelled = false;
    final started = DateTime.now();
    final deadline = started.add(budget ?? _budget);

    var totalStored = 0;
    String? lastError;

    try {
      // A catch-up drain is long and the link can drop mid-way. The cursor is
      // persisted after every page, so a dropped session is not lost work — we
      // reconnect and carry on from where we got to. Keep going as long as each
      // attempt makes progress; stop when an attempt stores nothing new, when
      // the budget runs out, or when cancelled.
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        final outcome = await _runSession(
            deviceMacAddress, deadline, onProgress, onStatus);

        if (outcome.legacy != null) return outcome.legacy!;

        totalStored += outcome.stored;
        lastError = outcome.error;

        if (outcome.done) {
          await DatabaseHelper.instance.updateLastSyncTime();
          _emit(1.0, SyncState.completed, 'Synced $totalStored samples');
          return SyncResult(
            success: true,
            message: totalStored > 0
                ? 'Synced $totalStored samples'
                : 'Already up to date',
            recordCounts: {'samples': totalStored},
            duration: DateTime.now().difference(started),
          );
        }

        if (outcome.stored == 0) break; // no forward progress — stop retrying
        if (_shouldStop(deadline)) break; // out of budget, or cancelled

        debugPrint('[HS-Sync] session ended early after ${outcome.stored} '
            'samples (attempt $attempt/$_maxAttempts) — resuming');
        onStatus('Reconnecting to resume…');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      // Partial: we stored real data but didn't reach head — either the budget
      // ran out, the user cancelled, or the link kept dropping. Report it
      // honestly; the next sync resumes from the persisted cursor.
      if (totalStored > 0) {
        await DatabaseHelper.instance.updateLastSyncTime();
        _emit(1.0, SyncState.completed, 'Synced $totalStored samples (partial)');
        return SyncResult(
          success: true,
          message: _cancelled
              ? 'Stopped — kept $totalStored samples'
              : 'Synced $totalStored samples · more remaining, sync again to '
                  'continue',
          recordCounts: {'samples': totalStored},
          duration: DateTime.now().difference(started),
        );
      }

      _emit(0, SyncState.error, lastError ?? 'Sync failed');
      return SyncResult(
        success: false,
        message: lastError ?? 'Sync failed',
        recordCounts: const {},
        duration: DateTime.now().difference(started),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// How many times to reconnect and resume a drain that dies mid-way.
  static const int _maxAttempts = 6;

  /// SMP per-request timeout for sync. A catch-up SYNC page makes the device
  /// scan its flash segments, which is far slower than the 10 s default.
  static const Duration _syncTimeout = Duration(seconds: 25);

  /// Hard wall-clock budget for one "Sync now". The device's catch-up scan is
  /// O(since) per page (see docs/HS_SYNC_FIRMWARE_BUG.md issue 2), so a large
  /// backlog cannot be drained in one go — without a budget the sync would run
  /// for many minutes and read as a hang. We stop, report what we stored, and
  /// resume from the persisted cursor on the next tap.
  static const Duration _budget = Duration(seconds: 75);

  bool _cancelled = false;

  /// Ask an in-flight sync to stop at the next page boundary. Everything already
  /// stored stays stored; the next sync resumes from the persisted cursor.
  void cancel() {
    if (_isSyncing) {
      _cancelled = true;
      debugPrint('[HS-Sync] cancel requested');
    }
  }

  bool _shouldStop(DateTime deadline) =>
      _cancelled || DateTime.now().isAfter(deadline);

  /// One connect → drain → disconnect cycle.
  Future<_SessionOutcome> _runSession(
    String deviceMacAddress,
    DateTime deadline,
    Function(String metric, double progress) onProgress,
    Function(String message) onStatus,
  ) async {
    final conn = ConnectionManager.instance;
    HealthyStoreClient? client;

    try {
      onStatus('Connecting…');
      _emit(0.02, SyncState.connecting, 'Connecting…');
      if (!conn.isConnected || conn.deviceId != deviceMacAddress) {
        await conn.connect(deviceMacAddress);
      }

      // Claims the SMP wire (acquireSmp), settles the MTU, probes HELLO.
      client = HealthyStoreClient(deviceMacAddress,
          requestTimeout: _syncTimeout);
      await client.connect();

      if (!client.hasHealthyStore) {
        // Older firmware: hand off to the legacy path. Release our SMP session
        // first — the legacy manager opens its own.
        await client.disconnect();
        client = null;
        onStatus('Using legacy sync…');
        final legacySub = BackgroundSyncManager.instance.progressStream
            .listen(_progressController.add);
        try {
          final r = await BackgroundSyncManager.instance.syncData(
            deviceMacAddress: deviceMacAddress,
            onProgress: onProgress,
            onStatus: onStatus,
          );
          return _SessionOutcome(legacy: r);
        } finally {
          await legacySub.cancel();
        }
      }

      return await _drain(client, deadline, onProgress, onStatus);
    } catch (e) {
      debugPrint('[HS-Sync] session failed: $e');
      return _SessionOutcome(error: '$e');
    } finally {
      // Always release the SMP wire, even on an early return or throw.
      await client?.disconnect();
    }
  }

  /// Fetch the newest [_recentWindow] samples ahead of the backlog and derive
  /// trends from them, so the screens show current data within seconds instead
  /// of at the end of a long drain.
  ///
  /// Stores with `advanceCursor: false` — the backlog cursor must not jump, or
  /// the older samples would be skipped forever. Failures here are swallowed:
  /// this is an optimisation, and the backlog drain is the source of truth.
  Future<int> _fetchRecent(
    HpiHs hs,
    DatabaseHelper db,
    String device,
    int head,
    int schema,
  ) async {
    var cursor = head - _recentWindow;
    var stored = 0;
    int? earliestTs;
    try {
      while (cursor < head) {
        final page = await hs.sync(since: cursor, max: _pageSize);
        if (page.samples.isEmpty) break;

        await db.insertSamplesPage(
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
          schema: schema,
          advanceCursor: false, // keep the backlog cursor where it is
        );

        var maxSeq = cursor;
        for (final s in page.samples) {
          if (earliestTs == null || s.tsUtc < earliestTs) earliestTs = s.tsUtc;
          if (s.seq > maxSeq) maxSeq = s.seq;
        }
        stored += page.samples.length;
        if (maxSeq <= cursor) break; // no forward progress
        cursor = maxSeq;
        if (!page.more) break;
      }

      if (stored > 0 && earliestTs != null) {
        // Must honour the same opt-in as the backlog drain. Defaulting to false
        // here made the recent-first pass drop synthetic samples while the
        // backlog kept them, so a bench device showed a hole at the newest end
        // of every chart — the opposite of what the toggle promises.
        final rows = await db.deriveTrends(device,
            sinceUtc: earliestTs, includeSynthetic: await _includeSynthetic());
        debugPrint('[HS-Sync] recent-first: $stored samples, $rows trend rows '
            '— the UI has current data now');
      }
    } catch (e) {
      debugPrint('[HS-Sync] recent-first pass failed (non-fatal): $e');
    }
    return stored;
  }

  /// Drain pages within one live session. Returns what it managed to store and
  /// whether it reached `head`; a mid-drain failure is reported, not thrown,
  /// because the cursor is already persisted and the caller can resume.
  Future<_SessionOutcome> _drain(
    HealthyStoreClient client,
    DateTime deadline,
    Function(String metric, double progress) onProgress,
    Function(String message) onStatus,
  ) async {
    final db = DatabaseHelper.instance;
    final hs = client.hs!;
    final hello = client.hello!;

    // Key the raw store on HELLO.uid — the per-unit device id. `dev` is only a
    // model string ("healthypi-move"), identical on every watch, so keying on it
    // would collide two devices onto one (device, seq) space. Stable across
    // OSes, unlike the BLE id (a CoreBluetooth UUID on Apple, a MAC on Android).
    final device = hello.storeKey;

    // Re-key anything stored under the old model-string key (pre-uid builds).
    if (hello.uid.isNotEmpty && hello.dev.isNotEmpty && hello.dev != device) {
      await db.rekeyHealthyStoreDevice(hello.dev, device);
    }

    onStatus('Reading registry…');
    _emit(0.06, SyncState.downloading, 'Reading registry…');

    // TYPES: the self-describing registry. deriveTrends needs each type's key
    // (hr/spo2/skin_temp/steps) and scale to convert the fixed-point values.
    final knownBefore = (await db.getTypes(device)).keys.toSet();
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

    // Replay derivation over the whole store when it can no longer be trusted.
    //
    // `health_trends` is a *derived cache*, so it is only as good as the code and
    // the registry that produced it. Two things invalidate it, and both have now
    // bitten us:
    //   • the registry grew — samples whose type id we didn't recognise at the
    //     time were silently dropped (TYPES paging was broken, so only ids
    //     0x01–0x05 were cached and spo2/skin_temp/steps never derived); and
    //   • the derivation logic itself changed (cumulative steps → per-hour
    //     deltas, HR extremes from hr_min/hr_max).
    //
    // A version stamp covers both, and every future change, without needing to
    // guess which rows are stale. Bump _deriveVersion whenever deriveTrends
    // changes meaning.
    final includeSynthetic = await _includeSynthetic();

    final gained = types.keys.toSet().difference(knownBefore);
    final storedVersion = await db.getMetadata<int>(_deriveVersionKey) ?? 0;
    // The synthetic setting is part of "what derivation means", so flipping it
    // invalidates the cache exactly like a version bump does.
    final derivedWithSynthetic =
        (await db.getMetadata<int>(_syntheticModeKey) ?? 0) == 1;
    final stale = storedVersion != _deriveVersion ||
        derivedWithSynthetic != includeSynthetic;

    if (stale || (knownBefore.isNotEmpty && gained.isNotEmpty)) {
      final why = storedVersion != _deriveVersion
          ? 'derivation v$storedVersion → v$_deriveVersion'
          : (derivedWithSynthetic != includeSynthetic
              ? 'synthetic ${derivedWithSynthetic ? "on" : "off"} → '
                  '${includeSynthetic ? "on" : "off"}'
              : 'registry gained ${gained.length} types '
                  '(${gained.map((id) => types[id]?.key ?? "0x${id.toRadixString(16)}").join(", ")})');
      debugPrint('[HS-Sync] rebuilding trends from stored samples — $why');
      onStatus('Rebuilding trends…');
      final rows = await db.rebuildAllTrends(device,
          includeSynthetic: includeSynthetic);
      await db.setMetadata(_deriveVersionKey, _deriveVersion);
      await db.setMetadata(_syntheticModeKey, includeSynthetic ? 1 : 0);
      debugPrint('[HS-Sync] rebuilt $rows trend rows from existing data');
    }

    // Resume from the highest seq we have durably stored.
    final storedCursor = await db.getSyncCursor(device);
    final head = hello.head;

    // `oldest` is the start of the device's retention window. A cursor below it
    // points at samples that have aged out and are gone — asking for them
    // forever would spin, so jump forward. This is also exactly the path the
    // HS-2 one-time flash migration takes (it discards the old log and rounds
    // seq up to a segment boundary, so `oldest` leaps ahead).
    var cursor = hello.resumeCursor(storedCursor);
    if (cursor != storedCursor) {
      debugPrint('[HS-Sync] cursor $storedCursor is below oldest=${hello.oldest}'
          ' — those samples are gone; resuming from $cursor');
    }

    debugPrint('[HS-Sync] dev=$device cursor=$cursor head=$head '
        'oldest=${hello.oldest} types=${types.length}');

    var stored = 0;
    int? earliestTs;
    String? error;
    var done = false;

    // `oldest > head` means the store is empty (HS-2 §4) — nothing to do, and
    // not an error.
    if (hello.isEmpty) {
      debugPrint('[HS-Sync] device store is empty (oldest > head)');
      return const _SessionOutcome(stored: 0, done: true);
    }

    // ── Newest-first pass ───────────────────────────────────────────────────
    // SYNC only walks forward from a cursor, so a device with a long backlog
    // hands us weeks-old samples first and today's screens stay empty until the
    // drain finally catches up. Grab the most recent window up front so the UI
    // has real data immediately, storing it WITHOUT advancing the cursor — the
    // backlog below still drains from where it left off, and re-fetching these
    // seqs later is a no-op (PRIMARY KEY (device, seq)).
    //
    // It's also the cheap request for the device: a cursor near `head` is served
    // from the RAM ring instead of a flash scan, when the ring is warm.
    if (head > _recentWindow && cursor < head - _recentWindow) {
      // …but only if we don't already have that window. Re-fetching it on every
      // tap would burn budget that belongs to the backlog. New samples arrive
      // between syncs, so `head` moves and this re-runs when it should.
      final have = await db.countSamplesAbove(device, head - _recentWindow);
      if (have < _recentWindow) {
        onStatus('Fetching recent data…');
        final recent = await _fetchRecent(hs, db, device, head, hello.schema);
        if (recent > 0) stored += recent;
      } else {
        debugPrint('[HS-Sync] recent window already stored ($have) — skipping');
      }
    }

    onStatus('Syncing history…');
    try {
      while (true) {
        // Stop at a page boundary when the budget runs out or the user cancels.
        // Everything already stored is durable, so this is a clean stop, not a
        // failure — the next sync resumes from the persisted cursor.
        if (_shouldStop(deadline)) {
          debugPrint('[HS-Sync] stopping at cursor $cursor/$head '
              '(${_cancelled ? "cancelled" : "budget reached"})');
          break;
        }

        final since = cursor < 0 ? 0 : cursor;
        final page = await hs.sync(since: since, max: _pageSize);

        if (page.samples.isEmpty) {
          // Nothing decodable. If we're already at head this is simply
          // "caught up"; if not, the device has data we failed to read and that
          // must not be reported as a clean, up-to-date sync.
          if (cursor >= head) {
            done = true;
          } else {
            error = 'Device holds samples up to seq $head but SYNC returned '
                'none we could decode (stored up to $cursor).';
            debugPrint('[HS-Sync] $error');
          }
          break;
        }

        // Commit the page AND advance the persisted cursor in one transaction.
        // Re-inserting a seq is a no-op (PRIMARY KEY (device, seq)), so a
        // retried page after a dropped link can never double-count.
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
        stored += page.samples.length;

        if (newCursor > cursor) {
          cursor = newCursor;
        } else {
          debugPrint('[HS-Sync] cursor did not advance ($cursor) — stopping');
          done = true;
          break;
        }

        final progress =
            (head > 0) ? (cursor / head).clamp(0.05, 0.9).toDouble() : 0.5;
        onProgress('all', progress);
        _emit(progress, SyncState.downloading,
            'History $cursor / $head · $stored samples');

        if (!page.more || cursor >= head) {
          done = true;
          break;
        }
      }
    } catch (e) {
      // A timeout or link drop mid-drain. Everything committed so far is
      // durable, so this is partial progress, not a failure — the caller
      // reconnects and resumes from the persisted cursor.
      error = '$e';
      debugPrint('[HS-Sync] drain interrupted after $stored samples: $e');
    }

    // ACK once per session, not once per page.
    //
    // Every page is already committed with its cursor persisted, so the invariant
    // that matters — never ack data we haven't durably stored — holds either way.
    // Acking per page cost an extra SMP round-trip for all 819 pages of a full
    // drain, doubling the request count for no benefit. Acking the final cursor
    // once says exactly the same thing. If the drain died mid-way we simply ack
    // less; the next session re-acks from its own persisted cursor.
    if (stored > 0 && cursor > storedCursor) {
      try {
        await hs.ackDurablyStored(cursor);
      } catch (e) {
        // Non-fatal: ACK frees nothing on current firmware, and the cursor is
        // already durable on our side.
        debugPrint('[HS-Sync] ack($cursor) failed (non-fatal): $e');
      }
    }

    // Aggregate whatever we got into the derived health_trends cache the trend
    // screens read — even on a partial drain, so the UI shows real data now.
    if (stored > 0 && earliestTs != null) {
      onStatus('Deriving trends…');
      _emit(0.95, SyncState.parsing, 'Deriving trends…');
      final rows = await db.deriveTrends(device,
          sinceUtc: earliestTs, includeSynthetic: includeSynthetic);
      debugPrint('[HS-Sync] derived $rows trend rows');
    }

    // SUMMARY carries what the phone cannot derive itself: the device's own
    // rolling baselines, and — since firmware P3 — the HRV-derived stress score
    // with its validity flag. Cheap (one round-trip), so refresh it every
    // session, and never let a failure here fail the sync: the samples are the
    // system of record, this is a convenience read on top of them.
    try {
      await db.setHsSummary(device, (await hs.summary()).raw);
    } catch (e) {
      debugPrint('[HS-Sync] SUMMARY refresh failed (non-fatal): $e');
    }

    // What actually landed, per type. This distinguishes "never downloaded" from
    // "downloaded but dropped in derivation" — the two look identical in the UI.
    final counts = await db.sampleCountsByType(device);
    if (counts.isNotEmpty) {
      final byKey = counts.entries.map((e) {
        final key = types[e.key]?.key ?? '0x${e.key.toRadixString(16)}';
        return '$key=${e.value}';
      }).toList()
        ..sort();
      debugPrint('[HS-Sync] stored samples by type: ${byKey.join("  ")}');
    }

    // The third possibility, and the one that bit us: downloaded, decodable, and
    // then *correctly* excluded because the firmware fabricated it. A bench board
    // running CONFIG_HPI_HS_SYNTH generates its whole history this way, so every
    // screen renders empty and looks broken. Say so, loudly.
    final synthetic = await db.syntheticSampleCount(device);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (synthetic > 0) {
      debugPrint('[HS-Sync] ⚠ $synthetic of $total stored samples are SYNTHETIC '
          '(firmware test data). Currently '
          '${includeSynthetic ? "INCLUDED in" : "EXCLUDED from"} trends'
          '${includeSynthetic ? "" : " — enable Settings → Developer → "
              "\"Include synthetic data\" to see them."}');
    }

    return _SessionOutcome(stored: stored, done: done, error: error);
  }
}

/// Result of one connect → drain → disconnect cycle.
class _SessionOutcome {
  const _SessionOutcome({
    this.stored = 0,
    this.done = false,
    this.error,
    this.legacy,
  });

  /// Samples durably stored in this session.
  final int stored;

  /// True when the drain reached `head` (nothing left to fetch).
  final bool done;

  final String? error;

  /// Set when the device predates HPI_HS and the legacy path ran instead.
  final SyncResult? legacy;
}
