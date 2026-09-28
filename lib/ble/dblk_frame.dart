// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

/// DBLK — the Move Ultralight's self-describing live-stream frame.
///
/// Radio-free and Flutter-free, like the rest of `lib/ble/`: bytes in, typed
/// frames and counters out, so every rule here is unit-testable with no device.
/// The host-side reference is the firmware's `tools/healthypi_ul/dblk.py`
/// (repo `move_ultralight`); `test/ble/dblk_frame_test.dart` pins this parser to
/// values produced by running that script over the same bytes.
///
/// On BLE the frames arrive on characteristic `0x2002` (service `0x2000`), one
/// whole frame per notification — the device never splits a frame. Layout,
/// all little-endian:
///
/// ```text
///  off size field
///   0   4   magic "DBLK"
///   4   4   block_len     magic..crc inclusive (= total frame length)
///   8   4   seq           per-CHANNEL monotonic u32; a gap means lost frames
///  12   8   t_ns          device-monotonic ns of the FIRST sample
///  20   1   channel
///  21   1   flags         bit0 GAP_BEFORE, bit1 SYNTHETIC
///  22   2   sample_count
///  24   2   sample_rate   Hz
///  26   2   reserved
///  28   N   sample_count x per-sample struct
/// 28+N  4   crc32 (IEEE / zlib) over [0, 28+N)
/// ```
///
/// Per-sample size is **derived**, `(block_len - 32) / sample_count`, never
/// looked up — so an unknown channel is still structurally parseable and can be
/// counted and skipped. For a *known* channel the derived size must equal the
/// layout this file knows; a mismatch means firmware and app have drifted, and
/// is reported as [DblkError.layoutMismatch] rather than silently misparsed.
///
/// **The rule, same as dblk.py: a reader never throws on bad data.** [DblkFrame.parse]
/// returns a typed [DblkBad]; [DblkStreamTracker] counts it and moves on.
library;

import 'dart:typed_data';

import 'package:healthypi_healthy_store/healthypi_healthy_store.dart'
    show Crc32;

// --- Wire constants ----------------------------------------------------------

/// "DBLK" read as a little-endian u32.
const int kDblkMagic = 0x4B4C4244;
const int kDblkHeaderSize = 28;
const int kDblkCrcSize = 4;
const int kDblkOverhead = kDblkHeaderSize + kDblkCrcSize;

/// Upper bound on a plausible frame — the same sanity limit dblk.py applies, so
/// a corrupt length field cannot make a reader wait for 4 GB.
const int kDblkMaxBlockLen = 4096;

/// The producer knows it lost samples before this frame. Draw a gap.
const int kDblkFlagGapBefore = 1 << 0;

/// The samples are generated, not measured. Must raise the synthetic banner.
const int kDblkFlagSynthetic = 1 << 1;

/// Channel ids — mirror of `enum hpi_channel` in the firmware's
/// `core/channels.h`. 6 (EDA) and 7 (ECG) are reserved on the Ultralight.
///
/// The Ultralight has two PPG LED modules on one photodiode: [ppg] (channel 1)
/// is module **M2**, [ppgM1] (channel 9) is module **M1**. Both carry the same
/// sample struct from the same AFE frames, so sample i of a channel-9 frame has
/// the timestamp of sample i of the channel-1 frame published alongside it.
/// Firmware before the second module never sends channel 9.
abstract final class DblkChannel {
  /// PPG, LED module M2 (LED5/7/8).
  static const int ppg = 1;
  static const int acc = 2;
  static const int rr = 3;
  static const int vitals = 4;
  static const int temp = 5;
  static const int eda = 6;
  static const int ecg = 7;
  static const int event = 8;

  /// PPG, LED module M1 (LED1/2/3). Same layout as [ppg].
  static const int ppgM1 = 9;

  /// True for either PPG module's channel.
  static bool isPpg(int channel) => channel == ppg || channel == ppgM1;

  /// Canonical per-sample size of each channel this app can decode.
  /// Channels absent here are *unknown* — counted and skipped, never an error.
  static const Map<int, int> sampleSize = {
    ppg: 12,
    acc: 8,
    rr: 8,
    vitals: 16,
    temp: 4,
    event: 8,
    ppgM1: 12,
  };

  static bool isKnown(int channel) => sampleSize.containsKey(channel);

  static String name(int channel) => switch (channel) {
    ppg => 'PPG',
    acc => 'ACC',
    rr => 'RR',
    vitals => 'VITALS',
    temp => 'TEMP',
    eda => 'EDA',
    ecg => 'ECG',
    event => 'EVENT',
    ppgM1 => 'PPG_M1',
    _ => 'CH$channel',
  };
}

// --- Typed samples -----------------------------------------------------------

/// One decoded sample of a known channel.
sealed class DblkSample {
  const DblkSample();
}

/// Channels 1 (module M2) and 9 (module M1). Ambient-subtracted counts: positive, larger with more light.
/// A large DC with the pulse as a small AC ripple on it.
final class PpgSample extends DblkSample {
  const PpgSample(this.green, this.red, this.ir);
  final int green, red, ir;
}

/// Channel 2. Raw accelerometer counts.
final class AccSample extends DblkSample {
  const AccSample(this.x, this.y, this.z, this.flags);
  final int x, y, z, flags;
}

/// Channel 3. One beat-to-beat interval.
final class RrSample extends DblkSample {
  const RrSample(this.rrMs, this.quality, this.conf, this.tMsBeat);
  final int rrMs, quality, conf, tMsBeat;
}

/// Channel 4. An unavailable field is `0xFFFF` (u16) or `-32768` (i16) on the
/// wire, **never 0** — the getters here map that sentinel to `null` so no
/// caller can mistake "not measured" for a real zero.
final class VitalsSample extends DblkSample {
  const VitalsSample({
    required this.hrBpmRaw,
    required this.spo2X10Raw,
    required this.respBpmRaw,
    required this.tempCX100Raw,
    required this.rmssdX10Raw,
    required this.sdnnX10Raw,
    required this.quality,
    required this.activity,
  });
  final int hrBpmRaw, spo2X10Raw, respBpmRaw, tempCX100Raw;
  final int rmssdX10Raw, sdnnX10Raw, quality, activity;

  static int? _u16(int v) => v == 0xFFFF ? null : v;
  int? get hrBpm => _u16(hrBpmRaw);
  int? get spo2X10 => _u16(spo2X10Raw);
  int? get respBpm => _u16(respBpmRaw);
  int? get tempCX100 => tempCX100Raw == -32768 ? null : tempCX100Raw;
  int? get rmssdX10 => _u16(rmssdX10Raw);
  int? get sdnnX10 => _u16(sdnnX10Raw);
}

/// Channel 5.
final class TempSample extends DblkSample {
  const TempSample(this.tempCX100Raw, this.flags);
  final int tempCX100Raw, flags;
  int? get tempCX100 => tempCX100Raw == -32768 ? null : tempCX100Raw;
}

/// Channel 8. PPG gain events mark a step in the PPG signal.
///
/// Types 1/2 are module M2 (channel 1), types 3/4 module M1 (channel 9); the
/// LED codes in `arg` are that module's LEDs. A lift change is shared by both
/// modules, so it arrives as one M2 event and one M1 event.
final class EventSample extends DblkSample {
  const EventSample(this.type, this.code, this.arg);
  final int type, code, arg;

  static const int typePpgStart = 1;
  static const int typePpgGain = 2;
  static const int typePpgStartM1 = 3;
  static const int typePpgGainM1 = 4;

  /// A PPG START/GAIN event for either module.
  bool get isPpgGain =>
      type == typePpgStart ||
      type == typePpgGain ||
      type == typePpgStartM1 ||
      type == typePpgGainM1;

  /// A START (rather than GAIN) event, either module.
  bool get isPpgStart => type == typePpgStart || type == typePpgStartM1;

  /// The event is for module M1 (types 3/4).
  bool get isM1 => type == typePpgStartM1 || type == typePpgGainM1;

  /// The PPG channel whose signal this event steps: [DblkChannel.ppg] or
  /// [DblkChannel.ppgM1]; null for a non-PPG event.
  int? get ppgChannel =>
      !isPpgGain ? null : (isM1 ? DblkChannel.ppgM1 : DblkChannel.ppg);

  /// LED settings in force *after* the event (`arg` = lift | g<<8 | r<<16 | ir<<24).
  int get lift => arg & 0xFF;
  int get green => (arg >> 8) & 0xFF;
  int get red => (arg >> 16) & 0xFF;
  int get ir => (arg >> 24) & 0xFF;

  /// Which settings changed, from `code` (0x1 lift, 0x2 green, 0x4 red, 0x8 ir).
  List<String> get changed => [
    if (code & 0x1 != 0) 'lift',
    if (code & 0x2 != 0) 'green',
    if (code & 0x4 != 0) 'red',
    if (code & 0x8 != 0) 'ir',
  ];

  /// Human-readable, matching dblk.py's `describe_event` in substance.
  String describe() {
    if (!isPpgGain) {
      return 'event $type code $code arg 0x${arg.toRadixString(16)}';
    }
    final kind = '${isPpgStart ? 'PPG start' : 'PPG gain'}${isM1 ? ' M1' : ''}';
    return '$kind [${changed.join(',')}] lift $lift G $green R $red IR $ir';
  }
}

// --- Frame -------------------------------------------------------------------

/// Why a frame was rejected.
enum DblkError {
  /// Fewer than 28 bytes, or fewer than `block_len`.
  truncated,

  /// First four bytes are not "DBLK".
  badMagic,

  /// `block_len` is below 32 or above [kDblkMaxBlockLen].
  badLength,

  /// `block_len - 32` is not `sample_count` whole samples.
  sampleCountMismatch,

  /// Stored CRC-32 disagrees with the bytes.
  badCrc,

  /// A known channel whose derived per-sample size is not the size this app
  /// decodes — the firmware struct changed and the app was not updated.
  layoutMismatch,
}

/// Result of [DblkFrame.parse]: exactly one of [DblkOk] / [DblkBad].
sealed class DblkParse {
  const DblkParse();
}

final class DblkOk extends DblkParse {
  const DblkOk(this.frame);
  final DblkFrame frame;
}

final class DblkBad extends DblkParse {
  const DblkBad(this.error, this.detail);
  final DblkError error;
  final String detail;

  @override
  String toString() => 'DblkBad(${error.name}: $detail)';
}

/// One verified frame.
final class DblkFrame {
  DblkFrame._({
    required this.blockLen,
    required this.seq,
    required this.tNs,
    required this.channel,
    required this.flags,
    required this.sampleCount,
    required this.sampleRate,
    required this.reserved,
    required this.payload,
    required this.crc,
  });

  final int blockLen;
  final int seq;

  /// Device-monotonic nanoseconds of the first sample.
  final int tNs;
  final int channel;
  final int flags;
  final int sampleCount;

  /// Nominal rate in Hz as the producer declares it (0 for event channels).
  final int sampleRate;
  final int reserved;

  /// The `sample_count x sampleSize` bytes between header and CRC.
  final Uint8List payload;
  final int crc;

  bool get gapBefore => flags & kDblkFlagGapBefore != 0;
  bool get synthetic => flags & kDblkFlagSynthetic != 0;
  bool get isKnownChannel => DblkChannel.isKnown(channel);
  String get channelName => DblkChannel.name(channel);

  /// Derived, not looked up: `(block_len - 32) / sample_count`.
  int get sampleSize => sampleCount == 0 ? 0 : payload.length ~/ sampleCount;

  /// Parse one frame starting at [offset] in [bytes]. Bytes after the frame
  /// are ignored; the frame's length is [DblkFrame.blockLen]. Never throws.
  static DblkParse parse(Uint8List bytes, [int offset = 0]) {
    final avail = bytes.length - offset;
    if (offset < 0 || avail < kDblkHeaderSize) {
      return DblkBad(
        DblkError.truncated,
        '$avail B available, header needs $kDblkHeaderSize',
      );
    }
    final bd = ByteData.sublistView(bytes, offset);
    final magic = bd.getUint32(0, Endian.little);
    if (magic != kDblkMagic) {
      return DblkBad(
        DblkError.badMagic,
        'magic 0x${magic.toRadixString(16).padLeft(8, '0')}',
      );
    }
    final blockLen = bd.getUint32(4, Endian.little);
    if (blockLen < kDblkOverhead || blockLen > kDblkMaxBlockLen) {
      return DblkBad(DblkError.badLength, 'implausible block_len $blockLen');
    }
    if (avail < blockLen) {
      return DblkBad(
        DblkError.truncated,
        '$avail B available, block_len $blockLen',
      );
    }
    final seq = bd.getUint32(8, Endian.little);
    final tNs = bd.getUint64(12, Endian.little);
    final channel = bd.getUint8(20);
    final flags = bd.getUint8(21);
    final sampleCount = bd.getUint16(22, Endian.little);
    final sampleRate = bd.getUint16(24, Endian.little);
    final reserved = bd.getUint16(26, Endian.little);

    final payloadLen = blockLen - kDblkOverhead;
    final consistent =
        sampleCount == 0 ? payloadLen == 0 : payloadLen % sampleCount == 0;
    if (!consistent) {
      return DblkBad(
        DblkError.sampleCountMismatch,
        '$payloadLen B payload is not $sampleCount whole samples',
      );
    }

    final bodyEnd = blockLen - kDblkCrcSize;
    final want = bd.getUint32(bodyEnd, Endian.little);
    final got = Crc32.compute(
      Uint8List.sublistView(bytes, offset, offset + bodyEnd),
    );
    if (want != got) {
      return DblkBad(
        DblkError.badCrc,
        'crc ${_hex(got)} != stored ${_hex(want)}',
      );
    }

    final known = DblkChannel.sampleSize[channel];
    if (known != null &&
        sampleCount > 0 &&
        payloadLen ~/ sampleCount != known) {
      return DblkBad(
        DblkError.layoutMismatch,
        '${DblkChannel.name(channel)}: frame says '
        '${payloadLen ~/ sampleCount} B/sample, app decodes $known B',
      );
    }

    return DblkOk(
      DblkFrame._(
        blockLen: blockLen,
        seq: seq,
        tNs: tNs,
        channel: channel,
        flags: flags,
        sampleCount: sampleCount,
        sampleRate: sampleRate,
        reserved: reserved,
        // Copy: universal_ble hands back views into a larger, reused buffer.
        payload: Uint8List.fromList(
          Uint8List.sublistView(
            bytes,
            offset + kDblkHeaderSize,
            offset + bodyEnd,
          ),
        ),
        crc: want,
      ),
    );
  }

  /// Typed samples; empty for an unknown channel. [parse] has already checked
  /// the size, so this cannot misread.
  List<DblkSample> get samples {
    if (!isKnownChannel || sampleCount == 0) return const [];
    final bd = ByteData.sublistView(payload);
    final n = sampleSize;
    const le = Endian.little;
    return List<DblkSample>.generate(sampleCount, (i) {
      final o = i * n;
      return switch (channel) {
        DblkChannel.ppg || DblkChannel.ppgM1 => PpgSample(
          bd.getInt32(o, le),
          bd.getInt32(o + 4, le),
          bd.getInt32(o + 8, le),
        ),
        DblkChannel.acc => AccSample(
          bd.getInt16(o, le),
          bd.getInt16(o + 2, le),
          bd.getInt16(o + 4, le),
          bd.getUint16(o + 6, le),
        ),
        DblkChannel.rr => RrSample(
          bd.getUint16(o, le),
          bd.getUint8(o + 2),
          bd.getUint8(o + 3),
          bd.getUint32(o + 4, le),
        ),
        DblkChannel.vitals => VitalsSample(
          hrBpmRaw: bd.getUint16(o, le),
          spo2X10Raw: bd.getUint16(o + 2, le),
          respBpmRaw: bd.getUint16(o + 4, le),
          tempCX100Raw: bd.getInt16(o + 6, le),
          rmssdX10Raw: bd.getUint16(o + 8, le),
          sdnnX10Raw: bd.getUint16(o + 10, le),
          quality: bd.getUint8(o + 12),
          activity: bd.getUint8(o + 13),
        ),
        DblkChannel.temp => TempSample(
          bd.getInt16(o, le),
          bd.getUint16(o + 2, le),
        ),
        DblkChannel.event => EventSample(
          bd.getUint16(o, le),
          bd.getUint16(o + 2, le),
          bd.getUint32(o + 4, le),
        ),
        _ => throw StateError('unreachable: channel $channel is known'),
      };
    });
  }

  /// Convenience typed views.
  /// PPG samples of either module; empty for any other channel.
  List<PpgSample> get ppg => samples.whereType<PpgSample>().toList();
  List<AccSample> get acc => samples.whereType<AccSample>().toList();
  List<EventSample> get events => samples.whereType<EventSample>().toList();

  static String _hex(int v) => v.toRadixString(16).padLeft(8, '0');

  @override
  String toString() =>
      'DblkFrame($channelName seq=$seq t_ns=$tNs '
      'n=$sampleCount@${sampleRate}Hz flags=0x${flags.toRadixString(16)})';
}

// --- Stream tracker ----------------------------------------------------------

/// A frame accepted by [DblkStreamTracker], with what the tracker learned
/// about the stream just before it.
final class DblkTracked {
  const DblkTracked(this.frame, this.lostBefore);
  final DblkFrame frame;

  /// Frames of this channel missing between the previous one and this one
  /// (a seq gap). 0 when contiguous or on the channel's first frame.
  final int lostBefore;

  /// Anything that should break the trace here: the producer's own
  /// GAP_BEFORE, or frames lost on the way.
  bool get discontinuity => frame.gapBefore || lostBefore > 0;
}

/// Per-channel stream counters.
final class DblkChannelStats {
  int frames = 0;
  int samples = 0;

  /// Frames lost, from seq gaps.
  int lostFrames = 0;

  /// Frames carrying the producer's GAP_BEFORE flag.
  int gapBeforeFrames = 0;
  int? lastSeq;

  /// (t_ns, sample_count) of recent frames, for [measuredRateHz].
  final List<(int, int)> _window = [];

  /// Sample rate measured from the device's own clock over recent contiguous
  /// frames: samples in all but the newest frame over the t_ns span they cover.
  /// Null until two contiguous frames with advancing t_ns have arrived.
  double? get measuredRateHz {
    if (_window.length < 2) return null;
    final span = _window.last.$1 - _window.first.$1;
    if (span <= 0) return null;
    var n = 0;
    for (var i = 0; i < _window.length - 1; i++) {
      n += _window[i].$2;
    }
    return n * 1e9 / span;
  }
}

/// Counts what a live DBLK stream is doing, for evaluation: frames per
/// channel, lost frames (seq gaps), CRC and format errors, unknown channels,
/// SYNTHETIC frames, and the sample rate measured from `t_ns`.
///
/// Pure: no clock, no radio. Feed it each notification with [ingest].
class DblkStreamTracker {
  DblkStreamTracker({this.rateWindowFrames = 32});

  /// How many recent frames [DblkChannelStats.measuredRateHz] averages over.
  final int rateWindowFrames;

  final Map<int, DblkChannelStats> channels = {};

  int frames = 0;
  int crcErrors = 0;

  /// Every rejection other than a CRC failure (magic, length, truncation,
  /// sample-count or layout mismatch).
  int formatErrors = 0;

  /// Frames on a channel this app does not decode (skipped, not an error).
  int unknownChannelFrames = 0;
  int syntheticFrames = 0;
  DblkError? lastError;
  String? lastErrorDetail;

  /// The most recent PPG START/GAIN event for module **M2** (types 1/2), and
  /// its device time.
  EventSample? lastGainEvent;
  int? lastGainEventTNs;

  /// The most recent PPG START/GAIN event for module **M1** (types 3/4), and
  /// its device time. Null on firmware without the second module.
  EventSample? lastGainEventM1;
  int? lastGainEventM1TNs;

  /// The last gain event for [ppgChannel] ([DblkChannel.ppg] or
  /// [DblkChannel.ppgM1]).
  EventSample? lastGainFor(int ppgChannel) =>
      ppgChannel == DblkChannel.ppgM1 ? lastGainEventM1 : lastGainEvent;

  int get lostFrames => channels.values.fold(0, (a, c) => a + c.lostFrames);

  DblkChannelStats channel(int ch) =>
      channels.putIfAbsent(ch, DblkChannelStats.new);

  /// Parse one notification. Normally exactly one frame; if a platform ever
  /// coalesces several whole frames, each is taken in turn. A malformed frame
  /// is counted and the rest of the notification is dropped — there is no
  /// in-notification resync, because frames are never split across
  /// notifications, so the next one starts clean.
  List<DblkTracked> ingest(Uint8List bytes) {
    final out = <DblkTracked>[];
    var off = 0;
    while (off < bytes.length) {
      final r = DblkFrame.parse(bytes, off);
      switch (r) {
        case DblkBad(:final error, :final detail):
          if (error == DblkError.badCrc) {
            crcErrors++;
          } else {
            formatErrors++;
          }
          lastError = error;
          lastErrorDetail = detail;
          return out;
        case DblkOk(:final frame):
          out.add(_accept(frame));
          off += frame.blockLen;
      }
    }
    return out;
  }

  DblkTracked _accept(DblkFrame f) {
    frames++;
    if (f.synthetic) syntheticFrames++;
    if (!f.isKnownChannel) unknownChannelFrames++;

    final cs = channel(f.channel);
    cs.frames++;
    cs.samples += f.sampleCount;
    if (f.gapBefore) cs.gapBeforeFrames++;

    var lost = 0;
    final prev = cs.lastSeq;
    if (prev != null) {
      final delta = (f.seq - prev) & 0xFFFFFFFF; // u32 wrap-safe
      if (delta == 0 || delta >= 0x80000000) {
        // Repeat or regression: the producer restarted. Not a loss — and the
        // old t_ns baseline is meaningless now.
        cs._window.clear();
      } else {
        lost = delta - 1;
      }
    }
    cs.lastSeq = f.seq;
    cs.lostFrames += lost;

    // Rate window: only across contiguous frames on an advancing clock.
    final w = cs._window;
    if (lost > 0 || f.gapBefore || (w.isNotEmpty && f.tNs <= w.last.$1)) {
      w.clear();
    }
    w.add((f.tNs, f.sampleCount));
    while (w.length > rateWindowFrames) {
      w.removeAt(0);
    }

    if (f.channel == DblkChannel.event) {
      for (final e in f.events) {
        if (!e.isPpgGain) continue;
        if (e.isM1) {
          lastGainEventM1 = e;
          lastGainEventM1TNs = f.tNs;
        } else {
          lastGainEvent = e;
          lastGainEventTNs = f.tNs;
        }
      }
    }
    return DblkTracked(f, lost);
  }

  void reset() {
    channels.clear();
    frames = crcErrors = formatErrors = 0;
    unknownChannelFrames = syntheticFrames = 0;
    lastError = null;
    lastErrorDetail = null;
    lastGainEvent = null;
    lastGainEventTNs = null;
    lastGainEventM1 = null;
    lastGainEventM1TNs = null;
  }
}
