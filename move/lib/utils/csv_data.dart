// Generic CSV Data Manager class for HR, SpO2, Temp, Steps, etc.
// This class is kept for backward compatibility with home.dart and scr_bpt.dart
// New trend screens (scr_hr, scr_spo2, scr_activity, scr_skin_temp) use TrendsDataManager instead
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../globals.dart';
import 'package:path/path.dart' as p;

class CsvDataManager<T> {
  final String filePrefix;
  final T Function(List<dynamic> row) fromRow;
  final String Function(File file) getFileType; // For extensibility

  CsvDataManager({
    required this.filePrefix,
    required this.fromRow,
    required this.getFileType,
  });

  /// Helper function to parse timestamp from CSV (handles both Unix timestamps and formatted dates)
  DateTime? _parseTimestamp(String timestampStr) {
    try {
      // Try parsing as Unix timestamp FIRST (device stores Unix timestamps in seconds)
      // This prevents DateTime.tryParse from incorrectly interpreting numeric strings as years
      int? ts = int.tryParse(timestampStr);
      if (ts != null) {
        // Unix timestamp detected - convert to DateTime
        // Device stores timestamps in UTC, but we need them in local time for display
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
      }
      
      // If not a Unix timestamp, try parsing as formatted date (for formatted dates like "2025-10-02 14:30:00")
      DateTime? dt = DateTime.tryParse(timestampStr);
      if (dt != null) {
        return dt;
      }
      
      return null;
    } catch (e) {
      print('Error parsing timestamp "$timestampStr": $e');
      return null;
    }
  }

  Future<List<File>> listCsvFiles() async {
    Directory? downloadsDirectory;
    if (Platform.isAndroid || Platform.isIOS) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    }

    if (downloadsDirectory == null) return [];

    String downloadsPath = downloadsDirectory.path;
    Directory downloadsDir = Directory(downloadsPath);
    if (!downloadsDir.existsSync()) return [];

    List<FileSystemEntity> files = downloadsDir.listSync();
    return files
        .where((file) => file is File && file.path.endsWith('.csv'))
        .map((file) => file as File)
        .where((file) => p.basename(file.path).startsWith(filePrefix))
        .toList();
  }

  Future<List<List<dynamic>>> readAllDataSorted(List<File> csvFiles) async {
    List<List<dynamic>> allRows = [];
    for (File file in csvFiles) {
      try {
        List<String> lines = await file.readAsLines();
        if (lines.length <= 1) continue;
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.isEmpty) continue;
          List<String> parts = line.split(',');
          allRows.add(parts);
        }
      } catch (e) {
        print('Error reading file ${file.path}: $e');
        continue;
      }
    }
    // Sort by timestamp (handle both Unix timestamps and formatted date strings)
    allRows.sort((a, b) {
      try {
        // Try parsing as DateTime (for formatted dates like "2025-10-02 14:30:00")
        DateTime? dateA = DateTime.tryParse(a[0].toString());
        DateTime? dateB = DateTime.tryParse(b[0].toString());
        
        if (dateA != null && dateB != null) {
          return dateA.compareTo(dateB);
        }
        
        // Fall back to Unix timestamp parsing (for legacy numeric timestamps)
        int? tsA = int.tryParse(a[0].toString());
        int? tsB = int.tryParse(b[0].toString());
        
        if (tsA != null && tsB != null) {
          return tsA.compareTo(tsB);
        }
        
        // If one is date and one is timestamp, convert timestamp to date
        if (dateA != null && tsB != null) {
          DateTime dateBFromTs = DateTime.fromMillisecondsSinceEpoch(tsB * 1000);
          return dateA.compareTo(dateBFromTs);
        }
        if (tsA != null && dateB != null) {
          DateTime dateAFromTs = DateTime.fromMillisecondsSinceEpoch(tsA * 1000);
          return dateAFromTs.compareTo(dateB);
        }
        
        // If all else fails, compare as strings
        return a[0].toString().compareTo(b[0].toString());
      } catch (e) {
        print('Error sorting rows: $e');
        return 0;
      }
    });

    return allRows;
  }

  /// Get all data objects from CSV files
  /// Used by: home.dart, scr_bpt.dart
  Future<List<T>> getDataObjects() async {
    List<File> csvFiles = await listCsvFiles();
    List<List<dynamic>> allRows = await readAllDataSorted(csvFiles);
    return allRows.map(fromRow).toList();
  }

  /// Helper to filter rows by timestamp range (inclusive)
  Future<List<List<dynamic>>> _getRowsByTimestampRange(
    DateTime start,
    DateTime end,
  ) async {
    List<File> csvFiles = await listCsvFiles();
    List<List<dynamic>> allRows = await readAllDataSorted(csvFiles);

    List<List<dynamic>> filteredRows = allRows.where((row) {
      try {
        DateTime? dt;
        
        // Try parsing as DateTime first (for formatted dates like "2025-10-02 14:30:00")
        dt = DateTime.tryParse(row[0].toString());
        
        // If not a formatted date, try parsing as Unix timestamp
        if (dt == null) {
          int? ts = int.tryParse(row[0].toString());
          if (ts != null) {
            dt = DateTime.fromMillisecondsSinceEpoch(
              ts * 1000,
              isUtc: true,
            ); // Assuming timestamp is in seconds
          }
        }
        
        if (dt == null) return false;
        
        return dt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            dt.isBefore(end.add(const Duration(milliseconds: 1)));
      } catch (e) {
        print('Error filtering row by timestamp: $e');
        return false;
      }
    }).toList();

    return filteredRows;
  }

  /// Get min, max, and average for every day of the current month in MonthlyTrend format
  /// Used by: home.dart, scr_bpt.dart
  Future<List<MonthlyTrend>> getMonthlyTrend(DateTime dateInMonth) async {
    DateTime startOfMonth = DateTime(dateInMonth.year, dateInMonth.month, 1);
    DateTime endOfMonth =
        (dateInMonth.month < 12)
            ? DateTime(
              dateInMonth.year,
              dateInMonth.month + 1,
              1,
            ).subtract(const Duration(seconds: 1))
            : DateTime(
              dateInMonth.year + 1,
              1,
              1,
            ).subtract(const Duration(seconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(
      startOfMonth,
      endOfMonth,
    );

    Map<DateTime, List<double>> dailyData = {};

    for (var row in rows) {
      DateTime? dt = _parseTimestamp(row[0].toString());
      if (dt == null) continue;
      
      DateTime day = DateTime(dt.year, dt.month, dt.day);

      double value =
          double.tryParse(row[1].toString()) ??
          0; // Assuming the second column contains the data values
      dailyData.putIfAbsent(day, () => []);
      dailyData[day]!.add(value);
    }

    List<MonthlyTrend> monthlyTrends = [];
    dailyData.forEach((day, values) {
      double min = values.reduce((a, b) => a < b ? a : b);
      double max = values.reduce((a, b) => a > b ? a : b);
      double avg =
          (values.reduce((a, b) => a + b) / values.length).floorToDouble();

      monthlyTrends.add(MonthlyTrend(date: day, min: min, max: max, avg: avg));
    });

    return monthlyTrends;
  }

  /// Get activity trends for a specific month in ActivityMonthlyTrend format
  /// Used by: home.dart
  Future<List<ActivityMonthlyTrend>> getActivityMonthlyTrend(
    DateTime dateInMonth,
  ) async {
    DateTime startOfMonth = DateTime(dateInMonth.year, dateInMonth.month, 1);
    DateTime endOfMonth =
        (dateInMonth.month < 12)
            ? DateTime(
              dateInMonth.year,
              dateInMonth.month + 1,
              1,
            ).subtract(const Duration(seconds: 1))
            : DateTime(
              dateInMonth.year + 1,
              1,
              1,
            ).subtract(const Duration(seconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(
      startOfMonth,
      endOfMonth,
    );

    Map<DateTime, int> monthlySteps = {};

    for (var row in rows) {
      DateTime? timestamp = _parseTimestamp(row[0].toString());
      if (timestamp == null) continue;

      DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      int steps = int.tryParse(row[1].toString()) ?? 0;

      monthlySteps[day] = (monthlySteps[day] ?? 0) + steps;
    }

    List<ActivityMonthlyTrend> monthlyTrends = [];
    monthlySteps.forEach((day, steps) {
      monthlyTrends.add(ActivityMonthlyTrend(date: day, steps: steps));
    });

    monthlyTrends.sort((a, b) => a.date.compareTo(b.date));
    return monthlyTrends;
  }

  /// Get SpO2 trends for a specific month in SpO2MonthlyTrend format
  /// Used by: home.dart
  Future<List<SpO2MonthlyTrend>> getSpO2MonthlyTrend(
    DateTime dateInMonth,
  ) async {
    DateTime startOfMonth = DateTime(dateInMonth.year, dateInMonth.month, 1);
    DateTime endOfMonth =
        (dateInMonth.month < 12)
            ? DateTime(
              dateInMonth.year,
              dateInMonth.month + 1,
              1,
            ).subtract(const Duration(seconds: 1))
            : DateTime(
              dateInMonth.year + 1,
              1,
              1,
            ).subtract(const Duration(seconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(
      startOfMonth,
      endOfMonth,
    );

    Map<DateTime, List<double>> monthlySpo2 = {};

    for (var row in rows) {
      DateTime? timestamp = _parseTimestamp(row[0].toString());
      if (timestamp == null) continue;

      DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
      double spo2 = double.tryParse(row[1].toString()) ?? 0.0;

      monthlySpo2.putIfAbsent(day, () => []);
      monthlySpo2[day]!.add(spo2);
    }

    List<SpO2MonthlyTrend> monthlyTrends = [];
    monthlySpo2.forEach((day, spo2Values) {
      double min = spo2Values.reduce((a, b) => a < b ? a : b);
      double max = spo2Values.reduce((a, b) => a > b ? a : b);
      double avg = spo2Values.reduce((a, b) => a + b) / spo2Values.length;

      monthlyTrends.add(
        SpO2MonthlyTrend(date: day, min: min, max: max, avg: avg),
      );
    });

    monthlyTrends.sort((a, b) => a.date.compareTo(b.date));
    return monthlyTrends;
  }
}
