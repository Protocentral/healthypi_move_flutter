import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';

import '../globals.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
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
  List<BluetoothDevice> systemDevices = [];
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
  bool _showOnSuccessCal = false;

  bool startListeningFlag = false;

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
    _streamDataSubscription.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future onScanPressed() async {
    try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      var withServices = [Guid("180f")]; // Battery Level Service
      systemDevices = await FlutterBluePlus.systemDevices(withServices);
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
            //_showcalibrationButton = true;
            _showcalibrationCard = true;
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

  void showSuccessDialog(BuildContext context, String titleMessage, String message, Icon customIcon) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                //Icon(Icons.check_circle, color: Colors.green),
                customIcon,
                SizedBox(width: 10),
                Text('Success',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext); // Close the dialog
                  //sendEndCalibration(context, Connecteddevice, 'success');
                },
                child: Text(
                  'OK',
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

  int index = 0;
  int progress = 0;
  int status = 0;
  String statusString = "";

  Future<void> _startListeningData(BluetoothDevice deviceName) async {
    logConsole("Started listening....");
    startListeningFlag = true;
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      logConsole("Data Rx: $value");
      logConsole("Data Rx in hex: ${hex.encode(value)}");

      setState(() {
        status = bdata.getUint8(0);
        progress = bdata.getUint8(1);
        //index = bdata.getUint8(2);
      });
      if (status == 0) {
        statusString = "No signal";
      } else if (status == 1) {
        statusString = "";
      } else if (status == 2) {
        statusString = "";
        setState(() {
          _showOnSuccessCal = true;
          _showcalibrationButton = false;
          _showcalibrationCard = false;
          _showcalibrationprogress = false;
        });
        showSuccessDialog(context, 'Success', 'Calibration was successful!',
          Icon(Icons.check_circle, color: Colors.green), // Pass the custom icon here
        );
      }
      else if (status == 4) {
        statusString = "Excess motion. Hold still";
      }
      else if (status == 6) {
        statusString = "Failed";
      }
      else if (status == 16 || status == 19 || status == 3) {
        statusString = "Weak signal. Try moving the sensor";
      }
      else if (status == 23 || status == 24) {
        statusString = "No finger contact. Adjust sensor position";
      }
      else {
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
    if(startListeningFlag == true) {
      _streamDataSubscription.cancel();
    }
      await _startListeningData(deviceName);
      await Future.delayed(Duration(seconds: 2), () async {
        List<int> commandPacket = [];
        String userInput1 = _systolicController.text;
        String userInput2 = _diastolicController.text;
        List<int> userCommandData = [];
        List<int> userCommandData1 = [];
        List<int> calIndex = [];
        calIndex = [index];
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
        commandPacket.addAll(calIndex);

        await _sendCommand(commandPacket, deviceName);
        logConsole(commandPacket.toString());
        setState(() {
          _showcalibrationprogress = true;
        });
        Navigator.pop(context);
      });
    }

  Future<void> sendEndCalibration(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Send end calibration command initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.EndBPTCal);
      await _sendCommand(commandPacket, deviceName);
      logConsole(commandPacket.toString());
      setState(() {
        _showOnSuccessCal = true;
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
        child:ElevatedButton(
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
        ),
      );
    }
  }

  Widget _showAnotherPointCard(){
    if (_showOnSuccessCal == true) {
      return Card(
        color: Colors.grey[800],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Calibration point no "+(index+1).toString()+"/5",
                  style: hPi4Global.movecardSubValue1TextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child:  ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hPi4Global.hpi4Color, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async{
                    setState((){
                      //_showcalibrationButton = true;
                      _showcalibrationCard = true;
                      _showOnSuccessCal = false;
                      index = index+1;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.add, color: Colors.white),
                        const Text(
                          ' Add another point ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Upto five calibrations points can be added to the device. \nMore points = More accuracy.',
                  style: hPi4Global.movecardSubValue1TextStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child:  ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async{
                    sendEndCalibration(context, Connecteddevice);
                    Future.delayed(Duration(seconds: 2), () async {
                      Navigator.of(
                        context,
                      ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
                    });

                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.cancel, color: Colors.white),
                        const Text(
                          ' End Calibration ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
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
      );
    } else {
      return Container();
    }
  }

  Widget _showCancelButton(){
    if (_showcalibrationprogress == true) {
      return Card(
        color: Colors.grey[800],
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'In calibration mode',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child:  ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async{
                    sendEndCalibration(context, Connecteddevice);
                    Future.delayed(Duration(seconds: 2), () async {
                      await onDisconnectPressed();
                      Navigator.of(
                        context,
                      ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
                    });

                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.cancel, color: Colors.white),
                        const Text(
                          ' Exit calibration mode ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
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
                          "Calibrate point "+ (index+1).toString(),
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
                              enabled: !_showcalibrationprogress,
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
                              enabled: !_showcalibrationprogress,
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
                      padding: const EdgeInsets.fromLTRB(32, 4, 32, 4),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              hPi4Global.hpi4Color, // background color
                          foregroundColor: Colors.white, // text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () async {
                          if(_showcalibrationprogress == false){
                            FocusScope.of(context).unfocus();
                            if (_formKey.currentState!.validate()) {
                              showLoadingIndicator(
                                "Sending start calibration...",
                                context,
                              );
                              await FlutterBluePlus.stopScan();
                              await subscribeToChar(Connecteddevice);
                              // _sendCurrentDateTime(Connecteddevice);
                              Future.delayed(Duration(seconds: 2), () async {
                                await sendStartCalibration(
                                  context,
                                  Connecteddevice,
                                );
                              });
                            } else {
                              // Input is invalid, show errors
                            }
                          }else{
                            null;
                          }

                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            //mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                ' Start ',
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
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
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
                      width: SizeConfig.blockSizeHorizontal * 78,
                      child: Card(
                        color: Colors.grey[900],
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            mainAxisSize:
                                MainAxisSize.min, // Shrink-wrap children
                            children: <Widget>[
                              SizedBox(height: 10.0),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize:
                                    MainAxisSize.min, // Shrink-wrap children
                                children: <Widget>[
                                  Text(
                                    '$progress%',
                                    style: hPi4Global.movecardTextStyle,
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.0),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: <Widget>[
                                  SizedBox(
                                    height: 10,
                                    width: 150, // Provide a fixed width for the progress bar
                                    child: LinearProgressIndicator(
                                      //value: progress.toDouble() > 0 ? progress.toDouble() : null,
                                      value: (progress/100).toDouble(),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            hPi4Global.hpi4Color,
                                          ),
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.0),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize:
                                MainAxisSize.min, // Shrink-wrap children
                                children: <Widget>[
                                  Text('Calibrating...',
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
                                  Text('$statusString',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,color: Colors.red),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10.0),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                                child:  ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red, // background color
                                    foregroundColor: Colors.white, // text color
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed: () async{
                                    sendEndCalibration(context, Connecteddevice);
                                    Future.delayed(Duration(seconds: 2), () async {
                                      await onDisconnectPressed();
                                      Navigator.of(
                                        context,
                                      ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
                                    });

                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: <Widget>[
                                        Icon(Icons.cancel, color: Colors.white),
                                        const Text(
                                          ' Cancel ',
                                          style: TextStyle(fontSize: 16, color: Colors.white),
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
              ],
            ),
          ],
        ),
      );
    } else {
      return Container();
    }
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
    debugText += logString;
    debugText += "\n";
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
              ],
            ),
            _buildScanCard(context),
            SizedBox(height: 20),
            _showAnotherPointCard(),
            SizedBox(height: 20),
            //_showCalibrationStartButton(),
            //SizedBox(height: 20),
            showCalibrationCard(),
            //SizedBox(height: 20),
            //_showCancelButton(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Colors.grey[900],
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: <Widget>[
                      _buildDebugConsole(),
                    ],
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
