import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
//import 'package:move/scanConnect.dart';
import 'dfu.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/fetchfileData.dart';
import 'package:move/sizeConfig.dart';

import '../utils/snackbar.dart';
import '../widgets/scan_result_tile.dart';
import '../utils/extra.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';

import 'home.dart';

class DevicePage extends StatefulWidget {
  DevicePage({Key? key}) : super(key: key);

  @override
  _DevicePageState createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;

  String selectedOption = "sync";

  @override
  void initState() {
    super.initState();

    if (_isScanning == false) {
      FlutterBluePlus.startScan(withNames: ['healthypi move'],timeout: const Duration(seconds: 15));
    }
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results;

    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;

    });

  }

  @override
  Future<void> dispose() async {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _connectionStateSubscription.cancel();
    onStopPressed();
    super.dispose();
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future<void> _sendCurrentDateTime(BluetoothDevice deviceName) async {
    /* Send current DataTime to wiser device - Bluetooth Packet format

     | Byte  | Value
     ----------------
     | 0 | WISER_CMD_SET_DEVICE_TIME (0x41)
     | 1 | sec
     | 2 | min
     | 3 | hour
     | 4 | mday(day of the month)
     | 5 | month
     | 6 | year

     */

    List<int> commandDateTimePacket = [];

    var dt = DateTime.now();
    String cdate = DateFormat("yy").format(DateTime.now());
    print(cdate);
    print(dt.month);
    print(dt.day);
    print(dt.hour);
    print(dt.minute);
    print(dt.second);

    ByteData sessionParametersLength = new ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);

    logConsole("AKW: Sending DateTime information: " + cmdByteList.toString());

    commandDateTimePacket.addAll(cmdByteList);

    logConsole("AKW: Sending DateTime Command: " + commandDateTimePacket.toString());

    List<BluetoothService> services = await deviceName.discoverServices();
    BluetoothService? targetService;
    BluetoothCharacteristic? targetCharacteristic;

    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        targetService = service;
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            targetCharacteristic = characteristic;
            break;
          }
        }
      }
    }

    if (targetService != null && targetCharacteristic != null) {
      // Write to the characteristic
      await targetCharacteristic.write(commandDateTimePacket,
        withoutResponse: true);
      print('Data written: $commandDateTimePacket');

    }

    await deviceName.disconnect();

  }


  Future onScanPressed() async {
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withNames: ['healthypi move'],
      );
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
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });

    _connectionStateSubscription = device.connectionState.listen((state) {
      _connectionState = state;
      if( _connectionState == BluetoothConnectionState.connected && selectedOption == "sync"){
        //await device.disconnect();
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomePage()));
      }
      else if(_connectionState == BluetoothConnectionState.connected && selectedOption == "fetchLogs"){
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) =>
                FetchFileData(connectionState:_connectionState, connectedDevice:device )));
      }else if(_connectionState == BluetoothConnectionState.connected && selectedOption == "setTime") {
        _sendCurrentDateTime(device);
      }
      else if(_connectionState == BluetoothConnectionState.connected && selectedOption == "readDevice"){

      }
      else if(_connectionState == BluetoothConnectionState.connected && selectedOption == "eraseAll"){

      }
      else{
        //device.disconnect();
      }
      /*if (mounted) {
        setState(() {

        });

      }*/
    });
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        minimumSize: Size(SizeConfig.blockSizeHorizontal*40, 40),
      ),
      onPressed: () {
        onScanPressed();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('SCAN', style: new TextStyle(fontSize: 16, color:Colors.white)
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
          onTap: () => onConnectPressed(r.device)
      ),
    ).toList();
  }

  Future<void> showScanDialog(){
  return showDialog<void>(
      context: context,
      barrierDismissible: true, // user must tap button!
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor:Colors.black,
            title: Text('Select device to connect',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            content: Container(
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
                                  children: [
                                    buildScanButton(context),
                                  ]),
                              ..._buildScanResultTiles(context),
                            ]
                        )
                    )
                  ]
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('Close',
                  style: TextStyle(fontSize: 16, color: Colors.white),),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        });
      }
  );
}

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
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
                                Container(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: <Widget>[
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Text('Device Management',
                                                    style: hPi4Global.movecardTextStyle),
                                                //Icon(Icons.favorite_border, color: Colors.black),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => DeviceManagement()),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  //mainAxisSize: MainAxisSize.min,
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.system_update,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Update Firmware ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  selectedOption = "readDevice";
                                                });
                                                //showScanDialog();
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.system_update,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Read Device ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  selectedOption = "sync";
                                                });
                                                showScanDialog();
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.sync,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Sync ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  selectedOption = "fetchLogs";
                                                });
                                                showScanDialog();
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.sync,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Fetch Logs ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  selectedOption = "setTime";
                                                });
                                                showScanDialog();
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.sync,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Set Time ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),

                                          ]),
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


