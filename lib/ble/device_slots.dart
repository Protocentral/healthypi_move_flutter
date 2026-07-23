// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// What the device reports about its own MCUboot image slots (from an MCUmgr
/// `image list`).
///
/// The distinction that matters is **"one slot" vs "couldn't ask"**. Older
/// firmware can answer an `image list` with an error, or omit the net-core
/// entry entirely; treating that silence as "the device has only slot 0" would
/// refuse updates that would have worked, while treating a genuine one-slot
/// answer as unknown would let a doomed net-core upload run for minutes before
/// failing device-side with `Failed to open flash area`.
class DeviceSlots {
  /// The device answered: these are the image indexes it exposes.
  const DeviceSlots.known(this.indexes) : isKnown = true;

  /// The image list could not be read (link flaked, group unsupported, an `rc`
  /// error on the slot query). Callers proceed without the slot cross-check.
  const DeviceSlots.unknown()
      : indexes = const {},
        isKnown = false;

  final Set<int> indexes;
  final bool isKnown;

  /// True when the device is known to expose [index].
  bool has(int index) => isKnown && indexes.contains(index);

  /// Sorted, comma-separated slot list for messages ("0, 1").
  String get pretty => (indexes.toList()..sort()).join(', ');

  @override
  String toString() => isKnown ? 'slots $pretty' : 'slots unknown';
}
