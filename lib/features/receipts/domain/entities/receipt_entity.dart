import 'package:equatable/equatable.dart';

import '../../../expenses/domain/entities/expense_entity.dart';
import 'receipt_item_entity.dart';

enum ReceiptStatus { pending, processing, completed, failed }

class ReceiptEntity extends Equatable {
  final String id;
  final String userId;
  final String imageUrl;
  final String? rawOcrText;
  final String? storeName;
  final DateTime? receiptDate;
  final List<ReceiptItemEntity> items;
  /// En centavos. Ver [Money].
  final int totalCents;
  final ExpenseCategory category;
  final ReceiptStatus status;
  final DateTime createdAt;
  final double ocrConfidence;

  const ReceiptEntity({
    required this.id,
    required this.userId,
    required this.imageUrl,
    this.rawOcrText,
    this.storeName,
    this.receiptDate,
    required this.items,
    required this.totalCents,
    required this.category,
    required this.status,
    required this.createdAt,
    this.ocrConfidence = 0.0,
  });

  ReceiptEntity copyWith({
    String? rawOcrText,
    String? storeName,
    DateTime? receiptDate,
    List<ReceiptItemEntity>? items,
    int? totalCents,
    ExpenseCategory? category,
    ReceiptStatus? status,
    double? ocrConfidence,
  }) {
    return ReceiptEntity(
      id: id,
      userId: userId,
      imageUrl: imageUrl,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      storeName: storeName ?? this.storeName,
      receiptDate: receiptDate ?? this.receiptDate,
      items: items ?? this.items,
      totalCents: totalCents ?? this.totalCents,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
    );
  }

  @override
  List<Object?> get props => [id, userId, status, totalCents, category];
}
