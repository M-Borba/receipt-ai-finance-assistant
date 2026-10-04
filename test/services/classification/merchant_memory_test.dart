import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
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

  // MemoriaComercios es la logica sin Firestore: lo que se lee del documento,
  // como se consulta y que se escribe. Lo unico que queda sin probar es la
  // lectura y la escritura en si.
  group('memoria por RUT y por nombre', () {
    const rut = '210000000010';

    test('el bug: aprendia el nombre corregido y buscaba el del OCR', () {
      // Escaneo: el OCR lee "GUILLERNO PUJADAS SAS" y la persona lo corrige.
      final m = MemoriaComercios();
      m.aprender(
        nombres: ['GUILLERNO PUJADAS SAS', 'Carnicería Pujadas'],
        categoria: ExpenseCategory.groceries,
      );
      // Proximo escaneo: el OCR vuelve a leer lo mismo de siempre.
      expect(m.categoriaPara(nombre: 'GUILLERNO PUJADAS SAS'),
          ExpenseCategory.groceries);
      // Y en un gasto manual se escribe el corregido.
      expect(m.categoriaPara(nombre: 'carniceria pujadas'),
          ExpenseCategory.groceries);
    });

    test('el RUT encuentra al comercio aunque el OCR lea otro nombre', () {
      final m = MemoriaComercios();
      m.aprender(
        rut: rut,
        nombres: ['GUILLERNO PUJADAS SAS'],
        categoria: ExpenseCategory.groceries,
      );
      expect(
        m.categoriaPara(rut: rut, nombre: 'GUILLERMO PUJADAS SAS'),
        ExpenseCategory.groceries,
      );
    });

    test('el RUT le gana al nombre', () {
      final m = MemoriaComercios(
        porNombre: {'pujadas': ExpenseCategory.restaurants},
        porRut: {rut: ExpenseCategory.groceries},
      );
      expect(m.categoriaPara(rut: rut, nombre: 'Pujadas'),
          ExpenseCategory.groceries);
    });

    test('un RUT que no conoce cae al nombre', () {
      final m = MemoriaComercios(porNombre: {'pujadas': ExpenseCategory.groceries});
      expect(m.categoriaPara(rut: '219999999999', nombre: 'Pujadas'),
          ExpenseCategory.groceries);
    });

    test('lo que se escribe: nombres sueltos y el RUT anidado', () {
      final cambios = MemoriaComercios().aprender(
        rut: '21 000000 0010',
        nombres: ['GUILLERNO PUJADAS SAS', 'Carnicería Pujadas', null],
        categoria: ExpenseCategory.groceries,
      );
      expect(cambios, {
        'guillerno pujadas sas': 'groceries',
        'carniceria pujadas': 'groceries',
        MemoriaComercios.campoRut: {rut: 'groceries'},
      });
    });

    test('lo escrito se vuelve a leer igual (documento con merge)', () {
      final m = MemoriaComercios();
      final doc = <String, dynamic>{'tienda inglesa': 'groceries'};
      final cambios = m.aprender(
        rut: rut,
        nombres: ['Pujadas'],
        categoria: ExpenseCategory.groceries,
      );
      doc.addAll(cambios);

      final leida = MemoriaComercios.desdeDocumento(doc);
      expect(leida.categoriaPara(rut: rut), ExpenseCategory.groceries);
      expect(leida.categoriaPara(nombre: 'Pujadas'), ExpenseCategory.groceries);
      expect(leida.categoriaPara(nombre: 'Tienda Inglesa'),
          ExpenseCategory.groceries);
      // El mapa de RUTs no se confunde con un comercio llamado asi.
      expect(leida.porNombre.containsKey(MemoriaComercios.campoRut), isFalse);
    });

    test('un documento viejo, sin RUTs, se sigue leyendo', () {
      final m = MemoriaComercios.desdeDocumento({'farmashop': 'health'});
      expect(m.categoriaPara(nombre: 'FARMASHOP'), ExpenseCategory.health);
      expect(m.porRut, isEmpty);
    });

    test('ningun nombre de comercio puede pisar el campo de los RUTs', () {
      expect(MemoriaComercios.claveNombre('por_rut'),
          isNot(MemoriaComercios.campoRut));
      expect(MemoriaComercios.claveNombre('POR-RUT'),
          isNot(MemoriaComercios.campoRut));
    });

    test('"Otros" no se aprende ni por nombre ni por RUT', () {
      final m = MemoriaComercios();
      final cambios = m.aprender(
        rut: rut,
        nombres: ['Kiosco Pepe'],
        categoria: ExpenseCategory.other,
      );
      expect(cambios, isEmpty);
      expect(m.categoriaPara(rut: rut, nombre: 'Kiosco Pepe'), isNull);
    });

    test('si ya estaba asi no escribe nada', () {
      final m = MemoriaComercios(
        porNombre: {'pujadas': ExpenseCategory.groceries},
        porRut: {rut: ExpenseCategory.groceries},
      );
      expect(
        m.aprender(
            rut: rut, nombres: ['Pujadas'], categoria: ExpenseCategory.groceries),
        isEmpty,
      );
    });

    test('cambiar de opinion pisa lo anterior', () {
      final m = MemoriaComercios(porRut: {rut: ExpenseCategory.restaurants});
      m.aprender(rut: rut, categoria: ExpenseCategory.groceries);
      expect(m.categoriaPara(rut: rut), ExpenseCategory.groceries);
    });

    test('el RUT tiene que tener 12 digitos', () {
      expect(MemoriaComercios.claveRut('21.000000.0010'), rut);
      expect(MemoriaComercios.claveRut('2100000000'), isNull);
      expect(MemoriaComercios.claveRut('2100000000101'), isNull);
      expect(MemoriaComercios.claveRut(null), isNull);
    });

    test('el tope no deja crecer el documento sin freno', () {
      final m = MemoriaComercios(porNombre: {
        for (var i = 0; i < MemoriaComercios.maxComercios; i++)
          'comercio $i': ExpenseCategory.groceries,
      });
      expect(
          m.aprender(nombres: ['Uno Nuevo'], categoria: ExpenseCategory.health),
          isEmpty);
      // Pero uno que ya estaba se puede corregir.
      expect(
          m.aprender(nombres: ['comercio 3'], categoria: ExpenseCategory.health),
          isNotEmpty);
    });
  });
}
