class Profile {
  final String id;
  final String name;
  final String? email;

  final String role;

  final String? familyGroupId;

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

    'FAMILY_ADMIN': 'Administrador familiar',
    'FAMILY_SECOND_ADMIN': 'Administrador secundario',
    'MEMBER': 'Miembro',
  };

  String get roleLabel => roleLabels[role] ?? role;

  String? get groupRoleLabel =>
      groupRole == null ? null : (roleLabels[groupRole] ?? groupRole);

  bool get isPrincipal => role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';

  bool get isGroupAdmin =>
      isPrincipal ||
      groupRole == 'FAMILY_ADMIN' ||
      groupRole == 'FAMILY_SECOND_ADMIN';
}
