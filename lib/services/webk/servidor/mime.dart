/// MIME para WebK: extensión → Content-Type del servidor local.
class MimeUtil {
  MimeUtil._();

  static const _mapa = <String, String>{
    'html': 'text/html; charset=utf-8',
    'htm': 'text/html; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'js': 'application/javascript; charset=utf-8',
    'mjs': 'application/javascript; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
    'md': 'text/markdown; charset=utf-8',
    'xml': 'application/xml; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
    'wasm': 'application/wasm',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
  };

  /// Content-Type por nombre de archivo. Desconocido → octet-stream.
  static String deNombre(String nombre) {
    final n = nombre.toLowerCase();
    final punto = n.lastIndexOf('.');
    if (punto < 0) return 'application/octet-stream';
    return _mapa[n.substring(punto + 1)] ?? 'application/octet-stream';
  }

  /// ¿Es texto legible (para preview/parseo)?
  static bool esTexto(String mime) =>
      mime.startsWith('text/') ||
      mime.contains('json') ||
      mime.contains('javascript') ||
      mime.contains('xml');
}
