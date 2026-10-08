import '../../../core/format/money.dart';
import '../../../services/classification/merchant_classifier.dart';
import '../../expenses/domain/entities/expense_entity.dart';
import 'entities/insight_entity.dart';

/// Insights calculados con los gastos, sin IA.
///
/// En produccion la IA no llega (apunta a Ollama en localhost) y el plan B
/// solo sabia decir cuanto se gasto en delivery, asi que la pantalla de
/// insights quedaba casi siempre vacia. Esto anda siempre, offline y gratis, y
/// los numeros son exactos: no los inventa un modelo.
///
/// Todo es logica pura sobre una lista de gastos y una fecha, para poder
/// testearlo sin reloj ni Firestore.
List<InsightEntity> insightsLocales({
  required List<ExpenseEntity> gastos,
  required DateTime hoy,
  required String userId,
}) {
  final mes = DateTime(hoy.year, hoy.month);
  InsightEntity nuevo(String id, String icon, InsightType type, String title,
          String description) =>
      InsightEntity(
        id: 'local_$id',
        userId: userId,
        month: mes,
        title: title,
        description: description,
        type: type,
        icon: icon,
        createdAt: hoy,
      );

  final dia = hoy.day;
  final diasMes = DateTime(hoy.year, hoy.month + 1, 0).day;
  final mesAnterior = DateTime(hoy.year, hoy.month - 1);
  final diasMesAnterior = DateTime(hoy.year, hoy.month, 0).day;

  bool esDe(ExpenseEntity e, DateTime m) =>
      e.date.year == m.year && e.date.month == m.month;

  // "A esta altura": del mes anterior solo cuenta hasta el mismo dia. Comparar
  // 8 dias de este mes con el mes pasado entero siempre da "gastaste menos".
  final actual = gastos.where((e) => esDe(e, mes) && e.date.day <= dia);
  final anteriorALaAltura = gastos.where((e) =>
      esDe(e, mesAnterior) &&
      e.date.day <= (dia < diasMesAnterior ? dia : diasMesAnterior));
  final anteriorEntero = gastos.where((e) => esDe(e, mesAnterior));

  int suma(Iterable<ExpenseEntity> xs) =>
      xs.fold<int>(0, (a, e) => a + e.amountCents);

  final totalActual = suma(actual);
  final totalAnterior = suma(anteriorALaAltura);
  final totalAnteriorEntero = suma(anteriorEntero);
  final salida = <InsightEntity>[];

  // 1. Gastos fijos que todavia no aparecen este mes: es lo mas accionable.
  for (final f in detectarFijos(gastos: gastos, hoy: hoy)) {
    if (f.pagadoEsteMes || dia < f.diaTipico - 2) continue;
    salida.add(nuevo(
      'fijo_${f.clave}',
      '🔔',
      InsightType.warning,
      'Todavía no pagaste ${f.nombre} este mes',
      'Lo pagaste los últimos ${f.meses} meses, cerca del día ${f.diaTipico}, '
          'por unos ${Money.format(f.montoTipico)}.',
    ));
  }

  if (totalActual > 0) {
    // 2. Proyeccion. Antes del dia 5 un par de compras grandes la disparan.
    if (dia >= 5 && dia < diasMes) {
      final proyeccion = totalActual * diasMes ~/ dia;
      final contra = totalAnteriorEntero > 0
          ? ' El mes pasado fueron ${Money.format(totalAnteriorEntero)}.'
          : '';
      salida.add(nuevo(
        'proyeccion',
        '📈',
        totalAnteriorEntero > 0 && proyeccion > totalAnteriorEntero * 11 ~/ 10
            ? InsightType.warning
            : InsightType.pattern,
        'A este ritmo cerrás el mes en ${Money.format(proyeccion)}',
        'Llevás ${Money.format(totalActual)} en $dia días.$contra',
      ));
    }

    // 3. Contra el mes pasado a la misma altura, si la diferencia se nota.
    if (dia >= 3 && totalAnterior > 0) {
      final pct = ((totalActual - totalAnterior) * 100 / totalAnterior).round();
      if (pct.abs() >= 10) {
        salida.add(nuevo(
          'vs_anterior',
          pct > 0 ? '⬆️' : '⬇️',
          pct > 0 ? InsightType.behavior : InsightType.saving,
          pct > 0
              ? 'Vas $pct% arriba del mes pasado'
              : 'Vas ${-pct}% abajo del mes pasado',
          'Al día $dia llevás ${Money.format(totalActual)}; el mes pasado, a '
              'esta altura, ${Money.format(totalAnterior)}.',
        ));
      }
    }

    // 4. La categoria que mas subio, a la misma altura.
    final porCatActual = _porCategoria(actual);
    final porCatAnterior = _porCategoria(anteriorALaAltura);
    ExpenseCategory? peor;
    var peorDiff = 0;
    for (final e in porCatActual.entries) {
      final antes = porCatAnterior[e.key] ?? 0;
      final diff = e.value - antes;
      // Al menos $500 y un 30% mas: lo que esta por debajo es ruido.
      if (diff >= 50000 && e.value * 10 >= antes * 13 && diff > peorDiff) {
        peor = e.key;
        peorDiff = diff;
      }
    }
    if (peor != null) {
      salida.add(nuevo(
        'categoria_${peor.name}',
        peor.emoji,
        InsightType.warning,
        '${peor.label} subió ${Money.format(peorDiff)}',
        'Llevás ${Money.format(porCatActual[peor]!)} contra '
            '${Money.format(porCatAnterior[peor] ?? 0)} el mes pasado a esta '
            'altura.',
      ));
    }

    // 5. El comercio que mas se repite en el mes.
    final visitas = <String, ({String nombre, int veces, int cents})>{};
    for (final e in actual) {
      final nombre = e.storeName?.trim();
      if (nombre == null || nombre.isEmpty) continue;
      final k = _claveComercio(nombre);
      final v = visitas[k];
      visitas[k] = (
        nombre: v?.nombre ?? nombre,
        veces: (v?.veces ?? 0) + 1,
        cents: (v?.cents ?? 0) + e.amountCents,
      );
    }
    final frecuente = visitas.values
        .where((v) => v.veces >= 3)
        .fold<({String nombre, int veces, int cents})?>(
            null, (a, b) => a == null || b.veces > a.veces ? b : a);
    if (frecuente != null) {
      salida.add(nuevo(
        'frecuente',
        '🔁',
        InsightType.pattern,
        'Fuiste ${frecuente.veces} veces a ${frecuente.nombre}',
        'Suman ${Money.format(frecuente.cents)} este mes, unos '
            '${Money.format(frecuente.cents ~/ frecuente.veces)} por vez.',
      ));
    }
  }

  return salida;
}

/// Clave para juntar el mismo comercio escrito distinto: "UTE", "U.T.E." y
/// "ute" son uno solo, igual que "TA-TA" y "Ta Ta". Mas agresiva que la de la
/// memoria de comercios porque aca solo agrupa, no se guarda.
String _claveComercio(String nombre) =>
    MerchantClassifier.normalize(nombre).replaceAll(RegExp(r'[^a-z0-9]'), '');

Map<ExpenseCategory, int> _porCategoria(Iterable<ExpenseEntity> xs) {
  final m = <ExpenseCategory, int>{};
  for (final e in xs) {
    m[e.category] = (m[e.category] ?? 0) + e.amountCents;
  }
  return m;
}

/// Algo que se paga todos los meses: UTE, el alquiler, Netflix.
class GastoFijo {
  const GastoFijo({
    required this.clave,
    required this.nombre,
    required this.montoTipico,
    required this.diaTipico,
    required this.meses,
    required this.pagadoEsteMes,
  });

  /// Nombre normalizado, para identificarlo entre escaneos.
  final String clave;

  /// Como lo escribiste la ultima vez.
  final String nombre;
  final int montoTipico;
  final int diaTipico;

  /// En cuantos de los meses mirados aparecio.
  final int meses;
  final bool pagadoEsteMes;
}

/// Lo que pagaste en cada uno de los ultimos [mesesMirados] meses completos,
/// por un monto parecido.
///
/// "Parecido" es dentro de un 25% de la mediana: la luz y el agua cambian de
/// un mes a otro, pero un super de $300 y otro de $9.000 no son un gasto fijo
/// aunque sean del mismo comercio. Y tiene que haber UN pago por mes: el super
/// al que vas cinco veces no es una factura.
List<GastoFijo> detectarFijos({
  required List<ExpenseEntity> gastos,
  required DateTime hoy,
  int mesesMirados = 3,
}) {
  final meses = [
    for (var i = 1; i <= mesesMirados; i++) DateTime(hoy.year, hoy.month - i),
  ];
  final porComercio = <String, List<ExpenseEntity>>{};
  for (final e in gastos) {
    final nombre = e.storeName?.trim();
    if (nombre == null || nombre.isEmpty) continue;
    porComercio.putIfAbsent(_claveComercio(nombre), () => []).add(e);
  }

  final salida = <GastoFijo>[];
  porComercio.forEach((clave, lista) {
    final enMeses = <ExpenseEntity>[];
    for (final m in meses) {
      final delMes = lista
          .where((e) => e.date.year == m.year && e.date.month == m.month)
          .toList();
      if (delMes.length != 1) return;
      enMeses.add(delMes.single);
    }

    final montos = enMeses.map((e) => e.amountCents).toList()..sort();
    final mediana = montos[montos.length ~/ 2];
    if (mediana <= 0) return;
    if (montos.any((c) => (c - mediana).abs() * 4 > mediana)) return;

    final dias = enMeses.map((e) => e.date.day).toList()..sort();
    final ultimo = lista.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    salida.add(GastoFijo(
      clave: clave,
      nombre: ultimo.storeName!.trim(),
      montoTipico: mediana,
      diaTipico: dias[dias.length ~/ 2],
      meses: mesesMirados,
      pagadoEsteMes: lista.any(
          (e) => e.date.year == hoy.year && e.date.month == hoy.month),
    ));
  });

  salida.sort((a, b) => a.diaTipico.compareTo(b.diaTipico));
  return salida;
}
