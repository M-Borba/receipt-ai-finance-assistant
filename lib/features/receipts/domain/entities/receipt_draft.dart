import 'package:cross_file/cross_file.dart';
import 'package:equatable/equatable.dart';

import '../../../expenses/domain/entities/expense_entity.dart';
import 'receipt_item_entity.dart';

/// Lo que el OCR leyo de un ticket, ANTES de guardarlo.
///
/// Existe para romper el flujo viejo, donde `uploadAndProcess` escribia a
/// Firestore sin que el usuario pudiera corregir nada: si el OCR leia mal el
/// monto, el dato malo quedaba guardado y recien despues se podia editar.
/// Ahora nada se escribe hasta que la persona confirma.
class ReceiptDraft extends Equatable {
  /// La imagen elegida. Se sube recien al confirmar.
  final XFile imageFile;

  /// Ruta que se le paso al OCR (comprimida en nativo, blob en web).
  final String ocrPath;

  final String rawOcrText;
  final List<ReceiptItemEntity> items;
  final String? storeName;
  final DateTime? receiptDate;
  /// En centavos, o null si el OCR no encontro un total.
  final int? totalCents;
  final ExpenseCategory category;
  final double ocrConfidence;

  const ReceiptDraft({
    required this.imageFile,
    required this.ocrPath,
    required this.rawOcrText,
    required this.items,
    this.storeName,
    this.receiptDate,
    this.totalCents,
    required this.category,
    this.ocrConfidence = 0.0,
  });

  /// Total leido, o la suma de los items si el OCR no encontro un total.
  int get resolvedTotalCents =>
      totalCents ?? items.fold<int>(0, (acc, item) => acc + item.totalPriceCents);

  /// Cuando esto es true conviene avisarle al usuario que revise bien:
  /// no hay total, o la confianza del OCR quedo por debajo del umbral.
  bool needsAttention({required double threshold}) =>
      totalCents == null ||
      resolvedTotalCents <= 0 ||
      (ocrConfidence > 0 && ocrConfidence < threshold);

  ReceiptDraft copyWith({
    List<ReceiptItemEntity>? items,
    String? storeName,
    DateTime? receiptDate,
    int? totalCents,
    ExpenseCategory? category,
  }) {
    return ReceiptDraft(
      imageFile: imageFile,
      ocrPath: ocrPath,
      rawOcrText: rawOcrText,
      items: items ?? this.items,
      storeName: storeName ?? this.storeName,
      receiptDate: receiptDate ?? this.receiptDate,
      totalCents: totalCents ?? this.totalCents,
      category: category ?? this.category,
      ocrConfidence: ocrConfidence,
    );
  }

  @override
  List<Object?> get props =>
      [ocrPath, rawOcrText, items, storeName, receiptDate, totalCents, category];
}
