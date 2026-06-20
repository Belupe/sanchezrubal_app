# Cutover — migrar datos y retirar Next

Paso FINAL, manual, porque depende de tus datos reales y de tu infra en marcha.
Hazlo cuando el backend (Supabase), MinIO y la app Flutter estén verificados.

## 0. Pre-requisitos

- Migraciones `0001`–`0007` aplicadas (ya está). 
- MinIO en marcha (`infra/`) + secrets de `media-sign` puestos.
- `CRON_SECRET` puesto en `send-email` (ver `docs/ARQUITECTURA.md`).
- SMTP rellenado en `system_config` y MEGA_ADMIN creado.
- cloudflared apuntando al nuevo stack.

## 1. Migrar datos (SQLite viejo → Postgres)

Reto: los IDs pasan de `cuid` (text) a `uuid`, y cada `User` antiguo debe
convertirse en un usuario de **Supabase Auth**.

Plan:
1. Localiza la BD vieja: `legacy-next/prisma/dev.db` (o el `familia.db` de tu
   servidor de producción).
2. Por cada `User`: crea un usuario en Auth (admin API) con su email. Para el
   MEGA_ADMIN que entraba por nombre, usa un email real. Guarda el mapeo
   `viejo_id → nuevo uuid` (= `auth.users.id`). El trigger `handle_new_user`
   crea el `profile`; luego haz `UPDATE` de `role`, `name`, `family_group_id`.
3. Inserta `family_groups` y `properties` con uuid nuevos; guarda los mapeos.
4. Inserta `reservations`, `out_reports`, `announcements`, `sorteos`,
   `sorteo_resultados`, `notification_settings`, remapeando TODAS las FKs.
5. **Contraseñas**: NO migran (bcrypt de Prisma ≠ GoTrue). Cada usuario usará
   "contraseña olvidada", o reenvías invitaciones desde la app.

Esqueleto de script (Node; ejecútalo con el `service_role` key, NUNCA en cliente):

```js
// scripts/migrate-data.mjs  —  npm i better-sqlite3 @supabase/supabase-js
import Database from 'better-sqlite3';
import { createClient } from '@supabase/supabase-js';

const db = new Database('legacy-next/prisma/dev.db');
const sb = createClient(process.env.SUPABASE_URL, process.env.SERVICE_ROLE_KEY);
const idMap = new Map(); // viejo_id -> nuevo uuid

// 1) Usuarios -> Auth + profiles
for (const u of db.prepare('SELECT * FROM User').all()) {
  const email = u.email ?? `${u.id}@placeholder.local`;
  const { data, error } = await sb.auth.admin.createUser({
    email, email_confirm: true,
    user_metadata: { name: u.name, role: u.role },
  });
  if (error) { console.error(email, error.message); continue; }
  idMap.set(u.id, data.user.id);
}
// 2) family_groups, properties, reservations... (genera uuid, remapea FKs)
//    usando sb.from('...').insert(...) y idMap para las referencias.
```

## 2. Migrar imágenes de reportes (base64/disco → MinIO)

Las imágenes viejas estaban en `OutReport.imageUrls` (base64/JSON) o en
`uploads_data/`. Para cada una: súbela a MinIO bajo `{reservation_id}/...`
(con el cliente S3 o `mc cp`) y guarda la clave resultante en
`out_reports.media_urls` (`[{type:'photo', key:'...'}]`).

## 3. Conmutar el tráfico

1. `cd infra && docker compose up -d --build`
2. Configura el ingress de cloudflared (`infra/cloudflared/config.example.yml`)
   y los DNS del túnel.
3. Verifica end-to-end: login, calendario, crear reserva, subir inspección.

## 4. Retirar Next

1. Para el contenedor viejo (en tu servidor): `docker compose down` del
   despliegue antiguo de `belupe/portal-familia`.
2. Cuando TODO esté verificado en producción, borra `legacy-next/`.
3. **Revoca/rota** el certificado origin de Cloudflare si aún no lo hiciste
   (la carpeta `Cloudflare/` con la clave privada ya se eliminó del repo).
```
