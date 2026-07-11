import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../globals.dart';
import '../models/device_info.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/adaptive/breakpoints.dart';
import '../ui/charts/hpi_sweep_waveform.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';

/// Live signals (handoff 1f; 4b dual-signal on tablets).
///
/// Streams the selected signal over the custom GATT characteristics via
/// [ConnectionManager] — the same primitives the legacy live screen uses
/// (subscribe + host-endian Int32/Uint32 parse) — and renders it with the
/// monitor-style sweep. On expanded widths two channels stack on a shared
/// timebase (4b). Stat values that need derivation the app doesn't do yet
/// (RR interval, leads-on) are shown as "—" rather than invented.
class ScrLive extends StatefulWidget {
  const ScrLive({super.key});

  @override
  State<ScrLive> createState() => _ScrLiveState();
}

/// A streamable signal: its GATT route, sample decoding, and identity color.
enum LiveSignal { ecg, ppg, gsr }

extension on LiveSignal {
  String get label => switch (this) {
        LiveSignal.ecg => 'ECG',
        LiveSignal.ppg => 'PPG',
        LiveSignal.gsr => 'GSR',
      };

  Color get color => switch (this) {
        LiveSignal.ecg => HpiColors.hr,
        LiveSignal.ppg => HpiColors.spo2,
        LiveSignal.gsr => HpiColors.eda,
      };

  String get service => switch (this) {
        LiveSignal.ecg => hPi4Global.UUID_ECG_SERVICE,
        LiveSignal.ppg => hPi4Global.UUID_SERV_PPG,
        LiveSignal.gsr => hPi4Global.UUID_ECG_SERVICE,
      };

  String get characteristic => switch (this) {
        LiveSignal.ecg => hPi4Global.UUID_ECG_CHAR,
        LiveSignal.ppg => hPi4Global.UUID_CHAR_PPG,
        LiveSignal.gsr => hPi4Global.UUID_GSR_CHAR,
      };

  String get caption => switch (this) {
        LiveSignal.ecg => 'LEAD I · 128 SPS',
        LiveSignal.ppg => 'PPG · 25 SPS',
        LiveSignal.gsr => 'GSR · 32 SPS',
      };

  /// Decode a notification payload into samples. Copy into a fresh, offset-0
  /// buffer first: universal_ble hands back views into a larger buffer, so
  /// reinterpreting `value.buffer` directly would be misaligned.
  List<double> decode(Uint8List value) {
    final bytes = Uint8List.fromList(value);
    return switch (this) {
      LiveSignal.ecg =>
        bytes.buffer.asInt32List().map((e) => e.toDouble()).toList(),
      LiveSignal.ppg =>
        bytes.buffer.asUint32List().map((e) => e.toDouble()).toList(),
      LiveSignal.gsr =>
        bytes.buffer.asInt32List().map((e) => e.toDouble()).toList(),
    };
  }
}

class _ScrLiveState extends State<ScrLive> {
  final _cm = ConnectionManager.instance;

  DeviceInfo? _device;
  bool _resolving = true;
  String? _error;

  LiveSignal _primary = LiveSignal.ecg;

  /// Second channel, shown only on expanded layouts (4b).
  LiveSignal? _secondary;

  final _buffers = <LiveSignal, SweepBuffer>{};
  final _subs = <LiveSignal, StreamSubscription<Uint8List>>{};

  @override
  void initState() {
    super.initState();
    _cm.addListener(_onLink);
    // Kept alive in the shell's IndexedStack — re-resolve when pairing changes.
    DeviceManager.pairingRevision.addListener(_init);
    _init();
  }

  @override
  void dispose() {
    _cm.removeListener(_onLink);
    DeviceManager.pairingRevision.removeListener(_init);
    for (final s in _subs.values) {
      s.cancel();
    }
    for (final b in _buffers.values) {
      b.dispose();
    }
    // Leave the link itself alone — ConnectionManager owns it and other flows
    // (sync, DFU) may still need it.
    unawaited(_unsubscribeAll());
    super.dispose();
  }

  void _onLink() {
    if (!mounted) return;
    setState(() {});
    if (!_cm.isConnected) {
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
    }
  }

  Future<void> _init() async {
    final device = await DeviceManager.getPairedDevice();
    if (!mounted) return;
    setState(() {
      _device = device;
      _resolving = false;
    });
    if (device != null && _cm.isConnected) _startAll();
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
      _startAll();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _startAll() {
    _start(_primary);
    final s = _secondary;
    if (s != null) _start(s);
  }

  void _start(LiveSignal signal) {
    if (!_cm.isConnected || _subs.containsKey(signal)) return;
    final buffer = _buffers.putIfAbsent(signal, () => SweepBuffer());
    try {
      _subs[signal] = _cm
          .subscribe(signal.service, signal.characteristic)
          .listen(
        (value) => buffer.addAll(signal.decode(value)),
        onError: (Object e) => debugPrint('live ${signal.label}: $e'),
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _stop(LiveSignal signal) async {
    await _subs.remove(signal)?.cancel();
    _buffers[signal]?.clear();
    if (_cm.isConnected) {
      await _cm
          .unsubscribe(signal.service, signal.characteristic)
          .catchError((_) {});
    }
  }

  Future<void> _unsubscribeAll() async {
    for (final signal in _buffers.keys.toList()) {
      if (_cm.isConnected) {
        await _cm
            .unsubscribe(signal.service, signal.characteristic)
            .catchError((_) {});
      }
    }
  }

  Future<void> _selectPrimary(LiveSignal signal) async {
    if (signal == _primary) return;
    final old = _primary;
    setState(() => _primary = signal);
    await _stop(old);
    _start(signal);
  }

  Future<void> _toggleSecondary(LiveSignal signal) async {
    if (_secondary == signal) {
      setState(() => _secondary = null);
      await _stop(signal);
    } else {
      final old = _secondary;
      setState(() => _secondary = signal);
      if (old != null) await _stop(old);
      _start(signal);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Center(child: CircularProgressIndicator(color: HpiColors.hr));
    }
    if (_device == null) return _noDevice();

    final expanded = Breakpoints.isExpanded(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(expanded),
            const SizedBox(height: 12),
            if (!_cm.isConnected)
              Expanded(child: _disconnected())
            else ...[
              Expanded(child: _waveformCard(_primary)),
              if (expanded && _secondary != null) ...[
                const SizedBox(height: 12),
                Expanded(child: _waveformCard(_secondary!)),
              ],
              const SizedBox(height: 12),
              _statsRow(expanded),
              if (expanded) ...[
                const SizedBox(height: 8),
                Text(
                  'Both channels share a t_ms timebase — exported CSVs align '
                  'row-for-row for correlation studies.',
                  style: HpiText.supporting,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(bool expanded) {
    return Row(
      children: [
        Text('Live signals', style: HpiText.screenTitle),
        const Spacer(),
        for (final s in LiveSignal.values) ...[
          _signalChip(s, expanded),
          const SizedBox(width: 6),
        ],
        HpiPill(
          label: _cm.isConnected ? 'CONNECTED' : 'OFFLINE',
          color: _cm.isConnected ? HpiColors.steps : HpiColors.muted,
        ),
      ],
    );
  }

  /// Tap selects the primary channel. On expanded layouts a long-press adds the
  /// signal as the stacked second channel (4b).
  Widget _signalChip(LiveSignal s, bool expanded) {
    final isPrimary = _primary == s;
    final isSecondary = _secondary == s;
    final active = isPrimary || isSecondary;
    return GestureDetector(
      onTap: () => _selectPrimary(s),
      onLongPress: expanded && !isPrimary ? () => _toggleSecondary(s) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? HpiMetricColors.tint(s.color, 0.18)
              : HpiColors.chipBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          s.label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: active ? s.color : HpiColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _waveformCard(LiveSignal s) {
    final buffer = _buffers.putIfAbsent(s, () => SweepBuffer());
    return HpiCard(
      waveform: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(s.label,
                  style: HpiText.sectionLabel.copyWith(color: s.color)),
              const Spacer(),
              Text(s.caption, style: HpiText.mono.copyWith(fontSize: 9.5)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: HpiSweepWaveform(buffer: buffer, color: s.color)),
        ],
      ),
    );
  }

  Widget _statsRow(bool expanded) {
    return Row(
      children: [
        // HR/RR derivation from the live trace isn't implemented — show "—"
        // rather than a fabricated number.
        const Expanded(child: HpiStatChip(value: '—', label: 'BPM')),
        const SizedBox(width: 10),
        const Expanded(child: HpiStatChip(value: '—', label: 'RR-int ms')),
        const SizedBox(width: 10),
        Expanded(
          child: HpiStatChip(
            value: _cm.isConnected ? 'ON' : 'OFF',
            label: 'Link',
            valueColor: _cm.isConnected ? HpiColors.steps : HpiColors.muted,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: expanded ? 240 : 150,
          child: HpiFilledButton(
            label: 'Record 30 s',
            icon: Symbols.fiber_manual_record,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'On-device recording is started from the Recordings tab.'),
              ),
            ),
          ),
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
          Text('Connect to ${_device!.displayName} to see live signals.',
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
