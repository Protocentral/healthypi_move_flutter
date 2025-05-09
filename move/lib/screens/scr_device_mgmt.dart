import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:move/screens/bptCalibrationPage1.dart';
import 'package:move/screens/scr_dfu.dart';
import 'package:move/screens/scr_scan.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/sizeConfig.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  _DevicePageState createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  String selectedOption = "sync";

  @override
  void initState() {
    super.initState();
  }

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }


  void logConsole(String logString) async {
    print("debug - $logString");
    setState(() {
      debugText += logString;
      debugText += "\n";
    });
  }

  void resetLogConsole() async {
    setState(() {
      debugText = "";
    });
  }

  String debugText = "Console Inited...";

  Widget _buildDebugConsole() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: SizedBox(
          height: 150, // 8 lines of text approximately
          width: SizeConfig.blockSizeHorizontal * 88,
          child: SingleChildScrollView(
            child: Text(
              debugText,
              style: TextStyle(
                fontSize: 12,
                color: hPi4Global.hpi4AppBarIconsColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Load the stored value
  _resetStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setString('lastSynced','0');
      prefs.setString('latestHR','0');
      prefs.setString('latestTemp','0');
      prefs.setString('latestSpo2','0');
      prefs.setString('latestActivityCount','0');
      prefs.setString('lastUpdatedHR','0');
      prefs.setString('lastUpdatedTemp','0');
      prefs.setString('lastUpdatedSpo2','0');
      prefs.setString('lastUpdatedActivity','0');
      prefs.setString('fetchStatus','0');
    });
  }

 showConfirmationDialog(BuildContext context, String action) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
          ),
          child: AlertDialog(
            title: Text('Are you sure you wish to delete all data.',
                style:TextStyle(fontSize: 18, color: Colors.white)),
            content: Text('This action is not reversible.',
                style:TextStyle(fontSize: 16, color: Colors.red)),
            actions: <Widget>[
              TextButton(
                child: const Text('Yes',
                    style:TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color:hPi4Global.hpi4Color)),
                onPressed: () {
                  if(action == "logs on the device"){
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ScrScan(tabIndex:"2")),
                    );
                  }else{
                    Navigator.pop(context);
                    deleteAllFiles();
                    _resetStoredValue();
                  }
                },
              ),
              TextButton(
                child: const Text('No',
                    style:TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color:hPi4Global.hpi4Color)),
                onPressed: () {
                  Navigator.pop(context); // Returns false
                },
              ),
            ],
          ),
        );

      },
    );
  }

  Future<void> deleteAllFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync();

      for (var file in files) {
        if (file is File) {
          await file.delete();
        }
      }
      print('All files deleted.');
      showSuccessDialog(context, "Deleted all files");
    } catch (e) {
      print('Error deleting files: $e');
    }
  }

  void showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: Colors.grey[900]),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text('Success',
                    style:TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            content: Text(message,
                style:TextStyle(fontSize: 16, color:Colors.white)),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text('OK',
                    style:TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color:hPi4Global.hpi4Color)),
              ),
            ],
          ),
        );
      },
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
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Text(
                                                'Device Management',
                                                style:
                                                    hPi4Global
                                                        .movecardTextStyle,
                                              ),
                                              //Icon(Icons.favorite_border, color: Colors.black),
                                            ],
                                          ),
                                         /* SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  hPi4Global
                                                      .hpi4Color, // background color
                                              foregroundColor:
                                                  Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (context) => ScrDFU(),
                                                ),
                                              );
                                            },

                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                //mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.system_update,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Update Firmware ',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),*/
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  hPi4Global
                                                      .hpi4Color, // background color
                                              foregroundColor:
                                                  Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              showConfirmationDialog(context, "logs on the device.");
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.delete,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Erase all logs on device ',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                              hPi4Global
                                                  .hpi4Color, // background color
                                              foregroundColor:
                                              Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                BorderRadius.circular(20),
                                              ),
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              showConfirmationDialog(context, "app data.");
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.delete,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Erase app data ',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 10.0),
                                          /*ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  hPi4Global
                                                      .hpi4Color, // background color
                                              foregroundColor:
                                                  Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                selectedOption = "BPT";
                                              });
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (context) =>
                                                          BPTCalibrationPage1(),
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.sync,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' BPT Calibration',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),*/
                                          SizedBox(height: 10.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            //SizedBox(height: 20),
                            /*Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  //height: SizeConfig.blockSizeVertical * 20,
                                  width: SizeConfig.blockSizeHorizontal * 88,
                                  child: Card(
                                    color: Colors.grey[900],
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.max,
                                        children: <Widget>[
                                          SizedBox(height: 10),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: hPi4Global
                                                  .hpi4Color
                                                  .withOpacity(
                                                    0.5,
                                                  ), // background color
                                              foregroundColor:
                                                  Colors.white, // text color
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              minimumSize: Size(
                                                SizeConfig.blockSizeHorizontal *
                                                    100,
                                                40,
                                              ),
                                            ),
                                            onPressed: () {
                                              /*Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (context) =>
                                                      DeviceManagement(),
                                                ),
                                              );*/
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Row(
                                                //mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.system_update,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Update Firmware ',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  Spacer(),
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Icon(
                                                Icons.warning_amber,
                                                color: Colors.white,
                                                size: 30.0,
                                              ),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  " Firmware Update through this app is still not available. Please use the nrfConnect App to update your firmware. "
                                                  "For more details details, ",
                                                  style:
                                                      hPi4Global
                                                          .movecardSubValue1TextStyle,
                                                  textAlign: TextAlign.justify,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              GestureDetector(
                                                onTap: () async {
                                                  const url =
                                                      'https://move.protocentral.com/updating_move/01-updating_with_nRF_connect/';
                                                  if (await canLaunchUrl(
                                                    Uri.parse(url),
                                                  )) {
                                                    await launchUrl(
                                                      Uri.parse(url),
                                                      mode:
                                                          LaunchMode
                                                              .externalApplication,
                                                    );
                                                  } else {
                                                    throw 'Could not launch $url';
                                                  }
                                                },
                                                child: Text(
                                                  'check our docs',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.blue,
                                                    decoration:
                                                        TextDecoration
                                                            .underline,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                          SizedBox(height: 10),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),*/
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
