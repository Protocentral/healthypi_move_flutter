import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart' as rs;
import '../globals.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'csvData.dart';

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

    activityDataManager = CsvDataManager<ActivityTrends>(
      filePrefix: "activity_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int count = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return ActivityTrends(date, count);
      },
      getFileType: (file) => "activity",
    );

    _loadData();
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
      _loadData();
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

  double borderWidth(){
    if (_tabController.index == 0){
      return 7;
    }else if(_tabController.index == 1){
      return 20;
    }else{
      return 7;
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
                      lowValueMapper: (ActivityTrends data, _) => 0,
                      highValueMapper: (ActivityTrends data, _) => data.count,
                      borderWidth: borderWidth(),
                      animationDuration: 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }

  // Example usage for HR data:
  late CsvDataManager<ActivityTrends> activityDataManager;

  Future<void> _loadData() async {
    List<ActivityTrends> data = await activityDataManager.getDataObjects();
    if (data.isEmpty) {
      print('No valid Activity data found in CSV files.');
      return;
    }

    DateTime today = DateTime.now();

    if(_tabController.index == 0){
      // Get the hourly HR trends for today
      ActivityTrendsData = [];
      List<ActivityDailyTrend> activityDailyTrend =
      await activityDataManager.getActivityDailyTrend(today);
      for (var trend in activityDailyTrend) {

        setState((){
          ActivityTrendsData.add(
            ActivityTrends(
              trend.date,
              trend.steps,
            ),
          );
        });
        print(
          'Hour: ${trend.date}, Step: ${trend.steps}',
        );
      }

     /* // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> dailyStats = await activityDataManager.getDailyStatistics(
        today,
      );

      setState((){
        rangeMinHR = dailyStats['min']!.toInt();
        rangeMaxHR = dailyStats['max']!.toInt();
        averageHR = dailyStats['avg']!.toInt();
      });

      print('Daily Stats: $dailyStats');*/

    }else if(_tabController.index == 1){
      // Get the weekly HR trends for the current week
      ActivityTrendsData = [];
      List<ActivityWeeklyTrend> activityWeeklyTrend =
      await activityDataManager.getActivityWeeklyTrend(today);
      for (var trend in activityWeeklyTrend) {

        setState((){
          ActivityTrendsData.add(
            ActivityTrends(
              trend.date,
              trend.steps,
            ),
          );
        });
        print(
          'week: ${trend.date}, Step: ${trend.steps}',
        );
      }

      /*Map<String, double> weeklyStats = await activityDataManager.getWeeklyStatistics(
        today,
      );

      setState((){
        rangeMinHR = weeklyStats['min']!.toInt();
        rangeMaxHR = weeklyStats['max']!.toInt();
        averageHR = weeklyStats['avg']!.toInt();
      });

      print('Weekly Stats: $weeklyStats');*/

    }else if(_tabController.index == 2) {
      // Get the monthly HR trends for the current month
      ActivityTrendsData = [];
      List<ActivityMonthlyTrend> activityMonthlyTrend =
      await activityDataManager.getActivityMonthlyTrend(today);
      for (var trend in activityMonthlyTrend) {

        setState((){
          ActivityTrendsData.add(
            ActivityTrends(
              trend.date,
              trend.steps,
            ),
          );
        });
        print(
          'Month: ${trend.date}, Step: ${trend.steps}',
        );
      }
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
  ActivityTrends(this.date,this.count);
  final DateTime date;
  final int count;
}
