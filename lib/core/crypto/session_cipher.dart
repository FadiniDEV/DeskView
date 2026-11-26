import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Motor criptográfico autónomo em Dart puro (SHA-256 FIPS 180-4, HMAC-SHA256 RFC 2104,
/// assinatura de sinalização MQTT, Challenge-Response e cifragem autenticada de pacotes de sessão).
class SessionCipher {
  SessionCipher._();

  static const String _signalSecret = 'DeskView.V2.Signal.HMAC.2026';
  static const String _storageSecret = 'DeskView.V3.LocalSecretVault.2026';

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

  /// Calcula o digest SHA-256 (32 bytes) de um buffer arbitrário.
  static Uint8List sha256Bytes(List<int> input) {
    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    final int bitLen = input.length * 8;
    final int padLen = ((input.length + 9 + 63) ~/ 64) * 64;
    final Uint8List padded = Uint8List(padLen);
    padded.setRange(0, input.length, input);
    padded[input.length] = 0x80;

    final ByteData bd = ByteData.sublistView(padded);
    bd.setUint32(padLen - 8, (bitLen ~/ 0x100000000) & 0xffffffff, Endian.big);
    bd.setUint32(padLen - 4, bitLen & 0xffffffff, Endian.big);

    final Int32List w = Int32List(64);

    for (int chunkOffset = 0; chunkOffset < padLen; chunkOffset += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = bd.getUint32(chunkOffset + (i * 4), Endian.big);
      }
      for (int i = 16; i < 64; i++) {
        final int s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ ((w[i - 15] & 0xffffffff) >>> 3);
        final int s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ ((w[i - 2] & 0xffffffff) >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (int i = 0; i < 64; i++) {
        final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final int ch = (e & f) ^ ((~e) & g);
        final int temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final int maj = (a & b) ^ (a & c) ^ (b & c);
        final int temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final Uint8List out = Uint8List(32);
    final ByteData outBd = ByteData.sublistView(out);
    outBd.setUint32(0, h0, Endian.big);
    outBd.setUint32(4, h1, Endian.big);
    outBd.setUint32(8, h2, Endian.big);
    outBd.setUint32(12, h3, Endian.big);
    outBd.setUint32(16, h4, Endian.big);
    outBd.setUint32(20, h5, Endian.big);
    outBd.setUint32(24, h6, Endian.big);
    outBd.setUint32(28, h7, Endian.big);
    return out;
  }

  /// Calcula o HMAC-SHA256 (RFC 2104) de [message] usando [key].
  static Uint8List hmacSha256Bytes(List<int> key, List<int> message) {
    const int blockSize = 64;
    Uint8List normalizedKey = Uint8List.fromList(key);
    if (normalizedKey.length > blockSize) {
      normalizedKey = sha256Bytes(normalizedKey);
    }
    final Uint8List keyBlock = Uint8List(blockSize);
    keyBlock.setRange(0, normalizedKey.length, normalizedKey);

    final Uint8List oKeyPad = Uint8List(blockSize);
    final Uint8List iKeyPad = Uint8List(blockSize);
    for (int i = 0; i < blockSize; i++) {
      oKeyPad[i] = keyBlock[i] ^ 0x5c;
      iKeyPad[i] = keyBlock[i] ^ 0x36;
    }

    final Uint8List innerInput = Uint8List(blockSize + message.length);
    innerInput.setRange(0, blockSize, iKeyPad);
    innerInput.setRange(blockSize, innerInput.length, message);
    final Uint8List innerHash = sha256Bytes(innerInput);

    final Uint8List outerInput = Uint8List(blockSize + innerHash.length);
    outerInput.setRange(0, blockSize, oKeyPad);
    outerInput.setRange(blockSize, outerInput.length, innerHash);
    return sha256Bytes(outerInput);
  }

  /// Converte bytes em hexadecimal minúsculo.
  static String bytesToHex(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final int b in bytes) {
      sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Gera um código DeskID determinístico de 9 dígitos a partir de uma semente de hardware.
  static String generateDeterministicDeskId(String hardwareSeed) {
    final Uint8List hash = sha256Bytes(utf8.encode(hardwareSeed));
    final ByteData bd = ByteData.sublistView(hash);
    final int rawVal = bd.getUint32(0, Endian.little);
    final int nineDigits = (rawVal % 900000000) + 100000000;
    return nineDigits.toString().padLeft(9, '0');
  }

  /// Gera uma assinatura HMAC-SHA256 de 16 caracteres compatível com a sinalização global DeskView.
  static String signSignalPayload(String body) {
    final Uint8List mac = hmacSha256Bytes(utf8.encode(_signalSecret), utf8.encode(body));
    return bytesToHex(mac).substring(0, 16);
  }

  /// Verifica de forma constante se a assinatura de um pacote de sinalização é legítima.
  static bool verifySignalSignature(String signature, String body) {
    final String expected = signSignalPayload(body);
    return constantTimeEquals(signature.toLowerCase(), expected.toLowerCase());
  }

  /// Calcula o hash de senha desassistida compatível com `IdentityManager.HashPassword` (Base64 HMAC-SHA256).
  static String hashPasswordWithSalt(String plainPassword, String salt) {
    final Uint8List mac = hmacSha256Bytes(utf8.encode(salt), utf8.encode(plainPassword));
    return base64Encode(mac);
  }

  /// Gera um salt criptográfico aleatório em Base64.
  static String generateRandomSalt([int length = 16]) {
    final Random rng = _createSecureOrFallbackRandom();
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// Gera um nonce hexadecimal aleatório para sessões e desafios.
  static String generateNonceHex([int byteLength = 16]) {
    final Random rng = _createSecureOrFallbackRandom();
    final Uint8List bytes = Uint8List(byteLength);
    for (int i = 0; i < byteLength; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytesToHex(bytes);
  }

  /// Cifra e autentica um payload binário para tráfego seguro em canais Relay ou WAN.
  /// Formato de saída: [12 bytes Nonce] + [Payload XOR Keystream SHA-256 CTR] + [16 bytes Tag HMAC-SHA256].
  static Uint8List sealPacket(Uint8List plainPayload, String sessionKey) {
    final Random rng = _createSecureOrFallbackRandom();
    final Uint8List nonce = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      nonce[i] = rng.nextInt(256);
    }

    final Uint8List keyBytes = sha256Bytes(utf8.encode(sessionKey));
    final Uint8List cipherText = _xorCounterStream(plainPayload, keyBytes, nonce);

    final BytesBuilder authBuilder = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(cipherText);
    final Uint8List fullMac = hmacSha256Bytes(keyBytes, authBuilder.toBytes());

    final Uint8List output = Uint8List(12 + cipherText.length + 16);
    output.setRange(0, 12, nonce);
    output.setRange(12, 12 + cipherText.length, cipherText);
    output.setRange(12 + cipherText.length, output.length, fullMac.sublist(0, 16));
    return output;
  }

  /// Verifica a tag HMAC e decifra um pacote recebido em canal Relay ou WAN.
  /// Retorna `null` se o pacote foi adulterado ou a chave for inválida.
  static Uint8List? openPacket(Uint8List sealedPayload, String sessionKey) {
    if (sealedPayload.length < 28) return null;
    final Uint8List nonce = sealedPayload.sublist(0, 12);
    final Uint8List cipherText = sealedPayload.sublist(12, sealedPayload.length - 16);
    final Uint8List receivedTag = sealedPayload.sublist(sealedPayload.length - 16);

    final Uint8List keyBytes = sha256Bytes(utf8.encode(sessionKey));
    final BytesBuilder authBuilder = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(cipherText);
    final Uint8List expectedTag = hmacSha256Bytes(keyBytes, authBuilder.toBytes()).sublist(0, 16);

    int diff = 0;
    for (int i = 0; i < 16; i++) {
      diff |= (receivedTag[i] ^ expectedTag[i]);
    }
    if (diff != 0) return null;

    return _xorCounterStream(cipherText, keyBytes, nonce);
  }

  static Uint8List _xorCounterStream(Uint8List input, Uint8List keyBytes, Uint8List nonce) {
    final Uint8List out = Uint8List(input.length);
    final Uint8List blockInput = Uint8List(keyBytes.length + nonce.length + 4);
    blockInput.setRange(0, keyBytes.length, keyBytes);
    blockInput.setRange(keyBytes.length, keyBytes.length + nonce.length, nonce);
    final ByteData counterBd = ByteData.sublistView(blockInput);

    int blockCounter = 0;
    int offset = 0;
    while (offset < input.length) {
      counterBd.setUint32(keyBytes.length + nonce.length, blockCounter++, Endian.big);
      final Uint8List keystreamBlock = sha256Bytes(blockInput);
      final int chunk = min(32, input.length - offset);
      for (int i = 0; i < chunk; i++) {
        out[offset + i] = input[offset + i] ^ keystreamBlock[i];
      }
      offset += chunk;
    }
    return out;
  }

  /// Protege um segredo localmente para persistência em disco.
  static String encryptLocalSecret(String plainText) {
    if (plainText.isEmpty) return '';
    final Uint8List sealed = sealPacket(Uint8List.fromList(utf8.encode(plainText)), _storageSecret);
    return 'DV3:${base64Encode(sealed)}';
  }

  /// Recupera um segredo local (compatível com `DV3:`, `B64:` e Base64 legado).
  static String decryptLocalSecret(String cipherText) {
    if (cipherText.isEmpty) return '';
    try {
      if (cipherText.startsWith('DV3:')) {
        final Uint8List raw = base64Decode(cipherText.substring(4));
        final Uint8List? opened = openPacket(raw, _storageSecret);
        return opened != null ? utf8.decode(opened) : '';
      }
      if (cipherText.startsWith('B64:')) {
        return utf8.decode(base64Decode(cipherText.substring(4)));
      }
      if (cipherText.startsWith('DPAPI:')) {
        // Registros legados DPAPI específicos da conta Windows
        return '';
      }
      return utf8.decode(base64Decode(cipherText));
    } catch (_) {
      return '';
    }
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Random _createSecureOrFallbackRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random(DateTime.now().microsecondsSinceEpoch);
    }
  }
}
