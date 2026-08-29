import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/format/money.dart';
import '../../domain/entities/expense_entity.dart';

class ExpenseModel extends ExpenseEntity {
  const ExpenseModel({
    required super.id,
    required super.userId,
    super.receiptId,
    required super.category,
    required super.amountCents,
    super.storeName,
    super.note,
    required super.date,
    required super.createdAt,
  });

  /// Tolerante a documentos incompletos: antes un `amount` faltante o un `date`
  /// nulo tiraba una excepcion de cast que tumbaba la lista entera de gastos.
  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return ExpenseModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      receiptId: data['receiptId'] as String?,
      category: ExpenseCategory.fromString(data['category'] as String? ?? 'other'),
      // `amountCents` es la forma nueva. Los documentos viejos guardaban
      // `amount` en pesos como double: se convierten al leer, sin script de
      // migracion.
      amountCents: data['amountCents'] is num
          ? (data['amountCents'] as num).toInt()
          : Money.fromMajor((data['amount'] as num?) ?? 0),
      storeName: data['storeName'] as String?,
      note: data['note'] as String?,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory ExpenseModel.fromEntity(ExpenseEntity e) => ExpenseModel(
        id: e.id,
        userId: e.userId,
        receiptId: e.receiptId,
        category: e.category,
        amountCents: e.amountCents,
        storeName: e.storeName,
        note: e.note,
        date: e.date,
        createdAt: e.createdAt,
      );

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'receiptId': receiptId,
      'category': category.name,
      'amountCents': amountCents,
      'storeName': storeName,
      'note': note,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
