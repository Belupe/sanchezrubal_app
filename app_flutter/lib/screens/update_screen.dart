import 'package:flutter/material.dart';

import '../services/update_service.dart';

class UpdateScreen extends StatefulWidget {
  final UpdateInfo info;
  const UpdateScreen({super.key, required this.info});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  double _progress = 0;
  String? _error;
  late bool _busy = widget.info.puedeInstalarSola;

  @override
  void initState() {
    super.initState();

    if (widget.info.puedeInstalarSola) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
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

    if (err != null && mounted) {
      setState(() {
        _error = err;
        _busy = false;
      });
    }
  }

  Future<void> _abrirWeb() async {
    await UpdateService.abrirPaginaDeDescargas();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);

    final canLeave = !_busy && !info.mandatory;
    final soloAvisa = !info.puedeInstalarSola;

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
                  Icon(Icons.system_update,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    soloAvisa
                        ? 'Hay una versión nueva'
                            '${info.versionName.isNotEmpty ? ' (${info.versionName})' : ''}'
                        : 'Actualizando Portal Familia'
                            '${info.versionName.isNotEmpty ? ' a ${info.versionName}' : ''}',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (info.notes.isNotEmpty) ...[
                    Text(info.notes, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                  ],
                  if (soloAvisa) ...[
                    Text(
                      'Esta copia no se puede actualizar sola. Descarga la '
                      'versión nueva desde la página e instálala encima.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
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
                          onPressed: _abrirWeb,
                          icon: const Icon(Icons.download),
                          label: const Text('Descargar'),
                        ),
                      ],
                    ),
                  ] else if (_error == null) ...[
                    LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null),
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
                    if (info.pideContrasena) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Está instalada para todos los usuarios del equipo, así '
                        'que al terminar la descarga tu escritorio te pedirá la '
                        'contraseña de administrador.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ] else ...[
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
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
                        TextButton.icon(
                          onPressed: _abrirWeb,
                          icon: const Icon(Icons.public),
                          label: const Text('Abrir la web'),
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
