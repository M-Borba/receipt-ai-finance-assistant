import 'package:cross_file/cross_file.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../entities/receipt_draft.dart';
import '../entities/receipt_entity.dart';

abstract interface class ReceiptRepository {
  /// Comprime, corre OCR y clasifica. NO escribe nada en Firestore ni sube la
  /// imagen: devuelve un borrador para que el usuario lo revise y corrija.
  Future<Either<Failure, ReceiptDraft>> analyzeImage(XFile imageFile);

  /// Sube la imagen y guarda el recibo y su gasto, ya confirmados.
  Future<Either<Failure, ReceiptEntity>> saveDraft(ReceiptDraft draft);

  Future<Either<Failure, List<ReceiptEntity>>> getReceipts({int? limit});
  Future<Either<Failure, ReceiptEntity>> getReceiptById(String id);
  Future<Either<Failure, void>> deleteReceipt(String id);
  Future<Either<Failure, ReceiptEntity>> updateReceipt({
    required String id,
    required String storeName,
    required int totalCents,
    required ExpenseCategory category,
    required DateTime receiptDate,
  });
  /// Miniatura del ticket en base64, o null si no tiene.
  /// Vive en una subcoleccion aparte para que la lista de tickets no la
  /// arrastre en cada snapshot.
  Future<String?> getThumbnail(String receiptId);

  Stream<List<ReceiptEntity>> watchReceipts();
}
