import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/trends_data_manager.dart';
import 'package:move/screens/showTrendsAlert.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/export_helpers.dart';
import '../widgets/export_dialogs.dart';

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

    hrDataManager = TrendsDataManager(hPi4Global.PREFIX_HR);

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        color: const Color(0xFF2D2D2D),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: hrTrendsData.isEmpty 
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
                      HiloSeries<HRTrends, DateTime>(
                        dataSource: hrTrendsData,
                        xValueMapper: (HRTrends data, _) => data.date,
                        lowValueMapper: (HRTrends data, _) => data.minHR,
                        highValueMapper: (HRTrends data, _) => data.maxHR,
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

  // Example usage for HR data:
  late TrendsDataManager hrDataManager;

  Future<void> _loadData() async {
    try {
      if(_tabController.index == 0){
        // Daily view - Get hourly trends for today
        hrTrendsData = [];
        List<HourlyTrend> hourlyTrends = await hrDataManager.getHourlyTrendForToday();
        
        if (hourlyTrends.isEmpty) {
          print('No HR data available for today');
          setState(() {
            rangeMinHR = 0;
            rangeMaxHR = 0;
            averageHR = 0;
          });
          return;
        }

        // Convert HourlyTrend to HRTrends for display
        int minVal = double.maxFinite.toInt();
        int maxVal = 0;
        int sumAvg = 0;
        int count = 0;

        for (var trend in hourlyTrends) {
          if (!mounted) return;
          
          hrTrendsData.add(
            HRTrends(
              trend.hour,
              trend.max.toInt(),
              trend.min.toInt(),
            ),
          );
          
          if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
          if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
          sumAvg += trend.avg.toInt();
          count++;
        }

        if (!mounted) return;
        setState(() {
          rangeMinHR = minVal;
          rangeMaxHR = maxVal;
          averageHR = (sumAvg / count).round();
        });

      } else if(_tabController.index == 1){
        // Weekly view - Get daily trends for the week
        hrTrendsData = [];
        List<WeeklyTrend> weeklyTrends = await hrDataManager.getWeeklyTrends();
        
        if (weeklyTrends.isEmpty) {
          print('No HR data available for this week');
          setState(() {
            rangeMinHR = 0;
            rangeMaxHR = 0;
            averageHR = 0;
          });
          return;
        }

        int minVal = double.maxFinite.toInt();
        int maxVal = 0;
        int sumAvg = 0;
        int count = 0;

        for (var trend in weeklyTrends) {
          if (!mounted) return;
          
          hrTrendsData.add(
            HRTrends(
              trend.date,
              trend.max.toInt(),
              trend.min.toInt(),
            ),
          );
          
          if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
          if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
          sumAvg += trend.avg.toInt();
          count++;
        }

        if (!mounted) return;
        setState(() {
          rangeMinHR = minVal;
          rangeMaxHR = maxVal;
          averageHR = (sumAvg / count).round();
        });

      } else if(_tabController.index == 2){
        // Monthly view - Get daily trends for the month
        hrTrendsData = [];
        List<MonthlyTrend> monthlyTrends = await hrDataManager.getMonthlyTrends();
        
        if (monthlyTrends.isEmpty) {
          print('No HR data available for this month');
          setState(() {
            rangeMinHR = 0;
            rangeMaxHR = 0;
            averageHR = 0;
          });
          return;
        }

        int minVal = double.maxFinite.toInt();
        int maxVal = 0;
        int sumAvg = 0;
        int count = 0;

        for (var trend in monthlyTrends) {
          if (!mounted) return;
          
          hrTrendsData.add(
            HRTrends(
              trend.date,
              trend.max.toInt(),
              trend.min.toInt(),
            ),
          );
          
          if (trend.min.toInt() < minVal) minVal = trend.min.toInt();
          if (trend.max.toInt() > maxVal) maxVal = trend.max.toInt();
          sumAvg += trend.avg.toInt();
          count++;
        }

        if (!mounted) return;
        setState(() {
          rangeMinHR = minVal;
          rangeMaxHR = maxVal;
          averageHR = (sumAvg / count).round();
        });
      }
    } catch (e) {
      print('Error loading HR data: $e');
      if (!mounted) return;
      setState(() {
        hrTrendsData = [];
        rangeMinHR = 0;
        rangeMaxHR = 0;
        averageHR = 0;
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
          'Export Heart Rate Data',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOption(
              'Today',
              Icons.today,
              () => _exportHRData('today'),
            ),
            _buildExportOption(
              'Last 7 Days',
              Icons.date_range,
              () => _exportHRData('week'),
            ),
            _buildExportOption(
              'Last 30 Days',
              Icons.calendar_month,
              () => _exportHRData('month'),
            ),
            _buildExportOption(
              'All Data',
              Icons.all_inclusive,
              () => _exportHRData('all'),
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

  Future<void> _exportHRData(String range) async {
    Navigator.pop(context); // Close range selection dialog
    
    // Show action dialog (Share or Save)
    final action = await showExportActionDialog(context);
    if (action == null) return; // User cancelled
    
    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: LoadingIndicator(text: 'Preparing export...'),
      ),
    );
    
    try {
      List<List<String>> csvData = [
        ['Timestamp', 'Min HR (bpm)', 'Max HR (bpm)', 'Avg HR (bpm)'],
      ];
      
      String dateLabel = ExportHelpers.getCurrentDateLabel(range);
      
      switch (range) {
        case 'today':
          List<HourlyTrend> todayData = await hrDataManager.getHourlyTrendForToday();
          if (todayData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in todayData) {
            csvData.add([
              DateFormat('yyyy-MM-dd HH:mm:ss').format(trend.hour),
              trend.min.toStringAsFixed(0),
              trend.max.toStringAsFixed(0),
              trend.avg.toStringAsFixed(1),
            ]);
          }
          break;
          
        case 'week':
          List<WeeklyTrend> weekData = await hrDataManager.getWeeklyTrends();
          if (weekData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in weekData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.min.toStringAsFixed(0),
              trend.max.toStringAsFixed(0),
              trend.avg.toStringAsFixed(1),
            ]);
          }
          break;
          
        case 'month':
          List<MonthlyTrend> monthData = await hrDataManager.getMonthlyTrends();
          if (monthData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in monthData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.min.toStringAsFixed(0),
              trend.max.toStringAsFixed(0),
              trend.avg.toStringAsFixed(1),
            ]);
          }
          break;
          
        case 'all':
          // Export monthly data as the most comprehensive view
          List<MonthlyTrend> allData = await hrDataManager.getMonthlyTrends();
          if (allData.isEmpty) {
            Navigator.pop(context);
            _showNoDataMessage();
            return;
          }
          for (var trend in allData) {
            csvData.add([
              DateFormat('yyyy-MM-dd').format(trend.date),
              trend.min.toStringAsFixed(0),
              trend.max.toStringAsFixed(0),
              trend.avg.toStringAsFixed(1),
            ]);
          }
          break;
      }
      
      // Create CSV content
      String csv = const ListToCsvConverter().convert(csvData);
      final filename = ExportHelpers.generateFilename('hr', dateLabel, 'csv');
      
      Navigator.pop(context); // Close loading
      
      // Share file
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(csv);
      
      final result = await Share.shareXFiles(
        [XFile(file.path)],
      );
      
      if (result.status == ShareResultStatus.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Data shared successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
                                  Text((rangeMinHR.toString() == "0")
                                      ? "--"
                                      : rangeMinHR.toString(),
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
                                    (averageHR.toString() == "0")
                                        ? "--"
                                        : averageHR.toString(),
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
                                    (rangeMaxHR.toString() == "0")
                                        ? "--"
                                        : rangeMaxHR.toString(),
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
        automaticallyImplyLeading: false, // Remove back button
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Heart Rate',
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
        centerTitle: false,
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
