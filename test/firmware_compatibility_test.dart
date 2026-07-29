// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/device_generation.dart';
import 'package:move/ble/firmware_compatibility.dart';

void main() {
  group('minAppVersionFromReleaseNotes', () {
    test('reads the long-form tag', () {
      expect(minAppVersionFromReleaseNotes('Notes.\n[Minimum app version: 3.1.0]\n'),
          const FirmwareVersion(3, 1, 0));
    });

    test('reads the short :mav: tag and is case-insensitive', () {
      expect(minAppVersionFromReleaseNotes('[:MAV: 4.2.1]'),
          const FirmwareVersion(4, 2, 1));
      expect(minAppVersionFromReleaseNotes('[minimum APP version:3.2]'),
          const FirmwareVersion(3, 2, 0));
    });

    test('absent tag means compatible, not unknown', () {
      // Every firmware released before this convention existed has no tag, and
      // all of them are installable. Treating absence as "unknown, block" would
      // brick the update path for the entire back catalogue.
      expect(minAppVersionFromReleaseNotes('Fixes the HRV window.'), isNull);
      expect(minAppVersionFromReleaseNotes(''), isNull);
      expect(minAppVersionFromReleaseNotes(null), isNull);
    });

    test('ignores prose that merely mentions a version', () {
      expect(
          minAppVersionFromReleaseNotes('Works best with app 3.1.0 or newer.'),
          isNull);
    });
  });

  group('evaluateFirmwareState', () {
    const app = '3.0.1';

    test('unreadable current version yields unknown, never a nag', () {
      for (final current in [null, '', 'Unknown']) {
        expect(
          evaluateFirmwareState(
              currentFirmware: current, latestFirmware: '3.1.0', appVersion: app),
          FirmwareUpdateState.unknown,
          reason: 'current="$current"',
        );
      }
    });

    test('newer release on a supported watch is an available update', () {
      expect(
        evaluateFirmwareState(
            currentFirmware: '3.0.0+0', latestFirmware: '3.1.0', appVersion: app),
        FirmwareUpdateState.updateAvailable,
      );
    });

    test('equal versions are up to date', () {
      expect(
        evaluateFirmwareState(
            currentFirmware: '3.1.0+0', latestFirmware: '3.1.0', appVersion: app),
        FirmwareUpdateState.upToDate,
      );
    });

    test('a dev build ahead of the release is up to date, not downgraded', () {
      expect(
        evaluateFirmwareState(
            currentFirmware: '3.2.0', latestFirmware: '3.1.0', appVersion: app),
        FirmwareUpdateState.upToDate,
      );
    });

    test('pre-3.0 firmware is required, not merely available', () {
      // A 2.x watch cannot answer HPI_HS at all, so this is not an optional
      // "there is a newer one" — sync is dead until it is updated.
      expect(
        evaluateFirmwareState(
            currentFirmware: '2.1.0', latestFirmware: '3.1.0', appVersion: app),
        FirmwareUpdateState.updateRequired,
      );
    });

    test('pre-3.0 firmware is still required with no reachable release', () {
      expect(
        evaluateFirmwareState(
            currentFirmware: '2.1.0', latestFirmware: null, appVersion: app),
        FirmwareUpdateState.updateRequired,
      );
    });

    test('supported watch with no reachable release stays unknown', () {
      expect(
        evaluateFirmwareState(
            currentFirmware: '3.0.0', latestFirmware: null, appVersion: app),
        FirmwareUpdateState.unknown,
      );
    });

    test('a release demanding a newer app blocks the firmware offer', () {
      expect(
        evaluateFirmwareState(
          currentFirmware: '3.0.0',
          latestFirmware: '3.2.0',
          releaseNotes: '[Minimum app version: 3.5.0]',
          appVersion: app,
        ),
        FirmwareUpdateState.appUpdateRequired,
      );
    });

    test('app update wins over firmware-required — the app is fixed first', () {
      expect(
        evaluateFirmwareState(
          currentFirmware: '2.0.0',
          latestFirmware: '3.2.0',
          releaseNotes: '[:mav: 3.5.0]',
          appVersion: app,
        ),
        FirmwareUpdateState.appUpdateRequired,
      );
    });

    test('a satisfied minimum does not block', () {
      expect(
        evaluateFirmwareState(
          currentFirmware: '3.0.0',
          latestFirmware: '3.2.0',
          releaseNotes: '[Minimum app version: 3.0.1]',
          appVersion: app,
        ),
        FirmwareUpdateState.updateAvailable,
      );
    });

    test('an unreadable app version does not block the install', () {
      // That would be our own bug, and stranding the user on old firmware over
      // it is worse than trusting the untagged-release rule.
      expect(
        evaluateFirmwareState(
          currentFirmware: '3.0.0',
          latestFirmware: '3.2.0',
          releaseNotes: '[Minimum app version: 3.5.0]',
          appVersion: null,
        ),
        FirmwareUpdateState.updateAvailable,
      );
    });

    test('the minimum is only consulted when an update is actually newer', () {
      expect(
        evaluateFirmwareState(
          currentFirmware: '3.2.0',
          latestFirmware: '3.2.0',
          releaseNotes: '[Minimum app version: 9.0.0]',
          appVersion: app,
        ),
        FirmwareUpdateState.upToDate,
      );
    });
  });
}
