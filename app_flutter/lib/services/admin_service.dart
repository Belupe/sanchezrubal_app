// Operaciones de administración (invitar, grupos, borrar) vía Edge Function.
import '../main.dart';

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

  static Future<void> deleteUser(String userId) =>
      _invoke({'action': 'delete_user', 'userId': userId});
}
