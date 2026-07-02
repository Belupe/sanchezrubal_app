/// Configuración de compilación. Los valores reales se inyectan con
/// --dart-define en build/run; los defaults (claves PÚBLICAS) permiten
/// ejecutar en desarrollo sin parámetros. La seguridad la da el RLS.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pjceyplciujtrnxptwbx.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3pBEywFkB05ysg4MB_AeJw_JU7InPa7',
  );

  /// URL pública del API S3 de MinIO (solo informativo en el cliente;
  /// las URLs reales las firma la Edge Function media-sign).
  static const mediaPublicUrl = String.fromEnvironment(
    'MEDIA_PUBLIC_URL',
    defaultValue: '',
  );

  /// Base pública del servidor de actualizaciones (sirve `<plataforma>/version.json`
  /// y el instalador). La usan Android y Windows para auto-actualizarse; iOS lo
  /// ignora (va por TestFlight). Mismo nombre que en el `.env` único.
  static const updateBaseUrl = String.fromEnvironment(
    'UPDATES_PUBLIC_URL',
    defaultValue: 'https://app.sanchezrubal.net',
  );

  /// Auto-actualización interna (descarga+instala el paquete de tu servidor).
  /// ACTIVA por defecto para el APK self-hosted y Windows. En la build de
  /// Google Play DEBE ir DESACTIVADA (--dart-define=ENABLE_SELF_UPDATE=false):
  /// Play no permite que la app se auto-actualice bajando APKs, y ya gestiona
  /// las updates por su cuenta. Ver docs/GOOGLE.md.
  static const enableSelfUpdate = bool.fromEnvironment(
    'ENABLE_SELF_UPDATE',
    defaultValue: true,
  );
}
