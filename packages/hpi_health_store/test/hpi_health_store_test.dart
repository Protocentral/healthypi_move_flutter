import 'dart:typed_data';

import 'package:hpi_health_store/hpi_health_store.dart';
import 'package:test/test.dart';

/// Build one packed 18-byte SYNC record:
/// seq u32 @0 · ts_utc i64 @4 · type u8 @12 · quality u8 @13 · value i32 @14
Uint8List packSample({
  required int seq,
  required int tsUtc,
  required int type,
  required int quality,
  required int value,
}) {
  final b = ByteData(HsSample.wireSize);
  b.setUint32(0, seq, Endian.little);
  b.setInt64(4, tsUtc, Endian.little);
  b.setUint8(12, type);
  b.setUint8(13, quality);
  b.setInt32(14, value, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('Crc32', () {
    test('matches the standard check vector', () {
      // The canonical CRC-32/ISO-HDLC check value for "123456789".
      expect(Crc32.compute('123456789'.codeUnits), 0xCBF43926);
    });

    test('empty input is zero', () {
      expect(Crc32.compute(const []), 0);
    });

    test('seeding continues a running CRC across chunks', () {
      const data = [1, 2, 3, 4, 5, 6, 7, 8];
      final oneShot = Crc32.compute(data);
      final chunked =
          Crc32.compute(data.sublist(4), Crc32.compute(data.sublist(0, 4)));
      expect(chunked, oneShot);
    });
  });

  group('HsSample', () {
    test('decodes a single record, little-endian', () {
      final s = HsSample.fromBytes(packSample(
        seq: 0xDEADBEEF,
        tsUtc: 1751932800,
        type: 0x01,
        quality: HsQuality.valid | HsQuality.onSkin,
        value: 725,
      ));
      expect(s.seq, 0xDEADBEEF);
      expect(s.tsUtc, 1751932800);
      expect(s.type, 0x01);
      expect(s.value, 725);
      expect(s.isValid, isTrue);
      expect(s.isOnSkin, isTrue);
      expect(s.timestamp.isUtc, isTrue);
    });

    test('decodes negative values (int32, not uint32)', () {
      final s = HsSample.fromBytes(
          packSample(seq: 1, tsUtc: 0, type: 3, quality: 0, value: -150));
      expect(s.value, -150);
    });

    test('listFromBytes decodes back-to-back records', () {
      final buf = BytesBuilder()
        ..add(packSample(seq: 1, tsUtc: 100, type: 1, quality: 1, value: 60))
        ..add(packSample(seq: 2, tsUtc: 101, type: 1, quality: 1, value: 61))
        ..add(packSample(seq: 3, tsUtc: 102, type: 2, quality: 0, value: 98));
      final list = HsSample.listFromBytes(buf.toBytes());
      expect(list, hasLength(3));
      expect(list.map((s) => s.seq), [1, 2, 3]);
      expect(list.last.value, 98);
    });

    test('listFromBytes ignores a trailing partial record', () {
      final buf = BytesBuilder()
        ..add(packSample(seq: 1, tsUtc: 100, type: 1, quality: 1, value: 60))
        ..add(Uint8List(5)); // short tail
      expect(HsSample.listFromBytes(buf.toBytes()), hasLength(1));
    });

    test('real() applies the registry scale', () {
      const type = HsType(
        id: 3,
        key: 'skin_temp',
        unit: 'degC',
        scale: 100,
        klass: HsClass.discrete,
        derived: false,
      );
      final s = HsSample.fromBytes(
          packSample(seq: 1, tsUtc: 0, type: 3, quality: 0, value: 3671));
      expect(s.real(type), closeTo(36.71, 1e-9));
    });
  });

  group('HsType.fromMap defensive parsing', () {
    test('reads the documented shape', () {
      final t = HsType.fromMap({
        'id': 1,
        'key': 'hr',
        'unit': 'bpm',
        'scale': 1,
        'class': 'D',
        'derived': false,
        'hk': 'heartRate',
      });
      expect(t.id, 1);
      expect(t.key, 'hr');
      expect(t.klass, HsClass.discrete);
      expect(t.derived, isFalse);
      expect(t.healthKit, 'heartRate');
      expect(t.healthConnect, isNull);
    });

    test('tolerates class as an int code and derived as 0/1', () {
      // The firmware has been observed sending ints where the contract says
      // strings/bools — this must not throw.
      final t = HsType.fromMap({
        'id': 4,
        'key': 'steps',
        'unit': 'count',
        'scale': 1,
        'class': 1,
        'derived': 1,
      });
      expect(t.klass, HsClass.cumulative);
      expect(t.derived, isTrue);
    });

    test('missing fields fall back rather than throwing', () {
      final t = HsType.fromMap(const {});
      expect(t.id, 0);
      expect(t.key, '');
      expect(t.scale, 1, reason: 'scale must never default to 0 (div-by-zero)');
      expect(t.klass, HsClass.unknown);
    });

    test('toReal guards a zero scale rather than dividing by zero', () {
      const t = HsType(
        id: 9,
        key: 'odd',
        unit: '',
        scale: 0,
        klass: HsClass.unknown,
        derived: false,
      );
      expect(t.toReal(42), 42.0);
    });
  });
}
