import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/hpi_colors.dart';
import '../../utils/health_store_sync_manager.dart';

/// A persistent strip shown across the whole app whenever the developer opt-in
/// "Include synthetic data" is on.
///
/// The firmware can fabricate samples on-device (`CONFIG_HPI_HS_SYNTH`) so that
/// trends, the 7-day skin-temp baseline and sync-at-scale can be tested without
/// wearing the watch for a week. Those samples land in the same store as real
/// ones, interleaved with them, flagged only by `quality & (1<<6)`. The whole
/// point of that bit — per the firmware handoff — is that fabricated data can
/// never be *silently* mistaken for a measurement.
///
/// Filtering it out of the derived trends satisfies that. Charting it behind a
/// developer toggle with no label does not: every number on every screen would
/// then be invented, and nothing on screen would say so. This is that label.
///
/// Mounted from `MaterialApp.builder`, so it covers pushed routes and dialogs
/// too, not just the shell's four tabs.
class HpiSyntheticBanner extends StatelessWidget {
  const HpiSyntheticBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HealthStoreSyncManager.instance.syntheticIncluded,
      builder: (context, on, _) {
        if (!on) return child;
        return Column(
          children: [
            Material(
              color: HpiColors.error,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Symbols.science,
                          size: 16, color: HpiColors.onHr),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'SYNTHETIC DATA — these are fabricated test samples, '
                          'not measurements',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: HpiColors.onHr,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
