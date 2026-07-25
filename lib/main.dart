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

/// The oldest app build that can talk to a Move at all.
///
/// v3.0.0 firmware is the first to implement the Healthy Store (HPI_HS, group
/// `0x1000`), and this app has no other sync path — the legacy `0x50`/`0x54` +
/// `/lfs/tr*` protocol was removed. So a pre-3.0.0 *app* paired with a v3
/// watch has nothing to say to it, and a pre-3.0.0 *watch* has nothing to
/// answer with. There is no useful degraded mode to fall back to; the update is
/// mandatory, not advisory.
///
/// [Upgrader.blocked] turns this into a dialog with no Ignore and no Later —
/// see the note on [_upgrader] about which users this actually reaches.
const String kMinimumAppVersion = '3.0.0';

/// Built once, not per `build()`: `routes` runs its builders on every
/// navigation to `/`, and a fresh [Upgrader] each time would re-query the store
/// and reset the "already alerted" bookkeeping.
///
/// **This only forces users who are already on a build that contains it.**
/// Shipped binaries (2.1.0+87) carry their own compiled-in `minAppVersion`,
/// which is unset — so for them the lever is the *store listing* tag, which
/// `upgrader` reads at runtime and feeds into the same [Upgrader.blocked]
/// check. Both are needed: the constant below covers 3.x users on any future
/// bump, the store tag covers everyone already in the field. Tag formats:
///
///   Play Store description:  `[Minimum supported app version: 3.0.0]`
///   App Store description:   `[:mav: 3.0.0]`
final Upgrader _upgrader = Upgrader(minAppVersion: kMinimumAppVersion);

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
        // Ignore/Later are shown for an ordinary optional update, and suppressed
        // automatically by UpgradeAlert when Upgrader.blocked() is true (below
        // the minimum version), so a mandatory update leaves only "Update Now".
        //
        // shouldPopScope feeds PopScope.canPop. Its default is a flat `false`,
        // which also traps the back button on *optional* updates that already
        // have a Later button; this relaxes that to "dismissable unless the
        // update is mandatory", which is the only case that must not be
        // bypassed by a back gesture.
        '/': (context) => UpgradeAlert(
              upgrader: _upgrader,
              shouldPopScope: () => !_upgrader.blocked(),
              child: const ScrMainShell(),
            ),
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