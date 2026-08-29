import 'package:intl/intl.dart';

import '../config/environment.dart';

/// Dinero en unidades menores (centavos), como entero.
///
/// Toda la plata de la app se representa con `int` de centavos, NO con `double`.
/// `1234.56` no existe en punto flotante: se guarda el binario mas cercano, y
/// por eso `0.1 + 0.2` da `0.30000000000000004`. En un gasto suelto el error es
/// invisible, pero en sumas repetidas y comparaciones contra cero se nota.
///
/// Con enteros no hay error de representacion: las sumas son exactas, las
/// comparaciones contra cero son de verdad cero, y dos dispositivos calculan
/// siempre lo mismo.
class Money {
  Money._();

  static String get locale => Environment.appLocale;
  static String get currencyCode => Environment.currencyCode;

  /// Cuantas unidades menores tiene una unidad. 100 para monedas con centavos,
  /// 1 para las que no los usan (CLP, COP, PYG).
  static int minorUnitsFor(String code) => decimalDigitsFor(code) == 0 ? 1 : 100;

  static int get minorUnits => minorUnitsFor(currencyCode);

  /// Convierte centavos a la unidad mayor, SOLO para formatear.
  /// Nunca guardes ni sumes el resultado de esto.
  static double toMajor(int cents, {String? code}) =>
      cents / minorUnitsFor(code ?? currencyCode);

  /// Convierte un valor en unidades mayores a centavos, redondeando.
  /// Se usa al leer documentos viejos que guardaban `double`.
  static int fromMajor(num major, {String? code}) =>
      (major * minorUnitsFor(code ?? currencyCode)).round();

  /// `$ 1.234,56`
  static String format(int cents, {String? code, String? localeOverride}) {
    final resolvedCode = code ?? currencyCode;
    final digits = decimalDigitsFor(resolvedCode);

    // Simbolo adelante, siempre. CLDR lo pone AL FINAL en varios locales de la
    // region (es_UY da "1.234,56 $") y nadie escribe asi. Los separadores de
    // miles y decimales si vienen del locale, que es lo que realmente varia.
    return NumberFormat.currency(
      locale: localeOverride ?? locale,
      symbol: symbolFor(resolvedCode),
      decimalDigits: digits,
      customPattern: digits == 0 ? '¤ #,##0' : '¤ #,##0.00',
    ).format(toMajor(cents, code: resolvedCode));
  }

  /// Sin simbolo, para campos editables.
  static String formatPlain(int cents, {String? localeOverride}) {
    return NumberFormat.decimalPatternDigits(
      locale: localeOverride ?? locale,
      decimalDigits: decimalDigitsFor(currencyCode),
    ).format(toMajor(cents));
  }

  /// Lee un monto tipeado por el usuario y devuelve CENTAVOS.
  ///
  /// Acepta los dos convenios: `1.234,56` y `1,234.56` valen lo mismo.
  /// Devuelve null si no se puede interpretar.
  static int? parse(String input, {String? code}) {
    final s = input.replaceAll(RegExp(r'[^\d.,]'), '');
    if (s.isEmpty) return null;

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');

    String normalized;
    if (lastDot == -1 && lastComma == -1) {
      normalized = s;
    } else {
      final sep = lastDot > lastComma ? lastDot : lastComma;
      final decimals = s.length - sep - 1;
      final onlyOneKind = lastDot == -1 || lastComma == -1;

      // `1.234` / `1,234`: un precio no tiene tres decimales, es separador de miles.
      if (decimals == 3 && onlyOneKind) {
        normalized = s.replaceAll(RegExp(r'[.,]'), '');
      } else {
        final intPart = s.substring(0, sep).replaceAll(RegExp(r'[.,]'), '');
        final decPart = s.substring(sep + 1);
        normalized = '${intPart.isEmpty ? '0' : intPart}.$decPart';
      }
    }

    final major = double.tryParse(normalized);
    if (major == null) return null;
    return fromMajor(major, code: code);
  }

  static String symbolFor(String code) {
    return switch (code.toUpperCase()) {
      'UYU' || 'ARS' || 'MXN' || 'CLP' || 'COP' || 'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      'BRL' => r'R$',
      'PEN' => 'S/',
      'PYG' => '₲',
      'BOB' => 'Bs',
      _ => code.toUpperCase(),
    };
  }

  /// CLP, COP y PYG no usan centavos.
  static int decimalDigitsFor(String code) {
    return switch (code.toUpperCase()) {
      'CLP' || 'COP' || 'PYG' => 0,
      _ => 2,
    };
  }
}

/// Fechas en el idioma del usuario. `DateFormat` sin locale devolvia siempre
/// meses en ingles.
class AppDate {
  AppDate._();

  static String monthYear(DateTime d) =>
      DateFormat('MMMM yyyy', Money.locale).format(d);

  static String shortDate(DateTime d) =>
      DateFormat('d MMM yyyy', Money.locale).format(d);

  static String dayMonth(DateTime d) =>
      DateFormat('d MMM', Money.locale).format(d);

  static String longDate(DateTime d) =>
      DateFormat('EEEE d MMMM yyyy', Money.locale).format(d);
}
