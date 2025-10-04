import 'dart:async';
import 'dart:io' show Directory, File;
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/screens/scr_fetch_ecg.dart';
import 'package:move/screens/scrSync.dart';
import 'package:move/screens/scr_stream_selection.dart';
import 'package:move/utils/snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../home.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';
import '../widgets/scan_result_tile.dart';

class ScrScan extends StatefulWidget {
  const ScrScan({super.key, required this.tabIndex});

  final String tabIndex;

  @override
  State<ScrScan> createState() => _ScrScanState();
}

class _ScrScanState extends State<ScrScan> {
  List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late StreamSubscription<List<int>> _streamDataSubscription;

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;

  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int currentFileDataCounter = 0;
  int checkNoOfWrites = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  bool _autoConnecting = false;
  bool _deviceNotFound = false;
  
  String? _pairedDeviceMac;
  String? _pairedDeviceName;
  bool _autoConnectEnabled = true;

  Future<String?> getPairedDeviceMac() async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String filePath = '${appDocDir.path}/paired_device_mac.txt';
      final File macFile = File(filePath);
      if (!await macFile.exists()) return null;
      return (await macFile.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }
  
  Future<void> _loadPairedDeviceInfo() async {
    final deviceInfo = await DeviceManager.getPairedDevice();
    final prefs = await SharedPreferences.getInstance();
    final autoConnect = prefs.getBool('auto_connect_enabled') ?? true;
    
    if (mounted) {
      setState(() {
        _pairedDeviceMac = deviceInfo?.macAddress;
        _pairedDeviceName = deviceInfo?.displayName;
        _autoConnectEnabled = autoConnect;
      });
    }
  }
  
  Future<void> _unpairDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2D2D2D),
        title: Text(
          'Unpair Device?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          'This will remove the paired device. You\'ll need to pair again to use automatic connection.',
          style: TextStyle(color: Colors.grey[300], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Use DeviceManager to unpair (handles both new and legacy formats)
        await DeviceManager.unpairDevice();
        
        setState(() {
          _pairedDeviceMac = null;
          _pairedDeviceName = null;
        });
        
        Snackbar.show(
          ABC.b,
          'Device unpaired successfully',
          success: true,
        );
      } catch (e) {
        Snackbar.show(
          ABC.b,
          'Failed to unpair device: $e',
          success: false,
        );
      }
    }
  }

  Future<void> _tryAutoConnectToPairedDevice() async {
    String? pairedMac = await getPairedDeviceMac();
    if (pairedMac != null && pairedMac.isNotEmpty) {
      setState(() {
        _autoConnecting = true;
        _deviceNotFound = false;
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      StreamSubscription? tempSub;
      bool found = false;
      tempSub = FlutterBluePlus.scanResults.listen((results) async {
        for (var result in results) {
          if (result.device.id.id == pairedMac) {
            found = true;
            await FlutterBluePlus.stopScan();
            await tempSub?.cancel();
            if (mounted)
              setState(() {
                _autoConnecting = false;
                _deviceNotFound = false;
              });
            await onConnectPressed(result.device);
            return;
          }
        }
      });
      // Timeout fallback
      await Future.delayed(const Duration(seconds: 10), () async {
        await FlutterBluePlus.stopScan();
        await tempSub?.cancel();
        if (!found && mounted) {
          setState(() {
            _autoConnecting = false;
            _deviceNotFound = true;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((
      state,
    ) {
      _adapterState = state;
      if (mounted) {
        setState(() {
          print("Adapter State: $state");
        });
      }
    });

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        print("HPI: Scan Results: $results");
        if (mounted) {
          setState(() => _scanResults = results);
        }
      },
      onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() => _isScanning = state);
      }
    });

    _loadPairedDeviceInfo().then((_) {
      if (_autoConnectEnabled && _pairedDeviceMac != null) {
        _tryAutoConnectToPairedDevice();
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();

    _connectionStateSubscription.cancel();
    super.dispose();
  }

  void logConsole(String logString) async {
    print("AKW - $logString");
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future onScanPressed() async {
    try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      var withServices = [Guid("180f")]; // Battery Level Service
      _systemDevices = await FlutterBluePlus.systemDevices(withServices);
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.b,
        prettyException("System Devices Error:", e),
        success: false,
      );
      print(e);
      print("backtrace: $backtrace");
    }
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [],
        withNames: ['healthypi move'],
      );
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.b,
        prettyException("Start Scan Error:", e),
        success: false,
      );
      print(e);
      print("backtrace: $backtrace");
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.b,
        prettyException("Stop Scan Error:", e),
        success: false,
      );
      print(e);
      print("backtrace: $backtrace");
    }
  }

  _resetStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setString('lastSynced', '0');
      prefs.setString('latestHR', '0');
      prefs.setString('latestTemp', '0');
      prefs.setString('latestSpo2', '0');
      prefs.setString('latestActivityCount', '0');
      prefs.setString('lastUpdatedHR', '0');
      prefs.setString('lastUpdatedTemp', '0');
      prefs.setString('lastUpdatedSpo2', '0');
      prefs.setString('lastUpdatedActivity', '0');
      prefs.setString('fetchStatus', '0');
    });
  }

  redirectToScreens(BluetoothDevice device) {
    if (widget.tabIndex == "1") {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => SyncingScreen(device: device)),
      );

    } else if (widget.tabIndex == "2") {
      showLoadingIndicator("Connected. Erasing the data...", context);
      _eraseAllLogs(context, device);
    } else if (widget.tabIndex == "3") {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ScrStreamsSelection(device: device),
        ),
      );
    } else if (widget.tabIndex == "4") {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => ScrFetchECG(device: device)),
      );
    } else {}
  }

  bool pairedStatus = false;

  Future<void> onConnectPressed(BluetoothDevice device) async {
    _connectionStateSubscription = device.connectionState.listen((state) async {
      _connectionState = state;

      if (_connectionState == BluetoothConnectionState.connected) {
        // Update last connected timestamp
        await DeviceManager.updateLastConnected();
        
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? pairedStatus = "";
        setState(() {
          pairedStatus = prefs.getString('pairedStatus');
        });
        if (pairedStatus == "paired") {
          redirectToScreens(device);
          _connectionStateSubscription.cancel();
        } else {
          showPairDeviceDialog(context, device);
          _connectionStateSubscription.cancel();
        }
      }
    });
    device.cancelWhenDisconnected(
      _connectionStateSubscription,
      delayed: true,
      next: true,
    );

    await device.connect(license:License.values.first);
  }

  Future<void> _eraseAllLogs(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Erase All initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogWipeAll);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
    _resetStoredValue();
    showLoadingIndicator("Disconnecting...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      disconnectDevice(deviceName);
      Navigator.pop(context);
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
    });
  }

  Future onRefresh() {
    if (_isScanning == false) {
      onScanPressed();
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color, // background color
            foregroundColor: Colors.white, // text color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: onStopPressed,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[const Icon(Icons.stop), Spacer()],
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            backgroundColor: hPi4Global.hpi4Color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onScanPressed,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.search, color: Colors.white),
                const Text(
                  ' Scan for devices ',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                Spacer(),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildScanContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Auto-connecting state
        if (_autoConnecting) ...[
          _buildAutoConnectingCard(),
          const SizedBox(height: 16),
        ],
        
        // Device not found state
        if (_deviceNotFound) ...[
          _buildDeviceNotFoundCard(),
          const SizedBox(height: 16),
        ],
        
        // Paired device card (only show when not auto-connecting or showing error)
        if (_pairedDeviceMac != null && !_autoConnecting && !_deviceNotFound) ...[
          _buildPairedDeviceCard(),
          const SizedBox(height: 16),
        ],
        
        // Scan section (only when not auto-connecting)
        if (!_autoConnecting) ...[
          _buildScanCard(),
        ],
      ],
    );
  }

  Widget _buildAutoConnectingCard() {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(hPi4Global.hpi4Color),
                  ),
                ),
                Icon(Icons.watch, color: hPi4Global.hpi4Color, size: 30),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Connecting...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _pairedDeviceName ?? _pairedDeviceMac ?? "HealthyPi Move",
              style: TextStyle(
                color: hPi4Global.hpi4Color,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Make sure your device is nearby and turned on',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                await FlutterBluePlus.stopScan();
                setState(() {
                  _autoConnecting = false;
                });
              },
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceNotFoundCard() {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bluetooth_disabled,
                color: Colors.redAccent,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Device Not Found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Could not find "${_pairedDeviceName ?? "your device"}" nearby',
              style: TextStyle(color: Colors.grey[300], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please check:',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    'Device is turned on',
                    'Device is within range',
                    'Battery is not depleted',
                  ].map((tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.grey[500], size: 16),
                        const SizedBox(width: 10),
                        Text(tip,
                            style: TextStyle(
                                color: Colors.grey[300], fontSize: 13)),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _unpairDevice,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[300],
                      side: BorderSide(color: Colors.grey[600]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Pair Different Device'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _deviceNotFound = false;
                      });
                      _tryAutoConnectToPairedDevice();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hPi4Global.hpi4Color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDeviceCard() {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paired Device',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pairedDeviceName ?? _pairedDeviceMac!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red[300]),
                  onPressed: _unpairDevice,
                  tooltip: 'Unpair device',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.autorenew, color: hPi4Global.hpi4Color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auto-Connect',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Automatically connect on app launch',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoConnectEnabled,
                    onChanged: (value) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('auto_connect_enabled', value);
                      setState(() {
                        _autoConnectEnabled = value;
                      });
                    },
                    activeColor: hPi4Global.hpi4Color,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanCard() {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _pairedDeviceMac != null
                  ? 'Scan for Other Devices'
                  : 'Scan for Devices',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_pairedDeviceMac == null) ...[
              const SizedBox(height: 8),
              Text(
                'Find your HealthyPi Move device',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            buildScanButton(context),
            if (_scanResults.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF1E1E1E), thickness: 1),
              const SizedBox(height: 16),
              Text(
                'Available Devices',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              ..._buildScanResultTiles(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => onConnectPressed(r.device),
          ),
        )
        .toList();
  }

  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      // Disconnect from the given Bluetooth device
      await device.disconnect();
      print('Device disconnected successfully');
    } catch (e) {
      print('Error disconnecting from device: $e');
    }
  }

  showPairDeviceDialog(BuildContext context, BluetoothDevice device) {
    final TextEditingController nicknameController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2D2D2D)),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.watch, color: hPi4Global.hpi4Color, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pair New Device',
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Found:',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hPi4Global.hpi4Color.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bluetooth, color: Colors.blue, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              device.name.isNotEmpty ? device.name : 'HealthyPi Move',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        device.id.id,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'What happens when you pair:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                _buildFeatureItem('Automatic reconnection on app launch'),
                _buildFeatureItem('Seamless data syncing'),
                _buildFeatureItem('Access to all health metrics'),
                SizedBox(height: 20),
                TextField(
                  controller: nicknameController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Device Nickname (Optional)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    hintText: 'e.g., "My Watch", "Work Device"',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[700]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: hPi4Global.hpi4Color),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: Icon(Icons.edit, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  redirectToScreens(device);
                },
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    // Create DeviceInfo with nickname
                    final deviceInfo = DeviceInfo(
                      macAddress: device.id.id,
                      deviceName: device.name.isNotEmpty ? device.name : 'healthypi move',
                      nickname: nicknameController.text.trim(),
                      firstPaired: DateTime.now(),
                      lastConnected: DateTime.now(),
                    );
                    
                    // Save using DeviceManager (also saves legacy format for compatibility)
                    await DeviceManager.savePairedDevice(deviceInfo);
                    
                    setState(() {
                      _pairedDeviceMac = deviceInfo.macAddress;
                      _pairedDeviceName = deviceInfo.displayName;
                    });
                    
                    Navigator.pop(context);
                    
                    Snackbar.show(
                      ABC.b,
                      '✓ Device paired successfully!',
                      success: true,
                    );
                    
                    redirectToScreens(device);
                  } catch (e) {
                    Snackbar.show(
                      ABC.b,
                      'Failed to pair device: $e',
                      success: false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(Icons.check),
                label: Text(
                  'Pair Device',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendCommand(
    List<int> commandList,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Tx CMD $commandList 0x${hex.encode(commandList)}");

    List<BluetoothService> services = await deviceName.discoverServices();

    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        commandService = service;
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            commandCharacteristic = characteristic;
            break;
          }
        }
      }
    }

    if (commandService != null && commandCharacteristic != null) {
      await commandCharacteristic?.write(commandList, withoutResponse: true);
    }
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[300], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void showLoadingIndicator(String text, BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            backgroundColor: Colors.black87,
            content: LoadingIndicator(text: text),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => HomePage()),
            ),
          ),
          title: Row(
            children: [
              Image.asset(
                'assets/healthypi_move.png',
                height: 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              const Text(
                'Pair Device',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          centerTitle: false,
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          color: hPi4Global.hpi4Color,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildScanContent(context),
            ],
          ),
        ),
      ),
    );
  }
}
