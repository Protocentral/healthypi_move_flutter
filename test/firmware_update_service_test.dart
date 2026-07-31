// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:move/utils/firmware_update_service.dart';

/// Regression coverage for the version comparison that gates the firmware
/// update button. The watch reports its version over BLE DIS with MCUboot build
/// metadata (`"3.0.2+0"`); GitHub releases are plain (`"3.0.2"`). The `+0` must
/// be stripped before comparing, or every equal-version release looks like an
/// upgrade — nagging the user forever and then failing the re-flash (MCUboot
/// rejects an image that is not strictly higher than the running one).
void main() {
  group('FirmwareUpdateService.isUpdateAvailable', () {
    test('equal version with MCUboot +0 metadata is NOT an update (the bug)', () {
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.2+0', '3.0.2'), isFalse);
    });

    test('genuine upgrade is offered', () {
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.1+0', '3.0.2'), isTrue);
    });

    test('original 2.2.0 -> 3.0.1 upgrade still works', () {
      expect(FirmwareUpdateService.isUpdateAvailable('2.2.0+0', '3.0.1'), isTrue);
    });

    test('device ahead of release (dev build) is not an update', () {
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.2+0', '3.0.1'), isFalse);
    });

    test("'v' prefix is tolerated", () {
      expect(FirmwareUpdateService.isUpdateAvailable('v3.0.2', '3.0.2'), isFalse);
      expect(FirmwareUpdateService.isUpdateAvailable('v3.0.1', '3.0.2'), isTrue);
    });

    test('pre-release suffix is stripped', () {
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.2-rc1', '3.0.2'), isFalse);
    });

    test('minor and major bumps are detected', () {
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.9+0', '3.1.0'), isTrue);
      expect(FirmwareUpdateService.isUpdateAvailable('3.9.9+0', '4.0.0'), isTrue);
    });

    test('unparseable input does not nag', () {
      expect(FirmwareUpdateService.isUpdateAvailable('Unknown', '3.0.2'), isFalse);
      expect(FirmwareUpdateService.isUpdateAvailable('3.0.2+0', ''), isFalse);
    });
  });
}
