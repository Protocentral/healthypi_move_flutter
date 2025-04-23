import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart' as rs;
import '../home.dart';
import '../sizeConfig.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({Key? key}) : super(key: key);
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}
class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  rs.SfRangeValues _values = rs.SfRangeValues(
    DateTime.now().subtract(Duration(hours: 4)), // Default start value
    DateTime.now(), // Default end value
  );

  rs.SfRangeValues _values1 = rs.SfRangeValues(
    DateTime.now().subtract(Duration(hours: 4)), // Default start value
    DateTime.now(), // Default end value
  );

  rs.SfRangeValues _values2 = rs.SfRangeValues(
    DateTime.now().subtract(Duration(hours: 24)), // Default start value
    DateTime.now(), // Default end value
  );

  late TabController _tabController;

  List<String> timestamp = [];
  List<String> minActivity = [];
  List<String> maxActivity =[];
  List<String> avgActivity =[];
  List<String> latestActivity =[];


  int totalCount = 0;
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
      // Rebuild the widget when the tab index changes
      //buildchartBlock();
    });
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
                  primaryXAxis: DateTimeAxis(
                    minimum: _values.start, // Start value of the range slider
                    maximum: _values.end, // End value of the range slider
                    interval: 1,
                    intervalType: DateTimeIntervalType.hours,
                    dateFormat: DateFormat.Hm(),
                    majorGridLines: MajorGridLines(width: 0),
                    labelStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(width: 0.05),
                    minimum: 0,
                    maximum: 10000,
                    interval: 1000,
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
                    ColumnSeries<ActivityTrends, DateTime>(
                      dataSource: ActivityTrendsData,
                      xValueMapper: (ActivityTrends data, _) => data.date,
                      yValueMapper: (ActivityTrends data, _) => data.count,
                      color: hPi4Global.hpi4Color,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 0,
                child: rs.SfRangeSlider(
                  min: DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                    0,
                    0,
                    0,
                  ), // Start of the current day
                  max: DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                    23,
                    59,
                    59,
                  ), // End of the current day
                  values: _values,
                  interval: 4, // Interval of 6 hours
                  dateIntervalType: rs.DateIntervalType.hours,
                  activeColor: hPi4Global.hpi4Color, // Set the active track color
                  inactiveColor: Colors.grey, // Set the inactive track color
                  dateFormat: DateFormat.Hm(),
                  labelFormatterCallback: (dynamic actualValue, String formattedText) {
                    return formattedText; // Customize the labels if needed
                  },
                  onChanged: (rs.SfRangeValues newValues) {
                    setState(() {
                      _values = newValues; // Update the range slider values
                    });
                  },
                ),
              ),
            ],
          ),
        ));
  }

  Widget buildWeekChartBlock() {
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
                primaryXAxis: DateTimeAxis(
                  minimum: _values1.start, // Start value of the range slider
                  maximum: _values1.end, // End value of the range slider
                  interval: 4, // 6-hour intervals
                  intervalType: DateTimeIntervalType.hours,
                  dateFormat: DateFormat('EEE, HH:mm'), // Show day and hour
                  majorGridLines: MajorGridLines(width: 0),
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  majorGridLines: MajorGridLines(width: 0.05),
                  minimum: 0,
                  maximum: 10000,
                  interval: 1000,
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
                  ColumnSeries<ActivityTrends, DateTime>(
                    dataSource: ActivityTrendsData,
                    xValueMapper: (ActivityTrends data, _) => data.date,
                    yValueMapper: (ActivityTrends data, _) => data.count,
                    color: hPi4Global.hpi4Color,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 0,
              child: rs.SfRangeSlider(
                min: DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ).subtract(Duration(days: 7)), // Start of the range (7 days before)
                max: DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ).add(Duration(days: 7)), // End of the range (7 days ahead)
                values: _values1,
                interval: 6, // Interval of 6 hours
                dateIntervalType: rs.DateIntervalType.hours, // Set interval to 6 hours
                activeColor: hPi4Global.hpi4Color, // Set the active track color
                inactiveColor: Colors.grey, // Set the inactive track color
                dateFormat: DateFormat('EEE, HH:mm'), // Format labels as day and hours
                labelFormatterCallback: (dynamic actualValue, String formattedText) {
                  return formattedText; // Customize the labels if needed
                },
                onChanged: (rs.SfRangeValues newValues) {
                  setState(() {
                    _values1 = newValues; // Update the range slider values
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMonthChartBlock() {
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
                primaryXAxis: DateTimeAxis(
                  // Display a month-long range dynamically based on slider values
                  minimum: _values2.start, // Start value of the range slider
                  maximum: _values2.end, // End value of the range slider
                  interval: 6, // 6-hour intervals
                  intervalType: DateTimeIntervalType.hours,
                  dateFormat: DateFormat('dd MMM, HH:mm'), // Show day, month, and hour
                  majorGridLines: MajorGridLines(width: 0),
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  majorGridLines: MajorGridLines(width: 0.05),
                  minimum: 0,
                  maximum: 10000,
                  interval: 1000,
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
                  ColumnSeries<ActivityTrends, DateTime>(
                    dataSource: ActivityTrendsData,
                    xValueMapper: (ActivityTrends data, _) => data.date,
                    yValueMapper: (ActivityTrends data, _) => data.count,
                    color: hPi4Global.hpi4Color,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 0,
              child: rs.SfRangeSlider(
                min: DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ).subtract(Duration(days: 30)), // Start of the range (30 days before today)
                max: DateTime(
                  DateTime.now().year,
                  DateTime.now().month,
                  DateTime.now().day,
                ).add(Duration(days: 30)), // End of the range (30 days after today)
                values: _values2,
                interval: 6, // Interval of 6 hours
                dateIntervalType: rs.DateIntervalType.hours, // Set interval to 6 hours
                //showLabels: true,
                //showTicks: true,
                activeColor: hPi4Global.hpi4Color, // Set the active track color
                inactiveColor: Colors.grey, // Set the inactive track color
                dateFormat: DateFormat('dd MMM, HH:mm'), // Format labels as day, month, and hour
                labelFormatterCallback: (dynamic actualValue, String formattedText) {
                  return formattedText; // Customize the labels if needed
                },
                onChanged: (rs.SfRangeValues newValues) {
                  setState(() {
                    _values2 = newValues; // Update the range slider values
                  });
                },
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

  Future<void> _listCSVFiles() async {
    Directory? downloadsDirectory ;
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

        List<File> csvFiles = files
            .where((file) => file is File && file.path.endsWith('.csv'))
            .map((file) => file as File)
            .where((file) => p.basename(file.path).startsWith("activity_")) // Filter by prefix
            .toList();

        List<String> fileNames = csvFiles.map((file) => p.basename(file.path)).toList();
        //print("......"+fileNames.toString());

        for (File file in csvFiles) {
          String timestamp = await _getSecondLineTimestamp(file);
          //timestamps.add(timestamp);
          String timestamp1 = timestamp.split(",")[0];
          int timestamp2 = int.parse(timestamp1);
          int updatedTimestamp = timestamp2*1000;
          String fileName1 = p.basename(file.path);

          DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
          //print("......"+timestampDateTime.toString());
          DateTime now = DateTime.now();
          // print("......"+now.toString());
          if(_tabController.index == 0){
            String todayStr = _formatDate(now);
            if (_formatDate(timestampDateTime) == todayStr) {
              getFileData(fileName1);
              // print("same..........");
            }else{
              // print("different........");
            }
          }else if(_tabController.index == 1){
            // Calculate the start of the week (7 days ago)
            DateTime weekStart = now.subtract(Duration(days: 7));
            // Check if the file's timestamp is within the past 7 days
            if (timestampDateTime.isAfter(weekStart) && timestampDateTime.isBefore(now)) {
              getFileData(fileName1); // Process the file data
            }
          }else if(_tabController.index == 2){
            // Calculate the start of the week (7 days ago)
            DateTime monthStart = now.subtract(Duration(days: 30));
            // Check if the file's timestamp is within the past 7 days
            if (timestampDateTime.isAfter(monthStart) && timestampDateTime.isBefore(now)) {
              getFileData(fileName1); // Process the file data
            }
          }

        }

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

  Future<void> getFileData(String fileName) async {
    Directory? downloadsDirectory;
    String myData = '';

    if (Platform.isAndroid) {
      //downloadsDirectory = Directory('/storage/emulated/0/Download');
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

    //String myData = await rootBundle.loadString("assets/Temp_data.csv");
    List<String> result = myData.split('\n');
    //print(result);
    timestamp = result.map((f) => f.split(",")[0]).toList();

    avgActivity = result.map((f) => f.split(",")[1]).toList();

    for(int i = 1; i< timestamp.length; i++){
      int tempTimeStamp = 0;
      int tempTimeStamp1 = 0;
      int tempAvgActivity = 0;

      tempTimeStamp = int.parse(timestamp[i]);
      tempTimeStamp1 = tempTimeStamp*1000;
      tempAvgActivity = int.parse(avgActivity[i]);

      //DateTime getUTCTime = DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1).toUtc();
      var getUTCTime = DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1).toUtc();
      // Format the DateTime to remove the 'Z' and make it human-readable
      String formattedDate = DateFormat("yyyy-MM-dd HH:mm:ss").format(getUTCTime);
      // Parse the formatted date string back into a DateTime object
      DateTime formattedDateTime = DateTime.parse(formattedDate);


      setState((){
        //print(DateTime.fromMillisecondsSinceEpoch(ActivityTimeStamp1).toString());
        ActivityTrendsData.add(ActivityTrends(formattedDateTime, tempAvgActivity-1));
        if( i == timestamp.length-1){
          lastUpdatedTime = formattedDateTime;
          totalCount = tempAvgActivity;
        }
      });
    }
    _saveValue();
  }

  // Save a value
  _saveValue() async {
    String lastDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestActivity', totalCount.toString());
    await prefs.setString('lastUpdatedActivity', lastDateTime.toString());
  }

  Widget displayValue(){
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                        Text(totalCount.toString(),
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
    if(tab == "Day"){
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
    }else if(tab == "Week"){
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
                        child:buildWeekChartBlock(),
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
    }else{
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
                        child:buildMonthChartBlock(),
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
                  Text('Day'),
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


class ActivityTrends {
  ActivityTrends(this.date, this.count);
  final DateTime date;
  final int count;
}
