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

import 'load_hr.dart';
import 'load_temp.dart';
import 'load_spo2.dart';
import 'load_activity.dart';

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
  bool listeningDataStream = false;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int currentFileDataCounter = 0;
  int totalFileDataCounter = 0;
  int checkNoOfWrites = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  @override
  void initState() {
    _connectionStateSubscription = widget.device.connectionState.listen((
      state,
    ) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        await discoverDataChar(widget.device);
        await _startListeningData();
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

    super.initState();
  }

  @override
  void dispose() async {
    // Cancel all subscriptions in the dispose method (https://github.com/flutter/flutter/issues/64935)
    Future.delayed(Duration.zero, () async {
      await _connectionStateSubscription.cancel();
      await _isConnectingSubscription.cancel();
      await _isDisconnectingSubscription.cancel();
      await onDisconnectPressed();
    });

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

  discoverDataChar(BluetoothDevice deviceName) async {
    List<BluetoothService> services = await deviceName.discoverServices();
    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        commandService = service;
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD_DATA)) {
            dataCharacteristic = characteristic;
            //await dataCharacteristic?.setNotifyValue(true);
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

  void startFetching() async {
    _sendCurrentDateTime(widget.device, "Sync");
    _saveValue();
    setState(() {
      isFetchingHR = true;
      isFetchingSpo2 = false;
      isFetchingTemp = false;
      isFetchingActivity = false;
    });
    await _fetchLogCount(context, widget.device, hPi4Global.HrTrend);
    await _fetchLogIndex(context, widget.device, hPi4Global.HrTrend);
  }

  // Function for converting little-endian bytes to integer
  int convertLittleEndianToInteger(List<int> bytes) {
    List<int> reversedBytes = bytes.reversed.toList();
    return reversedBytes.fold(0, (result, byte) => (result << 8) | byte);
  }

  Future<void> _writeLogDataToFile(List<int> mData, int sessionID) async {
    // logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    //logConsole("writing to file - hex: " +  hex.encode(mData));

    int logNumberPoints = ((mData.length) ~/ 16);

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
  ) async {
    // logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    int logNumberPoints = ((mData.length) ~/ 16);

    List<List<String>> dataList = []; //Outter List which contains the data List
    List<String> header = [];

    header.add("Timestamp");
    if (isFetchingSpo2) {
      header.add("SPO2");
    } else {
      header.add("Count");
    }
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
  bool isFetchingTodayTemp = false;
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

  Future<void> _startListeningData() async {
    listeningDataStream = true;
    logConsole("Started listening...");

    // Cancel previous subscription if it exists
    try {
      await _streamDataSubscription.cancel();
    } catch (_) {
      // Ignore if already cancelled or null
    }

    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      //logConsole("Data Rx: $value");
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);

      switch (pktType) {
        case hPi4Global.CES_CMDIF_TYPE_CMD_RSP:
          _handleCommandResponse(bdata);
          break;

        case hPi4Global.CES_CMDIF_TYPE_LOG_IDX:
          _handleLogIndex(bdata);
          break;

        case hPi4Global.CES_CMDIF_TYPE_DATA:
          _handleLogData(value);
          break;

        default:
          logConsole("Unknown packet type: $pktType");
      }
    });

    widget.device.cancelWhenDisconnected(_streamDataSubscription);
    await dataCharacteristic!.setNotifyValue(true);
  }

  void _handleCommandResponse(ByteData bdata) {
    int trendCode = bdata.getUint8(2);
    int sessionCount = bdata.getUint16(3, Endian.little);

    setState(() {
      switch (trendCode) {
        case 01: // HR
          hrSessionCount = sessionCount;
          _updateFetchingState(
            hrSessionCount,
            hPi4Global.Spo2Trend,
            isFetchingHR,
            isFetchingHRComplete,
            isFetchingSpo2,
          );
          break;

        case 02: // SpO2
          spo2SessionCount = sessionCount;
          _updateFetchingState(
            spo2SessionCount,
            hPi4Global.ActivityTrend,
            isFetchingSpo2,
            isFetchingSpo2Complete,
            isFetchingTemp,
          );
          break;

        case 03: // Temp
          tempSessionCount = sessionCount;
          if (tempSessionCount == 0)
            isFetchingTempComplete = true;
          break;

        case 04: // Activity
          activitySessionCount = sessionCount;
          _updateFetchingState(
            activitySessionCount,
            hPi4Global.TempTrend,
            isFetchingActivity,
            isFetchingActivityComplete,
            isFetchingTemp,
          );
          break;
      }
    });

    _checkAllFetchesComplete(widget.device);
  }

  void _updateFetchingState(
    int sessionCount,
    List<int> nextTrend,
    bool currentFetching,
    bool currentComplete,
    bool nextFetching,
  ) {
    if (sessionCount == 0) {
      currentComplete = true;
      currentFetching = false;
      nextFetching = true;
      Future.delayed(Duration.zero, () async {
        await _fetchLogCount(context, widget.device, nextTrend);
        await _fetchLogIndex(context, widget.device, nextTrend);
      });
    }
  }

  void _handleLogIndex(ByteData bdata) {
    int trendType = bdata.getUint8(13);
    int logFileID = bdata.getInt64(1, Endian.little);
    int sessionLength = bdata.getInt32(9, Endian.little);
    LogHeader header = (logFileID: logFileID, sessionLength: sessionLength);

    switch (trendType) {
      case hPi4Global.HPI_TREND_TYPE_HR:
        _processLogHeader(
          logHeaderList,
          hrSessionCount,
          _fetchNextLogFile,
          header,
        );
        break;

      case hPi4Global.HPI_TREND_TYPE_SPO2:
        _processLogHeader(
          logSpo2HeaderList,
          spo2SessionCount,
          _fetchNextSpo2LogFile,
          header,
        );
        break;

      case hPi4Global.HPI_TREND_TYPE_TEMP:
        _processLogHeader(
          logTempHeaderList,
          tempSessionCount,
          _fetchNextTempLogFile,
          header,
        );
        break;

      case hPi4Global.HPI_TREND_TYPE_ACTIVITY:
        _processLogHeader(
          logActivityHeaderList,
          activitySessionCount,
          _fetchNextActivityLogFile,
          header,
        );
        break;
    }
  }

  void _processLogHeader(
    List<LogHeader> headerList,
    int sessionCount,
    Function fetchNextFile,
    LogHeader header,
  ) {
    headerList.add(header);
    if (headerList.length == sessionCount) fetchNextFile(widget.device);
  }

  void _handleLogData(List<int> value) {
    int pktPayloadSize = value.length - 1;
    currentFileDataCounter += pktPayloadSize;
    checkNoOfWrites += 1;

    logConsole("Data Counter $currentFileDataCounter");

    List<int> dataChunk = value.sublist(1);
    logData.addAll(dataChunk);

    if (isFetchingHR) {
      _processDataChunk(
        logHeaderList,
        currentFileIndex,
        hrProgressPercent,
        _writeLogDataToFile,
        _fetchNextLogFile,
      );
    } else if (isFetchingSpo2) {
      _processDataChunk(
          logSpo2HeaderList,
          currentSpo2FileIndex,
          spo2ProgressPercent,
          _writeSpo2LogDataToFile,
          _fetchNextSpo2LogFile);
    } else if (isFetchingTemp) {
      _processDataChunk(
        logTempHeaderList,
        currentTempFileIndex,
        tempProgressPercent,
        _writeLogDataToFile,
        _fetchNextTempLogFile,
      );
    } else if (isFetchingActivity) {
      _processDataChunk(
          logActivityHeaderList,
          currentActivityFileIndex,
          activityProgressPercent,
          _writeSpo2LogDataToFile,
          _fetchNextActivityLogFile);
    }
  }

  void _processDataChunk(
    List<LogHeader> headerList,
    int currentIndex,
    double progressPercent,
    Future<void> Function(List<int>, int) writeToFile,
    Function fetchNextFile,
  ) {
    _handleDataChunkForTrend(
      headerList,
      currentIndex,
      (progress) => setState(() => progressPercent = progress),
      (header) => writeToFile(logData, header.logFileID),
      fetchNextFile,
    );
  }

  void _handleDataChunkForTrend(
    List<LogHeader> headerList,
    int currentIndex,
    void Function(double) updateProgress,
    Future<void> Function(LogHeader) writeToFile,
    Function fetchNextFile,
  ) async {
    if (headerList.isEmpty || currentIndex >= headerList.length) return;

    final header = headerList[currentIndex];
    final sessionLength = header.sessionLength;

    // Calculate progress
    double progress =
        sessionLength > 0 ? currentFileDataCounter / sessionLength : 0.0;
    if (progress > 1.0) progress = 1.0;
    updateProgress(progress);

    // If all data received for this file
    if (currentFileDataCounter >= sessionLength) {
      await writeToFile(header);
      currentFileDataCounter = 0;
      logData.clear();
      fetchNextFile(widget.device);
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
        logConsole(
          "Today's file detected with ID $logFileID. Always downloading...",
        );
        if (isFetchingTodayHR == false) {
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
      await listCSVFiles();
      _checkAllFetchesComplete(deviceName);
      await _fetchLogCount(context, deviceName, hPi4Global.Spo2Trend);
      await _fetchLogIndex(context, deviceName, hPi4Global.Spo2Trend);
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
        if (isFetchingTodaySpo2 == false) {
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
          break; // Exit the loop to fetch the current file
        }
      }

      currentSpo2FileIndex++; // Increment after processing
    }

    if (currentSpo2FileIndex == logSpo2HeaderList.length) {
      logConsole("All spo2 files have been processed.");
      currentSpo2FileIndex--;

      Future.delayed(Duration(seconds: 1), () async {
        setState(() {
          isFetchingSpo2Complete = true;
          isFetchingHR = false;
          isFetchingSpo2 = false;
          isFetchingTemp = false;
          isFetchingActivity = true;
        });
      });

      _checkAllFetchesComplete(deviceName);
      await listSpo2CSVFiles();
      await _fetchLogCount(context, deviceName, hPi4Global.ActivityTrend);
      await _fetchLogIndex(context, deviceName, hPi4Global.ActivityTrend);
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
        logConsole(
          "Today's Temp file detected with ID $logFileID. Always downloading...",
        );
        if (isFetchingTodayTemp == false) {
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

      Future.delayed(Duration(seconds: 5), () async {
        setState(() {
          totalFileDataCounter = 0;
          isFetchingTempComplete = true;
          isFetchingHR = false;
          isFetchingTemp = false;
          isFetchingSpo2 = false;
          isFetchingActivity = false;
        });
        await listTempCSVFiles();
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
        if (isFetchingTodayActivity == false) {
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
      Future.delayed(Duration(seconds: 1), () async {
        setState(() {
          isFetchingActivityComplete = true;
          isFetchingHR = false;
          isFetchingSpo2 = false;
          isFetchingTemp = true;
          isFetchingActivity = false;
        });
        await listActivityCSVFiles();
        _checkAllFetchesComplete(deviceName);
        await _fetchLogCount(context, deviceName, hPi4Global.TempTrend);
        await _fetchLogIndex(context, deviceName, hPi4Global.TempTrend);
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
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.getSessionCount);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, deviceName);
  }

  Future<void> _fetchLogIndex(
    BuildContext context,
    BluetoothDevice deviceName,
    List<int> trendType,
  ) async {
    //logConsole("Fetch log index initiated");
    List<int> commandPacket = [];
    //List<int> type = [trendType];
    commandPacket.addAll(hPi4Global.sessionLogIndex);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, deviceName);
  }

  Future<void> resetFetchVariables() async {
    // Reset all fetch variables
    setState(() {
      displayPercent = 0;
      globalDisplayPercentOffset = 0;
      currentFileDataCounter = 0;
      checkNoOfWrites = 0;
      logData.clear();
      logData = [];
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
    await _startListeningData();
    currentFileDataCounter = 0;
    logConsole("Fetch logs file entered: $sessionID, size: $sessionSize");
    List<int> commandFetchLogFile = [];
    commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
    commandFetchLogFile.addAll(trendType);
    for (int shift = 0; shift <= 56; shift += 8) {
      commandFetchLogFile.add((sessionID >> shift) & 0xFF);
    }
    await _sendCommand(commandFetchLogFile, deviceName);
  }

  Future<void> _checkAllFetchesComplete(BluetoothDevice deviceName) async {
    if (isFetchingHRComplete &&
        isFetchingTempComplete &&
        isFetchingSpo2Complete &&
        isFetchingActivityComplete) {
      Navigator.push(
        Navigator.of(context).context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    }
  }

  Widget displayCloseandCancel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed: () async {
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

  Widget showHRProgress() {
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress:
            (isFetchingHR)
                ? hrProgressPercent
                : (isFetchingHRComplete)
                ? 1.0
                : 0.0,
        label: "Heart rate",
      ),
    );
  }

  Widget showSpo2Progress() {
    if (isFetchingHRComplete) {
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress:
              (isFetchingSpo2)
                  ? spo2ProgressPercent
                  : (isFetchingSpo2Complete)
                  ? 1.0
                  : 0.0,
          label: "Spo2",
        ),
      );
    } else {
      return Container();
    }
  }

  Widget showTempProgress() {
    if (isFetchingActivityComplete) {
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress:
              (isFetchingTemp)
                  ? tempProgressPercent
                  : (isFetchingTempComplete)
                  ? 1.0
                  : 0.0,
          label: "Temperature",
        ),
      );
    } else {
      return Container();
    }
  }

  Widget showActivityProgress() {
    if (isFetchingSpo2Complete) {
      return SizedBox(
        height: SizeConfig.blockSizeVertical * 15,
        width: SizeConfig.blockSizeHorizontal * 95,
        child: TrendProgressIndicator(
          progress:
              (isFetchingActivity)
                  ? activityProgressPercent
                  : (isFetchingActivityComplete)
                  ? 1.0
                  : 0.0,
          label: "Activity",
        ),
      );
    } else {
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
            onPressed: () async {
              await onDisconnectPressed();
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
        body: ListView(
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
                        "Connected to: " + widget.device.remoteId.toString(),
                        style: TextStyle(fontSize: 16, color: Colors.green),
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
                      const Text(
                        'Syncing data..',
                        style: hPi4Global.movecardTextStyle,
                      ),
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
              label == "All files fetched" ? label : "Fetching $label data...",
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
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    hPi4Global.hpi4Color,
                  ),
                  backgroundColor: Colors.white24,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              progress > 0
                  ? "${(progress * 100).toStringAsFixed(1)}% completed"
                  : "...",
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
