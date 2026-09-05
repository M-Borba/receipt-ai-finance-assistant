import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/services/classification/merchant_memory.dart';

void main() {
  // La lectura y escritura contra Firestore no se prueba acá: haría falta el
  // emulador. Lo que sí se prueba es la normalización de la clave, que es la
  // parte con lógica y la que decide si dos escrituras del mismo comercio
  // caen en la misma entrada o en dos.
  group('la clave del comercio', () {
    String? clave(String? s) => MerchantMemory.claveDe(s);

    test('el mismo comercio escrito distinto es la misma clave', () {
      final esperada = clave('Tienda Inglesa');
      expect(clave('TIENDA INGLESA'), esperada);
      expect(clave('tienda inglesa'), esperada);
      expect(clave('  Tienda   Inglesa  '), esperada);
    });

    test('las tildes no parten un comercio en dos', () {
      expect(clave('Farmashop Céntrico'), clave('FARMASHOP CENTRICO'));
    });

    test('los guiones cuentan como espacio, igual que en el clasificador', () {
      expect(clave('TA-TA'), clave('ta ta'));
    });

    test('los nombres muy cortos se descartan', () {
      // Una o dos letras no identifican ningún comercio y solo ensucian.
      expect(clave('A'), isNull);
      expect(clave('AB'), isNull);
      expect(clave(null), isNull);
      expect(clave('   '), isNull);
    });

    test('saca los caracteres que Firestore no acepta en un nombre de campo',
        () {
      // Un punto en el nombre de un campo crea un campo anidado en vez de una
      // clave literal, y `~*/[]` estan directamente prohibidos.
      for (final malo in ['Super.Market', 'A/B Market', 'X[1] Market']) {
        final k = clave(malo)!;
        expect(k, isNot(contains('.')));
        expect(k, isNot(contains('/')));
        expect(k, isNot(contains('[')));
        expect(k.trim(), k, reason: 'no deberia quedar con espacios en la punta');
      }
    });

    test('comercios distintos no colisionan', () {
      expect(clave('Devoto'), isNot(clave('Disco')));
    });
  });
}
