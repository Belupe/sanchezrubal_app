import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mfa_service.dart';

/// [M-11] Pantalla para activar / desactivar la verificación en dos pasos (2FA)
/// por TOTP. Es opcional para cada usuario.
class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key});

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  late Future<List<Factor>> _future;

  // Estado del alta en curso (null = no estamos dando de alta).
  AuthMFAEnrollResponse? _enrolling;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = MfaService.verifiedTotpFactors();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _enrolling = null;
      _error = null;
      _code.clear();
      _future = MfaService.verifiedTotpFactors();
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _startEnroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await MfaService.enrollTotp();
      setState(() => _enrolling = res);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo iniciar la activación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnroll() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Introduce el código de 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MfaService.confirmTotp(_enrolling!.id, code);
      _snack('Verificación en dos pasos activada.');
      _reload();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'El código no es válido. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelEnroll() async {
    // Deshace el factor sin verificar que se acaba de crear.
    final id = _enrolling?.id;
    setState(() => _busy = true);
    try {
      if (id != null) await MfaService.unenroll(id);
    } catch (_) {/* si falla, el propio alta lo limpia la próxima vez */}
    if (mounted) {
      setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _disable(Factor f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar 2FA'),
        content: const Text(
            '¿Seguro que quieres desactivar la verificación en dos pasos? '
            'Volverás a entrar solo con tu contraseña.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desactivar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await MfaService.unenroll(f.id);
      _snack('Verificación en dos pasos desactivada.');
      _reload();
    } on AuthException catch (e) {
      _snack('Error: ${e.message}');
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      _snack('No se pudo desactivar.');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: FutureBuilder<List<Factor>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text('No se pudo cargar el estado de 2FA:\n${snap.error}',
                      textAlign: TextAlign.center)),
            );
          }
          final factors = snap.data ?? [];
          if (_enrolling != null) return _buildEnroll();
          if (factors.isNotEmpty) return _buildActive(factors);
          return _buildInactive();
        },
      ),
    );
  }

  Widget _buildInactive() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.verified_user_outlined, size: 56),
        const SizedBox(height: 12),
        Text('Añade una capa extra de seguridad',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text(
          'Con la verificación en dos pasos, además de tu contraseña necesitarás '
          'un código temporal de una app de autenticación (Google Authenticator, '
          'Authy, Microsoft Authenticator…) para entrar. Es opcional.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _startEnroll,
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_outline),
          label: const Text('Activar verificación en dos pasos'),
        ),
      ],
    );
  }

  Widget _buildActive(List<Factor> factors) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const ListTile(
            leading: Icon(Icons.verified_user),
            title: Text('Verificación en dos pasos ACTIVADA'),
            subtitle: Text(
                'Al entrar te pediremos un código de tu app de autenticación.'),
          ),
        ),
        const SizedBox(height: 8),
        for (final f in factors)
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(f.friendlyName?.isNotEmpty == true
                ? f.friendlyName!
                : 'App de autenticación'),
            subtitle: const Text('Activo'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _disable(f),
              child: const Text('Desactivar'),
            ),
          ),
      ],
    );
  }

  Widget _buildEnroll() {
    final totp = _enrolling!.totp!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('1) Añade la cuenta en tu app de autenticación',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Abre tu app de autenticación (Google Authenticator, Authy…), elige '
          '"Introducir una clave de configuración" y pega esta clave:',
        ),
        const SizedBox(height: 12),
        _CopyField(label: 'Clave de configuración', value: totp.secret),
        const SizedBox(height: 8),
        _CopyField(label: 'Enlace (otpauth) — alternativa', value: totp.uri),
        const SizedBox(height: 20),
        Text('2) Escribe el código que aparece en la app',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Código de 6 dígitos',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _cancelEnroll,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _confirmEnroll,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verificar y activar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Campo de solo lectura con botón de copiar.
class _CopyField extends StatelessWidget {
  final String label;
  final String value;
  const _CopyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copiar',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copiado al portapapeles.')));
          },
        ),
      ),
      child: SelectableText(value,
          style: const TextStyle(fontFamily: 'monospace')),
    );
  }
}
