import 'dart:io';
import 'dart:async';

import '../utils/sizeConfig.dart';

import 'fetchfileData.dart';
import '../home.dart';
import 'package:provider/provider.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:signal_strength_indicator/signal_strength_indicator.dart';

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
    super.initState();
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

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  Widget _showAvailableDevicesCard() {
    return Container();
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
