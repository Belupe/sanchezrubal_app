class Profile {
  final String id;
  final String name;
  final String? email;
  final String role;
  final String? familyGroupId;
  final String? image;

  Profile({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.familyGroupId,
    this.image,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        email: m['email'] as String?,
        role: (m['role'] as String?) ?? 'MEMBER',
        familyGroupId: m['family_group_id'] as String?,
        image: m['image'] as String?,
      );

  static const roleLabels = {
    'MEGA_ADMIN': 'Mega administrador',
    'PRINCIPAL_ADMIN': 'Administrador principal',
    'FAMILY_ADMIN': 'Administrador familiar',
    'FAMILY_SECOND_ADMIN': 'Administrador secundario',
    'MEMBER': 'Miembro',
  };

  String get roleLabel => roleLabels[role] ?? role;
  bool get isPrincipal => role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';
}
