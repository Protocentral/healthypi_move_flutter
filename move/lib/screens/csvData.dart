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

    //Print all rows for debugging
    for (var row in allRows) {
      print(row);
    }
    return allRows;
  }

  Future<List<T>> getDataObjects() async {
    List<File> csvFiles = await listCsvFiles();
    List<List<dynamic>> allRows = await readAllDataSorted(csvFiles);
    return allRows.map(fromRow).toList();
  }

  /// Helper to filter rows by timestamp range (inclusive)
  Future<List<List<dynamic>>> _getRowsByTimestampRange(DateTime start, DateTime end) async {
    List<File> csvFiles = await listCsvFiles();
    List<List<dynamic>> allRows = await readAllDataSorted(csvFiles);
    return allRows.where((row) {
      int ts = int.tryParse(row[0].toString()) ?? 0;
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return dt.isAfter(start.subtract(const Duration(milliseconds: 1))) && dt.isBefore(end.add(const Duration(milliseconds: 1)));
    }).toList();
  }

  /// Get data objects for a specific day
  Future<List<T>> getDataForDay(DateTime day) async {
    DateTime start = DateTime(day.year, day.month, day.day);
    DateTime end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  /// Get data objects for a specific week (starting from the provided date's week)
  Future<List<T>> getDataForWeek(DateTime dateInWeek) async {
    DateTime start = dateInWeek.subtract(Duration(days: dateInWeek.weekday - 1));
    start = DateTime(start.year, start.month, start.day);
    DateTime end = start.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  /// Get data objects for a specific month
  Future<List<T>> getDataForMonth(DateTime month) async {
    DateTime start = DateTime(month.year, month.month, 1);
    DateTime end = (month.month < 12)
        ? DateTime(month.year, month.month + 1, 1).subtract(const Duration(milliseconds: 1))
        : DateTime(month.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
    List<List<dynamic>> rows = await _getRowsByTimestampRange(start, end);
    return rows.map(fromRow).toList();
  }

  
}
