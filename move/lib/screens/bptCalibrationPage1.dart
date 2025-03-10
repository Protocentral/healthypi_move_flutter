import 'package:flutter/material.dart';

import '../globals.dart';
import '../sizeConfig.dart';
import 'package:fl_chart/fl_chart.dart';
//import 'bptCalibrationPage.dart';

class BPTCalibrationPage1 extends StatefulWidget {
  @override
  State<BPTCalibrationPage1> createState() => _BPTCalibrationPage1State();
}

class _BPTCalibrationPage1State extends State<BPTCalibrationPage1> {

  final ppgLineData = <FlSpot>[];

  double ppgDataCounter = 0;

  @override
  void initState() {
    super.initState();
  }

  LineChartBarData currentLine(List<FlSpot> points, Color plotcolor) {
    return LineChartBarData(
      spots: points,
      dotData: FlDotData(
        show: false,
      ),
      gradient: LinearGradient(
        colors: [plotcolor, plotcolor],
        //stops: const [0.1, 1.0],
      ),
      barWidth: 4,
      isCurved: false,
    );
  }

  buildChart(int vertical, int horizontal, List<FlSpot> source, Color plotColor){
    return Container(
      height: SizeConfig.blockSizeVertical * vertical,
      width: SizeConfig.blockSizeHorizontal * horizontal,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(enabled: false),
          clipData: FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(
            show: false,
            //border: Border.all(color: const Color(0xff37434d)),
          ),

          lineBarsData: [
            currentLine(source,plotColor),
          ],
        ),
        //swapAnimationDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/healthypi5.png',
                fit: BoxFit.fitWidth, height: 30),
          ],
        ),
      ),
      body:  Center(
        child: Column(children: <Widget>[
          Container(
            height: SizeConfig.blockSizeVertical * 30,
            width: SizeConfig.blockSizeHorizontal * 95,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        //Icon(Icons.warning, color: Colors.yellow[300]),
                        Text('Calibration',
                            style: new TextStyle(fontSize: 24.0, color: hPi4Global.hpi4Color)),
                      ],
                    ),
                    SizedBox(height: 10.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        Expanded(
                          // optional flex property if flex is 1 because the default flex is 1
                          flex: 1,
                          child: TextField(
                            decoration: InputDecoration(
                                labelText: 'Systolic',
                                labelStyle: TextStyle(
                                    color: Colors.grey[400]
                                ),
                              filled: true,
                              //fillColor: Colors.blueAccent,
                              border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(16)
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 20.0),
                        Expanded(
                          // optional flex property if flex is 1 because the default flex is 1
                          flex: 1,
                          child: TextField(
                            decoration: InputDecoration(
                                labelText: 'Diastolic',
                                labelStyle: TextStyle(
                                    color: Colors.grey[400]
                                ),
                              filled: true,
                              //fillColor: Colors.blueAccent,
                              border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(16)
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 15.0),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                      child:Align(
                          alignment: Alignment.center,
                          child: OutlinedButton(
                            onPressed: () {

                            },
                            child: Text('Start',
                                style: new TextStyle(fontSize: 18.0, color: hPi4Global.hpi4Color)),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                      ),
                    ),

                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: SizeConfig.blockSizeVertical * 3,
          ),
          Container(
            height: SizeConfig.blockSizeVertical * 40,
            width: SizeConfig.blockSizeHorizontal * 95,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: buildChart(27, 95, ppgLineData, Colors.yellow),
              ),
            ),
          ),

        ]),
      ),
    );
  }

}