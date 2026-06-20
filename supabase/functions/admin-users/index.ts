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
// SUPABASE_URL/ANON/SERVICE_ROLE los inyecta Supabase automáticamente. La
// config de Supabase se gestiona en /.env.example; no introduzcas credenciales aquí.
// ===============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
const PRINCIPAL = ["MEGA_ADMIN", "PRINCIPAL_ADMIN"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

async function profileByEmail(email: string) {
  const { data } = await admin.from("profiles").select("id, role").eq("email", email).maybeSingle();
  return data as { id: string; role: string } | null;
}

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

    const { data: prof } = await userClient
      .from("profiles").select("role").eq("id", u.user.id).single();
    if (!prof || !PRINCIPAL.includes(prof.role)) {
      return json({ error: "Requiere administrador principal" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "invite_user") {
      const email = String(body.email ?? "").trim();
      const name = String(body.name ?? "").trim();
      const role = String(body.role ?? "MEMBER");
      const familyGroupId = body.familyGroupId ?? null;
      if (!email || !name) return json({ error: "Faltan nombre o email" }, 400);

      const existing = await profileByEmail(email);
      if (existing) {
        // Ya existe: vincular. NO degradar a un mega/principal.
        const keepRole = PRINCIPAL.includes(existing.role);
        await admin.from("profiles").update({
          ...(keepRole ? {} : { role }),
          ...(familyGroupId ? { family_group_id: familyGroupId } : {}),
        }).eq("id", existing.id);
        return json({ ok: true, userId: existing.id });
      }
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { name, role },
      });
      if (error) return json({ error: error.message }, 400);
      const userId = data.user.id;
      if (familyGroupId) {
        await admin.from("profiles").update({ family_group_id: familyGroupId }).eq("id", userId);
      }
      return json({ ok: true, userId });
    }

    if (action === "create_group") {
      const groupName = String(body.groupName ?? "").trim();
      const ownerName = String(body.ownerName ?? "").trim();
      const ownerEmail = String(body.ownerEmail ?? "").trim();
      const color = String(body.color ?? "#3b82f6");
      if (!groupName) return json({ error: "Falta el nombre del grupo" }, 400);

      const { data: group, error: gErr } = await admin
        .from("family_groups").insert({ name: groupName, color }).select("id").single();
      if (gErr) return json({ error: gErr.message }, 400);
      const groupId = group.id;

      // Propietario OPCIONAL. Si es un mega/principal, NO se degrada.
      if (ownerEmail) {
        const existing = await profileByEmail(ownerEmail);
        let ownerId: string;
        if (existing) {
          ownerId = existing.id;
          const keepRole = PRINCIPAL.includes(existing.role);
          await admin.from("profiles").update({
            family_group_id: groupId,
            ...(keepRole ? {} : { role: "FAMILY_ADMIN" }),
          }).eq("id", ownerId);
        } else {
          const { data, error } = await admin.auth.admin.inviteUserByEmail(ownerEmail, {
            data: { name: ownerName || ownerEmail, role: "FAMILY_ADMIN" },
          });
          if (error) return json({ error: error.message }, 400);
          ownerId = data.user.id;
          await admin.from("profiles").update({ family_group_id: groupId }).eq("id", ownerId);
        }
        await admin.from("family_groups").update({ owner_id: ownerId }).eq("id", groupId);
      }
      return json({ ok: true, groupId });
    }

    if (action === "delete_user") {
      const userId = String(body.userId ?? "");
      if (!userId) return json({ error: "Falta userId" }, 400);
      if (userId === u.user.id) return json({ error: "No puedes borrarte a ti mismo" }, 400);
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Acción no soportada" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
