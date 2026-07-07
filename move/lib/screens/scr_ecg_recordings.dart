import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../mcumgr/fs_mgmt.dart';
import '../smp/smp_ble_transport.dart';
import '../smp/smp_client.dart';
import '../utils/connection_manager.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import '../globals.dart';
import '../utils/snackbar.dart';

// ECG Recording Constants
class EcgConstants {
  static const int samplingRateHz = 128;
  static const int fileHeaderBytes = 10;
  static const int bytesPerSample = 4;
  static const int maxAdcValue = 8388608;
  static const double vRef = 1.0;
  static const double gain = 20.0;
  static const int sampleCountThreshold = 1000;
  static const int estimatedMinutesBetweenSessions = 5;
  static const int estimatedMaxSessionId = 100;
}

typedef LogHeader = ({int logFileID, int sessionLength});

/// Represents a single ECG recording session
class EcgRecording {
  final int sessionId;
  final int sessionLength;
  final DateTime timestamp;
  final int timestampSec;
  final String filePath;

  bool isDownloading = false;
  double downloadProgress = 0.0;

  EcgRecording({
    required this.sessionId,
    required this.sessionLength,
    required this.timestamp,
    required this.timestampSec,
  }) : filePath = '/lfs/ecg/$sessionId';

  String get displayName => 'ECG Recording #$sessionId';

  String get dateTime {
    print('ECG Recording: Session $sessionId timestamp: ${timestamp.toIso8601String()} (year: ${timestamp.year})');
    return DateFormat('EEE d MMM yyyy h:mm a').format(timestamp);
  }

  String get durationText {
    final sampleCount = sessionLength ~/ EcgConstants.bytesPerSample;
    final durationSeconds = (sampleCount / EcgConstants.samplingRateHz).toInt();
    return '$durationSeconds seconds • ${_formatSampleCount(sampleCount)} samples';
  }

  static String _formatSampleCount(int count) {
    if (count >= EcgConstants.sampleCountThreshold) {
      return '${(count / EcgConstants.sampleCountThreshold).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

/// Content-only version of ECG recordings for embedding in tabs
class ScrEcgRecordingsContent extends StatefulWidget {
  final String deviceMacAddress;

  const ScrEcgRecordingsContent({super.key, required this.deviceMacAddress});

  @override
  State<ScrEcgRecordingsContent> createState() => ScrEcgRecordingsContentState();
}

// NOTE: Public (no underscore) so it can be accessed via GlobalKey
// from scr_recordings_hub.dart
class ScrEcgRecordingsContentState extends State<ScrEcgRecordingsContent> {
  final ConnectionManager _conn = ConnectionManager.instance;
  SmpBleTransport? _smpTransport;
  SmpClient? _smpClient;
  FsMgmt? _fs;

  List<EcgRecording> _recordings = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  final List<StreamSubscription> _activeSubscriptions = [];

  int _totalSessionCount = 0;
  List<LogHeader> _logHeaderList = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _conn.connect(widget.deviceMacAddress);
      await Future.delayed(const Duration(milliseconds: 500));

      final transport =
          SmpBleTransport(widget.deviceMacAddress, manageConnection: false);
      await transport.connect();
      _smpTransport = transport;
      _smpClient = SmpClient(transport);
      _fs = FsMgmt(_smpClient!, maxWriteLength: () => _smpTransport?.maxWriteLength);

      await _loadRecordingsList();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Initialization failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRecordingsList() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _logHeaderList.clear();
    });

    try {
      await _fetchSessionCount();
      await _fetchSessionIndices();

      final recordings = <EcgRecording>[];
      for (final header in _logHeaderList) {
        final sampleCount = header.sessionLength ~/ EcgConstants.bytesPerSample;
        const millisecondsPerSecond = 1000;
        final timestampMs = header.logFileID * millisecondsPerSecond;
        final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: false);

        recordings.add(EcgRecording(
          sessionId: header.logFileID,
          sessionLength: header.sessionLength,
          timestamp: dt,
          timestampSec: header.logFileID,
        ));
      }

      recordings.sort((a, b) => b.sessionId.compareTo(a.sessionId));

      if (mounted) {
        setState(() {
          _recordings = recordings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load recordings: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSessionCount() async {
    final completer = Completer<int>();

    late StreamSubscription<Uint8List> subscription;
    subscription = _conn
        .subscribe(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD_DATA)
        .listen((value) {
      final bdata = Uint8List.fromList(value).buffer.asByteData();
      final pktType = bdata.getUint8(0);

      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        final trendCode = bdata.getUint8(2);
        if (trendCode == hPi4Global.ECGRecord[0]) {
          _totalSessionCount = bdata.getUint16(3, Endian.little);
          subscription.cancel();
          _activeSubscriptions.remove(subscription);
          completer.complete(_totalSessionCount);
        }
      }
    });

    _activeSubscriptions.add(subscription);

    final commandPacket = <int>[];
    commandPacket.addAll(hPi4Global.ECGLogCount);
    commandPacket.addAll(hPi4Global.ECGRecord);
    await _conn.write(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD,
          Uint8List.fromList(commandPacket));

    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Timeout fetching session count');
      },
    );
  }

  Future<void> _fetchSessionIndices() async {
    if (_totalSessionCount == 0) return;

    final completer = Completer<void>();

    late StreamSubscription<Uint8List> subscription;
    subscription = _conn
        .subscribe(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD_DATA)
        .listen((value) {
      final bdata = Uint8List.fromList(value).buffer.asByteData();
      final pktType = bdata.getUint8(0);

      if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        final logFileID = bdata.getInt64(1, Endian.little);
        final sessionLength = bdata.getUint16(9, Endian.little);

        _logHeaderList.add((logFileID: logFileID, sessionLength: sessionLength));

        if (_logHeaderList.length == _totalSessionCount) {
          subscription.cancel();
          _activeSubscriptions.remove(subscription);
          completer.complete();
        }
      }
    });

    _activeSubscriptions.add(subscription);

    final commandPacket = <int>[];
    commandPacket.addAll(hPi4Global.ECGLogIndex);
    commandPacket.addAll(hPi4Global.ECGRecord);
    await _conn.write(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD,
          Uint8List.fromList(commandPacket));

    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Timeout fetching session indices');
      },
    );
  }

  /// Public method called from ScrRecordingsHub to wipe all ECG recordings
  Future<void> wipeAll() async {
    if (!_conn.isConnected) return;

    try {
      final commandPacket = <int>[];
      commandPacket.addAll(hPi4Global.ECGLogWipeAll); // <-- replace with your actual wipe-all command constant
      commandPacket.addAll(hPi4Global.ECGRecord);
      await _conn.write(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD,
          Uint8List.fromList(commandPacket));
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadRecordingsList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All ECG recordings wiped from device'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wipe failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRecording(EcgRecording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Delete Recording',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this ECG recording? This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final commandPacket = <int>[];
      commandPacket.addAll(hPi4Global.ECGLogDelete);
      commandPacket.addAll(hPi4Global.ECGRecord);

      final timestampBytes = ByteData(8);
      timestampBytes.setInt64(0, recording.timestampSec, Endian.little);
      commandPacket.addAll(timestampBytes.buffer.asUint8List());

      await _conn.write(hPi4Global.UUID_SERVICE_CMD, hPi4Global.UUID_CHAR_CMD,
          Uint8List.fromList(commandPacket));
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadRecordingsList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording deleted successfully'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadRecording(EcgRecording recording) async {
    if (recording.isDownloading) return;

    setState(() {
      recording.isDownloading = true;
      recording.downloadProgress = 0.0;
    });

    try {
      final binaryData = await _fs!.download(
        recording.filePath,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              recording.downloadProgress = total > 0 ? done / total : 0.0;
            });
          }
        },
      );

      await _exportToCsv(recording, binaryData);

      if (mounted) {
        setState(() {
          recording.isDownloading = false;
        });
      }

      Snackbar.show(ABC.c, 'Recording downloaded successfully!', success: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          recording.isDownloading = false;
        });
      }
      Snackbar.show(ABC.c, 'Download failed: $e', success: false);
    }
  }

  Future<void> _exportToCsv(EcgRecording recording, List<int> binaryData) async {
    List<int> cleanData = binaryData;
    final byteData = ByteData.sublistView(Uint8List.fromList(cleanData));
    final numSamples = cleanData.length ~/ EcgConstants.bytesPerSample;

    final csvRows = <List<String>>[];
    csvRows.add(['ECG(mV)']);

    for (int i = 0; i < numSamples; i++) {
      try {
        final rawValue =
        byteData.getInt32(i * EcgConstants.bytesPerSample, Endian.little);
        final millivolts = _convertToMillivolts(rawValue);
        csvRows.add([millivolts.toStringAsFixed(2)]);
      } catch (e) {
        break;
      }
    }

    String csvContent = const ListToCsvConverter().convert(csvRows);
    await _saveAndShareCsv(
      csvContent,
      'ecg_recording_${recording.sessionId}_${DateFormat('yyyyMMdd_HHmmss').format(recording.timestamp)}.csv',
    );
  }

  Future<void> _saveAndShareCsv(String csvContent, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = directory.path;
    await Directory(path).create(recursive: true);

    final file = File('$path/$fileName');
    await file.writeAsString(csvContent);

    final xFile = XFile(file.path);
    await Share.shareXFiles([xFile], text: 'ECG Recording');
  }

  double _convertToMillivolts(int rawValue) {
    const int maxAdcValue = 8388608;
    const double vRef = 1.0;
    const double gain = 20.0;
    return ((rawValue / maxAdcValue) * (vRef * 1000 / gain));
  }

  void _cleanup() {
    for (var sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();

    _smpClient?.dispose();
    _smpClient = null;
    _smpTransport?.disconnect();
    _smpTransport?.dispose();
    _smpTransport = null;
    _fs = null;
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading recordings...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadRecordingsList,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              const Text(
                'No ECG recordings found',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Record ECG data on your device to see it here',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadRecordingsList,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hPi4Global.hpi4Color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecordingsList,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _recordings.length,
        itemBuilder: (context, index) =>
            _buildRecordingCard(_recordings[index]),
      ),
    );
  }

  Widget _buildRecordingCard(EcgRecording recording) {
    return Card(
      color: const Color(0xFF2D2D2D),
      elevation: 4,
      shadowColor: Colors.black54,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hPi4Global.hpi4Color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.monitor_heart,
                    color: hPi4Global.hpi4Color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recording.dateTime,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recording.durationText,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (recording.isDownloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: recording.downloadProgress,
                backgroundColor: Colors.grey[700],
                valueColor:
                AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
              ),
              const SizedBox(height: 4),
              Text(
                'Downloading... ${(recording.downloadProgress * 100).toInt()}%',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadRecording(recording),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: hPi4Global.hpi4Color,
                        side: BorderSide(color: hPi4Global.hpi4Color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _deleteRecording(recording),
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red[300],
                    tooltip: 'Delete recording',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}