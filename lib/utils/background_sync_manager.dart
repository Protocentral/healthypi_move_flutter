// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../globals.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';
import '../smp/smp_ble_transport.dart';
import 'connection_manager.dart';
import 'device_info_service.dart';
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

/// Downloads health-trend history (HR / SpO2 / Temp / Activity) from a paired
/// HealthyPi Move into the local database.
///
/// BLE is routed through the universal_ble stack (matching the rest of the app):
/// the custom cmd/data trend protocol goes over [ConnectionManager] (subscribe /
/// write), and file downloads use the ported MCUmgr [FsMgmt] over an SMP session
/// that **shares** the ConnectionManager link (`manageConnection: false`).
class BackgroundSyncManager {
  static final BackgroundSyncManager instance = BackgroundSyncManager._();
  BackgroundSyncManager._();

  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  final List<StreamSubscription> _activeSubscriptions = [];

  final ConnectionManager _conn = ConnectionManager.instance;

  // SMP FS session (rides the ConnectionManager link) for file downloads.
  SmpBleTransport? _smpTransport;
  SmpClient? _smpClient;
  FsMgmt? _fs;

  /// Token for the SMP wire, held for the duration of the sync's SMP work.
  Object? _smpToken;

  // MAC of the device currently being synced (used to tag DB rows).
  String? _deviceMac;

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

    // Claim the SMP wire up-front, before we touch the BLE link at all. If a
    // DFU or records flow holds it we must bail out *without* connecting or
    // disconnecting — `_safeDisconnect()` drops the shared link, which would
    // kill the flow that legitimately owns it.
    try {
      _smpToken = _conn.acquireSmp('background-sync');
    } on SmpBusyException catch (e) {
      debugPrint('Background sync: skipped — ${e.currentOwner} holds the SMP wire');
      return SyncResult(
        success: false,
        message: 'Device busy (${e.currentOwner}); sync skipped',
        recordCounts: {},
        duration: Duration.zero,
      );
    }

    _isSyncing = true;
    _deviceMac = deviceMacAddress;
    final startTime = DateTime.now();
    final recordCounts = <String, int>{};

    try {
      // Step 1: Connect (ConnectionManager owns the link + discovers services).
      _emitProgress('all', 0.0, SyncState.connecting, 'Connecting to device...');
      onStatus('Connecting to device...');

      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('Background sync: Connecting to device: $deviceMacAddress');
      await _conn.connect(deviceMacAddress);
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint('Background sync: Connected successfully');

      // Step 1.5: Check firmware version before syncing
      _emitProgress('all', 0.02, SyncState.connecting, 'Checking firmware version...');
      onStatus('Checking firmware version...');

      final firmwareVersion =
          await DeviceInfoService.readFirmwareVersion(deviceMacAddress);
      debugPrint('Background sync: Firmware version: $firmwareVersion');

      if (!DeviceInfoService.isAtLeast(firmwareVersion, major: 1, minor: 9)) {
        throw Exception(
          'Firmware version ${firmwareVersion ?? "unknown"} is not supported. '
          'Please update to version 1.9.0 or higher. '
          'Go to Device > Update Firmware to update.'
        );
      }

      // SMP FS session for file downloads, riding the existing link. The SMP
      // wire is already claimed (see the acquireSmp above).
      debugPrint('Background sync: Creating SMP FS session...');
      final transport =
          SmpBleTransport(deviceMacAddress, manageConnection: false);
      await transport.connect();
      _smpTransport = transport;
      _smpClient = SmpClient(transport);
      _fs = FsMgmt(_smpClient!,
          maxWriteLength: () => _smpTransport?.maxWriteLength);
      debugPrint('Background sync: SMP FS session ready');

      // Check for firmware updates in background (non-blocking)
      UpdateChecker.checkForUpdatesInBackground(deviceMacAddress)
          .then((updateAvailable) {
        if (updateAvailable) {
          debugPrint('Background sync: Firmware update available');
        }
      }).catchError((e) {
        debugPrint('Background sync: Update check failed: $e');
      });

      // Step 2: Set device time
      _emitProgress('all', 0.05, SyncState.connecting, 'Syncing device time...');
      onStatus('Syncing device time...');
      await _sendCurrentDateTime();

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
        final count = await _fetchLogCount(trendType);
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
        final logHeaders = await _fetchLogIndexAndWait(trendType, count);
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
            final records = await _fetchLogFile(header.logFileID, header.sessionLength, trendType, metricType);
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

      // Step 5: Ensure activity shows 0 if no data for today
      // If activity had 0 sessions, no file exists on device, so manually ensure today shows 0
      if (sessionCounts[hPi4Global.PREFIX_ACTIVITY] == 0) {
        debugPrint('Background sync: No activity sessions on device, ensuring today shows 0 steps');
        await _ensureTodayActivityExists(deviceMacAddress);
      }

      // Step 6: Complete
      _emitProgress('all', 1.0, SyncState.completed, 'Sync completed');
      onStatus('Sync completed');

      // Safe disconnect from device
      await _safeDisconnect();

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
        await _safeDisconnect();
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
      // Belt and braces: `_safeDisconnect()` already releases, but the
      // "no new data" path returns early without it. Releasing a stale/null
      // token is a no-op, so this can't free somebody else's lock.
      _conn.releaseSmp(_smpToken);
      _smpToken = null;
    }
  }

  /// Tear down the SMP FS session and release the ConnectionManager link.
  Future<void> _safeDisconnect() async {
    try {
      debugPrint('Background sync: Disconnect sequence initiated');

      // Dispose the SMP FS session first (unsubscribes its notify handler).
      _cleanupSubscriptions();
      await _smpClient?.dispose();
      _smpClient = null;
      await _smpTransport?.disconnect(); // manageConnection:false → just unsubscribes
      await _smpTransport?.dispose();
      _smpTransport = null;
      _fs = null;

      // Release the SMP wire before dropping the link.
      _conn.releaseSmp(_smpToken);
      _smpToken = null;

      // Release the shared BLE link.
      await _conn.disconnect();
      debugPrint('Background sync: Disconnect sequence completed');
    } catch (e) {
      debugPrint('Background sync: Error during disconnect: $e');
      // Don't throw - we want sync to complete even if disconnect fails
    }
  }

  Future<void> _sendCurrentDateTime() async {
    final dt = DateTime.now();
    final cdate = DateFormat("yy").format(dt);

    // Get timezone offset in total minutes (e.g., IST = +330, EST = -300)
    final offsetMinutes = dt.timeZoneOffset.inMinutes; // signed int

    debugPrint('Syncing device time: ${dt.toString()} (local time)');
    debugPrint('Timezone: ${dt.timeZoneName}, Offset: ${offsetMinutes} mins');

    List<int> commandDateTimePacket = [];
    ByteData sessionParametersLength = ByteData(8);
    commandDateTimePacket.addAll(hPi4Global.WISER_CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    // Encode signed offset in minutes as Int16 (2 bytes, big-endian)
    // Range: -840 to +840 minutes covers all real-world timezones
    sessionParametersLength.setInt16(6, offsetMinutes, Endian.little);

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 8);
    commandDateTimePacket.addAll(cmdByteList);

    debugPrint('Full Cmd: ${commandDateTimePacket.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ')}');
    debugPrint('Decoded → ss:${dt.second} mm:${dt.minute} hh:${dt.hour} dd:${dt.day} MM:${dt.month} yy:${int.parse(cdate)} tzOffset:${offsetMinutes}min');
    debugPrint('-------------------------------');
    // ──────────────────────────────────────────────────────────

    await _sendCommand(commandDateTimePacket);
  }

  Future<void> _sendCommand(List<int> commandList) async {
    await _conn.write(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD,
        Uint8List.fromList(commandList));
  }

  /// Check if a session is from today
  /// Session ID (logFileID) is a UNIX timestamp in seconds (in local time)
  bool _isToday(LogHeader header) {
    final now = DateTime.now();
    // Interpret session timestamp as local time
    final headerDate = DateTime.fromMillisecondsSinceEpoch(header.logFileID * 1000, isUtc: false);

    return now.year == headerDate.year &&
           now.month == headerDate.month &&
           now.day == headerDate.day;
  }

  /// Ensures that today's activity data exists in the database
  /// If no activity data exists for today, inserts a record with 0 steps
  Future<void> _ensureTodayActivityExists(String deviceMacAddress) async {
    try {
      final db = await DatabaseHelper.instance.database;

      // Calculate today's timestamp (start of day)
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayStartTimestamp = todayStart.millisecondsSinceEpoch ~/ 1000;

      // Check if any activity data exists for today
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM health_trends
        WHERE trend_type = ?
        AND timestamp >= ?
        AND timestamp < ?
        AND device_mac = ?
      ''', [
        'activity',
        todayStartTimestamp,
        todayStartTimestamp + 86400, // +24 hours
        deviceMacAddress,
      ]);

      final count = result.first['count'] as int;

      if (count == 0) {
        // No activity data for today, insert a record with 0 steps
        debugPrint('Background sync: Inserting 0 steps record for today');
        await db.insert('health_trends', {
          'trend_type': 'activity',
          'timestamp': todayStartTimestamp,
          'value_avg': 0,
          'value_min': 0,
          'value_max': 0,
          'device_mac': deviceMacAddress,
          'session_id': 0, // Placeholder session ID
        });
      }
    } catch (e) {
      debugPrint('Error ensuring today activity exists: $e');
    }
  }

  Future<int> _fetchLogCount(List<int> trendType) async {
    final completer = Completer<int>();
    int sessionCount = 0;

    // Listen for session count response
    late StreamSubscription<Uint8List> tempSubscription;
    tempSubscription = _conn
        .subscribe(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD_DATA)
        .listen((value) {
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

    // Send command
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.getSessionCount);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket);

    return await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => 0,
    );
  }

  Future<List<LogHeader>> _fetchLogIndexAndWait(
    List<int> trendType,
    int sessionCount,
  ) async {
    final headerList = <LogHeader>[];
    final completer = Completer<void>();

    // Listen for log index packets
    late StreamSubscription<Uint8List> tempSubscription;
    tempSubscription = _conn
        .subscribe(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD_DATA)
        .listen((value) {
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

    // Send command to fetch indices
    List<int> commandPacket = [];
    commandPacket.addAll(hPi4Global.sessionLogIndex);
    commandPacket.addAll(trendType);
    await _sendCommand(commandPacket);

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => debugPrint('Timeout fetching log indices'),
    );

    return headerList;
  }

  Future<int> _fetchLogFile(
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

    // Download file via MCUmgr FS (ported SMP client).
    final binaryData = await _fs!.download(deviceFilePath).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Download timeout'),
    );

    // Parse binary data and insert into database
    int offset = (binaryData.isNotEmpty && binaryData[0] == hPi4Global.CES_CMDIF_TYPE_DATA) ? 1 : 0;
    List<int> cleanData = binaryData.sublist(offset);

    final recordCount = await DatabaseHelper.instance.insertTrendsFromBinary(
      cleanData,
      metricType,
      sessionID,
      deviceMac: _deviceMac,
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

  void dispose() {
    _cleanupSubscriptions();
    _progressController.close();
  }
}
