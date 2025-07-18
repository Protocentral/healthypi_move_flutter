import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:screenshot/screenshot.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../globals.dart';
import '../home.dart';

class ECGHomePage extends StatefulWidget {
  final BluetoothDevice device;
  final List<int> logData;

  const ECGHomePage({super.key, required this.device, required this.logData});

  @override
  _ECGHomePageState createState() => _ECGHomePageState();
}

class _ECGHomePageState extends State<ECGHomePage> {
  ScreenshotController screenshotController = ScreenshotController();
  List<ChartData> ecgData = [];
  String pdfPath = '';

  //static const double samplingRate = 128.0; // samples per second

  @override
  void initState() {
    super.initState();
    print("Log data length: ${widget.logData.length}");
    ecgData = convertEcgToChartData(widget.logData);
  }

  List<List<ChartData>> getEcgSegments() {
    const int segmentLength = 768; // 6 seconds worth of data (6 * 128)

    List<List<ChartData>> segments = [];

    for (int i = 0; i < ecgData.length; i += segmentLength) {
      int end = min(i + segmentLength, ecgData.length);
      segments.add(ecgData.sublist(i, end));
    }

    return segments;
  }

  int convertLittleEndianToInteger(List<int> bytes) {
    // Convert 4-byte little-endian list to signed 32-bit integer
    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    return byteData.getInt32(0, Endian.little);

  }

  double convertToMillivolts(int rawValue) {
    const int maxAdcValue = 8388608; // 2^23 for 24-bit signed
   // const int maxAdcValue = 131072; // 2^17
    const double vRef = 1.0; // volts
    const double gain = 20.0; // amplifier gain

   return ((rawValue / maxAdcValue) * (vRef * 1000 / gain)); // in millivolts

    //const double adcRange = 131072.0;         // 2^(18 - 1) = 2^17
    //return (rawValue * 1000.0) / (adcRange * gain);
  }

  List<ChartData> convertEcgToChartData(List<int> rawBytes) {
    const double samplingRate = 128.0; // Hz
    List<ChartData> chartData = [];

    final int totalPoints = rawBytes.length ~/ 4;

    for (int i = 0; i < totalPoints; i++) {
      List<int> bytes = rawBytes.sublist(i * 4, i * 4 + 4);
      int value = convertLittleEndianToInteger(bytes);
      double value1 = convertToMillivolts(value);
      double timeInSeconds = i / samplingRate;

      // Optionally scale `value` to millivolts if needed (e.g., value / 1000)
      //chartData.add(ChartData(timeInSeconds, value.toDouble()));
      chartData.add(ChartData(timeInSeconds, value1));
    }

    return chartData;
  }

  /*Future<void> generatePDF() async {
    final Uint8List? chartImage = await screenshotController.capture();
    if (chartImage == null) return;

    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();

    page.graphics.drawString('30 seconds ECG',
      PdfStandardFont(PdfFontFamily.helvetica, 20),
      bounds: const Rect.fromLTWH(0, 0, 500, 30),
    );
    page.graphics.drawImage(
      PdfBitmap(chartImage),
      Rect.fromLTWH(0, 40, 500, 600),
    );
    final List<int> bytes = await document.save();
    document.dispose();

    await saveAndSharePdf(bytes, 'ecg_chart.pdf');
  }*/

  Future<void> generatePDF() async {
    final Uint8List? chartImage = await screenshotController.capture();
    if (chartImage == null) return;

    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();
    final PdfFont headerFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
    final PdfFont normalFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
    final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 10);

    double yOffset = 0;

    // Title
    page.graphics.drawString(
      'Healthypi Move - ECG',
      headerFont,
      bounds: Rect.fromLTWH(0, yOffset, page.getClientSize().width, 20),
    );
    yOffset += 30;

    // ECG Chart Image
    page.graphics.drawImage(
      PdfBitmap(chartImage),
      Rect.fromLTWH(0, yOffset, 500, 600),
    );
    yOffset += 620;

    // Footer Note
    const String footerNote =
        '25 mm/s, 10 mm/mV, 128.000 Hz, Healthypi Move (Watch)';

    page.graphics.drawString(
      footerNote,
      smallFont,
      bounds: Rect.fromLTWH(0, yOffset, page.getClientSize().width, 60),
    );

    final List<int> bytes = await document.save();
    document.dispose();

    await saveAndSharePdf(bytes, 'move_ecg.pdf');
  }

  Future<void> saveAndSharePdf(List<int> pdfContent, String fileName) async {
    Directory directory;
    if (Platform.isAndroid) {
      directory = Directory("/storage/emulated/0/Download");
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    final path = directory.path;
    await Directory(path).create(recursive: true);

    final file = File('$path/$fileName');
    await file.writeAsBytes(pdfContent);

    final result = await Share.shareXFiles([XFile(file.path)], text: "ECG Log File");

    if (result.status == ShareResultStatus.success) {
      print("File shared successfully!");
    }
  }

  Future<void> onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      // Show success snackbar or handle UI update here
    } catch (e, backtrace) {
      print("Disconnect error: $e");
      print("Backtrace: $backtrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            await onDisconnectPressed();
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          },
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(
              'assets/healthypi_move.png',
              fit: BoxFit.fitWidth,
              height: 30,
            ),
            IconButton(
              icon: Icon(Icons.file_download_rounded, color: Colors.white),
              onPressed: () async {
                generatePDF();
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Screenshot(
              controller: screenshotController,
              child: Column(
                children: getEcgSegments().map((segment) {
                  return SizedBox(
                    width: 500,
                    height: 200,
                    child: SfCartesianChart(
                      primaryXAxis: NumericAxis(
                        title: AxisTitle(text: 'Time (s)'),
                        minimum: segment.first.x,
                        maximum: segment.last.x,
                        interval: 1,
                      ),
                      primaryYAxis: NumericAxis(
                        title: AxisTitle(text: 'mV'),
                       // minimum: -4,
                       // maximum: 4,
                      ),
                      palette: <Color>[hPi4Global.hpi4Color],
                      series: <CartesianSeries>[
                        LineSeries<ChartData, double>(
                          dataSource: segment,
                          xValueMapper: (ChartData data, _) => data.x,
                          yValueMapper: (ChartData data, _) => data.y,
                          width: 1.5,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  final double x; // time in seconds
  final double y; // ECG value in mV
  ChartData(this.x, this.y);
}
