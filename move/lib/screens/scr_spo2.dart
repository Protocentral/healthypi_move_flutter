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

class ScrSPO2 extends StatefulWidget {
  const ScrSPO2({super.key});
  @override
  State<ScrSPO2> createState() => _ScrSPO2State();
}
class _ScrSPO2State extends State<ScrSPO2>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<String> timestamp = [];
  List<String> minSpo2 = [];
  List<String> maxSpo2 =[];
  List<String> avgSpo2 =[];
  List<String> latestSpo2 =[];

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
    _listCSVFiles();
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
                    palette: <Color>[
                      hPi4Global.hpi4Color,
                    ],
                    series: <CartesianSeries>[
                      RangeColumnSeries<Spo2Trends, DateTime>(
                          dataSource: Spo2TrendsData,
                          xValueMapper: (Spo2Trends data, _) => data.date,
                          lowValueMapper: (Spo2Trends data, _) => data.minSpo2,
                          highValueMapper: (Spo2Trends data, _) => data.maxSpo2,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
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
            .where((file) => p.basename(file.path).startsWith("spo2_")) // Filter by prefix
            .toList();

        List<String> fileNames = csvFiles.map((file) => p.basename(file.path)).toList();

        for (File file in csvFiles) {
          String timestamp = await _getSecondLineTimestamp(file);
          String timestamp1 = timestamp.split(",")[0];
          int timestamp2 = int.parse(timestamp1);
          int updatedTimestamp = timestamp2 * 1000;
          String fileName1 = p.basename(file.path);

          DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
          DateTime now = DateTime.now();

          if (_tabController.index == 0) {
            // Last 1 hour
            DateTime oneHourAgo = now.subtract(Duration(hours: 1));
            if (timestampDateTime.isAfter(oneHourAgo) && timestampDateTime.isBefore(now)) {
              await _processFileForHourlyOrDailyStats(fileName1, "hour");
            }
          } else if (_tabController.index == 1) {
            // Last 24 hours (1 day)
            DateTime oneDayAgo = now.subtract(Duration(days: 1));
            if (timestampDateTime.isAfter(oneDayAgo) && timestampDateTime.isBefore(now)) {
              await _processFileForHourlyOrDailyStats(fileName1, "day");
            }
          } else if (_tabController.index == 2) {
            // Last 30 days (1 month)
            DateTime oneMonthAgo = now.subtract(Duration(days: 30));
            if (timestampDateTime.isAfter(oneMonthAgo) && timestampDateTime.isBefore(now)) {
              await _processFileForHourlyOrDailyStats(fileName1, "month");
            }
          }
        }
      }
    }
  }

  Future<void> _processFileForHourlyOrDailyStats(String fileName, String range) async {
    Directory? downloadsDirectory;
    if (Platform.isAndroid) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    }

    if (downloadsDirectory != null) {
      String filePath = '${downloadsDirectory.path}/$fileName';
      File csvFile = File(filePath);

      if (await csvFile.exists()) {
        String fileContent = await csvFile.readAsString();
       _calculateMinMaxBasedOnRange(fileContent, range);

      }
    }
  }

  _calculateMinMaxBasedOnRange(String fileContent, String range) {
    List<String> lines = fileContent.split('\n');
    Map<String, List<int>> groupedData = {};
    DateTime now = DateTime.now();
    Duration rangeDuration;

    // Define the range for grouping
    if (range == "hour") {
      rangeDuration = Duration(hours: 1);
    } else if (range == "day") {
      rangeDuration = Duration(days: 1);
    } else if (range == "month") {
      rangeDuration = Duration(days: 30); // Assuming 30 days for a month
    } else {
      throw Exception("Invalid range specified.");
    }

    for (int i = 1; i < lines.length; i++) { // Start from 1 to skip the header
      if (lines[i].trim().isEmpty) continue;

      List<String> parts = lines[i].split(',');
      if (parts.length < 2) continue;

      int timestamp = int.parse(parts[0]) * 1000;
      int spo2 = int.parse(parts[1]);

      DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (dateTime.isBefore(now.subtract(rangeDuration)) || dateTime.isAfter(now)) {
        continue; // Skip data outside the range
      }

      String rangeKey = "0";

      if (range == "hour") {
        rangeKey = DateFormat('yyyy-MM-dd HH:00:00').format(dateTime); // Group by hour
      } else if (range == "day" || range == "month") {
        rangeKey = DateFormat('yyyy-MM-dd').format(dateTime); // Group by day
      }

      if (!groupedData.containsKey(rangeKey)) {
        groupedData[rangeKey] = [];
      }
      groupedData[rangeKey]!.add(spo2);
    }
    int minSpo2 = 0;
    int maxSpo2 = 0;

    groupedData.forEach((group, spo2Values) {
      minSpo2 = spo2Values.reduce((a, b) => a < b ? a : b); // Calculate min as an int
      maxSpo2 = spo2Values.reduce((a, b) => a > b ? a : b); // Calculate max as an int

      DateTime formattedDateTime = DateTime.parse(group);
      setState(() {
        Spo2TrendsData.add(Spo2Trends(formattedDateTime, minSpo2, maxSpo2));
        restingSpo2 = maxSpo2;
        averageSpo2 = maxSpo2;
        rangeMinSpo2 = minSpo2;
        rangeMaxSpo2 = maxSpo2;

      });
      print("$range: $group, Min: $minSpo2, Max: $maxSpo2");
    });

    if (groupedData.isNotEmpty) {
      String lastGroup = groupedData.keys.last;
      setState(() {
        lastUpdatedTime = DateTime.parse(lastGroup);
      });

      String todayStr = _formatDate(DateTime.now());
      if (_formatDate(lastUpdatedTime) == todayStr) {
        saveValue(lastUpdatedTime);
      }
    }
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

  /*Future<void> getFileData(String fileName) async {
    Directory? downloadsDirectory;
    String myData = '';

    if (Platform.isAndroid) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      downloadsDirectory = await getApplicationDocumentsDirectory();
    }

    if (downloadsDirectory != null) {
      String filePath = '${downloadsDirectory.path}/$fileName'; // Replace 'your_file.csv' with your actual file name
      File csvFile = File(filePath);


      if (await csvFile.exists()) {
        String fileContent = await csvFile.readAsString();
        setState(() {
          myData = fileContent;
        });
      }
    }

    CalculateLasthourMinMax(myData);

    List<String> result = myData.split('\n');
    print(result);
    timestamp = result.map((f) => f.split(",")[0]).toList();

    avgSpo2 = result.map((f) => f.split(",")[1]).toList();

    for(int i = 1; i< timestamp.length; i++){
      int tempTimeStamp = 0;
      int tempTimeStamp1 = 0;
      int tempAvgSpo2 = 0;
      int tempMinSpo2 = 0;
      int tempMaxSpo2 = 0;


      tempTimeStamp = int.parse(timestamp[i]);
      tempTimeStamp1 = tempTimeStamp*1000;
      tempAvgSpo2 = int.parse(avgSpo2[i]);

      //DateTime getUTCTime = DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1).toUtc();
     var getUTCTime = DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1).toUtc();
      // Format the DateTime to remove the 'Z' and make it human-readable
      String formattedDate = DateFormat("yyyy-MM-dd HH:mm:ss").format(getUTCTime);
      // Parse the formatted date string back into a DateTime object
      DateTime formattedDateTime = DateTime.parse(formattedDate);


      setState((){
        //print(DateTime.fromMillisecondsSinceEpoch(Spo2TimeStamp1).toString());
        Spo2TrendsData.add(Spo2Trends(formattedDateTime,
            tempAvgSpo2-1, tempAvgSpo2));
        if( i == timestamp.length-1){
          lastUpdatedTime = formattedDateTime;
          averageSpo2 = tempAvgSpo2;
          rangeMinSpo2 = tempMinSpo2;
          rangeMaxSpo2 = tempMaxSpo2;

        }
      });
    }
    _saveValue();
  }*/

  // Save a value
  saveValue(DateTime lastUpdatedTime) async {
    String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestSpo2', restingSpo2.toString());
    await prefs.setString('lastUpdatedSpo2', lastDateTime.toString());
  }

  /*void CalculateLasthourMinMax(String fileContent) {
    // Split file content into rows
    List<String> rows = fileContent.split('\n');
    List<int> timestamps = [];
    List<int> values = [];

    // Parse the rows into timestamps and values
    for (String row in rows) {
      if (row.trim().isNotEmpty) {
        try {
          List<String> parts = row.split(',');
          if (parts.length == 2) {
            int timestamp = int.parse(parts[0].trim()); // Trim whitespace
            int value = int.parse(parts[1].trim());    // Trim whitespace
            timestamps.add(timestamp);
            values.add(value);
          }
        } catch (e) {
          print('Skipping invalid row: $row. Error: $e');
        }
      }
    }

    // Get current timestamp and calculate one hour ago
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    int oneHourAgo = currentTime - (60 * 60 * 1000);

    // Filter the data for the last one hour
    List<int> lastHourValues = [];
    for (int i = 0; i < timestamps.length; i++) {
      if (timestamps[i] >= oneHourAgo) {
        lastHourValues.add(values[i]);
      }
    }

    // Calculate the minimum and maximum values
    if (lastHourValues.isNotEmpty) {
      int minValue = lastHourValues.reduce((a, b) => a < b ? a : b);
      int maxValue = lastHourValues.reduce((a, b) => a > b ? a : b);

      print('Minimum SpO2 in the last one hour: $minValue');
      print('Maximum SpO2 in the last one hour: $maxValue');
    } else {
      print('No data available for the last one hour.');
    }
  }*/

  Widget displayValue(){
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
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('RANGE',
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
                        Text( (rangeMinSpo2.toString()=="0")? "--":rangeMinSpo2.toString(),
                            style: hPi4Global.moveValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('-',
                            style: hPi4Global.moveValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                        Text((rangeMaxSpo2.toString()=="0")? "--":rangeMaxSpo2.toString(),
                            style: hPi4Global.moveValueTextStyle),
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
                        Text("%",
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
        Column(
          //mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
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
                              SizedBox(
                                width: 10.0,
                              ),
                              Text((averageSpo2.toString()=="0")? "--":averageSpo2.toString(),
                                  style: hPi4Global.moveValueTextStyle),
                              SizedBox(
                                width: 15.0,
                              ),
                              //Icon(Icons.favorite_border, color: Colors.black),
                            ],
                          ),
                          Row(
                            children: <Widget>[
                              SizedBox(
                                width: 10.0,
                              ),
                              Text('AVERAGE',
                                  style: hPi4Global.movecardSubValueTextStyle),
                            ],
                          ),

                        ]),
                  ),
                ),
              ),
            ]
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
                'Spo2',
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


class Spo2Trends {
  Spo2Trends(this.date, this.maxSpo2, this.minSpo2);
  final DateTime date;
  final int maxSpo2;
  final int minSpo2;
}
