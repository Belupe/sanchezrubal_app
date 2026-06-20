import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../main.dart';
import '../models/property.dart';
import '../models/reservation.dart';
import '../models/waitlist_entry.dart';
import '../services/data_service.dart';
import '../services/realtime_service.dart';
import '../utils/colors.dart';
import 'registros_screen.dart';
import 'reservation_detail.dart';
import 'reservation_form.dart';

/// Calendario individual de un domicilio: cada familia con su color, leyenda
/// lateral y clic en una reserva para ver toda su información.
class PropertyCalendarScreen extends StatefulWidget {
  final Property property;
  const PropertyCalendarScreen({super.key, required this.property});

  @override
  State<PropertyCalendarScreen> createState() => _PropertyCalendarScreenState();
}

class _PropertyCalendarScreenState extends State<PropertyCalendarScreen> {
  List<Reservation> _all = [];
  List<WaitlistEntry> _waitlist = [];
  bool _loading = true;
  String? _error;
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime: reservas y cola de ESTE domicilio se actualizan solas.
    _channel = subscribeTables(
      'property_${widget.property.id}',
      ['reservations', 'reservation_waitlist'],
      () { if (mounted) _load(); },
    );
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) supabase.removeChannel(ch);
    super.dispose();
  }

  DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DataService.reservationsForProperty(widget.property.id);
      final waitlist = await DataService.waitlistForProperty(widget.property.id);
      if (!mounted) return;
      setState(() {
        _all = data;
        _waitlist = waitlist;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las reservas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelWaitlist(WaitlistEntry w) async {
    try {
      await DataService.cancelWaitlistEntry(w.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Has salido de la lista de espera.')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Color _colorOf(Reservation r) => r.isMaintenance
      ? Colors.orange
      : (r.familyColor != null ? colorFromHex(r.familyColor!) : Colors.blueGrey);

  String _nameOf(Reservation r) => r.isMaintenance
      ? 'Mantenimiento'
      : (r.familyGroupName ?? 'Reserva');

  List<Reservation> _forDay(DateTime day) {
    final d = _d(day);
    return _all
        .where((r) => !d.isBefore(_d(r.startDate)) && !d.isAfter(_d(r.endDate)))
        .toList();
  }

  /// Celda de día: si hay reserva, se pinta del color de la familia
  /// (un bloque de N días se ve como una franja de color).
  Widget _dayCell(DateTime day,
      {bool selected = false, bool today = false, bool outside = false}) {
    final items = _forDay(day);
    final res = items.isNotEmpty ? _colorOf(items.first) : null;
    final cs = Theme.of(context).colorScheme;
    final Color? bg = selected ? cs.primary : res;
    final Color? fg = bg != null
        ? (bg.computeLuminance() > 0.55 ? Colors.black : Colors.white)
        : (outside ? Theme.of(context).disabledColor : null);
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: today && bg == null
            ? Border.all(color: cs.primary, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: fg,
          fontWeight: (today || selected) ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Leyenda: familias (o mantenimiento) presentes, con su color, sin repetir.
  List<MapEntry<String, Color>> _legend() {
    final map = <String, Color>{};
    for (final r in _all) {
      map.putIfAbsent(_nameOf(r), () => _colorOf(r));
    }
    return map.entries.toList();
  }

  Future<void> _newReservation() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ReservationForm(property: widget.property, initialDay: _selected),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.property.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Registros',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Registros')),
                body: const RegistrosScreen(),
              ),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newReservation,
        icon: const Icon(Icons.add),
        label: const Text('Reservar'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }

    final df = DateFormat('d MMM', 'es');
    final dayItems = _forDay(_selected);
    final legend = _legend();

    return ListView(
      children: [
        TableCalendar<Reservation>(
          locale: 'es',
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2035, 12, 31),
          focusedDay: _focused,
          selectedDayPredicate: (d) => isSameDay(d, _selected),
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarFormat: CalendarFormat.month,
          rowHeight: 64,
          daysOfWeekHeight: 28,
          availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
          headerStyle: const HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          onDaySelected: (sel, foc) => setState(() {
            _selected = sel;
            _focused = foc;
          }),
          calendarBuilders: CalendarBuilders<Reservation>(
            defaultBuilder: (c, day, foc) => _dayCell(day),
            outsideBuilder: (c, day, foc) => _dayCell(day, outside: true),
            todayBuilder: (c, day, foc) => _dayCell(day, today: true),
            selectedBuilder: (c, day, foc) => _dayCell(day, selected: true),
          ),
        ),
        const Divider(height: 1),

        // Leyenda color → familia
        if (legend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: legend
                  .map((e) => Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(backgroundColor: e.value, radius: 8),
                        label: Text(e.key),
                      ))
                  .toList(),
            ),
          ),
        const Divider(height: 1),

        // Reservas del día seleccionado
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Reservas del ${DateFormat('d MMMM', 'es').format(_selected)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (dayItems.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Sin reservas este día')),
          )
        else
          ...dayItems.map((r) => ListTile(
                leading: CircleAvatar(backgroundColor: _colorOf(r), radius: 10),
                title: Text(_nameOf(r)),
                subtitle: Text(
                    '${df.format(r.startDate)} → ${df.format(r.endDate)} · ${r.guestCount} pers.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showReservationDetail(context, r, _load),
              )),

        // Lista de espera (cola) del domicilio
        if (_waitlist.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Lista de espera',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          ..._waitlist.asMap().entries.map((e) {
            final pos = e.key + 1; // posición FIFO en la cola
            final w = e.value;
            final mine = w.requestedById == DataService.uid;
            return ListTile(
              leading: CircleAvatar(
                radius: 14,
                child: Text('$pos', style: const TextStyle(fontSize: 13)),
              ),
              title: Text(mine ? 'Tú' : (w.requesterName ?? 'En espera')),
              subtitle: Text(
                  '${df.format(w.startDate)} → ${df.format(w.endDate)} · ${w.guestCount} pers.'),
              trailing: mine
                  ? IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      tooltip: 'Salir de la lista',
                      onPressed: () => _cancelWaitlist(w),
                    )
                  : null,
            );
          }),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}
