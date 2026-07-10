import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_html_css/simple_html_css.dart';

import '../globals.dart';

void showTermsDialog(BuildContext context) async {
  String htmlContent = await rootBundle.loadString(
    'assets/termsAndConditions.html',
  );

  showDialog(
    context: context,
    builder: (BuildContext context) {
      // return object of type Dialog
      return AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          "Terms of Use",
          style: TextStyle(
            fontSize: 16,
            color: hPi4Global.hpi4AppBarIconsColor,
          ),
        ),
        content: SingleChildScrollView(
          child: Container(
            color: Colors.black,
            padding: EdgeInsets.all(16.0),
            child: Builder(
              builder: (context) {
                return RichText(
                  text: HTML.toTextSpan(
                    context,
                    htmlContent,
                    linksCallback: (link) {
                      print("You clicked on $link");
                    },

                    // as name suggests, optionally set the default text style
                    defaultTextStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    overrideStyle: {
                      //"h1": TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold),
                      "strong": TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                      //"p": TextStyle(fontSize: 12.0, color: Colors.black),
                    },
                  ),
                );
              },
            ),
          ),
        ),
        actions: <Widget>[
          // usually buttons at the bottom of the dialog
          TextButton(
            child: Text("Close", style: hPi4Global.eventsWhite),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
