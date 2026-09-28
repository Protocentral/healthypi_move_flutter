// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart'
    show Crc32;
import 'package:move/ble/dblk_frame.dart';

/// Every expected value in this file was produced by the firmware's reference
/// decoder, `tools/healthypi_ul/dblk.py` (repo `move_ultralight`), run over the
/// same bytes — the hex vectors were built and decoded there, and the fixture is
/// the first 20 whole frames of the bench capture `rec/0012.dblk` (fingertip
/// PPG, 2026-09-24). If a value here disagrees with dblk.py, this file is wrong.

Uint8List _hex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

// dblk.py-built vectors (see header comment).
const _vPpg =
    '44424c4b3800000007000000cb04fb711f0100000103020032000000a0860100fbffffff'
    'ffffff7f00000080000000002a000000c423e25e';
const _vUnknown =
    '44424c4b2c0000000100000005000000000000000600030020000000000102030405060708'
    '090a0b5ce391ba';
const _vVitals =
    '44424c4b3000000009000000630000000000000004000100010000004800ffff0f000080a9'
    '01ffffc8030000fb4bef41';
const _vEvent =
    '44424c4b28000000020000004d000000000000000800010000000000020006000a1e11fab5'
    '2cb117';
const _vTemp =
    '44424c4b24000000030000000b000000000000000500010001000000f00c0100844ecbd4';
const _vRr =
    '44424c4b28000000040000000c0000000000000003000100000000002c030b5a40e2010027'
    '03dba3';

/// Build a valid frame in-test (CRC computed here), for sequence tests. The
/// CRC routine itself is pinned by the dblk.py vectors above.
Uint8List _frame({
  int channel = DblkChannel.ppg,
  int seq = 0,
  int tNs = 0,
  int flags = 0,
  int rate = 50,
  int samples = 1,
  int? sampleSize,
}) {
  final size = sampleSize ?? DblkChannel.sampleSize[channel] ?? 4;
  final blockLen = kDblkOverhead + samples * size;
  final b = ByteData(blockLen);
  b.setUint32(0, kDblkMagic, Endian.little);
  b.setUint32(4, blockLen, Endian.little);
  b.setUint32(8, seq, Endian.little);
  b.setUint64(12, tNs, Endian.little);
  b.setUint8(20, channel);
  b.setUint8(21, flags);
  b.setUint16(22, samples, Endian.little);
  b.setUint16(24, rate, Endian.little);
  final bytes = b.buffer.asUint8List();
  for (var i = kDblkHeaderSize; i < blockLen - 4; i++) {
    bytes[i] = i & 0xFF;
  }
  b.setUint32(
    blockLen - 4,
    Crc32.compute(bytes.sublist(0, blockLen - 4)),
    Endian.little,
  );
  return bytes;
}

/// Build a frame from explicit samples, each packed by [pack] — the Dart twin
/// of `struct.pack(fmt, *s)` in the dblk.py-side script that produced the
/// `_vPpgM1` / `_vEventM1` hex below.
Uint8List _build({
  required int channel,
  required int seq,
  required int tNs,
  required int rate,
  required int sampleSize,
  required List<List<int>> samples,
  required void Function(ByteData b, int off, List<int> s) pack,
  int flags = 0,
}) {
  final blockLen = kDblkOverhead + samples.length * sampleSize;
  final b = ByteData(blockLen);
  b.setUint32(0, kDblkMagic, Endian.little);
  b.setUint32(4, blockLen, Endian.little);
  b.setUint32(8, seq, Endian.little);
  b.setUint64(12, tNs, Endian.little);
  b.setUint8(20, channel);
  b.setUint8(21, flags);
  b.setUint16(22, samples.length, Endian.little);
  b.setUint16(24, rate, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    pack(b, kDblkHeaderSize + i * sampleSize, samples[i]);
  }
  final bytes = b.buffer.asUint8List();
  b.setUint32(
    blockLen - 4,
    Crc32.compute(bytes.sublist(0, blockLen - 4)),
    Endian.little,
  );
  return bytes;
}

void _packPpg(ByteData b, int o, List<int> s) {
  b.setInt32(o, s[0], Endian.little);
  b.setInt32(o + 4, s[1], Endian.little);
  b.setInt32(o + 8, s[2], Endian.little);
}

void _packEvent(ByteData b, int o, List<int> s) {
  b.setUint16(o, s[0], Endian.little);
  b.setUint16(o + 2, s[1], Endian.little);
  b.setUint32(o + 4, s[2], Endian.little);
}

/// Channel 9 (PPG_M1), seq 41, three samples. Built here by [_build]; the same
/// bytes, built with `struct.pack('<iii', ...)` + `zlib.crc32` and decoded by
/// dblk.py's `decode()` / `Frame.samples()`, give:
///   PPG_M1 seq 41 t_ns 212902300000 n=3 @50Hz, 12 B/sample, crc 0x26407199
///   {green 46611, red 94549, ir 74942} {48130, 94203, 75723} {1, 0, 2147483647}
const _vPpgM1 =
    '44424c4b44000000290000006049f79131000000090003003200000013b6000055710100'
    'be24010002bc0000fb6f0100cb2701000100000000000000ffffff7f99714026';
const _ppgM1Samples = [
  [46611, 94549, 74942],
  [48130, 94203, 75723],
  [1, 0, 2147483647],
];

/// Channel 8, three events: START_M1, GAIN_M1, and an M2 GAIN. dblk.py's
/// `describe_event` on each:
///   PPG start M1 [lift,green,red,ir] {'lift': 128, 'green': 17, 'red': 17, 'ir': 17}
///   PPG gain M1 [lift,red] {'lift': 128, 'green': 22, 'red': 17, 'ir': 40}
///   PPG gain [lift] {'lift': 144, 'green': 17, 'red': 17, 'ir': 17}
const _vEventM1 =
    '44424c4b3800000003000000203cf49131000000080003000000000003000f0080111111'
    '0400050080161128020001009011111124786f90';
const _eventM1Samples = [
  [3, 15, 286331264],
  [4, 5, 672208512],
  [2, 1, 286331280],
];

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

DblkFrame _ok(Uint8List bytes) {
  final r = DblkFrame.parse(bytes);
  expect(r, isA<DblkOk>(), reason: '$r');
  return (r as DblkOk).frame;
}

DblkError _bad(Uint8List bytes) {
  final r = DblkFrame.parse(bytes);
  expect(r, isA<DblkBad>());
  return (r as DblkBad).error;
}

void main() {
  group('header', () {
    test('parses every field, little-endian', () {
      final f = _ok(_hex(_vPpg));
      expect(f.blockLen, 56);
      expect(f.channel, DblkChannel.ppg);
      expect(f.seq, 7);
      expect(f.tNs, 1234567890123);
      expect(f.flags, 3);
      expect(f.sampleCount, 2);
      expect(f.sampleRate, 50);
      expect(f.reserved, 0);
      expect(f.crc, 0x5ee223c4);
    });

    test('per-sample size is derived from block_len, not a table', () {
      expect(_ok(_hex(_vPpg)).sampleSize, 12);
      expect(_ok(_hex(_vVitals)).sampleSize, 16);
      expect(_ok(_hex(_vTemp)).sampleSize, 4);
      // Channel 6 is reserved; the app has no layout for it, and still knows
      // its size — which is what lets an unknown channel be skipped.
      expect(_ok(_hex(_vUnknown)).sampleSize, 4);
    });

    test('flags: GAP_BEFORE and SYNTHETIC are surfaced', () {
      final f = _ok(_hex(_vPpg));
      expect(f.gapBefore, isTrue);
      expect(f.synthetic, isTrue);
      final plain = _ok(_hex(_vTemp));
      expect(plain.gapBefore, isFalse);
      expect(plain.synthetic, isFalse);
      expect(_ok(_frame(flags: kDblkFlagGapBefore)).synthetic, isFalse);
      expect(_ok(_frame(flags: kDblkFlagSynthetic)).gapBefore, isFalse);
    });

    test('a frame with trailing bytes parses; the length is block_len', () {
      final two = Uint8List.fromList([..._hex(_vTemp), ..._hex(_vRr)]);
      final f = _ok(two);
      expect(f.channel, DblkChannel.temp);
      final g = DblkFrame.parse(two, f.blockLen);
      expect((g as DblkOk).frame.channel, DblkChannel.rr);
    });
  });

  group('typed samples (values from dblk.py)', () {
    test('PPG: signed 32-bit, full range', () {
      final s = _ok(_hex(_vPpg)).ppg;
      expect(s, hasLength(2));
      expect([s[0].green, s[0].red, s[0].ir], [100000, -5, 2147483647]);
      expect([s[1].green, s[1].red, s[1].ir], [-2147483648, 0, 42]);
    });

    test('VITALS: sentinels are null, never 0', () {
      final v = _ok(_hex(_vVitals)).samples.single as VitalsSample;
      expect(v.hrBpm, 72);
      expect(v.spo2X10Raw, 65535);
      expect(v.spo2X10, isNull);
      expect(v.respBpm, 15);
      expect(v.tempCX100Raw, -32768);
      expect(v.tempCX100, isNull);
      expect(v.rmssdX10, 425);
      expect(v.sdnnX10, isNull);
      expect(v.quality, 200);
      expect(v.activity, 3);
    });

    test('EVENT: PPG gain decodes to the settings in force after it', () {
      final f = _ok(_hex(_vEvent));
      expect(f.sampleRate, 0);
      final e = f.events.single;
      expect([e.type, e.code, e.arg], [2, 6, 4195425802]);
      expect(e.isPpgGain, isTrue);
      expect([e.lift, e.green, e.red, e.ir], [10, 30, 17, 250]);
      // dblk.py: "PPG gain [green,red] {'lift': 10, 'green': 30, 'red': 17, 'ir': 250}"
      expect(e.changed, ['green', 'red']);
      expect(e.describe(), 'PPG gain [green,red] lift 10 G 30 R 17 IR 250');
    });

    test('TEMP and RR', () {
      final t = _ok(_hex(_vTemp)).samples.single as TempSample;
      expect([t.tempCX100, t.flags], [3312, 1]);
      final r = _ok(_hex(_vRr)).samples.single as RrSample;
      expect([r.rrMs, r.quality, r.conf, r.tMsBeat], [812, 11, 90, 123456]);
    });

    test('an unknown channel parses, with no typed samples', () {
      final f = _ok(_hex(_vUnknown));
      expect(f.channel, 6);
      expect(f.isKnownChannel, isFalse);
      expect(f.sampleCount, 3);
      expect(f.payload, List.generate(12, (i) => i));
      expect(f.samples, isEmpty);
    });
  });

  group('second PPG module: channel 9 and event types 3/4', () {
    test('the in-test builder reproduces the dblk.py-built bytes', () {
      expect(
        _toHex(
          _build(
            channel: DblkChannel.ppgM1,
            seq: 41,
            tNs: 212902300000,
            rate: 50,
            sampleSize: 12,
            samples: _ppgM1Samples,
            pack: _packPpg,
          ),
        ),
        _vPpgM1,
      );
      expect(
        _toHex(
          _build(
            channel: DblkChannel.event,
            seq: 3,
            tNs: 212902100000,
            rate: 0,
            sampleSize: 8,
            samples: _eventM1Samples,
            pack: _packEvent,
          ),
        ),
        _vEventM1,
      );
    });

    test('channel 9 is a known channel named PPG_M1', () {
      expect(DblkChannel.ppgM1, 9);
      expect(DblkChannel.isKnown(9), isTrue);
      expect(DblkChannel.name(9), 'PPG_M1');
      expect(
        DblkChannel.sampleSize[9],
        DblkChannel.sampleSize[DblkChannel.ppg],
      );
      expect(DblkChannel.isPpg(1), isTrue);
      expect(DblkChannel.isPpg(9), isTrue);
      expect(DblkChannel.isPpg(8), isFalse);
    });

    test('a channel-9 frame decodes as PPG (values from dblk.py)', () {
      final f = _ok(_hex(_vPpgM1));
      expect(
        [f.channel, f.seq, f.tNs, f.sampleCount, f.sampleRate],
        [9, 41, 212902300000, 3, 50],
      );
      expect(f.sampleSize, 12);
      expect(f.crc, 0x26407199);
      expect(f.channelName, 'PPG_M1');
      expect(f.isKnownChannel, isTrue);
      expect(f.samples, everyElement(isA<PpgSample>()));
      expect([
        for (final p in f.ppg) [p.green, p.red, p.ir],
      ], _ppgM1Samples);
    });

    test('channel 9 at the wrong sample size is a layout mismatch', () {
      expect(
        _bad(_frame(channel: DblkChannel.ppgM1, samples: 2, sampleSize: 8)),
        DblkError.layoutMismatch,
      );
    });

    test('types 3/4 are M1 gain events (values from dblk.py)', () {
      final ev = _ok(_hex(_vEventM1)).events;
      expect([
        for (final e in ev) [e.type, e.code, e.arg],
      ], _eventM1Samples);

      final start = ev[0], gain = ev[1], m2 = ev[2];
      expect(
        [start.isPpgGain, start.isM1, start.isPpgStart],
        [true, true, true],
      );
      expect([gain.isPpgGain, gain.isM1, gain.isPpgStart], [true, true, false]);
      expect([m2.isPpgGain, m2.isM1], [true, false]);
      expect(start.ppgChannel, DblkChannel.ppgM1);
      expect(gain.ppgChannel, DblkChannel.ppgM1);
      expect(m2.ppgChannel, DblkChannel.ppg);
      expect(const EventSample(7, 0, 0).ppgChannel, isNull);

      expect([gain.lift, gain.green, gain.red, gain.ir], [128, 22, 17, 40]);
      expect(gain.changed, ['lift', 'red']);
      expect(
        start.describe(),
        'PPG start M1 [lift,green,red,ir] lift 128 G 17 R 17 IR 17',
      );
      expect(
        gain.describe(),
        'PPG gain M1 [lift,red] lift 128 G 22 R 17 IR 40',
      );
      expect(m2.describe(), 'PPG gain [lift] lift 144 G 17 R 17 IR 17');
    });

    test('tracker counts channel 9 per channel, not as unknown', () {
      final t = DblkStreamTracker();
      t.ingest(_hex(_vPpgM1));
      t.ingest(_frame(seq: 7)); // channel 1 alongside
      expect(t.unknownChannelFrames, 0);
      expect(t.channel(DblkChannel.ppgM1).frames, 1);
      expect(t.channel(DblkChannel.ppgM1).samples, 3);
      expect(t.channel(DblkChannel.ppg).frames, 1);
    });

    test('channel 9 has its own seq counter', () {
      final t = DblkStreamTracker();
      Uint8List m1(int seq) =>
          _frame(channel: DblkChannel.ppgM1, seq: seq, samples: 12);
      Uint8List m2(int seq) => _frame(seq: seq, samples: 12);
      t.ingest(m2(100));
      t.ingest(m1(5));
      expect(t.ingest(m2(101)).single.lostBefore, 0);
      final gap = t.ingest(m1(8)).single;
      expect(gap.lostBefore, 2);
      expect(gap.discontinuity, isTrue);
      expect(t.channel(DblkChannel.ppgM1).lostFrames, 2);
      expect(t.channel(DblkChannel.ppg).lostFrames, 0);
      final flagged =
          t
              .ingest(
                _frame(
                  channel: DblkChannel.ppgM1,
                  seq: 9,
                  flags: kDblkFlagGapBefore,
                ),
              )
              .single;
      expect(flagged.discontinuity, isTrue);
      expect(t.channel(DblkChannel.ppgM1).gapBeforeFrames, 1);
      expect(t.channel(DblkChannel.ppg).gapBeforeFrames, 0);
    });

    test('tracker keeps the last gain event per module', () {
      final t = DblkStreamTracker();
      t.ingest(_hex(_vEventM1));
      expect(t.lastGainEventM1!.type, EventSample.typePpgGainM1);
      expect(t.lastGainEventM1!.ir, 40);
      expect(t.lastGainEventM1TNs, 212902100000);
      expect(t.lastGainEvent!.type, EventSample.typePpgGain);
      expect(t.lastGainEvent!.lift, 144);
      expect(t.lastGainFor(DblkChannel.ppgM1), same(t.lastGainEventM1));
      expect(t.lastGainFor(DblkChannel.ppg), same(t.lastGainEvent));
      t.reset();
      expect(t.lastGainEventM1, isNull);
      expect(t.lastGainEventM1TNs, isNull);
    });

    test('older firmware: an M2-only event leaves M1 empty', () {
      final t = DblkStreamTracker();
      t.ingest(_hex(_vEvent));
      expect(t.lastGainEvent!.green, 30);
      expect(t.lastGainEventM1, isNull);
    });
  });

  group('bad input returns a typed error, never throws', () {
    test('CRC pass and fail', () {
      _ok(_hex(_vPpg));
      final bytes = _hex(_vPpg);
      bytes[30] ^= 0x01; // one payload bit
      expect(_bad(bytes), DblkError.badCrc);
      final crcByte = _hex(_vPpg);
      crcByte[crcByte.length - 1] ^= 0x80; // the stored CRC itself
      expect(_bad(crcByte), DblkError.badCrc);
    });

    test('truncated: short header, and short body', () {
      expect(_bad(Uint8List(0)), DblkError.truncated);
      expect(_bad(_hex(_vPpg).sublist(0, 27)), DblkError.truncated);
      expect(_bad(_hex(_vPpg).sublist(0, 55)), DblkError.truncated);
    });

    test('bad magic', () {
      final b = _hex(_vPpg)..[0] = 0x45;
      expect(_bad(b), DblkError.badMagic);
    });

    test('implausible block_len', () {
      final small = _hex(_vPpg);
      ByteData.sublistView(small).setUint32(4, 31, Endian.little);
      expect(_bad(small), DblkError.badLength);
      final huge = _hex(_vPpg);
      ByteData.sublistView(huge).setUint32(4, 0xFFFFFFFF, Endian.little);
      expect(_bad(huge), DblkError.badLength);
    });

    test('block_len inconsistent with sample_count', () {
      final b = _hex(_vPpg);
      // 24 B of payload is not 5 whole samples.
      ByteData.sublistView(b).setUint16(22, 5, Endian.little);
      expect(_bad(b), DblkError.sampleCountMismatch);
    });

    test('known channel at the wrong sample size is a layout mismatch', () {
      // A well-formed, CRC-valid PPG frame of 8-byte samples: firmware drift.
      expect(
        _bad(_frame(channel: DblkChannel.ppg, samples: 3, sampleSize: 8)),
        DblkError.layoutMismatch,
      );
    });

    test('random garbage never throws', () {
      var seed = 12345;
      for (var n = 0; n < 500; n++) {
        final len = n % 80;
        final b = Uint8List(len);
        for (var i = 0; i < len; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
          b[i] = seed & 0xFF;
        }
        if (len >= 4 && n.isEven) {
          b.setAll(0, [0x44, 0x42, 0x4c, 0x4b]); // real magic, junk after
        }
        expect(() => DblkFrame.parse(b), returnsNormally);
        expect(() => DblkStreamTracker().ingest(b), returnsNormally);
      }
    });
  });

  group('stream tracker', () {
    test('counts seq gaps as lost frames, per channel', () {
      final t = DblkStreamTracker();
      expect(t.ingest(_frame(seq: 10)).single.lostBefore, 0);
      expect(t.ingest(_frame(seq: 11)).single.lostBefore, 0);
      // An ACC frame in between does not disturb PPG's sequence.
      t.ingest(_frame(channel: DblkChannel.acc, seq: 500));
      final gap = t.ingest(_frame(seq: 14)).single;
      expect(gap.lostBefore, 2);
      expect(gap.discontinuity, isTrue);
      expect(t.channel(DblkChannel.ppg).lostFrames, 2);
      expect(t.channel(DblkChannel.acc).lostFrames, 0);
      expect(t.lostFrames, 2);
      expect(t.frames, 4);
    });

    test('seq wraps at u32 without a false gap', () {
      final t = DblkStreamTracker();
      t.ingest(_frame(seq: 0xFFFFFFFF));
      expect(t.ingest(_frame(seq: 0)).single.lostBefore, 0);
    });

    test('a seq regression is a producer restart, not a loss', () {
      final t = DblkStreamTracker();
      t.ingest(_frame(seq: 100));
      expect(t.ingest(_frame(seq: 1)).single.lostBefore, 0);
      expect(t.lostFrames, 0);
    });

    test('GAP_BEFORE is a discontinuity even with contiguous seq', () {
      final t = DblkStreamTracker();
      t.ingest(_frame(seq: 1));
      final r = t.ingest(_frame(seq: 2, flags: kDblkFlagGapBefore)).single;
      expect(r.lostBefore, 0);
      expect(r.discontinuity, isTrue);
      expect(t.channel(DblkChannel.ppg).gapBeforeFrames, 1);
    });

    test('counts CRC errors, format errors, unknown and synthetic frames', () {
      final t = DblkStreamTracker();
      final corrupt = _hex(_vTemp)..[30] ^= 0xFF;
      t.ingest(corrupt);
      t.ingest(_hex(_vTemp).sublist(0, 20));
      t.ingest(_hex(_vUnknown));
      t.ingest(_hex(_vPpg));
      expect(t.crcErrors, 1);
      expect(t.formatErrors, 1);
      expect(t.lastError, DblkError.truncated);
      expect(t.unknownChannelFrames, 1);
      expect(t.syntheticFrames, 1);
      expect(t.frames, 2);
    });

    test('keeps the last PPG gain event', () {
      final t = DblkStreamTracker();
      t.ingest(_hex(_vEvent));
      expect(t.lastGainEvent!.green, 30);
      expect(t.lastGainEventTNs, 77);
    });

    test('measures the rate from t_ns, and restarts it across a gap', () {
      final t = DblkStreamTracker();
      // 10 samples every 200 ms = 50 Hz on the device clock.
      for (var i = 0; i < 5; i++) {
        t.ingest(_frame(seq: i, tNs: i * 200000000, samples: 10));
      }
      expect(t.channel(DblkChannel.ppg).measuredRateHz, closeTo(50.0, 1e-9));
      t.ingest(_frame(seq: 9, tNs: 5 * 200000000, samples: 10));
      expect(t.channel(DblkChannel.ppg).measuredRateHz, isNull);
    });

    test('several whole frames in one notification are each taken', () {
      final t = DblkStreamTracker();
      final got = t.ingest(
        Uint8List.fromList([
          ..._frame(seq: 1),
          ..._frame(seq: 2),
          ..._frame(seq: 3),
        ]),
      );
      expect(got.map((e) => e.frame.seq), [1, 2, 3]);
    });
  });

  group('real capture: rec/0012.dblk, first 20 frames', () {
    late Uint8List data;
    late List<DblkFrame> frames;

    setUpAll(() {
      data = File('test/fixtures/ul_0012_first20.dblk').readAsBytesSync();
      frames = [];
      var off = 0;
      while (off < data.length) {
        final r = DblkFrame.parse(data, off);
        expect(r, isA<DblkOk>(), reason: 'offset $off: $r');
        frames.add((r as DblkOk).frame);
        off += r.frame.blockLen;
      }
    });

    test('frame structure matches dblk.py', () {
      expect(data.length, 4492);
      expect(frames, hasLength(20));
      // dblk.py: frames=20 [PPG=11, ACC=8, EVENT=1] bad_crc=0 seq_gaps=0
      expect(frames.where((f) => f.channel == DblkChannel.ppg), hasLength(11));
      expect(frames.where((f) => f.channel == DblkChannel.acc), hasLength(8));
      expect(frames.where((f) => f.channel == DblkChannel.event), hasLength(1));
      final first = frames.first;
      expect(
        [first.channel, first.seq, first.tNs, first.sampleCount],
        [8, 1, 212902100000, 1],
      );
      expect(frames.first.crc, 0xf977414d);
      final ppg = frames.firstWhere((f) => f.channel == DblkChannel.ppg);
      expect(
        [ppg.seq, ppg.tNs, ppg.sampleCount, ppg.sampleRate, ppg.sampleSize],
        [12, 212902300000, 17, 50, 12],
      );
      final acc = frames.firstWhere((f) => f.channel == DblkChannel.acc);
      expect(
        [acc.seq, acc.tNs, acc.sampleCount, acc.sampleSize],
        [423, 212566300000, 25, 8],
      );
      expect(frames.last.seq, 22);
      expect(frames.last.tNs, 216291999920);
      expect(frames.any((f) => f.flags != 0), isFalse);
    });

    test('sample values match dblk.py', () {
      final ppg = frames.where((f) => f.channel == DblkChannel.ppg).toList();
      final p0 = ppg.first.ppg;
      expect(
        [p0.first.green, p0.first.red, p0.first.ir],
        [46611, 94549, 74942],
      );
      expect([p0.last.green, p0.last.red, p0.last.ir], [48130, 94203, 75723]);
      final pl = ppg.last.ppg.last;
      expect([pl.green, pl.red, pl.ir], [42618, 89659, 71990]);
      final all = ppg.expand((f) => f.ppg);
      expect(all.fold<int>(0, (a, s) => a + s.green), 8733656);
      expect(all.fold<int>(0, (a, s) => a + s.ir), 13866739);

      final acc = frames.where((f) => f.channel == DblkChannel.acc).toList();
      final a0 = acc.first.acc.first;
      expect([a0.x, a0.y, a0.z, a0.flags], [34, 17, -981, 0]);
      expect(acc.expand((f) => f.acc).fold<int>(0, (a, s) => a + s.z), -196210);

      // dblk.py: PPG start [lift,green,red,ir] {'lift': 192, 'green': 17, ...}
      final ev = frames.first.events.single;
      expect([ev.type, ev.code, ev.arg], [1, 15, 286331328]);
      expect([ev.lift, ev.green, ev.red, ev.ir], [192, 17, 17, 17]);
    });

    test('tracker: no loss, measured rates match dblk.py arithmetic', () {
      final t = DblkStreamTracker();
      var off = 0;
      while (off < data.length) {
        final bl = ByteData.sublistView(data, off).getUint32(4, Endian.little);
        t.ingest(Uint8List.sublistView(data, off, off + bl));
        off += bl;
      }
      expect(t.frames, 20);
      expect(t.crcErrors + t.formatErrors, 0);
      expect(t.lostFrames, 0);
      expect(t.syntheticFrames, 0);
      expect(t.unknownChannelFrames, 0);
      expect(t.lastGainEvent!.lift, 192);
      // sum(sample_count of all but last) / (t_last - t_first), in Python.
      expect(
        t.channel(DblkChannel.ppg).measuredRateHz,
        closeTo(50.151932032968865, 1e-9),
      );
      expect(
        t.channel(DblkChannel.acc).measuredRateHz,
        closeTo(50.0228675966156, 1e-9),
      );
    });
  });
}
