import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:move/scanConnect.dart';
import 'dfu.dart';
import 'screens/skinTempPage.dart';
import 'screens/spo2Page.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'globals.dart';
import 'sizeConfig.dart';
import 'screens/hrPage.dart';
import 'screens/bptCalibrationPage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/cupertino.dart';

int globalHeartRate = 0;
int globalSpO2 = 0;
int globalRespRate = 0;
double globalTemp = 0;
int _globalBatteryLevel = 50;

String pcCurrentDeviceID = "";
String pcCurrentDeviceName = "";

class HomePage extends StatefulWidget {
  HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool connectedToDevice = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Widget _buildAppDrawer() {
    return Drawer(
      backgroundColor: hPi4Global.hpi4Color,
      child: ListView(
        // Important: Remove any padding from the ListView.
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              //color: hPi4Global.hpi4Color,
            ),
            child: Image.asset(
              'assets/healthypi_move.png',
              fit: BoxFit.contain,
            ),
          ),
          ListTile(
            leading: Icon(Icons.search),
            title: Text('DFU'),
            onTap: () {
              Navigator.pop(context);
               Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DeviceManagement(),
                  ));
            },
          ),
          Divider(color: Colors.black),
          _getPoliciesTile(),
          ListTile(
            title: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "v " + hPi4Global.hpi4AppVersion + " ",
                  style: new TextStyle(fontSize: 12),
                ),
                Text(
                  "© 2020-2022 Circuitects Electronic Solutions",
                  style: new TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _getPoliciesTile() {
    return ListTile(
      title: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: OutlinedButton(
              onPressed: () async {
                //_launchURL();
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'circuitects.com', //style: new TextStyle(fontSize: 12)
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: ' Privacy Policy',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.blue),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              //_showPrivacyDialog();
                            },
                    ),
                    TextSpan(
                      text: ' | ',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                    TextSpan(
                      text: 'Terms of use',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.blue),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              //_showTermsDialog();
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  int getGridCount() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return 4;
    } else {
      return 2;
    }
  }

  double getAspectRatio() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return MediaQuery.of(context).size.aspectRatio * 1.65 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 4.2 / 2;
    }
  }

  Widget _buildMainGrid() {
    return GridView.count(
      primary: false,
      padding: const EdgeInsets.all(12),
      crossAxisCount: getGridCount(),
      childAspectRatio: getAspectRatio(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HRPage()));
          },
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('Heartrate', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalHeartRate.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("bpm", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => SPO2Page()));
          },
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalSpO2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => SkinTemperaturePage()),
            );
          },
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('Temperature', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalTemp.toStringAsPrecision(3),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("\u00b0 C", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BPTCalibrationPage()),
            );
          },
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Blood Pressure',
                        style: hPi4Global.movecardTextStyle,
                      ),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalSpO2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      //Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text('Activity', style: hPi4Global.movecardTextStyle),
                    SizedBox(width: 15.0),
                    //Icon(Icons.favorite_border, color: Colors.black),
                  ],
                ),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text('Today', style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text("1 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("Hour", style: hPi4Global.movecardSubValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("12 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("min", style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                SizedBox(height: 40.0),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text(' ', style: hPi4Global.movecardSubValueTextStyle),
                    SizedBox(width: 50.0),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset(
              'assets/healthypi_move.png',
              fit: BoxFit.fitWidth,
              height: 30,
            ),
            MaterialButton(
              child: const Text("Sync", style: hPi4Global.eventsWhite),
              onPressed: (){
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ScanConnectScreen(pageFlag:true)),
                );
              },
              color: hPi4Global.oldHpi4Color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),

          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  //height: SizeConfig.blockSizeVertical * 42,
                  width: SizeConfig.blockSizeHorizontal * 95,
                  child: _buildMainGrid(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                  child: MaterialButton(
                    minWidth: 80.0,
                    height: 50.0,
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Fetch ECG Data',
                        style: new TextStyle(
                          fontSize: 18.0,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    onPressed: () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ScanConnectScreen(pageFlag:false)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChartData {
  ChartData(this.x, this.y);
  final String x;
  final double y;
}
