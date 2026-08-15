// Espejo de la política del servidor (Auth: mínimo 10, minúscula+mayúscula+número).
class PasswordPolicy {
  static const int minLength = 10;

  static List<(String, bool)> requisitos(String p) => [
        ('Al menos $minLength caracteres', p.length >= minLength),
        ('Una letra minúscula', RegExp(r'[a-z]').hasMatch(p)),
        ('Una letra mayúscula', RegExp(r'[A-Z]').hasMatch(p)),
        ('Un número', RegExp(r'[0-9]').hasMatch(p)),
      ];

  static bool cumple(String p) => requisitos(p).every((r) => r.$2);

  static String? validate(String? password) {
    final p = password ?? '';
    final fallo = requisitos(p).where((r) => !r.$2).toList();
    if (fallo.isEmpty) return null;
    return 'La contraseña necesita: ${fallo.map((r) => r.$1.toLowerCase()).join(', ')}.';
  }
}
