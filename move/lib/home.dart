import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:move/screens/activityPage.dart';
import 'package:move/screens/scr_device_mgmt.dart';
import 'package:move/settings.dart';
import 'screens/scr_scan.dart';
import 'screens/skinTempPage.dart';
import 'screens/spo2Page.dart';

import 'globals.dart';
import 'sizeConfig.dart';
import 'screens/hrPage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _screens = [HomeScreen(), DevicePage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: hPi4Global.hpi4Color,
        ), // sets the inactive color of the `BottomNavigationBar`
        child: Container(
          color: hPi4Global.hpi4AppBarColor,
          height: Platform.isAndroid ? 80 : 110,
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: BottomNavigationBar(
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
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
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
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool connectedToDevice = false;

  String selectedOption = "sync";
  String lastSyncedDateTime = '';

  String lastestHR = '';
  String lastestTemp = '';
  String lastestSpo2 = '';
  String lastestActivity = '';

  String lastUpdatedHR = '';
  String lastUpdatedTemp = '';
  String lastUpdatedSpo2 = '';
  String lastUpdatedActivity = '';

  String fetchStaus = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _loadStoredValue();
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  // Load the stored value
  _loadStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      lastSyncedDateTime = prefs.getString('lastSynced') ?? '--';
      lastestHR = prefs.getString('latestHR') ?? '--';
      lastestTemp = prefs.getString('latestTemp') ?? "--";
      lastestSpo2 = prefs.getString('latestSpo2') ?? '--';
      lastestActivity = prefs.getString('latestActivityCount') ?? '--';
      lastUpdatedHR = prefs.getString('lastUpdatedHR') ?? '--';
      lastUpdatedTemp = prefs.getString('lastUpdatedTemp') ?? '--';
      lastUpdatedSpo2 = prefs.getString('lastUpdatedSpo2') ?? '--';
      lastUpdatedActivity = prefs.getString('lastUpdatedActivity') ?? '--';
      fetchStaus = prefs.getString('fetchStatus') ?? 'Not synced';
    });
    showSuccessDialog(context, "Data synced");
  }

  void showSuccessDialog(BuildContext context, String message) {
    if (fetchStaus == "Data synced") {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Theme(
            data: ThemeData.dark().copyWith(
              textTheme: TextTheme(),
              dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
            ),
            child: AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text(
                    'Success',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              content: Text(
                message,
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    await prefs.setString('fetchStatus', "Not synced");
                    Navigator.pop(context); // Close the dialog
                  },
                  child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hPi4Global.hpi4Color,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      //Do Nothing;
    }
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
      return MediaQuery.of(context).size.aspectRatio * 3.0 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 3.0 / 2;
    }
  }

  Widget _buildMainGrid() {
    return GridView.count(
      primary: false,
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2, //getGridCount(),
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Heart Rate', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestHR.toString(),
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
                        "Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(
                        lastUpdatedHR.toString(),
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestSpo2.toString(),
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
                        "Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(
                        lastUpdatedSpo2.toString(),
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
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.thermostat, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Temperature', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestTemp,
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("\u00b0 F", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        "Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(
                        lastUpdatedTemp.toString(),
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
              MaterialPageRoute(builder: (_) => ActivityPage()),
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
                      Icon(Icons.directions_run, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Activity', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestActivity.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text(
                        "Steps",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        "Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(
                        lastUpdatedActivity.toString(),
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
            Column(
              children: <Widget>[
                InkWell(
                  onTap: () {
                    //showScanDialog();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "1")),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hPi4Global.hpi4Color,
                    ),
                    child: Icon(
                      Icons.sync,
                      color: hPi4Global.hpi4AppBarIconsColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text(
                      "Last synced: $lastSyncedDateTime",
                      style: hPi4Global.movecardSubValueTextStyle,
                    ),
                    SizedBox(width: 10.0),
                  ],
                ),
                SizedBox(height: 10),
                SizedBox(
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
