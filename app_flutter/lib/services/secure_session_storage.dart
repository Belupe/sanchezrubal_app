import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [M-09] Almacenamiento CIFRADO de la sesión de Supabase (JWT + refresh token)
/// en Keychain (iOS/macOS) / EncryptedSharedPreferences-Keystore (Android), con
/// la MISMA clave que usa supabase_flutter por defecto ("sb-<subdominio>-auth-token")
/// para migrar la sesión existente sin desloguear al actualizar.
///
/// Robustez: supabase_flutter llama initialize()/hasAccessToken()/accessToken()
/// SIN try/catch. El backend cifrado de Android puede lanzar al descifrar si el
/// Keystore se invalida (cambio de bloqueo/biometría, update de OS, restore). Por
/// eso TODAS las operaciones van protegidas: ante un fallo se degrada a "sin
/// sesión" (re-login una vez) en lugar de crashear el arranque en bucle. El texto
/// plano nunca reaparece.
// Opciones por defecto (flutter_secure_storage 10.x): Keystore en Android,
// Keychain en iOS/macOS. Se usan los defaults para no depender de parámetros que
// cambian entre versiones; el sistema operativo cifra el dato en reposo.
const FlutterSecureStorage _secure = FlutterSecureStorage();

String _persistSessionKey(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// LocalStorage cifrado para la sesión de Supabase.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required String supabaseUrl})
      : _key = _persistSessionKey(supabaseUrl);

  final String _key;

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _migrateFromSharedPreferences();
  }

  /// Migración transparente de una sola vez desde SharedPreferences (en claro).
  /// Best-effort: nunca debe impedir arrancar la app.
  Future<void> _migrateFromSharedPreferences() async {
    try {
      if (await _secure.containsKey(key: _key)) return;
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_key);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: _key, value: legacy);
        await prefs.remove(_key);
      }
    } catch (_) {
      // No bloquear el arranque.
    }
  }

  /// Borra la entrada (posiblemente corrupta) sin lanzar, para auto-sanar.
  Future<void> _safeDelete() async {
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
  }

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _secure.containsKey(key: _key);
    } catch (_) {
      await _safeDelete();
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _secure.read(key: _key);
    } catch (_) {
      // Fallo de descifrado → re-login en vez de crash-loop; auto-sanar.
      await _safeDelete();
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() => _safeDelete();

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _secure.write(key: _key, value: persistSessionString);
    } catch (_) {
      // Si no se puede persistir, la sesión sigue viva en memoria; no propagar.
    }
  }
}

/// Almacén cifrado para el code_verifier del flujo PKCE (deep links / recuperación
/// de contraseña). Protegido igual para no romper el intercambio de código.
class SecurePkceAsyncStorage extends GotrueAsyncStorage {
  const SecurePkceAsyncStorage();

  @override
  Future<String?> getItem({required String key}) async {
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await _secure.delete(key: key);
    } catch (_) {}
  }
}
