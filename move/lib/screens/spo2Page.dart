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

class SPO2Page extends StatefulWidget {
  const SPO2Page({super.key});
  @override
  State<SPO2Page> createState() => _SPO2PageState();
}
class _SPO2PageState extends State<SPO2Page>
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
          DateTime.now().day,
          23,
          59,
          59,
        ),
        //DateTime.now(), // End value of the range slider
        interval: 1,
        intervalType: DateTimeIntervalType.hours,
        dateFormat: DateFormat.Hm(),
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
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
      );
    } else {
      return DateTimeAxis(
        // Display a month-long range dynamically based on slider values
        minimum: DateTime.now().subtract(Duration(days: 30)), // 30 days ago
        maximum: DateTime.now(), // Today
        interval: 1, // 6-hour intervals
        intervalType: DateTimeIntervalType.days,
        dateFormat: DateFormat('dd MMM'), // Show day, month, and hour
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
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
                      minimum: 0,
                      maximum: 200,
                      interval: 10,
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
                      HiloSeries<Spo2Trends, DateTime>(
                          dataSource: Spo2TrendsData,
                          xValueMapper: (Spo2Trends data, _) => data.date,
                          lowValueMapper: (Spo2Trends data, _) => data.minSpo2,
                          highValueMapper: (Spo2Trends data, _) => data.maxSpo2
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
            .where((file) => p.basename(file.path).startsWith("spo2_")) // Filter by prefix
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

    CalculateLasthourMinMax(myData);

    //String myData = await rootBundle.loadString("assets/Temp_data.csv");
    List<String> result = myData.split('\n');
    //print(result);
    timestamp = result.map((f) => f.split(",")[0]).toList();

    avgSpo2 = result.map((f) => f.split(",")[1]).toList();

    for(int i = 1; i< timestamp.length; i++){
      int tempTimeStamp = 0;
      int tempTimeStamp1 = 0;
      int tempAvgSpo2 = 0;
      int tempMinSpo2 = 95;
      int tempMaxSpo2 = 99;


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
  }

  // Save a value
  _saveValue() async {
    String lastDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestSpo2', averageSpo2.toString());
    await prefs.setString('lastUpdatedSpo2', lastDateTime.toString());
  }

  void CalculateLasthourMinMax(String fileContent) {
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
  }

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
                        Text(rangeMinSpo2.toString(),
                            style: hPi4Global.moveValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('-',
                            style: hPi4Global.moveValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(rangeMaxSpo2.toString(),
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
                              Text(averageSpo2.toString(),
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
        physics: NeverScrollableScrollPhysics(),
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


class Spo2Trends {
  Spo2Trends(this.date, this.maxSpo2, this.minSpo2);
  final DateTime date;
  final int maxSpo2;
  final int minSpo2;
}
