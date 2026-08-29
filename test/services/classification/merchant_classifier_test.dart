import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/services/classification/merchant_classifier.dart';

void main() {
  const c = MerchantClassifier();

  group('normalize', () {
    test('quita tildes y baja a minusculas', () {
      expect(MerchantClassifier.normalize('Farmacía'), 'farmacia');
      expect(MerchantClassifier.normalize('EDUCACIÓN'), 'educacion');
      expect(MerchantClassifier.normalize('Ñandú'), 'nandu');
    });
  });

  group('por nombre de comercio', () {
    final casos = {
      'COTO CICSA': ExpenseCategory.groceries,
      'Carrefour Express': ExpenseCategory.groceries,
      'OXXO TIENDAS': ExpenseCategory.groceries,
      'Supermercado Dia': ExpenseCategory.groceries,
      'RAPPI ARGENTINA': ExpenseCategory.delivery,
      'PedidosYa': ExpenseCategory.delivery,
      'McDonalds Palermo': ExpenseCategory.restaurants,
      'Parrilla Don Julio': ExpenseCategory.restaurants,
      'YPF Servicompras': ExpenseCategory.fuel,
      'ESTACION DE SERVICIO SHELL': ExpenseCategory.fuel,
      'UBER TRIP': ExpenseCategory.transportation,
      'Cabify': ExpenseCategory.transportation,
      'FARMACITY S.A.': ExpenseCategory.health,
      'Farmacías del Ahorro': ExpenseCategory.health,
      'EDESUR': ExpenseCategory.utilities,
      'Movistar': ExpenseCategory.utilities,
      'NETFLIX.COM': ExpenseCategory.subscriptions,
      'Spotify AB': ExpenseCategory.subscriptions,
      'Inmobiliaria Lopez': ExpenseCategory.rent,
      'Universidad de Palermo': ExpenseCategory.education,
      'CINEMARK': ExpenseCategory.entertainment,
      'Veterinaria San Roque': ExpenseCategory.pets,
      'MERCADO LIBRE SRL': ExpenseCategory.shopping,
      'Sodimac': ExpenseCategory.shopping,
    };

    casos.forEach((tienda, esperada) {
      test('$tienda -> ${esperada.name}', () {
        expect(c.classify(storeName: tienda), esperada, reason: tienda);
      });
    });
  });

  group('Uruguay', () {
    final casos = {
      'TIENDA INGLESA': ExpenseCategory.groceries,
      'DEVOTO EXPRESS': ExpenseCategory.groceries,
      'TA-TA': ExpenseCategory.groceries,
      'MACROMERCADO': ExpenseCategory.groceries,
      'FARMASHOP 24': ExpenseCategory.health,
      'ANCAP - DUCSA': ExpenseCategory.fuel,
      'UTE': ExpenseCategory.utilities,
      'OSE MONTEVIDEO': ExpenseCategory.utilities,
      'ANTEL': ExpenseCategory.utilities,
      'CUTCSA': ExpenseCategory.transportation,
      'BUQUEBUS': ExpenseCategory.transportation,
      'PEDIDOSYA URUGUAY': ExpenseCategory.delivery,
      'MOSCA LIBRERIA': ExpenseCategory.shopping,
    };
    casos.forEach((tienda, esperada) {
      test('$tienda -> ${esperada.name}', () {
        expect(c.classify(storeName: tienda), esperada, reason: tienda);
      });
    });
  });

  group('desambiguacion', () {
    test('el match mas largo gana sobre el mas corto', () {
      // "supermercado dia" es mas especifico que "mercado".
      expect(c.classify(storeName: 'Supermercado Dia Belgrano'),
          ExpenseCategory.groceries);
    });

    test('el comercio pesa mas que los items', () {
      // Una farmacia que vende golosinas sigue siendo salud.
      expect(
        c.classify(storeName: 'FARMACITY', itemNames: ['Galletitas', 'Leche']),
        ExpenseCategory.health,
      );
    });
  });

  group('por items, cuando el comercio no dice nada', () {
    test('canasta de supermercado', () {
      expect(
        c.classify(
          storeName: 'AUTOSERV. LOS TRES HERMANOS',
          itemNames: ['Leche descremada', 'Pan lactal', 'Yerba mate', 'Huevos'],
        ),
        ExpenseCategory.groceries,
      );
    });

    test('items de farmacia', () {
      expect(
        c.classify(
          storeName: 'LOCAL 42',
          itemNames: ['Ibuprofeno 400mg', 'Protector solar FPS 50'],
        ),
        ExpenseCategory.health,
      );
    });

    test('items de mascotas', () {
      expect(
        c.classify(
          storeName: 'EL GALPON',
          itemNames: ['Alimento para perro adulto 15kg', 'Antipulgas'],
        ),
        ExpenseCategory.pets,
      );
    });
  });

  group('regresion: substrings que ensuciaban', () {
    test('un autoservicio no es un servicio publico', () {
      // "aut-OSE-rv" contenia "ose", la electrica uruguaya.
      expect(
        c.classify(storeName: 'AUTOSERV. LOS TRES HERMANOS', itemNames: ['Leche']),
        ExpenseCategory.groceries,
      );
    });

    test('una gaseosa no es gas', () {
      expect(c.classify(itemNames: ['Gaseosa Coca 2.25L']), ExpenseCategory.groceries);
    });

    test('un barbijo no es un bar', () {
      expect(c.classify(itemNames: ['Barbijo tricapa x10']), ExpenseCategory.health);
    });

    test('los guiones y puntos no rompen el match', () {
      // "TA-TA" no matcheaba la cadena "ta ta".
      expect(c.classify(storeName: 'TA-TA'), ExpenseCategory.groceries);
      expect(c.classify(storeName: 'ANCAP.DUCSA'), ExpenseCategory.fuel);
      expect(c.classify(storeName: 'MC-DONALDS'), ExpenseCategory.restaurants);
    });

    test('una libreria es comercio, una facultad es educacion', () {
      expect(c.classify(storeName: 'MOSCA LIBRERIA'), ExpenseCategory.shopping);
      expect(c.classify(storeName: 'UNIVERSIDAD ORT'), ExpenseCategory.education);
    });

    test('metrogas es servicios, no el metro', () {
      expect(c.classify(storeName: 'METROGAS S.A.'), ExpenseCategory.utilities);
    });
  });

  group('cuando no sabe, devuelve null y no adivina', () {
    test('sin datos', () {
      expect(c.classify(), isNull);
      expect(c.classify(storeName: ''), isNull);
    });

    test('comercio e items desconocidos', () {
      expect(
        c.classify(storeName: 'ZXQW 992', itemNames: ['Articulo 1', 'Articulo 2']),
        isNull,
      );
    });
  });

  group('cobertura del enum', () {
    test('todas las categorias tienen label, emoji y color', () {
      for (final cat in ExpenseCategory.values) {
        expect(cat.label, isNotEmpty, reason: cat.name);
        expect(cat.emoji, isNotEmpty, reason: cat.name);
        expect(cat.color, isNotNull, reason: cat.name);
      }
    });

    test('fromString es tolerante y cae en other', () {
      expect(ExpenseCategory.fromString('GROCERIES'), ExpenseCategory.groceries);
      expect(ExpenseCategory.fromString(' fuel '), ExpenseCategory.fuel);
      expect(ExpenseCategory.fromString('inexistente'), ExpenseCategory.other);
    });
  });
}
