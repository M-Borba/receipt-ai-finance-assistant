import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logger/logger.dart';

import '../../features/expenses/domain/entities/expense_entity.dart';
import 'merchant_classifier.dart';

/// Recuerda con qué categoría clasificaste cada comercio.
///
/// El clasificador por reglas solo conoce cadenas conocidas. Tu carnicería del
/// barrio no está ni va a estar en esa lista, pero si la clasificás una vez, no
/// tiene sentido volver a preguntarte. Esto le gana a cualquier lista fija y a
/// cualquier modelo: nadie sabe mejor que vos en qué gastás.
///
/// **Un solo documento** en `users/{uid}/preferences/merchants`, con un mapa de
/// comercio normalizado a categoría. Un documento y no una colección porque se
/// lee entero en cada escaneo: así cuesta **una** lectura, no una por comercio,
/// y Firestore lo sirve de su caché local cuando no cambió.
///
/// Va en Firestore y no en el disco del navegador porque la app se usa en el
/// celular y en la computadora: lo que corregís en uno tiene que valer en el
/// otro. Y el almacenamiento local del navegador se borra solo.
class MerchantMemory {
  MerchantMemory({
    required FirebaseFirestore firestore,
    required String userId,
  })  : _firestore = firestore,
        _userId = userId;

  final FirebaseFirestore _firestore;
  final String _userId;
  final _log = Logger();

  /// Tope de comercios recordados. Con 500 entradas el documento pesa unos
  /// 20 KB, muy lejos del limite de 1 MiB de Firestore. Existe para que no
  /// crezca sin freno, no porque alguien vaya a acercarse.
  static const maxComercios = 500;

  Map<String, ExpenseCategory>? _cache;

  DocumentReference<Map<String, dynamic>> get _doc => _firestore
      .collection('users')
      .doc(_userId)
      .collection('preferences')
      .doc('merchants');

  /// La categoría que elegiste para este comercio, o null si es nuevo.
  ///
  /// Nunca lanza: que la memoria falle no puede romper un escaneo. En el peor
  /// caso se cae a las reglas de siempre.
  Future<ExpenseCategory?> categoryFor(String? storeName) async {
    final clave = _clave(storeName);
    if (clave == null) return null;
    final mapa = await _cargar();
    return mapa[clave];
  }

  /// Guarda tu elección para este comercio.
  ///
  /// Se llama en cada guardado, no solo cuando corregís: reforzar lo que ya
  /// estaba es gratis, y si cambiaste de opinión gana lo último.
  Future<void> remember(String? storeName, ExpenseCategory category) async {
    final clave = _clave(storeName);
    if (clave == null) return;

    // `other` no se aprende: significa "no sé", y recordarlo congelaría el
    // comercio en esa respuesta para siempre, tapando las reglas.
    if (category == ExpenseCategory.other) return;

    try {
      final mapa = await _cargar();
      if (mapa[clave] == category) return;
      if (mapa.length >= maxComercios && !mapa.containsKey(clave)) return;

      mapa[clave] = category;
      _cache = mapa;
      // merge: no pisa lo que haya escrito otro dispositivo mientras tanto.
      await _doc.set({clave: category.name}, SetOptions(merge: true));
    } catch (e) {
      _log.w('No se pudo recordar la categoria de "$storeName"', error: e);
    }
  }

  /// Olvida un comercio, para cuando lo clasificaste mal a propósito o no.
  Future<void> forget(String? storeName) async {
    final clave = _clave(storeName);
    if (clave == null) return;
    try {
      _cache?.remove(clave);
      await _doc.update({clave: FieldValue.delete()});
    } catch (e) {
      _log.w('No se pudo olvidar "$storeName"', error: e);
    }
  }

  /// Todo lo recordado, para poder mostrarlo y editarlo en Ajustes.
  Future<Map<String, ExpenseCategory>> all() async =>
      Map.unmodifiable(await _cargar());

  Future<Map<String, ExpenseCategory>> _cargar() async {
    if (_cache != null) return _cache!;
    try {
      final snap = await _doc.get();
      final data = snap.data() ?? const <String, dynamic>{};
      _cache = {
        for (final e in data.entries)
          if (e.value is String)
            e.key: ExpenseCategory.fromString(e.value as String),
      };
    } catch (e) {
      _log.w('No se pudo leer la memoria de comercios', error: e);
      // Vacio y NO cacheado: asi el proximo intento vuelve a probar en vez de
      // quedarse sin memoria por el resto de la sesion.
      return <String, ExpenseCategory>{};
    }
    return _cache!;
  }

  /// La clave usa la misma normalización que el clasificador, así "TIENDA
  /// INGLESA", "Tienda Inglesa" y "tienda-inglesa" son el mismo comercio.
  ///
  /// Nombres de una o dos letras se descartan: no identifican nada y ensucian.
  @visibleForTesting
  static String? claveDe(String? storeName) => _clave(storeName);

  static String? _clave(String? storeName) {
    if (storeName == null) return null;
    final n = MerchantClassifier.normalize(storeName);
    if (n.length < 3) return null;
    // Firestore no acepta puntos ni barras en el nombre de un campo.
    return n.replaceAll(RegExp(r'[.~*/\[\]]'), ' ').trim();
  }
}
