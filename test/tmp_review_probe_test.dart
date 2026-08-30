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
      createdBy: 'ana', createdAt: DateTime(2026, 8, 29),
    );

Map<String, int> desdeDeudas(List<Debt> ds) {
  final m = <String, int>{};
  for (final d in ds) {
    m[d.from] = (m[d.from] ?? 0) - d.cents;
    m[d.to] = (m[d.to] ?? 0) + d.cents;
  }
  m.removeWhere((_, v) => v == 0);
  return m;
}

bool igual(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) { if (a[k] != b[k]) return false; }
  return true;
}

void main() {
  test('contraejemplo realista, 4 personas, dos pagadores', () {
    const gente = ['ana', 'beto', 'caro', 'dani'];
    var casos = 0;
    var peor = 0;
    String? primero;
    for (var total = 100; total <= 100000; total += 1) {
      for (final frac in const [0.5, 0.3, 0.25]) {
        final pA = (total * frac).round();
        if (pA <= 0 || pA >= total) continue;
        final libro = [
          g(total: total, pago: {'ana': pA, 'beto': total - pA},
            reparto: computeShares(
                totalCents: total, participants: gente, mode: SplitMode.equal)),
        ];
        final neto = netBalances(libro);
        final dd = desdeDeudas(pairwiseDebts(libro));
        if (!igual(neto, dd)) {
          casos++;
          for (final k in {...neto.keys, ...dd.keys}) {
            final d = ((neto[k] ?? 0) - (dd[k] ?? 0)).abs();
            if (d > peor) peor = d;
          }
          primero ??= 'total=$total pagoAna=$pA neto=$neto pares=$dd';
        }
      }
    }
    // ignore: avoid_print
    print('casos=$casos peorDiferencia=$peor');
    // ignore: avoid_print
    print('primero=$primero');
  });

  test('gasto NO balanceado: la vista de pares lo ignora entero', () {
    final libro = [
      g(total: 10000, pago: {'ana': 10000}, reparto: {'ana': 5000, 'juan': 5000}, id: 'a'),
      // documento corrupto: nadie pago, pero se reparte
      g(total: 6000, pago: const {}, reparto: {'juan': 3000, 'ana': 3000}, id: 'b'),
    ];
    // ignore: avoid_print
    print('neto=${netBalances(libro)}');
    // ignore: avoid_print
    print('pares=${pairwiseDebts(libro)}');
  });
}
