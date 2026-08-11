// Almacenamiento seguro de la sesión (keychain/keystore).
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const FlutterSecureStorage _secure = FlutterSecureStorage();

String _persistSessionKey(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required String supabaseUrl})
      : _key = _persistSessionKey(supabaseUrl);

  final String _key;

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _migrateFromSharedPreferences();
  }

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
    }
  }

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
    }
  }
}

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
