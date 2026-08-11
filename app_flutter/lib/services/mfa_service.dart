// Segundo factor (TOTP).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class MfaService {
  static Future<List<Factor>> verifiedTotpFactors() async {
    final res = await supabase.auth.mfa.listFactors();
    return res.totp.where((f) => f.status == FactorStatus.verified).toList();
  }

  static Future<bool> hasVerifiedTotp() async =>
      (await verifiedTotpFactors()).isNotEmpty;

  static Future<AuthMFAEnrollResponse> enrollTotp() async {
    final existing = await supabase.auth.mfa.listFactors();
    for (final f in existing.totp) {
      if (f.status != FactorStatus.verified) {
        await supabase.auth.mfa.unenroll(f.id);
      }
    }
    return supabase.auth.mfa.enroll(factorType: FactorType.totp);
  }

  static Future<void> confirmTotp(String factorId, String code) async {
    await supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  static Future<void> unenroll(String factorId) async {
    await supabase.auth.mfa.unenroll(factorId);
  }

  static bool needsChallenge() {
    final aal = supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  static Future<String?> firstVerifiedFactorId() async {
    final factors = await verifiedTotpFactors();
    return factors.isEmpty ? null : factors.first.id;
  }

  static Future<void> verifyChallenge(String factorId, String code) async {
    await supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }
}
