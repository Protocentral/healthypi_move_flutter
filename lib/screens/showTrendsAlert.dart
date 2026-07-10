import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../globals.dart';
import '../utils/sizeConfig.dart';

Widget displayValuesAlert() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Expanded(
        child: Text("These values should not be used to diagnose or monitor medical conditions.",
          style:
          hPi4Global.movecardSubValueRedTextStyle,
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

 launchURL(String showURL) async {
  String url = showURL;
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url));
  } else {
    throw 'Could not launch $url';
  }
}