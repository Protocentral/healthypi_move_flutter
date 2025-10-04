import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:version/version.dart';
import '../utils/snackbar.dart';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../globals.dart';
import '../home.dart';
import '../utils/database_helper.dart';

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

  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late BluetoothCharacteristic deviceFWCharacteristic;

  // MCU Manager for SMP file system access
  late mcumgr.FsManager fsManager;

  // Track active download subscriptions for proper cleanup
  final List<StreamSubscription> _activeDownloadSubscriptions = [];

  late StreamSubscription<List<int>> _streamDataSubscription;
  bool listeningDataStream = false;

  // Progress tracking for all metric types
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

  String _currentFWVersion = "";
  String _fWVersion = "1.6.0";
  String _fwVersionCheck = "";

  @override
  void initState() {
    // Initialize MCU Manager FsManager for file operations
    final deviceId = widget.device.remoteId.toString();
    fsManager = mcumgr.FsManager(deviceId);
    logConsole('FsManager initialized with device: $deviceId');

    _connectionStateSubscription = widget.device.connectionState.listen((
      state,
    ) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        await _discoverDataChar(widget.device);
        //await _startListeningData();
        // startFetching();
      }
    });

    super.initState();
  }

  @override
  void dispose() async {
    // Cancel all subscriptions in the dispose method (https://github.com/flutter/flutter/issues/64935)
    Future.delayed(Duration.zero, () async {
      await _connectionStateSubscription.cancel();

      // Clean up any active download subscriptions
      for (var subscription in _activeDownloadSubscriptions) {
        await subscription.cancel();
      }
      _activeDownloadSubscriptions.clear();

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

  String _getMcuMgrErrorMessage(String errorString) {
    logConsole('Parsing McuMgr Error: $errorString');

    if (errorString.contains('McuMgrErrorException')) {
      final errorMatch = RegExp(
        r'McuMgr Error: (\d+) \(group: (\d+)\)',
      ).firstMatch(errorString);
      if (errorMatch != null) {
        final errorCode = int.parse(errorMatch.group(1)!);
        final groupCode = int.parse(errorMatch.group(2)!);

        logConsole('Error Code: $errorCode, Group Code: $groupCode');

        if (groupCode == 8) {
          // File system errors
          switch (errorCode) {
            case 1:
              return "File system error: Unknown error";
            case 2:
              return "File not found or path does not exist";
            case 3:
              return "File system is not mounted";
            case 4:
              return "File already exists";
            case 5:
              return "Invalid file name or path";
            case 6:
              return "Not enough space on device";
            case 7:
              return "Permission denied";
            case 8:
              return "File is too large";
            case 9:
              return "Invalid file operation";
            default:
              return "File system error code: $errorCode";
          }
        } else {
          return "MCU Manager error: Code $errorCode (Group $groupCode)";
        }
      }
    }
    return errorString;
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

  Future<void> _discoverDataChar(BluetoothDevice deviceName) async {
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
      if (service.uuid == Guid("180a")) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid == Guid("2a26")) {
            deviceFWCharacteristic = characteristic;
            characteristic
                .read()
                .then((value) {
                  if (mounted) {
                    setState(() {
                      _currentFWVersion = String.fromCharCodes(value);
                      _fwVersionCheck = _compareFwVersion(
                        _currentFWVersion,
                        _fWVersion,
                      );
                      logConsole("Current FW version: $_currentFWVersion");
                      if (_fwVersionCheck == "Can_sync") {
                        startFetching();
                      } else if (_fwVersionCheck == "Cannot_sync") {
                        _cannotSyncAndClose();
                        return;
                      } else {}
                    });
                  }
                })
                .catchError((e) {
                  Snackbar.show(
                    ABC.c,
                    prettyException("Read Error:", e),
                    success: false,
                  );
                });
            break;
          }
        }
      }
    }
  }

  String _compareFwVersion(String versionCurrent, String versionAvail) {
    Version availVersion = Version.parse(versionAvail);
    Version currentVersion = Version.parse(versionCurrent);

    if (availVersion > currentVersion) {
      return "Cannot_sync";
    } else if (availVersion == currentVersion ||
        availVersion < currentVersion) {
      return "Can_sync";
    } else {
      return "None";
    }
  }

  // Save a value
  _saveValue() async {
    DateTime now = DateTime.now();
    // String lastDateTime = DateFormat('EEE d MMM h:mm a').format(now);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSynced', now.toIso8601String());
  }

  Future<void> _sendCommand(
    List<int> commandList,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Tx CMD $commandList 0x${hex.encode(commandList)}");

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

  Future<void> _sendCurrentDateTime(
    BluetoothDevice deviceName,
    String selectedOption,
  ) async {
    List<int> commandDateTimePacket = [];

    var dt = DateTime.now();
    String cdate = DateFormat("yy").format(DateTime.now());
    logConsole(
      'Setting device time: $cdate/${dt.month}/${dt.day} ${dt.hour}:${dt.minute}:${dt.second}',
    );

    ByteData sessionParametersLength = ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);
    commandDateTimePacket.addAll(cmdByteList);
    await _sendCommand(commandDateTimePacket, deviceName);
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
    // Log database statistics
    try {
      final stats = await DatabaseHelper.instance.getDatabaseStats();
      logConsole('=== SQLite Database Stats ===');
      logConsole('Total records: ${stats['total_records']}');
      logConsole('HR records: ${stats['hr_records']}');
      logConsole('Temp records: ${stats['temp_records']}');
      logConsole('SpO2 records: ${stats['spo2_records']}');
      logConsole('Activity records: ${stats['activity_records']}');
      logConsole('Database size: ${(stats['database_size_bytes'] / 1024).toStringAsFixed(2)} KB');
      logConsole('============================');
    } catch (e) {
      logConsole('Note: Could not retrieve database stats: $e');
    }
    
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

  // Helper function for converting little-endian bytes to integer
  int convertLittleEndianToInteger(List<int> bytes) {
    List<int> reversedBytes = bytes.reversed.toList();
    return reversedBytes.fold(0, (result, byte) => (result << 8) | byte);
  }

  Future<void> _writeLogDataToFile(
    List<int> mData,
    int sessionID,
    List<int> trendType,
  ) async {
    logConsole("Parsing binary log data, size: ${mData.length}");

    // Skip first byte (packet type) if present
    int offset =
        (mData.isNotEmpty && mData[0] == hPi4Global.CES_CMDIF_TYPE_DATA)
            ? 1
            : 0;

    // Write to SQLite database
    try {
      String trendTypeStr = trendType == hPi4Global.HrTrend 
          ? hPi4Global.PREFIX_HR 
          : hPi4Global.PREFIX_TEMP;
      
      // Get binary data without packet type header
      List<int> binaryData = mData.sublist(offset);
      
      int recordCount = await DatabaseHelper.instance.insertTrendsFromBinary(
        binaryData,
        trendTypeStr,
        sessionID,
      );
      
      logConsole("SQLite: Inserted $recordCount $trendTypeStr records from session $sessionID");
    } catch (e) {
      logConsole("Error: SQLite write failed: $e");
      rethrow; // Propagate error since we have no fallback
    }
  }

  Future<void> _writeSpo2ActivityLogDataToFile(
    List<int> mData,
    int sessionID,
    List<int> trendType,
  ) async {
    logConsole(
      "Parsing binary log data (SpO2/Activity), size: ${mData.length}",
    );

    // Skip first byte (packet type) if present
    int offset =
        (mData.isNotEmpty && mData[0] == hPi4Global.CES_CMDIF_TYPE_DATA)
            ? 1
            : 0;

    // Write to SQLite database
    try {
      String trendTypeStr = trendType == hPi4Global.Spo2Trend
          ? hPi4Global.PREFIX_SPO2
          : hPi4Global.PREFIX_ACTIVITY;
      
      // Get binary data without packet type header
      List<int> binaryData = mData.sublist(offset);
      
      int recordCount = await DatabaseHelper.instance.insertTrendsFromBinary(
        binaryData,
        trendTypeStr,
        sessionID,
      );
      
      logConsole("SQLite: Inserted $recordCount $trendTypeStr records from session $sessionID");
    } catch (e) {
      logConsole("Error: SQLite write failed: $e");
      rethrow; // Propagate error since we have no fallback
    }
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

  Future<void> _cannotSyncAndClose() async {
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
                Text('Cannot sync the data'),
              ],
            ),
            content: Text(
              'Please ensure the device has the latest fw version 1.7.0 or greater to sync.',
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
  }

  Future<String> _getLogFilePathByType(int logFileID, String prefix) async {
    String directoryPath = (await getApplicationDocumentsDirectory()).path;
    logConsole("directoryPath/${prefix}_$logFileID.csv");
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
    // Variables were used by old custom BLE protocol - no longer needed with SMP
    // Keeping empty method to avoid breaking existing calls
  }

  /// Helper method to update progress for a specific trend type
  /// Updates individual file progress and overall progress based on bytes fetched
  void _updateProgressForTrend(List<int> trendType, int sessionSize) {
    if (trendType == hPi4Global.HrTrend) {
      setState(() {
        hrProgressPercent = 1.0;
        totalHRBytesFetched += sessionSize;
        overallHRProgressPercent =
            totalHRBytesToFetch > 0
                ? totalHRBytesFetched / totalHRBytesToFetch
                : 1.0;
        if (overallHRProgressPercent > 1.0) overallHRProgressPercent = 1.0;
      });
    } else if (trendType == hPi4Global.TempTrend) {
      setState(() {
        tempProgressPercent = 1.0;
        totalTempBytesFetched += sessionSize;
        overallTempProgressPercent =
            totalTempBytesToFetch > 0
                ? totalTempBytesFetched / totalTempBytesToFetch
                : 1.0;
        if (overallTempProgressPercent > 1.0) overallTempProgressPercent = 1.0;
      });
    } else if (trendType == hPi4Global.Spo2Trend) {
      setState(() {
        spo2ProgressPercent = 1.0;
        totalSpo2BytesFetched += sessionSize;
        overallSpo2ProgressPercent =
            totalSpo2BytesToFetch > 0
                ? totalSpo2BytesFetched / totalSpo2BytesToFetch
                : 1.0;
        if (overallSpo2ProgressPercent > 1.0) overallSpo2ProgressPercent = 1.0;
      });
    } else if (trendType == hPi4Global.ActivityTrend) {
      setState(() {
        activityProgressPercent = 1.0;
        totalActivityBytesFetched += sessionSize;
        overallActivityProgressPercent =
            totalActivityBytesToFetch > 0
                ? totalActivityBytesFetched / totalActivityBytesToFetch
                : 1.0;
        if (overallActivityProgressPercent > 1.0) {
          overallActivityProgressPercent = 1.0;
        }
      });
    }
  }

  Future<void> _fetchLogFile(
    BluetoothDevice deviceName,
    int sessionID,
    int sessionSize,
    List<int> trendType,
  ) async {
    logConsole(
      "Fetch logs file initiated for session: $sessionID, size: $sessionSize (via SMP)",
    );

    // Determine file prefix and device directory based on trend type using constants
    String filePrefix;
    String deviceDirectory;
    if (trendType == hPi4Global.HrTrend) {
      filePrefix = hPi4Global.PREFIX_HR;
      deviceDirectory = hPi4Global.DEVICE_DIR_HR;
    } else if (trendType == hPi4Global.TempTrend) {
      filePrefix = hPi4Global.PREFIX_TEMP;
      deviceDirectory = hPi4Global.DEVICE_DIR_TEMP;
    } else if (trendType == hPi4Global.Spo2Trend) {
      filePrefix = hPi4Global.PREFIX_SPO2;
      deviceDirectory = hPi4Global.DEVICE_DIR_SPO2;
    } else if (trendType == hPi4Global.ActivityTrend) {
      filePrefix = hPi4Global.PREFIX_ACTIVITY;
      deviceDirectory = hPi4Global.DEVICE_DIR_ACTIVITY;
    } else {
      logConsole("Unknown trend type: $trendType");
      return;
    }

    // Construct device file path following SMP/LittleFS convention
    // Device organizes files in subdirectories: /lfs/trhr/<timestamp>, /lfs/trtemp/<timestamp>, etc.
    final String deviceFilePath = "/lfs/$deviceDirectory/$sessionID";
    logConsole("Downloading from device path: $deviceFilePath");

    try {
      // Set up a completer to wait for download completion
      final completer = Completer<List<int>>();

      // Listen for download events from MCU Manager
      late StreamSubscription downloadSubscription;
      downloadSubscription = fsManager.downloadCallbacks.listen((event) {
        if (event.path == deviceFilePath) {
          if (event is mcumgr.OnDownloadCompleted) {
            logConsole("Download completed: ${event.data.length} bytes");
            downloadSubscription.cancel();
            _activeDownloadSubscriptions.remove(downloadSubscription);
            completer.complete(event.data);
          } else if (event is mcumgr.OnDownloadFailed) {
            logConsole("Download failed: ${event.cause}");
            downloadSubscription.cancel();
            _activeDownloadSubscriptions.remove(downloadSubscription);
            completer.completeError(
              Exception("Download failed: ${event.cause}"),
            );
          } else if (event is mcumgr.OnDownloadCancelled) {
            logConsole("Download cancelled");
            downloadSubscription.cancel();
            _activeDownloadSubscriptions.remove(downloadSubscription);
            completer.completeError(Exception("Download cancelled"));
          } else if (event is mcumgr.OnDownloadProgressChanged) {
            // Update progress
            double progress = event.current / event.total;
            logConsole(
              "Download progress: ${event.current}/${event.total} bytes (${(progress * 100).toStringAsFixed(1)}%)",
            );
          }
        }
      });

      // Track subscription for proper cleanup
      _activeDownloadSubscriptions.add(downloadSubscription);

      // Start the download via SMP
      await fsManager.download(deviceFilePath);
      logConsole("Download initiated for $deviceFilePath");

      // Wait for download to complete and get binary data
      final List<int> binaryData = await completer.future;
      logConsole(
        "Successfully downloaded ${binaryData.length} bytes from device",
      );

      // Parse binary data and convert to CSV
      if (trendType == hPi4Global.Spo2Trend ||
          trendType == hPi4Global.ActivityTrend) {
        await _writeSpo2ActivityLogDataToFile(binaryData, sessionID, trendType);
      } else if (trendType == hPi4Global.TempTrend ||
          trendType == hPi4Global.HrTrend) {
        await _writeLogDataToFile(binaryData, sessionID, trendType);
      }

      // Binary data received directly from SMP - no temp file to clean up

      // Update progress to 100% for this file
      _updateProgressForTrend(trendType, sessionSize);
    } catch (e, stackTrace) {
      logConsole('Error downloading file $deviceFilePath: $e');
      logConsole('Stack trace: $stackTrace');

      final errorMsg = _getMcuMgrErrorMessage(e.toString());
      logConsole('Parsed error: $errorMsg');

      // Show error to user
      if (mounted) {
        Snackbar.show(
          ABC.c,
          "Download error for $filePrefix file: $errorMsg",
          success: false,
        );
      }

      rethrow; // Re-throw to allow caller to handle
    }
  }

  // To check timstamp is today
  bool _isToday(LogHeader header) {
    final now = DateTime.now();
    final headerDate = DateTime.fromMillisecondsSinceEpoch(
      header.logFileID * 1000,
    );

    return now.year == headerDate.year &&
        now.month == headerDate.month &&
        now.day == headerDate.day;
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
        fileExists = await _doesFileExistByType(header.logFileID, "hr");
        //logConsole("Existence result for ${header.logFileID}: $fileExists");
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
        fileExists = await _doesFileExistByType(header.logFileID, "temp");
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
        fileExists = await _doesFileExistByType(header.logFileID, "spo2");
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
        fileExists = await _doesFileExistByType(header.logFileID, "activity");
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

  @override
  Widget build(BuildContext context) {
    // Calculate overall progress across all metrics
    int completedCount = 0;
    if (!_showProgressHR) completedCount++;
    if (!_showProgressTemp) completedCount++;
    if (!_showProgressSpo2) completedCount++;
    if (!_showProgressActivity) completedCount++;
    
    int totalMetrics = 4;
    double overallProgress = completedCount / totalMetrics;
    
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              onDisconnectPressed();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()),
              );
            },
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/healthypi_move.png',
                height: 28,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              const Text(
                'Syncing Data',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Header Section with Device Info
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: hPi4Global.hpi4AppBarColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    // Device connection status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.device.remoteId.toString(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Overall progress circle
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: overallProgress,
                            strokeWidth: 8,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.greenAccent,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(overallProgress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$completedCount of $totalMetrics',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Metrics List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildMetricCard(
                      icon: Icons.favorite,
                      label: 'Heart Rate',
                      progress: overallHRProgressPercent,
                      isVisible: _showProgressHR,
                      color: Colors.red[400]!,
                    ),
                    const SizedBox(height: 12),
                    _buildMetricCard(
                      icon: Icons.water_drop,
                      label: 'SpO₂',
                      progress: overallSpo2ProgressPercent,
                      isVisible: _showProgressSpo2,
                      color: Colors.blue[400]!,
                    ),
                    const SizedBox(height: 12),
                    _buildMetricCard(
                      icon: Icons.thermostat,
                      label: 'Temperature',
                      progress: overallTempProgressPercent,
                      isVisible: _showProgressTemp,
                      color: Colors.orange[400]!,
                    ),
                    const SizedBox(height: 12),
                    _buildMetricCard(
                      icon: Icons.directions_walk,
                      label: 'Activity',
                      progress: overallActivityProgressPercent,
                      isVisible: _showProgressActivity,
                      color: Colors.purple[400]!,
                    ),
                  ],
                ),
              ),
              
              // Cancel Button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red[300]!, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    onPressed: () async {
                      onDisconnectPressed();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => HomePage()),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cancel_outlined, color: Colors.red[300]),
                        const SizedBox(width: 8),
                        Text(
                          'Cancel Sync',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red[300],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required double progress,
    required bool isVisible,
    required Color color,
  }) {
    if (!isVisible) {
      // Completed state
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green[400],
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Completed',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // In-progress state
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress > 0
                      ? '${(progress * 100).toInt()}% complete'
                      : 'Starting...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
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
