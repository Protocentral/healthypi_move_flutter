// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/cupertino.dart';

class SizeConfig {
  static late double screenWidth;
  static late double screenHeight;
  static late double blockSizeHorizontal;
  static late double blockSizeVertical;

  void init(BuildContext context) {
     MediaQueryData mediaQueryData = MediaQuery.of(context);
     screenWidth = mediaQueryData.size.width;
     screenHeight = mediaQueryData.size.height;
     blockSizeHorizontal = screenWidth / 100;
     blockSizeVertical = screenHeight / 100;
  }
}