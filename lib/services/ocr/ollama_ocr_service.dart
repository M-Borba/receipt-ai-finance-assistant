import 'dart:convert';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';

import '../../core/config/environment.dart';
import '../../core/errors/exceptions.dart';
import 'ocr_service.dart';
import 'receipt_text_parser.dart';

/// OCR strategy powered by Ollama's multimodal vision model (e.g., glm-ocr).
class OllamaOcrService implements OcrService {
  final String baseUrl;
  final String model;
  final _parser = ReceiptTextParser(dayFirst: Environment.datesAreDayFirst);
  final _log = Logger();
  final Dio _dio;

  OllamaOcrService({
    required this.baseUrl,
    required this.model,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 180),
            ));

  @override
  Future<OcrResult> processImage(String imagePath) async {
    try {
      // 1. Read bytes from path or URL
      List<int> bytes;
      if (kIsWeb || imagePath.startsWith('http') || imagePath.startsWith('blob:')) {
        final response = await _dio.get<List<int>>(
          imagePath,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = response.data!;
      } else {
        bytes = await io.File(imagePath).readAsBytes();
      }

      // 2. Encode to Base64
      final base64Image = base64Encode(bytes);

      // 3. Prepare Ollama payload with the image and prompt
      const prompt =
          'Please perform OCR on this receipt image. Extract and transcribe all text layout-accurately, including store name, date, items with their quantities and prices, taxes, and totals. Output ONLY the transcribed text of the receipt.';

      final body = {
        'model': model,
        'prompt': prompt,
        'images': [base64Image],
        'stream': false,
        'options': {
          'temperature': 0.0, // Low temperature for deterministic OCR output
        },
      };

      _log.i('Sending image to Ollama using model: $model (${bytes.length} bytes)');
      final response = await _dio.post('/api/generate', data: body);
      final data = response.data as Map<String, dynamic>;
      final text = (data['response'] as String? ?? '').trim();

      if (text.isEmpty) {
        throw const OcrException('No text detected in receipt image by Ollama');
      }

      _log.i('Ollama OCR completed successfully');

      // 4. Parse using the existing parser.
      //    Un modelo de vision no devuelve confianza por token, asi que no hay
      //    un numero honesto que reportar. Antes se hardcodeaba 0.95, lo que
      //    dejaba sin sentido a `ocrConfidenceThreshold`.
      return _parser.parse(text, confidence: 0.0);
    } catch (e) {
      if (e is OcrException) rethrow;
      _log.e('Ollama OCR error', error: e);
      throw OcrException('Failed to process image with Ollama OCR: $e');
    }
  }
}
