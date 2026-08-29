import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/services/classification/merchant_classifier.dart';
import 'package:receipt_ai_finance_assistant/services/ocr/receipt_text_parser.dart';

/// Tickets uruguayos reales, pasados por un OCR real.
///
/// El resto de los tests del parser usan texto escrito a mano. Estos no: cada
/// fixture de `test/assets/ocr/` es la salida literal de un motor de OCR
/// (Apple Vision) sobre la foto de un e-Ticket de verdad, con sus errores
/// incluidos: `0.0C` por `0.00`, `Zilertal` por `Zillertal`, `Direcoion` por
/// `Direccion`, columnas partidas en dos lineas.
///
/// Lo que estos tests protegen, y los inventados no protegian:
///
/// 1. **Los e-Ticket de DGI usan punto decimal y coma de miles** (`1,056.00`),
///    al reves de lo que se asume para LatAm. El parser resuelve el separador
///    mirando el ultimo, asi que aguanta las dos.
/// 2. **El numero de RUT y el de CAE entraban como productos.** El RUT de la
///    carniceria se leia como un item de $219.640.160,11.
/// 3. **Las filas de la tabla de IVA entraban como productos**, con el monto
///    del total.
void main() {
  final parser = ReceiptTextParser(dayFirst: true);
  const clasificador = MerchantClassifier();

  String fixture(String name) =>
      File('test/assets/ocr/$name.txt').readAsStringSync();

  group('carniceria (Guillermo Pujadas)', () {
    late final texto = fixture('carniceria');

    test('total con coma de miles y punto decimal: 1,056.00', () {
      expect(parser.extractTotal(texto), 105600);
    });

    test('no confunde el Sub TOTAL de la tabla de IVA con el total', () {
      // La tabla trae 215.60 y 840.40 en la columna "Sub TOTAL".
      expect(parser.extractTotal(texto), isNot(21560));
      expect(parser.extractTotal(texto), isNot(84040));
    });

    test('fecha DD/MM/YYYY, no el vencimiento del CAE', () {
      expect(parser.extractDate(texto), DateTime(2026, 7, 24));
    });

    test('comercio, salteando la linea del RUT', () {
      expect(parser.extractStoreName(texto), 'GUILLERNO PUJADAS SAS');
    });

    test('items: nombre arriba, cantidad/unitario/importe abajo', () {
      final items = parser.parseItems(texto, totalCents: 105600);
      expect(items.map((i) => i.name),
          containsAll(['CARNE VACUNA', 'Aves', 'Chacinado']));
      // El importe es la ultima columna, no el precio unitario: 0,5 kg de
      // aves a 349,00 el kilo son 174,50, no 349,00.
      final aves = items.firstWhere((i) => i.name == 'Aves');
      expect(aves.totalPriceCents, 17450);
    });

    test('el numero de RUT no es un producto', () {
      final items = parser.parseItems(texto, totalCents: 105600);
      // 219640160011 leido como plata son 219 millones de pesos.
      expect(items.every((i) => i.totalPriceCents <= 105600), isTrue);
      expect(items.map((i) => i.name), isNot(contains('RUT')));
    });

    test('el "Ajuste por Redondeo" no es un producto', () {
      final items = parser.parseItems(texto, totalCents: 105600);
      expect(items.map((i) => i.name.toLowerCase()),
          isNot(contains(contains('redondeo'))));
    });

    test('clasifica por los productos: la carniceria no es una cadena', () {
      final r = parser.parse(texto);
      expect(
        clasificador.classify(
          storeName: r.storeName,
          itemNames: r.items.map((i) => i.name).toList(),
        ),
        ExpenseCategory.groceries,
      );
    });
  });

  group('panaderia (Medialunas Guichon)', () {
    late final texto = fixture('panaderia');

    test('total 411.14', () {
      expect(parser.extractTotal(texto), 41114);
    });

    test('no toma el SUBTOTAL ni las filas de IVA de arriba', () {
      expect(parser.extractTotal(texto), isNot(21286));
      expect(parser.extractTotal(texto), isNot(19827));
    });

    test('fecha de emision, no la de vencimiento del CAE (2028-06-11)', () {
      expect(parser.extractDate(texto), DateTime(2026, 8, 28));
    });

    test('le saca la etiqueta R.U.T. pegada al nombre', () {
      expect(parser.extractStoreName(texto), 'MEDIALUNAS GUICHON S.R.L.');
    });

    test('items sin el codigo de articulo ni la cantidad adelante', () {
      final items = parser.parseItems(texto, totalCents: 41114);
      expect(items.map((i) => i.name),
          containsAll(['CATALANES REDONDOS', 'MEDIALUNAS MEDIANAS']));
    });

    test('el numero de CAE no es un producto', () {
      final items = parser.parseItems(texto, totalCents: 41114);
      // 90261832208 son 902 millones de pesos.
      expect(items.every((i) => i.totalPriceCents <= 41114), isTrue);
    });

    test('ni el telefono ni la direccion son productos', () {
      final items = parser.parseItems(texto, totalCents: 41114);
      final nombres = items.map((i) => i.name).join(' ').toLowerCase();
      expect(nombres, isNot(contains('frugoni')));
      expect(nombres, isNot(contains('cel')));
    });
  });

  group('distribuidora de bebidas (All in One)', () {
    late final texto = fixture('all_in_one');

    test('total escrito como "TOTAL \$ 768.00"', () {
      expect(parser.extractTotal(texto), 76800);
    });

    test('la fila "22% 629.51 138.49 768.00" no gana como total', () {
      // Contiene el mismo numero, pero el total real esta abajo.
      final items = parser.parseItems(texto, totalCents: 76800);
      expect(items.map((i) => i.name), isNot(contains(contains('22%'))));
    });

    test('fecha 15/08/2026', () {
      expect(parser.extractDate(texto), DateTime(2026, 8, 15));
    });

    test('moneda escrita en palabras: "Pesos Uruguayos"', () {
      expect(parser.extractCurrency(texto), 'UYU');
    });

    test('los cuatro productos, con el importe y no el precio unitario', () {
      final items = parser.parseItems(texto, totalCents: 76800);
      expect(items.length, 4);
      // Los importes suman exactamente el NETO que declara el propio ticket.
      final suma = items.fold<int>(0, (a, i) => a + i.totalPriceCents);
      expect(suma, 62951);
      // Dos retornables a 131,15 son 262,30: el importe, no el unitario.
      final zillertal =
          items.firstWhere((i) => i.name.toLowerCase().contains('zillertal'));
      expect(zillertal.totalPriceCents, 26230);
    });

    test('clasifica por bebidas aunque el comercio no este en la lista', () {
      final r = parser.parse(texto);
      expect(
        clasificador.classify(
          storeName: r.storeName,
          itemNames: r.items.map((i) => i.name).toList(),
        ),
        ExpenseCategory.groceries,
      );
    });
  });

  group('parse() de punta a punta', () {
    test('los tres tickets salen completos: comercio, fecha, total e items',
        () {
      for (final name in ['carniceria', 'panaderia', 'all_in_one']) {
        final r = parser.parse(fixture(name));
        expect(r.storeName, isNotNull, reason: name);
        expect(r.receiptDate, isNotNull, reason: name);
        expect(r.totalCents, isNotNull, reason: name);
        expect(r.items, isNotEmpty, reason: name);
        // Invariante que no depende del layout: ningun producto puede costar
        // mas que el ticket entero.
        for (final i in r.items) {
          expect(i.totalPriceCents, lessThanOrEqualTo(r.totalCents!),
              reason: '$name: ${i.name}');
        }
      }
    });

    test('rawOcrText no se pierde: el draft lo necesita para reintentar', () {
      final r = parser.parse(fixture('carniceria'));
      expect(r.rawText, contains('CARNE VACUNA'));
    });
  });
}
