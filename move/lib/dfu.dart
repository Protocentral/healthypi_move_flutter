import 'dart:io';
import 'dart:async';

import 'dart:typed_data';
import 'dart:ui';

import 'package:move/utils/snackbar.dart';
import 'package:move/widgets/scan_result_tile.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'sizeConfig.dart';
import 'package:intl/intl.dart';

import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
//import 'package:mcumgr_flutter/mcumgr_flutter.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/src/bloc/bloc/update_bloc.dart';
import '/src/model/firmware_update_request.dart';
import '/src/providers/firmware_update_request_provider.dart';
import '/src/view/stepper_view/firmware_select.dart';
import '/src/view/stepper_view/peripheral_select.dart';
import '/src/view/stepper_view/update_view.dart';
import 'package:provider/provider.dart';

//late QualifiedCharacteristic commandCharacteristic;
//late QualifiedCharacteristic DataCharacteristic;
//late StreamSubscription<ConnectionStateUpdate> _connection;

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

  List<ScanResult> _scanResults = [];

  String dfuFilePath = "";

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
  void initState(){
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


  /*Future<void> connectToDevice(
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
  }*/

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

  /*Future<void> _setMTU(String deviceMAC) async {
    int recdMTU = await _fble.requestMtu(deviceId: deviceMAC, mtu: 128);
    logConsole("MTU negotiated: " + recdMTU.toString());
    Navigator.pop(context);
  }*/

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

Future onScanPressed() async {
  /*try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      //var withServices = [Guid("180f")]; // Battery Level Service
      _systemDevices = await FlutterBluePlus.systemDevices();//withServices);
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("System Devices Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }*/
  try {
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      /*webOptionalServices: [
          Guid("180f"), // battery
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


Widget buildScanButton(BuildContext context) {
  return MaterialButton(
    child: const Text("SCAN"),
    onPressed: onScanPressed,
    color: Colors.green,
  );
}

List<Widget> _buildScanResultTiles(BuildContext context) {
  return _scanResults
      .map(
        (r) => ScanResultTile(
      result: r,
      //onTap: () => onConnectPressed(r.device),
    ),
  ).toList();
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
   /* await _fble.writeCharacteristicWithoutResponse(commandCharacteristic,
        value: commandDateTimePacket);*/
    print("DateTime Sent");
  }


  Future<void> _disconnect() async {
    //String deviceID = patchCurrentMAC;
    try {
      logConsole('Disconnecting ');
      if (connectedToDevice == true) {
        showLoadingIndicator("Disconnecting....", context);
        await Future.delayed(Duration(seconds: 3), () async {
         /// await _connection.cancel();
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

  //late QualifiedCharacteristic SMPCharacteristic;

  /*Future<void> _startSMPClient(String deviceID) async {
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
  }*/

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

  Widget _buildDFUCard(BuildContext context) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    return Stepper(
      currentStep: provider.currentStep,
      onStepContinue: () {
        setState(() {
          provider.nextStep();
        });
      },
      onStepCancel: () {
        setState(() {
          provider.previousStep();
        });
      },
      controlsBuilder: _controlBuilder,
      steps: [
        Step(
          title: Text('Select Firmware',style: hPi4Global.subValueWhiteTextStyle,),
          content: Center(child: FirmwareSelect()),
          isActive: provider.currentStep == 0,
        ),
        Step(
          title: Text('Select Device',style: hPi4Global.subValueWhiteTextStyle,),
          content: Center(child: PeripheralSelect()),
          isActive: provider.currentStep == 1,
        ),
        Step(
          title: Text('Update',style: hPi4Global.subValueWhiteTextStyle,),
          content: Text('Update'),
          isActive: provider.currentStep == 2,
        ),
      ],
    );

  }

  Widget _controlBuilder(BuildContext context, ControlsDetails details) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    FirmwareUpdateRequest parameters = provider.updateParameters;
    switch (provider.currentStep) {
      case 0:
        if (parameters.firmware == null) {
          return Container();
        }
        return Row(
          children: [
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
      case 1:
        if (parameters.peripheral == null) {
          return Container();
        }
        return Row(
          children: [
            TextButton(
              onPressed: details.onStepCancel,
              child: Text('Back'),
            ),
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
      case 2:
        return BlocProvider(
          create: (context) => UpdateBloc(firmwareUpdateRequest: parameters),
          child: UpdateStepView(),
        );
      default:
        throw Exception('Unknown step');
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
            Image.asset('assets/healthypi_move.png',
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
                  style: hPi4Global.cardTextStyle,
                ),
              ),
              Container(
                height: SizeConfig.blockSizeVertical * 45,
                width: SizeConfig.blockSizeHorizontal * 97,
                child: _buildDFUCard(context),
              ),
            ],
          ),
        )

      ),
    );
  }
}
