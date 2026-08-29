import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import '../models/expense_model.dart';

part 'expense_repository_impl.g.dart';

@riverpod
ExpenseRepository expenseRepository(Ref ref) {
  return ExpenseRepositoryImpl(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
}

class ExpenseRepositoryImpl implements ExpenseRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _log = Logger();

  ExpenseRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _auth = auth;

  String get _userId {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AuthException('No authenticated user');
    return uid;
  }

  CollectionReference get _col =>
      _firestore.collection(AppConstants.expensesCollection);

  @override
  Stream<List<ExpenseEntity>> watchExpenses({int windowMonths = 12}) {
    final now = DateTime.now();
    final windowStart = DateTime(now.year, now.month - windowMonths + 1);

    return _col
        .where('userId', isEqualTo: _userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
        .orderBy('date', descending: true)
        .limit(AppConstants.expensesWindowSize)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList());
  }

  @override
  Future<Either<Failure, ExpenseEntity>> addManualExpense({
    required int amountCents,
    required ExpenseCategory category,
    required DateTime date,
    String? storeName,
    String? note,
  }) async {
    try {
      if (amountCents <= 0) {
        return const Left(ValidationFailure('El monto tiene que ser mayor a 0'));
      }

      final store = storeName?.trim();
      final expense = ExpenseModel(
        id: '',
        userId: _userId,
        category: category,
        amountCents: amountCents,
        storeName: (store == null || store.isEmpty) ? null : store,
        note: (note == null || note.trim().isEmpty) ? null : note.trim(),
        // Se guarda a mediodia para que un cambio de zona horaria no corra el
        // gasto al mes anterior o al siguiente.
        date: DateTime(date.year, date.month, date.day, 12),
        createdAt: DateTime.now(),
      );

      final ref = await _col.add(expense.toFirestore());
      final saved = ExpenseModel(
        id: ref.id,
        userId: expense.userId,
        category: expense.category,
        amountCents: expense.amountCents,
        storeName: expense.storeName,
        note: expense.note,
        date: expense.date,
        createdAt: expense.createdAt,
      );
      return Right(saved);
    } catch (e) {
      _log.e('Failed to add manual expense', error: e);
      return Left(NetworkFailure('No se pudo guardar el gasto: $e'));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpense(
      ExpenseEntity expense) async {
    try {
      if (expense.amountCents <= 0) {
        return const Left(ValidationFailure('El monto tiene que ser mayor a 0'));
      }
      await _col.doc(expense.id).update({
        'category': expense.category.name,
        'amountCents': expense.amountCents,
        'storeName': expense.storeName,
        'note': expense.note,
        'date': Timestamp.fromDate(expense.date),
      });
      return Right(expense);
    } catch (e) {
      return Left(NetworkFailure('No se pudo actualizar el gasto: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteExpense(String id) async {
    try {
      await _col.doc(id).delete();
      return const Right(null);
    } catch (e) {
      return Left(NetworkFailure('No se pudo borrar el gasto: $e'));
    }
  }

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getAllExpenses() async {
    try {
      final snap = await _col
          .where('userId', isEqualTo: _userId)
          .orderBy('date', descending: true)
          .get();
      return Right(
        snap.docs.map((d) => ExpenseModel.fromFirestore(d)).toList(),
      );
    } catch (e) {
      return Left(NetworkFailure('No se pudieron leer los gastos: $e'));
    }
  }
}
