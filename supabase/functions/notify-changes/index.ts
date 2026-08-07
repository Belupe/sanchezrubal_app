// ===============================================================
// notify-changes — Avisa de todo lo que se mueve: reservas, lista de espera
// e informes de salida.
//
// La llaman los triggers de la migración 0027 (public.post_notify_changes),
// no el cliente: así el aviso sale aunque la app que provocó el cambio se
// cierre, y cubre también las modificaciones y las cancelaciones, que desde
// el cliente no se notificaban en absoluto.
//
// Destinatarios:
//   reserva creada/modificada/cancelada  ->  PRINCIPAL_ADMIN (correo + push)
//   bloqueo de mantenimiento             ->  todos menos MEGA_ADMIN (correo)
//                                            + PRINCIPAL_ADMIN (push)
//   alta en la lista de espera           ->  PRINCIPAL_ADMIN (correo + push)
//   informe de salida completado         ->  PRINCIPAL_ADMIN (correo + push)
//
// OJO con el rango: aquí PRINCIPAL_ADMIN significa PRINCIPAL_ADMIN y nada
// más. En send-email la constante PRINCIPAL vale ["MEGA_ADMIN",
// "PRINCIPAL_ADMIN"], y reutilizarla por inercia metería al mega admin en
// todos estos avisos, que es justo lo que no se quiere.
//
// Auth: cabecera x-cron-secret == CRON_SECRET (la pone el trigger desde
// Vault). El push se delega en la Edge Function send-push.
//
// Secrets: CRON_SECRET (auth propia) y PUSH_SECRET (para invocar send-push).
// SMTP se lee de system_config (service role).
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const PUSH_SECRET = Deno.env.get("PUSH_SECRET") ?? "";

// [B-05] Comparación en tiempo constante del secreto (ver send-email).
async function cronSecretMatches(provided: string | null): Promise<boolean> {
  if (!CRON_SECRET) return false;
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(provided ?? "")),
    crypto.subtle.digest("SHA-256", enc.encode(CRON_SECRET)),
  ]);
  const x = new Uint8Array(ha), y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

// [I-07] Origen permitido configurable (default "*" = igual que antes).
const ALLOWED_ORIGIN = Deno.env.get("FUNCTIONS_ALLOWED_ORIGIN") ?? "*";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Réplica inline de las plantillas por si la tabla no las tuviera (mismo
// criterio que send-email y notify-waitlist: el aviso nunca se cae por una
// plantilla que falte).
const FALLBACK: Record<string, { subject: string; body: string }> = {
  ADMIN_RESERVATION_CREATED: {
    subject: "Nueva reserva — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Nueva reserva</h2><p><b>{{UserName}}</b> ha reservado <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}.</p><p>Personas: {{GuestCount}}</p></div>",
  },
  ADMIN_RESERVATION_UPDATED: {
    subject: "Reserva modificada — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Reserva modificada</h2><p>La reserva de <b>{{UserName}}</b> en <b>{{PropertyName}}</b> ha cambiado.</p><p>Antes: del {{OldStartDate}} al {{OldEndDate}}<br>Ahora: del {{StartDate}} al {{EndDate}}</p></div>",
  },
  ADMIN_RESERVATION_CANCELLED: {
    subject: "Reserva cancelada — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Reserva cancelada</h2><p><b>{{UserName}}</b> ha cancelado su reserva en <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}.</p></div>",
  },
  ADMIN_WAITLIST_JOINED: {
    subject: "Nueva solicitud en lista de espera — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Lista de espera</h2><p><b>{{UserName}}</b> se ha apuntado a la lista de espera de <b>{{PropertyName}}</b> para el {{StartDate}} al {{EndDate}}.</p></div>",
  },
  ADMIN_OUT_REPORT: {
    subject: "Formulario de salida — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Formulario de salida completado</h2><p><b>{{UserName}}</b> ha completado el formulario de salida de <b>{{PropertyName}}</b>.</p><p>Estado general: <b>{{GeneralStatus}}</b><br>Desperfectos: {{Damages}}<br>Cosas que faltan: {{MissingItems}}</p></div>",
  },
  MAINTENANCE: {
    subject: "Mantenimiento programado — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Mantenimiento</h2><p>Se ha bloqueado <b>{{PropertyName}}</b> por mantenimiento del {{StartDate}} al {{EndDate}}.</p></div>",
  },
  MAINTENANCE_CANCELLED: {
    subject: "Mantenimiento levantado — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Mantenimiento levantado</h2><p>Se ha retirado el bloqueo por mantenimiento de <b>{{PropertyName}}</b> del {{StartDate}} al {{EndDate}}. Las fechas vuelven a estar libres.</p></div>",
  },
};

function fill(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(vars[k] ?? "");
  return out;
}

// [M-08] Escapa HTML. Aquí importa especialmente: los desperfectos y las cosas
// que faltan del informe de salida son texto libre escrito por un usuario y
// acaban en un correo que se manda a OTRAS personas.
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

function fmt(d: string | null | undefined) {
  return d ? new Date(d).toLocaleDateString("es-ES") : "";
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

async function sendMail(to: string[], subject: string, html: string) {
  if (!to.length) return 0;
  const cfg = await getSmtp();
  // 465 por defecto (TLS implícito). La RFC 8314 lo prefiere frente a
  // STARTTLS, y con 587 + smtp_secure activo la conexión falla: el puerto
  // espera STARTTLS, no TLS directo. Solo aplica si smtp_port viene vacío.
  const port = cfg.smtp_port ?? 465;
  const client = new SMTPClient({
    connection: {
      hostname: cfg.smtp_host,
      port,
      tls: cfg.smtp_secure || port === 465,
      auth: { username: cfg.smtp_user, password: cfg.smtp_pass ?? "" },
    },
  });
  // [2L-13] Cierra la conexión SMTP SIEMPRE, aunque send() lance.
  try {
    for (const addr of to) {
      await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to: addr, subject, html });
    }
  } finally {
    await client.close();
  }
  return to.length;
}

// Push best-effort vía send-push (no bloquea si falla: el correo ya cubre el
// aviso, y en escritorio el push no existe de todas formas).
async function sendPush(userIds: string[], title: string, body: string, data: Record<string, string>) {
  if (!userIds.length) return;
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-push-secret": PUSH_SECRET },
      body: JSON.stringify({ userIds, title, body, data }),
    });
  } catch (_) { /* el correo ya cubre el aviso */ }
}

type Persona = { id: string; email: string | null };

async function principalAdmins(): Promise<Persona[]> {
  // Literal a propósito: NI MEGA_ADMIN ni roles de grupo. Ver la nota de arriba.
  const { data } = await admin.from("profiles")
    .select("id, email").eq("role", "PRINCIPAL_ADMIN");
  return (data ?? []) as Persona[];
}

async function todosMenosMega(): Promise<Persona[]> {
  // El mantenimiento afecta a una casa, y las casas no están repartidas por
  // grupos (properties no tiene family_group_id): son comunes a todos.
  const { data } = await admin.from("profiles")
    .select("id, email").neq("role", "MEGA_ADMIN").not("email", "is", null);
  return (data ?? []) as Persona[];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    if (!(await cronSecretMatches(req.headers.get("x-cron-secret")))) {
      return json({ error: "No autorizado" }, 401);
    }
    const b = await req.json().catch(() => ({}));
    const event = String(b.event ?? "");
    if (!event) return json({ error: "Falta event" }, 400);

    const esMantenimiento = b.isMaintenance === true;

    // ---- Quién aparece como protagonista del aviso ----------------------
    // En un informe de salida la tabla no guarda autor: se atribuye al creador
    // de la reserva asociada (reservation_id es nullable, así que puede no
    // haberlo y entonces el correo dirá simplemente "Alguien").
    let sujetoId: string | null = b.createdById ? String(b.createdById) : null;
    if (!sujetoId && b.reservationId) {
      const { data: r } = await admin.from("reservations")
        .select("created_by_id").eq("id", String(b.reservationId)).maybeSingle();
      sujetoId = (r as any)?.created_by_id ?? null;
    }

    const [{ data: sujeto }, { data: prop }] = await Promise.all([
      sujetoId
        ? admin.from("profiles").select("name").eq("id", sujetoId).maybeSingle()
        : Promise.resolve({ data: null }),
      b.propertyId
        ? admin.from("properties").select("name").eq("id", String(b.propertyId)).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const vars: Record<string, string> = {
      PropertyName: (prop as any)?.name ?? "la casa",
      UserName: (sujeto as any)?.name ?? "Alguien",
      StartDate: fmt(b.startDate),
      EndDate: fmt(b.endDate),
      OldStartDate: fmt(b.oldStartDate),
      OldEndDate: fmt(b.oldEndDate),
      GuestCount: b.guestCount != null ? String(b.guestCount) : "",
      GeneralStatus: b.generalStatus ? String(b.generalStatus) : "",
      Damages: b.damages ? String(b.damages) : "ninguno",
      MissingItems: b.missingItems ? String(b.missingItems) : "ninguna",
    };

    // ---- Plantilla y destinatarios según el evento -----------------------
    let tipo: string;
    let destinatarios: Persona[];

    if (esMantenimiento) {
      tipo = event === "reservation_cancelled" ? "MAINTENANCE_CANCELLED" : "MAINTENANCE";
      destinatarios = await todosMenosMega();
    } else {
      const porEvento: Record<string, string> = {
        reservation_created: "ADMIN_RESERVATION_CREATED",
        reservation_updated: "ADMIN_RESERVATION_UPDATED",
        reservation_cancelled: "ADMIN_RESERVATION_CANCELLED",
        waitlist_joined: "ADMIN_WAITLIST_JOINED",
        out_report_created: "ADMIN_OUT_REPORT",
      };
      if (!porEvento[event]) return json({ error: `Evento desconocido: ${event}` }, 400);
      tipo = porEvento[event];
      destinatarios = await principalAdmins();
    }

    // Nadie se avisa de su propio cambio. actorId puede venir null cuando el
    // cambio lo hace el service role (p. ej. la promoción de la cola), y
    // entonces no se excluye a nadie.
    const actorId = b.actorId ? String(b.actorId) : null;
    if (actorId) destinatarios = destinatarios.filter((p) => p.id !== actorId);

    const tpl = await getTemplate(tipo);
    if (!tpl) return json({ error: `Sin plantilla para ${tipo}` }, 500);

    const correos = [...new Set(destinatarios.map((p) => p.email).filter(Boolean) as string[])];
    const enviados = await sendMail(correos, fill(tpl.subject, vars), fillHtml(tpl.body, vars));

    // El push va SIEMPRE solo al administrador principal, también en el
    // mantenimiento: el correo de mantenimiento es un aviso general, pero
    // nadie más necesita que le suene el móvil por esto.
    const paraPush = (await principalAdmins())
      .filter((p) => p.id !== actorId)
      .map((p) => p.id);
    await sendPush(
      paraPush,
      fill(tpl.subject, vars),
      fill(tpl.body, vars).replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim(),
      {
        type: event,
        reservationId: b.reservationId ? String(b.reservationId) : "",
        propertyId: b.propertyId ? String(b.propertyId) : "",
      },
    );

    return json({ ok: true, event, tipo, emailsSent: enviados, pushTo: paraPush.length });
  } catch (e) {
    console.error("notify-changes error:", e);
    return json({ error: "Error interno al notificar el cambio" }, 500);
  }
});
