// ===============================================================
// notify-waitlist — Avisa al usuario PROMOVIDO de la lista de espera.
//
// La llama el trigger promote_waitlist_on_cancel() (BD) cuando alguien
// cancela una reserva y el siguiente de la cola hereda las fechas. Envía
// DOS notificaciones al promovido, cada una por email + push:
//   1) "X ha cancelado su reserva"          (WAITLIST_CANCELLED)
//   2) "esas fechas ahora son tuyas"        (WAITLIST_PROMOTED)
//
// Auth: cabecera x-cron-secret == CRON_SECRET (la pone el trigger desde
// Vault). El push se delega en la Edge Function send-push.
//
// Secrets: CRON_SECRET. SMTP se lee de system_config (service role).
// SUPABASE_URL/SERVICE_ROLE inyectados por Supabase.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const FALLBACK: Record<string, { subject: string; body: string }> = {
  WAITLIST_CANCELLED: {
    subject: "Se ha liberado una reserva — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Reserva cancelada</h2><p>Hola {{UserName}}, {{CancelledBy}} ha cancelado su reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}, fechas en las que estabas en lista de espera.</p></div>",
  },
  WAITLIST_PROMOTED: {
    subject: "¡Las fechas son tuyas! — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Reserva asignada</h2><p>Hola {{UserName}}, como eras el siguiente en la lista de espera, <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}} es ahora tuyo. La reserva ya está creada a tu nombre.</p></div>",
  },
};

function fill(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(vars[k] ?? "");
  return out;
}

// [M-08] Escapa HTML. Evita que UserName (nombre del promovido) o CancelledBy
// (nombre de quien canceló) inyecten HTML/phishing en el correo de la cola.
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function fillHtml(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(escapeHtml(vars[k] ?? ""));
  return out;
}
function fmt(d: string) {
  return new Date(d).toLocaleDateString("es-ES");
}

async function getTemplate(type: string) {
  const { data } = await admin.from("notification_templates")
    .select("subject, body").eq("type", type).maybeSingle();
  return data ?? FALLBACK[type];
}

async function getSmtp() {
  const { data } = await admin.from("system_config")
    .select("smtp_host, smtp_port, smtp_user, smtp_secure").eq("id", "global").single();
  if (!data?.smtp_host || !data?.smtp_user) throw new Error("SMTP no configurado en system_config");
  // [M-07] La contraseña ya no vive en la tabla: se lee de Vault (service role).
  const { data: pass } = await admin.rpc("get_smtp_password");
  return { ...data, smtp_pass: (pass as string | null) ?? "" };
}

async function sendMails(to: string, mails: { subject: string; html: string }[]) {
  const cfg = await getSmtp();
  const port = cfg.smtp_port ?? 587;
  const client = new SMTPClient({
    connection: {
      hostname: cfg.smtp_host,
      port,
      // [M-07] TLS implícito (465) o STARTTLS (587/25). denomailer aborta antes de
      // mandar credenciales si no logra cifrar → la contraseña no viaja en claro.
      tls: cfg.smtp_secure || port === 465,
      auth: { username: cfg.smtp_user, password: cfg.smtp_pass ?? "" },
    },
  });
  for (const m of mails) {
    await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to, subject: m.subject, html: m.html });
  }
  await client.close();
}

// Push best-effort vía send-push (no bloquea si falla).
async function sendPush(userId: string, title: string, body: string, data: Record<string, string>) {
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-cron-secret": CRON_SECRET },
      body: JSON.stringify({ userIds: [userId], title, body, data }),
    });
  } catch (_) { /* el email ya cubre el aviso */ }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
      return json({ error: "No autorizado" }, 401);
    }
    const b = await req.json().catch(() => ({}));
    const promotedUserId = String(b.promotedUserId ?? "");
    const newReservationId = String(b.newReservationId ?? "");
    if (!promotedUserId) return json({ error: "Falta promotedUserId" }, 400);

    const [{ data: promoted }, { data: canceller }, { data: prop }] = await Promise.all([
      admin.from("profiles").select("name, email").eq("id", promotedUserId).maybeSingle(),
      b.cancelledByUserId
        ? admin.from("profiles").select("name").eq("id", String(b.cancelledByUserId)).maybeSingle()
        : Promise.resolve({ data: null }),
      b.propertyId
        ? admin.from("properties").select("name").eq("id", String(b.propertyId)).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const vars = {
      PropertyName: (prop as any)?.name ?? "la casa",
      UserName: (promoted as any)?.name ?? "",
      CancelledBy: (canceller as any)?.name ?? "Otra persona",
      StartDate: b.startDate ? fmt(String(b.startDate)) : "",
      EndDate: b.endDate ? fmt(String(b.endDate)) : "",
    };

    const tCancel = await getTemplate("WAITLIST_CANCELLED");
    const tPromo = await getTemplate("WAITLIST_PROMOTED");

    // 1) y 2) por email (si tiene correo).
    let emailsSent = 0;
    const email = (promoted as any)?.email;
    if (email) {
      await sendMails(email, [
        { subject: fill(tCancel.subject, vars), html: fillHtml(tCancel.body, vars) },
        { subject: fill(tPromo.subject, vars), html: fillHtml(tPromo.body, vars) },
      ]);
      emailsSent = 2;
    }

    // 1) y 2) por push (best-effort).
    const data = { type: "waitlist_promoted", reservationId: newReservationId };
    await sendPush(promotedUserId,
      `Reserva cancelada — ${vars.PropertyName}`,
      `${vars.CancelledBy} ha cancelado del ${vars.StartDate} al ${vars.EndDate}.`,
      data);
    await sendPush(promotedUserId,
      `¡Las fechas son tuyas! — ${vars.PropertyName}`,
      `${vars.PropertyName} del ${vars.StartDate} al ${vars.EndDate} ya es tuyo.`,
      data);

    return json({ ok: true, emailsSent });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
