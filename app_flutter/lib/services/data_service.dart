// Acceso a datos (PostgREST/RPC). La autorización real la impone el RLS.
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
import '../models/reservation_swap.dart';
import '../utils/errors.dart';
import '../utils/password_policy.dart';
import 'offline_cache.dart';

class InvalidCurrentPasswordException implements Exception {
  const InvalidCurrentPasswordException();
}

class DataService {
  static String? get uid => supabase.auth.currentUser?.id;

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
      if (image.length > 700000) {
        throw Exception('La imagen es demasiado grande (máx. ~500 KB).');
      }
      patch['image'] = image;
    }
    if (patch.isEmpty) return;
    await supabase.from('profiles').update(patch).eq('id', uid!);
  }

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

  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final err = PasswordPolicy.validate(newPassword);
    if (err != null) throw ArgumentError(err);
    await _reauthenticate(currentPassword);
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> changeEmail(
      String currentPassword, String newEmail) async {
    await _reauthenticate(currentPassword);
    await supabase.auth.updateUser(UserAttributes(email: newEmail));
  }

  // Fusiona en vez de reemplazar: ui_preferences guarda también 'onboarding'.
  static Future<void> _mergeUiPreferences(Map<String, dynamic> patch) async {
    final row = await supabase
        .from('profiles')
        .select('ui_preferences')
        .eq('id', uid!)
        .maybeSingle();
    final actual = (row?['ui_preferences'] as Map?)?.cast<String, dynamic>() ?? {};
    await supabase
        .from('profiles')
        .update({'ui_preferences': {...actual, ...patch}})
        .eq('id', uid!);
  }

  static Future<void> saveThemeMode(String mode) =>
      _mergeUiPreferences({'theme': mode});

  static Future<void> marcarOnboardingVisto() =>
      _mergeUiPreferences({'onboarding': true});

  // Las categorías que el usuario puede silenciar. Deben coincidir con
  // categoria() de la Edge Function notify-changes.
  static const categoriasAviso = {
    'reservas': 'Reservas',
    'cola': 'Lista de espera',
    'intercambios': 'Intercambios',
    'inspecciones': 'Inspecciones y partes',
    'mantenimiento': 'Mantenimiento',
  };

  static Future<Map<String, bool>> preferenciasAviso() async {
    final p = await myProfile();
    final m = (p?['ui_preferences'] as Map?)?['notificaciones'] as Map?;
    return {
      for (final c in categoriasAviso.keys) c: (m?[c] as bool?) ?? true,
    };
  }

  static Future<void> guardarPreferenciasAviso(Map<String, bool> prefs) =>
      _mergeUiPreferences({'notificaciones': prefs});

  static Future<bool> onboardingVisto() async {
    final p = await myProfile();
    return ((p?['ui_preferences'] as Map?)?['onboarding'] as bool?) ?? false;
  }

  static Future<List<Property>> properties() => OfflineCache.lista(
        'properties',
        () async => (await supabase.from('properties').select().order('name'))
            .cast<Map<String, dynamic>>(),
        Property.fromMap,
      );

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

  static Future<List<Reservation>> reservationsForProperty(String propertyId) =>
      OfflineCache.lista(
        'calendario_$propertyId',
        () async => (await supabase
                .from('calendar_occupancy')
                .select('*, properties(name), family_groups(name, color)')
                .eq('property_id', propertyId)
                .order('start_date'))
            .cast<Map<String, dynamic>>(),
        Reservation.fromMap,
      );

  static Future<List<Reservation>> reservationsByPerson(String personId) async {
    final rows = await supabase
        .from('calendar_occupancy')
        .select('*, properties(name), family_groups(name, color)')
        .eq('created_by_id', personId)
        .eq('is_maintenance', false)
        .gte('end_date', DateTime.now().toIso8601String())
        .order('start_date');
    return (rows as List).map((e) => Reservation.fromMap(e)).toList();
  }

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

  static Future<void> updateReservationDetails(String id,
      {int? guestCount, String? notes, List<String>? guestsList}) async {
    final patch = <String, dynamic>{};
    if (guestCount != null) patch['guest_count'] = guestCount;
    if (notes != null) patch['notes'] = notes;
    if (guestsList != null) patch['guests_list'] = guestsList;
    if (patch.isEmpty) return;
    await supabase.from('reservations').update(patch).eq('id', id);
  }

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

  // Vía RPC a propósito: system_config solo lo ve el mega; sin esto un usuario
  // normal no sabría el tope y no podría reservar.
  static Future<({int maxDays, double pricePerNight})> bookingSettings() async {
    final data = await supabase.rpc('booking_settings');
    final m = (data is List ? (data.isEmpty ? null : data.first) : data)
        as Map<String, dynamic>?;
    return (
      maxDays: (m?['max_days'] as int?) ?? 15,
      pricePerNight: (m?['price_per_night'] as num?)?.toDouble() ?? 0,
    );
  }

  static Future<void> updateBookingSettings(
      {required int maxDays, required double pricePerNight}) async {
    await supabase.rpc('update_booking_settings',
        params: {'p_max_days': maxDays, 'p_price': pricePerNight});
  }

  static Future<String?> testSmtp() async {
    final res = await supabase.functions.invoke('test-smtp', body: {});
    final data = res.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return null;
  }

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

  static Future<List<WaitlistEntry>> waitlistForProperty(String propertyId) =>
      OfflineCache.lista(
        'cola_$propertyId',
        () async => (await supabase
                .from('waitlist_occupancy')
                .select('*, profiles!requested_by_id(name)')
                .eq('property_id', propertyId)
                .inFilter('status', ['waiting', 'offered'])
                .order('created_at'))
            .cast<Map<String, dynamic>>(),
        WaitlistEntry.fromMap,
      );

  // La vista compartida no expone offered_until; la fila propia sí (RLS).
  static Future<DateTime?> myOfferDeadline(String entryId) async {
    final row = await supabase
        .from('reservation_waitlist')
        .select('offered_until')
        .eq('id', entryId)
        .maybeSingle();
    final s = row?['offered_until'] as String?;
    return s == null ? null : DateTime.parse(s);
  }

  static Future<void> respondWaitlistOffer(String entryId, bool accept) async {
    await supabase.rpc('respond_waitlist_offer',
        params: {'p_id': entryId, 'p_accept': accept});
  }

  static Future<void> cancelWaitlistEntry(String id) async {
    await supabase.from('reservation_waitlist').delete().eq('id', id);
  }

  static Future<void> setReservationFixed(String reservationId, bool fixed) async {
    await supabase.rpc('set_reservation_fixed',
        params: {'p_reservation_id': reservationId, 'p_fixed': fixed});
  }

  static Future<void> proposeSwap({
    required String offerProperty,
    required DateTime offerStart,
    required DateTime offerEnd,
    required String wantProperty,
    required DateTime wantStart,
    required DateTime wantEnd,
  }) async {
    await supabase.rpc('propose_swap', params: {
      'p_offer_property': offerProperty,
      'p_offer_start': offerStart.toIso8601String(),
      'p_offer_end': offerEnd.toIso8601String(),
      'p_want_property': wantProperty,
      'p_want_start': wantStart.toIso8601String(),
      'p_want_end': wantEnd.toIso8601String(),
    });
  }

  static Future<void> respondSwap(String swapId, bool accept) async {
    await supabase
        .rpc('respond_swap', params: {'p_swap_id': swapId, 'p_accept': accept});
  }

  static Future<List<ReservationSwap>> mySwaps() async {
    final rows = await supabase
        .from('reservation_swaps')
        .select('*, proposer:profiles!proposer_id(name), '
            'target:profiles!target_id(name), '
            'offer_property:properties!offer_property_id(name), '
            'want_property:properties!want_property_id(name)')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => ReservationSwap.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<FamilyGroup>> familyGroups() async {
    final rows = await supabase
        .from('family_groups')

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

        .select('id, name, email, role, group_members(group_id, role)')
        .order('name');
    return (rows as List).map((e) => Profile.fromMap(e)).toList();
  }

  static Future<void> setGroupRole(String userId, String groupRole) async {
    await supabase
        .from('group_members')
        .update({'role': groupRole}).eq('user_id', userId);
  }

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

  static Future<List<Sorteo>> sorteos() async {
    final rows = await supabase
        .from('sorteos')
        .select('id, name, created_at, seed, '
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

  static Future<List<OutReport>> outReports() async {
    final rows = await supabase
        .from('out_reports')
        .select('id, reservation_id, general_status, notes, media_urls, rating, '
            'check_out, created_at, properties(name)')
        .order('created_at', ascending: false);
    return (rows as List).map((e) => OutReport.fromMap(e)).toList();
  }

  static Future<List<AuditLog>> auditLogs() async {
    final rows = await supabase
        .from('audit_logs')
        .select('action, entity_type, entity_id, details, created_at, '
            'profiles!audit_logs_user_id_fkey(name)')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((e) => AuditLog.fromMap(e)).toList();
  }

  static Future<SystemConfig?> systemConfig() async {
    final row = await supabase
        .from('system_config')
        .select(
            'smtp_host, smtp_port, smtp_user, smtp_secure, max_reservation_days, max_reservation_days_cap')
        .eq('id', 'global')
        .maybeSingle();
    return row == null ? null : SystemConfig.fromMap(row);
  }

  static Future<void> setSmtpPassword(String pass) async {
    await supabase.rpc('set_smtp_password', params: {'p_pass': pass});
  }

  static Future<void> updateSystemConfig(Map<String, dynamic> patch) async {
    await supabase.from('system_config').update(patch).eq('id', 'global');
  }

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

      if (data is Map && data['enviado'] == false) {
        return (data['motivo'] ?? 'No se envió el registro.').toString();
      }
      return null;
    } catch (e) {
      return friendlyError(e, fallback: 'No se pudo enviar el registro.');
    }
  }
}
