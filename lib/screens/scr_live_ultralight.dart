// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../ble/dblk_frame.dart';
import '../globals.dart';
import '../models/device_info.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/charts/hpi_sweep_waveform.dart';
import '../ui/components/hpi_components.dart';
import '../ui/components/hpi_synthetic_banner.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';

/// Live tab for the **Move Ultralight**: the DBLK stream on characteristic
/// `0x2002` (docs/internal/ULTRALIGHT_SHARED_APP_DESIGN.md §4.2).
///
/// Built for evaluating the band's PPG: green, red and IR as sweep traces, ACC
/// as a secondary trace, and a stats row (negotiated MTU, frames/s, the PPG
/// rate measured on the device's own clock, lost frames, CRC errors, the last
/// gain event) so a bad link or a bad producer is visible rather than inferred
/// from a funny-looking waveform.
///
/// **Two LED modules.** Channel 1 is module M2; firmware with the second module
/// also sends channel 9, module M1, from the same AFE frames. Once a channel-9
/// frame arrives, a selector (M2 / M1 / Both, default Both) appears above the
/// traces; "Both" puts M2 and M1 side by side, one row per LED colour, so the
/// same wavelength from the two modules lines up for comparison. Until then —
/// and always, on older firmware — the screen is the single-module layout.
///
/// **Subscribing is what makes the band stream** — the firmware starts PPG on
/// the first subscriber and stops it on the last unsubscribe, LEDs and all. So
/// this screen subscribes only while it is the visible tab ([active]), the app
/// is in the foreground, and the link is up, and unsubscribes the moment any of
/// those stops being true. Leaving it subscribed from a hidden tab in the
/// shell's `IndexedStack` would drain the band's battery for nobody.
class ScrLiveUltralight extends StatefulWidget {
  const ScrLiveUltralight({super.key, required this.active});

  /// True while the Live tab is the one on screen.
  final bool active;

  @override
  State<ScrLiveUltralight> createState() => _ScrLiveUltralightState();
}

/// Frames are ≤176 B on current firmware (older builds sent up to 236 B), and
/// a notification carries MTU − 3 bytes.
const int _kMinUsefulMtu = 176 + 3;

/// ~8 s of 50 Hz on screen.
const int _kSweepCapacity = 400;

/// Which PPG module(s) to draw, once module M1 (channel 9) has been seen.
enum _ModuleView { m2, m1, both }

class _ScrLiveUltralightState extends State<ScrLiveUltralight>
    with WidgetsBindingObserver {
  final _cm = ConnectionManager.instance;
  final _tracker = DblkStreamTracker();

  DeviceInfo? _device;
  bool _resolving = true;
  String? _error;

  StreamSubscription<Uint8List>? _sub;
  bool _starting = false;

  /// An in-flight [_stop]. A start waits for it: otherwise a quick tab
  /// away-and-back could subscribe first and then have the old unsubscribe
  /// land on top, leaving a dead stream on a screen that looks live.
  Future<void>? _stopping;
  bool _foreground = true;
  DateTime? _startedAt;
  DateTime? _lastFrameAt;

  int? _mtu;

  /// Frames per second over the last tick, computed on the host clock.
  double? _fps;
  int _fpsFrames = 0;
  DateTime? _fpsAt;
  Timer? _ticker;

  // Module M2, channel 1.
  final _green = _Trace('GREEN', HpiColors.steps, module: 'M2');
  final _red = _Trace('RED', HpiColors.bpSys, module: 'M2');
  final _ir = _Trace('IR', HpiColors.stress, module: 'M2');
  // Module M1, channel 9. Same colours; the label and column tell them apart.
  final _greenM1 = _Trace('GREEN', HpiColors.steps, module: 'M1');
  final _redM1 = _Trace('RED', HpiColors.bpSys, module: 'M1');
  final _irM1 = _Trace('IR', HpiColors.stress, module: 'M1');
  final _acc = _Trace('ACC |a|', HpiColors.onSurfaceVariant);

  List<_Trace> get _ppgTraces => [_green, _red, _ir];
  List<_Trace> get _ppgTracesM1 => [_greenM1, _redM1, _irM1];
  List<_Trace> get _allTraces => [..._ppgTraces, ..._ppgTracesM1, _acc];

  /// The traces a gain event on [ppgChannel] steps.
  List<_Trace> _tracesFor(int ppgChannel) =>
      ppgChannel == DblkChannel.ppgM1 ? _ppgTracesM1 : _ppgTraces;

  _ModuleView _view = _ModuleView.both;

  /// A channel-9 frame has arrived this session: the band has module M1.
  /// False for the whole session on older firmware, which keeps the screen in
  /// its single-module layout.
  bool get _hasM1 =>
      (_tracker.channels[DblkChannel.ppgM1]?.frames ?? 0) > 0;

  bool get _shouldStream =>
      widget.active && _foreground && _cm.isConnected && _device != null;

  // --- Lifecycle --------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cm.addListener(_onLink);
    DeviceManager.pairingRevision.addListener(_init);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _init();
  }

  @override
  void didUpdateWidget(ScrLiveUltralight old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _reconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is a transient overlay (control centre, a system sheet): the
    // app is still on screen, so keep streaming. Hidden or paused is not.
    final fg = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      _ => false,
    };
    if (fg == _foreground) return;
    _foreground = fg;
    _reconcile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cm.removeListener(_onLink);
    DeviceManager.pairingRevision.removeListener(_init);
    _ticker?.cancel();
    unawaited(_stop());
    for (final t in _allTraces) {
      t.buffer.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final device = await DeviceManager.getPairedDevice();
    if (!mounted) return;
    setState(() {
      _device = device;
      _resolving = false;
    });
    _reconcile();
  }

  void _onLink() {
    if (!mounted) return;
    if (!_cm.isConnected && _sub != null) {
      // The link is gone, and the notify subscription with it; there is
      // nothing to unsubscribe from. Just drop our side.
      unawaited(_sub?.cancel());
      _sub = null;
      _clearLiveSynthetic();
    }
    setState(() {});
    _reconcile();
  }

  /// Bring the subscription in line with [_shouldStream].
  void _reconcile() {
    if (_shouldStream) {
      if (_sub == null) unawaited(_start());
    } else if (_sub != null) {
      unawaited(_stop());
    }
  }

  // --- Streaming --------------------------------------------------------------

  Future<void> _start() async {
    if (_starting || _sub != null) return;
    _starting = true;
    try {
      await _stopping;
      _tracker.reset();
      for (final t in _allTraces) {
        t.reset();
      }
      _fps = null;
      _fpsFrames = 0;
      _fpsAt = DateTime.now();
      _lastFrameAt = null;
      _error = null;

      // MTU before subscribing: the band drops (and counts) any frame that
      // does not fit the current MTU, so subscribing on the 23-byte default
      // loses every frame until the exchange completes. On Apple this is
      // OS-managed and just reports the value — which settles *late*, so
      // [_tick] re-reads it for the first few seconds.
      _mtu = await _cm.requestMtu(512);
      // Low-latency interval while streaming (Android; no-op elsewhere).
      await _cm.requestConnectionPriority(high: true);

      if (!mounted || !_shouldStream || _sub != null) {
        // Left (or backgrounded) while we were negotiating: hand the
        // low-latency interval back rather than holding it for nobody.
        if (_sub == null && _cm.isConnected) {
          await _cm.requestConnectionPriority(high: false);
        }
        return;
      }
      _sub = _cm
          .subscribe(
        hPi4Global.UUID_SERV_UL_STREAM,
        hPi4Global.UUID_CHAR_UL_DBLK,
        onSubscribeError: (e) {
          if (mounted) setState(() => _error = 'Could not start stream: $e');
        },
      )
          .listen(
        _onNotification,
        onError: (Object e) {
          if (mounted) setState(() => _error = 'Stream error: $e');
        },
      );
      _startedAt = DateTime.now();
      _cm.setStreaming(true);
    } catch (e) {
      _error = '$e';
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stop() {
    final f = _stopping = _doStop();
    return f.whenComplete(() {
      if (identical(_stopping, f)) _stopping = null;
    });
  }

  Future<void> _doStop() async {
    final sub = _sub;
    _sub = null;
    _startedAt = null;
    _cm.setStreaming(false);
    _clearLiveSynthetic();
    if (sub == null) return;
    await sub.cancel();
    if (_cm.isConnected) {
      // This unsubscribe is what tells the band to stop PPG.
      await _cm
          .unsubscribe(hPi4Global.UUID_SERV_UL_STREAM,
              hPi4Global.UUID_CHAR_UL_DBLK)
          .catchError((_) {});
      await _cm.requestConnectionPriority(high: false);
    }
    if (mounted) setState(() {});
  }

  void _clearLiveSynthetic() {
    // Only clear what we raised — never the developer preview flag.
    HpiSyntheticBanner.liveSyntheticSource.value = null;
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_sub != null) {
      final at = _fpsAt;
      if (at != null) {
        final dt = now.difference(at).inMicroseconds / 1e6;
        if (dt > 0) _fps = (_tracker.frames - _fpsFrames) / dt;
      }
      _fpsFrames = _tracker.frames;
      _fpsAt = now;
      // The MTU exchange completes after connect on iOS/macOS; keep reading it
      // for the first few seconds so the stat shows the settled value.
      final started = _startedAt;
      if (started != null && now.difference(started).inSeconds <= 6) {
        _cm.requestMtu(512).then((m) {
          if (m != null && mounted) _mtu = m;
        });
      }
    }
    if (_cm.isConnected) setState(() {});
  }

  void _onNotification(Uint8List value) {
    _lastFrameAt = DateTime.now();
    final hadM1 = _hasM1;
    for (final t in _tracker.ingest(value)) {
      final f = t.frame;
      if (f.synthetic && HpiSyntheticBanner.liveSyntheticSource.value == null) {
        HpiSyntheticBanner.liveSyntheticSource.value =
            _device?.displayName ?? 'Move Ultralight';
      }
      switch (f.channel) {
        // Each module's traces take only their own channel's frames, so a seq
        // gap or GAP_BEFORE on one breaks that module's traces and no others.
        case DblkChannel.ppg || DblkChannel.ppgM1:
          final s = f.ppg;
          final tr = _tracesFor(f.channel);
          tr[0].push(t, [for (final p in s) p.green.toDouble()]);
          tr[1].push(t, [for (final p in s) p.red.toDouble()]);
          tr[2].push(t, [for (final p in s) p.ir.toDouble()]);
        case DblkChannel.acc:
          _acc.push(t, [
            for (final a in f.acc)
              math.sqrt((a.x * a.x + a.y * a.y + a.z * a.z).toDouble()),
          ]);
        case DblkChannel.event:
          for (final e in f.events) {
            // A gain change is a step in the PPG DC. Let the baseline catch
            // up quickly from the moment it takes effect, so the step does not
            // ring through the AC trace for seconds. Only the module the event
            // names: a shared lift change arrives as one event per module.
            final ch = e.ppgChannel;
            if (ch != null) {
              for (final tr in _tracesFor(ch)) {
                tr.settleFrom(f.tNs);
              }
            }
          }
        default:
          break; // counted by the tracker; nothing to draw
      }
    }
    // First M1 frame: switch to the two-module layout now, not on the next tick.
    if (!hadM1 && _hasM1 && mounted) setState(() {});
  }

  Future<void> _connect() async {
    final device = _device;
    if (device == null) return;
    setState(() {
      _error = null;
      _resolving = true;
    });
    try {
      await _cm.connect(device.macAddress, name: device.displayName);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
    _reconcile();
  }

  // --- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Center(child: CircularProgressIndicator(color: HpiColors.hr));
    }
    if (_device == null) return _noDevice();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 12),
            if (!_cm.isConnected)
              Expanded(child: _disconnected())
            else ...[
              if (_hasM1) ...[
                HpiSegmentedControl(
                  segments: const ['M2', 'M1', 'Both'],
                  selectedIndex: _view.index,
                  onChanged: (i) =>
                      setState(() => _view = _ModuleView.values[i]),
                  accent: HpiColors.steps,
                ),
                const SizedBox(height: 8),
              ],
              for (var i = 0; i < 3; i++) ...[
                Expanded(flex: 3, child: _ppgRow(i)),
                const SizedBox(height: 8),
              ],
              Expanded(flex: 2, child: _traceCard(_acc)),
              const SizedBox(height: 10),
              _stats(),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style: HpiText.supporting.copyWith(color: HpiColors.error)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final synthetic = _tracker.syntheticFrames > 0 && _sub != null;
    return Row(
      children: [
        Flexible(child: Text('Live signals', style: HpiText.screenTitle)),
        const Spacer(),
        if (synthetic) ...[
          const HpiPill(label: 'SYNTHETIC', color: HpiColors.error),
          const SizedBox(width: 6),
        ],
        HpiPill(
          label: _sub != null
              ? 'STREAMING'
              : (_cm.isConnected ? 'CONNECTED' : 'OFFLINE'),
          color: _cm.isConnected ? HpiColors.steps : HpiColors.muted,
        ),
      ],
    );
  }

  bool get _waiting {
    final started = _startedAt;
    if (_sub == null || started == null) return false;
    final last = _lastFrameAt ?? started;
    return DateTime.now().difference(last) > const Duration(seconds: 3);
  }

  /// Row [i] (green, red, IR) of the PPG area, per [_view]. Without module M1
  /// this is exactly the single-module card.
  Widget _ppgRow(int i) {
    if (!_hasM1) return _traceCard(_ppgTraces[i]);
    return switch (_view) {
      _ModuleView.m2 => _traceCard(_ppgTraces[i]),
      _ModuleView.m1 => _traceCard(_ppgTracesM1[i]),
      _ModuleView.both => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _traceCard(_ppgTraces[i], compact: true)),
            const SizedBox(width: 8),
            Expanded(child: _traceCard(_ppgTracesM1[i], compact: true)),
          ],
        ),
    };
  }

  /// [compact]: half-width card in the side-by-side layout, with a shorter
  /// DC note so label and note fit a phone's half width.
  Widget _traceCard(_Trace t, {bool compact = false}) {
    final dc = t.lastRaw;
    // The module prefix appears only once there is a second module to tell
    // apart; older firmware keeps the plain "GREEN" label.
    final label =
        _hasM1 && t.module != null ? '${t.module} · ${t.label}' : t.label;
    final note = compact
        ? (dc == null ? 'AC' : 'DC ${dc.round()}')
        : (dc == null ? 'AC · DC removed' : 'DC ${dc.round()} · AC shown');
    final waitingHere = _waiting &&
        t == (_hasM1 && _view == _ModuleView.m1 ? _greenM1 : _green);
    return HpiCard(
      waveform: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HpiText.sectionLabel.copyWith(color: t.color)),
              ),
              const Spacer(),
              Text(
                note,
                maxLines: 1,
                style: HpiText.mono.copyWith(fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: HpiSweepWaveform(
                      buffer: t.buffer, color: t.color, strokeWidth: 1.8),
                ),
                if (waitingHere)
                  Center(
                    child: Text(
                      'Waiting for frames from the band…',
                      style: HpiText.body.copyWith(
                          fontSize: 12, color: HpiColors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final ppg = _tracker.channels[DblkChannel.ppg];
    final rate = ppg?.measuredRateHz;
    final mtu = _mtu;
    final mtuLow = mtu != null && mtu < _kMinUsefulMtu;
    final lost = _tracker.lostFrames;
    final crc = _tracker.crcErrors;
    final fmt = _tracker.formatErrors;
    final gain = _tracker.lastGainEvent;
    final gainM1 = _tracker.lastGainEventM1;
    final hasM1 = _hasM1;

    Widget chip(String value, String label, {Color? color}) => SizedBox(
          width: 104,
          child: HpiStatChip(value: value, label: label, valueColor: color),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(mtu?.toString() ?? '—', 'MTU',
                color: mtuLow ? HpiColors.error : null),
            chip(_fps == null ? '—' : _fps!.toStringAsFixed(1), 'Frames/s'),
            chip(rate == null ? '—' : rate.toStringAsFixed(2), 'PPG Hz'),
            chip('$lost', 'Lost frames',
                color: lost > 0 ? HpiColors.error : null),
            chip('$crc', fmt > 0 ? 'CRC err (+$fmt fmt)' : 'CRC errors',
                color: crc + fmt > 0 ? HpiColors.error : null),
            chip('${_tracker.frames}', 'Frames'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (!hasM1)
              gain == null ? 'Gain: no event yet' : 'Gain: ${gain.describe()}'
            else ...[
              gain == null
                  ? 'Gain M2: no event yet'
                  : 'Gain M2: ${gain.describe()}',
              gainM1 == null
                  ? 'Gain M1: no event yet'
                  : 'Gain M1: ${gainM1.describe()}',
            ],
            if (_tracker.unknownChannelFrames > 0)
              '${_tracker.unknownChannelFrames} unknown-channel frames skipped',
            if (mtuLow)
              'MTU $mtu is below $_kMinUsefulMtu — the band drops frames '
                  'that do not fit',
          ].join('  ·  '),
          style: HpiText.mono.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _disconnected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.ecg_heart, size: 44, color: HpiColors.disabled),
          const SizedBox(height: 12),
          Text('Not streaming', style: HpiText.appBarTitle),
          const SizedBox(height: 6),
          Text('Connect to ${_device!.displayName} to see live PPG.',
              style: HpiText.body.copyWith(fontSize: 12)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: HpiText.supporting.copyWith(color: HpiColors.error)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: HpiFilledButton(
              label: 'Connect',
              icon: Symbols.bluetooth,
              onPressed: _connect,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noDevice() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.ecg_heart, size: 44, color: HpiColors.disabled),
          const SizedBox(height: 12),
          Text('Pair a device to stream live signals',
              style: HpiText.appBarTitle, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: HpiFilledButton(
              label: 'Scan for devices',
              icon: Symbols.search,
              onPressed: () => Navigator.of(context).pushNamed('/scan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One displayed trace: DC removal, gap handling, and its [SweepBuffer].
///
/// PPG counts carry a large DC with the pulse as a small ripple on it, and the
/// sweep auto-scales to its min/max — so plotting raw counts shows a flat line.
/// A first-order high-pass (subtracting an exponential baseline, τ ≈ 1.5 s at
/// 50 Hz) leaves the pulse. The baseline is re-seeded after any gap, and
/// tracks fast for a moment after a gain step, so neither rings.
class _Trace {
  _Trace(this.label, this.color, {this.module});

  final String label;
  final Color color;

  /// 'M2' or 'M1' for a PPG trace; null for ACC.
  final String? module;
  final buffer = SweepBuffer(capacity: _kSweepCapacity, gap: 12);

  double? _baseline;
  double? lastRaw;

  /// Device time up to which the baseline tracks fast (after a gain step).
  int? _settleFrom;

  /// Where the next frame should start if nothing is lost, on the device clock.
  int? _expectedTNs;

  void reset() {
    buffer.clear();
    _baseline = null;
    lastRaw = null;
    _settleFrom = null;
    _expectedTNs = null;
  }

  /// Fast-track the baseline for samples from [tNs] on — a gain change takes
  /// effect at the event's time "plus one frame", per the firmware.
  void settleFrom(int tNs) => _settleFrom = tNs;

  void push(DblkTracked t, List<double> values) {
    final f = t.frame;
    if (values.isEmpty) return;
    final rate = f.sampleRate > 0 ? f.sampleRate : 50;
    final dtNs = 1e9 / rate;

    if (t.discontinuity) {
      // Draw the gap as a gap: blank samples spanning the lost time, measured
      // on the device clock where we can, a token break where we cannot.
      final exp = _expectedTNs;
      var n = 3;
      if (exp != null && f.tNs > exp) {
        n = ((f.tNs - exp) / dtNs).round();
      }
      _addBreak(n.clamp(3, _kSweepCapacity ~/ 4));
      _baseline = null;
    }

    const alphaSlow = 1 / (50 * 1.5);
    const alphaFast = 0.3;
    const settleNs = 600000000; // 0.6 s: covers the "+ one frame" at 50 Hz
    final out = <double>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final ts = f.tNs + (i * dtNs).round();
      final s = _settleFrom;
      final fast = s != null && ts >= s && ts < s + settleNs;
      if (s != null && ts >= s + settleNs) _settleFrom = null;
      final b = _baseline;
      _baseline = b == null ? v : b + (fast ? alphaFast : alphaSlow) * (v - b);
      out.add(v - _baseline!);
    }
    lastRaw = values.last;
    _expectedTNs = f.tNs + (values.length * dtNs).round();
    buffer.addAll(out); // notifies
  }

  /// [SweepBuffer] is reused unchanged (design §4.2), and it has no "append a
  /// blank" call — but a null sample is exactly what its painter treats as a
  /// break. So write a placeholder through the public API and blank it.
  void _addBreak(int n) {
    for (var i = 0; i < n; i++) {
      buffer.add(0);
      buffer.samples[(buffer.head - 1 + buffer.capacity) % buffer.capacity] =
          null;
    }
  }
}
