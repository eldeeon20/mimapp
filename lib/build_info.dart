/// Hash corto del commit inyectado por CI (--dart-define=GIT_SHA=...).
const String kSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
