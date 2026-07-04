import '../main.dart';

/// Operaciones que requieren la Admin API de Supabase Auth, vía la Edge
/// Function `admin-users` (solo admin principal). Lanza excepción si falla.
class AdminService {
  static Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final res = await supabase.functions.invoke('admin-users', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
  }

  /// Invita (o re-vincula si el email ya existe) a un usuario.
  /// Si la cuenta ya existe y el cambio reasigna grupo/rol, el backend
  /// responde {requiresConfirm:true,...} sin tocar nada; reintentar con
  /// confirmRelink:true tras confirmar con el usuario. [B-03]
  static Future<Map<String, dynamic>> inviteUser({
    required String name,
    required String email,
    required String role,
    String? familyGroupId,
    bool confirmRelink = false,
  }) =>
      _invoke({
        'action': 'invite_user',
        'name': name,
        'email': email,
        'role': role,
        'familyGroupId': familyGroupId,
        'confirmRelink': confirmRelink,
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
