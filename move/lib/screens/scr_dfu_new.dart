import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:mcumgr_flutter/models/firmware_upgrade_mode.dart';
import 'package:mcumgr_flutter/models/image_upload_alignment.dart';

import '../globals.dart';
import '../home.dart';
import '../models/firmware_release.dart';
import '../utils/firmware_update_service.dart';
import '../utils/manifest.dart';
import '../utils/snackbar.dart';

/// DFU Screen States
enum DFUScreenState {
  initializing,       // Connecting to device, reading version
  checkingUpdates,    // Fetching latest release from GitHub
  updateAvailable,    // Update found, showing install option
  downloading,        // Downloading firmware
  readyToInstall,     // Firmware downloaded and ready
  installing,         // DFU in progress
  upToDate,          // No update needed
  error,             // Error occurred
}

/// Modern DFU screen with automatic update detection
class ScrDFUNew extends StatefulWidget {
  final String? deviceMacAddress;

  const ScrDFUNew({super.key, this.deviceMacAddress});

  @override
  State<ScrDFUNew> createState() => _ScrDFUNewState();
}

class _ScrDFUNewState extends State<ScrDFUNew> {
  // Device connection
  BluetoothDevice? _currentDevice;
  List<BluetoothService> _services = [];

  // DFU state
  DFUScreenState _dfuState = DFUScreenState.initializing;
  String? _errorMessage;
  String _currentFWVersion = "Unknown";
  FirmwareRelease? _latestRelease;

  // Firmware files
  Directory? _extractedDir;
  Manifest? _manifest;

  // Progress tracking
  double _downloadProgress = 0.0;
  double _dfuProgress = 0.0;
  final Map<int, double> _imageProgress = {};
  int _currentImageIndex = 0;  // Track which image is currently being uploaded

  // MCU Manager
  final mcumgr.FirmwareUpdateManagerFactory _managerFactory = mcumgr.FirmwareUpdateManagerFactory();
  StreamSubscription<mcumgr.ProgressUpdate>? _updateManagerSubscription;
  StreamSubscription<mcumgr.FirmwareUpgradeState>? _updateStateSubscription;

  // Advanced options
  bool _isManualMode = false;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();

    if (widget.deviceMacAddress != null) {
      _initializeAndCheckUpdates();
    } else {
      setState(() {
        _dfuState = DFUScreenState.error;
        _errorMessage = 'No device specified. Please navigate from Device Management.';
      });
    }
  }

  @override
  void dispose() {
    _updateManagerSubscription?.cancel();
    _updateStateSubscription?.cancel();
    _currentDevice?.disconnect();
    super.dispose();
  }

  /// Load cache size for display
  Future<void> _loadCacheSize() async {
    final size = await FirmwareUpdateService.getCacheSize();
    if (mounted) {
      setState(() {
        _cacheSize = size;
      });
    }
  }

  /// Initialize connection and check for updates
  Future<void> _initializeAndCheckUpdates() async {
    setState(() {
      _dfuState = DFUScreenState.initializing;
      _errorMessage = null;
    });

    try {
      // Step 1: Connect to device
      debugPrint('[DFU] Connecting to device: ${widget.deviceMacAddress}');
      final device = BluetoothDevice.fromId(widget.deviceMacAddress!);
      _currentDevice = device;

      if (device.isDisconnected) {
        await device.connect(license: License.values.first, timeout: const Duration(seconds: 15));
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Step 2: Discover services and read firmware version
      final services = await device.discoverServices();
      _services = services;

      await _readCurrentFirmwareVersion();

      // Step 3: Check for updates from GitHub
      setState(() {
        _dfuState = DFUScreenState.checkingUpdates;
      });

      final latestRelease = await FirmwareUpdateService.getLatestRelease();

      if (latestRelease == null) {
        // Failed to check updates, but device connected
        setState(() {
          _dfuState = DFUScreenState.upToDate;
          _errorMessage = 'Could not check for updates. Check your internet connection.';
        });
        return;
      }

      _latestRelease = latestRelease;

      // Step 4: Compare versions
      final updateAvailable = FirmwareUpdateService.isUpdateAvailable(
        _currentFWVersion,
        latestRelease.version,
      );

      if (updateAvailable) {
        setState(() {
          _dfuState = DFUScreenState.updateAvailable;
        });

        // Step 5: Auto-download firmware in background
        _downloadFirmwareInBackground();
      } else {
        setState(() {
          _dfuState = DFUScreenState.upToDate;
        });
      }
    } catch (e) {
      debugPrint('[DFU] Initialization error: $e');
      if (mounted) {
        setState(() {
          _dfuState = DFUScreenState.error;
          _errorMessage = 'Failed to connect: $e';
        });
      }
    }
  }

  /// Read current firmware version from device
  Future<void> _readCurrentFirmwareVersion() async {
    try {
      for (var service in _services) {
        if (service.uuid == Guid("180a")) {
          // Device Information Service
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid("2a26")) {
              // Firmware Revision String
              final fwVersion = await characteristic.read();
              _currentFWVersion = String.fromCharCodes(fwVersion).trim();
              debugPrint('[DFU] Current firmware version: "$_currentFWVersion"');
              return;
            }
          }
        }
      }
      debugPrint('[DFU] Warning: Firmware version characteristic not found');
      _currentFWVersion = "Unknown";
    } catch (e) {
      debugPrint('[DFU] Failed to read firmware version: $e');
      _currentFWVersion = "Unknown";
    }
  }

  /// Download firmware in background
  Future<void> _downloadFirmwareInBackground() async {
    setState(() {
      _dfuState = DFUScreenState.downloading;
      _downloadProgress = 0.0;
    });

    try {
      final firmwareFile = await FirmwareUpdateService.downloadFirmware(
        _latestRelease!,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = total > 0 ? received / total : 0.0;
            });
          }
        },
      );

      if (firmwareFile == null) {
        throw Exception('Failed to download firmware');
      }

      // Extract and validate
      final extracted = await FirmwareUpdateService.extractFirmware(firmwareFile);
      if (extracted == null) {
        throw Exception('Failed to extract firmware package');
      }

      if (mounted) {
        setState(() {
          _extractedDir = extracted.extractedDir;
          _manifest = extracted.manifest;
          _dfuState = DFUScreenState.readyToInstall;
          _isManualMode = false;
        });
      }

      await _loadCacheSize();
    } catch (e) {
      debugPrint('[DFU] Download failed: $e');
      if (mounted) {
        setState(() {
          _dfuState = DFUScreenState.error;
          _errorMessage = 'Download failed: $e';
        });
      }
    }
  }

  /// Start automatic firmware update
  Future<void> _startFirmwareUpdate() async {
    if (_manifest == null || _extractedDir == null) {
      Snackbar.show(ABC.c, 'Firmware not ready', success: false);
      return;
    }

    setState(() {
      _dfuState = DFUScreenState.installing;
      _dfuProgress = 0.0;
      _imageProgress.clear();
      _currentImageIndex = 0;
    });

    try {
      final updateManager = await _managerFactory.getUpdateManager(
        _currentDevice!.remoteId.toString(),
      );

      updateManager.setup();

      // Load firmware images
      List<mcumgr.Image> fwImages = [];
      for (final file in _manifest!.files) {
        final firmwareFile = File('${_extractedDir!.path}/${file.file}');
        final firmwareFileData = await firmwareFile.readAsBytes();
        final image = mcumgr.Image(image: file.image, data: firmwareFileData);
        fwImages.add(image);
      }

      const fwConfig = mcumgr.FirmwareUpgradeConfiguration(
        estimatedSwapTime: Duration(seconds: 0),
        byteAlignment: ImageUploadAlignment.fourByte,
        eraseAppSettings: true,
        firmwareUpgradeMode: FirmwareUpgradeMode.confirmOnly,
      );

      // Create completer to wait for completion
      final completer = Completer<bool>();

      // Listen to state changes to detect completion
      _updateStateSubscription = updateManager.updateStateStream!.listen((event) {
        debugPrint('[DFU] State: ${event.toString()}');

        // Check for completion state (success is the final state)
        if (event == mcumgr.FirmwareUpgradeState.success) {
          if (!completer.isCompleted) {
            debugPrint('[DFU] Update completed with success state');
            completer.complete(true);
          }
        }
      });

      // Listen to progress updates
      _updateManagerSubscription = updateManager.progressStream.listen((event) {
        if (mounted) {
          setState(() {
            // Match progress to correct image file based on size
            for (int i = 0; i < _manifest!.files.length; i++) {
              if (event.imageSize == _manifest!.files[i].size) {
                final progress = (event.bytesSent / event.imageSize);
                _dfuProgress = progress;
                _imageProgress[i] = progress * 100;
                _currentImageIndex = i;  // Track which image is currently being uploaded

                debugPrint('[DFU] Image ${i + 1}/${_manifest!.files.length}: ${(progress * 100).toStringAsFixed(1)}%');
                break;
              }
            }
          });
        }
      });

      // Start the update (non-blocking)
      updateManager.update(fwImages, configuration: fwConfig);

      // Wait for completion or timeout after 5 minutes
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('[DFU] Update timeout');
          throw TimeoutException('Update took too long');
        },
      );

      // Update completed successfully
      debugPrint('[DFU] Update completed successfully');

      // Show completion dialog
      if (mounted && context.mounted) {
        _showCompletionDialog();
      }
    } catch (e) {
      debugPrint('[DFU] Update error: $e');
      if (mounted) {
        setState(() {
          _dfuState = DFUScreenState.error;
          _errorMessage = 'Update failed: $e';
        });
      }
    }
  }

  /// Show completion dialog
  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[400], size: 28),
            const SizedBox(width: 12),
            const Text('Update Complete', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Firmware update completed successfully. The device will restart.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => HomePage()),
              );
            },
            child: Text('OK', style: TextStyle(color: hPi4Global.hpi4Color)),
          ),
        ],
      ),
    );
  }

  /// Manual firmware selection
  Future<void> _onLoadFirmwareManual() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: 'Select Firmware ZIP File',
      );

      if (result == null) {
        return; // User cancelled
      }

      setState(() {
        _dfuState = DFUScreenState.downloading;
        _downloadProgress = 0.0;
      });

      final file = File(result.files.first.path!);

      // Extract and validate
      final extracted = await FirmwareUpdateService.extractFirmware(file);

      if (extracted == null) {
        throw Exception('Failed to extract firmware. Please check the ZIP file.');
      }

      setState(() {
        _extractedDir = extracted.extractedDir;
        _manifest = extracted.manifest;
        _dfuState = DFUScreenState.readyToInstall;
        _isManualMode = true;
        _latestRelease = null; // Clear automatic release info
      });

      Snackbar.show(ABC.c, 'Manual firmware loaded successfully', success: true);
    } catch (e) {
      setState(() {
        _dfuState = _latestRelease != null ? DFUScreenState.updateAvailable : DFUScreenState.upToDate;
      });

      Snackbar.show(ABC.c, 'Failed to load firmware: $e', success: false);
    }
  }

  /// Force refresh update check
  Future<void> _forceRefreshUpdateCheck() async {
    await FirmwareUpdateService.clearCache();
    await _loadCacheSize();
    await _initializeAndCheckUpdates();
  }

  /// Clear firmware cache
  Future<void> _clearFirmwareCache() async {
    try {
      await FirmwareUpdateService.clearCache();
      await _loadCacheSize();

      Snackbar.show(ABC.c, 'Firmware cache cleared', success: true);
    } catch (e) {
      Snackbar.show(ABC.c, 'Failed to clear cache: $e', success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: hPi4Global.hpi4AppBarColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              await _currentDevice?.disconnect();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
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
    if (_dfuState == DFUScreenState.initializing || _dfuState == DFUScreenState.checkingUpdates) {
      return _buildLoadingState();
    }

    if (_dfuState == DFUScreenState.error && _currentDevice == null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: _forceRefreshUpdateCheck,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildDeviceInfoCard(),
          const SizedBox(height: 16),
          _buildMainSection(),
          const SizedBox(height: 16),
          _buildAdvancedOptionsSection(),
          const SizedBox(height: 16),
          _buildDisconnectButton(),
        ],
      ),
    );
  }

  /// Loading state
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
          ),
          const SizedBox(height: 20),
          Text(
            _dfuState == DFUScreenState.initializing ? 'Connecting to device...' : 'Checking for updates...',
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            _dfuState == DFUScreenState.checkingUpdates ? 'Fetching latest firmware from GitHub' : '',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  /// Error state
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4Color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  /// Device info card
  Widget _buildDeviceInfoCard() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hPi4Global.hpi4Color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.watch, color: hPi4Global.hpi4Color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentDevice?.platformName ?? 'HealthyPi Move',
                    style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Firmware: v$_currentFWVersion',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
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
    );
  }

  /// Main section - shows different content based on state
  Widget _buildMainSection() {
    switch (_dfuState) {
      case DFUScreenState.updateAvailable:
      case DFUScreenState.downloading:
      case DFUScreenState.readyToInstall:
        return _isManualMode ? _buildManualFirmwareCard() : _buildUpdateAvailableCard();

      case DFUScreenState.installing:
        return _buildInstallingCard();

      case DFUScreenState.upToDate:
        return _buildUpToDateCard();

      case DFUScreenState.error:
        return _buildErrorCard();

      default:
        return Container();
    }
  }

  /// Update available card
  Widget _buildUpdateAvailableCard() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[700]!.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.system_update_alt, color: Colors.green[400], size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Update Available', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Version ${_latestRelease?.version ?? "Unknown"}', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Version comparison
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[800]!, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Text('Current', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text('v$_currentFWVersion', style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Icon(Icons.arrow_forward, color: hPi4Global.hpi4Color, size: 24),
                  Column(
                    children: [
                      Text('Latest', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text('v${_latestRelease?.version ?? "Unknown"}', style: TextStyle(fontSize: 18, color: Colors.green[400], fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Release notes (expandable)
            if (_latestRelease?.body != null && _latestRelease!.body.isNotEmpty)
              Theme(
                data: ThemeData.dark(),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('What\'s New', style: TextStyle(color: hPi4Global.hpi4Color, fontSize: 15, fontWeight: FontWeight.w600)),
                  iconColor: hPi4Global.hpi4Color,
                  collapsedIconColor: hPi4Global.hpi4Color,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(8)),
                      child: Text(_latestRelease!.body, style: TextStyle(color: Colors.grey[300], fontSize: 13)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Download progress
            if (_dfuState == DFUScreenState.downloading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Downloading firmware...', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${(_downloadProgress * 100).toStringAsFixed(0)}%', style: TextStyle(color: hPi4Global.hpi4Color, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 8,
                  valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
                  backgroundColor: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dfuState == DFUScreenState.readyToInstall ? hPi4Global.hpi4Color : Colors.grey[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: _dfuState == DFUScreenState.readyToInstall ? 3 : 1,
                ),
                onPressed: _dfuState == DFUScreenState.readyToInstall ? _startFirmwareUpdate : null,
                icon: Icon(_dfuState == DFUScreenState.downloading ? Icons.cloud_download : Icons.upgrade, size: 22),
                label: Text(_dfuState == DFUScreenState.downloading ? 'Preparing Update...' : 'Install Update', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Manual firmware card (when loaded from file)
  Widget _buildManualFirmwareCard() {
    return Card(
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[700]!.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.folder_special, color: Colors.orange[400], size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Manual Firmware Loaded', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${_manifest?.files.length ?? 0} firmware images ready', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[900]!.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[700]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[400], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Advanced mode: Ensure firmware compatibility', style: TextStyle(color: Colors.orange[300], fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Install button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 3,
                ),
                onPressed: _startFirmwareUpdate,
                icon: const Icon(Icons.upgrade, size: 22),
                label: const Text('Install Manual Firmware', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Installing card (DFU in progress)
  Widget _buildInstallingCard() {
    final totalImages = _manifest?.files.length ?? 1;
    final currentImage = _currentImageIndex + 1;

    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            CircularProgressIndicator(
              value: _dfuProgress,
              valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
              strokeWidth: 6,
            ),
            const SizedBox(height: 20),
            const Text('Installing Firmware...', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Image $currentImage of $totalImages - ${(_dfuProgress * 100).toStringAsFixed(0)}% complete',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            Text('Do not disconnect the device', style: TextStyle(fontSize: 13, color: Colors.red[300])),
          ],
        ),
      ),
    );
  }

  /// Up to date card
  Widget _buildUpToDateCard() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green[400]),
            const SizedBox(height: 16),
            const Text('Firmware Up to Date', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Version $_currentFWVersion', style: TextStyle(fontSize: 15, color: Colors.grey[400])),
            if (_latestRelease != null) ...[
              const SizedBox(height: 4),
              Text('Latest available: ${_latestRelease!.version}', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[900]!.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[400], size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.orange[300], fontSize: 12))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Error card
  Widget _buildErrorCard() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            const Text('Update Error', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'An error occurred', style: TextStyle(fontSize: 14, color: Colors.grey[400]), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: hPi4Global.hpi4Color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              ),
              onPressed: _forceRefreshUpdateCheck,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Retry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Advanced options section
  Widget _buildAdvancedOptionsSection() {
    return Card(
      elevation: 2,
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: ThemeData.dark(),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              Icon(Icons.settings, color: Colors.grey[400], size: 20),
              const SizedBox(width: 12),
              const Text('Advanced Options', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          iconColor: Colors.grey[400],
          collapsedIconColor: Colors.grey[400],
          children: [
            // Description
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[900]!.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[800]!.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[400], size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('For advanced users: Install custom or beta firmware', style: TextStyle(color: Colors.orange[300], fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Manual firmware selection button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: hPi4Global.hpi4Color,
                  side: BorderSide(color: hPi4Global.hpi4Color, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _dfuState != DFUScreenState.installing ? _onLoadFirmwareManual : null,
                icon: const Icon(Icons.folder_open, size: 20),
                label: const Text('Select Firmware File (.zip)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),

            // Force re-check button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[400],
                  side: BorderSide(color: Colors.grey[700]!, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _dfuState != DFUScreenState.installing ? _forceRefreshUpdateCheck : null,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Force Check for Updates', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),

            // Clear cache button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[400],
                  side: BorderSide(color: Colors.grey[700]!, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _dfuState != DFUScreenState.installing ? _clearFirmwareCache : null,
                icon: const Icon(Icons.cleaning_services, size: 20),
                label: Text(
                  'Clear Cache (${FirmwareUpdateService.formatCacheSize(_cacheSize)})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Disconnect button
  Widget _buildDisconnectButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[400],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 2,
        ),
        onPressed: () async {
          await _currentDevice?.disconnect();
          if (mounted) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage()));
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cancel_outlined, color: Colors.white),
            SizedBox(width: 8),
            Text('Disconnect', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
