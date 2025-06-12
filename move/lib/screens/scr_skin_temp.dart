import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:move/screens/showTrendsAlert.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../globals.dart';
import 'package:intl/intl.dart';

import 'csvData.dart';

class ScrSkinTemperature extends StatefulWidget {
  const ScrSkinTemperature({super.key});
  @override
  State<ScrSkinTemperature> createState() => _ScrSkinTemperatureState();
}

class _ScrSkinTemperatureState extends State<ScrSkinTemperature>
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

    tempDataManager = CsvDataManager<TempTrends>(
      filePrefix: "temp_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int minTemp = int.tryParse(row[1]) ?? 0;
        int maxTemp = int.tryParse(row[2]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return TempTrends(date, minTemp.toDouble(), maxTemp.toDouble());
      },
      getFileType: (file) => "temp",
    );

    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    TempTrendsData = [];
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        color: Colors.grey[900],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TempTrendsData.isEmpty 
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
                    palette: <Color>[hPi4Global.hpi4Color],
                    series: <CartesianSeries>[
                      HiloSeries<TempTrends, DateTime>(
                        dataSource: TempTrendsData,
                        xValueMapper: (TempTrends data, _) => data.date,
                        lowValueMapper: (TempTrends data, _) => data.minTemp/100,
                        highValueMapper: (TempTrends data, _) => data.maxTemp/100,
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

  double floorToOneDecimal(double value) {
    return (value * 10).floor() / 10;
  }

  // Example usage for HR data:
  late CsvDataManager<TempTrends> tempDataManager;

  Future<void> _loadData() async {
    List<TempTrends> data = await tempDataManager.getDataObjects();
    if (data.isEmpty) {
      print('No valid HR data found in CSV files.');
      return;
    }

    DateTime today = DateTime.now();

    if(_tabController.index == 0){
      // Get the hourly HR trends for today
      TempTrendsData = [];
      List<HourlyTrend> hourlyHRTrends =
      await tempDataManager.getHourlyTrendForToday();
      for (var trend in hourlyHRTrends) {

        setState((){
          TempTrendsData.add(
            TempTrends(
              trend.hour,
              trend.max.toDouble(),
              trend.min.toDouble(),
            ),
          );
        });
        print(
          'Hour: ${trend.hour}, Min Temp: ${trend.min}, Max Temp: ${trend.max}, Avg Temp: ${trend.avg}',
        );
      }

      // Call functions to get the weekly, hourly, and monthly min, max and average statistics
      Map<String, double> dailyStats = await tempDataManager.getDailyStatistics(
        today,
      );

      setState((){
        rangeMinTemp = floorToOneDecimal(dailyStats['min']!/100.toDouble());
        rangeMaxTemp = floorToOneDecimal(dailyStats['max']!/100.toDouble());
        averageTemp = floorToOneDecimal(dailyStats['avg']!/100.toDouble());
      });

      print('Daily Stats: $dailyStats');

    }else if(_tabController.index == 1){
      // Get the weekly HR trends for the current week
      TempTrendsData = [];
      List<WeeklyTrend> weeklyHRTrends = await tempDataManager.getWeeklyTrend(
        today,
      );
      for (var trend in weeklyHRTrends) {
        setState((){
          TempTrendsData.add(
            TempTrends(
              trend.date,
              trend.max.toDouble(),
              trend.min.toDouble(),
            ),
          );
        });

        print(
          'Date: ${trend.date}, Min Temp: ${trend.min}, Max Temp: ${trend.max}, Avg Temp: ${trend.avg}',
        );

      }

      Map<String, double> weeklyStats = await tempDataManager.getWeeklyStatistics(
        today,
      );

      setState((){
        rangeMinTemp = floorToOneDecimal(weeklyStats['min']!/100.toDouble());
        rangeMaxTemp = floorToOneDecimal(weeklyStats['max']!/100.toDouble());
        averageTemp = floorToOneDecimal(weeklyStats['avg']!/100.toDouble());
      });

      print('Weekly Stats: $weeklyStats');

    }else if(_tabController.index == 2){
      // Get the monthly HR trends for the current month
      TempTrendsData = [];
      List<MonthlyTrend> monthlyHRTrends = await tempDataManager.getMonthlyTrend(
        today,
      );
      for (var trend in monthlyHRTrends) {

        setState((){
          TempTrendsData.add(
            TempTrends(
              trend.date,
              trend.max.toDouble(),
              trend.min.toDouble(),
            ),
          );
        });

        print(
          'Date: ${trend.date.day}, Min Temp: ${trend.min}, Max Temp: ${trend.max}, Avg Temp: ${trend.avg}',
        );
      }

      Map<String, double> monthlyStats = await tempDataManager.getMonthlyStatistics(
        today,
      );

      setState((){
        rangeMinTemp =  floorToOneDecimal(monthlyStats['min']!/100.toDouble());
        rangeMaxTemp =  floorToOneDecimal(monthlyStats['max']!/100.toDouble());
        averageTemp =  floorToOneDecimal(monthlyStats['avg']!/100.toDouble());
      });
      print('Monthly Stats: $monthlyStats');
    }

  }

  Widget displayRangeValues() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 12,
          width: SizeConfig.blockSizeHorizontal * 88,
          child: Card(
            color: Colors.grey[900],
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
                                  Text((rangeMinTemp.toString() == "0")
                                      ? "--"
                                      : rangeMinTemp.toString(),
                                    style: hPi4Global.moveValueGreenTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('\u00b0 F', style: hPi4Global.movecardSubValueGreenTextStyle),
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
                                    (averageTemp.toString() == "0")
                                        ? "--"
                                        : averageTemp.toString(),
                                    style: hPi4Global.moveValueOrangeTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('\u00b0 F', style: hPi4Global.movecardSubValueOrangeTextStyle),
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
                                    (rangeMaxTemp.toString() == "0")
                                        ? "--"
                                        : rangeMaxTemp.toString(),
                                    style: hPi4Global.moveValueBlueTextStyle,
                                  ),
                                  SizedBox(width: 5.0),
                                  Text('\u00b0 F', style: hPi4Global.movecardSubValueBlueTextStyle),
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
          height: SizeConfig.blockSizeVertical * 35,
          width: SizeConfig.blockSizeHorizontal * 88,
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text("About Skin Temperature",
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
                          "Skin temperature is measured at the surface of the wrist and may differ from core body temperature. "
                              "Fluctuations can occur due to physical activity, ambient conditions, and device positioning. "
                              "This is provided for general awareness and is not a substitute for medical-grade thermometers ",
                          style:
                          hPi4Global.movecardSubValue1TextStyle,
                          textAlign: TextAlign.justify,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Text('Learn more at', style: hPi4Global.movecardSubValue1TextStyle),
                      TextButton(
                        onPressed: () {
                          //launchURL("");
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

class TempTrends {
  TempTrends(this.date, this.maxTemp, this.minTemp);
  final DateTime date;
  final double maxTemp;
  final double minTemp;
}