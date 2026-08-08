import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/announcement.dart';
import '../models/audit_log.dart';
import '../models/family_group.dart';
import '../models/out_report.dart';
import '../models/profile.dart';
import '../models/property.dart';
import '../models/reservation.dart';
import '../models/sorteo.dart';
import '../models/system_config.dart';
import '../models/waitlist_entry.dart';
import '../utils/errors.dart';
import '../utils/password_policy.dart';

/// [M-12] La contraseña ACTUAL de la reautenticación no es correcta. Se distingue
/// de AuthException genérica para que la UI muestre el mensaje adecuado.
class InvalidCurrentPasswordException implements Exception {
  const InvalidCurrentPasswordException();
}

/// Acceso a datos vía Supabase. El RLS decide qué puede ver/hacer cada rol.
class DataService {
  static String? get uid => supabase.auth.currentUser?.id;

  // ----------------------------------------------------------------
  // Perfil propio
  // ----------------------------------------------------------------
  /// Perfil propio, con la pertenencia aplanada. Desde la migración 0025 el
  /// grupo y el papel dentro de él viven en `group_members`, pero se devuelven
  /// como `family_group_id` y `group_role` para que quien lo consume no tenga
  /// que saberlo.
  static Future<Map<String, dynamic>?> myProfile() async {
    final id = uid;
    if (id == null) return null;
    final row = await supabase
        .from('profiles')
        .select('id, name, email, role, image, ui_preferences, '
            'group_members(group_id, role)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final gm = row['group_members'];
    final miembro = gm is List ? (gm.isEmpty ? null : gm.first) : gm;
    return {
      ...row,
      'family_group_id': miembro?['group_id'],
      'group_role': miembro?['role'],
    };
  }

  static Future<String?> currentRole() async =>
      (await myProfile())?['role'] as String?;

  static Future<void> updateMyProfile({String? name, String? image}) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (image != null) {
      // [2M-02] Acota el tamaño del avatar en cliente (el servidor también lo
      // limita con un CHECK). Evita blobs base64 enormes que inflan la BD.
      if (image.length > 700000) {
        throw Exception('La imagen es demasiado grande (máx. ~500 KB).');
      }
      patch['image'] = image;
    }
    if (patch.isEmpty) return;
    await supabase.from('profiles').update(patch).eq('id', uid!);
  }

  /// [M-12] Reautentica con la contraseña ACTUAL. Lanza
  /// InvalidCurrentPasswordException si no coincide.
  static Future<void> _reauthenticate(String currentPassword) async {
    final email = supabase.auth.currentUser?.email;
    if (email == null) throw const InvalidCurrentPasswordException();
    try {
      await supabase.auth
          .signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw const InvalidCurrentPasswordException();
    }
  }

  /// Cambia la contraseña. [M-12] exige la contraseña actual; [M-13] criba local
  /// (la autoridad real es Supabase Auth).
  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final err = PasswordPolicy.validate(newPassword);
    if (err != null) throw ArgumentError(err);
    await _reauthenticate(currentPassword);
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Cambia el correo. Supabase envía confirmación al nuevo email; profiles.email
  /// lo sincroniza el trigger on_auth_user_email_changed (0020) cuando GoTrue
  /// confirma el cambio en auth.users. No se escribe profiles.email desde el
  /// cliente: como 'authenticated' lo revierte profiles_guard [B-02]. [M-12]
  /// exige la contraseña actual antes.
  static Future<void> changeEmail(
      String currentPassword, String newEmail) async {
    await _reauthenticate(currentPassword);
    await supabase.auth.updateUser(UserAttributes(email: newEmail));
  }

  /// Guarda la preferencia de tema ('system' | 'light' | 'dark').
  static Future<void> saveThemeMode(String mode) async {
    await supabase
        .from('profiles')
        .update({'ui_preferences': {'theme': mode}})
        .eq('id', uid!);
  }

  // ----------------------------------------------------------------
  // Propiedades (domicilios)
  // ----------------------------------------------------------------
  static Future<List<Property>> properties() async {
    final rows = await supabase.from('properties').select().order('name');
    return (rows as List).map((e) => Property.fromMap(e)).toList();
  }

  static Future<void> createProperty({required String name, String? description}) async {
    await supabase.from('properties').insert({'name': name, 'description': description});
  }

  static Future<void> updateProperty(String id,
      {required String name, String? description}) async {
    await supabase
        .from('properties')
        .update({'name': name, 'description': description})
        .eq('id', id);
  }

  static Future<void> deleteProperty(String id) async {
    await supabase.from('properties').delete().eq('id', id);
  }

  // ----------------------------------------------------------------
  // Reservas
  // ----------------------------------------------------------------
  static Future<List<Reservation>> reservations() async {
    final rows = await supabase
        .from('reservations')
        .select('*, properties(name), family_groups(name, color)')
        .order('start_date');
    return (rows as List).map((e) => Reservation.fromMap(e)).toList();
  }

  /// Reservas de un domicilio concreto (para su calendario individual).
  static Future<List<Reservation>> reservationsForProperty(String propertyId) async {
    // [A-04] Lee de la VISTA de ocupación (sin guests_list/notes): el calendario
    // compartido sigue mostrando fechas + domicilio de todas las familias.
    final rows = await supabase
        .from('calendar_occupancy')
        .select('*, properties(name), family_groups(name, color)')
        .eq('property_id', propertyId)
        .order('start_date');
    return (rows as List).map((e) => Reservation.fromMap(e)).toList();
  }

  /// Fila COMPLETA de una reserva (incluye notes) desde la tabla. El RLS solo la
  /// devuelve al creador, a su grupo o a un admin; si no, null. [A-04]
  static Future<Reservation?> reservationById(String id) async {
    final row = await supabase
        .from('reservations')
        .select('*, properties(name), family_groups(name, color)')
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Reservation.fromMap(row);
  }

  static Future<Reservation> createReservation({
    required String propertyId,
    required DateTime start,
    required DateTime end,
    required int guestCount,
    String? familyGroupId,
    String? notes,
    bool isMaintenance = false,
  }) async {
    final inserted = await supabase
        .from('reservations')
        .insert({
          'property_id': propertyId,
          'created_by_id': uid,
          'family_group_id': familyGroupId,
          'start_date': start.toIso8601String(),
          'end_date': end.toIso8601String(),
          'guest_count': guestCount,
          'notes': notes,
          'is_maintenance': isMaintenance,
        })
        .select('*, properties(name)')
        .single();
    return Reservation.fromMap(inserted);
  }

  /// El creador solo puede ajustar personas/notas (el trigger de la BD
  /// rechaza cambios de fecha si no es admin).
  static Future<void> updateReservationDetails(String id,
      {int? guestCount, String? notes}) async {
    final patch = <String, dynamic>{};
    if (guestCount != null) patch['guest_count'] = guestCount;
    if (notes != null) patch['notes'] = notes;
    if (patch.isEmpty) return;
    await supabase.from('reservations').update(patch).eq('id', id);
  }

  /// Solo admin del grupo / principal (lo impone el RLS + trigger).
  static Future<void> updateReservationDates(String id,
      {required DateTime start, required DateTime end}) async {
    await supabase.from('reservations').update({
      'start_date': start.toIso8601String(),
      'end_date': end.toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteReservation(String id) async {
    await supabase.from('reservations').delete().eq('id', id);
  }

  static Future<int> maxReservationDays() async {
    final row = await supabase
        .from('system_config')
        .select('max_reservation_days')
        .eq('id', 'global')
        .maybeSingle();
    return (row?['max_reservation_days'] as int?) ?? 30;
  }

  /// Pide al backend que envíe el correo (best-effort).
  static Future<void> sendReservationEmail(String reservationId,
      {required bool maintenance}) async {
    try {
      await supabase.functions.invoke('send-email', body: {
        'type': maintenance ? 'maintenance' : 'reservation_confirmation',
        'reservationId': reservationId,
      });
    } catch (_) {/* no bloquea la creación */}
  }

  /// Envía un correo de prueba con la config SMTP (solo mega). Se envía SIEMPRE
  /// al propio correo del mega (el servidor ignora cualquier destino) [I-06].
  /// Devuelve null si fue bien, o el mensaje de error.
  static Future<String?> testSmtp() async {
    final res = await supabase.functions.invoke('test-smtp', body: {});
    final data = res.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }

  // ----------------------------------------------------------------
  // Lista de espera (cola) de reservas
  // ----------------------------------------------------------------

  /// Se apunta a la cola de un domicilio para unas fechas ocupadas. Si la
  /// reserva que las bloquea se cancela, un trigger de la BD promueve al
  /// primero de la cola y le crea la reserva (+ 2 notificaciones).
  static Future<void> joinWaitlist({
    required String propertyId,
    required DateTime start,
    required DateTime end,
    required int guestCount,
    String? familyGroupId,
    String? notes,
  }) async {
    await supabase.from('reservation_waitlist').insert({
      'property_id': propertyId,
      'requested_by_id': uid,
      'family_group_id': familyGroupId,
      'start_date': start.toIso8601String(),
      'end_date': end.toIso8601String(),
      'guest_count': guestCount,
      'notes': notes,
    });
  }

  /// Cola activa (en espera) de un domicilio, en orden FIFO. Incluye el
  /// nombre del solicitante para mostrar la lista y calcular la posición.
  static Future<List<WaitlistEntry>> waitlistForProperty(String propertyId) async {
    // [A-04] Lee de la VISTA de ocupación (sin notes): la cola compartida sigue
    // mostrando las posiciones de todas las familias, sin las notas privadas.
    final rows = await supabase
        .from('waitlist_occupancy')
        .select('*, profiles!requested_by_id(name)')
        .eq('property_id', propertyId)
        .eq('status', 'waiting')
        .order('created_at');
    return (rows as List).map((e) => WaitlistEntry.fromMap(e)).toList();
  }

  /// Mis solicitudes en cola (cualquier estado), para "Mis listas de espera".
  static Future<List<WaitlistEntry>> myWaitlistEntries() async {
    final rows = await supabase
        .from('reservation_waitlist')
        .select('*, properties(name)')
        .eq('requested_by_id', uid!)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => WaitlistEntry.fromMap(e)).toList();
  }

  /// Retira una solicitud de la cola (el solicitante o un admin del grupo).
  static Future<void> cancelWaitlistEntry(String id) async {
    await supabase.from('reservation_waitlist').delete().eq('id', id);
  }

  // ----------------------------------------------------------------
  // Grupos familiares y miembros
  // ----------------------------------------------------------------
  static Future<List<FamilyGroup>> familyGroups() async {
    final rows = await supabase
        .from('family_groups')
        // [2M-02] No se trae `image` en listados masivos (puede ser un blob
        // base64 grande y no se muestra); el avatar se cargaría bajo demanda.
        .select('id, name, color, owner_id, '
            'group_members(group_id, role, profiles(id, name, email, role))')
        .order('name');
    return (rows as List).map((e) => FamilyGroup.fromMap(e)).toList();
  }

  static Future<void> updateFamilyGroup(String id, {String? name, String? color}) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (color != null) patch['color'] = color;
    if (patch.isEmpty) return;
    await supabase.from('family_groups').update(patch).eq('id', id);
  }

  static Future<void> deleteFamilyGroup(String id) async {
    await supabase.from('family_groups').delete().eq('id', id);
  }

  static Future<List<Profile>> allProfiles() async {
    final rows = await supabase
        .from('profiles')
        // [2M-02] Sin `image` en el listado (no se muestra; evita difundir blobs).
        .select('id, name, email, role, group_members(group_id, role)')
        .order('name');
    return (rows as List).map((e) => Profile.fromMap(e)).toList();
  }

  /// Cambiar el rango GLOBAL de alguien (principal, vía RLS).
  static Future<void> setRole(String userId, String role) async {
    await supabase.from('profiles').update({'role': role}).eq('id', userId);
  }

  /// Cambiar el papel de alguien DENTRO de su casa. No toca su rango global.
  static Future<void> setGroupRole(String userId, String groupRole) async {
    await supabase
        .from('group_members')
        .update({'role': groupRole}).eq('user_id', userId);
  }

  /// Meter en un grupo o sacar de él. `null` = expulsar (la cuenta sigue viva).
  /// El `upsert` sobre `user_id` traslada de casa en un solo paso mientras siga
  /// existiendo la restricción de un grupo por persona.
  static Future<void> setMemberGroup(String userId, String? groupId,
      {String groupRole = 'MEMBER'}) async {
    if (groupId == null) {
      await supabase.from('group_members').delete().eq('user_id', userId);
      return;
    }
    await supabase.from('group_members').upsert(
      {'user_id': userId, 'group_id': groupId, 'role': groupRole},
      onConflict: 'user_id',
    );
  }

  // ----------------------------------------------------------------
  // Anuncios
  // ----------------------------------------------------------------
  static Future<List<Announcement>> announcements() async {
    final rows = await supabase
        .from('announcements')
        .select('id, title, content, created_at, '
            'profiles!announcements_author_id_fkey(name), '
            'announcement_properties(properties(name))')
        .order('created_at', ascending: false);
    return (rows as List).map((e) => Announcement.fromMap(e)).toList();
  }

  static Future<void> createAnnouncement({
    required String title,
    required String content,
    List<String> propertyIds = const [],
  }) async {
    final inserted = await supabase
        .from('announcements')
        .insert({'title': title, 'content': content, 'author_id': uid})
        .select('id')
        .single();
    final aId = inserted['id'] as String;
    if (propertyIds.isNotEmpty) {
      await supabase.from('announcement_properties').insert(
            propertyIds.map((p) => {'announcement_id': aId, 'property_id': p}).toList(),
          );
    }
  }

  static Future<void> deleteAnnouncement(String id) async {
    await supabase.from('announcements').delete().eq('id', id);
  }

  // ----------------------------------------------------------------
  // Sorteos
  // ----------------------------------------------------------------
  static Future<List<Sorteo>> sorteos() async {
    final rows = await supabase
        .from('sorteos')
        .select('id, name, created_at, '
            'profiles!sorteos_created_by_id_fkey(name), '
            'sorteo_resultados(premio, family_groups(name))')
        .order('created_at', ascending: false);
    return (rows as List).map((e) => Sorteo.fromMap(e)).toList();
  }

  static Future<void> runSorteo({
    required String name,
    required List<String> quincenas,
    required List<String> groupIds,
  }) async {
    await supabase.rpc('run_sorteo', params: {
      'p_name': name,
      'p_quincenas': quincenas,
      'p_group_ids': groupIds,
    });
  }

  static Future<void> deleteSorteo(String id) async {
    await supabase.from('sorteos').delete().eq('id', id);
  }

  // ----------------------------------------------------------------
  // Inspecciones (out_reports) — panel para admins
  // ----------------------------------------------------------------
  static Future<List<OutReport>> outReports() async {
    final rows = await supabase
        .from('out_reports')
        .select('id, reservation_id, general_status, notes, media_urls, rating, '
            'check_out, created_at, properties(name)')
        .order('created_at', ascending: false);
    return (rows as List).map((e) => OutReport.fromMap(e)).toList();
  }

  // ----------------------------------------------------------------
  // Registros / auditoría (quién crea/modifica/elimina)
  // ----------------------------------------------------------------
  static Future<List<AuditLog>> auditLogs() async {
    final rows = await supabase
        .from('audit_logs')
        .select('action, entity_type, entity_id, details, created_at, '
            'profiles!audit_logs_user_id_fkey(name)')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => AuditLog.fromMap(e)).toList();
  }

  // ----------------------------------------------------------------
  // Configuración del sistema (solo mega admin, vía RLS)
  // ----------------------------------------------------------------
  static Future<SystemConfig?> systemConfig() async {
    // [M-07] Sin smtp_pass: la contraseña vive en Vault y nunca se descarga al cliente.
    final row = await supabase
        .from('system_config')
        .select(
            'smtp_host, smtp_port, smtp_user, smtp_secure, max_reservation_days, max_reservation_days_cap')
        .eq('id', 'global')
        .maybeSingle();
    return row == null ? null : SystemConfig.fromMap(row);
  }

  /// [M-07] Guarda la contraseña SMTP en Vault (solo mega, vía RPC SECURITY DEFINER).
  static Future<void> setSmtpPassword(String pass) async {
    await supabase.rpc('set_smtp_password', params: {'p_pass': pass});
  }

  static Future<void> updateSystemConfig(Map<String, dynamic> patch) async {
    await supabase.from('system_config').update(patch).eq('id', 'global');
  }

  // Plantillas de correo
  static Future<List<Map<String, dynamic>>> templates() async {
    final rows = await supabase.from('notification_templates').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateTemplate(String type,
      {required String subject, required String body}) async {
    await supabase.from('notification_templates').upsert(
      {'type': type, 'subject': subject, 'body': body},
      onConflict: 'type',
    );
  }

  // Nota: los ajustes de notificación propios (myNotificationSettings /
  // saveNotificationSetting) se retiraron al convertir esa pestaña en Soporte,
  // y la tabla `notification_settings` se eliminó en la migración 0031 al
  // quedarse sin quien la escribiera. El recordatorio PRE_STAY se sigue
  // enviando a todo el mundo; lo que ya no existe es la forma de silenciarlo.
  // Si algún día hace falta volver a ofrecerlo, está en el historial.

  /// Manda el registro de diagnóstico a soporte. El destinatario NO viaja en la
  /// petición: lo fija la Edge Function, para que esto no sea un relé de correo.
  ///
  /// Devuelve `null` si fue bien, o el mensaje de error para enseñarlo.
  static Future<String?> enviarRegistroASoporte({
    required String registro,
    required bool esFallo,
    Map<String, String> contexto = const {},
  }) async {
    try {
      final res = await supabase.functions.invoke(
        'send-log',
        body: {'log': registro, 'esFallo': esFallo, 'contexto': contexto},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
      // El servidor puede aceptar la petición y aun así NO enviar: hay un
      // anti-doble-toque y un tope diario por usuario para no gastar el cupo
      // del SMTP. En ese caso explica por qué, y no es un fallo.
      if (data is Map && data['enviado'] == false) {
        return (data['motivo'] ?? 'No se envió el registro.').toString();
      }
      return null;
    } catch (e) {
      return friendlyError(e, fallback: 'No se pudo enviar el registro.');
    }
  }
}
