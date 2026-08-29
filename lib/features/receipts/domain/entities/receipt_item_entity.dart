import 'package:equatable/equatable.dart';

class ReceiptItemEntity extends Equatable {
  final String id;
  final String name;
  final double quantity;
  /// En centavos. La cantidad si es double: 1,5 kg es valido.
  final int unitPriceCents;
  final int totalPriceCents;

  const ReceiptItemEntity({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalPriceCents,
  });

  @override
  List<Object?> get props => [id, name, quantity, unitPriceCents, totalPriceCents];
}
