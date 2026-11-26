import 'dart:typed_data';

import '../../core/constants/protocol_constants.dart';
import '../../core/crypto/session_cipher.dart';
import '../../domain/entities/session_models.dart';

/// Pacote decodificado do stream de sessão.
class DecodedPacketFrame {
  final PacketType type;
  final Uint8List payload;

  const DecodedPacketFrame({
    required this.type,
    required this.payload,
  });
}

/// Codificador e decodificador de pacotes binários com cabeçalho de 5 bytes
/// (`[uint8 PacketType][int32 Little-Endian Length][byte[] Payload]`),
/// 100% compatível com `PacketFrameIO` do DeskView original e com suporte a cifragem de sessão.
class PacketFrameIO {
  PacketFrameIO._();

  /// Empacota um [PacketType] e [payload] no formato binário de 5 bytes de cabeçalho.
  static Uint8List encodeFrame(
    PacketType type,
    List<int>? payload, {
    String? encryptionKey,
  }) {
    Uint8List body = payload != null ? Uint8List.fromList(payload) : Uint8List(0);
    int typeCode = type.code;

    // Se uma chave de criptografia de sessão estiver ativa (exceto no Handshake inicial),
    // sela o pacote com nonce + stream cipher + tag HMAC-SHA256 e marca o bit 0x80 no tipo.
    if (encryptionKey != null &&
        encryptionKey.isNotEmpty &&
        type != PacketType.handshakeAuthRequest &&
        type != PacketType.handshakeAuthResponse) {
      body = SessionCipher.sealPacket(body, encryptionKey);
      typeCode |= 0x80;
    }

    final Uint8List frame = Uint8List(5 + body.length);
    final ByteData bd = ByteData.sublistView(frame);
    bd.setUint8(0, typeCode);
    bd.setInt32(1, body.length, Endian.little);
    if (body.isNotEmpty) {
      frame.setRange(5, 5 + body.length, body);
    }
    return frame;
  }
}

/// Acumulador de stream capaz de reconstruir pacotes completos mesmo quando fragmentados
/// em múltiplos pacotes TCP ou blocos de Relay.
class PacketStreamDecoder {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  String? encryptionKey;

  PacketStreamDecoder({this.encryptionKey});

  /// Alimenta novos bytes recebidos da rede e retorna todos os pacotes completos prontos.
  List<DecodedPacketFrame> addChunk(List<int> chunk) {
    if (chunk.isNotEmpty) {
      _buffer.add(chunk);
    }

    final Uint8List allBytes = _buffer.takeBytes();
    int offset = 0;
    final List<DecodedPacketFrame> frames = <DecodedPacketFrame>[];

    while (offset + 5 <= allBytes.length) {
      final ByteData bd = ByteData.sublistView(allBytes, offset, offset + 5);
      final int rawType = bd.getUint8(0);
      final int length = bd.getInt32(1, Endian.little);

      if (length < 0 || length > ProtocolConstants.maxPacketPayloadBytes) {
        // Pacote malformado ou corrompido: descarta buffer para evitar travamento
        return frames;
      }

      if (offset + 5 + length > allBytes.length) {
        // Ainda aguardando o restante do payload no próximo chunk TCP
        break;
      }

      final bool isEncryptedFrame = (rawType & 0x80) != 0;
      final PacketType type = PacketType.fromCode(rawType & 0x7f);
      Uint8List payload = allBytes.sublist(offset + 5, offset + 5 + length);
      offset += 5 + length;

      if (isEncryptedFrame && encryptionKey != null && encryptionKey!.isNotEmpty) {
        final Uint8List? opened = SessionCipher.openPacket(payload, encryptionKey!);
        if (opened == null) {
          // Falha na verificação HMAC do pacote: descarta pacote adulterado
          continue;
        }
        payload = opened;
      }

      frames.add(DecodedPacketFrame(type: type, payload: payload));
    }

    if (offset < allBytes.length) {
      _buffer.add(allBytes.sublist(offset));
    }

    return frames;
  }

  void clear() {
    _buffer.clear();
  }
}
