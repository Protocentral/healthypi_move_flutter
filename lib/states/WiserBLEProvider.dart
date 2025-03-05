import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bluetooth_enable_fork/bluetooth_enable_fork.dart';

class WiserBLEProvider extends ChangeNotifier {
  WiserBLEProvider({required FlutterReactiveBle ble}) : _ble = ble;

  final FlutterReactiveBle _ble;
  int patchBatteryLevel = 0;
  int patchRecordingStatus = 0;
  int patchRSSI = 0;

  bool patchRecordingFlag = false;
  int patchRecordingProgress = 0;
  String patchRecordingProgressString = "";
  String patchRecordingStatusString = "Not recording";
  //String patchCurrentMAC = "";
  String patchCurrentDeviceName = "";
  DateTime patchLastSeen = DateTime(1800);

  bool connectedToDevice = false;

  late QualifiedCharacteristic ECGCharacteristic;
  late QualifiedCharacteristic CommandCharacteristic;
  late QualifiedCharacteristic DataCharacteristic;
  late QualifiedCharacteristic BatteryCharacteristic;

  DeviceConnectionState currentConnState = DeviceConnectionState.disconnected;

  late StreamSubscription<ConnectionStateUpdate> _connection;

  String devConsoleStatus = "--";

  bool flagCommandSubStarted = false;
  bool flagDataSubStarted = false;

  //final _deviceConnectionController = StreamController<ConnectionStateUpdate>();

  StreamSubscription? _subscription;

  Stream<List<int>> streamECG = Stream.empty();
  Stream<List<int>> streamData = Stream.empty();
  Stream<List<int>> streamCommand = Stream.empty();

  void logConsole(String logString) {
    print("AKW - " + logString);
    //devConsoleStatus = logString;
    //notifyListeners();
  }

  Future<FlutterReactiveBle> getBLE() async {
    return _ble;
  }

  bool flagLooking = false;

  bool getLookingStatus() {
    return flagLooking;
  }

  bool getBleStatus() {
    if (_ble.status == BleStatus.poweredOff) {
      return true;
    } else {
      return false;
    }
  }

  Future waitWhile(bool test(), [Duration pollInterval = Duration.zero]) {
    var completer = new Completer();
    check() {
      if (!test()) {
        completer.complete();
      } else {
        new Timer(pollInterval, check);
      }
    }

    check();
    return completer.future;
  }

  Future<void> stopScan() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _showPermissionOffDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permissions required'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(
                  Icons.location_disabled_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                Center(
                    child: Text(
                        'Patch needs permission to use location serviceto scan for Bluetooth Devices.')),
                Center(
                    child: Text(
                        'Please allow permission when prompted. Location will NOT be used for any tracking')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Ok'),
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLocationOffDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Location Service Required'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(
                  Icons.location_disabled_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                Center(
                    child: Text(
                        'You need to turn on location services on your device to scan for Bluetooth Devices.')),
                Center(
                    child: Text(
                        'Patch cannot proceed without location enabled. Please enable and retry.')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Ok'),
              onPressed: () async {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> checkPermissions(context, bool bleStatusFlag) async {
    if (!await Permission.location.isGranted) {
      await Permission.location.request();
    }

    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
    }

    if (!await Permission.bluetoothScan.isGranted) {
      await Permission.bluetoothScan.request();
    }

    if (!await Permission.bluetoothConnect.isGranted) {
      await Permission.bluetoothConnect.request();
    }

    bool _locationServiceEnabled;
    bool _bluetoothServiceEnabled = false;
    bool _permBluetoothEnabled = false;
    bool _permLocationEnabled = false;
    //PermissionStatus _permissionGranted;
    //LocationData _locationData;

    var locationStatus = await Permission.location.status;
    if (locationStatus.isDenied) {
      print("Permission is denied.");
      _showPermissionOffDialog(context);
    } else if (locationStatus.isGranted) {
      print("Permission is already granted.");
      _permLocationEnabled = true;
    } else if (locationStatus.isPermanentlyDenied) {
      //permission is permanently denied.
      print("Permission is permanently denied");
      _showPermissionOffDialog(context);
      await Permission.bluetoothScan.request();
      //await Permission.locationAlways.request();
    } else if (locationStatus.isRestricted) {
      //permission is OS restricted.
      print("Permission is OS restricted.");
      _showPermissionOffDialog(context);
    }

    var bluetoothStatus = await Permission.bluetoothScan.status;
    if (bluetoothStatus.isDenied) {
      print("Permission is denied.");
      _showPermissionOffDialog(context);
    } else if (bluetoothStatus.isGranted) {
      print("Permission is already granted.");
      _permBluetoothEnabled = true;
    } else if (bluetoothStatus.isPermanentlyDenied) {
      //permission is permanently denied.
      print("Permission is permanently denied");
      _showPermissionOffDialog(context);
      await Permission.bluetoothScan.request();
      //await Permission.locationAlways.request();
    } else if (bluetoothStatus.isRestricted) {
      //permission is OS restricted.
      print("Permission is OS restricted.");
      _showPermissionOffDialog(context);
    }

    if (bleStatusFlag) {
      print('bluetooth is OFF');
      //_bluetoothServiceEnabled = false;
      BluetoothEnable.enableBluetooth;
    } else {
      print('bluetooth is ON');
      _bluetoothServiceEnabled = true;
    }

    _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_locationServiceEnabled) {
      //AKW: User rejected to turn on location. Display dialog
      _showLocationOffDialog(context);
      return false;
    }

    if (_permLocationEnabled == true &&
        _permBluetoothEnabled == true &&
        _locationServiceEnabled == true &&
        _bluetoothServiceEnabled == true) {
      return true;
    }

    return false;
  }

  String scanAndGetDeviceMData(String patchDeviceName) {
    logConsole("Scan initiated");
    logConsole("AKW: Looking to get MAC for dev: " + patchDeviceName);
    if (_ble.status == BleStatus.ready) {
      List<Uuid> serviceIds = [];
      _subscription?.cancel();
      flagLooking = true;
      _subscription =
          _ble.scanForDevices(withServices: serviceIds).listen((device) {
        //print("Found " + device.toString());

        if (device.name.contains(patchDeviceName.toUpperCase())) {
          logConsole("Found Patch device: " +
              device.name.toString() +
              " ID: " +
              device.id.toString());

          if (device.manufacturerData.isNotEmpty) {
            logConsole("Mfr Data:" + device.manufacturerData.toString());

            patchRecordingProgress = ((device.manufacturerData[4] |
                device.manufacturerData[5] << 8));
          }
          stopScan();
          notifyListeners();
          flagLooking = false;
        }

        Future.delayed(Duration(seconds: 5), () async {
          stopScan();
        });
      }, onError: (Object e) => logConsole('Device scan fails with error: $e'));
    }
    waitWhile(() => getLookingStatus());
    print('...............' + patchRecordingProgress.toString());
    return patchRecordingProgress.toString();
  }

  Future<bool> connect(String deviceID) async {
    bool retval = false;
    //await refreshScan();

    await Future.delayed(Duration(seconds: 4), () async {
      if (deviceID != "") {
        retval = await connectLowLevel(deviceID);
      } else {
        logConsole("Invalid MAC $deviceID . Device not found");
        retval = false;
      }
    });
    return retval;
  }

  Future<bool> connectLowLevel(String deviceID) async {
    bool retval = false;
    logConsole('Initiated connection to device: $deviceID');

    _connection = _ble
        .connectToAdvertisingDevice(
      id: deviceID,
      withServices: [],
      prescanDuration: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 5),
    )
        .listen((connectionStateUpdate) {
      currentConnState = connectionStateUpdate.connectionState;
      notifyListeners();
      logConsole("Connect device: " + connectionStateUpdate.toString());
      if (connectionStateUpdate.connectionState ==
          DeviceConnectionState.connected) {
        logConsole("Connected !");
        connectedToDevice = true;
        retval = true;
      }
      //if(connectionState.failure.code.toString();)
    }, onError: (dynamic error) {
      logConsole("Connect error: " + error.toString());
    });
    return retval;
  }

  Future<void> disconnect() async {
    //String deviceID = patchCurrentMAC;
    try {
      logConsole('Disconnecting ');
      if (connectedToDevice == true) await _connection.cancel();
    } on Exception catch (e, _) {
      logConsole("Error disconnecting from a device: $e");
    } finally {
      // Since [_connection] subscription is terminated, the "disconnected" state cannot be received and propagated
      /*_deviceConnectionController.add(
        ConnectionStateUpdate(
          deviceId: deviceID,
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );*/

    }
  }

  Future<void> writeCharacterisiticWithResponse(
      QualifiedCharacteristic characteristic, List<int> value) async {
    try {
      logConsole(
          'Write with response value : $value to ${characteristic.characteristicId}');
      await _ble.writeCharacteristicWithResponse(characteristic, value: value);
    } on Exception catch (e, s) {
      logConsole(
        'Error occured when writing ${characteristic.characteristicId} : $e',
      );
      //print(s);
      rethrow;
    }
  }

  Future<List<DiscoveredService>> discoverServices(String deviceId) async {
    try {
      logConsole('Start discovering services for: $deviceId');
      final result = await _ble.discoverServices(deviceId);
      logConsole('Discovering services finished:' + result.toString());
      return result;
    } on Exception catch (e) {
      logConsole('Error occured when discovering services: $e');
      rethrow;
    }
  }

  Future<bool> patchStartECGPreview(
      bool connectToDevice, String deviceID) async {
    bool retval = false;
    logConsole("ECG Preview initiated " + deviceID);
    if (connectToDevice == true) {
      await connect(deviceID);
    }

    await Future.delayed(Duration(seconds: 2), () async {
      if (connectedToDevice == true) {
        //logConsole("ECG Preview initiated on device: " + patchCurrentMAC);
        /*await Future.delayed(Duration(seconds: 2), () async {
          await patchSendCommand(PatchGlobal.stopFlashRecordCommand, deviceID);
        });
        */

        await patchSetMTU(deviceID);
        //await Future.delayed(Duration(seconds: 2), () async {
        //   await patchSendCommand(PatchGlobal.startECGCommand, deviceID);
        // });

        //await subscribeECGCharacteristic(deviceID);
        logConsole("ECG Preview started on: " + deviceID);
        retval = true;
      } else {
        logConsole("ECG Preview failed. Device not connected");
        retval = false;
      }
    });
    return retval;
  }

  Future<String> patchConnectGetFWVersion(
      String deviceID, bool connectToDevice) async {
    List<int> retval = [];
    logConsole("Read version initiated " + deviceID);
    if (connectToDevice == true) {
      await connect(deviceID);
    }

    await Future.delayed(Duration(seconds: 2), () async {
      if (connectedToDevice == true) {
        //logConsole("ECG Preview initiated on device: " + patchCurrentMAC);
        await Future.delayed(Duration(seconds: 2), () async {
          retval = await readDeviceFWVersionCharacteristic(deviceID);
          print("BLE: Read FW returned: " + retval.toString());
        });
      } else {
        logConsole("Read failed. Device not connected");
      }
    });
    Future.delayed(Duration(seconds: 2), () async {
      await disconnect();
    });
    return String.fromCharCodes(retval);
  }

  Future<void> patchStopECGPreview(String deviceID) async {
    logConsole("ECG Preview stopped on: " + deviceID);
    //await patchSendCommand(PatchGlobal.stopECGCommand, deviceID);
  }

  Future<void> patchFetchData(Uint8List datalength, deviceID) async {
    logConsole("Sending Fetch data command for " + datalength.toString());

    Uint8List listFetchData = new Uint8List(5);

    listFetchData[0] = 0; // PatchGlobal.fetchECG[0];
    listFetchData[1] = datalength[0];
    listFetchData[2] = datalength[1];
    listFetchData[3] = datalength[2];
    listFetchData[4] = datalength[3];

    print("AKW: Sending data fetch command:" + listFetchData.toString());
    //patchCommandCharacteristic.write(listFetchData, true);
    await patchSendCommand(listFetchData, deviceID);
  }

  Future<void> patchFetchDataFileNumber(int fileNumber, deviceID) async {
    logConsole(
        "Sending Fetch data command for file no." + fileNumber.toString());

    Uint8List listFetchData = new Uint8List(5);

    listFetchData[0] = 0;
    // PatchGlobal.fetchECG[0];
    listFetchData[1] = fileNumber;

    print("AKW: Sending data fetch command:" + listFetchData.toString());
    //patchCommandCharacteristic.write(listFetchData, true);
    await patchSendCommand(listFetchData, deviceID);
  }

  Future<void> patchResumeFetch(deviceID) async {
    print("Resuming Fetch data ");
    //await patchSendCommand(PatchGlobal.resumeFetchData, deviceID);
  }

  Future<void> patchConnect(String deviceID) async {
    logConsole("Connection initiated to : " + deviceID);

    await Future.delayed(Duration(seconds: 2), () async {
      await connect(deviceID);
    });
  }

  Future<void> patchResetWithConnect(String deviceID, context) async {
    logConsole("Initiated device reset on: " + deviceID);
    showLoadingIndicator("Connecting to the device...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      await connect(deviceID);
    });
    Navigator.pop(context);
    showLoadingIndicator("Resetting the device...", context);
    await Future.delayed(Duration(seconds: 6), () async {
      //await patchSendCommandWithoutAck(PatchGlobal.resetPatchDevice, deviceID);
    });
    Navigator.pop(context);
    await disconnect();
    _showResetSuccessDialog(context);
  }

  Future<void> patchResetOnly(String deviceID) async {
    //await patchSendCommandWithoutAck(PatchGlobal.resetPatchDevice, deviceID);
  }

  Future<void> patchEndRecording(String deviceID) async {
    logConsole("Stop recording initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      //await patchSendCommand(PatchGlobal.stopFlashRecordCommand, deviceID);
    });

    logConsole("Fetch recording initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      //await patchSendCommand(PatchGlobal.fetchECGLength, deviceID);
    });

    /*await Future.delayed(Duration(seconds: 2), () async {
      logConsole("Disconnecting");
      await disconnect();
    });
    */

    logConsole("End recording completed on " + deviceID);
  }

  Future<void> patchAbortRecording(String deviceID) async {
    await patchStopECGPreview(deviceID);
    await disconnect();
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
              //content: LoadingIndicator(text: text),
            ));
      },
    );
  }

  Future<void> _showClearedSuccessDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Cleared'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 72,
                ),
                Center(child: Text('Cache cleared successfully')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showResetSuccessDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Alert'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 72,
                ),
                Center(child: Text('Device Reset is successful')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Close'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> clearGATTCache(String deviceID, context) async {
    logConsole("Initiated clear GATT cache: " + deviceID);

    showLoadingIndicator("Connecting to the device...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      await connect(deviceID);
    });
    Navigator.pop(context);
    showLoadingIndicator("Clearing GATT Cache...", context);
    await Future.delayed(Duration(seconds: 6), () async {
      await _ble.clearGattCache(deviceID);
    });
    Navigator.pop(context);
    await disconnect();
    _showClearedSuccessDialog(context);
  }

  Future<void> patchSetMTU(String deviceMAC) async {
    int recdMTU = await _ble.requestMtu(deviceId: deviceMAC, mtu: 230);
    logConsole("MTU negotiated: " + recdMTU.toString());
  }

  Future<void> patchStartRecording(
      int recordLengthSeconds, bool connectToDevice, String deviceID) async {
    logConsole("Start recording initiated on: " + deviceID);

    if (connectToDevice == true) {
      //await refreshScan();
      await connect(deviceID);
    }

    await patchStopECGPreview(deviceID);
    //await patchSendCommand(PatchGlobal.formatPatchDevice, deviceID);

    logConsole("Format complete !");

    List<int> startFlashRecordingCommand = [];
    //startFlashRecordingCommand.addAll(PatchGlobal.startFlashRecordCommand);

    ByteData recordLength = new ByteData(4);
    recordLength.setUint32(0, recordLengthSeconds, Endian.little);

    Uint8List recordLengthBytes = recordLength.buffer.asUint8List(0, 4);

    logConsole("AKW: Starting recording for duration: " +
        recordLengthSeconds.toString() +
        " " +
        recordLengthBytes.toString());

    startFlashRecordingCommand.addAll(recordLengthBytes);

    Future.delayed(Duration(seconds: 3), () async {
      await patchSendCommand(startFlashRecordingCommand, deviceID);
      Future.delayed(Duration(seconds: 2), () async {
        await disconnect();
      });
    });

    //print("Start Recording Sent");
  }

  Future<List<int>> readDeviceFWVersionCharacteristic(String deviceID) async {
    QualifiedCharacteristic deviceFWCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_DIS_FW_REVISION),
        serviceId: Uuid.parse(hPi4Global.UUID_SERV_DIS),
        deviceId: deviceID);

    logConsole('Reading from: ${deviceFWCharacteristic.characteristicId} ');

    final List<int> readResponse =
        await _ble.readCharacteristic(deviceFWCharacteristic);
    logConsole('Read from: ${deviceFWCharacteristic.characteristicId} ' +
        readResponse.toString());
    return readResponse;
  }

  Future<void> patchSendCommand(List<int> commandList, String deviceID) async {
    /*CommandCharacteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(WiserGlobal.UUID_SERV_CMD_DATA),
        characteristicId: Uuid.parse(PatchGlobal.UUID_CHAR_CMD),
        deviceId: deviceID);
    logConsole(
        "Tx CMD " + commandList.toString() + " 0x" + hex.encode(commandList));

    await _ble.writeCharacteristicWithoutResponse(CommandCharacteristic,
        value: commandList);
        */
  }

  Future<void> patchSendCommandWithoutAck(
      List<int> commandList, String deviceID) async {
    /*CommandCharacteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(PatchGlobal.UUID_SERV_CMD_DATA),
        characteristicId: Uuid.parse(PatchGlobal.UUID_CHAR_CMD),
        deviceId: deviceID);
    logConsole("Tx CMD without ACK" +
        commandList.toString() +
        " 0x" +
        hex.encode(commandList));

    await _ble.writeCharacteristicWithoutResponse(CommandCharacteristic,
        value: commandList);
        */
  }

  /*Stream<List<int>> subscribeECGCharacteristic(String deviceID) {
    ECGCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(PatchGlobal.UUID_CHAR_ECG),
        serviceId: Uuid.parse(PatchGlobal.UUID_SERV_ECG),
        deviceId: deviceID);
    logConsole('Subscribing to: ${ECGCharacteristic.characteristicId} ');
    return _ble.subscribeToCharacteristic(ECGCharacteristic);
    
  }

  Stream<List<int>> subscribeDataCharacteristic(String deviceID) {
    DataCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(PatchGlobal.UUID_CHAR_DATA),
        serviceId: Uuid.parse(PatchGlobal.UUID_SERV_CMD_DATA),
        deviceId: deviceID);
    logConsole('Subscribing to: ${DataCharacteristic.characteristicId} ');
    return _ble.subscribeToCharacteristic(DataCharacteristic);
  }

  Stream<List<int>> subscribeCommandCharacteristic(String deviceID) {
    CommandCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(PatchGlobal.UUID_CHAR_CMD),
        serviceId: Uuid.parse(PatchGlobal.UUID_SERV_CMD_DATA),
        deviceId: deviceID);
    logConsole('Subscribing to: ${CommandCharacteristic.characteristicId} ');
    return _ble.subscribeToCharacteristic(CommandCharacteristic);
  }
  */

  Stream<List<int>> subscribeBatteryCharacteristic(String deviceID) {
    BatteryCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_BATT),
        serviceId: Uuid.parse(hPi4Global.UUID_SERV_BATT),
        deviceId: deviceID);
    logConsole('Subscribing to: ${BatteryCharacteristic.characteristicId} ');
    return _ble.subscribeToCharacteristic(BatteryCharacteristic);
    //notifyListeners();
  }
}
