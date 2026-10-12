# Supabase autoalojado

Desde la versión 1.5.2 la app ya no usa Supabase Cloud: el backend corre en el
servidor propio, con el compose oficial *self-hosted* de Supabase y los ajustes
de [`server/supabase-sr/`](../server/supabase-sr/).

## Qué hay

| Qué | Dónde |
|---|---|
| Compose oficial (`self-hosted/v0.8.2`) | carpeta del stack en el servidor |
| Ajustes de este proyecto | `server/supabase-sr/docker-compose.sr.yml` |
| Enrutador de las Edge Functions | `server/supabase-sr/functions/main/index.ts` |
| Variables | sección 7 de `.env.example` |

El override cambia el nombre del proyecto y de los contenedores para poder
convivir con otro Supabase en la misma máquina, no publica Postgres, añade la
política de contraseñas, MFA y límites de Auth, y pasa a las funciones sus
secretos.

## Qué sale a internet

Un solo nombre público, por el túnel de Cloudflare, con dos reglas:

| Ruta | Destino |
|---|---|
| `/auth/v1/`, `/rest/v1/`, `/realtime/v1/`, `/functions/v1/` | la pasarela (`API_GW_HTTP_PORT`) |
| todo lo demás (el Studio) | `studio-sso` (`STUDIO_SSO_PORT`) |

La app no puede pasar por un inicio de sesión web, así que la API va directa:
la protegen las claves y el RLS, igual que en la nube. El Studio autoalojado no
trae login propio; delante hay un oauth2-proxy que exige entrar con el SSO y
pertenecer al grupo de administradores.

## Instalar

```bash
sh setup.sh -y --skip-deps --project-dir <carpeta> --ref self-hosted/v0.8.2
cp server/supabase-sr/docker-compose.sr.yml <carpeta>/
cp server/supabase-sr/functions/main/index.ts <carpeta>/volumes/functions/main/
# rellenar en <carpeta>/.env la sección 7 de .env.example
cd <carpeta>
docker compose config | head -1     # debe decir: name: supabase-sr
sh run.sh start
```

Las funciones del proyecto se copian a `volumes/functions/<nombre>/index.ts`.
`send-email`, `send-push`, `notify-changes` y `health` van en `FUNCTIONS_PUBLIC`
porque se protegen con su propio secreto o son públicas a propósito; al resto
el enrutador le exige un JWT válido.

## Diferencias con la nube

- **Secretos de las funciones**: van en el `.env` del stack, no se suben con la
  CLI. Tras cambiarlos: `sh run.sh recreate functions`.
- **Llamadas de la base de datos a las funciones**: por la red interna de
  Docker (`http://functions:9000/<función>`), no por la URL pública.
- **Vault**: no viaja en un volcado (la clave de cifrado es otra). `cron_secret`
  y `smtp_pass` se recrean, y `cron_secret` tiene que coincidir con el
  `CRON_SECRET` del `.env` del stack.
- **Auth**: la versión autoalojada va por detrás de la de la nube. Al migrar
  datos de `auth` hay que copiar solo las tablas y columnas comunes.
- **Copias de seguridad**: ya no las hace nadie por ti.

## Salud

`/functions/v1/health?check=` admite `bd`, `cron`, `push`, `smtp`, `auth`, `api`,
`realtime`, `media` y `all`. Responde `ok` o `false` en texto plano.
