// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

// Progress / result types shared by the Healthy Store sync UI.
// Formerly next to the legacy custom-protocol sync manager; that path is gone.

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
