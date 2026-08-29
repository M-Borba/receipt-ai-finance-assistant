/// Reparto de un gasto entre varias personas, en centavos enteros.
///
/// Todo el modulo trabaja con `int`. Dividir 100 entre 3 da 33,33 y tres veces
/// eso son 99,99: con `double` el grupo nunca cierra en cero y la gente lo ve.
library;

/// Como se reparte un gasto.
enum SplitMode {
  /// Todos lo mismo. El 80% de los casos.
  equal,

  /// Partes por persona: `yo: 4, Juan: 1, Ana: 1` es 2/3 + 1/6 + 1/6 sin que
  /// nadie calcule fracciones, y no necesita sumar 100.
  shares,

  /// Porcentajes. Tienen que sumar 100.
  percentage,

  /// El monto de cada uno, ya sabido. Tiene que sumar el total.
  exact;

  String get label => switch (this) {
        SplitMode.equal => 'Partes iguales',
        SplitMode.shares => 'Por partes',
        SplitMode.percentage => 'Por porcentaje',
        SplitMode.exact => 'Montos exactos',
      };
}

/// Reparte [totalCents] en proporcion a [weights].
///
/// La suma del resultado es **siempre exactamente** [totalCents]: los centavos
/// que sobran de la division entera van a los restos mas grandes (metodo del
/// resto mayor). El desempate es por indice, asi que dos dispositivos calculan
/// lo mismo.
///
/// Devuelve una lista vacia si [weights] esta vacio, y todo cero si los pesos
/// suman cero (nadie participa: no hay a quien cobrarle).
List<int> splitLargestRemainder(int totalCents, List<int> weights) {
  if (weights.isEmpty) return const [];
  if (weights.any((w) => w < 0)) {
    throw ArgumentError('Los pesos no pueden ser negativos: $weights');
  }

  final totalWeight = weights.fold<int>(0, (a, b) => a + b);
  if (totalWeight == 0) return List<int>.filled(weights.length, 0);

  // Un gasto negativo (una devolucion) se reparte igual: el signo se mantiene
  // en el cociente y el resto se maneja aparte para no depender de como Dart
  // redondea la division de negativos.
  final signo = totalCents < 0 ? -1 : 1;
  final magnitud = totalCents.abs();

  final base = <int>[];
  final restos = <({int index, int rem})>[];
  var asignado = 0;

  for (var i = 0; i < weights.length; i++) {
    final exacto = magnitud * weights[i];
    final parte = exacto ~/ totalWeight;
    base.add(parte);
    asignado += parte;
    restos.add((index: i, rem: exacto % totalWeight));
  }

  // Los centavos que faltan van a los restos mas grandes. Desempate por
  // indice: determinista en todos los dispositivos.
  restos.sort((a, b) {
    final c = b.rem.compareTo(a.rem);
    return c != 0 ? c : a.index.compareTo(b.index);
  });

  final sobrante = magnitud - asignado;
  for (var k = 0; k < sobrante; k++) {
    base[restos[k].index] += 1;
  }

  return signo == 1 ? base : base.map((c) => -c).toList();
}

/// El resultado de repartir: cuanto le toca a cada uno, ya en centavos.
///
/// Se guarda **ya calculado** y no el modo con sus parametros, para que el
/// historico no se mueva si manana cambia el algoritmo.
typedef Shares = Map<String, int>;

/// Calcula cuanto le toca a cada participante.
///
/// [inputs] se interpreta segun [mode]:
/// - [SplitMode.equal]: se ignora, todos pesan 1
/// - [SplitMode.shares]: partes enteras por persona
/// - [SplitMode.percentage]: porcentajes en centesimas (1250 = 12,50%)
/// - [SplitMode.exact]: el monto de cada uno, en centavos
///
/// Tira [ArgumentError] si el modo exacto no suma [totalCents] o si el de
/// porcentajes no suma 100%: dejar pasar un reparto que no cierra es
/// exactamente el bug que hace que un grupo no llegue nunca a cero.
Shares computeShares({
  required int totalCents,
  required List<String> participants,
  required SplitMode mode,
  Map<String, int> inputs = const {},
}) {
  if (participants.isEmpty) return const {};

  final unicos = participants.toSet().toList();
  if (unicos.length != participants.length) {
    throw ArgumentError('Hay participantes repetidos: $participants');
  }

  switch (mode) {
    case SplitMode.equal:
      final partes = splitLargestRemainder(
        totalCents,
        List<int>.filled(participants.length, 1),
      );
      return _zip(participants, partes);

    case SplitMode.shares:
      final pesos = participants.map((p) => inputs[p] ?? 0).toList();
      if (pesos.every((w) => w == 0)) {
        throw ArgumentError('Alguien tiene que participar: todas las partes '
            'estan en cero');
      }
      return _zip(participants, splitLargestRemainder(totalCents, pesos));

    case SplitMode.percentage:
      final pct = participants.map((p) => inputs[p] ?? 0).toList();
      final suma = pct.fold<int>(0, (a, b) => a + b);
      if (suma != 10000) {
        throw ArgumentError('Los porcentajes tienen que sumar 100%, '
            'suman ${suma / 100}%');
      }
      // Los porcentajes son pesos: el resto mayor se encarga del redondeo.
      return _zip(participants, splitLargestRemainder(totalCents, pct));

    case SplitMode.exact:
      final montos = participants.map((p) => inputs[p] ?? 0).toList();
      final suma = montos.fold<int>(0, (a, b) => a + b);
      if (suma != totalCents) {
        throw ArgumentError(
            'Los montos suman $suma y el gasto es $totalCents');
      }
      return _zip(participants, montos);
  }
}

Shares _zip(List<String> uids, List<int> cents) {
  final out = <String, int>{};
  for (var i = 0; i < uids.length; i++) {
    out[uids[i]] = cents[i];
  }
  return out;
}
