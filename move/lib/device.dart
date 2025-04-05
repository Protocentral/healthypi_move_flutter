import 'dart:convert';
//import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:async';
//import 'dart:nativewrappers/_internal/vm/lib/ffi_native_type_patch.dart';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

typedef LogHeader = ({int logFileID, int sessionLength});

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
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  String selectedOption = "sync";

  int totalSessionCount = 0;
  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int globalTotalFiles = 0;
  int currentFileNumber = 0;
  int currentFileDataCounter = 0;
  int _globalReceivedData = 0;
  int _globalExpectedLength = 1;
  int tappedIndex = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late StreamSubscription<List<int>> _streamDataSubscription;

  @override
  void initState() {
    super.initState();

    if (_isScanning == false) {
      FlutterBluePlus.startScan(
        withNames: ['healthypi move'],
        timeout: const Duration(seconds: 15),
      );
    }
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        _scanResults = results;
      },
      onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
    });
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

  @override
  Future<void> dispose() async {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _connectionStateSubscription.cancel();
    onStopPressed();
    super.dispose();
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

    ByteData sessionParametersLength = new ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);

    logConsole("Sending DateTime information: " + cmdByteList.toString());

    commandDateTimePacket.addAll(cmdByteList);

    logConsole("Sending DateTime Command: " + commandDateTimePacket.toString());

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

    await deviceName.disconnect();
  }

  Future onScanPressed() async {
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
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

      if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "sync") {
        //await device.disconnect();
        /*Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomePage()));*/
        await subscribeToChar(device);
        Future.delayed(Duration(seconds: 2), () async {
          await _fetchLogCount(context, device);
        });
        Future.delayed(Duration(seconds: 3), () async {
          await _fetchLogIndex(context, device);
        });
      } else if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "fetchLogs") {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (_) => FetchFileData(
                  connectionState: _connectionState,
                  connectedDevice: device,
                ),
          ),
        );
      } else if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "setTime") {
        _sendCurrentDateTime(device);
      } else if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "readDevice") {
      } else if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "eraseAll") {
      } else {
        //device.disconnect();
      }
    });
  }

  Future<void> _writeLogDataToFile(
    List<int> mData,
    int sessionID,
    String formattedTime,
  ) async {
    logConsole("Log data size: " + mData.length.toString());

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    int logNumberPoints = ((mData.length - 1) ~/ 16);

    //List<String> data1 = ['1', 'Bilal Saeed', '1374934', '912839812'];
    List<List<String>> dataList = []; //Outter List which contains the data List

    List<String> header = [];

    header.add("Timestamp");
    header.add("Min");
    header.add("Max");
    header.add("avg");
    header.add("latest");
    dataList.add(header);

    for (int i = 0; i < logNumberPoints; i++) {
      List<String> dataRow = [
        bdata.getUint64((i * 16), Endian.little).toString(),
        bdata.getInt16((i * 16) + 8, Endian.little).toString(),
        bdata.getInt16((i * 16) + 10, Endian.little).toString(),
        bdata.getInt16((i * 16) + 12, Endian.little).toString(),
        bdata.getInt16((i * 16) + 14, Endian.little).toString(),
      ];
      dataList.add(dataRow);
    }

    // Code to convert logData to CSV file

    String csv = const ListToCsvConverter().convert(dataList);

    Directory _directory = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      _directory = Directory("/storage/emulated/0/Download");
    } else {
      _directory = await getApplicationDocumentsDirectory();
    }
    final exPath = _directory.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;

    File file = File('$directory/hr_$sessionID.csv');
    ;
    print("Save file");

    await file.writeAsString(csv);

    logConsole("File exported successfully!");

    //await _showDownloadSuccessDialog();
  }

  bool logIndexReceived = false;
  bool isTransfering = false;
  bool isFetchIconTap = false;
  List<LogHeader> logHeaderList = List.empty(growable: true);

  Future<void> listenForIndex(
    BluetoothDevice deviceName,
    int expectedLength,
    String sessionID,
    String formattedTime,
  ) async {
    logConsole("Started listening for index....");

    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen(
      (value) async {},
    );
  }

  Future<void> _startListeningData(
    BluetoothDevice deviceName,
    int expectedLength,
    int sessionID,
    String formattedTime,
  ) async {
    List<int> buffer = [];
    String fileName = "";

    logConsole("Started listening....");
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      logConsole("Data Rx: $value");
      //logConsole("Data Rx in hex: " +  hex.encode(value).toString());
      int pktType = bdata.getUint8(0);

      /**** Packet type Command Response ***/
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        setState(() {
          totalSessionCount = bdata.getUint16(2, Endian.little);
        });
        logConsole("Data Rx count: $totalSessionCount");

        await _streamDataSubscription.cancel();
      }
      /*****  Packet type Log Index ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        logConsole("Data Rx Index len: ${value.length}");

        logConsole(
          "Data Index session start: ${bdata.getInt64(1, Endian.little)}",
        );

        buffer.addAll(value);

        /*if (buffer.length >= 21) {
          try {
            int fileLength = ByteData.sublistView(Uint8List.fromList(buffer))
                .getUint32(17, Endian.little);
            logConsole("fileLength... " + fileLength.toString());

            //List<int> fileNameBytes = buffer. .sublist(1, 16); // Example: extract the first 16 bytes for fileName
            //fileName = String.fromCharCodes(fileNameBytes); // Decode as UTF-8 string
            //logConsole("fileName... " + fileName);
          } catch (e) {
            logConsole("Error processing the packet: $e");
          }

          // After processing, clear the buffer if needed
          buffer.clear();
        }*/

        int logFileID = bdata.getInt64(1, Endian.little);
         int sessionLength = bdata.getInt16(9, Endian.little);
        logConsole("Log file ID: $logFileID | Length: $sessionLength");

        LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

        logHeaderList.add(mLog);

        if (logHeaderList.length == totalSessionCount) {
          setState(() {
            logIndexReceived = true;
          });

          logConsole("All logs received. Cancel subscription");
          logConsole("All logs Header.......$logHeaderList");

          for (int i = 0; i <= logHeaderList.length; i++) {
            Future.delayed(Duration(seconds: 2), () async {
              /*_fetchLogFile(
                deviceName,
                logHeaderList[i].logFileID,
                logHeaderList[i].sessionLength,
                "",
              );*/
            });
          }

          await _streamDataSubscription.cancel();
        }
      }
      /***** Packet type Log Data ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
        int pktPayloadSize = value.length - 1; //((value[1] << 8) + value[2]);

        logConsole(
          "Data Rx length: ${value.length} | Actual Payload: $pktPayloadSize",
        );
        currentFileDataCounter += pktPayloadSize;
        _globalReceivedData += pktPayloadSize;
        logData.addAll(value.sublist(1, value.length));

        setState(() {
          displayPercent =
              globalDisplayPercentOffset +
              (_globalReceivedData / _globalExpectedLength) * 100.truncate();
          if (displayPercent > 100) {
            displayPercent = 100;
          }
        });

        logConsole(
          "File data counter: $currentFileDataCounter | Received: $displayPercent%",
        );

        if (currentFileDataCounter >= (expectedLength)) {
          logConsole("All data $currentFileDataCounter received");

          if (currentFileDataCounter > expectedLength) {
            int diffData = currentFileDataCounter - expectedLength;
            logConsole("Data received more than expected by: $diffData bytes");
          }

          //await _writeLogDataToFile(logData, sessionID, formattedTime);

          //Navigator.pop(context);

          setState(() {
            isTransfering = false;
            isFetchIconTap = false;
          });

          // Reset all fetch variables
          displayPercent = 0;
          globalDisplayPercentOffset = 0;
          currentFileDataCounter = 0;
          _globalReceivedData = 0;
          logData.clear();
        }
      }
    });

    // cleanup: cancel subscription when disconnected
    deviceName.cancelWhenDisconnected(_streamDataSubscription);
  }

  Future<void> _fetchLogCount(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Fetch log count initiated");
    //showLoadingIndicator("Fetching logs count...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.HrTrend);

      await _sendCommand(commandPacket, deviceName);
    });
    //Navigator.pop(context);
  }

  Future<void> _fetchLogIndex(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Fetch log index initiated");
    //showLoadingIndicator("Fetching logs...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.HrTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    //Navigator.pop(context);
  }

  Future<void> _fetchLogFile(
    BluetoothDevice deviceName,
    int sessionID,
    int sessionSize,
    String formattedTime,
  ) async {
    logConsole(
      "Fetch logs file initiated for session: $sessionID, size: $sessionSize",
    );
    isTransfering = true;
    //await _startListeningCommand(deviceID);
    // Session size is in bytes, so multiply by 6 to get the number of data points, add header size
    await _startListeningData(deviceName, ((sessionSize * 6)), sessionID, "0");

    // Reset all fetch variables
    currentFileDataCounter = 0;
    //currentFileReceivedComplete = false;

    _globalExpectedLength = sessionSize;
    //logData.clear();

    await Future.delayed(Duration(seconds: 2), () async {
      //List<int> uint8Data = utf8.encode(sessionID);
      //print(uint8Data);

      /*ByteData sessionIDLength = new ByteData(16);

      sessionIDLength.setUint8(0, uint8Data[0]);
      sessionIDLength.setUint8(1, uint8Data[1]);
      sessionIDLength.setUint8(2, uint8Data[2]);
      sessionIDLength.setUint8(3, uint8Data[3]);
      sessionIDLength.setUint8(4, uint8Data[4]);
      sessionIDLength.setUint8(5, uint8Data[5]);
      sessionIDLength.setUint8(6, uint8Data[6]);
      sessionIDLength.setUint8(7, uint8Data[7]);
      sessionIDLength.setUint8(8, uint8Data[8]);
      sessionIDLength.setUint8(9, uint8Data[9]);
      sessionIDLength.setUint8(10, uint8Data[10]);
      sessionIDLength.setUint8(11, uint8Data[11]);
      sessionIDLength.setUint8(12, uint8Data[12]);
      sessionIDLength.setUint8(13, uint8Data[13]);
      sessionIDLength.setUint8(14, uint8Data[14]);
      sessionIDLength.setUint8(15, uint8Data[15]);

      Uint8List cmdByteList = sessionIDLength.buffer.asUint8List(0, 15);

      logConsole("Sending file name: $cmdByteList");

      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(cmdByteList);
      */
      //await _sendCommand(commandFetchLogFile, deviceName);
    });
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
        onScanPressed();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'SCAN',
              style: new TextStyle(fontSize: 16, color: Colors.white),
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
                            SizedBox(height: 20),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Text(
                                                'Device Management',
                                                style:
                                                    hPi4Global
                                                        .movecardTextStyle,
                                              ),
                                              //Icon(Icons.favorite_border, color: Colors.black),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
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
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (context) =>
                                                          DeviceManagement(),
                                                ),
                                              );
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
                                                  Icon(
                                                    Icons.system_update,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Update Firmware ',
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
                                          SizedBox(height: 10.0),
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
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                selectedOption = "readDevice";
                                              });
                                              //showScanDialog();
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
                                                    Icons.system_update,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Read Device ',
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
                                          SizedBox(height: 10.0),
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
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                selectedOption = "sync";
                                              });
                                              showScanDialog();
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
                                                    Icons.sync,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Sync ',
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
                                          SizedBox(height: 10.0),
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
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                selectedOption = "fetchLogs";
                                              });
                                              showScanDialog();
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
                                                    Icons.sync,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Fetch Logs ',
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
                                          SizedBox(height: 10.0),
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
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                selectedOption = "setTime";
                                              });
                                              showScanDialog();
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
                                                    Icons.sync,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Set Time ',
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
                                          SizedBox(height: 10.0),
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
                                Container(
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
