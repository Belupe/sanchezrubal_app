import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// Helper de Supabase Realtime. Suscribe a los cambios (INSERT/UPDATE/DELETE)
/// de una o varias tablas y llama a [onChange] cada vez que algo cambia.
///
/// Patrón "señal de invalidación": en lugar de reconstruir el estado a partir
/// del payload (que no trae los joins de las queries), simplemente avisamos a
/// la pantalla para que re-ejecute su carga habitual con joins. Así el
/// calendario, la cola y los anuncios se actualizan solos en todos los
/// dispositivos abiertos.
///
/// Cierra el canal en `dispose` con `supabase.removeChannel(channel)`.
RealtimeChannel subscribeTables(
  String channelName,
  List<String> tables,
  void Function() onChange,
) {
  final channel = supabase.channel(channelName);
  for (final table in tables) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => onChange(),
    );
  }
  channel.subscribe();
  return channel;
}
