import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../insights/domain/entities/monthly_spending_summary.dart';
import '../../data/repositories/expense_repository_impl.dart';
import '../../domain/entities/expense_entity.dart';

part 'expense_provider.g.dart';

/// Cuántos meses hacia atrás se mantienen en memoria.
/// Antes se escuchaba TODO el historial del usuario, sin límite.
const _windowMonths = 12;

@riverpod
Stream<List<ExpenseEntity>> expensesStream(Ref ref) {
  // Observa la sesion: al cambiar de cuenta el stream se reconstruye en vez de
  // seguir sirviendo los datos del usuario anterior.
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return Stream.value(const []);

  return ref.watch(expenseRepositoryProvider).watchExpenses(
        windowMonths: _windowMonths,
      );
}

/// Alta, edicion y borrado de gastos manuales.
@riverpod
class ExpenseActions extends _$ExpenseActions {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Devuelve null si salio bien, o el mensaje de error.
  Future<String?> addManual({
    required int amountCents,
    required ExpenseCategory category,
    required DateTime date,
    String? storeName,
    String? note,
  }) async {
    state = const AsyncValue.loading();
    final result = await ref.read(expenseRepositoryProvider).addManualExpense(
          amountCents: amountCents,
          category: category,
          date: date,
          storeName: storeName,
          note: note,
        );
    // El valor que se devuelve sale SIEMPRE del resultado. Antes habia un
    // `if (!ref.mounted) return null` antes del fold, y como en el contrato de
    // este metodo null significa EXITO, una escritura fallida mientras la
    // pantalla se cerraba se reportaba como guardada: el gasto se perdia y la
    // UI decia que estaba todo bien.
    //
    // Lo que si depende de `mounted` es tocar `state`: eso revienta si el
    // provider ya se descarto.
    final mensaje = result.fold((f) => f.message, (_) => null);
    if (ref.mounted) {
      state = mensaje == null
          ? const AsyncValue.data(null)
          : AsyncValue.error(mensaje, StackTrace.current);
    }
    return mensaje;
  }

  Future<String?> delete(String id) async {
    state = const AsyncValue.loading();
    final result = await ref.read(expenseRepositoryProvider).deleteExpense(id);
    // El valor que se devuelve sale SIEMPRE del resultado. Antes habia un
    // `if (!ref.mounted) return null` antes del fold, y como en el contrato de
    // este metodo null significa EXITO, una escritura fallida mientras la
    // pantalla se cerraba se reportaba como guardada: el gasto se perdia y la
    // UI decia que estaba todo bien.
    //
    // Lo que si depende de `mounted` es tocar `state`: eso revienta si el
    // provider ya se descarto.
    final mensaje = result.fold((f) => f.message, (_) => null);
    if (ref.mounted) {
      state = mensaje == null
          ? const AsyncValue.data(null)
          : AsyncValue.error(mensaje, StackTrace.current);
    }
    return mensaje;
  }
}

@riverpod
MonthlySpendingSummary currentMonthSummary(Ref ref) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  return MonthlySpendingSummary.from(expenses, DateTime.now());
}

@riverpod
MonthlySpendingSummary previousMonthSummary(Ref ref) {
  final expenses = ref.watch(expensesStreamProvider).value ?? const [];
  final now = DateTime.now();
  return MonthlySpendingSummary.from(expenses, DateTime(now.year, now.month - 1));
}

@riverpod
Map<ExpenseCategory, int> categoryTotalsCurrentMonth(Ref ref) {
  return ref.watch(currentMonthSummaryProvider).categoryTotals;
}

@riverpod
int totalSpendingCurrentMonth(Ref ref) {
  return ref.watch(currentMonthSummaryProvider).totalCents;
}
