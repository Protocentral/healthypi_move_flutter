// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'device_generation.dart';
import 'device_slots.dart';
import 'firmware_updater.dart';

export 'device_slots.dart';

/// Which leg of the migration a plan represents.
enum DfuStage {
  /// Everything the package holds, in one session (v3 → v3).
  single,

  /// App core only, onto pre-v3 firmware. The radio follows after a reboot.
  appCoreFirst,

  /// The radio image, after the watch came back running v3.
  netCore,
}

/// The outcome of planning one update: what to send now, and what follows.
///
/// A plan is either runnable ([images] non-empty, [blockedReason] null) or a
/// refusal ([blockedReason] set). There is deliberately no third "nothing to do
/// but that's fine" state — an empty plan always means something is wrong, and
/// reporting success without transferring anything is the worst possible
/// outcome for an OTA flow.
class DfuPlan {
  const DfuPlan._({
    required this.images,
    required this.stage,
    required this.stageTwoFollows,
    this.notes = const [],
  }) : blockedReason = null;

  const DfuPlan.blocked(String reason)
      : images = const [],
        stage = DfuStage.single,
        stageTwoFollows = false,
        notes = const [],
        blockedReason = reason;

  /// Images to upload now, in order.
  final List<FirmwareImage> images;

  final DfuStage stage;

  /// True when a second session (the radio image) is still owed after this one
  /// completes and the watch reboots.
  final bool stageTwoFollows;

  /// Non-null when the update must not start; the text is user-facing.
  final String? blockedReason;

  /// Diagnostics worth logging but not worth stopping for — e.g. sending to a
  /// slot the device did not list (which is normal for the nRF5340 net core).
  final List<String> notes;

  bool get isBlocked => blockedReason != null;
  bool get isRunnable => !isBlocked && images.isNotEmpty;

  /// One line for logs: what is about to be sent and why.
  String describe() {
    if (isBlocked) return 'DFU plan: blocked — $blockedReason';
    final slots = images.map((i) => i.imageIndex).join(', ');
    return 'DFU plan: ${stage.name}, image(s) $slots'
        '${stageTwoFollows ? ", radio update follows after reboot" : ""}'
        '${notes.isEmpty ? "" : " [${notes.join("; ")}]"}';
  }
}

/// The MCUboot image index of the application core. Identical in every fielded
/// generation, which is what makes a single app-core binary serve the fleet.
const int kAppCoreImageIndex = 0;

/// Decides what to send to *this* watch from *this* package.
///
/// One place owns the whole policy, so the rules can be unit-tested without a
/// radio and cannot drift between call sites:
///
/// 1. **Pre-v3 firmware gets the app core alone.** Never the radio image in the
///    same session — an older bootloader's slot map is not v3's, and with
///    overwrite-only MCUboot there is no revert if it lands wrong. The radio is
///    updated afterwards, by the freshly-installed v3 firmware's own DFU path.
/// 2. **v3 firmware takes the whole package.**
/// 3. **[resumingStageTwo]** is the post-reboot leg: the watch has come back
///    running v3, so only the images the first leg skipped are sent.
/// 4. A planned image the device has no slot for is a **refusal**, not a silent
///    drop — quietly skipping the radio image would report success while
///    leaving the watch half-migrated.
///
/// [packageImages] is the package's full image list (already mapped out of the
/// manifest by the caller, so this stays free of JSON and `dart:io`).
DfuPlan planDfu({
  required DeviceGeneration generation,
  required DeviceSlots slots,
  required List<FirmwareImage> packageImages,
  bool resumingStageTwo = false,
}) {
  if (packageImages.isEmpty) {
    return const DfuPlan.blocked('This firmware package contains no images.');
  }

  final appCore =
      packageImages.where((i) => i.imageIndex == kAppCoreImageIndex).toList();
  final others =
      packageImages.where((i) => i.imageIndex != kAppCoreImageIndex).toList();

  final List<FirmwareImage> planned;
  final DfuStage stage;
  final bool stageTwoFollows;

  if (resumingStageTwo) {
    // Second leg. The watch must actually be running v3 by now — if it is not,
    // the reboot did not take, and sending the radio image would be exactly the
    // mismatch the two-stage flow exists to prevent.
    if (generation.isPreV3) {
      return DfuPlan.blocked(
        'The watch is still running its previous firmware '
        '(${generation.label}). Install the main firmware update first, then '
        'update the radio.',
      );
    }
    if (others.isEmpty) {
      return const DfuPlan.blocked(
        'This package has no radio firmware image, so there is nothing to '
        'install in the second step.',
      );
    }
    planned = others;
    stage = DfuStage.netCore;
    stageTwoFollows = false;
  } else if (generation.isPreV3) {
    if (appCore.isEmpty) {
      return const DfuPlan.blocked(
        'This package has no main firmware image, which is what a watch on '
        'older firmware needs first.',
      );
    }
    planned = appCore;
    stage = DfuStage.appCoreFirst;
    stageTwoFollows = others.isNotEmpty;
  } else {
    planned = packageImages;
    stage = DfuStage.single;
    stageTwoFollows = false;
  }

  // Refuse only on *positive* evidence that the watch cannot take an image —
  // i.e. its generation is known and the index is outside what that generation
  // builds. A missing entry in the device's own image list is NOT evidence:
  // MCUmgr omits any slot whose header it cannot read, and the nRF5340 net-core
  // primary lives in network-core flash the app core cannot read, so a healthy
  // two-image watch lists slot 0 alone while still accepting image 1.
  final supported = supportedImageIndexes(generation);
  final notes = <String>[];

  if (supported != null) {
    final unsupported = planned
        .map((i) => i.imageIndex)
        .where((idx) => !supported.contains(idx))
        .toSet();
    if (unsupported.isNotEmpty) {
      final want = (unsupported.toList()..sort()).join(', ');
      final have = (supported.toList()..sort()).join(', ');
      return DfuPlan.blocked(
        'This package contains image $want, which ${generation.label} firmware '
        'has no slot for (it uses image $have). Use a package built for this '
        'device.',
      );
    }
  }

  if (slots.isKnown) {
    final unlisted =
        planned.map((i) => i.imageIndex).where((idx) => !slots.has(idx)).toSet();
    if (unlisted.isNotEmpty) {
      notes.add('device listed only slot(s) ${slots.pretty}; sending to '
          '${(unlisted.toList()..sort()).join(", ")} anyway (unreadable slots '
          'are omitted from image list)');
    }
  }

  return DfuPlan._(
    images: planned,
    stage: stage,
    stageTwoFollows: stageTwoFollows,
    notes: notes,
  );
}
