// ===============================================================
// media-sign — Emite URLs prefirmadas de MinIO para subir/ver media
// de inspecciones, tras comprobar permisos con el RLS de Supabase.
//
// Las fotos/vídeos NO van a Supabase: viven en tu MinIO (Docker). Aquí
// solo firmamos una URL temporal; la app sube/descarga directo a MinIO.
//
// Secrets necesarios (supabase secrets set ...):
//   MINIO_ENDPOINT     p.ej. https://media.sanchezrubal.net
//   MINIO_BUCKET       inspections
//   MEDIA_SIGN_ACCESS_KEY  access key DEDICADA de MinIO (Get/Put sobre el bucket; NO la root)
//   MEDIA_SIGN_SECRET_KEY
//   MINIO_REGION       us-east-1   (opcional)
// SUPABASE_URL y SUPABASE_ANON_KEY los inyecta Supabase automáticamente.
// La config de Supabase se gestiona en /.env.example; no introduzcas
// credenciales en este fichero.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const MINIO_ENDPOINT = Deno.env.get("MINIO_ENDPOINT")!;
const MINIO_BUCKET = Deno.env.get("MINIO_BUCKET") ?? "inspections";
const MINIO_ACCESS_KEY = Deno.env.get("MEDIA_SIGN_ACCESS_KEY")!;
const MINIO_SECRET_KEY = Deno.env.get("MEDIA_SIGN_SECRET_KEY")!;
const MINIO_REGION = Deno.env.get("MINIO_REGION") ?? "us-east-1";

const PRINCIPAL = ["MEGA_ADMIN", "PRINCIPAL_ADMIN"];
const FAMILY_ADMIN = ["FAMILY_ADMIN", "FAMILY_SECOND_ADMIN"];
const EXPIRES = "3600"; // 1 h

// [M-02] Allowlist de tipos permitidos (invariante de seguridad → en código, no
// en .env). Bloquea HTML/SVG y otros que permitirían XSS almacenado servido desde
// el dominio de media. Clave = extensión (minúsculas); valor = Content-Type que se
// FIRMA y con el que queda almacenado el objeto.
const ALLOWED_TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  heic: "image/heic",
  heif: "image/heif",
  mp4: "video/mp4",
  mov: "video/quicktime",
  webm: "video/webm",
};

// [M-02] Tope de tamaño por subida (límite de despliegue → configurable en .env).
const MAX_UPLOAD_BYTES = Number(
  Deno.env.get("MEDIA_MAX_UPLOAD_BYTES") ?? "104857600", // 100 MiB
);

function extOf(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "No autorizado" }, 401);

    // Cliente con el JWT del usuario → respeta RLS.
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return json({ error: "No autorizado" }, 401);
    const uid = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const op = body.op as "put" | "get";
    const reservationId = String(body.reservationId ?? "");
    if (!reservationId) return json({ error: "Falta reservationId" }, 400);

    const { data: profile } = await supabase
      .from("profiles").select("role, family_group_id").eq("id", uid).single();
    if (!profile) return json({ error: "Perfil no encontrado" }, 403);

    const { data: reservation } = await supabase
      .from("reservations").select("created_by_id, family_group_id")
      .eq("id", reservationId).single();
    if (!reservation) return json({ error: "Reserva no encontrada" }, 404);

    const isPrincipal = PRINCIPAL.includes(profile.role);
    const isGroupAdmin = isPrincipal ||
      (FAMILY_ADMIN.includes(profile.role) &&
        profile.family_group_id === reservation.family_group_id);
    const isCreator = reservation.created_by_id === uid;
    const canWrite = isCreator || isGroupAdmin;
    const canRead = canWrite || isPrincipal;

    const aws = new AwsClient({
      accessKeyId: MINIO_ACCESS_KEY,
      secretAccessKey: MINIO_SECRET_KEY,
      service: "s3",
      region: MINIO_REGION,
    });

    if (op === "put") {
      if (!canWrite) return json({ error: "Sin permiso para subir" }, 403);

      // 1) Validar extensión y derivar el Content-Type canónico. Object.hasOwn
      //    evita consultar la cadena de prototipos (ext "__proto__"/"constructor"
      //    colarían un valor heredado y saltarían el allowlist). [M-02]
      const rawName = String(body.filename ?? "");
      const ext = extOf(rawName);
      const contentType = Object.hasOwn(ALLOWED_TYPES, ext)
        ? ALLOWED_TYPES[ext]
        : undefined;
      if (typeof contentType !== "string") {
        return json({ error: "Tipo de archivo no permitido" }, 415);
      }

      // 2) Validar el tamaño declarado contra el máximo.
      const size = Number(body.size);
      if (!Number.isFinite(size) || size <= 0) {
        return json({ error: "Falta el tamaño del archivo (size)" }, 400);
      }
      if (size > MAX_UPLOAD_BYTES) {
        return json({ error: "Archivo demasiado grande", maxBytes: MAX_UPLOAD_BYTES }, 413);
      }

      const safe = rawName.replace(/[^a-zA-Z0-9._-]/g, "_");
      const key = `${reservationId}/${crypto.randomUUID()}-${safe}`;
      const url = `${MINIO_ENDPOINT}/${MINIO_BUCKET}/${key}?X-Amz-Expires=${EXPIRES}`;

      // 3) Firmar el PUT incluyendo Content-Type en las SignedHeaders
      //    (allHeaders:true): el objeto SOLO puede subirse con este Content-Type.
      //    El cliente DEBE reenviar exactamente esta cabecera. [M-02]
      const signed = await aws.sign(
        new Request(url, { method: "PUT", headers: { "Content-Type": contentType } }),
        { aws: { signQuery: true, allHeaders: true } },
      );

      return json({
        url: signed.url,
        key,
        method: "PUT",
        headers: { "Content-Type": contentType },
        maxBytes: MAX_UPLOAD_BYTES,
      });
    }

    if (op === "get") {
      if (!canRead) return json({ error: "Sin permiso para ver" }, 403);
      const rawKey = String(body.key ?? "");
      // [M-01] Decodifica una vez para detectar traversal percent-encoded. Las
      // keys legítimas que emite 'put' nunca llevan percent-encoding (su sanitizado
      // reemplaza '%' y '/' por '_'); si al decodificar cambia, venía manipulada.
      let key: string;
      try {
        key = decodeURIComponent(rawKey);
      } catch {
        return json({ error: "Clave inválida" }, 400);
      }
      const prefix = `${reservationId}/`;
      // 'put' genera "<reservationId>/<uuid>-<archivo>": un único '/'. Exigir un
      // único segmento tras el prefijo bloquea todo traversal ('..', '//', subrutas,
      // barra absoluta, backslash) sin rechazar nombres con '..' dentro del fichero.
      const object = key.startsWith(prefix) ? key.slice(prefix.length) : "";
      const invalid =
        !key ||
        key !== rawKey ||
        !object ||
        object.includes("/") ||
        key.includes("\\");
      if (invalid) {
        return json({ error: "Clave inválida" }, 400);
      }
      const url = `${MINIO_ENDPOINT}/${MINIO_BUCKET}/${key}?X-Amz-Expires=${EXPIRES}`;
      const signed = await aws.sign(new Request(url, { method: "GET" }), {
        aws: { signQuery: true },
      });
      return json({ url: signed.url, key, method: "GET" });
    }

    return json({ error: "op debe ser 'put' o 'get'" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
