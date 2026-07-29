// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'device_generation.dart';

/// The oldest watch firmware this app build can talk to at all.
///
/// v3.0.0 is the first firmware with the Healthy Store (HPI_HS, group `0x1000`),
/// and since the legacy `0x50`/`0x54` + `/lfs/tr*` path was removed this app has
/// no other way to pull data. So a pre-3.0 watch is not "degraded", it is mute —
/// which is why [FirmwareUpdateState.updateRequired] exists as a state distinct
/// from "an update happens to be available".
///
/// This is the watch-side mirror of `kMinimumAppVersion` in `lib/main.dart`.
const FirmwareVersion kMinimumFirmwareVersion = FirmwareVersion(3, 0, 0);

/// What the app should tell the user about the watch's firmware.
///
/// Five states, not a bool, for the same reason `MetricAvailability` has four:
/// collapsing any two of these puts a wrong instruction on screen. In
/// particular [unknown] is **not** [upToDate] — we have not checked, or could
/// not read a version, and nagging on a guess is worse than staying quiet.
enum FirmwareUpdateState {
  /// Nothing checked yet, no paired device, or a version we could not parse.
  /// Render nothing.
  unknown,

  /// The watch is on the newest published release (or newer — dev builds).
  upToDate,

  /// A newer release exists and this app build can install it.
  updateAvailable,

  /// The watch predates [kMinimumFirmwareVersion], so sync cannot work at all
  /// until it is updated. Distinct from [updateAvailable]: this one is not
  /// optional, and the UI says so.
  updateRequired,

  /// A newer firmware exists but it declares a minimum app version above this
  /// build. Installing it would leave the user with a watch this app cannot
  /// talk to, so the app must be updated *first*.
  appUpdateRequired,
}

/// Minimum-app-version tag parsed out of a GitHub release body.
///
/// Firmware releases and app releases ship on independent schedules, so a
/// firmware can land that needs protocol support only a newer app has. The
/// release notes carry that requirement as a tag, mirroring the store-listing
/// convention `upgrader` already uses for the app itself (see `_upgrader` in
/// `lib/main.dart`):
///
///     [Minimum app version: 3.1.0]
///     [:mav: 3.1.0]
///
/// **Absence means compatible.** Every firmware released before this tag
/// existed has no tag, and those are all installable by any 3.x app — so an
/// untagged release must never be treated as "unknown, block it".
FirmwareVersion? minAppVersionFromReleaseNotes(String? body) {
  if (body == null || body.isEmpty) return null;
  final match = _minAppVersionTag.firstMatch(body);
  if (match == null) return null;
  return FirmwareVersion.tryParse(match.group(1));
}

final RegExp _minAppVersionTag = RegExp(
  r'\[\s*(?::mav:|minimum\s+app\s+version\s*:)\s*([0-9]+(?:\.[0-9]+){0,2})\s*\]',
  caseSensitive: false,
);

/// Decide what to say about [currentFirmware] given the newest published
/// release. Pure — no network, no radio, no clock.
///
/// [currentFirmware] is the DIS firmware-revision string (`0x2A26`), e.g.
/// `"3.0.0+0"`. [appVersion] is this build's `pubspec` version.
///
/// Both unreadable inputs collapse to [FirmwareUpdateState.unknown] rather than
/// to a verdict: an unparseable version means we learned nothing, and a nag
/// based on nothing is a support ticket.
FirmwareUpdateState evaluateFirmwareState({
  required String? currentFirmware,
  required String? latestFirmware,
  String? releaseNotes,
  required String? appVersion,
}) {
  final current = FirmwareVersion.tryParse(currentFirmware);
  if (current == null) return FirmwareUpdateState.unknown;

  final tooOld = current < kMinimumFirmwareVersion;
  final latest = FirmwareVersion.tryParse(latestFirmware);

  // No readable release: we still know a pre-3.0 watch cannot sync, and that
  // verdict does not depend on what GitHub says.
  if (latest == null) {
    return tooOld ? FirmwareUpdateState.updateRequired : FirmwareUpdateState.unknown;
  }

  // Not newer — includes the equal case and a dev build ahead of the release.
  if (latest.compareTo(current) <= 0) {
    return tooOld ? FirmwareUpdateState.updateRequired : FirmwareUpdateState.upToDate;
  }

  // An update exists. Can *this* app install it? If the release demands a newer
  // app, offering the firmware would walk the user into a watch we can't talk
  // to — so the app update comes first, even when the watch is also too old.
  final minApp = minAppVersionFromReleaseNotes(releaseNotes);
  if (minApp != null) {
    final app = FirmwareVersion.tryParse(appVersion);
    // An unreadable *app* version is our own bug, not the user's — don't block
    // on it; the untagged-release rule (absence means compatible) applies.
    if (app != null && app < minApp) return FirmwareUpdateState.appUpdateRequired;
  }

  return tooOld
      ? FirmwareUpdateState.updateRequired
      : FirmwareUpdateState.updateAvailable;
}
