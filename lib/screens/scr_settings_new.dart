// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart' show SmpException;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/auto_sync_controller.dart';
import '../utils/connection_manager.dart';
import '../utils/database_helper.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_client.dart';
import '../utils/healthy_store_sync_manager.dart';
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
  final _cm = ConnectionManager.instance;
  bool _devMode = false;
  bool _autoSync = true;
  bool _deleting = false;
  bool _erasingWatch = false;
  String _version = '';

  /// Erase everything on the **watch** (HPI_HS `ERASE`, cmd 12).
  ///
  /// Deliberately separate from "Delete all data on this phone": one clears the
  /// local copy and re-pulls on the next sync, the other destroys the original.
  /// Doing both from one button would make the recoverable case and the
  /// unrecoverable one look identical.
  Future<void> _confirmEraseWatch() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Erase all data on the watch?'),
        content: const Text(
          'Permanently deletes every sample and recording stored on the watch, '
          'including anything not yet synced to this phone.\n\n'
          'This cannot be undone, and the watch keeps no copy. Data already '
          'synced to this phone stays — use "Delete all data on this phone" as '
          'well if you want both gone.\n\n'
          'Your settings, profile and blood-pressure calibration are kept.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase the watch',
                style: TextStyle(color: HpiColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      _snack('No paired watch.', HpiColors.error);
      return;
    }

    setState(() => _erasingWatch = true);
    HealthyStoreClient? client;
    try {
      if (!_cm.isConnected || _cm.deviceId != device.macAddress) {
        await _cm.connect(device.macAddress);
      }
      client = HealthyStoreClient(device.macAddress,
          requestTimeout: const Duration(seconds: 30));
      await client.connect();
      if (!client.hasHealthyStore) {
        throw StateError('watch did not answer HELLO — no Healthy Store');
      }

      final rsp = await client.hs!.eraseAll();
      // The next sync re-reads HELLO and resumeCursor() jumps the local cursor
      // forward past the gap on its own, so nothing to reset here.
      _snack('Watch erased. head=${rsp['head']} oldest=${rsp['oldest']}',
          HpiColors.steps);
    } on SmpBusyException {
      // Our own lock. Never tear the link down here — that would kill whatever
      // legitimately holds it.
      _snack('The watch link is busy (sync or update). Try again after it '
          'finishes.', HpiColors.temp);
    } on SmpException catch (e) {
      final String msg;
      switch (e.rc) {
        case 3: // MGMT_ERR_EINVAL — also what an older group returns for cmd 12
          msg = 'This watch firmware has no erase command. Update it to 3.1 or '
              'newer, or erase from the watch: Settings › Erase data.';
        case 8: // MGMT_ERR_ENOTSUP
          msg = 'This watch firmware does not support erase. Nothing was '
              'changed.';
        case 10: // MGMT_ERR_EBUSY — DFU or a capture in flight
          msg = 'The watch is busy (an update or a recording is running). '
              'Nothing was erased.';
        default:
          msg = 'Erase failed: $e';
      }
      _snack(msg, HpiColors.error);
    } catch (e) {
      _snack('Erase failed: $e', HpiColors.error);
    } finally {
      // Releases the SMP lock. Must run even on the early throws above, or the
      // wire stays held and every later sync/update is refused.
      await client?.disconnect();
      if (mounted) setState(() => _erasingWatch = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }


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
          'CSVs you have already shared or saved elsewhere are not affected.',
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
      final files = removed.remove('_files') ?? 0;
      final total = removed.values.fold<int>(0, (a, b) => a + b);

      // Every screen that reads the store is kept alive in the shell's
      // IndexedStack and loads in initState, so without this they keep showing
      // the data we just deleted until the app is relaunched.
      HealthyStoreSyncManager.dataRevision.value++;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Deleted $total rows'
              '${files > 0 ? ' and $files recording file${files == 1 ? '' : 's'}' : ''}'
              '. Sync to re-pull from the watch.'),
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
      _autoSync = prefs.getBool(AutoSyncController.enabledPrefKey) ?? true;
      _version = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _setDevMode(bool v) async {
    setState(() => _devMode = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScrSettingsNew.devModePrefKey, v);
  }

  /// Auto-sync is on by default, but it is the user's radio and battery — and
  /// turning it off must not also disable the manual "Sync now" buttons, which
  /// never consult this.
  Future<void> _setAutoSync(bool v) async {
    setState(() => _autoSync = v);
    await AutoSyncController.setEnabled(v);
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
              HpiListRow(
                icon: Symbols.sync,
                iconColor: _autoSync ? HpiColors.hr : HpiColors.onSurfaceVariant,
                title: 'Auto-sync',
                supporting: _autoSync
                    ? 'On opening the app, at most every '
                        '${AutoSyncPolicy.minInterval.inMinutes} min'
                    : 'Off — sync only when you tap Sync now',
                showChevron: false,
                trailing: Switch(
                  value: _autoSync,
                  onChanged: _setAutoSync,
                  activeThumbColor: HpiColors.onHr,
                  activeTrackColor: HpiColors.hr,
                ),
                onTap: () => _setAutoSync(!_autoSync),
              ),
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
              // Listed after the phone-side delete on purpose: this one is the
              // irreversible half of the pair.
              HpiListRow(
                icon: Symbols.delete_forever,
                iconColor: HpiColors.error,
                title: 'Erase all data on the watch',
                supporting: _erasingWatch
                    ? 'Erasing…'
                    : 'Permanent — the watch keeps no copy',
                showChevron: false,
                onTap: _erasingWatch ? null : _confirmEraseWatch,
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
