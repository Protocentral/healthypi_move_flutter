import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'utils/trends_data_manager.dart';
import 'utils/background_sync_manager.dart';
import 'utils/device_manager.dart';
import 'utils/database_helper.dart';
import 'package:move/screens/scr_device_mgmt.dart';
import 'package:move/screens/scr_settings.dart';
import 'package:move/screens/scr_trends.dart';
import 'screens/scr_device_scan.dart';
import 'globals.dart';
import 'utils/sizeConfig.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:device_info_plus/device_info_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    ScrTrends(),
    ScrDeviceMgmt(),
    ScrSettings(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark background to match theme
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: hPi4Global.hpi4Color,
            unselectedItemColor: Colors.grey[500],
            selectedFontSize: 12,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded, size: 24),
                activeIcon: Icon(Icons.home_rounded, size: 26),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.trending_up_rounded, size: 24),
                activeIcon: Icon(Icons.trending_up_rounded, size: 26),
                label: 'Trends',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.watch_rounded, size: 24),
                activeIcon: Icon(Icons.watch_rounded, size: 26),
                label: 'Device',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_rounded, size: 24),
                activeIcon: Icon(Icons.settings_rounded, size: 26),
                label: 'Settings',
              ),
            ],
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
  
  // Vitals data loaded directly from database
  Map<String, Map<String, dynamic>?>? _vitals;
  DateTime? _lastSyncTime;

  bool _isIpad = false;
  bool _isLoadingData = false;
  
  // Background sync state
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _syncStatus = '';
  StreamSubscription? _syncProgressSubscription;

  @override
  void initState() {
    super.initState();
    
    // Initialize activity data manager (matches scr_activity.dart pattern)
    activityDataManager = TrendsDataManager(hPi4Global.PREFIX_ACTIVITY);
    
    _detectIpad();
    _initPackageInfo();
    _loadDataFromDatabase();
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        hPi4Global.hpi4AppVersion = info.version;
      });
    }

  }

  Future<void> _loadDataFromDatabase() async {
    if (_isLoadingData) return; // Prevent concurrent loads
    _isLoadingData = true;
    
    try {
      // Load vitals and sync time from database
      final vitals = await DatabaseHelper.instance.getLatestVitals();
      final syncTime = await DatabaseHelper.instance.getLastSyncTime();
      
      // For activity, use the SAME logic as the trends screen:
      // Get hourly trends and sum them (matches scr_activity.dart exactly)
      if (vitals['activity'] != null) {
        try {
          List<HourlyTrend> hourlyTrends = await activityDataManager.getHourlyTrendForToday();
          if (hourlyTrends.isNotEmpty) {
            int totalDailySteps = 0;
            for (var trend in hourlyTrends) {
              totalDailySteps += trend.max.toInt();
            }
            // Update the activity value with the calculated total
            vitals['activity']!['value'] = totalDailySteps;
          }
        } catch (e) {
          print('Error calculating activity total: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _vitals = vitals;
          _lastSyncTime = syncTime;
        });
      }
    } catch (e) {
      print('Error loading data from database: $e');
    } finally {
      _isLoadingData = false;
    }
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
    _syncProgressSubscription?.cancel();
    super.dispose();
  }

  // Helper to get formatted vital values and timestamps
  String _getVitalValue(String type) {
    if (_vitals == null || _vitals![type] == null) return '--';
    final value = _vitals![type]!['value'] as int;
    if (value == 0) return '--';
    
    // Temperature needs special formatting (divide by 100)
    if (type == 'temp') {
      return (value / 100).toStringAsFixed(1);
    }
    return value.toString();
  }

  String _getVitalTimestamp(String type) {
    if (_vitals == null || _vitals![type] == null) return '--';
    final timestamp = _vitals![type]!['timestamp'] as int;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return getRelativeTime(date);
  }

  String get lastSyncedDateTime {
    if (_lastSyncTime == null) return 'Never';
    return getRelativeTime(_lastSyncTime);
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
      return iosInfo.model.toLowerCase().contains('ipad');
    }
    return false;
  }


  // SQLite data managers for dashboard metrics
  late TrendsDataManager hrDataManager;
  late TrendsDataManager tempDataManager;
  late TrendsDataManager spo2DataManager;
  late TrendsDataManager activityDataManager;

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
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 32,
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
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
    // Data loading is handled in initState() and should not be called here
    // to avoid repeated database queries on every build
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
          value: _getVitalValue('hr'),
          unit: 'bpm',
          lastUpdated: _getVitalTimestamp('hr'),
          icon: Icons.favorite,
          accentColor: Colors.red[600]!,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScrTrends(initialMetric: 'hr'),
              ),
            );
          },
        ),
        _buildMetricCard(
          title: 'SpO2',
          value: _getVitalValue('spo2'),
          unit: '%',
          lastUpdated: _getVitalTimestamp('spo2'),
          icon: Symbols.spo2,
          accentColor: Colors.blue[600]!,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScrTrends(initialMetric: 'spo2'),
              ),
            );
          },
        ),
        _buildMetricCard(
          title: 'Temperature',
          value: _getVitalValue('temp'),
          unit: '°F',
          lastUpdated: _getVitalTimestamp('temp'),
          icon: Icons.thermostat,
          accentColor: Colors.orange[600]!,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScrTrends(initialMetric: 'temp'),
              ),
            );
          },
        ),
        _buildMetricCard(
          title: 'Activity',
          value: _getVitalValue('activity'),
          unit: 'Steps',
          lastUpdated: 'Today',  // Activity always shows "Today"
          icon: Icons.directions_run,
          accentColor: Colors.green[600]!,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ScrTrends(initialMetric: 'activity'),
              ),
            );
          },
        ),
      ],
    );
  }

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

  Future<void> _handleRefresh() async {
    if (_isSyncing) {
      // Already syncing, show message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sync already in progress'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Get paired device
    final deviceInfo = await DeviceManager.getPairedDevice();
    if (deviceInfo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No device paired. Please pair a device first.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Pair',
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScrDeviceScan()),
                );
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Start background sync (BackgroundSyncManager handles ALL BLE operations)
    debugPrint('Home: Starting sync for device: ${deviceInfo.macAddress}');
    debugPrint('Home: BackgroundSyncManager will handle all BLE connection/disconnection');

    if (mounted) {
      setState(() {
        _isSyncing = true;
        _syncProgress = 0.0;
        _syncStatus = 'Starting sync...';
      });
    }

    // Listen to progress updates
    _syncProgressSubscription = BackgroundSyncManager.instance.progressStream.listen(
      (progress) {
        if (mounted && progress.metric == 'all') {
          setState(() {
            _syncProgress = progress.progress;
            _syncStatus = progress.message ?? '';
          });
        }
      },
    );

    // Start sync - pass only MAC address string
    final result = await BackgroundSyncManager.instance.syncData(
      deviceMacAddress: deviceInfo.macAddress,
      onProgress: (metric, progress) {
        // Progress updates handled via stream
      },
      onStatus: (status) {
        if (mounted) {
          setState(() {
            _syncStatus = status;
          });
        }
      },
    );

    // Cleanup subscription
    await _syncProgressSubscription?.cancel();
    _syncProgressSubscription = null;

    // Update UI
    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncProgress = 0.0;
        _syncStatus = '';
      });

      // Show result
      if (result.success) {
        final totalRecords = result.recordCounts.values.fold(0, (sum, count) => sum + count);
        final message = totalRecords > 0
            ? '✓ Synced $totalRecords records in ${result.duration.inSeconds}s'
            : '✓ ${result.message}';
        
        // Update lastSynced timestamp in database
        await DatabaseHelper.instance.updateLastSyncTime();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Reload data from database
        await _loadDataFromDatabase();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ ${result.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
        title: Image.asset(
          'assets/healthypi_move.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        centerTitle: false,
        bottom: _isSyncing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4.0),
                child: LinearProgressIndicator(
                  value: _syncProgress,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: hPi4Global.hpi4Color,
        backgroundColor: const Color(0xFF2D2D2D),
        displacement: 60, // Move the refresh indicator higher to avoid covering content
        strokeWidth: 3.0,
        child: ListView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: _isSyncing ? 60 : 20, // Extra top padding when syncing to avoid overlap
            bottom: 20,
          ),
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
                          child: _isSyncing
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                                  ),
                                )
                              : Icon(
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
                                _isSyncing ? 'Syncing...' : 'Last Synced',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSyncing
                                    ? _syncStatus
                                    : (lastSyncedDateTime.isEmpty ? 'Never' : lastSyncedDateTime),
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
                          "Pull down to sync data with your device",
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSyncing ? null : _handleRefresh,
        backgroundColor: _isSyncing ? Colors.grey : hPi4Global.hpi4Color,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: _isSyncing 
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.sync, size: 24),
        label: Text(
          _isSyncing ? 'Syncing...' : 'Sync',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
