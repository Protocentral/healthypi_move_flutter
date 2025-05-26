import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/screens/scr_fetch_ecg.dart';
import 'package:move/screens/scr_syncing.dart';
import 'package:move/screens/scr_stream_selection.dart';
import 'package:move/utils/extra.dart';
import 'package:move/utils/snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import '../widgets/scan_result_tile.dart';
import '../widgets/system_device_tile.dart';
import 'scr_device.dart';

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
  String _deviceNotFoundMessage = "";

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

  Future<void> _tryAutoConnectToPairedDevice() async {
    String? pairedMac = await getPairedDeviceMac();
    if (pairedMac != null && pairedMac.isNotEmpty) {
      setState(() {
        _autoConnecting = true;
        _deviceNotFound = false;
        _deviceNotFoundMessage = "";
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
            if (mounted) setState(() {
              _autoConnecting = false;
              _deviceNotFound = false;
              _deviceNotFoundMessage = "";
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
            _deviceNotFoundMessage =
            "Device not found. Please make sure your paired device is turned on and in range.";
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

    _tryAutoConnectToPairedDevice();

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
      prefs.setString('lastSynced','0');
      prefs.setString('latestHR','0');
      prefs.setString('latestTemp','0');
      prefs.setString('latestSpo2','0');
      prefs.setString('latestActivityCount','0');
      prefs.setString('lastUpdatedHR','0');
      prefs.setString('lastUpdatedTemp','0');
      prefs.setString('lastUpdatedSpo2','0');
      prefs.setString('lastUpdatedActivity','0');
      prefs.setString('fetchStatus','0');
    });
  }

  bool pairedStatus = false;

  Future<void> onConnectPressed(BluetoothDevice device) async {
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(
        ABC.c,
        prettyException("Connect Error:", e),
        success: false,
      );
    });

    _connectionStateSubscription = device.connectionState.listen((state) async {
      _connectionState = state;

      final subscription = device.mtu.listen((int mtu) {
        print("mtu $mtu");
      });

      device.cancelWhenDisconnected(subscription);

      if (!kIsWeb && Platform.isAndroid) {
        device.requestMtu(512);
      }

      if (_connectionState == BluetoothConnectionState.connected) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? pairedStatus = "";
        setState(() {
          pairedStatus = prefs.getString('pairedStatus');
        });
        if(pairedStatus == "paired"){
          if(widget.tabIndex == "1"){
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScrSyncing(device: device),
            ),
          );
        }else if(widget.tabIndex == "2"){
          showLoadingIndicator("Connected. Erasing the data...", context);
          //await subscribeToChar(device);
          _eraseAllLogs(context, device);
        }else if(widget.tabIndex == "3"){
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ScrStreamsSelection(device: device),
            ),
          );
        }else if(widget.tabIndex == "4"){
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ScrFetchECG(device: device),
              ),
            );
          }
        else{

        }
        }else{
          showPairDeviceDialog(context, device);
        }
      }
    });
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
        child:ElevatedButton(
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
        child:  ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color, // background color
            foregroundColor: Colors.white, // text color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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

  Widget _buildScanCard(BuildContext context) {
    // --- Auto-Connect UI ---
    if (_autoConnecting) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Connecting to your paired device...",
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    // --- End Auto-Connect UI ---

    // --- Device Not Found Message UI ---
    if (_deviceNotFound) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
              SizedBox(height: 20),
              Text(
                _deviceNotFoundMessage,
                style: TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _deviceNotFound = false;
                    _deviceNotFoundMessage = "";
                  });
                  _tryAutoConnectToPairedDevice();
                },
                child: Text("Try Again"),
              ),
            ],
          ),
        ),
      );
    }
    // --- End Device Not Found Message UI ---

    // ...existing code...
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Select the device',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            buildScanButton(context),
            ..._buildScanResultTiles(context),
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
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                SizedBox(width: 10),
                Text('Do you wish to pair the device ?',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              ' Please click "Yes" to pair',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () async{
                  try {
                    final Directory appDocDir = await getApplicationDocumentsDirectory();
                    final String filePath = '${appDocDir.path}/paired_device_mac.txt';
                    final File macFile = File(filePath);
                    await macFile.writeAsString(device.id.id);
                    logConsole("...........Paired status saved");
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    setState((){
                      prefs.setString('pairedStatus','paired');
                    });
                    Navigator.pop(context);
                    if(widget.tabIndex == "1"){
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrSyncing(device: device),
                        ),
                      );
                    }else if(widget.tabIndex == "2"){
                      showLoadingIndicator("Connected. Erasing the data...", context);
                      //await subscribeToChar(device);
                      _eraseAllLogs(context, device);
                    } else if(widget.tabIndex == "3"){
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrStreamsSelection(device: device),
                        ),
                      );
                    } else if(widget.tabIndex == "4"){
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrFetchECG(device: device),
                        ),
                      );
                    }
                    else{

                    }
                  } catch (e) {
                  }
                },
                child: Text(
                  'Yes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if(widget.tabIndex == "1"){
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ScrSyncing(device: device),
                      ),
                    );
                  }else if(widget.tabIndex == "2"){
                    showLoadingIndicator("Connected. Erasing the data...", context);
                    //await subscribeToChar(device);
                    _eraseAllLogs(context, device);
                  }else if(widget.tabIndex == "3"){
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ScrStreamsSelection(device: device),
                      ),
                    );
                  }else if(widget.tabIndex == "4"){
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ScrFetchECG(device: device),
                      ),
                    );
                  }
                  else{

                  }
                },
                child: Text(
                  'No',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

 /* subscribeToChar(BluetoothDevice deviceName) async {
    List<BluetoothService> services = await deviceName.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        commandService = service;
        for (BluetoothCharacteristic characteristic
        in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD_DATA)) {
            dataCharacteristic = characteristic;
            await dataCharacteristic?.setNotifyValue(true);
            break;
          }
        }
      }
    }
  }*/

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
        backgroundColor: hPi4Global.appBackgroundColor,
        appBar: AppBar(
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed:
                () => Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage())),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Image.asset(
                'assets/healthypi_move.png',
                fit: BoxFit.fitWidth,
                height: 30,
              ),
              const Text('Find Devices', style: hPi4Global.movecardTextStyle),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Column(
                  children:[
                  ]
              ),
              _buildScanCard(context),
            ],
          ),
        ),
      ),
    );
  }
}