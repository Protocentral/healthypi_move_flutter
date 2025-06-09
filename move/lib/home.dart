import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:move/screens/csvData.dart';
import 'package:move/screens/scr_activity.dart';
import 'package:move/screens/scr_device_mgmt.dart';
import 'package:move/screens/scr_settings.dart';
import 'screens/scr_scan.dart';
import 'screens/scr_skin_temp.dart';
import 'screens/scr_spo2.dart';

import 'globals.dart';
import 'utils/sizeConfig.dart';
import 'screens/scr_hr.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _screens = [HomeScreen(), ScrDeviceMgmt(), ScrSettings()];

  bottomBarHeight() {
    if (Platform.isIOS) {
      return 110.0;
    }
  }

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
          height: bottomBarHeight(),
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

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _loadLastVitalInfo();
    _loadStoredValue();
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  Future<void> _loadLastVitalInfo() async {
    await _loadStoredHRValue();
    await _loadStoredSpo2Value();
    await _loadStoredTempValue();
    await _loadStoredActivityValue();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  double floorToOneDecimal(double value) {
    return (value * 10).floor() / 10;
  }

  _loadStoredHRValue() {
    hrDataManager = CsvDataManager<HRTrends>(
      filePrefix: "hr_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int minHR = int.tryParse(row[1]) ?? 0;
        int maxHR = int.tryParse(row[2]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return HRTrends(date, maxHR, minHR);
      },
      getFileType: (file) => "hr",
    );
    _loadHRData();
  }

  Future<void> _loadHRData() async {
    DateTime today = DateTime.now();
    List<MonthlyTrend> monthlyHRTrends = await hrDataManager.getMonthlyTrend(
      today,
    );

    if (monthlyHRTrends.isNotEmpty) {
      MonthlyTrend lastTrend = monthlyHRTrends.last;
      DateTime lastTime =
          lastTrend.date; // This is the last day's date in the month with data
      double lastAvg = floorToOneDecimal(lastTrend.avg);
      setState(() {
        saveValue(lastTime, lastAvg, "lastUpdatedHR", "latestHR");
      });
      print('Last Time: $lastTime, Min: $lastAvg');
    } else {
      print('No monthly HR trends data available.');
    }
  }

  _loadStoredSpo2Value() {
    Spo2DataManager = CsvDataManager<Spo2Trends>(
      filePrefix: "spo2_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int spo2 = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return Spo2Trends(date, spo2, 0);
      },
      getFileType: (file) => "spo2",
    );
    _loadSpo2Data();
  }

  Future<void> _loadSpo2Data() async {
    DateTime today = DateTime.now();
    List<SpO2MonthlyTrend> monthlySpo2Trends =
        await Spo2DataManager.getSpO2MonthlyTrend(today);
    if (monthlySpo2Trends.isNotEmpty) {
      SpO2MonthlyTrend lastTrend = monthlySpo2Trends.last;
      DateTime lastTime =
          lastTrend.date; // This is the last day's date in the month with data
      double lastAvg = floorToOneDecimal(lastTrend.avg);
      setState(() {
        saveValue(lastTime, lastAvg, "lastUpdatedSpo2", "latestSpo2");
      });
      print('Last Time: $lastTime, Min: $lastAvg');
    } else {
      print('No monthly HR trends data available.');
    }
  }

  _loadStoredTempValue() {
    tempDataManager = CsvDataManager<TempTrends>(
      filePrefix: "temp_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int minHR = int.tryParse(row[1]) ?? 0;
        int maxHR = int.tryParse(row[2]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return TempTrends(date, maxHR.toDouble(), minHR.toDouble());
      },
      getFileType: (file) => "temp",
    );
    _loadTempData();
  }

  Future<void> _loadTempData() async {
    DateTime today = DateTime.now();
    List<MonthlyTrend> monthlyTempTrends = await tempDataManager
        .getMonthlyTrend(today);

    if (monthlyTempTrends.isNotEmpty) {
      MonthlyTrend lastTrend = monthlyTempTrends.last;
      DateTime lastTime =
          lastTrend.date; // This is the last day's date in the month with data
      double lastAvg = floorToOneDecimal(lastTrend.avg / 100);
      setState(() {
        saveValue(lastTime, lastAvg, "lastUpdatedTemp", "latestTemp");
      });
      print('Last Time: $lastTime, Min: $lastAvg');
    } else {
      print('No monthly Temp trends data available.');
    }
  }

  _loadStoredActivityValue() {
    ActivityDataManager = CsvDataManager<ActivityTrends>(
      filePrefix: "activity_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int count = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        return ActivityTrends(date, count);
      },
      getFileType: (file) => "activity",
    );
    _loadActivityData();
  }

  Future<void> _loadActivityData() async {
    DateTime today = DateTime.now();
    List<ActivityMonthlyTrend> activityMonthlyTrend =
        await ActivityDataManager.getActivityMonthlyTrend(today);

    if (activityMonthlyTrend.isNotEmpty) {
      ActivityMonthlyTrend lastTrend = activityMonthlyTrend.last;
      DateTime lastTime =
          lastTrend.date; // This is the last day's date in the month with data
      double lastAvg = floorToOneDecimal(lastTrend.steps.toDouble());
      setState(() {
        saveValue(
          lastTime,
          lastAvg,
          "lastUpdatedActivity",
          "latestActivityCount",
        );
      });
      print('Last Time: $lastTime, steps: $lastAvg');
    } else {
      print('No monthly Activity trends data available.');
    }
  }

  // Save a value
  saveValue(
    DateTime lastUpdatedTime,
    double averageHR,
    String latestTimeString,
    String latestValueString,
  ) async {
    String lastDateTime = DateFormat('EEE d MMM').format(lastUpdatedTime);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(latestValueString, averageHR.toString());
    await prefs.setString(latestTimeString, lastDateTime);
  }

  // Load the stored value
  _loadStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      lastSyncedDateTime =
          (prefs.getString('lastSynced') ?? '--') == '0'
              ? '--'
              : prefs.getString('lastSynced') ?? '--';
      lastestHR =
          (prefs.getString('latestHR') ?? '--') == "0"
              ? '--'
              : prefs.getString('latestHR') ?? '--';
      lastestTemp =
          (prefs.getString('latestTemp') ?? '--') == "0"
              ? '--'
              : prefs.getString('latestTemp') ?? '--';
      lastestSpo2 =
          (prefs.getString('latestSpo2') ?? '--') == "0"
              ? '--'
              : prefs.getString('latestSpo2') ?? '--';
      lastestActivity =
          (prefs.getString('latestActivityCount') ?? '--') == "0"
              ? '--'
              : prefs.getString('latestActivityCount') ?? '--';
      lastUpdatedHR =
          (prefs.getString('lastUpdatedHR') ?? '--') == "0"
              ? '--'
              : prefs.getString('lastUpdatedHR') ?? '--';
      lastUpdatedTemp =
          (prefs.getString('lastUpdatedTemp') ?? '--') == "0"
              ? '--'
              : prefs.getString('lastUpdatedTemp') ?? '--';
      lastUpdatedSpo2 =
          (prefs.getString('lastUpdatedSpo2') ?? '--') == "0"
              ? '--'
              : prefs.getString('lastUpdatedSpo2') ?? '--';
      lastUpdatedActivity =
          (prefs.getString('lastUpdatedActivity') ?? '--') == "0"
              ? '--'
              : prefs.getString('lastUpdatedActivity') ?? '--';
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
      return MediaQuery.of(context).size.aspectRatio * 3.0 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 3.0 / 2;
    }
  }

  // Example usage for HR data:
  late CsvDataManager<HRTrends> hrDataManager;
  late CsvDataManager<TempTrends> tempDataManager;
  late CsvDataManager<Spo2Trends> Spo2DataManager;
  late CsvDataManager<ActivityTrends> ActivityDataManager;

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
            ).pushReplacement(MaterialPageRoute(builder: (_) => ScrHR()));
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
                      //SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestHR.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("bpm", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      /*Text(
                        "Updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),*/
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
            ).pushReplacement(MaterialPageRoute(builder: (_) => ScrSPO2()));
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
                      Icon(Symbols.spo2, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      //SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestSpo2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
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
              MaterialPageRoute(builder: (_) => ScrSkinTemperature()),
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
                      // SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestTemp,
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("\u00b0 F", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      /*Text(
                        "Updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),*/
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
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => ScrActivity()));
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
                      //SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        lastestActivity.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("Steps", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),

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

  Widget liveViewButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 36), // Minimum width, reasonable height
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Minimal padding
          backgroundColor: hPi4Global.hpi4Color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "3")),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min, // Shrink to fit content
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Symbols.monitoring, color: Colors.white, size: 18),
            const Text(
              ' Live View',
              style: TextStyle(fontSize: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void logConsole(String logString) async {
    print("AKW - $logString");
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
            Column(children: <Widget>[]),
          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                SizedBox(height: 10),
                // Add this note above "Last synced"
                
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
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Text(
                    "Note: Sync has to be done manually using the Sync button below.",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                SizedBox(height: 10),
                SizedBox(
                  width: SizeConfig.blockSizeHorizontal * 95,
                  child: _buildMainGrid(),
                ),
                // REMOVE the Live View button from Home tab:
                // SizedBox(
                //   width: SizeConfig.blockSizeHorizontal * 90,
                //   child: liveViewButton(),
                // ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Theme(
        data: Theme.of(context).copyWith(
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            shape: const CircleBorder(),
            backgroundColor: Colors.amber, // Changed to a standout color
            foregroundColor: Colors.black, // Black icon for contrast
          ),
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "1")),
            );
          },
          tooltip: 'Sync',
          child: const Icon(Icons.sync, size: 32),
        ),
      ),
    );
  }
}
