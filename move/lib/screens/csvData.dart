// Generic CSV Data Manager class for HR, SpO2, Temp, Steps, etc.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';
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
    // Sort by timestamp (assume first column is timestamp)
    allRows.sort((a, b) => int.parse(a[0]).compareTo(int.parse(b[0])));

    return allRows;
  }

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

    List<List<dynamic>> filteredRows =
        allRows.where((row) {
          int ts = int.tryParse(row[0].toString()) ?? 0;
          DateTime dt = DateTime.fromMillisecondsSinceEpoch(
            ts * 1000,
            isUtc: true
          ); // Assuming timestamp is in seconds
          return dt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
              dt.isBefore(end.add(const Duration(milliseconds: 1)));
        }).toList();

    return filteredRows;
  }

  /// Get data objects for a specific day
  Future<List<T>> getDataForDay(DateTime day) async {
    DateTime start = DateTime(day.year, day.month, day.day);
    DateTime end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  /// Get data objects for a specific week (starting from the provided date's week)
  Future<List<T>> getDataForWeek(DateTime dateInWeek) async {
    DateTime start = dateInWeek.subtract(
      Duration(days: dateInWeek.weekday - 1),
    );
    start = DateTime(start.year, start.month, start.day);
    DateTime end = start
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  /// Get data objects for a specific month
  Future<List<T>> getDataForMonth(DateTime month) async {
    DateTime start = DateTime(month.year, month.month, 1);
    DateTime end =
        (month.month < 12)
            ? DateTime(
              month.year,
              month.month + 1,
              1,
            ).subtract(const Duration(milliseconds: 1))
            : DateTime(
              month.year + 1,
              1,
              1,
            ).subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  /// Get min, max, and average for every hour of the current day in HourlyTrend format
  Future<List<HourlyTrend>> getHourlyTrendForToday() async {
    DateTime now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, now.day);
    DateTime end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);

    Map<int, List<double>> hourlyData = {};

    for (var row in rows) {
      int ts = int.tryParse(row[0].toString()) ?? 0;
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
      int hour = dt.hour;

      double value =
          double.tryParse(row[1].toString()) ??
          0; // Assuming the second column contains the data values
      hourlyData.putIfAbsent(hour, () => []);
      hourlyData[hour]!.add(value);
    }

    List<HourlyTrend> hourlyTrends = [];
    hourlyData.forEach((hour, values) {
      double min = values.reduce((a, b) => a < b ? a : b);
      double max = values.reduce((a, b) => a > b ? a : b);
      double avg = values.reduce((a, b) => a + b) / values.length;

      hourlyTrends.add(HourlyTrend(hour: hour, min: min, max: max, avg: avg));
    });

    return hourlyTrends;
  }

  /// Get min, max, and average for every day of the current week in WeeklyTrend format
  Future<List<WeeklyTrend>> getWeeklyTrend(DateTime dateInWeek) async {
    DateTime startOfWeek = dateInWeek.subtract(
      Duration(days: dateInWeek.weekday - 1),
    );
    startOfWeek = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );
    DateTime endOfWeek = startOfWeek
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(
      startOfWeek,
      endOfWeek,
    );

    Map<DateTime, List<double>> dailyData = {};

    for (var row in rows) {
      int ts = int.tryParse(row[0].toString()) ?? 0;
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
      DateTime day = DateTime(dt.year, dt.month, dt.day);

      double value =
          double.tryParse(row[1].toString()) ??
          0; // Assuming the second column contains the data values
      dailyData.putIfAbsent(day, () => []);
      dailyData[day]!.add(value);
    }

    List<WeeklyTrend> weeklyTrends = [];
    dailyData.forEach((day, values) {
      double min = values.reduce((a, b) => a < b ? a : b);
      double max = values.reduce((a, b) => a > b ? a : b);
      double avg =
          (values.reduce((a, b) => a + b) / values.length).floorToDouble();

      weeklyTrends.add(WeeklyTrend(date: day, min: min, max: max, avg: avg));
    });

    return weeklyTrends;
  }

  /// Get min, max, and average for every day of the current month in MonthlyTrend format
  Future<List<MonthlyTrend>> getMonthlyTrend(DateTime dateInMonth) async {
    DateTime startOfMonth = DateTime(dateInMonth.year, dateInMonth.month, 1);
    DateTime endOfMonth =
        (dateInMonth.month < 12)
            ? DateTime(
              dateInMonth.year,
              dateInMonth.month + 1,
              1,
            ).subtract(const Duration(milliseconds: 1))
            : DateTime(
              dateInMonth.year + 1,
              1,
              1,
            ).subtract(const Duration(milliseconds: 1));

    List<List<dynamic>> rows = await _getRowsByTimestampRange(
      startOfMonth,
      endOfMonth,
    );

    Map<DateTime, List<double>> dailyData = {};

    for (var row in rows) {
      int ts = int.tryParse(row[0].toString()) ?? 0;
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
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

  /// Get min, max, and average statistics for a specific day
  Future<Map<String, double>> getDailyStatistics(DateTime day) async {
    List<WeeklyTrend> dailyTrends = await getWeeklyTrend(day);
    double min = dailyTrends.map((trend) => trend.min).reduce((a, b) => a < b ? a : b);
    double max = dailyTrends.map((trend) => trend.max).reduce((a, b) => a > b ? a : b);
    double avg = dailyTrends.map((trend) => trend.avg).reduce((a, b) => a + b) / dailyTrends.length;

    return {
      'min': min,
      'max': max,
      'avg': avg,
    };
  }

  /// Get min, max, and average statistics for a specific week
  Future<Map<String, double>> getWeeklyStatistics(DateTime dateInWeek) async {
    List<WeeklyTrend> weeklyTrends = await getWeeklyTrend(dateInWeek);
    double min = weeklyTrends.map((trend) => trend.min).reduce((a, b) => a < b ? a : b);
    double max = weeklyTrends.map((trend) => trend.max).reduce((a, b) => a > b ? a : b);
    double avg = weeklyTrends.map((trend) => trend.avg).reduce((a, b) => a + b) / weeklyTrends.length;

    return {
      'min': min,
      'max': max,
      'avg': avg,
    };
  }

  /// Get min, max, and average statistics for a specific month
  Future<Map<String, double>> getMonthlyStatistics(DateTime dateInMonth) async {
    List<MonthlyTrend> monthlyTrends = await getMonthlyTrend(dateInMonth);
    double min = monthlyTrends.map((trend) => trend.min).reduce((a, b) => a < b ? a : b);
    double max = monthlyTrends.map((trend) => trend.max).reduce((a, b) => a > b ? a : b);
    double avg = monthlyTrends.map((trend) => trend.avg).reduce((a, b) => a + b) / monthlyTrends.length;

    return {
      'min': min,
      'max': max,
      'avg': avg,
    };
  }
}
