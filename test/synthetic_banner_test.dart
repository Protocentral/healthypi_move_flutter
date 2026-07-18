// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:move/ui/components/hpi_synthetic_banner.dart';
import 'package:move/utils/healthy_store_sync_manager.dart';

/// After QA, synthetic samples are never charted. The banner only appears if
/// [HealthyStoreSyncManager.syntheticIncluded] is forced true (it is not in
/// production). Production path: always hidden.
void main() {
  final flag = HealthyStoreSyncManager.instance.syntheticIncluded;

  tearDown(() => flag.value = false);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          home: HpiSyntheticBanner(child: Text('charts')),
        ),
      );

  testWidgets('hidden in production (synthetic never charted)', (tester) async {
    flag.value = false;
    await pump(tester);

    expect(find.textContaining('SYNTHETIC'), findsNothing);
    expect(find.text('charts'), findsOneWidget);
  });

  testWidgets('legacy banner still works if flag forced (defensive)',
      (tester) async {
    flag.value = true;
    await pump(tester);

    expect(find.textContaining('SYNTHETIC'), findsOneWidget);
    expect(find.text('charts'), findsOneWidget);
  });
}
