// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:move/utils/snackbar.dart';

import '../models/device_info.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/database_helper.dart';

/// Clean, focused screen for BLE device scanning and pairing.
/// Purpose: scan for HealthyPi Move devices and pair them. Can optionally connect
/// and trigger a callback (with the BLE **deviceId**) for downstream operations.
///
/// Migrated to `universal_ble` (see docs/HEALTH_STORE_SYNC_DESIGN.md §2.0).
/// `universal_ble`'s `deviceId` is the same platform identifier the old plugin
/// exposed as `remoteId.str` (CoreBluetooth UUID on Apple, MAC on Android), so it is
/// used unchanged as the stored MAC and lets not-yet-migrated screens bridge via
/// `BluetoothDevice.fromId(deviceId)`.
class ScrDeviceScan extends StatefulWidget {
  /// Fired with the connected device's **deviceId** (== FBP remoteId string).
  final Function(String deviceId)? onDeviceConnected;
  final bool pairOnly;

  const ScrDeviceScan({
    super.key,
    this.onDeviceConnected,
    this.pairOnly = false,
  });

  @override
  State<ScrDeviceScan> createState() => _ScrDeviceScanState();
}

class _ScrDeviceScanState extends State<ScrDeviceScan> {
  /// Discovered HealthyPi Move devices, keyed by deviceId (dedup + rssi update).
  final Map<String, BleDevice> _devices = {};
  bool _isScanning = false;
  AvailabilityState _adapterState = AvailabilityState.unknown;

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<AvailabilityState>? _adapterStateSubscription;
  Timer? _scanTimeout;

  /// The currently paired device's id, so the results list can mark it PAIRED
  /// and offer "Connect" instead of "Pair" (the reconnect/switch surface, 5c).
  String? _pairedDeviceId;

  static const String _nameMatch = 'healthypi move';

  List<BleDevice> get _scanResults {
    final list = _devices.values.toList();
    list.sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return list;
  }

  @override
  void initState() {
    super.initState();

    _adapterStateSubscription = UniversalBle.availabilityStream.listen((state) {
      if (mounted) setState(() => _adapterState = state);
    });
    UniversalBle.getBluetoothAvailabilityState().then((state) {
      if (mounted) setState(() => _adapterState = state);
    });

    // Note the already-paired device so the list can mark it and offer Connect.
    DeviceManager.getPairedDevice().then((d) {
      if (mounted) setState(() => _pairedDeviceId = d?.macAddress);
    });

    // Start scanning immediately.
    _startScan();
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    UniversalBle.stopScan().catchError((_) {});
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      if (state != AvailabilityState.poweredOn) {
        Snackbar.show(ABC.c, "Bluetooth is not enabled", success: false);
        return;
      }

      setState(() {
        _devices.clear();
        _isScanning = true;
      });

      _scanSubscription ??= UniversalBle.scanStream.listen(
        (device) {
          final name = (device.name ?? '').toLowerCase();
          // Keep only HealthyPi Move devices (FBP used an exact name filter;
          // match by substring so an id-suffixed advertised name still shows).
          if (!name.contains(_nameMatch)) return;
          if (mounted) setState(() => _devices[device.deviceId] = device);
        },
        onError: (e) =>
            Snackbar.show(ABC.c, prettyException("Scan Error:", e), success: false),
      );

      await UniversalBle.startScan();

      // universal_ble's startScan has no timeout — bound it like FBP's 15 s.
      _scanTimeout?.cancel();
      _scanTimeout = Timer(const Duration(seconds: 15), _stopScan);
    } catch (e) {
      setState(() => _isScanning = false);
      Snackbar.show(ABC.c, prettyException("Start Scan Error:", e), success: false);
    }
  }

  Future<void> _stopScan() async {
    _scanTimeout?.cancel();
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Stop Scan Error:", e), success: false);
    }
    if (mounted) setState(() => _isScanning = false);
  }

  /// Show warning dialog when switching devices with existing data
  Future<bool> _showDataLossWarningDialog(String existingDeviceName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Symbols.warning, color: HpiColors.temp, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Replace paired device?', style: HpiText.appBarTitle),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to pair a new device.',
                style: HpiText.body.copyWith(fontSize: 13, color: HpiColors.onSurface)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HpiMetricColors.tint(HpiColors.error, 0.12),
                border: Border.all(color: HpiMetricColors.tint(HpiColors.error, 0.35)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Symbols.info, color: HpiColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text('Data loss warning',
                          style: HpiText.cardTitle.copyWith(color: HpiColors.error)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All health data from "$existingDeviceName" will be permanently deleted.',
                    style: HpiText.body.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'To keep this data, cancel and export it first from Settings › Export data.',
              style: HpiText.supporting,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete & pair new device',
                style: TextStyle(color: HpiColors.error)),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Connect to device and either pair it or trigger callback
  Future<void> _connectToDevice(String deviceId, String deviceName) async {
    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: HpiCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(HpiColors.hr),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Connecting…', style: HpiText.cardTitle),
              ],
            ),
          ),
        ),
      );

      // Stop scanning first
      await _stopScan();

      // Connect to device (OS handles bonding/passkey on native).
      await UniversalBle.connect(deviceId,
          timeout: const Duration(seconds: 15));

      // If we have a callback (for live view, fetch recordings, etc.)
      if (widget.onDeviceConnected != null) {
        // Close loading dialog
        if (!mounted) return;
        Navigator.of(context).pop();

        // Trigger callback with connected device id
        widget.onDeviceConnected!(deviceId);
        return;
      }

      // Otherwise, pair the device
      // Check if there's already a paired device with data
      final existingDevice = await DeviceManager.getPairedDevice();
      bool shouldProceed = true;

      if (existingDevice != null && existingDevice.macAddress != deviceId) {
        // Check if existing device has any synced data
        final hasData = await DatabaseHelper.instance.hasDataForDevice(existingDevice.macAddress);

        if (hasData) {
          // Show confirmation dialog
          if (!mounted) return;
          shouldProceed = await _showDataLossWarningDialog(existingDevice.displayName);

          if (shouldProceed) {
            // Delete old device data
            await DatabaseHelper.instance.deleteDataForDevice(existingDevice.macAddress);
          }
        }
      }

      if (!shouldProceed) {
        // User cancelled, disconnect and exit
        await UniversalBle.disconnect(deviceId);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      // Create device info
      final deviceInfo = DeviceInfo(
        macAddress: deviceId,
        deviceName: deviceName,
        firstPaired: DateTime.now(),
      );

      // Save paired device
      await DeviceManager.savePairedDevice(deviceInfo);

      // Disconnect (we're just pairing, not syncing)
      await UniversalBle.disconnect(deviceId);

      // Close loading dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Show success message
      Snackbar.show(
        ABC.c,
        "Device paired successfully: $deviceName",
        success: true,
      );

      // Navigate back to home (pop back to previous screen)
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      Snackbar.show(
        ABC.c,
        prettyException("Connection Error:", e),
        success: false,
      );
    }
  }

  // --- Presentation: redesigned onboarding scan & pair (handoff 1g) ---------
  // The scan/connect/pair logic above is unchanged — only the UI was redesigned,
  // deliberately: this is the flow every other screen depends on.

  bool _isDfu(BleDevice d) =>
      (d.name ?? '').toLowerCase().contains('dfu');

  @override
  Widget build(BuildContext context) {
    final devices = _scanResults;
    final btOff = _adapterState != AvailabilityState.poweredOn;

    return Scaffold(
      backgroundColor: HpiColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Symbols.arrow_back,
                    color: HpiColors.onSurfaceBright),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PROTOCENTRAL', style: HpiText.wordmark),
                  const SizedBox(height: 10),
                  Text('Set up your HealthyPi Move',
                      style: HpiText.screenTitle.copyWith(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                    btOff
                        ? 'Turn on Bluetooth to search for your watch.'
                        : 'Keep the watch nearby and powered on while we look for it.',
                    style: HpiText.body.copyWith(
                        fontSize: 13,
                        color: btOff ? HpiColors.error : HpiColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: devices.isEmpty
                        ? _ScanRadar(scanning: _isScanning && !btOff)
                        : ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, i) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final d = devices[i];
                              return _FoundDeviceCard(
                                device: d,
                                dfu: _isDfu(d),
                                paired: _pairedDeviceId != null &&
                                    d.deviceId == _pairedDeviceId,
                                onPair: () => _connectToDevice(
                                    d.deviceId,
                                    (d.name?.isNotEmpty ?? false)
                                        ? d.name!
                                        : 'HealthyPi Move'),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _isScanning ? _stopScan : _startScan,
                      child: Text(
                        _isScanning ? 'Stop scanning' : "Can't find your device?",
                        style: HpiText.cardTitle
                            .copyWith(color: HpiColors.hr, fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scanning radar: concentric rings that pulse while a scan is running
/// (handoff 1g). Purely decorative — it reflects scan state, never device data.
class _ScanRadar extends StatefulWidget {
  const _ScanRadar({required this.scanning});
  final bool scanning;

  @override
  State<_ScanRadar> createState() => _ScanRadarState();
}

class _ScanRadarState extends State<_ScanRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _c.repeat();
  }

  @override
  void didUpdateWidget(_ScanRadar old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.scanning && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 216,
            height: 216,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => CustomPaint(
                painter: _RadarPainter(
                    t: _c.value, active: widget.scanning),
                child: const Center(
                  child: Icon(Symbols.watch, size: 34, color: HpiColors.spo2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            widget.scanning ? 'Searching…' : 'No devices found',
            style: HpiText.cardTitle.copyWith(color: HpiColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.t, required this.active});
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const radii = [104.0, 78.0, 52.0];
    const bases = [0.10, 0.16, 0.24];

    for (var i = 0; i < radii.length; i++) {
      // Each ring breathes on its own phase, so the rings read as a sweep.
      final phase = (t + i / radii.length) % 1.0;
      final pulse = active ? (0.5 + 0.5 * (1 - phase)) : 0.5;
      canvas.drawCircle(
        center,
        radii[i],
        Paint()
          ..color = HpiColors.spo2.withValues(alpha: bases[i] * pulse * 2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawCircle(
      center,
      30,
      Paint()..color = HpiColors.spo2.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.t != t || old.active != active;
}

/// A discovered device (handoff 1g / 5c). The already-paired watch gets a
/// green-bordered card with a PAIRED chip + "Connect"; a new Move gets the
/// amber-bordered "Pair" card; a device advertising in bootloader mode is
/// dimmed and labelled DFU instead of offering an action.
class _FoundDeviceCard extends StatelessWidget {
  const _FoundDeviceCard({
    required this.device,
    required this.dfu,
    required this.onPair,
    this.paired = false,
  });

  final BleDevice device;
  final bool dfu;

  /// True when this is the currently-paired device (reconnect/switch surface).
  final bool paired;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final name = (device.name?.isNotEmpty ?? false)
        ? device.name!
        : 'HealthyPi Move';
    final rssi = device.rssi;
    final meta = dfu
        ? 'bootloader mode${rssi != null ? " · $rssi dBm" : ""}'
        : '${device.deviceId}${rssi != null ? " · $rssi dBm" : ""}';
    final accent = paired ? HpiColors.steps : HpiColors.hr;

    return Opacity(
      opacity: dfu ? 0.55 : 1,
      child: HpiCard(
        highlightColor: dfu ? null : HpiMetricColors.tint(accent, 0.35),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: HpiMetricColors.tint(
                    dfu ? HpiColors.onSurfaceVariant : accent, 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                dfu ? Symbols.system_update : Symbols.watch,
                size: 20,
                color: dfu ? HpiColors.onSurfaceVariant : accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HpiText.cardTitle.copyWith(fontSize: 14.5)),
                      ),
                      if (paired && !dfu) ...[
                        const SizedBox(width: 8),
                        const HpiPill(label: 'PAIRED', color: HpiColors.steps),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HpiText.mono.copyWith(fontSize: 10.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (dfu)
              const HpiPill(label: 'DFU')
            else
              SizedBox(
                height: 38,
                child: Material(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPair,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Text(
                          paired ? 'Connect' : 'Pair',
                          style: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: HpiColors.onHr,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
