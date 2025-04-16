import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../globals.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;


class HRPage extends StatefulWidget {
  const HRPage({Key? key}) : super(key: key);
  @override
  State<HRPage> createState() => _HRPageState();
}
class _HRPageState extends State<HRPage>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<String> timestamp = [];
  List<String> minHR = [];
  List<String> maxHR =[];
  List<String> avgHR =[];
  List<String> latestHR =[];

  int restingHR = 0;
  int rangeMinHR = 0;
  int rangeMaxHR = 0;
  int averageHR = 0;

  List<HRTrends> hrTrendsData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _listCSVFiles();
  }

  @override
  void dispose() {
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

  displayDateAxis(){
  if(_tabController.index == 0){
      return  DateTimeAxis(
        // Minimum value set to 00:00 of the current day
        minimum: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 0, 0, 0),

        // Maximum value set to 00:00 of the next day
        maximum: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
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
    }else if(_tabController.index == 1){
      return DateTimeAxis(
        // Minimum value set to 7 days before the current date
        //minimum: DateTime.now().subtract(Duration(days: 7)),
        // Maximum value set to the current date and time
        //maximum: DateTime.now(),
        minimum: DateTime.now().subtract(Duration(days: 6, hours: DateTime.now().hour, minutes: DateTime.now().minute, seconds: DateTime.now().second)),
        // Maximum value set to the end of today (23:59:59)
        maximum: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
        interval: 1,
        intervalType: DateTimeIntervalType.days, // Interval type set to days
        dateFormat: DateFormat('dd'),
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }else{
      return DateTimeAxis(
        minimum: DateTime(DateTime.now().year, DateTime.now().month - 1, DateTime.now().day),
        // Maximum value set to the current date and time
        maximum: DateTime.now(),
        interval: 4,
        intervalType: DateTimeIntervalType.days, // Interval type set to days
        dateFormat: DateFormat('dd'), //
        majorGridLines: MajorGridLines(width: 0),
        labelStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }
  }

  Widget buildchartBlock() {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        color: Colors.grey[900],
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                  child: SfCartesianChart(
                      plotAreaBorderWidth: 0,
                      primaryXAxis: displayDateAxis(),
                      primaryYAxis: NumericAxis(
                          majorGridLines: MajorGridLines(width: 0.05),
                          minimum: 0,
                          maximum: 200,
                          interval: 10,
                          labelStyle: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500
                          )
                      ),
                      palette: <Color>[
                        hPi4Global.hpi4Color,
                      ],
                      series: <CartesianSeries>[
                        HiloSeries<HRTrends, DateTime>(
                            dataSource: hrTrendsData,
                            xValueMapper: (HRTrends data, _) => data.date,
                            lowValueMapper: (HRTrends data, _) => data.minHR,
                            highValueMapper: (HRTrends data, _) => data.maxHR
                        ),
                      ]
                  )
              )
            ]),
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
            .where((file) => p.basename(file.path).startsWith("hr_")) // Filter by prefix
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

    //String myData = await rootBundle.loadString("assets/hr_data.csv");
    List<String> result = myData.split('\n');
    //print(result);
    timestamp = result.map((f) => f.split(",")[0]).toList();

    maxHR = result.map((f) => f.split(",")[1]).toList();

    minHR = result.map((f) => f.split(",")[2]).toList();

    avgHR = result.map((f) => f.split(",")[3]).toList();

    latestHR = result.map((f) => f.split(",")[4]).toList();


    for(int i = 1; i< timestamp.length; i++){
      int tempTimeStamp = 0;
      int tempTimeStamp1 = 0;
      int tempMinHR = 0;
      int tempMaxHR = 0;
      int tempAvgHR = 0;
      int tempLatestHR = 0;

      tempTimeStamp = int.parse(timestamp[i]);
      tempTimeStamp1 = tempTimeStamp*1000;
      tempMinHR = int.parse(minHR[i]);
      tempMaxHR = int.parse(maxHR[i]);
      tempAvgHR = int.parse(avgHR[i]);
      tempLatestHR = int.parse(latestHR[i]);

      setState((){
        //print(DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1).toString());
        hrTrendsData.add(HRTrends(DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1, isUtc: false),
            tempMinHR, tempMaxHR));
        if( i == timestamp.length-1){
          averageHR = tempAvgHR;
          restingHR = tempLatestHR;
          rangeMinHR = tempMinHR;
          rangeMaxHR = tempMaxHR;

        }
      });
    }
    _saveValue();
  }

  // Save a value
  _saveValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('latestHR', restingHR.toString());
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
                      child:buildchartBlock(),
                    )
                  ],
                ),
                SizedBox(height:20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
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
                                  height: 50.0,
                                ),
                                Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 10.0,
                                    ),
                                    Text(rangeMinHR.toString(),
                                        style: hPi4Global.moveValueTextStyle),
                                    SizedBox(
                                      width: 10.0,
                                    ),
                                    Text('-',
                                        style: hPi4Global.moveValueTextStyle),
                                    SizedBox(
                                      width: 10.0,
                                    ),
                                    Text(rangeMaxHR.toString(),
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
                                    Text('BPM',
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
                          Container(
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
                                          SizedBox(
                                            width: 10.0,
                                          ),
                                          Text(averageHR.toString(),
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
                          Container(
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
                                          SizedBox(
                                            width: 10.0,
                                          ),
                                          Text(restingHR.toString(),
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
                                          Text('Latest',
                                              style: hPi4Global.movecardSubValueTextStyle),
                                        ],
                                      ),

                                    ]),
                              ),
                            ),
                          )
                        ]
                    ),
                  ],
                ),
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
                'Heart Rate',
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


class HRTrends {
  HRTrends(this.date, this.maxHR, this.minHR);
  final DateTime date;
  final int maxHR;
  final int minHR;
}
