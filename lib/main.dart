import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import 'home.dart';
import 'screens/scr_trends.dart';
import 'screens/scr_device_scan.dart';
import 'screens/scr_device_mgmt.dart';
import 'screens/scr_device_settings.dart';
import 'screens/scr_settings.dart';
import 'screens/scr_bpt_calibration.dart';
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
      theme: ThemeData(
        primarySwatch: Colors.purple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle()),
      ),
      // Named routes for major screens
      initialRoute: '/',
      routes: {
        '/': (context) => UpgradeAlert(child: HomePage()),
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
      // Fallback for direct MaterialPageRoute navigation
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => HomePage(),
        );
      },
    );
  }
}