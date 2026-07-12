import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/device_info.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/database_helper.dart';
import '../utils/device_manager.dart';
import '../utils/health_store_sync_manager.dart';
import 'scr_dfu_new.dart';
import 'scr_recordings.dart';
import 'scr_settings_new.dart';

/// Device page (handoff 1h). Reads the paired device, live connection status,
/// and last-sync state; wires Sync now, Firmware update, and Unpair to the
/// existing flows. Fields the app can't know at rest (storage %, watch face)
/// are shown only when a value exists.
class ScrDeviceNew extends StatefulWidget {
  const ScrDeviceNew({super.key});

  @override
  State<ScrDeviceNew> createState() => _ScrDeviceNewState();
}

class _ScrDeviceNewState extends State<ScrDeviceNew> {
  final _cm = ConnectionManager.instance;
  DeviceInfo? _device;
  DateTime? _lastSync;
  int _trendBins = 0;
  bool _syncing = false;
  String _syncStatus = '';
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _cm.addListener(_onLink);
    // The shell keeps this tab alive in an IndexedStack, so initState runs once
    // — before any pairing. Re-read whenever the paired device changes.
    DeviceManager.pairingRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _cm.removeListener(_onLink);
    DeviceManager.pairingRevision.removeListener(_load);
    _syncSub?.cancel();
    super.dispose();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final device = await DeviceManager.getPairedDevice();
    final lastSync = await DatabaseHelper.instance.getLastSyncTime();
    final bins = device == null
        ? 0
        : await DatabaseHelper.instance.getRecordCountForDevice(device.macAddress);
    if (!mounted) return;
    setState(() {
      _device = device;
      _lastSync = lastSync;
      _trendBins = bins;
    });
  }

  /// The Device screen is the deliberate place to catch up a long history, so it
  /// gets a much larger budget than Home's quick "Sync now". Still cancellable
  /// and resumable, so a long run can't strand the UI.
  Future<void> _sync() async {
    final device = _device;
    if (device == null || _syncing) return;
    setState(() => _syncing = true);
    _syncSub = HealthStoreSyncManager.instance.progressStream.listen((p) {
      if (mounted && p.metric == 'all') {
        setState(() => _syncStatus = p.message ?? '');
      }
    });
    try {
      final result = await HealthStoreSyncManager.instance.syncData(
        deviceMacAddress: device.macAddress,
        onProgress: (metric, progress) {},
        onStatus: (status) {},
        budget: const Duration(minutes: 5),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.message),
            backgroundColor:
                result.success ? HpiColors.steps : HpiColors.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync error: $e'),
                backgroundColor: HpiColors.error));
      }
    } finally {
      await _syncSub?.cancel();
      _syncSub = null;
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncStatus = '';
        });
      }
    }
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Unpair watch?'),
        content: const Text(
            'The app will forget this device. Your synced data stays on the '
            'phone. You can pair again anytime.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unpair',
                  style: TextStyle(color: HpiColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    await DeviceManager.unpairDevice();
    if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/scan', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    return Scaffold(
      backgroundColor: HpiColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _header(),
            const SizedBox(height: 14),
            if (device == null)
              _noDevice()
            else ...[
              _heroCard(device),
              const SizedBox(height: 12),
              _syncCard(),
              const SizedBox(height: 12),
              _actionsCard(device),
              const SizedBox(height: 12),
              _dangerCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Text('Device', style: HpiText.screenTitle),
        const Spacer(),
        IconButton(
          icon: const Icon(Symbols.settings, size: 22, color: HpiColors.onSurfaceBright),
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScrSettingsNew())),
        ),
      ],
    );
  }

  Widget _noDevice() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Icon(Symbols.watch_off, size: 46, color: HpiColors.disabled),
          const SizedBox(height: 14),
          Text('No watch paired', style: HpiText.appBarTitle),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: HpiFilledButton(
              label: 'Pair a device',
              icon: Symbols.add,
              onPressed: () => Navigator.of(context).pushNamed('/scan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(DeviceInfo device) {
    final connected = _cm.isConnected;
    final battery = device.batteryLevel;
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2A333B), width: 4),
                ),
                child: const Icon(Symbols.watch, size: 24, color: HpiColors.hr),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.displayName, style: HpiText.cardTitle.copyWith(fontSize: 16)),
                    const SizedBox(height: 6),
                    HpiPill(
                      label: connected ? 'CONNECTED' : 'NOT CONNECTED',
                      color: connected ? HpiColors.steps : HpiColors.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'FW ${device.firmwareVersion ?? "—"} · ${device.macAddress}',
            style: HpiText.mono.copyWith(fontSize: 10.5),
          ),
          if (battery != null) ...[
            const SizedBox(height: 12),
            _bar('Battery', battery / 100.0, HpiColors.spo2,
                Symbols.battery_5_bar, '$battery%'),
          ],
        ],
      ),
    );
  }

  Widget _bar(String label, double frac, Color color, IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              Container(height: 6, color: HpiColors.dividerStrong),
              FractionallySizedBox(
                  widthFactor: frac.clamp(0, 1),
                  child: Container(height: 6, color: color)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Text(value, style: HpiText.mono.copyWith(fontSize: 11, color: HpiColors.onSurface)),
      ],
    );
  }

  Widget _syncCard() {
    final last = _lastSync == null ? 'Never synced' : 'Last synced ${_relative(_lastSync!)}';
    return HpiCard(
      child: Column(
        children: [
          Row(
            children: [
              HpiIconSquare(icon: Symbols.sync, color: HpiColors.hr, size: 34, iconSize: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_syncing && _syncStatus.isNotEmpty ? _syncStatus : last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HpiText.cardTitle),
                    const SizedBox(height: 2),
                    Text('$_trendBins trend bins stored', style: HpiText.supporting),
                  ],
                ),
              ),
              SizedBox(
                width: 108,
                // A long history catch-up must always be interruptible;
                // everything already synced is kept.
                child: HpiTonalButton(
                  label: _syncing ? 'Stop' : 'Sync now',
                  icon: _syncing ? Symbols.stop : Symbols.sync,
                  color: _syncing ? HpiColors.error : HpiColors.hr,
                  onPressed: _syncing
                      ? () => HealthStoreSyncManager.instance.cancel()
                      : _sync,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(DeviceInfo device) {
    return HpiGroupedCard(rows: [
      HpiListRow(
        icon: Symbols.system_update,
        iconColor: HpiColors.hr,
        title: 'Firmware update',
        supporting: 'Current ${device.firmwareVersion ?? "unknown"}',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ScrDFUNew(deviceMacAddress: device.macAddress))),
      ),
      HpiListRow(
        icon: Symbols.receipt_long,
        iconColor: HpiColors.steps,
        title: 'Recordings',
        supporting: 'Long PPG · GSR · IMU sessions',
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScrRecordings())),
      ),
      HpiListRow(
        icon: Symbols.schedule,
        iconColor: HpiColors.onSurfaceVariant,
        title: 'Set device time',
        trailing: Text('Auto', style: HpiText.body.copyWith(fontSize: 12)),
        onTap: () {},
      ),
    ]);
  }

  Widget _dangerCard() {
    return HpiGroupedCard(rows: [
      HpiListRow(
        icon: Symbols.delete,
        iconColor: HpiColors.error,
        title: 'Delete all data on this phone',
        supporting: 'Resets the sync cursor and re-pulls from the watch',
        onTap: _confirmDeleteAll,
        showChevron: false,
      ),
      HpiListRow(
        icon: Symbols.link_off,
        iconColor: HpiColors.error,
        title: 'Unpair watch',
        onTap: _unpair,
        showChevron: false,
      ),
    ]);
  }

  /// Same wipe as Settings → Data. Reachable here too because this is where you
  /// end up when the phone's copy and the watch have diverged.
  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Delete all data on this phone?'),
        content: const Text(
          'Removes every synced sample, the derived trends, the recording index '
          'and the sync cursor.\n\n'
          'Your watch is not touched and stays paired — the next sync re-pulls '
          'whatever it still holds.',
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
    if (ok != true) return;
    final removed = await DatabaseHelper.instance.deleteAllHealthData();
    final total = removed.values.fold<int>(0, (a, b) => a + b);
    await _load(); // refresh the trend-bin count and last-sync time
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Deleted $total rows. Sync to re-pull from the watch.'),
        backgroundColor: HpiColors.steps,
      ));
    }
  }

  String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
