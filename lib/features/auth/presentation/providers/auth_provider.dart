import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/entities/user_entity.dart';

part 'auth_provider.g.dart';

@riverpod
Stream<User?> authState(Ref ref) {
  return FirebaseAuth.instance.authStateChanges();
}

@riverpod
UserEntity? currentUser(Ref ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  return UserEntity(
    id: user.uid,
    email: user.email ?? '',
    displayName: user.displayName,
    photoUrl: user.photoURL,
    createdAt: user.metadata.creationTime ?? DateTime.now(),
  );
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => kIsWeb ? _signInWithGoogleWeb() : _signInWithGoogleNative(),
    );
    if (!ref.mounted) return;
    state = result;
  }

  /// En web, `GoogleSignIn().signIn()` esta deprecado justamente porque no
  /// devuelve un `idToken` confiable, y sin idToken la credencial de Firebase
  /// no se puede armar. El popup nativo de firebase_auth hace todo el flujo
  /// contra `<proyecto>.firebaseapp.com/__/auth/handler`, que Firebase ya tiene
  /// autorizado: no hay que registrar origenes en Google Cloud Console.
  Future<void> _signInWithGoogleWeb() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    await FirebaseAuth.instance.signInWithPopup(provider);
  }

  Future<void> _signInWithGoogleNative() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Sign in cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    });
    if (!ref.mounted) return;
    state = result;
  }

  Future<void> registerWithEmail(String email, String password, String name) async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
    });
    if (!ref.mounted) return;
    state = result;
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      // En web no hay sesion de google_sign_in que cerrar, y llamarlo tira.
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
    state = const AsyncValue.data(null);
  }
}
