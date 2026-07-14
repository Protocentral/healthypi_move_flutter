// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';

/// One episodic raw-signal session from HPI_HS `RECORDS list`, plus local
/// download state for the Recordings library UI.
class HsRecording {
  const HsRecording({
    required this.header,
    this.localPath,
    this.crcOk,
    this.acked = false,
  });

  final HsRecordHeader header;

  /// Absolute path of the payload on the phone, if downloaded.
  final String? localPath;

  /// Null until a download completes; false means stored but CRC failed.
  final bool? crcOk;

  /// True after a successful `recordsAck` (device may have dropped it).
  final bool acked;

  int get id => header.id;
  int get startTs => header.startTs;
  int get signal => header.signal;
  int get sampleRate => header.sampleRate;
  int get nSamples => header.nSamples;
  int get byteLen => header.byteLen;
  bool get isPartial => header.isPartial;
  String get signalName => header.signalName;

  bool get onPhone => localPath != null && localPath!.isNotEmpty;

  DateTime get startTime => header.startTime.toLocal();

  /// Best-effort duration from sample count and rate; 0 if unknown.
  int get durationSeconds {
    final sr = sampleRate <= 0 ? 0 : sampleRate;
    if (sr == 0 || nSamples <= 0) return 0;
    return (nSamples / sr).round().clamp(0, 24 * 3600);
  }

  /// Filter bucket for the library chips (PPG / GSR / IMU / other).
  HsRecordingKind get kind {
    switch (signal) {
      case 1:
        return HsRecordingKind.gsr;
      case 2:
      case 3:
        return HsRecordingKind.ppg;
      case 5:
        return HsRecordingKind.imu;
      case 0:
        return HsRecordingKind.ecg;
      case 4:
        return HsRecordingKind.hrv;
      default:
        return HsRecordingKind.other;
    }
  }

  String get kindLabel {
    switch (kind) {
      case HsRecordingKind.ppg:
        return 'PPG';
      case HsRecordingKind.gsr:
        return 'GSR';
      case HsRecordingKind.imu:
        return 'IMU';
      case HsRecordingKind.ecg:
        return 'ECG';
      case HsRecordingKind.hrv:
        return 'HRV';
      case HsRecordingKind.other:
        return signalName;
    }
  }

  HsRecording copyWith({
    HsRecordHeader? header,
    String? localPath,
    bool? crcOk,
    bool? acked,
    bool clearLocal = false,
  }) {
    return HsRecording(
      header: header ?? this.header,
      localPath: clearLocal ? null : (localPath ?? this.localPath),
      crcOk: crcOk ?? this.crcOk,
      acked: acked ?? this.acked,
    );
  }
}

enum HsRecordingKind { ppg, gsr, imu, ecg, hrv, other }

/// Outcome of an on-demand `RECORDS get` download.
class HsRecordingDownloadResult {
  const HsRecordingDownloadResult({
    required this.recording,
    required this.data,
    required this.crcOk,
    required this.acked,
  });

  final HsRecording recording;
  final List<int> data;
  final bool crcOk;
  final bool acked;
}
