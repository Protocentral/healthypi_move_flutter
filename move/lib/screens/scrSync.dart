import 'dart:async';
import 'dart:developer';
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
  bool listeningDataStream = false;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int currentFileDataCounter = 0;
  int totalFileDataCounter = 0;
  int checkNoOfWrites = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  double overallHRProgressPercent = 0.0;
  int totalHRBytesToFetch = 0;
  int totalHRBytesFetched = 0;

  double overallTempProgressPercent = 0.0;
  int totalTempBytesToFetch = 0;
  int totalTempBytesFetched = 0;

  double overallSpo2ProgressPercent = 0.0;
  int totalSpo2BytesToFetch = 0;
  int totalSpo2BytesFetched = 0;

  double overallActivityProgressPercent = 0.0;
  int totalActivityBytesToFetch = 0;
  int totalActivityBytesFetched = 0;

  bool _showProgressHR = true;
  bool _showProgressTemp = true;
  bool _showProgressSpo2 = true;
  bool _showProgressActivity = true;

  @override
  void initState() {
    _connectionStateSubscription = widget.device.connectionState.listen((
      state,
    ) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        await discoverDataChar(widget.device);
        //await _startListeningData();
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
    print("HPI - $logString");
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnect(queue: true);
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
            //break;
          }
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
            commandCharacteristic = characteristic;
            //break;
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

    /*List<BluetoothService> services = await deviceName.discoverServices();

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
    }*/

    if (commandService != null && commandCharacteristic != null) {
      // Write to the characteristic
      await commandCharacteristic?.write(commandList, withoutResponse: true);
    }
  }

  Future<int> _fetchLogCount(
    BuildContext context,
    BluetoothDevice deviceName,
    List<int> trendType,
  ) async {
    final completer = Completer<int>();
    int sessionCount = 0;

    // Temporary listener for session count packets
    late StreamSubscription<List<int>> tempSubscription;
    tempSubscription = dataCharacteristic!.onValueReceived.listen((value) {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        int trendCode = bdata.getUint8(2);
        if (trendCode == trendType[0]) {
          sessionCount = bdata.getUint16(3, Endian.little);
          tempSubscription.cancel();
          completer.complete(sessionCount);
        }
      }
    });

    widget.device.cancelWhenDisconnected(tempSubscription);
    await dataCharacteristic!.setNotifyValue(true);

    // Build and send the command
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.getSessionCount);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, deviceName);

    // Wait for the response and return session count
    return await completer.future;
  }

  void startFetching() async {
    _sendCurrentDateTime(widget.device, "Sync");
    _saveValue();

    _showProgressActivity = true;
    _showProgressHR = true;
    _showProgressSpo2 = true;
    _showProgressTemp = true;

    hrSessionCount = await _fetchLogCount(
      context,
      widget.device,
      hPi4Global.HrTrend,
    );
    tempSessionCount = await _fetchLogCount(
      context,
      widget.device,
      hPi4Global.TempTrend,
    );
    spo2SessionCount = await _fetchLogCount(
      context,
      widget.device,
      hPi4Global.Spo2Trend,
    );
    activitySessionCount = await _fetchLogCount(
      context,
      widget.device,
      hPi4Global.ActivityTrend,
    );

    logConsole(
      "HR Session Count: $hrSessionCount, "
      "Temp Session Count: $tempSessionCount, "
      "SpO2 Session Count: $spo2SessionCount, "
      "Activity Session Count: $activitySessionCount",
    );

    //await _streamDataSubscription.cancel();

    // Check if all session counts are zero (no data on device)
    if (hrSessionCount == 0 &&
        spo2SessionCount == 0 &&
        tempSessionCount == 0 &&
        activitySessionCount == 0) {
      logConsole("No data found on device. Cancelling sync operation.");
      _cancelSyncAndClose();
      return;
    }

    // Fetch log indices for trend types that have data
    //_fetchLogIndicesForAvailableData();

    if (hrSessionCount > 0) {
      logConsole("Fetching HR log indices - Count: $hrSessionCount");
      //await _fetchLogIndex(context, widget.device, hPi4Global.HrTrend);
      await _fetchLogIndexAndWait(
        context,
        widget.device,
        hPi4Global.HrTrend,
        listHRLogIndices,
        hrSessionCount,
      );

      await fetchAllHRLogFiles(widget.device);
      setState(() {
        _showProgressHR = false;
      });
    }

    // Fetch Temperature log indices if count > 0
    if (tempSessionCount > 0) {
      logConsole("Fetching Temperature log indices - Count: $tempSessionCount");
      await _fetchLogIndexAndWait(
        context,
        widget.device,
        hPi4Global.TempTrend,
        listTempLogIndices,
        tempSessionCount,
      );

      await fetchAllTempLogFiles(widget.device);
      setState(() {
        _showProgressTemp = false;
      });
    }

    // Fetch SpO2 log indices if count > 0
    if (spo2SessionCount > 0) {
      logConsole("Fetching SpO2 log indices - Count: $spo2SessionCount");
      await _fetchLogIndexAndWait(
        context,
        widget.device,
        hPi4Global.Spo2Trend,
        listSpO2LogIndices,
        spo2SessionCount,
      );

      await fetchAllSpo2LogFiles(widget.device);
      setState(() {
        _showProgressSpo2 = false;
      });
    }

    // Fetch Activity log indices if count > 0
    if (activitySessionCount > 0) {
      logConsole(
        "Fetching Activity log indices - Count: $activitySessionCount",
      );
      await _fetchLogIndexAndWait(
        context,
        widget.device,
        hPi4Global.ActivityTrend,
        listActivityLogIndices,
        activitySessionCount,
      );

      await fetchAllActivityLogFiles(widget.device);
      setState(() {
        _showProgressActivity = false;
      });
    }

    await _showSyncCompleteDialog();

    //await _fetchLogIndex(context, widget.device, hPi4Global.HrTrend);
  }

  Future<void> _showSyncCompleteDialog() async {
    // Cancel data stream subscription if active
    if (listeningDataStream) {
      await _streamDataSubscription.cancel();
      listeningDataStream = false;
    }
    // Disconnect from device
    await widget.device.disconnect(queue: true);

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
    }
  }

  // Function for converting little-endian bytes to integer
  int convertLittleEndianToInteger(List<int> bytes) {
    List<int> reversedBytes = bytes.reversed.toList();
    return reversedBytes.fold(0, (result, byte) => (result << 8) | byte);
  }

  Future<void> _writeLogDataToFile(
    List<int> mData,
    int sessionID,
    List<int> trendType,
  ) async {
    // logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    int logNumberPoints = ((mData.length) ~/ 16);

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
      directory0 = await getApplicationDocumentsDirectory();
    } else {
      directory0 = await getApplicationDocumentsDirectory();
    }

    final exPath = directory0.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;
    File file;

    if (trendType == hPi4Global.HrTrend) {
      file = File('$directory/hr_$sessionID.csv');
    } else if (trendType == hPi4Global.TempTrend) {
      file = File('$directory/temp_$sessionID.csv');
    }  else {
      logConsole("Unknown trend type: $trendType");
      return;
    }
    //file = File('$directory/temp_$sessionID.csv');

    await file.writeAsString(csv);

    logConsole("File exported successfully!");
  }

  Future<void> _writeSpo2ActivityLogDataToFile(
    List<int> mData,
    int sessionID,
    List<int> trendType,
  ) async {
    ByteData bdata = Uint8List.fromList(mData).buffer.asByteData(1);

    int logNumberPoints = ((mData.length) ~/ 16);

    List<List<String>> dataList = []; //Outter List which contains the data List
    List<String> header = [];

    header.add("Timestamp");

    if (trendType == hPi4Global.ActivityTrend) {
      header.add("Count");
    } else {
      header.add("SpO2");
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

    if (trendType == hPi4Global.Spo2Trend) {
      file = File('$directory/spo2_$sessionID.csv');
    } else if (trendType == hPi4Global.ActivityTrend) {
      file = File('$directory/activity_$sessionID.csv');
    } else {
      logConsole("Unknown trend type: $trendType");
      return;
    }

    await file.writeAsString(csv);

    logConsole("File exported successfully!");
  }

  double hrProgressPercent = 0.0; // 0.0 to 1.0
  double tempProgressPercent = 0.0; // 0.0 to 1.0
  double spo2ProgressPercent = 0.0; // 0.0 to 1.0
  double activityProgressPercent = 0.0; // 0.0 to 1.0

  List<LogHeader> listHRLogIndices = List.empty(growable: true);
  List<LogHeader> listTempLogIndices = List.empty(growable: true);
  List<LogHeader> listSpO2LogIndices = List.empty(growable: true);
  List<LogHeader> listActivityLogIndices = List.empty(growable: true);

  int hrSessionCount = 0;
  int tempSessionCount = 0;
  int spo2SessionCount = 0;
  int activitySessionCount = 0;

  int currentFileIndex = 0; // Track the current file being fetched
  int currentTempFileIndex = 0; // Track the current Temp file being fetched
  int currentSpo2FileIndex = 0; // Track the current SpO2 file being fetched
  int currentActivityFileIndex =
      0; // Track the current Activity file being fetched

  // Add this new method to handle cancellation
  Future<void> _cancelSyncAndClose() async {
    try {
      // Cancel data stream subscription if active
      if (listeningDataStream) {
        await _streamDataSubscription.cancel();
        listeningDataStream = false;
      }

      // Disconnect from device
      await widget.device.disconnect(queue: true);

      // Show dialog to user
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false, // Prevent dismissing by tapping outside
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Text('No Data Found'),
                ],
              ),
              content: Text(
                'No data was found on the device. Please ensure the device has been used to record health data before attempting to sync.',
                style: TextStyle(fontSize: 16),
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => HomePage()),
                    );
                  },
                  child: Text(
                    'OK',
                    style: TextStyle(
                      color: hPi4Global.hpi4Color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      logConsole("Error during sync cancellation: $e");
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
      }
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

  Future<void> _fetchLogIndexAndWait(
    BuildContext context,
    BluetoothDevice deviceName,
    List<int> trendType,
    List<LogHeader> headerList,
    int sessionCount,
  ) async {
    // Clear the list before fetching
    headerList.clear();

    final completer = Completer<void>();

    // Temporary listener for log index packets
    late StreamSubscription<List<int>> tempSubscription;
    tempSubscription = dataCharacteristic!.onValueReceived.listen((value) {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);
      if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        int trendTypeReceived = bdata.getUint8(13);
        if (trendTypeReceived == trendType[0]) {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt32(9, Endian.little);
          headerList.add((logFileID: logFileID, sessionLength: sessionLength));
          if (headerList.length == sessionCount) {
            tempSubscription.cancel();
            completer.complete();
          }
        }
      }
    });

    widget.device.cancelWhenDisconnected(tempSubscription);
    await dataCharacteristic!.setNotifyValue(true);

    // Send the command to fetch indices
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.sessionLogIndex);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, deviceName);

    // Wait until all indices are received
    await completer.future;
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
    logConsole(
      "Fetch logs file initiated for session: $sessionID, size: $sessionSize",
    );

    // Reset counters and buffer
    currentFileDataCounter = 0;
    logData.clear();

    // Build command
    List<int> commandFetchLogFile = [];
    commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
    commandFetchLogFile.addAll(trendType);
    for (int shift = 0; shift <= 56; shift += 8) {
      commandFetchLogFile.add((sessionID >> shift) & 0xFF);
    }

    // Completer to wait for full file
    final completer = Completer<void>();

    // Listen for log data packets
    late StreamSubscription<List<int>> tempSubscription;
    tempSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      int pktType = value[0];
      if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
        int pktPayloadSize = value.length - 1;
        currentFileDataCounter += pktPayloadSize;
        logData.addAll(value.sublist(1));

       // logConsole(logData.toString());

        if (trendType == hPi4Global.HrTrend) {
          setState(() {
            hrProgressPercent =
                sessionSize > 0 ? currentFileDataCounter / sessionSize : 0.0;
            if (hrProgressPercent > 1.0) hrProgressPercent = 1.0;

            // Update overall HR progress
            totalHRBytesFetched += pktPayloadSize;
            overallHRProgressPercent =
                totalHRBytesToFetch > 0
                    ? totalHRBytesFetched / totalHRBytesToFetch
                    : 0.0;
            if (overallHRProgressPercent > 1.0) overallHRProgressPercent = 1.0;
          });
        } else if (trendType == hPi4Global.TempTrend) {
          setState(() {
            tempProgressPercent =
                sessionSize > 0 ? currentFileDataCounter / sessionSize : 0.0;
            if (tempProgressPercent > 1.0) tempProgressPercent = 1.0;

            // Update overall Temp progress
            totalTempBytesFetched += pktPayloadSize;
            overallTempProgressPercent =
                totalTempBytesToFetch > 0
                    ? totalTempBytesFetched / totalTempBytesToFetch
                    : 0.0;
            if (overallTempProgressPercent > 1.0) {
              overallTempProgressPercent = 1.0;
            }
          });
        } else if (trendType == hPi4Global.Spo2Trend) {
          setState(() {
            spo2ProgressPercent =
                sessionSize > 0 ? currentFileDataCounter / sessionSize : 0.0;
            if (spo2ProgressPercent > 1.0) spo2ProgressPercent = 1.0;

            // Update overall SpO2 progress
            totalSpo2BytesFetched += pktPayloadSize;
            overallSpo2ProgressPercent =
                totalSpo2BytesToFetch > 0
                    ? totalSpo2BytesFetched / totalSpo2BytesToFetch
                    : 0.0;
            if (overallSpo2ProgressPercent > 1.0) {
              overallSpo2ProgressPercent = 1.0;
            }
          });
        } else if (trendType == hPi4Global.ActivityTrend) {
          setState(() {
            activityProgressPercent =
                sessionSize > 0 ? currentFileDataCounter / sessionSize : 0.0;
            if (activityProgressPercent > 1.0) activityProgressPercent = 1.0;

            // Update overall Activity progress
            totalActivityBytesFetched += pktPayloadSize;
            overallActivityProgressPercent =
                totalActivityBytesToFetch > 0
                    ? totalActivityBytesFetched / totalActivityBytesToFetch
                    : 0.0;
            if (overallActivityProgressPercent > 1.0) {
              overallActivityProgressPercent = 1.0;
            }
          });
        }

        // Check if all data received
        if (currentFileDataCounter >= sessionSize) {
          await tempSubscription.cancel();
          completer.complete();
        }
      }
    });

    widget.device.cancelWhenDisconnected(tempSubscription);
    await dataCharacteristic!.setNotifyValue(true);

    // Send command to fetch log file
    await _sendCommand(commandFetchLogFile, deviceName);

    // Wait until all data is received
    await completer.future;

    if (trendType == hPi4Global.Spo2Trend ||
        trendType == hPi4Global.ActivityTrend) {
      await _writeSpo2ActivityLogDataToFile(logData, sessionID, trendType);
    } else if (trendType == hPi4Global.TempTrend ||
        trendType == hPi4Global.HrTrend) {
      await _writeLogDataToFile(logData, sessionID, trendType);
    }
  }

 // To check timstamp is today
  bool _isToday(dynamic header) {
    final DateTime now = DateTime.now();
    final DateTime fileDate = DateTime.fromMillisecondsSinceEpoch(header.logFileID);
    return now.year == fileDate.year &&
        now.month == fileDate.month &&
        now.day == fileDate.day;
  }

  Future<void> fetchAllHRLogFiles(BluetoothDevice deviceName) async {
    logConsole("Fetching all HR log files count: ${listHRLogIndices.length}");
    // Calculate total bytes to fetch
    totalHRBytesToFetch = listHRLogIndices.fold(
      0,
      (sum, header) => sum + header.sessionLength,
    );
    totalHRBytesFetched = 0;
    overallHRProgressPercent = 0.0;
    setState(() {});

    for (final header in listHRLogIndices) {

      // Determine if this header is for today
      bool isToday = _isToday(header);

      // Only check for file existence if NOT today
      bool fileExists = false;
      if (!isToday) {
        fileExists = await _doesFileExistByType(header.logFileID, "hr_");
        if (fileExists) {
          logConsole(
            "File for logFileID ${header.logFileID} already exists, skipping download.",
          );
          continue;
        }
      }

      logConsole(
        "HPI - Fetching HR log file with ID ${header.logFileID} and length ${header.sessionLength}",
      );

      // Always download today's file, or if non-today file doesn't exist
      await _fetchLogFile(
        deviceName,
        header.logFileID,
        header.sessionLength,
        hPi4Global.HrTrend,
      );
    }
  }

  Future<void> fetchAllTempLogFiles(BluetoothDevice deviceName) async {
    logConsole(
      "Fetching all Temp log files count: ${listTempLogIndices.length}",
    );

    totalTempBytesToFetch = listTempLogIndices.fold(
      0,
      (sum, header) => sum + header.sessionLength,
    );
    totalTempBytesFetched = 0;
    overallTempProgressPercent = 0.0;
    setState(() {});

    for (final header in listTempLogIndices) {

      // Determine if this header is for today
      bool isToday = _isToday(header);

      // Only check for file existence if NOT today
      bool fileExists = false;
      if (!isToday) {
        fileExists = await _doesFileExistByType(header.logFileID, "temp_");
        if (fileExists) {
          logConsole(
            "File for logFileID ${header.logFileID} already exists, skipping download.",
          );
          continue;
        }
      }

      logConsole(
        "HPI - Fetching Temp log file with ID ${header.logFileID} and length ${header.sessionLength}",
      );
      await _fetchLogFile(
        deviceName,
        header.logFileID,
        header.sessionLength,
        hPi4Global.TempTrend,
      );
    }
  }

  Future<void> fetchAllSpo2LogFiles(BluetoothDevice deviceName) async {
    logConsole(
      "Fetching all SpO2 log files count: ${listSpO2LogIndices.length}",
    );

    // Calculate total bytes to fetch
    totalSpo2BytesToFetch = listSpO2LogIndices.fold(
      0,
      (sum, header) => sum + header.sessionLength,
    );
    totalSpo2BytesFetched = 0;
    overallSpo2ProgressPercent = 0.0;
    setState(() {});

    for (final header in listSpO2LogIndices) {

      // Determine if this header is for today
      bool isToday = _isToday(header);

      // Only check for file existence if NOT today
      bool fileExists = false;
      if (!isToday) {
        fileExists = await _doesFileExistByType(header.logFileID, "spo2_");
        if (fileExists) {
          logConsole(
            "File for logFileID ${header.logFileID} already exists, skipping download.",
          );
          continue;
        }
      }

      logConsole(
        "HPI - Fetching SpO2 log file with ID ${header.logFileID} and length ${header.sessionLength}",
      );
      await _fetchLogFile(
        deviceName,
        header.logFileID,
        header.sessionLength,
        hPi4Global.Spo2Trend,
      );
    }
  }

  Future<void> fetchAllActivityLogFiles(BluetoothDevice deviceName) async {
    logConsole(
      "Fetching all Activity log files count: ${listActivityLogIndices.length}",
    );

    // Calculate total bytes to fetch
    totalActivityBytesToFetch = listActivityLogIndices.fold(
      0,
      (sum, header) => sum + header.sessionLength,
    );
    totalActivityBytesFetched = 0;
    overallActivityProgressPercent = 0.0;
    setState(() {});

    for (final header in listActivityLogIndices) {
      // Determine if this header is for today
      bool isToday = _isToday(header);

      // Only check for file existence if NOT today
      bool fileExists = false;
      if (!isToday) {
        fileExists = await _doesFileExistByType(header.logFileID, "activity_");
        if (fileExists) {
          logConsole(
            "File for logFileID ${header.logFileID} already exists, skipping download.",
          );
          continue;
        }
      }

      logConsole(
        "HPI - Fetching Activity log file with ID ${header.logFileID} and length ${header.sessionLength}",
      );
      await _fetchLogFile(
        deviceName,
        header.logFileID,
        header.sessionLength,
        hPi4Global.ActivityTrend,
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

  Widget showHRProgress(bool isVisible) {
    if (!isVisible) {
      return Container();
    }
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress: overallHRProgressPercent,
        label: "Heart rate",
      ),
    );
  }

  Widget showSpo2Progress(bool isVisible) {
    if (!isVisible) {
      return Container();
    }

    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress: overallSpo2ProgressPercent,
        label: "Spo2",
      ),
    );
  }

  Widget showTempProgress(bool isVisible) {
    if (!isVisible) {
      return Container();
    }

    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress: overallTempProgressPercent,
        label: "Temperature",
      ),
    );
  }

  Widget showActivityProgress(bool isVisible) {
    if (!isVisible) {
      return Container();
    }
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 15,
      width: SizeConfig.blockSizeHorizontal * 95,
      child: TrendProgressIndicator(
        progress: overallActivityProgressPercent,
        label: "Activity",
      ),
    );
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
              onDisconnectPressed();
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
                  showHRProgress(_showProgressHR),
                  SizedBox(height: 10),
                  showSpo2Progress(_showProgressSpo2),
                  SizedBox(height: 10),
                  showActivityProgress(_showProgressActivity),
                  SizedBox(height: 20),
                  showTempProgress(_showProgressTemp),
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
