import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:intl/intl.dart';
import '../globals.dart';
import 'database_helper.dart';
import 'update_checker.dart';

typedef LogHeader = ({int logFileID, int sessionLength});

enum SyncState { idle, connecting, downloading, parsing, completed, error }

class SyncProgress {
  final String metric;
  final double progress;
  final SyncState state;
  final String? message;
  final int? bytesDownloaded;
  final int? totalBytes;

  SyncProgress({
    required this.metric,
    required this.progress,
    required this.state,
    this.message,
    this.bytesDownloaded,
    this.totalBytes,
  });

  SyncProgress copyWith({
    String? metric,
    double? progress,
    SyncState? state,
    String? message,
    int? bytesDownloaded,
    int? totalBytes,
  }) {
    return SyncProgress(
      metric: metric ?? this.metric,
      progress: progress ?? this.progress,
      state: state ?? this.state,
      message: message ?? this.message,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

class SyncResult {
  final bool success;
  final String message;
  final Map<String, int> recordCounts;
  final Duration duration;

  SyncResult({
    required this.success,
    required this.message,
    required this.recordCounts,
    required this.duration,
  });
}

class BackgroundSyncManager {
  static final BackgroundSyncManager instance = BackgroundSyncManager._();
  BackgroundSyncManager._();

  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final List<StreamSubscription> _activeSubscriptions = [];
  
  // BLE characteristics for communication
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;
  
  // MCU Manager for file downloads
  mcumgr.FsManager? _fsManager;
  
  // Current device being synced
  BluetoothDevice? _currentDevice;

  Future<SyncResult> syncData({
    required String deviceMacAddress,
    required Function(String metric, double progress) onProgress,
    required Function(String message) onStatus,
  }) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Sync already in progress',
        recordCounts: {},
        duration: Duration.zero,
      );
    }

    _isSyncing = true;
    final startTime = DateTime.now();
    final recordCounts = <String, int>{};

    try {
      // Step 1: Create device and connect - ALL BLE logic contained here
      _emitProgress('all', 0.0, SyncState.connecting, 'Connecting to device...');
      onStatus('Connecting to device...');
      
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Background sync: Creating device from MAC: $deviceMacAddress');
      final device = BluetoothDevice.fromId(deviceMacAddress);
      _currentDevice = device;

      if (device.isDisconnected) {
        debugPrint('Background sync: Connecting to device...');
        await device.connect(
          license: License.values.first,
          timeout: const Duration(seconds: 15),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('Background sync: Connected successfully');
      } else {
        debugPrint('Background sync: Device already connected');
      }

      final services = await device.discoverServices();
      
      // Find command service and characteristics
      for (var service in services) {
        if (service.uuid == Guid(hPi4Global.UUID_SERVICE_CMD)) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD_DATA)) {
              _dataCharacteristic = characteristic;
            }
            if (characteristic.uuid == Guid(hPi4Global.UUID_CHAR_CMD)) {
              _commandCharacteristic = characteristic;
            }
          }
        }
      }

      if (_commandCharacteristic == null || _dataCharacteristic == null) {
        throw Exception('Required BLE characteristics not found');
      }

      // Step 1.5: Check firmware version before syncing
      _emitProgress('all', 0.02, SyncState.connecting, 'Checking firmware version...');
      onStatus('Checking firmware version...');

      final firmwareVersion = await _readFirmwareVersion(services);
      debugPrint('Background sync: Firmware version: $firmwareVersion');

      if (!_isFirmwareVersionSupported(firmwareVersion)) {
        throw Exception(
          'Firmware version $firmwareVersion is not supported. '
          'Please update to version 1.9.0 or higher. '
          'Go to Device > Update Firmware to update.'
        );
      }

      // ============================================================================
      // MCU Manager Strategy: Create ONCE at start, dispose before disconnect
      // ============================================================================
      // Initialize MCU Manager for this sync session
      debugPrint('Background sync: Creating MCU Manager instance...');
      _fsManager = mcumgr.FsManager(_currentDevice!.remoteId.toString());
      debugPrint('Background sync: MCU Manager created successfully');
      // ============================================================================

      // Check for firmware updates in background (non-blocking)
      UpdateChecker.checkForUpdatesInBackground(device).then((updateAvailable) {
        if (updateAvailable) {
          debugPrint('Background sync: Firmware update available');
        }
      }).catchError((e) {
        debugPrint('Background sync: Update check failed: $e');
      });

      // Step 2: Set device time
      _emitProgress('all', 0.05, SyncState.connecting, 'Syncing device time...');
      onStatus('Syncing device time...');
      await _sendCurrentDateTime(_currentDevice!);
      
      // Step 3: Fetch session counts for each metric
      _emitProgress('all', 0.1, SyncState.downloading, 'Checking available data...');
      onStatus('Checking available data...');
      
      final metrics = [
        {'type': hPi4Global.PREFIX_HR, 'trend': hPi4Global.HrTrend, 'name': 'Heart Rate'},
        {'type': hPi4Global.PREFIX_SPO2, 'trend': hPi4Global.Spo2Trend, 'name': 'SpO2'},
        {'type': hPi4Global.PREFIX_TEMP, 'trend': hPi4Global.TempTrend, 'name': 'Temperature'},
        {'type': hPi4Global.PREFIX_ACTIVITY, 'trend': hPi4Global.ActivityTrend, 'name': 'Activity'},
      ];

      // Query session counts
      final sessionCounts = <String, int>{};
      for (var metric in metrics) {
        final trendType = metric['trend'] as List<int>;
        final metricType = metric['type'] as String;
        final count = await _fetchLogCount(_currentDevice!, trendType);
        sessionCounts[metricType] = count;
        debugPrint('Background sync: $metricType session count = $count');
      }

      // Check if there's any data
      final totalSessions = sessionCounts.values.fold(0, (sum, count) => sum + count);
      if (totalSessions == 0) {
        return SyncResult(
          success: true,
          message: 'No new data available on device',
          recordCounts: {},
          duration: DateTime.now().difference(startTime),
        );
      }

      // Step 4: Fetch and download sessions for each metric
      int completedMetrics = 0;
      final totalMetrics = metrics.where((m) => sessionCounts[m['type'] as String]! > 0).length;
      
      for (var metric in metrics) {
        final metricType = metric['type'] as String;
        final trendType = metric['trend'] as List<int>;
        final metricName = metric['name'] as String;
        final count = sessionCounts[metricType]!;
        
        if (count == 0) continue;

        _emitProgress(metricType, 0.0, SyncState.downloading, 'Fetching $metricName indices...');
        onStatus('Syncing $metricName...');
        onProgress(metricType, 0.0);

        // Fetch log indices
        final logHeaders = await _fetchLogIndexAndWait(_currentDevice!, trendType, count);
        debugPrint('Background sync: Found ${logHeaders.length} $metricType sessions');

        // Get list of already synced sessions for this metric
        final syncedSessionIds = await DatabaseHelper.instance.getSyncedSessionIds(metricType);
        debugPrint('Background sync: Already synced ${syncedSessionIds.length} $metricType sessions');

        // Filter sessions: always include today's sessions (they can change), skip old synced sessions
        final newHeaders = logHeaders.where((h) {
          // Always download today's session (it's actively being recorded)
          if (_isToday(h)) {
            return true;
          }
          // For past sessions, only download if not already synced
          return !syncedSessionIds.contains(h.logFileID);
        }).toList();
        
        final todayCount = logHeaders.where((h) => _isToday(h)).length;
        final actualNewCount = newHeaders.length - todayCount;
        debugPrint('Background sync: $metricType - ${newHeaders.length} to download ($todayCount today, $actualNewCount new past sessions)');

        if (newHeaders.isEmpty) {
          // All sessions already synced
          _emitProgress(metricType, 1.0, SyncState.completed, 'No new $metricName data');
          completedMetrics++;
          final overallProgress = 0.1 + (completedMetrics / totalMetrics * 0.9);
          _emitProgress('all', overallProgress, SyncState.downloading, 'Progress: $completedMetrics/$totalMetrics');
          continue;
        }

        // Download new sessions and today's sessions
        int downloadedRecords = 0;
        for (int i = 0; i < newHeaders.length; i++) {
          final header = newHeaders[i];
          final progress = (i + 1) / newHeaders.length;
          
          final isToday = _isToday(header);
          final action = isToday ? 'Updating' : 'Downloading';
          _emitProgress(metricType, progress, SyncState.downloading, '$action $metricName ${i + 1}/${newHeaders.length}');
          onProgress(metricType, progress);

          try {
            final records = await _fetchLogFile(_currentDevice!, header.logFileID, header.sessionLength, trendType, metricType);
            downloadedRecords += records;
          } catch (e) {
            debugPrint('Error downloading $metricType session ${header.logFileID}: $e');
            // Continue with next session
          }
        }

        recordCounts[metricType] = downloadedRecords;
        completedMetrics++;
        
        final overallProgress = 0.1 + (completedMetrics / totalMetrics * 0.9);
        _emitProgress('all', overallProgress, SyncState.downloading, 'Progress: $completedMetrics/$totalMetrics');
        _emitProgress(metricType, 1.0, SyncState.completed, 'Completed $metricName');
      }

      // Step 5: Complete
      _emitProgress('all', 1.0, SyncState.completed, 'Sync completed');
      onStatus('Sync completed');

      // Safe disconnect from device
      await _safeDisconnect(_currentDevice!);

      final totalRecords = recordCounts.values.fold(0, (sum, count) => sum + count);
      return SyncResult(
        success: true,
        message: 'Synced $totalRecords records in ${DateTime.now().difference(startTime).inSeconds}s',
        recordCounts: recordCounts,
        duration: DateTime.now().difference(startTime),
      );

    } catch (e) {
      _emitProgress('all', 0.0, SyncState.error, 'Sync failed: $e');
      onStatus('Sync failed');
      debugPrint('Background sync error: $e');
      
      // Try to disconnect even on error
      try {
        await _safeDisconnect(_currentDevice!);
      } catch (disconnectError) {
        debugPrint('Error disconnecting after sync failure: $disconnectError');
      }
      
      return SyncResult(
        success: false,
        message: 'Sync failed: $e',
        recordCounts: recordCounts,
        duration: DateTime.now().difference(startTime),
      );
    } finally {
      _isSyncing = false;
      _cleanupSubscriptions();
    }
  }

  /// Safe disconnect - properly releases BLE connection
  /// Must be called after fsManager.kill() to ensure clean disconnect
  Future<void> _safeDisconnect(BluetoothDevice device) async {
    try {
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Background sync: DISCONNECT SEQUENCE INITIATED');
      debugPrint('Background sync: Device: ${device.remoteId}');
      debugPrint('═══════════════════════════════════════════════════════');
      
      // ============================================================================
      // STEP 0: CRITICAL - Kill MCU Manager FIRST (releases internal BLE connection)
      // ============================================================================
      debugPrint('STEP 0: ⚠️ KILLING MCU MANAGER (releases native BLE resources)');
      try {
        if (_fsManager != null) {
          // FsManager.kill() explicitly releases native BLE resources
          // This is documented as necessary to prevent memory leaks
          debugPrint('  Calling _fsManager.kill()...');
          await _fsManager!.kill();
          _fsManager = null;
          
          // Give native layer time to clean up BLE connection
          await Future.delayed(const Duration(milliseconds: 1500));
          debugPrint('  ✓ FsManager killed - native BLE resources released');
        } else {
          debugPrint('  FsManager already null, skipping kill()');
        }
      } catch (e) {
        debugPrint('  ⚠️ Error killing FsManager: $e');
        // Continue with disconnect anyway
      }
      // ============================================================================
      
      // STEP 1: Immediate cleanup - clear ALL references
      debugPrint('STEP 1: Clearing ${_activeSubscriptions.length} subscriptions and references');
      _cleanupSubscriptions();
      _commandCharacteristic = null;
      _dataCharacteristic = null;
      
      // STEP 2: Check initial state
      await Future.delayed(const Duration(milliseconds: 500));
      bool isConnected = await device.isConnected;
      debugPrint('STEP 2: Initial connection status: $isConnected');
      
      if (!isConnected) {
        debugPrint('✓ Device already disconnected - exiting');
        return;
      }
      
      // STEP 3: Simple disconnect
      debugPrint('STEP 3: Calling device.disconnect()...');
      try {
        await device.disconnect(timeout: 5);
        debugPrint('  ✓ Disconnect called successfully');
      } catch (e) {
        debugPrint('  ⚠️ Disconnect call failed: $e');
      }

      // STEP 4: Wait and verify
      await Future.delayed(const Duration(milliseconds: 1000));
      isConnected = await device.isConnected;
      debugPrint('STEP 4: Post-disconnect status: $isConnected');
      
      if (isConnected) {
        debugPrint('⚠️ Device still connected after disconnect call');
        debugPrint('⚠️ This may indicate fsManager.kill() was not called or failed');
      } else {
        debugPrint('✓✓✓ SUCCESS - Device confirmed disconnected');
      }
      
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Background sync: DISCONNECT SEQUENCE COMPLETED');
      debugPrint('═══════════════════════════════════════════════════════');
      
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ CRITICAL ERROR in disconnect sequence: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't throw - we want sync to complete even if disconnect fails
    }
  }

  Future<void> _sendCurrentDateTime(BluetoothDevice device) async {
    final dt = DateTime.now();
    final cdate = DateFormat("yy").format(DateTime.now());
    
    List<int> commandDateTimePacket = [];
    ByteData sessionParametersLength = ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);
    
    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));
    
    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);
    commandDateTimePacket.addAll(cmdByteList);
    await _sendCommand(commandDateTimePacket, device);
  }

  Future<void> _sendCommand(List<int> commandList, BluetoothDevice device) async {
    if (_commandCharacteristic != null) {
      await _commandCharacteristic!.write(commandList, withoutResponse: true);
    }
  }

  /// Check if a session is from today
  /// Session ID (logFileID) is a UNIX timestamp in seconds
  bool _isToday(LogHeader header) {
    final now = DateTime.now();
    final headerDate = DateTime.fromMillisecondsSinceEpoch(header.logFileID * 1000);
    
    return now.year == headerDate.year &&
           now.month == headerDate.month &&
           now.day == headerDate.day;
  }

  Future<int> _fetchLogCount(BluetoothDevice device, List<int> trendType) async {
    final completer = Completer<int>();
    int sessionCount = 0;

    // Listen for session count response
    late StreamSubscription<List<int>> tempSubscription;
    tempSubscription = _dataCharacteristic!.onValueReceived.listen((value) {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        int trendCode = bdata.getUint8(2);
        if (trendCode == trendType[0]) {
          sessionCount = bdata.getUint16(3, Endian.little);
          tempSubscription.cancel();
          _activeSubscriptions.remove(tempSubscription);
          completer.complete(sessionCount);
        }
      }
    });

    _activeSubscriptions.add(tempSubscription);
    device.cancelWhenDisconnected(tempSubscription);
    await _dataCharacteristic!.setNotifyValue(true);

    // Send command
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.getSessionCount);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, device);

    return await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => 0,
    );
  }

  Future<List<LogHeader>> _fetchLogIndexAndWait(
    BluetoothDevice device,
    List<int> trendType,
    int sessionCount,
  ) async {
    final headerList = <LogHeader>[];
    final completer = Completer<void>();

    // Listen for log index packets
    late StreamSubscription<List<int>> tempSubscription;
    tempSubscription = _dataCharacteristic!.onValueReceived.listen((value) {
      ByteData bdata = Uint8List.fromList(value).buffer.asByteData();
      int pktType = bdata.getUint8(0);
      if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        int trendTypeReceived = bdata.getUint8(13);
        if (trendTypeReceived == trendType[0]) {
          int logFileID = bdata.getInt64(1, Endian.little);
          int sessionLength = bdata.getInt32(9, Endian.little);
          headerList.add((logFileID: logFileID, sessionLength: sessionLength));
          if (headerList.length == sessionCount) {
            tempSubscription.cancel();
            _activeSubscriptions.remove(tempSubscription);
            completer.complete();
          }
        }
      }
    });

    _activeSubscriptions.add(tempSubscription);
    device.cancelWhenDisconnected(tempSubscription);
    await _dataCharacteristic!.setNotifyValue(true);

    // Send command to fetch indices
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.sessionLogIndex);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket, device);

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => debugPrint('Timeout fetching log indices'),
    );

    return headerList;
  }

  Future<int> _fetchLogFile(
    BluetoothDevice device,
    int sessionID,
    int sessionSize,
    List<int> trendType,
    String metricType,
  ) async {
    // Determine device directory based on trend type
    String deviceDirectory;
    if (trendType == hPi4Global.HrTrend) {
      deviceDirectory = hPi4Global.DEVICE_DIR_HR;
    } else if (trendType == hPi4Global.TempTrend) {
      deviceDirectory = hPi4Global.DEVICE_DIR_TEMP;
    } else if (trendType == hPi4Global.Spo2Trend) {
      deviceDirectory = hPi4Global.DEVICE_DIR_SPO2;
    } else if (trendType == hPi4Global.ActivityTrend) {
      deviceDirectory = hPi4Global.DEVICE_DIR_ACTIVITY;
    } else {
      throw Exception('Unknown trend type');
    }

    final String deviceFilePath = "/lfs/$deviceDirectory/$sessionID";
    
    // Download file via MCU Manager
    final completer = Completer<List<int>>();
    
    late StreamSubscription downloadSubscription;
    downloadSubscription = _fsManager!.downloadCallbacks.listen((event) {
      if (event.path == deviceFilePath) {
        if (event is mcumgr.OnDownloadCompleted) {
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.complete(event.data);
        } else if (event is mcumgr.OnDownloadFailed) {
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.completeError(Exception('Download failed: ${event.cause}'));
        } else if (event is mcumgr.OnDownloadCancelled) {
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.completeError(Exception('Download cancelled'));
        }
      }
    });

    _activeSubscriptions.add(downloadSubscription);
    await _fsManager!.download(deviceFilePath);

    final binaryData = await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        downloadSubscription.cancel();
        throw TimeoutException('Download timeout');
      },
    );

    // Parse binary data and insert into database
    int offset = (binaryData.isNotEmpty && binaryData[0] == hPi4Global.CES_CMDIF_TYPE_DATA) ? 1 : 0;
    List<int> cleanData = binaryData.sublist(offset);

    final recordCount = await DatabaseHelper.instance.insertTrendsFromBinary(
      cleanData,
      metricType,
      sessionID,
      deviceMac: _currentDevice?.remoteId.str,
    );

    return recordCount;
  }

  void _emitProgress(String metric, double progress, SyncState state, String message) {
    if (!_progressController.isClosed) {
      _progressController.add(SyncProgress(
        metric: metric,
        progress: progress,
        state: state,
        message: message,
      ));
    }
  }

  void _cleanupSubscriptions() {
    for (var sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
  }

  /// Read firmware version from Device Information Service
  Future<String> _readFirmwareVersion(List<BluetoothService> services) async {
    try {
      // Look for Device Information Service (0x180A)
      for (var service in services) {
        if (service.uuid == Guid("180a")) {
          // Look for Firmware Revision String characteristic (0x2A26)
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid("2a26")) {
              final value = await characteristic.read();
              final version = String.fromCharCodes(value).trim();
              return version;
            }
          }
        }
      }

      debugPrint('Background sync: Firmware version characteristic not found');
      return 'unknown';
    } catch (e) {
      debugPrint('Background sync: Error reading firmware version: $e');
      return 'unknown';
    }
  }

  /// Check if firmware version is supported (>= 1.9.0)
  bool _isFirmwareVersionSupported(String version) {
    if (version == 'unknown') {
      // If we can't read the version, allow sync but log warning
      debugPrint('Background sync: WARNING - Could not verify firmware version, proceeding anyway');
      return true;
    }

    try {
      // Remove 'v' prefix if present
      final cleanVersion = version.toLowerCase().startsWith('v')
          ? version.substring(1)
          : version;

      // Parse version parts
      final parts = cleanVersion.split('.');
      if (parts.length < 2) {
        debugPrint('Background sync: Invalid version format: $version');
        return false;
      }

      final major = int.tryParse(parts[0]) ?? 0;
      final minor = int.tryParse(parts[1]) ?? 0;

      // Check if version >= 1.9.0
      if (major > 1) return true;
      if (major == 1 && minor >= 9) return true;

      debugPrint('Background sync: Firmware version $version is below minimum 1.9.0');
      return false;
    } catch (e) {
      debugPrint('Background sync: Error parsing version $version: $e');
      return false;
    }
  }

  void dispose() {
    _cleanupSubscriptions();
    _progressController.close();
  }
}
