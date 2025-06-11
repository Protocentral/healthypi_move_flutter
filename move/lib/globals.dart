import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class HourlyTrend {
  final DateTime hour;
  final double min;
  final double max;
  final double avg;

  HourlyTrend({
    required this.hour,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class WeeklyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  WeeklyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class MonthlyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  MonthlyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class ActivityDailyTrend {
  final DateTime date;
  final int steps;

  ActivityDailyTrend({required this.date, required this.steps});
}

class ActivityWeeklyTrend {
  final DateTime date;
  final int steps;

  ActivityWeeklyTrend({required this.date, required this.steps});
}

class ActivityMonthlyTrend {
  final DateTime date;
  final int steps;

  ActivityMonthlyTrend({required this.date, required this.steps});
}

class SpO2DailyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2DailyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class SpO2WeeklyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2WeeklyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

/// Represents a monthly SpO2 trend with min, max, and average values.
class SpO2MonthlyTrend {
  final DateTime date;
  final double min;
  final double max;
  final double avg;

  SpO2MonthlyTrend({
    required this.date,
    required this.min,
    required this.max,
    required this.avg,
  });
}

class hPi4Global {
  static const String UUID_SERV_DIS = "0000180a-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_BATT = "0000180f-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_HR = "0000180d-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_SPO2 = "00001822-0000-1000-8000-00805f9b34fb";

  static const String UUID_SERV_PPG = "cd5c7491-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_CHAR_FINGERPPG =
      "cd5ca86f-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_CHAR_PPG = "cd5c1525-4448-7db8-ae4c-d1da8cba36d0";

  static const String UUID_SERVICE_CMD = "01bf7492-970f-8d96-d44d-9023c47faddc";
  static const String UUID_CHAR_CMD = "01bf1528-970f-8d96-d44d-9023c47faddc";
  static const String UUID_CHAR_CMD_DATA =
      "01bf1527-970f-8d96-d44d-9023c47faddc";

  static const String UUID_ECG_SERVICE = "00001122-0000-1000-8000-00805f9b34fb";
  static const String UUID_ECG_CHAR = "00001424-0000-1000-8000-00805f9b34fb";
  static const String UUID_GSR_CHAR = "babe4a4c-7789-11ed-a1eb-0242ac120002";

  static const String UUID_SERV_STREAM_2 =
      "cd5c7491-4448-7db8-ae4c-d1da8cba36d0";
  static const String UUID_STREAM_2 = "01bf1525-970f-8d96-d44d-9023c47faddc";

  static const String UUID_CHAR_HR = "00002a37-0000-1000-8000-00805f9b34fb";
  static const String UUID_SPO2_CHAR = "00002a5e-0000-1000-8000-00805f9b34fb";
  static const String UUID_TEMP_CHAR = "00002a6e-0000-1000-8000-00805f9b34fb";

  static const String UUID_CHAR_ACT = "000000a2-0000-1000-8000-00805f9b34fb";
  static const String UUID_CHAR_BATT = "00002a19-0000-1000-8000-00805f9b34fb";
  static const String UUID_DIS_FW_REVISION =
      "00002a26-0000-1000-8000-00805f9b34fb";
  static const String UUID_SERV_HEALTH_THERM =
      "00001809-0000-1000-8000-00805f9b34fb";

  static const String UUID_SERV_SMP = "8d53dc1d-1db7-4cd3-868b-8a527460aa84";
  static const String UUID_CHAR_SMP = "da2e7828-fbce-4e01-ae9e-261174997c48";

  static const int HPI_TREND_TYPE_HR = 0x01;
  static const int HPI_TREND_TYPE_SPO2 = 0x02;
  static const int HPI_TREND_TYPE_TEMP = 0x03;
  static const int HPI_TREND_TYPE_ACTIVITY = 0x04;
  static const int HPI_TREND_TYPE_ECG = 0x05;

  static const List<int> sessionLogIndex = [0x50];
  static const List<int> sessionFetchLogFile = [0x51];
  static const List<int> sessionLogDelete = [0x52];
  static const List<int> sessionLogWipeAll = [0x53];
  static const List<int> getSessionCount = [0x54];
  static const List<int> getFWVersion = [0x55];

  static const List<int> ECGLogCount = [0x30];
  static const List<int> ECGLogIndex = [0x31];
  static const List<int> FetchECGLogFile = [0x32];
  static const List<int> ECGLogDelete = [0x33];
  static const List<int> ECGLogWipeAll = [0x34];

  static const List<int> HrTrend = [0x01];
  static const List<int> Spo2Trend = [0x02];
  static const List<int> TempTrend = [0x03];
  static const List<int> ActivityTrend = [0x04];

  static const List<int> ECGRecord = [0x10];

  static const int CES_CMDIF_TYPE_LOG_IDX = 0x05;
  static const int CES_CMDIF_TYPE_DATA = 0x02;
  static const int CES_CMDIF_TYPE_CMD_RSP = 0x06;

  static const List<int> WISER_CMD_SET_DEVICE_TIME = [0x41];

  static const List<int> StartBPTCal = [0x61];
  static const List<int> SetBPTCalMode = [0x60];
  static const List<int> EndBPTCal = [0x62];

  static const TextStyle eventStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static const TextStyle cardTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static const TextStyle cardValueTextStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle movecardTextStyle = TextStyle(
    fontSize: 16,
    color: Colors.white,
  );
  static const TextStyle movecardValueTextStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle moveValueTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle moveValueGreenTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.green,
  );

  static const TextStyle moveValueOrangeTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.orange,
  );

  static const TextStyle moveValueBlueTextStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.blue,
  );

  static const TextStyle movecardSubValueTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle movecardSubValueGreenTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.green,
  );

  static const TextStyle movecardSubValueOrangeTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.orange,
  );

  static const TextStyle movecardSubValueBlueTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.blue,
  );

  static const TextStyle movecardSubValue1TextStyle = TextStyle(
    fontSize: 14,
    color: Colors.white,
  );

  static const TextStyle movecardSubValueRedTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.red,
  );

  static const TextStyle movecardSubValue2TextStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle subValueWhiteTextStyle = TextStyle(
    fontSize: 12,
    color: Colors.white,
  );

  static const TextStyle cardBlackTextStyle = TextStyle(
    fontSize: 20,
    color: Colors.black,
  );

  static const TextStyle cardWhiteTextStyle = TextStyle(
    fontSize: 20,
    color: Colors.white,
  );

  static const TextStyle eventsWhite = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  //static const Color hpi4Color = Color(0xFFFFD551);

  static const Color hpi4Color = Color(0xFFFF6D00);

  static const Color hpi4AppBarColor = Colors.black;

  static const Color hpi4AppBarIconsColor = Colors.white;

  static const Color oldHpi4Color = Color(0xFF125871);

  static const TextStyle scrHeadStyle = TextStyle(
    fontSize: 24,
    color: Colors.white,
    letterSpacing: 1,
  );

  static const TextStyle HeadStyle = TextStyle(
    fontSize: 24,
    color: Colors.black,
    letterSpacing: 0.5,
  );

  static Color appBarColor = Colors.black38;
  static Color appBackgroundColor = Colors.black;

  static String hpi4AppVersion = "";
  static String hpi4AppBuildNumber = "";
}

/// Sample time series data type.
class HRSeries {
  final DateTime time;
  final int hr;

  HRSeries(this.time, this.hr);
}

/// Sample linear data type.
class ECGPoint {
  final int time;
  final double voltage;
  //final String labelValue;
  ECGPoint(this.time, this.voltage);
}

class BatteryLevelPainter extends CustomPainter {
  final int _batteryLevel;
  final int _batteryState;

  BatteryLevelPainter(this._batteryLevel, this._batteryState);

  @override
  void paint(Canvas canvas, Size size) {
    Paint getPaint({
      Color color = Colors.black,
      PaintingStyle style = PaintingStyle.stroke,
    }) {
      return Paint()
        ..color = color
        ..strokeWidth = 1.0
        ..style = style;
    }

    final double batteryRight = size.width - 4.0;

    final RRect batteryOutline = RRect.fromLTRBR(
      0.0,
      0.0,
      batteryRight,
      size.height,
      Radius.circular(3.0),
    );

    // Battery body
    canvas.drawRRect(batteryOutline, getPaint());

    // Battery nub
    canvas.drawRect(
      Rect.fromLTWH(batteryRight, (size.height / 2.0) - 5.0, 4.0, 10.0),
      getPaint(style: PaintingStyle.fill),
    );

    // Fill rect
    canvas.clipRect(
      Rect.fromLTWH(
        0.0,
        0.0,
        batteryRight * _batteryLevel / 100.0,
        size.height,
      ),
    );

    Color indicatorColor;
    if (_batteryLevel < 15) {
      indicatorColor = Colors.red;
    } else if (_batteryLevel < 30) {
      indicatorColor = Colors.orange;
    } else {
      indicatorColor = Colors.green;
    }

    canvas.drawRRect(
      RRect.fromLTRBR(
        0.5,
        0.5,
        batteryRight - 0.5,
        size.height - 0.5,
        Radius.circular(3.0),
      ),
      getPaint(style: PaintingStyle.fill, color: indicatorColor),
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    final BatteryLevelPainter old = oldDelegate as BatteryLevelPainter;
    return old._batteryLevel != _batteryLevel ||
        old._batteryState != _batteryState;
  }
}

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
