import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/environment.dart';
import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';

class ReceiptAIApp extends ConsumerWidget {
  const ReceiptAIApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'ReceiptAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      // Sin esto el date picker y los widgets de Material salen en inglés
      // aunque el resto de la app formatee en español.
      locale: _localeFromEnv(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es'),
        Locale('en'),
      ],
      routerConfig: router,
    );
  }

  static Locale _localeFromEnv() {
    final parts = Environment.appLocale.split(RegExp(r'[_-]'));
    return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  }
}
