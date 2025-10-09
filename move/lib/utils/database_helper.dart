import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../globals.dart';

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
      version: 1,
      onCreate: _createDB,
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
        value_max INTEGER,
        value_min INTEGER,
        value_avg INTEGER,
        value_latest INTEGER,
        synced_at INTEGER DEFAULT (strftime('%s', 'now')),
        UNIQUE(timestamp, trend_type)
      )
    ''');
    
    await db.execute('CREATE INDEX idx_timestamp ON health_trends(timestamp)');
    await db.execute('CREATE INDEX idx_trend_type ON health_trends(trend_type)');
    await db.execute('CREATE INDEX idx_composite ON health_trends(trend_type, timestamp)');
    
    print('DatabaseHelper: Tables created with indexes');
  }

  /// Insert trends from binary data
  Future<int> insertTrendsFromBinary(
    List<int> binaryData,
    String trendType,
    int sessionId,
  ) async {
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
          print('  Record $i: timestamp=$timestamp (${DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)}), '
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
    DateTime day,
  ) async {
    final db = await database;
    // DON'T convert to UTC - device timestamps are in local time
    int dayStart = DateTime(day.year, day.month, day.day)
        .millisecondsSinceEpoch ~/ 1000;
    int dayEnd = dayStart + 86400;
    
    print('DatabaseHelper.getHourlyTrends: trendType=$trendType, day=$day');
    print('  Query range: $dayStart to $dayEnd');
    print('  Date range: ${DateTime.fromMillisecondsSinceEpoch(dayStart * 1000)} to ${DateTime.fromMillisecondsSinceEpoch(dayEnd * 1000)}');
    
    // First, let's see what data exists for this trend type
    final allData = await db.query(
      'health_trends',
      where: 'trend_type = ?',
      whereArgs: [trendType],
      orderBy: 'timestamp DESC',
      limit: 10,
    );
    print('  All data for $trendType (last 10 records):');
    for (var row in allData) {
      print('    Timestamp: ${row['timestamp']} (${DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as int) * 1000)}), '
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
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ?
      GROUP BY hour_start
      ORDER BY hour_start ASC
    ''', [trendType, dayStart, dayEnd]);
    
    print('  Found ${results.length} hourly groups');
    for (var row in results) {
      print('    Hour: ${DateTime.fromMillisecondsSinceEpoch((row['hour_start'] as int) * 1000)}, '
            'Max: ${row['max_value']}, Min: ${row['min_value']}, Avg: ${row['avg_value']}, Points: ${row['data_points']}');
    }
    
    return results;
  }

  /// Get weekly aggregated trends
  Future<List<Map<String, dynamic>>> getWeeklyTrends(
    String trendType,
    DateTime startDate,
  ) async {
    final db = await database;
    // DON'T convert to UTC - device timestamps are in local time
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
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ?
      GROUP BY day_start
      ORDER BY day_start ASC
    ''', [trendType, weekStart, weekEnd]);
  }

  /// Get monthly aggregated trends
  Future<List<Map<String, dynamic>>> getMonthlyTrends(
    String trendType,
    int year,
    int month,
  ) async {
    final db = await database;
    // DON'T convert to UTC - device timestamps are in local time
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
      WHERE trend_type = ? AND timestamp >= ? AND timestamp < ?
      GROUP BY day_start
      ORDER BY day_start ASC
    ''', [trendType, monthStart, monthEnd]);
  }

  /// Clean up old data (older than specified retention days)
  Future<int> cleanupOldData({int retentionDays = 30}) async {
    final db = await database;
    int cutoffTime = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toUtc()
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
