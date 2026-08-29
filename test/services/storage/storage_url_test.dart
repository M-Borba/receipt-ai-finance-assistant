import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/services/storage/storage_service.dart';

void main() {
  group('StorageService.isStorageUrl', () {
    test('acepta URLs reales de Firebase Storage', () {
      expect(
        StorageService.isStorageUrl(
          'https://firebasestorage.googleapis.com/v0/b/mborba-proyect.appspot.com/o/receipt_images%2Fu1%2Fa.jpg?alt=media&token=abc',
        ),
        isTrue,
      );
      expect(
        StorageService.isStorageUrl('https://mborba-proyect.firebasestorage.app/a.jpg'),
        isTrue,
      );
    });

    test('rechaza lo que producia el error de CORS al borrar', () {
      // Recibos guardados cuando Storage no estaba activo.
      expect(StorageService.isStorageUrl(''), isFalse);
      expect(StorageService.isStorageUrl('blob:http://localhost:5000/abc-123'), isFalse);
      expect(StorageService.isStorageUrl('/data/user/0/app/cache/ticket.jpg'), isFalse);
      expect(StorageService.isStorageUrl('file:///tmp/ticket.jpg'), isFalse);
    });

    test('rechaza hosts ajenos', () {
      expect(StorageService.isStorageUrl('https://evil.com/a.jpg'), isFalse);
      // Sufijo parecido pero host distinto.
      expect(StorageService.isStorageUrl('https://firebasestorage.googleapis.com.evil.com/a.jpg'), isFalse);
    });
  });
}
