import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  int checkNoOfWrites = 0;

  int noOfFiles = 0;

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
    /*if (Platform.isAndroid) {
      requestPermissions();
    }*/
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


  @override
  Future<void> dispose() async {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _connectionStateSubscription.cancel();
    onStopPressed();
    super.dispose();
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

  Future<void> _sendCurrentDateTime(BluetoothDevice deviceName, String selectedOption) async {
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

    if(selectedOption == "Set Time"){
      await deviceName.disconnect();
    }else{
      /// Do Nothing;
    }


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

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.manageExternalStorage,
      Permission.storage,
    ].request();

    if (statuses.containsValue(PermissionStatus.denied)) {
      print("permission denied");
    }else{
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
        showLoadingIndicator("Connected. Syncing the data...", context);
        await subscribeToChar(device);
        _sendCurrentDateTime(device, "Sync");
        Navigator.pop(context);
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
        _sendCurrentDateTime(device, "Set Time");
      } else if (_connectionState == BluetoothConnectionState.connected &&
          selectedOption == "readDevice") {
      } else if (_connectionState == BluetoothConnectionState.connected && selectedOption == "eraseAll") {
        _eraseAllLogs(context, device);
      } else {
        //device.disconnect();
      }
    });
  }

  static const int FILE_HEADER_LEN = 8;

// Function for converting little-endian bytes to integer
  int convertLittleEndianToInteger(List<int> bytes) {
    List<int> reversedBytes = bytes.reversed.toList();
    return reversedBytes.fold(0, (result, byte) => (result << 8) | byte);
  }

  Future<void> _writeLogDataToFile(
    List<int> mData,
    int sessionID,
    String formattedTime,
  ) async {
    logConsole("Log data size: " + mData.length.toString());

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    //logConsole("writing to file - hex: " +  hex.encode(mData));

    int logNumberPoints = ((mData.length-1) ~/ 16);

    //logConsole("log no of point: " +  logNumberPoints.toString());

    List<List<String>> dataList = []; //Outter List which contains the data List

    List<String> header = [];

    header.add("Timestamp");
    header.add("Max");
    header.add("Min");
    header.add("avg");
    header.add("latest");
    dataList.add(header);

    for (int i = 0; i < logNumberPoints; i++) {
      // Extracting 16 bytes of data for the current row
      List<int> bytes = bdata.buffer.asUint8List(i * 16, 16);

      // Convert the first 8 bytes (timestamp) from little-endian to integer
      int timestamp = convertLittleEndianToInteger(bytes.sublist(0, 8));

      // Extract other data values (2 bytes each) and convert them
      int value1 = convertLittleEndianToInteger(bytes.sublist(8, 10));
      int value2 = convertLittleEndianToInteger(bytes.sublist(10, 12));
      int value3 = convertLittleEndianToInteger(bytes.sublist(12, 14));
      int value4 = convertLittleEndianToInteger(bytes.sublist(14, 16));

      // Construct the row data
      List<String> dataRow = [
        timestamp.toString(),
        value1.toString(),
        value2.toString(),
        value3.toString(),
        value4.toString(),
      ];
      dataList.add(dataRow);
    }

    // Code to convert logData to CSV file

    String csv = const ListToCsvConverter().convert(dataList);

    Directory _directory = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      //_directory = Directory("/storage/emulated/0/Download");
      _directory = await getApplicationDocumentsDirectory();
    } else {
      _directory = await getApplicationDocumentsDirectory();
    }

    final exPath = _directory.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;

    File file = File('$directory/hr_$sessionID.csv');
    print("Save file");

    await file.writeAsString(csv);

    logConsole("File exported successfully!");

   // await _showDownloadSuccessDialog();
  }

  bool logIndexReceived = false;
  bool isTransfering = false;
  bool isFetchIconTap = false;
  List<LogHeader> logHeaderList = List.empty(growable: true);

  int currentFileIndex = 0; // Track the current file being fetched

  Future<void> _startListeningData(
      BluetoothDevice deviceName,
      int expectedLength,
      int sessionID,
      String formattedTime,
      ) async {

    logConsole("Started listening....");
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
        value,
        ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      //logConsole("Data Rx: $value");
      logConsole("Data Rx in hex: " +  hex.encode(value).toString());
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

        int logFileID = bdata.getInt64(1, Endian.little);
        int sessionLength = bdata.getInt16(9, Endian.little);
        logConsole("Log file ID: $logFileID | Length: $sessionLength");

        LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

        setState(() {
          logHeaderList.add(mLog);
        });

        if (logHeaderList.length == totalSessionCount) {
          setState(() {
            logIndexReceived = true;
          });

          logConsole("All logs Header.......$logHeaderList");

          _fetchNextLogFile(deviceName);
          //await _streamDataSubscription.cancel();
        }
      }
      /***** Packet type Log Data ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
        int pktPayloadSize = value.length - 1; //((value[1] << 8) + value[2]);

        logConsole("Data Rx length: ${value.length} | Actual Payload: $pktPayloadSize",
        );
        currentFileDataCounter += pktPayloadSize;
        _globalReceivedData += pktPayloadSize;
        checkNoOfWrites += 1;

        logConsole("No of writes $checkNoOfWrites");
        logConsole("Data Counter $currentFileDataCounter");
        logConsole(logHeaderList[currentFileIndex].sessionLength.toString());

        logData.addAll(value.sublist(1, value.length));

        if (currentFileDataCounter >= logHeaderList[currentFileIndex].sessionLength-1) {
          logConsole("All data $currentFileDataCounter received");

          await _writeLogDataToFile(logData, logHeaderList[currentFileIndex].logFileID, formattedTime);

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
          checkNoOfWrites = 0;
          logData.clear();

          // Move to the next file
          if (currentFileIndex + 1 < logHeaderList.length) {
            currentFileIndex++; // Increment safely
            // Fetch the next log file
            _fetchNextLogFile(deviceName);
          } else {
            logConsole("All HR files have been fetched. Starting SpO2 file fetching...");
            /*Future.delayed(Duration(seconds: 2), () async {
              await _fetchSpo2LogCount(context, deviceName);
            });
            Future.delayed(Duration(seconds: 2), () async {
              await _fetchSpo2LogIndex(context, deviceName);
            });*/
          }

        }else{
          logConsole("Invalid index or condition not met: currentFileIndex=$currentFileIndex");
        }

      }
    });

    // cleanup: cancel subscription when disconnected

    deviceName.cancelWhenDisconnected(_streamDataSubscription);
  }


  Future<void> _fetchNextLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentFileIndex < logHeaderList.length) {
      int logFileID = logHeaderList[currentFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's file detected with ID $logFileID. Always downloading...");
        await _fetchLogFile(deviceName, logFileID, logHeaderList[currentFileIndex].sessionLength, "");
      } else {
        bool fileExists = await _doesFileExist(logFileID);

        if (fileExists) {
          logConsole("File with ID $logFileID already exists. Skipping...");
        } else {
          logConsole("Fetching file with ID $logFileID...");
          await _fetchLogFile(deviceName, logFileID, logHeaderList[currentFileIndex].sessionLength, "");
          break; // Exit the loop to fetch the current file
        }
      }

      currentFileIndex++;// Increment after processing
    }

    if (currentFileIndex == logHeaderList.length) {
      logConsole("All files have been processed.");
      currentFileIndex--;
    }
  }

  Future<bool> _doesFileExist(int logFileID) async {
    // Construct the file path
    String filePath = await _getLogFilePath(logFileID);

    // Check if the file exists
    return await File(filePath).exists();
  }

  Future<String> _getLogFilePath(int logFileID) async {
    // Define the file path logic here
    String directoryPath;
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      //_directory = Directory("/storage/emulated/0/Download");
       //directoryPath = (await Directory("/storage/emulated/0/Download")).path;
       directoryPath = (await getApplicationDocumentsDirectory()).path;
      //_directory = await getApplicationDocumentsDirectory();
    } else {
     // _directory = await getApplicationDocumentsDirectory();
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    }
    return "$directoryPath/hr_$logFileID.csv";
  }

  Future<void> _fetchLogCount(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Fetch log count initiated");
    showLoadingIndicator("Fetching logs count...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.HrTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchSpo2LogCount(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch spo2 log count initiated");
    showLoadingIndicator("Fetching spo2 logs count...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.Spo2Trend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchSpo2LogIndex(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch spo2 log index initiated");
    showLoadingIndicator("Fetching spo2 logs index...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.Spo2Trend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }



  Future<void> _fetchLogIndex(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Fetch log index initiated");
    showLoadingIndicator("Fetching logs index...", context);
    //await _startListeningCommand(deviceID);
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.HrTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
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
    showLoadingIndicator("Fetching file $sessionID...", context);
    //await _startListeningCommand(deviceID);
    // Session size is in bytes, so multiply by 6 to get the number of data points, add header size
    //await _startListeningData(deviceName, ((sessionSize * 6)), sessionID, "0");

    // Reset all fetch variables
    currentFileDataCounter = 0;
    //currentFileReceivedComplete = false;

    _globalExpectedLength = sessionSize;
    //logData.clear();

    await Future.delayed(Duration(seconds: 2), () async {
      logConsole("Fetch logs file entered: $sessionID, size: $sessionSize",);
      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(hPi4Global.HrTrend);
      for (int shift = 0; shift <= 56; shift += 8) {
        commandFetchLogFile.add((sessionID >> shift) & 0xFF);
      }
      await _sendCommand(commandFetchLogFile, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _eraseAllLogs(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Erase All initiated");
    //showLoadingIndicator("Erasing logs...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogWipeAll);
      await _sendCommand(commandPacket, deviceName);
    });
    //Navigator.pop(context);
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

  Future<void> _showDownloadSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Downloaded'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Icon(Icons.check_circle, color: Colors.green, size: 72),
                Center(
                  child: Text(
                    'File downloaded successfully!.',
                  ),
                ),
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
                                          /*ElevatedButton(
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
                                          SizedBox(height: 10.0),*/
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
                                         /* SizedBox(height: 10.0),
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
                                          SizedBox(height: 10.0),*/
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
                                                selectedOption = "eraseAll";
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
                                                    Icons.delete,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Erase Logs ',
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
                                          /*SizedBox(height: 10.0),
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
                                          ),*/
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
