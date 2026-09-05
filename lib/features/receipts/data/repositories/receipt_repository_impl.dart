import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/config/environment.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../services/ai/ai_service.dart';
import '../../../../services/image/image_compression_service.dart';
import '../../../../services/classification/merchant_memory.dart';
import '../../../../services/image/thumbnail_service.dart';
import '../../../../services/ocr/ocr_service.dart';
import '../../../../services/ocr/ocr_service_factory.dart';
import '../../../../services/storage/storage_service.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/receipt_draft.dart';
import '../../domain/entities/receipt_entity.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../models/receipt_model.dart';

part 'receipt_repository_impl.g.dart';

@riverpod
ReceiptRepository receiptRepository(Ref ref) {
  return ReceiptRepositoryImpl(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    storageService: ref.watch(storageServiceProvider),
    aiService: ref.watch(aiServiceProvider),
    imageCompressor: ImageCompressionService(),
    ocrService: ref.watch(ocrServiceProvider),
  );
}

class ReceiptRepositoryImpl implements ReceiptRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final StorageService _storageService;
  final AIService _aiService;
  final ImageCompressionService _imageCompressor;
  final OcrService _ocrService;
  final _thumbnails = const ThumbnailService();

  MerchantMemory? _memoryCache;
  String? _memoryUid;

  /// Se reusa la instancia porque cachea el mapa de comercios en memoria: una
  /// nueva en cada acceso releeria Firestore en cada escaneo. Se recrea si
  /// cambio el usuario, para no mezclar la memoria de dos cuentas.
  MerchantMemory get _memory {
    final uid = _userId;
    if (_memoryCache == null || _memoryUid != uid) {
      _memoryCache = MerchantMemory(firestore: _firestore, userId: uid);
      _memoryUid = uid;
    }
    return _memoryCache!;
  }
  final _log = Logger();
  final _uuid = const Uuid();

  ReceiptRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required StorageService storageService,
    required AIService aiService,
    required ImageCompressionService imageCompressor,
    required OcrService ocrService,
  })  : _firestore = firestore,
        _auth = auth,
        _storageService = storageService,
        _aiService = aiService,
        _imageCompressor = imageCompressor,
        _ocrService = ocrService;

  /// Falla de forma explícita en vez de con un `Null check operator` opaco.
  String get _userId {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthException('No authenticated user');
    return uid;
  }

  CollectionReference get _receiptsCol =>
      _firestore.collection(AppConstants.receiptsCollection);

  CollectionReference get _expensesCol =>
      _firestore.collection(AppConstants.expensesCollection);

  DocumentReference _thumbDoc(String receiptId) =>
      _receiptsCol.doc(receiptId).collection('media').doc('thumb');

  @override
  Future<String?> getThumbnail(String receiptId) async {
    try {
      final doc = await _thumbDoc(receiptId).get();
      final data = doc.data() as Map<String, dynamic>?;
      return data?['data'] as String?;
    } catch (e) {
      _log.w('No se pudo leer la miniatura', error: e);
      return null;
    }
  }

  @override
  Future<Either<Failure, ReceiptDraft>> analyzeImage(XFile imageFile) async {
    try {
      // 1. Comprimir (solo nativo: flutter_image_compress no soporta web).
      //    En web la estrategia de OCR lee el blob del picker directamente.
      final String ocrPath;
      if (kIsWeb) {
        ocrPath = imageFile.path;
      } else {
        final compressed = await _imageCompressor.compress(File(imageFile.path));
        ocrPath = compressed.path;
      }

      // 2. OCR
      final ocrResult = await _ocrService.processImage(ocrPath);

      // 3. Clasificar, en orden de mejor a peor senal:
      //
      //    a) lo que VOS elegiste antes para este mismo comercio. Le gana a
      //       todo: tu carniceria del barrio no esta en ninguna lista de
      //       cadenas, pero si la clasificaste una vez no hay que preguntarte
      //       de nuevo.
      //    b) las reglas locales por marca y por producto.
      //    c) la IA, si esta disponible.
      //
      //    Ninguna de las tres bloquea el flujo si falla.
      final recordada = await _memory.categoryFor(ocrResult.storeName);
      final category = recordada ??
          await _aiService.classifyExpense(
            items: ocrResult.items,
            storeName: ocrResult.storeName,
          );

      // Nada se escribio todavia: el usuario revisa y confirma.
      return Right(ReceiptDraft(
        imageFile: imageFile,
        ocrPath: ocrPath,
        rawOcrText: ocrResult.rawText,
        items: ocrResult.items,
        storeName: ocrResult.storeName,
        receiptDate: ocrResult.receiptDate,
        totalCents: ocrResult.totalCents,
        category: category,
        ocrConfidence: ocrResult.confidence,
      ));
    } on OcrException catch (e) {
      _log.e('OCR failed', error: e);
      return Left(OcrFailure(e.message));
    } catch (e) {
      _log.e('Unexpected receipt analysis error', error: e);
      return Left(UnexpectedFailure('No se pudo leer el ticket: $e'));
    }
  }

  @override
  Future<Either<Failure, ReceiptEntity>> saveDraft(ReceiptDraft draft) async {
    try {
      final total = draft.resolvedTotalCents;
      if (total <= 0) {
        return const Left(ValidationFailure('El total tiene que ser mayor a 0'));
      }

      // 1. Subir la imagen. Que falle no puede impedir guardar el dato, que es
      //    lo que realmente importa.
      final uploadBytes = kIsWeb
          ? await draft.imageFile.readAsBytes()
          : await File(draft.ocrPath).readAsBytes();

      // Sin Blaze no hay Storage, y sin este chequeo cada guardado se comia
      // hasta 45 segundos esperando una subida que no podia funcionar.
      String imageUrl = '';
      if (Environment.enableCloudStorage) {
        try {
          final name = draft.imageFile.name.isNotEmpty
              ? draft.imageFile.name
              : draft.imageFile.path;
          final ext = p.extension(name).isNotEmpty ? p.extension(name) : '.jpg';
          imageUrl = await _storageService
              .uploadReceiptImageBytes(uploadBytes, _userId, extension: ext)
              .timeout(const Duration(seconds: 45));
        } catch (e) {
          _log.w('Storage upload failed; queda solo la miniatura', error: e);
        }
      }

      // Miniatura como respaldo: Storage necesita plan Blaze, esto no.
      // Que falle no puede impedir guardar el ticket.
      final thumbnail = _thumbnails.buildBase64(uploadBytes);

      final receiptId = _uuid.v4();
      final receipt = ReceiptEntity(
        id: receiptId,
        userId: _userId,
        imageUrl: imageUrl,
        // Sin rawOcrText: ver ReceiptModel.toFirestore.
        storeName: draft.storeName,
        receiptDate: draft.receiptDate,
        items: draft.items,
        totalCents: total,
        category: draft.category,
        status: ReceiptStatus.completed,
        createdAt: DateTime.now(),
        ocrConfidence: draft.ocrConfidence,
      );

      // 2. Recibo y gasto en una sola escritura atomica.
      final batch = _firestore.batch();
      batch.set(
        _receiptsCol.doc(receiptId),
        ReceiptModel.fromEntity(receipt).toFirestore(),
      );
      batch.set(_expensesCol.doc(), {
        'userId': _userId,
        'receiptId': receiptId,
        'category': draft.category.name,
        'amountCents': total,
        'storeName': draft.storeName,
        'date': Timestamp.fromDate(draft.receiptDate ?? DateTime.now()),
        'createdAt': Timestamp.now(),
      });
      if (thumbnail != null) {
        batch.set(_thumbDoc(receiptId), {
          // userId en el propio documento: asi las reglas lo validan sin tener
          // que leer el ticket padre, que costaria una lectura por evaluacion.
          'userId': _userId,
          'data': thumbnail,
          'createdAt': Timestamp.now(),
        });
      }

      await batch.commit();

      // Recien aca se aprende, no al escanear: lo que importa es la categoria
      // que la persona CONFIRMO, que puede ser distinta de la que se adivino.
      // Que falle no puede tumbar un guardado que ya se hizo.
      unawaited(_memory.remember(draft.storeName, draft.category));

      return Right(receipt);
    } on StorageException catch (e) {
      return Left(StorageFailure(e.message));
    } catch (e) {
      _log.e('Unexpected receipt save error', error: e);
      return Left(UnexpectedFailure('No se pudo guardar el ticket: $e'));
    }
  }

  @override
  Future<Either<Failure, List<ReceiptEntity>>> getReceipts({int? limit}) async {
    try {
      var query = _receiptsCol
          .where('userId', isEqualTo: _userId)
          .orderBy('createdAt', descending: true);

      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();
      final receipts = snapshot.docs
          .map((doc) => ReceiptModel.fromFirestore(doc))
          .toList();

      return Right(receipts);
    } catch (e) {
      return Left(NetworkFailure('Failed to fetch receipts: $e'));
    }
  }

  @override
  Future<Either<Failure, ReceiptEntity>> getReceiptById(String id) async {
    try {
      final doc = await _receiptsCol.doc(id).get();
      if (!doc.exists) return const Left(NetworkFailure('Receipt not found'));
      return Right(ReceiptModel.fromFirestore(doc));
    } catch (e) {
      return Left(NetworkFailure('$e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteReceipt(String id) async {
    try {
      final doc = await _receiptsCol.doc(id).get();
      if (doc.exists) {
        final receipt = ReceiptModel.fromFirestore(doc);
        // Que falle borrar la imagen no puede impedir borrar el dato.
        try {
          await _storageService.deleteReceiptImage(receipt.imageUrl);
        } catch (e) {
          _log.w('Could not delete receipt image', error: e);
        }
      }

      // Los gastos asociados quedaban huérfanos y seguían sumando en el
      // dashboard aunque el recibo ya no existiera.
      final linkedExpenses = await _expensesCol
          .where('userId', isEqualTo: _userId)
          .where('receiptId', isEqualTo: id)
          .get();

      final batch = _firestore.batch();
      for (final expense in linkedExpenses.docs) {
        batch.delete(expense.reference);
      }
      batch.delete(_thumbDoc(id));
      batch.delete(_receiptsCol.doc(id));
      await batch.commit();

      return const Right(null);
    } catch (e) {
      return Left(StorageFailure('$e'));
    }
  }

  @override
  Future<Either<Failure, ReceiptEntity>> updateReceipt({
    required String id,
    required String storeName,
    required int totalCents,
    required ExpenseCategory category,
    required DateTime receiptDate,
  }) async {
    try {
      // Sin el filtro por userId esta query viola las reglas de Firestore
      // (`allow list: if owns()`) y devuelve PERMISSION_DENIED.
      final expensesQuery = await _expensesCol
          .where('userId', isEqualTo: _userId)
          .where('receiptId', isEqualTo: id)
          .get();

      final batch = _firestore.batch();

      batch.update(_receiptsCol.doc(id), {
        'storeName': storeName,
        'totalCents': totalCents,
        'category': category.name,
        'receiptDate': Timestamp.fromDate(receiptDate),
      });

      for (final expDoc in expensesQuery.docs) {
        batch.update(expDoc.reference, {
          'storeName': storeName,
          'amountCents': totalCents,
          'category': category.name,
          'date': Timestamp.fromDate(receiptDate),
        });
      }

      await batch.commit();

      // Editar la categoria de un ticket es la correccion mas explicita que
      // existe: es exactamente el momento en que hay que aprender.
      unawaited(_memory.remember(storeName, category));

      final doc = await _receiptsCol.doc(id).get();
      return Right(ReceiptModel.fromFirestore(doc));
    } catch (e) {
      return Left(NetworkFailure('Failed to update receipt: $e'));
    }
  }


  @override
  Stream<List<ReceiptEntity>> watchReceipts() {
    return _receiptsCol
        .where('userId', isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .limit(AppConstants.receiptsPageSize)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ReceiptModel.fromFirestore(doc))
            .toList());
  }
}
