# Seguridad de Portal Familia — explicado para todos

Este documento cuenta, **en lenguaje sencillo**, cómo protege la app los datos de
la familia. Se escribió a raíz de una auditoría de seguridad y se va **ampliando
por fases** a medida que se aplican las mejoras. La idea es que cualquier miembro
de la familia (sin ser técnico) pueda entender qué se protege y por qué.

> Para el detalle técnico de cada arreglo, cada apartado cita su identificador
> (p. ej. `[C-01]`) que corresponde al informe de auditoría y a los comentarios
> del código / migraciones (`supabase/migrations/0016+`, Edge Functions y cliente).

Cada cambio se hizo con una regla de oro: **cerrar el agujero sin cambiar lo que
tú ves y haces en la app**. Todo sigue funcionando igual; solo es más seguro por
dentro.

---

## Fase 1 — Lo más crítico

### Nadie puede auto-nombrarse "superadministrador" al registrarse `[C-01]`
Antes, por cómo se creaban las cuentas, alguien de fuera podía pedir el alta
eligiéndose a sí mismo el cargo de **superadministrador** y quedarse con el
control total. Ahora **toda cuenta nueva nace como "miembro"** (el escalón más
bajo), y los cargos altos solo los concede un administrador por el cauce oficial
(la pantalla de gestión de usuarios). Como la app **solo da de alta por
invitación**, esto no cambia nada del uso normal.

### Las actualizaciones se comprueban antes de instalarse `[C-02]`
La app de Windows puede actualizarse sola descargando un instalador. Antes lo
**descargaba y ejecutaba sin comprobar** de dónde venía ni si era el auténtico —
un punto perfecto para colar un programa malicioso. Ahora, antes de instalar
nada, la app: (1) comprueba una **huella digital (SHA-256)** del archivo y lo
rechaza si no coincide, y (2) solo acepta descargas **por HTTPS y de tu propio
dominio**. Si algo no cuadra, no instala nada. Actualizar sigue siendo igual de
fácil para ti.

---

## Fase 2 — Fallos altos

### Candado de rangos: quién puede nombrar a quién `[A-01]`
Hay una escala de responsables, de más a menos mando: **superadministrador →
administrador principal → responsable de familia → segundo responsable →
miembro**. Antes, un administrador principal podía, saltándose la pantalla
normal, **auto-ascenderse a superadministrador** (como si el encargado de una
tienda se diera a sí mismo las llaves del dueño). Ahora hay un candado en la base
de datos con una regla simple: **nadie puede dar un cargo igual o superior al que
tiene**. Solo el superadministrador gestiona superadministradores y principales.
En el uso normal (invitar, cambiar roles por los cauces oficiales) no se nota.

### La app firma las fotos con una llave "de mínimo privilegio" `[A-02]`
Las fotos y vídeos de las inspecciones no se guardan en la nube de la app: viven
en tu servidor de fotos (MinIO). Para dar "pases temporales" de subida/descarga,
un programa en la nube necesitaba una llave del almacén, y estaba usando la
**llave maestra** (la que abre todo). Si esa llave se filtraba, alguien podía
vaciar el almacén entero. Ahora ese programa usa una **llave limitada** que solo
sirve para *guardar* y *ver* fotos del almacén, nada más. Subir y ver fotos
funciona igual. *(Cómo crear esa llave: ver el apéndice al final.)*

### Cola de la lista de espera a prueba de trampas `[A-03]`
Cuando unas fechas están ocupadas, la gente se apunta a una **lista de espera**;
si el que reservó cancela, sube automáticamente el **primero de la cola**, y el
orden se decide por la hora exacta en que cada uno se apuntó. Antes esa hora la
ponía el móvil de cada persona, así que un espabilado podía **mentir para
colarse**. Ahora es **el servidor** quien pone el sello de hora en el momento
justo, y ya no se puede cambiar. La promoción automática sigue igual para quien
se apunta honestamente; solo desaparece la trampa.

### Qué ve cada familia del calendario `[A-04]`
Antes, al abrir el calendario de un domicilio, el móvil descargaba en secreto
**toda** la información de las reservas de las demás familias, incluidos sus
**invitados y comentarios privados** (no se mostraban, pero viajaban hasta el
teléfono). Ahora:
- **El calendario compartido sigue igual**: todas las familias ven qué domicilio
  está ocupado y en qué fechas (a través de una "ventanilla" que enseña solo lo
  imprescindible: domicilio, fechas, grupo y si es mantenimiento).
- **Los invitados y comentarios se quedan en casa**: la información completa de
  una reserva solo la lee quien la creó, su grupo y los administradores. Al abrir
  **tu** reserva, ves y editas tus comentarios como siempre.
- **La lista de espera** se ve igual (quién está y en qué posición), pero las
  notas privadas dejan de compartirse.

*Detalle menor:* el calendario ya no se **auto-refresca al instante** ante
cambios de **otras** familias (sí al reabrir/recargar la pantalla). Es a
propósito y más correcto: no tiene sentido recibir en vivo los cambios privados
de otros.

### Administradores de familia sin grupo asignado `[A-05]`
Antes, si a alguien se le daba el permiso de "responsable de familia" pero
**todavía no tenía familia asignada**, por un descuido técnico el sistema lo
trataba como responsable de todas las reservas que tampoco tuvieran familia. Ya
está corregido: un responsable de familia **solo manda sobre las reservas de SU
familia**; si aún no tiene, no manda sobre ninguna (salvo, como todos, las que
haya creado él mismo). Para los demás no cambia nada.

---

## Fase 3 — Fallos medios (base de datos)

### Imposible reservar dos veces las mismas fechas `[M-03]`
Antes, si dos personas confirmaban una reserva del mismo domicilio para las mismas
fechas **en el mismo instante**, las dos podían colarse y quedaba una **doble
reserva**. Ahora es la propia base de datos la que lo impide de forma **atómica**:
es físicamente imposible que existan dos reservas solapadas del mismo domicilio.
Para ti nada cambia; solo desaparece ese choque en el peor momento.

### Límite de duración de las reservas `[M-04]`
Hay dos valores que el administrador principal ajusta en *Configuración →
General*: **días mínimos** y **días máximos** por reserva (por defecto, 31). El
tope **máximo** se había perdido en una actualización anterior (solo se
comprobaba el mínimo), así que se podían crear reservas de duración ilimitada y
monopolizar una casa. Ya vuelve a existir. Ambos valores viven en la base de
datos (no en la configuración técnica), porque son reglas que el administrador
cambia cuando quiere. El mantenimiento sigue sin límite, y no se puede poner un
máximo menor que el mínimo.

### Cada reserva queda ligada a su familia automáticamente `[M-05]`
Al crear una reserva o apuntarse a la lista de espera, se guarda a qué familia
pertenece. Antes ese dato lo enviaba el dispositivo, así que **se podía manipular
para ponerle el nombre de OTRA familia**. Ahora lo rellena el **servidor** mirando
el perfil de quien la crea, ignorando lo que llegue del móvil. Nadie puede hacer
pasar su reserva por la de otra familia. (Las de mantenimiento no se asignan a
ninguna familia, porque son del edificio.) Se ve todo igual.

### Sorteos justos y a prueba de trampas `[M-06]`
El sorteo de quincenas ahora es **imposible de amañar, incluso por un
administrador principal**. El barajado usa azar de **calidad criptográfica**
(nadie puede adivinar ni forzar el resultado); los resultados quedan **"en
piedra"** (no se pueden editar a mano: la única forma de crearlos es pulsar el
botón de sortear); y **cada sorteo y cada borrado queda registrado** en el
historial (quién, cuándo y qué salió). Para ti funciona igual: se pulsa
"sortear" una vez y todas las familias ven el resultado.

---

## Fase 3 — Fallos medios (correos y fotos)

### Cada foto solo se abre desde su propia reserva `[M-01]`
Al pedir una foto de una inspección, la app manda el "nombre" del archivo. Antes,
con un nombre tramposo (con `../`) se podía pedir la foto de **otra reserva**.
Ahora se comprueba que el nombre corresponda **exactamente** a un archivo de esa
reserva y nada más; cualquier truco se rechaza. Subir y ver tus fotos funciona igual.

### Solo se suben fotos y vídeos, con límite de tamaño `[M-02]`
Antes, el "pase" para subir un archivo no comprobaba **qué** se subía: se podía
colar una página web con código (peligroso) o un archivo enorme. Ahora solo se
aceptan **imágenes y vídeos** (el tipo lo fija el servidor, no el móvil) y con un
**tope de tamaño** configurable. Tus fotos y vídeos normales suben igual.

### La contraseña del correo: cifrada y con conexión segura `[M-07]`
La app envía correos (avisos de reserva, lista de espera). Su **contraseña de
correo** se guardaba en texto plano y hasta se descargaba al panel del
administrador. Ahora vive en una **caja fuerte cifrada** (Vault): nunca se
descarga al dispositivo, y solo el servidor la usa para enviar. Además, la
conexión con el servidor de correo va **siempre cifrada** (si no puede cifrar, no
manda la contraseña). En el panel, el campo de contraseña aparece en blanco:
déjalo así para conservar la actual, o escribe una nueva para cambiarla.

### Los nombres no pueden colar enlaces falsos en los correos `[M-08]`
Los correos se arman metiendo datos como el **nombre** de una persona. Como el
nombre lo elige cada uno, antes se podía poner un nombre con **código o un enlace
de phishing** que llegaba en el correo a otras personas. Ahora esos datos se
"neutralizan" antes de meterlos en el correo, así que un nombre solo se ve como
texto, nunca como un enlace o botón falso.

---

## Fase 3 — Fallos medios (sesión y contraseñas)

### Tu sesión se guarda cifrada en el dispositivo `[M-09]`
Cuando inicias sesión, el móvil guarda un "pase" (token) para no pedirte la
contraseña cada vez. Antes ese pase se guardaba **en claro**; en un móvil
comprometido o con copia de seguridad, alguien podría robarlo. Ahora se guarda en
la **caja fuerte del sistema** (Llavero en iPhone/Mac, almacén cifrado por
hardware en Android). Si por lo que sea no se puede leer, simplemente te pedirá
iniciar sesión otra vez (nunca deja el pase en claro). No notas ningún cambio.

### Cambiar tu contraseña o correo pide confirmar tu contraseña `[M-12]`
Antes, con una sesión abierta (un móvil olvidado, por ejemplo), cualquiera podía
**cambiar tu contraseña o tu correo** y quedarse con la cuenta. Ahora, para
cambiar cualquiera de las dos, la app te pide primero tu **contraseña actual**.
Así, tener el móvil abierto un momento ya no basta para robar la cuenta.

### Contraseñas más fuertes `[M-13]`
El mínimo pasa de 6 a **10 caracteres**, y no se permiten contraseñas de **solo
números**. El servidor es quien manda de verdad (rechaza también contraseñas
filtradas en internet); la app solo avisa antes para ahorrarte el viaje.

> **Verificación en 2 pasos (2FA):** disponible y explicada en su propia sección
> más abajo (`[M-11]`).

---

## Fase 4 — Fallos bajos (últimos retoques)

Son mejoras de "cinturón y tirantes": cosas que ya eran difíciles de aprovechar,
pero que ahora quedan cerradas del todo. **Nada cambia en cómo usas la app.**

### Doble cerrojo en las tablas de datos `[B-01]`
Las reglas que deciden quién ve qué (RLS) ya estaban activas para todos los
usuarios. Ahora, en las tablas donde es seguro hacerlo, también se le aplican al
"dueño técnico" de la base de datos, por si algún día una función interna tuviera
un fallo. Se hizo con cuidado: en las tablas donde ese cerrojo extra rompería el
calendario compartido, los sorteos o la auditoría, se ha dejado a propósito como
estaba (si no, la app dejaría de funcionar).

### Nadie puede "robar" el correo de otra persona `[B-02]`
El correo es lo que identifica a cada uno. Antes, en teoría, alguien podría haber
intentado poner en su ficha el correo de otra persona. Ahora **tu ficha solo
copia tu correo cuando tú lo confirmas de verdad** (pulsando el enlace que te
llega); nadie puede escribir ahí a mano.

### Avisar antes de mover a alguien de grupo `[B-03]`
Al invitar por correo a alguien que **ya existe**, si esa acción fuese a cambiarle
el grupo o el rol, la app ahora **te pregunta primero** ("esta cuenta ya existe,
¿seguro que quieres re-vincularla?") en vez de hacerlo en silencio.

### Los mensajes de error ya no cuentan de más `[B-04]`
Si algo falla en el servidor, la app te muestra un aviso claro y genérico
("no se pudo enviar el correo"), y el detalle técnico queda **solo en el registro
del servidor**, no a la vista de nadie.

### Comprobación de contraseñas "a ciegas" `[B-05]`
Los avisos internos entre partes del sistema comparan su contraseña secreta de una
forma que **no deja medir el tiempo** para adivinarla poco a poco.

### Las notificaciones push tienen su propia llave `[B-06]`
El envío de notificaciones al móvil usa ahora una **llave dedicada, distinta** de
la del resto de avisos internos. Si una se filtrara, no serviría para lo otro.

### Los secretos no se ven al arrancar los scripts `[B-07]`
Al subir las contraseñas del servidor, ahora van por un **fichero temporal
privado** en vez de escribirse "a la vista" en la lista de procesos del ordenador.

### La app de Android solo se firma con la llave buena `[B-09]`
Al preparar la versión final de Android, si falta la llave de firma oficial, el
proceso **se detiene con un aviso** en lugar de firmar con una llave de pruebas
(que sería falsificable).

### El `.env` avisa si dejas contraseñas de ejemplo `[B-10]`
Al arrancar el servidor, una comprobación previa **para el arranque** si alguna
contraseña sigue con su valor de ejemplo, para que nunca se levante "abierto".

### La actualización se descarga en una carpeta impredecible `[B-11]`
El instalador nuevo se guarda en una carpeta con **nombre aleatorio**, así ningún
otro programa puede colar un fichero falso en su lugar. Justo antes de instalar se
vuelve a comprobar su huella (SHA-256), como ya se hacía.

### Los enlaces de la app se validan `[B-12]`
Cuando abres la app desde un enlace de una inspección, ahora se comprueba que el
identificador **tiene el formato correcto** antes de abrir nada.

### Los contenedores del servidor, más "encerrados" `[B-14]`
Los servicios del servidor (fotos y actualizaciones) corren con **menos permisos**,
sin poder escribir donde no deben, con límites de memoria y con las versiones de
sus imágenes fijadas para que sean siempre las mismas.

---

## Fase 5 — Higiene (buenas prácticas)

Últimos detalles de "orden y limpieza". No cambian nada de lo que ves en la app;
dejan el proyecto listo para publicarse con las puertas bien cerradas.

### Las funciones internas solo las usa el sistema `[I-04]`
Las pequeñas funciones internas que deciden "quién es admin" ahora **solo pueden
llamarlas las partes del sistema que las necesitan**, no cualquiera. (Con cuidado
de que las que sí usa el control de permisos sigan estando disponibles para no
romper nada.)

### Se guarda un registro más completo de acciones importantes `[I-05]`
El "libro de registro" (auditoría) ahora anota también los **cambios de rol**, los
**cambios de configuración** y los **movimientos de la lista de espera**, y marca
cuándo una acción la hizo el propio sistema (no una persona). Además, ese registro
**se conserva 12 meses** (antes 2). Es un registro interno, invisible para el uso
normal; solo sirve para poder mirar atrás si hace falta.

### El botón de "probar correo" solo se envía a ti mismo `[I-06]`
Al probar la configuración del correo, la prueba **se envía siempre a tu propio
correo** de administrador. Antes se podía escribir cualquier destino; ahora no, para
que nadie pueda usar ese botón para mandar correos a terceros.

### Las funciones del servidor aceptan solo el origen que tú digas `[I-07]`
Se puede indicar (opcional) **desde qué web** se permite llamar a las funciones del
servidor. Por defecto sigue igual que hoy (la app es una app nativa, no una web, así
que esto no le afecta); es una tuerca extra por si algún día hay una web propia.

### Copias de seguridad y cambio de contraseñas `[I-01]`
Se documenta cómo hacer **copias de seguridad** (de la base de datos y de las fotos)
y cómo **cambiar las contraseñas** del sistema de vez en cuando (ver apéndices).

### La "llave pública" de la app es pública a propósito `[I-03]`
La app lleva dentro una dirección y una "llave pública" (*anon key*) de Supabase.
**Es normal y seguro que sean públicas**: no dan acceso a nada por sí solas; lo que
protege los datos son las reglas de permisos (RLS) del servidor. Ver la nota en
`.env.example`.

### Versiones fijas de las piezas del servidor `[I-09]`
Las funciones del servidor usan **versiones concretas** de sus componentes para que
el resultado sea siempre el mismo (reproducible). El "candado de versiones"
(`deno.lock`) se genera al desplegar (ver apéndice).

---

## Segunda auditoría — repaso independiente

Se encargó una **segunda auditoría desde cero**, buscando fallos en sitios que la
primera no miró. Buena noticia: **no encontró nada grave** (0 críticos, 0 altos), solo
detalles finos de endurecimiento. Esto es lo que se arregló (nada cambia en tu día a día):

### Al recuperar la contraseña, ahora te obliga a crear una nueva `[2M-04]`
Antes, el enlace de "he olvidado mi contraseña" te dejaba entrar directamente. Ahora, al
abrirlo, la app **te obliga a escribir una contraseña nueva** antes de dejarte pasar (como
debe ser). El enlace, además, **abre la app** en vez de una web `[2L-10]`.

### La app se actualiza sola en Windows con una pantalla clara `[pedido]`
En Windows, cuando hay una versión nueva, aparece una **pantalla de actualización** que la
descarga, **comprueba su firma** y la instala sola, y reabre la app. (Android se actualiza
por Google Play e iPhone por el App Store.)

### Los avatares y notas no pueden ser gigantes `[2M-02][2L-09]`
Se pone un **límite de tamaño** a las imágenes de perfil y a los textos, para que nadie
pueda inflar la base de datos con datos enormes. Además, la foto de perfil ya no se
descarga en las listas donde no se muestra (ahorra datos).

### El registro de cambios no guarda datos de más `[2M-03][2L-15]`
El historial de reservas deja de guardar copias de la **lista de invitados y las notas**
(datos personales), y apunta correctamente **quién** hizo cada cambio.

### Aviso "tu estancia se acerca" `[PRE_STAY]`
Se completó el correo de **pre-estancia**: unos días antes de tu reserva recibes un aviso.
Puedes personalizar su texto desde *Configuración → Plantillas* (como los demás correos).

### Los vídeos de inspección se limpian de datos de ubicación `[2L-12]`
Los vídeos pueden llevar escondida la **ubicación GPS** de dónde se grabaron. El servidor
ahora se los quita automáticamente al subirlos. (Las fotos ya lo hacían.)

### Más retoques `[2L-05..2L-17, 2I-02..2I-11]`
Mensajes de error que no revelan detalles internos; el correo de prueba solo se envía a ti;
tope de dispositivos y de solicitudes por persona; las inspecciones quedan atadas a su
domicilio correcto; y varias piezas del servidor un poco más cerradas.

> **Se dejan para más adelante (a propósito):** firmar el instalador de Windows con un
> certificado de pago (Authenticode) `[2M-01]` y la ofuscación del código Android `[2L-03]`.
> Ninguno es un agujero: son mejoras que requieren coste o pruebas extra. La app de Windows ya
> comprueba su firma por huella (SHA-256).

---

## Verificación en dos pasos (2FA) `[M-11]`

Es una protección **opcional**: cada persona decide si la activa. Si no la activas,
entras como siempre (solo con tu contraseña) y **no cambia nada**.

**Para activarla:** entra en *Perfil → Verificación en dos pasos (2FA) → Activar*.
La app te muestra una **clave**; ábrela en una app de autenticación gratuita
(Google Authenticator, Authy, Microsoft Authenticator…), añade la cuenta con esa
clave y escribe el código de 6 dígitos que te aparece para confirmar.

**A partir de entonces:** cuando inicies sesión, después de la contraseña la app te
pedirá el **código de 6 dígitos** de tu app de autenticación. Así, aunque alguien
supiera tu contraseña, no podría entrar sin tu teléfono.

**Para quitarla:** en la misma pantalla, *Desactivar*. Volverás a entrar solo con la
contraseña.

> Nota técnica: usa el estándar **TOTP** (el mismo de la mayoría de bancos y webs).
> El servidor ya tenía habilitada esta opción (Fase 0); esto añade la pantalla para
> usarla dentro de la app.

---

## Apéndice operativo — copias de seguridad y rotación de secretos `[I-01]`

**Copias de seguridad (haz ambas con regularidad, p. ej. semanal):**
1. **Base de datos (Supabase):** el plan de Supabase incluye backups automáticos
   diarios (Dashboard → *Database → Backups*). Para una copia manual puntual:
   `supabase db dump -f backup.sql` (o *Backups → Download*). Guárdala fuera del
   servidor.
2. **Fotos y vídeos (MinIO):** es una carpeta del disco (`MEDIA_DATA_DIR` del
   `.env`). Cópiala con tu herramienta habitual, p. ej.
   `rsync -a "$MEDIA_DATA_DIR"/ /ruta/backup/media/` (o `mc mirror`). Incluye
   también `UPDATES_DATA_DIR` si quieres conservar los instaladores publicados.

**Rotación de secretos (cada cierto tiempo o si sospechas una fuga):**
- Genera nuevos valores (`openssl rand -base64 24`) para `MINIO_ROOT_PASSWORD`,
  `MEDIA_SIGN_SECRET_KEY`, `CRON_SECRET`, `PUSH_SECRET` en el `.env`.
- Re-súbelos: `./scripts/push-supabase-secrets.sh` (o `.ps1`) y reinicia el stack
  (`docker compose up -d`). El `cron_secret` del Vault debe seguir coincidiendo con
  `CRON_SECRET` (ver `.env.example`, sección 5).
- El *token* de la CLI de Supabase y la *service role key* se rotan desde el
  Dashboard de Supabase.

## Apéndice operativo — congelar versiones de las funciones `[I-09]`

En la máquina que despliega (donde está el CLI de `supabase`/`deno`), genera el
"candado de versiones" para que cada despliegue use exactamente las mismas piezas:

```bash
cd supabase/functions
deno cache --lock=deno.lock --lock-write */index.ts
```

Súbelo al repo (`git add supabase/functions/deno.lock`). A partir de ahí, los
despliegues (`supabase functions deploy`) reproducen las mismas versiones. Las
dependencias que ya van fijas: `denomailer@1.6.0` y `aws4fetch@1.0.20`;
`@supabase/supabase-js@2` sigue la recomendación oficial de Supabase (estable por
versionado semántico) y queda "congelada" por el `deno.lock`.

---

## Apéndice operativo — crear la llave limitada de MinIO `[A-02]`

Solo hace falta hacerlo **una vez**, en el servidor donde corre MinIO, con la
herramienta `mc` (cliente de MinIO):

1. Conecta `mc` con la llave maestra (solo para este alta):
   ```sh
   mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
   ```
2. Crea `media-sign-policy.json` con el permiso mínimo (leer/escribir objetos del
   bucket `inspections`, nada más):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       { "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject"],
         "Resource": ["arn:aws:s3:::inspections/*"] }
     ]
   }
   ```
   (Si cambiaste `MEDIA_BUCKET`, usa ese nombre en el `Resource`.)
3. Registra la política y crea la llave dedicada (elige tú los valores; el secret
   con `openssl rand -base64 24`):
   ```sh
   mc admin policy create local media-sign-rw media-sign-policy.json
   mc admin user add local "TU_MEDIA_SIGN_ACCESS_KEY" "TU_MEDIA_SIGN_SECRET_KEY"
   mc admin policy attach local media-sign-rw --user "TU_MEDIA_SIGN_ACCESS_KEY"
   ```
4. Pon esos dos valores en el `.env` como `MEDIA_SIGN_ACCESS_KEY` /
   `MEDIA_SIGN_SECRET_KEY`, ejecuta `./scripts/push-supabase-secrets.sh` (o `.ps1`)
   y redeploya: `supabase functions deploy media-sign`.
5. (Tras desplegar) borra los secrets viejos para que la root deje de estar cargada:
   ```sh
   supabase secrets unset MINIO_ACCESS_KEY MINIO_SECRET_KEY --project-ref pjceyplciujtrnxptwbx
   ```

> La consola de MinIO se protege **aparte** con Cloudflare Access (Google)
> delante. Esto es lo complementario: aunque nadie llegue a la consola, la llave
> que usa la nube ya no es la maestra.

---

## Ajustes que se aplican en el panel de Supabase (Fase 0)

Algunas protecciones son configuración del panel de Supabase (Authentication).
Están documentadas y versionadas en [`supabase/config.toml`](../supabase/config.toml),
con su checklist:
- Registro **solo por invitación** (`[C-01]`).
- **Verificación en 2 pasos (MFA/TOTP)** disponible de forma opcional (`[M-11]`).
- **Contraseñas más fuertes** y bloqueo de contraseñas filtradas (`[M-13]`).
- **Reautenticación** al cambiar contraseña/correo (`[M-12]`).
