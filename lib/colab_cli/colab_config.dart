import '../services/settings.dart';

/// OAuth2 del cliente propio de pr_app.
///
/// Las llaves embebidas son el default; el usuario puede poner las suyas
/// a mano con el botón + del diálogo (se guardan cifradas en Settings y
/// tienen prioridad sobre las embebidas).
class ColabConfig {
  ColabConfig._();

  static const _embeddedClientId = '';
  static const _embeddedClientSecret = '';

  /// Llaves manuales del usuario (vacío = no hay).
  static String get customClientId => Settings.instance.colabClientId.trim();
  static String get customClientSecret =>
      Settings.instance.colabClientSecret.trim();

  /// ¿Se están usando llaves manuales en vez de las embebidas?
  static bool get usingCustomKeys =>
      customClientId.isNotEmpty && customClientSecret.isNotEmpty;

  static String get clientId =>
      usingCustomKeys ? customClientId : _embeddedClientId;
  static String get clientSecret =>
      usingCustomKeys ? customClientSecret : _embeddedClientSecret;

  /// Loopback: la app abre un servidor local y Google redirige acá
  /// (el navegador corre en el mismo dispositivo).
  static const redirectHost = '127.0.0.1';

  static const authUri = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const tokenUri = 'https://oauth2.googleapis.com/token';

  static const scopes = 'openid '
      'https://www.googleapis.com/auth/userinfo.profile '
      'https://www.googleapis.com/auth/userinfo.email '
      'https://www.googleapis.com/auth/cloud-platform '
      'https://www.googleapis.com/auth/colaboratory '
      'https://www.googleapis.com/auth/drive.file';

  static const colabHost = 'colab.research.google.com';
  static const keepAliveInterval = Duration(seconds: 60);
  static const keepAliveTimeout = Duration(seconds: 10);
  static const keepAliveMaxDuration = Duration(hours: 24);
  static const tokenRefreshMargin = Duration(seconds: 60);
}
