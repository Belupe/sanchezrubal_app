# Pendiente

Lista viva de lo acordado pero **no hecho todavía**. Aquí se acumula todo —cambios,
anotaciones, cosas a tener en cuenta— en vez de ir tocando y compilando por cada
detalle suelto.

> **Cuándo se pone en marcha:** cuando la **1.5.0 esté publicada en la App Store**.
> Hasta entonces solo se anota.

Cada punto dice si **obliga a recompilar la app** (viaja en la siguiente build) o si
se despliega solo (backend, documentación, CI).

---

## Tanda 1 — al publicar la 1.5.0

### 1. Poner el README al día

**No recompila.** Solo documentación.

El README se ha quedado atrás en varios puntos concretos:

- **Se contradice a sí mismo con Android.** La tabla de la cabecera (línea 8) dice
  «APK propio alojado en tu Docker (sin Google Play)», y más abajo la línea 89 y la
  103 dicen que Android va por **Google Play** con `build-aab.ps1`. Lo cierto es lo
  segundo: `pubspec.yaml` documenta que `open_filex`/`permission_handler` se
  eliminaron precisamente porque ya no hay auto-update de APK.
- **Rango de migraciones.** Dice `0001–0021`; van por la **0046**.
- **Edge Functions.** Lista `notify-waitlist`, que **no existe**. Las que hay son:
  `admin-users`, `health`, `media-sign`, `notify-changes`, `send-email`, `send-log`,
  `send-push`, `test-smtp`.
- **Repasar «Novedades»** entera: describe la 1.3/1.4 y no menciona el modo sin
  conexión ni los invitados por reserva, que son de la 1.5.0.
- Comprobar de paso que lo de iOS («App Store privado, no listado») sigue siendo el
  plan tras la publicación real.

### 2. Dejar de releer el perfil en cada llamada

**Recompila la app.** `app_flutter/lib/services/data_service.dart`

`myProfile()` (línea 26) lanza una consulta cada vez que se le llama, y encima de
ella cuelgan `currentRole()` (45), `preferenciasAviso()` (116) y `onboardingVisto()`
(127). Cada una es un viaje de ida y vuelta a la base de datos con **el mismo
`select`**; en el arranque se repite varias veces seguidas.

Agrava el problema que ese `select` arrastra la columna `image`, que hoy guarda el
avatar en base64 con un tope de 700.000 caracteres (línea 52): se pueden estar
bajando ~500 KB en cada una de esas llamadas repetidas.

**Cómo:** cachear el perfil en memoria e invalidarlo en `onAuthStateChange` (cierre
de sesión y cambio de usuario) y después de cualquier escritura sobre `profiles`.

**Anotación aparte, para más adelante:** el avatar debería vivir en MinIO como el
resto de media, no dentro de una columna de Postgres. Es un cambio mayor (migración
+ pantallas + subida firmada) y no entra en esta tanda.

### 3. Que la caché sin conexión no tape los fallos de permisos

**Recompila la app.** `app_flutter/lib/services/offline_cache.dart:36`

`OfflineCache.lista()` envuelve la consulta en un `catch (e)` que se traga
**cualquier** excepción y sirve la copia guardada. Eso está pensado para la falta de
cobertura, pero hoy también absorbe cosas que no son de red: un rechazo de permisos
del RLS, un cambio de esquema o un fallo al interpretar la respuesta. En todos esos
casos la app dice «sin conexión» y muestra datos viejos como si fueran buenos.

Es justo el escenario que la arquitectura no quiere: **si a alguien se le retiran
permisos, la pantalla le sigue enseñando lo que ya no le corresponde**, y encima sin
señal de que algo va mal.

**Cómo:** filtrar por tipo de error. Servir la caché solo ante fallos de transporte
—`SocketException`, `ClientException`, tiempos de espera agotados— y dejar que el
resto se propague (`rethrow`) para que la pantalla muestre el error de verdad.

### 4. Escritura atómica de `ui_preferences`

**Backend + app.** `app_flutter/lib/services/data_service.dart:87`

`_mergeUiPreferences()` **lee** la columna, la fusiona en el cliente y la **vuelve a
escribir** entera. Entre la lectura y la escritura no hay nada que impida que otra
guarde por medio, y por esa misma función pasan el tema (101), el onboarding (104) y
las preferencias de aviso (125).

Resultado: dos cambios casi a la vez —o desde dos dispositivos del mismo usuario— y
uno pisa al otro sin avisar. El síntoma futuro sería «se me desactivan solas las
notificaciones», imposible de reproducir a voluntad.

**Cómo:** fusionar en la base de datos, no en el cliente. Un RPC que haga
`update profiles set ui_preferences = coalesce(ui_preferences, '{}'::jsonb) || p_patch
where id = auth.uid()`, y que `_mergeUiPreferences` pase a ser una sola llamada a ese
RPC. Migración nueva + cambio de una función en la app.

### 5. CI que ejecute `flutter analyze` y `flutter test`

**No recompila.** Fichero nuevo en `.github/workflows/`.

Hoy el único workflow (`media-scrub.yml`) publica una imagen de Docker. **Nada
comprueba la app automáticamente**: el analizador y los tests se lanzan a mano.

> **Aclaración sobre esto** (venía una duda al respecto): lo que se propone **es
> exactamente un workflow**, el mismo mecanismo que `media-scrub.yml`. No se está
> cambiando de formato. La comparación no es «workflow contra otra cosa», sino
> **automático contra a mano**:
>
> - Lo que se degrada con el tiempo es **la comprobación manual**: se olvida, o
>   pasan semanas sin tocar el proyecto y al volver no se sabe qué estaba verde.
> - Un workflow **también envejece**, es cierto —las versiones de las acciones se
>   quedan viejas, como ya pasó con el aviso de Node 20 → 24 que está documentado en
>   `media-scrub.yml`—, pero envejece **en rojo y a la vista**, no en silencio.
>   Mantenerlo es revisar versiones de acciones una o dos veces al año.
> - En un repositorio público, Actions no cuesta minutos.

**Cómo:** workflow que se dispare en `push` a `main` y en `pull_request`, con
`subosito/flutter-action` fijando la misma versión de Flutter que se usa en local
(hoy 3.44.6), y dos pasos: `flutter analyze` y `flutter test` sobre `app_flutter/`.
Nada de compilar artefactos: eso ya lo hacen los scripts de release.

Estado de partida (verificado el 29/8/2026): `flutter analyze` → *No issues found*;
`flutter test` → 21 tests en verde. Se arranca desde limpio.

---

## Acumulado de antes

**Etiquetas de las plantillas nuevas en el editor** (pendiente desde el 7/8/2026)
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
