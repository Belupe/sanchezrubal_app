import '../main.dart';

/// Operaciones que requieren la Admin API de Supabase Auth, vía la Edge
/// Function `admin-users` (solo admin principal). Lanza excepción si falla.
class AdminService {
  static Future<void> _invoke(Map<String, dynamic> body) async {
    final res = await supabase.functions.invoke('admin-users', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
  }

  /// Invita (o re-vincula si el email ya existe) a un usuario.
  static Future<void> inviteUser({
    required String name,
    required String email,
    required String role,
    String? familyGroupId,
  }) =>
      _invoke({
        'action': 'invite_user',
        'name': name,
        'email': email,
        'role': role,
        'familyGroupId': familyGroupId,
      });

  /// Crea un grupo familiar y su propietario (administrador familiar).
  static Future<void> createGroup({
    required String groupName,
    String color = '#3b82f6',
    String? ownerName,
    String? ownerEmail,
  }) =>
      _invoke({
        'action': 'create_group',
        'groupName': groupName,
        'color': color,
        'ownerName': ownerName,
        'ownerEmail': ownerEmail,
      });

  /// Borra un usuario por completo (auth + perfil en cascada).
  static Future<void> deleteUser(String userId) =>
      _invoke({'action': 'delete_user', 'userId': userId});
}
