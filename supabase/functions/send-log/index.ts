// ===============================================================
// send-log — Manda a soporte el registro de diagnóstico de un usuario.
//
// Existe para que pedir un registro sea un botón y no una conversación.
// Antes, en móvil, había que abrir el menú de compartir, elegir el cliente de
// correo y escribir la dirección a mano; en escritorio no había ni botón, solo
// "abrir la carpeta". Ahora la app manda el fichero y llega solo.
//
// El destino está FIJADO AQUÍ y no se acepta del cliente. Es la diferencia
// entre un botón de soporte y un relé de correo abierto: si la dirección
// viajara en el cuerpo de la petición, cualquiera con una sesión válida podría
// mandar adjuntos arbitrarios a quien quisiera desde tu SMTP.
//
// Auth: JWT del usuario (CUALQUIERA autenticado, no solo administradores: el
// que tiene el fallo suele ser justo el que no manda nada).
//
// Input JSON: { log: string, esFallo?: boolean, contexto?: Record<string,string> }
//
// SMTP se lee de system_config igual que en send-email.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Destino de los registros. Constante a propósito: ver la nota de arriba.
const SOPORTE_EMAIL = "ignacio@sanchezbas.com";

// Tope del adjunto. El registro de sesión ya está acotado a 1 MB en el cliente
// (LogService._maxBytes), pero un cuerpo JSON de ese tamaño más el base64 se
// acerca a los límites de la función y del SMTP. Se recorta por el PRINCIPIO,
// igual que hace LogService: lo que interesa es lo último que pasó.
const MAX_LOG_BYTES = 512 * 1024;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

// [I-07] Origen permitido configurable (default "*" = igual que el resto).
const ALLOWED_ORIGIN = Deno.env.get("FUNCTIONS_ALLOWED_ORIGIN") ?? "*";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Frenos de envío. Viven en la BD (tabla support_log_sends, migración 0030) y
// NO en un Map de memoria: cada isolate tendría el suyo, y se comprobó en
// producción que dos llamadas seguidas caen en isolates distintos y acaban
// mandando dos correos. Con un SMTP de 1000 correos al mes y adjuntos de medio
// mega, ese fallo se paga.
const ENVIO_TTL_MS = 60_000; // anti-doble-toque
const TOPE_DIARIO = 5;       // nadie manda 5 registros legítimos el mismo día

/// Devuelve el motivo por el que NO se debe enviar, o null si se puede.
async function motivoParaNoEnviar(userId: string): Promise<string | null> {
  const desdeHace24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await admin.from("support_log_sends")
    .select("created_at")
    .eq("user_id", userId)
    .gte("created_at", desdeHace24h)
    .order("created_at", { ascending: false });
  // Si la consulta falla, se deja pasar: perder un informe de fallo por un
  // problema del freno sería peor que mandar un correo de más.
  if (error) return null;
  const envios = data ?? [];
  if (envios.length >= TOPE_DIARIO) {
    return `Ya has enviado ${TOPE_DIARIO} registros hoy. Inténtalo mañana o escríbenos directamente.`;
  }
  const ultimo = envios[0]?.created_at;
  if (ultimo && Date.now() - new Date(ultimo).getTime() < ENVIO_TTL_MS) {
    return "Acabas de enviar un registro. Espera un minuto antes de mandar otro.";
  }
  return null;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// El adjunto va en base64: el registro lleva acentos y rutas con caracteres
// raros, y mandarlo como texto plano depende de que el charset del adjunto se
// negocie bien. En base64 llega byte a byte.
function aBase64(texto: string): string {
  const bytes = new TextEncoder().encode(texto);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function recortarPorElPrincipio(texto: string): { texto: string; recortado: boolean } {
  const bytes = new TextEncoder().encode(texto);
  if (bytes.length <= MAX_LOG_BYTES) return { texto, recortado: false };
  const trozo = bytes.slice(bytes.length - MAX_LOG_BYTES);
  // El corte puede caer a mitad de un carácter multibyte; el decoder lo
  // sustituye por el carácter de reemplazo en vez de reventar.
  return { texto: new TextDecoder().decode(trozo), recortado: true };
}

async function getSmtp() {
  const { data } = await admin.from("system_config")
    .select("smtp_host, smtp_port, smtp_user, smtp_secure").eq("id", "global").single();
  if (!data?.smtp_host || !data?.smtp_user) throw new Error("SMTP no configurado en system_config");
  // [M-07] La contraseña se lee de Vault (service role).
  const { data: pass } = await admin.rpc("get_smtp_password");
  return { ...data, smtp_pass: (pass as string | null) ?? "" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "No autorizado" }, 401);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    if (!u?.user) return json({ error: "No autorizado" }, 401);

    const body = await req.json().catch(() => ({}));
    const bruto = String(body.log ?? "");
    if (!bruto.trim()) return json({ error: "El registro está vacío" }, 400);

    const motivo = await motivoParaNoEnviar(u.user.id);
    if (motivo) return json({ ok: true, enviado: false, motivo });

    const esFallo = body.esFallo === true;
    const { texto: registro, recortado } = recortarPorElPrincipio(bruto);

    // Quién lo manda se resuelve en el SERVIDOR a partir del JWT, no de lo que
    // diga el cliente: si viniera del cuerpo, el remitente sería falsificable y
    // el correo de soporte dejaría de ser fiable para saber a quién responder.
    const { data: perfil } = await admin.from("profiles")
      .select("name, email, role").eq("id", u.user.id).maybeSingle();

    const quien = (perfil as any)?.name || (perfil as any)?.email || u.user.id;
    const contexto = (body.contexto ?? {}) as Record<string, unknown>;
    const filas = Object.entries(contexto)
      .map(([k, v]) => `<tr><td style='padding:2px 10px 2px 0'><b>${escapeHtml(k)}</b></td><td>${escapeHtml(String(v))}</td></tr>`)
      .join("");

    const asunto = esFallo
      ? `Portal Familia — informe de fallo de ${quien}`
      : `Portal Familia — registro de sesión de ${quien}`;

    const html = `<div style='font-family:sans-serif'>
<h2>${esFallo ? "Informe de fallo" : "Registro de sesión"}</h2>
<p>Enviado desde la app por <b>${escapeHtml(String(quien))}</b>${(perfil as any)?.email ? ` (${escapeHtml((perfil as any).email)})` : ""}.</p>
<table style='font-size:13px'>
<tr><td style='padding:2px 10px 2px 0'><b>Usuario</b></td><td>${escapeHtml(u.user.id)}</td></tr>
<tr><td style='padding:2px 10px 2px 0'><b>Rango</b></td><td>${escapeHtml(String((perfil as any)?.role ?? "?"))}</td></tr>
${filas}
</table>
${recortado ? "<p><i>El registro se ha recortado por el principio: solo van los últimos 512 KB.</i></p>" : ""}
<p>El registro va adjunto. Ya viene saneado por el cliente: no lleva sesión ni contraseñas.</p>
</div>`;

    const cfg = await getSmtp();
    // 465 por defecto (TLS implícito), mismo criterio que send-email.
    const port = cfg.smtp_port ?? 465;
    const client = new SMTPClient({
      connection: {
        hostname: cfg.smtp_host,
        port,
        tls: cfg.smtp_secure || port === 465,
        auth: { username: cfg.smtp_user, password: cfg.smtp_pass ?? "" },
      },
    });
    // [2L-13] Cerrar SIEMPRE la conexión, aunque send() lance.
    try {
      await client.send({
        from: `Portal Familia <${cfg.smtp_user}>`,
        to: SOPORTE_EMAIL,
        // Responder al correo lleva directamente a quien tiene el problema.
        replyTo: (perfil as any)?.email || undefined,
        subject: asunto,
        html,
        attachments: [{
          filename: esFallo ? "ultimo-fallo.log" : "sesion.log",
          encoding: "base64",
          content: aBase64(registro),
          contentType: "text/plain; charset=utf-8",
        }],
      });
    } finally {
      await client.close();
    }

    // Se anota DESPUÉS de enviar, no antes: si el SMTP falla, el usuario debe
    // poder reintentar en el acto en vez de chocar contra su propio freno.
    await admin.from("support_log_sends").insert({
      user_id: u.user.id,
      es_fallo: esFallo,
      bytes: new TextEncoder().encode(registro).length,
    });

    return json({ ok: true, enviado: true, recortado });
  } catch (e) {
    console.error("send-log error:", e);
    return json({ error: "No se pudo enviar el registro" }, 500);
  }
});
