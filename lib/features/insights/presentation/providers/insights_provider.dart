import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../services/ai/ai_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../domain/entities/insight_entity.dart';
import '../../domain/entities/monthly_spending_summary.dart';

part 'insights_provider.g.dart';

/// Genera los insights del mes con IA.
///
/// Depende de un único value object ([MonthlySpendingSummary]) en vez de un
/// `Map` y un `double` sueltos. Antes, cada snapshot de Firestore producía un
/// `Map` nuevo que nunca era `==` al anterior, así que el provider se
/// invalidaba y disparaba otra llamada al modelo: latencia y costo por cada
/// escritura, incluida la del propio recibo recién escaneado.
@riverpod
Future<List<InsightEntity>> monthlyInsights(Ref ref) async {
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
