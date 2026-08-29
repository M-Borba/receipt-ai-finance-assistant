import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/services/ocr/ollama_ocr_service.dart';

class FakeDio implements Dio {
  List<int>? mockGetBytes;
  Map<String, dynamic>? mockPostResponse;

  @override
  late BaseOptions options;

  FakeDio({required String baseUrl}) {
    options = BaseOptions(baseUrl: baseUrl);
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (mockGetBytes != null && T == List<int>) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: mockGetBytes as T,
        statusCode: 200,
      );
    }
    throw UnimplementedError('FakeDio get not configured for this call');
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (path == '/api/generate' && mockPostResponse != null) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: mockPostResponse as T,
        statusCode: 200,
      );
    }
    throw UnimplementedError('FakeDio post not configured for this call');
  }

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeDio fakeDio;
  late OllamaOcrService ocrService;

  setUp(() {
    fakeDio = FakeDio(baseUrl: 'http://localhost:11434');
    ocrService = OllamaOcrService(
      baseUrl: 'http://localhost:11434',
      model: 'glm-ocr',
      dio: fakeDio,
    );
  });

  group('OllamaOcrService', () {
    test('successfully processes image data and returns parsed OCR result', () async {
      // Configure FakeDio response for get
      fakeDio.mockGetBytes = [1, 2, 3, 4];

      // Configure FakeDio response for post
      fakeDio.mockPostResponse = {
        'response': '''
WHOLE FOODS MARKET
03/15/2025

Organic Milk 2%                  5.49
Sourdough Bread                  6.99

SUBTOTAL                        12.48
TAX                              1.00
TOTAL                           13.48
'''
      };

      final result = await ocrService.processImage('blob:http://localhost/abc');

      expect(result.rawText, contains('WHOLE FOODS MARKET'));
      expect(result.storeName, equals('WHOLE FOODS MARKET'));
      expect(result.totalCents, equals(1348));
      expect(result.items, hasLength(2));
      expect(result.items[0].name, equals('Organic Milk 2%'));
      expect(result.items[0].totalPriceCents, equals(549));
    });
  });
}
