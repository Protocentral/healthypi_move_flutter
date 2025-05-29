import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart' as rs;
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';

class ScrActivity extends StatefulWidget {
  const ScrActivity({super.key});
  @override
  State<ScrActivity> createState() => _ScrActivityState();
}
class _ScrActivityState extends State<ScrActivity>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<String> timestamp = [];

  int totalCount = 0;
  int Count = 0;
  late DateTime lastUpdatedTime;

  List<ActivityTrends> ActivityTrendsData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _listCSVFiles();
  }

  @override
  void dispose() {
    ActivityTrendsData = [];
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
            DateTime.now().day+1,
            0,
            0,
            0,
          ),
          //DateTime.now(), // End value of the range slider
          interval: 6,
          intervalType: DateTimeIntervalType.hours,
          dateFormat: DateFormat.H(),
          majorGridLines: MajorGridLines(width: 0),
          labelStyle: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          axisLabelFormatter: (AxisLabelRenderDetails details) {
            // Replace "0" (midnight) with "24"
            String labelText = details.text;
            if (details.value == DateTime(
              DateTime
                  .now()
                  .year,
              DateTime
                  .now()
                  .month,
              DateTime
                  .now()
                  .day + 1,
              0,
              0,
              0,
            ).millisecondsSinceEpoch.toDouble()) {
              labelText = '24';
            }
            return ChartAxisLabel(
              labelText,
              TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            );
          }
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
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          // Convert the DateTime value from the axis to a readable format
          DateTime date = DateTime.fromMillisecondsSinceEpoch(details.value.toInt());

          // Check if the date is today's date
          if (date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day) {
            return ChartAxisLabel(
              'Today',
              TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            );
          }
          // Otherwise, use the default label
          return ChartAxisLabel(
            details.text,
            TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
        },
      );
    } else {
      return DateTimeAxis(
        // Display a month-long range dynamically based on slider values
        minimum: DateTime.now().subtract(Duration(days: 30)), // 30 days ago
        maximum: DateTime.now(), // Today
        interval: 6,
        intervalType: DateTimeIntervalType.days,
        dateFormat: DateFormat('dd'), // Show day, month, and hour
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          // Convert the DateTime value from the axis to a readable format
          DateTime date = DateTime.fromMillisecondsSinceEpoch(details.value.toInt());

          // Check if the date is today's date
          if (date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day) {
            return ChartAxisLabel(
              'Today',
              TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            );
          }
          // Otherwise, use the default label
          return ChartAxisLabel(
            details.text,
            TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
        },
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
                  primaryXAxis:  dateTimeAxis(),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(width: 0.05),
                    //minimum: 0,
                    //maximum: ,
                   // interval: 1000,
                    anchorRangeToVisiblePoints: false,
                    labelStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  palette: <Color>[
                    hPi4Global.hpi4Color,
                  ],
                  series: <CartesianSeries>[
                    HiloSeries<ActivityTrends, DateTime>(
                      dataSource: ActivityTrendsData,
                      xValueMapper: (ActivityTrends data, _) => data.date,
                      lowValueMapper: (ActivityTrends data, _) => data.min,
                      highValueMapper: (ActivityTrends data, _) => data.count,
                      borderWidth: 7,
                      animationDuration: 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
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
      return 'No second line';
    } catch (e) {
      return 'Error reading file: $e';
    }
  }

  Future<void> _listCSVFiles() async {
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

          if (_tabController.index == 0) {
            // Group by every hour for the day
            String todayStr = _formatDate(now);
            if (_formatDate(timestampDateTime) == todayStr) {
              await processFileData(
                fileNames: [fileName1],
                groupingFormat: "yyyy-MM-dd HH:00:00", // Group by hour
              );
            }
          } else if (_tabController.index == 1) {
            // Group by every day for the week
            DateTime weekStart = now.subtract(Duration(days: 7));
            if (timestampDateTime.isAfter(weekStart) &&
                timestampDateTime.isBefore(now)) {
              await processFileData(
                fileNames: [fileName1],
                groupingFormat: "yyyy-MM-dd", // Group by day
              );
            }
          } else if (_tabController.index == 2) {
            // Group by every day for the month
            DateTime monthStart = now.subtract(Duration(days: 30));
            if (timestampDateTime.isAfter(monthStart) &&
                timestampDateTime.isBefore(now)) {
              await processFileData(
                fileNames: [fileName1],
                groupingFormat: "yyyy-MM-dd", // Group by day
              );
            }
          }
        }
      }
    }
  }
// Save the last updated values
  saveValue(DateTime lastUpdatedTime, int Count) async {
    String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestActivityCount', Count.toString());
    await prefs.setString('lastUpdatedActivity', lastDateTime);
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
            setState(() {
             Count = groupedStats[groupKey]!['count']!;
            });
          }
        }
      }
    }
    double average = 0;
    // Process the grouped stats and update the UI
    groupedStats.forEach((group, stats) {
      DateTime formattedDateTime = DateTime.parse(group);
      setState(() {
        ActivityTrendsData.add(ActivityTrends(formattedDateTime,0,stats['count']!),);
      });
     // print(" $group, Count: $stats");

    });

    // Update the last aggregated values
    if (groupedStats.isNotEmpty) {
      String lastGroup = groupedStats.keys.last;

      setState(() {
        lastUpdatedTime = DateTime.parse(lastGroup);
        Count = groupedStats[lastGroup]!['count']!;
      });
      saveValue(lastUpdatedTime, Count);
    }
  }

  Widget displayValue(){
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 18,
          width: SizeConfig.blockSizeHorizontal * 88,
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('Total',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        //Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                    SizedBox(
                      height: 20.0,
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text((Count.toString()=="0")? "--":Count.toString(),
                            style: hPi4Global.moveValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                        SizedBox(
                          width: 10.0,
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text("steps",
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        //Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                  ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget displayCard(String tab){
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
                        color:Colors.transparent,
                        child:buildChartBlock(),
                      )
                    ],
                  ),
                  SizedBox(height:20),
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
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()))
        ),
        title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            //mainAxisSize: MainAxisSize.max,
            children: [
              const Text(
                'Activity',
                style: TextStyle(fontSize: 16, color:hPi4Global.hpi4AppBarIconsColor),
              ),
              SizedBox(width:30.0),
            ]
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
                tabs: const [
                  Text('Today'),
                  Text('Week'),
                  Text('Month')
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: NeverScrollableScrollPhysics(),
        children: [
          displayCard("Today"),
          displayCard("Week"),
          displayCard("Month"),
        ],
      ),
      // ),
    );
  }

}


class ActivityTrends {
  ActivityTrends(this.date,this.min,this.count);
  final DateTime date;
  final int min;
  final int count;
}
