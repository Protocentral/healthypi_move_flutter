import 'dart:async';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:move/utils/snackbar.dart';

import '../globals.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';
import '../utils/database_helper.dart';

/// Clean, focused screen for BLE device scanning and pairing.
/// Purpose: scan for HealthyPi Move devices and pair them. Can optionally connect
/// and trigger a callback (with the BLE **deviceId**) for downstream operations.
///
/// Migrated from `flutter_blue_plus` to `universal_ble` (see
/// docs/HEALTH_STORE_SYNC_DESIGN.md §2.0). `universal_ble`'s `deviceId` is the same
/// platform identifier as FBP's `remoteId.str` (CoreBluetooth UUID on Apple, MAC on
/// Android), so it is used unchanged as the stored MAC and lets not-yet-migrated FBP
/// screens bridge via `BluetoothDevice.fromId(deviceId)`.
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
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Replace Paired Device?',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to pair a new device.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Data Loss Warning',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All health data from "$existingDeviceName" will be permanently deleted.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'To keep this data, cancel and export it first from Settings > Export Data.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Delete & Pair New Device',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
        builder: (context) => const Center(
          child: Card(
            color: Color(0xFF2D2D2D),
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Connecting...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Image.asset(
              'assets/healthypi_move.png',
              height: 30,
              fit: BoxFit.fitWidth,
            ),
            const SizedBox(width: 12),
            const Text(
              'Scan & Pair',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ],
        ),
        actions: [
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _stopScan,
              tooltip: 'Stop Scan',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _startScan,
              tooltip: 'Start Scan',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          if (_adapterState != AvailabilityState.poweredOn)
            Container(
              color: Colors.red[700],
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.bluetooth_disabled, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Bluetooth is not enabled. Please enable Bluetooth.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),

          // Scanning indicator
          if (_isScanning)
            Container(
              color: const Color(0xFF2D2D2D),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Scanning for devices...',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

          // Device list
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 80,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _isScanning
                                ? 'Searching for HealthyPi Move devices...'
                                : 'No devices found',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Make sure your device is powered on and nearby',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (!_isScanning) ...[
                            const SizedBox(height: 32),
                            ElevatedButton(
                              onPressed: _startScan,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: hPi4Global.hpi4Color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.refresh, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Start Scan',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final device = _scanResults[index];
                      final name = (device.name != null && device.name!.isNotEmpty)
                          ? device.name!
                          : 'Unknown Device';
                      return _DeviceListTile(
                        device: device,
                        onTap: () => _connectToDevice(device.deviceId, name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Individual device tile in scan results
class _DeviceListTile extends StatelessWidget {
  final BleDevice device;
  final VoidCallback onTap;

  const _DeviceListTile({
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rssi = device.rssi ?? -999;

    // Determine display name
    String displayName = (device.name != null && device.name!.isNotEmpty)
        ? device.name!
        : 'Unknown Device';

    // Signal strength indicator
    IconData signalIcon;
    Color signalColor;
    if (rssi >= -60) {
      signalIcon = Icons.signal_cellular_alt;
      signalColor = Colors.green;
    } else if (rssi >= -80) {
      signalIcon = Icons.signal_cellular_alt_2_bar;
      signalColor = Colors.orange;
    } else {
      signalIcon = Icons.signal_cellular_alt_1_bar;
      signalColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: const Color(0xFF2D2D2D),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Device icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hPi4Global.hpi4Color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bluetooth,
                  color: hPi4Global.hpi4Color,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),

              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      device.deviceId,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          signalIcon,
                          size: 16,
                          color: signalColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$rssi dBm',
                          style: TextStyle(
                            fontSize: 12,
                            color: signalColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Pair button
              ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Pair',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
