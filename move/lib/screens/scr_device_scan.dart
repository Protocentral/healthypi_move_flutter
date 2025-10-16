import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/snackbar.dart';

import '../globals.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';

/// Clean, focused screen for BLE device scanning and pairing
/// Purpose: Scan for HealthyPi Move devices and pair them
/// Can optionally connect to device and trigger callback for operations
class ScrDeviceScan extends StatefulWidget {
  final Function(BluetoothDevice)? onDeviceConnected;
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

      // Start scanning with name filter for HealthyPi Move devices
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
        withNames: ['healthypi move'],
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

  /// Connect to device and either pair it or trigger callback
  Future<void> _connectToDevice(BluetoothDevice device, String deviceName) async {
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

      // Connect to device
      await device.connect(
        license: License.values.first,
        timeout: const Duration(seconds: 15),
        mtu: null,
      );

      // If we have a callback (for live view, fetch recordings, etc.)
      if (widget.onDeviceConnected != null) {
        // Close loading dialog
        if (!mounted) return;
        Navigator.of(context).pop();
        
        // Trigger callback with connected device
        widget.onDeviceConnected!(device);
        return;
      }

      // Otherwise, pair the device
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
          if (_adapterState != BluetoothAdapterState.on)
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
                      final result = _scanResults[index];
                      return _DeviceListTile(
                        result: result,
                        onTap: () => _connectToDevice(
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
                      device.remoteId.str,
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
