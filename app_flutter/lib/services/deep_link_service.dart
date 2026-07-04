import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/inspection_screen.dart';

/// Maneja los enlaces `portalfamilia://...` de los correos para abrir la app
/// en la pantalla correcta. Multiplataforma (Android, Windows, iOS) vía
/// app_links + el esquema registrado en cada plataforma.
///
///   portalfamilia://inspeccion/<reservationId>  →  formulario de inspección
class DeepLinkService {
  static final _appLinks = AppLinks();
  static bool _inited = false;
  static Uri? _pending; // enlace recibido antes de tener sesión

  // [B-12] UUID canónico (8-4-4-4-12), hex, sin distinguir mayús/minús.
  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // Si el enlace llega antes de la sesión (arranque en frío), reprocésalo
    // en cuanto haya login.
    supabase.auth.onAuthStateChange.listen((_) {
      final p = _pending;
      if (p != null && supabase.auth.currentSession != null) {
        _pending = null;
        _navigate(p);
      }
    });

    // Enlace que abrió la app (arranque en frío).
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}

    // Enlaces con la app ya abierta.
    _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static void _handle(Uri uri) {
    if (uri.scheme != 'portalfamilia') return;
    // Sin sesión todavía: lo guardamos para procesarlo tras el login.
    if (supabase.auth.currentSession == null) {
      _pending = uri;
      return;
    }
    _navigate(uri);
  }

  static void _navigate(Uri uri) {
    // host = 'inspeccion', pathSegments = [<reservationId>]
    final parts = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2 && parts.first == 'inspeccion') {
      final id = parts[1];
      // [B-12] Ignorar el deep link si el id no es un UUID válido.
      if (!_uuidRe.hasMatch(id)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
              builder: (_) => InspectionScreen(reservationId: id)),
        );
      });
    }
  }
}
