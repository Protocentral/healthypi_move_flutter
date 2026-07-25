// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart' show SmpException;

import '../globals.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/connection_manager.dart';
import '../utils/database_helper.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_client.dart';
import '../utils/healthy_store_probe.dart';

/// The single developer surface. Everything behind the developer-mode toggle
/// lives here — nothing developer-facing is left scattered through Settings.
///
/// It absorbs what used to be the separate BLE console (handoff 1j): Settings
/// carried two rows, "BLE console" and "Raw packet log", that pushed the *same*
/// screen and read like two features.
///
/// Sections, in the order you actually need them when something is wrong:
///  - **Link** — is there a connection, and did the MTU settle.
///  - **Derivation** — rebuild trends (real samples only); optional SYNTH for FW load.
///  - **Local store** — what is actually on the phone: cursor, head, per-type
///    sample counts. These decide every sync's behaviour and until now existed
///    only in `debugPrint` output, which is useless on a user's device.
///  - **Healthy Store** — the HELLO probe and the raw TYPES / SUMMARY capture.
///  - **GATT** — the app's UUID table.
///  - **Live log** — connection events.
///
/// Values that need a live link (MTU, throughput) show "—" when there isn't
/// one, rather than a plausible-looking constant.
class ScrDeveloper extends StatefulWidget {
  const ScrDeveloper({super.key});

  @override
  State<ScrDeveloper> createState() => _ScrDeveloperState();
}

/// What the phone actually holds for the paired watch.
class _StoreStats {
  const _StoreStats({
    required this.device,
    required this.cursor,
    required this.head,
    required this.schema,
    required this.lastSync,
    required this.perType,
    required this.total,
    required this.synthetic,
  });

  final String device; // HELLO uid — the key hs_samples is stored under
  final int? cursor;
  final int? head;
  final int? schema;
  final DateTime? lastSync;
  final List<(String, int)> perType; // (type key, count), sorted
  final int total;
  final int synthetic;

  /// How far the phone is behind the watch. The pair that explains "why is my
  /// chart empty" faster than anything else on this screen.
  int? get behind =>
      (cursor != null && head != null) ? (head! - cursor!) : null;
}

class _ScrDeveloperState extends State<ScrDeveloper> {
  final _cm = ConnectionManager.instance;
  final List<_LogLine> _log = [];

  HsProbeResult? _probe;
  bool _probing = false;

  bool _rebuilding = false;
  bool _synthing = false;
  _StoreStats? _store;
  bool _loadingStore = true;

  @override
  void initState() {
    super.initState();
    _cm.addListener(_onLink);
    _push(
        'OK',
        _cm.isConnected
            ? 'link up · ${_cm.deviceName ?? _cm.deviceId ?? "device"}'
            : 'no active link');
    _loadStore();
  }

  @override
  void dispose() {
    _cm.removeListener(_onLink);
    super.dispose();
  }

  Future<void> _loadStore() async {
    setState(() => _loadingStore = true);
    final db = DatabaseHelper.instance;
    final device = await db.getHealthyStoreDeviceKey();
    if (device == null) {
      if (mounted) {
        setState(() {
          _store = null;
          _loadingStore = false;
        });
      }
      return;
    }
    final state = await db.getSyncState(device);
    final counts = await db.sampleCountsByType(device);
    final types = await db.getTypes(device);
    final synthetic = await db.syntheticSampleCount(device);

    // Label each type id with its registry key. An id with no entry means the
    // sample arrived before TYPES cached it — which is exactly the bug that
    // makes a metric vanish from every chart, so show the raw id, don't hide it.
    final perType = counts.entries
        .map((e) => (
              (types[e.key]?['key'] as String?) ??
                  '0x${e.key.toRadixString(16).padLeft(2, '0')}',
              e.value,
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    final lastSyncUtc = state?['last_sync_utc'] as int?;
    if (!mounted) return;
    setState(() {
      _store = _StoreStats(
        device: device,
        cursor: state?['cursor'] as int?,
        head: state?['head'] as int?,
        schema: state?['schema'] as int?,
        lastSync: lastSyncUtc == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSyncUtc * 1000),
        perType: perType,
        total: counts.values.fold<int>(0, (a, b) => a + b),
        synthetic: synthetic,
      );
      _loadingStore = false;
    });
  }

  /// Re-derive `health_trends` from samples already on the phone — no download.
  ///
  /// This is the repair for a metric that was synced but never showed up: if its
  /// type id wasn't in the cached registry when it arrived, derivation dropped
  /// it, and the raw sample sits in `hs_samples` invisible to every screen.
  /// Sync does this automatically when the registry grows; this is the manual
  /// lever. Always excludes SYNTHETIC samples (QA opt-in removed).
  Future<void> _rebuildTrends() async {
    setState(() => _rebuilding = true);
    try {
      final db = DatabaseHelper.instance;
      final device = await db.getHealthyStoreDeviceKey();
      if (device == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No synced samples on this phone yet.')));
        }
        return;
      }
      final rows =
          await db.rebuildAllTrends(device, includeSynthetic: false);
      final synthetic = await db.syntheticSampleCount(device);
      final total = (await db.sampleCountsByType(device))
          .values
          .fold<int>(0, (a, b) => a + b);
      if (mounted) {
        // All stored samples may be firmware test data — charts stay empty by
        // design. Say so rather than "0 rows" looking like a bug.
        final blocked = rows == 0 && synthetic > 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(blocked
              ? 'No trends: all $synthetic samples are synthetic test data '
                  'and are filtered out of charts.'
              : 'Rebuilt $rows trend rows from $total stored samples'
                  '${synthetic > 0 ? " ($synthetic synthetic filtered out)" : ""}'),
          backgroundColor: blocked ? HpiColors.temp : HpiColors.steps,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Rebuild failed: $e'),
            backgroundColor: HpiColors.error));
      }
    } finally {
      if (mounted) setState(() => _rebuilding = false);
      await _loadStore(); // the counts just changed
    }
  }

  /// `SYNTH` — ask the **watch** to fabricate a backdated dataset (HPI_HS cmd 6).
  ///
  /// Two things make this worth a real confirm rather than a plain button:
  ///
  ///  - **`wipe` is destructive on the device.** It discards the existing durable
  ///    log, so any real measurement the watch is still holding that this phone
  ///    has not synced yet is gone. Not the phone's copy — the watch's.
  ///  - **It only exists on a test build.** On release firmware the command is
  ///    compiled out (`CONFIG_HPI_HS_SYNTH=n`) and the device answers with an
  ///    unknown-command rc. That is a correct answer, not a bug, so it is
  ///    reported as "not a test build" rather than as a failure.
  ///
  /// Generation is asynchronous on the device (~100 s per week of data) and the
  /// command returns immediately, so we can't report completion — the honest
  /// thing is to say so and let the user watch `head` grow via Probe.
  Future<void> _generateSynthetic() async {
    final opts = await showDialog<({int days, bool wipe})>(
      context: context,
      builder: (_) => const _SynthDialog(),
    );
    if (opts == null || !mounted) return;

    final device = await DeviceManager.getPairedDevice();
    if (device == null) {
      if (mounted) setState(() => _push('WARN', 'no paired device'));
      return;
    }

    setState(() {
      _synthing = true;
      _push('TX', 'SYNTH days=${opts.days} wipe=${opts.wipe}');
    });

    HealthyStoreClient? client;
    try {
      if (!_cm.isConnected || _cm.deviceId != device.macAddress) {
        await _cm.connect(device.macAddress);
      }
      client = HealthyStoreClient(device.macAddress,
          requestTimeout: const Duration(seconds: 20));
      await client.connect();
      if (!client.hasHealthyStore) {
        throw StateError('device did not answer HELLO — no Healthy Store');
      }

      final rsp = await client.hs!.synth(days: opts.days, wipe: opts.wipe);

      if (!mounted) return;
      setState(() {
        _push('RX', 'SYNTH accepted → $rsp');
        _push('OK',
            'generating ~${opts.days}d on-device (~${opts.days * 15}s) — poll Probe and watch head grow');
        _push('WARN',
            'SYNTHETIC samples are filtered out of charts — for firmware load tests only');
      });
      _snack(
          'Generating ${opts.days} days on the watch (~${opts.days * 15}s). '
          'Probe to watch head grow. Sync will store samples but will not chart '
          'synthetic test data.',
          HpiColors.temp);
    } on SmpBusyException {
      // Our own lock: a sync or DFU owns the wire. Never tear the link down
      // here — that would kill the flow that legitimately holds it.
      if (mounted) {
        setState(() => _push('WARN', 'SMP busy — sync or DFU running'));
      }
      _snack('The SMP link is busy (sync or DFU). Try again after it finishes.',
          HpiColors.temp);
    } on SmpException catch (e) {
      // Two of the device's answers are expected, not defects, and each needs a
      // different sentence. Read the typed rc rather than sniffing the message.
      final String msg;
      switch (e.rc) {
        case 8: // MGMT_ERR_ENOTSUP — command compiled out of a release build
          msg = 'This watch has no SYNTH command: it is a release build '
              '(CONFIG_HPI_HS_SYNTH=n). Nothing was changed.';
        case 10: // MGMT_ERR_EBUSY — a generation is already in flight
          msg = 'A generation is already running on the watch. Wait for it to '
              'finish, then Probe to watch head grow.';
        default:
          msg = 'SYNTH failed: $e';
      }
      if (mounted) setState(() => _push('WARN', 'SYNTH rc=${e.rc}: $e'));
      _snack(msg, HpiColors.error);
    } catch (e) {
      if (mounted) setState(() => _push('WARN', 'SYNTH failed: $e'));
      _snack('SYNTH failed: $e', HpiColors.error);
    } finally {
      // Releases the SMP lock. Must run even on the early throws above, or the
      // wire stays held and every later sync/DFU is refused.
      await client?.disconnect();
      if (mounted) setState(() => _synthing = false);
      await _loadStore();
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 8),
    ));
  }

  /// The Healthy Store capability check: HELLO *is* the probe (design doc §6).
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

    final result =
        await HealthyStoreProbe.probe(device.macAddress, name: device.displayName);

    if (!mounted) return;
    setState(() {
      _probe = result;
      _probing = false;
      if (result.supported) {
        _push(
            'OK',
            'HPI_HS schema=${result.schema} group=${result.group} '
            'dev=${result.dev} head=${result.head} types=${result.typeCount}');
        _push(
            'RX',
            'TYPES ${result.types.length} entries · '
            'SUMMARY ${result.summary.length} keys');
        if (!result.mtuOk) {
          _push('WARN',
              'MTU never settled (${result.maxWriteLength}) — transfers will fail');
        }
      } else {
        _push(
            'WARN',
            result.error ??
                'no HPI_HS group — firmware predates the Healthy Store');
      }
    });
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
        title: const Text('Developer'),
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
            const HpiSectionLabel('DERIVATION'),
            _derivationCard(),
            const SizedBox(height: 16),
            const HpiSectionLabel('LOCAL STORE · THIS PHONE'),
            _storeCard(),
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
      // "NO" and "UNREACHABLE" are different answers: the first is a verdict on
      // the firmware, the second means the probe never got a reply and says
      // nothing about it at all.
      stat(
          'HPI_HS',
          _probe == null
              ? '—'
              : _probe!.supported
                  ? 'YES'
                  : (_probe!.reachable ? 'NO' : 'UNREACH'),
          _probe == null
              ? HpiColors.onSurface
              : _probe!.supported
                  ? HpiColors.steps
                  : (_probe!.reachable ? HpiColors.error : HpiColors.temp)),
      const SizedBox(width: 10),
      stat('STATE', _cm.state.name.toUpperCase(), HpiColors.spo2),
    ]);
  }

  Widget _derivationCard() {
    return HpiCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HpiIconSquare(
                    icon: Symbols.science,
                    color: HpiColors.muted,
                    size: 34,
                    iconSize: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Synthetic data filtered', style: HpiText.cardTitle),
                      const SizedBox(height: 2),
                      Text(
                        'Firmware SYNTH samples stay in the local store for '
                        'diagnostics but never enter charts or summaries. '
                        'QA opt-in has been removed.',
                        style: HpiText.supporting,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: HpiColors.divider, indent: 14),
          HpiListRow(
            icon: Symbols.refresh,
            iconColor: HpiColors.steps,
            title: 'Rebuild trends',
            supporting: 'Re-derive real samples only · no download',
            showChevron: false,
            onTap: _rebuilding ? null : _rebuildTrends,
            trailing: _rebuilding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: HpiColors.steps))
                : null,
          ),
          const Divider(height: 1, color: HpiColors.divider, indent: 14),
          // Writes to the WATCH. Kept for firmware load tests; results are not
          // charted by the app.
          HpiListRow(
            icon: Symbols.experiment,
            iconColor: HpiColors.error,
            title: 'Generate synthetic data on watch',
            supporting: 'Firmware load test only · not charted · can wipe watch log',
            showChevron: false,
            onTap: _synthing ? null : _generateSynthetic,
            trailing: _synthing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: HpiColors.error))
                : null,
          ),
        ],
      ),
    );
  }

  /// What the phone holds, and how far behind the watch it is. This is the first
  /// thing to look at when a chart is empty.
  Widget _storeCard() {
    if (_loadingStore) {
      return HpiCard(
        child: Text('Reading local store…', style: HpiText.supporting),
      );
    }
    final s = _store;
    if (s == null) {
      return HpiCard(
        child: Text(
          'Nothing synced on this phone yet. Sync the watch and come back — '
          'this is where the cursor, head and per-type sample counts appear.',
          style: HpiText.body.copyWith(fontSize: 11.5),
        ),
      );
    }

    final behind = s.behind;
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${s.total} samples stored',
                    style: HpiText.cardTitle.copyWith(
                        color: s.total == 0
                            ? HpiColors.onSurfaceVariant
                            : HpiColors.steps)),
              ),
              SizedBox(
                width: 110,
                child: HpiTonalButton(
                  label: 'Refresh',
                  icon: Symbols.refresh,
                  onPressed: _loadStore,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _kv('device (HELLO uid)', s.device),
          _kv('cursor (stored seq)', s.cursor?.toString() ?? '—'),
          _kv('head (watch newest)', s.head?.toString() ?? '—'),
          // The number that explains an out-of-date chart.
          _kv('behind by', behind == null ? '—' : '$behind samples',
              warn: behind != null && behind > 0),
          _kv('schema', s.schema?.toString() ?? '—'),
          _kv('last sync', s.lastSync?.toLocal().toString() ?? 'never'),
          _kv('synthetic', '${s.synthetic} of ${s.total}',
              warn: s.synthetic > 0),
          if (s.perType.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('SAMPLES BY TYPE', style: HpiText.sectionLabel),
            const SizedBox(height: 4),
            // A bare hex id here (rather than a name) means the sample arrived
            // before TYPES had cached its id — the exact reason a metric can be
            // synced and still be invisible on every chart.
            for (final (key, count) in s.perType)
              Text('$key = $count',
                  style: HpiText.mono.copyWith(fontSize: 9.5)),
          ],
        ],
      ),
    );
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
                          ? 'Healthy Store supported'
                          : (p.reachable
                              ? 'Healthy Store not available'
                              : 'Could not reach the watch'),
                  style: HpiText.cardTitle.copyWith(
                    color: p == null
                        ? HpiColors.onSurfaceVariant
                        : p.supported
                            ? HpiColors.steps
                            : (p.reachable
                                ? HpiColors.error
                                : HpiColors.temp),
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
          else if (!p.supported && !p.reachable)
            Text(
              'The probe got no answer — a timeout or a dropped link. This says '
              'nothing about the firmware: do not read it as "no Healthy Store". '
              'Check the link and probe again.\n\n${p.error ?? ""}',
              style: HpiText.supporting.copyWith(color: HpiColors.temp),
            )
          else if (!p.supported)
            Text(
              p.error ??
                  'The device answered, and has no HPI_HS group. Its firmware '
                      'predates the Healthy Store; the app will use the legacy '
                      'sync path.',
              style: HpiText.supporting.copyWith(color: HpiColors.error),
            )
          else ...[
            _kv('schema', '${p.schema}'),
            _kv('group', '${p.group}'),
            _kv('dev (model)', p.dev ?? '—'),
            _kv('uid (store key)', (p.uid?.isNotEmpty ?? false) ? p.uid! : '—',
                warn: !(p.uid?.isNotEmpty ?? false)),
            _kv('head (newest seq)', '${p.head}'),
            _kv('types', '${p.typeCount} declared / ${p.types.length} parsed'),
            _kv('max write', '${p.maxWriteLength}', warn: !p.mtuOk),
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
      _gattRow('HPI_HS · SMP', hPi4Global.UUID_CHAR_SMP,
          HpiColors.onSurfaceVariant, 'R/W'),
    ]);
  }

  Widget _gattRow(String name, String uuid, Color color, String status) {
    final statusColor =
        status == 'NOTIFY' ? HpiColors.steps : HpiColors.onSurfaceVariant;
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
                    style: HpiText.mono
                        .copyWith(fontSize: 9.5, color: HpiColors.muted)),
              ],
            ),
          ),
          HpiPill(label: status, color: statusColor),
        ],
      ),
    );
  }

  String _shortUuid(String u) => u.length > 8
      ? '${u.substring(0, 8)}…${u.substring(u.length - 4)}'
      : u;

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

/// Confirm + parameters for `SYNTH`. Returns null on cancel.
///
/// The firmware defaults are `days: 7`, `wipe: true`, and we keep them — 7 days
/// is what the skin-temp baseline needs, and stacking a second dataset on top of
/// the first (`wipe: false`) is usually not what you meant.
class _SynthDialog extends StatefulWidget {
  const _SynthDialog();

  @override
  State<_SynthDialog> createState() => _SynthDialogState();
}

class _SynthDialogState extends State<_SynthDialog> {
  int _days = 7;
  bool _wipe = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: HpiColors.surfaceContainer,
      title: const Text('Generate synthetic data on the watch?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The watch fabricates a backdated dataset so trends, the 7-day '
            'skin-temp baseline and the HRV stress baseline can be exercised '
            'without wearing it for a week.\n\n'
            'Every generated sample is flagged SYNTHETIC. It is test data, not a '
            'measurement, and the app will keep it out of anything user-facing.\n\n'
            'Only test firmware has this command. On a release build the watch '
            'will simply refuse it.',
            style: HpiText.body.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text('DAYS', style: HpiText.sectionLabel),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 7, label: Text('7')),
              ButtonSegment(value: 14, label: Text('14')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 8),
          // ~100 s per week on-device; scale it so 14 days doesn't look instant.
          Text('Runs on the watch for roughly ${_days * 15}s after you confirm.',
              style: HpiText.supporting),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _wipe,
            onChanged: (v) => setState(() => _wipe = v),
            activeThumbColor: HpiColors.onHr,
            activeTrackColor: HpiColors.error,
            title: Text('Wipe the watch log first', style: HpiText.cardTitle),
            subtitle: Text(
              _wipe
                  // This is the sentence that matters: it destroys data on the
                  // *device*, not on the phone, and the phone cannot get it back.
                  ? 'DESTRUCTIVE — discards the watch\'s stored log. Any real '
                      'measurement it still holds that this phone has not synced '
                      'yet is gone for good.'
                  : 'Appends to the existing log. A second run will stack another '
                      'dataset on top of the first.',
              style: HpiText.supporting.copyWith(
                  color: _wipe ? HpiColors.error : HpiColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (days: _days, wipe: _wipe)),
          child: Text(_wipe ? 'Wipe and generate' : 'Generate',
              style: const TextStyle(color: HpiColors.error)),
        ),
      ],
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
            TextSpan(
                text: message,
                style: const TextStyle(color: HpiColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
