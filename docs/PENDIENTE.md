# Pendiente

Lista viva de lo acordado pero **no hecho todavía**. Aquí se acumula todo —cambios,
anotaciones, cosas a tener en cuenta— en vez de ir tocando y compilando por cada
detalle suelto.

> **Cuándo se pone en marcha:** cuando la **1.5.0 esté publicada en la App Store**.
> Hasta entonces solo se anota.

Cada punto dice si **obliga a recompilar la app** (viaja en la siguiente build) o si
se despliega solo (backend, documentación, CI).

---

## Tanda 1 — HECHA el 30/8/2026 (va en la 1.5.1)

Los cinco puntos, más el acumulado, están aplicados. Detalle en el apartado
**Hecho** del final.

## Acumulado de antes

~~**Etiquetas de las plantillas nuevas en el editor**~~ — HECHO el 30/8/2026.
**Recompila la app.** `app_flutter/lib/screens/config_screen.dart:491`

`_label()` traduce los tipos de `notification_templates` a nombres legibles con un
`switch` que solo cubre cuatro. La migración `0027` añadió seis tipos
(`ADMIN_RESERVATION_CREATED` / `UPDATED` / `CANCELLED`, `ADMIN_WAITLIST_JOINED`,
`ADMIN_OUT_REPORT`, `MAINTENANCE_CANCELLED`) que salen en el editor con su nombre
crudo. Es puramente cosmético; por eso se aplazó.

---

## Ideas anotadas, sin decidir

Cosas vistas que **no** entran en la tanda 1 y que habría que hablar antes de tocar:

- **`main.dart` hace de módulo global.** Guarda el cliente de Supabase, el
  `navigatorKey` y los cuatro `ValueNotifier`, además del arranque, y todos los
  servicios hacen `import '../main.dart'`. Es la razón de que solo se pueda probar
  lo que son funciones puras: nada que toque datos es comprobable sin red. Sacar el
  cliente y los notifiers a un `lib/app_state.dart` es mecánico y abriría la puerta
  a tests de verdad.
- **`supabase/` está fuera del repositorio** (por `.gitignore`, al ser público).
  Eso deja ~5.000 líneas de SQL y ~1.700 de Edge Functions —donde vive toda la
  seguridad— sin historial ni copia fuera de este Mac. Un repositorio privado
  aparte, o hacer privado este, resolvería las dos cosas.
- **`config_screen.dart` va por 1.056 líneas** con cinco pestañas dentro. Trocear
  por pestaña es mecánico y no urge, pero es el fichero que va a seguir creciendo.
- **Repetición en las pantallas:** el patrón `_load()` + `setState` + `try/catch` se
  repite en diez, y solo hay un widget compartido (`password_widgets.dart`) para 21
  pantallas.

---

## Limitaciones conocidas que NO se van a tocar

- **RLS es por filas, no por columnas:** un `FAMILY_ADMIN` puede editar también el
  `name` y la `image` de los miembros de su grupo. Aceptado a conciencia (ver la
  migración `0024_family_admin_gestiona_su_grupo.sql`).
- **Los ficheros de MinIO no se borran** al eliminar una reserva o un informe: se
  acumulan huérfanos. Se resolvería con un trabajo periódico que compare las claves
  del bucket contra `out_reports`; de momento no compensa.
- **Protección de contraseñas filtradas (HIBP): no disponible.** Requiere plan Pro
  de Supabase; el API devuelve 402. No es un clic olvidado, está tras muro de pago.

---

## Hecho

- **Puerto SMTP por defecto 587 → 465** (acordado el 6/8/2026). Verificado el
  29/8/2026: `test-smtp:57`, `notify-changes:206` y `send-log:171` usan ya `?? 465`.
- **Política de contraseñas del servidor** (`password_min_length=10` + minúscula,
  mayúscula y número), aplicada el 15/8/2026 por la Management API.
- **Caducidad del OTP a 24 h** y **las 11 plantillas de Auth en español**, aplicadas
  el 15/8/2026 por la Management API.
- **Texto de primerizos en el login**, checklist de contraseña en vivo y ojo de ver
  contraseña (commit `4864f27`, 15/8/2026).

- **Tanda 1 completa, 30/8/2026** (va en la 1.5.1):
  1. **README al día**: Android ya no se contradice (Google Play, prueba interna),
     migraciones 0001–0047, Edge Functions reales (se citaba `notify-waitlist`, que
     no existe), Novedades reescrita con lo de la 1.4/1.5 y la publicación real.
  2. **Perfil cacheado en memoria** (`data_service.dart`), invalidado en
     `onAuthStateChange` y tras cada escritura en `profiles`. Deja de bajarse el
     avatar en base64 en cada `currentRole()` / `preferenciasAviso()`.
  3. **La caché sin conexión ya no tapa fallos de permisos**: solo sirve la copia
     ante errores de transporte (`SocketException`, `ClientException`, timeouts…);
     un rechazo del RLS se propaga a la pantalla.
  4. **`ui_preferences` se fusiona en la BD** (migración `0047`, RPC
     `merge_ui_preferences`, verificado en vivo): se acabó el leer-fusionar-escribir
     desde el cliente y el riesgo de que dos guardados se pisaran.
  5. **CI**: `.github/workflows/app-checks.yml` ejecuta `flutter analyze` y
     `flutter test` en cada push a `main` y en cada PR, con Flutter fijado a 3.44.9.
  6. **Etiquetas de plantillas**: las 28 de `notification_templates` traducidas
     (había 4); antes salían con el nombre crudo.
- **Icono de iOS a sangre** (commit `6aa7e8a`): tenía 192 px de margen blanco y iOS
  le aplica encima su propia máscara, así que se veía un cuadro dentro de otro.
  macOS se deja como está: allí el margen es correcto por diseño.
