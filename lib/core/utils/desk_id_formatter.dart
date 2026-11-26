/// Utilitários para formatação de código DeskID, sanitização de nomes de arquivos e validação de endpoints.
class DeskIdFormatter {
  DeskIdFormatter._();

  static const Set<String> _reservedWindowsNames = <String>{
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Extrai apenas os dígitos numéricos de uma string.
  static String extractDigits(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final int c = raw.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        sb.writeCharCode(c);
      }
    }
    return sb.toString();
  }

  /// Verifica se o alvo informado corresponde a um DeskID válido de 9 dígitos.
  static bool isValidDeskId(String? raw) {
    if (raw == null || raw.contains(':')) return false;
    final String digits = extractDigits(raw);
    return digits.length == 9;
  }

  /// Formata um DeskID de 9 dígitos no padrão visual "000 000 000".
  static String format(String? rawId) {
    if (rawId == null || rawId.isEmpty) return '000 000 000';
    final String clean = extractDigits(rawId);
    if (clean.length == 9) {
      return '${clean.substring(0, 3)} ${clean.substring(3, 6)} ${clean.substring(6, 9)}';
    }
    return rawId.trim();
  }

  /// Sanitiza um nome de arquivo recebido remotamente contra Path Traversal e dispositivos reservados do Windows.
  static String sanitizeFileName(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) {
      return 'arquivo_${DateTime.now().millisecondsSinceEpoch}.dat';
    }

    // Remove qualquer caminho anterior (/ ou \)
    String normalized = rawName.replaceAll('\\', '/').trim();
    if (normalized.contains('/')) {
      normalized = normalized.split('/').last;
    }

    // Substitui caracteres inválidos ou de controle
    final StringBuffer cleaned = StringBuffer();
    const String invalidChars = '<>:"/\\|?*';
    for (int i = 0; i < normalized.length; i++) {
      final int code = normalized.codeUnitAt(i);
      final String ch = normalized[i];
      if (code < 32 || invalidChars.contains(ch)) {
        cleaned.write('_');
      } else {
        cleaned.write(ch);
      }
    }

    String result = cleaned.toString().replaceAll('..', '_').trim();
    while (result.endsWith('.')) {
      result = result.substring(0, result.length - 1).trim();
    }

    if (result.isEmpty) {
      return 'arquivo_${DateTime.now().millisecondsSinceEpoch}.dat';
    }

    final int dotIdx = result.lastIndexOf('.');
    final String baseName = (dotIdx > 0 ? result.substring(0, dotIdx) : result).toUpperCase();
    if (_reservedWindowsNames.contains(baseName)) {
      result = '_$result';
    }

    if (result.length > 120) {
      final String ext = dotIdx > 0 ? result.substring(dotIdx) : '';
      final int keep = (100 - ext.length).clamp(16, 100);
      result = '${result.substring(0, keep)}$ext';
    }

    return result;
  }

  /// Faz o parse seguro de um endpoint "host:porta".
  static ({String host, int port})? parseEndpoint(String? endpoint, {int defaultPort = 7070}) {
    if (endpoint == null || endpoint.trim().isEmpty) return null;
    final String clean = endpoint.trim();
    final int lastColon = clean.lastIndexOf(':');
    if (lastColon <= 0) {
      return (host: clean, port: defaultPort);
    }
    final String hostPart = clean.substring(0, lastColon).trim();
    final String portPart = clean.substring(lastColon + 1).trim();
    final int? parsedPort = int.tryParse(portPart);
    if (hostPart.isEmpty || parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      return null;
    }
    return (host: hostPart, port: parsedPort);
  }
}
