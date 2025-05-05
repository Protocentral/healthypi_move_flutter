import 'package:flutter/material.dart';
import 'package:circular_countdown_timer/circular_countdown_timer.dart';

import '../home.dart';
import '../globals.dart';
import '../sizeConfig.dart';
import 'bptCalibrationPage1.dart';

class BPTCalibrationPage extends StatefulWidget {
  const BPTCalibrationPage({super.key});

  @override
  State<BPTCalibrationPage> createState() => _BPTCalibrationPageState();
}

class _BPTCalibrationPageState extends State<BPTCalibrationPage> {
  final int _duration = 300;
  final CountDownController _controller = CountDownController();

  @override
  void initState() {
    super.initState();
    _controller.restart(duration: _duration);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      appBar: AppBar(
        //backgroundColor: hPi4Global.hpi4Color,
        leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()))
        ),
        title: const Text(
          '',
          style: TextStyle(fontSize: 16),
        ),
      ),
      body:  Center(
        child: Column(children: <Widget>[
          SizedBox(
            height: SizeConfig.blockSizeVertical * 23,
            width: SizeConfig.blockSizeHorizontal * 95,
            child: Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.warning, color: Colors.yellow[300]),
                    Text('Critical Information',
                        style: TextStyle(fontSize: 24.0, color: hPi4Global.hpi4Color)),
                  ],
                ),
                Text("Calibration is very important and valid for 4 weeks."
                    "Any error in this protocol will cause incorrect reports, thereafter."
                    "Please use an FDA approved BP device for reference measurements.",
                    style: TextStyle(fontSize: 16.0, color: Colors.grey)),
              ],
            ),
          ),
        ),
          ),
          SizedBox(
            height: SizeConfig.blockSizeVertical * 20,
            width: SizeConfig.blockSizeHorizontal * 95,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.warning, color: Colors.yellow[300]),
                        Text('Resting 5 minutes',
                            style: TextStyle(fontSize: 24.0, color: hPi4Global.hpi4Color)),
                      ],
                    ),
                    Text("Please rest aleast 5 minutes before taking reference measurement.",
                        style: TextStyle(fontSize: 16.0, color: Colors.grey)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 2.0, 16.0, 2.0),
                      child: TextButton(
                        child: Text(
                          "Restart Timer",
                          style: TextStyle(fontSize: 20, color: hPi4Global.hpi4Color),
                        ),
                        onPressed: () async {
                          _controller.restart(duration: _duration);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
           SizedBox(
            height: SizeConfig.blockSizeVertical * 5,
          ),
          SizedBox(
            height: SizeConfig.blockSizeVertical * 30,
            width: SizeConfig.blockSizeHorizontal * 95,
            child: CircularCountDownTimer(
              duration: _duration,    // Countdown duration in Seconds.
              initialDuration: 0,    // Countdown initial elapsed Duration in Seconds.
              controller: _controller,   // Controls (i.e Start, Pause, Resume, Restart) the Countdown Timer.
              width: MediaQuery.of(context).size.width / 2,   // Width of the Countdown Widget.
              height: MediaQuery.of(context).size.height / 2,   // Height of the Countdown Widget.
              ringColor: Colors.grey[300]!,   // Ring Color for Countdown Widget.
              ringGradient: null,   // Ring Gradient for Countdown Widget.
              fillColor: hPi4Global.hpi4Color,   // Filling Color for Countdown Widget.
              fillGradient: null,    // Filling Gradient for Countdown Widget.
              backgroundColor: Colors.white,   // Background Color for Countdown Widget.
              backgroundGradient: null,    // Background Gradient for Countdown Widget.
              strokeWidth: 10.0,   // Border Thickness of the Countdown Ring.
              strokeCap: StrokeCap.round,   // Begin and end contours with a flat edge and no extension.
              textStyle: const TextStyle(
                fontSize: 32.0,
                color: hPi4Global.hpi4Color,
                fontWeight: FontWeight.bold,
              ),   // Text Style for Countdown Text.
              textFormat: CountdownTextFormat.MM_SS,  // Format for the Countdown Text.
              isReverse: false,       // Handles Countdown Timer (true for Reverse Countdown (max to 0), false for Forward Countdown (0 to max)).
              isReverseAnimation: false, // Handles Animation Direction (true for Reverse Animation, false for Forward Animation).
              isTimerTextShown: true,  // Handles visibility of the Countdown Text.
              autoStart: false,   // Handles the timer start.

              // This Callback will execute when the Countdown Starts.
              onStart: () {
                debugPrint('Countdown Started');
              },
              // This Callback will execute when the Countdown Ends.
              onComplete: () {
                debugPrint('Countdown Ended');
              },
              // This Callback will execute when the Countdown Changes.
              onChange: (String timeStamp) {
                debugPrint('Countdown Changed $timeStamp');
              },
              timeFormatterFunction: (defaultFormatterFunction, duration) {
                if (duration.inSeconds == 0) {
                  return "Start";
                } else {
                  return Function.apply(defaultFormatterFunction, [duration]);
                }
              },
            ),
          )
        ]),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 2.0, 16.0, 2.0),
            child: MaterialButton(
              minWidth: 200.0,
              color: hPi4Global.hpi4Color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BPTCalibrationPage1(),
                    ));
              },
              child: Row(
                children: <Widget>[
                  Text('Calibration',
                      style: new TextStyle(fontSize: 18.0, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}