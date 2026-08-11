// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// The Flutter-side presentation of a [DeviceProfile].
///
/// Kept out of `device_profile.dart` so that file can stay Flutter-free and
/// unit-testable with no radio and no widget binding — the same split
/// `lib/globals.dart` maintains. Everything here is glyphs and words; nothing
/// here decides a capability.
library;

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'device_profile.dart';

extension DeviceProfileUi on DeviceProfile {
  /// The product's glyph.
  ///
  /// The two products must be distinguishable **at 15 px**, which is the size
  /// this appears at in the Home footer — the app's primary "which device am I
  /// looking at?" surface. The screenless band form factor is the recognisable
  /// difference, so it gets the tracker glyph rather than a watch face.
  IconData get icon => switch (model) {
        DeviceModel.moveNext => Symbols.watch,
        DeviceModel.moveUltralight => Symbols.fitness_tracker,
        DeviceModel.unknown => Symbols.watch,
      };

  /// The glyph for "nothing paired".
  IconData get emptyIcon => Symbols.watch_off;

  /// How the device is named in the Home footer, alongside the sync status.
  ///
  /// A user-set nickname wins — it is what they chose to call it — with the
  /// product name kept alongside so a support screenshot still identifies the
  /// hardware. Falls back to the product name alone.
  String footerLabel(String? nickname) {
    final n = nickname?.trim();
    if (n == null || n.isEmpty) return productName;
    return '$n · $productName';
  }
}
