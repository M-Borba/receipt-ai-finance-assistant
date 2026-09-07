/// Balances del grupo, **derivados del libro de gastos**.
///
/// Nunca se guardan como estado mutable en Firestore: dos personas cargando un
/// gasto al mismo tiempo se pisarian el balance. Recalcular es barato y no
/// puede quedar desincronizado.
library;

import 'entities/group_expense_entity.dart';

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
/// entre los pagadores **en proporcion a lo que puso cada uno**, con
/// [allocateDebtsToCredits], que garantiza que lo que paga cada deudor y lo que
/// cobra cada acreedor cierren los dos exactamente.
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
    final matriz = allocateDebtsToCredits(
      [for (final d in deudoresOrd) deudores[d]!],
      creditosOrd,
    );
    for (var f = 0; f < deudoresOrd.length; f++) {
      for (var c = 0; c < acreedoresOrd.length; c++) {
        anotar(deudoresOrd[f], acreedoresOrd[c], matriz[f][c]);
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

/// Reparte lo que debe cada deudor entre los acreedores, en proporcion a lo
/// que puso cada uno.
///
/// Devuelve una matriz `[deudor][acreedor]` en centavos, donde **las dos
/// margenes cierran exactamente**: cada fila suma la deuda de ese deudor y cada
/// columna suma el credito de ese acreedor. Nunca devuelve negativos.
///
/// Hace falta porque redondear cada fila por separado no alcanza. Con dos
/// deudores de 1 centavo y dos acreedores de 1 centavo, el resto mayor le da a
/// los dos deudores el mismo acreedor: uno cobraba 2 y el otro nada. En un
/// barrido de 5,9 millones de combinaciones, repartir fila por fila daba
/// columnas equivocadas en el 83% de los casos con mas de un pagador. Eso se
/// veia en pantalla: el saldo neto de arriba y las deudas de a pares de abajo
/// se contradecian.
///
/// El metodo es el clasico de transporte: primero la parte entera de la
/// proporcion exacta, que nunca se pasa de ninguna margen, y despues los
/// centavos que sobran, a las celdas con el resto fraccionario mas grande que
/// todavia tengan lugar en su fila y en su columna.
///
/// Si el gasto esta descuadrado ([GroupExpenseEntity.isBalanced] en false) las
/// dos margenes no pueden cerrar las dos, porque no suman lo mismo. En ese caso
/// reparte lo que se puede y **deja el resto sin asignar** en vez de inventar
/// una deuda: la app ya no escribe gastos descuadrados, pero pueden quedar de
/// antes, y la UI los marca.
List<List<int>> allocateDebtsToCredits(List<int> debts, List<int> credits) {
  if (debts.any((d) => d < 0) || credits.any((c) => c < 0)) {
    throw ArgumentError('Deudas y creditos son magnitudes: $debts / $credits');
  }
  final matriz = [
    for (var f = 0; f < debts.length; f++) List<int>.filled(credits.length, 0),
  ];
  if (debts.isEmpty || credits.isEmpty) return matriz;

  final sumaDeudas = debts.fold<int>(0, (a, b) => a + b);
  final sumaCreditos = credits.fold<int>(0, (a, b) => a + b);
  if (sumaDeudas == 0 || sumaCreditos == 0) return matriz;

  // El denominador es el LADO MAS GRANDE. Con eso la parte entera no se pasa
  // ni de la fila ni de la columna, ni siquiera cuando el gasto esta
  // descuadrado y las dos sumas difieren.
  final denom = sumaDeudas > sumaCreditos ? sumaDeudas : sumaCreditos;

  final faltaFila = List<int>.filled(debts.length, 0);
  final faltaColumna = List<int>.filled(credits.length, 0);
  final celdas = <({int fila, int col, int resto})>[];

  for (var f = 0; f < debts.length; f++) {
    for (var c = 0; c < credits.length; c++) {
      final exacto = debts[f] * credits[c];
      matriz[f][c] = exacto ~/ denom;
      celdas.add((fila: f, col: c, resto: exacto % denom));
    }
  }
  for (var f = 0; f < debts.length; f++) {
    faltaFila[f] = debts[f] - matriz[f].fold<int>(0, (a, b) => a + b);
  }
  for (var c = 0; c < credits.length; c++) {
    var suma = 0;
    for (var f = 0; f < debts.length; f++) {
      suma += matriz[f][c];
    }
    faltaColumna[c] = credits[c] - suma;
  }

  // Resto decreciente, desempate por fila y columna: dos dispositivos calculan
  // exactamente lo mismo. Dart no garantiza un sort estable, asi que el
  // desempate va escrito.
  celdas.sort((a, b) {
    final c = b.resto.compareTo(a.resto);
    if (c != 0) return c;
    final f = a.fila.compareTo(b.fila);
    return f != 0 ? f : a.col.compareTo(b.col);
  });

  for (final celda in celdas) {
    if (faltaFila[celda.fila] > 0 && faltaColumna[celda.col] > 0) {
      matriz[celda.fila][celda.col] += 1;
      faltaFila[celda.fila] -= 1;
      faltaColumna[celda.col] -= 1;
    }
  }

  // La pasada de arriba puede dejar centavos sueltos: una fila con lugar y una
  // columna con lugar que no se cruzaron entre las celdas de mayor resto. Se
  // cierran aca. Con el gasto balanceado las dos margenes suman igual, asi que
  // esto siempre las deja en cero.
  for (var f = 0; f < debts.length; f++) {
    for (var c = 0; c < credits.length && faltaFila[f] > 0; c++) {
      if (faltaColumna[c] <= 0) continue;
      final cuanto = faltaFila[f] < faltaColumna[c]
          ? faltaFila[f]
          : faltaColumna[c];
      matriz[f][c] += cuanto;
      faltaFila[f] -= cuanto;
      faltaColumna[c] -= cuanto;
    }
  }

  return matriz;
}

/// Lo que [uid] debe (negativo) o le deben (positivo) en total.
int balanceOf(Iterable<GroupExpenseEntity> expenses, String uid) =>
    netBalances(expenses)[uid] ?? 0;

/// Las deudas que involucran a [uid], para mostrarle solo lo suyo.
List<Debt> debtsInvolving(Iterable<GroupExpenseEntity> expenses, String uid) =>
    pairwiseDebts(expenses)
        .where((d) => d.from == uid || d.to == uid)
        .toList();
