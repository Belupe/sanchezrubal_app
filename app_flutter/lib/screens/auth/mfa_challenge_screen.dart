import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../services/mfa_service.dart';

class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Introduce el código de 6 dígitos.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final factorId = await MfaService.firstVerifiedFactorId();
      if (factorId == null) {
        setState(() => _error = 'No hay ningún método de 2FA configurado.');
        return;
      }
      await MfaService.verifyChallenge(factorId, code);

    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'El código no es válido. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.verified_user, size: 56, color: Color(0xFF2563EB)),
                const SizedBox(height: 12),
                Text('Verificación en dos pasos',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'Escribe el código de 6 dígitos de tu app de autenticación.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  onSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _verify,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verificar'),
                  ),
                ),
                TextButton(
                  onPressed:
                      _loading ? null : () => supabase.auth.signOut(),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
