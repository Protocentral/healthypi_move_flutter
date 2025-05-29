import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _formatDate(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

List<String> timestamp = [];
List<String> minHR = [];
List<String> maxHR = [];
List<String> avgHR = [];
List<String> latestHR = [];

int restingHR = 0;
int rangeMinHR = 0;
int rangeMaxHR = 0;
int averageHR = 0;
late DateTime lastUpdatedTime;

Future<void> listCSVFiles() async {
  Directory? downloadsDirectory;
  if (Platform.isAndroid) {
    //downloadsDirectory = Directory('/storage/emulated/0/Download');
    downloadsDirectory = await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  }
  if (downloadsDirectory != null) {
    String downloadsPath = downloadsDirectory.path;
    Directory downloadsDir = Directory(downloadsPath);
    if (downloadsDir.existsSync()) {
      List<FileSystemEntity> files = downloadsDir.listSync();

      List<File> csvFiles =
      files
          .where((file) => file is File && file.path.endsWith('.csv'))
          .map((file) => file as File)
          .where(
            (file) => p.basename(file.path).startsWith("hr_"),
      ) // Filter by prefix
          .toList();

      restingHR = 0;
      rangeMinHR = 0;
      rangeMaxHR = 0;
      averageHR = 0;

      for (File file in csvFiles) {
        String timestamp = await _getSecondLineTimestamp(file);
        String timestamp1 = timestamp.split(",")[0];
        int timestamp2 = int.parse(timestamp1);
        int updatedTimestamp = timestamp2 * 1000;
        String fileName1 = p.basename(file.path);

        DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
          updatedTimestamp,
          isUtc: true,
        );
        DateTime now = DateTime.now();
        String todayStr = _formatDate(now);

        await processFileData(
          fileNames: [fileName1],
          groupingFormat: "yyyy-MM-dd HH:00:00", // Group by hour
        ); //

      }
    }
  }
}

Future<String> _getSecondLineTimestamp(File file) async {
  try {
    List<String> lines = await file.readAsLines();
    if (lines.length > 1) {
      return lines[1]; // Assuming the timestamp is on the second line
    }
    return '0';
  } catch (e) {
    return 'Error reading file: $e';
  }
}

// Save a value
saveValue(DateTime lastUpdatedTime, int averageHR) async {
  String lastDateTime = DateFormat(
    'EEE d MMM',
  ).format(lastUpdatedTime);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('latestHR', averageHR.toString());
  await prefs.setString('lastUpdatedHR', lastDateTime);
}

Future<void> processFileData({
  required List<String> fileNames, // List of files to process
  required String
  groupingFormat, // Grouping format: "yyyy-MM-dd HH:00:00" for hourly, "yyyy-MM-dd" for daily
}) async {
  Directory? downloadsDirectory;
  Map<String, Map<String, int>> groupedStats =
  {}; // To store grouped min and max values

  if (Platform.isAndroid) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    downloadsDirectory = await getApplicationDocumentsDirectory();
  }

  if (downloadsDirectory == null) return;

  for (String fileName in fileNames) {
    String filePath = '${downloadsDirectory.path}/$fileName';
    File csvFile = File(filePath);

    if (await csvFile.exists()) {
      String fileContent = await csvFile.readAsString();
      List<String> result = fileContent.split('\n');
      if (result.isEmpty) continue;

      // Extract headers and rows
      List<String> headers = result.first.split(',');
      List<List<String>> rows =
      result.skip(1).map((line) => line.split(',')).toList();

      // Process each row
      for (var row in rows) {
        if (row.length < 5) continue;

        int timestamp = int.parse(row[0]);
        int minHR = int.parse(row[1]);
        int maxHR = int.parse(row[2]);
        int avgHR = int.parse(row[3]);
        int latestHR = int.parse(row[4]);

        // Convert timestamp to DateTime and group by the specified format
        var dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
        String groupKey = DateFormat(groupingFormat).format(dateTime);

        // Update min and max for the group
        if (!groupedStats.containsKey(groupKey)) {
          groupedStats[groupKey] = {
            'min': minHR,
            'max': maxHR,
            'avg': avgHR,
            'count': 1,
            'latest': latestHR,
          };
        } else {
          groupedStats[groupKey]!['min'] = groupedStats[groupKey]!['min']! < minHR
              ? groupedStats[groupKey]!['min']!
              : minHR;
          groupedStats[groupKey]!['max'] =
          groupedStats[groupKey]!['max']! > maxHR
              ? groupedStats[groupKey]!['max']!
              : maxHR;
          groupedStats[groupKey]!['avg'] =
          (groupedStats[groupKey]!['avg']! + avgHR); // Add to sum
          groupedStats[groupKey]!['count'] =
              groupedStats[groupKey]!['count']! + 1;
        }
      }
    }
  }
  double average = 0;
  // Process the grouped stats and update the UI
  groupedStats.forEach((group, stats) {
    DateTime formattedDateTime = DateTime.parse(group);
    average = (stats['avg']! / stats['count']!);
  });

  // Update the last aggregated values
  if (groupedStats.isNotEmpty) {
    String lastGroup = groupedStats.keys.last;
    int lastMin = groupedStats[lastGroup]!['min']!;
    int lastMax = groupedStats[lastGroup]!['max']!;
    int lastAvg = average.toInt();

    lastUpdatedTime = DateTime.parse(lastGroup);
    rangeMinHR = lastMin;
    rangeMaxHR = lastMax;
    averageHR = lastAvg;
    restingHR = groupedStats[lastGroup]!['latest']!;
    String todayStr = _formatDate(DateTime.now());

    saveValue(lastUpdatedTime, averageHR);

   /* if (_formatDate(lastUpdatedTime) == todayStr) {
      saveValue(lastUpdatedTime, averageHR);
    }*/
  }
}
