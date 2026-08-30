import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/errors/failures.dart';

part 'account_service.g.dart';

@riverpod
AccountService accountService(Ref ref) => AccountService(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
    );

/// Borrado de cuenta y de todos sus datos.
///
/// Es requisito de App Store y Play, pero sobre todo es lo que hace que
/// alguien confie en meter sus gastos aca: tiene que poder irse entero.
class AccountService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _log = Logger();

  AccountService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  static const _colecciones = [
    AppConstants.receiptsCollection,
    AppConstants.expensesCollection,
    AppConstants.insightsCollection,
    'budgets',
  ];

  /// Subcolecciones que cuelgan de un documento de [_colecciones].
  ///
  /// Firestore **no borra las subcolecciones al borrar el documento padre**.
  /// Sin esto, la foto de cada ticket quedaba en `receipts/{id}/media/thumb`
  /// para siempre: al borrarse la cuenta se pierde el uid, y las reglas piden
  /// `userId == request.auth.uid`, asi que nadie podia volver a leerlas ni
  /// borrarlas. Ademas de ocupar la cuota, incumple el derecho de supresion.
  static const _subcolecciones = <String, List<String>>{
    AppConstants.receiptsCollection: ['media'],
  };

  /// Firestore limita cada batch a 500 escrituras.
  static const _batchSize = 400;

  /// Borra los datos primero y la cuenta al final.
  ///
  /// Ese orden importa: al borrar la cuenta se pierde el `uid`, y sin `uid` las
  /// reglas ya no dejan tocar los documentos, que quedarian huerfanos para
  /// siempre y sin nadie que pueda leerlos ni borrarlos.
  Future<Either<Failure, void>> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return const Left(AuthFailure('No hay sesión activa'));

    try {
      for (final coleccion in _colecciones) {
        await _borrarColeccion(coleccion, user.uid);
      }
      await _borrarGrupos(user.uid);
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .delete()
          .catchError((_) {});

      await user.delete();

      if (!kIsWeb) {
        try {
          await GoogleSignIn().signOut();
        } catch (_) {}
      }
      return const Right(null);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Firebase exige sesion fresca para una operacion destructiva.
        return const Left(AuthFailure(
          'Por seguridad, volvé a iniciar sesión y probá de nuevo.',
        ));
      }
      return Left(AuthFailure(e.message ?? 'No se pudo borrar la cuenta'));
    } catch (e) {
      _log.e('Account deletion failed', error: e);
      return Left(UnexpectedFailure('No se pudo borrar la cuenta: $e'));
    }
  }

  Future<void> _borrarColeccion(String coleccion, String userId) async {
    final subs = _subcolecciones[coleccion] ?? const <String>[];

    while (true) {
      final snap = await _firestore
          .collection(coleccion)
          .where('userId', isEqualTo: userId)
          .limit(_batchSize)
          .get();

      if (snap.docs.isEmpty) return;

      // Se cuentan las escrituras en vez de contar documentos: cada ticket
      // borra ademas su subcoleccion, asi que 400 tickets podian ser 800
      // escrituras y el limite de Firestore son 500 por batch.
      var batch = _firestore.batch();
      var escrituras = 0;

      Future<void> anotar(DocumentReference ref) async {
        if (escrituras >= _batchSize) {
          await batch.commit();
          batch = _firestore.batch();
          escrituras = 0;
        }
        batch.delete(ref);
        escrituras++;
      }

      for (final doc in snap.docs) {
        // Las subcolecciones primero: despues de borrar el padre siguen
        // existiendo igual, pero ya no hay forma de llegar a ellas.
        for (final sub in subs) {
          final hijos = await doc.reference.collection(sub).get();
          for (final hijo in hijos.docs) {
            await anotar(hijo.reference);
          }
        }
        await anotar(doc.reference);
      }
      if (escrituras > 0) await batch.commit();

      // Si vino menos que el maximo, no queda nada mas.
      if (snap.docs.length < _batchSize) return;
    }
  }

  /// Borra los grupos donde la persona es la unica integrante, con sus gastos.
  ///
  /// Los grupos compartidos NO se borran: son datos de otras personas tambien,
  /// y borrarlos destruiria el historial de gente que no pidio nada. Ahi solo
  /// corresponde sacar a quien se va de `memberIds`, y eso llega junto con las
  /// invitaciones, que es cuando un grupo puede tener a alguien mas.
  Future<void> _borrarGrupos(String userId) async {
    final snap = await _firestore
        .collection('groups')
        .where('memberIds', arrayContains: userId)
        .get();

    for (final grupo in snap.docs) {
      final data = grupo.data();
      final miembros = (data['memberIds'] as List?)?.cast<String>() ?? const [];
      if (miembros.length > 1) continue;

      final gastos = await grupo.reference.collection('expenses').get();
      // Un grupo puede tener muchos gastos: se corta en tandas para no pasar
      // el limite de 500 escrituras por batch.
      for (var i = 0; i < gastos.docs.length; i += _batchSize) {
        final tanda = gastos.docs.skip(i).take(_batchSize);
        final batch = _firestore.batch();
        for (final g in tanda) {
          batch.delete(g.reference);
        }
        await batch.commit();
      }
      await grupo.reference.delete();
    }
  }

  /// Reautentica con Google para poder borrar cuando Firebase pide sesion
  /// fresca.
  Future<Either<Failure, void>> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) return const Left(AuthFailure('No hay sesión activa'));

    try {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(GoogleAuthProvider());
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          return const Left(AuthFailure('Cancelado'));
        }
        final googleAuth = await googleUser.authentication;
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message));
    } catch (e) {
      return Left(AuthFailure('No se pudo reautenticar: $e'));
    }
  }
}
