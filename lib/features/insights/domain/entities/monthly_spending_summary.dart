import 'package:equatable/equatable.dart';

import '../../../expenses/domain/entities/expense_entity.dart';

/// Resumen agregado de un mes, con igualdad por valor.
///
/// Existe para que los insights de IA NO se regeneren en cada snapshot de
/// Firestore: un `Map` nuevo nunca es `==` al anterior, así que cualquier
/// rebuild disparaba otra llamada al modelo. Con un value object, dos meses
/// con los mismos números son el mismo objeto y el provider no recomputa.
class MonthlySpendingSummary extends Equatable {
  final DateTime month;
  /// En centavos.
  final int totalCents;
  /// En centavos, por categoria.
  final Map<ExpenseCategory, int> categoryTotals;
  final List<MerchantTotal> topMerchants;
  final int expenseCount;

  const MonthlySpendingSummary({
    required this.month,
    required this.totalCents,
    required this.categoryTotals,
    required this.topMerchants,
    required this.expenseCount,
  });

  MonthlySpendingSummary.emptyFor(this.month)
      : totalCents = 0,
        categoryTotals = const {},
        topMerchants = const [],
        expenseCount = 0;

  bool get isEmpty => expenseCount == 0 || totalCents <= 0;

  /// Construye el resumen de [month] a partir de los gastos ya cargados.
  factory MonthlySpendingSummary.from(
    List<ExpenseEntity> expenses,
    DateTime month,
  ) {
    final ofMonth = expenses.where(
      (e) => e.date.year == month.year && e.date.month == month.month,
    );

    final categoryTotals = <ExpenseCategory, int>{};
    final merchants = <String, MerchantTotal>{};
    var total = 0;
    var count = 0;

    for (final e in ofMonth) {
      total += e.amountCents;
      count++;
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amountCents;

      final name = e.storeName?.trim();
      if (name == null || name.isEmpty) continue;
      final current = merchants[name];
      merchants[name] = MerchantTotal(
        name: name,
        totalCents: (current?.totalCents ?? 0) + e.amountCents,
        visits: (current?.visits ?? 0) + 1,
      );
    }

    final top = merchants.values.toList()
      ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

    return MonthlySpendingSummary(
      month: DateTime(month.year, month.month),
      totalCents: total,
      categoryTotals: categoryTotals,
      topMerchants: top.take(5).toList(),
      expenseCount: count,
    );
  }

  /// Firma estable: dos resúmenes con los mismos totales al centavo son
  /// iguales, aunque sean instancias distintas.
  @override
  List<Object?> get props => [
        month,
        totalCents,
        expenseCount,
        _categorySignature,
        topMerchants.map((m) => m.signature).join(','),
      ];

  String get _categorySignature {
    final entries = categoryTotals.entries.toList()
      ..sort((a, b) => a.key.name.compareTo(b.key.name));
    return entries.map((e) => '${e.key.name}:${e.value}').join(',');
  }
}

class MerchantTotal extends Equatable {
  final String name;
  /// En centavos.
  final int totalCents;
  final int visits;

  const MerchantTotal({
    required this.name,
    required this.totalCents,
    required this.visits,
  });

  String get signature => '\$name:\$totalCents:\$visits';

  Map<String, dynamic> toPromptMap() => {
        'name': name,
        'totalCents': totalCents,
        'count': visits,
      };

  @override
  List<Object?> get props => [name, totalCents, visits];
}
