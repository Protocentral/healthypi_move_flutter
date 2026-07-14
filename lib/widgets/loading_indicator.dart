// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.text = ''});

  final String text;

  @override
  Widget build(BuildContext context) {
    var displayedText = text;

    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.black.withOpacity(0.7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _getLoadingIndicator(),
          _getHeading(context),
          _getText(displayedText),
        ],
      ),
    );
  }

  Padding _getLoadingIndicator() {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Container(
        child: SpinKitCircle(color: Colors.blue, size: 32.0),
        width: 32,
        height: 32,
      ),
    );
  }

  Widget _getHeading(context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Text(
        'Please wait…',
        style: TextStyle(color: Colors.white, fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }

  Text _getText(String displayedText) {
    return Text(
      displayedText,
      style: TextStyle(color: Colors.white, fontSize: 14),
      textAlign: TextAlign.center,
    );
  }
}
