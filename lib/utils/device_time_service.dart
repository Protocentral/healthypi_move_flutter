// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

/// Sets the watch RTC via the **standard MCUmgr OS datetime command**
/// ([OsMgmt.setDatetime] — group 0, id 4).
///
/// This is not the retired custom CMD opcode `0x41`. Current firmware only
/// exposes SMP for management; datetime is the Zephyr/mcumgr stock path already
/// implemented in `package:mcumgr_dart`.
///
/// The RTC holds **UTC**, and the wall-clock offset is sent separately via
/// [HpiHs.setTimezone] (see [setDeviceTime]) — so a DST change only re-sends the
/// offset and never rewrites the clock.
///
/// Call on every sync after the SMP session is up and before pulling samples —
/// without a correct RTC, HPI_HS sample timestamps are wrong.
class DeviceTimeService {
  DeviceTimeService._();

  /// Push the phone's current clock to the device with
  /// [OsMgmt.setDatetime] (MCUmgr OS group, datetime write), and — when the
  /// device speaks HPI_HS ([hs] non-null) — its current UTC offset via
  /// [HpiHs.setTimezone].
  ///
  /// [OsMgmt.setDatetime] already sends the instant as UTC, so the RTC lands on
  /// UTC; the offset (seconds east of UTC, DST-aware) tells the watch how to
  /// render local wall-clock time. Sending it every sync carries the live DST
  /// state with no RTC rewrite.
  ///
  /// The offset is sent **before** the datetime so the display is already
  /// correct the instant the clock lands; order is not functionally required.
  ///
  /// Returns `true` when the RTC was set. A failed timezone write is logged but
  /// does not fail the result — sample sync can still proceed on a correct RTC.
  /// Never throws.
  static Future<bool> setDeviceTime(OsMgmt os, {HpiHs? hs}) async {
    final when = DateTime.now();
    final offsetSec = when.timeZoneOffset.inSeconds;
    debugPrint(
      '[DeviceTime] OsMgmt.setDatetime(${when.toUtc().toIso8601String()}) '
      'local=$when tz=${when.timeZoneName} '
      'offset=${when.timeZoneOffset.inMinutes}min (${offsetSec}s)',
    );

    if (hs != null) {
      try {
        await hs.setTimezone(offsetSec);
        debugPrint('[DeviceTime] HpiHs.setTimezone(${offsetSec}s) completed');
      } catch (e, st) {
        // Non-fatal: an old RTC offset only skews the watch's local display,
        // not the UTC-based sample timestamps the sync relies on.
        debugPrint('[DeviceTime] HpiHs.setTimezone failed: $e');
        debugPrint('$st');
      }
    }

    try {
      await os.setDatetime(when);
      debugPrint('[DeviceTime] OsMgmt.setDatetime completed');
      return true;
    } catch (e, st) {
      debugPrint('[DeviceTime] OsMgmt.setDatetime failed: $e');
      debugPrint('$st');
      return false;
    }
  }
}
