import '../../../../core/format/money.dart';
import '../../domain/entities/receipt_item_entity.dart';

class ReceiptItemModel extends ReceiptItemEntity {
  const ReceiptItemModel({
    required super.id,
    required super.name,
    required super.quantity,
    required super.unitPriceCents,
    required super.totalPriceCents,
  });

  factory ReceiptItemModel.fromEntity(ReceiptItemEntity entity) {
    return ReceiptItemModel(
      id: entity.id,
      name: entity.name,
      quantity: entity.quantity,
      unitPriceCents: entity.unitPriceCents,
      totalPriceCents: entity.totalPriceCents,
    );
  }

  /// Tolera los documentos viejos, que guardaban los precios en pesos como
  /// double. Se convierten al leer, sin script de migracion.
  factory ReceiptItemModel.fromMap(Map<String, dynamic> map) {
    int cents(String nuevo, String viejo) {
      final v = map[nuevo];
      if (v is num) return v.toInt();
      final legacy = map[viejo];
      return legacy is num ? Money.fromMajor(legacy) : 0;
    }

    return ReceiptItemModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      unitPriceCents: cents('unitPriceCents', 'unitPrice'),
      totalPriceCents: cents('totalPriceCents', 'totalPrice'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'unitPriceCents': unitPriceCents,
      'totalPriceCents': totalPriceCents,
    };
  }
}
