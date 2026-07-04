import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// [M-11] Verificación en dos pasos (2FA) por TOTP, sobre la API `auth.mfa` de
/// Supabase. Es OPCIONAL: quien no active un factor no nota ningún cambio.
///
/// Flujo:
///  - `enrollTotp()` crea un factor SIN verificar y devuelve la clave/URI para
///    la app de autenticación (Google Authenticator, etc.).
///  - `confirmTotp()` valida el primer código y deja el factor verificado.
///  - En el login, si la cuenta tiene un factor verificado, la sesión queda en
///    AAL1 y hay que completar el desafío (`verifyChallenge`) para llegar a AAL2.
class MfaService {
  /// Factores TOTP ya verificados (los que "cuentan" como 2FA activa).
  static Future<List<Factor>> verifiedTotpFactors() async {
    final res = await supabase.auth.mfa.listFactors();
    return res.totp.where((f) => f.status == FactorStatus.verified).toList();
  }

  /// ¿La cuenta tiene 2FA (TOTP verificado) activada?
  static Future<bool> hasVerifiedTotp() async =>
      (await verifiedTotpFactors()).isNotEmpty;

  /// Inicia el alta de un factor TOTP. Antes limpia posibles intentos previos
  /// SIN verificar (evita acumular factores huérfanos y choques de nombre).
  static Future<AuthMFAEnrollResponse> enrollTotp() async {
    final existing = await supabase.auth.mfa.listFactors();
    for (final f in existing.totp) {
      if (f.status != FactorStatus.verified) {
        await supabase.auth.mfa.unenroll(f.id);
      }
    }
    return supabase.auth.mfa.enroll(factorType: FactorType.totp);
  }

  /// Confirma el alta verificando el primer código de la app de autenticación.
  /// Lanza [AuthException] si el código es incorrecto.
  static Future<void> confirmTotp(String factorId, String code) async {
    await supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  /// Desactiva un factor (quita la 2FA de esa cuenta).
  static Future<void> unenroll(String factorId) async {
    await supabase.auth.mfa.unenroll(factorId);
  }

  /// ¿La sesión actual necesita completar el desafío de 2FA? (AAL1 con un
  /// factor verificado disponible -> debe subir a AAL2).
  static bool needsChallenge() {
    final aal = supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  /// Id del primer factor TOTP verificado (para lanzar el desafío en el login).
  static Future<String?> firstVerifiedFactorId() async {
    final factors = await verifiedTotpFactors();
    return factors.isEmpty ? null : factors.first.id;
  }

  /// Completa el desafío de login con el código de la app de autenticación.
  /// Al verificar, la sesión pasa a AAL2 y `onAuthStateChange` se dispara.
  /// Lanza [AuthException] si el código es incorrecto.
  static Future<void> verifyChallenge(String factorId, String code) async {
    await supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }
}
