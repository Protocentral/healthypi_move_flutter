// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:move/models/hs_recording.dart';
import 'package:move/screens/scr_recording_preview.dart';
import 'package:move/screens/scr_settings_new.dart';
import 'package:move/screens/scr_trend_detail.dart';
import 'package:package_info_plus/package_info_plus.dart';
// The platform interface is supplied by path_provider.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.directory);
  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const sqliteChannel = MethodChannel('com.tekartik.sqflite');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  setUpAll(() => databaseFactory = databaseFactorySqflitePlugin);
  tearDownAll(() => databaseFactory = null);

  late Directory directory;
  late PathProviderPlatform previousPaths;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('move_csv_test_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Move',
      packageName: 'example.move.csvtest',
      version: '0.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    messenger.setMockMethodCallHandler(sqliteChannel, (call) async {
      switch (call.method) {
        case 'getDatabasesPath':
          return directory.path;
        case 'openDatabase':
          return {'id': 1};
        case 'execute':
          return null;
        case 'query':
          final sql = call.arguments['sql'] as String;
          final args = call.arguments['arguments'] as List<Object?>?;
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 8},
            ];
          }
          if (sql.contains('COUNT(*) AS n FROM hs_samples')) {
            return [
              {'device': 'fixture', 'n': 1},
            ];
          }
          if (sql.contains('FROM hs_samples s')) {
            return [
              {
                'seq': 1,
                'ts_utc': 1751932800,
                'type': 1,
                'quality': 0,
                'value': 72,
                'type_key': 'hr',
                'unit': 'bpm',
                'scale': 1,
              },
            ];
          }
          if (sql.contains('timestamp as hour_start') &&
              args?.contains('hr') == true) {
            return [
              {
                'hour_start': 1751932800,
                'min_value': 70,
                'avg_value': 72,
                'max_value': 75,
              },
            ];
          }
          return <Map<String, Object?>>[];
      }
      throw MissingPluginException(call.method);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(shareChannel, null);
    messenger.setMockMethodCallHandler(sqliteChannel, null);
    PathProviderPlatform.instance = previousPaths;
    directory.deleteSync(recursive: true);
  });

  Future<void> checkExport(
    WidgetTester tester, {
    required Widget screen,
    required Finder action,
    required Size logicalSize,
    required String header,
    required String value,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = logicalSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final shared = Completer<({MethodCall call, String csv})>();
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      final path = (call.arguments['paths'] as List<Object?>).single as String;
      shared.complete((call: call, csv: File(path).readAsStringSync()));
      throw PlatformException(code: 'error', message: 'Test share failure');
    });

    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.75)),
              child: child!,
            ),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
    if (action.evaluate().isEmpty) {
      await tester.scrollUntilVisible(action, 250);
    }
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();

    await tester.tap(action);
    for (var attempt = 0; attempt < 100 && !shared.isCompleted; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final error = find.textContaining('Export failed:');
      if (!shared.isCompleted && error.evaluate().isNotEmpty) {
        fail(tester.widget<Text>(error).data!);
      }
    }
    expect(shared.isCompleted, isTrue);
    await tester.pumpAndSettle();

    final (:call, :csv) = await shared.future;
    expect(csv.split('\r\n').first, startsWith(header));
    expect(csv, contains(value));
    expect(call.method, 'share');
    final args = call.arguments as Map<Object?, Object?>;
    final x = args['originX'];
    final y = args['originY'];
    final width = args['originWidth'];
    final height = args['originHeight'];
    expect([x, y, width, height], everyElement(isA<double>()));
    final rect = Rect.fromLTWH(
      x as double,
      y as double,
      width as double,
      height as double,
    );
    expect(rect.isFinite, isTrue);
    expect(rect.isEmpty, isFalse);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(logicalSize.width));
    expect(rect.bottom, lessThanOrEqualTo(logicalSize.height));
    expect(find.textContaining('Export failed:'), findsOneWidget);
    final path = (args['paths'] as List<Object?>).single as String;
    expect(File(path).readAsStringSync(), csv);
  }

  testWidgets(
    'HR Trends writes CSV before sharing from a phone view',
    (tester) => checkExport(
      tester,
      screen: const TrendDetailScreen(metricKey: 'hr'),
      action: find.byTooltip('Export CSV'),
      logicalSize: const Size(390, 844),
      header: 'bucket_start_local,bucket,metric,unit,min,avg,max',
      value: ',hour,hr,bpm,70.0,72.0,75.0',
    ),
  );

  testWidgets(
    'Settings Export data shares from a tablet view',
    (tester) => checkExport(
      tester,
      screen: const ScrSettingsNew(),
      action: find.text('Export data'),
      logicalSize: const Size(1024, 768),
      header: 'timestamp_utc,timestamp_local,seq,metric,value,unit',
      value: ',hr,72.0,bpm,72,1,0',
    ),
  );

  for (final (name, signal) in [
    ('GSR', HsSignal.bioz),
    ('PPG', HsSignal.ppgWrist),
    ('ECG', HsSignal.ecg),
  ]) {
    testWidgets('$name Recording Export writes and retains CSV', (tester) {
      final payload = Uint8List.fromList([
        for (var i = 0; i < 256; i++) ...[10 + i % 3, 0, 0, 0],
      ]);
      final recording = HsRecording(
        header: HsRecordHeader(
          id: 1,
          startTs: 1751932800,
          signal: signal,
          sampleFormat: 0,
          channels: 1,
          sampleRate: 128,
          nSamples: 256,
          byteLen: payload.length,
          crc32: 0,
          flags: 0,
        ),
      );
      return checkExport(
        tester,
        // Keep the export interactive while skipping the existing waveform paint.
        screen: Opacity(
          opacity: 0,
          child: ScrRecordingPreview(recording: recording, payload: payload),
        ),
        action: find.textContaining('Export CSV ·'),
        logicalSize: const Size(430, 932),
        header: 'timestamp_utc,t_ms,ch0,ch0_detrended',
        value: ',0.0,10.0,',
      );
    });
  }
}
