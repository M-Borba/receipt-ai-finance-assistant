import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../../core/errors/exceptions.dart';
import 'ai_provider.dart';

class OllamaProvider implements AIProvider {
  final Dio _dio;
  final String _model;
  final _log = Logger();

  OllamaProvider({
    required String baseUrl,
    required String model,
    Dio? dio,
  })  : _model = model,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 120),
              headers: {'Content-Type': 'application/json'},
            ));

  @override
  String get name => 'ollama:$_model';

  @override
  Future<String> complete({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.3,
    int maxTokens = 1024,
  }) async {
    try {
      final body = {
        'model': _model,
        'prompt': prompt,
        if (systemPrompt != null) 'system': systemPrompt,
        'stream': false,
        'options': {
          'temperature': temperature,
          'num_predict': maxTokens,
        },
      };

      final response = await _dio.post('/api/generate', data: body);
      final data = response.data as Map<String, dynamic>;
      return (data['response'] as String? ?? '').trim();
    } on DioException catch (e) {
      _log.e('Ollama complete error', error: e);
      throw AiException('Ollama request failed: ${e.message}');
    }
  }

  @override
  Stream<String> stream({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.3,
  }) async* {
    try {
      final body = {
        'model': _model,
        'prompt': prompt,
        if (systemPrompt != null) 'system': systemPrompt,
        'stream': true,
        'options': {'temperature': temperature},
      };

      final response = await _dio.post<ResponseBody>(
        '/api/generate',
        data: body,
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data!.stream;
      await for (final chunk in stream) {
        final lines = utf8.decode(chunk).split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final token = json['response'] as String? ?? '';
            if (token.isNotEmpty) yield token;
            if (json['done'] == true) return;
          } catch (_) {
            // Partial JSON chunk — skip
          }
        }
      }
    } on DioException catch (e) {
      throw AiException('Ollama stream failed: ${e.message}');
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _dio.get('/api/tags');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
