// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:move/utils/connection_manager.dart';

import '../ble/bpt_calibrator.dart';
import '../globals.dart';
import 'scr_main_shell.dart';
import '../utils/sizeConfig.dart';
import '../utils/snackbar.dart';
import '../utils/device_manager.dart';
import 'scr_device_scan.dart';
import '../theme/hpi_legacy_theme.dart';
import '../widgets/loading_indicator.dart';

// CalibrationState + CalibrationPoint + the BptCalibrator state machine live in
// ../ble/bpt_calibrator.dart (SDK-bound, transport-agnostic). This screen is now
// just its view + input.

class ScrBPTCalibration extends StatefulWidget {
  const ScrBPTCalibration({super.key});

  @override
  State<ScrBPTCalibration> createState() => _ScrBPTCalibrationState();
}

class _ScrBPTCalibrationState extends State<ScrBPTCalibration> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final ConnectionManager _conn = ConnectionManager.instance;

  /// The transport-agnostic BPT state machine. Bound to the custom CMD GATT
  /// service today via [_ConnCmdBptTransport]; a future HPI_HS/SMP binding is an
  /// adapter swap here, with no change to this screen or the calibrator.
  late final BptCalibrator _cal;

  bool _isInitializing = true;
  String _statusMessage = "Connecting to device...";

  // --- calibrator state, surfaced as shims so the view code reads unchanged ---
  CalibrationState get _currentState => _cal.phase;
  int get _currentPointIndex => _cal.currentPointIndex;
  List<CalibrationPoint> get _calibrationPoints => _cal.points;
  int get _progress => _cal.progress;
  int get _statusCode => _cal.statusCode;
  String get _statusString => _cal.statusMessage;
  bool get _fingerSignalGood => _cal.fingerSignalGood;
  bool get _pointFailed => _cal.pointFailed;

  Future<void> _initializeConnection() async {
    try {
      // Check for paired device
      final deviceInfo = await DeviceManager.getPairedDevice();
      
      if (deviceInfo == null) {
        // No paired device, navigate to scan screen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ScrDeviceScan(
                pairOnly: false,
                onDeviceConnected: (device) {
                  // After pairing, navigate back to BPT calibration
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ScrBPTCalibration()),
                  );
                },
              ),
            ),
          );
        }
        return;
      }
      
      // Connect to the paired device (scan-assisted connect + service discovery
      // handled by ConnectionManager).
      if (mounted) {
        setState(() {
          _statusMessage = "Connecting to ${deviceInfo.displayName}...";
        });
      }

      await _conn.connect(deviceInfo.macAddress, name: deviceInfo.displayName);

      // Update last connected time
      await DeviceManager.updateLastConnected();

      // Enter BPT calibration mode and start the finger-signal stream so the
      // user can seat the sensor and see contact quality *before* they enter
      // cuff readings. Waiting until "Begin" to listen is too late — by then
      // a bad finger placement just burns a calibration attempt.
      if (mounted) {
        setState(() => _isInitializing = false);
        // Enter calibration mode and begin listening (0x60 + status subscribe).
        await _cal.enterCalibrationMode();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Connection failed: $e';
        });
        
        // Show error and option to retry or go to scan
        _showConnectionErrorDialog();
      }
    }
  }
  
  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text(
            'Connection Failed',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScrMainShell.returnToRoot(context);
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: HpiLegacyTheme.hpi4Color),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ScrDeviceScan()),
                );
              },
              child: Text(
                'Scan for Device',
                style: TextStyle(color: HpiLegacyTheme.hpi4Color),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _cal = BptCalibrator(
      _ConnCmdBptTransport(_conn),
      log: logConsole,
    )..addListener(_onCalChanged);
    _initializeConnection();
  }

  /// Rebuild whenever the calibrator's state changes (status packets, phase
  /// transitions). All BPT state now lives in [_cal].
  void _onCalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cal.removeListener(_onCalChanged);
    _cal.dispose(); // cancels the status subscription
    _systolicController.dispose();
    _diastolicController.dispose();
    // Leave the BLE link up — ConnectionManager owns it and Home/Device may
    // still need it.
    super.dispose();
  }

  Future onRefresh() {
    // Refresh not needed as we auto-connect
    return Future.delayed(const Duration(milliseconds: 500));
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }

  void showSuccessDialog(
    BuildContext context,
    String titleMessage,
    String message,
    Icon customIcon,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Theme(
          data: ThemeData.dark().copyWith(
            textTheme: TextTheme(),
            dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF2D2D2D)),
          ),
          child: AlertDialog(
            title: Row(
              children: [
                //Icon(Icons.check_circle, color: Colors.green),
                customIcon,
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
                  Navigator.pop(dialogContext); // Close the dialog
                },
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: HpiLegacyTheme.hpi4Color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(int statusCode) {
    switch (statusCode) {
      case 0:
      case 6:
        return Colors.red[400]!;
      case 1:
      case 2:
        return Colors.green[400]!;
      case 3:
      case 4:
      case 16:
      case 19:
      case 23:
      case 24:
        return Colors.orange[400]!;
      default:
        return Colors.white70;
    }
  }

  /// Start the current point. Reads the cuff numbers, hands them to the
  /// calibrator (which sends `0x61` + `[sys, dia, index]` and moves to
  /// calibrating), and closes the loading dialog.
  Future<void> sendStartCalibration(BuildContext context) async {
    final sys = int.tryParse(_systolicController.text.trim()) ?? 0;
    final dia = int.tryParse(_diastolicController.text.trim()) ?? 0;

    // Close the loading dialog if one is open.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    await _cal.startPoint(systolic: sys, diastolic: dia);
  }

  void _retryCurrentPoint() => _cal.retryPoint();

  Future<void> sendEndCalibration(BuildContext context) => _cal.endCalibration();

  void showLoadingIndicator(String text, BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            backgroundColor: Colors.black87,
            content: LoadingIndicator(text: text),
          ),
        );
      },
    );
  }

  Future onDisconnectPressed() async {
    try {
      if (_conn.isConnected) {
        await _conn.disconnect();
        Snackbar.show(ABC.c, "Disconnect: Success", success: true);
      }
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.c,
        prettyException("Disconnect Error:", e),
        success: false,
      );
      print("$e backtrace: $backtrace");
    }
  }

  Widget _buildStatusCard(BuildContext context) {
    if (_isInitializing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(HpiLegacyTheme.hpi4Color),
              ),
              const SizedBox(height: 20),
              Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // Show connected device info
    if (_conn.isConnected) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.bluetooth_connected, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            const Text(
              "Connected to HealthyPi Move",
              style: TextStyle(fontSize: 14, color: Colors.green),
            ),
          ],
        ),
      );
    }
    
    return Container();
  }

  Widget _buildPreCalibrationScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(
                    Icons.monitor_heart,
                    size: 64,
                    color: HpiLegacyTheme.hpi4Color,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Blood Pressure Calibration',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildInfoTile(Icons.timer, 'Duration', '3–5 minutes'),
                  const SizedBox(height: 12),
                  _buildInfoTile(Icons.sensors, 'Readings required', '3 points · finger PPG'),
                  const SizedBox(height: 12),
                  _buildInfoTile(Icons.medical_services, 'You\'ll need', 'Cuff BP monitor + finger sensor'),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Finger sensor first',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTipTile('Slide the finger sensor fully onto the index fingertip (snug, not crushing)'),
                  _buildTipTile('Rest your hand palm-up on a table; stay still during each point'),
                  _buildTipTile('Warm hands help — cold fingers kill the PPG signal'),
                  _buildTipTile('Measure cuff BP, enter the numbers, then start only when signal is green'),
                  const SizedBox(height: 16),
                  if (_statusString.isNotEmpty) _buildFingerSignalBanner(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _cal.beginInput(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HpiLegacyTheme.hpi4Color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Start Calibration',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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

  Widget _buildFingerSignalBanner() {
    final good = _fingerSignalGood || _statusCode == 1;
    final color = good ? Colors.green[400]! : _getStatusColor(_statusCode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle : Icons.fingerprint,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  good ? 'Finger sensor: good contact' : 'Finger sensor',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (_statusString.isNotEmpty)
                  Text(
                    _statusString,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: HpiLegacyTheme.hpi4Color, size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTipTile(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: HpiLegacyTheme.hpi4Color, fontSize: 16)),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          bool isComplete = index < _calibrationPoints.length;
          bool isCurrent = index == _currentPointIndex;
          
          return Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isComplete
                      ? Colors.green
                      : isCurrent
                          ? HpiLegacyTheme.hpi4Color
                          : Colors.grey[700],
                ),
                child: Center(
                  child: isComplete
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              if (index < 2)
                Container(
                  width: 40,
                  height: 2,
                  color: isComplete ? Colors.green : Colors.grey[700],
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildInputScreen() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildProgressIndicator(),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: const Color(0xFF2D2D2D),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text(
                      'Calibration Point ${_currentPointIndex + 1} of 3',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildFingerSignalBanner(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: HpiLegacyTheme.hpi4Color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.fingerprint, color: HpiLegacyTheme.hpi4Color, size: 32),
                          SizedBox(height: 12),
                          Text(
                            'Finger first, then cuff',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Seat the finger sensor (wait for green signal)\n'
                            '2. Take a cuff BP reading now\n'
                            '3. Enter systolic / diastolic below\n'
                            '4. Hold still until the point finishes',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.left,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _systolicController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Systolic',
                                labelStyle: TextStyle(color: Colors.grey[400]),
                                filled: true,
                                fillColor: Colors.grey[800],
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixText: 'mmHg',
                                suffixStyle: const TextStyle(color: Colors.grey),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final intValue = int.tryParse(value);
                                if (intValue == null) {
                                  return 'Invalid';
                                }
                                if (intValue < 80 || intValue > 180) {
                                  return '80-180';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _diastolicController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Diastolic',
                                labelStyle: TextStyle(color: Colors.grey[400]),
                                filled: true,
                                fillColor: Colors.grey[800],
                                border: OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixText: 'mmHg',
                                suffixStyle: const TextStyle(color: Colors.grey),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final intValue = int.tryParse(value);
                                if (intValue == null) {
                                  return 'Invalid';
                                }
                                if (intValue < 50 || intValue > 120) {
                                  return '50-120';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_fingerSignalGood) ...[
                      Text(
                        'Tip: start only when the finger sensor shows good contact. '
                        'You can still proceed, but failed points are usually a bad PPG signal.',
                        style: TextStyle(color: Colors.orange[300], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          if (!_formKey.currentState!.validate()) return;
                          showLoadingIndicator(
                            _fingerSignalGood
                                ? 'Starting point ${_currentPointIndex + 1}…'
                                : 'Starting without strong finger signal…',
                            context,
                          );
                          await sendStartCalibration(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _fingerSignalGood
                              ? HpiLegacyTheme.hpi4Color
                              : Colors.orange[800],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          _fingerSignalGood
                              ? 'Begin point ${_currentPointIndex + 1}'
                              : 'Begin anyway · point ${_currentPointIndex + 1}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
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

  Widget _buildCalibratingScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Calibrating Point ${_currentPointIndex + 1}...',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: _progress / 100,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey[700],
                          valueColor: const AlwaysStoppedAnimation<Color>(HpiLegacyTheme.hpi4Color),
                        ),
                      ),
                      Text(
                        '$_progress%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_statusString.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor(_statusCode).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _statusCode == 1 || _statusCode == 2
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: _getStatusColor(_statusCode),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusString,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(_statusCode),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_pointFailed) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _retryCurrentPoint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HpiLegacyTheme.hpi4Color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Retry this point',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reseat the finger sensor, wait for a green signal, then retry. '
                      'Earlier completed points are kept.',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF2D2D2D),
                            title: const Text(
                              'Cancel Calibration?',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              'Are you sure you want to cancel? Progress will be lost.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Continue',
                                  style: TextStyle(color: HpiLegacyTheme.hpi4Color),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context); // Close dialog
                                  if (mounted) {
                                    try {
                                      await sendEndCalibration(context);
                                    } catch (e) {
                                      logConsole("Error ending calibration: $e");
                                    }
                                    if (mounted) {
                                      ScrMainShell.returnToRoot(context);
                                    }
                                  }
                                },
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Cancel Calibration',
                        style: TextStyle(fontSize: 16),
                      ),
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

  Widget _buildPointCompleteScreen() {
    final currentPoint = _calibrationPoints[_currentPointIndex];
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildProgressIndicator(),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 64,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Point ${currentPoint.pointNumber} Complete!',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Readings Captured:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text(
                                  'Systolic',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  '${currentPoint.systolic}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'mmHg',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                            Container(
                              width: 2,
                              height: 60,
                              color: Colors.grey[700],
                            ),
                            Column(
                              children: [
                                const Text(
                                  'Diastolic',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  '${currentPoint.diastolic}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'mmHg',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Progress: ${_calibrationPoints.length}/3 (${3 - _calibrationPoints.length} more needed)',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _cal.advanceToNextPoint(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HpiLegacyTheme.hpi4Color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        'Continue to Point ${_calibrationPoints.length + 1}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await sendEndCalibration(context);
                        } catch (e) {
                          logConsole("Error ending calibration: $e");
                        }
                        await onDisconnectPressed();
                        if (mounted) {
                          ScrMainShell.returnToRoot(context);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.grey[700]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Finish Calibration Early',
                        style: TextStyle(fontSize: 14),
                      ),
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

  Widget _buildAllCompleteScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  const Icon(
                    Icons.celebration,
                    size: 80,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Calibration Complete!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your device is now calibrated with 3 reference points',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ...List.generate(_calibrationPoints.length, (index) {
                    final point = _calibrationPoints[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              'Point ${point.pointNumber}:',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${point.systolic}/${point.diastolic} mmHg',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await sendEndCalibration(context);
                        } catch (e) {
                          logConsole("Error ending calibration: $e");
                        }
                        await onDisconnectPressed();
                        if (mounted) {
                          ScrMainShell.returnToRoot(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HpiLegacyTheme.hpi4Color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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
  void logConsole(String logString) async {
    print("AKW - $logString");
    debugText += logString;
    debugText += "\n";
  }

  String debugText = "Console Inited...";

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      backgroundColor: HpiLegacyTheme.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: HpiLegacyTheme.hpi4AppBarColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            await onDisconnectPressed();
            ScrMainShell.returnToRoot(context);
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
      body: _isInitializing
          ? _buildStatusCard(context)
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildStatusCard(context),
                  if (_currentState == CalibrationState.preCalibration)
                    _buildPreCalibrationScreen()
                  else if (_currentState == CalibrationState.readyForInput)
                    _buildInputScreen()
                  else if (_currentState == CalibrationState.calibrating)
                    _buildCalibratingScreen()
                  else if (_currentState == CalibrationState.pointComplete)
                    _buildPointCompleteScreen()
                  else if (_currentState == CalibrationState.allComplete)
                    _buildAllCompleteScreen(),
                ],
              ),
            ),
    );
  }
}

/// Binds [BptCalTransport] to today's transport: the custom CMD GATT service via
/// [ConnectionManager]. This thin adapter is the *only* app-specific glue — when
/// the calibrator moves into the `healthypi_move` SDK, the machine and interface
/// go with it and this stays behind (or is replaced by an HPI_HS/SMP binding).
class _ConnCmdBptTransport implements BptCalTransport {
  _ConnCmdBptTransport(this._conn);

  final ConnectionManager _conn;

  @override
  Stream<Uint8List> get statusStream => _conn.subscribe(
      hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD_DATA);

  @override
  Future<void> sendCommand(List<int> bytes) => _conn.write(
      hPi4Global.UUID_SERVICE_CMD,
      hPi4Global.UUID_CHAR_CMD,
      Uint8List.fromList(bytes));

  @override
  bool get isConnected => _conn.isConnected;
}

