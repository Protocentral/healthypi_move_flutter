// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:move/ui/components/hpi_synthetic_banner.dart';
import 'package:move/utils/healthy_store_sync_manager.dart';

/// The developer **synthetic preview** charts firmware-fabricated samples so a
/// bench Ultralight — where every sample is synthetic, because both producers
/// are down behind a dead I²C4 — can be validated at all.
///
/// Charting fabricated data is only defensible because of four guarantees, and
/// this file exists to keep them true:
///
///  1. off by default, so production never charts a fabricated number;
///  2. never silent — the banner shows on every route while it is on;
///  3. never dismissable, so it cannot be cleared and forgotten;
///  4. never persisted, and reachable only from the hidden developer screen.
void main() {
  final flag = HealthyStoreSyncManager.instance.syntheticIncluded;

  tearDown(() {
    flag.value = false;
    HpiSyntheticBanner.liveSyntheticSource.value = null;
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          home: HpiSyntheticBanner(child: Text('charts')),
        ),
      );

  testWidgets('off by default — production never charts fabricated samples',
      (tester) async {
    // Read before anything in this file mutates it: the notifier is constructed
    // false, which is what makes the preview reset on every app launch.
    expect(HealthyStoreSyncManager.instance.syntheticIncluded.value, isFalse);

    await pump(tester);
    expect(find.textContaining('SYNTHETIC'), findsNothing);
    expect(find.text('charts'), findsOneWidget);
  });

  testWidgets('banner shows, and says what it means, while preview is on',
      (tester) async {
    flag.value = true;
    await pump(tester);

    expect(find.textContaining('SYNTHETIC'), findsOneWidget);
    // "fabricated" and "not measurements" are the load-bearing words — a bare
    // "test mode" label would not tell a user the numbers are invented.
    expect(find.textContaining('fabricated'), findsOneWidget);
    expect(find.textContaining('not measurements'), findsOneWidget);
    // The content is still reachable; the banner wraps rather than replaces.
    expect(find.text('charts'), findsOneWidget);
  });

  testWidgets('banner has no dismiss affordance', (tester) async {
    flag.value = true;
    await pump(tester);

    // A closable warning is one that gets closed and forgotten while every
    // number on screen stays fabricated.
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a SYNTHETIC live frame raises the same banner, naming the device',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('SYNTHETIC'), findsNothing);

    // Set by the Ultralight Live screen on a DBLK frame with the SYNTHETIC flag.
    HpiSyntheticBanner.liveSyntheticSource.value = 'MoveUL A1B2C3';
    await tester.pump();
    expect(find.textContaining('SYNTHETIC'), findsOneWidget);
    expect(find.textContaining('MoveUL A1B2C3'), findsOneWidget);
    expect(find.textContaining('fabricated'), findsOneWidget);
    expect(find.textContaining('not measurements'), findsOneWidget);
    expect(find.text('charts'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);

    HpiSyntheticBanner.liveSyntheticSource.value = null;
    await tester.pump();
    expect(find.textContaining('SYNTHETIC'), findsNothing);
  });

  group('containment', () {
    test('the preview is never persisted', () {
      // In-memory only is what guarantees the reset-on-restart contract. If this
      // ever reaches SharedPreferences, a device left in preview mode overnight
      // comes back still charting invented numbers.
      final src = File('lib/utils/healthy_store_sync_manager.dart')
          .readAsStringSync();
      final body = src.substring(src.indexOf('Future<int?> setSyntheticPreview'),
          src.indexOf('Future<void> ensureRealDataOnly'));
      expect(body.contains('SharedPreferences'), isFalse,
          reason: 'setSyntheticPreview must not persist the flag');
      expect(body.contains('prefs'), isFalse,
          reason: 'setSyntheticPreview must not persist the flag');
    });

    test('only the developer screen can turn it on', () {
      // It is not a Setting and must never become one: the developer screen is
      // itself behind a 7-tap easter egg, which is the whole containment story.
      final callers = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (src.contains('setSyntheticPreview') &&
            !f.path.endsWith('healthy_store_sync_manager.dart')) {
          callers.add(f.path);
        }
      }
      expect(callers, ['lib/screens/scr_developer.dart'],
          reason: 'synthetic preview must stay behind the developer screen');
    });

    test('startup always re-derives real-only trends', () {
      // The persisted stamp is the only durable trace of the preview, and it
      // exists precisely so ensureRealDataOnly can undo the preview's rebuild
      // even if the app was killed while it was on.
      final src = File('lib/utils/healthy_store_sync_manager.dart')
          .readAsStringSync();
      expect(src.contains('rebuildAllTrends(device, includeSynthetic: false)'),
          isTrue,
          reason: 'ensureRealDataOnly must rebuild without synthetic samples');
    });
  });
}
