import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/balance.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/entities/group_expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/recordatorio.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/split.dart';

GroupExpenseEntity _entrada({
  required String id,
  required int total,
  required Map<String, int> pago,
  required Map<String, int> reparto,
  GroupEntryKind kind = GroupEntryKind.expense,
}) =>
    GroupExpenseEntity(
      id: id,
      groupId: 'grupo',
      description: kind == GroupEntryKind.payment ? 'Pago' : 'asado',
      amountCents: total,
      date: DateTime(2026, 10, 1),
      mode: kind == GroupEntryKind.payment ? SplitMode.exact : SplitMode.equal,
      paidBy: pago,
      shares: reparto,
      createdBy: 'ana',
      createdAt: DateTime(2026, 10, 1),
      kind: kind,
    );

/// Lo que guarda GroupRepository.recordPayment.
GroupExpenseEntity _pago(String id, String de, String a, int cents) => _entrada(
      id: id,
      total: cents,
      pago: {de: cents},
      reparto: {a: cents},
      kind: GroupEntryKind.payment,
    );

void main() {
  // Ana pago un asado de $1.500 entre tres: Juan y yo le debemos $500 cada uno.
  final asado = _entrada(
    id: 'asado',
    total: 150000,
    pago: {'ana': 150000},
    reparto: {'ana': 50000, 'juan': 50000, 'yo': 50000},
  );

  group('un pago salda la deuda con la cuenta de siempre', () {
    test('pagar todo deja a los dos en cero', () {
      final libro = [asado, _pago('p1', 'yo', 'ana', 50000)];
      // balanceOf es lo que muestra la pantalla; netBalances omite a quien
      // quedo en cero.
      expect(balanceOf(libro, 'yo'), 0);
      expect(balanceOf(libro, 'ana'), 50000, reason: 'Juan todavia le debe');
      expect(debtsInvolving(libro, 'yo'), isEmpty);
    });

    test('un pago parcial deja el resto', () {
      final libro = [asado, _pago('p1', 'yo', 'ana', 20000)];
      final mias = debtsInvolving(libro, 'yo');
      expect(mias.single.from, 'yo');
      expect(mias.single.to, 'ana');
      expect(mias.single.cents, 30000);
    });

    test('pagar de mas da vuelta la deuda en vez de perderla', () {
      final libro = [asado, _pago('p1', 'yo', 'ana', 60000)];
      final mias = debtsInvolving(libro, 'yo');
      expect(mias.single.from, 'ana');
      expect(mias.single.cents, 10000);
    });

    test('con todos los pagos el grupo cierra en cero', () {
      final libro = [
        asado,
        _pago('p1', 'yo', 'ana', 50000),
        _pago('p2', 'juan', 'ana', 50000),
      ];
      expect(netBalances(libro).values.every((v) => v == 0), isTrue);
      expect(pairwiseDebts(libro), isEmpty);
      expect(simplifiedDebts(libro), isEmpty);
    });

    test('un pago esta balanceado como cualquier entrada', () {
      expect(_pago('p', 'yo', 'ana', 12345).isBalanced, isTrue);
    });
  });

  group('tipo de entrada', () {
    test('los documentos viejos, sin tipo, son gastos', () {
      expect(GroupEntryKind.fromString(null), GroupEntryKind.expense);
      expect(GroupEntryKind.fromString('cualquiera'), GroupEntryKind.expense);
      expect(GroupEntryKind.fromString('payment'), GroupEntryKind.payment);
    });
  });

  group('recordatorio por WhatsApp', () {
    test('el mensaje dice el grupo, el monto y el link', () {
      final m = mensajeRecordatorio(
        grupo: 'Asado del sábado',
        cents: 50000,
        moneda: 'UYU',
        link: 'https://x.web.app/groups/g1',
      );
      expect(m, contains('Asado del sábado'));
      expect(m, contains('500'));
      expect(m, contains('https://x.web.app/groups/g1'));
    });

    test('el link escapa el texto entero', () {
      final url = linkWhatsApp('me debés \$500 & algo');
      expect(url, startsWith('https://wa.me/?text='));
      expect(url, isNot(contains(' ')));
      expect(url, isNot(contains('&algo')));
      expect(Uri.parse(url).queryParameters['text'], 'me debés \$500 & algo');
    });
  });
}
