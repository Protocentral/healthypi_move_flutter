import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
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
import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'package:uuid/uuid.dart';
import 'package:version/version.dart';

import '../globals.dart';
import '../home.dart';
import '../utils/manifest.dart';
import '../widgets/scan_result_tile.dart';
import '../widgets/system_device_tile.dart';
import 'scr_device.dart';

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
  bool _updateAvailable = false;
  bool _showUpdateCard = false;
  bool _checkingUpdates = false;

  late BluetoothDevice _currentDevice;
  List<BluetoothService> _services = [];

  late StreamSubscription _streamDebug;

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
    Map<Permission, PermissionStatus> statuses = await [
      Permission.manageExternalStorage,
      Permission.storage,
    ].request();

    if (statuses.containsValue(PermissionStatus.denied)) {

    }
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
        withServices: [
          // Guid("180f"), // battery
          // Guid("180a"), // device info
          // Guid("1800"), // generic access
          // Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
        ],
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
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: hPi4Global.hpi4Color, // background color
          foregroundColor: Colors.white, // text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed: _onStopPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[const Icon(Icons.stop), Spacer()],
          ),
        ),
      );
    } else {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: hPi4Global.hpi4Color, // background color
          foregroundColor: Colors.white, // text color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          //minimumSize: Size(SizeConfig.blockSizeHorizontal * 20, 40),
        ),
        onPressed: _onScanPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.search, color: Colors.white),
              const Text(
                ' Scan for devices ',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Spacer(),
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
    late final firmwareFile;

    if(fwFilePath == ""){
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

      firmwareFile = File('${tempDir.path}/firmware.zip');
      await firmwareFile.writeAsBytes(firmwareFileData);

      destinationDir = Directory('${tempDir.path}/firmware');
      await destinationDir.create();


    }else{
      showLoadingIndicator("Checking for firmware...", context);

      final file = File(fwFilePath);
      final Uint8List firmwareFileData = await file.readAsBytes();

      final prefix = 'firmware_${Uuid().v4()}';
      final systemTempDir = await path_provider.getTemporaryDirectory();

      final tempDir = Directory('${systemTempDir.path}/$prefix');
      await tempDir.create();

      final firmwareFile = File('${tempDir.path}/firmware.zip');
      await firmwareFile.writeAsBytes(firmwareFileData);

      destinationDir = Directory('${tempDir.path}/firmware');
      await destinationDir.create();

      Navigator.pop(context);
    }

    try {
      await ZipFile.extractToDirectory(
        zipFile: firmwareFile,
        destinationDir: destinationDir,
      );
    } catch (e) {
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

    List <mcumgr.Image> _fw_images = [];
    for (final file in _fw_manifest.files) {
      final firmwareFile = File('${destinationDir.path}/${file.file}');
      final firmwareFileData = await firmwareFile.readAsBytes();
      final image = mcumgr.Image(
        image: file.image,
        data: firmwareFileData,
      );
      _fw_images.add(image);
    }

    final _fw_config = const FirmwareUpgradeConfiguration(estimatedSwapTime: Duration(seconds: 0),
        byteAlignment: ImageUploadAlignment.fourByte, eraseAppSettings: true,
        firmwareUpgradeMode: FirmwareUpgradeMode.confirmOnly );

    _updateManagerSubscription = updateManager.progressStream.listen((event) {
      if (mounted) {
        setState(() {
          if(event.imageSize == _fw_manifest.files[0].size){
            progressPercentage1 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          }else if(event.imageSize == _fw_manifest.files[1].size){
            progressPercentage2 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          }else if(event.imageSize == _fw_manifest.files[2].size){
            progressPercentage3 = (event.bytesSent / event.imageSize) * 100;
            dfuProgress = (event.bytesSent / event.imageSize);
            print("DFU progress: ${event.bytesSent} / ${event.imageSize}");
          }else{

          }

        });
      }
    });

    updateManager.update(_fw_images, configuration: _fw_config);

    //updateManager.kill();

    //Navigator.pop(context);
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

  void _onConnectPressed(BluetoothDevice device) {
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
        onTap: () => _onConnectPressed(r.device),
      ),
    )
        .toList();
  }

  Widget _getFirmwareInfo() {
    if (_isManifestLoaded == true) {
      return Column(
        children: [
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: <Widget>[
                  Text("Image name: ${_fw_manifest.files[0].file}", style: const TextStyle(color: Colors.white)),
                  Text("Size: ${_fw_manifest.files[0].size}",style: const TextStyle(color: Colors.white)),
                  Text("Version: ${_fw_manifest.files[0].versionMcuboot}",style: const TextStyle(color: Colors.white)),
                  SizedBox(
                    height: 10, // Adjust this value to increase or decrease height
                    child: LinearProgressIndicator(
                      value: (progressPercentage1/100),
                      valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: <Widget>[
                  Text("Image name: ${_fw_manifest.files[2].file}",style: const TextStyle(color: Colors.white)),
                  Text("Size: ${_fw_manifest.files[2].size}",style: const TextStyle(color: Colors.white)),
                  Text("Version: ${_fw_manifest.files[2].version}",style: const TextStyle(color: Colors.white)),
                  SizedBox(
                    height: 10, // Adjust this value to increase or decrease height
                    child: LinearProgressIndicator(
                      value: (progressPercentage3/100),
                      valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                      backgroundColor: Colors.white24,
                    ),
                  ),

                ],
              ),
            ),
          ),
          Card(
            color: Colors.grey[900],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: <Widget>[
                  Text("Image name: ${_fw_manifest.files[1].file}",style: const TextStyle(color: Colors.white)),
                  Text("Size: ${_fw_manifest.files[1].size}",style: const TextStyle(color: Colors.white)),
                  Text("Version: ${_fw_manifest.files[1].versionMcuboot}",style: const TextStyle(color: Colors.white)),
                  SizedBox(
                    height: 10, // Adjust this value to increase or decrease height
                    child: LinearProgressIndicator(
                      value: (progressPercentage2/100),
                      valueColor: const AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                      backgroundColor: Colors.white24,
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
    final url = Uri.parse('https://api.github.com/repos/Protocentral/healthypi-move-fw/tags');
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

    List<String> tagsWithoutV = tags.map((tag) => tag.startsWith('v') ? tag.substring(1) : tag).toList();

    // Print the new list
    print(tagsWithoutV);

    for (int i = 0; i < tagsWithoutV.length; i++) {
      _latestFWVersion = _getAvailableLatestVersion(_latestFWVersion, tagsWithoutV[i]);
    }

    return _latestFWVersion;
  }

  String _getAvailableLatestVersion(String versionCurrent, String versionAvail) {
    Version availVersion = Version.parse(versionAvail);
    Version currentVersion = Version.parse(versionCurrent);

    if (availVersion > currentVersion) {
      //print("...........availble"+versionAvail);
      return versionAvail;
    } else {
      //print("...........current"+versionCurrent);
      return versionCurrent;
    }
  }


  String _status = 'Click the button to download the ZIP file';
  String fwFilePath = "";

  Future<void> downloadFile() async {
    String fwVesion = await _getLatestVersion();
    Directory  dir = Directory("");
    if (Platform.isAndroid) {
      // Redirects it to download folder in android
      dir = Directory("/storage/emulated/0/Download/");
    } else {
      dir = await path_provider.getApplicationDocumentsDirectory();
    }

    final url = 'https://github.com/Protocentral/healthypi-move-fw/releases/latest/download/healthypi_move_update_v$fwVesion.zip'; // Replace with your URL
    print(url);
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final filePath = '${dir.path}/$fwVesion.zip';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      setState(() {
        _status = 'File downloaded to: $filePath';
        fwFilePath = filePath;
      });
    } else {
      setState(() {
        _status = 'Failed to download file';
      });
    }

    print(_status);
  }

  Widget _buildDeviceCard() {
    if (_showUpdateCard == true &&
        //_updateAvailable == true &&
        _checkingUpdates == false) {
      return Card(
        color: Colors.grey[900],
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(_dispConnStatus, style: TextStyle(fontSize: 16,color: Colors.white)),
              Text(
                "Firmware version: $_currentFWVersion",
                style: TextStyle(fontSize: 16,color: Colors.white),
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
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Loaded Firmware",style: TextStyle(fontSize: 14,color: Colors.white)),
              ),
              _getFirmwareInfo(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "Updating FW Image:  ${(dfuProgress * 100).toStringAsFixed(0)} %",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hPi4Global.hpi4Color, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async {
                    await downloadFile();
                    _onLoadFirmware();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.upgrade, color: Colors.white),
                        const Text(
                          ' DFU Update ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child:  ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // background color
                    foregroundColor: Colors.white, // text color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () async {
                    await onDisconnectPressed();
                    Navigator
                        .of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => HomePage()));
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.stop_rounded, color: Colors.white),
                        const Text(
                          ' Disconnect ',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_showUpdateCard == true &&
        _updateAvailable == false &&
        _checkingUpdates == false) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Card(
          color: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "Your device already runs the latest firmware ( $_currentFWVersion )",
                    style: TextStyle(fontSize: 20,color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
                Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
              ],
            ),
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
        backgroundColor: hPi4Global.appBackgroundColor,
        appBar: AppBar(
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                onDisconnectPressed();
                Navigator
                    .of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => HomePage()));
              }
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              material.Image.asset(
                'assets/healthypi_move.png',
                fit: BoxFit.fitWidth,
                height: 30,
              ),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            children: <Widget>[
              Column(
                  children:[
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Select the device to update',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(64, 8, 64, 8),
                      child: buildScanButton(context),
                    ),
                  ]
              ),
              ..._buildScanResultTiles(context),
              _buildDeviceCard(),
            ],
          ),
        ),
      ),
    );
  }
}

