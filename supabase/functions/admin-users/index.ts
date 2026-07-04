// ===============================================================
// admin-users — Operaciones de administración de usuarios/grupos que
// requieren la Admin API de Supabase Auth. Solo admin principal.
//
// Acciones (body.action):
//   invite_user   { name, email, role, familyGroupId? }
//   create_group  { groupName, color?, ownerName?, ownerEmail? }  (propietario OPCIONAL)
//   delete_user   { userId }
//
// IMPORTANTE: el rol global manda. Un MEGA_ADMIN / PRINCIPAL_ADMIN que
// se mete en un grupo NO se degrada (conserva su rol).
//
// Seguridad:
//   - [C-01] El rol NO viaja por raw_user_meta_data. Tras invitar (el trigger
//     crea el profile como MEMBER) se fija el rol validado vía service_role.
//   - [A-01] Techo de rol: un PRINCIPAL_ADMIN no puede crear/ascender a
//     MEGA_ADMIN ni a PRINCIPAL_ADMIN. Solo un MEGA_ADMIN gestiona esos roles.
//   - [M-10] delete_user con salvaguardas (no borrar megas desde principal,
//     no borrar al último mega). owner_id de grupos queda NULL por el FK.
//   - [B-04] Errores genéricos al cliente; el detalle va solo a los logs.
//
// SUPABASE_URL/ANON/SERVICE_ROLE los inyecta Supabase automáticamente.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
const PRINCIPAL = ["MEGA_ADMIN", "PRINCIPAL_ADMIN"];

const VALID_ROLES = [
  "MEGA_ADMIN",
  "PRINCIPAL_ADMIN",
  "FAMILY_ADMIN",
  "FAMILY_SECOND_ADMIN",
  "MEMBER",
];

// Techo de rol [A-01]: qué roles puede ASIGNAR cada llamante.
// El mega gestiona todo; el principal, solo de FAMILY_ADMIN hacia abajo.
function assignableRoles(callerRole: string): string[] {
  if (callerRole === "MEGA_ADMIN") return VALID_ROLES;
  if (callerRole === "PRINCIPAL_ADMIN") {
    return ["FAMILY_ADMIN", "FAMILY_SECOND_ADMIN", "MEMBER"];
  }
  return [];
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Respuesta de error genérica; el detalle real solo a logs [B-04].
function fail(status: number, publicMsg: string, detail?: unknown) {
  if (detail !== undefined) console.error(`admin-users: ${publicMsg}`, detail);
  return json({ error: publicMsg }, status);
}

async function profileByEmail(email: string) {
  const { data } = await admin.from("profiles").select("id, role").eq("email", email).maybeSingle();
  return data as { id: string; role: string } | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return fail(401, "No autorizado");

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: u } = await userClient.auth.getUser();
    if (!u?.user) return fail(401, "No autorizado");

    const { data: prof } = await userClient
      .from("profiles").select("role").eq("id", u.user.id).single();
    if (!prof || !PRINCIPAL.includes(prof.role)) {
      return fail(403, "Requiere administrador principal");
    }
    const callerRole = prof.role as string;

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "invite_user") {
      const email = String(body.email ?? "").trim();
      const name = String(body.name ?? "").trim();
      const role = String(body.role ?? "MEMBER");
      const familyGroupId = body.familyGroupId ?? null;
      if (!email || !name) return fail(400, "Faltan nombre o email");
      if (!assignableRoles(callerRole).includes(role)) {
        return fail(403, "No tienes permiso para asignar ese rol");
      }

      const existing = await profileByEmail(email);
      if (existing) {
        // Ya existe: vincular. NO degradar a un mega/principal.
        const keepRole = PRINCIPAL.includes(existing.role);
        const { error } = await admin.from("profiles").update({
          ...(keepRole ? {} : { role }),
          ...(familyGroupId ? { family_group_id: familyGroupId } : {}),
        }).eq("id", existing.id);
        if (error) return fail(400, "No se pudo vincular el usuario", error);
        return json({ ok: true, userId: existing.id });
      }

      // Nuevo: el trigger handle_new_user lo crea como MEMBER; fijamos aquí el
      // rol ya validado (el rol NO viaja por metadata) [C-01].
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { name },
      });
      if (error) return fail(400, "No se pudo invitar al usuario", error);
      const userId = data.user.id;
      const { error: upErr } = await admin.from("profiles").update({
        role,
        ...(familyGroupId ? { family_group_id: familyGroupId } : {}),
      }).eq("id", userId);
      if (upErr) return fail(400, "No se pudo asignar el rol", upErr);
      return json({ ok: true, userId });
    }

    if (action === "create_group") {
      const groupName = String(body.groupName ?? "").trim();
      const ownerName = String(body.ownerName ?? "").trim();
      const ownerEmail = String(body.ownerEmail ?? "").trim();
      const color = String(body.color ?? "#3b82f6");
      if (!groupName) return fail(400, "Falta el nombre del grupo");

      const { data: group, error: gErr } = await admin
        .from("family_groups").insert({ name: groupName, color }).select("id").single();
      if (gErr) return fail(400, "No se pudo crear el grupo", gErr);
      const groupId = group.id;

      // Propietario OPCIONAL (rol FAMILY_ADMIN, dentro del techo de cualquier
      // principal). Si ya es un mega/principal, NO se degrada.
      if (ownerEmail) {
        const existing = await profileByEmail(ownerEmail);
        let ownerId: string;
        if (existing) {
          ownerId = existing.id;
          const keepRole = PRINCIPAL.includes(existing.role);
          const { error } = await admin.from("profiles").update({
            family_group_id: groupId,
            ...(keepRole ? {} : { role: "FAMILY_ADMIN" }),
          }).eq("id", ownerId);
          if (error) return fail(400, "No se pudo vincular al propietario", error);
        } else {
          const { data, error } = await admin.auth.admin.inviteUserByEmail(ownerEmail, {
            data: { name: ownerName || ownerEmail },
          });
          if (error) return fail(400, "No se pudo invitar al propietario", error);
          ownerId = data.user.id;
          const { error: upErr } = await admin.from("profiles").update({
            family_group_id: groupId,
            role: "FAMILY_ADMIN",
          }).eq("id", ownerId);
          if (upErr) return fail(400, "No se pudo asignar el propietario", upErr);
        }
        await admin.from("family_groups").update({ owner_id: ownerId }).eq("id", groupId);
      }
      return json({ ok: true, groupId });
    }

    if (action === "delete_user") {
      const userId = String(body.userId ?? "");
      if (!userId) return fail(400, "Falta userId");
      if (userId === u.user.id) return fail(400, "No puedes borrarte a ti mismo");

      // Salvaguardas [M-10]: proteger a los mega-admin.
      const { data: target } = await admin
        .from("profiles").select("role").eq("id", userId).maybeSingle();
      const targetRole = (target as { role: string } | null)?.role ?? null;
      if (targetRole === "MEGA_ADMIN") {
        if (callerRole !== "MEGA_ADMIN") {
          return fail(403, "Solo un mega-admin puede borrar a otro mega-admin");
        }
        const { count } = await admin
          .from("profiles").select("id", { count: "exact", head: true }).eq("role", "MEGA_ADMIN");
        if ((count ?? 0) <= 1) return fail(400, "No puedes borrar al último mega-admin");
      }

      // family_groups.owner_id queda NULL por el FK ON DELETE SET NULL.
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return fail(400, "No se pudo borrar el usuario", error);
      return json({ ok: true });
    }

    return fail(400, "Acción no soportada");
  } catch (e) {
    return fail(500, "Error interno", e);
  }
});
