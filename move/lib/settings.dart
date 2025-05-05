import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'screens/showTerms.dart';
import 'screens/showPrivacy.dart';

import 'globals.dart';
import 'sizeConfig.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

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
                minimumSize: Size(SizeConfig.blockSizeHorizontal*100, 40),
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
                        'protocentral.com', style: TextStyle(fontSize: 14, color:Colors.white)
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
                      style: TextStyle(fontSize: 16, color: hPi4Global.hpi4AppBarIconsColor),
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
                      style: TextStyle(fontSize: 16, color: hPi4Global.hpi4AppBarIconsColor),
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
                                SizedBox(
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
                                                Text('About',
                                                    style: hPi4Global.movecardTextStyle),
                                                //Icon(Icons.favorite_border, color: Colors.black),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Expanded(
                                                  child: Text(
                                                    "HealthyPi Move is a wearable smartwatch that can be used for development of fitness and health related applications. "
                                                        "With this app for HealthyPi Move, you can now download trends and other data, manage your device and more.",
                                                    style:hPi4Global.movecardSubValue1TextStyle,
                                                    textAlign: TextAlign.justify,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Expanded(
                                                  child: Text(
                                                    "We do not collect any personal data and there is no registration or cloud connection required.",
                                                    textAlign: TextAlign.justify,
                                                    style:hPi4Global.movecardSubValue1TextStyle,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Expanded(
                                                  child: Text(
                                                    "Disclaimer:  This app and device are only for fitness and wellness purposes and NOT for medical or diagnostics use.",
                                                    textAlign: TextAlign.justify,
                                                    style:hPi4Global.movecardSubValue1TextStyle,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            SizedBox(
                                              height: 10.0,
                                            ),
                                            _getPoliciesTile(),
                                            ListTile(
                                              title: Column(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    "v ${hPi4Global.hpi4AppVersion} ",
                                                    style: TextStyle(fontSize: 12,color: Colors.white ),
                                                  ),
                                                  Text(
                                                    "© ProtoCentral Electronics 2020",
                                                    style: TextStyle(fontSize: 12,color: Colors.white),
                                                  ),
                                                ],
                                              ),
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
