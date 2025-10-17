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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            onDisconnectPressed();
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          },
        ),
        title: const Row(
          children: [
            Icon(Icons.show_chart, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Text(
              'Live View',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Device Connection Status Card
            Card(
              elevation: 2,
              color: const Color(0xFF2D2D2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[700]!.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.bluetooth_connected, color: Colors.green[400], size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.device.platformName.isNotEmpty 
                              ? widget.device.platformName 
                              : 'HealthyPi Move',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ready for streaming',
                            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[700]!.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green[700]!, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: Colors.green[400], shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text('Connected', style: TextStyle(color: Colors.green[400], fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Stream Selection Card
            Card(
              elevation: 2,
              color: const Color(0xFF2D2D2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Select Signal Type',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a signal to view in real-time',
                      style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 20),
                    // ECG Button
                    _buildStreamButton(
                      context: context,
                      icon: Symbols.cardiology,
                      label: 'ECG',
                      subtitle: 'Electrocardiogram signal',
                      streamType: 'ECG',
                    ),
                    const SizedBox(height: 12),
                    // Wrist PPG Button
                    _buildStreamButton(
                      context: context,
                      icon: Symbols.wrist,
                      label: 'Wrist PPG',
                      subtitle: 'Photoplethysmogram from wrist',
                      streamType: 'PPG',
                    ),
                    const SizedBox(height: 12),
                    // GSR Button
                    _buildStreamButton(
                      context: context,
                      icon: Symbols.eda,
                      label: 'GSR',
                      subtitle: 'Galvanic skin response',
                      streamType: 'GSR',
                    ),
                    const SizedBox(height: 12),
                    // Finger PPG Button
                    _buildStreamButton(
                      context: context,
                      icon: Symbols.show_chart,
                      label: 'Finger PPG',
                      subtitle: 'Photoplethysmogram from finger',
                      streamType: 'Finger PPG',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build a modern stream selection button
  Widget _buildStreamButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required String streamType,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[850],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          elevation: 0,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScrLiveStream(
                selectedType: streamType,
                device: widget.device,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hPi4Global.hpi4Color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: hPi4Global.hpi4Color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}
