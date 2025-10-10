import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/snackbar.dart';

import '../globals.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';

/// Clean, focused screen for BLE device scanning and pairing
/// Purpose: Scan for HealthyPi Move devices and pair them
/// Does NOT handle sync, streaming, or other operations
class ScrDeviceScan extends StatefulWidget {
  const ScrDeviceScan({super.key});

  @override
  State<ScrDeviceScan> createState() => _ScrDeviceScanState();
}

class _ScrDeviceScanState extends State<ScrDeviceScan> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    
    // Subscribe to scan results
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        if (mounted) {
          setState(() {
            _scanResults = results;
          });
        }
      },
      onError: (e) => Snackbar.show(ABC.c, prettyException("Scan Error:", e), success: false),
    );

    // Subscribe to scanning state
    _isScanningSubscription = FlutterBluePlus.isScanning.listen(
      (state) {
        if (mounted) {
          setState(() {
            _isScanning = state;
          });
        }
      },
    );

    // Subscribe to adapter state
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen(
      (state) {
        if (mounted) {
          setState(() {
            _adapterState = state;
          });
        }
      },
    );

    // Start scanning immediately
    _startScan();
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _adapterStateSubscription.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      // Check adapter state
      if (_adapterState != BluetoothAdapterState.on) {
        Snackbar.show(ABC.c, "Bluetooth is not enabled", success: false);
        return;
      }

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Start Scan Error:", e), success: false);
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Stop Scan Error:", e), success: false);
    }
  }

  /// Connect to device, pair it, and navigate to home
  Future<void> _pairDevice(BluetoothDevice device, String deviceName) async {
    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Stop scanning first
      await _stopScan();

      // Connect to device (required to verify it's a valid device)
      await device.connect(
        license: License.values.first,
        timeout: const Duration(seconds: 15),
        mtu: null,
      );

      // Create device info
      final deviceInfo = DeviceInfo(
        macAddress: device.remoteId.str,
        deviceName: deviceName,
        firstPaired: DateTime.now(),
      );

      // Save paired device
      await DeviceManager.savePairedDevice(deviceInfo);

      // Disconnect (we're just pairing, not syncing)
      await device.disconnect();

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
        prettyException("Pairing Error:", e),
        success: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan & Pair Device'),
        backgroundColor: hPi4Global.hpi4AppBarColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopScan,
              tooltip: 'Stop Scan',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Start Scan',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          if (_adapterState != BluetoothAdapterState.on)
            Container(
              color: Colors.red,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Bluetooth is not enabled. Please enable Bluetooth.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Scanning indicator
          if (_isScanning)
            Container(
              color: hPi4Global.hpi4Color.withAlpha(26), // 10% opacity
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Scanning for devices...'),
                ],
              ),
            ),

          // Device list
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_searching,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Searching for devices...'
                              : 'No devices found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (!_isScanning) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Start Scan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hPi4Global.hpi4Color,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      return _DeviceListTile(
                        result: result,
                        onTap: () => _pairDevice(
                          result.device,
                          result.advertisementData.advName.isNotEmpty
                              ? result.advertisementData.advName
                              : result.device.platformName,
                        ),
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
  final ScanResult result;
  final VoidCallback onTap;

  const _DeviceListTile({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final device = result.device;
    final advName = result.advertisementData.advName;
    final platformName = device.platformName;
    final rssi = result.rssi;

    // Determine display name
    String displayName = advName.isNotEmpty ? advName : platformName;
    if (displayName.isEmpty) {
      displayName = 'Unknown Device';
    }

    // Signal strength indicator
    Widget signalStrength;
    Color signalColor;
    if (rssi >= -60) {
      signalStrength = const Icon(Icons.signal_cellular_alt, color: Colors.green);
      signalColor = Colors.green;
    } else if (rssi >= -80) {
      signalStrength = const Icon(Icons.signal_cellular_alt_2_bar, color: Colors.orange);
      signalColor = Colors.orange;
    } else {
      signalStrength = const Icon(Icons.signal_cellular_alt_1_bar, color: Colors.red);
      signalColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: ListTile(
        leading: Icon(
          Icons.bluetooth,
          color: hPi4Global.hpi4Color,
          size: 36,
        ),
        title: Text(
          displayName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'MAC: ${device.remoteId.str}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                signalStrength,
                const SizedBox(width: 4),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                    fontSize: 12,
                    color: signalColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text('Pair'),
        ),
      ),
    );
  }
}
