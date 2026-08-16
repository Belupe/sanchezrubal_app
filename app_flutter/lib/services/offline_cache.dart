// Caché de solo lectura para poder abrir la app sin cobertura. Guarda la
// última respuesta buena de cada consulta; si la red falla, se sirve esa.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCache {
  static const _prefijo = 'cache_';

  /// true mientras la última lectura se haya servido desde la caché.
  static final ValueNotifier<bool> sinConexion = ValueNotifier(false);

  static Future<void> _guardar(String clave, Object datos) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_prefijo$clave', jsonEncode(datos));
  }

  static Future<dynamic> _leer(String clave) async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('$_prefijo$clave');
    return s == null ? null : jsonDecode(s);
  }

  /// Intenta la red; si falla, devuelve lo último guardado. Si no hay nada
  /// guardado, propaga el error original para no ocultar el problema.
  static Future<List<T>> lista<T>(
    String clave,
    Future<List<Map<String, dynamic>>> Function() traer,
    T Function(Map<String, dynamic>) crear,
  ) async {
    try {
      final filas = await traer();
      await _guardar(clave, filas);
      sinConexion.value = false;
      return filas.map(crear).toList();
    } catch (e) {
      final guardado = await _leer(clave);
      if (guardado is List) {
        sinConexion.value = true;
        return guardado
            .map((f) => crear((f as Map).cast<String, dynamic>()))
            .toList();
      }
      rethrow;
    }
  }

  static Future<void> limpiar() async {
    final sp = await SharedPreferences.getInstance();
    for (final k in sp.getKeys().where((k) => k.startsWith(_prefijo))) {
      await sp.remove(k);
    }
    sinConexion.value = false;
  }
}
