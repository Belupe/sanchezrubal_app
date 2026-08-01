import 'package:flutter_test/flutter_test.dart';
import 'package:portal_familia/config.dart';
import 'package:portal_familia/services/log_service.dart';

/// El registro de fallos está pensado para que el usuario nos lo ENVÍE (por
/// correo o por el menú de compartir del móvil). Si se cuela una credencial,
/// se filtra en cuanto alguien reenvía el fichero. Esta prueba blinda esa
/// redacción: es lo único de LogService que, si se rompe, hace daño.
void main() {
  group('LogService.redactar', () {
    test('quita los JWT de Supabase (sesión y refresh)', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final r = LogService.redactar('AuthException: token=$jwt caducado');
      expect(r, contains('<JWT>'));
      expect(r, isNot(contains(jwt)));
      expect(r, isNot(contains('eyJhbGci')));
    });

    test('quita los tokens de los cuerpos JSON', () {
      final r = LogService.redactar(
          '{"access_token":"abc123","refresh_token":"zzz-999","expires_in":3600}');
      expect(r, isNot(contains('abc123')));
      expect(r, isNot(contains('zzz-999')));
      expect(r, contains('<REDACTADO>'));
      // Lo que NO es secreto debe seguir ahí: si no, el informe no sirve.
      expect(r, contains('expires_in'));
    });

    test('quita las cabeceras de autorización', () {
      final r = LogService.redactar(
          'headers: {Authorization: Bearer secreto-de-verdad, apikey: otra-cosa}');
      expect(r, isNot(contains('secreto-de-verdad')));
      expect(r, isNot(contains('otra-cosa')));
    });

    test('quita la firma de las URLs prefirmadas de MinIO', () {
      // Las excepciones de Dio incluyen la URL ENTERA, con su firma.
      const url =
          'https://media.sanchezrubal.net/inspecciones/foto.jpg?X-Amz-Algorithm=AWS4-HMAC-SHA256'
          '&X-Amz-Credential=MINIOKEY%2F20260801%2Fus-east-1%2Fs3%2Faws4_request'
          '&X-Amz-Signature=3f1a9c8e7d6b5a4c3f1a9c8e7d6b5a4c3f1a9c8e7d6b5a4c3f1a9c8e7d6b5a4c';
      final r = LogService.redactar('DioException: $url');
      expect(r, isNot(contains('3f1a9c8e7d6b5a4c')));
      expect(r, isNot(contains('MINIOKEY')));
      // El host y la ruta sí interesan para diagnosticar.
      expect(r, contains('media.sanchezrubal.net'));
      expect(r, contains('foto.jpg'));
    });

    test('anonimiza los correos pero deja el dominio', () {
      final r = LogService.redactar('login fallido para juan.perez@gmail.com');
      expect(r, isNot(contains('juan.perez')));
      expect(r, contains('gmail.com'));
    });

    test('quita la clave publicable horneada en la build', () {
      if (AppConfig.supabaseAnonKey.isEmpty) return;
      final r = LogService.redactar('apikey usada: ${AppConfig.supabaseAnonKey}');
      expect(r, isNot(contains(AppConfig.supabaseAnonKey)));
    });

    test('no destroza un texto normal', () {
      const texto = 'No se pudo subir el archivo (413).';
      expect(LogService.redactar(texto), texto);
    });
  });
}
