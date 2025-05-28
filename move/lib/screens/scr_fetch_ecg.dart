import 'dart:io';
import 'package:convert/convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/sizeConfig.dart';

import 'package:path_provider/path_provider.dart';
import '../globals.dart';
import 'package:flutter/material.dart';
import '../home.dart';

import 'dart:async';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';

import '../utils/snackbar.dart';

typedef LogHeader = ({int logFileID, int sessionLength});

class ScrFetchECG extends StatefulWidget {
  final BluetoothDevice device;

  const ScrFetchECG({super.key, required this.device});

  @override
  _ScrFetchECGState createState() => _ScrFetchECGState();
}

class _ScrFetchECGState extends State<ScrFetchECG> {
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;

  bool pcConnected = false;
  bool currentFileReceivedComplete = false;
  bool fetchingFile = false;
  bool listeningDataStream = false;
  final bool _listeningCommandStream = false;

  late StreamSubscription<List<int>> _streamDataSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int globalTotalFiles = 0;
  int currentFileName = 0;
  int currentFileDataCounter = 0;
  int _globalReceivedData = 0;
  int _globalExpectedLength = 1;
  int tappedIndex = 0;
  int totalSessionCount = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  final _scrollController = ScrollController();

  int totalFileDataCounter = 0;
  int checkNoOfWrites = 0;

  @override
  void initState() {
    tappedIndex = 0;

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
    requestPermissions();
    super.initState();
  }

  @override
  void dispose() async {
    // Cancel all subscriptions in the dispose method (https://github.com/flutter/flutter/issues/64935)
    Future.delayed(Duration.zero, () async {
      await _connectionStateSubscription.cancel();
      await _isConnectingSubscription.cancel();
      await _isDisconnectingSubscription.cancel();
      //await _streamDataSubscription.cancel();
      await onDisconnectPressed();
    });

    super.dispose();
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [Permission.manageExternalStorage, Permission.storage].request();

    if (statuses.containsValue(PermissionStatus.denied)) {}
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
    await subscribeToChar(widget.device);
    await _startListeningData();
    await _fetchLogCount(context);
    await _fetchLogIndex(context);
  }

  Future waitWhile(
    bool Function() test, [
    Duration pollInterval = Duration.zero,
  ]) {
    var completer = Completer();
    check() {
      if (!test()) {
        completer.complete();
      } else {
        Timer(pollInterval, check);
      }
    }

    check();
    return completer.future;
  }

  bool isTransfering = false;
  bool isFetchIconTap = false;

  int logIndexNumElements = 0;
  static const int WISER_FILE_HEADER_LEN = 10;

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
                    'File downloaded successfully!. Please check in the downloads',
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

  // Function for converting little-endian bytes to integer
  int convertLittleEndianToInteger(List<int> bytes) {
    List<int> reversedBytes = bytes.reversed.toList();
    return reversedBytes.fold(0, (result, byte) => (result << 8) | byte);
  }

  Future<void> _writeLogDataToFile(List<int> mData, int sessionID) async {
    logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(
      mData,
    ).buffer.asByteData(WISER_FILE_HEADER_LEN);

    int logNumberPoints = ((mData.length - 1) ~/ 4);
    logConsole("File point..$logNumberPoints");

    //List<String> data1 = ['1', 'Bilal Saeed', '1374934', '912839812'];
    List<List<String>> dataList = []; //Outter List which contains the data List

    List<String> header = [];
    header.add("ECG");

    dataList.add(header);

    for (int i = 0; i < logNumberPoints - 1; i++) {
      // Extracting 16 bytes of data for the current row
      List<int> bytes = bdata.buffer.asInt8List(i * 4, 4);

      int value1 = convertLittleEndianToInteger(bytes.sublist(0, 4));

      // Construct the row data
      List<String> dataRow = [value1.toString()];
      dataList.add(dataRow);
    }

    // Code to convert logData to CSV file

    String csv = const ListToCsvConverter().convert(dataList);

    Directory directory0 = Directory("");

    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      directory0 = Directory("/storage/emulated/0/Download");
    } else {
      directory0 = await getApplicationDocumentsDirectory();
    }
    final exPath = directory0.path;
    print("Saved Path: $exPath");
    await Directory(exPath).create(recursive: true);

    final String directory = exPath;

    File file = File('$directory/$sessionID.csv');
    print("Save file");

    await file.writeAsString(csv);

    logConsole("File exported successfully!");

    await _showDownloadSuccessDialog();
  }

  bool logIndexReceived = false;
  List<LogHeader> logHeaderList = List.empty(growable: true);

  Future<void> _startListeningData() async {
    listeningDataStream = true;
    logConsole("Started listening...");

    await _streamDataSubscription.cancel();

    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      logConsole("Data Rx: $value");
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        //int _cmdType = bdata.getUint8(1);
        //if (_cmdType == 84) {
        if (mounted) {
          setState(() {
            totalSessionCount = bdata.getUint16(3, Endian.little);
          });
        }
        logConsole("Data Rx count: $totalSessionCount");

        //}
      } else if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        //print("Data Rx: " + value.toString());
        logConsole("Data Rx length: ${value.length}");

        int logFileID = bdata.getInt64(1, Endian.little);
        int sessionLength = bdata.getInt16(9, Endian.little);
        int trendType = bdata.getUint8(11);
        LogHeader header = (logFileID: logFileID, sessionLength: sessionLength);
        logConsole("Log: " + header.toString());

        logHeaderList.add(header);

        if (logHeaderList.length == totalSessionCount) {
          if (mounted) {
            setState(() {
              logIndexReceived = true;
            });
          }
        } else {}
      } else if (pktType == hPi4Global.CES_CMDIF_TYPE_DATA) {
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

        if (currentFileDataCounter >= (_globalExpectedLength)) {
          logConsole("All data $currentFileDataCounter received");

          if (currentFileDataCounter > _globalExpectedLength) {
            int diffData = currentFileDataCounter - _globalExpectedLength;
            logConsole("Data received more than expected by: $diffData bytes");
            //logData.removeRange(expectedLength, currentFileDataCounter);
          }

          await _writeLogDataToFile(logData, currentFileName);
          //_streamDataSubscription.cancel();
          //Navigator.pop(context);
        } else {}

        //_streamDataSubscription.cancel();
      }
    });
    widget.device.cancelWhenDisconnected(_streamDataSubscription);
    await dataCharacteristic!.setNotifyValue(true);

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
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            backgroundColor: Colors.black87,
            content: LoadingIndicator(text: text),
          ),
        );
      },
    );
  }

  String debugText = "Console Inited...";

  bool connectedToDevice = false;

  Future<void> _fetchLogCount(BuildContext context) async {
    logConsole("Fetch log count initiated");
    showLoadingIndicator("Fetching logs count...", context);
    //await _startListeningCommand(deviceID);
    //await _startListeningData(0, 0, "0");

    List<int> commandFetchLogFile = List.empty(growable: true);
    commandFetchLogFile.addAll(hPi4Global.ECGLogCount);
    commandFetchLogFile.addAll(hPi4Global.ECGRecord);
    await _sendCommand(commandFetchLogFile, widget.device);

    Navigator.pop(context);
  }

  Future<void> resetFetchVariables() async {
    // Reset all fetch variables
    setState(() {
      isTransfering = false;
      isFetchIconTap = false;
      // Reset all fetch variables
      displayPercent = 0;
      globalDisplayPercentOffset = 0;
      currentFileDataCounter = 0;
      _globalReceivedData = 0;
      currentFileName = 0;
      currentFileReceivedComplete = false;
      logData.clear();
    });
  }

  Future<void> _fetchLogIndex(BuildContext context) async {
    logConsole("Fetch logs initiated");
    showLoadingIndicator("Fetching logs...", context);
    //await _startListeningCommand(deviceID);
    // await _startListeningData(0, 0, "0");

    List<int> commandFetchLogFile = List.empty(growable: true);
    commandFetchLogFile.addAll(hPi4Global.ECGLogIndex);
    commandFetchLogFile.addAll(hPi4Global.ECGRecord);
    await _sendCommand(commandFetchLogFile, widget.device);

    Navigator.pop(context);
  }

  Future<void> _deleteLogIndex(
    String deviceID,
    int sessionID,
    BuildContext context,
  ) async {
    logConsole("Deleted logs initiated");
    showLoadingIndicator("Deleting log...", context);

    List<int> commandFetchLogFile = List.empty(growable: true);
    commandFetchLogFile.addAll(hPi4Global.ECGLogDelete);
    commandFetchLogFile.addAll(hPi4Global.ECGRecord);
    commandFetchLogFile.add(sessionID & 0xFF);
    commandFetchLogFile.add((sessionID >> 8) & 0xFF);
    await _sendCommand(commandFetchLogFile, widget.device);

    Navigator.pop(context);
    //await _fetchLogIndex(widget.currentDevice.id, context);
  }

  Future<void> _deleteAllLog(BuildContext context) async {
    logConsole("Deleted logs initiated");
    showLoadingIndicator("Deleting log...", context);

    List<int> commandFetchLogFile = List.empty(growable: true);
    commandFetchLogFile.addAll(hPi4Global.ECGLogWipeAll);
    await _sendCommand(commandFetchLogFile, widget.device);

    Navigator.pop(context);
    //await _fetchLogIndex(widget.currentDevice.id, context);
  }

  Future<void> _fetchLogFile(int sessionID, int sessionSize) async {
    await resetFetchVariables();
    await _startListeningData();
    logConsole("Fetch logs initiated");

    isTransfering = true;
    //await _startListeningCommand(deviceID);
    // Session size is in bytes, so multiply by 6 to get the number of data points, add header size
    // await _startListeningData((sessionSize * 2), sessionID);

    // Reset all fetch variables
    currentFileDataCounter = 0;
    currentFileReceivedComplete = false;

    setState(() {
      _globalExpectedLength = sessionSize;
      currentFileName = sessionID;
    });

    logData.clear();

    List<int> commandFetchLogFile = List.empty(growable: true);
    commandFetchLogFile.addAll(hPi4Global.FetchECGLogFile);
    commandFetchLogFile.addAll(hPi4Global.ECGRecord);
    for (int shift = 0; shift <= 56; shift += 8) {
      commandFetchLogFile.add((sessionID >> shift) & 0xFF);
    }
    await _sendCommand(commandFetchLogFile, widget.device);
  }

  Future<void> cancelAction() async {
    await onDisconnectPressed();
    //await _streamDataSubscription.cancel();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
  }

  String formattedTime(int timestamp) {
    DateTime date =
        DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
    String formattedDate = DateFormat('EEE d MMM h:mm a').format(date);
    return formattedDate;
  }

  Widget _getSessionIDList() {
    return (logIndexReceived == false)
        ? Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            //width: 320,
            //height: 100,
            child: Card(
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    "No logs present on device ",
                    style: TextStyle(
                      fontSize: 18,
                      color: hPi4Global.hpi4AppBarIconsColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        : SizedBox(
          // height: 400,
          child: Scrollbar(
            //isAlwaysShown: true,
            controller: _scrollController,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      "Session logs on device ",
                      style: TextStyle(fontSize: 20, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 15.0),
                    ListView.builder(
                      itemCount: totalSessionCount,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemBuilder: (BuildContext context, int index) {
                        return (index >= 0)
                            ? Card(
                              color: Colors.grey[900],
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.only(
                                    left: 0.0,
                                    right: 0.0,
                                  ),
                                  minLeadingWidth: 10,
                                  title: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            "Session ID: ${logHeaderList[index].logFileID}",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            "Recorded : " +
                                                formattedTime(
                                                  logHeaderList[index]
                                                      .logFileID,
                                                ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          isTransfering
                                              ? Container()
                                              : IconButton(
                                                onPressed: () async {
                                                  setState(() {
                                                    isFetchIconTap = true;
                                                    tappedIndex = index;
                                                  });
                                                  _fetchLogFile(
                                                    logHeaderList[index]
                                                        .logFileID,
                                                    logHeaderList[index]
                                                        .sessionLength,
                                                  );
                                                },
                                                icon: Icon(
                                                  Icons.download_rounded,
                                                ),
                                                color: hPi4Global.hpi4Color,
                                              ),
                                          /*isTransfering
                                              ? Container()
                                              : IconButton(
                                                onPressed: () async {},
                                                icon: Icon(Icons.delete),
                                                color: hPi4Global.hpi4Color,
                                              ),*/
                                        ],
                                      ),
                                      isFetchIconTap
                                          ? Visibility(
                                            visible: tappedIndex == index,
                                            child: Row(
                                              children: [
                                                Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child: SizedBox(
                                                    width: 150,
                                                    child:
                                                        LinearProgressIndicator(
                                                          backgroundColor:
                                                              Colors
                                                                  .blueGrey[100],
                                                          color:
                                                              hPi4Global
                                                                  .hpi4Color,
                                                          value:
                                                              (displayPercent /
                                                                  100),
                                                          minHeight: 25,
                                                          semanticsLabel:
                                                              'Receiving Data',
                                                        ),
                                                  ),
                                                ),
                                                Text(
                                                  "${displayPercent.truncate()} %",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          : Container(),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            : Container();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }

  Widget _buildDebugConsole() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Text(
          debugText,
          style: TextStyle(
            fontSize: 12,
            color: hPi4Global.hpi4AppBarIconsColor,
          ),
          maxLines: 4,
        ),
      ),
    );
  }

  showConfirmationDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
          ),
          child: AlertDialog(
            title: Text(
              'Are you sure you wish to delete all data.',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            content: Text(
              'This action is not reversible.',
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text(
                  'Yes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _deleteAllLog(context);
                  await _fetchLogCount(context);
                  await _fetchLogIndex(context);
                },
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text(
                  'No',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            await cancelAction();
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
            IconButton(
              icon: Icon(Icons.refresh, color: hPi4Global.hpi4AppBarIconsColor),
              onPressed: () async {
                await _fetchLogCount(context);
                await _fetchLogIndex(context);
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            _getSessionIDList(),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          //backgroundColor: hPi4Global.hpi4Color, // background color
                          backgroundColor: Colors.red, // background color
                          foregroundColor: Colors.white, // text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: Size(
                            SizeConfig.blockSizeHorizontal * 60,
                            40,
                          ),
                        ),
                        onPressed: () async {
                          showConfirmationDialog(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            //mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Icon(Icons.delete, color: Colors.white),
                              const Text(
                                ' Delete all records ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              Spacer(),
                              const Text(
                                ' >',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          //backgroundColor: hPi4Global.hpi4Color, // background color
                          backgroundColor: Colors.red, // background color
                          foregroundColor: Colors.white, // text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          minimumSize: Size(
                            SizeConfig.blockSizeHorizontal * 60,
                            40,
                          ),
                        ),
                        onPressed: () async {
                          await cancelAction();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            //mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Icon(Icons.close, color: Colors.white),
                              const Text(
                                ' Disconnect & Close ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                              Spacer(),
                              const Text(
                                ' >',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
