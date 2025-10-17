import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import 'device_manager.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

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
      version: 4, // Increment version for device_mac column
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
        value_latest INTEGER,
        synced_at INTEGER DEFAULT (strftime('%s', 'now')),
        UNIQUE(timestamp, trend_type, device_mac)
      )
    ''');
    
    await db.execute('CREATE INDEX idx_timestamp ON health_trends(timestamp)');
    await db.execute('CREATE INDEX idx_trend_type ON health_trends(trend_type)');
    await db.execute('CREATE INDEX idx_device_mac ON health_trends(device_mac)');
    await db.execute('CREATE INDEX idx_composite ON health_trends(trend_type, timestamp, device_mac)');
    
    // Table to track synced sessions (prevents re-downloading)
    await db.execute('''
      CREATE TABLE synced_sessions (
        session_id INTEGER NOT NULL,
        trend_type TEXT NOT NULL,
        record_count INTEGER NOT NULL,
        synced_at INTEGER DEFAULT (strftime('%s', 'now')),
        PRIMARY KEY (session_id, trend_type)
      )
    ''');
    
    await db.execute('CREATE INDEX idx_synced_trend ON synced_sessions(trend_type)');
    
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
    
    print('DatabaseHelper: Tables created with indexes');
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

  /// Insert trends from binary data
  Future<int> insertTrendsFromBinary(
    List<int> binaryData,
    String trendType,
    int sessionId, {
    String? deviceMac,
  }) async {
    final db = await database;
    int offset = (binaryData.isNotEmpty && binaryData[0] == 0x0A) ? 1 : 0;
    int recordCount = ((binaryData.length - offset) ~/ 16);
    int inserted = 0;
    
    print('DatabaseHelper.insertTrendsFromBinary: trendType=$trendType, sessionId=$sessionId');
    print('  Binary data length: ${binaryData.length}, offset: $offset, expected records: $recordCount');
    
    await db.transaction((txn) async {
      for (int i = 0; i < recordCount; i++) {
        int pos = i * 16 + offset;
        
        // Read little-endian values
        int timestamp = _readInt64LE(binaryData, pos);
        
        // SPO2 binary format has min/max fields swapped compared to HR/Temp
        int valueMax, valueMin;
        if (trendType == hPi4Global.PREFIX_SPO2) {
          valueMin = _readInt16LE(binaryData, pos + 8);  // SPO2: min at offset 8
          valueMax = _readInt16LE(binaryData, pos + 10); // SPO2: max at offset 10
        } else {
          valueMax = _readInt16LE(binaryData, pos + 8);  // HR/Temp: max at offset 8
          valueMin = _readInt16LE(binaryData, pos + 10); // HR/Temp: min at offset 10
        }
        
        int valueAvg = _readInt16LE(binaryData, pos + 12);
        int valueLatest = _readInt16LE(binaryData, pos + 14);

        // Special-case sanitization for SpO2 prefix values
        // Some device binary formats pack flags or unused bytes into fields
        // which can yield values like 8194 (0x2002). Prefer plausible human
        // SpO2 range (30-100) and collapse values to a single sane number when
        // only one field contains a valid reading.
        if (trendType == hPi4Global.PREFIX_SPO2) {
          bool maxValid = valueMax >= 30 && valueMax <= 100;
          bool minValid = valueMin >= 30 && valueMin <= 100;
          bool avgValid = valueAvg >= 30 && valueAvg <= 100;
          bool latestValid = valueLatest >= 30 && valueLatest <= 100;

          if (maxValid || minValid || avgValid || latestValid) {
            final int chosen = maxValid
                ? valueMax
                : (minValid ? valueMin : (avgValid ? valueAvg : valueLatest));
            valueMax = chosen;
            valueMin = chosen;
            valueAvg = chosen;
            valueLatest = chosen;
          } else {
            // Try low-byte heuristic: some firmware packs value in low byte
            final int lowByte = valueMax & 0xFF;
            if (lowByte >= 30 && lowByte <= 100) {
              valueMax = lowByte;
              valueMin = lowByte;
              valueAvg = lowByte;
              valueLatest = lowByte;
            } else {
              // Unusual values; log for later inspection but still insert raw values
              print('DatabaseHelper: Unusual SPO2 parsed values max=$valueMax min=$valueMin avg=$valueAvg latest=$valueLatest at ts $timestamp');
            }
          }
        }
        
        if (i < 3 || i == recordCount - 1) {
          print('  Record $i: timestamp=$timestamp (${DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: false)}), '
                'max=$valueMax, min=$valueMin, avg=$valueAvg, latest=$valueLatest');
        }
        
        // Validate timestamp (reject if invalid - must be between 2020 and 2030)
        if (timestamp < 1577836800 || timestamp > 1893456000) {
          print('DatabaseHelper: Skipping invalid timestamp: $timestamp');
          continue;
        }
        
        try {
          await txn.insert(
            'health_trends',
            {
              'timestamp': timestamp,
              'trend_type': trendType,
              'session_id': sessionId,
              'device_mac': deviceMac ?? 'unknown',
              'value_max': valueMax,
              'value_min': valueMin,
              'value_avg': valueAvg,
              'value_latest': valueLatest,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          inserted++;
        } catch (e) {
          print('DatabaseHelper: Error inserting record $i: $e');
        }
      }
      
      // Mark session as synced after successful insertion
      if (inserted > 0) {
        await txn.insert(
          'synced_sessions',
          {
            'session_id': sessionId,
            'trend_type': trendType,
            'record_count': inserted,
            'synced_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    
    print('DatabaseHelper: Inserted $inserted/$recordCount records for $trendType (session $sessionId)');
    return inserted;
  }

  /// Get trends for a specific day
  Future<List<Map<String, dynamic>>> getTrendsForDay(
    String trendType,
    DateTime day,
  ) async {
    final db = await database;
    // DON'T convert to UTC - device timestamps are in local time
    int dayStart = DateTime(day.year, day.month, day.day)
        .millisecondsSinceEpoch ~/ 1000;
    int dayEnd = dayStart + 86400;
    
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
    
    // Timestamps in DB are in LOCAL time (device records local time).
    // Create range for the requested local day.
    // DateTime(day.year, day.month, day.day) creates local midnight
    int dayStart = DateTime(day.year, day.month, day.day)
        .millisecondsSinceEpoch ~/ 1000;
    int dayEnd = dayStart + 86400;
    
    print('DatabaseHelper.getHourlyTrends: trendType=$trendType, day=$day, device=$effectiveMac');
    print('  Query range: $dayStart to $dayEnd');
    print('  Date range: ${DateTime.fromMillisecondsSinceEpoch(dayStart * 1000, isUtc: false)} to ${DateTime.fromMillisecondsSinceEpoch(dayEnd * 1000, isUtc: false)}');
    
    // First, let's see what data exists for this trend type
    final allData = await db.query(
      'health_trends',
      where: 'trend_type = ? AND device_mac = ?',
      whereArgs: [trendType, effectiveMac],
      orderBy: 'timestamp DESC',
      limit: 10,
    );
    print('  All data for $trendType (last 10 records):');
    for (var row in allData) {
      print('    Timestamp: ${row['timestamp']} (${DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as int) * 1000, isUtc: false)}), '
            'Max: ${row['value_max']}, Min: ${row['value_min']}, Avg: ${row['value_avg']}');
    }
    
    final results = await db.rawQuery('''
      SELECT 
        (timestamp / 3600) * 3600 as hour_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value,
        COUNT(*) as data_points
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      GROUP BY hour_start
      ORDER BY hour_start ASC
    ''', [trendType, dayStart, dayEnd, effectiveMac]);
    
    print('  Found ${results.length} hourly groups');
    for (var row in results) {
      print('    Hour: ${DateTime.fromMillisecondsSinceEpoch((row['hour_start'] as int) * 1000, isUtc: false)}, '
            'Max: ${row['max_value']}, Min: ${row['min_value']}, Avg: ${row['avg_value']}, Points: ${row['data_points']}');
    }
    
    return results;
  }

  /// Get weekly aggregated trends
  Future<List<Map<String, dynamic>>> getWeeklyTrends(
    String trendType,
    DateTime startDate, {
    String? deviceMac,
  }) async {
    final db = await database;
    final effectiveMac = deviceMac ?? await _getCurrentDeviceMac();
    
    // Timestamps in DB are in LOCAL time (device records local time).
    int weekStart = DateTime(startDate.year, startDate.month, startDate.day)
        .millisecondsSinceEpoch ~/ 1000;
    int weekEnd = weekStart + (7 * 86400);
    
    return await db.rawQuery('''
      SELECT 
        (timestamp / 86400) * 86400 as day_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value,
        COUNT(*) as data_points
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      GROUP BY day_start
      ORDER BY day_start ASC
    ''', [trendType, weekStart, weekEnd, effectiveMac]);
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
    
    // Timestamps in DB are in LOCAL time (device records local time).
    int monthStart = DateTime(year, month, 1)
        .millisecondsSinceEpoch ~/ 1000;
    int monthEnd = DateTime(year, month + 1, 1)
        .millisecondsSinceEpoch ~/ 1000;
    
    return await db.rawQuery('''
      SELECT 
        (timestamp / 86400) * 86400 as day_start,
        MAX(value_max) as max_value,
        MIN(value_min) as min_value,
        AVG(value_avg) as avg_value,
        COUNT(*) as data_points
      FROM health_trends
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ? AND device_mac = ?
      GROUP BY day_start
      ORDER BY day_start ASC
    ''', [trendType, monthStart, monthEnd, effectiveMac]);
  }

  /// Clean up old data (older than specified retention days)
  Future<int> cleanupOldData({int retentionDays = 30}) async {
    final db = await database;
    // Timestamps in DB are local time, so use local time for cutoff
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

  /// Check if a session has already been synced
  Future<bool> isSessionSynced(int sessionId, String trendType) async {
    final db = await database;
    final result = await db.query(
      'synced_sessions',
      where: 'session_id = ? AND trend_type = ?',
      whereArgs: [sessionId, trendType],
    );
    return result.isNotEmpty;
  }

  /// Mark a session as synced
  Future<void> markSessionSynced(int sessionId, String trendType, int recordCount) async {
    final db = await database;
    await db.insert(
      'synced_sessions',
      {
        'session_id': sessionId,
        'trend_type': trendType,
        'record_count': recordCount,
        'synced_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('DatabaseHelper: Marked session $sessionId ($trendType) as synced with $recordCount records');
  }

  /// Get list of synced session IDs for a trend type
  Future<List<int>> getSyncedSessionIds(String trendType) async {
    final db = await database;
    final result = await db.query(
      'synced_sessions',
      columns: ['session_id'],
      where: 'trend_type = ?',
      whereArgs: [trendType],
      orderBy: 'session_id DESC',
    );
    return result.map((row) => row['session_id'] as int).toList();
  }

  /// Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final db = await database;
    
    final result = await db.rawQuery('''
      SELECT 
        trend_type,
        COUNT(*) as session_count,
        SUM(record_count) as total_records,
        MAX(synced_at) as last_sync
      FROM synced_sessions
      GROUP BY trend_type
    ''');
    
    Map<String, dynamic> stats = {};
    for (var row in result) {
      String type = row['trend_type'] as String;
      stats['${type}_sessions'] = row['session_count'];
      stats['${type}_records'] = row['total_records'];
      stats['${type}_last_sync'] = row['last_sync'];
    }
    
    // Get total synced sessions
    final total = await db.rawQuery('SELECT COUNT(*) as total FROM synced_sessions');
    if (total.isNotEmpty) {
      stats['total_sessions'] = total.first['total'];
    }
    
    return stats;
  }

  /// Clear sync history (useful for forcing re-sync)
  Future<int> clearSyncHistory({String? trendType}) async {
    final db = await database;
    if (trendType != null) {
      return await db.delete(
        'synced_sessions',
        where: 'trend_type = ?',
        whereArgs: [trendType],
      );
    } else {
      return await db.delete('synced_sessions');
    }
  }

  // ============================================================================
  // App Metadata Methods (replaces SharedPreferences for health-related data)
  // ============================================================================

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

    // Calculate today's date range (midnight to midnight in local timezone)
    // Timestamps in DB are in LOCAL time (device records local time)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(Duration(days: 1));
    final todayStartTimestamp = todayStart.millisecondsSinceEpoch ~/ 1000;
    final todayEndTimestamp = todayEnd.millisecondsSinceEpoch ~/ 1000;

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
            (timestamp / 3600) * 3600 as hour_start,
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
    
    // Delete from synced_sessions (session_id is not device-specific but we should clear to allow re-sync)
    // Note: This is conservative - we delete all synced session history when switching devices
    await db.delete('synced_sessions');
    
    print('DatabaseHelper: Deleted $trendsDeleted records for device $deviceMac');
    return trendsDeleted;
  }

  /// Helper: Read 64-bit little-endian integer
  int _readInt64LE(List<int> bytes, int offset) {
    int result = 0;
    for (int i = 7; i >= 0; i--) {
      result = (result << 8) | bytes[offset + i];
    }
    return result;
  }

  /// Helper: Read 16-bit little-endian integer
  int _readInt16LE(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  /// Close database
  Future close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
