import '../services/log_service.dart';

String friendlyError(Object error,
    {String fallback = 'No se pudo completar la operación. Inténtalo de nuevo.'}) {
  LogService.error(error, StackTrace.current, 'backend');
  return fallback;
}
