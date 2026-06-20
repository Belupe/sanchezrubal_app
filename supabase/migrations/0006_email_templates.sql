-- ===============================================================
-- 0006_email_templates.sql — Extensiones de cron + plantillas de correo
-- ===============================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Plantillas editables por el admin desde la app. La Edge Function
-- send-email las usa (con fallback inline). Placeholders soportados:
-- {{PropertyName}} {{UserName}} {{StartDate}} {{EndDate}} {{FormLink}}
insert into public.notification_templates (type, subject, body) values
('RESERVATION_CONFIRMATION', 'Reserva confirmada — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva confirmada</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} está confirmada.</p></div>'),
('MAINTENANCE', 'Mantenimiento programado — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Mantenimiento</h2><p>Se ha bloqueado <b>{{PropertyName}}</b> por mantenimiento del {{StartDate}} al {{EndDate}}.</p></div>'),
('INSPECTION_REMINDER', 'Formulario de salida — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Formulario de salida</h2><p>Hola {{UserName}}, completa el formulario de salida de <b>{{PropertyName}}</b>: <a href=''{{FormLink}}''>Abrir formulario</a></p></div>')
on conflict (type) do nothing;
