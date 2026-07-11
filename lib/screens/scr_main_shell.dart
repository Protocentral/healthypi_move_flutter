import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/hpi_colors.dart';
import '../ui/adaptive/adaptive_scaffold.dart';
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

  @override
  State<ScrMainShell> createState() => _ScrMainShellState();
}

class _ScrMainShellState extends State<ScrMainShell> {
  int _index = 0;

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
