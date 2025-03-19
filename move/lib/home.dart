import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:move/scanConnect.dart';
import 'package:move/settings.dart';
import 'device.dart';
import 'screens/skinTempPage.dart';
import 'screens/spo2Page.dart';

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
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    DevicePage(),
    SettingsPage(),
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar:new Theme(
        data: Theme.of(context).copyWith(
            canvasColor: hPi4Global.hpi4Color,
           ), // sets the inactive color of the `BottomNavigationBar`
        child:  Container(
          color:hPi4Global.hpi4AppBarColor,
          height: Platform.isAndroid? 80 : 110,
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child:BottomNavigationBar(
          type: BottomNavigationBarType.shifting, // Shifting
          selectedItemColor: hPi4Global.oldHpi4Color,
          unselectedItemColor: Colors.white,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices),
              label: 'Device',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
    ),
        ),
      ),

    );
  }
}


class HomeScreen extends StatefulWidget {
  HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool connectedToDevice = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
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
      return 1;
    } else {
      return 1;
    }
  }

  double getAspectRatio() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return MediaQuery.of(context).size.aspectRatio * 4.0 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 10.0 / 2;
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
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Heartrate', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      Text(' (Today)', style: hPi4Global.movecardSubValueTextStyle,
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
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 90.0),
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
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      Text('(Today)', style: hPi4Global.movecardSubValueTextStyle,),
                      //Icon(Icons.directions_run, color: Colors.white),
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
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 90.0),
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
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.thermostat, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Temperature', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      Text('(Today)', style: hPi4Global.movecardSubValueTextStyle,),
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
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 90.0),
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
        /*InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BPTCalibrationPage()),
            );
          },
          child: Card(
            color: Colors.grey[900],
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
        ),*/
        Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.directions_run, color: Colors.white),
                    SizedBox(width: 10.0),
                    Text('Activity', style: hPi4Global.movecardTextStyle),
                    SizedBox(width: 15.0),
                    Text('(Today)', style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text("0 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("Hour", style: hPi4Global.movecardSubValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("0 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("min", style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                SizedBox(height: 20.0),
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
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset(
              'assets/healthypi_move.png',
              fit: BoxFit.fitWidth,
              height: 30,
            ),
            IconButton(
              icon: Icon(
                Icons.sync,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
              onPressed: () {

                /*Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ScanConnectScreen(pageFlag:true)),
                );*/
              },
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child:
            Column(
              children: <Widget>[
                SizedBox(height:20),
                Container(
                  //height: SizeConfig.blockSizeVertical * 42,
                  width: SizeConfig.blockSizeHorizontal * 95,
                  child: _buildMainGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

