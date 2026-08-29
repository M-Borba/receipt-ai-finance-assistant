import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/group_entity.dart';

class GroupModel extends GroupEntity {
  const GroupModel({
    required super.id,
    required super.name,
    required super.currency,
    required super.createdBy,
    required super.memberIds,
    required super.members,
    required super.createdAt,
    super.archived,
  });

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? const {};
    final crudos = (data['members'] as Map<String, dynamic>?) ?? const {};

    final miembros = <String, GroupMember>{};
    crudos.forEach((uid, valor) {
      final m = (valor as Map<String, dynamic>?) ?? const {};
      miembros[uid] = GroupMember(
        uid: uid,
        displayName: m['displayName'] as String? ?? 'Alguien',
        photoUrl: m['photoUrl'] as String?,
        joinedAt: (m['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    });

    return GroupModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Grupo',
      currency: data['currency'] as String? ?? 'UYU',
      createdBy: data['createdBy'] as String? ?? '',
      memberIds: (data['memberIds'] as List?)?.cast<String>() ?? const [],
      members: miembros,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      archived: data['archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'currency': currency,
        'createdBy': createdBy,
        // Desnormalizado para las reglas: ver GroupEntity.
        'memberIds': memberIds,
        'members': {
          for (final m in members.values)
            m.uid: {
              'displayName': m.displayName,
              'photoUrl': m.photoUrl,
              'joinedAt': Timestamp.fromDate(m.joinedAt),
            }
        },
        'createdAt': Timestamp.fromDate(createdAt),
        'archived': archived,
      };
}
