import 'dart:async';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:move/utils/extra.dart';

import '../globals.dart';
import '../home.dart';
import '../utils/sizeConfig.dart';
import '../utils/snackbar.dart';
import '../utils/device_manager.dart';
import 'scr_device_scan.dart';

enum CalibrationState {
  preCalibration,
  readyForInput,
  calibrating,
  pointComplete,
  allComplete
}

class CalibrationPoint {
  final int pointNumber;
  final int systolic;
  final int diastolic;
  final bool isComplete;
  final DateTime? timestamp;

  CalibrationPoint({
    required this.pointNumber,
    required this.systolic,
    required this.diastolic,
    this.isComplete = false,
    this.timestamp,
  });
}

class ScrBPTCalibration extends StatefulWidget {
  const ScrBPTCalibration({super.key});

  @override
  State<ScrBPTCalibration> createState() => _ScrBPTCalibrationState();
}

class _ScrBPTCalibrationState extends State<ScrBPTCalibration> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  BluetoothDevice? _device;

  BluetoothService? commandService;
  BluetoothCharacteristic? commandCharacteristic;

  BluetoothService? dataService;
  BluetoothCharacteristic? dataCharacteristic;

  late StreamSubscription<List<int>> _streamDataSubscription;

  bool startListeningFlag = false;

  bool _isInitializing = true;
  String _statusMessage = "Connecting to device...";
  
  // New state management
  CalibrationState _currentState = CalibrationState.preCalibration;
  int _currentPointIndex = 0;
  List<CalibrationPoint> _calibrationPoints = [];
  int _progress = 0;
  int _statusCode = 0;
  String _statusString = "";

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
      
      // Create device from MAC address and connect
      _device = BluetoothDevice.fromId(deviceInfo.macAddress);
      
      if (mounted) {
        setState(() {
          _statusMessage = "Connecting to ${deviceInfo.displayName}...";
        });
      }
      
      if (_device!.isDisconnected) {
        await _device!.connect(license: License.values.first);
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Update last connected time
      await DeviceManager.updateLastConnected();
      
      // Discover services and characteristics
      final services = await _device!.discoverServices();
      
      for (var service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
          commandService = service;
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD_DATA)) {
              dataCharacteristic = characteristic;
            }
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
              commandCharacteristic = characteristic;
            }
          }
        }
      }
      
      if (commandCharacteristic == null || dataCharacteristic == null) {
        throw Exception('Required characteristics not found');
      }
      
      // Set up calibration mode
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _currentState = CalibrationState.preCalibration;
        });
        await sendSetCalibrationCommand(_device!);
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
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => HomePage()),
                );
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: hPi4Global.hpi4Color),
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
                style: TextStyle(color: hPi4Global.hpi4Color),
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
    _initializeConnection();
  }

  @override
  void dispose() {
    // Dispose the controller when the widget is removed from the widget tree
    Future.delayed(Duration.zero, () async {
      _systolicController.dispose();
      _diastolicController.dispose();
      await onDisconnectPressed();
    });

    super.dispose();
  }

  Future onRefresh() {
    // Refresh not needed as we auto-connect
    return Future.delayed(const Duration(milliseconds: 500));
  }

  subscribeToChar(BluetoothDevice deviceName) async {
    List<BluetoothService> services = await deviceName.discoverServices();
    // Find a service and characteristic by UUID
    for (BluetoothService service in services) {
      if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
        commandService = service;
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD_DATA)) {
            dataCharacteristic = characteristic;
            await dataCharacteristic?.setNotifyValue(true);
            break;
          }
        }
      }
    }
  }

  void setStateIfMounted(f) {
    if (mounted) setState(f);
  }



  Future<void> sendSetCalibrationCommand(BluetoothDevice device) async {
    await Future.delayed(Duration.zero, () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.SetBPTCalMode);
      await _sendCommand(commandPacket, device);
      logConsole(commandPacket.toString());
    });
  }

  BluetoothDevice get connectedDevice => _device!;

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

  int progress = 0;
  int status = 0;
  String statusString = "";

  String _getStatusMessage(int statusCode) {
    switch (statusCode) {
      case 0:
        return "❌ No signal - Check finger placement";
      case 1:
        return "✓ Good signal";
      case 2:
        return "✓ Calibration complete!";
      case 4:
        return "⚠️ Too much movement - Stay still";
      case 6:
        return "❌ Calibration failed";
      case 3:
      case 16:
      case 19:
        return "⚠️ Weak signal - Adjust sensor position";
      case 23:
      case 24:
        return "⚠️ No finger contact - Reposition sensor";
      default:
        return "";
    }
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

  void _startPreCalibration() {
    setState(() {
      _currentState = CalibrationState.preCalibration;
      _currentPointIndex = 0;
      _calibrationPoints.clear();
    });
  }

  void _startCalibrationInput() {
    setState(() {
      _currentState = CalibrationState.readyForInput;
      _systolicController.clear();
      _diastolicController.clear();
    });
  }

  void _completeCurrentPoint() {
    setState(() {
      _calibrationPoints.add(CalibrationPoint(
        pointNumber: _currentPointIndex + 1,
        systolic: int.parse(_systolicController.text),
        diastolic: int.parse(_diastolicController.text),
        isComplete: true,
        timestamp: DateTime.now(),
      ));
      
      if (_calibrationPoints.length >= 3) {
        _currentState = CalibrationState.allComplete;
      } else {
        _currentState = CalibrationState.pointComplete;
      }
    });
  }

  Future<void> _startListeningData(BluetoothDevice deviceName) async {
    logConsole("Started listening....");
    startListeningFlag = true;
    _streamDataSubscription = dataCharacteristic!.onValueReceived.listen((
      value,
    ) async {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      logConsole("Data Rx: $value");
      logConsole("Data Rx in hex: ${hex.encode(value)}");

      setState(() {
        _statusCode = bdata.getUint8(0);
        _progress = bdata.getUint8(1);
        _statusString = _getStatusMessage(_statusCode);
      });
      
      if (_statusCode == 2) {
        // Calibration point complete
        _completeCurrentPoint();
      }
    });

    // cleanup: cancel subscription when disconnected
    deviceName.cancelWhenDisconnected(_streamDataSubscription);
  }

  Future<void> sendStartCalibration(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Send start calibration command initiated");
    if (startListeningFlag == true) {
      _streamDataSubscription.cancel();
    }
    await _startListeningData(deviceName);
    await Future.delayed(Duration.zero, () async {
      List<int> commandPacket = [];
      String userInput1 = _systolicController.text;
      String userInput2 = _diastolicController.text;
      List<int> userCommandData = [];
      List<int> userCommandData1 = [];
      List<int> calIndex = [];
      calIndex = [_currentPointIndex];
      // Convert the user input string to an integer list (if applicable)
      if (userInput1.isNotEmpty) {
        userCommandData =
            userInput1.split(',').map((e) => int.parse(e.trim())).toList();
      } else {
        userCommandData = [0];
      }
      if (userInput2.isNotEmpty) {
        userCommandData1 =
            userInput2.split(',').map((e) => int.parse(e.trim())).toList();
      } else {
        userCommandData1 = [0];
      }

      commandPacket.addAll(hPi4Global.StartBPTCal);
      commandPacket.addAll(userCommandData);
      commandPacket.addAll(userCommandData1);
      commandPacket.addAll(calIndex);

      await _sendCommand(commandPacket, deviceName);
      logConsole(commandPacket.toString());
      setState(() {
        _currentState = CalibrationState.calibrating;
      });
      Navigator.pop(context);
    });
  }

  Future<void> sendEndCalibration(
    BuildContext context,
    BluetoothDevice deviceName,
  ) async {
    logConsole("Send end calibration command initiated");
    await Future.delayed(Duration.zero, () async {
      List<int> commandPacket = [];
      commandPacket.addAll(hPi4Global.EndBPTCal);
      await _sendCommand(commandPacket, deviceName);
      logConsole(commandPacket.toString());
    });
  }

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

  Future<void> _sendCommand(
    List<int> commandList,
    BluetoothDevice deviceName,
  ) async {
    try {
      // Check if device is still connected
      if (_device == null || deviceName.isDisconnected) {
        logConsole("Device disconnected, skipping command");
        return;
      }

      logConsole("Tx CMD $commandList 0x${hex.encode(commandList)}");

      List<BluetoothService> services = await deviceName.discoverServices();

      // Find a service and characteristic by UUID
      for (BluetoothService service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
          commandService = service;
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
              commandCharacteristic = characteristic;
              break;
            }
          }
        }
      }

      if (commandService != null && commandCharacteristic != null) {
        // Write to the characteristic
        await commandCharacteristic?.write(commandList, withoutResponse: true);
        //logConsole('Data written: $commandList');
      }
    } catch (e) {
      logConsole("Error sending command: $e");
      // Silently handle error if device is disconnected
    }
  }

  Future onDisconnectPressed() async {
    try {
      if (_device != null) {
        await _device!.disconnectAndUpdateStream();
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
                valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
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
    if (_device != null) {
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
                    color: hPi4Global.hpi4Color,
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
                  _buildInfoTile(Icons.timer, 'Duration', '5-7 minutes'),
                  const SizedBox(height: 12),
                  _buildInfoTile(Icons.sensors, 'Readings Required', '3 calibration points'),
                  const SizedBox(height: 12),
                  _buildInfoTile(Icons.medical_services, 'You\'ll Need', 'BP monitor + Finger sensor'),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Important Tips:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTipTile('Sit comfortably and stay still during measurement'),
                  _buildTipTile('Ensure proper finger sensor placement'),
                  _buildTipTile('Take BP readings at different times for best accuracy'),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _currentState = CalibrationState.readyForInput;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hPi4Global.hpi4Color,
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

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: hPi4Global.hpi4Color, size: 20),
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
          const Text('• ', style: TextStyle(color: hPi4Global.hpi4Color, fontSize: 16)),
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
                          ? hPi4Global.hpi4Color
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: hPi4Global.hpi4Color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.info_outline, color: hPi4Global.hpi4Color, size: 32),
                          SizedBox(height: 12),
                          Text(
                            'Instructions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Put on the finger sensor\n2. Measure your BP with standard monitor\n3. Enter the readings below',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          FocusScope.of(context).unfocus();
                          if (_formKey.currentState!.validate()) {
                            showLoadingIndicator("Starting calibration...", context);
                            await subscribeToChar(connectedDevice);
                            Future.delayed(Duration.zero, () async {
                              await sendStartCalibration(context, connectedDevice);
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hPi4Global.hpi4Color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Begin Calibration Point ${_currentPointIndex + 1}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                          valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
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
                                  style: TextStyle(color: hPi4Global.hpi4Color),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context); // Close dialog
                                  if (mounted) {
                                    // Send end command before disconnecting
                                    try {
                                      await sendEndCalibration(context, connectedDevice);
                                    } catch (e) {
                                      logConsole("Error ending calibration: $e");
                                    }
                                    await onDisconnectPressed();
                                    if (mounted) {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(builder: (_) => HomePage()),
                                      );
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
                      onPressed: () {
                        setState(() {
                          _currentPointIndex++;
                          _currentState = CalibrationState.readyForInput;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hPi4Global.hpi4Color,
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
                          await sendEndCalibration(context, connectedDevice);
                        } catch (e) {
                          logConsole("Error ending calibration: $e");
                        }
                        await onDisconnectPressed();
                        if (mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => HomePage()),
                          );
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
                          await sendEndCalibration(context, connectedDevice);
                        } catch (e) {
                          logConsole("Error ending calibration: $e");
                        }
                        await onDisconnectPressed();
                        if (mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => HomePage()),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hPi4Global.hpi4Color,
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
      backgroundColor: hPi4Global.appBackgroundColor,
      appBar: AppBar(
        backgroundColor: hPi4Global.hpi4AppBarColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            await onDisconnectPressed();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => HomePage()),
            );
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


