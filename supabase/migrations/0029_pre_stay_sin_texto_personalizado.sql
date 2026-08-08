-- ===============================================================
-- 0029_pre_stay_sin_texto_personalizado.sql
--
-- La pestaña "Mis notificaciones" pasó a ser "Soporte" y con ella desapareció
-- el campo de texto personalizado por usuario. El marcador {{CustomText}} de
-- la plantilla PRE_STAY se rellenaba desde notification_settings.custom_text,
-- que ahora nadie puede escribir: quedaría siempre vacío y dejaría un párrafo
-- en blanco al final del correo.
--
-- El recordatorio en sí NO se toca y sigue ACTIVO para todo el mundo:
-- send-email solo lo omite si existe una fila con is_active = false, y al
-- retirar la interfaz ya no se pueden crear filas nuevas.
--
-- El WHERE protege una edición manual: si alguien ya cambió la plantilla desde
-- la app, esta migración no le pisa el texto.
-- ===============================================================

update public.notification_templates
   set body = '<div style=''font-family:sans-serif''><h2>Tu estancia se acerca</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> empieza el {{StartDate}}.</p></div>'
 where type = 'PRE_STAY'
   and body = '<div style=''font-family:sans-serif''><h2>Tu estancia se acerca</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> empieza el {{StartDate}}.</p><p>{{CustomText}}</p></div>';
