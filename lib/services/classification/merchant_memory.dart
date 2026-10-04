import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/expenses/domain/entities/expense_entity.dart';
import 'merchant_classifier.dart';

part 'merchant_memory.g.dart';

/// Una sola instancia para toda la app: cachea el mapa de comercios, y una
/// nueva en cada acceso releeria Firestore en cada escaneo. La comparten el
/// escaneo de tickets y la carga manual, asi lo que se aprende en una vale en
/// la otra.
@Riverpod(keepAlive: true)
MerchantMemory merchantMemory(Ref ref) => MerchantMemory(
      firestore: FirebaseFirestore.instance,
      uid: () => FirebaseAuth.instance.currentUser?.uid,
    );

/// Recuerda con qué categoría clasificaste cada comercio.
///
/// El clasificador por reglas solo conoce cadenas conocidas. Tu carnicería del
/// barrio no está ni va a estar en esa lista, pero si la clasificás una vez, no
/// tiene sentido volver a preguntarte. Esto le gana a cualquier lista fija y a
/// cualquier modelo: nadie sabe mejor que vos en qué gastás.
///
/// **Un solo documento** en `users/{uid}/preferences/merchants`. Un documento y
/// no una colección porque se lee entero en cada escaneo: así cuesta **una**
/// lectura, no una por comercio, y Firestore lo sirve de su caché local cuando
/// no cambió. Lo que hay adentro y cómo se consulta está en [MemoriaComercios].
///
/// Va en Firestore y no en el disco del navegador porque la app se usa en el
/// celular y en la computadora: lo que corregís en uno tiene que valer en el
/// otro. Y el almacenamiento local del navegador se borra solo.
class MerchantMemory {
  MerchantMemory({
    required FirebaseFirestore firestore,
    required String? Function() uid,
  })  : _firestore = firestore,
        _uid = uid;

  final FirebaseFirestore _firestore;

  /// Se pregunta en cada uso y no se fija al construir: la instancia vive lo
  /// que la app, y en ese tiempo se puede cerrar sesión y entrar con otra
  /// cuenta. La caché se tira cuando cambia, para no mezclar dos memorias.
  final String? Function() _uid;
  final _log = Logger();

  MemoriaComercios? _cache;
  String? _cacheUid;

  /// La lectura en curso. Sin esto, escribir el nombre de un comercio letra
  /// por letra disparaba una lectura por tecla hasta que llegaba la primera.
  Future<MemoriaComercios?>? _cargando;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('preferences')
      .doc('merchants');

  /// La categoría que elegiste para este comercio, o null si es nuevo.
  ///
  /// Nunca lanza: que la memoria falle no puede romper un escaneo. En el peor
  /// caso se cae a las reglas de siempre.
  Future<ExpenseCategory?> categoryFor({String? rut, String? storeName}) async {
    final memoria = await _cargar();
    return memoria?.categoriaPara(rut: rut, nombre: storeName);
  }

  /// Guarda tu elección para este comercio, bajo su RUT y bajo cada nombre.
  ///
  /// Se llama en cada guardado, no solo cuando corregís: reforzar lo que ya
  /// estaba es gratis, y si cambiaste de opinión gana lo último.
  Future<void> remember({
    String? rut,
    Iterable<String?> nombres = const [],
    required ExpenseCategory category,
  }) async {
    final uid = _uid();
    if (uid == null) return;
    try {
      // Si la lectura falló se escribe igual: el merge no pisa lo que ya
      // había, solo se pierde el chequeo de "ya estaba así".
      final memoria = await _cargar() ?? MemoriaComercios();
      final cambios =
          memoria.aprender(rut: rut, nombres: nombres, categoria: category);
      if (cambios.isEmpty) return;
      // merge: no pisa lo que haya escrito otro dispositivo mientras tanto. Y
      // con merge los mapas anidados se combinan, así que agregar un RUT no
      // borra los demás.
      await _doc(uid).set(cambios, SetOptions(merge: true));
    } catch (e) {
      _log.w('No se pudo recordar la categoria de "${nombres.join(' / ')}"',
          error: e);
    }
  }

  /// Olvida un comercio, para cuando lo clasificaste mal a propósito o no.
  Future<void> forget(String? storeName) async {
    final uid = _uid();
    final clave = MemoriaComercios.claveNombre(storeName);
    if (uid == null || clave == null) return;
    try {
      if (_cacheUid == uid) _cache?.porNombre.remove(clave);
      await _doc(uid).update({clave: FieldValue.delete()});
    } catch (e) {
      _log.w('No se pudo olvidar "$storeName"', error: e);
    }
  }

  /// Todo lo recordado por nombre, para poder mostrarlo y editarlo en Ajustes.
  Future<Map<String, ExpenseCategory>> all() async =>
      Map.unmodifiable((await _cargar())?.porNombre ?? const {});

  Future<MemoriaComercios?> _cargar() {
    final uid = _uid();
    if (uid == null) return Future.value(null);
    if (_cacheUid != uid) {
      _cache = null;
      _cargando = null;
      _cacheUid = uid;
    }
    if (_cache != null) return Future.value(_cache);
    return _cargando ??= _leer(uid);
  }

  Future<MemoriaComercios?> _leer(String uid) async {
    try {
      final snap = await _doc(uid).get();
      final memoria = MemoriaComercios.desdeDocumento(snap.data() ?? const {});
      if (_cacheUid == uid) _cache = memoria;
      return memoria;
    } catch (e) {
      _log.w('No se pudo leer la memoria de comercios', error: e);
      // Null y NO cacheado: así el próximo intento vuelve a probar en vez de
      // quedarse sin memoria por el resto de la sesión.
      return null;
    } finally {
      if (_cacheUid == uid) _cargando = null;
    }
  }

  /// Ver [MemoriaComercios.claveNombre].
  @visibleForTesting
  static String? claveDe(String? storeName) =>
      MemoriaComercios.claveNombre(storeName);
}

/// Lo que hay en el documento y cómo se consulta, sin Firestore: separado para
/// poder testearlo sin emulador.
///
/// Dos índices en el mismo documento:
///
/// - **Por RUT**, dentro del campo [campoRut]. Es el que manda: el RUT del
///   e-Ticket es el mismo en cada compra, mientras que el nombre lo lee el OCR
///   y cambia de un escaneo a otro ("GUILLERNO" por "GUILLERMO").
/// - **Por nombre**, en campos sueltos, que es el formato de siempre. Cubre
///   los gastos manuales, los tickets sin RUT y lo guardado antes de que
///   existiera el otro índice.
class MemoriaComercios {
  MemoriaComercios({
    Map<String, ExpenseCategory>? porNombre,
    Map<String, ExpenseCategory>? porRut,
  })  : porNombre = porNombre ?? {},
        porRut = porRut ?? {};

  /// Lleva guión bajo a propósito: la normalización de nombres convierte `_`
  /// en espacio, así que ningún comercio puede caer en esta misma clave.
  static const campoRut = 'por_rut';

  /// Tope por índice. Con 500 entradas el documento pesa unos 20 KB, muy lejos
  /// del límite de 1 MiB de Firestore. Existe para que no crezca sin freno,
  /// no porque alguien vaya a acercarse.
  static const maxComercios = 500;

  final Map<String, ExpenseCategory> porNombre;
  final Map<String, ExpenseCategory> porRut;

  factory MemoriaComercios.desdeDocumento(Map<String, dynamic> data) {
    final ruts = data[campoRut];
    return MemoriaComercios(
      // El mapa de RUTs no es un String, así que este filtro ya lo saltea.
      porNombre: {
        for (final e in data.entries)
          if (e.value is String)
            e.key: ExpenseCategory.fromString(e.value as String),
      },
      porRut: {
        if (ruts is Map)
          for (final e in ruts.entries)
            if (e.key is String && e.value is String)
              e.key as String: ExpenseCategory.fromString(e.value as String),
      },
    );
  }

  /// Primero el RUT y después el nombre.
  ExpenseCategory? categoriaPara({String? rut, String? nombre}) {
    final r = claveRut(rut);
    final porRutRecordado = r == null ? null : porRut[r];
    if (porRutRecordado != null) return porRutRecordado;
    final n = claveNombre(nombre);
    return n == null ? null : porNombre[n];
  }

  /// Anota la elección y devuelve lo que hay que escribir en Firestore con
  /// merge, o un mapa vacío si no cambió nada.
  ///
  /// Recibe VARIOS nombres porque un ticket tiene dos: el que leyó el OCR y el
  /// que quedó después de que lo corregiste. El que se busca en el próximo
  /// escaneo es el del OCR, así que aprender solo el corregido no servía: si
  /// cambiabas "GUILLERNO PUJADAS SAS" por "Carnicería Pujadas", la memoria no
  /// lo encontraba nunca.
  Map<String, dynamic> aprender({
    String? rut,
    Iterable<String?> nombres = const [],
    required ExpenseCategory categoria,
  }) {
    // `other` no se aprende: significa "no sé", y recordarlo congelaría el
    // comercio en esa respuesta para siempre, tapando las reglas.
    if (categoria == ExpenseCategory.other) return const {};

    final cambios = <String, dynamic>{};
    for (final n in nombres.map(claveNombre).whereType<String>().toSet()) {
      if (_anotar(porNombre, n, categoria)) cambios[n] = categoria.name;
    }
    final r = claveRut(rut);
    if (r != null && _anotar(porRut, r, categoria)) {
      cambios[campoRut] = {r: categoria.name};
    }
    return cambios;
  }

  static bool _anotar(
    Map<String, ExpenseCategory> mapa,
    String clave,
    ExpenseCategory categoria,
  ) {
    if (mapa[clave] == categoria) return false;
    if (mapa.length >= maxComercios && !mapa.containsKey(clave)) return false;
    mapa[clave] = categoria;
    return true;
  }

  /// La clave usa la misma normalización que el clasificador, así "TIENDA
  /// INGLESA", "Tienda Inglesa" y "tienda-inglesa" son el mismo comercio.
  ///
  /// Nombres de una o dos letras se descartan: no identifican nada y ensucian.
  static String? claveNombre(String? storeName) {
    if (storeName == null) return null;
    final n = MerchantClassifier.normalize(storeName);
    if (n.length < 3) return null;
    // Firestore no acepta puntos ni barras en el nombre de un campo.
    return n.replaceAll(RegExp(r'[.~*/\[\]]'), ' ').trim();
  }

  /// Los 12 dígitos del RUT, sin puntos ni espacios, o null si no son 12.
  static String? claveRut(String? rut) {
    if (rut == null) return null;
    final digitos = rut.replaceAll(RegExp(r'\D'), '');
    return digitos.length == 12 ? digitos : null;
  }
}
