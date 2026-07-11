import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import '../globals.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/device_manager.dart';
import '../utils/health_store_probe.dart';

/// BLE developer console (handoff 1j). A pushed route behind developer mode.
/// Shows link status, the HealthyPi GATT map (from the app's UUID table), and a
/// live connection-event log. Values that require a live link (MTU, throughput)
/// read from [ConnectionManager] when connected and show "—" otherwise, rather
/// than displaying fabricated numbers.
class ScrBleConsole extends StatefulWidget {
  const ScrBleConsole({super.key});

  @override
  State<ScrBleConsole> createState() => _ScrBleConsoleState();
}

class _ScrBleConsoleState extends State<ScrBleConsole> {
  final _cm = ConnectionManager.instance;
  final List<_LogLine> _log = [];

  HsProbeResult? _probe;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _cm.addListener(_onLink);
    _push('OK', _cm.isConnected
        ? 'link up · ${_cm.deviceName ?? _cm.deviceId ?? "device"}'
        : 'no active link');
  }

  /// The Health Store capability check: HELLO *is* the probe (design doc §6).
  /// Read-only — it never acks, so it cannot drop device data.
  Future<void> _runProbe() async {
    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      setState(() => _push('WARN', 'no paired device'));
      return;
    }
    setState(() {
      _probing = true;
      _push('TX', 'HELLO → ${device.macAddress}');
    });

    final result = await HealthStoreProbe.probe(device.macAddress,
        name: device.displayName);

    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
      if (result.supported) {
        _push('OK',
            'HPI_HS schema=${result.schema} group=${result.group} '
            'dev=${result.dev} head=${result.head} types=${result.typeCount}');
        _push('RX', 'TYPES ${result.types.length} entries · '
            'SUMMARY ${result.summary.length} keys');
        if (!result.mtuOk) {
          _push('WARN',
              'MTU never settled (${result.maxWriteLength}) — transfers will fail');
        }
      } else {
        _push('WARN',
            result.error ?? 'no HPI_HS group — firmware predates the Health Store');
      }
    });
  }

  @override
  void dispose() {
    _cm.removeListener(_onLink);
    super.dispose();
  }

  void _onLink() {
    if (!mounted) return;
    setState(() => _push(
        _cm.isConnected ? 'RX' : 'WARN',
        'link ${_cm.state.name}'
            '${_cm.deviceId != null ? " · ${_cm.deviceId}" : ""}'));
  }

  void _push(String kind, String msg) {
    _log.insert(0, _LogLine(kind, msg));
    if (_log.length > 200) _log.removeLast();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _cm.isConnected;
    return Scaffold(
      backgroundColor: HpiColors.background,
      appBar: AppBar(
        title: const Text('BLE console'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(_cm.deviceId ?? 'no device',
                  style: HpiText.mono.copyWith(fontSize: 10)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _linkStats(connected),
            const SizedBox(height: 16),
            const HpiSectionLabel('HEALTH STORE · HPI_HS 0x1000'),
            _healthStoreCard(),
            const SizedBox(height: 16),
            const HpiSectionLabel('GATT · HPI MOVE SERVICE'),
            _gattCard(),
            const SizedBox(height: 16),
            const HpiSectionLabel('LIVE LOG'),
            _logCard(),
          ],
        ),
      ),
    );
  }

  Widget _linkStats(bool connected) {
    Widget stat(String label, String value, Color c) => Expanded(
          child: HpiCard(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: HpiText.mono.copyWith(fontSize: 13, color: c)),
                const SizedBox(height: 4),
                Text(label, style: HpiText.sectionLabel.copyWith(fontSize: 8.5)),
              ],
            ),
          ),
        );
    // MTU is only known once an SMP session has negotiated it — i.e. after a
    // probe. Until then it is genuinely unknown, so show "—" rather than a
    // plausible-looking constant.
    final mtu = _probe?.maxWriteLength;
    return Row(children: [
      stat('STATUS', connected ? 'UP' : 'DOWN',
          connected ? HpiColors.steps : HpiColors.muted),
      const SizedBox(width: 10),
      stat('MAX WRITE', mtu?.toString() ?? '—',
          (mtu != null && mtu <= 20) ? HpiColors.error : HpiColors.onSurface),
      const SizedBox(width: 10),
      stat('HPI_HS', _probe == null ? '—' : (_probe!.supported ? 'YES' : 'NO'),
          _probe == null
              ? HpiColors.onSurface
              : (_probe!.supported ? HpiColors.steps : HpiColors.error)),
      const SizedBox(width: 10),
      stat('STATE', _cm.state.name.toUpperCase(), HpiColors.spo2),
    ]);
  }

  /// The capability check + the raw capture used to pin the wire shapes.
  Widget _healthStoreCard() {
    final p = _probe;
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p == null
                      ? 'Not probed yet'
                      : p.supported
                          ? 'Health Store supported'
                          : 'Health Store not available',
                  style: HpiText.cardTitle.copyWith(
                    color: p == null
                        ? HpiColors.onSurfaceVariant
                        : (p.supported ? HpiColors.steps : HpiColors.error),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: HpiTonalButton(
                  label: _probing ? 'Probing…' : 'Probe',
                  icon: Symbols.bolt,
                  onPressed: _probing ? null : _runProbe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (p == null)
            Text(
              'Runs HELLO against the paired device. HELLO is the capability '
              'probe — if it answers, the device implements HPI_HS. Read-only: '
              'it never acks, so it cannot drop data.',
              style: HpiText.body.copyWith(fontSize: 11.5),
            )
          else if (!p.supported)
            Text(
              p.error ??
                  'The device did not answer HELLO. Its firmware predates the '
                      'Health Store; the app will keep using the legacy sync path.',
              style: HpiText.supporting.copyWith(color: HpiColors.error),
            )
          else ...[
            _kv('schema', '${p.schema}'),
            _kv('group', '${p.group}'),
            _kv('dev (serial)', p.dev ?? '—'),
            _kv('head (newest seq)', '${p.head}'),
            _kv('types', '${p.typeCount} declared / ${p.types.length} parsed'),
            _kv('max write', '${p.maxWriteLength}',
                warn: !p.mtuOk),
            if (p.types.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('REGISTRY', style: HpiText.sectionLabel),
              const SizedBox(height: 4),
              for (final t in p.types.values)
                Text(
                  '${t.id}  ${t.key}  ${t.unit}  scale=${t.scale}  '
                  '${t.klass.name}${t.derived ? "  derived" : ""}',
                  style: HpiText.mono.copyWith(fontSize: 9.5),
                ),
            ],
            if (p.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('SUMMARY (raw)', style: HpiText.sectionLabel),
              const SizedBox(height: 4),
              for (final e in p.summary.entries)
                Text('${e.key} = ${e.value}',
                    style: HpiText.mono.copyWith(fontSize: 9.5)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool warn = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: HpiText.supporting.copyWith(fontSize: 10.5)),
          ),
          Expanded(
            child: Text(v,
                style: HpiText.mono.copyWith(
                    fontSize: 10.5,
                    color: warn ? HpiColors.error : HpiColors.onSurface)),
          ),
        ],
      ),
    );
  }

  Widget _gattCard() {
    return HpiGroupedCard(rows: [
      _gattRow('ECG_STREAM', hPi4Global.UUID_ECG_CHAR, HpiColors.hr, 'NOTIFY'),
      _gattRow('PPG_STREAM', hPi4Global.UUID_CHAR_PPG, HpiColors.spo2, 'NOTIFY'),
      _gattRow('GSR_STREAM', hPi4Global.UUID_GSR_CHAR, HpiColors.eda, 'NOTIFY'),
      _gattRow('CMD', hPi4Global.UUID_CHAR_CMD, HpiColors.onSurfaceVariant, 'R/W'),
    ]);
  }

  Widget _gattRow(String name, String uuid, Color color, String status) {
    final statusColor = status == 'NOTIFY' ? HpiColors.steps : HpiColors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: HpiText.mono.copyWith(fontSize: 11, color: color)),
                const SizedBox(height: 2),
                Text(_shortUuid(uuid),
                    style: HpiText.mono.copyWith(fontSize: 9.5, color: HpiColors.muted)),
              ],
            ),
          ),
          HpiPill(label: status, color: statusColor),
        ],
      ),
    );
  }

  String _shortUuid(String u) => u.length > 8 ? '${u.substring(0, 8)}…${u.substring(u.length - 4)}' : u;

  Widget _logCard() {
    return HpiCard(
      waveform: true,
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120, maxHeight: 260),
        child: _log.isEmpty
            ? Text('waiting for link events…',
                style: HpiText.monoLog.copyWith(color: HpiColors.faint))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _log.length,
                itemBuilder: (_, i) => _log[i].build(),
              ),
      ),
    );
  }
}

class _LogLine {
  _LogLine(this.kind, this.message);
  final String kind;
  final String message;

  Color get _color {
    switch (kind) {
      case 'TX':
        return HpiColors.hr;
      case 'RX':
        return HpiColors.spo2;
      case 'OK':
        return HpiColors.steps;
      case 'WARN':
        return HpiColors.error;
      default:
        return HpiColors.muted;
    }
  }

  Widget build() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: HpiText.monoLog,
          children: [
            TextSpan(text: '$kind ', style: TextStyle(color: _color)),
            TextSpan(text: message,
                style: const TextStyle(color: HpiColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
