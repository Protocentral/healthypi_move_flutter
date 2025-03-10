import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:move/screens/scan_screen.dart';
import 'package:move/widgets/scan_result_tile.dart';
import 'dfu.dart';
import 'screens/skinTempPage.dart';
import 'screens/spo2Page.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'globals.dart';
import 'sizeConfig.dart';
import 'screens/hrPage.dart';
import 'screens/bptCalibrationPage.dart';

import 'package:provider/provider.dart';
import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/cupertino.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'utils/snackbar.dart';
import 'utils/extra.dart';

int globalHeartRate = 0;
int globalSpO2 = 0;
int globalRespRate = 0;
double globalTemp = 0;
int _globalBatteryLevel = 50;

String pcCurrentDeviceID = "";
String pcCurrentDeviceName = "";

class HomePage extends StatefulWidget {
  HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  bool connectedToDevice = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Widget _buildAppDrawer() {
    return Drawer(
      backgroundColor: hPi4Global.hpi4Color,
      child: ListView(
        // Important: Remove any padding from the ListView.
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              //color: hPi4Global.hpi4Color,
            ),
            child: Image.asset(
              'assets/healthypi_move.png',
              fit: BoxFit.contain,
            ),
          ),
          ListTile(
            leading: Icon(Icons.search),
            title: Text('DFU'),
            onTap: () {
              Navigator.pop(context);
               Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DeviceManagement(),
                  ));
            },
          ),
          Divider(color: Colors.black),
          _getPoliciesTile(),
          ListTile(
            title: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "v " + hPi4Global.hpi4AppVersion + " ",
                  style: new TextStyle(fontSize: 12),
                ),
                Text(
                  "© 2020-2022 Circuitects Electronic Solutions",
                  style: new TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _getPoliciesTile() {
    return ListTile(
      title: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: OutlinedButton(
              onPressed: () async {
                //_launchURL();
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'circuitects.com', //style: new TextStyle(fontSize: 12)
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: ' Privacy Policy',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.blue),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              //_showPrivacyDialog();
                            },
                    ),
                    TextSpan(
                      text: ' | ',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                    TextSpan(
                      text: 'Terms of use',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.blue),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              //_showTermsDialog();
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  /*Future<void> connectToDevice(
      BuildContext context, DiscoveredDevice currentDevice) async {

    _fble =
        await Provider.of<WiserBLEProvider>(context, listen: false).getBLE();

    logConsole("Fetch Initiated: " + currentDevice.id);
    ;
    logConsole('Initiated connection to device: ' + currentDevice.id);

    ECGCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_ECG_CHAR),
        serviceId: Uuid.parse(hPi4Global.UUID_ECG_SERVICE),
        deviceId: currentDevice.id);

    RESPCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_RESP_CHAR),
        serviceId: Uuid.parse(hPi4Global.UUID_ECG_SERVICE),
        deviceId: currentDevice.id);

    PPGCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_PPG),
        serviceId: Uuid.parse(hPi4Global.UUID_SERV_PPG_RESP),
        deviceId: currentDevice.id);

    BatteryCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_BATT),
        serviceId: Uuid.parse(hPi4Global.UUID_SERV_BATT),
        deviceId: currentDevice.id);

    CommandCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_CMD),
        serviceId: Uuid.parse(hPi4Global.UUID_SERVICE_CMD),
        deviceId: currentDevice.id);

    _connection = _fble.connectToDevice(id: currentDevice.id).listen(
        (connectionStateUpdate) async {
      logConsole("Connecting device: " + connectionStateUpdate.toString());
      if (connectionStateUpdate.connectionState ==
          DeviceConnectionState.connected) {
        logConsole("Connected !");
        setState(() {
          connectedToDevice = true;
          pcCurrentDeviceID = currentDevice.id;
          pcCurrentDeviceName = currentDevice.name;
        });
        showLoadingIndicator("Connecting to device...",context);
        await _setMTU(currentDevice.id);
        await _startListeningBattery();
      } else if (connectionStateUpdate.connectionState ==
          DeviceConnectionState.disconnected) {
        connectedToDevice = false;
      }
    }, onError: (dynamic error) {
      logConsole("Connect error: " + error.toString());
    });
  }*/

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

  /*Future onScanPressed() async {
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        webOptionalServices: [
          Guid("180f"), // battery
          Guid("1800"), // generic access
          //Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        ],
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
    if (mounted) {
      setState(() {});
    }
  }*/

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  /*Future<void> _setMTU(String deviceMAC) async {
    int recdMTU = await _fble.requestMtu(deviceId: deviceMAC, mtu: 200);
    logConsole("MTU negotiated: " + recdMTU.toString());
    Navigator.pop(context);
  }

  Future<void> _startListeningBattery() async {
    print("AKW: Started listening to Battery stream");
    listeningBatteryStream = true;

    await Future.delayed(Duration(seconds: 1), () async {
      _streamBattery =
          await _fble.subscribeToCharacteristic(BatteryCharacteristic);
    });

    streamBatterySubscription = _streamBattery.listen((event) {
      setStateIfMounted(() {
        _globalBatteryLevel = event[0];
        print("AKW: Rx Battery: " + event[0].toString());
      });
    });
  }

  Future<void> _disconnect() async {
    try {
      logConsole('Disconnecting ');
      if (connectedToDevice == true) {
        showLoadingIndicator("Disconnecting....", context);
        await Future.delayed(Duration(seconds: 6), () async {
          closeAllStreams();
          await _connection.cancel();
          setState(() {
            connectedToDevice = false;
            pcCurrentDeviceID = "";
            pcCurrentDeviceName = "";
          });
        });
        Navigator.pop(context);
      }
    } on Exception catch (e, _) {
      logConsole("Error disconnecting from a device: $e");
    } finally {
      // Since [_connection] subscription is terminated, the "disconnected" state cannot be received and propagated

    }
  }*/

  Widget showScanResults() {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          //const ScanScreen(),
        ],
      ),
    );
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  Widget buildConnectedBlock() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(16.0)),
        child: Container(
          height: SizeConfig.blockSizeVertical * 30,
          width: SizeConfig.blockSizeHorizontal * 88,
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: SizeConfig.blockSizeVertical * 30,
                    width: SizeConfig.blockSizeHorizontal * 30,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text('--', style: hPi4Global.moveValueTextStyle),
                            //Icon(Icons.favorite_border, color: Colors.black),
                          ],
                        ),
                        SizedBox(height: 20.0),
                        Row(
                          children: <Widget>[
                            Text('--', style: hPi4Global.moveValueTextStyle),
                            //Icon(Icons.favorite_border, color: Colors.black),
                          ],
                        ),
                        SizedBox(height: 20.0),
                        Row(
                          children: <Widget>[
                            Text('--', style: hPi4Global.moveValueTextStyle),
                            //Icon(Icons.favorite_border, color: Colors.black),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    //mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        height: SizeConfig.blockSizeVertical * 30,
                        width: SizeConfig.blockSizeHorizontal * 44,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            child: SfCircularChart(
                              series: <CircularSeries>[
                                RadialBarSeries<ChartData, String>(
                                  dataSource: <ChartData>[
                                    ChartData("H", 50),
                                    ChartData("S", 75),
                                    ChartData("S", 100),
                                  ],
                                  xValueMapper: (ChartData data, _) => data.x,
                                  yValueMapper: (ChartData data, _) => data.y,
                                  // Corner style of radial bar segment
                                  cornerStyle: CornerStyle.bothCurve,
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
    );
  }

  int getGridCount() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return 4;
    } else {
      return 2;
    }
  }

  double getAspectRatio() {
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return MediaQuery.of(context).size.aspectRatio * 1.65 / 2;
    } else {
      return MediaQuery.of(context).size.aspectRatio * 4.2 / 2;
    }
  }

  Widget _buildMainGrid() {
    return GridView.count(
      primary: false,
      padding: const EdgeInsets.all(12),
      //crossAxisSpacing: 10,
      //mainAxisSpacing: 10,
      //crossAxisCount: 2,
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
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('Heartrate', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalHeartRate.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("bpm", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
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
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('SpO2', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalSpO2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
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
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text('Temperature', style: hPi4Global.movecardTextStyle),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalTemp.toStringAsPrecision(3),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      Text("\u00b0 C", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BPTCalibrationPage()),
            );
          },
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Blood Pressure',
                        style: hPi4Global.movecardTextStyle,
                      ),
                      SizedBox(width: 15.0),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        'Today',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        globalSpO2.toString(),
                        style: hPi4Global.movecardValueTextStyle,
                      ),
                      SizedBox(width: 5.0),
                      //Text("%", style: hPi4Global.movecardTextStyle),
                    ],
                  ),
                  SizedBox(height: 40.0),
                  Row(
                    children: <Widget>[
                      SizedBox(width: 10.0),
                      Text(
                        '00:00',
                        style: hPi4Global.movecardSubValueTextStyle,
                      ),
                      SizedBox(width: 50.0),
                      Text(
                        '24:00',
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
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text('Activity', style: hPi4Global.movecardTextStyle),
                    SizedBox(width: 15.0),
                    //Icon(Icons.favorite_border, color: Colors.black),
                  ],
                ),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text('Today', style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text("1 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("Hour", style: hPi4Global.movecardSubValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("12 ", style: hPi4Global.movecardValueTextStyle),
                    SizedBox(width: 5.0),
                    Text("min", style: hPi4Global.movecardSubValueTextStyle),
                  ],
                ),
                SizedBox(height: 40.0),
                Row(
                  children: <Widget>[
                    SizedBox(width: 10.0),
                    Text(' ', style: hPi4Global.movecardSubValueTextStyle),
                    SizedBox(width: 50.0),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future onScanPressed() async {
    /*try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      //var withServices = [Guid("180f")]; // Battery Level Service
      _systemDevices = await FlutterBluePlus.systemDevices();//withServices);
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("System Devices Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }*/
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        /*webOptionalServices: [
          Guid("180f"), // battery
          Guid("1800"), // generic access
          Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        ],*/
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
    if (mounted) {
      setState(() {});
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


  Widget buildScanButton(BuildContext context) {
    return MaterialButton(
      child: const Text("SCAN"),
      onPressed: onScanPressed,
      color: Colors.green,
    );
  }

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults
        .map(
          (r) => ScanResultTile(
            result: r,
            //onTap: () => onConnectPressed(r.device),
          ),
        ).toList();
  }


  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
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
                buildScanButton(context),
                 ListView(
                   shrinkWrap: true,
                     physics: ScrollPhysics(),
                  children: <Widget>[
                    ..._buildScanResultTiles(context),
                  ],
                ),
                Container(
                  //height: SizeConfig.blockSizeVertical * 42,
                  width: SizeConfig.blockSizeHorizontal * 95,
                  child: _buildMainGrid(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                  child: MaterialButton(
                    minWidth: 80.0,
                    height: 50.0,
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Fetch ECG Data',
                        style: new TextStyle(
                          fontSize: 18.0,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    onPressed: () async {
                      /*
                      Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => ConnectToFetchFileData()));*/
                    },
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

class ChartData {
  ChartData(this.x, this.y);
  final String x;
  final double y;
}
