// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:move/utils/connection_manager.dart';

import '../ble/bpt_calibrator.dart';
import '../ble/hpi_hs_bpt_transport.dart';
import '../theme/hpi_colors.dart';
import '../theme/hpi_text.dart';
import '../ui/components/hpi_components.dart';
import '../utils/device_manager.dart';
import '../utils/healthy_store_client.dart';
import '../utils/snackbar.dart';
import 'scr_device_scan.dart';
import 'scr_main_shell.dart';

// CalibrationState + CalibrationPoint + the BptCalibrator state machine live in
// ../ble/bpt_calibrator.dart (SDK-bound, transport-agnostic). This screen is now
// just its view + input, restyled to the redesign token system (handoff 5b).

class ScrBPTCalibration extends StatefulWidget {
  const ScrBPTCalibration({super.key});

  @override
  State<ScrBPTCalibration> createState() => _ScrBPTCalibrationState();
}

class _ScrBPTCalibrationState extends State<ScrBPTCalibration> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final ConnectionManager _conn = ConnectionManager.instance;

  /// The SMP session that carries the HPI_HS BPT commands. Rides the
  /// [ConnectionManager] link and holds the SMP wire lock for the whole
  /// calibration (like sync/DFU), so a background sync cannot interleave frames.
  HealthyStoreClient? _hsClient;

  /// Feedback poll + command adapter over HPI_HS (`0x1000`).
  HpiHsBptTransport? _bptTransport;

  /// The transport-agnostic BPT state machine. Created once the HPI_HS session
  /// is up (the transport needs its `hs` client), so it is nullable until then.
  BptCalibrator? _cal;

  bool _isInitializing = true;
  String _statusMessage = "Connecting to device…";

  // --- calibrator state, surfaced as shims so the view code reads unchanged ---
  // Null-safe: the state body only renders after [_cal] is created (once
  // _isInitializing is false), but the defaults keep the getters total.
  CalibrationState get _currentState =>
      _cal?.phase ?? CalibrationState.preCalibration;
  int get _currentPointIndex => _cal?.currentPointIndex ?? 0;
  List<CalibrationPoint> get _calibrationPoints => _cal?.points ?? const [];
  int get _progress => _cal?.progress ?? 0;
  int get _statusCode => _cal?.statusCode ?? 0;
  String get _statusString => _cal?.statusMessage ?? '';
  bool get _fingerSignalGood => _cal?.fingerSignalGood ?? false;
  bool get _pointFailed => _cal?.pointFailed ?? false;

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  /// Rebuild whenever the calibrator's state changes (status packets, phase
  /// transitions). All BPT state now lives in [_cal].
  void _onCalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cal?.removeListener(_onCalChanged);
    _cal?.dispose(); // cancels the status subscription
    // Tear the HPI_HS session down (releases the SMP lock); leaves the
    // ConnectionManager link up for Home/Device.
    _bptTransport?.dispose();
    _hsClient?.disconnect();
    _systolicController.dispose();
    _diastolicController.dispose();
    super.dispose();
  }

  Future<void> _initializeConnection() async {
    try {
      // Check for paired device
      final deviceInfo = await DeviceManager.getPairedDevice();

      if (deviceInfo == null) {
        // No paired device, route through the scan/switch surface first.
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ScrDeviceScan(
                pairOnly: false,
                onDeviceConnected: (device) {
                  // After pairing, navigate back to BPT calibration
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ScrBPTCalibration()),
                  );
                },
              ),
            ),
          );
        }
        return;
      }

      // Connect to the paired device (scan-assisted connect + service discovery
      // handled by ConnectionManager).
      if (mounted) {
        setState(() {
          _statusMessage = "Connecting to ${deviceInfo.displayName}…";
        });
      }

      await _conn.connect(deviceInfo.macAddress, name: deviceInfo.displayName);
      await DeviceManager.updateLastConnected();

      // Open an HPI_HS SMP session over that link (acquires the SMP lock, probes
      // HELLO). BPT control + status now ride group 0x1000 — the custom cmd/data
      // GATT service is retired.
      if (mounted) setState(() => _statusMessage = 'Opening HPI_HS session…');
      final hsClient = HealthyStoreClient(deviceInfo.macAddress,
          name: deviceInfo.displayName);
      await hsClient.connect();
      _hsClient = hsClient;

      if (!hsClient.hasHealthyStore || hsClient.hs == null) {
        // The watch answered but has no HPI_HS group — firmware too old for the
        // BPT-over-HS path (there is no custom-service fallback any more).
        _statusMessage =
            'This watch\'s firmware does not support BPT calibration over '
            'HPI_HS. Update the firmware and try again.';
        await _teardownHs();
        if (mounted) {
          setState(() => _isInitializing = false);
          _showConnectionErrorDialog();
        }
        return;
      }

      final transport = HpiHsBptTransport(
        hsClient.hs!,
        isConnected: () => hsClient.isConnected,
        log: logConsole,
      );
      _bptTransport = transport;
      final cal = BptCalibrator(transport, log: logConsole)
        ..addListener(_onCalChanged);
      _cal = cal;

      // Enter BPT calibration mode and start the finger-signal poll so the user
      // can seat the sensor and see contact quality *before* they enter cuff
      // readings. Waiting until "Begin" to listen is too late — by then a bad
      // finger placement just burns a calibration attempt.
      if (mounted) {
        setState(() => _isInitializing = false);
        await cal.enterCalibrationMode();
      }
    } catch (e) {
      await _teardownHs();
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = 'Connection failed: $e';
        });
        _showConnectionErrorDialog();
      }
    }
  }

  /// Tear down the HPI_HS session + feedback poll, releasing the SMP lock.
  /// Leaves the ConnectionManager link up.
  Future<void> _teardownHs() async {
    await _bptTransport?.dispose();
    _bptTransport = null;
    await _hsClient?.disconnect();
    _hsClient = null;
  }

  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Connection failed'),
        content: Text(_statusMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScrMainShell.returnToRoot(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const ScrDeviceScan()),
              );
            },
            child: const Text('Scan for device',
                style: TextStyle(color: HpiColors.hr)),
          ),
        ],
      ),
    );
  }

  /// Status-code → palette color, mapped onto the redesign tokens.
  Color _statusColor(int statusCode) {
    switch (statusCode) {
      case 0:
      case 6:
        return HpiColors.error;
      case 1:
      case 2:
        return HpiColors.steps;
      case 3:
      case 4:
      case 16:
      case 19:
      case 23:
      case 24:
        return HpiColors.temp;
      default:
        return HpiColors.onSurfaceVariant;
    }
  }

  /// Read the cuff numbers, hand them to the calibrator (which sends `0x61` +
  /// `[sys, dia, index]` and moves to calibrating).
  Future<void> _startPoint() async {
    final sys = int.tryParse(_systolicController.text.trim()) ?? 0;
    final dia = int.tryParse(_diastolicController.text.trim()) ?? 0;
    await _cal?.startPoint(systolic: sys, diastolic: dia);
  }

  Future<void> _endAndExit() async {
    try {
      await _cal?.endCalibration();
    } catch (e) {
      logConsole('Error ending calibration: $e');
    }
    await _teardownHs(); // release the SMP lock before dropping the link
    await _disconnect();
    if (mounted) ScrMainShell.returnToRoot(context);
  }

  Future<void> _disconnect() async {
    try {
      if (_conn.isConnected) await _conn.disconnect();
    } catch (e) {
      logConsole('Disconnect error: $e');
    }
  }

  void logConsole(String logString) {
    debugPrint('BPT - $logString');
  }

  // --- Presentation: redesigned calibration flow (handoff 5b) ---------------

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        backgroundColor: HpiColors.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: HpiColors.background,
          leading: IconButton(
            icon: const Icon(Symbols.arrow_back, color: HpiColors.onSurfaceBright),
            onPressed: () async {
              final nav = Navigator.of(context);
              await _disconnect();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ScrMainShell()),
                (r) => false,
              );
            },
          ),
          title: Text('BP calibration', style: HpiText.appBarTitle),
          centerTitle: false,
        ),
        body: SafeArea(
          child: _isInitializing ? _connecting() : _stateBody(),
        ),
      ),
    );
  }

  Widget _connecting() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(HpiColors.hr),
            ),
          ),
          const SizedBox(height: 20),
          Text(_statusMessage,
              style: HpiText.cardTitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _stateBody() {
    switch (_currentState) {
      case CalibrationState.preCalibration:
        return _introView();
      case CalibrationState.readyForInput:
        return _inputView();
      case CalibrationState.calibrating:
        return _capturingView();
      case CalibrationState.pointComplete:
        return _pointCompleteView();
      case CalibrationState.allComplete:
        return _completeView();
    }
  }

  // --- Intro / sensor prep (preCalibration) ---------------------------------

  Widget _introView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        HpiCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              HpiIconSquare(
                  icon: Symbols.monitor_heart,
                  color: HpiColors.hr,
                  size: 56,
                  iconSize: 30),
              const SizedBox(height: 14),
              Text('Blood pressure calibration',
                  style: HpiText.screenTitle.copyWith(fontSize: 20),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                'Three cuff readings teach the watch to estimate BP from finger PPG.',
                style: HpiText.body.copyWith(fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HpiGroupedCard(rows: [
          _infoRow(Symbols.timer, 'Duration', '3–5 minutes'),
          _infoRow(Symbols.sensors, 'Readings', '3 points · finger PPG'),
          _infoRow(Symbols.medical_services, "You'll need",
              'Cuff BP monitor + finger sensor'),
        ]),
        const SizedBox(height: 12),
        HpiCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HpiSectionLabel('Finger sensor first'),
              _tip('Slide the finger sensor fully onto the index fingertip '
                  '(snug, not crushing).'),
              _tip('Rest your hand palm-up on a table; stay still during each '
                  'point.'),
              _tip('Warm hands help — cold fingers kill the PPG signal.'),
              _tip('Measure cuff BP, enter the numbers, then start only when '
                  'the signal is green.'),
            ],
          ),
        ),
        if (_statusString.isNotEmpty) ...[
          const SizedBox(height: 12),
          _fingerBanner(),
        ],
        const SizedBox(height: 16),
        HpiFilledButton(
          label: 'Start calibration',
          icon: Symbols.play_arrow,
          onPressed: () => _cal?.beginInput(),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    // label over value (not a trailing column) so a long value wraps within the
    // row instead of fighting the title for horizontal space.
    return HpiListRow(
      icon: icon,
      iconColor: HpiColors.hr,
      title: label,
      supporting: value,
      supportingColor: HpiColors.onSurfaceVariant,
      showChevron: false,
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Symbols.check_circle, size: 15, color: HpiColors.hr),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: HpiText.body.copyWith(fontSize: 12.5))),
        ],
      ),
    );
  }

  /// Finger-signal banner: green on good contact, else the status color.
  Widget _fingerBanner() {
    final good = _fingerSignalGood || _statusCode == 1;
    final color = good ? HpiColors.steps : _statusColor(_statusCode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HpiMetricColors.tint(color, 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HpiMetricColors.tint(color, 0.5)),
      ),
      child: Row(
        children: [
          Icon(good ? Symbols.check_circle : Symbols.fingerprint,
              color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(good ? 'Finger sensor: good contact' : 'Finger sensor',
                    style: HpiText.cardTitle.copyWith(color: color, fontSize: 13)),
                if (_statusString.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_statusString,
                      style: HpiText.supporting.copyWith(
                          color: HpiColors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Enter cuff reading (readyForInput) -----------------------------------

  Widget _inputView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _progressDots(),
        const SizedBox(height: 16),
        HpiCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Calibration point ${_currentPointIndex + 1} of 3',
                  style: HpiText.appBarTitle, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _fingerBanner(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HpiMetricColors.tint(HpiColors.hr, 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Symbols.fingerprint, color: HpiColors.hr, size: 22),
                      const SizedBox(width: 8),
                      Text('Finger first, then cuff',
                          style: HpiText.cardTitle.copyWith(color: HpiColors.hr)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      '1. Seat the finger sensor (wait for a green signal)\n'
                      '2. Take a cuff BP reading now\n'
                      '3. Enter systolic / diastolic below\n'
                      '4. Hold still until the point finishes',
                      style: HpiText.body.copyWith(fontSize: 12.5, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Form(
                key: _formKey,
                child: Row(
                  children: [
                    Expanded(
                      child: _bpField(
                        _systolicController,
                        'Systolic',
                        min: 80,
                        max: 180,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _bpField(
                        _diastolicController,
                        'Diastolic',
                        min: 50,
                        max: 120,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_fingerSignalGood) ...[
                const SizedBox(height: 14),
                Text(
                  'Tip: start only when the finger sensor shows good contact. '
                  'You can still proceed, but failed points are usually a bad '
                  'PPG signal.',
                  style: HpiText.supporting.copyWith(color: HpiColors.temp),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              HpiFilledButton(
                label: _fingerSignalGood
                    ? 'Begin point ${_currentPointIndex + 1}'
                    : 'Begin anyway · point ${_currentPointIndex + 1}',
                color: _fingerSignalGood ? HpiColors.hr : HpiColors.temp,
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  if (!_formKey.currentState!.validate()) return;
                  await _startPoint();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bpField(TextEditingController controller, String label,
      {required int min, required int max}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: HpiText.statChip,
      cursorColor: HpiColors.hr,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: HpiText.body.copyWith(fontSize: 12.5),
        floatingLabelStyle: HpiText.body.copyWith(color: HpiColors.hr),
        filled: true,
        fillColor: HpiColors.chipBg,
        suffixText: 'mmHg',
        suffixStyle: HpiText.mono,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: HpiColors.hr, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        errorStyle: HpiText.supporting.copyWith(color: HpiColors.error),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        final v = int.tryParse(value);
        if (v == null) return 'Invalid';
        if (v < min || v > max) return '$min–$max';
        return null;
      },
    );
  }

  /// 3-step progress dots: done = green check, current = amber, upcoming = grey.
  Widget _progressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final done = i < _calibrationPoints.length;
        final current = i == _currentPointIndex && !done;
        final color = done
            ? HpiColors.steps
            : current
                ? HpiColors.hr
                : HpiColors.dividerStrong;
        return Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              child: done
                  ? const Icon(Symbols.check, color: HpiColors.onHr, size: 20)
                  : Text('${i + 1}',
                      style: HpiText.cardTitle.copyWith(
                          color: current ? HpiColors.onHr : HpiColors.muted)),
            ),
            if (i < 2)
              Container(
                width: 34,
                height: 2,
                color: done ? HpiColors.steps : HpiColors.dividerStrong,
              ),
          ],
        );
      }),
    );
  }

  // --- Capturing (calibrating) ----------------------------------------------

  Widget _capturingView() {
    final statusColor = _statusColor(_statusCode);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
      children: [
        HpiCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Capturing point ${_currentPointIndex + 1}',
                  style: HpiText.appBarTitle, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(
                width: 128,
                height: 128,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: CircularProgressIndicator(
                        value: _progress / 100,
                        strokeWidth: 8,
                        backgroundColor: HpiColors.dividerStrong,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(HpiColors.hr),
                      ),
                    ),
                    Text('$_progress%',
                        style: HpiText.heroNumberSm.copyWith(fontSize: 32)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (_statusString.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: HpiMetricColors.tint(statusColor, 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          _statusCode == 1 || _statusCode == 2
                              ? Symbols.check_circle
                              : Symbols.info,
                          color: statusColor,
                          size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(_statusString,
                            textAlign: TextAlign.center,
                            style: HpiText.cardTitle
                                .copyWith(color: statusColor, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              if (_pointFailed) ...[
                const SizedBox(height: 14),
                HpiFilledButton(
                  label: 'Retry this point',
                  icon: Symbols.refresh,
                  onPressed: () => _cal?.retryPoint(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reseat the finger sensor, wait for a green signal, then '
                  'retry. Earlier completed points are kept.',
                  style: HpiText.supporting,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _outlinedDanger('Cancel calibration', _confirmCancel),
      ],
    );
  }

  Future<void> _confirmCancel() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HpiColors.surfaceContainer,
        title: const Text('Cancel calibration?'),
        content: const Text('Progress on this point will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continue')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Cancel', style: TextStyle(color: HpiColors.error)),
          ),
        ],
      ),
    );
    if (cancel == true) await _endAndExit();
  }

  // --- Point complete (pointComplete) ---------------------------------------

  Widget _pointCompleteView() {
    final point = _calibrationPoints[_currentPointIndex];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _progressDots(),
        const SizedBox(height: 16),
        HpiCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Symbols.check_circle, size: 60, color: HpiColors.steps),
              const SizedBox(height: 14),
              Text('Point ${point.pointNumber} complete',
                  style: HpiText.appBarTitle),
              const SizedBox(height: 18),
              _readingRow(point),
              const SizedBox(height: 14),
              Text(
                '${_calibrationPoints.length}/3 captured · '
                '${3 - _calibrationPoints.length} more needed',
                style: HpiText.body.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        HpiFilledButton(
          label: 'Continue to point ${_calibrationPoints.length + 1}',
          icon: Symbols.arrow_forward,
          onPressed: () => _cal?.advanceToNextPoint(),
        ),
        const SizedBox(height: 10),
        _outlinedNeutral('Finish calibration early', _endAndExit),
      ],
    );
  }

  Widget _readingRow(CalibrationPoint point) {
    Widget col(String label, int value) => Column(
          children: [
            Text(label, style: HpiText.supporting),
            const SizedBox(height: 4),
            Text('$value', style: HpiText.heroNumberSm.copyWith(fontSize: 30)),
            Text('mmHg', style: HpiText.supporting),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: HpiMetricColors.tint(HpiColors.steps, 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          col('Systolic', point.systolic),
          Container(width: 1, height: 54, color: HpiColors.dividerStrong),
          col('Diastolic', point.diastolic),
        ],
      ),
    );
  }

  // --- All complete (allComplete) -------------------------------------------

  Widget _completeView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        HpiCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Symbols.verified, size: 80, color: HpiColors.steps),
              const SizedBox(height: 14),
              Text('Calibration complete',
                  style: HpiText.screenTitle.copyWith(fontSize: 20)),
              const SizedBox(height: 8),
              Text('The watch now has 3 reference points for BP estimation.',
                  style: HpiText.body.copyWith(fontSize: 12.5),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HpiGroupedCard(
          rows: List.generate(_calibrationPoints.length, (i) {
            final p = _calibrationPoints[i];
            return HpiListRow(
              icon: Symbols.check_circle,
              iconColor: HpiColors.steps,
              title: 'Point ${p.pointNumber}',
              trailing: Text('${p.systolic}/${p.diastolic} mmHg',
                  style: HpiText.valueSm),
              showChevron: false,
            );
          }),
        ),
        const SizedBox(height: 16),
        HpiFilledButton(
          label: 'Done',
          onPressed: _endAndExit,
        ),
      ],
    );
  }

  // --- shared buttons -------------------------------------------------------

  Widget _outlinedDanger(String label, VoidCallback onTap) =>
      _outlined(label, onTap, HpiColors.error);

  Widget _outlinedNeutral(String label, VoidCallback onTap) =>
      _outlined(label, onTap, HpiColors.onSurfaceVariant);

  Widget _outlined(String label, VoidCallback onTap, Color color) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: HpiMetricColors.tint(color, 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(label,
                style: HpiText.cardTitle.copyWith(color: color, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

