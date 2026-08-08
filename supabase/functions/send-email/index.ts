// ===============================================================
// send-email — Los dos barridos diarios del cron.
//
// EL NOMBRE YA NO DESCRIBE LO QUE HACE, y se mantiene solo porque los dos
// trabajos de pg_cron apuntan a esta URL: renombrarla obligaría a reescribir
// las tareas programadas para no ganar nada. Esta función ya NO manda correos.
//
// Lo que hace es buscar en la base de datos las dos situaciones que nadie
// provoca —no hay ningún cambio que dispare un trigger, simplemente pasa el
// tiempo— y avisar de cada una a notify-changes:
//
//   inspection_reminders  ->  reservas que terminan HOY y siguen sin formulario
//   pre_stay_reminders    ->  reservas que empiezan dentro de PRE_STAY_DAYS
//
// Quién recibe cada aviso y por qué canal NO se decide aquí: eso vive entero en
// notify-changes, para que haya un solo sitio donde mirarlo. Antes esta función
// mandaba sus propios correos y era el segundo sitio donde había que acordarse
// de cambiar las cosas.
//
// Auth: cabecera x-cron-secret == CRON_SECRET, y el mismo secreto se reenvía a
// notify-changes.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

// [B-05] Comparación en tiempo constante del secreto de cron.
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

// [I-07] Origen permitido configurable (default "*").
const ALLOWED_ORIGIN = Deno.env.get("FUNCTIONS_ALLOWED_ORIGIN") ?? "*";
const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

/// Un aviso por reserva. En serie a propósito: son puñados de filas al día y
/// así notify-changes reutiliza su conexión SMTP entre llamadas seguidas en vez
/// de abrir varias a la vez.
async function avisar(payload: Record<string, unknown>) {
  await fetch(`${SUPABASE_URL}/functions/v1/notify-changes`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-cron-secret": CRON_SECRET },
    body: JSON.stringify(payload),
  });
}

/// Reservas que terminan HOY y aún no tienen informe de salida.
async function barridoFormulariosPendientes() {
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0);
  const manana = new Date(hoy); manana.setDate(manana.getDate() + 1);
  const { data: rows } = await admin.from("reservations")
    .select("id, start_date, end_date, created_by_id, property_id, out_reports(id)")
    .gte("end_date", hoy.toISOString()).lt("end_date", manana.toISOString())
    .eq("is_maintenance", false);

  let n = 0;
  for (const r of rows ?? []) {
    if ((r as any).out_reports?.length) continue;  // ya lo rellenó
    await avisar({
      event: "inspection_missing",
      reservationId: (r as any).id,
      propertyId: (r as any).property_id,
      createdById: (r as any).created_by_id,
      startDate: (r as any).start_date,
      endDate: (r as any).end_date,
    });
    n++;
  }
  return n;
}

/// Reservas que empiezan dentro de PRE_STAY_DAYS días.
///
/// Eran 3 días y pasan a 2 por petición expresa: con 3 el aviso llegaba
/// demasiado pronto para ser útil.
const PRE_STAY_DAYS = 2;
async function barridoEstanciasProximas() {
  const desde = new Date(); desde.setHours(0, 0, 0, 0);
  desde.setDate(desde.getDate() + PRE_STAY_DAYS);
  const hasta = new Date(desde); hasta.setDate(hasta.getDate() + 1);
  const { data: rows } = await admin.from("reservations")
    .select("id, start_date, end_date, created_by_id, property_id")
    .gte("start_date", desde.toISOString()).lt("start_date", hasta.toISOString())
    .eq("is_maintenance", false);

  let n = 0;
  for (const r of rows ?? []) {
    await avisar({
      event: "pre_stay",
      reservationId: (r as any).id,
      propertyId: (r as any).property_id,
      createdById: (r as any).created_by_id,
      startDate: (r as any).start_date,
      endDate: (r as any).end_date,
    });
    n++;
  }
  return n;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  // [2I-11] Solo POST (la lógica asume cuerpo JSON POST).
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);
  try {
    if (!(await cronSecretMatches(req.headers.get("x-cron-secret")))) {
      return json({ error: "No autorizado (cron)" }, 401);
    }
    const body = await req.json().catch(() => ({}));
    const type = String(body.type ?? "");

    if (type === "inspection_reminders") {
      return json({ ok: true, sent: await barridoFormulariosPendientes() });
    }
    if (type === "pre_stay_reminders") {
      return json({ ok: true, sent: await barridoEstanciasProximas() });
    }
    return json({ error: "type no soportado" }, 400);
  } catch (e) {
    console.error("send-email error:", e);
    return json({ error: "Error interno en el barrido" }, 500);
  }
});
