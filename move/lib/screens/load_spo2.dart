import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> timestamp = [];
List<String> minSpo2 = [];
List<String> maxSpo2 =[];
List<String> avgSpo2 =[];
List<String> latestSpo2 =[];

int restingSpo2 = 0;
int rangeMinSpo2 = 0;
int rangeMaxSpo2 = 0;
int averageSpo2 = 0;
late DateTime lastUpdatedTime;

String _formatDate(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

Future<void> listSpo2CSVFiles() async {
  Directory? downloadsDirectory;
  if (Platform.isAndroid) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  }
  if (downloadsDirectory != null) {
    String downloadsPath = downloadsDirectory.path;
    Directory downloadsDir = Directory(downloadsPath);
    if (downloadsDir.existsSync()) {
      List<FileSystemEntity> files = downloadsDir.listSync();

      List<File> csvFiles = files
          .where((file) => file is File && file.path.endsWith('.csv'))
          .map((file) => file as File)
          .where((file) => p.basename(file.path).startsWith("spo2_")) // Filter by prefix
          .toList();

      List<String> fileNames = csvFiles.map((file) => p.basename(file.path)).toList();

      for (File file in csvFiles) {
        String timestamp = await _getSecondLineTimestamp(file);
        String timestamp1 = timestamp.split(",")[0];
        int timestamp2 = int.parse(timestamp1);
        int updatedTimestamp = timestamp2 * 1000;
        String fileName1 = p.basename(file.path);

        await _processFileForHourlyOrDailyStats(fileName1, "hour");

      }
    }
  }
}

Future<void> _processFileForHourlyOrDailyStats(String fileName, String range) async {
  Directory? downloadsDirectory;
  if (Platform.isAndroid) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  }

  if (downloadsDirectory != null) {
    String filePath = '${downloadsDirectory.path}/$fileName';
    File csvFile = File(filePath);

    if (await csvFile.exists()) {
      String fileContent = await csvFile.readAsString();
      _calculateMinMaxBasedOnRange(fileContent, range);

    }
  }
}

_calculateMinMaxBasedOnRange(String fileContent, String range) {
  List<String> lines = fileContent.split('\n');
  Map<String, List<int>> groupedData = {};
  DateTime now = DateTime.now();
  Duration rangeDuration;

  // Define the range for grouping
  if (range == "hour") {
    rangeDuration = Duration(hours: 1);
  } else if (range == "day") {
    rangeDuration = Duration(days: 1);
  } else if (range == "month") {
    rangeDuration = Duration(days: 30); // Assuming 30 days for a month
  } else {
    throw Exception("Invalid range specified.");
  }

  for (int i = 1; i < lines.length; i++) { // Start from 1 to skip the header
    if (lines[i].trim().isEmpty) continue;

    List<String> parts = lines[i].split(',');
    if (parts.length < 2) continue;

    int timestamp = int.parse(parts[0]) * 1000;
    int spo2 = int.parse(parts[1]);

    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (dateTime.isBefore(now.subtract(rangeDuration)) || dateTime.isAfter(now)) {
      continue; // Skip data outside the range
    }

    String rangeKey = "0";

    if (range == "hour") {
      rangeKey = DateFormat('yyyy-MM-dd HH:00:00').format(dateTime); // Group by hour
    } else if (range == "day" || range == "month") {
      rangeKey = DateFormat('yyyy-MM-dd').format(dateTime); // Group by day
    }

    if (!groupedData.containsKey(rangeKey)) {
      groupedData[rangeKey] = [];
    }
    groupedData[rangeKey]!.add(spo2);
  }
  int minSpo2 = 0;
  int maxSpo2 = 0;

  groupedData.forEach((group, spo2Values) {
    minSpo2 = spo2Values.reduce((a, b) => a < b ? a : b); // Calculate min as an int
    maxSpo2 = spo2Values.reduce((a, b) => a > b ? a : b); // Calculate max as an int

    DateTime formattedDateTime = DateTime.parse(group);
      restingSpo2 = maxSpo2;
      averageSpo2 = maxSpo2;
      rangeMinSpo2 = minSpo2;
      rangeMaxSpo2 = maxSpo2;

    // print("$range: $group, Min: $minSpo2, Max: $maxSpo2");
  });

  if (groupedData.isNotEmpty) {
    String lastGroup = groupedData.keys.last;

      lastUpdatedTime = DateTime.parse(lastGroup);

    saveSpo2Value(lastUpdatedTime);
  }
}

Future<String> _getSecondLineTimestamp(File file) async {
  try {
    List<String> lines = await file.readAsLines();
    if (lines.length > 1) {
      return lines[1]; // Assuming the timestamp is on the second line
    }
    return 'No second line';
  } catch (e) {
    return 'Error reading file: $e';
  }
}

// Save a value
saveSpo2Value(DateTime lastUpdatedTime) async {
  String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('latestSpo2', restingSpo2.toString());
  await prefs.setString('lastUpdatedSpo2', lastDateTime.toString());
}