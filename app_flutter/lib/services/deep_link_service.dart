// Enlaces profundos (portalfamilia://): sesión y establecer contraseña.
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/inspection_screen.dart';
import 'log_service.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static bool _inited = false;
  static Uri? _pending;

  static Uri? _ultimo;
  static DateTime? _ultimoInstante;
  static const _ventanaDuplicado = Duration(seconds: 3);

  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static Future<void> init({List<String> argumentosDeArranque = const []}) async {
    if (_inited) return;
    _inited = true;

    supabase.auth.onAuthStateChange.listen((_) {
      final p = _pending;
      if (p != null && supabase.auth.currentSession != null) {
        _pending = null;
        _navigate(p);
      }
    });

    for (final a in argumentosDeArranque) {
      final uri = Uri.tryParse(a);
      if (uri != null && uri.scheme == 'portalfamilia') _handle(uri);
    }

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}

    _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static void _handle(Uri uri) {
    if (uri.scheme != 'portalfamilia') return;

    final ahora = DateTime.now();
    if (_ultimo == uri &&
        _ultimoInstante != null &&
        ahora.difference(_ultimoInstante!) < _ventanaDuplicado) {
      return;
    }
    _ultimo = uri;
    _ultimoInstante = ahora;

    LogService.evento('Deep link recibido: ${uri.scheme}://${uri.host}');

    if (supabase.auth.currentSession == null) {
      _pending = uri;
      return;
    }
    _navigate(uri);
  }

  static void _navigate(Uri uri) {
    final parts = [uri.host, ...uri.pathSegments].where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2 && parts.first == 'inspeccion') {
      final id = parts[1];

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
