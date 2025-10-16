import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:mcumgr_flutter/mcumgr_flutter.dart';
import 'package:mcumgr_flutter/models/firmware_upgrade_mode.dart';
import 'package:mcumgr_flutter/models/image_upload_alignment.dart';
import 'package:move/utils/extra.dart';
import 'package:move/utils/snackbar.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:version/version.dart';
import 'package:flutter/widgets.dart' as widgets;

import '../globals.dart';
import '../home.dart';
import '../utils/manifest.dart';
import '../widgets/scan_result_tile.dart';

class ScrDFU extends StatefulWidget {
  final String? deviceMacAddress;
  
  const ScrDFU({super.key, this.deviceMacAddress});

  @override
  State createState() => ScrDFUState();
}

class ScrDFUState extends State<ScrDFU> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  late StreamSubscription<BluetoothConnectionState>
  _connectionStateSubscription;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  late StreamSubscription<mcumgr.ProgressUpdate> _updateManagerSubscription;
  late StreamSubscription<mcumgr.FirmwareUpgradeState> _updateStateSubscription;

  late BluetoothCharacteristic deviceFWCharacteristic;

  String _currentFWVersion = "";
  String _latestFWVersion = "";
  //String _updateAvailable = "None";
  String _updateAvailable = "Available";
  bool _showUpdateCard = false;
  bool _checkingUpdates = false;

  late BluetoothDevice _currentDevice;
  List<BluetoothService> _services = [];

  String _dispConnStatus = "--";

  bool dfuInProgress = false;
  double dfuProgress = 0;
  double progressPercentage1 = 0.0;
  double progressPercentage2 = 0.0;
  double progressPercentage3 = 0.0;

  late Manifest _fw_manifest;
  bool _isManifestLoaded = false;

  final UpdateManagerFactory _managerFactory =
      mcumgr.FirmwareUpdateManagerFactory();

  @override
  void initState() {
    super.initState();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        if (mounted) {
          setState(() => _scanResults = results);
        }
      },
      onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() => _isScanning = state);
      }
    });

    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((
      state,
    ) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
    });

    requestPermissions();
    
    // Auto-connect to paired device if MAC address provided
    if (widget.deviceMacAddress != null) {
      _autoConnectToDevice();
    }
  }
  
  /// Auto-connect to paired device - similar pattern to ECG recordings and background sync
  Future<void> _autoConnectToDevice() async {
    setState(() {
      _isLoading = true;
      _dispConnStatus = 'Connecting to device...';
    });

    try {
      debugPrint('[DFU] Auto-connecting to device: ${widget.deviceMacAddress}');
      final device = BluetoothDevice.fromId(widget.deviceMacAddress!);
      _currentDevice = device;

      if (device.isDisconnected) {
        await device.connect(
          license: License.values.first,
          timeout: const Duration(seconds: 15),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final services = await device.discoverServices();
      _services = services;

      // Find firmware version characteristic (in Device Information Service 180a)
      bool foundFirmwareChar = false;
      for (var service in services) {
        debugPrint('[DFU] Checking service: ${service.uuid}');
        if (service.uuid == Guid("180a")) {
          debugPrint('[DFU] Found Device Information Service');
          for (var characteristic in service.characteristics) {
            debugPrint('[DFU] Checking characteristic: ${characteristic.uuid}');
            if (characteristic.uuid == Guid("2a26")) {
              foundFirmwareChar = true;
              deviceFWCharacteristic = characteristic;
              try {
                final fwVersion = await characteristic.read();
                _currentFWVersion = String.fromCharCodes(fwVersion).trim();
                debugPrint('[DFU] Current firmware version: "$_currentFWVersion"');
              } catch (e) {
                debugPrint('[DFU] Failed to read firmware version: $e');
                _currentFWVersion = "Unknown";
              }
              break;
            }
          }
        }
      }
      
      if (!foundFirmwareChar) {
        debugPrint('[DFU] Warning: Firmware version characteristic not found');
        _currentFWVersion = "Unknown";
      }

      // Check for latest firmware version
      _latestFWVersion = await _getLatestVersion();
      debugPrint('[DFU] Latest firmware version: $_latestFWVersion');
      
      // Only compare versions if we have a valid current version
      if (_currentFWVersion.isNotEmpty && _currentFWVersion != "Unknown") {
        try {
          _updateAvailable = _CompareFWVersion(_currentFWVersion, _latestFWVersion);
        } catch (e) {
          debugPrint('[DFU] Version comparison failed: $e');
          _updateAvailable = "Available"; // Default to showing update available
        }
      } else {
        _updateAvailable = "Available"; // Default to showing update available
      }

      if (mounted) {
        setState(() {
          _showUpdateCard = true;
          _dispConnStatus = 'Connected to ${device.platformName}';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DFU] Auto-connect error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Future<void> dispose() async {
    Future.delayed(Duration.zero, () async {
      _scanResultsSubscription.cancel();
      _isScanningSubscription.cancel();
      FlutterBluePlus.stopScan();
      await onDisconnectPressed();
    });

    super.dispose();
  }

  void logConsole(String logString) async {
    print("[HPI] $logString");
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [Permission.manageExternalStorage, Permission.storage].request();

    if (statuses.containsValue(PermissionStatus.denied)) {}
  }

  Future _onScanPressed() async {
    if (_adapterState != BluetoothAdapterState.on) {
      Snackbar.show(ABC.b, "Bluetooth is not enabled", success: false);
      return;
    }
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withKeywords: ['healthypi'],
        withServices: [],
        webOptionalServices: [
          Guid("180f"), // battery
          Guid("180a"), // device info
          Guid("1800"), // generic access
          Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        ],
      );
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.b,
        prettyException("Start Scan Error:", e),
        success: false,
      );
      print(e);
      print("backtrace: $backtrace");
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onRefresh() {
    if (_isScanning == false) {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  Future _onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e, backtrace) {
      Snackbar.show(
        ABC.b,
        prettyException("Stop Scan Error:", e),
        success: false,
      );
      print(e);
      print("backtrace: $backtrace");
    }
  }

  Widget buildScanButton(BuildContext context) {
    if (FlutterBluePlus.isScanningNow) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 2,
          ),
          onPressed: _onStopPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const <Widget>[
              Icon(Icons.stop),
              SizedBox(width: 8),
              Text(
                'Stop Scan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: hPi4Global.hpi4Color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 2,
          ),
          onPressed: _onScanPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const <Widget>[
              Icon(Icons.search, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Scan for Devices',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _onCheckLatestFirmware() async {
    setState(() {
      _checkingUpdates = true;
    });
    
    try {
      String checkfw = await downloadFile();
      String resultfw = _CompareFWVersion(_currentFWVersion, checkfw);
      
      if (resultfw == "Available") {
        setState(() {
          _updateAvailable = "Available";
          _isManifestLoaded = true;
        });
      } else {
        setState(() {
          _updateAvailable = "Not Available";
        });
      }
    } catch (e) {
      Snackbar.show(ABC.c, "Failed to check for updates: $e", success: false);
    } finally {
      setState(() {
        _checkingUpdates = false;
      });
    }
  }

  void _onLoadFirmwareManual() async {
    await _loadFirmwareFromFile();
  }

  void _onStartUpdate() async {
    setState(() {
      dfuInProgress = true;
    });
    await _startFirmwareUpdate();
  }

  Future<void> _loadFirmwareFromFile() async {
    late final destinationDir;
    late final firmwareGHFile;

    //if (fwFilePath == "") {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null) {
        return;
      }

      final firstResult = result.files.first;
      final file = File(firstResult.path!);
      final Uint8List firmwareFileData = await file.readAsBytes();

      final prefix = 'firmware_${Uuid().v4()}';
      final systemTempDir = await path_provider.getTemporaryDirectory();

      final tempDir = Directory('${systemTempDir.path}/$prefix');
      await tempDir.create();

      firmwareGHFile = File('${tempDir.path}/firmware.zip');
      await firmwareGHFile.writeAsBytes(firmwareFileData);

      destinationDir = Directory('${tempDir.path}/firmware');
      await destinationDir.create();
   // }
    /*else {
      showLoadingIndicator("Checking for firmware...", context);

      final file = File(fwFilePath);
      final Uint8List firmwareFileData = await file.readAsBytes();

      final prefix = 'firmware_${Uuid().v4()}';
      final systemTempDir = await path_provider.getTemporaryDirectory();

      final tempDir = Directory('${systemTempDir.path}/$prefix');
      await tempDir.create();

      firmwareGHFile = File('${tempDir.path}/firmware.zip');
      await firmwareGHFile.writeAsBytes(firmwareFileData);

      destinationDir = Directory('${tempDir.path}/firmware');
      await destinationDir.create();

      Navigator.pop(context);
    }*/

    try {
      await ZipFile.extractToDirectory(
        zipFile: firmwareGHFile,
        destinationDir: destinationDir,
      );
    } catch (e, stack) {
      print("Unzipping failed: $e\n$stack"); // <--- Add this
      throw Exception('Failed to unzip firmware');
    }

    // read manifest.json
    final manifestFile = File('${destinationDir.path}/manifest.json');
    final manifestString = await manifestFile.readAsString();
    Map<String, dynamic> manifestJson = json.decode(manifestString);

    try {
      _fw_manifest = Manifest.fromJson(manifestJson);
    } catch (e) {
      throw Exception('Failed to parse manifest.json');
    }

    print(_fw_manifest.files.length.toString());

    if (mounted) {
      setState(() {
        _isManifestLoaded = true;
        _updateAvailable = "Available";
      });
    }
  }

  Future<void> _startFirmwareUpdate() async {
    if (!_isManifestLoaded) {
      Snackbar.show(ABC.c, "No firmware loaded", success: false);
      return;
    }

    // Read firmware images from extracted directory
    final systemTempDir = await path_provider.getTemporaryDirectory();
    final tempDirs = Directory(systemTempDir.path).listSync();
    Directory? destinationDir;
    
    for (var dir in tempDirs) {
      if (dir.path.contains('firmware_') && dir is Directory) {
        final fwDir = Directory('${dir.path}/firmware');
        if (await fwDir.exists()) {
          destinationDir = fwDir;
          break;
        }
      }
    }

    if (destinationDir == null) {
      Snackbar.show(ABC.c, "Firmware files not found", success: false);
      return;
    }

    final updateManager = await _managerFactory.getUpdateManager(
      _currentDevice.remoteId.toString(),
    );

    updateManager.setup();

    _updateStateSubscription = updateManager.updateStateStream!.listen((event) {
      if (mounted) {
        setState(() {
          print("DFU state: ${event.toString()}");
        });
      }
    });

    List<mcumgr.Image> _fw_images = [];
    for (final file in _fw_manifest.files) {
      final firmwareFile = File('${destinationDir.path}/${file.file}');
      final firmwareFileData = await firmwareFile.readAsBytes();
      final image = mcumgr.Image(image: file.image, data: firmwareFileData);
      _fw_images.add(image);
    }

    final _fw_config = const FirmwareUpgradeConfiguration(
      estimatedSwapTime: Duration(seconds: 0),
      byteAlignment: ImageUploadAlignment.fourByte,
      eraseAppSettings: true,
      firmwareUpgradeMode: FirmwareUpgradeMode.confirmOnly,
    );

    _updateManagerSubscription = updateManager.progressStream.listen((event) {
      if (mounted) {
        setState(() {
          // Dynamically match progress to the correct image file based on size
          bool matched = false;
          
          for (int i = 0; i < _fw_manifest.files.length; i++) {
            if (event.imageSize == _fw_manifest.files[i].size) {
              final progress = (event.bytesSent / event.imageSize) * 100;
              dfuProgress = (event.bytesSent / event.imageSize);
              
              // Update specific progress percentage based on index
              switch (i) {
                case 0:
                  progressPercentage1 = progress;
                  break;
                case 1:
                  progressPercentage2 = progress;
                  break;
                case 2:
                  progressPercentage3 = progress;
                  break;
              }
              
              print("DFU progress (image ${i + 1}/${_fw_manifest.files.length}): ${event.bytesSent} / ${event.imageSize} (${progress.toStringAsFixed(1)}%)");
              matched = true;
              break;
            }
          }
          
          if (!matched) {
            // Update generic progress even if we don't match a specific file
            print("DFU progress (unknown image size ${event.imageSize}): ${event.bytesSent} bytes");
          }
        });
      }
    });

    updateManager.update(_fw_images, configuration: _fw_config);
  }

  void _listenDeviceConnected() {
    _currentDevice.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          logConsole("Device connection state: $state");
          if (state == BluetoothConnectionState.connected) {
            _currentDevice.discoverServices().then((services) {
              if (mounted) {
                setState(() {
                  _services = services;
                  _dispConnStatus = "Connected to ${_currentDevice.name}";
                });
              }
              for (BluetoothService service in services) {
                if (service.uuid == Guid("180a")) {
                  for (BluetoothCharacteristic characteristic
                      in service.characteristics) {
                    if (characteristic.uuid == Guid("2a26")) {
                      deviceFWCharacteristic = characteristic;
                      characteristic
                          .read()
                          .then((value) {
                            if (mounted) {
                              setState(() {
                                _currentFWVersion = String.fromCharCodes(value);
                                logConsole(
                                  "Current FW version: $_currentFWVersion",
                                );
                              });
                            }
                          })
                          .catchError((e) {
                            Snackbar.show(
                              ABC.c,
                              prettyException("Read Error:", e),
                              success: false,
                            );
                          });
                      break;
                    }
                  }
                }
              }
            });
          }
        });
      }
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

  Future<void> onConnectPressed(BluetoothDevice device) async {
    logConsole("Connecting to device: ${device.platformName}");
    if (mounted) {
      setState(() {
        _dispConnStatus = "Connecting to ${device.platformName}";
      });
    }

    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(
        ABC.c,
        prettyException("Connect Error:", e),
        success: false,
      );
    });

    if (mounted) {
      setState(() {
        _showUpdateCard = true;
        _currentDevice = device;
      });
    }

    _listenDeviceConnected();
  }

  Future onDisconnectPressed() async {
    try {
      await _currentDevice.disconnectAndUpdateStream();
      if (mounted) {
        setState(() {
          //_showUpdateCard = false;
          _dispConnStatus = "Disconnected";
        });
      }
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

  List<Widget> _buildScanResultTiles(BuildContext context) {
    return _scanResults
        .map(
          (r) => ScanResultTile(
            result: r,
            onTap: () => onConnectPressed(r.device),
          ),
        )
        .toList();
  }

  Future<List<String>> fetchTags() async {
    final url = Uri.parse(
      'https://api.github.com/repos/Protocentral/healthypi-move-fw/tags',
    );
    final response = await http.get(url);

    if (response.statusCode == 200) {
      // Parse the JSON response
      List<dynamic> data = json.decode(response.body);
      // Extract the tag names from the response
      List<String> tags = data.map((tag) => tag['name'] as String).toList();
      //print("............."+ tags.toString());
      return tags;
    } else {
      throw Exception('Failed to load tags');
    }
  }

  String latestReleasePath = "";

  Future<String> _getLatestVersion() async {
    List<String> tags = await fetchTags();
    print(tags);

    String _latestFWVersion = "0.9.18";

    List<String> tagsWithoutV =
        tags
            .map((tag) => tag.startsWith('v') ? tag.substring(1) : tag)
            .toList();

    // Print the new list
    print(tagsWithoutV);

    for (int i = 0; i < tagsWithoutV.length; i++) {
      _latestFWVersion = _getAvailableLatestVersion(
        _latestFWVersion,
        tagsWithoutV[i],
      );
    }

    return _latestFWVersion;
  }

  String _getAvailableLatestVersion(
    String versionCurrent,
    String versionAvail,
  ) {
    Version availVersion = Version.parse(versionAvail);
    Version currentVersion = Version.parse(versionCurrent);

    if (availVersion > currentVersion) {
      return versionAvail;
    } else {
      return versionCurrent;
    }
  }

  String _CompareFWVersion(String versionCurrent, String versionAvail) {
    Version availVersion = Version.parse(versionAvail);
    Version currentVersion = Version.parse(versionCurrent);

    if (availVersion > currentVersion) {
      return "Available";
    } else if (availVersion == currentVersion ||
        availVersion < currentVersion) {
      return "Updated";
    } else {
      return "None";
    }
  }

  String _status = 'Click the button to download the ZIP file';
  String fwFilePath = "";

  Future<String> downloadFile() async {
    String fwVesion = await _getLatestVersion();
    Directory dir = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      dir = Directory("/storage/emulated/0/Download");
    } else {
      dir = await path_provider.getApplicationDocumentsDirectory();
    }

    final url =
        'https://github.com/Protocentral/healthypi-move-fw/releases/latest/download/healthypi_move_update_v$fwVesion.zip'; // Replace with your URL
    print(url);
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final filePath = '${dir.path}/$fwVesion.zip';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      setState(() {
        _status = 'File downloaded to: $filePath';
        fwFilePath = filePath;
        _latestFWVersion = fwVesion;
      });
    } else {
      setState(() {
        _status = 'Failed to download file';
      });
    }
    print(_status);
    return fwVesion;
  }

  Widget disconnectButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[400],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 2,
          ),
          onPressed: () async {
            await onDisconnectPressed();
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const <Widget>[
              Icon(Icons.cancel_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Disconnect',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateModeSection() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update Mode',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hPi4Global.hpi4Color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _checkingUpdates ? null : _onCheckLatestFirmware,
                    icon: _checkingUpdates 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.cloud_download, size: 20),
                    label: Text(
                      _checkingUpdates ? 'Checking...' : 'Automatic',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hPi4Global.hpi4Color,
                      side: BorderSide(color: hPi4Global.hpi4Color, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _onLoadFirmwareManual,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text(
                      'Manual',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateProgressSection() {
    if (!_isManifestLoaded) return Container();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Firmware Images',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ..._buildImageProgressCards(),
        const SizedBox(height: 16),
        if (!dfuInProgress)
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
                elevation: 2,
              ),
              onPressed: _onStartUpdate,
              icon: const Icon(Icons.upgrade, size: 24),
              label: const Text(
                'Start Update',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildImageProgressCards() {
    final cards = <Widget>[];
    
    for (int i = 0; i < _fw_manifest.files.length; i++) {
      double progress = 0.0;
      switch (i) {
        case 0:
          progress = progressPercentage1;
          break;
        case 1:
          progress = progressPercentage2;
          break;
        case 2:
          progress = progressPercentage3;
          break;
      }
      
      final isUploading = progress > 0 && progress < 100;
      final isComplete = progress >= 100;
      
      cards.add(
        Card(
          elevation: 2,
          color: const Color(0xFF2D2D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isComplete 
                          ? Colors.green[700] 
                          : isUploading 
                            ? hPi4Global.hpi4Color.withOpacity(0.3)
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: isComplete
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fw_manifest.files[i].file,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${((_fw_manifest.files[i].size ?? 0) / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isUploading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            hPi4Global.hpi4Color,
                          ),
                        ),
                      )
                    else if (isComplete)
                      Icon(Icons.check_circle, color: Colors.green[400], size: 20),
                  ],
                ),
                if (progress > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (progress / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              hPi4Global.hpi4Color,
                            ),
                            backgroundColor: Colors.grey[800],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: hPi4Global.hpi4Color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      
      if (i < _fw_manifest.files.length - 1) {
        cards.add(const SizedBox(height: 8));
      }
    }
    
    return cards;
  }

  Widget _buildUpToDateSection() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.green[400],
            ),
            const SizedBox(height: 16),
            Text(
              "Firmware Up to Date",
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Version $_currentFWVersion",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard() {
    if (_showUpdateCard == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Info Card
          Card(
            elevation: 2,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.devices,
                        color: hPi4Global.hpi4Color,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dispConnStatus,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Current: v$_currentFWVersion",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Update Mode Section
          _buildUpdateModeSection(),
          
          // Show "Up to Date" message if firmware is current
          if (_updateAvailable == "Not Available")
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildUpToDateSection(),
            ),
          
          // Show update progress section if firmware is loaded
          if (_isManifestLoaded && _updateAvailable == "Available")
            _buildUpdateProgressSection(),
            
          // Disconnect Button
          const SizedBox(height: 16),
          disconnectButton(),
        ],
      );
    } else {
      return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              await onDisconnectPressed();
              Navigator.of(context).pop();
            },
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widgets.Image.asset(
                'assets/healthypi_move.png',
                height: 28,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              const Text(
                'Firmware Update',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Show loading state
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
            ),
            const SizedBox(height: 20),
            Text(
              _dispConnStatus,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    // Show error state
    if (_errorMessage != null && !_showUpdateCard) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Show device connected state
    if (_showUpdateCard) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildDeviceCard(),
          ],
        ),
      );
    }

    // Show scan screen (fallback if no paired device)
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          // Header
          Text(
            'Connect to Device',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan for your HealthyPi Move device to update firmware',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          buildScanButton(context),
          const SizedBox(height: 20),
          ..._buildScanResultTiles(context),
        ],
      ),
    );
  }
}
