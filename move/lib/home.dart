import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'skinTempPage.dart';
import 'spo2Page.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'connectToFetchFiles.dart';
import 'globals.dart';
import 'hrPage.dart';
import 'sizeConfig.dart';
import 'dfu.dart';

import 'ble/ble_scanner.dart';
import 'states/WiserBLEProvider.dart';
import 'package:provider/provider.dart';
//import 'package:battery_indicator/battery_indicator.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'bptCalibrationPage.dart';

import 'package:flutter/cupertino.dart';

late StreamSubscription streamBatterySubscription;
late StreamSubscription streamECGSubscription;
late StreamSubscription streamPPGSubscription;
late StreamSubscription streamRESPSubscription;

late QualifiedCharacteristic CommandCharacteristic;
late QualifiedCharacteristic ECGCharacteristic;
late QualifiedCharacteristic PPGCharacteristic;
late QualifiedCharacteristic RESPCharacteristic;
late QualifiedCharacteristic BatteryCharacteristic;

late Stream<List<int>> _streamECG;
late Stream<List<int>> _streamPPG;
late Stream<List<int>> _streamRESP;
late Stream<List<int>> _streamBattery;

bool listeningECGStream = false;
bool listeningPPGStream = false;
bool listeningRESPStream = false;
bool listeningBatteryStream = false;

late FlutterReactiveBle _fble;
bool connectedToDevice = false;

late StreamSubscription<ConnectionStateUpdate> _connection;

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
  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Widget _buildAppDrawer() {
    return Drawer(
      child: ListView(
        // Important: Remove any padding from the ListView.
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            child: Image.asset('assets/healthypi5.png', fit: BoxFit.contain),
            decoration: BoxDecoration(
              color: hPi4Global.hpi4Color,
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
          Divider(
            color: Colors.black,
          ),
          _getPoliciesTile(),
          ListTile(
            title: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "v " + hPi4Global.hpi4AppVersion + " ",
                  style: new TextStyle(
                    fontSize: 12,
                  ),
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
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          //_showPrivacyDialog();
                        },
                    ),
                    TextSpan(
                        text: ' | ',
                        //'s', // Privacy Policy and Terms of Service ',

                        style: TextStyle(fontSize: 16, color: Colors.black)),
                    TextSpan(
                      text: 'Terms of use',
                      //'s', // Privacy Policy and Terms of Service ',

                      style: TextStyle(fontSize: 16, color: Colors.blue),
                      recognizer: TapGestureRecognizer()
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

  void closeAllStreams() async {
    if (listeningBatteryStream == true) {
      await streamBatterySubscription.cancel();
    }

    connectedToDevice = false;
    await _connection.cancel();
  }

  Future<void> connectToDevice(
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

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Future<void> _setMTU(String deviceMAC) async {
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
  }

  Widget showScanResults() {
    return Consumer3<BleScannerState, BleScanner, WiserBLEProvider>(
        builder: (context, bleScannerState, bleScanner, wiserBle, child) {
      return Card(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              connectedToDevice
                  ? MaterialButton(
                      minWidth: 100.0,
                      color: Colors.red,
                      child: Row(
                        children: <Widget>[
                          Text('Disconnect',
                              style: new TextStyle(
                                  fontSize: 18.0, color: Colors.white)),
                        ],
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      onPressed: () async {
                        await _disconnect();
                       // bleScanner.startScan([], "");
                      },
                    )
                  : MaterialButton(
                      minWidth: 100.0,
                      color: hPi4Global.hpi4Color,
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.refresh,
                            color: Colors.white,
                          ),
                          Text('Scan & Connect',
                              style: new TextStyle(
                                  fontSize: 18.0, color: Colors.white)),
                        ],
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          bool bleStatusFlag = await wiserBle.getBleStatus();
                          if (await wiserBle.checkPermissions(
                                  context, bleStatusFlag) ==
                              true) {
                            bleScanner.startScan([], "");
                          } else {
                            //Do not attempt to connect
                          }
                        } else {
                          bleScanner.startScan([], "");
                        }

                      },
                    ),
            ],
          ),
        ),
        Consumer3<BleScannerState, BleScanner, WiserBLEProvider>(
            builder: (context, bleScannerState, bleScanner, wiserBle, child) {
              return Column(
            children: [
              connectedToDevice?
              Column(
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Connected To:  "+pcCurrentDeviceName,
                                  style: new TextStyle(fontSize: 18.0, color: Colors.black)),
                              Padding(
                                padding:
                                const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                /*child: BatteryIndicator(
                                  batteryFromPhone: false,
                                  batteryLevel: _globalBatteryLevel,
                                  style: BatteryIndicatorStyle.skeumorphism,
                                  colorful: true,
                                  showPercentNum: true,
                                  size: 20,
                                ),*/
                              ),
                            ]))]):
              ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: bleScannerState.discoveredDevices.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(),
                  itemBuilder: (BuildContext context, int index) {
                    return ListTile(
                      title: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bluetooth),
                                Text(bleScannerState
                                    .discoveredDevices[index].name),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                  child: SignalStrengthIndicator.bars(
                                    value: bleScannerState
                                                .discoveredDevices.length >
                                            0
                                        ? 2 *
                                            (bleScannerState
                                                    .discoveredDevices[index]
                                                    .rssi +
                                                100) /
                                            100
                                        : 0, //patchBLE.patchRSSI / 100,
                                    size: 25,
                                    barCount: 4,
                                    spacing: 0.2,
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(8, 0, 8, 0),
                                  /*child: BatteryIndicator(
                                    batteryFromPhone: false,
                                    batteryLevel: _globalBatteryLevel,
                                    style: BatteryIndicatorStyle.skeumorphism,
                                    colorful: true,
                                    showPercentNum: true,
                                    size: 20,
                                  ),*/
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        connectToDevice(
                            context, bleScannerState.discoveredDevices[index]);
                      },
                    );
                  }),
            ],
          );
        }),
      ]));
    });
  }

  Future<void> _initPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    setState(() {
      hPi4Global.hpi4AppVersion = info.version;
    });
  }

  Widget _buildConnectionBlock() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              showScanResults(),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: Text(
                  "Ver: " + hPi4Global.hpi4AppVersion,
                  style: new TextStyle(fontSize: 12),
                ),
              ),
            ]),
      ),
    );
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
                                Text('--',
                                    style: hPi4Global.moveValueTextStyle),
                                //Icon(Icons.favorite_border, color: Colors.black),
                              ],
                            ),
                            SizedBox(
                              height: 20.0,
                            ),
                            Row(
                              children: <Widget>[
                                Text('--',
                                    style: hPi4Global.moveValueTextStyle),
                                //Icon(Icons.favorite_border, color: Colors.black),
                              ],
                            ),
                            SizedBox(
                              height: 20.0,
                            ),
                            Row(
                              children: <Widget>[
                                Text('--',
                                    style: hPi4Global.moveValueTextStyle),
                                //Icon(Icons.favorite_border, color: Colors.black),
                              ],
                            ),
                          ]),
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
                                              cornerStyle: CornerStyle.bothCurve
                                          )
                                        ]
                                    )
                                )
                            ),
                          ),

                        ]
                    ),

                  ],
                ),
              ]),
        ),
      ),

    );
  }


  int getGridCount(){
    if (MediaQuery.of(context).orientation == Orientation.landscape){
      return 4;
    }else{
      return 2;
    }
  }

  double getAspectRatio(){
    if (MediaQuery.of(context).orientation == Orientation.landscape){
      return MediaQuery.of(context).size.aspectRatio * 1.65 / 2;
    }else{
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
      crossAxisCount:getGridCount(),
      childAspectRatio: getAspectRatio(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HRPage()));
          },
          child:   Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(
                            'Heartrate',
                            style: hPi4Global.movecardTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('Today',
                            style: hPi4Global.movecardSubValueTextStyle),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(
                            globalHeartRate.toString(),
                            style: hPi4Global.movecardValueTextStyle),
                        SizedBox(
                          width: 5.0,
                        ),
                        Text("bpm", style: hPi4Global.movecardTextStyle),
                      ],
                    ),
                    SizedBox(
                      height: 40.0,
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('00:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 50.0,
                        ),
                        Text('24:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                      ],
                    ),
                  ]),
            ),
          ),
        ),

        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => SPO2Page()));
          },
          child:   Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(
                            'SpO2',
                            style: hPi4Global.movecardTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        //Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('Today',
                            style: hPi4Global.movecardSubValueTextStyle),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(globalSpO2.toString(),
                            style: hPi4Global.movecardValueTextStyle),
                        SizedBox(
                          width: 5.0,
                        ),
                        Text("%", style: hPi4Global.movecardTextStyle),
                      ],
                    ),
                    SizedBox(
                      height: 40.0,
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('00:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 50.0,
                        ),
                        Text('24:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                      ],
                    ),
                  ]),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => SkinTemperaturePage()));
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
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(
                            'Temperature',
                            style: hPi4Global.movecardTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        //Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('Today',
                            style: hPi4Global.movecardSubValueTextStyle),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(globalTemp.toStringAsPrecision(3),
                            style: hPi4Global.movecardValueTextStyle),
                        SizedBox(
                          width: 5.0,
                        ),
                        Text("\u00b0 C", style: hPi4Global.movecardTextStyle),
                      ],
                    ),
                    SizedBox(
                      height: 40.0,
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('00:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 50.0,
                        ),
                        Text('24:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                      ],
                    ),
                  ]),
            ),
          ),
        ),

        InkWell(
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BPTCalibrationPage(),
                ));
          },
          child:
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(
                            'Blood Pressure',
                            style: hPi4Global.movecardTextStyle),
                        SizedBox(
                          width: 15.0,
                        ),
                        //Icon(Icons.favorite_border, color: Colors.black),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('Today',
                            style: hPi4Global.movecardSubValueTextStyle),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text(globalSpO2.toString(),
                            style: hPi4Global.movecardValueTextStyle),
                        SizedBox(
                          width: 5.0,
                        ),
                        //Text("%", style: hPi4Global.movecardTextStyle),
                      ],
                    ),
                    SizedBox(
                      height: 40.0,
                    ),
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: 10.0,
                        ),
                        Text('00:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 50.0,
                        ),
                        Text('24:00',
                            style: hPi4Global.movecardSubValueTextStyle),
                        SizedBox(
                          width: 10.0,
                        ),
                      ],
                    ),
                  ]),
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
                      SizedBox(
                        width: 10.0,
                      ),
                      Text('Activity',
                          style: hPi4Global.movecardTextStyle),
                      SizedBox(
                        width: 15.0,
                      ),
                      //Icon(Icons.favorite_border, color: Colors.black),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 10.0,
                      ),
                      Text('Today',
                          style: hPi4Global.movecardSubValueTextStyle),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 10.0,
                      ),
                      Text("1 ",
                          style: hPi4Global.movecardValueTextStyle),
                      SizedBox(
                        width: 5.0,
                      ),
                      Text("Hour", style: hPi4Global.movecardSubValueTextStyle),
                      SizedBox(
                        width: 5.0,
                      ),
                      Text("12 ",
                          style: hPi4Global.movecardValueTextStyle),
                      SizedBox(
                        width: 5.0,
                      ),
                      Text("min", style: hPi4Global.movecardSubValueTextStyle),
                    ],
                  ),
                  SizedBox(
                    height: 40.0,
                  ),
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 10.0,
                      ),
                      Text(' ',
                          style: hPi4Global.movecardSubValueTextStyle),
                      SizedBox(
                        width: 50.0,
                      ),
                    ],
                  ),
                ]),
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
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/healthypi5.png',
                fit: BoxFit.fitWidth, height: 30),
          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(children: <Widget>[
              Container(
                //height: SizeConfig.blockSizeVertical * 45,
                width: SizeConfig.blockSizeHorizontal * 95,
                child:  _buildConnectionBlock(),
              ),
              Container(
                //height: SizeConfig.blockSizeVertical * 45,
                width: SizeConfig.blockSizeHorizontal * 95,
                child:  buildConnectedBlock(),
              ),
              Container(
                //height: SizeConfig.blockSizeVertical * 42,
                width: SizeConfig.blockSizeHorizontal * 95,
                child: _buildMainGrid(),
              ),
              Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
                  child:  MaterialButton(
                    minWidth: 80.0,
                    height: 50.0,
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.center, // Align however you like (i.e .centerRight, centerLeft)
                      child: Text('Fetch ECG Data',
                          style: new TextStyle(
                              fontSize: 18.0, color: Colors.black)),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => ConnectToFetchFileData()));
                    },
                  )
              ),

            ]),
          )
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