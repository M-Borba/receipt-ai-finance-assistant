import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

class ImageCompressionService {
  final _log = Logger();
  final _uuid = const Uuid();

  Future<File> compress(File imageFile) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = path.extension(imageFile.path).toLowerCase();
      final outputPath = '${tempDir.path}/${_uuid.v4()}$ext';

      final result = await FlutterImageCompress.compressAndGetFile(
        imageFile.absolute.path,
        outputPath,
        quality: AppConstants.imageQuality,
        minWidth: AppConstants.imageMaxWidth,
        minHeight: AppConstants.imageMaxHeight,
        keepExif: false,
      );

      if (result == null) {
        _log.w('Compression failed, returning original');
        return imageFile;
      }

      final compressed = File(result.path);
      final originalSize = await imageFile.length();
      final compressedSize = await compressed.length();

      _log.d(
        'Compressed: ${(originalSize / 1024).round()}KB -> ${(compressedSize / 1024).round()}KB',
      );

      return compressed;
    } catch (e) {
      _log.e('Compression error', error: e);
      return imageFile;
    }
  }
}
