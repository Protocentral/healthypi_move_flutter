import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/screens/scr_device_scan.dart';
import 'package:move/screens/scr_device_settings.dart';
import 'package:move/screens/scr_ecg_recordings.dart';
import 'package:move/screens/scr_gsr_recordings.dart';
import 'package:move/screens/scr_hrv_recordings.dart';
import 'package:move/screens/scr_ppg_recordings.dart';
import 'package:move/utils/extra.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';
import '../utils/sizeConfig.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';
import '../home.dart';
import '../utils/snackbar.dart';

class ScrRecordingsSelection extends StatefulWidget {
  const ScrRecordingsSelection({super.key});

  @override
  _ScrRecordingsSelectionState createState() => _ScrRecordingsSelectionState();
}

class _ScrRecordingsSelectionState extends State<ScrRecordingsSelection> {
  String selectedOption = "sync";

  @override
  void initState() {
    super.initState();
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }


  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: hPi4Global.hpi4AppBarColor,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/healthypi_move.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text(
              'Device',
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Paired Device Info Card
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paired Device',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<DeviceInfo?>(
                    future: DeviceManager.getPairedDevice(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(
                              color: hPi4Global.hpi4Color,
                            ),
                          ),
                        );
                      }

                      final deviceInfo = snapshot.data;

                      if (deviceInfo == null) {
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[800]!.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.grey[700]!,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.grey[400],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'No device paired yet',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hPi4Global.hpi4Color,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 3,
                                ),
                                onPressed: () async {
                                  // Navigate to scan screen for pairing
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ScrDeviceScan(
                                        pairOnly: true,
                                        // Don't pass onDeviceConnected - we want pairing, not connection
                                      ),
                                    ),
                                  );

                                  // When user returns, trigger rebuild to show new paired device
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                                icon: const Icon(Icons.bluetooth_searching, size: 22),
                                label: const Text(
                                  'Pair Device',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hPi4Global.hpi4Color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.watch,
                            color: hPi4Global.hpi4Color,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          deviceInfo.displayName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'MAC: ${deviceInfo.macAddress}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Paired: ${_formatDate(deviceInfo.firstPaired)}',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ScrDeviceSettings(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Device Actions Card
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Recordings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ECG Recordings
                  _buildActionButton(
                    icon: Icons.monitor_heart,
                    label: 'ECG Recordings',
                    color: hPi4Global.hpi4Color,
                    onPressed: () async {
                      // Get paired device info
                      final deviceInfo = await DeviceManager.getPairedDevice();
                      if (deviceInfo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No device paired. Please pair a device first.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Navigate directly to ECG recordings with device MAC
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrEcgRecordings(
                            deviceMacAddress: deviceInfo.macAddress,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // GSR Recordings
                  _buildActionButton(
                    icon: Icons.monitor_heart,
                    label: 'GSR Recordings',
                    color: hPi4Global.hpi4Color,
                    onPressed: () async {
                      // Get paired device info
                      final deviceInfo = await DeviceManager.getPairedDevice();
                      if (deviceInfo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No device paired. Please pair a device first.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Navigate directly to ECG recordings with device MAC
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrGSRRecordings(
                            deviceMacAddress: deviceInfo.macAddress,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // PPG Recordings
                  _buildActionButton(
                    icon: Icons.monitor_heart,
                    label: 'PPG Recordings',
                    color: hPi4Global.hpi4Color,
                    onPressed: () async {
                      // Get paired device info
                      final deviceInfo = await DeviceManager.getPairedDevice();
                      if (deviceInfo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No device paired. Please pair a device first.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Navigate directly to ECG recordings with device MAC
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrPPGRecordings(
                            deviceMacAddress: deviceInfo.macAddress,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // HRV Recordings
                  _buildActionButton(
                    icon: Icons.monitor_heart,
                    label: 'HRV Recordings',
                    color: hPi4Global.hpi4Color,
                    onPressed: () async {
                      // Get paired device info
                      final deviceInfo = await DeviceManager.getPairedDevice();
                      if (deviceInfo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No device paired. Please pair a device first.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      // Navigate directly to ECG recordings with device MAC
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ScrHRVRecordings(
                            deviceMacAddress: deviceInfo.macAddress,
                          ),
                        ),
                      );
                    },
                  ),


                  const SizedBox(height: 16),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}