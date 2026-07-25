// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_slots.dart';
import 'mcuboot_image.dart';

/// The transport a [FirmwareUpdater] needs: upload one signed image, then stage
/// it for the next boot. Deliberately narrow and SMP-agnostic — today an adapter binds it
/// to `ImgMgmt` over the Nordic SMP characteristic, but the state machine below
/// never sees an `SmpClient`, so it drives and unit-tests without a radio.
///
/// Both calls mirror `ImgMgmt`: [uploadImage] streams the image to the
/// secondary slot and returns its SHA-256; [markPending] flags that SHA to be
/// booted next time (MCUmgr `test`), after which a reset performs the swap.
abstract class FirmwareUploadTransport {
  /// Upload a signed image to slot [imageIndex]. [onProgress] reports
  /// `(bytesSent, totalBytes)`.
  ///
  /// Returns the digest MCUmgr uses to match a resumed upload — SHA-256 of the
  /// whole file. That is NOT the image's identity for `test`/`confirm`; see
  /// [markPending].
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  });

  /// The hash the device reports for the staged (secondary) slot of
  /// [imageIndex], or null if it does not list one.
  ///
  /// This is the documented way to learn an image's identity: upload, then read
  /// it back out of `image list` (Nordic's `tfm_psa_template` README — "the hash
  /// of the image is shown in the image list", and for the second core "as
  /// image 1 in slot 1"). Returning null is normal rather than fatal — the
  /// nRF5340 omits slots it cannot read — and the caller falls back to parsing
  /// the image's own TLV.
  Future<List<int>?> stagedImageHash(int imageIndex);

  /// Stage an uploaded image for the next boot, by its MCUboot image hash —
  /// the MCUmgr `test` operation.
  ///
  /// The hash is NOT the SHA-256 of the uploaded file. Per the SMP Image
  /// group specification it is "SHA256 hash of the image header and body …
  /// the field in the MCUboot TLV section", so it must come from
  /// [stagedImageHash] or [McubootImage.sha256Tlv] — never from [uploadImage]'s
  /// return value, which is the upload-resume digest over the whole file.
  ///
  /// NOT `confirm`. Confirm applies to the image that is *already running*;
  /// asking a device to confirm a slot it has never booted is refused outright
  /// by current Zephyr (`IMG_MGMT_ERR_IMAGE_CONFIRMATION_DENIED`, surfacing as a
  /// bare `rc=1`), which left the upload staged and the watch never restarting.
  /// `test` + reset is also the flow every fielded generation supports, which
  /// matters when the same code drives updates onto NCS 2.9 and 3.1 devices.
  ///
  /// There is no post-boot confirm step: this bootloader is overwrite-only, so
  /// the copy is permanent and there is nothing to revert to.
  Future<void> markPending(List<int> sha);

  /// The image slots the device actually exposes (from its MCUmgr image list).
  ///
  /// Used to fail fast: uploading to an index the device has no flash area for
  /// only errors *after* the whole image has transferred (minutes of BLE), and
  /// surfaces device-side as `Failed to open flash area ID n: -2`. A
  /// [DeviceSlots.unknown] answer skips the pre-flight rather than blocking an
  /// update that would have worked — older firmware can fail this query outright.
  Future<DeviceSlots> deviceSlots();
}

/* FirmwareImageUnsupported (thrown when the device's `image list` omitted a
 * slot the package targets) is gone. Its premise was wrong: MCUmgr silently
 * drops any slot whose image header it cannot read, so the nRF5340's net-core
 * image never appears in the list and the check refused valid two-image
 * updates. The decision now lives in `planDfu`, which reasons from the
 * firmware generation — positive knowledge of what our own builds contain —
 * rather than from an incomplete report. */

/// Neither the device nor the image itself could tell us the MCUboot image
/// hash, so there is no way to name the image in a `test` request.
///
/// In practice this means the package holds something that is not an
/// MCUboot-signed image (or was signed without a SHA-256 TLV) — staging it
/// would fail on the device with "hash not found" anyway.
class FirmwareImageUnidentifiable implements Exception {
  const FirmwareImageUnidentifiable();

  @override
  String toString() =>
      'This firmware file is not a valid signed image — the watch cannot '
      'identify it. Use a package built for this device.';
}

/// The watch refused the transfer because its battery is below the firmware's
/// DFU floor (30 %). The firmware answers the img-mgmt upload hook with
/// `MGMT_ERR_EBADSTATE` (`rc=6`) and shows its own low-battery screen; without
/// this mapping the user sees a raw `bad state (rc=6)`, which reads like a crash.
///
/// Recoverable by definition: charge and retry, nothing was written.
class DfuBatteryTooLow implements Exception {
  const DfuBatteryTooLow();

  @override
  String toString() =>
      'The watch stopped the update because its battery is too low. Charge it '
      'to at least 30% and try again.';
}

/// One image to flash: its MCUboot slot index plus a lazy byte [load]er. The
/// loader keeps the updater `dart:io`-free (the screen reads the extracted file;
/// a test hands back an in-memory buffer) and defers reading large images until
/// their turn.
class FirmwareImage {
  FirmwareImage({
    required this.imageIndex,
    required this.load,
    this.name,
  });

  /// MCUboot image slot (0 = primary MCU, 1 = second core, …).
  final int imageIndex;

  /// Reads the image bytes on demand, when this image's turn comes.
  final Future<Uint8List> Function() load;

  /// Optional label for logs/diagnostics (e.g. the manifest file name).
  final String? name;
}

/// Where a [FirmwareUpdater] is in the install flow.
enum FirmwareUpdateState { idle, uploading, complete, failed, cancelled }

/// Thrown out of [FirmwareUpdater.run] when [FirmwareUpdater.cancel] was
/// requested. A distinct type so callers can tell a user abort from a real
/// failure (the screen shows no error banner for a cancel).
class FirmwareUpdateCancelled implements Exception {
  const FirmwareUpdateCancelled();
  @override
  String toString() => 'FirmwareUpdateCancelled';
}

/// The DFU install state machine, lifted out of `scr_dfu_new.dart` so the
/// multi-image upload/stage walk can be driven and unit-tested without a
/// widget or a real SMP session.
///
/// Protocol: for each image in the package, `upload` it to the secondary slot
/// and stage it for the next boot (`test`). The caller resets the device
/// afterwards, which is when MCUboot performs the swap. The SMP-wire plumbing — the
/// `ConnectionManager.acquireSmp` lock, the `SmpBleTransport`, MTU settling —
/// stays in the caller; this class only owns the loop, its progress, and
/// cooperative cancellation. See DECISIONS §… (BPT/Phase 8) for the extraction
/// pattern this mirrors.
///
/// A [ChangeNotifier] so the screen can `addListener` and rebuild; every state
/// mutation calls [notifyListeners]. `foundation`-only, so it moves into the
/// `healthypi_move` SDK package unchanged when that lands (Phase 8).
class FirmwareUpdater extends ChangeNotifier {
  FirmwareUpdater(
    this._transport, {
    void Function(String message)? log,
  }) : _log = log;

  final FirmwareUploadTransport _transport;
  final void Function(String message)? _log;

  FirmwareUpdateState _state = FirmwareUpdateState.idle;
  int _imageCount = 0;
  int _currentImageIndex = 0; // 0-based ordinal in the run list, not the slot
  final Map<int, double> _imageProgress = {}; // ordinal → 0..1
  double _currentImageProgress = 0;
  Object? _error;
  bool _cancelRequested = false;

  FirmwareUpdateState get state => _state;

  /// Number of images in the current/last run.
  int get imageCount => _imageCount;

  /// 0-based ordinal of the image currently uploading (add 1 for display).
  int get currentImageIndex => _currentImageIndex;

  /// Fraction (0..1) of the current image uploaded.
  double get currentImageProgress => _currentImageProgress;

  /// Per-image fraction (0..1), keyed by ordinal — for a multi-bar UI.
  Map<int, double> get imageProgress => Map.unmodifiable(_imageProgress);

  /// Fraction (0..1) across the whole package, images weighted equally
  /// (completed images + the in-flight image's fraction, over the total).
  double get overallProgress =>
      _imageCount == 0 ? 0 : (_currentImageIndex + _currentImageProgress) / _imageCount;

  /// The failure that put [state] in [FirmwareUpdateState.failed] (null
  /// otherwise). A [FirmwareUpdateCancelled] on a user abort.
  Object? get error => _error;

  bool get isRunning => _state == FirmwareUpdateState.uploading;

  /// Upload + stage each image in order. Completes when all are staged
  /// ([state] → [FirmwareUpdateState.complete]); on failure or cancel it sets
  /// [state] + [error] and rethrows, so the caller's `finally` can still tear
  /// the SMP session down.
  ///
  /// Cancellation is cooperative: [cancel] stops the walk before the next image
  /// and before each staging step; it cannot interrupt an `upload` already in
  /// flight (that image finishes, then the loop aborts). An uploaded-but-not-
  /// staged image is inert — the device keeps booting what it has.
  Future<void> run(List<FirmwareImage> images) async {
    _imageCount = images.length;
    _currentImageIndex = 0;
    _imageProgress.clear();
    _currentImageProgress = 0;
    _error = null;
    _cancelRequested = false;
    _state = FirmwareUpdateState.uploading;
    notifyListeners();

    try {
      // Log the device's slot map for diagnostics only. It deliberately does
      // NOT gate the upload: MCUmgr omits any slot whose image header it cannot
      // read, and on the nRF5340 the net core's primary slot is in network-core
      // flash the app core cannot read — so a healthy two-image watch reports
      // slot 0 alone while accepting image 1 perfectly well. Refusing on that
      // basis blocked valid updates. Whether an image *may* be sent is decided
      // by `planDfu`, from the device's firmware generation.
      final slots = await _transport.deviceSlots();
      if (slots.isKnown) {
        _log?.call('DFU: device lists image slots ${slots.pretty}');
        final unlisted = images
            .map((i) => i.imageIndex)
            .where((idx) => !slots.has(idx))
            .toSet();
        if (unlisted.isNotEmpty) {
          _log?.call('DFU: slot(s) ${(unlisted.toList()..sort()).join(", ")} '
              'not listed by the device — sending anyway');
        }
      } else {
        _log?.call('DFU: image list unavailable');
      }

      for (var i = 0; i < images.length; i++) {
        if (_cancelRequested) throw const FirmwareUpdateCancelled();
        final img = images[i];
        _currentImageIndex = i;
        _currentImageProgress = 0;
        notifyListeners();

        final bytes = await img.load();
        _log?.call('DFU: uploading image ${i + 1}/${images.length} '
            '(slot ${img.imageIndex}, ${bytes.length} B)');

        await _transport.uploadImage(
          bytes,
          imageIndex: img.imageIndex,
          onProgress: (sent, total) {
            _currentImageProgress = total > 0 ? sent / total : 0.0;
            _imageProgress[i] = _currentImageProgress;
            notifyListeners();
          },
        );

        if (_cancelRequested) throw const FirmwareUpdateCancelled();

        // Ask the device what it calls the image it just received — the
        // documented flow (upload → image list → test <hash>). Fall back to the
        // image's own IMAGE_TLV_SHA256 when the slot is missing from the
        // listing, which is normal for the nRF5340 net core.
        List<int>? hash = await _transport.stagedImageHash(img.imageIndex);
        if (hash != null) {
          _log?.call('DFU: device reports staged hash for image '
              '${img.imageIndex}');
        } else {
          hash = McubootImage.sha256Tlv(bytes);
          _log?.call('DFU: image ${img.imageIndex} not listed after upload — '
              'using the hash from its own TLV');
        }
        if (hash == null) {
          throw const FirmwareImageUnidentifiable();
        }

        await _transport.markPending(hash);
        _currentImageProgress = 1.0;
        _imageProgress[i] = 1.0;
        _log?.call('DFU: image ${i + 1} uploaded + staged for next boot');
        notifyListeners();
      }
      _state = FirmwareUpdateState.complete;
      notifyListeners();
    } on FirmwareUpdateCancelled catch (e) {
      _error = e;
      _state = FirmwareUpdateState.cancelled;
      _log?.call('DFU: cancelled');
      notifyListeners();
      rethrow;
    } catch (e) {
      _error = e;
      _state = FirmwareUpdateState.failed;
      _log?.call('DFU: update failed: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// Request cancellation. The [run] loop aborts before the next image or its
  /// staging step; an already-started `upload` finishes first.
  void cancel() {
    _cancelRequested = true;
  }
}
