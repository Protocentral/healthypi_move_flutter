import 'package:flutter/material.dart';
import 'package:move/screens/showTrendsAlert.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'csvData.dart';

class ScrSPO2 extends StatefulWidget {
  const ScrSPO2({super.key});
  @override
  State<ScrSPO2> createState() => _ScrSPO2State();
}

class _ScrSPO2State extends State<ScrSPO2> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String> timestamp = [];
  List<String> minSpo2 = [];
  List<String> maxSpo2 = [];
  List<String> avgSpo2 = [];
  List<String> latestSpo2 = [];

  int restingSpo2 = 0;
  int rangeMinSpo2 = 0;
  int rangeMaxSpo2 = 0;
  int averageSpo2 = 0;
  late DateTime lastUpdatedTime;

  List<Spo2Trends> Spo2TrendsData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    spo2DataManager = CsvDataManager<Spo2Trends>(
      filePrefix: "spo2_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int spo2 = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return Spo2Trends(date, spo2, 0);
      },
      getFileType: (file) => "spo2",
    );

    _loadData();
  }

  @override
  void dispose() {
    Spo2TrendsData = [];
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
          color: Colors.grey,
          fontSize: 12,
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
              color: Colors.grey,
              fontSize: 12,
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
          color: Colors.grey,
          fontSize: 12,
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
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            );
          }
          // Otherwise, use the default label
          return ChartAxisLabel(
            details.text,
            TextStyle(
              color: Colors.grey,
              fontSize: 12,
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
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            );
          }
          // Otherwise, use the default label
          return ChartAxisLabel(
            details.text,
            TextStyle(
              color: Colors.grey,
              fontSize: 12,
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
              child: Spo2TrendsData.isEmpty 
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
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x : point.high',
                  textStyle: TextStyle(color: Colors.white, fontSize: 12),
                  color: Colors.black87,
                  borderColor: Colors.grey,
                  borderWidth: 1,
                ),
                trackballBehavior: TrackballBehavior(
                  enable: true,
                  activationMode: ActivationMode.singleTap,
                  tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
                  //tooltipDisplayMode: TrackballDisplayMode.nearestPoint
                ),
                    primaryXAxis: dateTimeAxis(),
                    primaryYAxis: NumericAxis(
                      majorGridLines: MajorGridLines(width: 0.05),
                      anchorRangeToVisiblePoints: true,
                      rangePadding: ChartRangePadding.auto,
                      labelStyle: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    palette: <Color>[hPi4Global.hpi4Color],
                    series: <CartesianSeries>[
                      // Use LineSeries for single values and HiloSeries for ranges
                      ...Spo2TrendsData.any((data) => data.minSpo2 != data.maxSpo2)
                          ? [
                              HiloSeries<Spo2Trends, DateTime>(
                                dataSource: Spo2TrendsData.where((data) => data.minSpo2 != data.maxSpo2).toList(),
                                xValueMapper: (Spo2Trends data, _) => data.date,
                                lowValueMapper: (Spo2Trends data, _) => data.minSpo2,
                                highValueMapper: (Spo2Trends data, _) => data.maxSpo2,
                                borderWidth: borderWidth(),
                                animationDuration: 0,
                              ),
                            ]
                          : [],
                      // Add scatter series for points where min == max
                      ...Spo2TrendsData.any((data) => data.minSpo2 == data.maxSpo2)
                          ? [
                              ScatterSeries<Spo2Trends, DateTime>(
                                dataSource: Spo2TrendsData.where((data) => data.minSpo2 == data.maxSpo2).toList(),
                                xValueMapper: (Spo2Trends data, _) => data.date,
                                yValueMapper: (Spo2Trends data, _) => data.maxSpo2,
                                markerSettings: MarkerSettings(
                                  isVisible: true,
                                  width: borderWidth(),
                                  height: borderWidth(),
                                  shape: DataMarkerType.circle,
                                ),
                                animationDuration: 0,
                              ),
                            ]
                          : [],
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Example usage for HR data:
  late CsvDataManager<Spo2Trends> spo2DataManager;

  Future<void> _loadData() async {
    List<Spo2Trends> data = await spo2DataManager.getDataObjects();
    if (data.isEmpty) {
      print('No valid HR data found in CSV files.');
      return;
    }

    DateTime today = DateTime.now();

    if (_tabController.index == 0) {
      // Get the hourly HR trends for today
      Spo2TrendsData = [];
      List<SpO2DailyTrend> hourlySpo2Trends = await spo2DataManager
          .getSpO2DailyTrend(today);
      for (var trend in hourlySpo2Trends) {
        setState(() {
          Spo2TrendsData.add(
            Spo2Trends(trend.date, trend.max.toInt(), trend.min.toInt()),
          );
        });
        print(
          'Hour: ${trend.date}, Min HR: ${trend.min}, Max HR: ${trend.max}, Avg HR: ${trend.avg}',
        );
      }

      // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> dailyStats = await spo2DataManager
          .getSpO2DailyStatistics(today);

      setState(() {
        rangeMinSpo2 = dailyStats['min']!.toInt();
        rangeMaxSpo2 = dailyStats['max']!.toInt();
        averageSpo2 = dailyStats['avg']!.toInt();
      });

      print('Daily Stats: $dailyStats');
    } else if (_tabController.index == 1) {
      // Get the weekly HR trends for the current week
      Spo2TrendsData = [];
      List<SpO2WeeklyTrend> weeklySpo2Trends = await spo2DataManager
          .getSpO2WeeklyTrend(today);
      for (var trend in weeklySpo2Trends) {
        setState(() {
          Spo2TrendsData.add(
            Spo2Trends(trend.date, trend.max.toInt(), trend.min.toInt()),
          );
        });

        print(
          'Date: ${trend.date}, Min: ${trend.min}, Max: ${trend.max}, Avg : ${trend.avg}',
        );
      }
      // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> weeklyStats = await spo2DataManager
          .getSpO2WeeklyStatistics(today);

      setState(() {
        rangeMinSpo2 = weeklyStats['min']!.toInt();
        rangeMaxSpo2 = weeklyStats['max']!.toInt();
        averageSpo2 = weeklyStats['avg']!.toInt();
      });

      print('Daily Stats: $weeklyStats');
    } else if (_tabController.index == 2) {
      // Get the monthly HR trends for the current month
      Spo2TrendsData = [];
      List<SpO2MonthlyTrend> monthlySpo2Trends = await spo2DataManager
          .getSpO2MonthlyTrend(today);
      for (var trend in monthlySpo2Trends) {
        setState(() {
          Spo2TrendsData.add(
            Spo2Trends(trend.date, trend.max.toInt(), trend.min.toInt()),
          );
        });

        print(
          'Date: ${trend.date.day}, Min: ${trend.min}, Max: ${trend.max}, Avg: ${trend.avg}',
        );
      }

      // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> monthlyStats = await spo2DataManager
          .getSpO2MonthlyStatistics(today);

      setState(() {
        rangeMinSpo2 = monthlyStats['min']!.toInt();
        rangeMaxSpo2 = monthlyStats['max']!.toInt();
        averageSpo2 = monthlyStats['avg']!.toInt();
      });

      print('Daily Stats: $monthlyStats');
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
                          Text(
                            "Minimum",
                            style: hPi4Global.movecardSubValueTextStyle,
                          ),
                          Row(
                            children: <Widget>[
                              Text(
                                (rangeMinSpo2.toString() == "0")
                                    ? "--"
                                    : rangeMinSpo2.toString(),
                                style: hPi4Global.moveValueGreenTextStyle,
                              ),
                              SizedBox(width: 5.0),
                              Text(
                                '%',
                                style:
                                    hPi4Global.movecardSubValueGreenTextStyle,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        //mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            "Average",
                            style: hPi4Global.movecardSubValueTextStyle,
                          ),
                          Row(
                            children: <Widget>[
                              Text(
                                (averageSpo2.toString() == "0")
                                    ? "--"
                                    : averageSpo2.toString(),
                                style: hPi4Global.moveValueOrangeTextStyle,
                              ),
                              SizedBox(width: 5.0),
                              Text(
                                '%',
                                style:
                                    hPi4Global.movecardSubValueOrangeTextStyle,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        //mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            "Maximum",
                            style: hPi4Global.movecardSubValueTextStyle,
                          ),
                          Row(
                            children: <Widget>[
                              Text(
                                (rangeMaxSpo2.toString() == "0")
                                    ? "--"
                                    : rangeMaxSpo2.toString(),
                                style: hPi4Global.moveValueBlueTextStyle,
                              ),
                              SizedBox(width: 5.0),
                              Text(
                                '%',
                                style: hPi4Global.movecardSubValueBlueTextStyle,
                              ),
                            ],
                          ),
                        ],
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
          height: SizeConfig.blockSizeVertical * 28,
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
                      Text("About SpO2", style: hPi4Global.moveValueTextStyle),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          "SpO2 is estimated from optical sensors and represents the percentage of oxygen carried by your red blood cells."
                          " Values may be influenced by motion, light interference, or sensor placement. ",
                          style: hPi4Global.movecardSubValue1TextStyle,
                          textAlign: TextAlign.justify,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Learn more at',
                        style: hPi4Global.movecardSubValue1TextStyle,
                      ),
                      TextButton(
                        onPressed: () {
                          launchURL("https://www.yalemedicine.org/conditions/pulse-oximetry");
                        },
                        child: Text(
                          'Yale Medicine',
                          style: TextStyle(fontSize: 14, color: Colors.blue),
                        ),
                      ),
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
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: SizeConfig.blockSizeVertical * 30,
                        width: SizeConfig.blockSizeHorizontal * 88,
                        color: Colors.transparent,
                        child: buildChartBlock(),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  displayRangeValues(),
                  SizedBox(height: 10),
                  displayAboutValues(),
                  SizedBox(height: 10),
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
              'Spo2',
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

class Spo2Trends {
  Spo2Trends(this.date, this.maxSpo2, this.minSpo2);
  final DateTime date;
  final int maxSpo2;
  final int minSpo2;
}
