import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

int totalCount = 0;
int Count = 0;
late DateTime lastUpdatedTime;

String _formatDate(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
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

Future<void> listActivityCSVFiles() async {
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
          .where(
            (file) => p.basename(file.path).startsWith("activity_"),
      ) // Filter by prefix
          .toList();

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

        await processActivityFileData(
          fileNames: [fileName1],
          groupingFormat: "yyyy-MM-dd HH:00:00", // Group by hour
        );
      }
    }
  }
}
// Save the last updated values
saveActivityValue(DateTime lastUpdatedTime, int Count) async {
  String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('latestActivityCount', Count.toString());
  await prefs.setString('lastUpdatedActivity', lastDateTime);
}

Future<void> processActivityFileData({
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
        if (row.length < 2) continue;

        int timestamp = int.parse(row[0]);
        int count = int.parse(row[1]);

        // Convert timestamp to DateTime and group by the specified format
        var dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
        String groupKey = DateFormat(groupingFormat).format(dateTime);

        // Update min and max for the group
        if (!groupedStats.containsKey(groupKey)) {
          groupedStats[groupKey] = {
            'count': count,
          };
        } else {
          groupedStats[groupKey]!['count'] = (groupedStats[groupKey]!['count']! + count); // Add to sum
            Count = groupedStats[groupKey]!['count']!;
        }
      }
    }
  }
  double average = 0;
  // Process the grouped stats and update the UI
  groupedStats.forEach((group, stats) {
    DateTime formattedDateTime = DateTime.parse(group);
  });

  // Update the last aggregated values
  if (groupedStats.isNotEmpty) {
    String lastGroup = groupedStats.keys.last;

      lastUpdatedTime = DateTime.parse(lastGroup);
      Count = groupedStats[lastGroup]!['count']!;

    saveActivityValue(lastUpdatedTime, Count);
  }
}