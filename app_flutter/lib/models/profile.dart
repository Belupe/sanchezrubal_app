class Profile {
  final String id;
  final String name;
  final String? email;

  /// Rango GLOBAL: `MEGA_ADMIN`, `PRINCIPAL_ADMIN` o `USER`. Desde la migración
  /// 0025 ya NO dice nada de lo que eres dentro de una casa: eso es [groupRole].
  final String role;

  /// La casa a la que perteneces, si es que perteneces a alguna.
  final String? familyGroupId;

  /// Tu papel DENTRO de esa casa: `FAMILY_ADMIN`, `FAMILY_SECOND_ADMIN` o
  /// `MEMBER`. Es ortogonal a [role]: un mega administrador puede ser
  /// perfectamente un miembro más de su propia familia.
  final String? groupRole;

  final String? image;

  Profile({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.familyGroupId,
    this.groupRole,
    this.image,
  });

  factory Profile.fromMap(Map<String, dynamic> m) {
    // La pertenencia llega anidada cuando la consulta hace el join con
    // group_members; PostgREST la devuelve como lista o como objeto según la
    // forma de la relación, así que se admiten las dos.
    //
    // Solo de ahí. Antes había un respaldo a `m['family_group_id']` y
    // `m['group_role']`, columnas de `profiles` que la migración 0025 eliminó:
    // no podían llegar nunca y hacían creer que el grupo aún vivía en el
    // perfil. Si el join falta, el resultado correcto es null, no un valor
    // heredado de un esquema que ya no existe.
    final gm = m['group_members'];
    final miembro = gm is List
        ? (gm.isEmpty ? null : gm.first as Map<String, dynamic>)
        : gm as Map<String, dynamic>?;
    return Profile(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      email: m['email'] as String?,
      role: (m['role'] as String?) ?? 'USER',
      familyGroupId: miembro?['group_id'] as String?,
      groupRole: miembro?['role'] as String?,
      image: m['image'] as String?,
    );
  }

  static const roleLabels = {
    'MEGA_ADMIN': 'Mega administrador',
    'PRINCIPAL_ADMIN': 'Administrador principal',
    'USER': 'Usuario',
    // De grupo. Se dejan aquí para que [groupRoleLabel] los traduzca igual.
    'FAMILY_ADMIN': 'Administrador familiar',
    'FAMILY_SECOND_ADMIN': 'Administrador secundario',
    'MEMBER': 'Miembro',
  };

  /// Etiqueta del rango global.
  String get roleLabel => roleLabels[role] ?? role;

  /// Etiqueta del papel dentro de la casa, o `null` si no está en ninguna.
  String? get groupRoleLabel =>
      groupRole == null ? null : (roleLabels[groupRole] ?? groupRole);

  bool get isPrincipal => role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';

  /// Manda en su casa: o bien por rango global, o bien por ser su administrador.
  bool get isGroupAdmin =>
      isPrincipal ||
      groupRole == 'FAMILY_ADMIN' ||
      groupRole == 'FAMILY_SECOND_ADMIN';
}
