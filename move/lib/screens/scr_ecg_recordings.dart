import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mcumgr_flutter/mcumgr_flutter.dart' as mcumgr;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import '../globals.dart';
import '../utils/snackbar.dart';

// ECG Recording Constants
class EcgConstants {
  // Sample rate for ECG recordings in Hz
  static const int samplingRateHz = 128;
  
  // File format constants
  static const int fileHeaderBytes = 10;
  static const int bytesPerSample = 4;
  
  // ADC conversion constants
  static const int maxAdcValue = 8388608; // 2^23 for 24-bit signed
  static const double vRef = 1.0; // volts
  static const double gain = 20.0; // amplifier gain
  
  // Display formatting
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
  final String filePath;
  
  bool isDownloading = false;
  double downloadProgress = 0.0;
  
  EcgRecording({
    required this.sessionId,
    required this.sessionLength,
    required this.timestamp,
  }) : filePath = '/lfs/ecg/$sessionId';
  
  String get displayName => 'ECG Recording #$sessionId';
  
  String get dateTime {
    // Debug timestamp (device stores in local time)
    print('ECG Recording: Session $sessionId timestamp: ${timestamp.toIso8601String()} (year: ${timestamp.year})');
    return DateFormat('EEE d MMM yyyy h:mm a').format(timestamp);
  }
  
  String get durationText {
    // sessionLength is the number of data bytes (points start from beginning of file)
    // Calculate sample count: dataBytes / bytesPerSample
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

/// Modern ECG recordings management screen using FsManager for downloads
class ScrEcgRecordings extends StatefulWidget {
  final String deviceMacAddress;
  
  const ScrEcgRecordings({super.key, required this.deviceMacAddress});
  
  @override
  State<ScrEcgRecordings> createState() => _ScrEcgRecordingsState();
}

class _ScrEcgRecordingsState extends State<ScrEcgRecordings> {
  BluetoothDevice? _device;
  mcumgr.FsManager? _fsManager;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _dataCharacteristic;
  
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
      // Create device from MAC address and connect
      _device = BluetoothDevice.fromId(widget.deviceMacAddress);
      
      if (_device!.isDisconnected) {
        await _device!.connect(license: License.values.first);
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Discover services and characteristics
      final services = await _device!.discoverServices();
      
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
        throw Exception('Required characteristics not found');
      }
      
      // Initialize FsManager for downloads
      _fsManager = mcumgr.FsManager(_device!.remoteId.toString());
      
      // Load recordings list
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
      // Fetch session count
      await _fetchSessionCount();
      
      // Fetch session indices
      await _fetchSessionIndices();
      
      // Convert to EcgRecording objects
      final recordings = <EcgRecording>[];
      print('ECG Recordings: Converting ${_logHeaderList.length} headers to recording objects...');
      
      for (final header in _logHeaderList) {
        // sessionLength is the number of data bytes (no header bytes to subtract)
        // Calculate sample count: dataBytes / bytesPerSample
        final sampleCount = header.sessionLength ~/ EcgConstants.bytesPerSample;
        final durationSeconds = (sampleCount / EcgConstants.samplingRateHz).toInt();
        
        // Parse timestamp from session ID (Unix epoch in seconds)
        // Device stores timestamps in LOCAL time, so interpret as local
        const millisecondsPerSecond = 1000;
        final timestampMs = header.logFileID * millisecondsPerSecond;
        final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: false);
        print('ECG Recordings:   - Session ${header.logFileID}: ${header.sessionLength} bytes = $sampleCount samples = ${durationSeconds}s');
        print('ECG Recordings:     Timestamp: ${header.logFileID}s → ${dt.toIso8601String()} (year: ${dt.year})');
        
        recordings.add(EcgRecording(
          sessionId: header.logFileID,
          sessionLength: header.sessionLength,
          timestamp: dt,
        ));
      }
      
      // Sort by session ID descending (most recent first)
      recordings.sort((a, b) => b.sessionId.compareTo(a.sessionId));
      print('ECG Recordings: Recordings sorted. Displaying ${recordings.length} card(s)');
      
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
  
  /// Fetch session count using custom BLE protocol
  Future<void> _fetchSessionCount() async {
    print('ECG Recordings: Fetching session count...');
    
    final completer = Completer<int>();
    
    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      final bdata = Uint8List.fromList(value).buffer.asByteData();
      final pktType = bdata.getUint8(0);
      
      if (pktType == hPi4Global.CES_CMDIF_TYPE_CMD_RSP) {
        final trendCode = bdata.getUint8(2);
        if (trendCode == hPi4Global.ECGRecord[0]) {
          _totalSessionCount = bdata.getUint16(3, Endian.little);
          print('ECG Recordings: Session count received: $_totalSessionCount');
          subscription.cancel();
          _activeSubscriptions.remove(subscription);
          completer.complete(_totalSessionCount);
        }
      }
    });
    
    _activeSubscriptions.add(subscription);
    _device!.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);
    
    // Send command
    final commandPacket = <int>[];
    commandPacket.addAll(hPi4Global.ECGLogCount);
    commandPacket.addAll(hPi4Global.ECGRecord);
    await _sendCommand(commandPacket);
    print('ECG Recordings: Sent ECGLogCount command');
    
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('ECG Recordings: ⚠️ TIMEOUT waiting for session count');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Timeout fetching session count');
      },
    );
  }
  
  /// Fetch session indices using custom BLE protocol
  Future<void> _fetchSessionIndices() async {
    if (_totalSessionCount == 0) {
      print('ECG Recordings: No sessions to fetch (count = 0)');
      return;
    }
    
    print('ECG Recordings: Fetching indices for $_totalSessionCount session(s)...');
    
    final completer = Completer<void>();
    
    late StreamSubscription<List<int>> subscription;
    subscription = _dataCharacteristic!.onValueReceived.listen((value) {
      final bdata = Uint8List.fromList(value).buffer.asByteData();
      final pktType = bdata.getUint8(0);
      
      if (pktType == hPi4Global.CES_CMDIF_TYPE_LOG_IDX) {
        final logFileID = bdata.getInt64(1, Endian.little);
        final sessionLength = bdata.getUint16(9, Endian.little); // uint16 as per device protocol
        
        print('ECG Recordings: Received index - Session ID: $logFileID, Length: $sessionLength samples');
        
        _logHeaderList.add((logFileID: logFileID, sessionLength: sessionLength));
        
        if (_logHeaderList.length == _totalSessionCount) {
          print('ECG Recordings: All ${_logHeaderList.length} indices received');
          subscription.cancel();
          _activeSubscriptions.remove(subscription);
          completer.complete();
        }
      }
    });
    
    _activeSubscriptions.add(subscription);
    _device!.cancelWhenDisconnected(subscription);
    await _dataCharacteristic!.setNotifyValue(true);
    
    // Send command
    final commandPacket = <int>[];
    commandPacket.addAll(hPi4Global.ECGLogIndex);
    commandPacket.addAll(hPi4Global.ECGRecord);
    await _sendCommand(commandPacket);
    print('ECG Recordings: Sent ECGLogIndex command');
    
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        print('ECG Recordings: ⚠️ TIMEOUT waiting for session indices');
        subscription.cancel();
        _activeSubscriptions.remove(subscription);
        throw TimeoutException('Timeout fetching session indices');
      },
    );
    
    print('ECG Recordings: Session indices fetch complete. Total headers: ${_logHeaderList.length}');
  }
  
  Future<void> _sendCommand(List<int> commandList) async {
    await _commandCharacteristic?.write(commandList, withoutResponse: true);
  }
  
  /// Delete a single ECG recording
  Future<void> _deleteRecording(EcgRecording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Delete Recording', style: TextStyle(color: Colors.white)),
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
      // Send delete command via BLE
      final commandPacket = <int>[];
      commandPacket.addAll(hPi4Global.ECGLogDelete);
      commandPacket.addAll(hPi4Global.ECGRecord);
      
      // Add session ID as 2-byte little-endian
      final sessionIdBytes = ByteData(2);
      sessionIdBytes.setUint16(0, recording.sessionId & 0xFFFF, Endian.little);
      commandPacket.addAll(sessionIdBytes.buffer.asUint8List());
      
      await _sendCommand(commandPacket);
      print('ECG Recordings: Sent delete command for session ${recording.sessionId}');
      
      // Wait a moment for device to process
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Refresh the list
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
      print('Error deleting recording: $e');
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

  /// Wipe all ECG recordings from device
  Future<void> _wipeAllRecordings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Wipe All Recordings?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete all ${_recordings.length} ECG recording(s) from your device. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Wipe All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Send wipe all command via BLE
      final commandPacket = <int>[];
      commandPacket.addAll(hPi4Global.ECGLogWipeAll);
      commandPacket.addAll(hPi4Global.ECGRecord);
      
      await _sendCommand(commandPacket);
      print('ECG Recordings: Sent wipe all command');
      
      // Wait for device to process
      await Future.delayed(const Duration(seconds: 1));
      
      // Refresh the list
      await _loadRecordingsList();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All recordings deleted successfully'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      print('Error wiping recordings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to wipe recordings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Download a single ECG recording using FsManager
  Future<void> _downloadRecording(EcgRecording recording) async {
    if (recording.isDownloading) return;
    
    setState(() {
      recording.isDownloading = true;
      recording.downloadProgress = 0.0;
    });
    
    try {
      final completer = Completer<List<int>>();
      
      late StreamSubscription downloadSubscription;
      downloadSubscription = _fsManager!.downloadCallbacks.listen((event) {
        if (event.path == recording.filePath) {
          print('ECG Download Event: ${event.runtimeType} for ${event.path}');
          
          if (event is mcumgr.OnDownloadCompleted) {
            print('ECG Download: Completed - ${event.data.length} bytes');
            downloadSubscription.cancel();
            _activeSubscriptions.remove(downloadSubscription);
            completer.complete(event.data);
          } else if (event is mcumgr.OnDownloadFailed) {
            print('ECG Download: Failed - ${event.cause}');
            downloadSubscription.cancel();
            _activeSubscriptions.remove(downloadSubscription);
            completer.completeError(Exception('Download failed: ${event.cause}'));
          } else if (event is mcumgr.OnDownloadCancelled) {
            print('ECG Download: Cancelled');
            downloadSubscription.cancel();
            _activeSubscriptions.remove(downloadSubscription);
            completer.completeError(Exception('Download cancelled'));
          } else if (event is mcumgr.OnDownloadProgressChanged) {
            // The mcumgr package's OnDownloadProgressChanged may not expose progress fields
            // So we'll estimate progress based on time or use a simple incremental approach
            // This is a limitation of the current mcumgr_flutter package
            print('ECG Download: Progress event received (no accessible progress data)');
            
            // Simulate progress - increment by small amount each callback
            // This at least shows activity even if not accurate
            if (mounted) {
              setState(() {
                // Increment by 5% each callback, capped at 90% until completion
                recording.downloadProgress = (recording.downloadProgress + 0.05).clamp(0.0, 0.9);
                print('ECG Download: Estimated progress ${(recording.downloadProgress * 100).toStringAsFixed(0)}%');
              });
            }
          }
        }
      });
      
      _activeSubscriptions.add(downloadSubscription);
      await _fsManager!.download(recording.filePath);
      
      final binaryData = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          downloadSubscription.cancel();
          _activeSubscriptions.remove(downloadSubscription);
          throw TimeoutException('Download timeout');
        },
      );
      
      // Convert to CSV and export
      await _exportToCsv(recording, binaryData);
      
      if (mounted) {
        setState(() {
          recording.isDownloading = false;
        });
      }
      
      Snackbar.show(
        ABC.c,
        'Recording downloaded successfully!',
        success: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          recording.isDownloading = false;
        });
      }
      
      Snackbar.show(
        ABC.c,
        'Download failed: $e',
        success: false,
      );
    }
  }
  
  /// Convert ECG binary data to CSV and share
  Future<void> _exportToCsv(EcgRecording recording, List<int> binaryData) async {
    print('ECG Export: Binary data length: ${binaryData.length} bytes');
    print('ECG Export: Expected session length: ${recording.sessionLength} bytes');
    
    // FsManager downloads raw files from device filesystem - no packet type byte or header
    // Data starts immediately with ECG samples (Int32 little-endian)
    List<int> cleanData = binaryData;
    
    final byteData = ByteData.sublistView(Uint8List.fromList(cleanData));
    final numSamples = cleanData.length ~/ EcgConstants.bytesPerSample;
    
    print('ECG Export: Calculated $numSamples samples');
    
    // Create CSV content - match archived format (ECG values only, no time column)
    final csvRows = <List<String>>[];
    csvRows.add(['ECG(mV)']); // Match archived format exactly
    
    for (int i = 0; i < numSamples; i++) {
      try {
        // ECG samples are Int32 in little-endian format
        final rawValue = byteData.getInt32(i * EcgConstants.bytesPerSample, Endian.little);
        final millivolts = _convertToMillivolts(rawValue);
        // Match archived format: 2 decimal places, no time column
        csvRows.add([millivolts.toStringAsFixed(2)]);
      } catch (e) {
        print('Error parsing sample $i: $e');
        break;
      }
    }
    
    print('ECG Export: Generated ${csvRows.length - 1} CSV rows');
    
    // Convert to CSV string
    String csvContent = const ListToCsvConverter().convert(csvRows);
    
    // Save and share
    await _saveAndShareCsv(
      csvContent,
      'ecg_recording_${recording.sessionId}_${DateFormat('yyyyMMdd_HHmmss').format(recording.timestamp)}.csv',
    );
  }
  
  /// Save CSV to file and share it
  Future<void> _saveAndShareCsv(String csvContent, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      await Directory(path).create(recursive: true);
      
      final file = File('$path/$fileName');
      await file.writeAsString(csvContent);
      
      final xFile = XFile(file.path);
      await Share.shareXFiles(
        [xFile],
        text: 'ECG Recording',
      );
    } catch (e) {
      print('Error sharing file: $e');
      rethrow;
    }
  }
  
  double _convertToMillivolts(int rawValue) {
    const int maxAdcValue = 8388608; // 2^23 for 24-bit signed
    const double vRef = 1.0; // volts
    const double gain = 20.0; // amplifier gain
    return ((rawValue / maxAdcValue) * (vRef * 1000 / gain));
  }
  
  /// Download all recordings
  Future<void> _downloadAllRecordings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Download All Recordings?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will download ${_recordings.length} recording(s) as CSV files.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: hPi4Global.hpi4Color),
            child: const Text('Download All'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    for (final recording in _recordings) {
      if (!recording.isDownloading) {
        await _downloadRecording(recording);
        // Small delay between downloads
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
  
  void _cleanup() {
    for (var sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
    
    if (_fsManager != null) {
      _fsManager!.kill();
      _fsManager = null;
    }
    
    // Disconnect from device
    if (_device != null) {
      _device!.disconnect().catchError((e) {
        print('Error disconnecting device: $e');
      });
      _device = null;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('ECG Recordings'),
        backgroundColor: hPi4Global.hpi4AppBarColor,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading && _recordings.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'download_all':
                    _downloadAllRecordings();
                    break;
                  case 'wipe_all':
                    _wipeAllRecordings();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'download_all',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 8),
                      Text('Download All'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'wipe_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Wipe All Recordings', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          if (!_isLoading)
            IconButton(
              icon: Icon(_isRefreshing ? Icons.hourglass_empty : Icons.refresh),
              onPressed: _isRefreshing ? null : () async {
                setState(() => _isRefreshing = true);
                await _loadRecordingsList();
                if (mounted) {
                  setState(() => _isRefreshing = false);
                }
              },
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildBody(),
    );
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
        itemBuilder: (context, index) => _buildRecordingCard(_recordings[index]),
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
                valueColor: AlwaysStoppedAnimation<Color>(hPi4Global.hpi4Color),
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
