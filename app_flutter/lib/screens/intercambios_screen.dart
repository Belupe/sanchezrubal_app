import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reservation_swap.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';

class IntercambiosScreen extends StatefulWidget {
  const IntercambiosScreen({super.key});

  @override
  State<IntercambiosScreen> createState() => _IntercambiosScreenState();
}

class _IntercambiosScreenState extends State<IntercambiosScreen> {
  List<ReservationSwap> _swaps = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await DataService.mySwaps();
      if (!mounted) return;
      setState(() {
        _swaps = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e, fallback: 'No se pudieron cargar los intercambios.');
        _loading = false;
      });
    }
  }

  Future<void> _respond(ReservationSwap s, bool accept) async {
    setState(() => _busy = true);
    try {
      await DataService.respondSwap(s.id, accept);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept ? 'Intercambio aceptado.' : 'Intercambio rechazado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo responder.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _load, child: const Text('Reintentar')),
          ]),
        ),
      );
    }

    final uid = DataService.uid;
    final entrantes = _swaps
        .where((s) => s.status == 'pending' && s.targetId == uid)
        .toList();
    final salientes = _swaps
        .where((s) => s.status == 'pending' && s.proposerId == uid)
        .toList();
    final historial = _swaps.where((s) => s.status != 'pending').toList();

    if (_swaps.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No tienes intercambios.\n\nPuedes proponer uno desde el detalle de una reserva tuya.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (entrantes.isNotEmpty) ...[
            _Titulo('Te proponen (${entrantes.length})'),
            ...entrantes.map((s) => _SwapCard(swap: s, entrante: true, busy: _busy,
                onAccept: () => _respond(s, true), onReject: () => _respond(s, false))),
          ],
          if (salientes.isNotEmpty) ...[
            _Titulo('Has propuesto (${salientes.length})'),
            ...salientes.map((s) => _SwapCard(swap: s, entrante: false, busy: _busy)),
          ],
          if (historial.isNotEmpty) ...[
            const _Titulo('Historial'),
            ...historial.map((s) => _SwapCard(swap: s, entrante: s.targetId == uid, busy: _busy)),
          ],
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(texto, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _SwapCard extends StatelessWidget {
  final ReservationSwap swap;
  final bool entrante;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  const _SwapCard({
    required this.swap,
    required this.entrante,
    required this.busy,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM', 'es');
    final otro = entrante ? (swap.proposerName ?? 'Alguien') : (swap.targetName ?? 'Alguien');

    // Desde el punto de vista de quien mira: lo que "recibe" y lo que "da".
    // Al proponente: da su oferta, recibe lo que pide. Al objetivo, al revés.
    final recibe = entrante
        ? '${swap.offerPropertyName ?? 'una casa'} · ${df.format(swap.offerStart)}–${df.format(swap.offerEnd)}'
        : '${swap.wantPropertyName ?? 'una casa'} · ${df.format(swap.wantStart)}–${df.format(swap.wantEnd)}';
    final da = entrante
        ? '${swap.wantPropertyName ?? 'una casa'} · ${df.format(swap.wantStart)}–${df.format(swap.wantEnd)}'
        : '${swap.offerPropertyName ?? 'una casa'} · ${df.format(swap.offerStart)}–${df.format(swap.offerEnd)}';

    final estado = switch (swap.status) {
      'accepted' => ('Aceptado', Colors.green),
      'rejected' => ('Rechazado', Colors.red),
      'cancelled' => ('Cancelado', Colors.grey),
      _ => (entrante ? 'Pendiente de tu respuesta' : 'Esperando respuesta', Colors.orange),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.swap_horiz, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Con $otro',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(estado.$1, style: TextStyle(color: estado.$2, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            _Fila(icon: Icons.arrow_downward, label: 'Recibes', valor: recibe),
            const SizedBox(height: 4),
            _Fila(icon: Icons.arrow_upward, label: 'Das', valor: da),
            if (entrante && swap.status == 'pending') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: const Text('Aceptar'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valor;
  const _Fila({required this.icon, required this.label, required this.valor});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 6),
        SizedBox(width: 58, child: Text(label, style: TextStyle(color: Theme.of(context).hintColor))),
        Expanded(child: Text(valor)),
      ]);
}
