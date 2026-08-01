import '../services/log_service.dart';

/// [2L-06] Devuelve un mensaje GENÉRICO para el usuario y loguea el detalle
/// real (que puede traer nombres de columnas/constraints/RLS de Postgres).
///
/// El detalle va además al registro de fallos (`Logs/sesion.log`), ya redactado
/// de credenciales, para poder diagnosticar después lo que el usuario solo vio
/// como "no se pudo completar la operación".
String friendlyError(Object error,
    {String fallback = 'No se pudo completar la operación. Inténtalo de nuevo.'}) {
  LogService.error(error, StackTrace.current, 'backend');
  return fallback;
}
