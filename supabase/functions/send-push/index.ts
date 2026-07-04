// ===============================================================
// send-push — Envía notificaciones push a los dispositivos de uno o varios
// usuarios vía FCM HTTP v1. Reutilizable por cualquier otra función.
//
// Auth: cabecera x-push-secret == PUSH_SECRET (secreto DEDICADO de push,
// DISTINTO del CRON_SECRET: filtrar el CRON_SECRET ya no basta para spamear
// push). Uso interno: lo llama notify-waitlist y otros disparadores del backend.
//
// Input JSON: { userIds: string[], title: string, body: string,
//               data?: Record<string,string> }
//
// Secrets necesarios:
//   PUSH_SECRET          — secreto DEDICADO solo para invocar send-push.
//   FCM_SERVICE_ACCOUNT  — JSON (string) de la service account de Firebase
//                          con permiso de FCM (Cloud Messaging).
// SUPABASE_URL/SERVICE_ROLE los inyecta Supabase en runtime.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUSH_SECRET = Deno.env.get("PUSH_SECRET") ?? "";
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

// [B-05] Comparación en tiempo constante del secreto de push (ver send-email).
// Hasheamos ambos valores a 32 bytes fijos y comparamos con XOR acumulado: ni
// el tiempo ni la longitud del secreto se filtran.
async function pushSecretMatches(provided: string | null): Promise<boolean> {
  if (!PUSH_SECRET) return false;
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(provided ?? "")),
    crypto.subtle.digest("SHA-256", enc.encode(PUSH_SECRET)),
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
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// ---- OAuth2: firma un JWT con la service account y obtiene access_token ----
function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

let cachedToken: { token: string; exp: number } | null = null;

async function getAccessToken(sa: { client_email: string; private_key: string; token_uri?: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.token;

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = b64url(new TextEncoder().encode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned),
  ));
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tok = await res.json();
  if (!res.ok || !tok.access_token) {
    // [B-04] No filtrar el JSON crudo de OAuth/FCM al cliente; solo al log.
    console.error("send-push OAuth FCM error:", res.status, tok);
    throw new Error("OAuth FCM falló");
  }
  cachedToken = { token: tok.access_token, exp: now + (tok.expires_in ?? 3600) };
  return tok.access_token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!(await pushSecretMatches(req.headers.get("x-push-secret")))) {
      return json({ error: "No autorizado" }, 401);
    }
    if (!FCM_SERVICE_ACCOUNT) return json({ error: "FCM_SERVICE_ACCOUNT no configurado" }, 500);

    const body = await req.json().catch(() => ({}));
    const userIds: string[] = Array.isArray(body.userIds) ? body.userIds : [];
    const title = String(body.title ?? "");
    const text = String(body.body ?? "");
    const data: Record<string, string> = body.data ?? {};
    if (!userIds.length || (!title && !text)) return json({ error: "Faltan userIds o contenido" }, 400);

    const sa = JSON.parse(FCM_SERVICE_ACCOUNT);
    const projectId = sa.project_id;
    const accessToken = await getAccessToken(sa);

    const { data: tokens } = await admin.from("device_tokens")
      .select("token").in("user_id", userIds);
    if (!tokens?.length) return json({ ok: true, sent: 0, note: "Sin dispositivos registrados" });

    let sent = 0;
    const stale: string[] = [];
    for (const { token } of tokens) {
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: { token, notification: { title, body: text }, data },
        }),
      });
      if (r.ok) {
        sent++;
      } else {
        const err = await r.json().catch(() => ({}));
        const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
        // Token caducado/desinstalado → lo limpiamos.
        if (r.status === 404 || code === "UNREGISTERED" || code === "NOT_FOUND") stale.push(token);
      }
    }
    if (stale.length) await admin.from("device_tokens").delete().in("token", stale);

    return json({ ok: true, sent, cleaned: stale.length });
  } catch (e) {
    console.error("send-push error:", e);
    return json({ error: "Error interno al enviar la notificación push" }, 500);
  }
});
