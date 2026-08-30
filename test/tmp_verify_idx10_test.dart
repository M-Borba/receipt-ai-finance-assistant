import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/balance.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/entities/group_expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/split.dart';

GroupExpenseEntity g({
  required int total,
  required Map<String, int> pago,
  required Map<String, int> reparto,
  String id = 'x',
}) => GroupExpenseEntity(
      id: id, groupId: 'grupo', description: 'd', amountCents: total,
      date: DateTime(2026, 8, 29), mode: SplitMode.equal,
      paidBy: pago, shares: reparto,
      memberIds: {...pago.keys, ...reparto.keys}.toList(),
      createdBy: 'a', createdAt: DateTime(2026, 8, 29),
    );

Map<String, int> desde(List<Debt> ds) {
  final m = <String, int>{};
  for (final d in ds) {
    m[d.from] = (m[d.from] ?? 0) - d.cents;
    m[d.to] = (m[d.to] ?? 0) + d.cents;
  }
  m.removeWhere((_, v) => v == 0);
  return m;
}

void main() {
  test('contraejemplo 4 centavos', () {
    final libro = [g(total: 4, pago: {'a': 1, 'b': 3}, reparto: {'c': 2, 'd': 2})];
    // ignore: avoid_print
    print('neto=${netBalances(libro)}');
    // ignore: avoid_print
    print('pares=${pairwiseDebts(libro)}');
    // ignore: avoid_print
    print('desdePares=${desde(pairwiseDebts(libro))}');
  });

  test('un solo pagador: cuantos acreedores', () {
    // 4 personas, un pagador, montos "reales"
    var descuadres = 0;
    for (var total = 1; total <= 200000; total++) {
      final gente = ['ana', 'beto', 'caro', 'dani'];
      final libro = [g(total: total, pago: {'ana': total},
          reparto: computeShares(totalCents: total, participants: gente, mode: SplitMode.equal))];
      final x = desde(pairwiseDebts(libro));
      final y = netBalances(libro);
      var ok = x.length == y.length;
      if (ok) { for (final k in y.keys) { if (x[k] != y[k]) { ok = false; break; } } }
      if (!ok) descuadres++;
    }
    // ignore: avoid_print
    print('un pagador, descuadres=$descuadres');
  });
}
