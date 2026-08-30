import 'package:flutter_dotenv/flutter_dotenv.dart';

enum AppEnvironment { development, staging, production }

class Environment {
  Environment._();

  /// `dotenv.env` lanza si nunca se llamó a `load()`, cosa que pasa en los
  /// tests unitarios. Leer siempre por acá evita acoplar cualquier clase que
  /// use config a que la app haya arrancado.
  static String? _get(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  static AppEnvironment get current {
    return switch (_get('APP_ENV') ?? 'development') {
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      _ => AppEnvironment.development,
    };
  }

  static bool get isDev => current == AppEnvironment.development;
  static bool get isProd => current == AppEnvironment.production;

  static String get ollamaBaseUrl =>
      _get('OLLAMA_BASE_URL') ?? 'http://localhost:11434';

  static String get ollamaModel => _get('OLLAMA_MODEL') ?? 'llama3.2';

  static String get ocrProvider => _get('OCR_PROVIDER') ?? 'local';

  static String get ollamaOcrModel => _get('OLLAMA_OCR_MODEL') ?? 'glm-ocr';

  /// Proveedor de IA activo: `ollama` (dev) o `proxy` (produccion).
  static String get aiProviderName => _get('AI_PROVIDER') ?? 'ollama';

  /// URL del proxy server-side que guarda las claves. Vacia en desarrollo.
  static String get aiProxyBaseUrl => _get('AI_PROXY_BASE_URL') ?? '';

  /// Convierte el texto crudo del OCR en estructura usando un modelo de texto,
  /// en vez de depender solo del parser de regex.
  static bool get enableAiStructuring => _get('ENABLE_AI_STRUCTURING') == 'true';

  static bool get enableAiClassification =>
      _get('ENABLE_AI_CLASSIFICATION') == 'true';

  static bool get enableAiInsights => _get('ENABLE_AI_INSIGHTS') == 'true';

  /// Si se intenta subir la foto a Firebase Storage.
  ///
  /// Apagado por defecto **a proposito**: Storage exige plan Blaze en proyectos
  /// nuevos y este proyecto esta en Spark. Con esto prendido, cada guardado
  /// hacia una subida condenada a fallar, con hasta 45 segundos de timeout, en
  /// el camino critico de guardar un ticket. La foto vive en Firestore.
  ///
  /// Se enciende poniendo ENABLE_CLOUD_STORAGE=true, para el dia que el
  /// proyecto pase a Blaze.
  static bool get enableCloudStorage =>
      _get('ENABLE_CLOUD_STORAGE') == 'true';

  static double get ocrConfidenceThreshold =>
      double.tryParse(_get('OCR_CONFIDENCE_THRESHOLD') ?? '0.7') ?? 0.7;

  /// Locale para formatear dinero y fechas. Ej: `es_AR`, `es_MX`, `en_US`.
  static String get appLocale => _get('APP_LOCALE') ?? 'es_AR';

  /// Moneda por defecto de los montos. Ej: `ARS`, `MXN`, `USD`.
  static String get currencyCode => _get('CURRENCY_CODE') ?? 'ARS';

  /// `true` cuando los tickets usan DD/MM (LatAm, Europa).
  static bool get datesAreDayFirst => (_get('DATE_DAY_FIRST') ?? 'true') != 'false';
}
