import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/budget_entity.dart';

class BudgetModel extends BudgetEntity {
  const BudgetModel({
    required super.id,
    required super.userId,
    required super.category,
    required super.limitCents,
  });

  factory BudgetModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    return BudgetModel(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      category: ExpenseCategory.fromString(data['category'] as String? ?? 'other'),
      limitCents: (data['limitCents'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'category': category.name,
        'limitCents': limitCents,
        'updatedAt': Timestamp.now(),
      };
}
