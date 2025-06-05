import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'showTerms.dart';
import 'showPrivacy.dart';

import '../globals.dart';
import '../utils/sizeConfig.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScrSettings extends StatefulWidget {
  ScrSettings({super.key});

  @override
  _ScrSettingsState createState() => _ScrSettingsState();
}

class _ScrSettingsState extends State<ScrSettings> {
  @override
  void initState() {
    super.initState();
  }

  void logConsole(String logString) async {
    print("AKW - $logString");
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  _launchURL() async {
    const url = 'https://protocentral.com';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }
  }

  Widget _getPoliciesTile() {
    return ListTile(
      title: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4Color, // background color
                foregroundColor: Colors.white, // text color
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: Size(SizeConfig.blockSizeHorizontal * 100, 40),
              ),
              onPressed: () {
                _launchURL();
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'protocentral.com',
                      style: TextStyle(fontSize: 14, color: Colors.white),
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
                      style: TextStyle(
                        fontSize: 16,
                        color: hPi4Global.hpi4AppBarIconsColor,
                      ),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              showPrivacyDialog(context);
                            },
                    ),
                    TextSpan(
                      text: ' | ',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    TextSpan(
                      text: 'Terms of use',

                      //'s', // Privacy Policy and Terms of Service ',
                      style: TextStyle(
                        fontSize: 16,
                        color: hPi4Global.hpi4AppBarIconsColor,
                      ),
                      recognizer:
                          TapGestureRecognizer()
                            ..onTap = () async {
                              showTermsDialog(context);
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
                Text(
                  'Success',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text(
                  'OK',
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

  Future<void> deletePairedDeviceFile() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String filePath = '${appDocDir.path}/paired_device_mac.txt';
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
      print('File deleted');
    } else {
      print('File does not exist');
    }
  }

  // Load the stored value
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
      prefs.setString('pairedStatus', '0');
    });
  }

  // Load the stored value
  _resetStoredPairedValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      prefs.setString('pairedStatus', '0');
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
              'Are you sure you wish to delete '+action,
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
                  Navigator.pop(context);
                  if(action == "all data."){
                    deleteAllFiles();
                    _resetStoredValue();
                  }else if(action == "paired device."){
                    deletePairedDeviceFile();
                    _resetStoredPairedValue();
                  }else{

                  }

                },
              ),
              TextButton(
                child: const Text(
                  'No',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
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
                SizedBox(
                  height: 10.0,
                ),
                Card(
                  color: Colors.black,
                  child:Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        //height: SizeConfig.blockSizeVertical * 20,
                        width: SizeConfig.blockSizeHorizontal * 88,
                        child: Card(
                          color: Colors.grey[900],
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                              child: Column(
                                  children:[
                                    SizedBox(height:10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red, // background color
                                        foregroundColor: Colors.white, // text color
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        minimumSize: Size(SizeConfig.blockSizeHorizontal * 100, 40),
                                      ),
                                      onPressed: () {
                                        showConfirmationDialog(context, "all data.");
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          //mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: <Widget>[
                                            Icon(
                                              Icons.delete,
                                              color: Colors.white,
                                            ),
                                            Text(
                                              'Erase app data',
                                              style: TextStyle(fontSize: 16, color: Colors.white),
                                            ),
                                            Spacer(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(height:10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red, // background color
                                        foregroundColor: Colors.white, // text color
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        minimumSize: Size(SizeConfig.blockSizeHorizontal * 100, 40),
                                      ),
                                      onPressed: () {
                                        showConfirmationDialog(context, "paired device.");
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Row(
                                          //mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          children: <Widget>[
                                            Icon(
                                              Icons.delete,
                                              color: Colors.white,
                                            ),
                                            Text(
                                              'Delete preferred device ',
                                              style: TextStyle(fontSize: 16, color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ]
                              )

                          ),
                        ),

                      ),

                    ],
                  ),
                ),

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
                                                'About',
                                                style:
                                                    hPi4Global
                                                        .movecardTextStyle,
                                              ),
                                              //Icon(Icons.favorite_border, color: Colors.black),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Expanded(
                                                child: Text(
                                                  "HealthyPi Move is a wearable smartwatch that can be used for development of fitness and health related applications. "
                                                  "With this app for HealthyPi Move, you can now download trends and other data, manage your device and more.",
                                                  style:
                                                      hPi4Global
                                                          .movecardSubValue1TextStyle,
                                                  textAlign: TextAlign.justify,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Expanded(
                                                child: Text(
                                                  "We do not collect any personal data and there is no registration or cloud connection required.",
                                                  textAlign: TextAlign.justify,
                                                  style:
                                                      hPi4Global
                                                          .movecardSubValue1TextStyle,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 10.0),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Expanded(
                                                child: Text(
                                                  "Disclaimer:  This app and device are only for fitness and wellness purposes and NOT for medical or diagnostics use.",
                                                  textAlign: TextAlign.justify,
                                                  style:
                                                      hPi4Global
                                                          .movecardSubValue1TextStyle,
                                                ),
                                              ),
                                            ],
                                          ),

                                          SizedBox(height: 10.0),
                                          _getPoliciesTile(),
                                          ListTile(
                                            title: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  "v ${hPi4Global.hpi4AppVersion} ",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                Text(
                                                  "© ProtoCentral Electronics 2025",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
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

              ],
            ),
          ),
        ],
      ),
    );
  }
}
