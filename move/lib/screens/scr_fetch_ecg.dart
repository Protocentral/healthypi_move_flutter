import 'dart:io';
import 'package:convert/convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';
import '../utils/sizeConfig.dart';

import 'package:path_provider/path_provider.dart';
import '../globals.dart';
import 'package:flutter/material.dart';
import '../home.dart';

import 'dart:async';
import 'dart:typed_data';
import 'package:csv/csv.dart';

import '../utils/snackbar.dart';

typedef LogHeader =
    ({
      int logFileID,
      int sessionLength,
      int sessionID,
      int tmSec,
      int tmMin,
      int tmHour,
      int tmMday,
      int tmMon,
      int tmYear,
    });

class ScrFetchECG extends StatefulWidget {
  const ScrFetchECG({
    super.key,
    required this.device
  });

  final BluetoothDevice device;

  @override
  _ScrFetchECGState createState() => _ScrFetchECGState();
}

class _ScrFetchECGState extends State<ScrFetchECG> {
  bool pcConnected = false;
  bool currentFileReceivedComplete = false;
  bool fetchingFile = false;
  bool listeningDataStream = false;
  final bool _listeningCommandStream = false;

  late StreamSubscription _streamCommandSubscription;
  late StreamSubscription _streamDataSubscription;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  double displayPercent = 0;
  double globalDisplayPercentOffset = 0;

  int globalTotalFiles = 0;
  int currentFileNumber = 0;
  int currentFileDataCounter = 0;
  int _globalReceivedData = 0;
  int _globalExpectedLength = 1;
  int tappedIndex = 0;
  int totalSessionCount = 0;

  List<int> currentFileData = [];
  List<int> logData = [];

  final _scrollController = ScrollController();

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _isDisconnecting = false;
  
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;

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
        subscribeToChar(widget.device);
        await _fetchLogCount(context);
        await _fetchLogIndex(context);
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
    _connectionStateSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    await onDisconnectPressed();
    super.dispose();
  }

  List<LogHeader> logHeaderList = List.empty(growable: true);

  Future waitWhile(bool Function() test, [Duration pollInterval = Duration.zero]) {
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

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
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

  bool isTransfering = false;
  bool isFetchIconTap = false;

  void logConsole(String logString) async {
    print("AKW - $logString");
    debugText += logString;
    debugText += "\n";
  }

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

  Future<void> _writeLogDataToFile(
    List<int> mData,
    int sessionID,
    String formattedTime,
  ) async {
    logConsole("Log data size: ${mData.length}");

    ByteData bdata = Uint8List.fromList(
      mData,
    ).buffer.asByteData(WISER_FILE_HEADER_LEN);

    int logNumberPoints = ((mData.length - WISER_FILE_HEADER_LEN) ~/ 6);

    //List<String> data1 = ['1', 'Bilal Saeed', '1374934', '912839812'];
    List<List<String>> dataList = []; //Outter List which contains the data List

    List<String> header = [];

    List<String> timeStore = ["Time: ", formattedTime.toString()];
    dataList.add(timeStore);

    header.add("Session Count");
    header.add("ECG");
    dataList.add(header);

    for (int i = 0; i < logNumberPoints; i++) {
      List<String> dataRow = [
        bdata.getUint16((i * 4), Endian.little).toString(),
        bdata.getInt16((i * 4) + 2, Endian.little).toString(),
      ];
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

  Future<void> _startListeningData(
    int expectedLength,
    int sessionID,
    String formattedTime,
  ) async {
    listeningDataStream = true;

    dataCharacteristic?.onValueReceived.listen((value) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      logConsole("Data Rx: $value");
      int pktType = bdata.getUint8(0);

      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        //int _cmdType = bdata.getUint8(1);
        //if (_cmdType == 84) {
        setState(() {
          totalSessionCount = bdata.getUint16(2, Endian.little);
        });
        logConsole("Data Rx count: $totalSessionCount");

        //}
      } else if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        //print("Data Rx: " + value.toString());
        logConsole("Data Rx length: ${value.length}");

        LogHeader mLog = (
          logFileID: bdata.getUint16(1, Endian.little),
          sessionID: bdata.getUint8(1), // same as log file id
          sessionLength: bdata.getUint16(3, Endian.little),
          tmYear: bdata.getUint8(5),
          tmMon: bdata.getUint8(6),
          tmMday: bdata.getUint8(7),
          tmHour: bdata.getUint8(8),
          tmMin: bdata.getUint8(9),
          tmSec: bdata.getUint8(10),
        );

        logConsole("Log: " + mLog.toString());

        logHeaderList.add(mLog);

        if (logHeaderList.length == totalSessionCount) {
          setState(() {
            logIndexReceived = true;
          });

          logConsole("All logs received. Cancel subscription");
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

        if (currentFileDataCounter >= (expectedLength)) {
          logConsole(
            "All data $currentFileDataCounter received",
          );

          if (currentFileDataCounter > expectedLength) {
            int diffData = currentFileDataCounter - expectedLength;
            logConsole(
              "Data received more than expected by: $diffData bytes",
            );
            //logData.removeRange(expectedLength, currentFileDataCounter);
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
          currentFileReceivedComplete = false;
          logData.clear();
        }
      }
    });
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
    await _startListeningData(0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandFetchLogFile = List.empty(growable: true);
      commandFetchLogFile.addAll(hPi4Global.ECGLogCount);
      commandFetchLogFile.addAll(hPi4Global.ECGRecord);
      await _sendCommand(commandFetchLogFile);
    });
    Navigator.pop(context);
  }

  Future<void> _fetchLogIndex(BuildContext context) async {
    logConsole("Fetch logs initiated");
    showLoadingIndicator("Fetching logs...", context);
    //await _startListeningCommand(deviceID);
   // await _startListeningData(0, 0, "0");
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandFetchLogFile = List.empty(growable: true);
      commandFetchLogFile.addAll(hPi4Global.ECGLogIndex);
      commandFetchLogFile.addAll(hPi4Global.ECGRecord);
      await _sendCommand(commandFetchLogFile);
    });
    Navigator.pop(context);
  }

  Future<void> _deleteLogIndex(
    String deviceID,
    int sessionID,
    BuildContext context,
  ) async {
    logConsole("Deleted logs initiated");
    showLoadingIndicator("Deleting log...", context);
    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandFetchLogFile = List.empty(growable: true);
      commandFetchLogFile.addAll(hPi4Global.ECGLogDelete);
      commandFetchLogFile.addAll(hPi4Global.ECGRecord);
      commandFetchLogFile.add(sessionID & 0xFF);
      commandFetchLogFile.add((sessionID >> 8) & 0xFF);
      await _sendCommand(commandFetchLogFile);
    });
    Navigator.pop(context);
    //await _fetchLogIndex(widget.currentDevice.id, context);
  }

  Future<void> _fetchLogFile(
    String deviceID,
    int sessionID,
    int sessionSize,
    String formattedTime,
  ) async {
    logConsole("Fetch logs initiated");
    isTransfering = true;
    //await _startListeningCommand(deviceID);
    // Session size is in bytes, so multiply by 6 to get the number of data points, add header size
    await _startListeningData(
      ((sessionSize * 6) + WISER_FILE_HEADER_LEN),
      sessionID,
      formattedTime,
    );

    // Reset all fetch variables
    currentFileDataCounter = 0;
    currentFileReceivedComplete = false;

    _globalExpectedLength = sessionSize;
    logData.clear();

    await Future.delayed(Duration(seconds: 2), () async {
      List<int> commandFetchLogFile = List.empty(growable: true);
      commandFetchLogFile.addAll(hPi4Global.FetchECGLogFile);
      commandFetchLogFile.add((sessionID >> 8) & 0xFF);
      commandFetchLogFile.add(sessionID & 0xFF);
      await _sendCommand(commandFetchLogFile);
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

  Future<void> _sendCommand(List<int> commandList) async {
    logConsole(
      "Tx CMD $commandList 0x${hex.encode(commandList)}",
    );

    if (commandService != null && commandCharacteristic != null) {
      // Write to the characteristic
      await commandCharacteristic?.write(commandList, withoutResponse: true);
      print('Data written: $commandList');
    }
  }

  Future<void> cancelAction() async {
    await onDisconnectPressed();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
  }

  String _getFormattedDate(
    int year,
    int month,
    int day,
    int hour,
    int min,
    int sec,
  ) {
    String formattedDate =
        "$hour:$min:$sec $day/$month/$year";

    return formattedDate;
  }

  Widget _getSessionIDList() {
    return (logIndexReceived == false)
        ? Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: 320,
            height: 100,
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
          height: 400,
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
                      style: TextStyle(
                        fontSize: 20,
                        color: hPi4Global.hpi4AppBarIconsColor,
                      ),
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
                                            "Session ID: ${logHeaderList[index].sessionID}",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            _getFormattedDate(
                                              logHeaderList[index].tmYear,
                                              logHeaderList[index].tmMon,
                                              logHeaderList[index].tmMday,
                                              logHeaderList[index].tmHour,
                                              logHeaderList[index].tmMin,
                                              logHeaderList[index].tmSec,
                                            ),
                                            style: TextStyle(fontSize: 12),
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
                                                },
                                                icon: Icon(
                                                  Icons.download_rounded,
                                                ),
                                                color: hPi4Global.hpi4Color,
                                              ),
                                          isTransfering
                                              ? Container()
                                              : IconButton(
                                                onPressed: () async {},
                                                icon: Icon(Icons.delete),
                                                color: hPi4Global.hpi4Color,
                                              ),
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
                                                          //color: Colors.blue,
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
                                                  "${displayPercent
                                                          .truncate()} %",
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

  @override
  Widget build(BuildContext context) {
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _getSessionIDList(),
              Padding(
                padding: const EdgeInsets.all(32),
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
                                Icon(Icons.system_update, color: Colors.white),
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
                                    fontSize: 20,
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

              /*Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: Colors.grey[900],
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: <Widget>[
                          _buildDebugConsole(),
                        ],
                      ),
                    ),
                  ),
              ),*/
            ],
          ),
        ),
      ),
    );
  }
}
