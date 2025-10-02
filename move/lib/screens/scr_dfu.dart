import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
  const ScrDFU({super.key});

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
    super.initState();
  }

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

  void _onLoadFirmware() async {
    Uint8List? zipFile;
    List<mcumgr.Image>? firmwareImages;
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
      });
    }

    final updateManager = await _managerFactory.getUpdateManager(
      _currentDevice.remoteId.toString(),
    );

    final updateStream = updateManager.setup();

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
          if (event.imageSize == _fw_manifest.files[0].size) {
            progressPercentage1 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          } else if (event.imageSize == _fw_manifest.files[1].size) {
            progressPercentage2 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          } else if (event.imageSize == _fw_manifest.files[2].size) {
            progressPercentage3 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          } else {}
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

  Widget _getFirmwareInfo() {
    if (_isManifestLoaded == true) {
      return Column(
        children: [
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Image: ${_fw_manifest.files[0].file}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Size: ${_fw_manifest.files[0].size}",
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                      Text(
                        "v${_fw_manifest.files[0].versionMcuboot}",
                        style: TextStyle(
                          color: hPi4Global.hpi4Color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (progressPercentage1 / 100),
                      minHeight: 8,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        hPi4Global.hpi4Color,
                      ),
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Image: ${_fw_manifest.files[2].file}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Size: ${_fw_manifest.files[2].size}",
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                      Text(
                        "v${_fw_manifest.files[2].version}",
                        style: TextStyle(
                          color: hPi4Global.hpi4Color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (progressPercentage3 / 100),
                      minHeight: 8,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        hPi4Global.hpi4Color,
                      ),
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 4,
            shadowColor: Colors.black54,
            color: const Color(0xFF2D2D2D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Image: ${_fw_manifest.files[1].file}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Size: ${_fw_manifest.files[1].size}",
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                      Text(
                        "v${_fw_manifest.files[1].versionMcuboot}",
                        style: TextStyle(
                          color: hPi4Global.hpi4Color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (progressPercentage2 / 100),
                      minHeight: 8,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        hPi4Global.hpi4Color,
                      ),
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return Container();
    }
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

  Widget loadLatestFWAvailable() {
    if (_updateAvailable == "Available" && _showUpdateCard == true) {
      return Card(
        elevation: 4,
        shadowColor: Colors.black54,
        color: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              Text(
                "Firmware Package Loaded",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _getFirmwareInfo(),
              if (dfuProgress > 0) ...[
                const SizedBox(height: 20),
                Text(
                  "Updating: ${(dfuProgress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: dfuProgress,
                    minHeight: 8,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      hPi4Global.hpi4Color,
                    ),
                    backgroundColor: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
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
                    onPressed: () async {
                      _onLoadFirmware();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const <Widget>[
                        Icon(Icons.upgrade, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Start Update',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              disconnectButton(),
            ],
          ),
        ),
      );
    } else if (_updateAvailable == "Not Available" && _showUpdateCard == true) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          elevation: 4,
          shadowColor: Colors.black54,
          color: const Color(0xFF2D2D2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.green[400],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    "Your device already runs the latest firmware",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Version $_currentFWVersion",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                disconnectButton(),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container();
    }
  }

  Widget _buildDeviceCard() {
    if (_showUpdateCard == true) {
      return Card(
        elevation: 4,
        shadowColor: Colors.black54,
        color: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                _dispConnStatus,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Firmware version: $_currentFWVersion",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Latest version: $_latestFWVersion",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  onPressed: () async {
                    String checkfw = await downloadFile();
                    String resultfw = _CompareFWVersion(
                      _currentFWVersion,
                      checkfw,
                    );
                    print("...........availble" + resultfw);
                    if (resultfw == "Available") {
                      setState(() {
                        _updateAvailable = "Available";
                      });
                    } else {
                      setState(() {
                        _updateAvailable = "Not Available";
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.check, color: Colors.white),
                        const Text(
                          ' Check Latest Firmware ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              loadLatestFWAvailable(),
            ],
          ),
        ),
      );
    } else
      return Container();
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
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              onDisconnectPressed();
              Navigator.of(
                context,
              ).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
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
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (!_showUpdateCard) ...[
                const Text(
                  'Select Your Device',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a device to update its firmware',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                buildScanButton(context),
                const SizedBox(height: 20),
              ],
              ..._buildScanResultTiles(context),
              _buildDeviceCard(),
            ],
          ),
        ),
      ),
    );
  }
}
