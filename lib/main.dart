import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import 'home.dart';
import 'screens/scr_main_shell.dart';
import 'screens/scr_trends.dart';
import 'screens/scr_device_scan.dart';
import 'screens/scr_device_mgmt.dart';
import 'screens/scr_device_settings.dart';
import 'screens/scr_settings.dart';
import 'screens/scr_bpt_calibration.dart';
import 'theme/hpi_theme.dart';
import 'utils/ble_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sets the universal_ble log level; without this the plugin stays at its
  // verbose default and floods release logs.
  await BleManager.instance.init();

  runApp(const HealthyPiApp());
}

class HealthyPiApp extends StatelessWidget {
  const HealthyPiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthyPi Move',
      debugShowCheckedModeBanner: false,
      // Redesign theme (dark-only, M3, per-metric identity colors).
      theme: HpiTheme.dark(),
      darkTheme: HpiTheme.dark(),
      themeMode: ThemeMode.dark,
      // Named routes for major screens
      initialRoute: '/',
      routes: {
        // The redesigned 4-tab shell is the app entry; the pre-redesign home
        // stays reachable at /home_legacy for quick rollback during migration.
        '/': (context) => UpgradeAlert(child: const ScrMainShell()),
        '/home_legacy': (context) => UpgradeAlert(child: HomePage()),
        '/scan': (context) => const ScrDeviceScan(),
        '/trends': (context) => const ScrTrends(),
        '/trends/hr': (context) => const ScrTrends(initialMetric: 'hr'),
        '/trends/spo2': (context) => const ScrTrends(initialMetric: 'spo2'),
        '/trends/temp': (context) => const ScrTrends(initialMetric: 'temp'),
        '/trends/activity': (context) => const ScrTrends(initialMetric: 'activity'),
        '/device': (context) => const ScrDeviceMgmt(),
        '/device/settings': (context) => const ScrDeviceSettings(),
        '/device/bpt-calibration': (context) => const ScrBPTCalibration(),
        '/settings': (context) => ScrSettings(),
      },
      // Fallback for an unregistered route name. This must land on the
      // redesigned shell, not the legacy home: the legacy home syncs through
      // BackgroundSyncManager (the pre-HPI_HS path), so falling back to it
      // would silently drop a user onto the old data pipeline.
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const ScrMainShell(),
        );
      },
    );
  }
}