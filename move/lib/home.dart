import 'dart:async';
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:move/screens/activityPage.dart';
import 'package:move/settings.dart';
import 'device.dart';
import 'screens/skinTempPage.dart';
import 'screens/spo2Page.dart';
import 'package:path/path.dart' as p;

import 'globals.dart';
import 'sizeConfig.dart';
import 'screens/hrPage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/snackbar.dart';
import '../widgets/scan_result_tile.dart';
import '../utils/extra.dart';

int globalSpO2 = 0;
int globalRespRate = 0;
int _globalBatteryLevel = 50;

String pcCurrentDeviceID = "";
String pcCurrentDeviceName = "";

typedef LogHeader = ({int logFileID, int sessionLength});

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    DevicePage(),
    SettingsPage(),
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar:new Theme(
        data: Theme.of(context).copyWith(
            canvasColor: hPi4Global.hpi4Color,
           ), // sets the inactive color of the `BottomNavigationBar`
        child:  Container(
          color:hPi4Global.hpi4AppBarColor,
          height: Platform.isAndroid? 80 : 110,
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child:BottomNavigationBar(
          type: BottomNavigationBarType.shifting, // Shifting
          selectedItemColor: hPi4Global.oldHpi4Color,
          unselectedItemColor: Colors.white,
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices),
              label: 'Device',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
    ),
        ),
      ),

    );
  }
}


class HomeScreen extends StatefulWidget {
  HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool connectedToDevice = false;

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  String selectedOption = "sync";
  String lastSyncedDateTime = '';

  String lastestHR = '';
  String lastestTemp = '';
  String lastestSpo2 = '';
  String lastestActivity = '';

  String lastUpdatedHR = '';
  String lastUpdatedTemp = '';
  String lastUpdatedSpo2 = '';
  String lastUpdatedActivity = '';

  int totalSessionCount = 0;
  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int globalTotalFiles = 0;
  int currentFileNumber = 0;
  int currentFileDataCounter = 0;
  int globalReceivedData = 0;
  int globalExpectedLength = 1;
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
    _initPackageInfo();
    _loadStoredValue();
    if (_isScanning == false) {
      startScan();
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

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  @override
  Future<void> dispose() async {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    //_connectionStateSubscription.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Load the stored value
  _loadStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      lastSyncedDateTime = prefs.getString('lastSynced') ?? 'No value saved yet';
      lastestHR = prefs.getString('latestHR') ?? '0';
      lastestTemp = prefs.getString('latestTemp') ?? '0';
      lastestSpo2 = prefs.getString('latestSpo2') ?? '0';
      lastestActivity = prefs.getString('latestActivityCount') ?? '0';
      lastUpdatedHR = prefs.getString('lastUpdatedHR') ?? '0';
      lastUpdatedTemp = prefs.getString('lastUpdatedTemp') ?? '0';
      lastUpdatedSpo2 = prefs.getString('lastUpdatedSpo2') ?? '0';
      lastUpdatedActivity = prefs.getString('lastUpdatedActivity') ?? '0';
    });
  }

  // Save a value
  _saveValue() async {
    DateTime now = DateTime.now();
    String lastDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSynced', lastDateTime);
    setState(() {
      lastSyncedDateTime = lastDateTime;
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

  }

  Future<void> startScan() async {
    // enable bluetooth on Android
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    if (await FlutterBluePlus.isSupported == false) {
      print("Bluetooth not supported by this device");
      return;
    }

    FlutterBluePlus.setLogLevel(LogLevel.verbose);
    FlutterBluePlus.adapterState.listen((event) {
      print(event);
    });

    await FlutterBluePlus.adapterState
        .where((BluetoothAdapterState state) => state == BluetoothAdapterState.on)
        .first;

    await FlutterBluePlus.startScan(
      withNames: ['healthypi move'],
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future onScanPressed() async {
    try {
      startScan();
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


  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      // Disconnect from the given Bluetooth device
      await device.disconnect();
      print('Device disconnected successfully');
    } catch (e) {
      print('Error disconnecting from device: $e');
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
    File file;
    if (isFetchingTemp) {
      file = File('$directory/temp_$sessionID.csv');
      print("Save file");
    }else{
      file = File('$directory/hr_$sessionID.csv');
      print("Save file");
    }

    await file.writeAsString(csv);

    logConsole("File exported successfully!");

    // await _showDownloadSuccessDialog();
  }

  Future<void> _writeSpo2LogDataToFile(
      List<int> mData,
      int sessionID,
      String headerName,
      ) async {
    logConsole("Log data size: " + mData.length.toString());

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

      logConsole("timestamp: " +timestamp.toString());
      logConsole("value: " + value1.toString());

      // Construct the row data
      List<String> dataRow = [
        timestamp.toString(),
        value1.toString(),
      ];
      dataList.add(dataRow);
    }

    // Code to convert logData to CSV file

    String csv = const ListToCsvConverter().convert(dataList);

    Directory _directory = Directory("");
    if (Platform.isAndroid) {
      _directory = await getApplicationDocumentsDirectory();
    } else {
      _directory = await getApplicationDocumentsDirectory();
    }

    final exPath = _directory.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;
    File file;

    if (isFetchingSpo2) {
      file = File('$directory/spo2_$sessionID.csv');
      print("Save file");
    }else{
      file = File('$directory/activity_$sessionID.csv');
      print("Save file");
    }


    await file.writeAsString(csv);

    logConsole("File exported successfully!");
  }

  bool isFetchingTemp = false;
  bool isFetchingSpo2 = false;
  bool isFetchingActivity = false;

  List<LogHeader> logHeaderList = List.empty(growable: true);
  List<LogHeader> logTempHeaderList = List.empty(growable: true);
  List<LogHeader> logSpo2HeaderList = List.empty(growable: true);
  List<LogHeader> logActivityHeaderList = List.empty(growable: true);

  int currentFileIndex = 0; // Track the current file being fetched
  int currentTempFileIndex = 0; // Track the current Temp file being fetched
  int currentSpo2FileIndex = 0; // Track the current SpO2 file being fetched
  int currentActivityFileIndex = 0; // Track the current Activity file being fetched


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

        if (isFetchingTemp) {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt16(9, Endian.little);
          logConsole("Temp Log file ID: $logFileID | Length: $sessionLength");

          LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

          setState(() {
            logTempHeaderList.add(mLog);
          });

          if (logTempHeaderList.length == totalSessionCount) {
            logConsole("All Temp logs Header.......$logTempHeaderList");
            _fetchNextTempLogFile(deviceName);
          }
        }else if(isFetchingSpo2) {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt16(9, Endian.little);
          logConsole("Spo2 Log file ID: $logFileID | Length: $sessionLength");

          LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

          setState(() {
            logSpo2HeaderList.add(mLog);
          });

          if (logSpo2HeaderList.length == totalSessionCount) {
            logConsole("All Spo2 logs Header.......$logSpo2HeaderList");
            _fetchNextSpo2LogFile(deviceName);
          }
        }else if(isFetchingActivity) {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt16(9, Endian.little);
          logConsole("Activity Log file ID: $logFileID | Length: $sessionLength");

          LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

          setState(() {
            logActivityHeaderList.add(mLog);
          });

          if (logActivityHeaderList.length == totalSessionCount) {
            logConsole("All Activity logs Header.......$logActivityHeaderList");
            _fetchNextActivityLogFile(deviceName);
          }
        }else {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt16(9, Endian.little);
          logConsole("HR Log file ID: $logFileID | Length: $sessionLength");

          LogHeader mLog = (logFileID: logFileID, sessionLength: sessionLength);

          setState(() {
            logHeaderList.add(mLog);
          });

          if (logHeaderList.length == totalSessionCount) {
            logConsole("All HR logs Header.......$logHeaderList");
            _fetchNextLogFile(deviceName);
          }

          //await _streamDataSubscription.cancel();
        }
      }
      /***** Packet type Log Data ***/
      else if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
        int pktPayloadSize = value.length -
            1; //((value[1] << 8) + value[2]);

        logConsole("Data Rx length: ${value
            .length} | Actual Payload: $pktPayloadSize",
        );
        currentFileDataCounter += pktPayloadSize;
        checkNoOfWrites += 1;

        logConsole("No of writes $checkNoOfWrites");
        logConsole("Data Counter $currentFileDataCounter");

        logData.addAll(value.sublist(1, value.length));

        logConsole("All data $currentFileDataCounter received");

        if (isFetchingTemp) {
          if (currentFileDataCounter >= logTempHeaderList[currentTempFileIndex].sessionLength - 1) {
            await _writeLogDataToFile(
              logData, logTempHeaderList[currentTempFileIndex].logFileID,
              formattedTime,
            );

            // Reset all fetch variables
            displayPercent = 0;
            globalDisplayPercentOffset = 0;
            currentFileDataCounter = 0;
            checkNoOfWrites = 0;
            logData.clear();

            if (currentTempFileIndex + 1 < logTempHeaderList.length) {
              currentTempFileIndex++;
              _fetchNextTempLogFile(deviceName);
            } else {
              logConsole("All temp files have been fetched.");
              setState(() {
                isFetchingTemp = false;
                isFetchingSpo2 = true;
                isFetchingActivity = false;
              });
              Future.delayed(Duration(seconds: 2), () async {
                await _fetchSpo2LogCount(context, deviceName);
              });
              Future.delayed(Duration(seconds: 2), () async {
                await _fetchSpo2LogIndex(context, deviceName);
              });
            }

          } else {
            logConsole("Invalid index or condition not met: currentFileIndex=$currentTempFileIndex");
          }

        }else if (isFetchingSpo2) {
          if (currentFileDataCounter >= logSpo2HeaderList[currentSpo2FileIndex].sessionLength - 1) {
            await _writeSpo2LogDataToFile(logData, logSpo2HeaderList[currentSpo2FileIndex].logFileID,
              "SPO2",
            );

            // Reset all fetch variables
            displayPercent = 0;
            globalDisplayPercentOffset = 0;
            currentFileDataCounter = 0;
            checkNoOfWrites = 0;
            logData.clear();

            if (currentSpo2FileIndex + 1 < logSpo2HeaderList.length) {
              currentSpo2FileIndex++;
              _fetchNextSpo2LogFile(deviceName);
            } else {
              logConsole("All Spo2 files have been fetched.");
              setState(() {
                isFetchingSpo2 = false;
                isFetchingTemp = false;
                isFetchingActivity = true;
              });
              Future.delayed(Duration(seconds: 2), () async {
                await _fetchActivityLogCount(context, deviceName);
              });
              Future.delayed(Duration(seconds: 2), () async {
                await _fetchActivityLogIndex(context, deviceName);
              });
            }

          } else {
            logConsole("Invalid index or condition not met: currentFileIndex=$currentSpo2FileIndex");
          }

        }else if (isFetchingActivity) {
          if (currentFileDataCounter >= logActivityHeaderList[currentActivityFileIndex].sessionLength - 1) {
            await _writeSpo2LogDataToFile(logData, logActivityHeaderList[currentActivityFileIndex].logFileID,
              "Count",
            );

            // Reset all fetch variables
            displayPercent = 0;
            globalDisplayPercentOffset = 0;
            currentFileDataCounter = 0;
            checkNoOfWrites = 0;
            logData.clear();

            if (currentActivityFileIndex + 1 < logActivityHeaderList.length) {
              currentActivityFileIndex++;
              _fetchNextActivityLogFile(deviceName);
            } else {
              logConsole("All Activity files have been fetched.");
              setState(() {
                isFetchingSpo2 = false;
                isFetchingTemp = false;
                isFetchingActivity = false;
              });
            }

          } else {
            logConsole("Invalid index or condition not met: currentFileIndex=$currentActivityFileIndex");
          }

        }
        else {
          if (currentFileDataCounter >= logHeaderList[currentFileIndex].sessionLength - 1) {
            await _writeLogDataToFile(
              logData,
              logHeaderList[currentFileIndex].logFileID,
              formattedTime,
            );

            // Reset all fetch variables
            displayPercent = 0;
            globalDisplayPercentOffset = 0;
            currentFileDataCounter = 0;
            checkNoOfWrites = 0;
            logData.clear();

            if (currentFileIndex + 1 < logHeaderList.length) {
              currentFileIndex++;
              _fetchNextLogFile(deviceName);
            } else {
              logConsole(
                  "All HR files have been fetched. Starting Temp file fetching...");
              setState(() {
                isFetchingTemp = true;
                isFetchingSpo2 = false;
                isFetchingActivity = false;
              });

              Future.delayed(Duration(seconds: 2), () async {
                await _fetchTempLogCount(context, deviceName);
              });
              Future.delayed(Duration(seconds: 2), () async {
                await _fetchTempLogIndex(context, deviceName);
              });
            }
          } else {
            logConsole(
                "Invalid index or condition not met: currentFileIndex=$currentFileIndex");
          }
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
      }
      else {
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
    String filePath = await _getLogFilePath(logFileID);
    return await File(filePath).exists();
  }

  Future<String> _getLogFilePath(int logFileID) async {
    // Define the file path logic here
    String directoryPath;
    if (Platform.isAndroid) {
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
    await _startListeningData(deviceName, 0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.HrTrend);
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

    showLoadingIndicator("Fetching file $sessionID...", context);
    // Reset all fetch variables
    currentFileDataCounter = 0;
    //currentFileReceivedComplete = false;
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



  Future<void> _fetchNextTempLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentTempFileIndex < logTempHeaderList.length) {
      int logFileID = logTempHeaderList[currentTempFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's Temp file detected with ID $logFileID. Always downloading...");
        await _fetchTempLogFile(deviceName, logFileID, logTempHeaderList[currentTempFileIndex].sessionLength, "");
      } else {
        bool fileExists = await _doesTempFileExist(logFileID);

        if (fileExists) {
          logConsole("temp file with ID $logFileID already exists. Skipping...");
        } else {
          logConsole("Fetching temp file with ID $logFileID...");
          await _fetchTempLogFile(deviceName, logFileID, logTempHeaderList[currentTempFileIndex].sessionLength, "");
          break; // Exit the loop to fetch the current file
        }
      }

      currentTempFileIndex++; // Increment after processing
    }

    if (currentTempFileIndex == logTempHeaderList.length) {
      logConsole("All Temperature files have been processed.");
      currentTempFileIndex--;
    }
  }

  Future<String> _getTempLogFilePath(int logFileID) async {
    String directoryPath;
    if (Platform.isAndroid) {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    }
    return "$directoryPath/temp_$logFileID.csv";
  }

  Future<bool> _doesTempFileExist(int logFileID) async {
    // Construct the file path
    String filePath = await _getTempLogFilePath(logFileID);

    // Check if the file exists
    return await File(filePath).exists();
  }

  Future<void> _fetchTempLogCount(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch temperature log count initiated");
    showLoadingIndicator("Fetching temperature logs count...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.tempTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchTempLogIndex(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch temperature log index initiated");
    showLoadingIndicator("Fetching temperature logs index...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.tempTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchTempLogFile(
      BluetoothDevice deviceName,
      int sessionID,
      int sessionSize,
      String formattedTime,
      ) async {
    logConsole(
      "Fetch temperature logs file initiated for session: $sessionID, size: $sessionSize",
    );
    showLoadingIndicator("Fetching temperature file $sessionID...", context);

    currentFileDataCounter = 0;

    await Future.delayed(Duration(seconds: 2), () async {
      logConsole("Fetch temperature logs file entered: $sessionID, size: $sessionSize");
      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(hPi4Global.tempTrend);
      for (int shift = 0; shift <= 56; shift += 8) {
        commandFetchLogFile.add((sessionID >> shift) & 0xFF);
      }
      await _sendCommand(commandFetchLogFile, deviceName);
    });
    Navigator.pop(context);
  }


  Future<void> _fetchNextSpo2LogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentSpo2FileIndex < logSpo2HeaderList.length) {
      int logFileID = logSpo2HeaderList[currentSpo2FileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's Spo2 file detected with ID $logFileID. Always downloading...");
        await _fetchSpo2LogFile(deviceName, logFileID, logSpo2HeaderList[currentSpo2FileIndex].sessionLength, "");
      } else {
        bool fileExists = await _doesSpo2FileExist(logFileID);

        if (fileExists) {
          logConsole("spo2 file with ID $logFileID already exists. Skipping...");
        } else {
          logConsole("Fetching spo2 file with ID $logFileID...");
          await _fetchSpo2LogFile(deviceName, logFileID, logSpo2HeaderList[currentSpo2FileIndex].sessionLength, "");
          break; // Exit the loop to fetch the current file
        }
      }

      currentSpo2FileIndex++; // Increment after processing
    }

    if (currentSpo2FileIndex == logSpo2HeaderList.length) {
      logConsole("All spo2 files have been processed.");
      currentSpo2FileIndex--;

    }
  }

  Future<String> _getSpo2LogFilePath(int logFileID) async {
    String directoryPath;
    if (Platform.isAndroid) {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    }
    return "$directoryPath/spo2_$logFileID.csv";
  }

  Future<bool> _doesSpo2FileExist(int logFileID) async {
    // Construct the file path
    String filePath = await _getSpo2LogFilePath(logFileID);
    // Check if the file exists
    return await File(filePath).exists();
  }

  Future<void> _fetchSpo2LogCount(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch spo2 log count initiated");
    showLoadingIndicator("Fetching spo2 logs count...", context);
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
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.Spo2Trend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchSpo2LogFile(
      BluetoothDevice deviceName,
      int sessionID,
      int sessionSize,
      String formattedTime,
      ) async {
    logConsole(
      "Fetch spo2 logs file initiated for session: $sessionID, size: $sessionSize",
    );
    showLoadingIndicator("Fetching spo2 file $sessionID...", context);

    currentFileDataCounter = 0;

    await Future.delayed(Duration(seconds: 2), () async {
      logConsole("Fetch spo2 logs file entered: $sessionID, size: $sessionSize");
      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(hPi4Global.Spo2Trend);
      for (int shift = 0; shift <= 56; shift += 8) {
        commandFetchLogFile.add((sessionID >> shift) & 0xFF);
      }
      await _sendCommand(commandFetchLogFile, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchNextActivityLogFile(BluetoothDevice deviceName) async {
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    while (currentActivityFileIndex < logActivityHeaderList.length) {
      int logFileID = logActivityHeaderList[currentActivityFileIndex].logFileID;
      int updatedTimestamp = logFileID * 1000;

      DateTime timestampDateTime = DateTime.fromMillisecondsSinceEpoch(updatedTimestamp);
      String fileDate = DateFormat('yyyy-MM-dd').format(timestampDateTime);

      if (fileDate == todayDate) {
        logConsole("Today's Activity file detected with ID $logFileID. Always downloading...");
        await _fetchActivityLogFile(deviceName, logFileID, logActivityHeaderList[currentActivityFileIndex].sessionLength, "");
      } else {
        bool fileExists = await _doesActivityFileExist(logFileID);

        if (fileExists) {
          logConsole("Activity file with ID $logFileID already exists. Skipping...");
        } else {
          logConsole("Fetching Activity file with ID $logFileID...");
          await _fetchActivityLogFile(deviceName, logFileID, logActivityHeaderList[currentActivityFileIndex].sessionLength, "");
          break; // Exit the loop to fetch the current file
        }
      }

      currentActivityFileIndex++; // Increment after processing
    }

    if (currentActivityFileIndex == logActivityHeaderList.length) {
      logConsole("All Activity files have been processed.");
      currentActivityFileIndex--;
    }
  }

  Future<String> _getActivityLogFilePath(int logFileID) async {
    String directoryPath;
    if (Platform.isAndroid) {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    } else {
      directoryPath = (await getApplicationDocumentsDirectory()).path;
    }
    return "$directoryPath/activity_$logFileID.csv";
  }

  Future<bool> _doesActivityFileExist(int logFileID) async {
    // Construct the file path
    String filePath = await _getActivityLogFilePath(logFileID);
    // Check if the file exists
    return await File(filePath).exists();
  }


  Future<void> _fetchActivityLogCount(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch Activity log count initiated");
    showLoadingIndicator("Fetching Activity logs count...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.getSessionCount);
      commandPacket.addAll(hPi4Global.ActivityTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchActivityLogIndex(
      BuildContext context,
      BluetoothDevice deviceName,
      ) async {
    logConsole("Fetch Activity log index initiated");
    showLoadingIndicator("Fetching Activity logs index...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.sessionLogIndex);
      commandPacket.addAll(hPi4Global.ActivityTrend);
      await _sendCommand(commandPacket, deviceName);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchActivityLogFile(
      BluetoothDevice deviceName,
      int sessionID,
      int sessionSize,
      String formattedTime,
      ) async {
    logConsole(
      "Fetch Activity logs file initiated for session: $sessionID, size: $sessionSize",
    );
    showLoadingIndicator("Fetching Activity file $sessionID...", context);

    currentFileDataCounter = 0;

    await Future.delayed(Duration(seconds: 2), () async {
      logConsole("Fetch Activity logs file entered: $sessionID, size: $sessionSize");
      List<int> commandFetchLogFile = [];
      commandFetchLogFile.addAll(hPi4Global.sessionFetchLogFile);
      commandFetchLogFile.addAll(hPi4Global.ActivityTrend);
      for (int shift = 0; shift <= 56; shift += 8) {
        commandFetchLogFile.add((sessionID >> shift) & 0xFF);
      }
      await _sendCommand(commandFetchLogFile, deviceName);
    });
    Navigator.pop(context);
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
        await FlutterBluePlus.stopScan();
        await subscribeToChar(device);
        _sendCurrentDateTime(device, "Sync");
        _saveValue();
        Navigator.pop(context);
        Future.delayed(Duration(seconds: 2), () async {
          await _fetchLogCount(context, device);
        });
        Future.delayed(Duration(seconds: 3), () async {
          await _fetchLogIndex(context, device);
        });
      }  else {
        //device.disconnect();
      }
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

  int getGridCount() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return 1;
    } else {
      return 1;
    }
  }

  double getAspectRatio() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return MediaQuery.of(context).size.aspectRatio * 4.0 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 10.0 / 2;
    }
  }

  Widget _buildMainGrid() {
    return GridView.count(
      primary: false,
      padding: const EdgeInsets.all(12),
      crossAxisCount: getGridCount(),
      childAspectRatio: getAspectRatio(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HRPage()));
          },
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Heartrate', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(lastestHR.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("bpm", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(lastUpdatedHR.toString(),
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        InkWell(
          onTap: () {
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => SPO2Page()));
          },
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.favorite_border, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(lastestSpo2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(lastUpdatedSpo2.toString(),
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => SkinTemperaturePage()),
            );
          },
          child: Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.thermostat, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Temperature', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(lastestTemp,
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("\u00b0 F", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(lastUpdatedTemp.toString(),
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => ActivityPage()),
            );
          },
          child:    Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.directions_run, color: Colors.white),
                      SizedBox(width: 10.0),
                      Text('Activity', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(lastestActivity.toString(), style: hPi4Global.movecardValueTextStyle),
                      SizedBox(width: 5.0),
                      Text("Steps", style: hPi4Global.movecardSubValueTextStyle),
                      SizedBox(width: 5.0),
                    ],
                  ),
                  SizedBox(height: 20.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text("Last updated: ",
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      Text(lastUpdatedActivity.toString(),
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 10.0),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

      ],
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
            Column(
                children: <Widget>[
                  InkWell(
                    onTap: () {
                      showScanDialog();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hPi4Global.hpi4Color,
                      ),
                      child: Icon(
                        Icons.sync,
                        color: hPi4Global.hpi4AppBarIconsColor,
                      ),
                    ),
                  ),
                ]
            )

          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child:
            Column(
              children: <Widget>[
                SizedBox(height:20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text("Last synced: "+lastSyncedDateTime,
                      style: hPi4Global.movecardSubValueTextStyle,),
                    SizedBox(width: 10.0),
                  ],
                ),
                SizedBox(height:10),
                Container(
                  //height: SizeConfig.blockSizeVertical * 42,
                  width: SizeConfig.blockSizeHorizontal * 95,
                  child: _buildMainGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

