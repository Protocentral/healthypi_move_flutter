// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/hpi_colors.dart';
import '../ui/adaptive/adaptive_scaffold.dart';
import '../utils/auto_sync_controller.dart';
import '../utils/database_helper.dart';
import 'scr_device_new.dart';
import 'scr_home.dart';
import 'scr_live.dart';
import 'scr_settings_new.dart';
import 'scr_trends_hub.dart';

/// The redesigned app shell: a 4-tab adaptive scaffold (Home · Trends · Live ·
/// Device) that becomes a NavigationRail on tablets. Settings is a pushed route
/// (rail avatar / Device header), per the handoff. All four tabs now host
/// redesigned screens (docs/REDESIGN_PLAN.md).
class ScrMainShell extends StatefulWidget {
  const ScrMainShell({super.key});

  /// Return to the app root from a terminal point in a pushed flow (DFU done,
  /// BPT calibration finished, device unpaired, back out of streaming).
  ///
  /// Every such site used to `pushReplacement` a fresh legacy `HomePage`.
  /// Route every "go home" through here so there is one way back and it lands
  /// on the redesigned shell (Healthy Store sync, not the retired custom path).
  static void returnToRoot(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ScrMainShell()),
      (route) => false,
    );
  }

  @override
  State<ScrMainShell> createState() => _ScrMainShellState();
}

class _ScrMainShellState extends State<ScrMainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Foreground auto-sync + the proactive firmware check both hang off the
    // shell's lifetime rather than `main()`, so they start once the app has a
    // UI and restart cleanly after `returnToRoot` (notably straight after a DFU,
    // where the firmware version has just changed). Both are idempotent.
    AutoSyncController.instance.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _legacyDataNotice());
  }

  /// Explain the history gap left by the v8 database upgrade, exactly once.
  ///
  /// Shown here rather than in Settings because the user who needs it will not
  /// go looking: they open the app, find months of charts missing, and conclude
  /// the update broke something. `acknowledgeLegacyDataCleared` runs only after
  /// they dismiss it, so a crash or a force-quit first means they still get told.
  Future<void> _legacyDataNotice() async {
    final rows = await DatabaseHelper.instance.pendingLegacyDataClearedNotice();
    if (rows == null || rows <= 0 || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Older history was cleared'),
        content: const Text(
          'Health data recorded by firmware older than 3.0 used a format that '
          'did not store a timezone, so those readings could not be placed '
          'correctly on a clock and have been removed.\n\n'
          'Everything recorded since is unaffected, and new data keeps syncing '
          'normally.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    await DatabaseHelper.instance.acknowledgeLegacyDataCleared();
  }

  static const _destinations = [
    HpiDestination(icon: Symbols.home, label: 'Home'),
    HpiDestination(icon: Symbols.monitoring, label: 'Trends'),
    HpiDestination(icon: Symbols.ecg_heart, label: 'Live'),
    HpiDestination(icon: Symbols.watch, label: 'Device'),
  ];

  void _openSettings() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ScrSettingsNew()));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const ScrHome(),
      const ScrTrendsHub(),
      const ScrLive(),
      const ScrDeviceNew(),
    ];
    return HpiAdaptiveScaffold(
      destinations: _destinations,
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      railLeading: _RailAvatar(onTap: _openSettings),
      body: IndexedStack(index: _index, children: tabs),
    );
  }
}

class _RailAvatar extends StatelessWidget {
  const _RailAvatar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HpiMetricColors.tint(HpiColors.hr, 0.16),
          shape: BoxShape.circle,
        ),
        child: const Icon(Symbols.watch, size: 20, color: HpiColors.hr),
      ),
    );
  }
}
