import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'home.dart';
import 'pdfGenerator.dart';
import 'sizeConfig.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'globals.dart';

import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert' show LineSplitter, utf8;

class HRPage extends StatefulWidget {
  const HRPage({Key? key}) : super(key: key);
  @override
  State<HRPage> createState() => _HRPageState();
}
class _HRPageState extends State<HRPage>
    with SingleTickerProviderStateMixin {

  @override
  void initState() {
    super.initState();
  }

  Widget buildchartBlock() {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                  child: SfCartesianChart(
                      primaryXAxis: NumericAxis(
                          minimum: 0,
                          maximum: 150
                      ),
                      primaryYAxis: NumericAxis(
                          minimum: 0,
                          maximum: 200
                      ),
                      palette: <Color>[
                      Color(0xFF125871),
                      ],
                      series: <CartesianSeries>[
                        HiloSeries<ChartData, int>(
                            dataSource: <ChartData>[
                              ChartData(50, 60, 70),
                              ChartData(55, 61, 95),
                              ChartData(60, 62, 71),
                              ChartData(65, 61, 73),
                              ChartData(70, 60, 75),
                            ],
                            xValueMapper: (ChartData data, _) => data.x,
                            lowValueMapper: (ChartData data, _) => data.low,
                            highValueMapper: (ChartData data, _) => data.high
                        ),
                      ]
                  )
              )
            ]),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HomePage()))
          ),
          title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              //mainAxisSize: MainAxisSize.max,
              children: [
                const Text(
                  'Heart Rate',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(width:30.0),
                IconButton(
                    icon: Icon(Icons.file_open, color: Colors.black),
                    onPressed: () async{

                      String myData = await rootBundle.loadString("assets/test.txt");
                      List<String> result = myData.split('\n');
                      print(result);
                      List<String> timestamp = result.map((f) => f.split(",")[0]).toList();

                      List<String> HR = result.map((f) => f.split(",")[1]).toList();

                      List<String> HR1 = result.map((f) => f.split(",")[2]).toList();

                      //print(".........time"+timestamp.toString());
                      //print(".........HR"+HR.toString());
                      //print(".........HR1"+HR1.toString());

                    }
                ),
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
                  color: Colors.grey.shade100,
                ),
                child: const TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: hPi4Global.hpi4Color,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.black54,
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
              color: Colors.grey[200],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: SizeConfig.blockSizeVertical * 10,
                          width: SizeConfig.blockSizeHorizontal * 80,
                          //color:Colors.white,
                          child:const Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("91", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black),),
                              Text("BPM", style: TextStyle(fontSize: 12, color: Colors.black),),
                            ],
                          ),
                        ),
                        SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 45,
                              width: SizeConfig.blockSizeHorizontal * 88,
                              //color:Colors.white,
                              child:buildchartBlock(),
                            )
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: SizeConfig.blockSizeVertical * 20,
                              width: SizeConfig.blockSizeHorizontal * 44,
                              child: Card(
                               // color: Colors.white,
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
                                      //color: Colors.white,
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
                                      //color: Colors.white,
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
            const Center(child: Text('Week')),
            const Center(child: Text('Month')),
          ],
        ),
      ),
    );
  }
}


class ChartData {
  ChartData(this.x, this.high, this.low);
  final int x;
  final double high;
  final double low;
}
