// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:test/test.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';

/// Firmware P3 (continuous HRV + HRV-derived stress), handoff §6.
///
/// The rule under test is the one the firmware team called "the single most
/// important line in this section": `stress_hrv_v == false` means NO SCORE YET,
/// not zero stress. A 0 rendered there is a number the user would believe and
/// that means nothing.
void main() {
  group('HRV stress validity', () {
    test('a valid score is surfaced', () {
      final s = HsSummary.fromMap({'stress_hrv': 62, 'stress_hrv_v': true});
      expect(s.stressHrv, 62);
      expect(s.isBuildingHrvBaseline, isFalse);
    });

    test('invalid means no score — NOT zero — even when a value is present', () {
      // The firmware still sends a number in stress_hrv; it is meaningless until
      // the baseline exists. Surfacing it (or coercing it to 0) is the bug.
      final s = HsSummary.fromMap({'stress_hrv': 0, 'stress_hrv_v': false});
      expect(s.stressHrv, isNull);
      expect(s.isBuildingHrvBaseline, isTrue,
          reason: 'the UI must say "building your baseline", not render a 0');
    });

    test('invalid with a non-zero value is still withheld', () {
      final s = HsSummary.fromMap({'stress_hrv': 47, 'stress_hrv_v': false});
      expect(s.stressHrv, isNull);
    });

    test('pre-P3 firmware (key absent) is unsupported, not baselining', () {
      final s = HsSummary.fromMap({'hr_avg': 71});
      expect(s.stressHrv, isNull);
      expect(s.isBuildingHrvBaseline, isFalse,
          reason: 'an old watch is not "still learning you" — it never will');
    });

    test('tolerates 0/1 in place of a CBOR bool', () {
      // The firmware's CBOR shapes are not fully pinned; parse defensively.
      expect(HsSummary.fromMap({'stress_hrv': 55, 'stress_hrv_v': 1}).stressHrv,
          55);
      expect(HsSummary.fromMap({'stress_hrv': 55, 'stress_hrv_v': 0}).stressHrv,
          isNull);
    });
  });

  group('HRV scaling', () {
    test('rmssd and its baseline are ms x10 on the wire', () {
      final s = HsSummary.fromMap({'rmssd': 423, 'rmssd_base': 380});
      expect(s.rmssdMs, 42.3);
      expect(s.rmssdBaselineMs, 38.0);
    });

    test('absent HRV fields do not fabricate a zero', () {
      final s = HsSummary.fromMap({});
      expect(s.rmssdMs, isNull);
      expect(s.rmssdBaselineMs, isNull);
      expect(s.hrvWindows, isNull);
    });

    test('hrv_wins is surfaced as the window count behind the baseline', () {
      expect(HsSummary.fromMap({'hrv_wins': 20}).hrvWindows, 20);
    });
  });
}
