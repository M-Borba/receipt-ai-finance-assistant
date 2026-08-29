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
    while (true) {
      final snap = await _firestore
          .collection(coleccion)
          .where('userId', isEqualTo: userId)
          .limit(_batchSize)
          .get();

      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Si vino menos que el maximo, no queda nada mas.
      if (snap.docs.length < _batchSize) return;
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
