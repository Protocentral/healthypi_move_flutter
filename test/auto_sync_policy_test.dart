// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';
import 'package:move/utils/auto_sync_controller.dart';

/// Every guard satisfied — each test flips exactly one thing.
AutoSyncSkip _evaluate({
  bool enabled = true,
  bool hasPairedDevice = true,
  bool isSyncing = false,
  bool isSmpBusy = false,
  bool isStreaming = false,
  DateTime? lastAttempt,
  DateTime? now,
}) {
  final t = now ?? DateTime(2026, 7, 29, 12, 0);
  return AutoSyncPolicy.evaluate(
    enabled: enabled,
    hasPairedDevice: hasPairedDevice,
    isSyncing: isSyncing,
    isSmpBusy: isSmpBusy,
    isStreaming: isStreaming,
    lastAttempt: lastAttempt,
    now: t,
  );
}

void main() {
  group('AutoSyncPolicy', () {
    test('runs when nothing is in the way and nothing ran before', () {
      expect(_evaluate(), AutoSyncSkip.none);
    });

    test('respects the settings toggle', () {
      expect(_evaluate(enabled: false), AutoSyncSkip.disabled);
    });

    test('does nothing without a paired watch', () {
      expect(_evaluate(hasPairedDevice: false), AutoSyncSkip.noDevice);
    });

    test('never doubles up on a sync already running', () {
      expect(_evaluate(isSyncing: true), AutoSyncSkip.alreadySyncing);
    });

    test('stands down while another SMP flow holds the wire', () {
      // The one that matters: a DFU. Sync, records and DFU share a single SMP
      // characteristic, and an automatic sync landing mid-upload corrupts the
      // image. `acquireSmp` would throw here anyway — this skips before we get
      // far enough to fight for it.
      expect(_evaluate(isSmpBusy: true), AutoSyncSkip.smpBusy);
    });

    test('stands down while the Live screen is streaming', () {
      // One radio, two logical modes that must not overlap on the wire. The SMP
      // lock does not cover this — it only arbitrates SMP against SMP.
      expect(_evaluate(isStreaming: true), AutoSyncSkip.streaming);
    });

    test('throttles a second pass inside the interval', () {
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(
        _evaluate(now: now, lastAttempt: now.subtract(const Duration(minutes: 5))),
        AutoSyncSkip.tooSoon,
      );
    });

    test('runs again once the interval has elapsed', () {
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(
        _evaluate(
            now: now,
            lastAttempt: now.subtract(AutoSyncPolicy.minInterval +
                const Duration(seconds: 1))),
        AutoSyncSkip.none,
      );
    });

    test('a backwards clock does not lock auto-sync out', () {
      // Timezone fix or NTP correction: the stored stamp lands in the future.
      // Waiting it out would strand auto-sync until real time caught up.
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(
        _evaluate(now: now, lastAttempt: now.add(const Duration(days: 2))),
        AutoSyncSkip.none,
      );
    });

    test('the wire guards outrank the throttle', () {
      // Order matters for the log line: "skipped (smpBusy)" during a DFU is a
      // very different diagnosis from "skipped (tooSoon)".
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(
        _evaluate(
            now: now,
            isSmpBusy: true,
            lastAttempt: now.subtract(const Duration(minutes: 1))),
        AutoSyncSkip.smpBusy,
      );
    });

    test('a custom interval overrides the default', () {
      final now = DateTime(2026, 7, 29, 12, 0);
      expect(
        AutoSyncPolicy.evaluate(
          enabled: true,
          hasPairedDevice: true,
          isSyncing: false,
          isSmpBusy: false,
          isStreaming: false,
          lastAttempt: now.subtract(const Duration(minutes: 5)),
          now: now,
          interval: const Duration(minutes: 1),
        ),
        AutoSyncSkip.none,
      );
    });
  });
}
