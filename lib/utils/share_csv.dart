// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Shares a CSV after its caller has finished writing it.
Future<ShareResult> shareCsv(
  BuildContext context,
  File file, {
  required String text,
}) {
  // iOS interprets the popover anchor in the source view's logical coordinates.
  final view = View.of(context);
  final size = view.physicalSize / view.devicePixelRatio;
  if (!size.isFinite || size.isEmpty) {
    throw StateError('No visible view to present the CSV share sheet.');
  }

  // Anchor to the current view even if the initiating control has scrolled away.
  final origin = Rect.fromCenter(
    center: size.center(Offset.zero),
    width: math.min(1.0, size.width / 2),
    height: math.min(1.0, size.height / 2),
  );
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      text: text,
      sharePositionOrigin: origin,
    ),
  );
}
