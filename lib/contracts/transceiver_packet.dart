import 'dart:convert';
import 'dart:typed_data';

/// Priority levels for Transceiver Packets
enum PacketPriority {
  normal,
  tactical,
  emergency,
}

/// Compact binary packet (< 80 bytes typical) for offline local mesh links.
/// Conforms to Protobuf field tags and binary packing to minimize link bandwidth.
class TransceiverPacket {
  static const int tagPacketId = 1;     // String
  static const int tagSenderId = 2;     // String
  static const int tagText = 3;         // String (Transcribed voice payload)
  static const int tagPriority = 4;     // Varint (0 = normal, 1 = tactical, 2 = emergency)
  static const int tagTimestampMs = 5;  // Varint (epoch ms)
  static const int tagLanguage = 6;     // String (e.g. 'en', 'hi', 'te')
  static const int tagIntent = 7;       // String (e.g. 'STATUS', 'SOS', 'TALK')

  final String packetId;
  final String senderId;
  final String text;
  final PacketPriority priority;
  final int timestampMs;
  final String languageCode;
  final String intent;

  TransceiverPacket({
    required this.packetId,
    required this.senderId,
    required this.text,
    this.priority = PacketPriority.normal,
    int? timestampMs,
    this.languageCode = 'en',
    this.intent = 'TALK',
  }) : timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  bool get isEmergency => priority == PacketPriority.emergency;

  /// Serializes to binary Protobuf format
  Uint8List toProtobufBytes() {
    final builder = BytesBuilder(copy: false);

    void writeStringField(int tag, String value) {
      if (value.isEmpty) return;
      final bytes = utf8.encode(value);
      // Tag wire type 2 (length-delimited): (tag << 3) | 2
      _writeVarint(builder, (tag << 3) | 2);
      _writeVarint(builder, bytes.length);
      builder.add(bytes);
    }

    void writeVarintField(int tag, int value) {
      // Tag wire type 0 (varint): (tag << 3) | 0
      _writeVarint(builder, (tag << 3) | 0);
      _writeVarint(builder, value);
    }

    writeStringField(tagPacketId, packetId);
    writeStringField(tagSenderId, senderId);
    writeStringField(tagText, text);
    writeVarintField(tagPriority, priority.index);
    writeVarintField(tagTimestampMs, timestampMs);
    writeStringField(tagLanguage, languageCode);
    writeStringField(tagIntent, intent);

    return builder.toBytes();
  }

  /// Deserializes from binary Protobuf format
  static TransceiverPacket fromProtobufBytes(Uint8List data) {
    var offset = 0;
    String packetId = '';
    String senderId = '';
    String text = '';
    PacketPriority priority = PacketPriority.normal;
    int timestampMs = DateTime.now().millisecondsSinceEpoch;
    String languageCode = 'en';
    String intent = 'TALK';

    while (offset < data.length) {
      final key = _readVarint(data, offset);
      offset = key.newOffset;
      final tag = key.value >> 3;
      final wireType = key.value & 0x07;

      if (wireType == 0) {
        // Varint
        final res = _readVarint(data, offset);
        offset = res.newOffset;
        if (tag == tagPriority) {
          final idx = res.value.clamp(0, PacketPriority.values.length - 1);
          priority = PacketPriority.values[idx];
        } else if (tag == tagTimestampMs) {
          timestampMs = res.value;
        }
      } else if (wireType == 2) {
        // Length-delimited string/bytes
        final lenRes = _readVarint(data, offset);
        offset = lenRes.newOffset;
        final length = lenRes.value;
        final rawStrBytes = data.sublist(offset, offset + length);
        offset += length;
        final str = utf8.decode(rawStrBytes, allowMalformed: true);

        switch (tag) {
          case tagPacketId:
            packetId = str;
            break;
          case tagSenderId:
            senderId = str;
            break;
          case tagText:
            text = str;
            break;
          case tagLanguage:
            languageCode = str;
            break;
          case tagIntent:
            intent = str;
            break;
        }
      } else {
        // Unknown wire type - break to avoid infinite loop
        break;
      }
    }

    return TransceiverPacket(
      packetId: packetId.isNotEmpty ? packetId : 'pkt_${DateTime.now().millisecondsSinceEpoch}',
      senderId: senderId.isNotEmpty ? senderId : 'UNKNOWN',
      text: text,
      priority: priority,
      timestampMs: timestampMs,
      languageCode: languageCode.isNotEmpty ? languageCode : 'en',
      intent: intent.isNotEmpty ? intent : 'TALK',
    );
  }

  static void _writeVarint(BytesBuilder builder, int value) {
    var v = value;
    while (v >= 0x80) {
      builder.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    builder.addByte(v & 0x7F);
  }

  static ({int value, int newOffset}) _readVarint(Uint8List data, int offset) {
    var result = 0;
    var shift = 0;
    var cur = offset;
    while (cur < data.length) {
      final byte = data[cur++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (value: result, newOffset: cur);
  }
}
