class PasswordPolicy {
  static const int minLength = 10;

  static const String helpText =
      'Mínimo 10 caracteres. Evita usar solo números: combina letras y números '
      'para que sea más segura.';

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
