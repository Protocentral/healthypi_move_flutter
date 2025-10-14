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
  String get dateTime => DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp);
  String get durationText {
    // sessionLength is already in number of samples/points, not bytes
    final sampleCount = sessionLength;
    final durationSeconds = (sampleCount / 400).toInt(); // 400 Hz sample rate
    return '$durationSeconds seconds • ${_formatSampleCount(sampleCount)} samples';
  }
  
  static String _formatSampleCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
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
        // Estimate timestamp from session ID (most recent = highest ID)
        final timestamp = DateTime.now().subtract(
          Duration(minutes: (100 - header.logFileID) * 5),
        );
        
        // sessionLength is in number of samples/points, not bytes
        final sampleCount = header.sessionLength;
        final durationSeconds = (sampleCount / 400).toInt();
        
        print('ECG Recordings:   - Session ${header.logFileID}: $sampleCount samples = ${durationSeconds}s');
        
        recordings.add(EcgRecording(
          sessionId: header.logFileID,
          sessionLength: header.sessionLength,
          timestamp: timestamp,
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
        final sessionLength = bdata.getInt32(9, Endian.little);
        
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
          // Update progress if available
          try {
            // Try to access progress field via dynamic dispatch
            final dynamic dynamicEvent = event;
            if (dynamicEvent.progress != null) {
              if (mounted) {
                setState(() {
                  recording.downloadProgress = dynamicEvent.progress / 100.0;
                });
              }
            }
          } catch (_) {
            // Ignore if progress not available
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
    // Remove packet type byte if present
    int offset = (binaryData.isNotEmpty && binaryData[0] == hPi4Global.CES_CMDIF_TYPE_DATA) ? 1 : 0;
    
    // Check for header (typically 10 bytes)
    if (binaryData.length > 10 && offset == 0) {
      offset = 10; // Skip standard header
    } else if (offset == 1 && binaryData.length > 11) {
      offset = 11; // Skip packet type + header
    }
    
    List<int> cleanData = binaryData.sublist(offset);
    
    final byteData = ByteData.sublistView(Uint8List.fromList(cleanData));
    final numSamples = cleanData.length ~/ 4;
    
    // Create CSV content
    final csvRows = <List<String>>[];
    csvRows.add(['Time (ms)', 'ECG (mV)']);
    
    const sampleRateHz = 400; // HealthyPi Move ECG sample rate
    
    for (int i = 0; i < numSamples; i++) {
      try {
        final rawValue = byteData.getInt32(i * 4, Endian.little);
        final millivolts = _convertToMillivolts(rawValue);
        final timeMs = (i / sampleRateHz * 1000).toStringAsFixed(1);
        csvRows.add([timeMs, millivolts.toStringAsFixed(3)]);
      } catch (e) {
        print('Error parsing sample $i: $e');
        break;
      }
    }
    
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
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'download_all',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 12),
                      Text('Download All'),
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
              OutlinedButton.icon(
                onPressed: () => _downloadRecording(recording),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download CSV'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: hPi4Global.hpi4Color,
                  side: BorderSide(color: hPi4Global.hpi4Color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
