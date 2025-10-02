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
import 'screens/scr_bpt.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  // Add DateTime fields for each value:
  DateTime? lastSyncedDate;
  DateTime? lastUpdatedHRDate;
  DateTime? lastUpdatedTempDate;
  DateTime? lastUpdatedSpo2Date;
  DateTime? lastUpdatedActivityDate;

  bool _isIpad = false;

  @override
  void initState() {
    super.initState();
    _detectIpad();
    _initPackageInfo();
    _loadLastVitalInfo();
    _loadStoredValue();
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        hPi4Global.hpi4AppVersion = info.version;
      });
    }

  }

  Future<void> _loadLastVitalInfo() async {
    await _loadStoredHRValue();
    await _loadStoredSpo2Value();
    await _loadStoredTempValue();
    await _loadStoredActivityValue();
  }

  Future<void> _detectIpad() async {
    bool ipad = await isIPad();
    if (mounted) {
      setState(() {
        _isIpad = ipad;
      });
    }
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
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
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

    List<HRTrends> allData = await hrDataManager.getDataObjects();

    if (monthlyHRTrends.isNotEmpty) {
      MonthlyTrend lastTrend = monthlyHRTrends.last;
      //DateTime lastTime = lastTrend.date; // This is the last day's date in the month with data
      DateTime lastTime = allData.last.date;
      int lastAvg = lastTrend.avg.toInt();
      if (mounted) {
        setState(() {
          saveValue(lastTime, lastAvg, "lastUpdatedHR", "latestHR");
        });
      }

      //print('Last Time: $lastTime, Min: $lastAvg');
    } else {
      //print('No monthly HR trends data available.');
    }
  }

  _loadStoredSpo2Value() {
    Spo2DataManager = CsvDataManager<Spo2Trends>(
      filePrefix: "spo2_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int spo2 = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
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


    List<Spo2Trends> allData = await Spo2DataManager.getDataObjects();

    if (monthlySpo2Trends.isNotEmpty) {
      SpO2MonthlyTrend lastTrend = monthlySpo2Trends.last;
      //DateTime lastTime = lastTrend.date; // This is the last day's date in the month with data
      DateTime lastTime = allData.last.date;
      int lastAvg = lastTrend.avg.toInt();
      if (mounted) {
        setState(() {
          saveValue(lastTime, lastAvg, "lastUpdatedSpo2", "latestSpo2");
        });
      }

     // print('Last Time: $lastTime, Min: $lastAvg');
    } else {
     // print('No monthly HR trends data available.');
    }
  }

  _loadStoredTempValue() {
    tempDataManager = CsvDataManager<TempTrends>(
      filePrefix: "temp_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int minHR = int.tryParse(row[1]) ?? 0;
        int maxHR = int.tryParse(row[2]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
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

    List<TempTrends> allData = await tempDataManager.getDataObjects();

    if (monthlyTempTrends.isNotEmpty) {
      MonthlyTrend lastTrend = monthlyTempTrends.last;
     // DateTime lastTime = lastTrend.date; // This is the last day's date in the month with data
      DateTime lastTime = allData.last.date;
      double lastAvg = floorToOneDecimal(lastTrend.avg / 100);
      if (mounted) {
        setState(() {
          saveTempValue(lastTime, lastAvg, "lastUpdatedTemp", "latestTemp");
        });
      }

      //print('Last Time: $lastTime, Min: $lastAvg');
    } else {
      //print('No monthly Temp trends data available.');
    }
  }

  _loadStoredActivityValue() {
    ActivityDataManager = CsvDataManager<ActivityTrends>(
      filePrefix: "activity_",
      fromRow: (row) {
        int timestamp = int.tryParse(row[0]) ?? 0;
        int count = int.tryParse(row[1]) ?? 0;
        DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
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

    List<ActivityTrends> allData = await ActivityDataManager.getDataObjects();

    if (activityMonthlyTrend.isNotEmpty) {
      ActivityMonthlyTrend lastTrend = activityMonthlyTrend.last;
      //DateTime lastTime = lastTrend.date; // This is the last day's date in the month with data
      DateTime lastTime = allData.last.date;
      int lastAvg = lastTrend.steps;
      if (mounted) {
        setState(() {
          saveValue(
            lastTime,
            lastAvg,
            "lastUpdatedActivity",
            "latestActivityCount",
          );
        });
      }

     // print('Last Time: $lastTime, steps: $lastAvg');
    } else {
      //print('No monthly Activity trends data available.');
    }
  }

  saveValue(
      DateTime lastUpdatedTime,
      int averageHR,
      String latestTimeString,
      String latestValueString,
      ) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(latestValueString, averageHR.toString());
    await prefs.setString(latestTimeString, lastUpdatedTime.toIso8601String().replaceFirst('Z', ''));
  }

  // Save a value
  saveTempValue(
    DateTime lastUpdatedTime,
    double averageHR,
    String latestTimeString,
    String latestValueString,
  ) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(latestValueString, averageHR.toString());
    await prefs.setString(latestTimeString, lastUpdatedTime.toIso8601String().replaceFirst('Z', ''));
  }

  // Load the stored value
  _loadStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      // Parse lastSyncedDateTime as DateTime if possible
      String? lastSyncedRaw = prefs.getString('lastSynced');
      lastSyncedDate = _parseDate(lastSyncedRaw);
      lastSyncedDateTime = getRelativeTime(lastSyncedDate);

      // Repeat for each updated date
      String? lastHRRaw = prefs.getString('lastUpdatedHR');
      lastUpdatedHRDate = _parseDate(lastHRRaw);
      lastUpdatedHR = getRelativeTime(lastUpdatedHRDate);


      String? lastTempRaw = prefs.getString('lastUpdatedTemp');
      lastUpdatedTempDate = _parseDate(lastTempRaw);
      lastUpdatedTemp = getRelativeTime(lastUpdatedTempDate);

      String? lastSpo2Raw = prefs.getString('lastUpdatedSpo2');
      lastUpdatedSpo2Date = _parseDate(lastSpo2Raw);
      lastUpdatedSpo2 = getRelativeTime(lastUpdatedSpo2Date);

      String? lastActivityRaw = prefs.getString('lastUpdatedActivity');
      lastUpdatedActivityDate = _parseDate(lastActivityRaw);
      lastUpdatedActivity = getRelativeTime(lastUpdatedActivityDate);

      // The rest remain unchanged
      lastestHR = (prefs.getString('latestHR') ?? '--') == "0"
          ? '--'
          : prefs.getString('latestHR') ?? '--';
      lastestTemp = (prefs.getString('latestTemp') ?? '--') == "0"
          ? '--'
          : prefs.getString('latestTemp') ?? '--';
      lastestSpo2 = (prefs.getString('latestSpo2') ?? '--') == "0"
          ? '--'
          : prefs.getString('latestSpo2') ?? '--';
      lastestActivity = (prefs.getString('latestActivityCount') ?? '--') == "0"
          ? '--'
          : prefs.getString('latestActivityCount') ?? '--';
    });
  }

  // 3. Add a helper to parse your stored date strings:
  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr == '--') return null;
    try {
      // Try parsing as ISO8601 first
      return DateTime.tryParse(dateStr) ??
          // Try parsing as your formatted string
          DateFormat('EEE d MMM').parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  int getGridCount() {
    if (_isIpad) {
      if (MediaQuery.of(context).orientation == Orientation.landscape) {
        return 3;
      } else {
        return 2;
      }
    } else {
      if (MediaQuery.of(context).orientation == Orientation.landscape) {
        return 3;
      } else {
        return 2;
      }
    }
  }

  double getAspectRatio() {
    // Aspect ratio for metric cards: width / height
    // For 2 columns, with proper card height
    if (_isIpad) {
      if (MediaQuery.of(context).orientation == Orientation.landscape) {
        return 1.5; // Wider cards in landscape
      } else {
        return 1.1; // Slightly tall cards in portrait
      }
    } else {
      if (MediaQuery.of(context).orientation == Orientation.landscape) {
        return 1.6; // Wider cards in landscape
      } else {
        return 0.95; // Cards slightly taller than wide for phones
      }
    }
  }

  Future<bool> isIPad() async {
    if (Platform.isIOS) {
      final deviceInfo = DeviceInfoPlugin();
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.model?.toLowerCase().contains('ipad') ?? false;
    }
    return false;
  }


  // Example usage for HR data:
  late CsvDataManager<HRTrends> hrDataManager;
  late CsvDataManager<TempTrends> tempDataManager;
  late CsvDataManager<Spo2Trends> Spo2DataManager;
  late CsvDataManager<ActivityTrends> ActivityDataManager;

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required String lastUpdated,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black54,
        color: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: accentColor,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        color: accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 32,
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  lastUpdated,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainGrid() {
    _loadLastVitalInfo();
    _loadStoredValue();
    return GridView.count(
      primary: false,
      padding: const EdgeInsets.all(0),
      crossAxisCount: getGridCount(),
      childAspectRatio: getAspectRatio(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        _buildMetricCard(
          title: 'Heart Rate',
          value: lastestHR.toString(),
          unit: 'bpm',
          lastUpdated: lastUpdatedHR.toString(),
          icon: Icons.favorite,
          accentColor: Colors.red[600]!,
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ScrHR()),
            );
          },
        ),
        _buildMetricCard(
          title: 'SpO2',
          value: lastestSpo2.toString(),
          unit: '%',
          lastUpdated: lastUpdatedSpo2.toString(),
          icon: Symbols.spo2,
          accentColor: Colors.blue[600]!,
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ScrSPO2()),
            );
          },
        ),
        _buildMetricCard(
          title: 'Temperature',
          value: lastestTemp,
          unit: '°F',
          lastUpdated: lastUpdatedTemp.toString(),
          icon: Icons.thermostat,
          accentColor: Colors.orange[600]!,
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ScrSkinTemperature()),
            );
          },
        ),
        _buildMetricCard(
          title: 'Activity',
          value: lastestActivity.toString(),
          unit: 'Steps',
          lastUpdated: lastUpdatedActivity.toString(),
          icon: Icons.directions_run,
          accentColor: Colors.green[600]!,
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ScrActivity()),
            );
          },
        ),
      ],
    );
  }

  /*Widget liveViewButton() {
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
  }*/

  void logConsole(String logString) async {
    print("AKW - $logString");
  }

  String getRelativeTime(DateTime? date) {
    if (date == null) return '--';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/healthypi_move.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'HealthyPi Move',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: <Widget>[
                // Last Synced Card
                Card(
                  elevation: 4,
                  shadowColor: Colors.black54,
                  color: const Color(0xFF2D2D2D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: hPi4Global.hpi4Color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.sync,
                            color: hPi4Global.hpi4Color,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Synced',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lastSyncedDateTime.isEmpty ? 'Never' : lastSyncedDateTime,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Info Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange[900]!.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange[700]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange[300],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Sync manually using the button below",
                          style: TextStyle(
                            color: Colors.orange[100],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "1")),
          );
        },
        backgroundColor: hPi4Global.hpi4Color,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.sync, size: 24),
        label: const Text(
          'Sync',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
