// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_healthy_store/healthypi_healthy_store.dart';
import 'package:move/models/hs_recording.dart';
import 'package:move/utils/healthy_store_records_manager.dart';

HsRecording rec({
  required int signal,
  int sampleRate = 128,
  int nSamples = 1280,
}) => HsRecording(
  header: HsRecordHeader(
    id: 1,
    startTs: 1751932800,
    signal: signal,
    sampleFormat: 0,
    channels: 1,
    sampleRate: sampleRate,
    nSamples: nSamples,
    byteLen: nSamples * 4,
    crc32: 0,
    flags: 0,
  ),
);

void main() {
  group('interval series (HRV R-R)', () {
    test('an HRV record is flagged as an interval series; others are not', () {
      expect(rec(signal: HsSignal.hrvRr).isIntervalSeries, isTrue);
      expect(rec(signal: HsSignal.ecg).isIntervalSeries, isFalse);
      expect(rec(signal: HsSignal.ppgWrist).isIntervalSeries, isFalse);
      expect(rec(signal: HsSignal.acc).isIntervalSeries, isFalse);
    });

    test(
      'HRV reports no fixed-rate duration, however plausible sampleRate looks',
      () {
        // Firmware still populates sampleRate on an R-R header, but it is not Hz.
        // Dividing by it yielded a confident, wrong duration (here it would read
        // as "10s") on the library row, the app bar and the minimap axis.
        final hrv = rec(
          signal: HsSignal.hrvRr,
          sampleRate: 128,
          nSamples: 1280,
        );
        expect(hrv.durationSeconds, 0);
        // The honest header-only figure.
        expect(hrv.beats, 1280);
      },
    );

    test('a fixed-rate record still reports its duration normally', () {
      final ecg = rec(signal: HsSignal.ecg, sampleRate: 128, nSamples: 1280);
      expect(ecg.durationSeconds, 10);
    });

    test(
      'a fixed-rate record with an unusable rate reports 0, not infinity',
      () {
        expect(rec(signal: HsSignal.ecg, sampleRate: 0).durationSeconds, 0);
      },
    );

    test('the kind mapping keeps HRV distinct from ECG', () {
      // Both feed HRV metrics, but only one is an interval series — conflating
      // them is what puts a fake timebase on a tachogram.
      expect(rec(signal: HsSignal.hrvRr).kind, HsRecordingKind.hrv);
      expect(rec(signal: HsSignal.ecg).kind, HsRecordingKind.ecg);
      expect(rec(signal: HsSignal.hrvRr).kindLabel, 'HRV');
    });

    test(
      'HRV RR payloads decode from repeated header, RR, and confidence blocks',
      () {
        // Block 1: 16-byte header + 2 RR intervals + 2 confidence bytes.
        final block1 = <int>[
          0x00, 0x00, 0x00, 0x00, // t_start_ms
          0x02, 0x00, // n_beats
          0x00, 0x00, // pad
          0x00, 0x00, 0x00, 0x00, // t_stop_ms
          0x00, 0x00, 0x00, 0x00, // total_sum
          0x01, 0x00, // rr[0]
          0x02, 0x00, // rr[1]
          0x64, 0x64, // conf[0..1]
        ];

        // Block 2: same layout, second batch of RR values.
        final block2 = <int>[
          0x00, 0x00, 0x00, 0x00,
          0x02, 0x00,
          0x00, 0x00,
          0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00,
          0x03, 0x00,
          0x04, 0x00,
          0x64, 0x64,
        ];

        final bytes = Uint8List.fromList([...block1, ...block2]);
        final decoded = decodeHrvIntervals(bytes);
        expect(decoded, [1.0, 2.0, 3.0, 4.0]);
      },
    );

    test('the packed RR-run header exposes t_stop_ms and total_sum at the aligned offsets', () {
      final block = <int>[
        0x01, 0x00, 0x00, 0x00, // t_start_ms = 1
        0x02, 0x00, // n_beats = 2
        0x00, 0x00, // pad
        0x05, 0x00, 0x00, 0x00, // t_stop_ms = 5
        0x0a, 0x00, 0x00, 0x00, // total_sum = 10
        0x0a, 0x00, // rr[0]
        0x14, 0x00, // rr[1]
        0x64, 0x64, // conf[0..1]
      ];

      final runs = decodeHrvRunBlocks(Uint8List.fromList(block));
      expect(runs, hasLength(1));
      expect(runs.first.tStopMs, 5);
      expect(runs.first.totalSum, 10);
      expect(runs.first.rr, [10, 20]);

      final formatted = formatHrvBlockData(Uint8List.fromList(block));
      expect(
        formatted,
        contains(
          '[HEADER: t_start_ms=1 n_beats=2 t_stop_ms=5 total_sum=10]',
        ),
      );
    });
  });
}
