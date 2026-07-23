// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/device_slots.dart';
import 'package:move/ble/firmware_updater.dart';

/// In-memory transport: records each upload, replays a fixed set of progress
/// ticks, returns a deterministic SHA, and records confirms. No radio, no SMP.
class FakeUploadTransport implements FirmwareUploadTransport {
  final List<({int imageIndex, int length})> uploads = [];
  final List<List<int>> staged = [];

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
  Future<void> markPending(List<int> sha) async => staged.add(List.of(sha));

  /// Slots the fake device exposes. Unknown (default) = the image list can't
  /// be read, so the pre-flight is skipped.
  DeviceSlots slots = const DeviceSlots.unknown();

  /// Hash the fake device reports for a staged slot; null = "not listed",
  /// which drives the updater onto the image's own TLV.
  List<int>? stagedHash = const [0xAA, 0xBB];

  @override
  Future<List<int>?> stagedImageHash(int imageIndex) async => stagedHash;

  @override
  Future<DeviceSlots> deviceSlots() async => slots;
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
    // Each image is staged with the hash the DEVICE reported for it — not the
    // digest upload() returned (that one is the upload-resume sha of the whole
    // file, which `image test` does not recognise).
    expect(tx.staged, [
      [0xAA, 0xBB],
      [0xAA, 0xBB],
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

  test('a staging step follows every upload (upload→stage→upload→stage)',
      () async {
    final order = <String>[];
    final tracer = _TracingTransport(order);
    final u = FirmwareUpdater(tracer);
    await u.run([_img(0, 10), _img(1, 10)]);
    expect(order, ['upload', 'stage', 'upload', 'stage']);
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
    expect(tx.staged, isEmpty); // never staged a failed upload
  });

  test('cancel mid-upload stops the walk before staging, with cancelled state',
      () async {
    // Request cancellation while the first image is still uploading.
    tx.duringFirstUpload = updater.cancel;

    await expectLater(
      updater.run([_img(0, 100), _img(1, 100)]),
      throwsA(isA<FirmwareUpdateCancelled>()),
    );

    expect(updater.state, FirmwareUpdateState.cancelled);
    expect(updater.error, isA<FirmwareUpdateCancelled>());
    // The in-flight image finished uploading but was NOT staged (so the device
    // won't swap to a half-committed update), and the second never ran.
    expect(tx.uploads, hasLength(1));
    expect(tx.staged, isEmpty);
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

  group('slot map is advisory, not a gate', () {
    test('sends to a slot the device did not list', () async {
      // The real nRF5340 case: the net core's primary slot lives in
      // network-core flash the app core can't read, so MCUmgr omits image 1
      // from `image list` even though uploads to it work. Refusing here used to
      // block every two-image update.
      tx.slots = const DeviceSlots.known({0});

      await updater.run([_img(0, 100), _img(1, 100)]);

      expect(updater.state, FirmwareUpdateState.complete);
      expect(tx.uploads, [
        (imageIndex: 0, length: 100),
        (imageIndex: 1, length: 100),
      ]);
    });

    test('a fully listed slot map changes nothing', () async {
      tx.slots = const DeviceSlots.known({0, 1});
      await updater.run([_img(0, 100), _img(1, 200)]);
      expect(updater.state, FirmwareUpdateState.complete);
      expect(tx.uploads, hasLength(2));
    });

    test('an unknown slot map does not block the update', () async {
      tx.slots = const DeviceSlots.unknown(); // list unreadable
      await updater.run([_img(1, 100)]);
      expect(updater.state, FirmwareUpdateState.complete);
      expect(tx.uploads, hasLength(1));
    });
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
  Future<void> markPending(List<int> sha) async => order.add('stage');

  @override
  Future<List<int>?> stagedImageHash(int imageIndex) async => const [0xAA];

  @override
  Future<DeviceSlots> deviceSlots() async => const DeviceSlots.unknown();
}
