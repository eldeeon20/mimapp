/// Constantes OAuth2 del cliente propio de pr_app.
class ColabConfig {
  ColabConfig._();

  static const clientId =
      '';
  static const clientSecret = '';

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
