import 'dart:typed_data';

import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:test/test.dart';

/// The RECORDS wire shape, pinned against the firmware
/// (`app/src/health/hpi_hs_mgmt.c`, `hpi_hs_types.h`).
///
/// Every one of these started life as a guess in the client, and every guess was
/// wrong in a way that produced *plausible* output rather than an error — a
/// recording that decoded to noise, a clean session labelled "partial", a
/// library that showed six items. That is exactly the failure mode a test is for.
void main() {
  /// A header exactly as the device emits it.
  Map<Object?, Object?> deviceHeader({
    int id = 3,
    int sig = 0,
    int fmt = 0,
    int ch = 1,
    int rate = 128,
    int ns = 256,
    int len = 1024,
    int crc = 0,
    int flags = 1,
    int ts = 1752480000,
  }) =>
      {
        'id': id,
        'sig': sig,
        'fmt': fmt,
        'ch': ch,
        'rate': rate,
        'ns': ns,
        'len': len,
        'crc': crc,
        'flags': flags,
        'ts': ts,
      };

  group('HsRecordHeader.fromMap — firmware keys', () {
    test('parses every key the device actually sends', () {
      final h = HsRecordHeader.fromMap(deviceHeader());
      expect(h.id, 3);
      expect(h.signal, 0);
      expect(h.sampleFormat, 0);
      expect(h.channels, 1);
      expect(h.sampleRate, 128);
      expect(h.byteLen, 1024);
      expect(h.startTs, 1752480000);
    });

    test('`ns` is the sample count', () {
      // This key was missing from the candidate list entirely, so nSamples came
      // back 0 for every record the device has ever sent.
      expect(HsRecordHeader.fromMap(deviceHeader(ns: 256)).nSamples, 256);
    });
  });

  group('record flags — COMPLETE is bit0, PARTIAL is bit1', () {
    test('a clean session is complete, not partial', () {
      final h = HsRecordHeader.fromMap(deviceHeader(flags: 1));
      expect(h.isComplete, isTrue);
      expect(h.isPartial, isFalse,
          reason: 'bit0 is COMPLETE; testing it as PARTIAL inverted every record');
    });

    test('an interrupted session is partial, not complete', () {
      final h = HsRecordHeader.fromMap(deviceHeader(flags: 2));
      expect(h.isPartial, isTrue);
      expect(h.isComplete, isFalse);
    });

    test('compressed is surfaced so callers do not decode noise', () {
      expect(HsRecordHeader.fromMap(deviceHeader(flags: 1 | 4)).isCompressed,
          isTrue);
      expect(HsRecordHeader.fromMap(deviceHeader(flags: 1)).isCompressed, isFalse);
    });
  });

  group('HsRecordSamples.decode — fmt is authoritative', () {
    test('fmt 0 decodes int32 little-endian, signed', () {
      final payload = Uint8List.fromList([
        0xFF, 0xFF, 0xFF, 0xFF, // -1
        0x02, 0x00, 0x00, 0x00, // 2
      ]);
      final h = HsRecordHeader.fromMap(deviceHeader(fmt: 0, ch: 1, ns: 2, len: 8));
      final s = HsRecordSamples.decode(h, payload);

      expect(s.bytesPerSample, 4);
      expect(s.assumed, isFalse);
      expect(s.data.first, [-1.0, 2.0]);
    });

    test('fmt 1 decodes int16 little-endian, signed', () {
      final payload = Uint8List.fromList([0xFF, 0xFF, 0x02, 0x00]); // -1, 2
      final h = HsRecordHeader.fromMap(deviceHeader(fmt: 1, ch: 1, ns: 2, len: 4));
      final s = HsRecordSamples.decode(h, payload);

      expect(s.bytesPerSample, 2);
      expect(s.data.first, [-1.0, 2.0]);
    });

    test('fmt 2 decodes uint16 — an R-R interval is never negative', () {
      // 0xFFFF as signed is -1; as an R-R interval in ms it is 65535.
      final payload = Uint8List.fromList([0xFF, 0xFF, 0xD0, 0x02]); // 65535, 720
      final h = HsRecordHeader.fromMap(deviceHeader(fmt: 2, ch: 1, ns: 2, len: 4));
      final s = HsRecordSamples.decode(h, payload);

      expect(s.data.first, [65535.0, 720.0],
          reason: 'fmt 2 is UNSIGNED; decoding it signed turns a long RR into -1');
    });

    test('interleaved channels are split per channel', () {
      // ch=2, int16: [c0=1, c1=2], [c0=3, c1=4]
      final payload = Uint8List.fromList(
          [0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00]);
      final h = HsRecordHeader.fromMap(deviceHeader(fmt: 1, ch: 2, ns: 2, len: 8));
      final s = HsRecordSamples.decode(h, payload);

      expect(s.channels, 2);
      expect(s.data[0], [1.0, 3.0]);
      expect(s.data[1], [2.0, 4.0]);
      expect(s.sampleCount, 2);
    });

    test('an unknown fmt falls back to inference and says so', () {
      final payload = Uint8List(8);
      final h = HsRecordHeader.fromMap(deviceHeader(fmt: 99, ch: 1, ns: 2, len: 8));
      final s = HsRecordSamples.decode(h, payload);

      expect(s.bytesPerSample, 4, reason: 'inferred from 8 bytes / (2 x 1)');
      expect(s.assumed, isTrue,
          reason: 'the UI must be able to flag this as unverified');
    });
  });
}
