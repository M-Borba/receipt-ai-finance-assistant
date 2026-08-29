import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';

part 'storage_service.g.dart';

@riverpod
StorageService storageService(Ref ref) => StorageService();

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();
  final _log = Logger();

  /// Uploads raw image bytes. Works on every platform (web included),
  /// unlike [uploadReceiptImage] which needs a dart:io [File].
  Future<String> uploadReceiptImageBytes(
    Uint8List bytes,
    String userId, {
    String extension = '.jpg',
  }) async {
    try {
      final fileName = '${_uuid.v4()}$extension';
      final storagePath = '${AppConstants.receiptImagesPath}/$userId/$fileName';

      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedBy': userId},
      );

      final task = await ref.putData(bytes, metadata);
      final downloadUrl = await task.ref.getDownloadURL();

      _log.d('Uploaded receipt image: $storagePath');
      return downloadUrl;
    } catch (e) {
      _log.e('Failed to upload receipt image', error: e);
      throw StorageException('Failed to upload image: $e');
    }
  }

  Future<String> uploadReceiptImage(File imageFile, String userId) async {
    try {
      final ext = path.extension(imageFile.path);
      final fileName = '${_uuid.v4()}$ext';
      final storagePath =
          '${AppConstants.receiptImagesPath}/$userId/$fileName';

      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedBy': userId},
      );

      final task = await ref.putFile(imageFile, metadata);
      final downloadUrl = await task.ref.getDownloadURL();

      _log.d('Uploaded receipt image: $storagePath');
      return downloadUrl;
    } catch (e) {
      _log.e('Failed to upload receipt image', error: e);
      throw StorageException('Failed to upload image: $e');
    }
  }

  /// True solo si la URL apunta de verdad a Firebase Storage.
  ///
  /// Los recibos guardados cuando Storage no estaba activo tienen un `blob:`,
  /// una ruta local o directamente vacio. Llamar a Storage con eso falla
  /// siempre, y en web el navegador tira un error de CORS bien visible.
  static bool isStorageUrl(String url) {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return uri.host == 'firebasestorage.googleapis.com' ||
        uri.host.endsWith('.firebasestorage.app') ||
        uri.host == 'storage.googleapis.com';
  }

  Future<void> deleteReceiptImage(String imageUrl) async {
    if (!isStorageUrl(imageUrl)) {
      _log.d('Sin imagen en Storage que borrar: $imageUrl');
      return;
    }
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      _log.w('Failed to delete image', error: e);
    }
  }

  Stream<double> uploadWithProgress(File imageFile, String userId) {
    final ext = path.extension(imageFile.path);
    final fileName = '${_uuid.v4()}$ext';
    final storagePath = '${AppConstants.receiptImagesPath}/$userId/$fileName';

    final ref = _storage.ref(storagePath);
    final task = ref.putFile(imageFile);

    return task.snapshotEvents.map((event) {
      return event.bytesTransferred / event.totalBytes;
    });
  }
}
