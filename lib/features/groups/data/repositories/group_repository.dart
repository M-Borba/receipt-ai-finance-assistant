import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/write_timeout.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/group_expense_entity.dart';
import '../../domain/split.dart';
import '../models/group_expense_model.dart';
import '../models/group_model.dart';

part 'group_repository.g.dart';

@riverpod
GroupRepository groupRepository(Ref ref) => GroupRepository(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
    );

/// Grupos de gastos compartidos.
///
/// A diferencia del resto de la app, estos documentos **no tienen un dueño**:
/// se autorizan por pertenencia (`uid in memberIds`), no por `userId`. Es la
/// decision de seguridad mas importante del feature.
class GroupRepository {
  GroupRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _log = Logger();
  final _uuid = const Uuid();

  User get _user {
    final u = _auth.currentUser;
    if (u == null) throw const AuthException('No authenticated user');
    return u;
  }

  CollectionReference get _groups => _firestore.collection('groups');

  CollectionReference _expenses(String groupId) =>
      _groups.doc(groupId).collection('expenses');

  /// Los grupos donde participo. Filtrar por `memberIds` es lo que hace que la
  /// regla de lectura pueda aprobar la consulta: una query sin este filtro es
  /// rechazada entera, no filtrada.
  Stream<List<GroupEntity>> watchGroups() {
    return _groups
        .where('memberIds', arrayContains: _user.uid)
        .snapshots()
        .map((s) => s.docs.map(GroupModel.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<GroupEntity?> watchGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map(
        (d) => d.exists ? GroupModel.fromFirestore(d) : null);
  }

  Stream<List<GroupExpenseEntity>> watchExpenses(String groupId) {
    // Sin filtro: la regla de lectura autoriza mirando el grupo padre, no una
    // copia dentro del gasto, asi que no depende de `resource` y Firestore la
    // evalua una vez para toda la consulta.
    return _expenses(groupId)
        .snapshots()
        .map((s) => s.docs
            .map((d) => GroupExpenseModel.fromFirestore(d, groupId))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  Future<Either<Failure, GroupEntity>> createGroup({
    required String name,
    required String currency,
  }) async {
    try {
      final u = _user;
      final id = _uuid.v4();
      final yo = GroupMember(
        uid: u.uid,
        displayName: u.displayName ?? u.email ?? 'Yo',
        photoUrl: u.photoURL,
        joinedAt: DateTime.now(),
      );
      final grupo = GroupModel(
        id: id,
        name: name.trim(),
        currency: currency,
        createdBy: u.uid,
        memberIds: [u.uid],
        members: {u.uid: yo},
        createdAt: DateTime.now(),
      );
      await _groups.doc(id).set(grupo.toFirestore()).timeout(escrituraTimeout);
      return Right(grupo);
    } on TimeoutException {
      return Left(timeoutAlGuardar('el grupo'));
    } catch (e, st) {
      _log.e('createGroup fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Agrega un gasto al grupo.
  ///
  /// El reparto se calcula aca y se guarda **ya resuelto**. Se valida que
  /// cierre antes de escribir: un gasto donde lo pagado o lo repartido no suma
  /// el total deja al grupo sin poder llegar nunca a cero.
  Future<Either<Failure, GroupExpenseEntity>> addExpense({
    required GroupEntity group,
    required String description,
    required int amountCents,
    required DateTime date,
    required SplitMode mode,
    required List<String> participants,
    required Map<String, int> paidBy,
    Map<String, int> splitInputs = const {},
    String? receiptId,
  }) async {
    try {
      if (amountCents <= 0) {
        return const Left(ValidationFailure('El monto tiene que ser mayor a cero'));
      }
      final pagado = paidBy.values.fold<int>(0, (a, b) => a + b);
      if (pagado != amountCents) {
        return const Left(ValidationFailure(
            'Lo pagado no coincide con el monto del gasto'));
      }
      if (participants.any((p) => !group.memberIds.contains(p)) ||
          paidBy.keys.any((p) => !group.memberIds.contains(p))) {
        return const Left(
            ValidationFailure('Hay alguien que no es del grupo'));
      }

      final Shares shares;
      try {
        shares = computeShares(
          totalCents: amountCents,
          participants: participants,
          mode: mode,
          inputs: splitInputs,
        );
      } on ArgumentError catch (e) {
        return Left(ValidationFailure(e.message.toString()));
      }

      final id = _uuid.v4();
      final gasto = GroupExpenseModel(
        id: id,
        groupId: group.id,
        description: description.trim(),
        amountCents: amountCents,
        date: date,
        mode: mode,
        paidBy: paidBy,
        shares: shares,
        createdBy: _user.uid,
        createdAt: DateTime.now(),
        receiptId: receiptId,
      );

      // Cinturon y tirantes: si esto falla hay un bug en el reparto, y es
      // mejor no escribirlo que arrastrarlo en el libro para siempre.
      if (!gasto.isBalanced) {
        _log.e('Reparto descuadrado: ${gasto.paidBy} / ${gasto.shares}');
        return const Left(ValidationFailure('El reparto no cierra'));
      }

      await _expenses(group.id)
          .doc(id)
          .set(gasto.toFirestore())
          .timeout(escrituraTimeout);
      return Right(gasto);
    } on TimeoutException {
      return Left(timeoutAlGuardar('el gasto'));
    } catch (e, st) {
      _log.e('addExpense fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  Future<Either<Failure, Unit>> deleteExpense(
      String groupId, String expenseId) async {
    try {
      await _expenses(groupId)
          .doc(expenseId)
          .delete()
          .timeout(escrituraTimeout);
      return const Right(unit);
    } on TimeoutException {
      return Left(timeoutAlGuardar('el borrado'));
    } catch (e, st) {
      _log.e('deleteExpense fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Cuanto vive un link de invitacion.
  ///
  /// El token ES la credencial: quien lo tiene entra al grupo. Un link que no
  /// vence es una llave que queda dando vueltas en un chat para siempre.
  static const invitacionDura = Duration(days: 7);

  CollectionReference get _invites => _firestore.collection('invites');

  /// De donde cuelga el link de invitacion.
  ///
  /// En web sale de la URL actual, asi que en desarrollo apunta a localhost y
  /// en produccion al dominio real sin configurar nada.
  String get _baseUrl =>
      kIsWeb ? Uri.base.origin : 'https://mborba-proyect.web.app';

  /// Crea un link para invitar a alguien a [group].
  ///
  /// Devuelve la URL lista para compartir.
  Future<Either<Failure, String>> createInvite(GroupEntity group) async {
    try {
      final token = _uuid.v4();
      await _invites.doc(token).set({
        'groupId': group.id,
        // El nombre viaja en el invite porque quien todavia no es miembro NO
        // puede leer el grupo: sin esto la pantalla de invitacion no podria
        // decir a que grupo lo estan invitando.
        'groupName': group.name,
        'createdBy': _user.uid,
        'createdAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(invitacionDura)),
      }).timeout(escrituraTimeout);
      return Right('$_baseUrl/join/$token');
    } on TimeoutException {
      // Sin el documento escrito el link no sirve para nadie, asi que no se
      // devuelve una URL que todavia no funciona.
      return Left(timeoutAlGuardar('la invitación'));
    } catch (e, st) {
      _log.e('createInvite fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Lo que se puede saber de una invitacion SIN haberla aceptado todavia.
  Future<Either<Failure, ({String groupId, String groupName})>> peekInvite(
      String token) async {
    try {
      final doc = await _invites.doc(token).get();
      if (!doc.exists) {
        return const Left(ValidationFailure('Este link no existe o ya se usó'));
      }
      final data = doc.data()! as Map<String, dynamic>;
      final vence = (data['expiresAt'] as Timestamp?)?.toDate();
      if (vence == null || vence.isBefore(DateTime.now())) {
        return const Left(ValidationFailure(
            'Este link venció. Pedile a quien te invitó que te mande uno nuevo.'));
      }
      return Right((
        groupId: data['groupId'] as String? ?? '',
        groupName: data['groupName'] as String? ?? 'un grupo',
      ));
    } catch (e, st) {
      _log.e('peekInvite fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Se suma al grupo usando el token del link.
  ///
  /// No se lee el grupo antes: quien todavia no es miembro no puede leerlo. Se
  /// escribe a ciegas y **son las reglas las que deciden**, que es justo lo que
  /// hay que verificar antes de mandarle un link a alguien.
  Future<Either<Failure, String>> joinWithToken(String token) async {
    try {
      final vistazo = await peekInvite(token);
      final inv = vistazo.fold((f) => null, (v) => v);
      if (inv == null) {
        return Left(vistazo.swap().getOrElse(
            () => const ValidationFailure('Link inválido')));
      }

      final u = _user;
      await _groups.doc(inv.groupId).update({
        'memberIds': FieldValue.arrayUnion([u.uid]),
        'members.${u.uid}': {
          'displayName': u.displayName ?? u.email ?? 'Alguien',
          'photoUrl': u.photoURL,
          'joinedAt': Timestamp.now(),
        },
        // La regla necesita el token para validarlo, y la unica forma de
        // hacerselo llegar es dentro del documento que se escribe.
        'inviteToken': token,
      }).timeout(escrituraTimeout);
      return Right(inv.groupId);
    } on TimeoutException {
      return Left(timeoutAlGuardar('la entrada al grupo'));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const Left(ValidationFailure(
            'No se pudo entrar al grupo. El link puede haber vencido.'));
      }
      return Left(ServerFailure(message: e.message ?? e.code));
    } catch (e, st) {
      _log.e('joinWithToken fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }

  Future<Either<Failure, Unit>> renameGroup(String groupId, String name) async {
    try {
      await _groups
          .doc(groupId)
          .update({'name': name.trim()})
          .timeout(escrituraTimeout);
      return const Right(unit);
    } on TimeoutException {
      return Left(timeoutAlGuardar('el nombre'));
    } catch (e, st) {
      _log.e('renameGroup fallo', error: e, stackTrace: st);
      return Left(ServerFailure(message: e.toString()));
    }
  }
}
