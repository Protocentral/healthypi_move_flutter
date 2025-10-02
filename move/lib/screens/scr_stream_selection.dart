import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';
import '../utils/sizeConfig.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';
import '../home.dart';
import '../utils/snackbar.dart';
import 'scr_live_stream.dart';

class ScrStreamsSelection extends StatefulWidget {
  const ScrStreamsSelection({super.key, required this.device});

  final BluetoothDevice device;

  @override
  _ScrStreamsSelectionState createState() => _ScrStreamsSelectionState();
}

class _ScrStreamsSelectionState extends State<ScrStreamsSelection> {
  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {});
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

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.c,
        prettyException("Disconnect Error:", e),
        success: false,
      );
      print("$e backtrace: $backtrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            onDisconnectPressed();
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          },
        ),
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
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.max,
                children: <Widget>[
                  SizedBox(width: 10.0),
                  Text(
                    "Connected to: " + widget.device.remoteId.toString(),
                    style: TextStyle(fontSize: 16, color: Colors.green),
                  ),
                  SizedBox(width: 10.0),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    //height: SizeConfig.blockSizeVertical * 20,
                    width: SizeConfig.blockSizeHorizontal * 88,
                    child: Card(
                      color: const Color(0xFF2D2D2D),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(
                                  ' Select signal ',
                                  style: hPi4Global.movecardTextStyle,
                                ),
                                //Icon(Icons.favorite_border, color: Colors.black),
                              ],
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ScrLiveStream(
                                          selectedType: "ECG",
                                          device: widget.device,
                                        ),
                                  ),
                                );
                              },

                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  //mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Symbols.cardiology,
                                      color: Colors.white,
                                    ),
                                    const Text(
                                      ' ECG ',
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ScrLiveStream(
                                          selectedType: "PPG",
                                          device: widget.device,
                                        ),
                                  ),
                                );
                              },

                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  //mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(Symbols.wrist, color: Colors.white),
                                    const Text(
                                      'Wrist PPG ',
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ScrLiveStream(
                                          selectedType: "GSR",
                                          device: widget.device,
                                        ),
                                  ),
                                );
                              },

                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  //mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(Symbols.eda, color: Colors.white),
                                    const Text(
                                      ' GSR ',
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ScrLiveStream(
                                          selectedType: "Finger PPG",
                                          device: widget.device,
                                        ),
                                  ),
                                );
                              },

                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  //mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Symbols.show_chart,
                                      color: Colors.white,
                                    ),
                                    const Text(
                                      ' Finger PPG ',
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
            ),
          ],
        ),
      ),
    );
  }
}
