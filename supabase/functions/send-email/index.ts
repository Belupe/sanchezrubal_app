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
  INSPECTION_REMINDER: {
    subject: "Formulario de salida — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Formulario de salida</h2><p>Hola {{UserName}}, por favor completa el formulario de salida de <b>{{PropertyName}}</b> desde la app.</p><p><a href='{{FormLink}}' style='display:inline-block;background:#2563eb;color:#fff;text-decoration:none;padding:12px 20px;border-radius:8px;font-weight:600'>Abrir Portal Familia</a></p></div>",
  },
  PRE_STAY: {
    subject: "Tu estancia se acerca — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><h2>Tu estancia se acerca</h2><p>Hola {{UserName}}, tu reserva en <b>{{PropertyName}}</b> empieza el {{StartDate}}.</p><p>{{CustomText}}</p></div>",
  },
};

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

/// Abre UNA conexión SMTP y devuelve con qué mandar por ella.
///
/// Los recordatorios recorren N reservas y mandan un correo por cada una.
/// Antes cada envío abría su propia conversación con el servidor —saludo,
/// autenticación, cifrado— y releía la contraseña de Vault: 10 recordatorios
/// eran 10 conexiones y 20 consultas. Además muchos proveedores limitan las
/// CONEXIONES por minuto antes que los mensajes, así que era el patrón que
/// antes te acercaba al tope.
async function abrirSmtp() {
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
  return {
    async enviar(to: string[], subject: string, html: string) {
      for (const addr of to) {
        await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to: addr, subject, html });
      }
    },
    async cerrar() {
      await client.close();
    },
  };
}

function fmt(d: string) {
  return new Date(d).toLocaleDateString("es-ES");
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
  const smtp = await abrirSmtp();
  try {
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
    await smtp.enviar([creator.email], fill(tpl.subject, vars), fillHtml(tpl.body, vars));
    sent++;
  }
  } finally {
    await smtp.cerrar();
  }
  return sent;
}

// [PRE_STAY] Aviso "tu estancia se acerca": reservas que empiezan dentro de
// PRE_STAY_DAYS días.
//
// Cada correo va A UNA SOLA PERSONA: quien creó esa reserva. No es un aviso
// general ni lo recibe ningún administrador —de las reservas ajenas se entera
// el PRINCIPAL_ADMIN por otra vía, los triggers de la migración 0027 y la
// función notify-changes—. Aquí solo se avisa a cada uno de lo suyo.
//
// Lo que cambió al retirar notification_settings (migración 0031) es que ya no
// se excluye a nadie: antes había un interruptor por usuario para silenciarlo
// y un texto personalizado que se añadía al final. Esa pantalla desapareció al
// convertir la pestaña en Soporte, la tabla se quedó sin quien la escribiera y
// su única fila decía lo mismo que el valor por defecto, así que la consulta
// sobraba.
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
  const smtp = await abrirSmtp();
  try {
  for (const r of rows ?? []) {
    const creator = (r as any).profiles;
    if (!creator?.email) continue;
    const vars = {
      PropertyName: (r as any).properties?.name ?? "la casa",
      UserName: creator.name ?? "",
      StartDate: fmt(r.start_date), EndDate: fmt(r.end_date),
    };
    await smtp.enviar([creator.email], fill(tpl.subject, vars), fillHtml(tpl.body, vars));
    sent++;
  }
  } finally {
    await smtp.cerrar();
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

    // Ya no hay camino de USUARIO. La confirmación de reserva y el aviso de
    // mantenimiento los manda notify-changes desde los triggers de la 0027, así
    // que esta función solo atiende al cron. Con ello se van también la
    // comprobación de permisos que hacía falta para fiarse del cliente y el
    // anti-doble-envío que compensaba los dobles toques.
    return json({ error: "type no soportado" }, 400);
  } catch (e) {
    console.error("send-email error:", e);
    return json({ error: "Error interno al enviar el correo" }, 500);
  }
});
