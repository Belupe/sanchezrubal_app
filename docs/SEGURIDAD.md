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
