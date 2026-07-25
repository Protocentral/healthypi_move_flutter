// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import '../ble/device_generation.dart';
import '../ble/device_info.dart';
import '../ble/dfu_plan.dart';
import '../ble/firmware_updater.dart';
import '../models/firmware_release.dart';
import '../smp/smp_ble_transport.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/ble_dis_transport.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';
import '../utils/dfu_stage_state.dart';
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
  awaitingReboot,     // Leg 1 installed; waiting for the watch to restart on v3
  radioUpdateReady,   // Watch is on v3; the radio (net core) image is still owed
  completed,         // Install finished successfully
  upToDate,          // No update needed
  error,             // Error occurred
}

/// DFU firmware-update screen (handoff 5a). Restyled to the redesign token
/// system; the install flow itself is unchanged — the `DFUScreenState` machine
/// here plus the extracted [FirmwareUpdater] (upload→stage walk over
/// `mcumgr_dart` `ImgMgmt`: each image is uploaded then marked for the next
/// boot, and the screen resets the watch once they all are).
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

  /// Which firmware generation the watch is running, from its DIS revision.
  /// Decides whether the radio image may travel with the app core (v3 only) or
  /// has to follow in a second leg — see [planDfu].
  DeviceGeneration _generation = DeviceGeneration.unknown;

  /// The plan the current/last install ran, kept so the UI can describe what is
  /// happening ("main firmware now, radio after the restart").
  DfuPlan? _plan;

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

  /// The install state machine (upload + stage walk); the screen is its view.
  FirmwareUpdater? _updater;

  /// Token for the SMP wire, held for the duration of the image upload.
  Object? _smpToken;

  // Advanced options
  bool _isManualMode = false;

  /// A radio (second-leg) update is owed from a hand-picked package. The app
  /// can't re-download that file, so the user has to re-select it.
  bool _manualRadioUpdatePending = false;
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

      // Step 4: A radio image owed from a previous two-stage migration takes
      // precedence over the version comparison. After leg one the watch reports
      // the new version, so isUpdateAvailable() says "up to date" and the second
      // leg would never be offered.
      final pendingVersion = await DfuStageState.pendingRadioVersion(_deviceMac!);
      if (pendingVersion != null && !_generation.isPreV3) {
        if (pendingVersion == DfuStageState.manualPackageTag) {
          // The first leg came from a hand-picked zip, which the app cannot
          // fetch again. Flag it so the up-to-date card says so and the manual
          // card runs the second leg once the same file is re-selected.
          debugPrint('[DFU] radio image still owed from a manual package');
          _manualRadioUpdatePending = true;
        } else if (pendingVersion == latestRelease.version) {
          debugPrint('[DFU] radio image still owed for $pendingVersion');
          setState(() => _dfuState = DFUScreenState.radioUpdateReady);
          _downloadFirmwareInBackground(thenState: DFUScreenState.radioUpdateReady);
          return;
        } else {
          // A newer release has superseded the half-finished migration; fall
          // through to the normal flow, which installs both images at once.
          debugPrint('[DFU] pending radio update ($pendingVersion) superseded by '
              '${latestRelease.version}');
          await DfuStageState.clear();
        }
      }

      // Step 5: Compare versions
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
    _generation = generationFromFwRevision(version);
    debugPrint('[DFU] Current firmware version: "$_currentFWVersion" '
        '→ ${_generation.label}');
  }

  /// Download firmware in background.
  ///
  /// [thenState] is where to land once the package is extracted — normally
  /// `readyToInstall`, but the second leg of a two-stage migration returns to
  /// its own card instead.
  Future<void> _downloadFirmwareInBackground({
    DFUScreenState thenState = DFUScreenState.readyToInstall,
  }) async {
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
          _dfuState = thenState;
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

  /// Start a firmware update.
  ///
  /// [resumingStageTwo] runs the second leg of a two-stage migration: the watch
  /// has come back on v3 and only the radio image is left to send.
  Future<void> _startFirmwareUpdate({bool resumingStageTwo = false}) async {
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
      var uploadTransport = await _openSmpSession();

      final packageImages = _manifest!.files
          .map((f) => FirmwareImage(
                imageIndex: f.image,
                name: f.file,
                load: () =>
                    File('${_extractedDir!.path}/${f.file}').readAsBytes(),
              ))
          .toList();

      // Decide what this watch may receive *before* sending anything. Pre-v3
      // firmware takes the app core alone; the radio follows once the watch is
      // running v3 (see planDfu for why the two legs must not be merged).
      final slots = await uploadTransport.deviceSlots();
      final plan = planDfu(
        generation: _generation,
        slots: slots,
        packageImages: packageImages,
        resumingStageTwo: resumingStageTwo,
      );
      _plan = plan;
      debugPrint('[DFU] ${_generation.label}, $slots — ${plan.describe()}');

      if (plan.isBlocked) {
        await _teardownSmpSession();
        if (mounted) {
          setState(() {
            _dfuState = DFUScreenState.error;
            _errorMessage = plan.blockedReason;
          });
        }
        return;
      }

      // Losing the link mid-transfer used to end the update; the user then had
      // to start again by hand — and it worked, because MCUmgr resumes from the
      // offset the device reports. Do that automatically: a several-minute
      // upload over BLE on a wrist-worn device will meet the occasional RF gap,
      // and a dropped link is not a reason to throw away 60% of a transfer.
      const maxAttempts = 4;
      for (var attempt = 1;; attempt++) {
        final updater = FirmwareUpdater(
          uploadTransport,
          log: (m) => debugPrint('[DFU] $m'),
        );
        _updater = updater;
        updater.addListener(_onUpdaterProgress);
        try {
          await updater.run(plan.images);
          break;
        } catch (e) {
          if (attempt >= maxAttempts || !_isResumableLinkFailure(e)) rethrow;
          debugPrint('[DFU] attempt $attempt lost the link ($e) — '
              'reconnecting to resume');
          await _teardownSmpSession();
          await Future.delayed(const Duration(seconds: 3));
          if (!mounted) return;
          uploadTransport = await _openSmpSession();
        } finally {
          updater.removeListener(_onUpdaterProgress);
        }
      }

      debugPrint('[DFU] Images staged for next boot — restarting the watch');

      // MCUboot swaps on the next boot and the firmware does not restart itself,
      // so without this the update sits staged until someone power-cycles the
      // watch — and the second leg could never run. The device usually drops the
      // link before acking the reset, so a failure here is expected, not fatal.
      try {
        // _dfuClient is whichever session survived the retry loop.
        await OsMgmt(_dfuClient!).reset();
      } catch (e) {
        debugPrint('[DFU] reset request returned $e (device likely already gone)');
      }

      await _teardownSmpSession();

      if (plan.stageTwoFollows) {
        // Leg one done. Remember the debt before waiting, so a crash or a user
        // walking away doesn't lose the second leg.
        // A hand-picked zip has no release version to record; tag it so the
        // second leg is still remembered and asks for the same file back.
        await DfuStageState.setRadioUpdatePending(
          mac: _deviceMac!,
          version: _latestRelease?.version ?? DfuStageState.manualPackageTag,
        );
        if (mounted) {
          setState(() => _dfuState = DFUScreenState.awaitingReboot);
        }
        await _awaitRebootThenOfferRadioUpdate();
        return;
      }

      if (resumingStageTwo) {
        await DfuStageState.clear();
      }

      if (mounted) {
        setState(() => _dfuState = DFUScreenState.completed);
      }
    } catch (e) {
      debugPrint('[DFU] Update error: $e');
      await _teardownSmpSession();
      // A user-cancelled update (screen torn down mid-upload) isn't an error to
      // surface — the widget is already gone.
      if (mounted && e is! FirmwareUpdateCancelled) {
        setState(() {
          _dfuState = DFUScreenState.error;
          _errorMessage = _describeUpdateFailure(e);
        });
      }
    }
  }

  /// User-facing text for an install failure. The watch's own refusals get
  /// plain-language wording; everything else falls through to the raw error.
  String _describeUpdateFailure(Object e) {
    if (e is DfuBatteryTooLow) return e.toString();
    if (e is FirmwareImageUnidentifiable) return e.toString();
    if (e is TimeoutException) {
      return 'The watch stopped responding. Bring it close to the phone, make '
          'sure it is awake and charged, then try again.';
    }
    if (e is StateError) return e.message;
    if (e is SmpBusyException) {
      return 'Device busy (${e.currentOwner}). Wait for it to finish, then '
          'retry the update.';
    }
    return 'Update failed: $e';
  }

  /// True for failures where the transfer can simply be picked up again: the
  /// link went away, not the device saying no. A device-side error carries an
  /// `rc` and means retrying would fail the same way.
  bool _isResumableLinkFailure(Object e) =>
      e is TimeoutException || (e is SmpException && e.rc == null);

  /// Open an SMP session over the ConnectionManager link, reconnecting first if
  /// the link is down. Sets [_smpToken], [_dfuTransport] and [_dfuClient].
  Future<_ImgMgmtUploadTransport> _openSmpSession() async {
    // Minutes can pass between opening this screen and tapping install — a
    // file-picker modal, the watch restarting, the user walking out of range.
    // Building the SMP session on a dead link fails opaquely (MTU stuck at the
    // 23-byte default, iOS logging "API MISUSE: ... state = disconnected", and
    // finally a bare TimeoutException), so re-establish it first.
    if (!_conn.isConnected) {
      debugPrint('[DFU] link is down — reconnecting');
      await _conn.connect(_deviceMac!, name: _deviceName);
      await Future.delayed(const Duration(milliseconds: 500));
      // It may have restarted while we were away; the generation drives the
      // plan, so re-read it rather than trusting the value from screen entry.
      await _readCurrentFirmwareVersion();
    }

    // Claim the SMP wire for the whole upload — a background sync landing
    // mid-upload would interleave frames on the SMP characteristic and corrupt
    // the image.
    _smpToken = _conn.acquireSmp('dfu');

    final transport = SmpBleTransport(_deviceMac!, manageConnection: false);
    await transport.connect();
    _dfuTransport = transport;
    final client = SmpClient(transport);
    // The default 10 s is too tight for this watch. The MCUboot secondary slot
    // lives on the external QSPI NOR, so a write can sit behind a block erase
    // (hundreds of ms each, and the same die carries /lfs).
    client.timeout = const Duration(seconds: 40);
    _dfuClient = client;
    final img =
        ImgMgmt(client, maxWriteLength: () => _dfuTransport?.maxWriteLength);
    await transport.refreshMtu(); // ensure a large chunk size

    // A link that never negotiated its MTU is a broken link, not a slow one:
    // the watch asks for 247, and at the 23-byte default a 773 KB image would
    // need ~39,000 round-trips. Stop here with something the user can act on
    // rather than crawling into a timeout deep in the transport.
    final maxWrite = transport.maxWriteLength ?? 0;
    if (maxWrite < 100) {
      throw StateError(
        'The connection to the watch is not ready (negotiated only $maxWrite '
        'bytes per write). Move the watch closer to the phone and try again.',
      );
    }

    return _ImgMgmtUploadTransport(img);
  }

  /// Close the SMP session and hand the wire back, leaving the
  /// [ConnectionManager] link itself alone. Safe to call twice.
  Future<void> _teardownSmpSession() async {
    await _dfuClient?.dispose();
    _dfuClient = null;
    try {
      await _dfuTransport?.disconnect();
    } catch (_) {
      // The watch may already be gone (e.g. it just took a reset command).
    }
    await _dfuTransport?.dispose();
    _dfuTransport = null;
    _conn.releaseSmp(_smpToken);
    _smpToken = null;
  }

  /// Between the two legs: wait for the watch to reboot onto v3, then offer the
  /// radio image.
  ///
  /// The swap is an overwrite-only copy of the whole app image out of external
  /// flash, so the watch is away for a while — poll rather than assume a fixed
  /// delay. If it never comes back on the new version, stop and say so: an
  /// automatic retry against a watch in an unknown state is the one thing that
  /// could turn a recoverable situation into an SWD recovery.
  Future<void> _awaitRebootThenOfferRadioUpdate() async {
    const attemptGap = Duration(seconds: 8);
    const maxAttempts = 15; // ~2 minutes

    await _conn.disconnect();

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted) return;
      await Future.delayed(attemptGap);
      try {
        await _conn.connect(_deviceMac!, name: _deviceName);
        await Future.delayed(const Duration(milliseconds: 500));
        await _readCurrentFirmwareVersion();
        debugPrint('[DFU] post-reboot attempt $attempt: '
            '$_currentFWVersion (${_generation.label})');

        if (!_generation.isPreV3) {
          if (mounted) {
            setState(() => _dfuState = DFUScreenState.radioUpdateReady);
          }
          return;
        }
        // Reachable but still on the old firmware: the swap did not happen.
        // Keep trying — the watch may have reconnected before rebooting.
      } catch (e) {
        debugPrint('[DFU] post-reboot attempt $attempt failed: $e');
      }
    }

    if (mounted) {
      setState(() {
        _dfuState = DFUScreenState.error;
        _errorMessage =
            'The watch did not come back on the new firmware. It now reports '
            '$_currentFWVersion. Check that it restarted and is charged, then '
            'reopen this screen — the radio update is still pending and will '
            'be offered again.';
      });
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
      // file_selector, not file_picker: the latter pulls in
      // DKImagePickerController on iOS (camera + photo-library), which this
      // screen never uses. On iOS the document picker filters by UTI, not
      // extension — `extensions` is ignored there and an empty
      // `uniformTypeIdentifiers` throws, so the zip UTI must be spelled out.
      const XTypeGroup firmwareZip = XTypeGroup(
        label: 'Firmware',
        extensions: ['zip'], // Android / desktop
        uniformTypeIdentifiers: ['public.zip-archive'], // iOS / macOS
        mimeTypes: ['application/zip'], // Android SAF
      );
      final XFile? picked = await openFile(acceptedTypeGroups: [firmwareZip]);

      if (picked == null) {
        return; // User cancelled
      }

      setState(() {
        _dfuState = DFUScreenState.downloading;
        _downloadProgress = 0.0;
      });

      // The iOS picker runs in `.import` mode, so this path is a readable copy
      // in the app's temp dir, not a security-scoped URL — safe to open here.
      final file = File(picked.path);

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

  /// Installing, waiting out the reboot, or completed — a focused card with no
  /// device/advanced chrome. (The radio-update step keeps the chrome: it is a
  /// normal actionable state, not a flow the user is locked into.)
  bool get _terminal =>
      _dfuState == DFUScreenState.installing ||
      _dfuState == DFUScreenState.awaitingReboot ||
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
      case DFUScreenState.awaitingReboot:
        return _awaitingRebootCard();
      case DFUScreenState.radioUpdateReady:
        return _radioUpdateCard();
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
          // Set expectations before the first tap: a watch on pre-v3 firmware
          // is migrated in two legs, and the second one needs the user to still
          // be here after the restart.
          if (_generation.isPreV3) ...[
            const SizedBox(height: 14),
            _noticeBanner(
              Symbols.looks_two,
              HpiColors.temp,
              'This watch (${_generation.label}) updates in two steps: the main '
              'firmware now, then the radio firmware after it restarts. Keep '
              'the watch nearby and on charge until both are done.',
            ),
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
                    Text(
                        _manualRadioUpdatePending
                            ? 'Step 2 of 2 · radio firmware'
                            : '${_manifest?.files.length ?? 0} images ready',
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
          // Same two-step rule as an automatic update: a watch on pre-v3
          // firmware takes the main firmware first, the radio after it
          // restarts. Selecting the package by hand does not change that.
          if (_generation.isPreV3) ...[
            const SizedBox(height: 12),
            _noticeBanner(
              Symbols.looks_two,
              HpiColors.temp,
              'This watch (${_generation.label}) installs in two steps — the '
              'main firmware now, the radio firmware after it restarts. Keep '
              'this file: you will be asked to select it again for step 2.',
            ),
          ],
          if (_manualRadioUpdatePending) ...[
            const SizedBox(height: 12),
            _noticeBanner(
              Symbols.info,
              HpiColors.hr,
              'Only the radio firmware will be installed — the main firmware '
              'is already on the watch.',
            ),
          ],
          const SizedBox(height: 16),
          HpiFilledButton(
            label: _manualRadioUpdatePending
                ? 'Install radio firmware'
                : 'Install manual firmware',
            icon: Symbols.upgrade,
            color: HpiColors.temp,
            onPressed: () =>
                _startFirmwareUpdate(resumingStageTwo: _manualRadioUpdatePending),
          ),
        ],
      ),
    );
  }

  /// DFU in progress — amber ring, image counter, "do not disconnect".
  Widget _installingCard() {
    final total = _plan?.images.length ?? _manifest?.files.length ?? 1;
    final current = _currentImageIndex + 1;
    final stageNote = switch (_plan?.stage) {
      DfuStage.appCoreFirst => 'Main firmware · step 1 of 2',
      DfuStage.netCore => 'Radio firmware · step 2 of 2',
      _ => null,
    };
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
          if (stageNote != null) ...[
            const SizedBox(height: 4),
            Text(stageNote, style: HpiText.supporting),
          ],
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

  /// Between the legs: the app core is installed, the watch is restarting, and
  /// the radio image is still owed.
  Widget _awaitingRebootCard() {
    return HpiCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(HpiColors.hr),
            ),
          ),
          const SizedBox(height: 20),
          Text('Main firmware installed', style: HpiText.appBarTitle),
          const SizedBox(height: 8),
          Text(
            'The watch is restarting on the new firmware. This takes up to a '
            'couple of minutes — keep it nearby and on charge.',
            style: HpiText.body.copyWith(fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _noticeBanner(
            Symbols.info,
            HpiColors.temp,
            'One step left: the radio firmware is installed after the restart.',
          ),
        ],
      ),
    );
  }

  /// Second leg: the watch is on v3 and only the radio image is left.
  Widget _radioUpdateCard() {
    return HpiCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HpiIconSquare(
                  icon: Symbols.settings_input_antenna,
                  color: HpiColors.hr,
                  size: 40,
                  iconSize: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Radio firmware update', style: HpiText.appBarTitle),
                    const SizedBox(height: 2),
                    Text('Step 2 of 2 · watch now on $_currentFWVersion',
                        style: HpiText.supporting),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'The main firmware is installed. This last step updates the '
            "watch's Bluetooth radio firmware to match.",
            style: HpiText.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          _noticeBanner(
            Symbols.battery_alert,
            HpiColors.temp,
            'Keep the watch on charge — it refuses updates below 30% battery.',
          ),
          const SizedBox(height: 16),
          HpiFilledButton(
            label: _dfuState == DFUScreenState.downloading
                ? 'Preparing…'
                : 'Install radio firmware',
            icon: Symbols.upgrade,
            onPressed: (_manifest != null && _extractedDir != null)
                ? () => _startFirmwareUpdate(resumingStageTwo: true)
                : null,
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
          // The version matches the latest release, but the migration this
          // watch started is not finished: its radio image is still owed and
          // came from a package only the user has.
          if (_manualRadioUpdatePending) ...[
            const SizedBox(height: 16),
            _noticeBanner(
              Symbols.looks_two,
              HpiColors.temp,
              'One step left: the radio firmware update for this watch is still '
              'pending. Open Advanced options and select the same firmware .zip '
              'again to finish it.',
            ),
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

  /// MCUmgr `MGMT_ERR_EBADSTATE`. The firmware answers the img-mgmt upload hook
  /// with this when the battery is under its DFU floor (30 %).
  static const int _rcBadState = 6;

  @override
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      return await _img.upload(image,
          imageIndex: imageIndex, onProgress: onProgress);
    } on SmpException catch (e) {
      // Translate the watch's own refusal into something a user can act on;
      // a raw "bad state (rc=6)" reads like a crash.
      if (e.rc == _rcBadState) throw const DfuBatteryTooLow();
      rethrow;
    }
  }

  @override
  Future<void> markPending(List<int> sha) => _img.test(sha);

  @override
  Future<List<int>?> stagedImageHash(int imageIndex) async {
    try {
      final slots = await _img.list();
      for (final s in slots) {
        // slot 1 = secondary: where an upload lands, and where the device
        // publishes the hash to hand back in `image test`.
        if (s.image == imageIndex && s.slot == 1 && s.hash.isNotEmpty) {
          return s.hash;
        }
      }
    } catch (e) {
      debugPrint('[DFU] could not read staged hash from image list: $e');
    }
    return null;
  }

  @override
  Future<DeviceSlots> deviceSlots() async {
    try {
      final slots = await _img.list();
      // An answer with no entries is not a usable slot map either — treat it
      // as unknown rather than "this device has no images".
      if (slots.isEmpty) return const DeviceSlots.unknown();
      return DeviceSlots.known(slots.map((s) => s.image).toSet());
    } catch (e) {
      // Older firmware can fail this query outright (or answer rc=1 on the
      // net-core slot). Unknown ⇒ skip the cross-check rather than block an
      // update that would have worked.
      debugPrint('[DFU] could not read image list (slot check skipped): $e');
      return const DeviceSlots.unknown();
    }
  }
}
