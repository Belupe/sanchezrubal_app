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
}
