import 'dart:io';
import 'dart:async';

import 'sizeConfig.dart';

import 'fetchfileData.dart';
import 'home.dart';
import 'states/WiserBLEProvider.dart';
import 'package:provider/provider.dart';

import 'globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'ble/ble_scanner.dart';

late FlutterReactiveBle _fble;

late QualifiedCharacteristic commandCharacteristic;
late QualifiedCharacteristic dataCharacteristic;
late StreamSubscription<ConnectionStateUpdate> _connection;

bool connectedToDevice = false;
bool pcConnected = false;
String pcCurrentDeviceID = " ";
String pcCurrentDeviceName = " ";

class ConnectToFetchFileData extends StatefulWidget {
  ConnectToFetchFileData({Key? key}) : super(key: key);

  @override
  State createState() => new ConnectToFetchFileDataState();
}

class ConnectToFetchFileDataState extends State<ConnectToFetchFileData> {
  @override
  void initState() {
    Provider.of<BleScanner>(context, listen: false)
        .startScan([Uuid.parse("0000180d-0000-1000-8000-00805f9b34fb")], "");
    super.initState();
  }

  Future<void> connectToDevice(
      BuildContext context, DiscoveredDevice currentDevice) async {
    showLoadingIndicator("Connecting to device...", context);

    _fble =
    await Provider.of<WiserBLEProvider>(context, listen: false).getBLE();

    logConsole('Initiated connection to device: ' + currentDevice.id);

    pcCurrentDeviceID = currentDevice.id;
    pcCurrentDeviceName = currentDevice.name;

    commandCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_CMD),
        serviceId: Uuid.parse(hPi4Global.UUID_SERVICE_CMD),
        deviceId: currentDevice.id);

    dataCharacteristic = QualifiedCharacteristic(
        characteristicId: Uuid.parse(hPi4Global.UUID_CHAR_CMD_DATA),
        serviceId: Uuid.parse(hPi4Global.UUID_SERVICE_CMD),
        deviceId: currentDevice.id);


    _connection = _fble.connectToDevice(id: currentDevice.id).listen(
            (connectionStateUpdate) async {

          logConsole("Connecting device: " + connectionStateUpdate.toString());
          if (connectionStateUpdate.connectionState ==
              DeviceConnectionState.connected) {
            logConsole("Connected !");
            connectedToDevice = true;
            pcConnected = true;
            await _setMTU(currentDevice.id);

            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FetchFileData(
                    currentDevice: currentDevice,
                    currConnection: _connection,
                  ),
                ));
          } else if (connectionStateUpdate.connectionState ==
              DeviceConnectionState.disconnected) {
            Navigator.pop(context);
          }
          //if(connectionState.failure.code.toString();)
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

  Future<void> _setMTU(String deviceMAC) async {
    int recdMTU = await _fble.requestMtu(deviceId: deviceMAC, mtu: 517);
    logConsole("MTU negotiated: " + recdMTU.toString());
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  Widget _showAvailableDevicesCard() {
    return Consumer3<BleScannerState, BleScanner, WiserBLEProvider>(
        builder: (context, bleScannerState, bleScanner, wiserBle, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Colors.white,
              child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MaterialButton(
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
                      SizedBox(height:10.0),

                Column(
                  children: [
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
                ),
                    ],
                  )),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4Color,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => HomePage()),
            );
          }
        ),
        iconTheme: IconThemeData(
          color: Colors.white, //change your color here
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Image.asset('assets/healthypi5.png',
                fit: BoxFit.fitWidth, height: 30),
          ],
        ),
      ),
      body: SingleChildScrollView(
          child: Center(
            child:  Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Text(
                    "Connect the device To fetch",
                    style: hPi4Global.HeadStyle,
                  ),
                ),
                //showScanResults(),
                Container(
                  height: SizeConfig.blockSizeVertical * 80,
                  width: SizeConfig.blockSizeHorizontal * 97,
                  child:  _showAvailableDevicesCard(),
                ),
              ],
            ),
          )

      ),
    );
  }
}
