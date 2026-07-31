// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// Which firmware generation a watch is running, derived from its DIS firmware
/// revision (`0x180A` → `0x2A26`).
///
/// This exists for exactly one decision: **may we send the net-core image in the
/// same session as the app-core image?** Only firmware built from the v3 tree
/// (two images, NCS 3.4, DTS partitioning) can take a full package. Everything
/// older gets the app core alone, then updates its radio from the new firmware's
/// own DFU UX — the two-stage migration.
///
/// The fielded generations, and why they are distinguished:
///
/// * [g1] — v1.x up to and including v1.2.2. NCS 2.9, **three** images: app,
///   net core, and a QSPI-XIP image 2. A package aimed at image 2 has nowhere to
///   go on v3 firmware, and v3's net-core image must not be pushed onto this
///   bootloader.
/// * [g1_5] — v1.5.0 and v1.5.1 **only**. Same layout as [g1] except MCUboot's
///   primary slot is declared larger (0xd8000 rather than 0xd4000). The *base*
///   address is 0x10000 in every generation and the secondary is identical
///   everywhere, so this does not need its own binary — it is called out because
///   the bench matrix must cover it, not because the app treats it differently.
/// * [g2] — v2.x. NCS 3.1, two images, the layout v3 inherits.
/// * [v3] — v3.x and later. The current tree; takes the full package.
///
/// Anything unparseable is [unknown], which is treated as pre-v3 on purpose:
/// MCUboot runs in overwrite-only mode with no auto-revert, so the conservative
/// path (app core only, one stage at a time) is the only safe default.
enum DeviceGeneration {
  g1,
  g1_5,
  g2,
  v3,
  unknown;

  /// True for every generation that must be updated app-core-first.
  ///
  /// [unknown] counts as pre-v3 — see the class doc: guessing "modern" on an
  /// unreadable version risks pushing a net-core image at a bootloader that
  /// cannot take it, and there is no rollback.
  bool get isPreV3 => this != DeviceGeneration.v3;

  /// Short label for logs and diagnostics.
  String get label => switch (this) {
        DeviceGeneration.g1 => 'G1 (v1.x, 3-image)',
        DeviceGeneration.g1_5 => 'G1.5 (v1.5.x)',
        DeviceGeneration.g2 => 'G2 (v2.x)',
        DeviceGeneration.v3 => 'v3 (current)',
        DeviceGeneration.unknown => 'unknown',
      };
}

/// The MCUboot image indexes a generation's firmware is built to accept, or
/// `null` when the generation is unknown and no claim can be made.
///
/// This is positive knowledge about our own builds, and it is the *only*
/// trustworthy source for "the watch cannot take this image". A device's own
/// `image list` cannot be used for that: MCUmgr silently omits any slot whose
/// image header it fails to read (`img_mgmt_state_encode_slot()` returns early
/// on error), and on the nRF5340 the net core's primary slot lives in
/// network-core flash that the app core cannot read — so a perfectly healthy
/// two-image watch reports slot 0 alone while still accepting uploads to image
/// 1 through the bootutil hook.
Set<int>? supportedImageIndexes(DeviceGeneration generation) => switch (generation) {
      // NCS 3.1 and 3.4 builds: app core + net core.
      DeviceGeneration.v3 || DeviceGeneration.g2 => const {0, 1},
      // NCS 2.9 builds also carried a QSPI-XIP image 2.
      DeviceGeneration.g1 || DeviceGeneration.g1_5 => const {0, 1, 2},
      DeviceGeneration.unknown => null,
    };

/// A parsed `major.minor.patch`, ignoring any build metadata.
///
/// The firmware derives `CONFIG_BT_DIS_FW_REV_STR` from `app/VERSION`, so the
/// string on the wire looks like `3.0.0+0` — the `+0` is MCUboot build metadata
/// and carries no generation information. Leading `v` is tolerated because
/// release tags carry one and hand-entered strings sometimes do too.
class FirmwareVersion implements Comparable<FirmwareVersion> {
  const FirmwareVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses `"3.0.0+0"`, `"v1.5.1"`, `"2.1"` → a version, or `null` when the
  /// string is absent, empty, or not a version at all (e.g. `"Unknown"`).
  static FirmwareVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    // Drop build metadata / pre-release suffixes: 3.0.0+0, 3.0.0-rc1.
    s = s.split('+').first.split('-').first.trim();

    final parts = s.split('.');
    if (parts.isEmpty) return null;

    final nums = <int>[];
    for (final p in parts.take(3)) {
      final n = int.tryParse(p.trim());
      if (n == null) return null; // any non-numeric component ⇒ not a version
      nums.add(n);
    }
    if (nums.isEmpty) return null;
    return FirmwareVersion(
      nums[0],
      nums.length > 1 ? nums[1] : 0,
      nums.length > 2 ? nums[2] : 0,
    );
  }

  @override
  int compareTo(FirmwareVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >=(FirmwareVersion other) => compareTo(other) >= 0;
  bool operator <(FirmwareVersion other) => compareTo(other) < 0;
  bool operator >(FirmwareVersion other) => compareTo(other) > 0;
  bool operator <=(FirmwareVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is FirmwareVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Classifies a DIS firmware-revision string into a [DeviceGeneration].
///
/// Deliberately total: every input maps to something, and anything it cannot
/// read maps to [DeviceGeneration.unknown] (which behaves as pre-v3).
DeviceGeneration generationFromFwRevision(String? fwRevision) {
  final v = FirmwareVersion.tryParse(fwRevision);
  if (v == null) return DeviceGeneration.unknown;

  if (v.major >= 3) return DeviceGeneration.v3;
  if (v.major == 2) return DeviceGeneration.g2;
  if (v.major == 1) {
    // v1.5.0 / v1.5.1 are the only builds with the enlarged primary slot.
    if (v.minor == 5 && v.patch <= 1) return DeviceGeneration.g1_5;
    return DeviceGeneration.g1;
  }
  // 0.x — pre-release firmware, treat as the oldest generation.
  return DeviceGeneration.g1;
}
