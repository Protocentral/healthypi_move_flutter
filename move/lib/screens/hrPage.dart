import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
    _listCSVFiles();
  }

  @override
  void dispose() {
    super.dispose();
  }


  Widget buildchartBlock() {
    // Get the current date
    final DateTime now = DateTime.now();
    // Calculate the start of the day (00:00)
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    // Calculate the end of the day (24:00)
    final DateTime endOfDay = startOfDay.add(Duration(hours: 24));
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
                      primaryXAxis: DateTimeAxis(
                        interval: 1,
                        //intervalType: DateTimeIntervalType.hours,
                        intervalType: DateTimeIntervalType.years,
                        dateFormat: DateFormat.H(),
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
      downloadsDirectory = Directory('/storage/emulated/0/Download');
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
        print("......"+fileNames.toString());

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
          String todayStr = _formatDate(now);
          if (_formatDate(timestampDateTime) == todayStr) {
            getFileData(fileName1);
           // print("same..........");
          }else{
           // print("different........");
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
      downloadsDirectory = Directory('/storage/emulated/0/Download');
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

    minHR = result.map((f) => f.split(",")[1]).toList();

    maxHR = result.map((f) => f.split(",")[2]).toList();

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
        hrTrendsData.add(HRTrends(DateTime.fromMillisecondsSinceEpoch(tempTimeStamp1),
            tempMinHR, tempMaxHR));
        if( i == timestamp.length-1){
          averageHR = tempAvgHR;
          restingHR = tempLatestHR;
          rangeMinHR = tempMinHR;
          rangeMaxHR = tempMaxHR;
        }

      });

    }

  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
                child: const TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: hPi4Global.hpi4Color,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white,
                  tabs: [
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
          children: [
            Card(
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
                                            Text('67',
                                                style: hPi4Global.moveValueTextStyle),
                                            SizedBox(
                                              width: 10.0,
                                            ),
                                            Text('-',
                                                style: hPi4Global.moveValueTextStyle),
                                            SizedBox(
                                              width: 10.0,
                                            ),
                                            Text('167',
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
                                                  Text('87',
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
                                                  Text('67',
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
                                                  Text('RESTING',
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
            ),
            /*Card(
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
                        SizedBox(height:60),

                      ],
                    ),
                  ],
                ),
              ),
            ),*/
            const Center(child: Text('Week')),
            const Center(child: Text('Month')),
          ],
        ),
      ),
    );
  }
}


class HRTrends {
  HRTrends(this.date, this.maxHR, this.minHR);
  final DateTime date;
  final int maxHR;
  final int minHR;
}
