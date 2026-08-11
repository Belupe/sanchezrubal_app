// Suscripciones en tiempo real (cambios de reservas).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

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
