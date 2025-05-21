import 'dart:async';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:move/screens/streamSelectionPage.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../globals.dart';
import '../home.dart';
import '../sizeConfig.dart';
import 'ble_ctlr.dart';

class WaveFormsPage extends StatefulWidget {
  WaveFormsPage({
    Key? key,
    required this.selectedType,
    required this.device,
  }) : super();

  final String selectedType;
  final BluetoothDevice device;

  @override
  _WaveFormsPageState createState() => _WaveFormsPageState();
}

class _WaveFormsPageState extends State<WaveFormsPage> {
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  Key key = UniqueKey();

  final ecgLineData = <FlSpot>[];
  final ppgLineData = <FlSpot>[];
  final gsrLineData = <FlSpot>[];
  final fingerPPGLineData = <FlSpot>[];

  double ecgDataCounter = 0;
  double ppgDataCounter = 0;
  double gsrDataCounter = 0;
  double fingerPPGDataCounter = 0;
  double globalTemp = 0;

  BluetoothService? ECGGSRService;
  BluetoothService? PPGFINGERPPGService;

  BluetoothCharacteristic? ECGCharacteristic;
  BluetoothCharacteristic? PPGCharacteristic;
  BluetoothCharacteristic? GSRCharacteristic;
  BluetoothCharacteristic? FingerPPGCharacteristic;

  late StreamSubscription<List<int>> streamECGSubscription;
  late StreamSubscription<List<int>> streamPPGSubscription;
  late StreamSubscription<List<int>> streamGSRSubscription;
  late StreamSubscription<List<int>> streamFingerPPGSubscription;

  bool listeningECGStream = false;
  bool listeningPPGStream = false;
  bool listeningGSRStream = false;
  bool listeningFingerPPGStream = false;
  bool startStreaming = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
    });
  }

  @override
  dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);

    ecgLineData.clear();
    ppgLineData.clear();
    gsrLineData.clear();
    fingerPPGLineData.clear();

    closeAllStreams();

    super.dispose();
  }

  subscribeToChar(BluetoothDevice deviceName) async {
    List<BluetoothService> services = await deviceName.discoverServices();
    if(widget.selectedType == "ECG"){
      // Find a service and characteristic by UUID
      for (BluetoothService service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_ECG_SERVICE)) {
          ECGGSRService = service;
          for (BluetoothCharacteristic characteristic
          in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_ECG_CHAR)) {
              ECGCharacteristic = characteristic;
              await ECGCharacteristic?.setNotifyValue(true);
              break;
            }
          }
        }
      }

    }else if(widget.selectedType == "PPG"){
      for (BluetoothService service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_SERV_PPG)) {
          PPGFINGERPPGService = service;
          for (BluetoothCharacteristic characteristic
          in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_PPG)) {
              PPGCharacteristic = characteristic;
              await PPGCharacteristic?.setNotifyValue(true);
              break;
            }
          }
        }
      }

    } else if(widget.selectedType == "GSR"){
      for (BluetoothService service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_ECG_SERVICE)) {
          ECGGSRService = service;
          for (BluetoothCharacteristic characteristic
          in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_GSR_CHAR)) {
              GSRCharacteristic = characteristic;
              await GSRCharacteristic?.setNotifyValue(true);
              break;
            }
          }
        }
      }

    } else if(widget.selectedType == "Finger PPG"){
      for (BluetoothService service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_SERV_PPG)) {
          PPGFINGERPPGService = service;
          for (BluetoothCharacteristic characteristic
          in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_FINGERPPG)) {
              FingerPPGCharacteristic = characteristic;
              await FingerPPGCharacteristic ?.setNotifyValue(true);
              break;
            }
          }
        }
      }

    }else{

    }

  }

  void dataFormatBasedOnBoardsSelection() async {
    if(widget.selectedType == "ECG"){
      startECG32Listening();
    }
    else if(widget.selectedType == "PPG"){
      startPPG32Listening();
    }
    else if(widget.selectedType == "GSR"){
      startGSR32Listening();
    }
    else if(widget.selectedType == "Finger PPG"){
      startFingerPPG32Listening();
    }else{

    }
  }

  void closeAllStreams() async {
    if (listeningECGStream == true) {
      await streamECGSubscription.cancel();
    }

    if (listeningPPGStream == true) {
      await streamPPGSubscription.cancel();
    }

    if (listeningGSRStream == true) {
      await streamGSRSubscription.cancel();
    }

    if (listeningFingerPPGStream == true) {
      await streamFingerPPGSubscription.cancel();
    }
  }

  void startECG32Listening() async {
    print("AKW: Started listening to stream");
    listeningECGStream = true;

    streamECGSubscription = ECGCharacteristic!.onValueReceived.listen((value) async
    {
        ByteData ecgByteData = Uint8List.fromList(value).buffer.asByteData(0);
        Int32List ecgList = ecgByteData.buffer.asInt32List();

        ecgList.forEach((element) {
          setStateIfMounted(() {
            ecgLineData.add(FlSpot(ecgDataCounter++, (element.toDouble())));
          });

          if (ecgDataCounter >= 128 * 6) {
            ecgLineData.removeAt(0);
          }
        });
      },
      onError: (Object error) {
      // Handle a possible error
      print("Error while monitoring data characteristic \n$error");
    },
    cancelOnError: true,
      );
  }

  void startPPG32Listening() async {
    print("AKW: Started listening to ppg stream");
    listeningPPGStream = true;

    streamPPGSubscription = PPGCharacteristic!.onValueReceived.listen((value) async
    {
        // print("AKW: Rx PPG: " + event.length.toString());
        ByteData ppgByteData = Uint8List.fromList(value).buffer.asByteData(0);
        Uint32List ppgList = ppgByteData.buffer.asUint32List();

        ppgList.forEach((element) {
          setStateIfMounted(() {
            ppgLineData.add(FlSpot(ppgDataCounter++, (element.toDouble())));
          });

          if (ppgDataCounter >= 128 * 3) {
            ppgLineData.removeAt(0);
          }
        });
      },
      onError: (Object error) {
        // Handle a possible error
        print("Error while monitoring data characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  void startGSR32Listening() async {
    print("AKW: Started listening to GSR stream");
    listeningGSRStream = true;

    streamGSRSubscription = GSRCharacteristic!.onValueReceived.listen((value) async
    {
      ByteData gsrByteData = Uint8List.fromList(value).buffer.asByteData(0);
      Int32List ecgList = gsrByteData.buffer.asInt32List();

      ecgList.forEach((element) {
        setStateIfMounted(() {
          gsrLineData.add(FlSpot(gsrDataCounter++, (element.toDouble())));
        });

        if (gsrDataCounter >= 128 * 6) {
          gsrLineData.removeAt(0);
        }
      });
    },
      onError: (Object error) {
        // Handle a possible error
        print("Error while monitoring data characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  void startFingerPPG32Listening() async {
    print("AKW: Started listening to Finger ppg stream");
    listeningFingerPPGStream = true;

    streamFingerPPGSubscription = FingerPPGCharacteristic!.onValueReceived.listen((value) async
    {
      // print("AKW: Rx PPG: " + event.length.toString());
      ByteData fingerppgByteData = Uint8List.fromList(value).buffer.asByteData(0);
      Uint32List ppgList = fingerppgByteData.buffer.asUint32List();

      ppgList.forEach((element) {
        setStateIfMounted(() {
          fingerPPGLineData.add(FlSpot(fingerPPGDataCounter++, (element.toDouble())));
        });

        if (fingerPPGDataCounter >= 128 * 3) {
          fingerPPGLineData.removeAt(0);
        }
      });
    },
      onError: (Object error) {
        // Handle a possible error
        print("Error while monitoring data characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  Widget sizedBoxForCharts() {
    return SizedBox(
      height: SizeConfig.blockSizeVertical * 2,
    );
  }


  Widget displayHealthyPiMoveCharts() {
    if(widget.selectedType == "ECG"){
      return Column(
        children: [
          buildChart(50, 70, ecgLineData, Colors.green),
        ],
      );
    }
    else if(widget.selectedType == "PPG"){
      return Column(
        children: [
          buildChart(50, 70, ppgLineData, Colors.green),
        ],
      );
    }
    else if(widget.selectedType == "GSR"){
      return Column(
        children: [
          buildChart(50, 70, gsrLineData, Colors.green),
        ],
      );
    }
    else if(widget.selectedType == "Finger PPG"){
      return Column(
        children: [
          buildChart(50, 70, fingerPPGLineData, Colors.green),
        ],
      );
    }else{
      return Container();
    }
  }

  Widget displayDeviceName() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(children: [
            Text(
              "Connected: " +
                  widget.selectedType +
                  " ( " +
                  widget.device.name +
                  " )",
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  LineChartBarData currentLine(List<FlSpot> points, Color plotcolor) {
    return LineChartBarData(
      spots: points,
      dotData: FlDotData(
        show: false,
      ),
      gradient: LinearGradient(
        colors: [plotcolor, plotcolor],
        //stops: const [0.1, 1.0],
      ),
      barWidth: 3,
      isCurved: false,
    );
  }

  buildChart(int vertical, int horizontal, List<FlSpot> source, Color plotColor) {
    return Container(
      height: SizeConfig.blockSizeVertical * vertical,
      width: SizeConfig.blockSizeHorizontal * horizontal,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(enabled: false),
          clipData: FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: false,
          ),
          borderData: FlBorderData(
            show: false,
            //border: Border.all(color: const Color(0xff37434d)),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            currentLine(source, plotColor),
          ],
        ),
        //swapAnimationDuration: Duration.zero,
        duration: Duration.zero,

      ),
    );
  }


  Widget buildCharts() {
    return Expanded(
        child: Container(
            color: Colors.black,
            child: Padding(
              padding: const EdgeInsets.all(0.0),
              child: Column(
                children: <Widget>[
                  displayHealthyPiMoveCharts()
                ],
              ),
            )));
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  String debugText = "Console Inited...";

  Widget displayDisconnectButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MaterialButton(
        minWidth: 100.0,
        color: Colors.red,
        child: Row(
          children: <Widget>[
            Text('Close',
                style: new TextStyle(fontSize: 18.0, color: Colors.white)),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        onPressed: () async {
          closeAllStreams();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => LiveStreamsOptions(device: widget.device)),
          );
        },
      ),
    );
  }


  Widget StartAndStopButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: MaterialButton(
        minWidth: 50.0,
        color: startStreaming ? Colors.red : Colors.green,
        child: Row(
          children: <Widget>[
            startStreaming
                ? Text('Stop',
                style: new TextStyle(fontSize: 16.0, color: Colors.white))
                : Text('Start',
                style: new TextStyle(fontSize: 16.0, color: Colors.white)),
          ],
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        onPressed: () async {
          subscribeToChar(widget.device);

          if (startStreaming == false) {
            setState(() {
              startStreaming = true;
            });
            dataFormatBasedOnBoardsSelection();
          } else {
            closeAllStreams();
            ecgLineData.removeAt(0);
            ppgLineData.removeAt(0);
            gsrLineData.removeAt(0);
            fingerPPGLineData.removeAt(0);
            setState(() {
              startStreaming = false;
            });
          }
        },
      ),
    );
  }

  Widget displayAppBarButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Column(children: <Widget>[
          Image.asset(
            'assets/healthypi_move.png',
            fit: BoxFit.fitWidth,
            height: 30,
          ),
          displayDeviceName(),
        ]),
        StartAndStopButton(),
        displayDisconnectButton(),
      ],
    );
  }

  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
        title: displayAppBarButtons(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              buildCharts(),
              //showPages(),
            ],
          ),
        ),
      ),
    );
  }
}