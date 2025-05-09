import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class SkinTemperaturePage extends StatefulWidget {
  const SkinTemperaturePage({super.key});
  @override
  State<SkinTemperaturePage> createState() => _SkinTemperaturePageState();
}

class _SkinTemperaturePageState extends State<SkinTemperaturePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> timestamp = [];
  List<String> minTemp = [];
  List<String> maxTemp = [];
  List<String> avgTemp = [];
  List<String> latestTemp = [];

  double restingTemp = 0;
  double rangeMinTemp = 0;
  double rangeMaxTemp = 0;
  double averageTemp = 0;
  late DateTime lastUpdatedTime;

  List<TempTrends> TempTrendsData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _listCSVFiles();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    setState(() {
      _listCSVFiles();
    });
  }

  dateTimeAxis() {
    if (_tabController.index == 0) {
      return DateTimeAxis(
        // Display a 6-hour range dynamically based on slider values
        minimum: DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          0,
          0,
          0,
        ), // Start value of the range slider
        maximum: DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          23,
          59,
          59,
        ),
        //DateTime.now(), // End value of the range slider
        interval: 1,
        intervalType: DateTimeIntervalType.hours,
        dateFormat: DateFormat.Hm(),
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    } else if (_tabController.index == 1) {
      return DateTimeAxis(
        // Display a 6-hour interval dynamically based on slider values
        minimum: DateTime.now().subtract(Duration(days: 7)), // 7 days before
        maximum: DateTime.now(),
        interval: 1, // 6-hour intervals
        intervalType: DateTimeIntervalType.days,
        dateFormat: DateFormat('EEE'), // Show day and hour
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    } else {
      return DateTimeAxis(
        // Display a month-long range dynamically based on slider values
        minimum: DateTime.now().subtract(Duration(days: 30)), // 30 days ago
        maximum: DateTime.now(), // Today
        interval: 1, // 6-hour intervals
        intervalType: DateTimeIntervalType.days,
        dateFormat: DateFormat('dd MMM'), // Show day, month, and hour
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }
  }

  Widget buildChartBlock() {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        color: Colors.grey[900],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                primaryXAxis: dateTimeAxis(),
                primaryYAxis: NumericAxis(
                  majorGridLines: MajorGridLines(width: 0.05),
                  minimum: 0,
                  maximum: 200,
                  interval: 10,
                  anchorRangeToVisiblePoints: false,
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                palette: <Color>[hPi4Global.hpi4Color],
                series: <CartesianSeries>[
                  RangeColumnSeries<TempTrends, DateTime>(
                    dataSource: TempTrendsData,
                    xValueMapper: (TempTrends data, _) => data.date,
                    lowValueMapper: (TempTrends data, _) => data.minTemp,
                    highValueMapper: (TempTrends data, _) => data.maxTemp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
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

  Future<void> _listCSVFiles() async {
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

        List<String> weeklyFileNames = [];
        List<String> MonthlyFileNames = [];

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

          DateTime now = DateTime.now();

          if (_tabController.index == 0) {
            String todayStr = _formatDate(now);
            if (_formatDate(timestampDateTime) == todayStr) {
              await processFileData(
                fileNames: [fileName1],
                groupingFormat: "yyyy-MM-dd HH:00:00", // Group by hour
              );
            } else {}
          } else if (_tabController.index == 1) {
            DateTime weekStart = now.subtract(Duration(days: 7));
            if (timestampDateTime.isAfter(weekStart) &&
                timestampDateTime.isBefore(now)) {
              weeklyFileNames.add(fileName1); // Process the file data
            }
            if (weeklyFileNames.isNotEmpty) {
              await processFileData(
                fileNames: weeklyFileNames,
                groupingFormat: "yyyy-MM-dd", // Group by day
              );
            } else {}
          } else if (_tabController.index == 2) {
            DateTime monthStart = now.subtract(Duration(days: 30));

            if (timestampDateTime.isAfter(monthStart) &&
                timestampDateTime.isBefore(now)) {
              MonthlyFileNames.add(fileName1);
            }
            if (MonthlyFileNames.isNotEmpty) {
              await processFileData(
                fileNames: MonthlyFileNames,
                groupingFormat: "yyyy-MM-dd", // Group by day
              );
            } else {}
          }
        }
      }
    }
  }

  // Save a value
  saveValue(DateTime lastUpdatedTime, double averageTemp) async {
    String lastDateTime = DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestTemp', averageTemp.toString());
    await prefs.setString('lastUpdatedTemp', lastDateTime.toString());
  }

  Future<void> processFileData({
    required List<String> fileNames, // List of files to process
    required String
    groupingFormat, // Grouping format: "yyyy-MM-dd HH:00:00" for hourly, "yyyy-MM-dd" for daily
  }) async {
    Directory? downloadsDirectory;
    Map<String, Map<String, double>> groupedStats =
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
          if (!groupedStats.containsKey(groupKey)) {
            groupedStats[groupKey] = {
              'min': min,
              'max': max,
              'avg': avg,
              'count': 1,
              'latest': latest,
            };
          } else {
            groupedStats[groupKey]!['min'] =
                groupedStats[groupKey]!['min']! < min
                    ? groupedStats[groupKey]!['min']!
                    : min;
            groupedStats[groupKey]!['max'] =
                groupedStats[groupKey]!['max']! > max
                    ? groupedStats[groupKey]!['max']!
                    : max;
            //print(groupedStats[groupKey]!['min']);
            //print(groupedStats[groupKey]!['max']);
            groupedStats[groupKey]!['avg'] =
                (groupedStats[groupKey]!['avg']! + avg); // Add to sum
            groupedStats[groupKey]!['count'] =
                groupedStats[groupKey]!['count']! + 1;
          }
        }
      }
    }
    double average = 0;
    double Max = 0;
    double Min = 0;
    // Process the grouped stats and update the UI
    groupedStats.forEach((group, stats) {
      DateTime formattedDateTime = DateTime.parse(group);
      setState(() {
        TempTrendsData.add(
          TempTrends(
            formattedDateTime,
            stats['min']! / 100,
            stats['max']! / 100,
          ),
        );
        average = ((stats['avg']! / 100) / stats['count']!);
      });
    });

    // Update the last aggregated values
    if (groupedStats.isNotEmpty) {
      String lastGroup = groupedStats.keys.last;
      String avgString = average.toStringAsFixed(2);
      double lastMin = groupedStats[lastGroup]!['min']! / 100;
      double lastMax = groupedStats[lastGroup]!['max']! / 100;
      double lastAvg = double.parse(avgString);

      setState(() {
        lastUpdatedTime = DateTime.parse(lastGroup);
        averageTemp = lastAvg;
        restingTemp = groupedStats[lastGroup]!['latest']! / 100;
        rangeMinTemp = lastMin;
        rangeMaxTemp = lastMax;
      });

      String todayStr = _formatDate(DateTime.now());

      /*if (_formatDate(lastUpdatedTime) == todayStr) {
        setState(() {
          averageTemp = lastAvg;
          restingTemp = groupedStats[lastGroup]!['latest']! / 100;
          rangeMinTemp = lastMin;
          rangeMaxTemp = lastMax;
        });
      }*/

      if (_formatDate(lastUpdatedTime) == todayStr) {
        saveValue(lastUpdatedTime, averageTemp);
      }
    }
  }

  Widget displayValue() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 20,
          width: SizeConfig.blockSizeHorizontal * 44,
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'RANGE',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Wrap(
                    spacing: 10.0, // Space between items
                    children: <Widget>[
                      Text(
                        rangeMinTemp.toString(),
                        style: hPi4Global.moveValueTextStyle,
                      ),
                      Text('-', style: hPi4Global.moveValueTextStyle),
                      Text(
                        rangeMaxTemp.toString(),
                        style: hPi4Global.moveValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        "\u00b0 F",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Column(
          //mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: SizeConfig.blockSizeVertical * 10,
              width: SizeConfig.blockSizeHorizontal * 44,
              child: Card(
                color: Colors.grey[900],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          SizedBox(width: 10.0),
                          Text(
                            averageTemp.toString(),
                            style: hPi4Global.moveValueTextStyle,
                          ),
                          SizedBox(width: 15.0),
                          //Icon(Icons.favorite_border, color: Colors.black),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          SizedBox(width: 10.0),
                          Text(
                            'AVERAGE',
                            style: hPi4Global.movecardSubValueTextStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: SizeConfig.blockSizeVertical * 10,
              width: SizeConfig.blockSizeHorizontal * 44,
              child: Card(
                color: Colors.grey[900],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          SizedBox(width: 10.0),
                          Text(
                            restingTemp.toString(),
                            style: hPi4Global.moveValueTextStyle,
                          ),
                          SizedBox(width: 15.0),
                          //Icon(Icons.favorite_border, color: Colors.black),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          SizedBox(width: 10.0),
                          Text(
                            'Latest',
                            style: hPi4Global.movecardSubValueTextStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget displayCard(String tab) {
      return Card(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: SizeConfig.blockSizeVertical * 45,
                        width: SizeConfig.blockSizeHorizontal * 88,
                        color: Colors.transparent,
                        child: buildChartBlock(),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  displayValue(),
                ],
              ),
            ],
          ),
        ),
      );

  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    //return DefaultTabController(
    //length: 3,
    // child:
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed:
              () => Navigator.of(
                context,
              ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage())),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          //mainAxisSize: MainAxisSize.max,
          children: [
            const Text(
              'Temperature',
              style: TextStyle(
                fontSize: 16,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
            ),
            SizedBox(width: 30.0),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                //color: Colors.grey.shade100,
                color: Colors.grey.shade800,
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: const BoxDecoration(
                  color: hPi4Global.hpi4Color,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white,
                tabs: const [Text('Day'), Text('Week'), Text('Month')],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: NeverScrollableScrollPhysics(),
        children: [
          displayCard("Day"),
          displayCard("Week"),
          displayCard("Month"),
        ],
      ),
      // ),
    );
  }
}

class TempTrends {
  TempTrends(this.date, this.maxTemp, this.minTemp);
  final DateTime date;
  final double maxTemp;
  final double minTemp;
}
