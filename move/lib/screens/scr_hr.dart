import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:move/screens/csvData.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class ScrHR extends StatefulWidget {
  const ScrHR({super.key});
  @override
  State<ScrHR> createState() => _ScrHRState();
}

class _ScrHRState extends State<ScrHR> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    hrDataManager = CsvDataManager<HRTrends>(
      filePrefix: "hr_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int minHR = int.tryParse(row[1]) ?? 0;
        int maxHR = int.tryParse(row[2]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return HRTrends(date, maxHR, minHR);
      },
      getFileType: (file) => "hr",
    );

    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    hrTrendsData = [];
    super.dispose();
  }

  List<HRTrends> hrTrendsData = [];

  void _handleTabChange() {
    setState(() {
      _loadData();
    });
  }

  Future<List<List<dynamic>>> readAllHRDataSorted(List<File> csvFiles) async {
    List<List<dynamic>> allRows = [];

    for (File file in csvFiles) {
      try {
        List<String> lines = await file.readAsLines();
        if (lines.length <= 1) continue; // Skip files with no data rows

        // Skip header, process each data row
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.isEmpty) continue;
          List<String> parts = line.split(',');
          if (parts.length < 5) continue; // Skip incomplete rows

          // Parse timestamp as int for sorting
          int? timestamp = int.tryParse(parts[0]);
          if (timestamp == null) continue;

          // Store as [timestamp, minHR, maxHR, avgHR, latestHR]
          List<dynamic> row = [
            timestamp,
            int.tryParse(parts[1]) ?? 0,
            int.tryParse(parts[2]) ?? 0,
            int.tryParse(parts[3]) ?? 0,
            int.tryParse(parts[4]) ?? 0,
          ];
          allRows.add(row);

          // Debug print for each row conversion
          print('Parsed row from file ${file.path}: $row');
        }
      } catch (e) {
        // Optionally handle file read errors
        print('Error reading file ${file.path}: $e');
        continue;
      }
    }

    // Sort all rows by timestamp (ascending)
    allRows.sort((a, b) => a[0].compareTo(b[0]));

    return allRows;
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
          DateTime.now().day + 1,
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
          if (details.value ==
              DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day + 1,
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
        },
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
          DateTime date = DateTime.fromMillisecondsSinceEpoch(
            details.value.toInt(),
          );

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
          DateTime date = DateTime.fromMillisecondsSinceEpoch(
            details.value.toInt(),
          );

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

 /* Widget customAxis() {
    if (_tabController.index == 0) {
      // 1 to 24 (hours)
      return NumericAxis(
        minimum: 1,
        maximum: 24,
        interval: 6, // Show every 6th hour
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          // Display 24 instead of 0 if needed (not applicable here, but included for parity)
          String labelText = details.value.toInt().toString();
          return ChartAxisLabel(
            labelText,
            TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
        },
      );
    } else if (_tabController.index == 1) {
      // 1 to 7 (days of week)
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return NumericAxis(
        minimum: 1,
        maximum: 7,
        interval: 1,
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          int idx = details.value.toInt() - 1;
          String labelText = (idx >= 0 && idx < days.length) ? days[idx] : details.value.toInt().toString();
          return ChartAxisLabel(
            labelText,
            TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
        },
      );
    } else {
      // 1 to 30 (days of month)
      return NumericAxis(
        minimum: 1,
        maximum: 30,
        interval: 6,
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        axisLabelFormatter: (AxisLabelRenderDetails details) {
          String labelText = details.value.toInt().toString();
          return ChartAxisLabel(
            labelText,
            TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
        },
      );
    }
  }*/

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
                  //minimum: 0,
                  //maximum: 200,
                  //interval: 10,
                  anchorRangeToVisiblePoints: false,
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                palette: <Color>[hPi4Global.hpi4Color],
                series: <CartesianSeries>[
                  HiloSeries<HRTrends, DateTime>(
                    dataSource: hrTrendsData,
                    xValueMapper: (HRTrends data, _) => data.date,
                    lowValueMapper: (HRTrends data, _) => data.minHR,
                    highValueMapper: (HRTrends data, _) => data.maxHR,
                    borderWidth: 7,
                    animationDuration: 0,
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

  // Example usage for HR data:
  late CsvDataManager<HRTrends> hrDataManager;

  Future<void> _loadData() async {
    List<HRTrends> data = await hrDataManager.getDataObjects();
    if (data.isEmpty) {
      print('No valid HR data found in CSV files.');
      return;
    }

    setState(() {
      hrTrendsData = data;
    });

    DateTime today = DateTime.now();

    if(_tabController.index == 0){
      // Get the hourly HR trends for today
      List<HourlyTrend> hourlyHRTrends =
      await hrDataManager.getHourlyTrendForToday();
      for (var trend in hourlyHRTrends) {

        print(
          'Hour: ${trend.hour}, Min HR: ${trend.min}, Max HR: ${trend.max}, Avg HR: ${trend.avg}',
        );
      }

      // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> dailyStats = await hrDataManager.getDailyStatistics(
        today,
      );

      print('Daily Stats: $dailyStats');

    }else if(_tabController.index == 1){
      // Get the weekly HR trends for the current week

      List<WeeklyTrend> weeklyHRTrends = await hrDataManager.getWeeklyTrend(
        today,
      );
      for (var trend in weeklyHRTrends) {
        setState((){
          hrTrendsData.add(
            HRTrends(
              trend.date,
              trend.max.toInt(),
              trend.max.toInt(),
            ),
          );
        });

        print(
          'Date: ${trend.date}, Min HR: ${trend.min}, Max HR: ${trend.max}, Avg HR: ${trend.avg}',
        );

      }

      Map<String, double> weeklyStats = await hrDataManager.getWeeklyStatistics(
        today,
      );



      print('Weekly Stats: $weeklyStats');

    }else if(_tabController.index == 2){
      // Get the monthly HR trends for the current month
      List<MonthlyTrend> monthlyHRTrends = await hrDataManager.getMonthlyTrend(
        today,
      );
      for (var trend in monthlyHRTrends) {
        print(
          'Date: ${trend.date.day}, Min HR: ${trend.min}, Max HR: ${trend.max}, Avg HR: ${trend.avg}',
        );
      }

      Map<String, double> monthlyStats = await hrDataManager.getMonthlyStatistics(
        today,
      );

      print('Monthly Stats: $monthlyStats');
    }


  }

  // Save a value
  saveValue(DateTime lastUpdatedTime, int averageHR) async {
    String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestHR', averageHR.toString());
    await prefs.setString('lastUpdatedHR', lastDateTime);
  }

  Widget displayValues() {
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
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        (rangeMinHR.toString() == "0")
                            ? "--"
                            : rangeMinHR.toString(),
                        style: hPi4Global.moveValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                      Text('-', style: hPi4Global.moveValueTextStyle),
                      SizedBox(width: 10.0),
                      Text(
                        (rangeMaxHR.toString() == "0")
                            ? "--"
                            : rangeMaxHR.toString(),
                        style: hPi4Global.moveValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('BPM', style: hPi4Global.movecardSubValueTextStyle),
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
                            (averageHR.toString() == "0")
                                ? "--"
                                : averageHR.toString(),
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
                            (restingHR.toString() == "0")
                                ? "--"
                                : restingHR.toString(),
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
                displayValues(),
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
              'Heart Rate',
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
                tabs: const [Text('Today'), Text('Week'), Text('Month')],
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

class HRTrends {
  HRTrends(this.date, this.maxHR, this.minHR);
  final DateTime date;
  final int maxHR;
  final int minHR;
}
