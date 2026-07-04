// ===============================================================
// test-smtp — Envía un correo de prueba con la config SMTP guardada.
// Solo MEGA_ADMIN (es quien gestiona el SMTP).
//
// SUPABASE_URL/ANON/SERVICE_ROLE los inyecta Supabase automáticamente. La
// config de Supabase se gestiona en /.env.example; no introduzcas credenciales aquí.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "No autorizado" }, 401);
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    if (!u?.user) return json({ error: "No autorizado" }, 401);
    const { data: prof } = await userClient.from("profiles").select("role").eq("id", u.user.id).single();
    if (prof?.role !== "MEGA_ADMIN") return json({ error: "Solo el mega administrador" }, 403);

    const body = await req.json().catch(() => ({}));
    const to = String(body.to ?? u.user.email ?? "").trim();
    if (!to) return json({ error: "Falta el correo de destino" }, 400);

    const { data: cfg } = await admin.from("system_config")
      .select("smtp_host, smtp_port, smtp_user, smtp_secure").eq("id", "global").single();
    if (!cfg?.smtp_host || !cfg?.smtp_user) {
      return json({ error: "SMTP no configurado. Rellena los datos y guarda primero." }, 400);
    }
    // [M-07] Contraseña desde Vault (service role); TLS forzado por puerto.
    const { data: pass } = await admin.rpc("get_smtp_password");
    const port = cfg.smtp_port ?? 587;

    const client = new SMTPClient({
      connection: {
        hostname: cfg.smtp_host,
        port,
        tls: cfg.smtp_secure || port === 465,
        auth: { username: cfg.smtp_user, password: (pass as string | null) ?? "" },
      },
    });
    await client.send({
      from: `Portal Familia <${cfg.smtp_user}>`,
      to,
      subject: "Prueba de SMTP — Portal Familia",
      html: "<div style='font-family:sans-serif'><h2>✅ SMTP funcionando</h2><p>Si recibes este correo, la configuración SMTP es correcta.</p></div>",
    });
    await client.close();

    return json({ ok: true, to });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
