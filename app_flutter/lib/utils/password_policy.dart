/// [M-13] Política de contraseñas del CLIENTE (espejo/UX, no autoridad).
///
/// La autoridad real es Supabase Auth (GoTrue), configurada en
/// supabase/config.toml (minimum_password_length = 10, password_requirements y
/// "Prevent use of leaked passwords" en el Dashboard). Esta validación local
/// solo evita viajes inútiles al servidor y da un mensaje claro antes de
/// llamarlo; es intencionadamente MÁS PERMISIVA (nunca bloquea algo que el
/// servidor sí aceptaría).
class PasswordPolicy {
  /// Longitud mínima. Invariante de seguridad alineado con el servidor → vive en
  /// código (no en .env ni system_config).
  static const int minLength = 10;

  static const String helpText =
      'Mínimo 10 caracteres. Evita usar solo números: combina letras y números '
      'para que sea más segura.';

  /// Mensaje de error si no cumple el mínimo del cliente, o null si es aceptable.
  static String? validate(String? password) {
    final p = password ?? '';
    if (p.length < minLength) {
      return 'La contraseña debe tener al menos $minLength caracteres.';
    }
    if (RegExp(r'^\d+$').hasMatch(p)) {
      return 'La contraseña no puede ser solo números; añade alguna letra.';
    }
    return null;
  }
}
