// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

/// Header of an episodic raw-signal **record** session (`RECORDS list`).
///
/// Key names are now **pinned against the firmware** (`hpi_hs_mgmt.c`, and
/// `HPI_HS_API.md` §RECORDS): the device emits
/// `{id, sig, fmt, ch, rate, ns, len, crc, flags, ts}`. [fromMap] still accepts
/// the historical candidates first-match-wins and never throws, but the real key
/// is listed first in each group.
///
/// The `ns` key used to be missing from the candidate list entirely, so every
/// header parsed `nSamples = 0` — which made [HsRecordSamples.decode] infer
/// bytes-per-sample from `len / (0 × ch)` and blow up. That is why this is
/// pinned now rather than guessed.
class HsRecordHeader {
  const HsRecordHeader({
    required this.id,
    required this.startTs,
    required this.signal,
    required this.sampleFormat,
    required this.channels,
    required this.sampleRate,
    required this.nSamples,
    required this.byteLen,
    required this.crc32,
    required this.flags,
  });

  final int id;
  final int startTs;
  final int signal; // signal type (ECG/BioZ/PPG/HRV/IMU)
  final int sampleFormat;
  final int channels;
  final int sampleRate;
  final int nSamples;
  final int byteLen;
  final int crc32;
  final int flags; // e.g. PARTIAL

  // Record flag bits — `HPI_HS_REC_F_*` in the firmware's hpi_hs_types.h.
  static const int flagComplete = 1 << 0; // session closed cleanly
  static const int flagPartial = 1 << 1; // interrupted (reset/battery) — usable
  static const int flagCompressed = 1 << 2; // payload is compressed

  /// Session closed cleanly.
  bool get isComplete => (flags & flagComplete) != 0;

  /// Interrupted by a reset or a flat battery. **Usable, not truncated** — store
  /// and mark it; don't discard.
  ///
  /// This used to test bit 0, which is `COMPLETE` — so it reported every clean
  /// recording as partial and every partial one as clean, exactly backwards.
  bool get isPartial => (flags & flagPartial) != 0;

  /// The payload is compressed. Nothing here decompresses it, and decoding it as
  /// raw samples would yield plausible-looking noise — so callers must check
  /// this before trusting [HsRecordSamples.decode].
  bool get isCompressed => (flags & flagCompressed) != 0;

  static int _i(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  /// The firmware's key is listed **first** in each group; the rest are legacy
  /// candidates kept so an older device still parses.
  factory HsRecordHeader.fromMap(Map<Object?, Object?> m) => HsRecordHeader(
        id: _i(m, ['id']),
        startTs: _i(m, ['ts', 'start_ts', 'start', 'start_utc']),
        signal: _i(m, ['sig', 'signal', 'type']),
        sampleFormat: _i(m, ['fmt', 'sample_format', 'format']),
        channels: _i(m, ['ch', 'channels', 'nch']),
        sampleRate: _i(m, ['rate', 'sr', 'sample_rate', 'fs']),
        nSamples: _i(m, ['ns', 'n', 'n_samples', 'nsamp', 'samples']),
        byteLen: _i(m, ['len', 'byte_len', 'bytes', 'size']),
        crc32: _i(m, ['crc', 'crc32']),
        flags: _i(m, ['flags', 'flag']),
      );

  DateTime get startTime =>
      DateTime.fromMillisecondsSinceEpoch(startTs * 1000, isUtc: true);

  String get signalName => hsSignalName(signal);

  int get effectiveChannels => channels <= 0 ? 1 : channels;
}

/// Signal-type codes, pinned against the firmware's `enum hpi_hs_signal`
/// (`app/src/health/hpi_hs_types.h`).
///
/// **The enum is 1-based.** This table used to start at 0, which shifted every
/// code by one: an ECG record (1) was reported as GSR, a GSR record (2) as PPG,
/// and IMU (6) fell off the end entirely. Nothing ever emitted 0, so
/// [HsSignal.ecg] was unreachable and ECG sessions could never be listed.
/// Values here are a wire contract — do not renumber them.
abstract final class HsSignal {
  static const int ecg = 0x01; // MAX30001 ECG, int32 raw
  static const int bioz = 0x02; // MAX30001 BioZ / GSR, int32 raw
  static const int ppgWrist = 0x03; // MAX32664C PPG (multi-LED)
  static const int ppgFinger = 0x04; // MAX32664D PPG (multi-LED)
  static const int hrvRr = 0x05; // R-R intervals, uint16 ms
  static const int acc = 0x06; // IMU accel, int16 x/y/z
}

/// Human-readable name for a firmware [HsSignal] code.
String hsSignalName(int code) {
  const names = {
    HsSignal.ecg: 'ECG',
    HsSignal.bioz: 'BioZ/GSR',
    HsSignal.ppgWrist: 'PPG (wrist)',
    HsSignal.ppgFinger: 'PPG (finger)',
    HsSignal.hrvRr: 'HRV (R-R)',
    HsSignal.acc: 'IMU',
  };
  return names[code] ?? 'signal $code';
}

/// Decoded raw-record samples, split per channel.
///
/// The encoding is **pinned** by the header's `fmt` (`enum hpi_hs_sfmt`):
/// `0` int32-LE, `1` int16-LE, `2` **uint16**-LE (e.g. R-R intervals in ms).
/// This used to ignore `fmt` and infer bytes-per-sample from
/// `byteLen / (nSamples × channels)`, decoding everything as *signed* — which
/// silently mis-sized an int32 record as int16 whenever the inference fell
/// through to its default, and read unsigned R-R data as signed.
///
/// [assumed] stays, and is now only true when the device sends a `fmt` code we
/// don't know — in which case we fall back to the old inference and the UI can
/// flag the waveform as unverified rather than present it as fact.
class HsRecordSamples {
  const HsRecordSamples({
    required this.channels,
    required this.data,
    required this.bytesPerSample,
    required this.assumed,
  });

  final int channels;
  final List<List<double>> data; // [channel][sample]
  final int bytesPerSample;
  final bool assumed;

  int get sampleCount => data.isEmpty ? 0 : data.first.length;

  // enum hpi_hs_sfmt (firmware hpi_hs_types.h).
  static const int fmtI32 = 0;
  static const int fmtI16 = 1;
  static const int fmtU16 = 2;

  factory HsRecordSamples.decode(HsRecordHeader h, Uint8List payload) {
    final ch = h.effectiveChannels;

    int bps;
    bool signed;
    bool assumed = false;

    switch (h.sampleFormat) {
      case fmtI32:
        bps = 4;
        signed = true;
      case fmtI16:
        bps = 2;
        signed = true;
      case fmtU16:
        // Unsigned on purpose: R-R intervals are milliseconds, never negative.
        bps = 2;
        signed = false;
      default:
        // Unknown format code — a firmware newer than this client. Fall back to
        // the old inference and mark the result as not fully trustworthy.
        signed = true;
        assumed = true;
        final inferred = (h.nSamples > 0 && ch > 0 && payload.isNotEmpty)
            ? payload.length ~/ (h.nSamples * ch)
            : 0;
        bps = (inferred == 1 || inferred == 2 || inferred == 4) ? inferred : 2;
    }

    final bd = ByteData.sublistView(payload);
    final totalSamples = payload.length ~/ (bps * ch);
    final data = List.generate(ch, (_) => <double>[]);
    for (int i = 0; i < totalSamples; i++) {
      for (int c = 0; c < ch; c++) {
        final off = (i * ch + c) * bps;
        if (off + bps > payload.length) break;
        final double v;
        switch (bps) {
          case 1:
            v = (signed ? bd.getInt8(off) : bd.getUint8(off)).toDouble();
          case 4:
            v = (signed
                    ? bd.getInt32(off, Endian.little)
                    : bd.getUint32(off, Endian.little))
                .toDouble();
          default:
            v = (signed
                    ? bd.getInt16(off, Endian.little)
                    : bd.getUint16(off, Endian.little))
                .toDouble();
        }
        data[c].add(v);
      }
    }
    return HsRecordSamples(
      channels: ch,
      data: data,
      bytesPerSample: bps,
      assumed: assumed,
    );
  }
}
