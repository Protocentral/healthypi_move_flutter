import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/sizeConfig.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../globals.dart';
import '../home.dart';

typedef LogHeader = ({int logFileID, int sessionLength});

class SyncingScreen extends StatefulWidget {
  final BluetoothDevice device;

  const SyncingScreen({super.key, required this.device});

  @override
  State<SyncingScreen> createState() => _SyncingScreenState();
}

class _SyncingScreenState extends State<SyncingScreen> {
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late StreamSubscription<List<int>> _streamDataSubscription;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int currentFileDataCounter = 0;
  int totalFileDataCounter = 0;
  int checkNoOfWrites = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((
        state,
        ) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        startFetching();
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((
        value,
        ) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  void logConsole(String logString) async {
    print("AKW - $logString");
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
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

  // Save a value
  _saveValue() async {
    DateTime now = DateTime.now();
    String lastDateTime = DateFormat('EEE d MMM h:mm a').format(now);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSynced', lastDateTime);
  }

  // Save fetch complete status value
  saveFetchCompleteStatus() async {

  }

  Future<void> _sendCurrentDateTime(
      BluetoothDevice deviceName,
      String selectedOption,
      ) async {
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
    // logConsole("Sending DateTime information: $cmdByteList");
    commandDateTimePacket.addAll(cmdByteList);
    //logConsole("Sending DateTime Command: $commandDateTimePacket");
    await _sendCommand(commandDateTimePacket, deviceName);

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
    }
  }

  void startFetching() async{
    await subscribeToChar(widget.device);
    _sendCurrentDateTime(widget.device, "Sync");
    _saveValue();
    await _startListeningData(widget.device, 0, 0, "0");
    setState(() {
      isFetchingHR = true;
      isFetchingSpo2 = false;
      isFetchingTemp = false;
      isFetchingActivity = false;
    });
    Future.delayed(Duration(seconds: 2), () async {
      await _fetchLogCount(context, widget.device, hPi4Global.HrTrend);
    });
    Future.delayed(Duration(seconds: 3), () async {
      await _fetchLogIndex(context, widget.device, hPi4Global.HrTrend);
    });
  }

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
    // logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    //logConsole("writing to file - hex: " +  hex.encode(mData));

    int logNumberPoints = ((mData.length - 1) ~/ 16);

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

    Directory directory0 = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      //_directory = Directory("/storage/emulated/0/Download");
      directory0 = await getApplicationDocumentsDirectory();
    } else {
      directory0 = await getApplicationDocumentsDirectory();
    }

    final exPath = directory0.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;
    File file;
    if (isFetchingTemp) {
      file = File('$directory/temp_$sessionID.csv');
      print("Save file");
    } else {
      file = File('$directory/hr_$sessionID.csv');
      print("Save file");
    }

    await file.writeAsString(csv);

    logConsole("File exported successfully!");
  }

  Future<void> _writeSpo2LogDataToFile(
      List<int> mData,
      int sessionID,
      String headerName,
      ) async {
    // logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    int logNumberPoints = ((mData.length) ~/ 16);

    List<List<String>> dataList = []; //Outter List which contains the data List
    List<String> header = [];

    header.add("Timestamp");
    header.add(headerName);
    dataList.add(header);

    for (int i = 0; i < logNumberPoints; i++) {
      // Extracting 16 bytes of data for the current row
      List<int> bytes = bdata.buffer.asUint8List(i * 16, 16);

      // Convert the first 8 bytes (timestamp) from little-endian to integer
      int timestamp = convertLittleEndianToInteger(bytes.sublist(0, 8));

      // Extract other data values (2 bytes each) and convert them
      int value1 = convertLittleEndianToInteger(bytes.sublist(8, 10));

      // Construct the row data
      List<String> dataRow = [timestamp.toString(), value1.toString()];
      dataList.add(dataRow);
    }

    // Code to convert logData to CSV file

    String csv = const ListToCsvConverter().convert(dataList);

    Directory directory0 = Directory("");
    if (Platform.isAndroid) {
      directory0 = await getApplicationDocumentsDirectory();
    } else {
      directory0 = await getApplicationDocumentsDirectory();
    }

    final exPath = directory0.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;
    File file;

    if (isFetchingSpo2) {
      file = File('$directory/spo2_$sessionID.csv');
      print("Save file");
    } else {
      file = File('$directory/activity_$sessionID.csv');
      print("Save file");
    }

    await file.writeAsString(csv);

    logConsole("File exported successfully!");

  }

  double hrProgressPercent = 0.0; // 0.0 to 1.0
  double tempProgressPercent = 0.0; // 0.0 to 1.0
  double spo2ProgressPercent = 0.0; // 0.0 to 1.0
  double activityProgressPercent = 0.0; // 0.0 to 1.0

  bool isFetchingHR = false;
  bool isFetchingTemp = false;
  bool isFetchingSpo2 = false;
  bool isFetchingActivity = false;

  bool isFetchingHRComplete = false;
  bool isFetchingTempComplete = false;
  bool isFetchingSpo2Complete = false;
  bool isFetchingActivityComplete = false;

  bool isFetchingTodayHR = false;
  bool isFetchingTodayTemp= false;
  bool isFetchingTodaySpo2 = false;
  bool isFetchingTodayActivity = false;


  List<LogHeader> logHeaderList = List.empty(growable: true);
  List<LogHeader> logTempHeaderList = List.empty(growable: true);
  List<LogHeader> logSpo2HeaderList = List.empty(growable: true);
  List<LogHeader> logActivityHeaderList = List.empty(growable: true);

  int hrSessionCount = 0;
  int tempSessionCount = 0;
  int spo2SessionCount = 0;
  int activitySessionCount = 0;

  int currentFileIndex = 0; // Track the current file being fetched
  int currentTempFileIndex = 0; // Track the current Temp file being fetched
  int currentSpo2FileIndex = 0; // Track the current SpO2 file being fetched
  int currentActivityFileIndex =
  0; // Track the current Activity file being fetched

  Future<void> _startListeningData(
      BluetoothDevice deviceName,
      int expectedLength,
      int sessionID,
      String formattedTime,
      ) async {
    logConsole("Started listening....");

    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((value) async {
      //logConsole("Data Rx: $value");
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);

      /*** 1. Handle Command Response (session counts) ***/
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        int trendCode = bdata.getUint8(2);
        int sessionCount = bdata.getUint16(3, Endian.little);

        setState(() {
          switch (trendCode) {
            case 01: // HR
              hrSessionCount = sessionCount;
              if (hrSessionCount == 0) {
                isFetchingHRComplete = true;
                isFetchingHR = false;
                isFetchingSpo2 = true;
                Future.delayed(Duration(seconds: 2), () async {
                  await _fetchLogCount(context, deviceName, hPi4Global.Spo2Trend);
                  await _fetchLogIndex(context, deviceName, hPi4Global.Spo2Trend);
                });
              }
              break;

            case 02: // SpO2
              spo2SessionCount = sessionCount;
              if (spo2SessionCount == 0) {
                isFetchingSpo2Complete = true;
                isFetchingSpo2 = false;
                isFetchingTemp = true;
                Future.delayed(Duration(seconds: 2), () async {
                  await _fetchLogCount(context, deviceName, hPi4Global.TempTrend);
                  await _fetchLogIndex(context, deviceName, hPi4Global.TempTrend);
                });
              }
              break;

            case 03: // Temp
              tempSessionCount = sessionCount;
              if (tempSessionCount == 0) {
                isFetchingTempComplete = true;
              }
              break;

            case 04: // Activity
              activitySessionCount = sessionCount;
              if (activitySessionCount == 0) {
                isFetchingActivityComplete = true;
                isFetchingTemp = true;
                isFetchingActivity = false;
                Future.delayed(Duration(seconds: 2), () async {
                  await _fetchLogCount(context, deviceName, hPi4Global.TempTrend);
                  await _fetchLogIndex(context, deviceName, hPi4Global.TempTrend);
                });
              }
              break;
          }
        });

        _checkAllFetchesComplete(deviceName);
      }

      /*** 2. Handle Log Index (header data for each trend) ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        int trendType = bdata.getUint8(11);
        int logFileID = bdata.getInt64(1, Endian.little);
        int sessionLength = bdata.getInt16(9, Endian.little);
        LogHeader header = (logFileID: logFileID, sessionLength: sessionLength);

        switch (trendType) {
          case 01:
            logHeaderList.add(header);
            if (logHeaderList.length == hrSessionCount) _fetchNextLogFile(deviceName);
            break;

          case 02:
            logSpo2HeaderList.add(header);
            if (logSpo2HeaderList.length == spo2SessionCount) _fetchNextSpo2LogFile(deviceName);
            break;

          case 03:
            logTempHeaderList.add(header);
            if (logTempHeaderList.length == tempSessionCount) _fetchNextTempLogFile(deviceName);
            break;

          case 04:
            logActivityHeaderList.add(header);
            if (logActivityHeaderList.length == activitySessionCount) _fetchNextActivityLogFile(deviceName);
            break;
        }
      }

      /*** 3. Handle Log Data (actual binary chunks per log file) ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
        int pktPayloadSize = value.length - 1;
        currentFileDataCounter += pktPayloadSize;
        checkNoOfWrites += 1;

        logConsole("Data Counter $currentFileDataCounter");

        if (isFetchingHR) {
          logData.addAll(value.sublist(1));
          _handleDataChunkForTrend(
            logHeaderList,
            currentFileIndex,
                (progress) => setState(() => hrProgressPercent = progress),
                (header) => _writeLogDataToFile(logData, header.logFileID, formattedTime),
                () => _fetchNextLogFile(deviceName),
          );
        } else if (isFetchingSpo2) {
          logData.addAll(value.sublist(1));
          _handleDataChunkForTrend(
            logSpo2HeaderList,
            currentSpo2FileIndex,
                (progress) => setState(() => spo2ProgressPercent = progress),
                (header) => _writeSpo2LogDataToFile(logData, header.logFileID, "SPO2"),
                () => _fetchNextSpo2LogFile(deviceName),
          );
        } else if (isFetchingTemp) {
          logData.addAll(value.sublist(1));
          _handleDataChunkForTrend(
            logTempHeaderList,
            currentTempFileIndex,
                (progress) => setState(() => tempProgressPercent = progress),
                (header) => _writeLogDataToFile(logData, header.logFileID, formattedTime),
                () => _fetchNextTempLogFile(deviceName),
          );
        } else if (isFetchingActivity) {
          logData.addAll(value.sublist(1));
          _handleDataChunkForTrend(
            logActivityHeaderList,
            currentActivityFileIndex,
                (progress) => setState(() => activityProgressPercent = progress),
                (header) => _writeSpo2LogDataToFile(logData, header.logFileID, "Count"),
                () => _fetchNextActivityLogFile(deviceName),
          );
        }
      }
    });

    deviceName.cancelWhenDisconnected(_streamDataSubscription);
  }


  Future<void> _handleDataChunkForTrend(
      List<LogHeader> headerList,
      int currentIndex,
      Function(double) updateProgress,
      Future<void> Function(LogHeader) writeToFile,
      Function fetchNext,
      ) async {
    if (currentIndex >= headerList.length) return;
    final header = headerList[currentIndex];
    int expectedSize = header.sessionLength;
    double progress = currentFileDataCounter / expectedSize;
    updateProgress(progress);

    if (currentFileDataCounter >= expectedSize - 1) {
      await writeToFile(header);
      displayPercent = 0;
      globalDisplayPercentOffset = 0;
      currentFileDataCounter = 0;
      checkNoOfWrites = 0;
      logData = [];
      fetchNext();
    }
  }

  Future<void> _fetchNextLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentFileIndex < logHeaderList.length) {
      int logFileID = logHeaderList[currentFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
        updatedTimestamp,
      );
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's file detected with ID $logFileID. Always downloading...",);
        if(isFetchingTodayHR == false){
          await _fetchLogFile(
            deviceName,
            logFileID,
            logHeaderList[currentFileIndex].sessionLength,
            hPi4Global.HrTrend,
          );
        }
        setState(() {
          isFetchingTodayHR = true;
        });
      } else {
        bool fileExists = await _doesFileExistByType(logFileID, "hr");
        if (fileExists) {
          logConsole("File with ID $logFileID already exists. Skipping...");
        } else {
          logConsole("Fetching file with ID $logFileID...");
          await _fetchLogFile(
            deviceName,
            logFileID,
            logHeaderList[currentFileIndex].sessionLength,
            hPi4Global.HrTrend,
          );
          break; // Exit the loop to fetch the current file
        }
      }

      currentFileIndex++; // Increment after processing
    }

    if (currentFileIndex == logHeaderList.length) {
      logConsole("All files have been processed.");
      currentFileIndex--;

      Future.delayed(Duration(seconds: 2), () async {
        setState(() {
          totalFileDataCounter = 0;
          isFetchingHRComplete = true;
          isFetchingHR = false;
          isFetchingSpo2 = true;
          isFetchingActivity = false;
          isFetchingTemp = false;
        });
      });
      _checkAllFetchesComplete(deviceName);
      Future.delayed(Duration(seconds: 2), () async {
        await _fetchLogCount(context, deviceName, hPi4Global.Spo2Trend);
      });
      Future.delayed(Duration(seconds: 2), () async {
        await _fetchLogIndex(context, deviceName, hPi4Global.Spo2Trend);
      });
    }
  }

  Future<void> _fetchNextSpo2LogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentSpo2FileIndex < logSpo2HeaderList.length) {
      int logFileID = logSpo2HeaderList[currentSpo2FileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
        updatedTimestamp,
      );
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole(
          "Today's Spo2 file detected with ID $logFileID. Always downloading...",
        );
        if(isFetchingTodaySpo2 == false){
          await _fetchLogFile(
            deviceName,
            logFileID,
            logSpo2HeaderList[currentSpo2FileIndex].sessionLength,
            hPi4Global.Spo2Trend,
          );
        }
        setState(() {
          isFetchingTodaySpo2 = true;
        });

      } else {
        bool fileExists = await _doesFileExistByType(logFileID, "spo2");
        if (fileExists) {
          logConsole(
            "spo2 file with ID $logFileID already exists. Skipping...",
          );
        } else {
          logConsole("Fetching spo2 file with ID $logFileID...");
          await _fetchLogFile(
            deviceName,
            logFileID,
            logSpo2HeaderList[currentSpo2FileIndex].sessionLength,
            hPi4Global.Spo2Trend,
          );
          break;// Exit the loop to fetch the current file
        }
      }

      currentSpo2FileIndex++; // Increment after processing
    }

    if (currentSpo2FileIndex == logSpo2HeaderList.length) {
      logConsole("All spo2 files have been processed.");
      currentSpo2FileIndex--;

      Future.delayed(Duration(seconds: 2), () async {
        setState(() {
          isFetchingSpo2Complete = true;
          isFetchingHR = false;
          isFetchingSpo2 = false;
          isFetchingTemp = false;
          isFetchingActivity = true;
        });
      });
      _checkAllFetchesComplete(deviceName);
      Future.delayed(Duration(seconds: 2), () async {
        await _fetchLogCount(
          context,
          deviceName,
          hPi4Global.ActivityTrend,
        );
      });
      Future.delayed(Duration(seconds: 2), () async {
        await _fetchLogIndex(
          context,
          deviceName,
          hPi4Global.ActivityTrend,
        );
      });

    }
  }

  Future<void> _fetchNextTempLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentTempFileIndex < logTempHeaderList.length) {
      int logFileID = logTempHeaderList[currentTempFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
        updatedTimestamp,
      );
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's Temp file detected with ID $logFileID. Always downloading...",
        );
        if(isFetchingTodayTemp == false){
          await _fetchLogFile(
            deviceName,
            logFileID,
            logTempHeaderList[currentTempFileIndex].sessionLength,
            hPi4Global.TempTrend,
          );
        }
        setState(() {
          isFetchingTodayTemp = true;
        });

      } else {
        bool fileExists = await _doesFileExistByType(logFileID, "temp");

        if (fileExists) {
          logConsole(
            "temp file with ID $logFileID already exists. Skipping...",
          );
        } else {
          logConsole("Fetching temp file with ID $logFileID...");
          await _fetchLogFile(
            deviceName,
            logFileID,
            logTempHeaderList[currentTempFileIndex].sessionLength,
            hPi4Global.TempTrend,
          );
          break; // Exit the loop to fetch the current file
        }
      }

      currentTempFileIndex++; // Increment after processing
    }

    if (currentTempFileIndex == logTempHeaderList.length) {
      logConsole("All Temperature files have been processed.");
      currentTempFileIndex--;

      Future.delayed(Duration(seconds: 8), () async {
        setState(() {
          totalFileDataCounter = 0;
          isFetchingTempComplete = true;
          isFetchingHR = false;
          isFetchingTemp = false;
          isFetchingSpo2 = false;
          isFetchingActivity = false;
        });
        _checkAllFetchesComplete(deviceName);
      });

    }
  }

  Future<void> _fetchNextActivityLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentActivityFileIndex < logActivityHeaderList.length) {
      int logFileID = logActivityHeaderList[currentActivityFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(
        updatedTimestamp,
      );
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole(
          "Today's Activity file detected with ID $logFileID. Always downloading...",
        );
        if(isFetchingTodayActivity == false){
          await _fetchLogFile(
            deviceName,
            logFileID,
            logActivityHeaderList[currentActivityFileIndex].sessionLength,
            hPi4Global.ActivityTrend,
          );
        }
        setState(() {
          isFetchingTodayActivity = true;
        });

      } else {
        bool fileExists = await _doesFileExistByType(logFileID, "activity");

        if (fileExists) {
          logConsole(
            "Activity file with ID $logFileID already exists. Skipping...",
          );
        } else {
          logConsole("Fetching Activity file with ID $logFileID...");
          await _fetchLogFile(
            deviceName,
            logFileID,
            logActivityHeaderList[currentActivityFileIndex].sessionLength,
            hPi4Global.ActivityTrend,
          );
          break; // Exit the loop to fetch the current file
        }
      }
      currentActivityFileIndex++; // Increment after processing
    }

    if (currentActivityFileIndex == logActivityHeaderList.length) {
      logConsole("All Activity files have been processed.");
      currentActivityFileIndex--;
      Future.delayed(Duration(seconds: 2), () async {
        setState(() {
          isFetchingActivityComplete = true;
          isFetchingHR = false;
          isFetchingSpo2 = false;
          isFetchingTemp = true;
          isFetchingActivity = false;
        });
        _checkAllFetchesComplete(deviceName);
        Future.delayed(Duration(seconds: 2), () async {
          await _fetchLogCount(context, deviceName, hPi4Global.TempTrend);
        });
        Future.delayed(Duration(seconds: 2), () async {
          await _fetchLogIndex(context, deviceName, hPi4Global.TempTrend);
        });
      });

    }
  }

  Future<String> _getLogFilePathByType(int logFileID, String prefix) async {
    String directoryPath = (await getApplicationDocumentsDirectory()).path;
    return "$directoryPath/${prefix}_$logFileID.csv";
  }

  Future<bool> _doesFileExistByType(int logFileID, String prefix) async {
    String filePath = await _getLogFilePathByType(logFileID, prefix);
    return await File(filePath).exists();
  }

  Future<void> _fetchLogCount(
      BuildContext context,
      BluetoothDevice deviceName,
      List<int> trendType,
      ) async {
    //logConsole("Fetch log count initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(trendType);
      await _sendCommand(commandPacket, deviceName);
    });
  }

  Future<void> _fetchLogIndex(
      BuildContext context,
      BluetoothDevice deviceName,
      List<int> trendType,
      ) async {
    //logConsole("Fetch log index initiated");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      //List<int> type = [trendType];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(trendType);
      await _sendCommand(commandPacket, deviceName);
    });
  }

  Future<void> _fetchLogFile(
      BluetoothDevice deviceName,
      int sessionID,
      int sessionSize,
      List<int> trendType,
      ) async {
    //logConsole("Fetch logs file initiated for session: $sessionID, size: $sessionSize",);
    // Reset all fetch variables
    currentFileDataCounter = 0;
    await Future.delayed(Duration(seconds: 2), () async {
      //logConsole("Fetch logs file entered: $sessionID, size: $sessionSize");
      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(trendType);
      for (int shift = 0; shift <= 56; shift += 8) {
        commandFetchLogFile.add((sessionID >> shift) & 0xFF);
      }
      await _sendCommand(commandFetchLogFile, deviceName);
    });
  }

  void _checkAllFetchesComplete(BluetoothDevice deviceName) {
    if (isFetchingHRComplete &&
        isFetchingTempComplete &&
        isFetchingSpo2Complete &&
        isFetchingActivityComplete) {
      // logConsole("disconnected..............");
      onDisconnectPressed();
      //Navigator.pop(context);
      Navigator.push(
        Navigator.of(context).context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    }
  }

  Widget displayCloseandCancel(){
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
      child:  ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed:(){
          onDisconnectPressed();
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
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
    );

  }

  Widget showHRProgress(){
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress: (isFetchingHR)
            ? hrProgressPercent
            : (isFetchingHRComplete)
            ? 1.0
            : 0.0,
        label: "Heart rate" ,
      ),
    );
  }

  Widget showSpo2Progress(){
    if(isFetchingHRComplete){
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress: (isFetchingSpo2)
              ? spo2ProgressPercent
              : (isFetchingSpo2Complete)
              ? 1.0
              : 0.0,
          label: "Spo2" ,
        ),
      );
    }else{
      return Container();
    }
  }

  Widget showTempProgress(){
    if(isFetchingActivityComplete){
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress: (isFetchingTemp)
              ? tempProgressPercent
              : (isFetchingTempComplete)
              ? 1.0
              : 0.0,
          label: "Temperature" ,
        ),
      );
    }else{
      return Container();
    }
  }

  Widget showActivityProgress(){
    if(isFetchingSpo2Complete){
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress: (isFetchingActivity)
              ? activityProgressPercent
              : (isFetchingActivityComplete)
              ? 1.0
              : 0.0,
          label: "Activity" ,
        ),
      );
    }else{
      return Container();
    }
  }


  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      //key: Snackbar.snackBarKeyC,
      child: Scaffold(
        backgroundColor: hPi4Global.appBackgroundColor,
        appBar: AppBar(
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: (){
                onDisconnectPressed();
                Navigator.of(
                  context,
                ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
              }
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
        body:  ListView(
          children: [
            Center(
              child: Column(
                children: <Widget>[
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.max,
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        "Connected to: " +
                            widget.device.remoteId.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.green,
                        ),
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.max,
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      const Text('Syncing data..', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 10.0),
                    ],
                  ),
                  SizedBox(height: 10),
                  showHRProgress(),
                  SizedBox(height: 10),
                  showSpo2Progress(),
                  SizedBox(height: 10),
                  showActivityProgress(),
                  SizedBox(height: 20),
                  showTempProgress(),
                  SizedBox(height: 10),
                  displayCloseandCancel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrendProgressIndicator extends StatelessWidget {
  final double progress;
  final String label;

  const TrendProgressIndicator({
    Key? key,
    required this.progress,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label == "All files fetched"
                  ? label
                  : "Fetching $label data...",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            if (label != "All files fetched")
              SizedBox(
                height: 10, // Adjust this value to increase or decrease height
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                  backgroundColor: Colors.white24,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              progress > 0
                  ? "${(progress * 100).toStringAsFixed(1)}% completed"
                  : "...",
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}