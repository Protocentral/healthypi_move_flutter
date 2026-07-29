// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ble/firmware_compatibility.dart';
import 'device_manager.dart';
import 'firmware_update_service.dart';

/// What the last firmware check concluded. Immutable; published through
/// [FirmwareUpdateChecker.status].
class FirmwareUpdateStatus {
  const FirmwareUpdateStatus({
    this.state = FirmwareUpdateState.unknown,
    this.currentVersion,
    this.latestVersion,
    this.checkedAt,
  });

  final FirmwareUpdateState state;

  /// DIS firmware revision last seen on the paired watch, or null if we have
  /// never had a connection long enough to read one.
  final String? currentVersion;

  /// Newest published release, or null if we have never reached GitHub.
  final String? latestVersion;

  final DateTime? checkedAt;

  /// True when the Device screen should draw attention to the firmware row.
  bool get needsAttention =>
      state == FirmwareUpdateState.updateAvailable ||
      state == FirmwareUpdateState.updateRequired ||
      state == FirmwareUpdateState.appUpdateRequired;

  /// True when the user should be sent to the DFU screen. Deliberately false
  /// for [FirmwareUpdateState.appUpdateRequired] — that one is fixed in the app
  /// store, and opening DFU there would offer an install we must not perform.
  bool get canInstall =>
      state == FirmwareUpdateState.updateAvailable ||
      state == FirmwareUpdateState.updateRequired;

  @override
  String toString() => 'FirmwareUpdateStatus($state, current: $currentVersion, '
      'latest: $latestVersion)';
}

/// Checks — at app start and on resume — whether the paired watch is behind the
/// newest published firmware, so the Device screen can say so *before* the user
/// thinks to go looking. Until this existed the only place that ever asked was
/// `ScrDFUNew.initState`, i.e. only after the user had already navigated to the
/// firmware screen on a hunch.
///
/// **This never touches the radio.** The current version comes from the DIS
/// revision cached on the paired [DeviceInfo] by whatever last held a
/// connection (sync, DFU); the latest comes from the release cache. Connecting
/// just to check would burn battery and would have to contend for the SMP lock
/// against a sync or, far worse, an in-flight DFU.
///
/// A null current version therefore means "no connection since pairing", which
/// resolves itself after the first sync — and until then the state is
/// [FirmwareUpdateState.unknown] and the UI stays quiet.
class FirmwareUpdateChecker {
  FirmwareUpdateChecker._();
  static final FirmwareUpdateChecker instance = FirmwareUpdateChecker._();

  /// Latest verdict. Screens listen and rebuild; it starts at `unknown`, which
  /// renders as nothing at all.
  static final ValueNotifier<FirmwareUpdateStatus> status =
      ValueNotifier<FirmwareUpdateStatus>(const FirmwareUpdateStatus());

  /// How long a fetched release stays good for a background check. Long enough
  /// that a user who opens the app ten times a day costs ~2 GitHub calls, short
  /// enough that a release published this morning is offered today.
  static const Duration cacheTtl = Duration(hours: 6);

  bool _running = false;

  /// Re-evaluate. [force] bypasses the release cache (user-initiated check).
  ///
  /// Never throws: a failed check leaves the previous verdict in place rather
  /// than flapping the UI back to `unknown` because the phone was offline.
  Future<void> refresh({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      final device = await DeviceManager.getPairedDevice();
      if (device == null) {
        status.value = const FirmwareUpdateStatus();
        return;
      }

      final release =
          await FirmwareUpdateService.getLatestRelease(cacheTtl: force ? null : cacheTtl);
      final appVersion = (await PackageInfo.fromPlatform()).version;

      final state = evaluateFirmwareState(
        currentFirmware: device.firmwareVersion,
        latestFirmware: release?.version,
        releaseNotes: release?.body,
        appVersion: appVersion,
      );

      status.value = FirmwareUpdateStatus(
        state: state,
        currentVersion: device.firmwareVersion,
        latestVersion: release?.version,
        checkedAt: DateTime.now(),
      );
      debugPrint('[FW-Check] ${status.value}');
    } catch (e) {
      debugPrint('[FW-Check] check failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Record the DIS firmware revision read off a live link, and re-evaluate if
  /// it changed.
  ///
  /// Call this from anywhere that already has a connection and has read DIS —
  /// sync and DFU both do. It is what keeps the radio-free check above supplied
  /// with a current version.
  static Future<void> recordFirmwareVersion(String? version) async {
    if (version == null || version.isEmpty || version == 'Unknown') return;
    final device = await DeviceManager.getPairedDevice();
    // Writing unconditionally would bump `pairingRevision` on every sync, and
    // every screen listening to it reloads from SQLite when it does.
    if (device == null || device.firmwareVersion == version) return;
    await DeviceManager.updateFirmwareVersion(version);
    await instance.refresh();
  }
}
