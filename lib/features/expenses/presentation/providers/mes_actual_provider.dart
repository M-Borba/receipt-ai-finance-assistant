import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mes_actual_provider.g.dart';

/// El mes que la app está mostrando. **Única fuente de verdad.**
///
/// Antes cada provider y cada pantalla llamaba a `DateTime.now()` por su
/// cuenta. Los providers de totales solo se recalculan cuando Firestore emite,
/// y `snapshots()` no emite si no cambió nada; el encabezado, en cambio, se
/// recalcula en cada build. Resultado: el 1 de septiembre a la mañana, con la
/// pestaña abierta desde el 31, veías el total de agosto bajo el título
/// "septiembre", y la alerta de presupuesto excedido con el presupuesto
/// realmente en cero.
///
/// Ahora todos leen de acá, así que el número y el título nunca discrepan.
@riverpod
class MesActual extends _$MesActual {
  Timer? _timer;

  @override
  DateTime build() {
    ref.onDispose(() => _timer?.cancel());
    _programar();
    return mesDe(DateTime.now());
  }

  /// El primer instante del mes de [d]. Se compara por mes, no por día.
  static DateTime mesDe(DateTime d) => DateTime(d.year, d.month);

  void _programar() {
    _timer?.cancel();
    final ahora = DateTime.now();
    // `month + 1` con month == 12 da enero del año siguiente: DateTime
    // normaliza el desborde, así que no hace falta el caso especial.
    final proximo = DateTime(ahora.year, ahora.month + 1);
    _timer = Timer(
      proximo.difference(ahora) + const Duration(seconds: 1),
      () {
        state = mesDe(DateTime.now());
        _programar();
      },
    );
  }

  /// Vuelve a mirar el reloj.
  ///
  /// Hace falta porque el timer **no corre con la app suspendida**: en el
  /// celular, o en una pestaña en segundo plano, el navegador lo congela. Sin
  /// esto, volver a la app después de dos días seguiría mostrando el mes viejo.
  void refrescar() {
    final ahora = mesDe(DateTime.now());
    if (ahora != state) state = ahora;
    _programar();
  }
}
