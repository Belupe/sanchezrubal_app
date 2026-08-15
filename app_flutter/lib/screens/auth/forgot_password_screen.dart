import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _msg;
  bool _ok = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _msg = null;
    });
    try {
      await supabase.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: 'portalfamilia://reset-password',
      );
      setState(() {
        _ok = true;
        _msg = 'Si el correo existe, te hemos enviado un enlace para '
            'restablecer la contraseña.';
      });
    } on AuthException catch (e) {
      setState(() => _msg = e.message);
    } catch (_) {
      setState(() => _msg = 'No se pudo enviar el correo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Introduce tu correo y te enviaremos un enlace '
                    'para crear una nueva contraseña.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_msg != null) ...[
                  const SizedBox(height: 12),
                  Text(_msg!,
                      style: TextStyle(
                          color: _ok ? Colors.green : Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _send,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enviar enlace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
