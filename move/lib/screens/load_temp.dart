import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _formatDate(DateTime date) {
  return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

List<String> timestampTemo = [];
List<String> minTemp = [];
List<String> maxTemp = [];
List<String> avgTemp = [];
List<String> latestTemp = [];

double restingTemp = 0;
double rangeMinTemp = 0;
double rangeMaxTemp = 0;
double averageTemp = 0;
late DateTime lastUpdatedTempTime;

Future<void> listTempCSVFiles() async {
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
            (file) => p.basename(file.path).startsWith("temp_"),
      ) // Filter by prefix
          .toList();

      List<String> fileNames =
      csvFiles.map((file) => p.basename(file.path)).toList();

      restingTemp = 0;
      rangeMinTemp = 0;
      rangeMaxTemp = 0;
      averageTemp = 0;

      for (File file in csvFiles) {
        String timestamp = await _getSecondLineTimestamp(file);
        //timestamps.add(timestamp);
        String timestamp1 = timestamp.split(",")[0];
        int timestamp2 = int.parse(timestamp1);
        int updatedTimestamp = timestamp2 * 1000;
        String fileName1 = p.basename(file.path);

        DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
          updatedTimestamp,
          isUtc: true,
        );

        await processTempFileData(
          fileNames: [fileName1],
          groupingFormat: "yyyy-MM-dd HH:00:00", // Group by hour
        );

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
saveTempValue(DateTime lastUpdatedTime, double averageTemp) async {
  String lastDateTime = DateFormat(
    'EEE d MMM',
  ).format(lastUpdatedTime);
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('latestTemp', averageTemp.toString());
  await prefs.setString('lastUpdatedTemp', lastDateTime.toString());
}

Future<void> processTempFileData({
  required List<String> fileNames, // List of files to process
  required String
  groupingFormat, // Grouping format: "yyyy-MM-dd HH:00:00" for hourly, "yyyy-MM-dd" for daily
}) async {
  Directory? downloadsDirectory;
  Map<String, Map<String, double>> groupedTempStats =
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
        double min = double.parse(row[1]);
        double max = double.parse(row[2]);
        double avg = double.parse(row[3]);
        double latest = double.parse(row[4]);

        // Convert timestamp to DateTime and group by the specified format
        var dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
        String groupKey = DateFormat(groupingFormat).format(dateTime);

        // Update min and max for the group
        if (!groupedTempStats.containsKey(groupKey)) {
          groupedTempStats[groupKey] = {
            'min': min,
            'max': max,
            'avg': avg,
            'count': 1,
            'latest': latest,
          };
        } else {
          groupedTempStats[groupKey]!['min'] =
          groupedTempStats[groupKey]!['min']! < min
              ? groupedTempStats[groupKey]!['min']!
              : min;
          groupedTempStats[groupKey]!['max'] =
          groupedTempStats[groupKey]!['max']! > max
              ? groupedTempStats[groupKey]!['max']!
              : max;
          //print(groupedStats[groupKey]!['min']);
          //print(groupedStats[groupKey]!['max']);
          groupedTempStats[groupKey]!['avg'] =
          (groupedTempStats[groupKey]!['avg']! + avg); // Add to sum
          groupedTempStats[groupKey]!['count'] =
              groupedTempStats[groupKey]!['count']! + 1;
        }
      }
    }
  }
  double average = 0;
  double Max = 0;
  double Min = 0;
  // Process the grouped stats and update the UI
  groupedTempStats.forEach((group, stats) {
    DateTime formattedDateTime = DateTime.parse(group);

      average = ((stats['avg']! / 100) / stats['count']!);

  });

  // Update the last aggregated values
  if (groupedTempStats.isNotEmpty) {
    String lastGroup = groupedTempStats.keys.last;
    String avgString = average.toStringAsFixed(2);
    double lastMin = groupedTempStats[lastGroup]!['min']! / 100;
    double lastMax = groupedTempStats[lastGroup]!['max']! / 100;
    double lastAvg = double.parse(avgString);

      lastUpdatedTempTime = DateTime.parse(lastGroup);
      averageTemp = lastAvg;
      restingTemp = groupedTempStats[lastGroup]!['latest']! / 100;
      rangeMinTemp = lastMin;
      rangeMaxTemp = lastMax;

    saveTempValue(lastUpdatedTempTime, averageTemp);
  }
}
