import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:move/screens/scr_bpt_calibration.dart';
import 'package:move/screens/scr_device_scan.dart';
import 'package:move/screens/scr_stream_selection.dart';
import 'package:move/screens/scr_ecg_recordings.dart';
import 'package:move/screens/scr_dfu.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../utils/sizeConfig.dart';
import '../models/device_info.dart';
import '../utils/device_manager.dart';
import 'scr_device_settings.dart';
import '../home.dart';

import '../globals.dart';
import 'package:flutter/cupertino.dart';

class ScrDeviceMgmt extends StatefulWidget {
  const ScrDeviceMgmt({super.key});

  @override
  _ScrDeviceMgmtState createState() => _ScrDeviceMgmtState();
}

class _ScrDeviceMgmtState extends State<ScrDeviceMgmt> {
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

  showConfirmationDialog(BuildContext context, String action) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2D2D2D)),
          ),
          child: AlertDialog(
            title: Text(
              'Are you sure you wish to delete all data.',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            content: Text(
              'This action is not reversible.',
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text(
                  'Yes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
                onPressed: () async {
                  // Directly navigate to HomePage to trigger database deletion
                  await DeviceManager.unpairDevice();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => HomePage()),
                  );
                },
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text(
                  'No',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                        return Container(
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
                    'Device Management',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Update Firmware
                  _buildActionButton(
                    icon: Icons.system_update,
                    label: 'Update Firmware',
                    color: hPi4Global.hpi4Color,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ScrDFU()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  // BPT Calibration
                  _buildActionButton(
                    icon: Symbols.blood_pressure,
                    label: 'BPT Calibration',
                    color: hPi4Global.hpi4Color,
                    onPressed: () {
                      setState(() {
                        selectedOption = "BPT";
                      });
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ScrBPTCalibration()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  
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
                  
                  // Live View
                  _buildActionButton(
                    icon: Symbols.monitoring,
                    label: 'Live View',
                    color: hPi4Global.hpi4Color,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ScrDeviceScan(
                            onDeviceConnected: (device) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => ScrStreamsSelection(device: device),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey[700], thickness: 1),
                  const SizedBox(height: 16),
                  
                  // Erase logs
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Erase All Logs on Device',
                    color: Colors.red[700]!,
                    onPressed: () {
                      showConfirmationDialog(context, "logs on the device.");
                    },
                  ),
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
