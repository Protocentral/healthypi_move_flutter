// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/firmware_updater.dart';

/// In-memory transport: records each upload, replays a fixed set of progress
/// ticks, returns a deterministic SHA, and records confirms. No radio, no SMP.
class FakeUploadTransport implements FirmwareUploadTransport {
  final List<({int imageIndex, int length})> uploads = [];
  final List<List<int>> confirms = [];

  /// Progress ticks (fractions 0..1) replayed for every upload.
  List<double> ticks = const [0.5, 1.0];

  /// If set, [uploadImage] throws this instead of completing (nth upload).
  Object? failOnUpload;

  /// Fired once, mid-way through the *first* upload's progress — lets a test
  /// request cancellation deterministically while an upload is in flight.
  void Function()? duringFirstUpload;
  bool _hookFired = false;

  @override
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add((imageIndex: imageIndex, length: image.length));
    onProgress?.call(0, image.length);
    for (final t in ticks) {
      if (uploads.length == 1 && duringFirstUpload != null && !_hookFired) {
        _hookFired = true;
        duringFirstUpload!();
      }
      onProgress?.call((image.length * t).round(), image.length);
    }
    if (failOnUpload != null) throw failOnUpload!;
    // SHA stand-in: first byte + length, enough to tie confirm↔upload in tests.
    return [imageIndex, image.length & 0xFF];
  }

  @override
  Future<void> confirm(List<int> sha) async => confirms.add(List.of(sha));
}

FirmwareImage _img(int slot, int len, {String? name}) => FirmwareImage(
      imageIndex: slot,
      name: name,
      load: () async => Uint8List.fromList(List.filled(len, 0xAB)),
    );

void main() {
  late FakeUploadTransport tx;
  late FirmwareUpdater updater;
  late int notifications;

  setUp(() {
    tx = FakeUploadTransport();
    updater = FirmwareUpdater(tx);
    notifications = 0;
    updater.addListener(() => notifications++);
  });

  tearDown(() => updater.dispose());

  test('starts idle', () {
    expect(updater.state, FirmwareUpdateState.idle);
    expect(updater.overallProgress, 0);
    expect(updater.error, isNull);
  });

  test('uploads then confirms each image in order, reaching complete',
      () async {
    await updater.run([_img(0, 100), _img(1, 200)]);

    expect(updater.state, FirmwareUpdateState.complete);
    expect(tx.uploads, [
      (imageIndex: 0, length: 100),
      (imageIndex: 1, length: 200),
    ]);
    // Each image is confirmed with the SHA its own upload returned.
    expect(tx.confirms, [
      [0, 100 & 0xFF],
      [1, 200 & 0xFF],
    ]);
    expect(updater.imageCount, 2);
    expect(updater.overallProgress, 1.0);
    expect(notifications, greaterThan(0));
  });

  test('overall progress advances across images', () async {
    tx.ticks = const [1.0];
    final seen = <double>[];
    updater.addListener(() => seen.add(updater.overallProgress));

    await updater.run([_img(0, 10), _img(1, 10)]);

    // Should pass through the mid-point (first image done, second not started).
    expect(seen, contains(0.5));
    expect(seen.last, 1.0);
  });

  test('a confirm follows every upload (upload→confirm→upload→confirm)',
      () async {
    final order = <String>[];
    final tracer = _TracingTransport(order);
    final u = FirmwareUpdater(tracer);
    await u.run([_img(0, 10), _img(1, 10)]);
    expect(order, ['upload', 'confirm', 'upload', 'confirm']);
    u.dispose();
  });

  test('an upload failure sets failed state and rethrows', () async {
    tx.failOnUpload = StateError('flash open failed');

    await expectLater(
      updater.run([_img(0, 100)]),
      throwsA(isA<StateError>()),
    );
    expect(updater.state, FirmwareUpdateState.failed);
    expect(updater.error, isA<StateError>());
    expect(tx.confirms, isEmpty); // never confirmed a failed upload
  });

  test('cancel mid-upload stops the walk before confirm, with cancelled state',
      () async {
    // Request cancellation while the first image is still uploading.
    tx.duringFirstUpload = updater.cancel;

    await expectLater(
      updater.run([_img(0, 100), _img(1, 100)]),
      throwsA(isA<FirmwareUpdateCancelled>()),
    );

    expect(updater.state, FirmwareUpdateState.cancelled);
    expect(updater.error, isA<FirmwareUpdateCancelled>());
    // The in-flight image finished uploading but was NOT confirmed (so the
    // device won't swap to a half-committed update), and the second never ran.
    expect(tx.uploads, hasLength(1));
    expect(tx.confirms, isEmpty);
  });

  test('cancelled is a distinct type from a real failure', () async {
    tx.duringFirstUpload = updater.cancel;
    Object? caught;
    try {
      await updater.run([_img(0, 10)]);
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<FirmwareUpdateCancelled>());
    expect(caught, isNot(isA<StateError>()));
  });

  test('run resets state, so a retry after a failure starts clean', () async {
    tx.failOnUpload = Exception('boom');
    await expectLater(updater.run([_img(0, 10)]), throwsA(isA<Exception>()));
    expect(updater.state, FirmwareUpdateState.failed);

    tx.failOnUpload = null;
    await updater.run([_img(0, 10), _img(1, 20)]);
    expect(updater.state, FirmwareUpdateState.complete);
    expect(updater.error, isNull);
    expect(updater.imageCount, 2);
  });
}

/// Records the interleaving of upload vs confirm calls.
class _TracingTransport implements FirmwareUploadTransport {
  _TracingTransport(this.order);
  final List<String> order;

  @override
  Future<List<int>> uploadImage(
    Uint8List image, {
    required int imageIndex,
    void Function(int sent, int total)? onProgress,
  }) async {
    order.add('upload');
    return [imageIndex];
  }

  @override
  Future<void> confirm(List<int> sha) async => order.add('confirm');
}
