import 'dart:io';
import 'package:flutter/material.dart';
import 'package:move/screens/showTrendsAlert.dart';
import '../globals.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../utils/trends_data_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/export_helpers.dart';

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

    activityDataManager = TrendsDataManager(hPi4Global.PREFIX_ACTIVITY);

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
        // Display 7-day range including today (last 6 days + today)
        minimum: DateTime.now().subtract(Duration(days: 6)), // Start of 7-day range
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
              child: ActivityTrendsData.isEmpty 
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
                      anchorRangeToVisiblePoints: false,
                      labelStyle: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    palette: <Color>[hPi4Global.hpi4Color],
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
      ),
    );
  }

  // Example usage for Activity data:
  late TrendsDataManager activityDataManager;

  Future<void> _loadData() async {
    try {
      if(_tabController.index == 0){
        // Daily view - Get hourly trends for today
        Count = 0;
        ActivityTrendsData = [];
        List<HourlyTrend> hourlyTrends = await activityDataManager.getHourlyTrendForToday();
        
        if (hourlyTrends.isEmpty) {
          print('No activity data available for today');
          setState(() {
            Count = 0;
          });
          return;
        }

        for (var trend in hourlyTrends) {
          if (!mounted) return;
          
          setState(() {
            ActivityTrendsData.add(ActivityTrends(trend.hour, trend.avg.toInt()));
            Count = Count + trend.avg.toInt();
          });
          print('Hour: ${trend.hour}, Steps: ${trend.avg}');
        }

      } else if(_tabController.index == 1){
        // Weekly view - Get daily trends for the week
        Count = 0;
        ActivityTrendsData = [];
        List<WeeklyTrend> weeklyTrends = await activityDataManager.getWeeklyTrends();
        
        if (weeklyTrends.isEmpty) {
          print('No activity data available for this week');
          setState(() {
            Count = 0;
          });
          return;
        }

        for (var trend in weeklyTrends) {
          if (!mounted) return;
          
          setState(() {
            ActivityTrendsData.add(ActivityTrends(trend.date, trend.avg.toInt()));
            Count = Count + trend.avg.toInt();
          });
          print('Week: ${trend.date}, Steps: ${trend.avg}');
        }

      } else if(_tabController.index == 2){
        // Monthly view - Get daily trends for the month
        Count = 0;
        ActivityTrendsData = [];
        List<MonthlyTrend> monthlyTrends = await activityDataManager.getMonthlyTrends();
        
        if (monthlyTrends.isEmpty) {
          print('No activity data available for this month');
          setState(() {
            Count = 0;
          });
          return;
        }

        for (var trend in monthlyTrends) {
          if (!mounted) return;
          
          setState(() {
            ActivityTrendsData.add(ActivityTrends(trend.date, trend.avg.toInt()));
            Count = Count + trend.avg.toInt();
          });
          print('Month: ${trend.date}, Steps: ${trend.avg}');
        }
      }
    } catch (e) {
      print('Error loading activity data: $e');
      if (!mounted) return;
      setState(() {
        ActivityTrendsData = [];
        Count = 0;
      });
    }
  }

  // Export Dialog
  Future<void> _showExportDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Text(
          'Export Activity Data',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOption(
              'Today',
              Icons.today,
              () => _exportActivityData('today'),
            ),
            _buildExportOption(
              'Last 7 Days',
              Icons.date_range,
              () => _exportActivityData('week'),
            ),
            _buildExportOption(
              'Last 30 Days',
              Icons.calendar_month,
              () => _exportActivityData('month'),
            ),
            _buildExportOption(
              'All Data',
              Icons.all_inclusive,
              () => _exportActivityData('all'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(String label, IconData icon, VoidCallback onTap) {
    return Card(
      color: Color(0xFF1E1E1E),
      child: ListTile(
        leading: Icon(icon, color: hPi4Global.hpi4Color),
        title: Text(label, style: TextStyle(color: Colors.white)),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }

  Future<void> _exportActivityData(String range) async {
    Navigator.pop(context); // Close dialog
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: LoadingIndicator(text: 'Preparing export...'),
      ),
    );
    
    try {
      List<List<String>> csvData = [
        ['Timestamp', 'Steps'],
      ];
      
      String dateLabel = ExportHelpers.getCurrentDateLabel(range);
      
      switch (range) {
        case 'today':
          List<HourlyTrend> todayData = await activityDataManager.getHourlyTrendForToday();
          if (todayData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in todayData) {
            csvData.add([
              DateFormat('yyyy-MM-dd HH:mm:ss').format(trend.hour),
              trend.avg.toStringAsFixed(0),
            ]);
          }
          break;
          
        case 'week':
          List<WeeklyTrend> weekData = await activityDataManager.getWeeklyTrends();
          if (weekData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in weekData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.avg.toStringAsFixed(0),
            ]);
          }
          break;
          
        case 'month':
          List<MonthlyTrend> monthData = await activityDataManager.getMonthlyTrends();
          if (monthData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in monthData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.avg.toStringAsFixed(0),
            ]);
          }
          break;
          
        case 'all':
          // Export monthly data as the most comprehensive view
          List<MonthlyTrend> allData = await activityDataManager.getMonthlyTrends();
          if (allData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in allData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.avg.toStringAsFixed(0),
            ]);
          }
          break;
      }
      
      // Create CSV content
      String csv = const ListToCsvConverter().convert(csvData);
      
      // Save and share
      final directory = await getApplicationDocumentsDirectory();
      final filename = ExportHelpers.generateFilename('activity', dateLabel, 'csv');
      final file = File('${directory.path}/$filename');
      await file.writeAsString(csv);
      
      Navigator.pop(context); // Close loading
      
      // Share file
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Activity Data - HealthyPi Move',
      );
      
      if (result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Data exported successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _showNoDataMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No data available for selected period'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

 Widget stepsBasedOnTab(){
    if(_tabController.index == 0){
     return Column(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text("Today's total", style: hPi4Global.movecardSubValueTextStyle,),
            Row(
                children: <Widget>[
                  Text((Count.toString() == "0")
                      ? "--"
                      : Count.toString(),
                    style: hPi4Global.moveValueGreenTextStyle,
                  ),
                  SizedBox(width: 5.0),
                  Text('steps', style: hPi4Global.movecardSubValueGreenTextStyle),
                ]
            ),

          ]
      );
    }else if(_tabController.index == 1){
      return Column(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text("This week's total", style: hPi4Global.movecardSubValueTextStyle,),
            Row(
                children: <Widget>[
                  Text((Count.toString() == "0")
                      ? "--"
                      : Count.toString(),
                    style: hPi4Global.moveValueGreenTextStyle,
                  ),
                  SizedBox(width: 5.0),
                  Text('steps', style: hPi4Global.movecardSubValueGreenTextStyle),
                ]
            ),

          ]
      );
    }else if(_tabController.index == 2){
      return Column(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text("This month's total", style: hPi4Global.movecardSubValueTextStyle,),
            Row(
                children: <Widget>[
                  Text((Count.toString() == "0")
                      ? "--"
                      : Count.toString(),
                    style: hPi4Global.moveValueGreenTextStyle,
                  ),
                  SizedBox(width: 5.0),
                  Text('steps', style: hPi4Global.movecardSubValueGreenTextStyle),
                ]
            ),

          ]
      );
    }else{
      return Container();
    }
  }

  Widget displayValue() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SizeConfig.blockSizeVertical * 12.5,
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
                      stepsBasedOnTab(),
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
                      Text("About Activity",
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
                          "Step count is estimated using motion sensors in the device. "
                              "It reflects walking-related movement but may vary based on gait, posture, and activity type.",
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
                          launchURL("https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/walking/art-20047880");
                        },
                        child: Text('Mayo Clinic', style:TextStyle(
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
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: SizeConfig.blockSizeVertical * 32,
                        width: SizeConfig.blockSizeHorizontal * 88,
                        color: Colors.transparent,
                        child: buildChartBlock(),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  displayValue(),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: 48),
            const Text(
              'Activity',
              style: TextStyle(
                fontSize: 16,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
            ),
            IconButton(
              icon: Icon(Icons.file_download, color: Colors.white),
              tooltip: 'Export Data',
              onPressed: _showExportDialog,
            ),
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

class ActivityTrends {
  ActivityTrends(this.date, this.count);
  final DateTime date;
  final int count;
}
