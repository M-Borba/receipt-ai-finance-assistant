/// Balances del grupo, **derivados del libro de gastos**.
///
/// Nunca se guardan como estado mutable en Firestore: dos personas cargando un
/// gasto al mismo tiempo se pisarian el balance. Recalcular es barato y no
/// puede quedar desincronizado.
library;

import 'entities/group_expense_entity.dart';
import 'split.dart';

/// Una deuda concreta: [from] le debe [cents] a [to]. Siempre positiva.
class Debt {
  const Debt({required this.from, required this.to, required this.cents});

  final String from;
  final String to;
  final int cents;

  @override
  String toString() => '$from -> $to: $cents';

  @override
  bool operator ==(Object other) =>
      other is Debt &&
      other.from == from &&
      other.to == to &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(from, to, cents);
}

/// Balance neto por persona: lo que puso menos lo que le correspondia.
///
/// Positivo = le deben. Negativo = debe. **La suma de todos es siempre cero**,
/// siempre que cada gasto este balanceado.
Map<String, int> netBalances(Iterable<GroupExpenseEntity> expenses) {
  final neto = <String, int>{};
  for (final e in expenses) {
    e.paidBy.forEach((uid, cents) => neto[uid] = (neto[uid] ?? 0) + cents);
    e.shares.forEach((uid, cents) => neto[uid] = (neto[uid] ?? 0) - cents);
  }
  neto.removeWhere((_, v) => v == 0);
  return neto;
}

/// Deudas **de a pares**, sin simplificar.
///
/// Esta es la vista por defecto a proposito. Splitwise tiene la simplificacion
/// apagada porque a la gente le resulta rarisimo que le digan "pagale a Ana"
/// cuando nunca gasto nada con Ana. La vista simplificada (fase 2) se deriva
/// del mismo libro.
///
/// Con varios pagadores en un mismo gasto, lo que debe cada deudor se reparte
/// entre los pagadores **en proporcion a lo que puso cada uno**, con el metodo
/// del resto mayor para no perder centavos.
List<Debt> pairwiseDebts(Iterable<GroupExpenseEntity> expenses) {
  // Clave canonica: siempre el uid menor primero, y el signo dice la
  // direccion. Sin esto, A->B y B->A quedan como dos deudas separadas en vez
  // de netearse.
  final acumulado = <(String, String), int>{};

  void anotar(String deudor, String acreedor, int cents) {
    if (cents == 0 || deudor == acreedor) return;
    final key = deudor.compareTo(acreedor) < 0
        ? (deudor, acreedor)
        : (acreedor, deudor);
    final signo = deudor.compareTo(acreedor) < 0 ? 1 : -1;
    acumulado[key] = (acumulado[key] ?? 0) + signo * cents;
  }

  for (final e in expenses) {
    final acreedores = <String>[];
    final creditos = <int>[];
    final deudores = <String, int>{};

    for (final uid in {...e.paidBy.keys, ...e.shares.keys}) {
      final neto = e.netFor(uid);
      if (neto > 0) {
        acreedores.add(uid);
        creditos.add(neto);
      } else if (neto < 0) {
        deudores[uid] = -neto;
      }
    }
    if (acreedores.isEmpty) continue;

    // Orden estable: el reparto no puede depender del orden de iteracion de
    // un Map, que Dart no garantiza entre plataformas.
    final orden = List.generate(acreedores.length, (i) => i)
      ..sort((a, b) => acreedores[a].compareTo(acreedores[b]));
    final acreedoresOrd = [for (final i in orden) acreedores[i]];
    final creditosOrd = [for (final i in orden) creditos[i]];

    final deudoresOrd = deudores.keys.toList()..sort();
    for (final deudor in deudoresOrd) {
      final partes = splitLargestRemainder(deudores[deudor]!, creditosOrd);
      for (var i = 0; i < acreedoresOrd.length; i++) {
        anotar(deudor, acreedoresOrd[i], partes[i]);
      }
    }
  }

  final salida = <Debt>[];
  final claves = acumulado.keys.toList()
    ..sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  for (final k in claves) {
    final v = acumulado[k]!;
    if (v == 0) continue;
    salida.add(v > 0
        ? Debt(from: k.$1, to: k.$2, cents: v)
        : Debt(from: k.$2, to: k.$1, cents: -v));
  }
  return salida;
}

/// Lo que [uid] debe (negativo) o le deben (positivo) en total.
int balanceOf(Iterable<GroupExpenseEntity> expenses, String uid) =>
    netBalances(expenses)[uid] ?? 0;

/// Las deudas que involucran a [uid], para mostrarle solo lo suyo.
List<Debt> debtsInvolving(Iterable<GroupExpenseEntity> expenses, String uid) =>
    pairwiseDebts(expenses)
        .where((d) => d.from == uid || d.to == uid)
        .toList();
