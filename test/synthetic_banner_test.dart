import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:move/ui/components/hpi_synthetic_banner.dart';
import 'package:move/utils/health_store_sync_manager.dart';

/// The SYNTHETIC quality bit exists so fabricated samples can never be silently
/// mistaken for measurements. When the developer opt-in charts them anyway, the
/// banner is the only thing on screen saying so — so it is worth a test.
void main() {
  final flag = HealthStoreSyncManager.instance.syntheticIncluded;

  tearDown(() => flag.value = false);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(
          home: HpiSyntheticBanner(child: Text('charts')),
        ),
      );

  testWidgets('hidden in production (opt-in off)', (tester) async {
    flag.value = false;
    await pump(tester);

    expect(find.textContaining('SYNTHETIC'), findsNothing);
    expect(find.text('charts'), findsOneWidget);
  });

  testWidgets('shown whenever synthetic data is being charted', (tester) async {
    flag.value = true;
    await pump(tester);

    expect(find.textContaining('SYNTHETIC'), findsOneWidget);
    expect(find.text('charts'), findsOneWidget);
  });

  testWidgets('appears the moment the opt-in is flipped, without a rebuild',
      (tester) async {
    flag.value = false;
    await pump(tester);
    expect(find.textContaining('SYNTHETIC'), findsNothing);

    flag.value = true;
    await tester.pump();

    expect(find.textContaining('SYNTHETIC'), findsOneWidget);
  });
}
