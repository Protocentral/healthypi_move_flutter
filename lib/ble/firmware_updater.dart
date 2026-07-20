// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';

/// The transport a [FirmwareUpdater] needs: upload one signed image, then
/// confirm it. Deliberately narrow and SMP-agnostic — today an adapter binds it
/// to `ImgMgmt` over the Nordic SMP characteristic, but the state machine below
/// never sees an `SmpClient`, so it drives and unit-tests without a radio.
///
/// Both calls mirror `ImgMgmt`: [uploadImage] streams the image to the
/// secondary slot and returns its SHA-256; [confirm] marks that SHA permanent
/// (MCUboot confirmOnly, swap on next reboot).
abstract class FirmwareUploadTransport {
  /// Upload a signed image to slot [imageIndex]; returns the image SHA-256 to
  /// hand to [confirm]. [onProgress] reports `(bytesSent, totalBytes)`.
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  });

  /// Mark an uploaded image permanent by its SHA (from [uploadImage]).
  Future<void> confirm(List<int> sha);

  /// Image indexes the device actually exposes (from its MCUmgr image list).
  ///
  /// Used to fail fast: uploading to an index the device has no flash area for
  /// only errors *after* the whole image has transferred (minutes of BLE), and
  /// surfaces device-side as `Failed to open flash area ID n: -2`. An **empty**
  /// set means "couldn't determine" and the pre-flight check is skipped.
  Future<Set<int>> deviceImageIndexes();
}

/// The package targets an image index this device has no slot for — e.g. a
/// 2-image package on a watch whose firmware was built for a single image.
/// Raised before any upload starts.
class FirmwareImageUnsupported implements Exception {
  const FirmwareImageUnsupported(this.imageIndex, this.available);

  final int imageIndex;
  final Set<int> available;

  @override
  String toString() {
    final have = (available.toList()..sort()).join(', ');
    return 'This firmware package contains an image for slot $imageIndex, but '
        'the watch only exposes image slot(s) $have. Its firmware was built for '
        'fewer images than the package provides — installing would fail after '
        'the upload. Use a package built for this device.';
  }
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
/// multi-image upload/confirm walk can be driven and unit-tested without a
/// widget or a real SMP session.
///
/// Protocol: for each image in the package, `upload` it to the secondary slot
/// and `confirm` its SHA (MCUboot confirmOnly). The SMP-wire plumbing — the
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

  /// Upload + confirm each image in order. Completes when all are confirmed
  /// ([state] → [FirmwareUpdateState.complete]); on failure or cancel it sets
  /// [state] + [error] and rethrows, so the caller's `finally` can still tear
  /// the SMP session down.
  ///
  /// Cancellation is cooperative: [cancel] stops the walk before the next image
  /// and before each `confirm`; it cannot interrupt an `upload` already in
  /// flight (that image finishes, then the loop aborts).
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
      // Pre-flight the slot map before transferring anything: a package image
      // aimed at a slot the device lacks fails only once the whole image has
      // been sent, which costs minutes and looks like a mid-update crash.
      final available = await _transport.deviceImageIndexes();
      if (available.isNotEmpty) {
        _log?.call('DFU: device exposes image slots '
            '${(available.toList()..sort()).join(", ")}');
        for (final img in images) {
          if (!available.contains(img.imageIndex)) {
            throw FirmwareImageUnsupported(img.imageIndex, available);
          }
        }
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

        final sha = await _transport.uploadImage(
          bytes,
          imageIndex: img.imageIndex,
          onProgress: (sent, total) {
            _currentImageProgress = total > 0 ? sent / total : 0.0;
            _imageProgress[i] = _currentImageProgress;
            notifyListeners();
          },
        );

        if (_cancelRequested) throw const FirmwareUpdateCancelled();
        await _transport.confirm(sha);
        _currentImageProgress = 1.0;
        _imageProgress[i] = 1.0;
        _log?.call('DFU: image ${i + 1} uploaded + confirmed');
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

  /// Request cancellation. The [run] loop aborts before the next image or
  /// `confirm`; an already-started `upload` finishes first.
  void cancel() {
    _cancelRequested = true;
  }
}
