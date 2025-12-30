import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:archive/archive.dart';
import '../globals.dart';
import '../models/research_recording.dart';

/// Manager for research recording operations
/// Handles BLE communication, file downloads, and data parsing
class ResearchRecordingManager {

  final BluetoothDevice device;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;
  mcumgr.FsManager? _fsManager;

  final List<StreamSubscription> _activeSubscriptions = [];

  bool _isInitialized = false;

  ResearchRecordingManager(this.device);

  /// Initialize the manager - must be called before using any methods
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Discover services if needed
    List<BluetoothService> services;
    if (device.servicesList.isEmpty) {
      services = await device.discoverServices();
    } else {
      services = device.servicesList;
    }

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

    // Initialize FsManager for file downloads
    _fsManager = mcumgr.FsManager(device.remoteId.toString());

    _isInitialized = true;
    print('[ResearchRecordingManager] Initialized for device: ${device.remoteId}');
  }

  /// Dispose of resources
  Future<void> dispose() async {
    for (var sub in _activeSubscriptions) {
      await sub.cancel();
    }
    _activeSubscriptions.clear();

    if (_fsManager != null) {
      _fsManager!.kill();
      _fsManager = null;
    }

    _isInitialized = false;
    print('[ResearchRecordingManager] Disposed');
  }

  /// Send a command to the device
  Future<void> _sendCommand(List<int> command) async {
    if (_commandCharacteristic == null) {
      throw Exception('Not initialized - call initialize() first');
    }
    await _commandCharacteristic!.write(command, withoutResponse: true);
    print('[ResearchRecordingManager] Sent command: ${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
  }

  // ============================================================================
  // Recording Control Commands
  // ============================================================================

  /// Configure recording parameters
  /// Returns: 0 = OK, 1 = invalid parameters, 2 = storage full
  Future<int> configure(RecordingConfig config) async {
    if (!config.isValid) {
      throw ArgumentError('Invalid recording configuration');
    }

    final completer = Completer<int>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 3 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_CONFIGURE[0]) {
        final status = value[2];
        print('[ResearchRecordingManager] Configure response: status=$status');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(config.toCommandPacket());

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Configure command timeout');
      },
    );
  }

  /// Start recording
  /// Returns: 0 = started, 1 = already recording, 2 = not configured, 3 = sensor error
  Future<int> startRecording() async {
    final completer = Completer<int>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 3 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_START[0]) {
        final status = value[2];
        print('[ResearchRecordingManager] Start response: status=$status');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(hPi4Global.REC_START);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Start command timeout');
      },
    );
  }

  /// Stop recording
  /// Returns: 0 = stopped, 1 = not recording
  Future<int> stopRecording() async {
    final completer = Completer<int>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 3 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_STOP[0]) {
        final status = value[2];
        print('[ResearchRecordingManager] Stop response: status=$status');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(hPi4Global.REC_STOP);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Stop command timeout');
      },
    );
  }

  /// Get current recording status
  Future<RecordingStatus> getStatus() async {
    final completer = Completer<RecordingStatus>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 8 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_GET_STATUS[0]) {
        print('[ResearchRecordingManager] Status response: ${value.length} bytes');
        final status = RecordingStatus.fromBytes(value);
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(hPi4Global.REC_GET_STATUS);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Get status command timeout');
      },
    );
  }

  // ============================================================================
  // Session Management
  // ============================================================================

  /// Get list of all recording sessions on device
  Future<List<ResearchRecording>> getSessionList() async {
    final sessions = <ResearchRecording>[];
    final completer = Completer<List<ResearchRecording>>();
    Timer? timeoutTimer;

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      // Reset timeout on each received packet
      timeoutTimer?.cancel();

      if (value.isNotEmpty && value[0] == hPi4Global.CES_CMDIF_TYPE_REC_SESSION) {
        try {
          final session = ResearchRecording.fromSessionListBytes(value);
          sessions.add(session);
          print('[ResearchRecordingManager] Received session: ts=${session.sessionTimestamp}, duration=${session.durationSeconds}s');
        } catch (e) {
          print('[ResearchRecordingManager] Error parsing session: $e');
        }

        // Set timeout to complete when no more sessions arrive
        timeoutTimer = Timer(const Duration(milliseconds: 500), () {
          subscription.cancel();
          _activeSubscriptions.remove(subscription);
          if (!completer.isCompleted) {
            completer.complete(sessions);
          }
        });
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(hPi4Global.REC_GET_SESSION_LIST);

    // Initial timeout in case no sessions exist
    timeoutTimer = Timer(const Duration(seconds: 3), () {
      subscription.cancel();
      _activeSubscriptions.remove(subscription);
      if (!completer.isCompleted) {
        completer.complete(sessions);
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        timeoutTimer?.cancel();
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        return sessions;
      },
    );
  }

  /// Delete a specific session from device
  /// Returns: 0 = deleted, 1 = not found, 2 = error
  Future<int> deleteSession(ResearchRecording session) async {
    final completer = Completer<int>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 3 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_DELETE_SESSION[0]) {
        final status = value[2];
        print('[ResearchRecordingManager] Delete response: status=$status');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(session.toDeleteCommandPacket());

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Delete session command timeout');
      },
    );
  }

  /// Wipe all recording sessions from device
  /// Returns: 0 = wiped, 1 = error
  Future<int> wipeAll() async {
    final completer = Completer<int>();

    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      if (value.length >= 3 &&
          value[0] == hPi4Global.CES_CMDIF_TYPE_CMD_RSP &&
          value[1] == hPi4Global.REC_WIPE_ALL[0]) {
        final status = value[2];
        print('[ResearchRecordingManager] Wipe all response: status=$status');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        completer.complete(status);
      }
    });

    _activeSubscriptions.add(subscription);
    device.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);

    await _sendCommand(hPi4Global.REC_WIPE_ALL);

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Wipe all command timeout');
      },
    );
  }

  // ============================================================================
  // File Operations
  // ============================================================================

  /// Download a signal file from device
  /// Returns the raw binary data
  Future<Uint8List> downloadSignalFile(
      ResearchRecording session,
      ResearchSignalType signal, {
        void Function(double progress)? onProgress,
      }) async {
    if (_fsManager == null) {
      throw Exception('Not initialized - call initialize() first');
    }

    final filePath = session.signalFilePath(signal);
    print('[ResearchRecordingManager] Downloading: $filePath');

    final completer = Completer<Uint8List>();

    late StreamSubscription downloadSubscription;
    downloadSubscription = _fsManager!.downloadCallbacks.listen((event) {
      if (event.path == filePath) {
        if (event is mcumgr.OnDownloadCompleted) {
          print('[ResearchRecordingManager] Download completed: ${event.data.length} bytes');
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.complete(Uint8List.fromList(event.data));
        } else if (event is mcumgr.OnDownloadFailed) {
          print('[ResearchRecordingManager] Download failed: ${event.cause}');
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.completeError(Exception('Download failed: ${event.cause}'));
        } else if (event is mcumgr.OnDownloadCancelled) {
          print('[ResearchRecordingManager] Download cancelled');
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          completer.completeError(Exception('Download cancelled'));
        } else if (event is mcumgr.OnDownloadProgressChanged) {
          // Progress callback if provided
          onProgress?.call(0.5); // Estimate since we don't have exact progress
        }
      }
    });

    _activeSubscriptions.add(downloadSubscription);
    await _fsManager!.download(filePath);

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        downloadSubscription.cancel();
        _activeSubscriptions.remove(downloadSubscription);
        throw TimeoutException('Download timeout for $filePath');
      },
    );
  }

  /// Download all signal files for a session
  /// Returns a map of signal type to binary data
  Future<Map<ResearchSignalType, Uint8List>> downloadSession(
      ResearchRecording session, {
        void Function(ResearchSignalType signal, double progress)? onProgress,
      }) async {
    final results = <ResearchSignalType, Uint8List>{};

    for (final signal in session.signals) {
      try {
        final data = await downloadSignalFile(
          session,
          signal,
          onProgress: (p) => onProgress?.call(signal, p),
        );
        results[signal] = data;
      } catch (e) {
        print('[ResearchRecordingManager] Failed to download ${signal.displayName}: $e');
        // Continue with other files
      }
    }

    return results;
  }

  // ============================================================================
  // Data Parsing
  // ============================================================================

  /// Parse file header from binary data
  RecordingFileHeader parseHeader(Uint8List data) {
    return RecordingFileHeader.fromBytes(data);
  }

  /// Parse PPG Wrist samples (12 bytes each: IR, Red, Green as uint32)
  List<PpgWristSample> parsePpgWristSamples(Uint8List data) {
    final header = parseHeader(data);
    final samples = <PpgWristSample>[];
    final byteData = data.buffer.asByteData(data.offsetInBytes);

    int offset = hPi4Global.REC_FILE_HEADER_SIZE;
    for (int i = 0; i < header.numSamples; i++) {
      if (offset + 12 > data.length) break;
      samples.add(PpgWristSample(
        ir: byteData.getUint32(offset, Endian.little),
        red: byteData.getUint32(offset + 4, Endian.little),
        green: byteData.getUint32(offset + 8, Endian.little),
      ));
      offset += 12;
    }

    return samples;
  }

  /// Parse PPG Finger samples (8 bytes each: IR, Red as uint32)
  List<PpgFingerSample> parsePpgFingerSamples(Uint8List data) {
    final header = parseHeader(data);
    final samples = <PpgFingerSample>[];
    final byteData = data.buffer.asByteData(data.offsetInBytes);

    int offset = hPi4Global.REC_FILE_HEADER_SIZE;
    for (int i = 0; i < header.numSamples; i++) {
      if (offset + 8 > data.length) break;
      samples.add(PpgFingerSample(
        ir: byteData.getUint32(offset, Endian.little),
        red: byteData.getUint32(offset + 4, Endian.little),
      ));
      offset += 8;
    }

    return samples;
  }

  /// Parse Accelerometer samples (6 bytes each: X, Y, Z as int16)
  List<AccelSample> parseAccelSamples(Uint8List data) {
    final header = parseHeader(data);
    final samples = <AccelSample>[];
    final byteData = data.buffer.asByteData(data.offsetInBytes);

    int offset = hPi4Global.REC_FILE_HEADER_SIZE;
    for (int i = 0; i < header.numSamples; i++) {
      if (offset + 6 > data.length) break;
      samples.add(AccelSample(
        x: byteData.getInt16(offset, Endian.little),
        y: byteData.getInt16(offset + 2, Endian.little),
        z: byteData.getInt16(offset + 4, Endian.little),
      ));
      offset += 6;
    }

    return samples;
  }

  /// Parse Gyroscope samples (6 bytes each: X, Y, Z as int16)
  List<GyroSample> parseGyroSamples(Uint8List data) {
    final header = parseHeader(data);
    final samples = <GyroSample>[];
    final byteData = data.buffer.asByteData(data.offsetInBytes);

    int offset = hPi4Global.REC_FILE_HEADER_SIZE;
    for (int i = 0; i < header.numSamples; i++) {
      if (offset + 6 > data.length) break;
      samples.add(GyroSample(
        x: byteData.getInt16(offset, Endian.little),
        y: byteData.getInt16(offset + 2, Endian.little),
        z: byteData.getInt16(offset + 4, Endian.little),
      ));
      offset += 6;
    }

    return samples;
  }

  /// Parse GSR samples (4 bytes each: value as int32)
  List<GsrSample> parseGsrSamples(Uint8List data) {
    final header = parseHeader(data);
    final samples = <GsrSample>[];
    final byteData = data.buffer.asByteData(data.offsetInBytes);

    int offset = hPi4Global.REC_FILE_HEADER_SIZE;
    for (int i = 0; i < header.numSamples; i++) {
      if (offset + 4 > data.length) break;
      samples.add(GsrSample(
        value: byteData.getInt32(offset, Endian.little),
      ));
      offset += 4;
    }

    return samples;
  }

  // ============================================================================
  // Export Functions
  // ============================================================================

  /// Generate CSV content from binary data (returns string, not file)
  String _generateCsvContent(
      ResearchRecording session,
      ResearchSignalType signal,
      Uint8List data,
      ) {
    final header = parseHeader(data);
    final rows = <List<String>>[];

    // Generate timestamps for each sample
    final startTime = header.startTime;
    final sampleIntervalMs = 1000.0 / header.sampleRateHz;

    switch (signal) {
      case ResearchSignalType.ppgWrist:
        rows.add(['timestamp', 'ir', 'red', 'green']);
        final samples = parsePpgWristSamples(data);
        for (int i = 0; i < samples.length; i++) {
          final ts = startTime.add(Duration(milliseconds: (i * sampleIntervalMs).round()));
          rows.add([
            ts.toIso8601String(),
            samples[i].ir.toString(),
            samples[i].red.toString(),
            samples[i].green.toString(),
          ]);
        }
        break;

      case ResearchSignalType.ppgFinger:
        rows.add(['timestamp', 'ir', 'red']);
        final samples = parsePpgFingerSamples(data);
        for (int i = 0; i < samples.length; i++) {
          final ts = startTime.add(Duration(milliseconds: (i * sampleIntervalMs).round()));
          rows.add([
            ts.toIso8601String(),
            samples[i].ir.toString(),
            samples[i].red.toString(),
          ]);
        }
        break;

      case ResearchSignalType.accel:
        rows.add(['timestamp', 'x', 'y', 'z']);
        final samples = parseAccelSamples(data);
        for (int i = 0; i < samples.length; i++) {
          final ts = startTime.add(Duration(milliseconds: (i * sampleIntervalMs).round()));
          rows.add([
            ts.toIso8601String(),
            samples[i].x.toString(),
            samples[i].y.toString(),
            samples[i].z.toString(),
          ]);
        }
        break;

      case ResearchSignalType.gyro:
        rows.add(['timestamp', 'x', 'y', 'z']);
        final samples = parseGyroSamples(data);
        for (int i = 0; i < samples.length; i++) {
          final ts = startTime.add(Duration(milliseconds: (i * sampleIntervalMs).round()));
          rows.add([
            ts.toIso8601String(),
            samples[i].x.toString(),
            samples[i].y.toString(),
            samples[i].z.toString(),
          ]);
        }
        break;

      case ResearchSignalType.gsr:
        rows.add(['timestamp', 'value']);
        final samples = parseGsrSamples(data);
        for (int i = 0; i < samples.length; i++) {
          final ts = startTime.add(Duration(milliseconds: (i * sampleIntervalMs).round()));
          rows.add([
            ts.toIso8601String(),
            samples[i].value.toString(),
          ]);
        }
        break;
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Export signal data to CSV file
  Future<File> exportToCsv(
      ResearchRecording session,
      ResearchSignalType signal,
      Uint8List data,
      ) async {
    final csvContent = _generateCsvContent(session, signal, data);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = '${signal.shortName.toLowerCase()}_${session.sessionTimestamp}.csv';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csvContent);

    print('[ResearchRecordingManager] Exported CSV: ${file.path}');
    return file;
  }

  /// Export session metadata to JSON file
  Future<File> exportMetadataToJson(
      ResearchRecording session,
      Map<ResearchSignalType, Uint8List> signalData,
      ) async {
    final metadata = <String, dynamic>{
      'sessionTimestamp': session.sessionTimestamp,
      'startTime': session.startTime.toIso8601String(),
      'endTime': session.endTime.toIso8601String(),
      'durationSeconds': session.durationSeconds,
      'signalMask': session.signalMask,
      'signals': <String, dynamic>{},
    };

    for (final entry in signalData.entries) {
      try {
        final header = parseHeader(entry.value);
        metadata['signals'][entry.key.shortName.toLowerCase()] = {
          'sampleRate': header.sampleRateHz,
          'sampleCount': header.numSamples,
          'fileSize': entry.value.length,
        };
      } catch (e) {
        print('[ResearchRecordingManager] Error parsing header for ${entry.key}: $e');
      }
    }

    final jsonContent = const JsonEncoder.withIndent('  ').convert(metadata);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'meta_${session.sessionTimestamp}.json';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonContent);

    print('[ResearchRecordingManager] Exported JSON: ${file.path}');
    return file;
  }

  /// Export all session data to ZIP archive (CSV files only, no binary)
  Future<File> exportToZip(
      ResearchRecording session,
      Map<ResearchSignalType, Uint8List> signalData,
      ) async {
    final archive = Archive();

    // Add metadata JSON
    final metadata = session.toJson();
    metadata['signals'] = <String, dynamic>{};

    for (final entry in signalData.entries) {
      try {
        final header = parseHeader(entry.value);
        metadata['signals'][entry.key.shortName.toLowerCase()] = {
          'sampleRate': header.sampleRateHz,
          'sampleCount': header.numSamples,
          'fileSize': entry.value.length,
        };

        // Generate and add CSV content directly to archive
        final csvContent = _generateCsvContent(session, entry.key, entry.value);
        final csvBytes = utf8.encode(csvContent);
        archive.addFile(ArchiveFile(
          '${entry.key.shortName.toLowerCase()}.csv',
          csvBytes.length,
          csvBytes,
        ));
        print('[ResearchRecordingManager] Added CSV to ZIP: ${entry.key.shortName.toLowerCase()}.csv');
      } catch (e) {
        print('[ResearchRecordingManager] Error creating CSV for ${entry.key}: $e');
      }
    }

    // Add metadata JSON
    final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(metadata));
    archive.addFile(ArchiveFile('meta.json', jsonBytes.length, jsonBytes));

    // Create ZIP
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Failed to create ZIP archive');
    }

    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'research_recording_${session.sessionTimestamp}.zip';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(zipData);

    print('[ResearchRecordingManager] Exported ZIP: ${file.path}');
    return file;
  }


  /// Get local storage directory for a session
  Future<Directory> getSessionDirectory(ResearchRecording session, String deviceMac) async {
    final appDir = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(
      '${appDir.path}/HealthyPiRecordings/$deviceMac/research/${session.sessionTimestamp}',
    );
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    return sessionDir;
  }

  /// Save downloaded signal file to local storage
  Future<File> saveSignalFile(
    ResearchRecording session,
    ResearchSignalType signal,
    Uint8List data,
    String deviceMac,
  ) async {
    final sessionDir = await getSessionDirectory(session, deviceMac);
    final file = File('${sessionDir.path}/${signal.fileName}');
    await file.writeAsBytes(data);
    print('[ResearchRecordingManager] Saved: ${file.path}');
    return file;
  }
}

// ============================================================================
// Sample Data Classes
// ============================================================================

/// PPG Wrist sample (IR, Red, Green channels)
class PpgWristSample {
  final int ir;
  final int red;
  final int green;

  const PpgWristSample({
    required this.ir,
    required this.red,
    required this.green,
  });
}

/// PPG Finger sample (IR, Red channels)
class PpgFingerSample {
  final int ir;
  final int red;

  const PpgFingerSample({
    required this.ir,
    required this.red,
  });
}

/// Accelerometer sample (X, Y, Z axes)
class AccelSample {
  final int x;
  final int y;
  final int z;

  const AccelSample({
    required this.x,
    required this.y,
    required this.z,
  });
}

/// Gyroscope sample (X, Y, Z axes)
class GyroSample {
  final int x;
  final int y;
  final int z;

  const GyroSample({
    required this.x,
    required this.y,
    required this.z,
  });
}

/// GSR sample (raw BioZ value)
class GsrSample {
  final int value;

  const GsrSample({required this.value});
}
