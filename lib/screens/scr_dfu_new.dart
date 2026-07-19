// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import '../ble/device_info.dart';
import '../ble/firmware_updater.dart';
import '../models/firmware_release.dart';
import '../smp/smp_ble_transport.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/ble_dis_transport.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';
import '../utils/firmware_update_service.dart';
import '../utils/manifest.dart';
import '../utils/snackbar.dart';
import 'scr_main_shell.dart';

/// DFU Screen States
enum DFUScreenState {
  initializing,       // Connecting to device, reading version
  checkingUpdates,    // Fetching latest release from GitHub
  updateAvailable,    // Update found, showing install option
  downloading,        // Downloading firmware
  readyToInstall,     // Firmware downloaded and ready
  installing,         // DFU in progress
  completed,         // Install finished successfully
  upToDate,          // No update needed
  error,             // Error occurred
}

/// DFU firmware-update screen (handoff 5a). Restyled to the redesign token
/// system; the install flow itself is unchanged — the `DFUScreenState` machine
/// here plus the extracted [FirmwareUpdater] (upload→confirm walk over
/// `mcumgr_dart` `ImgMgmt`, confirm-only per image).
class ScrDFUNew extends StatefulWidget {
  final String? deviceMacAddress;

  const ScrDFUNew({super.key, this.deviceMacAddress});

  @override
  State<ScrDFUNew> createState() => _ScrDFUNewState();
}

class _ScrDFUNewState extends State<ScrDFUNew> {
  // Device connection
  final ConnectionManager _conn = ConnectionManager.instance;
  String? _deviceMac;
  String _deviceName = 'HealthyPi Move';

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

  // SMP DFU session (ported img_mgmt over universal_ble)
  SmpBleTransport? _dfuTransport;
  SmpClient? _dfuClient;

  /// The install state machine (upload + confirm walk); the screen is its view.
  FirmwareUpdater? _updater;

  /// Token for the SMP wire, held for the duration of the image upload.
  Object? _smpToken;

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
    // Stop the upload walk before the next image if we're torn down mid-update.
    _updater?.cancel();
    _updater?.dispose();
    _dfuClient?.dispose();
    _dfuTransport?.dispose();
    // Free the SMP wire if the screen is torn down mid-update, otherwise the
    // lock outlives the flow and blocks every later sync/DFU.
    _conn.releaseSmp(_smpToken);
    _smpToken = null;
    _conn.disconnect();
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
      // Step 1: Connect to device (scan-assisted connect + service discovery)
      debugPrint('[DFU] Connecting to device: ${widget.deviceMacAddress}');
      _deviceMac = widget.deviceMacAddress!;
      final paired = await DeviceManager.getPairedDevice();
      if (paired != null) _deviceName = paired.displayName;

      await _conn.connect(_deviceMac!, name: _deviceName);
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Read firmware version
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

  /// Read current firmware version from device (DIS 0x180A → 0x2A26).
  Future<void> _readCurrentFirmwareVersion() async {
    final reader = DeviceInfoReader(
      BleDisTransport(_deviceMac!),
      log: (m) => debugPrint('[DFU] $m'),
    );
    final version = await reader.readFirmwareVersion();
    _currentFWVersion = version ?? 'Unknown';
    debugPrint('[DFU] Current firmware version: "$_currentFWVersion"');
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
      // Claim the SMP wire for the whole upload — a background sync landing
      // mid-upload would interleave frames on the SMP characteristic and
      // corrupt the image.
      _smpToken = _conn.acquireSmp('dfu');

      // SMP session riding the existing ConnectionManager link.
      final transport = SmpBleTransport(_deviceMac!, manageConnection: false);
      await transport.connect();
      _dfuTransport = transport;
      final client = SmpClient(transport);
      _dfuClient = client;
      final img =
          ImgMgmt(client, maxWriteLength: () => _dfuTransport?.maxWriteLength);
      await transport.refreshMtu(); // ensure a large chunk size

      // Drive the upload + confirm walk through the extracted state machine
      // (MCUboot confirmOnly per image); the screen just mirrors its progress.
      final updater = FirmwareUpdater(
        _ImgMgmtUploadTransport(img),
        log: (m) => debugPrint('[DFU] $m'),
      );
      _updater = updater;
      updater.addListener(_onUpdaterProgress);

      final images = _manifest!.files
          .map((f) => FirmwareImage(
                imageIndex: f.image,
                name: f.file,
                load: () =>
                    File('${_extractedDir!.path}/${f.file}').readAsBytes(),
              ))
          .toList();

      try {
        await updater.run(images);
      } finally {
        updater.removeListener(_onUpdaterProgress);
      }

      debugPrint('[DFU] Update completed successfully');

      // Release the SMP session (keeps the ConnectionManager link).
      await _dfuClient?.dispose();
      _dfuClient = null;
      await _dfuTransport?.disconnect();
      await _dfuTransport?.dispose();
      _dfuTransport = null;
      _conn.releaseSmp(_smpToken);
      _smpToken = null;

      if (mounted) {
        setState(() => _dfuState = DFUScreenState.completed);
      }
    } catch (e) {
      debugPrint('[DFU] Update error: $e');
      await _dfuClient?.dispose();
      _dfuClient = null;
      await _dfuTransport?.dispose();
      _dfuTransport = null;
      _conn.releaseSmp(_smpToken);
      _smpToken = null;
      // A user-cancelled update (screen torn down mid-upload) isn't an error to
      // surface — the widget is already gone.
      if (mounted && e is! FirmwareUpdateCancelled) {
        setState(() {
          _dfuState = DFUScreenState.error;
          _errorMessage = e is SmpBusyException
              ? 'Device busy (${e.currentOwner}). Wait for it to finish, '
                  'then retry the update.'
              : 'Update failed: $e';
        });
      }
    }
  }

  /// Mirror the [FirmwareUpdater]'s progress into the installing-card UI.
  void _onUpdaterProgress() {
    final u = _updater;
    if (u == null || !mounted) return;
    setState(() {
      _currentImageIndex = u.currentImageIndex;
      _dfuProgress = u.currentImageProgress;
      _imageProgress[u.currentImageIndex] = u.currentImageProgress * 100;
    });
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

  bool get _installing => _dfuState == DFUScreenState.installing;

  /// Installing or completed — a focused card with no device/advanced chrome.
  bool get _terminal =>
      _dfuState == DFUScreenState.installing ||
      _dfuState == DFUScreenState.completed;

  // --- Presentation: redesigned firmware-update flow (handoff 5a) -----------

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        backgroundColor: HpiColors.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: HpiColors.background,
          leading: IconButton(
            // A close (not back) affordance while installing — leaving mid-flow
            // is unsafe, so it stays a deliberate tap that tears the flow down.
            icon: Icon(_installing ? Symbols.close : Symbols.arrow_back,
                color: HpiColors.onSurfaceBright),
            onPressed: () async {
              final nav = Navigator.of(context);
              await _conn.disconnect();
              if (mounted) nav.maybePop();
            },
          ),
          title: Text('Firmware update', style: HpiText.appBarTitle),
          centerTitle: false,
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_dfuState == DFUScreenState.initializing ||
        _dfuState == DFUScreenState.checkingUpdates) {
      return _loadingState();
    }

    if (_dfuState == DFUScreenState.error && _deviceMac == null) {
      return _fatalErrorState();
    }

    return RefreshIndicator(
      color: HpiColors.hr,
      backgroundColor: HpiColors.surfaceContainer,
      onRefresh: _forceRefreshUpdateCheck,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (!_terminal) ...[
            _deviceCard(),
            const SizedBox(height: 12),
          ],
          _mainSection(),
          if (!_terminal) ...[
            const SizedBox(height: 12),
            _advancedOptions(),
          ],
        ],
      ),
    );
  }

  Widget _loadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(HpiColors.hr),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _dfuState == DFUScreenState.initializing
                ? 'Connecting to device…'
                : 'Checking for updates…',
            style: HpiText.cardTitle,
          ),
          const SizedBox(height: 6),
          Text(
            _dfuState == DFUScreenState.checkingUpdates
                ? 'Fetching the latest firmware from GitHub'
                : 'Reading firmware version',
            style: HpiText.supporting,
          ),
        ],
      ),
    );
  }

  Widget _fatalErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Symbols.error, size: 56, color: HpiColors.error),
            const SizedBox(height: 18),
            Text(_errorMessage ?? 'An error occurred',
                style: HpiText.body.copyWith(fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            SizedBox(
              width: 200,
              child: HpiFilledButton(
                label: 'Go back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Connected-device summary card (watch tile · FW · MAC · CONNECTED pill).
  Widget _deviceCard() {
    return HpiCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2A333B), width: 4),
            ),
            child: const Icon(Symbols.watch, size: 20, color: HpiColors.hr),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_deviceName, style: HpiText.cardTitle.copyWith(fontSize: 14.5)),
                const SizedBox(height: 3),
                Text('FW $_currentFWVersion · ${_deviceMac ?? "—"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HpiText.mono.copyWith(fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const HpiPill(label: 'CONNECTED', color: HpiColors.steps),
        ],
      ),
    );
  }

  Widget _mainSection() {
    switch (_dfuState) {
      case DFUScreenState.updateAvailable:
      case DFUScreenState.downloading:
      case DFUScreenState.readyToInstall:
        return _isManualMode ? _manualCard() : _updateAvailableCard();
      case DFUScreenState.installing:
        return _installingCard();
      case DFUScreenState.completed:
        return _completeCard();
      case DFUScreenState.upToDate:
        return _upToDateCard();
      case DFUScreenState.error:
        return _errorCard();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Update-available / downloading / ready-to-install card.
  Widget _updateAvailableCard() {
    final ready = _dfuState == DFUScreenState.readyToInstall;
    final downloading = _dfuState == DFUScreenState.downloading;
    return HpiCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HpiIconSquare(
                  icon: Symbols.system_update_alt,
                  color: HpiColors.steps,
                  size: 40,
                  iconSize: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update available', style: HpiText.appBarTitle),
                    const SizedBox(height: 2),
                    Text('Version ${_latestRelease?.version ?? "—"}',
                        style: HpiText.supporting),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _versionCompare(_currentFWVersion, _latestRelease?.version ?? '—'),
          if (_latestRelease?.body.isNotEmpty ?? false) ...[
            const SizedBox(height: 14),
            _whatsNew(_latestRelease!.body),
          ],
          const SizedBox(height: 14),
          Text(
            downloading
                ? 'Downloading firmware…'
                : '${_manifest?.files.length ?? "—"} images · '
                    'ready to install',
            style: HpiText.mono.copyWith(fontSize: 10.5),
          ),
          if (downloading) ...[
            const SizedBox(height: 8),
            _linearBar(_downloadProgress),
            const SizedBox(height: 4),
            Text('${(_downloadProgress * 100).toStringAsFixed(0)}%',
                style: HpiText.mono.copyWith(color: HpiColors.hr)),
          ],
          const SizedBox(height: 16),
          HpiFilledButton(
            label: ready ? 'Install update' : 'Preparing update…',
            icon: ready ? Symbols.upgrade : Symbols.cloud_download,
            onPressed: ready ? _startFirmwareUpdate : null,
          ),
        ],
      ),
    );
  }

  Widget _versionCompare(String current, String latest) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: HpiColors.chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _versionCol('CURRENT', current, HpiColors.onSurface),
          const Icon(Symbols.arrow_forward, size: 20, color: HpiColors.hr),
          _versionCol('LATEST', latest, HpiColors.steps),
        ],
      ),
    );
  }

  Widget _versionCol(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 9)),
        const SizedBox(height: 8),
        Text(value, style: HpiText.statChip.copyWith(color: valueColor)),
      ],
    );
  }

  /// Collapsible release-notes ("What's new").
  Widget _whatsNew(String body) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text("What's new",
            style: HpiText.cardTitle.copyWith(color: HpiColors.hr)),
        iconColor: HpiColors.hr,
        collapsedIconColor: HpiColors.hr,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HpiColors.chipBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(body,
                style: HpiText.body
                    .copyWith(fontSize: 11.5, color: HpiColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _manualCard() {
    return HpiCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HpiIconSquare(
                  icon: Symbols.folder_special,
                  color: HpiColors.temp,
                  size: 40,
                  iconSize: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manual firmware loaded', style: HpiText.appBarTitle),
                    const SizedBox(height: 2),
                    Text('${_manifest?.files.length ?? 0} images ready',
                        style: HpiText.supporting),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _noticeBanner(
            Symbols.warning_amber,
            HpiColors.temp,
            'Advanced mode — ensure firmware compatibility with this watch.',
          ),
          const SizedBox(height: 16),
          HpiFilledButton(
            label: 'Install manual firmware',
            icon: Symbols.upgrade,
            color: HpiColors.temp,
            onPressed: _startFirmwareUpdate,
          ),
        ],
      ),
    );
  }

  /// DFU in progress — amber ring, image counter, "do not disconnect".
  Widget _installingCard() {
    final total = _manifest?.files.length ?? 1;
    final current = _currentImageIndex + 1;
    return HpiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: _dfuProgress,
                    strokeWidth: 8,
                    backgroundColor: HpiColors.dividerStrong,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(HpiColors.hr),
                  ),
                ),
                Text('${(_dfuProgress * 100).toStringAsFixed(0)}%',
                    style: HpiText.heroNumberSm.copyWith(fontSize: 30)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Installing firmware', style: HpiText.appBarTitle),
          const SizedBox(height: 6),
          Text('Image $current of $total',
              style: HpiText.mono.copyWith(fontSize: 11)),
          const SizedBox(height: 16),
          _linearBar(_dfuProgress),
          const SizedBox(height: 18),
          _noticeBanner(
            Symbols.warning,
            HpiColors.error,
            'Do not disconnect the watch while installing.',
          ),
        ],
      ),
    );
  }

  /// Update complete — green check, WAS→NOW chip, Done → root.
  Widget _completeCard() {
    return HpiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Symbols.check_circle, size: 84, color: HpiColors.steps),
          const SizedBox(height: 16),
          Text('Update complete', style: HpiText.screenTitle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text('The watch will restart and reconnect.',
              style: HpiText.body.copyWith(fontSize: 12.5),
              textAlign: TextAlign.center),
          if (_latestRelease != null) ...[
            const SizedBox(height: 16),
            _versionCompare(_currentFWVersion, _latestRelease!.version),
          ],
          const SizedBox(height: 20),
          HpiFilledButton(
            label: 'Done',
            onPressed: () => ScrMainShell.returnToRoot(context),
          ),
        ],
      ),
    );
  }

  Widget _upToDateCard() {
    return HpiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Symbols.check_circle, size: 64, color: HpiColors.steps),
          const SizedBox(height: 14),
          Text('Firmware up to date',
              style: HpiText.screenTitle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text('Version $_currentFWVersion',
              style: HpiText.body.copyWith(fontSize: 13)),
          if (_latestRelease != null) ...[
            const SizedBox(height: 4),
            Text('Latest available: ${_latestRelease!.version}',
                style: HpiText.supporting),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _noticeBanner(Symbols.info, HpiColors.temp, _errorMessage!),
          ],
        ],
      ),
    );
  }

  Widget _errorCard() {
    return HpiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Symbols.error, size: 64, color: HpiColors.error),
          const SizedBox(height: 14),
          Text('Update error', style: HpiText.screenTitle.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'An error occurred',
              style: HpiText.body.copyWith(fontSize: 12.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          SizedBox(
            width: 180,
            child: HpiFilledButton(
              label: 'Retry',
              icon: Symbols.refresh,
              onPressed: _forceRefreshUpdateCheck,
            ),
          ),
        ],
      ),
    );
  }

  /// Advanced options: manual .zip, force re-check, clear cache.
  Widget _advancedOptions() {
    return HpiCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Symbols.settings,
              size: 20, color: HpiColors.onSurfaceVariant),
          title: Text('Advanced options', style: HpiText.cardTitle),
          iconColor: HpiColors.onSurfaceVariant,
          collapsedIconColor: HpiColors.onSurfaceVariant,
          children: [
            _noticeBanner(Symbols.info, HpiColors.temp,
                'For advanced users: install custom or beta firmware.'),
            const SizedBox(height: 12),
            _outlinedAction(Symbols.folder_open, 'Select firmware file (.zip)',
                _installing ? null : _onLoadFirmwareManual),
            const SizedBox(height: 10),
            _outlinedAction(Symbols.refresh, 'Force check for updates',
                _installing ? null : _forceRefreshUpdateCheck),
            const SizedBox(height: 10),
            _outlinedAction(
                Symbols.cleaning_services,
                'Clear cache (${FirmwareUpdateService.formatCacheSize(_cacheSize)})',
                _installing ? null : _clearFirmwareCache),
          ],
        ),
      ),
    );
  }

  // --- small shared pieces --------------------------------------------------

  Widget _linearBar(double value) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: HpiColors.dividerStrong,
        valueColor: const AlwaysStoppedAnimation<Color>(HpiColors.hr),
      ),
    );
  }

  Widget _noticeBanner(IconData icon, Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HpiMetricColors.tint(color, 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HpiMetricColors.tint(color, 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: HpiText.body.copyWith(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _outlinedAction(IconData icon, String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    final fg = disabled ? HpiColors.disabled : HpiColors.onSurfaceBright;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: HpiColors.dividerStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(label,
                        style: HpiText.cardTitle
                            .copyWith(fontSize: 13, color: fg))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Binds the SDK-ready [FirmwareUploadTransport] seam to `mcumgr_dart`'s
/// `ImgMgmt` over the live SMP session. The only piece that touches both the
/// state machine and the wire — it moves to the app/SDK boundary, never into
/// the pure-Dart `mcumgr_dart` package.
class _ImgMgmtUploadTransport implements FirmwareUploadTransport {
  _ImgMgmtUploadTransport(this._img);

  final ImgMgmt _img;

  @override
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  }) =>
      _img.upload(image, imageIndex: imageIndex, onProgress: onProgress);

  @override
  Future<void> confirm(List<int> sha) => _img.confirm(sha);
}
