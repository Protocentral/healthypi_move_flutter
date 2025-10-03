import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/trends_data_manager.dart';
import 'package:move/screens/showTrendsAlert.dart';
import 'package:url_launcher/url_launcher.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';

class ScrBPT extends StatefulWidget {
  const ScrBPT({super.key});
  @override
  State<ScrBPT> createState() => _ScrBPTState();
}

class _ScrBPTState extends State<ScrBPT> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> timestampSys = [];
  List<String> minSys = [];
  List<String> maxSys = [];
  List<String> avgSys = [];

  int rangeMinSys = 0;
  int rangeMaxSys = 0;
  int averageSys = 0;
  late DateTime lastUpdatedTime;

  List<String> timestampDia = [];
  List<String> minDia = [];
  List<String> maxDia = [];
  List<String> avgDia = [];

  int rangeMinDia = 0;
  int rangeMaxDia = 0;
  int averageDia = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    // Initialize SQLite data manager for blood pressure trends (uses HR data)
    dataManager = TrendsDataManager(hPi4Global.PREFIX_HR);

    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    BPTTrendsData = [];
    super.dispose();
  }

  List<BPTTrends> BPTTrendsData = [];

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
        // Display 7-day range including today (last 6 days + today)
        minimum: DateTime.now().subtract(Duration(days: 6)), // Start of 7-day range
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
      final now = DateTime.now();
      return DateTimeAxis(
        // Display current calendar month
        minimum: DateTime(now.year, now.month, 1), // First day of current month
        maximum: now, // Today
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

  double borderWidth() {
    if (_tabController.index == 0) {
      return 7;
    } else if (_tabController.index == 1) {
      return 20;
    } else {
      return 7;
    }
  }

  Widget buildChartBlock() {
    String periodText = "";
    if (_tabController.index == 0) {
      periodText = "today";
    } else if (_tabController.index == 1) {
      periodText = "this week";
    } else {
      periodText = "this month";
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: const Color(0xFF2D2D2D),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: BPTTrendsData.isEmpty
                  ? Center(
                child: Text(
                  "No data available for $periodText",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
                  : SfCartesianChart(
                plotAreaBorderWidth: 0,
                primaryXAxis: dateTimeAxis(),
                primaryYAxis: NumericAxis(
                  majorGridLines: MajorGridLines(width: 0.05),
                  anchorRangeToVisiblePoints: true,
                  rangePadding: ChartRangePadding.auto,
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
               // palette: <Color>[hPi4Global.hpi4Color],
                series: <CartesianSeries>[
                  ColumnSeries<BPTTrends, DateTime>(
                    dataSource: BPTTrendsData,
                    color: hPi4Global.hpi4Color, // Set color for the first line
                    xValueMapper: (BPTTrends data, _) => data.date,
                    yValueMapper: (BPTTrends data, _) => data.minHR,
                    borderWidth: borderWidth(),
                    animationDuration: 0,
                  ),
                  ColumnSeries<BPTTrends, DateTime>(
                    dataSource: BPTTrendsData,
                    color: Colors.blue, // Set color for the first line
                    xValueMapper: (BPTTrends data, _) => data.date,
                    yValueMapper: (BPTTrends data, _) => data.maxHR,
                    borderWidth: borderWidth(),
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

  // SQLite data manager for blood pressure trends (uses HR data)
  late TrendsDataManager dataManager;

  Future<void> _loadData() async {
    if (_tabController.index == 0) {
      // Get the hourly trends for today
      List<HourlyTrend> hourlyTrends = await dataManager.getHourlyTrendForToday();
      
      // Compute statistics inline from aggregated data
      int minVal = double.maxFinite.toInt();
      int maxVal = 0;
      int sumAvg = 0;
      
      BPTTrendsData = [];
      for (var trend in hourlyTrends) {
        BPTTrendsData.add(
          BPTTrends(trend.hour, trend.max.toInt(), trend.min.toInt()),
        );
        
        if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
        if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
        sumAvg += trend.avg.toInt();
        
        print(
          'Hour: ${trend.hour}, Min: ${trend.min}, Max: ${trend.max}, Avg: ${trend.avg}',
        );
      }

      setState(() {
        rangeMinSys = hourlyTrends.isEmpty ? 0 : minVal;
        rangeMaxSys = hourlyTrends.isEmpty ? 0 : maxVal;
        averageSys = hourlyTrends.isEmpty ? 0 : (sumAvg / hourlyTrends.length).round();
      });

      print('Daily Stats - Min: $minVal, Max: $maxVal, Avg: $averageSys');
    } else if (_tabController.index == 1) {
      // Get the weekly trends for the current week
      List<WeeklyTrend> weeklyTrends = await dataManager.getWeeklyTrends();
      
      // Compute statistics inline from aggregated data
      int minVal = double.maxFinite.toInt();
      int maxVal = 0;
      int sumAvg = 0;
      
      BPTTrendsData = [];
      for (var trend in weeklyTrends) {
        BPTTrendsData.add(
          BPTTrends(trend.date, trend.max.toInt(), trend.min.toInt()),
        );
        
        if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
        if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
        sumAvg += trend.avg.toInt();

        print(
          'Date: ${trend.date}, Min: ${trend.min}, Max: ${trend.max}, Avg: ${trend.avg}',
        );
      }

      setState(() {
        rangeMinSys = weeklyTrends.isEmpty ? 0 : minVal;
        rangeMaxSys = weeklyTrends.isEmpty ? 0 : maxVal;
        averageSys = weeklyTrends.isEmpty ? 0 : (sumAvg / weeklyTrends.length).round();
      });

      print('Weekly Stats - Min: $minVal, Max: $maxVal, Avg: $averageSys');
    } else if (_tabController.index == 2) {
      // Get the monthly trends for the current month
      List<MonthlyTrend> monthlyTrends = await dataManager.getMonthlyTrends();
      
      // Compute statistics inline from aggregated data
      int minVal = double.maxFinite.toInt();
      int maxVal = 0;
      int sumAvg = 0;
      
      BPTTrendsData = [];
      for (var trend in monthlyTrends) {
        BPTTrendsData.add(
          BPTTrends(
            trend.date,
            trend.max.toInt(),
            trend.min.toInt(),
          ),
        );
        
        if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
        if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
        sumAvg += trend.avg.toInt();

        print(
          'Date: ${trend.date.day}, Min: ${trend.min}, Max: ${trend.max}, Avg: ${trend.avg}',
        );
      }

      setState(() {
        rangeMinSys = monthlyTrends.isEmpty ? 0 : minVal;
        rangeMaxSys = monthlyTrends.isEmpty ? 0 : maxVal;
        averageSys = monthlyTrends.isEmpty ? 0 : (sumAvg / monthlyTrends.length).round();
      });

      print('Monthly Stats - Min: $minVal, Max: $maxVal, Avg: $averageSys');
    }
  }

  Widget displayRangeValues() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 13,
          width: SizeConfig.blockSizeHorizontal * 88,
          child: Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Column(
                        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text("Minimum", style: hPi4Global.movecardSubValueTextStyle,),
                            Row(
                                children: <Widget>[
                                  Text((rangeMinSys.toString() == "0")
                                      ? "--"
                                      : rangeMinSys.toString(),
                                    style: hPi4Global.moveValueGreenTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('bpm', style: hPi4Global.movecardSubValueGreenTextStyle),
                                ]
                            ),

                          ]
                      ),
                      Column(
                        //mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text("Average", style: hPi4Global.movecardSubValueTextStyle,),
                            Row(
                                children: <Widget>[
                                  Text(
                                    (averageSys.toString() == "0")
                                        ? "--"
                                        : averageSys.toString(),
                                    style: hPi4Global.moveValueOrangeTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('bpm', style: hPi4Global.movecardSubValueOrangeTextStyle),
                                ]
                            ),
                          ]
                      ),
                      Column(
                        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text("Maximum", style: hPi4Global.movecardSubValueTextStyle,),
                            Row(
                                children: <Widget>[
                                  Text(
                                    (rangeMaxSys.toString() == "0")
                                        ? "--"
                                        : rangeMaxSys.toString(),
                                    style: hPi4Global.moveValueBlueTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('bpm', style: hPi4Global.movecardSubValueBlueTextStyle),
                                ]
                            ),

                          ]
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget displayAboutValues() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 30,
          width: SizeConfig.blockSizeHorizontal * 88,
          child: Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text("About Heart Rate",
                        style: hPi4Global.moveValueTextStyle,
                      ),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          "Heart rate is measured using optical PPG sensors on the wrist. "
                              "The values shown reflect pulse rate and are for general information and personal insight only.",
                          style:
                          hPi4Global.movecardSubValue1TextStyle,
                          textAlign: TextAlign.justify,
                        ),
                      ),
                    ],
                  ),
                  // SizedBox(height: 5.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Text('Learn more at', style: hPi4Global.movecardSubValue1TextStyle),
                      TextButton(
                        onPressed: () {
                          launchURL('https://www.health.harvard.edu/heart-health/all-about-your-heart-rate');
                        },
                        child: Text('Harvard Health', style:TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                        )),
                      )
                    ],
                  ),

                  displayValuesAlert(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget displayCard(String title) {
    return SingleChildScrollView(
      child: Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: SizeConfig.blockSizeVertical * 35,
                        width: SizeConfig.blockSizeHorizontal * 88,
                        color: Colors.transparent,
                        child: buildChartBlock(),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  displayRangeValues(),
                  SizedBox(height: 20),
                  displayAboutValues(),
                  SizedBox(height: 10),
                  //displayValuesAlert(),
                ],
              ),
            ],
          ),
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
              'BPT',
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

class BPTTrends {
  BPTTrends(this.date, this.maxHR, this.minHR);
  final DateTime date;
  final int maxHR;
  final int minHR;
}
