import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  static Future<bool> pendiente() async {
    final sp = await SharedPreferences.getInstance();
    return !(sp.getBool('onboarding_visto') ?? false);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Pagina {
  final IconData icono;
  final String titulo;
  final String texto;
  const _Pagina(this.icono, this.titulo, this.texto);
}

const _paginas = [
  _Pagina(
    Icons.home_work_outlined,
    'Bienvenido a Portal Familia',
    'La app para organizar las estancias en las casas de la familia: '
        'calendario compartido, reservas y avisos, todo en un sitio.',
  ),
  _Pagina(
    Icons.calendar_month,
    'Reserva tus fechas',
    'Elige casa y fechas: una quincena entera o los días que quieras. '
        'Si el hueco está ocupado, apúntate a la lista de espera y te '
        'avisaremos si queda libre.',
  ),
  _Pagina(
    Icons.swap_horiz,
    'Intercambia con otros',
    '¿Os venís mejor otras fechas? Proponle un intercambio a quien las tenga: '
        'eliges qué das y qué recibes, y cuando acepte se cruzan solas.',
  ),
  _Pagina(
    Icons.notifications_active_outlined,
    'Siempre al día',
    'Recibirás avisos de reservas, colas e intercambios. En tu perfil puedes '
        'ajustar el tema y la accesibilidad a tu gusto.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _pagina = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _terminar() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('onboarding_visto', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ultima = _pagina == _paginas.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _terminar,
                child: const Text('Saltar'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _paginas.length,
                onPageChanged: (i) => setState(() => _pagina = i),
                itemBuilder: (context, i) {
                  final p = _paginas[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(p.icono, size: 96, color: cs.primary),
                        const SizedBox(height: 32),
                        Text(p.titulo,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        Text(p.texto,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _paginas.length,
                (i) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _pagina ? cs.primary : cs.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: ultima
                      ? _terminar
                      : () => _ctrl.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(ultima ? 'Empezar' : 'Siguiente'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
