import 'profile.dart';

class FamilyGroup {
  final String id;
  final String name;
  final String color;
  final String? ownerId;
  final List<Profile> members;

  FamilyGroup({
    required this.id,
    required this.name,
    required this.color,
    this.ownerId,
    this.members = const [],
  });

  factory FamilyGroup.fromMap(Map<String, dynamic> m) => FamilyGroup(
        id: m['id'] as String,
        name: m['name'] as String,
        color: (m['color'] as String?) ?? '#3b82f6',
        ownerId: m['owner_id'] as String?,
        // Desde la 0025 los miembros llegan por group_members, que trae el
        // papel en la casa y anida el perfil. Se aplanan los dos niveles en un
        // solo Profile para que las pantallas no vean el cambio.
        members: (m['group_members'] as List?)
                ?.map((e) {
                  final fila = e as Map<String, dynamic>;
                  final p = (fila['profiles'] as Map<String, dynamic>?) ?? {};
                  return Profile.fromMap({
                    ...p,
                    'family_group_id': fila['group_id'],
                    'group_role': fila['role'],
                  });
                })
                .toList() ??
            const [],
      );
}
