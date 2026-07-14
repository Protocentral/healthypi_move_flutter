// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:move/screens/scr_stream_selection.dart';
import 'package:fl_chart/fl_chart.dart';

import '../globals.dart';
import '../utils/connection_manager.dart';
import '../utils/sizeConfig.dart';

class ScrLiveStream extends StatefulWidget {
  ScrLiveStream({
    Key? key,
    required this.selectedType,
    required this.deviceId,
    this.deviceName = 'HealthyPi Move',
  }) : super();

  final String selectedType;
  final String deviceId;
  final String deviceName;

  @override
  _ScrLiveStreamState createState() => _ScrLiveStreamState();
}

class _ScrLiveStreamState extends State<ScrLiveStream> {
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  final ecgLineData = <FlSpot>[];
  final ppgLineData = <FlSpot>[];
  final gsrLineData = <FlSpot>[];
  final fingerPPGLineData = <FlSpot>[];

  double ecgDataCounter = 0;
  double ppgDataCounter = 0;
  double gsrDataCounter = 0;
  double fingerPPGDataCounter = 0;

  final ConnectionManager _conn = ConnectionManager.instance;

  /// The (service, characteristic) UUIDs for the selected signal.
  String? _service;
  String? _characteristic;
  StreamSubscription<Uint8List>? _streamSubscription;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _startStreaming();
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

    _closeStream();

    super.dispose();
  }

  /// Resolve the (service, characteristic) for the selected signal, subscribe
  /// via the ConnectionManager, and start parsing values into chart data.
  void _startStreaming() {
    switch (widget.selectedType) {
      case "ECG":
        _service = hPi4Global.UUID_ECG_SERVICE;
        _characteristic = hPi4Global.UUID_ECG_CHAR;
        break;
      case "PPG":
        _service = hPi4Global.UUID_SERV_PPG;
        _characteristic = hPi4Global.UUID_CHAR_PPG;
        break;
      case "GSR":
        _service = hPi4Global.UUID_ECG_SERVICE;
        _characteristic = hPi4Global.UUID_GSR_CHAR;
        break;
      case "Finger PPG":
        _service = hPi4Global.UUID_SERV_PPG;
        _characteristic = hPi4Global.UUID_CHAR_FINGERPPG;
        break;
      default:
        return;
    }

    _streamSubscription = _conn.subscribe(_service!, _characteristic!).listen(
      _onValue,
      onError: (Object error) {
        debugPrint("Error while monitoring data characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  void _onValue(Uint8List value) {
    // Copy into a fresh, offset-0 buffer before reinterpreting as Int32/Uint32.
    // universal_ble delivers Uint8Lists that are views into a larger buffer
    // (non-zero offsetInBytes / oversized buffer), so reading `value.buffer`
    // directly would be misaligned. This matches the original FBP parsing
    // (`Uint8List.fromList(value).buffer.as…List()`), host-endian (little).
    final bytes = Uint8List.fromList(value);
    switch (widget.selectedType) {
      case "ECG":
        final list = bytes.buffer.asInt32List();
        for (final element in list) {
          setStateIfMounted(() =>
              ecgLineData.add(FlSpot(ecgDataCounter++, element.toDouble())));
          if (ecgDataCounter >= 128 * 6) ecgLineData.removeAt(0);
        }
        break;
      case "PPG":
        final list = bytes.buffer.asUint32List();
        for (final element in list) {
          setStateIfMounted(() =>
              ppgLineData.add(FlSpot(ppgDataCounter++, element.toDouble())));
          if (ppgDataCounter >= 64 * 3) ppgLineData.removeAt(0);
        }
        break;
      case "GSR":
        final list = bytes.buffer.asInt32List();
        for (final element in list) {
          setStateIfMounted(() =>
              gsrLineData.add(FlSpot(gsrDataCounter++, element.toDouble())));
          if (gsrDataCounter >= 128 * 6) gsrLineData.removeAt(0);
        }
        break;
      case "Finger PPG":
        final list = bytes.buffer.asUint32List();
        for (final element in list) {
          setStateIfMounted(() => fingerPPGLineData
              .add(FlSpot(fingerPPGDataCounter++, element.toDouble())));
          if (fingerPPGDataCounter >= 64 * 3) fingerPPGLineData.removeAt(0);
        }
        break;
    }
  }

  void _closeStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    final s = _service, c = _characteristic;
    if (s != null && c != null) {
      _conn.unsubscribe(s, c).catchError((_) {});
    }
  }

  Widget sizedBoxForCharts() {
    return SizedBox(height: SizeConfig.blockSizeVertical * 2);
  }

  Widget displayHealthyPiMoveCharts() {
    if (widget.selectedType == "ECG") {
      return Column(children: [buildChart(50, 90, ecgLineData, Colors.green)]);
    } else if (widget.selectedType == "PPG") {
      return Column(children: [buildChart(50, 90, ppgLineData, Colors.green)]);
    } else if (widget.selectedType == "GSR") {
      return Column(children: [buildChart(50, 90, gsrLineData, Colors.green)]);
    } else if (widget.selectedType == "Finger PPG") {
      return Column(
        children: [buildChart(50, 90, fingerPPGLineData, Colors.green)],
      );
    } else {
      return Container();
    }
  }

  LineChartBarData currentLine(List<FlSpot> points, Color plotcolor) {
    return LineChartBarData(
      spots: points,
      dotData: FlDotData(show: false),
      gradient: LinearGradient(
        colors: [plotcolor, plotcolor],
      ),
      barWidth: 3,
      isCurved: false,
    );
  }

  buildChart(
    int vertical,
    int horizontal,
    List<FlSpot> source,
    Color plotColor,
  ) {
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
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [currentLine(source, plotColor)],
        ),
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
          child: Column(children: <Widget>[displayHealthyPiMoveCharts()]),
        ),
      ),
    );
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: Colors.black,
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _closeStream();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ScrStreamsSelection(
                  deviceId: widget.deviceId,
                  deviceName: widget.deviceName,
                ),
              ),
            );
          },
        ),
        title: Row(
          children: [
            Icon(
              widget.selectedType == "ECG"
                  ? Icons.favorite
                  : widget.selectedType == "PPG"
                      ? Icons.monitor_heart
                      : widget.selectedType == "GSR"
                          ? Icons.water_drop
                          : Icons.show_chart,
              color: hPi4Global.hpi4Color,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              widget.selectedType,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Device status indicator
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.deviceName.isNotEmpty
                          ? widget.deviceName
                          : 'HealthyPi Move',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              buildCharts(),
            ],
          ),
        ),
      ),
    );
  }
}
