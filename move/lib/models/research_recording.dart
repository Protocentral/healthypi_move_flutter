import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../globals.dart';

/// Signal types for research recordings
enum ResearchSignalType {
  ppgWrist,   // Bit 0 (0x01) - PPG Wrist (IR, Red, Green @ 25 Hz)
  ppgFinger,  // Bit 1 (0x02) - PPG Finger (IR, Red @ 25 Hz)
  accel,      // Bit 2 (0x04) - IMU Accelerometer (X, Y, Z @ 100 Hz)
  gyro,       // Bit 3 (0x08) - IMU Gyroscope (X, Y, Z @ 100 Hz)
  gsr,        // Bit 4 (0x10) - GSR (@ 32 Hz)
}

/// Extension to provide utilities for ResearchSignalType
extension ResearchSignalTypeExtension on ResearchSignalType {
  /// Get the bit mask for this signal type
  int get bitMask {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return hPi4Global.SIGNAL_PPG_WRIST;
      case ResearchSignalType.ppgFinger:
        return hPi4Global.SIGNAL_PPG_FINGER;
      case ResearchSignalType.accel:
        return hPi4Global.SIGNAL_ACCEL;
      case ResearchSignalType.gyro:
        return hPi4Global.SIGNAL_GYRO;
      case ResearchSignalType.gsr:
        return hPi4Global.SIGNAL_GSR;
    }
  }

  /// Get the sample rate in Hz for this signal type
  int get sampleRateHz {
    switch (this) {
      case ResearchSignalType.ppgWrist:
      case ResearchSignalType.ppgFinger:
        return hPi4Global.REC_SAMPLE_RATE_PPG;
      case ResearchSignalType.accel:
        return hPi4Global.REC_SAMPLE_RATE_ACCEL;
      case ResearchSignalType.gyro:
        return hPi4Global.REC_SAMPLE_RATE_GYRO;
      case ResearchSignalType.gsr:
        return hPi4Global.REC_SAMPLE_RATE_GSR;
    }
  }

  /// Get the bytes per sample for this signal type
  int get bytesPerSample {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return hPi4Global.REC_SAMPLE_SIZE_PPG_WRIST;
      case ResearchSignalType.ppgFinger:
        return hPi4Global.REC_SAMPLE_SIZE_PPG_FINGER;
      case ResearchSignalType.accel:
        return hPi4Global.REC_SAMPLE_SIZE_ACCEL;
      case ResearchSignalType.gyro:
        return hPi4Global.REC_SAMPLE_SIZE_GYRO;
      case ResearchSignalType.gsr:
        return hPi4Global.REC_SAMPLE_SIZE_GSR;
    }
  }

  /// Get the file name on device for this signal type
  String get fileName {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return 'ppgw.bin';
      case ResearchSignalType.ppgFinger:
        return 'ppgf.bin';
      case ResearchSignalType.accel:
        return 'accel.bin';
      case ResearchSignalType.gyro:
        return 'gyro.bin';
      case ResearchSignalType.gsr:
        return 'gsr.bin';
    }
  }

  /// Get the display name for this signal type
  String get displayName {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return 'PPG Wrist';
      case ResearchSignalType.ppgFinger:
        return 'PPG Finger';
      case ResearchSignalType.accel:
        return 'Accelerometer';
      case ResearchSignalType.gyro:
        return 'Gyroscope';
      case ResearchSignalType.gsr:
        return 'GSR';
    }
  }

  /// Get the short display name for this signal type
  String get shortName {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return 'PPG-W';
      case ResearchSignalType.ppgFinger:
        return 'PPG-F';
      case ResearchSignalType.accel:
        return 'Accel';
      case ResearchSignalType.gyro:
        return 'Gyro';
      case ResearchSignalType.gsr:
        return 'GSR';
    }
  }

  /// Get the icon for this signal type
  IconData get icon {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return Symbols.wrist;
      case ResearchSignalType.ppgFinger:
        return Symbols.cardiology;
      case ResearchSignalType.accel:
        return Symbols.show_chart;
      case ResearchSignalType.gyro:
        return Symbols.rotate_right;
      case ResearchSignalType.gsr:
        return Symbols.eda;
    }
  }

  /// Get the description for this signal type
  String get description {
    switch (this) {
      case ResearchSignalType.ppgWrist:
        return 'IR, Red, Green channels @ ${sampleRateHz} Hz';
      case ResearchSignalType.ppgFinger:
        return 'IR, Red channels @ ${sampleRateHz} Hz';
      case ResearchSignalType.accel:
        return 'X, Y, Z axes @ ${sampleRateHz} Hz';
      case ResearchSignalType.gyro:
        return 'X, Y, Z axes @ ${sampleRateHz} Hz';
      case ResearchSignalType.gsr:
        return 'Raw BioZ value @ ${sampleRateHz} Hz';
    }
  }

  /// Calculate estimated storage in bytes for given duration in seconds
  int estimatedBytes(int durationSeconds) {
    return bytesPerSample * sampleRateHz * durationSeconds + hPi4Global.REC_FILE_HEADER_SIZE;
  }

  /// Calculate estimated storage in KB per minute
  double get kbPerMinute {
    return (bytesPerSample * sampleRateHz * 60) / 1024.0;
  }

  /// Get signal type from file header signal_type byte
  static ResearchSignalType? fromHeaderType(int headerType) {
    switch (headerType) {
      case 0:
        return ResearchSignalType.ppgWrist;
      case 1:
        return ResearchSignalType.ppgFinger;
      case 2:
        return ResearchSignalType.accel;
      case 3:
        return ResearchSignalType.gyro;
      case 4:
        return ResearchSignalType.gsr;
      default:
        return null;
    }
  }

  /// Get all signal types from a signal mask
  static List<ResearchSignalType> fromMask(int mask) {
    final signals = <ResearchSignalType>[];
    for (final signal in ResearchSignalType.values) {
      if ((mask & signal.bitMask) != 0) {
        signals.add(signal);
      }
    }
    return signals;
  }

  /// Create a signal mask from a list of signal types
  static int toMask(List<ResearchSignalType> signals) {
    int mask = 0;
    for (final signal in signals) {
      mask |= signal.bitMask;
    }
    return mask;
  }
}

/// Recording state from device
enum RecordingState {
  idle,       // 0 - No recording active
  armed,      // 1 - Recording configured, ready to start
  recording,  // 2 - Recording in progress
  finalizing, // 3 - Recording complete, writing to storage
  error,      // 4 - Error occurred
}

extension RecordingStateExtension on RecordingState {
  /// Get state from device response byte
  static RecordingState fromByte(int stateByte) {
    switch (stateByte) {
      case 0:
        return RecordingState.idle;
      case 1:
        return RecordingState.armed;
      case 2:
        return RecordingState.recording;
      case 3:
        return RecordingState.finalizing;
      case 4:
        return RecordingState.error;
      default:
        return RecordingState.error;
    }
  }

  /// Get display name for this state
  String get displayName {
    switch (this) {
      case RecordingState.idle:
        return 'Idle';
      case RecordingState.armed:
        return 'Ready';
      case RecordingState.recording:
        return 'Recording';
      case RecordingState.finalizing:
        return 'Finalizing';
      case RecordingState.error:
        return 'Error';
    }
  }

  /// Get color for this state
  Color get color {
    switch (this) {
      case RecordingState.idle:
        return Colors.grey;
      case RecordingState.armed:
        return Colors.orange;
      case RecordingState.recording:
        return Colors.red;
      case RecordingState.finalizing:
        return Colors.blue;
      case RecordingState.error:
        return Colors.red;
    }
  }

  /// Whether recording is active (either armed, recording, or finalizing)
  bool get isActive {
    return this == RecordingState.armed ||
        this == RecordingState.recording ||
        this == RecordingState.finalizing;
  }
}

/// Research recording configuration (for starting a new recording)
class RecordingConfig {
  final int durationSeconds;
  final int signalMask;
  final int decimation;

  const RecordingConfig({
    required this.durationSeconds,
    required this.signalMask,
    this.decimation = 1,
  });

  /// Get list of signals from the mask
  List<ResearchSignalType> get signals => ResearchSignalTypeExtension.fromMask(signalMask);

  /// Calculate estimated total file size in bytes
  int get estimatedSizeBytes {
    int total = 0;
    for (final signal in signals) {
      total += signal.estimatedBytes(durationSeconds);
    }
    return total;
  }

  /// Get estimated size as formatted string
  String get estimatedSizeFormatted {
    final bytes = estimatedSizeBytes;
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Get duration as formatted string (MM:SS)
  String get durationFormatted {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Create command packet for configure command (0x70)
  List<int> toCommandPacket() {
    final packet = <int>[];
    packet.addAll(hPi4Global.REC_CONFIGURE);
    // Duration as uint16 little-endian
    packet.add(durationSeconds & 0xFF);
    packet.add((durationSeconds >> 8) & 0xFF);
    // Signal mask as uint8
    packet.add(signalMask & 0xFF);
    // Decimation as uint8
    packet.add(decimation & 0xFF);
    return packet;
  }

  /// Validate configuration
  bool get isValid {
    return durationSeconds > 0 &&
        durationSeconds <= 3600 &&
        signalMask > 0 &&
        decimation >= 1;
  }
}

/// Recording status response from device (0x73)
class RecordingStatus {
  final RecordingState state;
  final int elapsedSeconds;
  final int remainingSeconds;
  final int signalMask;

  const RecordingStatus({
    required this.state,
    required this.elapsedSeconds,
    required this.remainingSeconds,
    required this.signalMask,
  });

  /// Create from BLE response bytes
  /// Format: [0x06][0x73][state][elapsed_lo][elapsed_hi][remaining_lo][remaining_hi][signal_mask]
  factory RecordingStatus.fromBytes(List<int> bytes) {
    if (bytes.length < 8) {
      return const RecordingStatus(
        state: RecordingState.error,
        elapsedSeconds: 0,
        remainingSeconds: 0,
        signalMask: 0,
      );
    }

    final data = Uint8List.fromList(bytes).buffer.asByteData();
    return RecordingStatus(
      state: RecordingStateExtension.fromByte(data.getUint8(2)),
      elapsedSeconds: data.getUint16(3, Endian.little),
      remainingSeconds: data.getUint16(5, Endian.little),
      signalMask: data.getUint8(7),
    );
  }

  /// Get list of active signals
  List<ResearchSignalType> get signals => ResearchSignalTypeExtension.fromMask(signalMask);

  /// Get elapsed time as formatted string (MM:SS)
  String get elapsedFormatted {
    final minutes = elapsedSeconds ~/ 60;
    final seconds = elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get remaining time as formatted string (MM:SS)
  String get remainingFormatted {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get progress as percentage (0.0 to 1.0)
  double get progress {
    final total = elapsedSeconds + remainingSeconds;
    if (total == 0) return 0.0;
    return elapsedSeconds / total;
  }

  /// Whether a recording is currently active
  bool get isRecording => state.isActive;
}

/// Research recording session (stored on device)
class ResearchRecording {
  final int sessionTimestamp; // Unix timestamp (seconds)
  final int durationSeconds;
  final int signalMask;
  final int totalSizeBytes;
  final String? deviceMac;
  final RecordingSessionStatus status;

  const ResearchRecording({
    required this.sessionTimestamp,
    required this.durationSeconds,
    required this.signalMask,
    required this.totalSizeBytes,
    this.deviceMac,
    this.status = RecordingSessionStatus.complete,
  });

  /// Create from session list entry bytes
  /// Format: [0x05][timestamp:8][duration:2][signal_mask][total_size:4]
  factory ResearchRecording.fromSessionListBytes(List<int> bytes) {
    if (bytes.length < 16) {
      throw ArgumentError('Invalid session list entry: too short');
    }

    final data = Uint8List.fromList(bytes).buffer.asByteData();
    return ResearchRecording(
      sessionTimestamp: data.getInt64(1, Endian.little),
      durationSeconds: data.getUint16(9, Endian.little),
      signalMask: data.getUint8(11),
      totalSizeBytes: data.getUint32(12, Endian.little),
    );
  }

  /// Get start time as DateTime
  DateTime get startTime {
    return DateTime.fromMillisecondsSinceEpoch(
      sessionTimestamp * 1000,
      isUtc: false,
    );
  }

  /// Get end time as DateTime
  DateTime get endTime {
    return startTime.add(Duration(seconds: durationSeconds));
  }

  /// Get list of signals
  List<ResearchSignalType> get signals => ResearchSignalTypeExtension.fromMask(signalMask);

  /// Get device file path for this session
  String get devicePath => '/lfs/${hPi4Global.DEVICE_DIR_RESEARCH}/$sessionTimestamp';

  /// Get file path for a specific signal
  String signalFilePath(ResearchSignalType signal) => '$devicePath/${signal.fileName}';

  /// Get metadata file path
  String get metadataPath => '$devicePath/meta.bin';

  /// Get formatted start date/time
  String get formattedDateTime {
    final dt = startTime;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year} $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  /// Get formatted duration (e.g., "10 min 0 sec")
  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes > 0 && seconds > 0) {
      return '$minutes min $seconds sec';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$seconds sec';
    }
  }

  /// Get formatted size
  String get formattedSize {
    if (totalSizeBytes < 1024) {
      return '$totalSizeBytes B';
    } else if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Create delete command packet
  List<int> toDeleteCommandPacket() {
    final packet = <int>[];
    packet.addAll(hPi4Global.REC_DELETE_SESSION);
    // Timestamp as int64 little-endian
    final timestampBytes = ByteData(8);
    timestampBytes.setInt64(0, sessionTimestamp, Endian.little);
    packet.addAll(timestampBytes.buffer.asUint8List());
    return packet;
  }

  /// Copy with modified fields
  ResearchRecording copyWith({
    int? sessionTimestamp,
    int? durationSeconds,
    int? signalMask,
    int? totalSizeBytes,
    String? deviceMac,
    RecordingSessionStatus? status,
  }) {
    return ResearchRecording(
      sessionTimestamp: sessionTimestamp ?? this.sessionTimestamp,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      signalMask: signalMask ?? this.signalMask,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      deviceMac: deviceMac ?? this.deviceMac,
      status: status ?? this.status,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'sessionTimestamp': sessionTimestamp,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'durationSeconds': durationSeconds,
      'signalMask': signalMask,
      'signals': signals.map((s) => s.name).toList(),
      'totalSizeBytes': totalSizeBytes,
      'deviceMac': deviceMac,
      'status': status.name,
    };
  }
}

/// Recording session status
enum RecordingSessionStatus {
  complete,
  partial,
  error,
  pending, // Not yet downloaded
  downloading,
}

extension RecordingSessionStatusExtension on RecordingSessionStatus {
  String get displayName {
    switch (this) {
      case RecordingSessionStatus.complete:
        return 'Complete';
      case RecordingSessionStatus.partial:
        return 'Partial';
      case RecordingSessionStatus.error:
        return 'Error';
      case RecordingSessionStatus.pending:
        return 'On Device';
      case RecordingSessionStatus.downloading:
        return 'Downloading';
    }
  }

  Color get color {
    switch (this) {
      case RecordingSessionStatus.complete:
        return Colors.green;
      case RecordingSessionStatus.partial:
        return Colors.orange;
      case RecordingSessionStatus.error:
        return Colors.red;
      case RecordingSessionStatus.pending:
        return Colors.blue;
      case RecordingSessionStatus.downloading:
        return Colors.cyan;
    }
  }

  IconData get icon {
    switch (this) {
      case RecordingSessionStatus.complete:
        return Icons.check_circle;
      case RecordingSessionStatus.partial:
        return Icons.warning;
      case RecordingSessionStatus.error:
        return Icons.error;
      case RecordingSessionStatus.pending:
        return Icons.cloud_download;
      case RecordingSessionStatus.downloading:
        return Icons.downloading;
    }
  }
}

/// Individual signal file info
class SignalFileInfo {
  final ResearchSignalType signalType;
  final int sampleCount;
  final int sampleRateHz;
  final int fileSizeBytes;
  final String filePath;
  final DateTime? startTimestamp;

  const SignalFileInfo({
    required this.signalType,
    required this.sampleCount,
    required this.sampleRateHz,
    required this.fileSizeBytes,
    required this.filePath,
    this.startTimestamp,
  });

  /// Get duration in seconds
  double get durationSeconds => sampleCount / sampleRateHz;

  /// Get formatted duration
  String get formattedDuration {
    final totalSeconds = durationSeconds.toInt();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Get formatted file size
  String get formattedSize {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    } else if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Get formatted sample info
  String get formattedSampleInfo {
    final countStr = sampleCount >= 1000
        ? '${(sampleCount / 1000).toStringAsFixed(1)}k'
        : sampleCount.toString();
    return '$countStr samples @ $sampleRateHz Hz';
  }
}

/// Recording file header (32 bytes)
class RecordingFileHeader {
  final int magic;        // uint32 - 0x48504952 ("HPIR")
  final int version;      // uint8
  final int signalType;   // uint8
  final int sampleRateHz; // uint16
  final int startTimestamp; // int64 (Unix seconds)
  final int numSamples;   // uint32

  const RecordingFileHeader({
    required this.magic,
    required this.version,
    required this.signalType,
    required this.sampleRateHz,
    required this.startTimestamp,
    required this.numSamples,
  });

  /// Parse header from binary data
  factory RecordingFileHeader.fromBytes(Uint8List data) {
    if (data.length < hPi4Global.REC_FILE_HEADER_SIZE) {
      throw ArgumentError('Invalid header: too short (${data.length} bytes)');
    }

    final byteData = data.buffer.asByteData(data.offsetInBytes);
    final magic = byteData.getUint32(0, Endian.little);

    if (magic != hPi4Global.REC_FILE_MAGIC) {
      throw ArgumentError('Invalid magic number: 0x${magic.toRadixString(16)}');
    }

    return RecordingFileHeader(
      magic: magic,
      version: byteData.getUint8(4),
      signalType: byteData.getUint8(5),
      sampleRateHz: byteData.getUint16(6, Endian.little),
      startTimestamp: byteData.getInt64(8, Endian.little),
      numSamples: byteData.getUint32(16, Endian.little),
    );
  }

  /// Get signal type enum
  ResearchSignalType? get signal => ResearchSignalTypeExtension.fromHeaderType(signalType);

  /// Get start time as DateTime
  DateTime get startTime {
    return DateTime.fromMillisecondsSinceEpoch(
      startTimestamp * 1000,
      isUtc: false,
    );
  }

  /// Check if header is valid
  bool get isValid => magic == hPi4Global.REC_FILE_MAGIC && version == 1;
}
