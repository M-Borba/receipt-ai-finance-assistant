import 'package:equatable/equatable.dart';

import '../split.dart';

/// Un gasto compartido.
///
/// [shares] se guarda **ya resuelto en centavos**, no el modo con sus
/// parametros: asi el historico no se mueve si manana cambia el algoritmo de
/// reparto. [mode] queda solo para poder reabrir el gasto en el mismo modo.
///
/// [paidBy] es un mapa y no un uid suelto porque en la vida real pagan varios:
/// "puse yo la mitad y Ana la otra mitad".
class GroupExpenseEntity extends Equatable {
  const GroupExpenseEntity({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amountCents,
    required this.date,
    required this.mode,
    required this.paidBy,
    required this.shares,
    required this.memberIds,
    required this.createdBy,
    required this.createdAt,
    this.receiptId,
  });

  final String id;
  final String groupId;
  final String description;
  final int amountCents;
  final DateTime date;
  final SplitMode mode;

  /// Quien puso la plata, y cuanto. Suma [amountCents].
  final Map<String, int> paidBy;

  /// A quien le corresponde, y cuanto. Suma [amountCents].
  final Map<String, int> shares;

  /// Copia para las reglas de Firestore.
  final List<String> memberIds;

  final String createdBy;
  final DateTime createdAt;

  /// Enlace al ticket escaneado, si el gasto salio de uno.
  final String? receiptId;

  /// Lo que esta persona puso de mas (positivo) o de menos (negativo) en
  /// **este** gasto.
  int netFor(String uid) => (paidBy[uid] ?? 0) - (shares[uid] ?? 0);

  /// Un gasto esta bien formado si lo pagado y lo repartido suman el total.
  /// Si esto no se cumple, los balances del grupo no cierran nunca en cero.
  bool get isBalanced =>
      paidBy.values.fold<int>(0, (a, b) => a + b) == amountCents &&
      shares.values.fold<int>(0, (a, b) => a + b) == amountCents;

  @override
  List<Object?> get props => [
        id, groupId, description, amountCents, date, mode,
        paidBy, shares, memberIds, createdBy, createdAt, receiptId,
      ];
}
