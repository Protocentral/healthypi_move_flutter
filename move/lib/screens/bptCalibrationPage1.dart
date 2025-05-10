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
  final _formKey = GlobalKey<FormState>();

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

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  bool _showcalibrationButton = false;
  bool _showcalibrationCard = false;
  bool _showcalibrationprogress = false;
  bool _showScanCard = true;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
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

    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((
      state,
    ) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
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

  void logConsole(String logString) async {
    print("[HPI] $logString");
  }

  Future onScanPressed() async {
    try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      var withServices = [Guid("180f")]; // Battery Level Service
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
        //withNames: ['healthypi move'],
        /*webOptionalServices: [
          Guid("180f"), // battery
          Guid("180a"), // device info
          Guid("1800"), // generic access
          Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        ],*/
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

  Future onRefresh() {
    if (_isScanning == false) {
      onScanPressed();
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Future _onStopPressed() async {
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

  late BluetoothDevice Connecteddevice;

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

      if (mounted) {
        setState(() {
          _showScanCard = false;
          _showcalibrationButton = true;
          //_showcalibrationCard = true;
        });
      }

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
        if (mounted) {
          setState(() {
            Connecteddevice = device;
            sendSetCalibrationCommand(device);
            _showcalibrationButton = true;
          });
        }
      }
    });
  }

  Future<void> sendSetCalibrationCommand(BluetoothDevice device) async {
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.SetBPTCalMode);
      await _sendCommand(commandPacket, device);
      logConsole(commandPacket.toString());
    });
  }

  int index = 0;
  int progress = 0;
  int status = 0;
  String statusString = "";

  Future<void> _startListeningData(BluetoothDevice deviceName) async {
    logConsole("Started listening....");
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      //logConsole("Data Rx: $value");
      logConsole("Data Rx in hex: ${hex.encode(value)}");

      setState(() {
        status = bdata.getUint8(0);
        progress = bdata.getUint8(1);
        index = bdata.getUint8(2);
      });
      if (status == 0) {
        statusString = "Nosignal";
      } else if (status == 1) {
        statusString = "In progress";
      } else if (status == 2) {
        statusString = "Success";
        setState(() {
          _showcalibrationButton = false;
          _showcalibrationCard = false;
          _showcalibrationprogress = false;
        });
      } else if (status == 6) {
        statusString = "Failed";
      } else {
        statusString = "";
      }
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
        userCommandData =
            userInput1.split(',').map((e) => int.parse(e.trim())).toList();
      } else {
        userCommandData = [0];
      }
      if (userInput2.isNotEmpty) {
        userCommandData1 =
            userInput2.split(',').map((e) => int.parse(e.trim())).toList();
      } else {
        userCommandData1 = [0];
      }

      commandPacket.addAll(hPi4Global.StartBPTCal);
      commandPacket.addAll(userCommandData);
      commandPacket.addAll(userCommandData1);
      commandPacket.addAll([0x00]);

      await _sendCommand(commandPacket, deviceName);
      logConsole(commandPacket.toString());
      setState(() {
        _showcalibrationprogress = true;
      });
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
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            backgroundColor: Colors.black87,
            content: LoadingIndicator(text: text),
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

  Future onDisconnectPressed() async {
    try {
      await Connecteddevice.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.c,
        prettyException("Disconnect Error:", e),
        success: false,
      );
      print("$e backtrace: $backtrace");
    }
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

  Widget _buildScanCard(BuildContext context) {
    if (_showScanCard == true) {
      return Card(
        color: Colors.grey[800],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Select the device to calibrate',
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
    } else {
      return Container();
    }
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: hPi4Global.hpi4Color, // background color
          foregroundColor: Colors.white, // text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed: _onStopPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[const Icon(Icons.stop), Spacer()],
          ),
        ),
      );
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: hPi4Global.hpi4Color, // background color
          foregroundColor: Colors.white, // text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
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
      );
    }
  }

  Widget _showCalibrationStartButton() {
    if (_showcalibrationButton == true) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: hPi4Global.hpi4Color, // background color
          foregroundColor: Colors.white, // text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed: () {
          setState(() {
            _showcalibrationCard = true;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.search, color: Colors.white),
              const Text(
                ' Start Calibration ',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Spacer(),
            ],
          ),
        ),
      );
    } else {
      return Container();
    }
  }

  Widget showCalibrationCard() {
    if (_showcalibrationCard == true) {
      return Card(
        color: Colors.grey[800],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        //Icon(Icons.warning, color: Colors.yellow[300]),
                        Text(
                          'Calibrate point ${index+1} of 3',
                          style: hPi4Global.movecardTextStyle,
                        ),
                        SizedBox(height: 5.0),
                        Text(
                          'Measure your blood pressure using a standard BP moniter and enter the results below. \nWhen you are ready and the finger sensor is in place, press the Proceed button.',
                          style: hPi4Global.movecardSubValue1TextStyle,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    SizedBox(height: 10.0),
                    Form(
                      key: _formKey,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Expanded(
                            // optional flex property if flex is 1 because the default flex is 1
                            flex: 1,
                            child: TextFormField(
                              controller: _systolicController,
                              style: TextStyle(
                                color: Colors.white, // Sets the text color
                                fontSize: 16, // Sets the font size
                              ),
                              decoration: InputDecoration(
                                labelText: 'Systolic',
                                labelStyle: TextStyle(color: Colors.grey[400]),
                                filled: true,
                                fillColor: Colors.grey[700],
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              keyboardType:
                                  TextInputType
                                      .number, // Sets the keyboard type for numeric input
                              validator: (value) {
                                // Validation logic
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a value';
                                }
                                final intValue = int.tryParse(value);
                                if (intValue == null) {
                                  return 'Please enter a valid number';
                                }
                                if (intValue < 80 || intValue > 180) {
                                  return 'Enter between 80 and 180';
                                }
                                return null; // Return null if the input is valid
                              },
                            ),
                          ),
                          SizedBox(width: 20.0),
                          Expanded(
                            // optional flex property if flex is 1 because the default flex is 1
                            flex: 1,
                            child: TextFormField(
                              controller: _diastolicController,
                              style: TextStyle(
                                color: Colors.white, // Sets the text color
                                fontSize: 16, // Sets the font size
                              ),
                              decoration: InputDecoration(
                                labelText: 'Diastolic',
                                labelStyle: TextStyle(color: Colors.grey[400]),
                                filled: true,
                                fillColor: Colors.grey[700],
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              keyboardType:
                                  TextInputType
                                      .number, // Sets the keyboard type for numeric input
                              validator: (value) {
                                // Validation logic
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a value';
                                }
                                final intValue = int.tryParse(value);
                                if (intValue == null) {
                                  return 'Please enter a valid number';
                                }
                                if (intValue < 50 || intValue > 120) {
                                  return ' Enter between 50 and 120';
                                }
                                return null; // Return null if the input is valid
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 15.0),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              hPi4Global.hpi4Color, // background color
                          foregroundColor: Colors.white, // text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: Size(
                            SizeConfig.blockSizeHorizontal * 100,
                            40,
                          ),
                        ),
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          if (_formKey.currentState!.validate()) {
                            showLoadingIndicator(
                              "Sending start calibration...",
                              context,
                            );
                            await FlutterBluePlus.stopScan();
                            await subscribeToChar(Connecteddevice);
                            _sendCurrentDateTime(Connecteddevice);
                            Future.delayed(Duration(seconds: 2), () async {
                              await sendStartCalibration(
                                context,
                                Connecteddevice,
                              );
                            });
                          } else {
                            // Input is invalid, show errors
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            //mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                ' Proceed ',
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
                    showCalibrationProgress(),
                  ],
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      );
    } else {
      return Container();
    }
  }

  Widget showCalibrationProgress() {
    if (_showcalibrationprogress == true) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                // SizedBox(height:20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      //height: SizeConfig.blockSizeVertical * 20,
                      width: SizeConfig.blockSizeHorizontal * 88,
                      child: Card(
                        color: Colors.grey[900],
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min, // Shrink-wrap children
                            children: <Widget>[
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize:
                                    MainAxisSize.min, // Shrink-wrap children
                                children: <Widget>[
                                  Text(
                                    'Calibration of $index',
                                    style: hPi4Global.movecardTextStyle,
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.0),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize:
                                    MainAxisSize.min, // Shrink-wrap children
                                children: <Widget>[
                                  Text(
                                    'Progress: $progress%',
                                    style: hPi4Global.movecardTextStyle,
                                  ),
                                ],
                              ),
                              SizedBox(height: 5.0),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: <Widget>[
                                  SizedBox(
                                    height: 10,
                                    width:
                                        200, // Provide a fixed width for the progress bar
                                    child: LinearProgressIndicator(
                                      value:
                                          progress.toDouble() > 0
                                              ? progress.toDouble()
                                              : null,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            hPi4Global.hpi4Color,
                                          ),
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 5.0),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize:
                                    MainAxisSize.min, // Shrink-wrap children
                                children: <Widget>[
                                  Text(
                                    'Calibration $index is: $statusString',
                                    style: hPi4Global.movecardTextStyle,
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
              ],
            ),
          ],
        ),
      );
    } else {
      return Container();
    }
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
          onPressed: () {
            if (_showcalibrationButton == true) {
              onDisconnectPressed();
            } else {
              /// Do Nothing
            }
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          },
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
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: <Widget>[
            Column(
              children: [
                
                //buildScanButton(context),
                //..._buildScanResultTiles(context),
              ],
            ),
            _buildScanCard(context),
            SizedBox(height: 20),
            _showCalibrationStartButton(),
            SizedBox(height: 20),
            showCalibrationCard(),
          ],
        ),
      ),
    );
  }
}
