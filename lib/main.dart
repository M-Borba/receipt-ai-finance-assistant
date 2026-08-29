import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config/environment.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Config versionada y sin secretos. Antes esto apuntaba a `.env`, que estaba
  // gitignoreado y era asset obligatorio: ningun clone limpio ni CI compilaba.
  try {
    await dotenv.load(fileName: 'assets/config/app.env');
  } catch (e) {
    debugPrint('No se pudo cargar app.env, se usan los defaults: $e');
  }

  // Sin esto, DateFormat con locale es_* lanza en runtime.
  await initializeDateFormatting(Environment.appLocale);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    const ProviderScope(
      child: ReceiptAIApp(),
    ),
  );
}
