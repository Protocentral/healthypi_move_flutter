// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:move/device/device_capabilities.dart';
import 'package:move/device/device_profile.dart';
import 'package:move/globals.dart';
import 'package:move/models/device_info.dart';

void main() {
  group('DeviceProfile.forHelloDev', () {
    test('resolves each product from its firmware model string', () {
      expect(DeviceProfile.forHelloDev('healthypi-move').model,
          DeviceModel.moveNext);
      expect(DeviceProfile.forHelloDev('healthypi-move-ultralight').model,
          DeviceModel.moveUltralight);
    });

    test('matches exactly, never by prefix', () {
      // A prefix match would classify the Ultralight as a Move and put a
      // blood-pressure screen on a band with no BP sensor. This is the single
      // most important assertion in this file.
      final ul = DeviceProfile.forHelloDev(DeviceProfile.devUltralight);
      expect(ul.model, DeviceModel.moveUltralight);
      expect(ul.hasBloodPressure, isFalse);
    });

    test('tolerates case and whitespace from the wire', () {
      expect(DeviceProfile.forHelloDev('  HealthyPi-Move  ').model,
          DeviceModel.moveNext);
    });

    test('an unrecognised device is unknown, not a guess', () {
      for (final dev in ['healthypi-move-2', 'something-else', '', '   ', null]) {
        expect(DeviceProfile.forHelloDev(dev).model, DeviceModel.unknown,
            reason: 'dev=$dev');
      }
    });

    test('unknown gets the conservative intersection', () {
      const p = DeviceProfile.unknown;
      expect(p.hasBloodPressure, isFalse);
      expect(p.hasEcg, isFalse);
      expect(p.hasGsrEda, isFalse);
      expect(p.hasFingerSensor, isFalse);
      // It still syncs and still charts: the sample stream and the TYPES
      // registry describe themselves, so a device we cannot name is not a
      // device whose data we must refuse.
      expect(p.homeSignals, contains(hPi4Global.PREFIX_SPO2));
    });
  });

  group('DeviceProfile.forStoredModel', () {
    test('null means Move, not unknown', () {
      // Every pairing made before DeviceInfo.model existed is a Move. An app
      // update must not change what a current user sees before their next sync.
      expect(DeviceProfile.forStoredModel(null).model, DeviceModel.moveNext);
      expect(DeviceProfile.forStoredModel('').model, DeviceModel.moveNext);
      expect(DeviceProfile.forStoredModel('  ').model, DeviceModel.moveNext);
    });

    test('a stored string resolves like a HELLO string', () {
      expect(DeviceProfile.forStoredModel('healthypi-move-ultralight').model,
          DeviceModel.moveUltralight);
    });

    test('an unrecognised stored value is unknown', () {
      expect(DeviceProfile.forStoredModel('mystery').model,
          DeviceModel.unknown);
    });

    test('storedModel round-trips through forStoredModel', () {
      for (final p in [DeviceProfile.moveNext, DeviceProfile.moveUltralight]) {
        expect(DeviceProfile.forStoredModel(p.storedModel).model, p.model);
      }
    });
  });

  group('DeviceProfile.forAdvertisedName', () {
    test('recognises both advertised name shapes', () {
      // Firmware builds "MoveUL XXYYZZ" from the hardware id.
      expect(DeviceProfile.forAdvertisedName('MoveUL A1B2C3').model,
          DeviceModel.moveUltralight);
      expect(DeviceProfile.forAdvertisedName('HealthyPi Move').model,
          DeviceModel.moveNext);
      expect(DeviceProfile.forAdvertisedName('healthypi move 1234').model,
          DeviceModel.moveNext);
    });

    test('an unknown name yields unknown, never a default product', () {
      expect(DeviceProfile.forAdvertisedName('Nordic_DFU').model,
          DeviceModel.unknown);
      expect(DeviceProfile.forAdvertisedName(null).model, DeviceModel.unknown);
    });
  });

  group('product capabilities', () {
    test('the Move has the sensors the Ultralight does not', () {
      const move = DeviceProfile.moveNext;
      expect(move.hasBloodPressure, isTrue);
      expect(move.hasEcg, isTrue);
      expect(move.hasGsrEda, isTrue);
      expect(move.hasFingerSensor, isTrue);
    });

    test('the Ultralight has no electrodes and no finger sensor', () {
      // The Nerve board carries an AS7058 PPG AFE, a BMI323 IMU and an AS6221
      // temperature sensor. Nothing else reaches skin.
      const ul = DeviceProfile.moveUltralight;
      expect(ul.hasBloodPressure, isFalse);
      expect(ul.hasEcg, isFalse);
      expect(ul.hasGsrEda, isFalse);
      expect(ul.hasFingerSensor, isFalse);
    });

    test('the Ultralight keeps stress — it is HRV-derived from wrist PPG', () {
      expect(DeviceProfile.moveUltralight.homeSignals,
          contains(hPi4Global.PREFIX_STRESS));
    });
  });

  group('home row composition', () {
    test('the Move shows blood pressure and EDA', () {
      expect(DeviceProfile.moveNext.homeSignals,
          containsAll([kSignalBloodPressure, kSignalEda]));
    });

    test('the Ultralight has no BP or EDA row at all', () {
      // Absent, not dim. A permanently dim BP row on a band with no BP sensor
      // implies a measurement that cannot be made — and BP is the app's one
      // regulated surface.
      final rows = DeviceProfile.moveUltralight.homeSignals;
      expect(rows, isNot(contains(kSignalBloodPressure)));
      expect(rows, isNot(contains(kSignalEda)));
    });

    test('a profile without BP hardware never lists the BP row', () {
      for (final p in [DeviceProfile.moveUltralight, DeviceProfile.unknown]) {
        expect(p.hasBloodPressure, isFalse);
        expect(p.homeSignals, isNot(contains(kSignalBloodPressure)),
            reason: '${p.productName} lists a BP row without BP hardware');
      }
    });

    test('every grid signal is also a list signal', () {
      // The grid is a subset view of the same data; a tile with no row behind it
      // would open a detail screen the list cannot reach.
      for (final p in [
        DeviceProfile.moveNext,
        DeviceProfile.moveUltralight,
        DeviceProfile.unknown
      ]) {
        expect(p.homeSignals, containsAll(p.gridSignals),
            reason: p.productName);
      }
    });

    test('the grid never contains blood pressure', () {
      // The BP tile needs a supporting sentence (relative wording, never a
      // category) that the 2x2 grid has no room for.
      for (final p in [DeviceProfile.moveNext, DeviceProfile.moveUltralight]) {
        expect(p.gridSignals, isNot(contains(kSignalBloodPressure)));
      }
    });
  });

  group('copy', () {
    test('the device noun matches the product', () {
      expect(DeviceProfile.moveNext.deviceNoun, 'watch');
      // "Measure on watch" is an instruction an Ultralight owner cannot follow:
      // the band has no screen and no buttons.
      expect(DeviceProfile.moveUltralight.deviceNoun, 'band');
    });
  });

  group('DeviceInfo.model persistence', () {
    DeviceInfo sample({String? model}) => DeviceInfo(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          deviceName: 'HealthyPi Move',
          firstPaired: DateTime.utc(2026, 1, 1),
          model: model,
        );

    test('round-trips through JSON', () {
      final info = sample(model: DeviceProfile.devUltralight);
      final back = DeviceInfo.fromJson(info.toJson());
      expect(back.model, DeviceProfile.devUltralight);
    });

    test('a record written before the field existed reads as null', () {
      final legacy = sample().toJson()..remove('model');
      expect(DeviceInfo.fromJson(legacy).model, isNull);
      // …and therefore resolves to the Move profile, not unknown.
      expect(DeviceProfile.forStoredModel(DeviceInfo.fromJson(legacy).model).model,
          DeviceModel.moveNext);
    });

    test('copyWith carries the model forward', () {
      final info = sample(model: DeviceProfile.devUltralight);
      expect(info.copyWith(nickname: 'Band').model, DeviceProfile.devUltralight);
    });
  });

  group('DeviceCapabilities', () {
    test('a success is yes', () {
      expect(DeviceCapabilities.fold(Tri.unknown, ok: true), Tri.yes);
    });

    test('only ENOTSUP demotes to no', () {
      expect(
          DeviceCapabilities.fold(Tri.unknown,
              ok: false, rc: kMgmtErrNotSupported),
          Tri.no);
    });

    test('a timeout is not a verdict — the previous value survives', () {
      // Reporting a dropped link as "not supported" is how a flaky connection
      // gets mistaken for old firmware.
      expect(DeviceCapabilities.fold(Tri.yes, ok: false, rc: null), Tri.yes);
      expect(DeviceCapabilities.fold(Tri.unknown, ok: false, rc: null),
          Tri.unknown);
    });

    test('an unrelated error does not demote either', () {
      expect(DeviceCapabilities.fold(Tri.yes, ok: false, rc: 1), Tri.yes);
    });

    test('isNo is true only for a definite no', () {
      expect(Tri.no.isNo, isTrue);
      expect(Tri.unknown.isNo, isFalse);
      expect(Tri.yes.isNo, isFalse);
    });

    test('a cache entry is invalidated by a firmware change', () {
      const caps = DeviceCapabilities(records: Tri.no, firmwareVersion: '1.0.0');
      // The Ultralight will grow RECORDS; a stale `no` must not hide a feature
      // the user just updated to get.
      expect(caps.invalidatedBy('1.1.0'), isTrue);
      expect(caps.invalidatedBy('1.0.0'), isFalse);
      // Not knowing one side is not a reason to throw the cache away.
      expect(caps.invalidatedBy(null), isFalse);
      expect(const DeviceCapabilities(records: Tri.no).invalidatedBy('1.0.0'),
          isFalse);
    });

    test('JSON round-trips, and a corrupt entry degrades to unknown', () {
      const caps = DeviceCapabilities(
          summary: Tri.no,
          records: Tri.yes,
          setTimezone: Tri.unknown,
          firmwareVersion: '3.0.1');
      final back = DeviceCapabilities.fromJson(caps.toJson());
      expect(back.summary, Tri.no);
      expect(back.records, Tri.yes);
      expect(back.firmwareVersion, '3.0.1');

      // One bad row must never sink the whole entry.
      final bad = DeviceCapabilities.fromJson(
          {'summary': 42, 'records': 'nonsense'});
      expect(bad.summary, Tri.unknown);
      expect(bad.records, Tri.unknown);
    });
  });
}
