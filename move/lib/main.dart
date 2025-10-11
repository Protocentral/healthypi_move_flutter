import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import 'home.dart';
import 'screens/scr_trends.dart';
import 'screens/scr_device_scan.dart';
import 'screens/scr_device_mgmt.dart';
import 'screens/scr_device_settings.dart';
import 'screens/scr_settings.dart';
import 'screens/scr_dfu.dart';
import 'screens/scr_bpt_calibration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        '/device/dfu': (context) => const ScrDFU(),
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