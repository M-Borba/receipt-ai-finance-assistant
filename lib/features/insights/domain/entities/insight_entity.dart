import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum InsightType { pattern, saving, behavior, warning }

class InsightEntity extends Equatable {
  final String id;
  final String userId;
  final DateTime month;
  final String title;
  final String description;
  final InsightType type;
  final String icon;
  final DateTime createdAt;

  const InsightEntity({
    required this.id,
    required this.userId,
    required this.month,
    required this.title,
    required this.description,
    required this.type,
    required this.icon,
    required this.createdAt,
  });

  factory InsightEntity.fromAiResponse(
    Map<String, dynamic> json,
    String userId,
    DateTime month,
  ) {
    final typeStr = (json['type'] as String? ?? 'pattern').toLowerCase();
    final type = InsightType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => InsightType.pattern,
    );

    return InsightEntity(
      id: const Uuid().v4(),
      userId: userId,
      month: month,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: type,
      icon: json['icon'] as String? ?? '💡',
      createdAt: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, userId, month, type];
}
