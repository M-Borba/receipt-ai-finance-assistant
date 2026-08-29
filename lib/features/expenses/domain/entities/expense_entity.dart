import 'package:equatable/equatable.dart';

import '../../../../shared/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum ExpenseCategory {
  groceries,
  delivery,
  restaurants,
  transportation,
  fuel,
  utilities,
  rent,
  subscriptions,
  health,
  education,
  entertainment,
  shopping,
  pets,
  other;

  static ExpenseCategory fromString(String value) {
    final v = value.toLowerCase().trim();
    return ExpenseCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == v,
      orElse: () => ExpenseCategory.other,
    );
  }

  /// Las que se ofrecen al usuario, con `other` al final.
  static List<ExpenseCategory> get selectable => ExpenseCategory.values;

  String get label {
    return switch (this) {
      groceries => 'Supermercado',
      delivery => 'Delivery',
      restaurants => 'Restaurantes',
      transportation => 'Transporte',
      fuel => 'Combustible',
      utilities => 'Servicios',
      rent => 'Alquiler',
      subscriptions => 'Suscripciones',
      health => 'Salud',
      education => 'Educación',
      entertainment => 'Entretenimiento',
      shopping => 'Compras',
      pets => 'Mascotas',
      other => 'Otros',
    };
  }

  String get emoji {
    return switch (this) {
      groceries => '🛒',
      delivery => '🚚',
      restaurants => '🍽️',
      transportation => '🚌',
      fuel => '⛽',
      utilities => '💡',
      rent => '🏠',
      subscriptions => '📱',
      health => '💊',
      education => '📚',
      entertainment => '🎬',
      shopping => '🛍️',
      pets => '🐾',
      other => '📦',
    };
  }

  Color get color {
    return switch (this) {
      groceries => AppColors.categoryGroceries,
      delivery => AppColors.categoryDelivery,
      restaurants => AppColors.categoryRestaurants,
      transportation => AppColors.categoryTransportation,
      fuel => AppColors.categoryFuel,
      utilities => AppColors.categoryUtilities,
      rent => AppColors.categoryRent,
      subscriptions => AppColors.categorySubscriptions,
      health => AppColors.categoryHealth,
      education => AppColors.categoryEducation,
      entertainment => AppColors.categoryEntertainment,
      shopping => AppColors.categoryShopping,
      pets => AppColors.categoryPets,
      other => AppColors.categoryOther,
    };
  }
}

class ExpenseEntity extends Equatable {
  final String id;
  final String userId;

  /// Null cuando el gasto se cargo a mano, sin escanear un ticket.
  final String? receiptId;
  final ExpenseCategory category;
  /// En centavos. Ver [Money] para por que no es double.
  final int amountCents;
  final String? storeName;

  /// Nota libre del usuario. Solo tiene sentido en gastos manuales.
  final String? note;
  final DateTime date;
  final DateTime createdAt;

  const ExpenseEntity({
    required this.id,
    required this.userId,
    this.receiptId,
    required this.category,
    required this.amountCents,
    this.storeName,
    this.note,
    required this.date,
    required this.createdAt,
  });

  /// Cargado a mano: no hay recibo del que venga, asi que tampoco hay imagen
  /// ni items que mostrar.
  bool get isManual => receiptId == null;

  ExpenseEntity copyWith({
    ExpenseCategory? category,
    int? amountCents,
    String? storeName,
    String? note,
    DateTime? date,
  }) {
    return ExpenseEntity(
      id: id,
      userId: userId,
      receiptId: receiptId,
      category: category ?? this.category,
      amountCents: amountCents ?? this.amountCents,
      storeName: storeName ?? this.storeName,
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, userId, receiptId, amountCents, category, storeName, note, date];
}
