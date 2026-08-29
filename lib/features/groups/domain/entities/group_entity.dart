import 'package:equatable/equatable.dart';

/// Un integrante del grupo. Los datos se copian al entrar para poder mostrar
/// la lista sin leer el perfil de cada uno.
class GroupMember extends Equatable {
  const GroupMember({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.joinedAt,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final DateTime joinedAt;

  @override
  List<Object?> get props => [uid, displayName, photoUrl, joinedAt];
}

/// Un grupo de gastos compartidos.
///
/// [memberIds] esta desnormalizado a proposito: las reglas de Firestore lo
/// usan para autorizar (`request.auth.uid in resource.data.memberIds`). La
/// alternativa, un `get()` del grupo dentro de la regla, cobra una lectura en
/// cada evaluacion.
class GroupEntity extends Equatable {
  const GroupEntity({
    required this.id,
    required this.name,
    required this.currency,
    required this.createdBy,
    required this.memberIds,
    required this.members,
    required this.createdAt,
    this.archived = false,
  });

  final String id;
  final String name;

  /// Una moneda por grupo, fija al crear. Multi-moneda esta fuera de alcance.
  final String currency;

  final String createdBy;
  final List<String> memberIds;
  final Map<String, GroupMember> members;
  final DateTime createdAt;
  final bool archived;

  String nameOf(String uid) => members[uid]?.displayName ?? 'Alguien';

  GroupEntity copyWith({
    String? name,
    List<String>? memberIds,
    Map<String, GroupMember>? members,
    bool? archived,
  }) {
    return GroupEntity(
      id: id,
      name: name ?? this.name,
      currency: currency,
      createdBy: createdBy,
      memberIds: memberIds ?? this.memberIds,
      members: members ?? this.members,
      createdAt: createdAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, currency, createdBy, memberIds, members, createdAt, archived];
}
