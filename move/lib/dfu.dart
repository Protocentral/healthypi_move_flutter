import 'dart:io';
import 'dart:async';

import 'dart:typed_data';
import 'dart:ui';

import 'states/WiserBLEProvider.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'ble/ble_scanner.dart';
import 'sizeConfig.dart';
import 'package:intl/intl.dart';

//import 'package:mcumgr/mcumgr.dart' as mcumgr;
import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
//import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;

late FlutterReactiveBle _fble;

late QualifiedCharacteristic commandCharacteristic;
late QualifiedCharacteristic DataCharacteristic;
late StreamSubscription<ConnectionStateUpdate> _connection;

bool connectedToDevice = false;
bool pcConnected = false;
String pcCurrentDeviceID = " ";
String pcCurrentDeviceName = " ";

class DeviceManagement extends StatefulWidget {
  DeviceManagement({Key? key}) : super(key: key);

  @override
  State createState() => new DeviceManagementState();
}

class DeviceManagementState extends State<DeviceManagement> {

  String dfuFilePath = "";

  //late mcumgr.Client _smpClient;

  bool _showDeviceCard = false;

  bool _listeningDebug = false;
  bool _listeningSMP = false;

  String debugOutput = "";
  int globalDFUProgress = 0;
  late ProgressDialog prDFU;
  bool dfuRunning = false;

  String dfuPath = " ";
  String dfuLength = " ";
  String dfuHash = " ";


  @override
  void initState() {
    Provider.of<BleScanner>(context, listen: false)
        .startScan([Uuid.parse("0000180d-0000-1000-8000-00805f9b34fb")], "");
    super.initState();
  }

  void dispose() {
    print("AKW: DISPOSING");
    _cancel();
    super.dispose();
  }

  void _cancel() async {
    if (_listeningSMP) {
      //_smpClient.close();
    }
  }


  Future<void> connectToDevice(
      BuildContext context, DiscoveredDevice currentDevice) async {

    _fble =
    await Provider.of<WiserBLEProvider>(context, listen: false).getBLE();

    logConsole('Initiated connection to device: ' + currentDevice.id);

    //pcCurrentDeviceID = currentDevice.id;
    //pcCurrentDeviceName = currentDevice.name;

    commandCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_CMD),
        serviceId: Uuid.parse(hPi4Global.UUID_SERVICE_CMD),
        deviceId: currentDevice.id);

    _connection = _fble
        .connectToAdvertisingDevice(
        id: currentDevice.id,
        withServices: [Uuid.parse(hPi4Global.UUID_CHAR_CMD_DATA)],
        prescanDuration: const Duration(seconds: 5))
        .listen((connectionStateUpdate) async {
      //currentConnState = connectionStateUpdate.connectionState;

      ///notifyListeners();
      logConsole("Connecting device: " + connectionStateUpdate.toString());
      if (connectionStateUpdate.connectionState ==
          DeviceConnectionState.connected) {
        showLoadingIndicator("Connecting to device...", context);
        logConsole("Connected !");
        setState(() {
          connectedToDevice = true;
          pcConnected = true;
          pcCurrentDeviceID = currentDevice.id;
          pcCurrentDeviceName = currentDevice.name;
        });
        await Future.delayed(Duration(seconds: 1), () async {
          await _setMTU(currentDevice.id);
        });

      } else if (connectionStateUpdate.connectionState ==
          DeviceConnectionState.disconnected) {
        connectedToDevice = false;
        //Navigator.pop(context);
      }
      //if(connectionState.failure.code.toString();)
    }, onError: (dynamic error) {
      logConsole("Connect error: " + error.toString());
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

  Future<void> _setMTU(String deviceMAC) async {
    int recdMTU = await _fble.requestMtu(deviceId: deviceMAC, mtu: 128);
    logConsole("MTU negotiated: " + recdMTU.toString());
    Navigator.pop(context);
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  Widget showScanResults() {
    return Consumer3<BleScannerState, BleScanner, WiserBLEProvider>(
        builder: (context, bleScannerState, bleScanner, wiserBle, child) {
          return Card(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      connectedToDevice
                          ? MaterialButton(
                        minWidth: 100.0,
                        color: Colors.red,
                        child: Row(
                          children: <Widget>[
                            Text('Disconnect',
                                style: new TextStyle(
                                    fontSize: 18.0, color: Colors.white)),
                          ],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        onPressed: () async {
                          await _disconnect();
                          bleScanner.startScan([], "");
                        },
                      )
                          : MaterialButton(
                        minWidth: 100.0,
                        color: Colors.blue,
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            Text('Scan & Connect',
                                style: new TextStyle(
                                    fontSize: 18.0, color: Colors.white)),
                          ],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        onPressed: () async {
                          if (Platform.isAndroid) {
                            bool bleStatusFlag = await wiserBle.getBleStatus();
                            if (await wiserBle.checkPermissions(
                                context, bleStatusFlag) ==
                                true) {
                              bleScanner.startScan([], "");
                            } else {
                              //Do not attempt to connect
                            }
                          } else {
                            bleScanner.startScan([], "");
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Consumer3<BleScannerState, BleScanner, WiserBLEProvider>(
                    builder: (context, bleScannerState, bleScanner, wiserBle, child) {
                      return Column(
                        children: [
                          connectedToDevice?
                          Text("Connected To:  "+pcCurrentDeviceName,
                              style: new TextStyle(fontSize: 18.0, color: Colors.black)):
                          ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(8),
                              itemCount: bleScannerState.discoveredDevices.length,
                              separatorBuilder: (BuildContext context, int index) =>
                              const Divider(),
                              itemBuilder: (BuildContext context, int index) {
                                return ListTile(
                                  title: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.bluetooth),
                                            Text(bleScannerState
                                                .discoveredDevices[index].name),
                                            Padding(
                                              padding:
                                              const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                              child: SignalStrengthIndicator.bars(
                                                value: bleScannerState
                                                    .discoveredDevices.length >
                                                    0
                                                    ? 2 *
                                                    (bleScannerState
                                                        .discoveredDevices[index]
                                                        .rssi +
                                                        100) /
                                                    100
                                                    : 0, //patchBLE.patchRSSI / 100,
                                                size: 25,
                                                barCount: 4,
                                                spacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    Provider.of<BleScanner>(context, listen: false)
                                        .stopScan();
                                    await connectToDevice(context,
                                        bleScannerState.discoveredDevices[index]);
                                  },
                                );
                              }),
                        ],
                      );
                    }),
              ]));
        });
  }

  Future<void> _sendCurrentDateTime() async {
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
    await _fble.writeCharacteristicWithoutResponse(commandCharacteristic,
        value: commandDateTimePacket);
    print("DateTime Sent");
  }


  Future<void> _disconnect() async {
    //String deviceID = patchCurrentMAC;
    try {
      logConsole('Disconnecting ');
      if (connectedToDevice == true) {
        showLoadingIndicator("Disconnecting....", context);
        await Future.delayed(Duration(seconds: 3), () async {
          await _connection.cancel();
          setState(() {
            connectedToDevice = false;
          });
          Navigator.pop(context);
        });
        Navigator.pop(context);
      }
    } on Exception catch (e, _) {
      logConsole("Error disconnecting from a device: $e");
    } finally {
      // Since [_connection] subscription is terminated, the "disconnected" state cannot be received and propagated
    }
  }

  Widget _setDeviceDateTime() {
    if (connectedToDevice == true) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(64.0, 4.0, 64.0, 4.0),
        child: MaterialButton(
          //minWidth: 50.0,
          color: Colors.blue,
          child: Row(
            children: <Widget>[
              Text('Set Time',
                  style: new TextStyle(fontSize: 18.0, color: Colors.white)),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          onPressed: () async {
            await _sendCurrentDateTime();
          },
        ),
      );
    } else {
      return Container();
    }
  }


  void _smpReset() {
   // _smpClient.reset(SMPtimeout);
  }

  late QualifiedCharacteristic SMPCharacteristic;

  Future<void> _startSMPClient(String deviceID) async {
    SMPCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_SMP),
        serviceId: Uuid.parse(hPi4Global.UUID_SERV_SMP),
        deviceId: deviceID);

   /* _smpClient = mcumgr.Client(
        input: //await Provider.of<PatchBLEProvider>(context, listen: false)
        await _fble.subscribeToCharacteristic(SMPCharacteristic),
        output: (value) => _patchSendSMP(value, deviceID));
    _listeningSMP = true;*/
  }

  Future<void> _patchSendSMP(List<int> commandList, String deviceID) async {
    await _fble.writeCharacteristicWithoutResponse(SMPCharacteristic,
        value: commandList);
  }

  Future<void> _patchSetMTU(String deviceMAC) async {
    int recdMTU = await _fble.requestMtu(deviceId: deviceMAC, mtu: 517);
    logConsole("MTU negotiated: " + recdMTU.toString());
  }

  bool dfuInProgress = false;
  double dfuProgress = 0;
  static const Duration SMPtimeout = Duration(seconds: 5);

  Future<String> pickFileFromPhone() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) {
      return "";
    }
    final resultFile = result.files.single;
    final file = File(resultFile.path!);
    return file.path;


    /*final File dfuPacketFile = File(file.path);
    final content = await dfuPacketFile.readAsBytes();
    final image = mcumgr.McuImage.decode(content);

    setState(() {
      dfuPath = resultFile.name;
      dfuLength = dfuPacketFile.lengthSync().toString();
      dfuHash = image.hash.toString();
    });

    return file.path;*/
  }

  Widget _buildDFUCard() {
    if(connectedToDevice == true){
      return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Consumer2<BleScannerState, WiserBLEProvider>(
              builder: (context, bleScanner, patchBle, child) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "Connected to " + pcCurrentDeviceName,
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Updating FW Image:  " +
                                (dfuProgress * 100).toStringAsFixed(0) +
                                " %",
                            style: TextStyle(fontSize: 16, color: Colors.black),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        LinearProgressIndicator(
                          backgroundColor: Colors.blueGrey[100],
                          //color: Colors.blue,
                          value: (dfuProgress),
                          minHeight: 25,
                          semanticsLabel: 'Receiving Data',
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: MaterialButton(
                            onPressed: () async {
                              dfuFilePath = await pickFileFromPhone();
                            },
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 16.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.upload_rounded,
                                    color: Colors.white,
                                  ),
                                  const Text(
                                    'Pick File',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            color: hPi4Global.appBarColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: MaterialButton(
                            onPressed: () async {

                              await _startSMPClient(pcCurrentDeviceID);

                              /*final File dfuPacketFile = File(dfuFilePath);

                              print("DFU ready: " +
                                  dfuPacketFile.path +
                                  " Length:" +
                                  dfuPacketFile.lengthSync().toString());

                              final content = await dfuPacketFile.readAsBytes();

                              //final images = await widget.image.getSelectedFwContent();
                              final images = content;

                              final updateManager = await mcumgr.FirmwareUpdateManagerFactory()
                                  .getUpdateManager(pcCurrentDeviceID);

                              updateManager.setup();

                              updateManager.updateStateStream!.listen(
                                    (event) {
                                  if (event == mcumgr.FirmwareUpgradeState.success) {
                                   // logger.d("Update Success");
                                    setState(() {
                                      //_showProgress = false;
                                    });
                                  } else {
                                   // logger.d("updateStateStream $event");
                                  }
                                },
                                // cleanup afterwards
                                onDone: () async => {
                                  await updateManager.kill(),
                                },
                                onError: (error) async => {
                                  //logger.e("DFU failed", error),
                                  await updateManager.kill(),
                                },
                              );

                              updateManager.progressStream.listen((event) {
                                //logger.d("${event.bytesSent} / ${event.imageSize}} bytes sent");
                              });

                              updateManager.logger.logMessageStream
                                  .listen((log) {
                               // logger.d(log.message);
                              });

                              await updateManager.update(images as List<Tuple2<int, Uint8List>>);*/

                             /* mcumgr.ImageState state =
                              await _smpClient.readImageState(SMPtimeout);
                              print("DFU Imagestate: " + state.toString());

                              final File dfuPacketFile = File(dfuFilePath);

                              print("DFU ready: " +
                                  dfuPacketFile.path +
                                  " Length:" +
                                  dfuPacketFile.lengthSync().toString());

                              final content = await dfuPacketFile.readAsBytes();
                              final image = mcumgr.McuImage.decode(content);
                              print("DFU package loaded: " +
                                  content.length.toString());

                              setState(() {
                                dfuInProgress = true;
                                dfuProgress = 0;
                              });

                              try {
                                await _smpClient.uploadImage(0, content, image.hash,
                                    const Duration(seconds: 30),
                                    onProgress: (count) {
                                      setState(() {
                                        dfuProgress =
                                        (count.toDouble() / content.length);
                                        //print("DFU Prg: " + dfuProgress.toString());
                                      });
                                    });
                              } finally {
                                setState(() {
                                  dfuInProgress = false;
                                });
                              }

                              state = await _smpClient.readImageState(SMPtimeout);
                              print("DFU Imagestate: " + state.toString());

                              if (state.images.length > 1) {
                                await _smpClient.setPendingImage(
                                    state.images[1].hash, true, SMPtimeout);
                              }

                              state = await _smpClient.readImageState(SMPtimeout);
                              print("DFU Imagestate: " + state.toString());

                              _smpClient.reset(SMPtimeout);*/
                              setState(() {
                                _showDeviceCard = false;
                              });
                            },
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 16.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.upgrade,
                                    color: Colors.white,
                                  ),
                                  const Text(
                                    ' DFU Update',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            color: Colors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }));
    }else{
      return Container();
    }

  }

  Widget _buildConnectionBlock() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              showScanResults(),
              _setDeviceDateTime(),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        iconTheme: IconThemeData(
          color: Colors.white, //change your color here
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/healthypi5.png',
                fit: BoxFit.fitWidth, height: 30),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child:  Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Text(
                  "Select device to control",
                  style: hPi4Global.HeadStyle,
                ),
              ),
              //showScanResults(),
              Container(
                height: SizeConfig.blockSizeVertical * 40,
                width: SizeConfig.blockSizeHorizontal * 97,
                child:  _buildConnectionBlock(),
              ),
              Container(
                height: SizeConfig.blockSizeVertical * 45,
                width: SizeConfig.blockSizeHorizontal * 97,
                child: _buildDFUCard(),
              ),
            ],
          ),
        )

      ),
    );
  }
}
