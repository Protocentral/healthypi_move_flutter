// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers that a watch has had its **app core** updated but still owes the
/// **radio (net core)** image — the second leg of the two-stage migration off
/// pre-v3 firmware.
///
/// Without this, closing the app between the two legs strands the watch in a
/// state the DFU screen reads as "up to date": its firmware revision now
/// matches the latest release, so the ordinary version comparison finds nothing
/// to do and never offers the radio update. The watch works like that (app core
/// v3 on the old radio firmware is exactly what leg one delivers), but it is not
/// the finished migration.
///
/// Scoped per device MAC, and tagged with the package version the first leg
/// installed so a newer release supersedes a stale pending flag.
class DfuStageState {
  static const _keyMac = 'dfu_pending_radio_mac';
  static const _keyVersion = 'dfu_pending_radio_version';

  /// Stand-in "version" for a package the user supplied by hand. A manual zip
  /// has no release version to match against, and the app cannot fetch it again
  /// — so the second leg has to ask for the same file back rather than
  /// downloading it. Distinguishing this from a real version keeps the
  /// superseded-by-a-newer-release check from silently dropping the flag.
  static const String manualPackageTag = '__manual__';

  /// Record that [mac] still needs the radio image from package [version].
  static Future<void> setRadioUpdatePending({
    required String mac,
    required String version,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMac, mac);
    await prefs.setString(_keyVersion, version);
  }

  /// The package version whose radio image [mac] still owes, or `null` when
  /// nothing is pending for that device.
  static Future<String?> pendingRadioVersion(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyMac) != mac) return null;
    return prefs.getString(_keyVersion);
  }

  /// Clear the flag — the radio image landed, or the user abandoned the flow
  /// and a newer package has taken over.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMac);
    await prefs.remove(_keyVersion);
  }
}
