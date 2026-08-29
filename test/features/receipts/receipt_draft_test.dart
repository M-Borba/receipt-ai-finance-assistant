import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/domain/entities/receipt_draft.dart';
import 'package:receipt_ai_finance_assistant/features/receipts/domain/entities/receipt_item_entity.dart';

ReceiptItemEntity _item(String name, int cents) => ReceiptItemEntity(
      id: name,
      name: name,
      quantity: 1,
      unitPriceCents: cents,
      totalPriceCents: cents,
    );

ReceiptDraft _draft({
  int? totalCents,
  List<ReceiptItemEntity> items = const [],
  double confidence = 0.9,
}) {
  return ReceiptDraft(
    imageFile: XFile('/tmp/ticket.jpg'),
    ocrPath: '/tmp/ticket.jpg',
    rawOcrText: 'texto crudo',
    items: items,
    totalCents: totalCents,
    category: ExpenseCategory.groceries,
    ocrConfidence: confidence,
  );
}

void main() {
  group('resolvedTotalCents', () {
    test('usa el total leido cuando existe', () {
      expect(_draft(totalCents: 149382).resolvedTotalCents, 149382);
    });

    test('si no hay total, suma los items', () {
      final d = _draft(items: [_item('Pan', 89000), _item('Leche', 119999)]);
      expect(d.resolvedTotalCents, 208999);
    });

    test('el total leido gana sobre la suma de items', () {
      // El total del ticket incluye impuestos que no estan en los items.
      final d = _draft(totalCents: 250000, items: [_item('Pan', 89000)]);
      expect(d.resolvedTotalCents, 250000);
    });

    test('sin total ni items da 0, y eso bloquea el guardado', () {
      expect(_draft().resolvedTotalCents, 0);
    });
  });

  group('needsAttention', () {
    test('avisa cuando el OCR no encontro total', () {
      expect(_draft().needsAttention(threshold: 0.7), isTrue);
    });

    test('avisa cuando la confianza esta por debajo del umbral', () {
      expect(_draft(totalCents: 10000, confidence: 0.4).needsAttention(threshold: 0.7),
          isTrue);
    });

    test('no avisa con total y buena confianza', () {
      expect(_draft(totalCents: 10000, confidence: 0.9).needsAttention(threshold: 0.7),
          isFalse);
    });

    test('confianza 0 no cuenta como baja: hay motores que no la reportan', () {
      // OllamaOcrService devuelve 0.0 porque un modelo de vision no da
      // confianza por token. Eso no debe disparar la alerta por si solo.
      expect(_draft(totalCents: 10000, confidence: 0.0).needsAttention(threshold: 0.7),
          isFalse);
    });
  });

  group('copyWith', () {
    test('aplica las correcciones del usuario y preserva el resto', () {
      final original = _draft(totalCents: 123, items: [_item('Pan', 89000)]);
      final corregido = original.copyWith(
        totalCents: 149382,
        storeName: 'Coto',
        category: ExpenseCategory.delivery,
        receiptDate: DateTime(2025, 12, 25),
      );

      expect(corregido.totalCents, 149382);
      expect(corregido.storeName, 'Coto');
      expect(corregido.category, ExpenseCategory.delivery);
      expect(corregido.receiptDate, DateTime(2025, 12, 25));
      expect(corregido.rawOcrText, original.rawOcrText);
      expect(corregido.items, original.items);
      expect(corregido.ocrConfidence, original.ocrConfidence);
    });
  });
}
