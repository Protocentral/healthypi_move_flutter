// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

import 'screens/scr_main_shell.dart';
import 'screens/scr_device_scan.dart';
import 'screens/scr_bpt_calibration.dart';
import 'screens/scr_blood_pressure.dart';
import 'theme/hpi_theme.dart';
import 'ui/components/hpi_synthetic_banner.dart';
import 'utils/ble_manager.dart';
import 'utils/healthy_store_sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sets the universal_ble log level; without this the plugin stays at its
  // verbose default and floods release logs.
  await BleManager.instance.init();

  // Drop any leftover synthetic-QA opt-in and rebuild trends from real samples
  // only — fabricated firmware test data must never stay on charts after QA.
  await HealthyStoreSyncManager.instance.ensureRealDataOnly();

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
      // Wraps every route (pushed screens and dialogs included), so no chart can
      // render fabricated samples without the app saying so on screen.
      builder: (context, child) =>
          HpiSyntheticBanner(child: child ?? const SizedBox.shrink()),
      // Named routes for major screens
      initialRoute: '/',
      routes: {
        // The redesigned 4-tab shell is the app entry. The pre-redesign screens
        // (legacy home / trends / device / settings) have been deleted; all
        // in-app navigation now goes through the shell and MaterialPageRoutes.
        '/': (context) => UpgradeAlert(child: const ScrMainShell()),
        '/scan': (context) => const ScrDeviceScan(),
        '/device/bpt-calibration': (context) => const ScrBPTCalibration(),
        '/blood-pressure': (context) => const ScrBloodPressure(),
      },
      // Fallback for an unregistered route name — always the redesigned shell.
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const ScrMainShell(),
        );
      },
    );
  }
}