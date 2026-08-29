import '../../features/expenses/domain/entities/expense_entity.dart';

/// Clasifica un ticket por nombre de comercio y por los items que contiene.
///
/// Corre en el dispositivo: gratis, instantaneo y offline. Es lo que decide la
/// categoria cuando no hay IA disponible, que hoy es SIEMPRE fuera de la maquina
/// de desarrollo, porque el proveedor apunta a Ollama en localhost.
///
/// El fallback anterior conocia diez marcas de Estados Unidos, asi que en
/// produccion todo caia en `other`.
class MerchantClassifier {
  const MerchantClassifier();

  /// Marcas y palabras de comercio. El nombre del comercio pesa mucho mas que
  /// los items: si el ticket dice "FARMACITY", es salud sin importar que haya
  /// vendido golosinas.
  static const _merchantRules = <ExpenseCategory, List<String>>{
    ExpenseCategory.groceries: [
      // AR
      'coto', 'carrefour', 'jumbo', 'disco', 'vea', 'dia%', 'dia', 'supermercado dia',
      'chango mas', 'changomas', 'la anonima', 'toledo', 'josimar', 'vital',
      'maxiconsumo', 'diarco', 'makro', 'walmart', 'chino', 'autoservicio',
      // MX
      'oxxo', 'soriana', 'chedraui', 'bodega aurrera', 'la comer', 'heb',
      'superama', 'sams club', 'costco',
      // CL / CO / UY / PE
      'lider', 'santa isabel', 'unimarc', 'tottus', 'exito', 'olimpica',
      'ara', 'd1', 'justo y bueno',
      // UY
      'devoto', 'tienda inglesa', 'ta ta', 'tata', 'geant', 'fresh market',
      'el dorado', 'macromercado', 'kinko', 'multi ahorro',
      'wong', 'plaza vea', 'metro',
      // generico
      'supermercado', 'super mercado', 'mercado', 'almacen', 'verduleria',
      'carniceria', 'panaderia', 'fiambreria', 'dietetica',
    ],
    ExpenseCategory.delivery: [
      'rappi', 'pedidosya', 'pedidos ya', 'uber eats', 'ubereats', 'glovo',
      'didi food', 'didifood', 'justo', 'doordash', 'grubhub', 'ifood',
      'delivery', 'envio a domicilio',
    ],
    ExpenseCategory.restaurants: [
      'mcdonalds', 'mc donalds', 'burger king', 'starbucks', 'subway',
      'kfc', 'wendys', 'dominos', 'papa johns', 'mostaza', 'la birra',
      'restaurant', 'restaurante', 'parrilla', 'pizzeria', 'cafe', 'cafeteria',
      'bar', 'cerveceria', 'heladeria', 'sushi', 'confiteria', 'resto',
    ],
    ExpenseCategory.fuel: [
      'ypf', 'shell', 'axion', 'puma energy', 'petrobras', 'esso', 'refinor',
      'pemex', 'copec', 'terpel', 'primax', 'ancap', 'ducsa', 'disa',
      'estacion de servicio',
      'gasolinera', 'combustible', 'nafta', 'gasoil',
    ],
    ExpenseCategory.transportation: [
      'uber', 'cabify', 'didi', 'lyft', 'beat', 'taxi', 'remis',
      'sube', 'subte', 'metrobus', 'colectivo', 'peaje', 'autopista',
      'stm', 'cutcsa', 'copsa', 'coetc', 'buquebus', 'colonia express',
      'aerolineas', 'latam', 'flybondi', 'jetsmart', 'estacionamiento',
      'cochera', 'parking',
    ],
    ExpenseCategory.health: [
      'farmacity', 'farmacia', 'farmacias', 'del ahorro', 'guadalajara',
      'cruz verde', 'ahumada', 'salcobrand', 'la sante', 'drogueria',
      'osde', 'swiss medical', 'galeno', 'medicus', 'sanatorio', 'clinica',
      'hospital', 'laboratorio', 'odontolog', 'dentista', 'optica',
      'farmashop', 'san roque', 'asse', 'casmu', 'medica uruguaya', 'summum',
      'cvs', 'walgreen', 'pharmacy',
    ],
    ExpenseCategory.utilities: [
      'edenor', 'edesur', 'edea', 'metrogas', 'naturgy', 'camuzzi',
      'aysa', 'absa', 'aguas', 'cfe', 'enel', 'epm', 'ute', 'ose', 'antel',
      'telecom', 'movistar', 'personal', 'claro', 'fibertel', 'flow',
      'telecentro', 'telmex', 'izzi', 'totalplay', 'directv',
      'montevideo gas', 'nuevo siglo', 'tcc', 'dedicado',
      'luz', 'gas', 'agua', 'internet', 'electricidad',
    ],
    ExpenseCategory.subscriptions: [
      'netflix', 'spotify', 'disney', 'hbo', 'max', 'prime video',
      'amazon prime', 'apple', 'itunes', 'google', 'youtube', 'paramount',
      'crunchyroll', 'dropbox', 'notion', 'canva', 'adobe', 'microsoft',
      'openai', 'anthropic', 'github', 'suscripcion', 'membresia',
    ],
    ExpenseCategory.rent: [
      'alquiler', 'inmobiliaria', 'expensas', 'consorcio', 'administracion',
      'renta', 'arrendamiento',
    ],
    ExpenseCategory.education: [
      'universidad', 'facultad', 'colegio', 'escuela', 'instituto',
      'academia', 'curso', 'udemy', 'coursera', 'platzi', 'duolingo',
      'matricula', 'cuota escolar',
    ],
    ExpenseCategory.entertainment: [
      'cinemark', 'hoyts', 'showcase', 'cinepolis', 'cine', 'teatro',
      'ticketek', 'passline', 'eventbrite', 'steam', 'playstation', 'xbox',
      'nintendo', 'gimnasio', 'gym', 'smartfit', 'club',
    ],
    ExpenseCategory.pets: [
      'veterinaria', 'veterinario', 'petshop', 'pet shop', 'puppis',
      'mascotas', 'kongo',
    ],
    ExpenseCategory.shopping: [
      'mercado libre', 'mercadolibre', 'amazon', 'aliexpress', 'shein',
      'temu', 'falabella', 'liverpool', 'palacio de hierro', 'ripley',
      'paris', 'zara', 'h&m', 'nike', 'adidas', 'dexter', 'stock center',
      'fravega', 'garbarino', 'musimundo', 'coppel', 'elektra',
      'divino', 'mosca', 'bookshop', 'tienda mia',
      'easy', 'sodimac', 'home depot', 'ferreteria', 'libreria', 'papeleria',
    ],
  };

  /// Palabras que aparecen en los items. Señal mas debil: se usa cuando el
  /// comercio no dice nada.
  static const _itemRules = <ExpenseCategory, List<String>>{
    ExpenseCategory.groceries: [
      'leche', 'pan', 'arroz', 'fideos', 'aceite', 'azucar', 'harina',
      'yerba', 'mate', 'cafe', 'te', 'huevo', 'queso', 'jamon', 'yogur',
      'manteca', 'fruta', 'verdura', 'tomate', 'papa', 'cebolla', 'banana',
      'manzana', 'pollo', 'carne', 'milanesa', 'asado', 'galletita',
      'gaseosa', 'agua mineral', 'cerveza', 'vino', 'detergente', 'lavandina',
      'papel higienico', 'shampoo', 'jabon', 'pañal', 'panal',
      // Vocabulario que aparecio en tickets uruguayos reales y no matcheaba:
      // panaderia, carniceria y distribuidora de bebidas.
      'medialuna', 'medialunas', 'bizcocho', 'bizcochos', 'catalanes',
      'factura de panaderia', 'chacinado', 'chacinados', 'fiambre',
      'cordero', 'cerdo', 'pescado', 'aves', 'pulpa', 'costilla',
      'jugo', 'refresco', 'malbec', 'tannat', 'cabernet', 'merlot',
      'zillertal', 'patricia', 'pilsen', 'norteña', 'nortena',
    ],
    ExpenseCategory.restaurants: [
      'empanada', 'pizza', 'hamburguesa', 'milanesa napolitana', 'cubierto',
      'menu', 'entrada', 'postre', 'guarnicion', 'copa de vino',
    ],
    ExpenseCategory.health: [
      'ibuprofeno', 'paracetamol', 'amoxicilina', 'aspirina', 'vitamina',
      'jarabe', 'comprimidos', 'crema', 'alcohol en gel', 'barbijo',
      'preservativo', 'protector solar',
    ],
    ExpenseCategory.pets: [
      'alimento para perro', 'alimento para gato', 'balanceado',
      'arena sanitaria', 'antipulgas',
    ],
    ExpenseCategory.fuel: ['nafta', 'infinia', 'diesel', 'gasoil'],
  };

  /// Quita tildes y pasa a minusculas, para que "Farmacía" matchee "farmacia".
  static String normalize(String input) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    const to = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final idx = from.indexOf(ch);
      buffer.write(idx == -1 ? ch : to[idx]);
    }
    // Guiones, puntos, barras y guiones bajos cuentan como separadores de
    // palabra: sin esto "TA-TA" no matcheaba la cadena "ta ta".
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[-_/.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Cache de expresiones por palabra clave.
  static final Map<String, RegExp> _cache = {};

  /// Match por palabra completa, no por substring.
  ///
  /// Sin esto, "ose" (la eléctrica uruguaya) matcheaba dentro de
  /// "aut-OSE-rv" y un autoservicio quedaba como servicios. Lo mismo pasaba
  /// con "gas" dentro de "gaseosa" y "bar" dentro de "barbijo".
  static bool _matches(String text, String keyword) {
    final re = _cache.putIfAbsent(keyword, () {
      final escaped = RegExp.escape(keyword);
      return RegExp('(?<![a-z0-9])$escaped(?![a-z0-9])');
    });
    return re.hasMatch(text);
  }

  /// Categoria sugerida, o null si no hay ninguna señal.
  ///
  /// Devolver null (y no `other`) permite distinguir "no se" de "es otro",
  /// para que quien llame decida si vale la pena preguntarle a la IA.
  ExpenseCategory? classify({String? storeName, List<String> itemNames = const []}) {
    final store = normalize(storeName ?? '');

    if (store.isNotEmpty) {
      // Gana el match mas largo: "supermercado dia" antes que "dia".
      ExpenseCategory? mejor;
      var largo = 0;
      _merchantRules.forEach((category, keywords) {
        for (final k in keywords) {
          if (k.length > largo && _matches(store, k)) {
            largo = k.length;
            mejor = category;
          }
        }
      });
      if (mejor != null) return mejor;
    }

    if (itemNames.isEmpty) return null;

    final texto = itemNames.map(normalize).join(' | ');
    final puntos = <ExpenseCategory, int>{};
    _itemRules.forEach((category, keywords) {
      for (final k in keywords) {
        if (_matches(texto, k)) {
          puntos[category] = (puntos[category] ?? 0) + 1;
        }
      }
    });
    if (puntos.isEmpty) return null;

    // Desempate por orden del enum: determinista.
    final ganador = puntos.entries.reduce((a, b) {
      if (b.value != a.value) return b.value > a.value ? b : a;
      return a.key.index <= b.key.index ? a : b;
    });
    return ganador.key;
  }
}
