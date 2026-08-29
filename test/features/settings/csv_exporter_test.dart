import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/settings/domain/csv_exporter.dart';

ExpenseEntity _gasto({
  required int cents,
  required DateTime date,
  String? store,
  String? note,
  String? receiptId,
  ExpenseCategory category = ExpenseCategory.groceries,
}) =>
    ExpenseEntity(
      id: 'e${date.millisecondsSinceEpoch}',
      userId: 'u1',
      receiptId: receiptId,
      category: category,
      amountCents: cents,
      storeName: store,
      note: note,
      date: date,
      createdAt: date,
    );

void main() {
  const exporter = CsvExporter();

  List<String> lineas(String csv) => csv
      .replaceFirst(CsvExporter.bom, '')
      .trim()
      .split('\n')
      .map((l) => l.trimRight())
      .toList();

  group('formato', () {
    test('arranca con BOM, sin el cual Excel rompe las tildes', () {
      final csv = exporter.export([]);
      expect(csv.startsWith(CsvExporter.bom), isTrue);
    });

    test('en espanol usa punto y coma', () {
      final csv = exporter.export([
        _gasto(cents: 123456, date: DateTime(2026, 3, 2), store: 'Devoto'),
      ], locale: 'es_UY');
      expect(lineas(csv)[0], 'Fecha;Comercio;Categoria;Monto;Nota;Origen');
      expect(lineas(csv)[1], contains('Devoto'));
    });

    test('en ingles usa coma', () {
      final csv = exporter.export([], locale: 'en_US');
      expect(lineas(csv)[0], 'Fecha,Comercio,Categoria,Monto,Nota,Origen');
    });

    test('fecha en ISO, que Excel entiende en cualquier idioma', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2)),
      ]);
      expect(lineas(csv)[1], startsWith('2026-03-02;'));
    });
  });

  group('montos', () {
    test('centavos a decimal con coma en espanol', () {
      final csv = exporter.export([
        _gasto(cents: 123456, date: DateTime(2026, 3, 2)),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], contains(';1234,56;'));
    });

    test('con punto en ingles', () {
      final csv = exporter.export([
        _gasto(cents: 123456, date: DateTime(2026, 3, 2)),
      ], locale: 'en_US');
      expect(lineas(csv)[1], contains(',1234.56,'));
    });

    test('centavos exactos, sin redondeos raros', () {
      final csv = exporter.export([
        _gasto(cents: 1, date: DateTime(2026, 3, 2)),
        _gasto(cents: 99, date: DateTime(2026, 3, 3)),
        _gasto(cents: 100, date: DateTime(2026, 3, 4)),
      ], locale: 'es_UY');
      final l = lineas(csv);
      expect(l[1], contains(';0,01;'));
      expect(l[2], contains(';0,99;'));
      expect(l[3], contains(';1,00;'));
    });
  });

  group('escapado', () {
    test('entrecomilla los campos con el separador adentro', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2), store: 'Coto; sucursal 4'),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], contains('"Coto; sucursal 4"'));
    });

    test('duplica las comillas internas', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2), note: 'el "super" de casa'),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], contains('"el ""super"" de casa"'));
    });

    test('un salto de linea en la nota no rompe el archivo', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2), note: 'linea1\nlinea2'),
      ], locale: 'es_UY');
      expect(csv, contains('"linea1\nlinea2"'));
    });
  });

  group('contenido', () {
    test('distingue manual de ticket', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2)),
        _gasto(cents: 200, date: DateTime(2026, 3, 3), receiptId: 'r1'),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], endsWith(';Manual'));
      expect(lineas(csv)[2], endsWith(';Ticket'));
    });

    test('ordena de mas viejo a mas nuevo', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 5, 1)),
        _gasto(cents: 200, date: DateTime(2026, 1, 1)),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], startsWith('2026-01-01'));
      expect(lineas(csv)[2], startsWith('2026-05-01'));
    });

    test('sin gastos exporta solo el encabezado', () {
      expect(lineas(exporter.export([])).length, 1);
    });

    test('la categoria sale traducida', () {
      final csv = exporter.export([
        _gasto(cents: 100, date: DateTime(2026, 3, 2), category: ExpenseCategory.fuel),
      ], locale: 'es_UY');
      expect(lineas(csv)[1], contains(';Combustible;'));
    });
  });

  test('el nombre del archivo lleva la fecha', () {
    expect(exporter.fileName(DateTime(2026, 8, 29)), 'gastos-2026-08-29.csv');
  });
}
