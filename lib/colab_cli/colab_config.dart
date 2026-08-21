/// Constantes OAuth2 del Google Cloud SDK (mismas que usa gcloud/colab-cli).
class ColabConfig {
  ColabConfig._();

  static const clientId =
      '764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com';
  static const clientSecret = 'd-FL95Q19q7MQmFpd7hHD0Ty';
  static const redirect = 'http://localhost';
  static const remoteRedirect =
      'https://sdk.cloud.google.com/applicationdefaultauthcode.html';
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
