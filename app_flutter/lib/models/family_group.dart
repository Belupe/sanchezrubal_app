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
        //
        // La pertenencia se rearma con la MISMA forma que devuelve PostgREST
        // (una lista `group_members`), porque es la única que lee
        // Profile.fromMap. Aquí la relación viene del revés —el grupo trae a
        // sus miembros, no al contrario—, pero el modelo no tiene por qué
        // enterarse. Antes se le pasaban `family_group_id` y `group_role`
        // sueltos, que Profile.fromMap dejó de aceptar en f5f59bd: desde
        // entonces el papel de TODOS los miembros llegaba nulo y la ficha los
        // pintaba a todos como "Miembro", aunque en la base de datos
        // estuvieran bien guardados.
        members: (m['group_members'] as List?)
                ?.map((e) {
                  final fila = e as Map<String, dynamic>;
                  final p = (fila['profiles'] as Map<String, dynamic>?) ?? {};
                  return Profile.fromMap({
                    ...p,
                    'group_members': [
                      {'group_id': fila['group_id'], 'role': fila['role']},
                    ],
                  });
                })
                .toList() ??
            const [],
      );
}
