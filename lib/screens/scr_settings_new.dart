// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/database_helper.dart';
import 'scr_developer.dart';

/// Settings (handoff 1i). A pushed route (no nav bar). Preference rows that
/// aren't yet wired to real settings show their current value read-only,
/// honestly, rather than faking controls.
///
/// The developer card is now only a **gate**: the toggle (persisted, so it
/// survives restarts) reveals a single row into [ScrDeveloper], which owns every
/// developer control. It used to inline them here, including two rows — "BLE
/// console" and "Raw packet log" — that pushed the same screen.
class ScrSettingsNew extends StatefulWidget {
  const ScrSettingsNew({super.key});

  static const devModePrefKey = 'developer_mode_enabled';

  @override
  State<ScrSettingsNew> createState() => _ScrSettingsNewState();
}

class _ScrSettingsNewState extends State<ScrSettingsNew> {
  bool _devMode = false;
  bool _deleting = false;
  String _version = '';


  /// Destructive, and irreversible on the phone — so it's a two-step confirm
  /// that states plainly what goes and what stays.
  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Delete all data on this phone?'),
        content: const Text(
          'Removes every synced sample, the derived trends, the recording index '
          'and the sync cursor.\n\n'
          'Your watch is not touched and stays paired — its own data is intact, '
          'so the next sync re-pulls whatever the watch still holds. Anything '
          'the watch has already aged out is gone for good.\n\n'
          'CSV files you have already exported are not affected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything',
                style: TextStyle(color: HpiColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final removed = await DatabaseHelper.instance.deleteAllHealthData();
      final total = removed.values.fold<int>(0, (a, b) => a + b);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deleted $total rows. Sync to re-pull from the watch.'),
          backgroundColor: HpiColors.steps,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: HpiColors.error));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _devMode = prefs.getBool(ScrSettingsNew.devModePrefKey) ?? false;
      _version = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _setDevMode(bool v) async {
    setState(() => _devMode = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScrSettingsNew.devModePrefKey, v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _profileCard(),
            const SizedBox(height: 20),
            const HpiSectionLabel('PREFERENCES'),
            HpiGroupedCard(rows: [
              _row(Symbols.straighten, 'Units', '°F · mi'),
              _row(Symbols.dark_mode, 'Theme', 'Dark'),
              _row(Symbols.notifications, 'Health alerts', 'High HR · Low SpO₂'),
            ]),
            const SizedBox(height: 20),
            const HpiSectionLabel('DATA'),
            HpiGroupedCard(rows: [
              _row(Symbols.description, 'Export data', 'CSV · EDF'),
              _row(Symbols.cloud_off, 'Cloud sync', 'Off — local only'),
              HpiListRow(
                icon: Symbols.delete,
                iconColor: HpiColors.error,
                title: 'Delete all data on this phone',
                supporting: _deleting
                    ? 'Deleting…'
                    : 'Resets the sync cursor and re-pulls from the watch',
                showChevron: false,
                onTap: _deleting ? null : _confirmDeleteAll,
              ),
            ]),
            const SizedBox(height: 20),
            const HpiSectionLabel('DEVELOPER'),
            _developerCard(),
            const SizedBox(height: 24),
            Center(
              child: Text('App $_version · MIT licensed',
                  style: HpiText.mono.copyWith(
                      fontSize: 10, color: HpiColors.disabled)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    return HpiCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HpiMetricColors.tint(HpiColors.hr, 0.16),
              shape: BoxShape.circle,
            ),
            child: Text('AK',
                style: HpiText.cardTitle.copyWith(color: HpiColors.hr)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HealthyPi user', style: HpiText.cardTitle),
              const SizedBox(height: 2),
              Text('Signed in locally', style: HpiText.supporting),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String value) {
    return HpiListRow(
      icon: icon,
      iconColor: HpiColors.onSurfaceVariant,
      title: title,
      trailing: Text(value, style: HpiText.body.copyWith(fontSize: 12)),
      onTap: () {},
    );
  }

  /// Just the gate now. Every developer control lives on [ScrDeveloper] — the
  /// toggle stays here because it has to be reachable while that screen is
  /// hidden, and because a setting is what it is.
  Widget _developerCard() {
    return HpiCard(
      padding: EdgeInsets.zero,
      highlightColor: HpiMetricColors.tint(HpiColors.hr, 0.22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                HpiIconSquare(
                    icon: Symbols.code,
                    color: HpiColors.hr,
                    size: 34,
                    iconSize: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Developer mode', style: HpiText.cardTitle),
                ),
                Switch(
                  value: _devMode,
                  onChanged: _setDevMode,
                  activeThumbColor: HpiColors.onHr,
                  activeTrackColor: HpiColors.hr,
                  thumbIcon: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? const Icon(Symbols.check, color: HpiColors.onHr)
                          : null),
                ),
              ],
            ),
          ),
          if (_devMode) ...[
            const Divider(height: 1, color: HpiColors.divider, indent: 14),
            HpiListRow(
              icon: Symbols.terminal,
              iconColor: HpiColors.hr,
              title: 'Developer tools',
              supporting:
                  'Link · store · HPI_HS probe · GATT · log',
              trailing: Text('DEV',
                  style:
                      HpiText.mono.copyWith(color: HpiColors.hr, fontSize: 10)),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ScrDeveloper())),
            ),
          ],
        ],
      ),
    );
  }
}
