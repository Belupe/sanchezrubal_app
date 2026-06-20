# Referencia del proyecto legacy (Next.js) — extracción completa

> Estos documentos son la **extracción fiel y completa** de la app Next.js original
> (`legacy-next/`, ya **eliminada del repo**) hecha antes de borrarla. Son la
> especificación de referencia para terminar la app Flutter + Supabase. Capturan
> *todo* lo que tenía el proyecto: funciones, datos, configuración, detalles de uso.

## Índice

| Doc | Contenido |
|-----|-----------|
| [01-backend-funciones-datos.md](01-backend-funciones-datos.md) | Server Actions (cada función, validaciones, permisos, efectos), modelo Prisma, sesión/JWT, rate-limit, middleware, **cron** (avisos, archivado anual, Excel), inventario de correos |
| [02-ui-casas-config-anuncios.md](02-ui-casas-config-anuncios.md) | UI: layout/navegación, Inicio/anuncios, Domicilios, calendario de casa, **Configuración** (SMTP, notificaciones, plantillas, límites), preferencias |
| [03-ui-usuarios-sorteos-publicas.md](03-ui-usuarios-sorteos-publicas.md) | UI: Usuarios/grupos, Perfil, Reportes, **Sorteos**, Login/Init, recuperar/restablecer, Checkout, **formulario post-estancia** |
| [04-configuracion-despliegue-manual.md](04-configuracion-despliegue-manual.md) | Variables de entorno, next.config, package.json, **Docker**, logs, y el **manual de usuario** (LEEME.html) íntegro |

## Mapeo de roles: legacy → nuevo (Supabase)

| Legacy | Nuevo | Notas |
|--------|-------|-------|
| `MEGA_ADMIN` | `MEGA_ADMIN` | Igual (superusuario). |
| `SUPER_ADMIN` | `PRINCIPAL_ADMIN` | Renombrado ("administrador principal"). |
| `FAMILY_ADMIN` | `FAMILY_ADMIN` | Propietario del grupo (ahora con `owner_id`). |
| — | `FAMILY_SECOND_ADMIN` | **Nuevo**: coadministrador (la pareja). No existía. |
| `MEMBER` | `MEMBER` | Igual. |

## ⚠️ Reglas de negocio del legacy AÚN NO portadas a Flutter+Supabase

Pendientes de implementar al completar la app (la lógica exacta está en los docs):

- **Límite de días de reserva** (`max_reservation_days`, default 15): el campo existe en `system_config` pero **no se valida** todavía (ni en RLS ni en Flutter). Ver doc 01 (`createReservation`) y doc 02 (§4.6 Límites).
- **Sorteo (algoritmo Fisher-Yates)**: asignación aleatoria de quincenas/premios a familias. Ver doc 01 (`runSorteo`) y doc 03 (§4). Habría que portarlo a una Edge Function o lógica cliente.
- **Archivado anual a Excel (31 dic)**: el cron viejo exportaba el año a `.xlsx` y purgaba el año vencido. El nuevo cron solo hace recordatorios de inspección. Ver doc 01 (cron) y doc 04 (§7).
- **Aviso pre-estancia (2 días antes)** con texto de "reglas de casa" configurable, y **recordatorio mensual (día 1)**: no portados (en el nuevo modelo varias notificaciones pasan a push). Ver doc 02 (§4.4) y doc 04 (§7).
- **Enlace fantasma por email**: al crear grupo/miembro con un email ya existente, el legacy reasignaba ese usuario como admin del grupo sin duplicar. Relevante para el flujo de invitaciones. Ver doc 04 (§7 Parte 2).
- **Purga total (`wipeStorage`)**: acción destructiva de admin (borra fotos + reportes). Ver doc 02 (§4.3.2).
- **Preferencia de tamaño de fuente** (`uiPreferences.fontSize`). Ver doc 02 (§5.2).
- **Pantallas que en Flutter son placeholders**: Casas (CRUD), Usuarios/grupos, Sorteos, Configuración, Anuncios.

## Nota importante

El nuevo sistema **reemplaza**, no adapta, este código. La lógica de datos ya está en
`supabase/migrations/`, los correos/cron en `supabase/functions/`, y la UI se rehace en
`app_flutter/`. Estos docs solo sirven de referencia funcional.
