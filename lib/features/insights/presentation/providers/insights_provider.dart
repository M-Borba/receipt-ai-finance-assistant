import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../services/ai/ai_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../expenses/presentation/providers/mes_actual_provider.dart';
import '../../domain/entities/insight_entity.dart';
import '../../domain/entities/monthly_spending_summary.dart';
import '../../domain/insights_locales.dart';

part 'insights_provider.g.dart';

/// Lo que muestran el dashboard y la pantalla de insights: los calculados
/// primero, que estan siempre, y despues los de la IA si llegaron.
///
/// No espera a la IA: mientras genera (o cuando falla, que en produccion es
/// siempre) se ven los calculados igual. Cuando responde, este provider se
/// recalcula solo porque la mira con `watch`.
@riverpod
Future<List<InsightEntity>> monthlyInsights(Ref ref) async {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return const [];

  final gastos = ref.watch(expensesStreamProvider).value ?? const [];
  final mes = ref.watch(mesActualProvider);
  // El dia sale del reloj, pero acotado al mes de MesActual: si la pestana
  // quedo abierta y el reloj ya paso al mes siguiente, se toma el ultimo dia
  // del mes que se esta mostrando, en vez de mezclar dos meses.
  final ahora = DateTime.now();
  final hoy = ahora.year == mes.year && ahora.month == mes.month
      ? ahora
      : DateTime(mes.year, mes.month + 1, 0, 12);

  return [
    ...insightsLocales(gastos: gastos, hoy: hoy, userId: userId),
    ...?ref.watch(aiInsightsProvider).value,
  ];
}

/// Los gastos fijos detectados, para ofrecer el recordatorio en el calendario.
@riverpod
List<GastoFijo> gastosFijos(Ref ref) {
  final gastos = ref.watch(expensesStreamProvider).value ?? const [];
  final mes = ref.watch(mesActualProvider);
  final ahora = DateTime.now();
  final hoy = ahora.year == mes.year && ahora.month == mes.month
      ? ahora
      : DateTime(mes.year, mes.month + 1, 0, 12);
  return detectarFijos(gastos: gastos, hoy: hoy);
}

/// Genera los insights del mes con IA.
///
/// Depende de un único value object ([MonthlySpendingSummary]) en vez de un
/// `Map` y un `double` sueltos. Antes, cada snapshot de Firestore producía un
/// `Map` nuevo que nunca era `==` al anterior, así que el provider se
/// invalidaba y disparaba otra llamada al modelo: latencia y costo por cada
/// escritura, incluida la del propio recibo recién escaneado.
@riverpod
Future<List<InsightEntity>> aiInsights(Ref ref) async {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return const [];

  final summary = ref.watch(currentMonthSummaryProvider);
  if (summary.isEmpty) return const [];

  // Mantiene el resultado vivo un rato: volver al dashboard no debe repagar
  // la generación.
  final link = ref.keepAlive();
  ref.onDispose(link.close);

  final aiService = ref.watch(aiServiceProvider);

  return aiService.generateMonthlyInsights(
    userId: userId,
    categoryTotals: summary.categoryTotals,
    totalCents: summary.totalCents,
    // Comercios del MES, no de todo el historial: el reporte decía ser
    // mensual y mezclaba períodos.
    topMerchants: summary.topMerchants.map((m) => m.toPromptMap()).toList(),
    month: summary.month,
  );
}
