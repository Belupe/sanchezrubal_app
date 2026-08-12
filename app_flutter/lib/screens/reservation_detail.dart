import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/profile.dart';
import '../models/reservation.dart';
import '../services/data_service.dart';
import '../utils/errors.dart';
import 'inspection_screen.dart';

Future<void> showReservationDetail(
    BuildContext context, Reservation r, VoidCallback onChanged) async {
  final role = await DataService.currentRole();
  final profile = await DataService.myProfile();
  final uid = DataService.uid;
  final isPrincipal = role == 'MEGA_ADMIN' || role == 'PRINCIPAL_ADMIN';

  final groupRole = profile?['group_role'] as String?;
  final isGroupAdmin = isPrincipal ||
      ((groupRole == 'FAMILY_ADMIN' || groupRole == 'FAMILY_SECOND_ADMIN') &&
          profile?['family_group_id'] == r.familyGroupId);
  final isCreator = r.createdById == uid;

  Reservation full = r;
  if (isCreator || isGroupAdmin) {
    final fetched = await DataService.reservationById(r.id);
    if (fetched != null) full = fetched;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ReservationDetailSheet(
        r: full,
        canEditDates: isGroupAdmin,
        canEditDetails: isCreator || isGroupAdmin,
        canDelete: isCreator || isGroupAdmin,
        canFix: isGroupAdmin,
        isOwner: isCreator,
        onChanged: onChanged,
      ),
    ),
  );
}

class _ReservationDetailSheet extends StatefulWidget {
  final Reservation r;
  final bool canEditDates;
  final bool canEditDetails;
  final bool canDelete;
  final bool canFix;
  final bool isOwner;
  final VoidCallback onChanged;

  const _ReservationDetailSheet({
    required this.r,
    required this.canEditDates,
    required this.canEditDetails,
    required this.canDelete,
    required this.canFix,
    required this.isOwner,
    required this.onChanged,
  });

  @override
  State<_ReservationDetailSheet> createState() => _ReservationDetailSheetState();
}

class _ReservationDetailSheetState extends State<_ReservationDetailSheet> {
  late int _guests = widget.r.guestCount;
  late final _notes = TextEditingController(text: widget.r.notes ?? '');
  late DateTime _start = widget.r.startDate;
  late DateTime _end = widget.r.endDate;
  late bool _isFixed = widget.r.isFixed;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e,
                fallback: 'No se pudo completar la operación.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => start ? _start = picked : _end = picked);
    }
  }

  Future<void> _toggleFix(bool value) async {
    setState(() => _busy = true);
    try {
      await DataService.setReservationFixed(widget.r.id, value);
      if (mounted) setState(() => _isFixed = value);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo cambiar.'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _proposeSwap() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ProposeSwapSheet(reservation: widget.r),
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Propuesta enviada. La otra persona debe aceptarla.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy', 'es');
    final eur = NumberFormat.currency(locale: 'es', symbol: '€', decimalDigits: 2);
    final r = widget.r;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r.propertyName ?? 'Reserva',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(r.isMaintenance ? 'Bloqueo de mantenimiento' : 'Reserva familiar',
              style: TextStyle(color: Theme.of(context).hintColor)),
          if (_isFixed) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: Icon(Icons.push_pin, size: 16),
                label: Text('Reserva fija'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          if (!r.isMaintenance && (r.totalPrice ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.euro, size: 18),
              const SizedBox(width: 6),
              Text('${eur.format(r.totalPrice)}  ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('· ${r.nights} ${r.nights == 1 ? 'noche' : 'noches'} × '
                  '${eur.format(r.pricePerNight ?? 0)}',
                  style: TextStyle(color: Theme.of(context).hintColor)),
            ]),
          ],
          const Divider(height: 24),

          if (widget.canEditDates) ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(df.format(_start)),
                  onPressed: _busy ? null : () => _pick(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: Text(df.format(_end)),
                  onPressed: _busy ? null : () => _pick(false),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => DataService.updateReservationDates(r.id,
                            start: _start, end: _end),
                        'Fechas actualizadas.',
                      ),
              child: const Text('Guardar fechas'),
            ),
          ] else
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('${df.format(_start)} → ${df.format(_end)}'),
              subtitle: const Text('Solo un administrador puede cambiar las fechas'),
            ),

          const SizedBox(height: 8),

          if (widget.canEditDetails) ...[
            Row(children: [
              const Text('Personas'),
              const Spacer(),
              IconButton(
                onPressed:
                    _busy || _guests <= 1 ? null : () => setState(() => _guests--),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_guests', style: const TextStyle(fontSize: 18)),
              IconButton(
                onPressed: _busy ? null : () => setState(() => _guests++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Comentarios', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => DataService.updateReservationDetails(r.id,
                            guestCount: _guests,
                            notes: _notes.text.trim().isEmpty
                                ? null
                                : _notes.text.trim()),
                        'Reserva actualizada.',
                      ),
              child: const Text('Guardar personas y comentarios'),
            ),
          ],

          if (widget.canEditDetails) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Inspección de salida'),
              onPressed: _busy
                  ? null
                  : () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(MaterialPageRoute(
                        builder: (_) =>
                            InspectionScreen(reservationId: widget.r.id),
                      ));
                    },
            ),
          ],

          if (widget.isOwner && !r.isMaintenance) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Proponer intercambio'),
              onPressed: _busy ? null : _proposeSwap,
            ),
          ],

          if (widget.canFix && !r.isMaintenance) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.push_pin_outlined),
              title: const Text('Reserva fija'),
              subtitle: const Text(
                  'Solo se puede mover por intercambio; el dueño no la cancela.'),
              value: _isFixed,
              onChanged: _busy ? null : _toggleFix,
            ),
          ],

          if (widget.canDelete && !(_isFixed && !widget.canFix)) ...[
            const Divider(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Cancelar y eliminar reserva'),
              onPressed: _busy
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Eliminar reserva'),
                          content: const Text('¿Seguro que quieres eliminarla?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('No')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Sí, eliminar')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        _run(() => DataService.deleteReservation(r.id),
                            'Reserva eliminada.');
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class _ProposeSwapSheet extends StatefulWidget {
  final Reservation reservation;
  const _ProposeSwapSheet({required this.reservation});

  @override
  State<_ProposeSwapSheet> createState() => _ProposeSwapSheetState();
}

class _ProposeSwapSheetState extends State<_ProposeSwapSheet> {
  late DateTime _offerStart = _day(widget.reservation.startDate);
  late DateTime _offerEnd = _day(widget.reservation.endDate);

  List<Profile> _people = [];
  Profile? _person;
  List<Reservation> _personRes = [];
  Reservation? _wantRes;
  DateTime? _wantStart;
  DateTime? _wantEnd;

  bool _loading = true;
  bool _loadingRes = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final people = await DataService.allProfiles();
    if (!mounted) return;
    setState(() {
      _people = people.where((p) => p.id != DataService.uid).toList();
      _loading = false;
    });
  }

  Future<void> _pickPerson() async {
    final chosen = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PersonPicker(people: _people),
    );
    if (chosen == null) return;
    setState(() {
      _person = chosen;
      _wantRes = null;
      _wantStart = null;
      _wantEnd = null;
      _personRes = [];
      _loadingRes = true;
      _error = null;
    });
    final res = await DataService.reservationsByPerson(chosen.id);
    if (!mounted) return;
    setState(() {
      _personRes = res;
      _loadingRes = false;
    });
  }

  void _pickWantReservation(Reservation r) {
    setState(() {
      _wantRes = r;
      _wantStart = _day(r.startDate);
      _wantEnd = _day(r.endDate);
    });
  }

  Future<void> _submit() async {
    if (_wantRes == null || _wantStart == null || _wantEnd == null) {
      setState(() => _error = 'Elige la reserva de la otra persona.');
      return;
    }
    if (!_offerEnd.isAfter(_offerStart) || !_wantEnd!.isAfter(_wantStart!)) {
      setState(() => _error = 'Los tramos deben tener al menos una noche.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DataService.proposeSwap(
        offerProperty: widget.reservation.propertyId,
        offerStart: _offerStart,
        offerEnd: _offerEnd,
        wantProperty: _wantRes!.propertyId,
        wantStart: _wantStart!,
        wantEnd: _wantEnd!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error =
          friendlyError(e, fallback: 'No se pudo proponer el intercambio.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final hint = Theme.of(context).hintColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Proponer intercambio',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Text('Ofreces · ${r.propertyName ?? 'tu casa'}',
                    style: Theme.of(context).textTheme.titleSmall),
                Text('Arrastra para elegir qué tramo de tu reserva das',
                    style: TextStyle(color: hint, fontSize: 12)),
                const SizedBox(height: 10),
                _DragRangeBar(
                  rangeStart: _day(r.startDate),
                  rangeEnd: _day(r.endDate),
                  selStart: _offerStart,
                  selEnd: _offerEnd,
                  onChanged: (a, b) => setState(() {
                    _offerStart = a;
                    _offerEnd = b;
                  }),
                ),
                const Divider(height: 32),
                Text('Quieres · con quién',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_search),
                  label: Text(_person?.name ?? 'Buscar persona'),
                  onPressed: _saving ? null : _pickPerson,
                ),
                if (_loadingRes) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ] else if (_person != null && _personRes.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text('${_person!.name} no tiene reservas próximas.',
                      style: TextStyle(color: hint)),
                ] else if (_person != null) ...[
                  const SizedBox(height: 12),
                  Text('Elige su reserva', style: TextStyle(color: hint, fontSize: 12)),
                  const SizedBox(height: 6),
                  ..._personRes.map((res) => _ResChoice(
                        res: res,
                        selected: _wantRes?.id == res.id,
                        onTap: () => _pickWantReservation(res),
                      )),
                ],
                if (_wantRes != null) ...[
                  const SizedBox(height: 16),
                  Text('Arrastra para elegir qué tramo quieres',
                      style: TextStyle(color: hint, fontSize: 12)),
                  const SizedBox(height: 10),
                  _DragRangeBar(
                    rangeStart: _day(_wantRes!.startDate),
                    rangeEnd: _day(_wantRes!.endDate),
                    selStart: _wantStart!,
                    selEnd: _wantEnd!,
                    onChanged: (a, b) => setState(() {
                      _wantStart = a;
                      _wantEnd = b;
                    }),
                  ),
                  const SizedBox(height: 16),
                  _SwapSummary(
                    youGetProperty: _wantRes!.propertyName ?? 'una casa',
                    youGetStart: _wantStart!,
                    youGetEnd: _wantEnd!,
                    otherName: _person!.name,
                    otherGetProperty: r.propertyName ?? 'tu casa',
                    otherGetStart: _offerStart,
                    otherGetEnd: _offerEnd,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving || _wantRes == null ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enviar propuesta'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PersonPicker extends StatefulWidget {
  final List<Profile> people;
  const _PersonPicker({required this.people});

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.people
        .where((p) => p.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar persona',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView(
              shrinkWrap: true,
              children: filtered
                  .map((p) => ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(p.name),
                        subtitle: Text(p.roleLabel),
                        onTap: () => Navigator.pop(context, p),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResChoice extends StatelessWidget {
  final Reservation res;
  final bool selected;
  final VoidCallback onTap;
  const _ResChoice(
      {required this.res, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM', 'es');
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        leading: const Icon(Icons.home_outlined),
        title: Text(res.propertyName ?? 'Casa'),
        subtitle: Text('${df.format(res.startDate)} – ${df.format(res.endDate)}'),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: onTap,
      ),
    );
  }
}

class _SwapSummary extends StatelessWidget {
  final String youGetProperty;
  final DateTime youGetStart;
  final DateTime youGetEnd;
  final String otherName;
  final String otherGetProperty;
  final DateTime otherGetStart;
  final DateTime otherGetEnd;
  const _SwapSummary({
    required this.youGetProperty,
    required this.youGetStart,
    required this.youGetEnd,
    required this.otherName,
    required this.otherGetProperty,
    required this.otherGetStart,
    required this.otherGetEnd,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM', 'es');
    String span(DateTime a, DateTime b) => '${df.format(a)} – ${df.format(b)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.arrow_downward, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Tú recibes: $youGetProperty · '
                    '${span(youGetStart, youGetEnd)}')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.arrow_upward, size: 16, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
                child: Text('$otherName recibe: $otherGetProperty · '
                    '${span(otherGetStart, otherGetEnd)}')),
          ]),
        ],
      ),
    );
  }
}

class _DragRangeBar extends StatelessWidget {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime selStart;
  final DateTime selEnd;
  final void Function(DateTime start, DateTime end) onChanged;
  const _DragRangeBar({
    required this.rangeStart,
    required this.rangeEnd,
    required this.selStart,
    required this.selEnd,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final total = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day)
        .difference(DateTime(rangeStart.year, rangeStart.month, rangeStart.day))
        .inDays;
    final days = List.generate(
        total + 1,
        (i) => DateTime(rangeStart.year, rangeStart.month, rangeStart.day + i));
    final n = days.length;
    int idxOf(DateTime d) {
      for (var i = 0; i < n; i++) {
        if (days[i].year == d.year &&
            days[i].month == d.month &&
            days[i].day == d.day) {
          return i;
        }
      }
      return 0;
    }

    final selA = idxOf(selStart).clamp(0, n - 1);
    final selB = idxOf(selEnd).clamp(0, n - 1);
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('EEE d', 'es');

    void handle(double dx, double width, {int? anchor}) {
      final cellW = width / n;
      var idx = (dx / cellW).floor().clamp(0, n - 1);
      var a = anchor ?? selA;
      var lo = a < idx ? a : idx;
      var hi = a < idx ? idx : a;
      if (lo == hi) {
        if (hi < n - 1) {
          hi += 1;
        } else {
          lo -= 1;
        }
      }
      onChanged(days[lo], days[hi]);
    }

    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      int? anchor;
      return GestureDetector(
        onTapDown: (d) => handle(d.localPosition.dx, width),
        onHorizontalDragStart: (d) {
          final cellW = width / n;
          anchor = (d.localPosition.dx / cellW).floor().clamp(0, n - 1);
          handle(d.localPosition.dx, width, anchor: anchor);
        },
        onHorizontalDragUpdate: (d) =>
            handle(d.localPosition.dx, width, anchor: anchor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: List.generate(n, (i) {
                  final on = i >= selA && i <= selB;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: on ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text('${days[i].day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: on ? cs.onPrimary : cs.onSurfaceVariant,
                          )),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Text('${df.format(days[selA])} → ${df.format(days[selB])}  ·  '
                '${selB - selA} ${selB - selA == 1 ? 'noche' : 'noches'}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    });
  }
}
