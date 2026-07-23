// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:move/ble/mcuboot_image.dart';

/// Builds a minimal but structurally real MCUboot image: 32-byte header,
/// [bodyLen] bytes of payload, then a TLV area carrying SHA256 + a signature.
Uint8List _image({
  int hdrSize = 32,
  int bodyLen = 64,
  required List<int> sha,
  bool withProtectedArea = false,
  int headerMagic = 0x96f3b83d,
}) {
  final protTlvs = withProtectedArea ? (4 + 4 + 4) : 0; // info + one 4-byte TLV
  final body = List<int>.generate(bodyLen, (i) => i & 0xFF);

  final b = BytesBuilder();
  final hdr = ByteData(hdrSize);
  hdr.setUint32(0, headerMagic, Endian.little); // ih_magic
  hdr.setUint32(4, 0, Endian.little); // ih_load_addr
  hdr.setUint16(8, hdrSize, Endian.little); // ih_hdr_size
  hdr.setUint16(10, protTlvs, Endian.little); // ih_protect_tlv_size
  hdr.setUint32(12, bodyLen, Endian.little); // ih_img_size
  hdr.setUint32(16, 0, Endian.little); // ih_flags
  b.add(hdr.buffer.asUint8List());
  b.add(body);

  if (withProtectedArea) {
    final p = ByteData(protTlvs);
    p.setUint16(0, 0x6908, Endian.little); // IMAGE_TLV_PROT_INFO_MAGIC
    p.setUint16(2, protTlvs, Endian.little);
    p.setUint8(4, 0x60); // some protected TLV type
    p.setUint16(6, 4, Endian.little);
    b.add(p.buffer.asUint8List());
  }

  // Unprotected area: SHA256 (0x10) then a fake signature TLV (0x22).
  const sigLen = 8;
  final total = 4 + (4 + 32) + (4 + sigLen);
  final t = BytesBuilder();
  final info = ByteData(4);
  info.setUint16(0, 0x6907, Endian.little); // IMAGE_TLV_INFO_MAGIC
  info.setUint16(2, total, Endian.little);
  t.add(info.buffer.asUint8List());

  final shaHdr = ByteData(4);
  shaHdr.setUint8(0, 0x10); // IMAGE_TLV_SHA256
  shaHdr.setUint16(2, 32, Endian.little);
  t.add(shaHdr.buffer.asUint8List());
  t.add(sha);

  final sigHdr = ByteData(4);
  sigHdr.setUint8(0, 0x22);
  sigHdr.setUint16(2, sigLen, Endian.little);
  t.add(sigHdr.buffer.asUint8List());
  t.add(List<int>.filled(sigLen, 0x5A));

  b.add(t.toBytes());
  return b.toBytes();
}

void main() {
  final sha = List<int>.generate(32, (i) => (i * 7) & 0xFF);

  test('extracts IMAGE_TLV_SHA256 from a signed image', () {
    final img = _image(sha: sha);
    expect(McubootImage.sha256Tlv(img), equals(sha));
  });

  test('the TLV hash is NOT the sha256 of the file', () {
    // The whole point. MCUmgr identifies an image by the hash of its header +
    // body from the TLV section; hashing the file (which includes the trailer
    // and signature) gives a different value, and `image test` with it fails
    // "hash not found" — reported to the client as a bare rc=1.
    final img = _image(sha: sha);
    final fileDigest = crypto.sha256.convert(img).bytes;
    expect(McubootImage.sha256Tlv(img), isNot(equals(fileDigest)));
  });

  test('skips a protected TLV area to reach the unprotected one', () {
    final img = _image(sha: sha, withProtectedArea: true);
    expect(McubootImage.sha256Tlv(img), equals(sha));
  });

  test('handles a larger header (real images use 512)', () {
    final img = _image(sha: sha, hdrSize: 512, bodyLen: 1024);
    expect(McubootImage.sha256Tlv(img), equals(sha));
  });

  group('rejects things that are not signed images', () {
    test('wrong header magic', () {
      final img = _image(sha: sha, headerMagic: 0xDEADBEEF);
      expect(McubootImage.looksValid(img), isFalse);
      expect(McubootImage.sha256Tlv(img), isNull);
    });

    test('too short', () {
      expect(McubootImage.sha256Tlv(Uint8List(8)), isNull);
    });

    test('plain text', () {
      final img = Uint8List.fromList(utf8.encode('not a firmware image at all'));
      expect(McubootImage.sha256Tlv(img), isNull);
    });

    test('truncated before its TLV area', () {
      final full = _image(sha: sha);
      final cut = Uint8List.sublistView(full, 0, full.length - 20);
      expect(McubootImage.sha256Tlv(cut), isNull);
    });
  });
}
