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

  /// True when the payload is a series of **intervals**, not fixed-rate samples.
  ///
  /// An HRV record ([HsSignal.hrvRr]) is R-R intervals in milliseconds. Beats are
  /// irregularly spaced by definition, so `sampleRate` is not a real Hz and any
  /// `i / sampleRate` timebase is fiction. Elapsed time is the running sum of the
  /// values themselves, which needs the payload — see [beats] for what the header
  /// alone can honestly say.
  bool get isIntervalSeries => kind == HsRecordingKind.hrv;

  /// Beat count for an [isIntervalSeries] record — one interval per sample.
  int get beats => nSamples;

  /// Best-effort duration from sample count and rate; 0 if unknown.
  ///
  /// **0 for an [isIntervalSeries] record**, deliberately. The header carries a
  /// `sampleRate` for HRV too, but it does not mean Hz there, and dividing by it
  /// produced a confident, wrong duration on every screen that asked. Returning
  /// 0 makes callers render "—" until they compute the real elapsed time from
  /// the decoded intervals.
  int get durationSeconds {
    if (isIntervalSeries) return 0;
    final sr = sampleRate <= 0 ? 0 : sampleRate;
    if (sr == 0 || nSamples <= 0) return 0;
    return (nSamples / sr).round().clamp(0, 24 * 3600);
  }

  /// Filter bucket for the library chips (ECG / PPG / GSR / IMU / other).
  ///
  /// Keyed off [HsSignal], which is **1-based** — the firmware's own enum. These
  /// used to be raw 0-based literals, so every session landed one bucket off
  /// (ECG→GSR, GSR→PPG) and `ecg`/`imu` were unreachable.
  HsRecordingKind get kind {
    switch (signal) {
      case HsSignal.ecg:
        return HsRecordingKind.ecg;
      case HsSignal.bioz:
        return HsRecordingKind.gsr;
      case HsSignal.ppgWrist:
      case HsSignal.ppgFinger:
        return HsRecordingKind.ppg;
      case HsSignal.hrvRr:
        return HsRecordingKind.hrv;
      case HsSignal.acc:
        return HsRecordingKind.imu;
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
