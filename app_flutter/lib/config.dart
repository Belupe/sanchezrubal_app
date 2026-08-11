// Configuración de compilación. Los valores por defecto son públicos (la
// seguridad la da el RLS). En la build de Google Play: ENABLE_SELF_UPDATE=false.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pjceyplciujtrnxptwbx.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_3pBEywFkB05ysg4MB_AeJw_JU7InPa7',
  );

  static const updateBaseUrl = String.fromEnvironment(
    'UPDATES_PUBLIC_URL',
    defaultValue: 'https://app.sanchezrubal.net',
  );

  static const enableSelfUpdate = bool.fromEnvironment(
    'ENABLE_SELF_UPDATE',
    defaultValue: true,
  );
}
