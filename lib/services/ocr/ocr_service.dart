import '../../features/receipts/domain/entities/receipt_item_entity.dart';

/// Abstraction for OCR implementations (ML Kit, Tesseract, cloud OCR, etc.)
abstract interface class OcrService {
  Future<OcrResult> processImage(String imagePath);
}

class OcrResult {
  final String rawText;
  final List<ReceiptItemEntity> items;
  final String? storeName;
  /// RUT del comercio que emitio el ticket, 12 digitos. Ver
  /// `ReceiptTextParser.extractRut`.
  final String? merchantRut;
  final DateTime? receiptDate;
  /// En centavos, o null si no se encontro total.
  final int? totalCents;
  final double confidence;

  const OcrResult({
    required this.rawText,
    required this.items,
    this.storeName,
    this.merchantRut,
    this.receiptDate,
    this.totalCents,
    this.confidence = 0.0,
  });
}
