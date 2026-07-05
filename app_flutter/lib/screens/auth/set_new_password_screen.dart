import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart';
import '../../utils/password_policy.dart';

/// [2M-04] Pantalla OBLIGATORIA tras abrir el enlace de recuperación. La sesión
/// de recuperación NO da acceso a la app hasta fijar una contraseña nueva: esta
/// pantalla bloquea el resto (no hay "atrás") y solo al guardar con éxito llama
/// a [onDone] para que el AuthGate deje entrar.
class SetNewPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetNewPasswordScreen({super.key, required this.onDone});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass = _password.text;
    // [M-13] Espejo de la política del servidor (mínimo 10, no solo dígitos).
    final err = PasswordPolicy.validate(pass);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await supabase.auth.updateUser(UserAttributes(password: pass));
      widget.onDone();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo actualizar la contraseña.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    // Salir de la recuperación = cerrar la sesión de recuperación y volver al login.
    await supabase.auth.signOut();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    // Bloquea el gesto "atrás": la única salida es guardar o cancelar (logout).
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nueva contraseña'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Crea una contraseña nueva para tu cuenta.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nueva contraseña',
                      helperText: PasswordPolicy.helpText,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    onSubmitted: (_) => _loading ? null : _save(),
                    decoration: const InputDecoration(
                      labelText: 'Repite la contraseña',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Guardar contraseña'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : _cancel,
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
