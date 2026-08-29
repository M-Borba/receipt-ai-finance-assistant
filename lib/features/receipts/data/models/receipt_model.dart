import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/format/money.dart';

import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/receipt_entity.dart';
import 'receipt_item_model.dart';

class ReceiptModel extends ReceiptEntity {
  const ReceiptModel({
    required super.id,
    required super.userId,
    required super.imageUrl,
    super.rawOcrText,
    super.storeName,
    super.receiptDate,
    required super.items,
    required super.totalCents,
    required super.category,
    required super.status,
    required super.createdAt,
    super.ocrConfidence,
  });

  factory ReceiptModel.fromEntity(ReceiptEntity entity) {
    return ReceiptModel(
      id: entity.id,
      userId: entity.userId,
      imageUrl: entity.imageUrl,
      rawOcrText: entity.rawOcrText,
      storeName: entity.storeName,
      receiptDate: entity.receiptDate,
      items: entity.items,
      totalCents: entity.totalCents,
      category: entity.category,
      status: entity.status,
      createdAt: entity.createdAt,
      ocrConfidence: entity.ocrConfidence,
    );
  }

  factory ReceiptModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReceiptModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      rawOcrText: data['rawOcrText'] as String?,
      storeName: data['storeName'] as String?,
      receiptDate: data['receiptDate'] != null
          ? (data['receiptDate'] as Timestamp).toDate()
          : null,
      items: (data['items'] as List<dynamic>? ?? [])
          .map((i) => ReceiptItemModel.fromMap(i as Map<String, dynamic>))
          .toList(),
      // `totalCents` es la forma nueva; `totalAmount` en pesos es la vieja.
      totalCents: data['totalCents'] is num
          ? (data['totalCents'] as num).toInt()
          : Money.fromMajor((data['totalAmount'] as num?) ?? 0),
      category: ExpenseCategory.fromString(data['category'] as String? ?? 'other'),
      status: ReceiptStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => ReceiptStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ocrConfidence: (data['ocrConfidence'] as num? ?? 0).toDouble(),
    );
  }

  /// `rawOcrText` NO se persiste a proposito: es el texto completo de la
  /// compra (que compraste, donde y cuando) y no lo lee nadie despues del
  /// escaneo. Guardarlo era exposicion sin beneficio. Se sigue leyendo de los
  /// documentos viejos para no romperlos.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'imageUrl': imageUrl,
      'storeName': storeName,
      'receiptDate': receiptDate != null ? Timestamp.fromDate(receiptDate!) : null,
      'items': items
          .map((i) => ReceiptItemModel.fromEntity(i).toMap())
          .toList(),
      'totalCents': totalCents,
      'category': category.name,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'ocrConfidence': ocrConfidence,
    };
  }
}
