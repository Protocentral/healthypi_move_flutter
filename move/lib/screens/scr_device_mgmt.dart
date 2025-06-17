import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:move/screens/scr_bpt_calibration.dart';
import 'package:move/screens/scr_scan.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../utils/sizeConfig.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';

class ScrDeviceMgmt extends StatefulWidget {
  const ScrDeviceMgmt({super.key});

  @override
  _ScrDeviceMgmtState createState() => _ScrDeviceMgmtState();
}

class _ScrDeviceMgmtState extends State<ScrDeviceMgmt> {
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

  // reset the stored value
  _resetStoredValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setString('lastSynced', '0');
      prefs.setString('latestHR', '0');
      prefs.setString('latestTemp', '0');
      prefs.setString('latestSpo2', '0');
      prefs.setString('latestActivityCount', '0');
      prefs.setString('lastUpdatedHR', '0');
      prefs.setString('lastUpdatedTemp', '0');
      prefs.setString('lastUpdatedSpo2', '0');
      prefs.setString('lastUpdatedActivity', '0');
      prefs.setString('fetchStatus', '0');
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
                onPressed: () {
                  if (action == "logs on the device.") {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "2")),
                    );
                  } else {
                    Navigator.pop(context);
                    // deleteAllFiles();
                    _resetStoredValue();
                  }
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
                                          SizedBox(height: 10.0),
                                          /*ElevatedButton(
                                           style: ElevatedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              backgroundColor: hPi4Global.hpi4Color,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              backgroundColor: hPi4Global.hpi4Color,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                                                          ScrBPTCalibration(),
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
                                                    Symbols.blood_pressure,
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
                                          ),
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              backgroundColor: hPi4Global.hpi4Color,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () {
                                              Navigator.of(
                                                context,
                                              ).pushReplacement(
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) => ScrScan(
                                                    tabIndex: "4",
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.max,
                                                children: <Widget>[
                                                  Icon(
                                                    Icons.download_for_offline,
                                                    color: Colors.white,
                                                  ),
                                                  const Text(
                                                    ' Fetch Recordings',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              backgroundColor: hPi4Global.hpi4Color,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () {
                                              Navigator.of(context).pushReplacement(
                                                MaterialPageRoute(builder: (_) => ScrScan(tabIndex: "3")),
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.max,
                                                children: <Widget>[
                                                  Icon(
                                                    Symbols.monitoring,
                                                    color: Colors.white,
                                                    size: 18,
                                                  ),
                                                  const Text(
                                                    ' Live View',
                                                    style: TextStyle(fontSize: 14, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Divider(
                                            // Horizontal line
                                            color: Colors.grey,
                                            thickness: 0.5,
                                            height: 20, // space above and below
                                          ),
                                          SizedBox(height: 10.0),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              minimumSize: const Size(0, 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              backgroundColor: Colors.red,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: () {
                                              showConfirmationDialog(
                                                context,
                                                "logs on the device.",
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
