import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Pantalla de actualización de Windows. Se abre sola al detectar una versión
/// nueva y **se actualiza sola**: descarga el instalador, verifica su firma
/// SHA-256 y lo lanza (la app se cierra y el instalador la relanza).
class UpdateScreen extends StatefulWidget {
  final UpdateInfo info;
  const UpdateScreen({super.key, required this.info});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  double _progress = 0;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    // Auto-arranca la actualización al abrirse la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    final err = await UpdateService.downloadVerifyInstall(
      widget.info,
      (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    // Si va bien, la app ya se ha cerrado dentro de downloadVerifyInstall.
    if (err != null && mounted) {
      setState(() {
        _error = err;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);
    // Bloquea "atrás" mientras instala o si es obligatoria; si falla y no es
    // obligatoria, se puede cerrar y seguir usando la versión actual.
    final canLeave = !_busy && (_error != null) && !info.mandatory;

    return PopScope(
      canPop: canLeave,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.system_update, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Actualizando Portal Familia'
                    '${info.versionName.isNotEmpty ? ' a ${info.versionName}' : ''}',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (info.notes.isNotEmpty) ...[
                    Text(info.notes, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                  ],
                  if (_error == null) ...[
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                    const SizedBox(height: 12),
                    Text(
                      _progress > 0
                          ? 'Descargando… ${(_progress * 100).toStringAsFixed(0)} %'
                          : 'Preparando la actualización…',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'La app se cerrará y se reabrirá sola al terminar.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!info.mandatory)
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Ahora no'),
                          ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
