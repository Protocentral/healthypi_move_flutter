// Copyright (c) 2024-2026 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

/// Reads the MCUboot image header/TLV area of a signed image.
///
/// Exists for one value: the **image hash MCUmgr identifies a firmware image
/// by**. Per the SMP Image-management specification, that hash is
///
///   "SHA256 hash of the image header and body. Note that this will not be the
///    same as the SHA256 of the whole file, it is the field in the MCUboot TLV
///    section that contains a hash of the data which is used for signature
///    verification purposes."
///
/// — i.e. `IMAGE_TLV_SHA256` (type 0x10) out of the trailer, not a digest of
/// the `.bin` on disk. Handing the device the wrong one makes `image test`
/// fail with "hash not found", which surfaces as a bare `rc=1`.
///
/// The documented way to obtain it is to read it back from `image list` after
/// uploading (see Nordic's `tfm_psa_template` README: "the hash of the image is
/// shown in the image list"). This parser is the fallback for when the device
/// omits the slot from that listing — which the nRF5340 does for the net core,
/// whose primary slot lives in flash the application core cannot read.
class McubootImage {
  McubootImage._();

  /// `IMAGE_MAGIC` — first word of a valid MCUboot image header.
  static const int _headerMagic = 0x96f3b83d;

  /// `IMAGE_TLV_INFO_MAGIC` (unprotected TLV area).
  static const int _tlvInfoMagic = 0x6907;

  /// `IMAGE_TLV_PROT_INFO_MAGIC` (protected TLV area, precedes the above).
  static const int _tlvProtInfoMagic = 0x6908;

  /// `IMAGE_TLV_SHA256`.
  static const int _tlvSha256 = 0x10;

  static const int _sha256Len = 32;

  /// True when [image] starts with an MCUboot image header.
  static bool looksValid(Uint8List image) =>
      image.length >= 32 &&
      ByteData.sublistView(image).getUint32(0, Endian.little) == _headerMagic;

  /// The image's `IMAGE_TLV_SHA256`, or null if the image is malformed or
  /// carries no such TLV (e.g. it was signed with a different hash algorithm).
  static Uint8List? sha256Tlv(Uint8List image) {
    if (!looksValid(image)) return null;

    final bd = ByteData.sublistView(image);
    // image_header: magic(4) load_addr(4) hdr_size(2) protect_tlv_size(2)
    //               img_size(4) flags(4) version(8) pad(4)
    final hdrSize = bd.getUint16(8, Endian.little);
    final imgSize = bd.getUint32(12, Endian.little);

    var off = hdrSize + imgSize;

    // Walk the TLV areas: the protected area (if any) comes first, then the
    // unprotected one. The SHA is normally in the unprotected area, but scan
    // both rather than assuming.
    while (off + 4 <= image.length) {
      final areaMagic = bd.getUint16(off, Endian.little);
      final areaTotal = bd.getUint16(off + 2, Endian.little);
      if (areaMagic != _tlvInfoMagic && areaMagic != _tlvProtInfoMagic) {
        return null;
      }
      if (areaTotal < 4) return null;

      final areaEnd =
          (off + areaTotal <= image.length) ? off + areaTotal : image.length;
      var p = off + 4; // skip image_tlv_info
      while (p + 4 <= areaEnd) {
        // image_tlv: type(1) pad(1) len(2)
        final type = bd.getUint8(p);
        final len = bd.getUint16(p + 2, Endian.little);
        final valueStart = p + 4;
        if (type == _tlvSha256 &&
            len == _sha256Len &&
            valueStart + len <= image.length) {
          return Uint8List.fromList(
              image.sublist(valueStart, valueStart + len));
        }
        // A zero entry is padding at the end of the area, not a parse failure:
        // stop scanning this area and move on to the next one.
        if (len == 0 && type == 0) break;
        p = valueStart + len;
      }

      if (areaMagic != _tlvProtInfoMagic) return null; // no more areas
      off += areaTotal;
    }
    return null;
  }
}
