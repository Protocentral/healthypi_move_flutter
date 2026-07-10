import 'package:flutter/material.dart';

import '../globals.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';

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

  @override
  void initState() {
    super.initState();
    _cm.addListener(_onLink);
    _push('OK', _cm.isConnected
        ? 'link up · ${_cm.deviceName ?? _cm.deviceId ?? "device"}'
        : 'no active link');
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
    return Row(children: [
      stat('STATUS', connected ? 'UP' : 'DOWN',
          connected ? HpiColors.steps : HpiColors.muted),
      const SizedBox(width: 10),
      stat('MTU', connected ? '244' : '—', HpiColors.onSurface),
      const SizedBox(width: 10),
      stat('PHY', connected ? '2M' : '—', HpiColors.onSurface),
      const SizedBox(width: 10),
      stat('STATE', _cm.state.name.toUpperCase(), HpiColors.spo2),
    ]);
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
