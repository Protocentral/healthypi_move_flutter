// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart'
    show HsQuality, HsRecordHeader;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import 'device_manager.dart';

/// What a TYPES key contributes to its trend row. Since HS-2, `hr` carries the
/// per-minute *mean* while `hr_min` / `hr_max` carry the true epoch extremes, so
/// they feed different columns of the same derived row.
enum _Role { value, min, max }

/// Floor [tsUtc] (epoch seconds, UTC) to the start of the **local** hour, and
/// return that instant as epoch seconds — still a true UTC epoch, just aligned
/// to a wall-clock edge.
///
/// Trend rows are keyed by their bucket start and every screen renders that key
/// with `DateTime.fromMillisecondsSinceEpoch` (local). Flooring on the *UTC*
/// hour therefore puts every bucket edge at :30 in a half-hour zone — India,
/// Nepal, parts of Australia — so a reading taken at 10:02 IST files under a
/// bucket that renders as "09:30". That is the beta report this fixes.
///
/// The conversion goes through `DateTime`, so DST is handled by the platform
/// rather than by an offset we captured at some other instant. On a fall-back
/// the repeated local hour maps to one bucket (the two hours merge); that is
/// the intended reading of "the 1 AM bucket".
@visibleForTesting
int localHourStart(int tsUtc) => _localHourStart(tsUtc);

@visibleForTesting
int localDayStart(int tsUtc) => _localDayStart(tsUtc);

@visibleForTesting
int localDayEnd(DateTime dayStart) => _localDayEnd(dayStart);

@visibleForTesting
List<Map<String, dynamic>> foldToLocalDays(
  List<Map<String, dynamic>> hourRows, {
  required String maxKey,
  required String minKey,
  required String avgKey,
  bool withCount = false,
}) =>
    _foldToLocalDays(hourRows,
        maxKey: maxKey, minKey: minKey, avgKey: avgKey, withCount: withCount);

int _localHourStart(int tsUtc) {
  final l = DateTime.fromMillisecondsSinceEpoch(tsUtc * 1000);
  return DateTime(l.year, l.month, l.day, l.hour).millisecondsSinceEpoch ~/ 1000;
}

/// As [_localHourStart], but the start of the local calendar **day**.
///
/// The day rollups used to compute this as `(timestamp / 86400) * 86400`, which
/// is a UTC-day floor: in IST that boundary is 05:30 local, so everything a user
/// recorded between midnight and 05:30 was charted under the *previous* day.
int _localDayStart(int tsUtc) {
  final l = DateTime.fromMillisecondsSinceEpoch(tsUtc * 1000);
  return DateTime(l.year, l.month, l.day).millisecondsSinceEpoch ~/ 1000;
}

/// Exclusive end of the local day that starts at local midnight [dayStart].
/// Not `dayStart + 86400`: a DST day is 23 or 25 hours long.
int _localDayEnd(DateTime dayStart) =>
    DateTime(dayStart.year, dayStart.month, dayStart.day + 1)
            .millisecondsSinceEpoch ~/
        1000;

/// Fold hour-bucket rows into local-day rows, preserving the shape the day
/// rollups have always returned. Done in Dart rather than SQL because the only
/// DST-correct way to floor to a local day is to go through `DateTime` — SQLite's
/// `'localtime'` modifier depends on platform tz data we don't control.
List<Map<String, dynamic>> _foldToLocalDays(
  List<Map<String, dynamic>> hourRows, {
  required String maxKey,
  required String minKey,
  required String avgKey,
  bool withCount = false,
}) {
  final byDay = SplayTreeMap<int, List<Map<String, dynamic>>>();
  for (final r in hourRows) {
    byDay
        .putIfAbsent(_localDayStart(r['timestamp'] as int), () => [])
        .add(r);
  }
  final out = <Map<String, dynamic>>[];
  for (final e in byDay.entries) {
    final avgs =
        e.value.map((r) => r['value_avg'] as num?).whereType<num>().toList();
    // A day with no central value has nothing to plot, and callers cast the
    // aggregates non-nullably. SQL's MIN/MAX/AVG would have handed back a row
    // full of nulls here; dropping it is strictly safer.
    if (avgs.isEmpty) continue;
    final maxs =
        e.value.map((r) => r['value_max'] as num?).whereType<num>().toList();
    final mins =
        e.value.map((r) => r['value_min'] as num?).whereType<num>().toList();
    out.add({
      'day_start': e.key,
      maxKey: maxs.isEmpty
          ? avgs.reduce((a, b) => a > b ? a : b)
          : maxs.reduce((a, b) => a > b ? a : b),
      minKey: mins.isEmpty
          ? avgs.reduce((a, b) => a < b ? a : b)
          : mins.reduce((a, b) => a < b ? a : b),
      avgKey: avgs.reduce((a, b) => a + b) / avgs.length,
      if (withCount) 'data_points': e.value.length,
    });
  }
  return out;
}

/// Accumulator for one (hour, trend_type) while deriving.
class _TrendBin {
  final List<num> values = []; // the central series (means / raw readings)
  final List<num> mins = []; // true extremes, when the device reports them
  final List<num> maxs = [];
  num? latest; // chronologically last value (rows are read ts ASC)
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// `app_metadata` key set by the v8 upgrade when it removed pre-3.0 trend rows.
  /// Its value is how many rows went. Present == "the user has history missing
  /// and has not been told yet"; [acknowledgeLegacyDataCleared] clears it.
  static const String legacyDataClearedKey = 'legacy_data_cleared';

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('healthypi_trends.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    
    return await openDatabase(
      path,
      version: 8, // v8: purge of pre-3.0 (session_id != 0) trend rows
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      // Enable single instance and proper configuration for concurrent access
      singleInstance: true,
      // onConfigure is called before onCreate/onUpgrade/onDowngrade
      onConfigure: (db) async {
        // Enable foreign keys if needed
        // await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE health_trends (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        trend_type TEXT NOT NULL,
        session_id INTEGER NOT NULL,
        device_mac TEXT NOT NULL,
        value_max INTEGER,
        value_min INTEGER,
        value_avg INTEGER,
        value_median INTEGER,
        value_latest INTEGER,
        synced_at INTEGER DEFAULT (strftime('%s', 'now')),
        UNIQUE(timestamp, trend_type, device_mac)
      )
    ''');

    await db.execute('CREATE INDEX idx_timestamp ON health_trends(timestamp)');
    await db.execute('CREATE INDEX idx_trend_type ON health_trends(trend_type)');
    await db.execute('CREATE INDEX idx_device_mac ON health_trends(device_mac)');
    await db.execute('CREATE INDEX idx_composite ON health_trends(trend_type, timestamp, device_mac)');
    
    /* `synced_sessions` is deliberately NOT created. It deduped the pre-3.0 BLE
     * trend-file pull, a path removed from both firmware and app; the v8 upgrade
     * drops it on existing installs. Historical CREATEs are left in _onUpgrade
     * because an upgrading DB really does pass through those versions. */

    // Table to store app metadata (replaces SharedPreferences for health-related metadata)
    await db.execute('''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        value_type TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        description TEXT
      )
    ''');
    
    await db.execute('CREATE INDEX idx_app_metadata_updated ON app_metadata(updated_at)');

    // Research recording sessions table
    await db.execute('''
      CREATE TABLE research_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_mac TEXT NOT NULL,
        session_timestamp INTEGER NOT NULL UNIQUE,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_seconds INTEGER NOT NULL,
        signal_mask INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        total_size_bytes INTEGER,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('CREATE INDEX idx_research_sessions_device ON research_sessions(device_mac)');
    await db.execute('CREATE INDEX idx_research_sessions_timestamp ON research_sessions(session_timestamp)');
    await db.execute('CREATE INDEX idx_research_sessions_status ON research_sessions(status)');

    // Research recording signal files table
    await db.execute('''
      CREATE TABLE research_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_timestamp INTEGER NOT NULL,
        signal_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        sample_count INTEGER NOT NULL,
        sample_rate_hz INTEGER NOT NULL,
        file_size_bytes INTEGER NOT NULL,
        downloaded_at TEXT,
        FOREIGN KEY (session_timestamp) REFERENCES research_sessions(session_timestamp) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_research_files_session ON research_files(session_timestamp)');
    await db.execute('CREATE INDEX idx_research_files_signal ON research_files(signal_type)');

    await _createHealthyStoreTables(db);

    print('DatabaseHelper: Tables created with indexes');
  }

  /// Healthy Store (HPI_HS) raw sample store — the system of record once a Move
  /// running HPI_HS firmware syncs. `health_trends` becomes a derived cache
  /// aggregated from `hs_samples`. Additive; see docs/HEALTH_STORE_SYNC_DESIGN.md
  /// §5 and docs/REDESIGN_PLAN.md. Shared by _createDB (fresh) and _onUpgrade.
  Future<void> _createHealthyStoreTables(Database db) async {
    // Raw samples — the source of truth. `seq` is device-monotonic and doubles
    // as the sync cursor and the dedup key. `value` is fixed-point; the real
    // value is value / hs_types.scale.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hs_samples (
        device   TEXT NOT NULL,
        seq      INTEGER NOT NULL,
        ts_utc   INTEGER NOT NULL,
        type     INTEGER NOT NULL,
        quality  INTEGER NOT NULL,
        value    INTEGER NOT NULL,
        PRIMARY KEY (device, seq)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hs_type_ts ON hs_samples(device, type, ts_utc)');

    // Self-describing registry cached from the TYPES response.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hs_types (
        device  TEXT NOT NULL,
        id      INTEGER NOT NULL,
        key     TEXT,
        unit    TEXT,
        scale   INTEGER,
        class   TEXT,
        derived INTEGER,
        hk      TEXT,
        hc      TEXT,
        PRIMARY KEY (device, id)
      )
    ''');

    // Per-device sync state. `cursor` is the highest seq durably stored — the
    // only value ever fed to an ACK. Never ack `head`; never ack an unpersisted
    // cursor (both are destructive on the device). See docs/HPI_HS_API.md §6.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hs_sync_state (
        device         TEXT PRIMARY KEY,
        cursor         INTEGER,
        head           INTEGER,
        schema         INTEGER,
        last_sync_utc  INTEGER,
        last_record_id INTEGER
      )
    ''');

    // Local index of episodic RECORDS downloads (raw payload lives on disk).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hs_records (
        device         TEXT NOT NULL,
        record_id      INTEGER NOT NULL,
        start_ts       INTEGER NOT NULL,
        signal         INTEGER NOT NULL,
        sample_format  INTEGER,
        channels       INTEGER,
        sample_rate    INTEGER,
        n_samples      INTEGER,
        byte_len       INTEGER,
        crc32          INTEGER,
        flags          INTEGER,
        file_path      TEXT,
        crc_ok         INTEGER,
        acked          INTEGER DEFAULT 0,
        status         TEXT,
        downloaded_at  TEXT,
        PRIMARY KEY (device, record_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_hs_records_device ON hs_records(device, start_ts)');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add synced_sessions table for smart sync
      await db.execute('''
        CREATE TABLE IF NOT EXISTS synced_sessions (
          session_id INTEGER NOT NULL,
          trend_type TEXT NOT NULL,
          record_count INTEGER NOT NULL,
          synced_at INTEGER DEFAULT (strftime('%s', 'now')),
          PRIMARY KEY (session_id, trend_type)
        )
      ''');
      
      await db.execute('CREATE INDEX IF NOT EXISTS idx_synced_trend ON synced_sessions(trend_type)');
      print('DatabaseHelper: Upgraded to version 2 - added synced_sessions table');
    }
    
    if (oldVersion < 3) {
      // Add app_metadata table for app state
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          value_type TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          description TEXT
        )
      ''');
      
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_app_metadata_updated 
        ON app_metadata(updated_at)
      ''');
      
      print('DatabaseHelper: Upgraded to version 3 - added app_metadata table');
    }
    
    if (oldVersion < 4) {
      // Add device_mac column for device-specific data tracking
      await db.execute('ALTER TABLE health_trends ADD COLUMN device_mac TEXT DEFAULT "unknown"');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_device_mac ON health_trends(device_mac)');
      // Drop and recreate composite index to include device_mac
      await db.execute('DROP INDEX IF EXISTS idx_composite');
      await db.execute('CREATE INDEX idx_composite ON health_trends(trend_type, timestamp, device_mac)');
      print('DatabaseHelper: Upgraded to version 4 - added device_mac column');
    }

    if (oldVersion < 5) {
      // Add research recording tables
      await db.execute('''
        CREATE TABLE IF NOT EXISTS research_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_mac TEXT NOT NULL,
          session_timestamp INTEGER NOT NULL UNIQUE,
          start_time TEXT NOT NULL,
          end_time TEXT,
          duration_seconds INTEGER NOT NULL,
          signal_mask INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          total_size_bytes INTEGER,
          sync_status TEXT DEFAULT 'pending',
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_research_sessions_device ON research_sessions(device_mac)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_research_sessions_timestamp ON research_sessions(session_timestamp)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_research_sessions_status ON research_sessions(status)');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS research_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_timestamp INTEGER NOT NULL,
          signal_type TEXT NOT NULL,
          file_path TEXT NOT NULL,
          sample_count INTEGER NOT NULL,
          sample_rate_hz INTEGER NOT NULL,
          file_size_bytes INTEGER NOT NULL,
          downloaded_at TEXT,
          FOREIGN KEY (session_timestamp) REFERENCES research_sessions(session_timestamp) ON DELETE CASCADE
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_research_files_session ON research_files(session_timestamp)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_research_files_signal ON research_files(signal_type)');

      print('DatabaseHelper: Upgraded to version 5 - added research recording tables');
    }

    if (oldVersion < 6) {
      // v6: Healthy Store raw sample store + a derived median column on trends.
      // ADD COLUMN cannot use a non-constant default, so no default is given;
      // existing rows get NULL median (legacy sync never computed one).
      await db.execute('ALTER TABLE health_trends ADD COLUMN value_median INTEGER');
      await _createHealthyStoreTables(db);
    }

    if (oldVersion < 7) {
      // v7: local index for HPI_HS RECORDS downloads. _createHealthyStoreTables is
      // IF NOT EXISTS-safe for the v6 tables already present on upgrade from 6.
      await _createHealthyStoreTables(db);
      print('DatabaseHelper: Upgraded to version 7 - hs_records index');
    }

    if (oldVersion < 8) {
      // v8: drop everything the pre-3.0 sync path left behind.
      //
      // `session_id != 0` marks a row pulled by the legacy BLE trend-file path
      // (0x50/0x54 + /lfs/tr*). That path was removed from both firmware and app
      // — insertBulkTrendData, the only writer, now has no callers — so these
      // rows are frozen forever, and rebuildAllTrends deliberately spares them
      // (it deletes only session_id = 0). They would sit next to Healthy Store
      // data indefinitely.
      //
      // They also cannot be trusted next to it. Pre-3.0 firmware had no SET_TZ
      // and stored wall-clock time, so these timestamps carry an unknown, no
      // longer discoverable UTC offset — the user may have travelled. Charting
      // them beside correctly bucketed HS rows means two differently-offset
      // series on one axis. Deleting is the honest option; there is nothing to
      // migrate them *to*.
      final legacyRows = await db.delete('health_trends',
          where: 'session_id != 0');
      await db.execute('DROP TABLE IF EXISTS synced_sessions');

      // Remembered so the UI can explain the gap ONCE, rather than letting a
      // user watch months of history disappear with no account of why.
      if (legacyRows > 0) {
        await db.insert(
          'app_metadata',
          {
            'key': legacyDataClearedKey,
            'value': '$legacyRows',
            'value_type': 'int',
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'description': 'Pre-3.0 trend rows removed by the v8 migration',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      print('DatabaseHelper: Upgraded to version 8 - '
          'removed $legacyRows pre-3.0 trend row(s)');
    }

    // Migrate lastSynced from SharedPreferences to database (moved outside version check)
    if (oldVersion < 3) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastSynced = prefs.getString('lastSynced');
        if (lastSynced != null && lastSynced != '0' && lastSynced.isNotEmpty) {
          await db.insert('app_metadata', {
            'key': 'last_sync_time',
            'value': lastSynced,
            'value_type': 'timestamp',
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'description': 'Last successful sync timestamp',
          });
          print('DatabaseHelper: Migrated lastSynced from SharedPreferences');
        }
      } catch (e) {
        print('DatabaseHelper: Failed to migrate lastSynced: $e');
      }
    }
  }

  /// Get trends for a specific day
  Future<List<Map<String, dynamic>>> getTrendsForDay(
    String trendType,
    DateTime day,
  ) async {
    final db = await database;
    // `timestamp` is a UTC epoch second (aligned to a local hour edge), and
    // `DateTime(y, m, d).millisecondsSinceEpoch` is local midnight expressed as
    // a UTC epoch — so these compare directly. Do not "fix" this to .toUtc().
    final midnight = DateTime(day.year, day.month, day.day);
    int dayStart = midnight.millisecondsSinceEpoch ~/ 1000;
    int dayEnd = _localDayEnd(midnight);

    return await db.query(
      'health_trends',
      where: 'trend_type = ? AND timestamp >= ? AND timestamp < ?',
      whereArgs: [trendType, dayStart, dayEnd],
      orderBy: 'timestamp ASC',
    );
  }

  /// Get hourly aggregated trends
  Future<List<Map<String, dynamic>>> getHourlyTrends(
    String trendType,
    DateTime day, {
    String? deviceMac,
  }) async {
    final db = await database;
    // If no device specified, get current paired device
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    
    // `timestamp` is a UTC epoch second already floored to a LOCAL hour edge by
    // deriveTrends. So local midnight is itself a bucket start and the range is
    // exactly the day's 24 buckets.
    final midnight = DateTime(day.year, day.month, day.day); // local midnight
    int dayStart = midnight.millisecondsSinceEpoch ~/ 1000;
    int dayEnd = _localDayEnd(midnight);

    return await db.rawQuery('''
      SELECT
        timestamp as hour_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value,
        COUNT(*) as data_points
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      GROUP BY hour_start
      ORDER BY hour_start ASC
    ''', [trendType, dayStart, dayEnd, effectiveMac]);
  }

  /// Hourly buckets over a rolling window ending now, rather than a calendar day.
  ///
  /// The home cards use this: a strict "today" query goes blank at 00:05, and on
  /// a device whose history stops before midnight it shows nothing at all even
  /// though there's plenty of recent data. Returns oldest-first.
  Future<List<Map<String, dynamic>>> getRecentHourlyTrends(
    String trendType, {
    int hours = 24,
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    final from = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - hours * 3600;
    return await db.rawQuery('''
      SELECT
        timestamp as hour_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value,
        COUNT(*) as data_points
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND device_mac = ?
      GROUP BY hour_start
      ORDER BY hour_start ASC
    ''', [trendType, from, effectiveMac]);
  }

  /// The most recent hourly bucket for [trendType] within [withinDays], or null.
  /// Lets a card show "last reading, 6 h ago" instead of nothing when the newest
  /// data predates today.
  Future<Map<String, dynamic>?> getLatestHourlyTrend(
    String trendType, {
    int withinDays = 7,
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    final from =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - withinDays * 86400;
    final rows = await db.rawQuery('''
      SELECT
        timestamp as hour_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND device_mac = ?
      GROUP BY hour_start
      ORDER BY hour_start DESC
      LIMIT 1
    ''', [trendType, from, effectiveMac]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Get weekly aggregated trends
  Future<List<Map<String, dynamic>>> getWeeklyTrends(
    String trendType,
    DateTime startDate, {
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    
    // Local calendar week. Day grouping happens in Dart — see [_foldToLocalDays]
    // — because the old `(timestamp / 86400) * 86400` floored to the *UTC* day,
    // which in IST cuts the day at 05:30 local and files a user's small hours
    // under the previous day.
    final weekStartDt =
        DateTime(startDate.year, startDate.month, startDate.day);
    int weekStart = weekStartDt.millisecondsSinceEpoch ~/ 1000;
    int weekEnd = DateTime(weekStartDt.year, weekStartDt.month,
                weekStartDt.day + 7)
            .millisecondsSinceEpoch ~/
        1000;

    final hourRows = await db.rawQuery('''
      SELECT timestamp, value_max, value_min, value_avg
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      ORDER BY timestamp ASC
    ''', [trendType, weekStart, weekEnd, effectiveMac]);

    return _foldToLocalDays(hourRows,
        maxKey: 'max_value',
        minKey: 'min_value',
        avgKey: 'avg_value',
        withCount: true);
  }

  /// Get monthly aggregated trends
  Future<List<Map<String, dynamic>>> getMonthlyTrends(
    String trendType,
    int year,
    int month, {
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    
    // Local calendar month; days folded in Dart (see [_foldToLocalDays]).
    int monthStart = DateTime(year, month, 1)
        .millisecondsSinceEpoch ~/ 1000;
    int monthEnd = DateTime(year, month + 1, 1)
        .millisecondsSinceEpoch ~/ 1000;

    final hourRows = await db.rawQuery('''
      SELECT timestamp, value_max, value_min, value_avg
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      ORDER BY timestamp ASC
    ''', [trendType, monthStart, monthEnd, effectiveMac]);

    return _foldToLocalDays(hourRows,
        maxKey: 'max_value',
        minKey: 'min_value',
        avgKey: 'avg_value',
        withCount: true);
  }

  /// Daily average values for [trendType] over the last [days] days, oldest
  /// first, for computing rolling baselines/percentiles on the phone. Each entry
  /// is `{day_start, avg, min, max}` in stored units. Empty if no data.
  Future<List<Map<String, dynamic>>> getDailyAveragesSince(
    String trendType, {
    int days = 30,
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    final sinceTs = DateTime.now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch ~/
        1000;
    final hourRows = await db.rawQuery('''
      SELECT timestamp, value_max, value_min, value_avg
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND device_mac = ?
      ORDER BY timestamp ASC
    ''', [trendType, sinceTs, effectiveMac]);

    // Days folded in Dart (see [_foldToLocalDays]) — this feeds the 30-day
    // baseline and the Month / 6-Month tabs, so a UTC-day floor here shifted
    // every point on those charts for any user east or west of UTC.
    return _foldToLocalDays(hourRows,
        maxKey: 'max', minKey: 'min', avgKey: 'avg');
  }

  /// Clean up old data (older than specified retention days)
  Future<int> cleanupOldData({int retentionDays = 30}) async {
    final db = await database;
    // `timestamp` is a UTC epoch, and so is `millisecondsSinceEpoch` — a plain
    // "now minus N days" cutoff is correct in any timezone.
    int cutoffTime = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch ~/ 1000;
    
    int deleted = await db.delete(
      'health_trends',
      where: 'timestamp < ?',
      whereArgs: [cutoffTime],
    );
    
    if (deleted > 0) {
      await db.execute('VACUUM');
      print('DatabaseHelper: Deleted $deleted old records, database vacuumed');
    }
    
    return deleted;
  }

  /// Get database stats
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT 
        trend_type,
        COUNT(*) as count,
        MIN(timestamp) as oldest,
        MAX(timestamp) as newest
      FROM health_trends
      GROUP BY trend_type
    ''');
    
    Map<String, dynamic> stats = {};
    for (var row in result) {
      String type = row['trend_type'] as String;
      stats['${type}_count'] = row['count'];
      stats['${type}_oldest'] = row['oldest'];
      stats['${type}_newest'] = row['newest'];
    }
    
    // Get total count
    final total = await db.rawQuery('SELECT COUNT(*) as total FROM health_trends');
    if (total.isNotEmpty) {
      stats['total_count'] = total.first['total'];
    }
    
    return stats;
  }


  // ============================================================================
  // App Metadata Methods (replaces SharedPreferences for health-related data)
  // ============================================================================

  /// How many pre-3.0 trend rows the v8 upgrade removed, or null if there is
  /// nothing to tell the user (fresh install, no legacy data, or already
  /// acknowledged).
  ///
  /// Exists so the gap gets explained exactly once. A user who watched months of
  /// charts vanish after an update, with no message, reasonably files a bug —
  /// and the answer ("that data was recorded in a format with no recoverable
  /// timezone") is not something they can work out themselves.
  Future<int?> pendingLegacyDataClearedNotice() async =>
      getMetadata<int>(legacyDataClearedKey);

  /// Mark the legacy-cleared notice as shown, so it does not reappear.
  Future<void> acknowledgeLegacyDataCleared() async {
    final db = await database;
    await db.delete('app_metadata',
        where: 'key = ?', whereArgs: [legacyDataClearedKey]);
  }

  /// Set metadata value (generic)
  Future<void> setMetadata(String key, dynamic value, {String? description}) async {
    final db = await database;
    
    String valueType;
    String valueString;
    
    if (value is int) {
      valueType = 'int';
      valueString = value.toString();
    } else if (value is bool) {
      valueType = 'bool';
      valueString = value.toString();
    } else if (value is DateTime) {
      valueType = 'timestamp';
      valueString = value.toIso8601String();
    } else {
      valueType = 'string';
      valueString = value.toString();
    }
    
    await db.insert(
      'app_metadata',
      {
        'key': key,
        'value': valueString,
        'value_type': valueType,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'description': description,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get metadata value (generic)
  Future<T?> getMetadata<T>(String key) async {
    final db = await database;
    final result = await db.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    
    if (result.isEmpty) return null;
    
    final value = result.first['value'] as String;
    final type = result.first['value_type'] as String;
    
    try {
      switch (type) {
        case 'int':
          return int.parse(value) as T;
        case 'bool':
          return (value == 'true') as T;
        case 'timestamp':
          return DateTime.parse(value) as T;
        default:
          return value as T;
      }
    } catch (e) {
      print('DatabaseHelper: Error parsing metadata $key: $e');
      return null;
    }
  }

  /// Update last sync timestamp
  Future<void> updateLastSyncTime() async {
    await setMetadata(
      'last_sync_time',
      DateTime.now(),
      description: 'Last successful sync timestamp',
    );
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    return await getMetadata<DateTime>('last_sync_time');
  }

  /// Query latest vitals directly from health_trends table
  /// Returns map with values for each metric:
  /// - HR, Temp, SpO2: Latest/most recent value (last reading)
  /// - Activity: Today's cumulative total (sum of hourly maximums)
  Future<Map<String, Map<String, dynamic>?>> getLatestVitals() async {
    final db = await database;
    final effectiveMac = await _getCurrentDeviceMac();

    // Today's local range. `timestamp` is a UTC epoch already aligned to a local
    // hour edge, so local midnight is itself a bucket start.
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayStartTimestamp = todayStart.millisecondsSinceEpoch ~/ 1000;
    final todayEndTimestamp = _localDayEnd(todayStart);

    final results = await Future.wait([
      // HR: Latest/most recent value
      db.rawQuery('''
        SELECT value_avg as value, timestamp
        FROM health_trends
        WHERE trend_type = ? AND device_mac = ?
        ORDER BY timestamp DESC
        LIMIT 1
      ''', ['hr', effectiveMac]),

      // Temp: Latest/most recent value
      db.rawQuery('''
        SELECT value_avg as value, timestamp
        FROM health_trends
        WHERE trend_type = ? AND device_mac = ?
        ORDER BY timestamp DESC
        LIMIT 1
      ''', ['temp', effectiveMac]),

      // SpO2: Latest/most recent value
      db.rawQuery('''
        SELECT value_avg as value, timestamp
        FROM health_trends
        WHERE trend_type = ? AND device_mac = ?
        ORDER BY timestamp DESC
        LIMIT 1
      ''', ['spo2', effectiveMac]),
      
      // For activity: sum the MAX(value_max) per hour for today (matches trends screen logic)
      // This uses the same aggregation as getHourlyTrends: MAX(value_max) per hour, then SUM
      // With proper UTC time sync, timestamps accurately reflect recording time
      db.rawQuery('''
        SELECT SUM(hourly_max) as value, MAX(hour_start) as timestamp
        FROM (
          SELECT
            timestamp as hour_start,
            MAX(value_max) as hourly_max
          FROM health_trends
          WHERE trend_type = ?
          AND timestamp >= ?
          AND timestamp < ?
          AND device_mac = ?
          GROUP BY hour_start
        )
      ''', ['activity', todayStartTimestamp, todayEndTimestamp, effectiveMac]),
    ]);

    return {
      'hr': results[0].isNotEmpty && results[0][0]['value'] != null ? {
        'value': results[0][0]['value'] as int,
        'timestamp': results[0][0]['timestamp'] as int,
      } : null,
      'temp': results[1].isNotEmpty && results[1][0]['value'] != null ? {
        'value': results[1][0]['value'] as int,
        'timestamp': results[1][0]['timestamp'] as int,
      } : null,
      'spo2': results[2].isNotEmpty && results[2][0]['value'] != null ? {
        'value': results[2][0]['value'] as int,
        'timestamp': results[2][0]['timestamp'] as int,
      } : null,
      // Activity: Always return a value (0 if no data for today)
      // This matches health app behavior where 0 steps = valid state
      'activity': {
        'value': results[3].isNotEmpty && results[3][0]['value'] != null
            ? results[3][0]['value'] as int
            : 0,  // Default to 0 steps if no data for today
        'timestamp': results[3].isNotEmpty && results[3][0]['timestamp'] != null
            ? results[3][0]['timestamp'] as int
            : todayStartTimestamp,  // Use today's start as timestamp
      },
    };
  }

  // ============================================================================
  // Research Recording Methods
  // ============================================================================

  /// Insert or update a research recording session
  Future<int> insertResearchSession({
    required String deviceMac,
    required int sessionTimestamp,
    required DateTime startTime,
    DateTime? endTime,
    required int durationSeconds,
    required int signalMask,
    String status = 'complete',
    int? totalSizeBytes,
    String syncStatus = 'pending',
  }) async {
    final db = await database;
    return await db.insert(
      'research_sessions',
      {
        'device_mac': deviceMac,
        'session_timestamp': sessionTimestamp,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'signal_mask': signalMask,
        'status': status,
        'total_size_bytes': totalSizeBytes,
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all research sessions for a device
  Future<List<Map<String, dynamic>>> getResearchSessions({String? deviceMac}) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();

    return await db.query(
      'research_sessions',
      where: 'device_mac = ?',
      whereArgs: [effectiveMac],
      orderBy: 'session_timestamp DESC',
    );
  }

  /// Get a specific research session by timestamp
  Future<Map<String, dynamic>?> getResearchSession(int sessionTimestamp) async {
    final db = await database;
    final result = await db.query(
      'research_sessions',
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Update research session status
  Future<int> updateResearchSessionStatus(int sessionTimestamp, String status) async {
    final db = await database;
    return await db.update(
      'research_sessions',
      {'status': status},
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
    );
  }

  /// Update research session sync status
  Future<int> updateResearchSessionSyncStatus(int sessionTimestamp, String syncStatus) async {
    final db = await database;
    return await db.update(
      'research_sessions',
      {'sync_status': syncStatus},
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
    );
  }

  /// Delete a research session and its files
  Future<int> deleteResearchSession(int sessionTimestamp) async {
    final db = await database;
    // Files are deleted via CASCADE
    return await db.delete(
      'research_sessions',
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
    );
  }

  /// Delete all research sessions for a device
  Future<int> deleteAllResearchSessions({String? deviceMac}) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    return await db.delete(
      'research_sessions',
      where: 'device_mac = ?',
      whereArgs: [effectiveMac],
    );
  }

  /// Insert a research file record
  Future<int> insertResearchFile({
    required int sessionTimestamp,
    required String signalType,
    required String filePath,
    required int sampleCount,
    required int sampleRateHz,
    required int fileSizeBytes,
  }) async {
    final db = await database;
    return await db.insert(
      'research_files',
      {
        'session_timestamp': sessionTimestamp,
        'signal_type': signalType,
        'file_path': filePath,
        'sample_count': sampleCount,
        'sample_rate_hz': sampleRateHz,
        'file_size_bytes': fileSizeBytes,
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all files for a research session
  Future<List<Map<String, dynamic>>> getResearchFiles(int sessionTimestamp) async {
    final db = await database;
    return await db.query(
      'research_files',
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
      orderBy: 'signal_type ASC',
    );
  }

  /// Check if a research session has been downloaded
  Future<bool> isResearchSessionDownloaded(int sessionTimestamp) async {
    final db = await database;
    final result = await db.query(
      'research_files',
      where: 'session_timestamp = ?',
      whereArgs: [sessionTimestamp],
    );
    return result.isNotEmpty;
  }

  /// Get research session statistics
  Future<Map<String, dynamic>> getResearchSessionStats({String? deviceMac}) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as session_count,
        SUM(duration_seconds) as total_duration,
        SUM(total_size_bytes) as total_size,
        MIN(session_timestamp) as oldest,
        MAX(session_timestamp) as newest
      FROM research_sessions
      WHERE device_mac = ?
    ''', [effectiveMac]);

    if (result.isEmpty) {
      return {
        'session_count': 0,
        'total_duration': 0,
        'total_size': 0,
      };
    }

    return result.first;
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /// Get current paired device MAC address (for filtering queries)
  Future<String> _getCurrentDeviceMac() async {
    final deviceInfo = await DeviceManager.getPairedDevice();
    return deviceInfo?.macAddress ?? 'unknown';
  }

  /// Check if a device has any synced data
  Future<bool> hasDataForDevice(String deviceMac) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM health_trends WHERE device_mac = ?',
      [deviceMac],
    );
    final count = result.first['count'] as int;
    return count > 0;
  }

  /// Get record count for a specific device
  Future<int> getRecordCountForDevice(String deviceMac) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM health_trends WHERE device_mac = ?',
      [deviceMac],
    );
    return result.first['count'] as int;
  }

  /// Get all unique device MACs in the database
  Future<List<String>> getAllDeviceMacs() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT device_mac FROM health_trends WHERE device_mac != "unknown" ORDER BY device_mac',
    );
    return result.map((row) => row['device_mac'] as String).toList();
  }

  /// Delete all data for a specific device
  Future<int> deleteDataForDevice(String deviceMac) async {
    final db = await database;
    
    // Delete from health_trends
    final trendsDeleted = await db.delete(
      'health_trends',
      where: 'device_mac = ?',
      whereArgs: [deviceMac],
    );
    
    print('DatabaseHelper: Deleted $trendsDeleted records for device $deviceMac');
    return trendsDeleted;
  }

  // ---------------------------------------------------------------------------
  // Healthy Store (HPI_HS) raw sample store — see docs/HEALTH_STORE_SYNC_DESIGN.md
  // §5. `health_trends` remains a derived cache aggregated from `hs_samples`.
  // These are the seams the (not-yet-wired) HealthyStoreSyncManager writes to and
  // HealthRepository reads from; safe to call today, they simply stay empty until
  // a Move running HPI_HS firmware syncs.
  // ---------------------------------------------------------------------------

  /// Highest `seq` durably stored for [device], or -1 if none. This is the value
  /// to resume `sync(since:)` from — and the only value safe to ACK.
  Future<int> getSyncCursor(String device) async {
    final db = await database;
    final rows = await db.query('hs_sync_state',
        columns: ['cursor'], where: 'device = ?', whereArgs: [device], limit: 1);
    if (rows.isEmpty || rows.first['cursor'] == null) return -1;
    return rows.first['cursor'] as int;
  }

  /// Insert a page of raw samples and advance the persisted cursor atomically.
  /// Returns the new cursor (max seq stored). Idempotent: re-inserting the same
  /// seqs is a no-op via the (device, seq) primary key, so a re-run after an
  /// interrupted sync cannot double-count. The caller must only ACK the returned
  /// cursor *after* this future completes.
  /// [advanceCursor] false stores the rows **without** moving the persisted sync
  /// cursor. That's for an out-of-order "newest first" pass: we want today's
  /// samples on the phone immediately, but the cursor must stay behind so the
  /// older backlog is still drained. (Re-fetching those seqs later is a no-op
  /// thanks to the primary key.)
  Future<int> insertSamplesPage(
    String device,
    List<Map<String, Object?>> samples, {
    int? head,
    int? schema,
    bool advanceCursor = true,
  }) async {
    final db = await database;
    final persisted = await getSyncCursor(device);
    int maxSeq = persisted;
    await db.transaction((txn) async {
      for (final s in samples) {
        final seq = s['seq'] as int;
        await txn.insert(
          'hs_samples',
          {
            'device': device,
            'seq': seq,
            'ts_utc': s['ts_utc'],
            'type': s['type'],
            'quality': s['quality'] ?? 0,
            'value': s['value'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (seq > maxSeq) maxSeq = seq;
      }
      if (!advanceCursor) return;
      final nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      // Preserve last_record_id — REPLACE would otherwise null it out.
      final prev = await txn.query('hs_sync_state',
          columns: ['last_record_id'],
          where: 'device = ?',
          whereArgs: [device],
          limit: 1);
      final lastRecordId =
          prev.isEmpty ? null : prev.first['last_record_id'] as int?;
      await txn.insert(
        'hs_sync_state',
        {
          'device': device,
          'cursor': maxSeq,
          'head': head,
          'schema': schema,
          'last_sync_utc': nowUtc,
          if (lastRecordId != null) 'last_record_id': lastRecordId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return advanceCursor ? maxSeq : persisted;
  }

  /// The whole `hs_sync_state` row for [device] (cursor, head, schema,
  /// last_sync_utc, last_record_id), or null if the device has never synced.
  ///
  /// For the developer screen: these numbers decide every sync's behaviour and
  /// until now existed only in `debugPrint` output.
  Future<Map<String, Object?>?> getSyncState(String device) async {
    final db = await database;
    final rows = await db.query('hs_sync_state',
        where: 'device = ?', whereArgs: [device], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Highest RECORDS id listed for [device], or -1 if none.
  Future<int> getLastRecordId(String device) async {
    final db = await database;
    final rows = await db.query('hs_sync_state',
        columns: ['last_record_id'],
        where: 'device = ?',
        whereArgs: [device],
        limit: 1);
    if (rows.isEmpty || rows.first['last_record_id'] == null) return -1;
    return rows.first['last_record_id'] as int;
  }

  /// Persist the RECORDS list cursor without clobbering the sample-tier cursor.
  Future<void> setLastRecordId(String device, int recordId) async {
    final db = await database;
    final existing = await db.query('hs_sync_state',
        where: 'device = ?', whereArgs: [device], limit: 1);
    if (existing.isEmpty) {
      await db.insert('hs_sync_state', {
        'device': device,
        'cursor': -1,
        'last_record_id': recordId,
      });
      return;
    }
    await db.update(
      'hs_sync_state',
      {'last_record_id': recordId},
      where: 'device = ?',
      whereArgs: [device],
    );
  }

  /// All locally indexed HPI_HS records for [device], keyed by record_id.
  Future<Map<int, Map<String, Object?>>> getHsRecordIndex(String device) async {
    final db = await database;
    final rows = await db.query('hs_records',
        where: 'device = ?', whereArgs: [device]);
    return {
      for (final r in rows) (r['record_id'] as int): Map<String, Object?>.from(r),
    };
  }

  /// Upsert a downloaded RECORDS payload's metadata (file lives on disk).
  Future<void> upsertHsRecord({
    required String device,
    required HsRecordHeader header,
    required String filePath,
    required bool crcOk,
    required bool acked,
    required String status,
  }) async {
    final db = await database;
    await db.insert(
      'hs_records',
      {
        'device': device,
        'record_id': header.id,
        'start_ts': header.startTs,
        'signal': header.signal,
        'sample_format': header.sampleFormat,
        'channels': header.channels,
        'sample_rate': header.sampleRate,
        'n_samples': header.nSamples,
        'byte_len': header.byteLen,
        'crc32': header.crc32,
        'flags': header.flags,
        'file_path': filePath,
        'crc_ok': crcOk ? 1 : 0,
        'acked': acked ? 1 : 0,
        'status': status,
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markHsRecordAcked(String device, int recordId) async {
    final db = await database;
    await db.update(
      'hs_records',
      {'acked': 1},
      where: 'device = ? AND record_id = ?',
      whereArgs: [device, recordId],
    );
  }

  /// Cache the self-describing TYPES registry for [device].
  Future<void> upsertTypes(String device, List<Map<String, Object?>> types) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in types) {
        await txn.insert(
          'hs_types',
          {
            'device': device,
            'id': t['id'],
            'key': t['key'],
            'unit': t['unit'],
            'scale': t['scale'],
            'class': t['class'],
            'derived': t['derived'],
            'hk': t['hk'],
            'hc': t['hc'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Re-key the Healthy Store tables from [oldKey] to [newKey].
  ///
  /// Early builds keyed the raw store on `HELLO.dev`, which turned out to be a
  /// model string (`"healthypi-move"`) that is identical on every watch — two
  /// devices would collide on `(device, seq)`. The store is now keyed on the
  /// per-unit `HELLO.uid`. This moves any rows written under the old key.
  ///
  /// Idempotent, and a no-op when nothing was ever stored under [oldKey].
  /// Conflicts are ignored rather than overwritten: if a row already exists
  /// under [newKey] for a seq, the already-correct row wins.
  Future<void> rekeyHealthyStoreDevice(String oldKey, String newKey) async {
    if (oldKey.isEmpty || newKey.isEmpty || oldKey == newKey) return;
    final db = await database;
    await db.transaction((txn) async {
      final stale = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM hs_samples WHERE device = ?',
            [oldKey],
          )) ??
          0;
      final staleState = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM hs_sync_state WHERE device = ?',
            [oldKey],
          )) ??
          0;
      if (stale == 0 && staleState == 0) return;

      await txn.rawUpdate(
          'UPDATE OR IGNORE hs_samples SET device = ? WHERE device = ?',
          [newKey, oldKey]);
      await txn.rawUpdate(
          'UPDATE OR IGNORE hs_types SET device = ? WHERE device = ?',
          [newKey, oldKey]);
      await txn.rawUpdate(
          'UPDATE OR IGNORE hs_records SET device = ? WHERE device = ?',
          [newKey, oldKey]);
      await txn.rawUpdate(
          'UPDATE OR IGNORE hs_sync_state SET device = ? WHERE device = ?',
          [newKey, oldKey]);
      // Anything that lost the UPDATE race to an existing row is a duplicate.
      await txn.delete('hs_samples', where: 'device = ?', whereArgs: [oldKey]);
      await txn.delete('hs_types', where: 'device = ?', whereArgs: [oldKey]);
      await txn.delete('hs_records', where: 'device = ?', whereArgs: [oldKey]);
      await txn
          .delete('hs_sync_state', where: 'device = ?', whereArgs: [oldKey]);
    });
  }

  /// Raw sample counts per type id for [device], newest-first-agnostic.
  ///
  /// Diagnostic: this is what actually landed on the phone, before any
  /// derivation. If a metric is missing from the UI, this says whether it was
  /// never downloaded, or downloaded and then dropped during derivation (e.g. an
  /// unknown type id, or the SYNTHETIC filter).
  Future<Map<int, int>> sampleCountsByType(String device) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT type, COUNT(*) AS n FROM hs_samples WHERE device = ? GROUP BY type',
      [device],
    );
    return {for (final r in rows) r['type'] as int: r['n'] as int};
  }

  /// Recent blood-pressure spot readings (an `HsClass.event` metric — sparse,
  /// never averaged). BP arrives as two separate event types, systolic and
  /// diastolic, that share a timestamp; this resolves their type ids from the
  /// registry, pulls recent samples, and pairs sys+dia by `ts_utc`.
  ///
  /// Type keys are matched **tolerantly** — firmware may name them `bp_sys`/
  /// `bp_dia`, `sys`/`dia`, etc. If the registry has no BP types, returns empty
  /// (the screen then shows its not-calibrated / no-data state — it never
  /// invents a value). Returns newest-first maps `{ts, sys, dia, quality}` with
  /// values already divided by each type's scale.
  Future<List<Map<String, Object?>>> getBpReadings(String device,
      {int limit = 90}) async {
    final db = await database;
    final types =
        await db.query('hs_types', where: 'device = ?', whereArgs: [device]);

    int? sysId, diaId;
    double sysScale = 1, diaScale = 1;
    double scaleOf(Object? s) {
      final v = (s as num?)?.toDouble() ?? 1;
      return v == 0 ? 1 : v;
    }

    for (final t in types) {
      final key = (t['key'] as String?)?.toLowerCase() ?? '';
      final id = (t['id'] as num?)?.toInt();
      if (id == null || !key.contains('bp')) continue;
      if (key.contains('sys')) {
        sysId = id;
        sysScale = scaleOf(t['scale']);
      } else if (key.contains('dia')) {
        diaId = id;
        diaScale = scaleOf(t['scale']);
      }
    }
    if (sysId == null || diaId == null) return const [];

    final rows = await db.rawQuery(
      'SELECT ts_utc, type, quality, value FROM hs_samples '
      'WHERE device = ? AND type IN (?, ?) ORDER BY ts_utc DESC LIMIT ?',
      [device, sysId, diaId, limit * 2],
    );

    // Pair sys+dia by shared timestamp (the watch stamps both at measurement).
    final byTs = <int, Map<String, Object?>>{};
    for (final r in rows) {
      final ts = (r['ts_utc'] as num).toInt();
      final type = (r['type'] as num).toInt();
      final value = (r['value'] as num).toDouble();
      final m = byTs.putIfAbsent(ts, () => {'ts': ts, 'quality': r['quality']});
      if (type == sysId) m['sys'] = value / sysScale;
      if (type == diaId) m['dia'] = value / diaScale;
    }
    final paired = byTs.values
        .where((m) => m['sys'] != null && m['dia'] != null)
        .toList()
      ..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    return paired.take(limit).toList();
  }

  /// The Healthy Store device key (HELLO.uid) we hold samples for, or null when
  /// nothing has synced. Used by tools that need to act on "the" store without
  /// a live connection to ask HELLO.
  Future<String?> getHealthyStoreDeviceKey() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT device, COUNT(*) AS n FROM hs_samples '
        'GROUP BY device ORDER BY n DESC LIMIT 1');
    if (rows.isEmpty) return null;
    return rows.first['device'] as String?;
  }

  /// Oldest `ts_utc` we hold for [device], or null when the store is empty.
  Future<int?> earliestSampleTs(String device) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT MIN(ts_utc) AS t FROM hs_samples WHERE device = ?',
      [device],
    );
    return rows.first['t'] as int?;
  }

  /// Re-derive `health_trends` from **every** stored sample.
  ///
  /// Needed when the type registry grows: `deriveTrends` skips samples whose type
  /// id it doesn't know, and it normally only runs over the window just synced.
  /// So a sample that arrived while its type was missing from `hs_types` stays
  /// invisible forever, even though the raw data is on the phone. This replays
  /// the lot. No network — it reads only what's already stored.
  Future<int> rebuildAllTrends(
    String device, {
    String? deviceMac,
    bool includeSynthetic = false,
  }) async {
    final earliest = await earliestSampleTs(device);
    if (earliest == null) return 0;
    // Rebuilding replaces rows for the hours it touches, but rows derived under
    // the *other* synthetic setting would linger for hours it no longer covers.
    // Clear the derived cache first so it always reflects the current setting.
    final db = await database;
    await db.delete('health_trends',
        where: 'session_id = 0'); // derived rows only; legacy sync rows have real ids
    return deriveTrends(device,
        sinceUtc: earliest,
        deviceMac: deviceMac,
        includeSynthetic: includeSynthetic);
  }

  /// How many stored samples are firmware-fabricated (quality bit 1<<6).
  /// A bench device running CONFIG_HPI_HS_SYNTH generates its entire history this
  /// way, so this is the difference between "no data" and "all data is synthetic".
  Future<int> syntheticSampleCount(String device) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM hs_samples WHERE device = ? AND (quality & ?) != 0',
          [device, HsQuality.synthetic],
        )) ??
        0;
  }

  /// Cache the raw HPI_HS `SUMMARY` map for [device].
  ///
  /// Stored whole and untyped, exactly as the device sent it. SUMMARY is the one
  /// thing the phone cannot recompute — it carries the device's own rolling
  /// baselines (7-day RMSSD, skin-temp nights) and, since firmware P3, the
  /// HRV-derived stress score. Keys are additive and not fully pinned, so
  /// freezing a schema over them would just guarantee a migration later.
  Future<void> setHsSummary(String device, Map<String, Object?> summary) =>
      setMetadata('hs_summary_$device', jsonEncode(summary),
          description: 'Last HPI_HS SUMMARY response');

  /// The last cached `SUMMARY` for [device], or null if none has been read yet.
  Future<Map<String, Object?>?> getHsSummary(String device) async {
    final raw = await getMetadata<String>('hs_summary_$device');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null; // corrupt cache is not worth crashing a dashboard over
    }
  }

  /// The cached `SUMMARY` of the most recently synced device.
  ///
  /// Read-side callers (the dashboard) key off the platform BLE id, not the
  /// HELLO `uid` that the Healthy Store tables are keyed on, and they have no way
  /// to resolve one to the other without a live connection. Since the app pairs
  /// one watch at a time, "the device we synced last" is that device.
  Future<Map<String, Object?>?> latestHsSummary() async {
    final db = await database;
    final rows = await db.query('hs_sync_state',
        columns: ['device'], orderBy: 'last_sync_utc DESC', limit: 1);
    if (rows.isEmpty) return null;
    return getHsSummary(rows.first['device'] as String);
  }

  /// How many samples we already hold for [device] with `seq > [seq]`.
  /// Used to skip a redundant newest-first fetch when that window is already on
  /// the phone.
  Future<int> countSamplesAbove(String device, int seq) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM hs_samples WHERE device = ? AND seq > ?',
          [device, seq],
        )) ??
        0;
  }

  /// TYPES registry for [device], keyed by type id.
  Future<Map<int, Map<String, Object?>>> getTypes(String device) async {
    final db = await database;
    final rows =
        await db.query('hs_types', where: 'device = ?', whereArgs: [device]);
    return {for (final r in rows) r['id'] as int: r};
  }

  /// Derive `health_trends` hourly rows from `hs_samples` for the given UTC time
  /// window, so the existing TrendsDataManager / trend screens keep working. One
  /// derived row per (type-key, hour): min/avg/**median**/max, plus latest.
  ///
  /// Fixed-point: values are divided by each type's `scale` and then converted
  /// into `health_trends`' existing per-metric integer convention (e.g. skin
  /// temp is stored in centi-degrees — DECISIONS §3). Runs incrementally over
  /// only the touched hours; safe to re-run (idempotent upsert on the trends
  /// UNIQUE key). Returns the number of derived rows written.
  /// [includeSynthetic] admits firmware-fabricated samples (quality bit 1<<6)
  /// into the derived trends. **Off in production, always.** It exists because a
  /// bench device running `CONFIG_HPI_HS_SYNTH=y` generates its whole history as
  /// synthetic data — so with the filter on (correctly), every screen renders
  /// empty and the pipeline can't be tested at all. Gated behind developer mode,
  /// and the UI must label the data as synthetic wherever it's shown.
  Future<int> deriveTrends(
    String device, {
    required int sinceUtc,
    String? deviceMac,
    bool includeSynthetic = false,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    final types = await getTypes(device);
    if (types.isEmpty) return 0;

    final rows = await db.query('hs_samples',
        where: 'device = ? AND ts_utc >= ?',
        whereArgs: [device, sinceUtc],
        orderBy: 'ts_utc ASC');
    if (rows.isEmpty) return 0;

    // hourStart -> trendType -> bin  (discrete metrics)
    final buckets = <int, Map<String, _TrendBin>>{};

    // trendType -> hourStart -> highest RUNNING TOTAL seen in that hour.
    // Cumulative metrics (steps, energy) carry a running daily total, not an
    // increment, so they are accumulated separately and differenced below.
    final cumulative = <String, SplayTreeMap<int, num>>{};

    // ts_utc -> HRV window coverage %. The firmware emits `hrv_coverage` as its
    // own sample sharing the window's end timestamp with `hrv_rmssd`, so the two
    // are correlated by ts. Collected in a pre-pass because a window's coverage
    // may be read before or after its RMSSD in ts-ASC order.
    final hrvCoverage = <int, num>{};
    for (final r in rows) {
      final t = types[r['type'] as int];
      if ((t?['key'] as String?) != 'hrv_coverage') continue;
      final scale = (t!['scale'] as int?) ?? 1;
      hrvCoverage[r['ts_utc'] as int] =
          (r['value'] as int) / (scale == 0 ? 1 : scale);
    }

    int? memoHour; // see the local-hour bucketing below

    for (final r in rows) {
      // Never derive from fabricated data (HS-2 §2c). It is stored — deliberately
      // — but it must not reach a chart, a summary or an export, or synthetic
      // samples would be silently indistinguishable from measurements.
      // The only exception is an explicit developer opt-in (see [includeSynthetic]).
      final quality = (r['quality'] as int?) ?? 0;
      if (!includeSynthetic && quality & HsQuality.synthetic != 0) continue;

      final t = types[r['type'] as int];
      if (t == null) continue; // unknown id → skip (registry is additive)
      final key = t['key'] as String?;
      final role = _trendRoleFor(key, quality);
      if (role == null) continue;

      // A low-coverage HRV window is a motion artefact, not physiology, and it
      // charts as a perfectly plausible line — so drop it rather than plot it.
      if (key == 'hrv_rmssd') {
        final cov = hrvCoverage[r['ts_utc'] as int];
        if (cov != null && cov < _minHrvCoveragePct) continue;
      }

      final scale = (t['scale'] as int?) ?? 1;
      final stored = _toStoredUnits(
          role.trend, (r['value'] as int) / (scale == 0 ? 1 : scale));

      // Bucket on the LOCAL hour — see [_localHourStart]. Epoch records
      // timestamp the END of their window, so the bucket is the hour the window
      // closed in; good enough at 1-minute epochs.
      //
      // Rows arrive ts ASC, so a one-entry memo skips the DateTime work for
      // every sample after the first in each hour.
      //
      // The 3600 s window is exact wherever a DST step lands on an hour
      // boundary, which is everywhere except the handful of zones that shift by
      // 30 minutes (Lord Howe). There, the half hour following a transition is
      // still inside the memo's window and gets filed under the previous
      // bucket — measured at 30 samples, twice a year. Not worth a DateTime
      // call per sample to fix, but it is a mis-bucket and not, as this comment
      // once claimed, a recompute.
      final ts = r['ts_utc'] as int;
      if (memoHour == null || ts < memoHour || ts >= memoHour + 3600) {
        memoHour = _localHourStart(ts);
      }
      final hourStart = memoHour;

      if ((t['class'] as String?) == 'cumulative') {
        final byHour = cumulative.putIfAbsent(role.trend, () => SplayTreeMap());
        final prev = byHour[hourStart];
        if (prev == null || stored > prev) byHour[hourStart] = stored;
        continue;
      }

      final bin = (buckets[hourStart] ??= {})
          .putIfAbsent(role.trend, () => _TrendBin());
      switch (role.role) {
        case _Role.value:
          bin.values.add(stored);
          bin.latest = stored; // rows are ts ASC, so the last write wins
        case _Role.min:
          bin.mins.add(stored);
        case _Role.max:
          bin.maxs.add(stored);
      }
    }

    // Cumulative → per-hour increments.
    //
    // `steps` is a running daily total, but the read path computes a day's total
    // as SUM(MAX(value_max) per hour) — i.e. it expects each hour to hold that
    // hour's *increment*. Storing the running total would sum running totals and
    // wildly over-count. So difference consecutive hours here; the hourly bar
    // chart then also shows steps-per-hour, which is what it should show.
    cumulative.forEach((trendType, byHour) {
      num? prev;
      byHour.forEach((hourStart, total) {
        // A drop means the counter reset (steps zero at local midnight), so the
        // new running total *is* the increment.
        final delta = (prev == null || total < prev!) ? total : total - prev!;
        prev = total;
        if (delta <= 0) return; // nothing gained this hour — don't write a row
        final bin = (buckets[hourStart] ??= {})
            .putIfAbsent(trendType, () => _TrendBin());
        bin.values.add(delta);
        bin.latest = delta;
      });
    });

    int written = 0;
    await db.transaction((txn) async {
      buckets.forEach((hourStart, byType) {
        byType.forEach((trendType, bin) {
          if (bin.values.isEmpty) return; // no central series → nothing to write

          final sorted = [...bin.values]..sort();
          final avgV =
              bin.values.reduce((a, b) => a + b) / bin.values.length;
          final medV = sorted[sorted.length ~/ 2];

          // HS-2: `hr` is now a per-MINUTE MEAN, so a max taken over the hr
          // series is a peak-of-means and systematically under-reports (a 10 s
          // spike to 150 collapses to ~110). The firmware emits the true epoch
          // extremes as separate hr_min / hr_max types — prefer those, and only
          // fall back to the series when they're absent (older firmware).
          final minV = bin.mins.isNotEmpty
              ? bin.mins.reduce((a, b) => a < b ? a : b)
              : sorted.first;
          final maxV = bin.maxs.isNotEmpty
              ? bin.maxs.reduce((a, b) => a > b ? a : b)
              : sorted.last;

          txn.insert(
            'health_trends',
            {
              'timestamp': hourStart,
              'trend_type': trendType,
              'session_id': 0, // derived rows have no device session
              'device_mac': effectiveMac,
              'value_max': maxV.round(),
              'value_min': minV.round(),
              'value_avg': avgV.round(),
              'value_median': medV.round(),
              'value_latest': (bin.latest ?? medV).round(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          written++;
        });
      });
    });
    return written;
  }

  /// Map an HPI_HS TYPES `key` onto a `health_trends.trend_type` and the role it
  /// plays in that trend, or null if the metric has no trend screen (it stays
  /// raw in `hs_samples`).
  ///
  /// The role matters since HS-2: `hr` carries the epoch mean while `hr_min` /
  /// `hr_max` carry the true extremes, and they must feed different columns.
  ///
  /// Keyed on the TYPES **key string**, never on the numeric id. The firmware
  /// handoff's P3 section renumbers several HRV/stress ids relative to its own
  /// as-built registry (it lists SDNN as both 0x50 and 0x52, stress as both
  /// 0x60 and 0x62), so an id-keyed map would silently mis-bind. The registry is
  /// self-describing precisely so we don't have to guess — see design doc §1.
  ///
  /// [quality] is needed because `stress` is two different metrics on one type:
  /// the MANUAL bit distinguishes the EDA spot check from the continuous
  /// HRV-derived score (handoff §6.3).
  ({String trend, _Role role})? _trendRoleFor(String? key, int quality) {
    switch (key) {
      case 'hr':
        return (trend: hPi4Global.PREFIX_HR, role: _Role.value);
      case 'hr_min':
        return (trend: hPi4Global.PREFIX_HR, role: _Role.min);
      case 'hr_max':
        return (trend: hPi4Global.PREFIX_HR, role: _Role.max);
      case 'spo2':
        return (trend: hPi4Global.PREFIX_SPO2, role: _Role.value);
      case 'skin_temp':
      case 'temp':
        return (trend: hPi4Global.PREFIX_TEMP, role: _Role.value);
      case 'steps':
      case 'activity':
        return (trend: hPi4Global.PREFIX_ACTIVITY, role: _Role.value);
      case 'hrv_rmssd':
        // RMSSD, not SDNN: the short-window parasympathetic marker, and what the
        // stress score is built on (handoff §6.4).
        return (trend: hPi4Global.PREFIX_HRV, role: _Role.value);
      case 'stress':
        return (
          trend: quality & HsQuality.manual != 0
              ? hPi4Global.PREFIX_STRESS_EDA // manual 30 s GSR spot check
              : hPi4Global.PREFIX_STRESS, // continuous, HRV-derived
          role: _Role.value,
        );
      default:
        return null;
    }
  }

  /// Below this, a 5-minute HRV window is motion artefact rather than
  /// physiology: its RMSSD still plots as a perfectly plausible line, which is
  /// exactly what makes it dangerous (handoff §6). The firmware already drops
  /// anything under 50%, but we don't depend on that — if `hrv_coverage` is
  /// absent (older firmware) we keep the sample rather than silently discard the
  /// whole series.
  static const int _minHrvCoveragePct = 50;

  /// Convert a real-world value into `health_trends`' stored integer convention.
  /// Temp is stored in centi-degrees (read side divides by 100, see
  /// scr_skin_temp.dart); HR / SpO₂ / steps are stored raw.
  ///
  /// HRV (RMSSD) arrives as ms×10 and is stored as whole **milliseconds** — the
  /// 0.1 ms the rounding drops is far below the measurement's own noise, and
  /// keeping it raw would put a 10× error in every chart that reads it as ms.
  /// Stress is a 0..100 index, stored raw.
  num _toStoredUnits(String trendType, num real) {
    if (trendType == hPi4Global.PREFIX_TEMP) return real * 100;
    return real;
  }

  /// Delete every health record the app holds, in one transaction.
  ///
  /// Wipes the raw Healthy Store (`hs_samples` / `hs_types` / `hs_sync_state`),
  /// the derived `health_trends` cache, the
  /// research-recording index, and the sync metadata.
  ///
  /// **Clearing `hs_sync_state` resets the sync cursor**, which is the whole
  /// point: the next sync re-pulls from the device's oldest retained sample. Use
  /// this when the local store and the device have diverged — e.g. after the
  /// HS-2 firmware discards its on-flash log, or after a derivation bug means
  /// the derived trends can no longer be trusted.
  ///
  /// The pairing is **kept** (that lives in SharedPreferences, not here), so the
  /// watch stays paired and its own data is untouched — this only deletes the
  /// phone's copy. Returns the number of rows removed per table, plus a
  /// `_files` entry counting the downloaded payloads unlinked from disk.
  ///
  /// **Deleting the index is not deleting the data.** Downloaded RECORDS
  /// payloads live on the filesystem, not in SQLite; dropping only the rows left
  /// every `.bin` orphaned under the documents directory with nothing left
  /// pointing at it, so it could never be found or freed again. The files go
  /// first, and the directory sweep also collects orphans left behind by earlier
  /// index-only deletes.
  Future<Map<String, int>> deleteAllHealthData() async {
    final db = await database;

    // Collect payload paths *before* the rows that name them are dropped.
    final indexed = <String>{};
    for (final table in ['hs_records', 'research_files']) {
      try {
        final rows = await db.query(table, columns: ['file_path']);
        for (final r in rows) {
          final p = r['file_path'] as String?;
          if (p != null && p.isNotEmpty) indexed.add(p);
        }
      } catch (e) {
        debugPrint('[DB] could not read $table.file_path: $e');
      }
    }

    const tables = [
      'hs_samples',
      'hs_types',
      'hs_sync_state',
      'hs_records',
      'health_trends',
      'research_files',
      'research_sessions',
      'app_metadata',
    ];
    final removed = <String, int>{};
    await db.transaction((txn) async {
      for (final table in tables) {
        // The table list is a const literal, never user input.
        removed[table] = await txn.delete(table);
      }
    });

    removed['_files'] = await _deleteRecordingFiles(indexed);
    return removed;
  }

  /// Unlink downloaded recording payloads and exported CSVs.
  ///
  /// Deletes [indexed] paths, then sweeps the `HealthyPiRecordings` tree and the
  /// `hs_record_*.csv` exports, which no table indexes. Never throws: a file the
  /// OS refuses to remove must not abort the wipe, since the rows are already
  /// gone by the time this runs.
  Future<int> _deleteRecordingFiles(Set<String> indexed) async {
    var deleted = 0;

    Future<void> unlink(FileSystemEntity e) async {
      try {
        if (await e.exists()) {
          await e.delete(recursive: e is Directory);
          if (e is File) deleted++;
        }
      } catch (err) {
        debugPrint('[DB] could not delete ${e.path}: $err');
      }
    }

    for (final p in indexed) {
      await unlink(File(p));
    }

    try {
      final docs = await getApplicationDocumentsDirectory();

      // Whole-tree sweep: catches payloads orphaned by earlier index-only
      // deletes, which nothing else can ever find again.
      final recordings = Directory('${docs.path}/HealthyPiRecordings');
      if (await recordings.exists()) {
        await for (final e in recordings.list(recursive: true)) {
          if (e is File) await unlink(e);
        }
        await unlink(recordings);
      }

      // Exported CSVs sit loose in the documents root (see
      // HealthyStoreRecordsManager.exportCsv) and are indexed by nothing.
      await for (final e in docs.list()) {
        if (e is File && basename(e.path).startsWith('hs_record_')) {
          await unlink(e);
        }
      }
    } catch (e) {
      debugPrint('[DB] recording-file sweep failed: $e');
    }

    return deleted;
  }

  /// Close database
  Future close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
