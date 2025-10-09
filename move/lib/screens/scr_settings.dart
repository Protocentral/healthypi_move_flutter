import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'showTerms.dart';
import 'showPrivacy.dart';

import '../globals.dart';
import '../utils/sizeConfig.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/trends_data_manager.dart';
import '../utils/database_helper.dart';
import '../utils/device_manager.dart';
import '../widgets/export_dialogs.dart';

class ScrSettings extends StatefulWidget {
  ScrSettings({super.key});

  @override
  _ScrSettingsState createState() => _ScrSettingsState();
}

class _ScrSettingsState extends State<ScrSettings> {
  @override
  void initState() {
    super.initState();
  }

  void logConsole(String logString) async {
    print("AKW - $logString");
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  _launchURL() async {
    const url = 'https://protocentral.com';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'Could not launch $url';
    }
  }

  Widget _getPoliciesTile() {
    return Column(
      children: [
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
            ),
            onPressed: () {
              _launchURL();
            },
            icon: Icon(Icons.language, size: 20),
            label: Text(
              'protocentral.com',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(
                      fontSize: 14,
                      color: hPi4Global.hpi4Color,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        showPrivacyDialog(context);
                      },
                  ),
                  TextSpan(
                    text: ' | ',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  TextSpan(
                    text: 'Terms of Use',
                    style: TextStyle(
                      fontSize: 14,
                      color: hPi4Global.hpi4Color,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        showTermsDialog(context);
                      },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2D2D2D)),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text(
                  'Success',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                },
                child: Text(
                  'OK',
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

  Future<void> _exportAllData() async {
    // Show action dialog (Share or Save)
    final action = await showExportActionDialog(context);
    if (action == null) return; // User cancelled
    
    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          color: const Color(0xFF2D2D2D),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: hPi4Global.hpi4Color),
                SizedBox(height: 16),
                Text(
                  'Preparing complete data export...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Create comprehensive CSV with all health data
      List<List<String>> csvData = [
        ['Timestamp', 'Metric', 'Value', 'Min', 'Max', 'Avg', 'Period'],
      ];

      // Export Heart Rate Data
      final hrManager = TrendsDataManager(hPi4Global.PREFIX_HR);
      List<MonthlyTrend> hrMonthly = await hrManager.getMonthlyTrends();
      for (var trend in hrMonthly) {
        csvData.add([
          DateFormat('yyyy-MM-dd').format(trend.date),
          'Heart Rate',
          '${trend.avg.toStringAsFixed(1)} bpm',
          trend.min.toStringAsFixed(0),
          trend.max.toStringAsFixed(0),
          trend.avg.toStringAsFixed(1),
          'Daily',
        ]);
      }

      // Export SpO2 Data
      final spo2Manager = TrendsDataManager(hPi4Global.PREFIX_SPO2);
      List<MonthlyTrend> spo2Monthly = await spo2Manager.getMonthlyTrends();
      for (var trend in spo2Monthly) {
        csvData.add([
          DateFormat('yyyy-MM-dd').format(trend.date),
          'SpO2',
          '${trend.avg.toStringAsFixed(1)}%',
          trend.min.toStringAsFixed(0),
          trend.max.toStringAsFixed(0),
          trend.avg.toStringAsFixed(1),
          'Daily',
        ]);
      }

      // Export Temperature Data
      final tempManager = TrendsDataManager(hPi4Global.PREFIX_TEMP);
      List<MonthlyTrend> tempMonthly = await tempManager.getMonthlyTrends();
      for (var trend in tempMonthly) {
        csvData.add([
          DateFormat('yyyy-MM-dd').format(trend.date),
          'Temperature',
          '${(trend.avg / 100).toStringAsFixed(2)}°C',
          (trend.min / 100).toStringAsFixed(2),
          (trend.max / 100).toStringAsFixed(2),
          (trend.avg / 100).toStringAsFixed(2),
          'Daily',
        ]);
      }

      // Export Activity Data
      final activityManager = TrendsDataManager(hPi4Global.PREFIX_ACTIVITY);
      List<MonthlyTrend> activityMonthly = await activityManager.getMonthlyTrends();
      for (var trend in activityMonthly) {
        csvData.add([
          DateFormat('yyyy-MM-dd').format(trend.date),
          'Steps',
          trend.max.toStringAsFixed(0),
          trend.min.toStringAsFixed(0),
          trend.max.toStringAsFixed(0),
          trend.avg.toStringAsFixed(1),
          'Daily',
        ]);
      }

      if (csvData.length <= 1) {
        Navigator.pop(context); // Close loading
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No data available to export'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Create CSV content
      String csv = const ListToCsvConverter().convert(csvData);
      String timestamp = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
      String filename = 'healthypi_complete_data_$timestamp.csv';
      
      Navigator.pop(context); // Close loading
      
      // Share the data
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(csv);
      
      final result = await Share.shareXFiles(
        [XFile(file.path)],
      );
      
      if (result.status == ShareResultStatus.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Data exported successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Erase all app data including database, files, and preferences
  Future<void> deleteAllAppData() async {
    try {
      int deletedRecords = 0;
      int deletedFiles = 0;
      
      // 1. Close and delete the SQLite database
      try {
        // Close the database first
        await DatabaseHelper.instance.close();
        
        // Get database path and delete it
        final dbPath = await getDatabasesPath();
        final dbFile = File('$dbPath/healthypi_trends.db');
        if (await dbFile.exists()) {
          await dbFile.delete();
          deletedRecords = 1; // Flag that database was deleted
          print('Database deleted successfully');
        }
      } catch (e) {
        print('Error deleting database: $e');
      }
      
      // 2. Delete all files in app documents directory
      try {
        final dir = await getApplicationDocumentsDirectory();
        if (await dir.exists()) {
          final files = dir.listSync(recursive: true);
          for (var entity in files) {
            if (entity is File) {
              await entity.delete();
              deletedFiles++;
            }
          }
          print('Deleted $deletedFiles files from documents directory');
        }
      } catch (e) {
        print('Error deleting files: $e');
      }
      
      // 3. Unpair device (removes pairing info from SharedPreferences and files)
      try {
        await DeviceManager.unpairDevice();
        print('Device unpaired successfully');
      } catch (e) {
        print('Error unpairing device: $e');
      }
      
      // 4. Clear all SharedPreferences data
      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        print('SharedPreferences cleared');
      } catch (e) {
        print('Error clearing SharedPreferences: $e');
      }
      
      if (!mounted) return;
      
      // Show success dialog with details
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Theme(
            data: ThemeData.dark().copyWith(
              dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2D2D2D)),
            ),
            child: AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Data Erased',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All app data has been successfully deleted:',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  SizedBox(height: 12),
                  _buildDeletedItem('Database', deletedRecords > 0),
                  _buildDeletedItem('Files', deletedFiles > 0),
                  _buildDeletedItem('Device pairing', true),
                  _buildDeletedItem('Settings', true),
                  SizedBox(height: 12),
                  Text(
                    'The app has been reset to its initial state.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'OK',
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
    } catch (e) {
      print('Error during data deletion: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error erasing data: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  
  Widget _buildDeletedItem(String label, bool success) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle : Icons.cancel,
            color: success ? Colors.green : Colors.red,
            size: 18,
          ),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
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
              'Are you sure you wish to delete '+action,
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
                onPressed: () {
                  Navigator.pop(context);
                  if(action == "all data."){
                    deleteAllAppData();
                  }else if(action == "paired device."){
                    DeviceManager.unpairDevice();
                  }else{

                  }

                },
              ),
              TextButton(
                child: const Text(
                  'No',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hPi4Global.hpi4Color,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context); // Returns false
                },
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
              'Settings',
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
          // Data Management Section
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
                    'Data Management',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: hPi4Global.hpi4Color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _exportAllData,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Download All Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        showConfirmationDialog(context, "all data.");
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Erase App Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // About Section
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "HealthyPi Move is a wearable smartwatch that can be used for development of fitness and health related applications. "
                    "With this app for HealthyPi Move, you can now download trends and other data, manage your device and more.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[300],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We do not collect any personal data and there is no registration or cloud connection required.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[300],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[900]!.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange[700]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange[300],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Disclaimer: This app and device are only for fitness and wellness purposes and NOT for medical or diagnostics use.",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange[100],
                              height: 1.4,
                            ),
                            textAlign: TextAlign.justify,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _getPoliciesTile(),
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          "v ${hPi4Global.hpi4AppVersion}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "© ProtoCentral Electronics 2025",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
