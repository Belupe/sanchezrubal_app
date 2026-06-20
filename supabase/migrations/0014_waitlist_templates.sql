-- ===============================================================
-- 0014_waitlist_templates.sql — Plantillas de email de la lista de espera
-- ===============================================================
-- Las usa la Edge Function notify-waitlist (con fallback inline). Se envían
-- las DOS al usuario promovido cuando alguien cancela y él hereda las fechas.
-- Placeholders: {{PropertyName}} {{UserName}} {{CancelledBy}} {{StartDate}} {{EndDate}}
-- ===============================================================
insert into public.notification_templates (type, subject, body) values
('WAITLIST_CANCELLED', 'Se ha liberado una reserva — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva cancelada</h2><p>Hola {{UserName}}, {{CancelledBy}} ha cancelado su reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}, fechas en las que estabas en lista de espera.</p></div>'),
('WAITLIST_PROMOTED', '¡Las fechas son tuyas! — {{PropertyName}}',
 '<div style=''font-family:sans-serif''><h2>Reserva asignada</h2><p>Hola {{UserName}}, como eras el siguiente en la lista de espera, <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} es ahora tuyo. La reserva ya está creada a tu nombre.</p></div>')
on conflict (type) do nothing;
