// ===============================================================
// notify-changes — Avisa de todo lo que se mueve: reservas, lista de espera
// e informes de salida.
//
// La llaman los triggers de la migración 0027 (public.post_notify_changes),
// no el cliente: así el aviso sale aunque la app que provocó el cambio se
// cierre, y cubre también las modificaciones y las cancelaciones, que desde
// el cliente no se notificaban en absoluto.
//
// REGLA DE CANAL (la de verdad, la que hay que recordar):
//   · admin principal  -> correo Y push, siempre.
//   · cualquier otro   -> push si tiene algún dispositivo registrado;
//                         correo SOLO si no lo tiene.
//   · mega admin       -> nada.
//
// El correo dejó de ser el canal por defecto: ahora es la red de seguridad de
// quien no puede recibir push (Windows y Linux no lo soportan, y en móvil el
// permiso puede estar denegado). No se puede forzar el permiso: iOS, macOS y
// Android 13+ exigen que la persona acepte.
//
// QUIÉN RECIBE QUÉ:
//   reserva creada        -> admin + confirmación a quien reservó
//   reserva modificada    -> admin + el DUEÑO, si no fue él quien la tocó
//   reserva cancelada     -> admin + el DUEÑO, si no fue él
//   mantenimiento         -> admin + TODOS menos el mega admin y menos quien
//                            lo creó
//   alta en la cola       -> admin + quien se apunta + quien tiene esas fechas
//   promoción de la cola  -> admin + el promovido. UN solo aviso: los tres
//                            sucesos que ocurren a la vez (borrado, alta y
//                            promoción) los funde la migración 0033.
//   informe de salida     -> admin + quien lo rellenó
//   falta el formulario   -> admin + el dueño de la reserva   (lo trae el cron)
//   2 días antes          -> admin + el dueño                 (lo trae el cron)
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

// Enlace profundo que abre la app en el formulario de salida. Lo usa la
// plantilla INSPECTION_REMINDER en su botón.
const APP_SCHEME = "portalfamilia://";

// [I-07] Origen permitido configurable (default "*" = igual que antes).
const ALLOWED_ORIGIN = Deno.env.get("FUNCTIONS_ALLOWED_ORIGIN") ?? "*";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });


// ---------------------------------------------------------------
// Plantillas
// ---------------------------------------------------------------
// Antes había una réplica inline de cada plantilla por si faltaba su fila.
// Con 4 tenía sentido; con 19 es una garantía de que acaben divergiendo del
// texto real, que es el de la base de datos y el que se edita desde la app.
// El respaldo pasa a ser genérico: feo pero honesto, y solo aparece si alguien
// borra una fila de notification_templates.
async function getTemplate(type: string) {
  const { data } = await admin.from("notification_templates")
    .select("subject, body").eq("type", type).maybeSingle();
  if (data) return data;
  return {
    subject: "Portal Familia — {{PropertyName}}",
    body: "<div style='font-family:sans-serif'><p>Ha habido un cambio en <b>{{PropertyName}}</b> ({{StartDate}} – {{EndDate}}).</p><p>Falta la plantilla <code>" + type + "</code> en la configuración.</p></div>",
  };
}

function fill(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(vars[k] ?? "");
  return out;
}

// [M-08] Escapa HTML. Importa especialmente con los desperfectos del informe de
// salida: texto libre de un usuario que acaba en el correo de otras personas.
function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function fillHtml(tpl: string, vars: Record<string, string>) {
  let out = tpl;
  for (const k of Object.keys(vars)) out = out.split("{{" + k + "}}").join(escapeHtml(vars[k] ?? ""));
  return out;
}

function fmt(d: string | null | undefined) {
  return d ? new Date(d).toLocaleDateString("es-ES") : "";
}

// El push no admite HTML: se queda el texto plano de la plantilla.
function aTextoPlano(html: string) {
  return html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

// ---------------------------------------------------------------
// Personas y canales
// ---------------------------------------------------------------
type Persona = { id: string; email: string | null; push: boolean };

/// Resuelve correo y si la persona tiene ALGÚN dispositivo con push. Esa
/// segunda parte es la que decide el canal, así que se consulta siempre.
async function personas(ids: string[]): Promise<Persona[]> {
  const unicos = [...new Set(ids.filter(Boolean))];
  if (!unicos.length) return [];
  const [{ data: perfiles }, { data: tokens }] = await Promise.all([
    admin.from("profiles").select("id, email, role").in("id", unicos),
    admin.from("device_tokens").select("user_id").in("user_id", unicos),
  ]);
  const conPush = new Set((tokens ?? []).map((t: any) => t.user_id));
  return (perfiles ?? [])
    // El mega admin no recibe nada, decidido al montar los avisos.
    .filter((p: any) => p.role !== "MEGA_ADMIN")
    .map((p: any) => ({ id: p.id, email: p.email, push: conPush.has(p.id) }));
}

async function principalAdmins(): Promise<Persona[]> {
  // Literal: PRINCIPAL_ADMIN y nada más. En send-email la constante PRINCIPAL
  // incluía al MEGA_ADMIN, y reutilizarla por inercia era el error fácil.
  const { data } = await admin.from("profiles").select("id").eq("role", "PRINCIPAL_ADMIN");
  return personas((data ?? []).map((p: any) => p.id));
}

async function todosLosDemas(): Promise<Persona[]> {
  // Para el mantenimiento, que es el único aviso general. Las casas no están
  // repartidas por grupos (properties no tiene family_group_id): son comunes.
  const { data } = await admin.from("profiles").select("id").neq("role", "MEGA_ADMIN");
  return personas((data ?? []).map((p: any) => p.id));
}

/// Un grupo de gente que recibe el MISMO texto.
/// `siempreCorreo` distingue al admin principal, que recibe por los dos
/// canales; para el resto el correo solo entra si no hay push.
type Audiencia = { tipo: string; gente: Persona[]; siempreCorreo?: boolean };

type Mensaje = { to: string[]; subject: string; html: string };

async function getSmtp() {
  const { data } = await admin.from("system_config")
    .select("smtp_host, smtp_port, smtp_user, smtp_secure").eq("id", "global").single();
  if (!data?.smtp_host || !data?.smtp_user) throw new Error("SMTP no configurado en system_config");
  // [M-07] La contraseña se lee de Vault (service role).
  const { data: pass } = await admin.rpc("get_smtp_password");
  return { ...data, smtp_pass: (pass as string | null) ?? "" };
}

/// Manda VARIOS correos distintos por UNA sola conexión SMTP.
///
/// Abrir la conversación con el servidor (saludo, autenticación, cifrado) es lo
/// caro; mandar por ella ya es barato. Y muchos proveedores limitan las
/// CONEXIONES por minuto antes que los mensajes.
async function enviarCorreos(mensajes: Mensaje[]) {
  const utiles = mensajes.filter((m) => m.to.length);
  if (!utiles.length) return 0;
  const cfg = await getSmtp();
  // 465 por defecto (TLS implícito): la RFC 8314 lo prefiere frente a STARTTLS.
  const port = cfg.smtp_port ?? 465;
  const client = new SMTPClient({
    connection: {
      hostname: cfg.smtp_host, port,
      tls: cfg.smtp_secure || port === 465,
      auth: { username: cfg.smtp_user, password: cfg.smtp_pass ?? "" },
    },
  });
  let n = 0;
  // [2L-13] Cierra la conexión SIEMPRE, aunque send() lance.
  try {
    for (const m of utiles) {
      for (const addr of m.to) {
        await client.send({ from: `Portal Familia <${cfg.smtp_user}>`, to: addr, subject: m.subject, html: m.html });
        n++;
      }
    }
  } finally {
    await client.close();
  }
  return n;
}

/// Push best-effort: si falla, no se cae el aviso. Para quien tiene push este
/// es su ÚNICO canal, así que un fallo aquí sí se nota — pero bloquear la
/// transacción del trigger por ello sería peor.
async function enviarPush(userIds: string[], title: string, body: string, data: Record<string, string>) {
  if (!userIds.length) return;
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-push-secret": PUSH_SECRET },
      body: JSON.stringify({ userIds, title, body, data }),
    });
  } catch (_) { /* no bloquea */ }
}

// ---------------------------------------------------------------
// Manejador
// ---------------------------------------------------------------
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
    const actorId = b.actorId ? String(b.actorId) : null;
    const duenoId = b.createdById ? String(b.createdById) : null;

    // Protagonista del aviso: quien creó la reserva, o el autor del informe de
    // salida, que la tabla no guarda y hay que deducir de su reserva.
    let sujetoId = duenoId;
    if (!sujetoId && b.reservationId) {
      const { data: r } = await admin.from("reservations")
        .select("created_by_id").eq("id", String(b.reservationId)).maybeSingle();
      sujetoId = (r as any)?.created_by_id ?? null;
    }

    const [{ data: sujeto }, { data: prop }, { data: canceller }] = await Promise.all([
      sujetoId ? admin.from("profiles").select("name").eq("id", sujetoId).maybeSingle()
               : Promise.resolve({ data: null }),
      b.propertyId ? admin.from("properties").select("name").eq("id", String(b.propertyId)).maybeSingle()
                   : Promise.resolve({ data: null }),
      b.cancelledByUserId ? admin.from("profiles").select("name").eq("id", String(b.cancelledByUserId)).maybeSingle()
                          : Promise.resolve({ data: null }),
    ]);

    const vars: Record<string, string> = {
      PropertyName: (prop as any)?.name ?? "la casa",
      UserName: (sujeto as any)?.name ?? "Alguien",
      CancelledBy: (canceller as any)?.name ?? "Otra persona",
      StartDate: fmt(b.startDate),
      EndDate: fmt(b.endDate),
      OldStartDate: fmt(b.oldStartDate),
      OldEndDate: fmt(b.oldEndDate),
      GuestCount: b.guestCount != null ? String(b.guestCount) : "",
      GeneralStatus: b.generalStatus ? String(b.generalStatus) : "",
      Damages: b.damages ? String(b.damages) : "ninguno",
      MissingItems: b.missingItems ? String(b.missingItems) : "ninguna",
      FormLink: b.reservationId ? `${APP_SCHEME}inspeccion/${String(b.reservationId)}` : "",
    };

    const principales = await principalAdmins();
    const idsPrincipales = new Set(principales.map((p) => p.id));
    const audiencias: Audiencia[] = [];

    /// Añade a una persona suelta, si existe, no es el actor cuando no debe, y
    /// no está ya cubierta por el aviso de administrador (que es más completo).
    const aUnaPersona = async (id: string | null, tipo: string) => {
      if (!id || idsPrincipales.has(id)) return;
      const p = await personas([id]);
      if (p.length) audiencias.push({ tipo, gente: p });
    };

    if (esMantenimiento) {
      const tipo = event === "reservation_cancelled" ? "MAINTENANCE_CANCELLED" : "MAINTENANCE";
      audiencias.push({ tipo, gente: principales, siempreCorreo: true });
      // Todos los demás, menos quien lo creó: no se avisa a alguien de su
      // propio bloqueo.
      const resto = (await todosLosDemas())
        .filter((p) => !idsPrincipales.has(p.id) && p.id !== actorId);
      audiencias.push({ tipo, gente: resto });
    } else if (event === "reservation_created") {
      audiencias.push({ tipo: "ADMIN_RESERVATION_CREATED", gente: principales, siempreCorreo: true });
      // Confirmación SIEMPRE, aunque la haya hecho él mismo: es el acuse.
      await aUnaPersona(duenoId, "USER_RESERVATION_CONFIRMED");
    } else if (event === "reservation_updated" || event === "reservation_cancelled") {
      const cancelada = event === "reservation_cancelled";
      audiencias.push({
        tipo: cancelada ? "ADMIN_RESERVATION_CANCELLED" : "ADMIN_RESERVATION_UPDATED",
        gente: principales, siempreCorreo: true,
      });
      // Al DUEÑO, no a quien hizo el cambio. Si un administrador cancela mi
      // reserva, el que necesita enterarse soy yo; y además el panel de
      // registros no deja consultar una reserva ya borrada. Si fui yo mismo, no
      // hace falta avisarme de lo que acabo de hacer.
      if (duenoId !== actorId) {
        await aUnaPersona(duenoId, cancelada ? "USER_RESERVATION_CANCELLED" : "USER_RESERVATION_UPDATED");
      }
    } else if (event === "waitlist_joined") {
      audiencias.push({ tipo: "ADMIN_WAITLIST_JOINED", gente: principales, siempreCorreo: true });
      await aUnaPersona(duenoId, "USER_WAITLIST_JOINED");
      // Quien tiene esas fechas ahora mismo. Puede no haber nadie, o ser el
      // mismo que se apunta si se solapa con una reserva suya.
      const bloqueador = b.bloqueadorId ? String(b.bloqueadorId) : null;
      if (bloqueador && bloqueador !== duenoId) {
        await aUnaPersona(bloqueador, "USER_WAITLIST_BEHIND_YOU");
      }
    } else if (event === "waitlist_promoted") {
      audiencias.push({ tipo: "ADMIN_WAITLIST_PROMOTED", gente: principales, siempreCorreo: true });
      await aUnaPersona(duenoId, "USER_WAITLIST_PROMOTED");
    } else if (event === "out_report_created") {
      audiencias.push({ tipo: "ADMIN_OUT_REPORT", gente: principales, siempreCorreo: true });
      await aUnaPersona(sujetoId, "USER_OUT_REPORT_DONE");
    } else if (event === "inspection_missing") {
      audiencias.push({ tipo: "ADMIN_INSPECTION_MISSING", gente: principales, siempreCorreo: true });
      await aUnaPersona(duenoId, "INSPECTION_REMINDER");
    } else if (event === "pre_stay") {
      audiencias.push({ tipo: "ADMIN_PRE_STAY", gente: principales, siempreCorreo: true });
      await aUnaPersona(duenoId, "PRE_STAY");
    } else {
      return json({ error: `Evento desconocido: ${event}` }, 400);
    }

    // ---- Reparto ------------------------------------------------------
    // Aquí es donde vive la regla de canal, en un único sitio: push a quien
    // pueda recibirlo, correo a quien no, y las dos cosas al administrador.
    // Modo simulación: calcula el reparto y lo devuelve SIN enviar nada. Existe
    // para poder comprobar la regla de canal contra los datos reales sin
    // mandarle a nadie el aviso de una reserva inventada.
    const simular = b.dryRun === true;
    const plan: Record<string, { push: string[]; correo: string[] }> = {};

    const mensajes: Mensaje[] = [];
    let pushEnviados = 0;
    const datosPush = {
      type: event,
      reservationId: b.reservationId ? String(b.reservationId) : "",
      propertyId: b.propertyId ? String(b.propertyId) : "",
    };

    for (const a of audiencias) {
      if (!a.gente.length) continue;
      const tpl = await getTemplate(a.tipo);
      const asunto = fill(tpl.subject, vars);
      const html = fillHtml(tpl.body, vars);

      const porPush = a.gente.filter((p) => p.push).map((p) => p.id);
      const porCorreo = a.gente
        .filter((p) => p.email && (a.siempreCorreo || !p.push))
        .map((p) => p.email as string);

      if (simular) {
        plan[a.tipo] = { push: porPush, correo: [...new Set(porCorreo)] };
        continue;
      }
      if (porPush.length) {
        await enviarPush(porPush, asunto, aTextoPlano(fill(tpl.body, vars)), datosPush);
        pushEnviados += porPush.length;
      }
      if (porCorreo.length) {
        mensajes.push({ to: [...new Set(porCorreo)], subject: asunto, html });
      }
    }

    if (simular) return json({ ok: true, simulado: true, event, plan });

    const correosEnviados = await enviarCorreos(mensajes);
    return json({ ok: true, event, correos: correosEnviados, push: pushEnviados });
  } catch (e) {
    console.error("notify-changes error:", e);
    return json({ error: "Error interno al notificar el cambio" }, 500);
  }
});
