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

// [B-05] Comparación en tiempo constante del secreto de cron.
// crypto.subtle.digest (Web Crypto) está disponible en el edge-runtime de
// Deno de Supabase (no requiere import). Hasheamos AMBOS valores a 32 bytes
// de longitud fija y comparamos con XOR acumulado: ni el tiempo de ejecución
// ni la longitud del secreto se filtran. No usamos node:crypto.timingSafeEqual
// porque lanza con longitudes distintas y filtraría la longitud del secreto.
async function cronSecretMatches(provided: string | null): Promise<boolean> {
  if (!CRON_SECRET) return false;            // guard de secreto vacío (conservado)
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

// Esquema propio para que los enlaces de los correos ABRAN la app nativa
// (ya no hay web). Registrado en Android/Windows/iOS.
const APP_SCHEME = "portalfamilia://";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const PRINCIPAL = ["MEGA_ADMIN", "PRINCIPAL_ADMIN"];
const FAMILY_ADMIN = ["FAMILY_ADMIN", "FAMILY_SECOND_ADMIN"];

// [I-07] Origen permitido configurable (default "*" = igual que antes).
const ALLOWED_ORIGIN = Deno.env.get("FUNCTIONS_ALLOWED_ORIGIN") ?? "*";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
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
  PRE_STAY: {
    subject: "Tu estancia se acerca — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Tu estancia se acerca</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> empieza el {{StartDate}}.</p><p>{{CustomText}}</p></div>",
  },
};

// [2L-11] Anti-doble-envío del correo de confirmación (best-effort por isolate):
// evita que un doble toque re-dispare el correo al propio creador en segundos.
const recentConfirmations = new Map<string, number>();
const CONFIRMATION_TTL_MS = 60_000;

function fill(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(vars[k] ?? "");
  return out;
}

// [M-08] Escapa los 5 caracteres peligrosos de HTML. Evita que un valor editable
// por el usuario (profiles.name -> UserName, PropertyName…) inyecte etiquetas o
// enlaces de phishing en el cuerpo del correo que se envía a OTRAS personas.
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Igual que fill() pero escapando CADA valor. Solo para el cuerpo HTML: la
// plantilla (con su <div>, href='{{FormLink}}'…) queda intacta y solo se escapan
// los valores (el &#39; impide romper el atributo entrecomillado).
function fillHtml(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(escapeHtml(vars[k] ?? ""));
  return out;
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
  const cfg = await getSmtp();
  // 465 por defecto (TLS implícito). La RFC 8314 lo prefiere frente a
  // STARTTLS, y con 587 + smtp_secure activo la conexión falla: el puerto
  // espera STARTTLS, no TLS directo. Solo aplica si smtp_port viene vacío.
  const port = cfg.smtp_port ?? 465;
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
  // [2L-13] Cierra la conexión SMTP SIEMPRE, aunque send() lance (evita fuga
  // de conexión en isolates reutilizados).
  try {
    for (const addr of to) {
      await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to: addr, subject, html });
    }
  } finally {
    await client.close();
  }
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
    // Aviso a todos los administradores con email. Desde la migración 0025 hay
    // que mirar en DOS sitios: el rango global está en profiles.role y el de
    // cada casa en group_members.role.
    const { data: globales } = await admin.from("profiles")
      .select("email").in("role", PRINCIPAL).not("email", "is", null);
    for (const a of globales ?? []) if (a.email) recipients.push(a.email);

    const { data: jefes } = await admin.from("group_members")
      .select("user_id").in("role", FAMILY_ADMIN);
    const ids = (jefes ?? []).map((j) => j.user_id);
    if (ids.length) {
      const { data: sus } = await admin.from("profiles")
        .select("email").in("id", ids).not("email", "is", null);
      for (const a of sus ?? []) if (a.email) recipients.push(a.email);
    }
  }
  const uniq = [...new Set(recipients)];
  if (uniq.length) await sendMail(uniq, fill(tpl.subject, vars), fillHtml(tpl.body, vars));
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
    await sendMail([creator.email], fill(tpl.subject, vars), fillHtml(tpl.body, vars));
    sent++;
  }
  return sent;
}

// [PRE_STAY] Aviso "tu estancia se acerca": reservas que empiezan dentro de
// PRE_STAY_DAYS días. Respeta la preferencia del usuario (notification_settings
// PRE_STAY: si is_active=false, se omite) y añade su custom_text opcional.
const PRE_STAY_DAYS = 3;
async function handlePreStayReminders() {
  const from = new Date(); from.setHours(0, 0, 0, 0);
  from.setDate(from.getDate() + PRE_STAY_DAYS);
  const to = new Date(from); to.setDate(to.getDate() + 1);
  const { data: rows } = await admin.from("reservations")
    .select("id, start_date, end_date, created_by_id, is_maintenance, properties(name), profiles!reservations_created_by_id_fkey(name, email)")
    .gte("start_date", from.toISOString()).lt("start_date", to.toISOString())
    .eq("is_maintenance", false);
  const tpl = await getTemplate("PRE_STAY");
  let sent = 0;
  for (const r of rows ?? []) {
    const creator = (r as any).profiles;
    if (!creator?.email) continue;
    const { data: ns } = await admin.from("notification_settings")
      .select("is_active, custom_text")
      .eq("user_id", (r as any).created_by_id).eq("type", "PRE_STAY").maybeSingle();
    if (ns && ns.is_active === false) continue; // el usuario lo desactivó
    const vars = {
      PropertyName: (r as any).properties?.name ?? "la casa",
      UserName: creator.name ?? "",
      StartDate: fmt(r.start_date), EndDate: fmt(r.end_date),
      CustomText: (ns?.custom_text as string | null) ?? "",
    };
    await sendMail([creator.email], fill(tpl.subject, vars), fillHtml(tpl.body, vars));
    sent++;
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // [2I-11] Solo POST (la lógica asume cuerpo JSON POST).
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    const body = await req.json().catch(() => ({}));
    const type = String(body.type ?? "");

    // --- Camino cron (recordatorios) ---
    if (type === "inspection_reminders") {
      if (!(await cronSecretMatches(req.headers.get("x-cron-secret")))) {
        return json({ error: "No autorizado (cron)" }, 401);
      }
      const sent = await handleInspectionReminders();
      return json({ ok: true, sent });
    }

    // --- Camino cron (pre-estancia) ---
    if (type === "pre_stay_reminders") {
      if (!(await cronSecretMatches(req.headers.get("x-cron-secret")))) {
        return json({ error: "No autorizado (cron)" }, 401);
      }
      const sent = await handlePreStayReminders();
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
      .select("role").eq("id", u.user.id).single();
    // El rol dentro de la casa vive en group_members desde la migración 0025;
    // `profiles.role` ya solo dice el rango GLOBAL.
    const { data: member } = await userClient.from("group_members")
      .select("group_id, role").eq("user_id", u.user.id).maybeSingle();
    const { data: resv } = await userClient.from("reservations")
      .select("created_by_id, family_group_id, is_maintenance").eq("id", reservationId).single();
    if (!prof || !resv) return json({ error: "Sin acceso" }, 403);

    const isPrincipal = PRINCIPAL.includes(prof.role);
    // [2L-14] Quien no está en ninguna casa no es admin de reservas de grupo
    // NULL: exigir pertenencia (espeja private.is_group_admin(NULL)).
    const isGroupAdmin = isPrincipal ||
      (member != null &&
        FAMILY_ADMIN.includes(member.role) &&
        member.group_id === resv.family_group_id);
    const isCreator = resv.created_by_id === u.user.id;

    if (type === "reservation_confirmation") {
      if (!(isCreator || isGroupAdmin)) return json({ error: "Sin permiso" }, 403);
      // [2L-11] Anti-doble-envío best-effort (evita re-disparo por doble toque).
      const now = Date.now();
      const last = recentConfirmations.get(reservationId);
      if (last && now - last < CONFIRMATION_TTL_MS) {
        return json({ ok: true, sent: 0, deduped: true });
      }
      recentConfirmations.set(reservationId, now);
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
    console.error("send-email error:", e);
    return json({ error: "Error interno al enviar el correo" }, 500);
  }
});
