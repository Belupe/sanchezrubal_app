// ===============================================================
// send-email — Envía los correos PERSONALIZADOS de Portal Familia.
//   - reservation_confirmation  (la app lo llama tras crear reserva)
//   - maintenance               (la app lo llama tras bloquear mantenimiento)
//   - inspection_reminders      (pg_cron lo llama a diario)
// SMTP se lee de public.system_config (service role). Plantillas de
// public.notification_templates con fallback inline.
//
// Auth: o bien JWT de usuario (confirmación/mantenimiento) o bien la
// cabecera x-cron-secret == CRON_SECRET (recordatorios por cron).
//
// Secrets: CRON_SECRET. SUPABASE_URL/ANON/SERVICE_ROLE los inyecta Supabase.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// La config de Supabase se gestiona en /.env.example (sección Supabase).
// SUPABASE_URL/ANON/SERVICE_ROLE los inyecta Supabase en runtime; aquí solo se
// LEEN. No introduzcas credenciales en este fichero.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

// Esquema propio para que los enlaces de los correos ABRAN la app nativa
// (ya no hay web). Registrado en Android/Windows/iOS.
const APP_SCHEME = "portalfamilia://";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const PRINCIPAL = ["MEGA_ADMIN", "PRINCIPAL_ADMIN"];
const FAMILY_ADMIN = ["FAMILY_ADMIN", "FAMILY_SECOND_ADMIN"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const FALLBACK: Record<string, { subject: string; body: string }> = {
  RESERVATION_CONFIRMATION: {
    subject: "Reserva confirmada — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Reserva confirmada</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} está confirmada.</p></div>",
  },
  MAINTENANCE: {
    subject: "Mantenimiento programado — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Mantenimiento</h2><p>Se ha bloqueado <b>{{PropertyName}}</b> por mantenimiento del {{StartDate}} al {{EndDate}}.</p></div>",
  },
  INSPECTION_REMINDER: {
    subject: "Formulario de salida — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Formulario de salida</h2><p>Hola {{UserName}}, por favor completa el formulario de salida de <b>{{PropertyName}}</b> desde la app.</p><p><a href='{{FormLink}}' style='display:inline-block;background:#2563eb;color:#fff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:600'>Abrir Portal Familia</a></p></div>",
  },
};

function fill(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(vars[k] ?? "");
  return out;
}

async function getTemplate(type: string) {
  const { data } = await admin.from("notification_templates")
    .select("subject, body").eq("type", type).maybeSingle();
  return data ?? FALLBACK[type];
}

async function getSmtp() {
  const { data } = await admin.from("system_config").select("*").eq("id", "global").single();
  if (!data?.smtp_host || !data?.smtp_user) throw new Error("SMTP no configurado en system_config");
  return data;
}

async function sendMail(to: string[], subject: string, html: string) {
  const cfg = await getSmtp();
  const client = new SMTPClient({
    connection: {
      hostname: cfg.smtp_host,
      port: cfg.smtp_port ?? 587,
      tls: cfg.smtp_secure ?? false,
      auth: { username: cfg.smtp_user, password: cfg.smtp_pass ?? "" },
    },
  });
  for (const addr of to) {
    await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to: addr, subject, html });
  }
  await client.close();
}

function fmt(d: string) {
  return new Date(d).toLocaleDateString("es-ES");
}

async function handleReservation(reservationId: string, type: "RESERVATION_CONFIRMATION" | "MAINTENANCE") {
  const { data: r } = await admin.from("reservations")
    .select("start_date, end_date, properties(name), profiles!reservations_created_by_id_fkey(name, email)")
    .eq("id", reservationId).single();
  if (!r) throw new Error("Reserva no encontrada");
  const prop = (r as any).properties?.name ?? "la casa";
  const creator = (r as any).profiles;
  const tpl = await getTemplate(type);
  const vars = {
    PropertyName: prop,
    UserName: creator?.name ?? "",
    StartDate: fmt(r.start_date),
    EndDate: fmt(r.end_date),
    FormLink: `${APP_SCHEME}inspeccion/${reservationId}`,
  };
  const recipients = creator?.email ? [creator.email] : [];
  if (type === "MAINTENANCE") {
    // Aviso a todos los administradores con email.
    const { data: admins } = await admin.from("profiles")
      .select("email").in("role", [...PRINCIPAL, ...FAMILY_ADMIN]).not("email", "is", null);
    for (const a of admins ?? []) if (a.email) recipients.push(a.email);
  }
  const uniq = [...new Set(recipients)];
  if (uniq.length) await sendMail(uniq, fill(tpl.subject, vars), fill(tpl.body, vars));
  return uniq.length;
}

async function handleInspectionReminders() {
  // Reservas que terminan HOY y aún sin reporte de salida.
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1);
  const { data: rows } = await admin.from("reservations")
    .select("id, start_date, end_date, is_maintenance, properties(name), profiles!reservations_created_by_id_fkey(name, email), out_reports(id)")
    .gte("end_date", today.toISOString()).lt("end_date", tomorrow.toISOString())
    .eq("is_maintenance", false);
  const tpl = await getTemplate("INSPECTION_REMINDER");
  let sent = 0;
  for (const r of rows ?? []) {
    if ((r as any).out_reports?.length) continue; // ya tiene reporte
    const creator = (r as any).profiles;
    if (!creator?.email) continue;
    const vars = {
      PropertyName: (r as any).properties?.name ?? "la casa",
      UserName: creator.name ?? "",
      StartDate: fmt(r.start_date), EndDate: fmt(r.end_date),
      FormLink: `${APP_SCHEME}inspeccion/${r.id}`,
    };
    await sendMail([creator.email], fill(tpl.subject, vars), fill(tpl.body, vars));
    sent++;
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const type = String(body.type ?? "");

    // --- Camino cron (recordatorios) ---
    if (type === "inspection_reminders") {
      if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
        return json({ error: "No autorizado (cron)" }, 401);
      }
      const sent = await handleInspectionReminders();
      return json({ ok: true, sent });
    }

    // --- Camino usuario (confirmación / mantenimiento) ---
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "No autorizado" }, 401);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    if (!u?.user) return json({ error: "No autorizado" }, 401);

    const reservationId = String(body.reservationId ?? "");
    if (!reservationId) return json({ error: "Falta reservationId" }, 400);

    const { data: prof } = await userClient.from("profiles")
      .select("role, family_group_id").eq("id", u.user.id).single();
    const { data: resv } = await userClient.from("reservations")
      .select("created_by_id, family_group_id, is_maintenance").eq("id", reservationId).single();
    if (!prof || !resv) return json({ error: "Sin acceso" }, 403);

    const isPrincipal = PRINCIPAL.includes(prof.role);
    const isGroupAdmin = isPrincipal ||
      (FAMILY_ADMIN.includes(prof.role) && prof.family_group_id === resv.family_group_id);
    const isCreator = resv.created_by_id === u.user.id;

    if (type === "reservation_confirmation") {
      if (!(isCreator || isGroupAdmin)) return json({ error: "Sin permiso" }, 403);
      const n = await handleReservation(reservationId, "RESERVATION_CONFIRMATION");
      return json({ ok: true, sent: n });
    }
    if (type === "maintenance") {
      if (!isPrincipal) return json({ error: "Solo admin principal" }, 403);
      const n = await handleReservation(reservationId, "MAINTENANCE");
      return json({ ok: true, sent: n });
    }
    return json({ error: "type no soportado" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
