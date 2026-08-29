class AppConstants {
  AppConstants._();

  // Firestore collections
  static const String usersCollection = 'users';
  static const String receiptsCollection = 'receipts';
  static const String expensesCollection = 'expenses';
  static const String insightsCollection = 'insights';

  // Storage paths
  static const String receiptImagesPath = 'receipt_images';

  // Image compression
  static const int imageMaxWidth = 1920;
  static const int imageMaxHeight = 1920;
  static const int imageQuality = 80;
  static const int imageMaxSizeKb = 500;

  // AI prompts
  /// Encuadre descriptivo y educativo a proposito. Antes decia "personal
  /// finance advisor", y dar consejo financiero personalizado tiene
  /// implicaciones regulatorias segun el pais. Describimos patrones, no
  /// recomendamos decisiones.
  static const String generateInsightsSystemPrompt = '''
Analizas patrones de gasto y los describes de forma clara y util.

Reglas:
- Escribi en espanol rioplatense, breve y directo. Sin gerundios de relleno.
- DESCRIBI lo que muestran los numeros. No des consejo financiero ni de inversion.
- No inventes cifras: usa solamente los numeros que te paso.
- Cada observacion tiene que ser especifica y accionable. "Gastaste mucho en
  delivery" no sirve; "el delivery fue el 28% del mes, repartido en 11 pedidos"
  si.
- Responde en formato JSON.
''';

  // Pagination
  static const int receiptsPageSize = 20;
  static const int expensesWindowSize = 1000;

  // Cache TTL
  static const Duration insightsCacheDuration = Duration(hours: 6);
  static const Duration dashboardCacheDuration = Duration(minutes: 30);
}

