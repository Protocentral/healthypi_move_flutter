import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/hpi_colors.dart';
import '../ui/adaptive/adaptive_scaffold.dart';
import '../utils/device_manager.dart';
import 'scr_home.dart';
import 'scr_settings.dart';
import 'scr_trends_hub.dart';
import 'scr_device_mgmt.dart';
import 'scr_stream_selection.dart';

/// The redesigned app shell: a 4-tab adaptive scaffold (Home · Trends · Live ·
/// Device) that becomes a NavigationRail on tablets. Settings is a pushed route
/// off the Home header, per the handoff. Non-Home tabs still host the existing
/// screens — they get their own redesign in later passes (docs/REDESIGN_PLAN.md).
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
        MaterialPageRoute(builder: (_) => ScrSettings()));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const ScrHome(),
      const ScrTrendsHub(),
      const _LiveTab(),
      const ScrDeviceMgmt(),
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

/// The Live tab needs a paired device to stream. Resolve it once; if none is
/// paired yet, show a prompt into the scan flow instead of the stream selector.
class _LiveTab extends StatelessWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DeviceManager.getPairedDevice(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: HpiColors.hr));
        }
        final device = snapshot.data;
        if (device == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Symbols.ecg_heart,
                      size: 44, color: HpiColors.disabled),
                  const SizedBox(height: 12),
                  const Text('Pair a device to stream live signals',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HpiColors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/scan'),
                    child: const Text('Scan for devices'),
                  ),
                ],
              ),
            ),
          );
        }
        return ScrStreamsSelection(
            deviceId: device.macAddress, deviceName: device.displayName);
      },
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
