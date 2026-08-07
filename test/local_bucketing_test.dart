// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Coverage for the local-time bucketing that every trend chart stands on.
///
/// A beta user in IST reported a 10:02 reading charted as 09:30: `deriveTrends`
/// floored to the UTC hour while the screens render the bucket key in local
/// time, so in a half-hour zone every edge landed at :30. That fix shipped with
/// no tests at all, which is what let the *second* half of the bug — charts that
/// spread marks by index under a fixed 12A–11P axis — go unnoticed.
///
/// These assert invariants rather than fixed epoch values, so they hold in
/// whatever zone the runner happens to be in (CI is UTC; a dev machine is not).
/// Run under `TZ=Asia/Kolkata` to exercise the half-hour offset that started it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ui/charts/hpi_trend_charts.dart';
import 'package:move/utils/database_helper.dart';

DateTime _local(int ts) => DateTime.fromMillisecondsSinceEpoch(ts * 1000);

void main() {
  group('localHourStart', () {
    test('lands on a local wall-clock hour edge', () {
      // Every minute of a day, plus the DST transitions of both hemispheres.
      for (final day in [
        DateTime(2026, 8, 6),
        DateTime(2026, 3, 8), // US spring forward
        DateTime(2026, 11, 1), // US fall back
        DateTime(2026, 3, 29), // EU spring forward
        DateTime(2026, 10, 25), // EU fall back
      ]) {
        final base = day.millisecondsSinceEpoch ~/ 1000;
        for (var m = 0; m < 60 * 26; m++) {
          final b = _local(localHourStart(base + m * 60));
          expect(b.minute, 0, reason: 'bucket $b is not on the hour');
          expect(b.second, 0);
          expect(b.millisecond, 0);
        }
      }
    });

    test('contains its sample and never runs ahead of it', () {
      final base = DateTime(2026, 8, 6).millisecondsSinceEpoch ~/ 1000;
      for (var m = 0; m < 60 * 26; m++) {
        final ts = base + m * 60;
        final start = localHourStart(ts);
        expect(start, lessThanOrEqualTo(ts));
        // A bucket may be wider than an hour only where the zone steps back;
        // it must never be so narrow that the sample falls outside it.
        expect(ts - start, lessThan(2 * 3600));
      }
    });

    test('is non-decreasing, and never bucketes one local hour twice', () {
      for (final day in [
        DateTime(2026, 3, 8),
        DateTime(2026, 11, 1),
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
      ]) {
        final base = day.millisecondsSinceEpoch ~/ 1000;
        final seen = <int>[];
        var prev = 0;
        for (var m = 0; m < 60 * 26; m++) {
          final b = localHourStart(base + m * 60);
          expect(b, greaterThanOrEqualTo(prev), reason: 'went backwards on $day');
          prev = b;
          if (seen.isEmpty || seen.last != b) seen.add(b);
        }
        // Non-adjacent repeats would put two rows on one chart position.
        expect(seen.toSet().length, seen.length,
            reason: 'a bucket recurred on $day');
      }
    });

    test('a day yields one bucket per local wall-clock hour it has', () {
      // 24 normally; 23 on a spring-forward, because that hour never happened.
      // A fall-back day is 25 hours long but still yields 24 buckets: the two
      // repeated 01:00 hours share a wall-clock label, so they share a bucket —
      // that is what "the 1 AM bucket" means, and localHourStart says so.
      for (final day in [
        DateTime(2026, 8, 6),
        DateTime(2026, 3, 8),
        DateTime(2026, 11, 1),
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
      ]) {
        final start = day.millisecondsSinceEpoch ~/ 1000;
        final end = localDayEnd(day);
        final buckets = <int>{};
        for (var t = start; t < end; t += 60) {
          buckets.add(localHourStart(t));
        }
        final hours = (end - start) ~/ 3600;
        expect(buckets.length, hours < 24 ? hours : 24,
            reason: 'wrong bucket count for $day');
      }
    });

    test('is idempotent — flooring a bucket start returns it unchanged', () {
      final base = DateTime(2026, 8, 6).millisecondsSinceEpoch ~/ 1000;
      for (var h = 0; h < 26; h++) {
        final b = localHourStart(base + h * 3600);
        expect(localHourStart(b), b);
      }
    });
  });

  group('localDayStart / localDayEnd', () {
    test('lands on local midnight', () {
      final base = DateTime(2026, 8, 6).millisecondsSinceEpoch ~/ 1000;
      for (var h = 0; h < 24 * 5; h++) {
        final d = _local(localDayStart(base + h * 3600));
        expect(d.hour, 0);
        expect(d.minute, 0);
      }
    });

    test('a DST day is 23 or 25 hours, not a hardcoded 86400', () {
      for (final day in [
        DateTime(2026, 3, 8),
        DateTime(2026, 11, 1),
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
        DateTime(2026, 8, 6), // an ordinary day
      ]) {
        final span =
            localDayEnd(day) - day.millisecondsSinceEpoch ~/ 1000;
        expect(span, inInclusiveRange(22 * 3600, 26 * 3600));
        expect(_local(localDayEnd(day)).hour, 0,
            reason: 'the day must end at the next local midnight');
      }
    });

    test('every hour of a day folds into that day', () {
      final day = DateTime(2026, 8, 6);
      final start = day.millisecondsSinceEpoch ~/ 1000;
      final end = localDayEnd(day);
      for (var t = start; t < end; t += 3600) {
        expect(localDayStart(t), start);
      }
      expect(localDayStart(end), isNot(start));
    });
  });

  group('foldToLocalDays', () {
    List<Map<String, dynamic>> hour(DateTime t, num v) => [
          {
            'timestamp': t.millisecondsSinceEpoch ~/ 1000,
            'value_avg': v,
            'value_min': v - 2,
            'value_max': v + 2,
          }
        ];

    test('groups by local day, ascending, with true extremes', () {
      final rows = [
        ...hour(DateTime(2026, 8, 6, 23), 70), // late on the 6th
        ...hour(DateTime(2026, 8, 7, 0), 90), // just after local midnight
        ...hour(DateTime(2026, 8, 7, 9), 60),
      ];
      final out = foldToLocalDays(rows,
          maxKey: 'max', minKey: 'min', avgKey: 'avg', withCount: true);

      expect(out.length, 2);
      expect(_local(out[0]['day_start'] as int), DateTime(2026, 8, 6));
      expect(_local(out[1]['day_start'] as int), DateTime(2026, 8, 7));
      // The 00:00 reading belongs to the 7th. A UTC-day floor put it on the 6th
      // for anyone east of UTC — that was the Week/Month half of the report.
      expect(out[1]['data_points'], 2);
      expect(out[1]['max'], 92);
      expect(out[1]['min'], 58);
      expect(out[1]['avg'], 75);
    });

    test('drops a day with no central value rather than emitting nulls', () {
      final out = foldToLocalDays([
        {
          'timestamp': DateTime(2026, 8, 6, 9).millisecondsSinceEpoch ~/ 1000,
          'value_avg': null,
          'value_min': null,
          'value_max': null,
        }
      ], maxKey: 'max', minKey: 'min', avgKey: 'avg');
      expect(out, isEmpty);
    });

    test('falls back to the averages when extremes are absent', () {
      final out = foldToLocalDays([
        {
          'timestamp': DateTime(2026, 8, 6, 9).millisecondsSinceEpoch ~/ 1000,
          'value_avg': 71,
          'value_min': null,
          'value_max': null,
        }
      ], maxKey: 'max', minKey: 'min', avgKey: 'avg');
      expect(out.single['max'], 71);
      expect(out.single['min'], 71);
    });
  });

  group('TrendXAxis.localHours', () {
    test('pins each bucket to its own hour, not to its index', () {
      // The regression: three readings taken before dawn. Index spacing put
      // them at 1/6, 3/6 and 5/6 of a card labelled 12A-11P, so they read as
      // 4 AM, noon and 8 PM.
      final axis = TrendXAxis.localHours([
        DateTime(2026, 8, 6, 1),
        DateTime(2026, 8, 6, 2),
        DateTime(2026, 8, 6, 4),
      ]);
      expect(axis.slots, 24);
      expect(axis.positions, [1.5 / 24, 2.5 / 24, 4.5 / 24]);
      // All three sit in the first quarter of the axis, where they happened.
      expect(axis.positions.every((p) => p < 0.25), isTrue);
    });

    test('a lone reading sits at its hour, not in the middle of the card', () {
      // The original report, exactly: one SpO2 spot check just after 10 AM.
      final axis = TrendXAxis.localHours([DateTime(2026, 8, 6, 10, 2)]);
      expect(axis.positions.single, closeTo(10.5 / 24, 1e-9));
      expect(axis.positions.single, isNot(closeTo(0.5, 0.02)));
    });

    test('spans the full axis without ever leaving the plot', () {
      for (var h = 0; h < 24; h++) {
        final p = TrendXAxis.localHours([DateTime(2026, 8, 6, h)])
            .positions
            .single;
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });

    test('at() falls back to index spacing when positions run short', () {
      const axis = TrendXAxis(positions: [], slots: 24);
      expect(axis.at(0, 2), 0.25);
      expect(axis.at(1, 2), 0.75);
    });
  });
}
