import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/group_expense_entity.dart';
import '../../domain/split.dart';

class GroupExpenseModel extends GroupExpenseEntity {
  const GroupExpenseModel({
    required super.id,
    required super.groupId,
    required super.description,
    required super.amountCents,
    required super.date,
    required super.mode,
    required super.paidBy,
    required super.shares,
    required super.createdBy,
    required super.createdAt,
    super.receiptId,
  });

  factory GroupExpenseModel.fromFirestore(DocumentSnapshot doc, String groupId) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return GroupExpenseModel(
      id: doc.id,
      groupId: groupId,
      description: data['description'] as String? ?? '',
      amountCents: (data['amountCents'] as num?)?.toInt() ?? 0,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      mode: SplitMode.values.firstWhere(
        (m) => m.name == data['mode'],
        orElse: () => SplitMode.equal,
      ),
      paidBy: _cents(data['paidBy']),
      shares: _cents(data['shares']),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      receiptId: data['receiptId'] as String?,
    );
  }

  /// Firestore devuelve los numeros como `num`. Se fuerza a `int` porque toda
  /// la plata son centavos enteros.
  static Map<String, int> _cents(Object? raw) {
    final m = (raw as Map<String, dynamic>?) ?? const {};
    return {
      for (final e in m.entries) e.key: (e.value as num?)?.toInt() ?? 0,
    };
  }

  Map<String, dynamic> toFirestore() => {
        'description': description,
        'amountCents': amountCents,
        'date': Timestamp.fromDate(date),
        'mode': mode.name,
        'paidBy': paidBy,
        'shares': shares,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
        if (receiptId != null) 'receiptId': receiptId,
      };
}
