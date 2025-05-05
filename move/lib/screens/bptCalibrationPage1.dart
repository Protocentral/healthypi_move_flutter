import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';

import '../globals.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'package:fl_chart/fl_chart.dart';

import '../utils/snackbar.dart';
import '../widgets/scan_result_tile.dart';

class BPTCalibrationPage1 extends StatefulWidget {
  const BPTCalibrationPage1({super.key});

  @override
  State<BPTCalibrationPage1> createState() => _BPTCalibrationPage1State();
}

class _BPTCalibrationPage1State extends State<BPTCalibrationPage1> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late StreamSubscription<List<int>> _streamDataSubscription;

  @override
  void initState() {
    super.initState();
    if (_isScanning == false) {
      startScan();
    }
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
          (results) {
        _scanResults = results;
      },
      onError: (e) {
        // Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
    });
  }

  @override
  void dispose() {
    // Dispose the controller when the widget is removed from the widget tree
    _systolicController.dispose();
    _diastolicController.dispose();
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> startScan() async {
    // enable bluetooth on Android
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      return;
    }

    FlutterBluePlus.setLogLevel(LogLevel.verbose);
    FlutterBluePlus.adapterState.listen((event) {
      print(event);
    });

    await FlutterBluePlus.adapterState
        .where((BluetoothAdapterState state) => state == BluetoothAdapterState.on)
        .first;

    await FlutterBluePlus.startScan(
      withNames: ['healthypi move'],
    );
  }


  subscribeToChar(BluetoothDevice deviceName) async {
    List<BluetoothService> services = await deviceName.discoverServices();
    // Find a service and characteristic by UUID
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
  }


  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }


  Future<void> _sendCurrentDateTime(BluetoothDevice deviceName) async {
    List<int> commandDateTimePacket = [];

    var dt = DateTime.now();
    String cdate = DateFormat("yy").format(DateTime.now());
    print(cdate);
    print(dt.month);
    print(dt.day);
    print(dt.hour);
    print(dt.minute);
    print(dt.second);

    ByteData sessionParametersLength = ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);

    logConsole("Sending DateTime information: $cmdByteList");

    commandDateTimePacket.addAll(cmdByteList);

    logConsole("Sending DateTime Command: $commandDateTimePacket");

    List<BluetoothService> services = await deviceName.discoverServices();

    BluetoothService? targetService;
    BluetoothCharacteristic? targetCharacteristic;

    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        targetService = service;
        for (BluetoothCharacteristic characteristic
        in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            targetCharacteristic = characteristic;
            break;
          }
        }
      }
    }

    if (targetService != null && targetCharacteristic != null) {
      // Write to the characteristic
      await targetCharacteristic.write(
        commandDateTimePacket,
        withoutResponse: true,
      );
      logConsole('Data written: $commandDateTimePacket');
    }

  }

  Future onScanPressed() async {
    try {
      startScan();
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Stop Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  void onConnectPressed(BluetoothDevice device) {
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(
        ABC.c,
        prettyException("Connect Error:", e),
        success: false,
      );
    });

    Navigator.pop(context);

    _connectionStateSubscription = device.connectionState.listen((state) async {
      _connectionState = state;

      final subscription = device.mtu.listen((int mtu) {
        // iOS: initial value is always 23, but iOS will quickly negotiate a higher value
        print("mtu $mtu");
      });

      // cleanup: cancel subscription when disconnected
      device.cancelWhenDisconnected(subscription);

      // You can also manually change the mtu yourself.
      if (!kIsWeb && Platform.isAndroid) {
        device.requestMtu(512);
      }

      if (_connectionState == BluetoothConnectionState.connected) {
        showLoadingIndicator("Connected. Sending the calibration parameters...", context);
        await FlutterBluePlus.stopScan();
        await subscribeToChar(device);
        _sendCurrentDateTime(device);
        Future.delayed(Duration(seconds: 2), () async {
          await sendStartCalibration(context, device);
        });
      }
      else {

      }
    });
  }

  Future<void> _startListeningData(
      BluetoothDevice deviceName,
      ) async {

    logConsole("Started listening....");
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
        value,
        ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      //logConsole("Data Rx: $value");
      logConsole("Data Rx in hex: ${hex.encode(value)}");
      int pktType = bdata.getUint8(0);
    });

    // cleanup: cancel subscription when disconnected
    deviceName.cancelWhenDisconnected(_streamDataSubscription);
  }

  Future<void> sendStartCalibration(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Send start calibration command initiated");
    await _startListeningData(deviceName);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      String userInput1 = _systolicController.text;
      String userInput2 = _diastolicController.text;
      List<int> userCommandData = [];
      List<int> userCommandData1 = [];

      // Convert the user input string to an integer list (if applicable)
        if (userInput1.isNotEmpty) {
          userCommandData = userInput1.split(',').map((e) => int.parse(e.trim())).toList();
        }else{
          userCommandData = [0];
        }
      if (userInput2.isNotEmpty) {
        userCommandData1 = userInput2.split(',').map((e) => int.parse(e.trim())).toList();
      }else{
        userCommandData1 = [0];
      }

      commandPacket.addAll(hPi4Global.StartBPTCal);
      commandPacket.addAll(userCommandData);
      commandPacket.addAll(userCommandData1);
      commandPacket.addAll([0x00]);

      await _sendCommand(commandPacket, deviceName);
      logConsole(commandPacket.toString());
      Navigator.pop(context);
    });
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
                  borderRadius: BorderRadius.all(Radius.circular(8.0))),
              backgroundColor: Colors.black87,
              content: LoadingIndicator(text: text),
            ));
      },
    );
  }

  Future<void> _sendCommand(
      List<int> commandList,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Tx CMD $commandList 0x${hex.encode(commandList)}");

    List<BluetoothService> services = await deviceName.discoverServices();

    // Find a service and characteristic by UUID
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
      // Write to the characteristic
      await commandCharacteristic?.write(commandList, withoutResponse: true);
      //logConsole('Data written: $commandList');
    }
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Widget buildScanButton(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: hPi4Global.hpi4Color, // background color
        foregroundColor: Colors.white, // text color
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        minimumSize: Size(SizeConfig.blockSizeHorizontal * 40, 40),
      ),
      onPressed: () {
        onRefresh();
        onScanPressed();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'SCAN',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
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

  Future<void> showScanDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // user must tap button!
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.black,
              title: Text(
                'Select device to connect',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [buildScanButton(context)],
                          ),
                          ..._buildScanResultTiles(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(
                    'Close',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  onPressed: () {
                    FlutterBluePlus.stopScan();
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void logConsole(String logString) async {
    print("debug - $logString");
    setState(() {
      debugText += logString;
      debugText += "\n";
    });
  }

  void resetLogConsole() async {
    setState(() {
      debugText = "";
    });
  }

  String debugText = "Console Inited...";

  Widget _buildDebugConsole() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: SizedBox(
          height: 150, // 8 lines of text approximately
          width: SizeConfig.blockSizeHorizontal * 88,
          child: SingleChildScrollView(
            child: Text(
              debugText,
              style: TextStyle(
                fontSize: 12,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
            ),
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()))
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
          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                Card(
                  color: Colors.black,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height:20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child:Card(
                                    color: Colors.grey[900],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: <Widget>[
                                              //Icon(Icons.warning, color: Colors.yellow[300]),
                                              Text('BPT Calibration',
                                                style:
                                                hPi4Global.movecardTextStyle,),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: <Widget>[
                                              Expanded(
                                                // optional flex property if flex is 1 because the default flex is 1
                                                flex: 1,
                                                child: TextField(
                                                  controller: _systolicController,
                                                  style: TextStyle(
                                                    color: Colors.white, // Sets the text color
                                                    fontSize: 16,       // Sets the font size
                                                  ),
                                                  decoration: InputDecoration(
                                                    labelText: 'Systolic',
                                                    labelStyle: TextStyle(
                                                        color: Colors.grey[400]
                                                    ),
                                                    filled: true,
                                                    fillColor: Colors.grey[700],
                                                    border: OutlineInputBorder(
                                                        borderSide: BorderSide.none,
                                                        borderRadius: BorderRadius.circular(16)
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 20.0),
                                              Expanded(
                                                // optional flex property if flex is 1 because the default flex is 1
                                                flex: 1,
                                                child: TextField(
                                                  controller: _diastolicController,
                                                  style: TextStyle(
                                                    color: Colors.white, // Sets the text color
                                                    fontSize: 16,       // Sets the font size
                                                  ),
                                                  decoration: InputDecoration(
                                                    labelText: 'Diastolic',
                                                    labelStyle: TextStyle(
                                                        color: Colors.grey[400]
                                                    ),
                                                    filled: true,
                                                    fillColor: Colors.grey[700],
                                                    border: OutlineInputBorder(
                                                        borderSide: BorderSide.none,
                                                        borderRadius: BorderRadius.circular(16)
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 15.0),
                                          Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child:ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                hPi4Global
                                                    .hpi4Color, // background color
                                                foregroundColor:
                                                Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                  BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(
                                                  SizeConfig.blockSizeHorizontal *
                                                      100,
                                                  40,
                                                ),
                                              ),
                                              onPressed: () {
                                                FocusScope.of(context).unfocus();
                                                showScanDialog();
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8.0,
                                                ),
                                                child: Row(
                                                  //mainAxisSize: MainAxisSize.min,
                                                  mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    const Text(
                                                      ' Start Calibration ',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    Spacer(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.max,
                                        children: <Widget>[
                                          _buildDebugConsole(),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                              hPi4Global
                                                  .hpi4Color, // background color
                                              foregroundColor:
                                              Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(20),
                                              ),
                                            ),
                                            onPressed: () {
                                              resetLogConsole();
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.clear,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    'Clear Console ',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),


                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}