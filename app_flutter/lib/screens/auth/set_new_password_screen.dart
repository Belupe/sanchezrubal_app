import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../utils/password_policy.dart';
import '../../widgets/password_widgets.dart';

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

  bool get _todoBien =>
      PasswordPolicy.cumple(_password.text) && _password.text == _confirm.text;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass = _password.text;

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
    await supabase.auth.signOut();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
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
                  PasswordField(
                    controller: _password,
                    label: 'Nueva contraseña',
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirm,
                    label: 'Repite la contraseña',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _loading || !_todoBien ? null : _save(),
                  ),
                  const SizedBox(height: 12),
                  PasswordChecklist(
                      password: _password.text, confirm: _confirm.text),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading || !_todoBien ? null : _save,
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
