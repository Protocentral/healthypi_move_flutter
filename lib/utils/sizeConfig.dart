import 'package:flutter/cupertino.dart';

class SizeConfig {
  static late MediaQueryData _mediaQueryData;
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