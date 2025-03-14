import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:move/scanConnect.dart';
import 'dfu.dart';

import 'globals.dart';
import 'sizeConfig.dart';
import 'package:flutter/cupertino.dart';

class DevicePage extends StatefulWidget {
  DevicePage({Key? key}) : super(key: key);

  @override
  _DevicePageState createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {

  @override
  void initState() {
    super.initState();
  }

  void logConsole(String logString) async {
    print("AKW - " + logString);
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
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

          ],
        ),
      ),
      body: ListView(
        children: [
          Center(
            child: Column(
              children: <Widget>[
                Card(
                  color: Colors.black,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height:20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: <Widget>[
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Text('Device Management',
                                                    style: hPi4Global.movecardTextStyle),
                                                //Icon(Icons.favorite_border, color: Colors.black),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => DeviceManagement()),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  //mainAxisSize: MainAxisSize.min,
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.system_update,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Update Firmware ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {

                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.system_update,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Read Device ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => ScanConnectScreen(pageFlag:true)),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.sync,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Sync ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: hPi4Global.hpi4Color, // background color
                                                foregroundColor: Colors.white, // text color
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => ScanConnectScreen(pageFlag:false)),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  children: <Widget>[
                                                    Icon(
                                                      Icons.sync,
                                                      color: Colors.white,
                                                    ),
                                                    const Text(
                                                      ' Fetch Logs ',
                                                      style: TextStyle(
                                                          fontSize: 16, color: Colors.white),
                                                    ),
                                                    Spacer(),

                                                  ],
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),

                                          ]),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
