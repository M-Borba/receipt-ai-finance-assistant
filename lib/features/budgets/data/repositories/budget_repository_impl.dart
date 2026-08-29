import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../models/budget_model.dart';

part 'budget_repository_impl.g.dart';

@riverpod
BudgetRepository budgetRepository(Ref ref) {
  return BudgetRepositoryImpl(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
}

class BudgetRepositoryImpl implements BudgetRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _log = Logger();

  BudgetRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  String get _userId {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthException('No authenticated user');
    return uid;
  }

  CollectionReference get _col => _firestore.collection('budgets');

  String _docId(ExpenseCategory category) => '${_userId}_${category.name}';

  @override
  Stream<List<BudgetEntity>> watchBudgets() {
    return _col
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((s) => s.docs.map((d) => BudgetModel.fromFirestore(d)).toList());
  }

  @override
  Future<Either<Failure, BudgetEntity>> setBudget({
    required ExpenseCategory category,
    required int limitCents,
  }) async {
    try {
      if (limitCents <= 0) {
        return const Left(ValidationFailure('El tope tiene que ser mayor a 0'));
      }

      // Un tope por categoria y por usuario: el id es determinista, asi que
      // guardar dos veces la misma categoria actualiza en vez de duplicar.
      final id = _docId(category);
      final budget = BudgetModel(
        id: id,
        userId: _userId,
        category: category,
        limitCents: limitCents,
      );
      await _col.doc(id).set(budget.toFirestore());
      return Right(budget);
    } catch (e) {
      _log.e('Failed to set budget', error: e);
      return Left(NetworkFailure('No se pudo guardar el presupuesto: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> removeBudget(ExpenseCategory category) async {
    try {
      await _col.doc(_docId(category)).delete();
      return const Right(null);
    } catch (e) {
      return Left(NetworkFailure('No se pudo borrar el presupuesto: $e'));
    }
  }
}
