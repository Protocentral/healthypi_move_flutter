// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/device_generation.dart';
import 'package:move/ble/dfu_plan.dart';
import 'package:move/ble/firmware_updater.dart';

FirmwareImage _img(int slot) => FirmwareImage(
      imageIndex: slot,
      name: slot == 0 ? 'app.signed.bin' : 'ipc_radio.bin',
      load: () async => Uint8List(4),
    );

/// The standard v3 package: app core (0) + radio (1).
List<FirmwareImage> get _fullPackage => [_img(0), _img(1)];

void main() {
  group('FirmwareVersion.tryParse', () {
    test('parses the DIS string the firmware actually emits', () {
      // CONFIG_BT_DIS_FW_REV_STR derives from app/VERSION → "3.0.0+0".
      expect(FirmwareVersion.tryParse('3.0.0+0'), const FirmwareVersion(3, 0, 0));
    });

    test('tolerates a leading v and a pre-release suffix', () {
      expect(FirmwareVersion.tryParse('v1.5.1'), const FirmwareVersion(1, 5, 1));
      expect(FirmwareVersion.tryParse('3.1.0-rc1'), const FirmwareVersion(3, 1, 0));
    });

    test('fills in missing components', () {
      expect(FirmwareVersion.tryParse('2.1'), const FirmwareVersion(2, 1, 0));
      expect(FirmwareVersion.tryParse('2'), const FirmwareVersion(2, 0, 0));
    });

    test('returns null for anything that is not a version', () {
      expect(FirmwareVersion.tryParse(null), isNull);
      expect(FirmwareVersion.tryParse(''), isNull);
      expect(FirmwareVersion.tryParse('   '), isNull);
      expect(FirmwareVersion.tryParse('Unknown'), isNull);
      expect(FirmwareVersion.tryParse('1.x.0'), isNull);
    });

    test('orders versions', () {
      expect(const FirmwareVersion(3, 0, 0) >= const FirmwareVersion(2, 9, 9), isTrue);
      expect(const FirmwareVersion(1, 5, 1) < const FirmwareVersion(1, 5, 2), isTrue);
    });
  });

  group('generationFromFwRevision', () {
    test('v3 and later are current', () {
      expect(generationFromFwRevision('3.0.0+0'), DeviceGeneration.v3);
      expect(generationFromFwRevision('4.2.1'), DeviceGeneration.v3);
    });

    test('2.x is G2', () {
      expect(generationFromFwRevision('2.0.0'), DeviceGeneration.g2);
      expect(generationFromFwRevision('2.4.7'), DeviceGeneration.g2);
    });

    test('only v1.5.0 and v1.5.1 are G1.5', () {
      expect(generationFromFwRevision('1.5.0'), DeviceGeneration.g1_5);
      expect(generationFromFwRevision('1.5.1'), DeviceGeneration.g1_5);
      // The enlarged-primary-slot builds stop there; 1.5.2+ and 1.9.0 are normal.
      expect(generationFromFwRevision('1.5.2'), DeviceGeneration.g1);
      expect(generationFromFwRevision('1.9.0'), DeviceGeneration.g1);
    });

    test('other 1.x and 0.x are G1', () {
      expect(generationFromFwRevision('1.2.2'), DeviceGeneration.g1);
      expect(generationFromFwRevision('0.9.0'), DeviceGeneration.g1);
    });

    test('an unreadable version is unknown, and unknown counts as pre-v3', () {
      expect(generationFromFwRevision(null), DeviceGeneration.unknown);
      expect(generationFromFwRevision('Unknown'), DeviceGeneration.unknown);
      // The safety property the whole flow rests on.
      expect(DeviceGeneration.unknown.isPreV3, isTrue);
    });

    test('only v3 is not pre-v3', () {
      for (final g in DeviceGeneration.values) {
        expect(g.isPreV3, g != DeviceGeneration.v3, reason: '$g');
      }
    });
  });

  group('planDfu — first leg', () {
    test('v3 device takes the whole package in one session', () {
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: _fullPackage,
      );

      expect(plan.isRunnable, isTrue);
      expect(plan.stage, DfuStage.single);
      expect(plan.images.map((i) => i.imageIndex), [0, 1]);
      expect(plan.stageTwoFollows, isFalse);
    });

    for (final gen in [
      DeviceGeneration.g1,
      DeviceGeneration.g1_5,
      DeviceGeneration.g2,
      DeviceGeneration.unknown,
    ]) {
      test('${gen.name} gets the app core alone, with stage two owed', () {
        final plan = planDfu(
          generation: gen,
          slots: const DeviceSlots.unknown(),
          packageImages: _fullPackage,
        );

        expect(plan.stage, DfuStage.appCoreFirst);
        // The property that matters most: the radio image is never in the first
        // leg for pre-v3 firmware.
        expect(plan.images.map((i) => i.imageIndex), [kAppCoreImageIndex]);
        expect(plan.stageTwoFollows, isTrue);
      });
    }

    test('a 3-image legacy package still yields app-core-only on old firmware',
        () {
      final plan = planDfu(
        generation: DeviceGeneration.g1,
        slots: const DeviceSlots.unknown(),
        packageImages: [_img(0), _img(1), _img(2)],
      );
      expect(plan.images.map((i) => i.imageIndex), [0]);
      expect(plan.stageTwoFollows, isTrue);
    });

    test('no stage two is owed when the package is app-core only', () {
      final plan = planDfu(
        generation: DeviceGeneration.g2,
        slots: const DeviceSlots.unknown(),
        packageImages: [_img(0)],
      );
      expect(plan.stage, DfuStage.appCoreFirst);
      expect(plan.stageTwoFollows, isFalse);
    });

    test('a package with no app-core image is refused for old firmware', () {
      final plan = planDfu(
        generation: DeviceGeneration.g1,
        slots: const DeviceSlots.unknown(),
        packageImages: [_img(1)],
      );
      expect(plan.isBlocked, isTrue);
      expect(plan.images, isEmpty);
    });

    test('an empty package is refused', () {
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: const [],
      );
      expect(plan.isBlocked, isTrue);
    });
  });

  group('planDfu — what the device may receive', () {
    test('an unlisted slot does not block the update — it is only a note', () {
      // The bug this replaces: a healthy v3 watch reports slot 0 alone (MCUmgr
      // omits slots whose header it can't read, and the nRF5340 net-core
      // primary is in network-core flash), and the whole update was refused.
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0}),
        packageImages: _fullPackage,
      );

      expect(plan.isRunnable, isTrue);
      expect(plan.images.map((i) => i.imageIndex), [0, 1]);
      expect(plan.notes, isNotEmpty);
      expect(plan.describe(), contains('sending to 1 anyway'));
    });

    test('refuses an image the generation genuinely has no slot for', () {
      // A 3-image G1-era package aimed at a v3 watch: image 2 does not exist in
      // a 2-image build, and that IS positive evidence.
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: [_img(0), _img(1), _img(2)],
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.blockedReason, contains('image 2'));
      expect(plan.images, isEmpty);
    });

    test('an unknown generation makes no claim, so nothing is refused', () {
      final plan = planDfu(
        generation: DeviceGeneration.unknown,
        slots: const DeviceSlots.unknown(),
        packageImages: [_img(0), _img(2)],
      );
      // Pre-v3 policy still reduces it to the app core alone.
      expect(plan.isRunnable, isTrue);
      expect(plan.images.map((i) => i.imageIndex), [0]);
    });

    test('an unknown slot map does not block planning', () {
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.unknown(),
        packageImages: _fullPackage,
      );
      expect(plan.isRunnable, isTrue);
      expect(plan.images, hasLength(2));
      expect(plan.notes, isEmpty);
    });

    test('old firmware reporting only slot 0 still gets its app-core update',
        () {
      final plan = planDfu(
        generation: DeviceGeneration.g2,
        slots: const DeviceSlots.known({0}),
        packageImages: _fullPackage,
      );
      expect(plan.isRunnable, isTrue);
      expect(plan.images.map((i) => i.imageIndex), [0]);
      expect(plan.stageTwoFollows, isTrue);
      expect(plan.notes, isEmpty); // slot 0 was listed; nothing to warn about
    });
  });

  group('planDfu — second leg', () {
    test('sends the radio image once the watch reports v3', () {
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: _fullPackage,
        resumingStageTwo: true,
      );

      expect(plan.stage, DfuStage.netCore);
      expect(plan.images.map((i) => i.imageIndex), [1]);
      expect(plan.stageTwoFollows, isFalse);
    });

    test('refuses if the watch is still on its old firmware', () {
      // The reboot did not take: never push a v3 radio image at an old bootloader.
      final plan = planDfu(
        generation: DeviceGeneration.g2,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: _fullPackage,
        resumingStageTwo: true,
      );

      expect(plan.isBlocked, isTrue);
      expect(plan.blockedReason, contains('main firmware update first'));
      expect(plan.images, isEmpty);
    });

    test('refuses when the package holds no radio image', () {
      final plan = planDfu(
        generation: DeviceGeneration.v3,
        slots: const DeviceSlots.known({0, 1}),
        packageImages: [_img(0)],
        resumingStageTwo: true,
      );
      expect(plan.isBlocked, isTrue);
    });
  });

  group('DfuPlan.describe', () {
    test('names the stage and slots for the log', () {
      final plan = planDfu(
        generation: DeviceGeneration.g1_5,
        slots: const DeviceSlots.unknown(),
        packageImages: _fullPackage,
      );
      expect(plan.describe(), contains('appCoreFirst'));
      expect(plan.describe(), contains('image(s) 0'));
      expect(plan.describe(), contains('radio update follows'));
    });

    test('a blocked plan describes why', () {
      const plan = DfuPlan.blocked('nope');
      expect(plan.describe(), contains('blocked'));
      expect(plan.describe(), contains('nope'));
    });
  });
}
