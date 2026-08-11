// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// What a paired device's firmware answers *right now*, as opposed to what its
/// hardware could ever do (`DeviceProfile`).
///
/// Imports no Flutter library and does no I/O — pure, and unit-testable with no
/// radio.
///
/// ## Why this is three-valued
///
/// `HsProbeResult` already encodes the distinction that matters, for the whole
/// HPI_HS group: `supported: false, reachable: true` is a **verdict** (the
/// device answered and said no), while `reachable: false` is a **timeout** —
/// you learned nothing. Reporting the second as the first is how a flaky link
/// gets mistaken for old firmware.
///
/// The same applies per command. The Ultralight answers `ENOTSUP` for `SUMMARY`
/// and `RECORDS` today because their MCUmgr handlers are deliberately `NULL`;
/// its firmware comment is explicit that this "is what a client should branch
/// on; it is not the same as an empty result". Both will grow producers. So a
/// `no` must be attributable to an answer, and must not outlive the firmware
/// that gave it.
library;

/// A three-valued answer: the device said yes, the device said no, or we do not
/// know yet.
enum Tri {
  /// The command answered successfully at least once.
  yes,

  /// The device replied `ENOTSUP` — a verdict about this firmware.
  no,

  /// Never probed, or every attempt timed out. **Not** a verdict.
  unknown;

  /// True only for a definite `no`. Use this to hide a feature; never use
  /// `!isYes`, which would also hide it on a dropped link.
  bool get isNo => this == Tri.no;

  bool get isYes => this == Tri.yes;
}

/// MCUmgr's `MGMT_ERR_ENOTSUP`. A handler registered as `NULL` in a group's
/// table produces this, which is exactly how the Ultralight reports `SUMMARY`
/// and `RECORDS` as absent.
const int kMgmtErrNotSupported = 8;

/// Per-command capabilities observed on a device, keyed in storage by the
/// HPI_HS `uid`.
class DeviceCapabilities {
  const DeviceCapabilities({
    this.summary = Tri.unknown,
    this.records = Tri.unknown,
    this.setTimezone = Tri.unknown,
    this.firmwareVersion,
  });

  /// HPI_HS `SUMMARY` (cmd 3) — the device's own rolling baselines and the
  /// `stress_hrv_v` validity flag.
  ///
  /// When this is [Tri.no], HRV stress has no validity flag to read, so it
  /// renders an honest zero-state. It must **never** render a 0: a 0 there reads
  /// as "calm", and is a number the user would believe.
  final Tri summary;

  /// HPI_HS `RECORDS` (cmd 4) — the episodic raw-signal tier. [Tri.no] hides the
  /// Recordings entry point entirely rather than showing a permanently empty
  /// list.
  final Tri records;

  /// HPI_HS `SET_TZ` (cmd 7). A [Tri.no] means the device has no wall-clock
  /// offset — its UTC sample timestamps are still usable, but anything the
  /// device renders locally will be wrong.
  final Tri setTimezone;

  /// The firmware revision these observations were made against.
  ///
  /// Load-bearing: a cached `no` is only valid for the firmware that produced
  /// it. The Ultralight *will* grow `SUMMARY` and `RECORDS`, and a stale `no`
  /// would hide a feature the user just updated to get. See [invalidatedBy].
  final String? firmwareVersion;

  static const DeviceCapabilities unknownAll = DeviceCapabilities();

  /// Whether a cache entry must be discarded because the device's firmware
  /// changed under it.
  ///
  /// Unknown-to-known is not a change worth discarding over (we simply had not
  /// read DIS yet), but a *different* known version is.
  bool invalidatedBy(String? currentFirmware) {
    if (firmwareVersion == null || currentFirmware == null) return false;
    return firmwareVersion != currentFirmware;
  }

  /// Fold one command's outcome in.
  ///
  /// Pass [rc] from the MCUmgr response, or leave it null for a transport
  /// failure. Only [kMgmtErrNotSupported] demotes to [Tri.no]; every other
  /// error, and every timeout, leaves the previous value alone — an unrelated
  /// failure is not evidence that a command is missing.
  static Tri fold(Tri previous, {required bool ok, int? rc}) {
    if (ok) return Tri.yes;
    if (rc == kMgmtErrNotSupported) return Tri.no;
    return previous;
  }

  DeviceCapabilities copyWith({
    Tri? summary,
    Tri? records,
    Tri? setTimezone,
    String? firmwareVersion,
  }) =>
      DeviceCapabilities(
        summary: summary ?? this.summary,
        records: records ?? this.records,
        setTimezone: setTimezone ?? this.setTimezone,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      );

  Map<String, Object?> toJson() => {
        'summary': summary.name,
        'records': records.name,
        'setTimezone': setTimezone.name,
        'firmwareVersion': firmwareVersion,
      };

  /// Tolerant of anything: an unreadable field falls back to [Tri.unknown],
  /// which only costs a re-probe. Throwing here would break a sync over a
  /// cache entry.
  factory DeviceCapabilities.fromJson(Map<String, Object?> json) {
    Tri read(String key) {
      final v = json[key];
      if (v is! String) return Tri.unknown;
      return Tri.values.firstWhere((t) => t.name == v,
          orElse: () => Tri.unknown);
    }

    return DeviceCapabilities(
      summary: read('summary'),
      records: read('records'),
      setTimezone: read('setTimezone'),
      firmwareVersion: json['firmwareVersion'] as String?,
    );
  }

  @override
  String toString() => 'DeviceCapabilities(summary: ${summary.name}, '
      'records: ${records.name}, setTz: ${setTimezone.name}, '
      'fw: $firmwareVersion)';
}
