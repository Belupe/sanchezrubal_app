# Especificación Funcional Exhaustiva — Backend Legacy Next.js "Portal Familia"

> Documentación de captura total previa al borrado. Cubre: 10 archivos de Server Actions, librerías de soporte (`session`, `rate-limit`, `prisma`, `logger`, `cron`), `middleware`, `instrumentation` (arranque) y el esquema completo de Prisma. Todos los valores, nombres de campo, condiciones, plantillas de correo y reglas se transcriben literalmente del código fuente.

## Índice
1. Conceptos transversales (roles, sesión, autorización)
2. Server Actions por archivo
3. Modelo de datos (Prisma)
4. Sesión / JWT
5. Rate limiting
6. Middleware
7. Arranque (instrumentation: logger + cron)
8. Cron (jobs, horarios, correos, Excel)
9. Inventario de correos
10. Variables de entorno

---

## 1. Conceptos transversales

### Roles del sistema
Definidos como `String` (no enum) en `User.role`. Valores conocidos: `MEGA_ADMIN`, `SUPER_ADMIN`, `FAMILY_ADMIN`, `MEMBER`. Default en BD: `"MEMBER"`.

Jerarquía efectiva (de mayor a menor privilegio): **MEGA_ADMIN > SUPER_ADMIN > FAMILY_ADMIN > MEMBER**.

### Patrón de autenticación en cada action
Casi todas las server actions empiezan con:
```ts
const cookieStore = await cookies()
const session = await decrypt(cookieStore.get('session')?.value)
```
`session` es `{ userId, role, expiresAt }` o `null`. Las comprobaciones de rol se hacen comparando `session.role` con literales de string.

### Comportamiento ante fallo de autorización (IMPORTANTE — varía por función)
- Algunas actions hacen `return` (vacío → `undefined`) silencioso (p.ej. `createAnnouncement`, `deleteAnnouncement`, `deleteSorteo`, `deleteUser`, `deleteFamilyGroup`).
- Otras devuelven `{ error: '...' }`.
- Esto se especifica función por función.

### `BCRYPT_ROUNDS`
Constante `= 12` replicada literalmente en `auth.ts`, `family.ts` y `user.ts`. Comentario: "12 ≈ 250 ms/hash en CPU moderna … hace el brute-force offline ~4× más difícil que 10".

---

## 2. Server Actions

### 2.1 `actions/announcement.ts`

#### `createAnnouncement(formData: FormData)`
- **Propósito:** crear un anuncio (general o asociado a propiedades) y notificar por email a todos los usuarios excepto el autor.
- **Inputs (FormData):**
  - `title` (string)
  - `content` (string)
  - `propertyIds` (multivaluado, `formData.getAll('propertyIds')` → `string[]`)
- **Autorización:** requiere `session.userId` y `role ∈ {SUPER_ADMIN, MEGA_ADMIN}`. Si no, `return` silencioso (sin valor).
- **Validación:** solo procede si `title && content` son truthy. **No usa zod ni límites de longitud.**
- **Efectos en BD:**
  - `prisma.announcement.create` con `{ title, content, authorId: session.userId, properties: connect[...] }`. Si `propertyIds.length > 0`, conecta esas propiedades por `id`; si no, `properties: undefined`.
  - `include: { properties: { select: { name: true } } }`.
- **Correo:**
  - Lee `systemConfig` (`id: 'global'`). Solo envía si `config.smtpHost && config.smtpUser`.
  - Destinatarios: todos los `User` con `id != session.userId` y `email != null` (campo `email`), enviados como **BCC**.
  - Transport nodemailer: `host`, `port = smtpPort || 587`, `secure = smtpSecure`, auth `{ user: smtpUser, pass: smtpPass }`, `connectionTimeout: 5000`.
  - `from`: `"Portal Familia" <smtpUser>`.
  - `appName = "Portal Familia"`, `baseUrl = config.baseUrl || "http://localhost:3000"`.
  - **Asunto:** si no hay propiedades → `Nuevo Anuncio General: {title}`. Si hay propiedades → `Anuncio para {propertyNames}: {title}` (nombres unidos por `, `).
  - **Cuerpo HTML:** fondo `#f9fafb`; muestra cabecera con emoji 🏠 (`Comunicado importante referente a: {propertyNames}`) o 📢 (`Anuncio General`); título, contenido (`white-space: pre-wrap`) y enlace al `baseUrl` ("Portal Familia"). Color de acento `#4D8AF0`.
  - Errores de envío se capturan (`try/catch`) y se loguean con `console.error("Error al enviar correos de anuncio:", err)` — no rompen la creación.
- **Otros efectos:** `revalidatePath('/')` (solo dentro del bloque `if (title && content)`).
- **Casos límite:** sin `title`/`content` no hace nada. Sin SMTP configurado, crea el anuncio pero no envía correos.

#### `deleteAnnouncement(formData: FormData)`
- **Propósito:** borrar un anuncio.
- **Input:** `id` (string).
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}`; si no, `return` silencioso.
- **Efecto:** si `id`, `prisma.announcement.delete({ where: { id } })` + `revalidatePath('/')`.

---

### 2.2 `actions/auth.ts`

**Constantes / helpers globales del archivo:**
- `BCRYPT_ROUNDS = 12`.
- `turnstileEnforced = process.env.NODE_ENV === 'production' || !!process.env.TURNSTILE_SECRET_KEY` — en producción el captcha NUNCA puede quedar desactivado por falta de secret.
- `verifyTurnstile(formData)`:
  - Si `!turnstileEnforced` → `null` (sin captcha, modo dev/test).
  - Si `turnstileEnforced` pero falta `TURNSTILE_SECRET_KEY` → `'La verificación anti-bots no está configurada en el servidor.'`
  - Si falta `cf-turnstile-response` en el FormData → `'Por favor, completa la verificación anti-bots.'`
  - Hace POST a `https://challenges.cloudflare.com/turnstile/v0/siteverify` con body `secret=...&response=...`. Si `!data.success` → `'Prueba anti-bots fallida. Intenta nuevamente.'`. Si éxito → `null`.
- `tokensMatch(a, b)`: comparación en tiempo constante con `crypto.timingSafeEqual`; si longitudes distintas → `false` (sin fuga de longitud).

#### `checkMegaAdminExists()`
- **Propósito:** indicar si ya existe un `MEGA_ADMIN`.
- **Sin autenticación.**
- **Retorno:** `boolean` (`!!megaAdmin`), buscando `prisma.user.findFirst({ where: { role: 'MEGA_ADMIN' } })`.

#### `createMegaAdmin(prevState, formData)`
- **Propósito:** bootstrap inicial: crear el primer y único `MEGA_ADMIN`.
- **Inputs:** `name`, `password` + `cf-turnstile-response`.
- **Captcha:** `verifyTurnstile`; si error → `{ error }`.
- **Validación (zod):**
  - `name`: `string().min(1, 'Requerido').max(150, 'Máximo 150 caracteres')`.
  - `password`: `string().min(1, 'Requerida').max(500, 'Máximo 500 caracteres')`.
  - Fallo de parseo → `{ error: 'Nombre o contraseña requeridos y en formato válido' }`.
- **Regla de negocio:** si ya existe MegaAdmin → `{ error: 'El Mega Administrador ya ha sido inicializado.' }`.
- **Efectos BD:** hash bcrypt(12) de password; `prisma.user.create` con `{ name, passwordHash, role: 'MEGA_ADMIN' }` (sin email).
- **Sesión:** `createSession(megaAdmin.id, 'MEGA_ADMIN')`.
- **Redirect:** `redirect('/')`.

#### `login(prevState, formData)`
- **Propósito:** autenticar y crear sesión.
- **Inputs:** `emailOrName`, `password` + `cf-turnstile-response`.
- **Captcha:** `verifyTurnstile`.
- **Rate limit:** IP de `x-forwarded-for` → `x-real-ip` → `'unknown'`; `checkRateLimit(ip, 15, 60000)` (15 intentos / 60 s). Si bloqueado → `{ error: 'Demasiados intentos. Has sido bloqueado por 1 minuto por seguridad.' }`.
- **Validación (zod):** `emailOrName: string().min(1).max(250)`, `password: string().min(1).max(500)`. Fallo → `{ error: 'Credenciales inválidas o formato excesivo' }`.
- **Lógica:** `prisma.user.findFirst` con `OR: [{ email: emailOrName }, { name: emailOrName, role: 'MEGA_ADMIN' }]`. Es decir: se puede entrar por email (cualquier rol) o **por nombre solo si es MEGA_ADMIN**.
- **Comprobaciones:** si `!user || !user.passwordHash` → `{ error: 'Credenciales inválidas' }`. `bcrypt.compare`; si falla → mismo error genérico.
- **Sesión:** `createSession(user.id, user.role)` + `redirect('/')`.

#### `logout()`
- **Efecto:** `deleteSession()` + `redirect('/login')`.

#### `sendPasswordReset(prevState, formData)`
- **Propósito:** enviar email de restablecimiento de contraseña.
- **Input:** `email`.
- **Rate limit:** `checkRateLimit(ip, 15, 60000)`. Bloqueo → `{ error: 'Demasiados intentos. Espera 1 minuto.' }`.
- **Validación (zod):** `email: string().email().max(250)`. Fallo → `{ error: 'Aporta un correo electrónico válido' }`.
- **Anti-enumeración:** si el email NO existe → devuelve `{ success: true }` (no revela existencia).
- **Token:** `crypto.randomBytes(32).toString('hex')` (64 hex, ~256 bits). Expiración `Date.now() + 15*60*1000` (**15 min**). Guarda `resetToken` y `resetTokenExpiry` en el usuario.
- **SMTP:** lee `systemConfig`. Si falta `smtpHost || smtpUser || baseUrl` → `{ error: 'El sistema SMTP no está configurado.' }`.
- **Correo:** transport (`port = smtpPort || 587`, `connectionTimeout: 5000`). `from`: `"Portal Familia" <smtpUser>`. `to`: email. Asunto `Restablecimiento de Contraseña`. Enlace: `{baseUrl}/reset-password?token={token}&email={encodeURIComponent(email)}`. HTML fondo negro `#000`, "válido por 15 min", color `#4D8AF0`.
- **Retorno:** `{ success: true }` tras enviar. En error SMTP: log `console.error('sendPasswordReset SMTP failure:', err?.message)` (sin volcar el error completo) → `{ error: 'No se pudo enviar el correo de recuperación.' }`.

#### `resetPassword(prevState, formData)`
- **Propósito:** cambiar la contraseña usando el token.
- **Inputs:** `email`, `token`, `password`.
- **Validación (zod):** `email: string().max(250)`, `token: string().max(300)`, `password: string().min(8, 'Mínimo 8 caracteres').max(500)`. Fallo → `{ error: 'Datos incompletos o corruptos' }`.
- **Comprobaciones:**
  - Usuario por email; si `!u || !u.resetToken || !u.resetTokenExpiry` → `{ error: 'Token inválido' }`.
  - Si `resetTokenExpiry < now` → `{ error: 'El enlace ha caducado. Solicita uno nuevo.' }`.
  - Si `tokensMatch` falla (comparación tiempo constante) → `{ error: 'Token inválido' }`.
- **Efecto atómico (single-use):** `bcrypt.hash(password, 12)`, luego `prisma.user.updateMany` con `where: { id, resetToken, resetTokenExpiry }` (los valores ya verificados) y `data: { passwordHash, resetToken: null, resetTokenExpiry: null }`. Si `result.count === 0` (token ya consumido en concurrencia) → `{ error: 'El enlace ya ha sido utilizado.' }`.
- **Retorno éxito:** `{ success: true }`.

---

### 2.3 `actions/config.ts`

#### `getSystemConfig()`
- **Autorización:** `role ∈ {MEGA_ADMIN, SUPER_ADMIN}`; si no → `null`.
- **Lógica:** lee `systemConfig` (`id: 'global'`); si no existe, lo **crea** con `{ id: 'global' }` (defaults del modelo). Retorna el config completo (incluye `smtpPass` en claro).

#### `updateSystemConfig(prevState, formData)`
- **Autorización:** **solo `MEGA_ADMIN`** (estrictamente; SUPER_ADMIN NO). Si no → `{ error: 'Requerido nivel Mega Admin' }`.
- **Inputs (FormData):** `baseUrl`, `smtpHost`, `smtpPort` (`parseInt(...) || null`), `smtpUser`, `smtpPass`, `smtpSecure` (`=== 'on'`), `maxReservationDays` (`parseInt`).
- **Efecto:** `prisma.systemConfig.upsert` (`id: 'global'`). `maxReservationDays` solo se escribe si es truthy (`...(maxReservationDays ? { maxReservationDays } : {})`) — un `0`/NaN no actualiza ese campo.
- **Retorno:** `{ success: true }`. Sin validación de longitud/formato.

#### `updateTemplate(formData)`
- **Autorización:** `session?.role !== 'MEGA_ADMIN'` → `{ error: 'No autorizado' }` (solo MEGA_ADMIN).
- **Inputs:** para cada `type ∈ ['POST_STAY', 'MONTHLY_REMINDER']`: `{type}_subject` y `{type}_body`.
- **Efecto:** por cada tipo, si `subject && body`, `prisma.notificationTemplate.upsert({ where: { type }, update/create: { type, subject, body } })`.
- **Otros:** `revalidatePath('/configuracion')` → `{ success: true }`.

#### `testSmtpConnection(targetEmail = 'contacto@belucm.me')`
- **Autorización:** solo `MEGA_ADMIN` → si no `{ error: 'Requerido nivel Mega Admin' }`.
- **Lógica:** lee config; si `!config.smtpHost` → `{ error: 'No hay configuración SMTP guardada' }`. Crea transport con timeouts `connectionTimeout/greetingTimeout/socketTimeout = 5000`. Ejecuta `transporter.verify()` y envía correo de prueba a `targetEmail`.
- **Correo:** `from`: `Portal Familia <smtpUser>`. Asunto `Portal Familia - Prueba de Conexión SMTP`. HTML con "¡Protocolo de Red Abierto!" y timestamp `new Date().toLocaleString()`.
- **Retorno:** éxito `{ success: true, message: 'Conectado y correo enviado a: {targetEmail}' }`; error `{ error: 'Fallo al conectar: ' + error.message }`.

#### `wipeStorage()`
- **Propósito:** purga destructiva de reportes e imágenes.
- **Autorización:** solo `MEGA_ADMIN` → si no `{ error: 'No autorizado' }`.
- **Efectos:**
  - `prisma.outReport.deleteMany({})` — **borra TODOS los OutReport**.
  - Directorio: `process.env.UPLOAD_DIR || path.join(process.cwd(), 'uploads')`. Si existe → `fs.rmSync(..., { recursive: true, force: true })` y luego `fs.mkdirSync(..., { recursive: true })` (lo recrea vacío).
  - `revalidatePath('/reportes')`.
- **Retorno:** `{ success: true, message: 'Todos los recursos y reportes han sido destruidos irrevocablemente.' }`; error `{ error: 'Fallo catastrófico al purgar: ' + error.message }`.

---

### 2.4 `actions/family.ts`

**Helpers del archivo:**
- `generateRandomColor()`: `hsl(h, s%, l%)` con `h ∈ [0,359]`, `s ∈ [60,79]`, `l ∈ [40,59]`.
- `sendWelcomeEmail(email, name)`: lee config; si falta `smtpHost || smtpUser || baseUrl` → return. Busca el usuario por email; genera `resetToken = randomBytes(32).hex` con expiración **7 días** (`7*24*60*60*1000`), lo guarda. Envía correo "Bienvenido a Portal Familia" (`from: "Portal Familia" <smtpUser>`), con botón "Configurar Mi Contraseña" → enlace `{baseUrl}/reset-password?token=...&email=...`. HTML tema oscuro `#18181b`. Errores → `console.error("Error sending welcome email:", error)`. **Nota:** el token de bienvenida usa el mismo mecanismo `resetToken`/`resetTokenExpiry` que el reset normal, pero con ventana de 7 días.

#### `createFamilyGroup(prevState, formData)`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'No autorizado' }`.
- **Inputs:** `groupName`, `adminName`, `adminEmail`. Si falta alguno → `{ error: 'Datos incompletos' }`.
- **Efectos BD:**
  - Crea `FamilyGroup { name: groupName, color: generateRandomColor() }`.
  - Si el email ya existe → actualiza ese usuario poniendo `familyGroupId = group.id` (lo mueve al nuevo grupo, **sin** cambiarle el rol ni reenviar correo).
  - Si no existe → crea `User { name, email, role: 'FAMILY_ADMIN', passwordHash: bcrypt(randomBytes(16).base64url, 12), familyGroupId }` y dispara `sendWelcomeEmail(adminEmail, adminName)` en segundo plano (`.catch(console.error)`).
- **Otros:** `revalidatePath('/usuarios', 'page')` → `{ success: true }`.

#### `addFamilyMember(prevState, formData)`
- **Autorización:** requiere sesión. Reglas:
  - Si `FAMILY_ADMIN`: se ignora el `familyGroupId` enviado y se fuerza al `familyGroupId` del propio admin (`me.familyGroupId`).
  - Si NO es `FAMILY_ADMIN` ni `SUPER_ADMIN`/`MEGA_ADMIN` → `{ error: 'No autorizado para añadir miembros' }`.
  - Si `selectedRole === 'SUPER_ADMIN'` y el actor no es `SUPER_ADMIN`/`MEGA_ADMIN` → `{ error: 'No autorizado para otorgar rol Super Administrador' }`.
- **Inputs:** `name`, `email`, `familyGroupId`, `role` (default `'MEMBER'`). Si falta `name || email || familyGroupId` → `{ error: 'Datos incompletos' }`.
- **Unicidad:** si el email ya existe → `{ error: 'El correo electrónico ya se encuentra ocupado' }`.
- **Efecto:** crea `User { name, email, role: selectedRole, familyGroupId, passwordHash: bcrypt(randomBytes(16).base64url,12) }`; `sendWelcomeEmail(email, name)` en segundo plano.
- **Otros:** `revalidatePath('/usuarios', 'page')` → `{ success: true }`.

#### `registerIndividualUser(prevState, formData)`
- **Propósito:** crear usuario "suelto" (sin grupo familiar).
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'Solo los administradores globales pueden crear usuarios sueltos' }`.
- **Inputs:** `name`, `email`, `role` (default `'MEMBER'`).
- **Regla:** si `selectedRole === 'SUPER_ADMIN'` y actor NO es `MEGA_ADMIN` → `{ error: 'No autorizado para otorgar rol Super Administrador' }` (aquí solo MEGA_ADMIN puede otorgar SUPER_ADMIN, a diferencia de `addFamilyMember`).
- **Validación:** falta `name || email` → `{ error: 'Datos incompletos' }`. Email duplicado → `{ error: 'El correo electrónico ya se encuentra ocupado' }`.
- **Efecto:** `User { name, email, role: selectedRole, passwordHash }` **sin** `familyGroupId`. `sendWelcomeEmail`. `revalidatePath('/usuarios', 'page')` → `{ success: true }`.

#### `promoteUserToRole(formData)`
- **Inputs:** `userId`, `newRole`. Falta alguno → `{ error: 'Faltan parámetros' }`.
- **Autorización:** **No comprueba sesión válida al inicio** (lee `session` pero no exige que exista). Solo si `newRole === 'SUPER_ADMIN'` y `session?.role ∉ {MEGA_ADMIN, SUPER_ADMIN}` → `{ error: 'Solo Mega_Admin o Súper Admin pueden promover a Súper Administrador' }`. Para cualquier otro `newRole` no hay control de rol explícito (caso límite/posible debilidad).
- **Efecto:** `prisma.user.update({ where: { id: userId }, data: { role: newRole } })`. `revalidatePath('/usuarios', 'page')` → `{ success: true }`.

#### `updateFamilyGroupName(prevState, formData)`
- **Autorización:** requiere sesión (cualquier rol autenticado) → si no `{ error: 'No autorizado' }`.
- **Inputs:** `groupId`, `newName`. Falta alguno → `{ error: 'Faltan datos' }`.
- **Efecto:** `prisma.familyGroup.update({ where: { id: groupId }, data: { name: newName } })`. `revalidatePath('/usuarios', 'page')` → `{ success: true }`.

#### `deleteUser(formData): Promise<void>`
- **Autorización:** requiere sesión (si no, `return` silencioso).
- **Input:** `userId`.
- **Reglas:**
  - Busca usuario; si `!u || u.role === 'MEGA_ADMIN'` → `return` (no se puede borrar al MegaAdmin).
  - Si el actor NO es `SUPER_ADMIN`/`MEGA_ADMIN`: debe ser `FAMILY_ADMIN` (si no, `return`), y solo puede borrar usuarios de **su mismo grupo** (`u.familyGroupId === me.familyGroupId`; si no, `return`).
- **Preservación de historial:** busca el `MEGA_ADMIN`; reasigna todas las `Reservation` con `createdById = userId` a `createdById = megaAdmin.id` y `familyGroupId = null` (`updateMany`). Luego `prisma.user.delete({ where: { id: userId } })`.
- **Otros:** `revalidatePath('/usuarios', 'page')`.

#### `deleteFamilyGroup(formData): Promise<void>`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `return` silencioso.
- **Input:** `groupId`.
- **Secuencia (5 pasos, transcrita):**
  1. Desconecta el grupo de reservas: `reservation.updateMany({ where: { familyGroupId: groupId }, data: { familyGroupId: null } })`.
  2. Protege a Super/Mega admins del grupo: `user.updateMany({ where: { familyGroupId: groupId, role: { in: ['MEGA_ADMIN','SUPER_ADMIN'] } }, data: { familyGroupId: null } })` (los saca, no los borra).
  3. Reasigna reservas creadas por el resto de miembros del grupo al MegaAdmin: busca `usersToDelete` (todos los que aún tengan `familyGroupId = groupId`), y si hay y existe megaAdmin → `reservation.updateMany({ where: { createdById: { in: userIds } }, data: { createdById: megaAdmin.id } })`.
  4. `prisma.user.deleteMany({ where: { familyGroupId: groupId } })` (borra los miembros estándar restantes).
  5. `prisma.familyGroup.delete({ where: { id: groupId } })`.
- **Otros:** `revalidatePath('/usuarios', 'page')`.

---

### 2.5 `actions/notifications.ts`

#### `getMyNotificationSettings()`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `[]`.
- **Retorno:** `prisma.notificationSetting.findMany({ where: { userId: session.userId } })`.

#### `saveNotificationSetting(prevState, formData)`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'Requeridos privilegios de Super Administrador' }`.
- **Inputs:** `type` (string), `customText` (string), `isActive` (`=== 'on'`).
- **Efecto:** `prisma.notificationSetting.upsert` con clave compuesta `userId_type` (`{ userId: session.userId, type }`); update/create `{ customText, isActive }` (create incluye `userId`, `type`).
- **Retorno:** `{ success: true }`.
- **Nota de negocio:** estas `NotificationSetting` con `type: 'PRE_STAY'` e `isActive: true` son las que el cron lee para inyectar "Mensaje de Administración" en los correos pre-estancia (ver §8).

---

### 2.6 `actions/property.ts`

#### `createProperty(prevState, formData)`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'No autorizado' }`.
- **Inputs:** `name`, `description`. Falta `name` → `{ error: 'Nombre requerido' }`.
- **Efecto:** `prisma.property.create({ data: { name, description } })`. `revalidatePath('/casas')` → `{ success: true }`. Sin validación de longitud.

#### `deleteProperty(formData)`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'No autorizado' }`.
- **Input:** `id`. Falta → `{ error: 'ID requerido' }`.
- **Efecto:** `prisma.property.delete({ where: { id } })`. Por cascada del esquema, borra también `Reservation`, `OutReport`, `AuditLog` asociados (ver onDelete en §3). `revalidatePath('/casas')` → `{ success: true }`.

---

### 2.7 `actions/report.ts`

#### `submitReport(formData)`
- **Propósito:** recibir el "formulario de salida" (inventario fotográfico) de una reserva, guardar imágenes y notificar a administradores.
- **AUTORIZACIÓN:** **NINGUNA.** No lee sesión ni rol. Es público (coherente con la ruta pública `/reporte` del middleware). Caso límite de seguridad relevante.
- **Inputs (FormData):**
  - `reservationId` (string)
  - `propertyId` (string)
  - `notes` (string)
  - `images` (multivaluado `getAll('images')` → `File[]`)
  - **Nota:** `checkIn` y `checkOut` se establecen ambos a `new Date()` (momento del envío) — NO provienen del formulario.
- **Validación de ficheros (3 capas):**
  - Directorio destino: `process.env.UPLOAD_DIR || path.join(process.cwd(), 'uploads')` (se crea con `mkdir recursive` si no existe).
  - Procesa **como máximo 5** ficheros (`Math.min(files.length, 5)`).
  - Por fichero: descarta si `file.size <= 0` o `> 30 MB` (`30 * 1024 * 1024`).
  - **Allowlist MIME + magic bytes:**
    - `image/jpeg` → ext `jpg`, sniff `FF D8 FF`.
    - `image/png` → ext `png`, sniff `89 50 4E 47`.
    - `image/webp` → ext `webp`, sniff bytes 0–4 == `RIFF` y bytes 8–12 == `WEBP`.
    - `application/pdf` → ext `pdf`, sniff bytes 0–4 == `%PDF`.
    - Si el MIME no está en la allowlist → se salta.
    - Si `buffer.length < 12` o la firma no coincide → se salta.
  - **Nombre seguro en disco:** `{reservationId}_{randomBytes(4).hex}.{ext}` (la extensión se deriva del MIME verificado, **nunca** del nombre original — evita `evil.php.jpg`).
- **Efecto BD:** `prisma.outReport.create` con:
  - `reservationId`, `propertyId`, `checkIn` (=now), `checkOut` (=now), `generalStatus: 'COMPLETADO'`, `rating: 5`, `damages: ''`, `missingItems: ''`, `notes: notes || ''`, `imageUrls: JSON.stringify(savedImages)` (array de nombres de fichero).
- **Correo a administradores:**
  - Carga la reserva (`include: createdBy, familyGroup, property`). Solo si existe y `config.smtpHost && config.smtpUser`.
  - Transport nodemailer (sin timeouts explícitos aquí).
  - Destinatarios: todos los `User` con `role ∈ {MEGA_ADMIN, SUPER_ADMIN}` que tengan email; un correo por admin (`Promise.allSettled`).
  - `from`: `"Portal Familia Automático" <smtpUser>`. Asunto `✅ Nuevo Reporte de Salida: {property.name}`. Cuerpo: "Formulario de Salida Recibido", menciona `createdBy.name`, grupo (`familyGroup?.name || 'Ninguno / Independiente'`), rango `startDate.toLocaleDateString()` – `endDate.toLocaleDateString()`, `property.name`, botón "Ver en Inspecciones" → `{baseUrl||'http://localhost:3000'}/reportes`.
- **Redirect final:** `redirect('/')` (siempre, haya o no correo).

---

### 2.8 `actions/reservation.ts`

#### `createReservation(formData)`
- **Autorización:** requiere sesión (cualquier rol) → si no `{ error: 'No autorizado' }`.
- **Validación (zod):**
  - `propertyId: string().max(200)`
  - `startDate: string().pipe(z.coerce.date())`
  - `endDate: string().pipe(z.coerce.date())`
  - `guestCount: coerce.number().min(1).max(50)`
  - `guestsList: string().max(10000)` (límite 10k, anti-DoS)
  - `isMaintenance: string().nullable().optional()`
  - Fallo → `{ error: 'Los datos de la reserva tienen un formato inválido: {detalle por campo}' }`.
- **Reglas de negocio:**
  - `isMaintenance` solo se respeta (`=== 'true'`) si el actor es `SUPER_ADMIN`/`MEGA_ADMIN`; en otros roles queda `false`.
  - Usuario debe existir (`{ error: 'Usuario inválido' }`).
  - `startDate >= endDate` → `{ error: 'La fecha de fin debe ser posterior a la de inicio' }`.
  - Límite de días: `maxDays = sysConfig.maxReservationDays || 15` (ojo: el default del modelo es `30`, pero aquí el fallback en código es `15`). `diffDays = ceil(|end-start| / 86400000)`. Si `diffDays > maxDays` **y** rol ∉ {MEGA_ADMIN, SUPER_ADMIN} → `{ error: 'La reserva excede el límite máximo permitido de {maxDays} días' }` (los admins están exentos del límite).
  - **Solapamiento:** `findFirst` con `propertyId` y `startDate < endDate (nuevo) && endDate > startDate (nuevo)`. Si hay overlap → `{ error: 'Ya existe una reserva ocupando estas fechas exactas' }`.
- **Efecto BD (creación):** `reservation.create` con `{ propertyId, createdById: user.id, familyGroupId: user.familyGroupId || null, startDate, endDate, guestCount, guestsList, isMaintenance }`.
- **Audit log:** `auditLog.create` `{ action: 'CREAR_RESERVA', details: 'Reserva programada del {start es-ES} al {end es-ES}.', userId: (role===MEGA_ADMIN ? null : user.id), propertyId }`. (Las acciones del MegaAdmin se registran con `userId: null`.)
- **Correo a SUPER_ADMIN:**
  - Solo si `smtpHost && smtpUser`. Destinatarios: usuarios con `role: 'SUPER_ADMIN'` con email (NO incluye MEGA_ADMIN aquí).
  - `from`: `"Portal Familia Automático" <smtpUser>`. `to`: lista unida por `, `.
  - Asunto `🏨 Nueva reserva creada en {propertyName}`. Cuerpo lista: Propiedad, Grupo Familiar (`familyGroup?.name || "Sin grupo familiar"`), Miembro que reservó (`user.name`), Rango `DD/MM` – `DD/MM` (formato manual con `padStart`).
  - Errores capturados con `console.error("Error enviando notificación de reserva a administradores:", error)`.
- **Otros:** `revalidatePath('/casas/${propertyId}')` → `{ success: true }`.

#### `deleteReservation(reservationId: string)`
- **Firma:** recibe `reservationId` directo (no FormData).
- **Autorización:** requiere sesión → si no `{ error: 'No autorizado' }`. Busca reserva; si no existe → `{ error: 'Reserva no encontrada' }`.
- **Regla de permiso:** si `role ∉ {SUPER_ADMIN, MEGA_ADMIN, FAMILY_ADMIN}` **y** `res.createdById !== session.userId` → `{ error: 'No autorizado' }`. (Es decir: admins y cualquier FAMILY_ADMIN pueden borrar cualquier reserva; un MEMBER solo las suyas. Nota: FAMILY_ADMIN no está restringido a su grupo aquí.)
- **Efecto BD:** `reservation.delete`. Audit log `{ action: 'CANCELAR_RESERVA', details: 'Reserva cancelada (Periodo: {start es-ES} - {end es-ES}).', userId: (role===MEGA_ADMIN ? null : session.userId), propertyId: res.propertyId }`.
- **Otros:** `revalidatePath('/casas/${res.propertyId}')` → `{ success: true }`.

---

### 2.9 `actions/sorteo.ts`

**Helper:** `shuffleQueue<T>(array)`: barajado Fisher-Yates con `Math.random()`.

#### `runSorteo(data: { name: string, quincenas: string[], familyGroupIds: string[] })`
- **Firma:** objeto directo (no FormData).
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `{ error: 'No autorizado para ejecutar sorteos' }`.
- **Validación:** si falta `name` o `quincenas.length === 0` o `familyGroupIds.length === 0` → `{ error: 'Se requieren grupos de familia y quincenas para efectuar el sorteo.' }`.
- **Algoritmo:** baraja `quincenas` y `familyGroupIds`. Por cada índice `i` de quincenas barajadas: asigna `familyGroupId = shuffledFamilies[i % shuffledFamilies.length]` y `premio = shuffledQuincenas[i]`. (Si hay más quincenas que familias, las familias se reutilizan cíclicamente.)
- **Efecto BD:** `prisma.sorteo.create` con `{ name, createdById: session.userId, resultados: { create: records } }`, `include` resultados con `familyGroup`.
- **Otros:** `revalidatePath('/sorteos')` → `{ success: true, sorteo }`.

#### `deleteSorteo(formData)`
- **Autorización:** `role ∈ {SUPER_ADMIN, MEGA_ADMIN}` → si no `return` silencioso.
- **Input:** `id`. Falta → `return`.
- **Efecto:** `prisma.sorteo.delete({ where: { id } })` (cascada borra `SorteoResultado`). `revalidatePath('/sorteos')`.

---

### 2.10 `actions/user.ts`

`BCRYPT_ROUNDS = 12`.

#### `updateFontSize(prevState, formData)`
- **Autorización:** requiere sesión → si no `{ error: 'No autorizado' }`.
- **Input:** `fontSize`. Falta → `{ error: 'Parámetro no válido' }`.
- **Efecto:** lee `user.uiPreferences` (JSON), lo parsea (try/catch → `{}` si falla), hace merge `{ ...prefs, fontSize }`, y guarda `uiPreferences: JSON.stringify(prefs)`.
- **Otros:** `revalidatePath('/', 'layout')` → `{ success: true }`.

#### `updateUserProfile(prevState, formData)`
- **Autorización:** requiere sesión → si no `{ error: 'No autorizado' }`.
- **Inputs:** `name`, `email`, `password`, `image`. Falta `name || email` → `{ error: 'Nombre y correo son requeridos' }`.
- **Reglas:**
  - Unicidad de email: `findFirst({ where: { email } })`; si existe y `id !== session.userId` → `{ error: 'El correo ya está en uso' }`.
  - `image`: si truthy se guarda en `image` (Base64 avatar).
  - `password`: si truthy y `length > 0`: requiere `length >= 6` (`{ error: 'Mínimo 6 caracteres' }`); hashea con bcrypt(12) en `passwordHash`. (Discrepancia: el reset de `auth.ts` exige mínimo 8; aquí 6.)
- **Efecto:** `prisma.user.update({ where: { id: session.userId }, data: { name, email, [image], [passwordHash] } })`.
- **Otros:** `revalidatePath('/', 'layout')` → `{ success: true }`.

---

## 3. Modelo de datos (Prisma)

- **Generador:** `prisma-client-js`.
- **Datasource:** `provider = "sqlite"`, `url = env("DATABASE_URL")`.

### `User`
| Campo | Tipo | Default / Notas |
|---|---|---|
| `id` | String `@id` | `@default(cuid())` |
| `email` | String? `@unique` | opcional |
| `passwordHash` | String? | |
| `role` | String | `@default("MEMBER")` — comentario: MEGA_ADMIN, SUPER_ADMIN, FAMILY_ADMIN, MEMBER |
| `name` | String | obligatorio |
| `uiPreferences` | String? | JSON |
| `image` | String? | Base64 Avatar |
| `resetToken` | String? | |
| `resetTokenExpiry` | DateTime? | |
| `createdAt` | DateTime | `@default(now())` |
| `updatedAt` | DateTime | `@updatedAt` |
| `familyGroupId` | String? | FK |
| `familyGroup` | FamilyGroup? | relación, **onDelete: SetNull** |
| Relaciones inversas | `reservations` Reservation[], `notifications` NotificationSetting[], `announcements` Announcement[], `auditLogs` AuditLog[], `sorteosCreados` Sorteo[] | |

### `NotificationSetting`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `userId` | String | FK |
| `user` | User | **onDelete: Cascade** |
| `type` | String | p.ej. `'PRE_STAY'` |
| `isActive` | Boolean | `@default(true)` |
| `customText` | String? | |
| `updatedAt` | DateTime | `@updatedAt` |
| Restricción | `@@unique([userId, type])` | clave compuesta `userId_type` |

### `FamilyGroup`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `name` | String | |
| `color` | String | `@default("#3b82f6")` |
| `createdAt` / `updatedAt` | DateTime | now / `@updatedAt` |
| Inversas | `members` User[], `reservations` Reservation[], `sorteoResultados` SorteoResultado[] | |

### `Property`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `name` | String | |
| `description` | String? | |
| `image` | String? | |
| `createdAt` / `updatedAt` | DateTime | |
| Inversas | `reservations` Reservation[], `outReports` OutReport[], `auditLogs` AuditLog[], `announcements` Announcement[] | |

### `Reservation`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `propertyId` | String | FK |
| `property` | Property | **onDelete: Cascade** |
| `familyGroupId` | String? | FK |
| `familyGroup` | FamilyGroup? | **onDelete: SetNull** |
| `createdById` | String | FK |
| `createdBy` | User | (sin onDelete explícito → Restrict por defecto; por eso las actions reasignan reservas al MegaAdmin antes de borrar usuarios) |
| `startDate` | DateTime | |
| `endDate` | DateTime | |
| `guestCount` | Int | `@default(1)` |
| `guestsList` | String? | JSON string |
| `isMaintenance` | Boolean | `@default(false)` |
| `createdAt` / `updatedAt` | DateTime | |
| `outReport` | OutReport? | relación 1:1 inversa |

### `OutReport`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `propertyId` | String | FK |
| `property` | Property | **onDelete: Cascade** |
| `checkIn` | DateTime | |
| `checkOut` | DateTime | |
| `generalStatus` | String | (en `submitReport` se guarda `'COMPLETADO'`) |
| `damages` | String? | |
| `missingItems` | String? | |
| `notes` | String? | |
| `imageUrls` | String? | JSON string |
| `rating` | Int? | 1-5 stars |
| `checklist` | String? | JSON string |
| `createdAt` | DateTime | `@default(now())` |
| `reservationId` | String? `@unique` | |
| `reservation` | Reservation? | (sin onDelete explícito) |

### `SystemConfig`
| Campo | Tipo | Default |
|---|---|---|
| `id` | String `@id` | `@default("global")` |
| `smtpHost` | String? | |
| `smtpPort` | Int? | |
| `smtpUser` | String? | |
| `smtpPass` | String? | (en claro) |
| `smtpSecure` | Boolean | `@default(false)` |
| `baseUrl` | String? | |
| `maxReservationDays` | Int | `@default(30)` |
| `updatedAt` | DateTime | `@updatedAt` |

### `Announcement`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `title` | String | |
| `content` | String | |
| `createdAt` | DateTime | now |
| `authorId` | String | FK |
| `author` | User | **onDelete: Cascade** |
| `properties` | Property[] | relación M:N implícita |

### `AuditLog`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `action` | String | (`CREAR_RESERVA`, `CANCELAR_RESERVA`) |
| `details` | String | |
| `createdAt` | DateTime | now |
| `userId` | String? | FK (null para acciones de MEGA_ADMIN) |
| `user` | User? | **onDelete: SetNull** |
| `propertyId` | String? | FK |
| `property` | Property? | **onDelete: Cascade** |

### `NotificationTemplate`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `type` | String `@unique` | `'POST_STAY'`, `'MONTHLY_REMINDER'` |
| `subject` | String | |
| `body` | String | |
| `updatedAt` | DateTime | `@updatedAt` |

### `Sorteo`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `name` | String | |
| `createdAt` | DateTime | now |
| `createdById` | String | FK |
| `createdBy` | User | (sin onDelete explícito) |
| `resultados` | SorteoResultado[] | |

### `SorteoResultado`
| Campo | Tipo | Notas |
|---|---|---|
| `id` | String `@id` `@default(cuid())` | |
| `sorteoId` | String | FK |
| `sorteo` | Sorteo | **onDelete: Cascade** |
| `familyGroupId` | String | FK |
| `familyGroup` | FamilyGroup | **onDelete: Cascade** |
| `premio` | String | p.ej. `"1ra Quincena Julio"` |

**Resumen de `onDelete`:** SetNull → User.familyGroup, Reservation.familyGroup, AuditLog.user. Cascade → NotificationSetting.user, Reservation.property, OutReport.property, AuditLog.property, Announcement.author, SorteoResultado.sorteo, SorteoResultado.familyGroup. Sin declarar (Restrict por defecto) → Reservation.createdBy, OutReport.reservation, Sorteo.createdBy.

---

## 4. Sesión / JWT (`lib/session.ts`)

- **Librería:** `jose` (`SignJWT` / `jwtVerify`).
- **Secret:** `process.env.JWT_SECRET`. Si no está definido, el módulo **lanza error en import** (`CRÍTICO: No se ha definido JWT_SECRET … el servidor no puede arrancar.`). Se codifica con `TextEncoder`.
- **Algoritmo:** `HS256`.
- **Claims fijos:** `issuer = 'portal-familia'`, `audience = 'portal-familia'`, `setIssuedAt()`, `setExpirationTime('7d')`.
- **Payload (`SessionPayload`):** `{ userId: string, role: string, expiresAt: Date }`.
- **`encrypt(payload)`:** firma JWT con header `{ alg: 'HS256' }`.
- **`decrypt(session = '')`:** verifica con `algorithms: ['HS256']`, issuer y audience. En cualquier error → `null` (no lanza).
- **`createSession(userId, role)`:** `expiresAt = Date.now() + 7 días`. Setea cookie `session`:
  - `httpOnly: true`
  - `secure: process.env.NODE_ENV === 'production'`
  - `expires: expiresAt`
  - `sameSite: 'lax'`
  - `path: '/'`
- **`deleteSession()`:** `cookieStore.delete('session')`.
- **Cookie:** nombre `session`, vigencia **7 días**.

---

## 5. Rate limiting (`lib/rate-limit.ts`)

- **Implementación:** en memoria, `Map<string, { count, resetAt }>`. Comentario: válido para Docker Node-standalone; NO usar en serverless sin Redis.
- **`checkRateLimit(ip, maxAttempts = 15, windowMs = 60000)`:**
  - Si no hay registro o `resetAt < now` → reinicia `{ count: 1, resetAt: now + windowMs }`, devuelve `{ allowed: true, remaining: maxAttempts - 1 }`.
  - Si `count >= maxAttempts` → `{ allowed: false, remaining: 0 }`.
  - En otro caso incrementa `count` → `{ allowed: true, remaining: maxAttempts - count }`.
- **Usos reales:** `login` y `sendPasswordReset`, ambos con **15 intentos / 60 000 ms (1 min)** por IP. IP tomada de `x-forwarded-for` → `x-real-ip` → `'unknown'`.

---

## 6. Middleware (`middleware.ts`)

- **Rutas protegidas (`protectedRoutes`):** `['/', '/casas', '/configuracion', '/usuarios', '/reportes']`.
- **Rutas públicas (`publicRoutes`):** `['/login', '/reporte']`.
- **Coincidencia:** una ruta cuenta como protegida/pública si `path === route` **o** `path.startsWith(route + '/')`. (Nota: como `'/'` es prefijo, en la práctica toda ruta no excluida por el matcher entra en `isProtectedRoute`.)
- **Lógica:**
  - Lee cookie `session` y la desencripta.
  - Si ruta protegida y `!session?.userId` → `redirect('/login')`.
  - Si ruta pública y hay sesión y `path === '/login'` → `redirect('/')`.
  - En otro caso → `NextResponse.next()`.
- **Matcher:** `['/((?!api|_next/static|_next/image|favicon.ico).*)']` (excluye API, estáticos de Next, imágenes y favicon).

---

## 7. Arranque — `instrumentation.ts` + logger

### `register()` (instrumentation)
- Solo actúa si `process.env.NEXT_RUNTIME === 'nodejs'`.
- Importa e invoca `initLogger()` (de `@/lib/logger`).
- **Fail-fast producción:** si `NODE_ENV === 'production'` y falta `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` → lanza error `CRÍTICO: NEXT_SERVER_ACTIONS_ENCRYPTION_KEY no está definida…` (evita el error "Failed to find Server Action" entre despliegues). Sugiere generarla con `openssl rand -base64 32`.
- Importa e invoca `startCronJobs()` (de `@/lib/cron`).

### `lib/logger.ts` (logger de archivo)
- **Directorio:** `process.env.LOG_DIR?.trim()` o `path.join(process.cwd(), 'logs')`. Se crea con `mkdirSync recursive` y se comprueba escritura (`W_OK`); si no es escribible, escribe aviso a `stderr` y desactiva escritura a fichero (`dirWritable = false`).
- **Fichero diario:** `app-{YYYY-MM-DD}.log` (fecha ISO truncada a 10 chars). Se escribe con `appendFileSync`. Línea: `[{ISO timestamp}] [{LEVEL}] {mensaje}`.
- **Redacción de secretos (`REDACT_KEYS`):** cualquier clave (case-insensitive) en: `password, pass, passwordhash, secret, token, resettoken, authorization, cookie, session, jwt_secret, turnstile_secret_key, next_server_actions_encryption_key` se reemplaza por `'[REDACTED]'` en el `safeStringify` (que además detecta referencias circulares → `'[Circular]'`).
- **`initLogger()`** (idempotente):
  - Sustituye `console.error` y `console.warn` por wrappers que además escriben al fichero con nivel `ERROR`/`WARN` (y siguen llamando al original).
  - Handlers de proceso: `uncaughtException` y `unhandledRejection` → nivel `FATAL`; `SIGTERM`/`SIGINT` → `INFO` ("Received {signal}, process is shutting down"); `exit` → `INFO` ("Process exit (code=…)").
  - Escribe línea inicial `INFO` "Logger initialized. Writing to … (writable=…)".
- **`logger` export:** `info/warn/error/debug` que escriben directamente al fichero con esos niveles.

### `lib/prisma.ts`
- Singleton: reutiliza `global.prisma` o crea `new PrismaClient()`. En no-producción guarda la instancia en `global` (evita múltiples conexiones con HMR).

---

## 8. Cron (`lib/cron.ts`)

### Programación
- **Guard `cronStarted`:** evita registrar handlers duplicados (HMR en dev). Comentario: para multi-instancia haría falta lock distribuido (Redis o fila en SystemConfig).
- **Un único `cron.schedule('30 8 * * *', …)`** → **todos los días a las 08:30** en la zona horaria del servidor. En cada ejecución, en orden:
  1. `processDailyNotifications()`
  2. `processPostStayNotifications()`
  3. Si `new Date().getDate() === 1` (día 1 del mes): `processMonthlyReminders()`
  4. `processEndOfYearArchive()`
- Errores globales → `console.error('Error procesando el Cron de Portal Familia:', …)`.

### `processDailyNotifications()` — recordatorio PRE-estancia
- Requiere `config.smtpHost && config.smtpUser` (si no, return).
- **Ventana:** reservas cuyo `startDate` está en **[mañana, pasado mañana)** (es decir, empiezan **mañana**) y `isMaintenance: false`. Incluye `createdBy`, `familyGroup.members`, `property`.
- Por reserva:
  - Lee `notificationSetting` con `type: 'PRE_STAY', isActive: true` (de cualquier usuario). Por cada una con `customText`, concatena un bloque HTML "Mensaje de Administración" (con `\n` → `<br/>`).
  - Destinatarios (`Set`, sin duplicados): `createdBy.email` + email de cada miembro del `familyGroup`.
  - Enlace: `{baseUrl || ''}/reporte`.
  - **Correo:** `from`: `"Portal Familia Automático" <smtpUser>`. Asunto `🏡 Recordatorio Oficial de Viaje a {property.name}`. Cuerpo: bienvenida + "preparar todo para el viaje de {guestCount} personas en {property.name}", reglas de administración, botón "Formulario de Salida Seguro" → `/reporte`.
  - Errores por destinatario → `console.error('Error enviando recordatorio pre-estancia:', mailError?.message)` (sin PII).

### `processPostStayNotifications()` — POST-estancia / checkout
- Requiere `config.smtpHost`. Requiere plantilla `notificationTemplate` con `type: 'POST_STAY'` (si no existe, return).
- **Ventana:** reservas con `endDate` en **[ayer, hoy)** (terminaron **ayer**) y `isMaintenance: false`.
- Por reserva determina los "viajeros":
  - Siempre incluye `createdBy`.
  - Si hay `guestsList` y `familyGroup`: añade los miembros cuyo `name` aparece (substring `includes`) en `guestsList` (excluyendo al creador).
  - Busca un "admin viajero": primer miembro con `role ∈ {FAMILY_ADMIN, SUPER_ADMIN}`.
  - **Destinatario único:** `adminTraveler?.email || travelingMembers[0]?.email`. Si no hay email, se salta.
- **Correo:** enlace `{baseUrl||'http://localhost:3000'}/checkout/{res.id}`. Cuerpo = `template.body` con reemplazos globales: `{{PropertyName}}` → `property.name`, `{{UserName}}` → nombre del admin viajero o del primer viajero, `{{FormLink}}` → formLink. Asunto = `template.subject` con `{{PropertyName}}` reemplazado. `from`: `"Portal Familia Automático" <smtpUser>`. Errores → `console.error('Error mailing checkout:', e?.message)`.

### `processMonthlyReminders()` — solo el día 1 del mes
- Requiere `config.smtpHost` y plantilla `type: 'MONTHLY_REMINDER'`.
- **Ventana:** reservas con `startDate` dentro del **mes actual completo** (`startOfMonth` … `endOfMonth` 23:59:59) y `isMaintenance: false`. Si no hay ninguna, return.
- Por reserva: destinatario `createdBy.email` (si no hay, se salta). Cuerpo = `template.body` con `{{PropertyName}}`, `{{UserName}}` (`createdBy.name`), `{{StartDate}}` (`startDate.toLocaleDateString()`). Asunto = `template.subject` (sin reemplazos). Errores silenciados (`catch {}`).

### `processEndOfYearArchive()` — archivado anual (31 de diciembre)
- **Condición:** solo se ejecuta si `today.getMonth() === 11 && today.getDate() === 31` (31 dic).
- **Recopila datos del año:**
  - `reservations`: `where: { startDate: { lte: yearEnd } }` (incluye año actual y anteriores), `include: property, familyGroup, createdBy`. (`yearStart` se calcula pero el filtro real usa solo `lte: yearEnd`.)
  - `reports`: `outReport` `where: { checkOut: { lte: yearEnd } }`, `include: property`.
- **Genera Excel (`xlsx`)** con 2 hojas:
  - **Hoja "Reservas Anuales"** — columnas exactas: `"Casa Destino"` (property.name), `"Llegada Real"` (startDate locale), `"Salida Check-out"` (endDate locale), `"Grupo Familiar"` (`familyGroup?.name || 'Varios/Ninguno'`), `"Creador/Responsable"` (createdBy.name), `"Lista de Asistentes"` (guestsList), `"Total Plazas"` (guestCount), `"Mantenimiento Bloqueo"` (`isMaintenance ? 'SÍ' : 'NO'`).
  - **Hoja "Reportes y Evaluaciones"** — columnas: `"Casa Evaluada"` (property.name), `"Calificación Otorgada (/10)"` (generalStatus), `"Lista Daños"` (`damages || 'Ninguno'`), `"Lista Faltantes"` (`missingItems || 'Ninguno'`), `"Fecha Declarada CheckIn"` (checkIn locale), `"Día Salida CheckOut"` (checkOut locale).
  - Fichero: `Archivo_Historico_Ano_{año}.xlsx` en `process.env.UPLOAD_DIR || {cwd}/uploads` (se crea el dir si falta). `xlsx.writeFile`.
- **Borrado tras archivar:**
  - `outReport.deleteMany({ where: { checkOut: { lte: yearEnd } } })`.
  - `reservation.deleteMany({ where: { endDate: { lte: yearEnd } } })` (conserva reservas futuras cuyo `endDate > yearEnd`).
- **Correo a administradores:** si `smtpHost && smtpUser`, a todos los `User` con `role ∈ {MEGA_ADMIN, SUPER_ADMIN}` con email. `from`: `"Sistema de Archivo GBD" <smtpUser>`. Asunto `📦 Cierre del Año Operativo {año} Realizado Correctamente`. Cuerpo: explica el cierre, el empaquetado a Excel en carpetas persistentes (Docker), reinicio en blanco para enero, y enlace de descarga `{baseUrl}/api/uploads/{fileName}`. Errores silenciados (`catch {}`).

---

## 9. Inventario de correos (resumen)

| Disparador | Función | `from` | Destinatarios | Asunto |
|---|---|---|---|---|
| Crear anuncio | `createAnnouncement` | `"Portal Familia"` | Todos los usuarios con email salvo autor (BCC) | `Nuevo Anuncio General: …` / `Anuncio para {props}: …` |
| Reset password | `sendPasswordReset` | `"Portal Familia"` | Usuario solicitante | `Restablecimiento de Contraseña` |
| Alta usuario | `sendWelcomeEmail` (family.ts) | `"Portal Familia"` | Usuario nuevo | `Bienvenido a Portal Familia` |
| Test SMTP | `testSmtpConnection` | `Portal Familia` | `targetEmail` (def. `contacto@belucm.me`) | `Portal Familia - Prueba de Conexión SMTP` |
| Envío reporte salida | `submitReport` | `"Portal Familia Automático"` | MEGA_ADMIN + SUPER_ADMIN con email | `✅ Nuevo Reporte de Salida: {prop}` |
| Crear reserva | `createReservation` | `"Portal Familia Automático"` | SUPER_ADMIN con email | `🏨 Nueva reserva creada en {prop}` |
| Cron pre-estancia | `processDailyNotifications` | `"Portal Familia Automático"` | Creador + miembros del grupo | `🏡 Recordatorio Oficial de Viaje a {prop}` |
| Cron post-estancia | `processPostStayNotifications` | `"Portal Familia Automático"` | Admin viajero o creador | (plantilla `POST_STAY.subject`) |
| Cron mensual (día 1) | `processMonthlyReminders` | `"Portal Familia Automático"` | Creador de cada reserva del mes | (plantilla `MONTHLY_REMINDER.subject`) |
| Cron cierre anual (31 dic) | `processEndOfYearArchive` | `"Sistema de Archivo GBD"` | MEGA_ADMIN + SUPER_ADMIN con email | `📦 Cierre del Año Operativo {año}…` |

Todos los transports usan `port = smtpPort || 587`, `secure = smtpSecure`, auth `{ smtpUser, smtpPass }`. Timeouts de 5000 ms presentes en: announcement, auth (reset), config (welcome/test). Reservation, report y cron no fijan timeout salvo lo indicado.

---

## 10. Variables de entorno detectadas

- `JWT_SECRET` (obligatoria; el módulo session lanza si falta).
- `NODE_ENV` (controla `secure` cookie, enforcement de Turnstile, fail-fast de encryption key, singleton Prisma).
- `TURNSTILE_SECRET_KEY` (captcha Cloudflare Turnstile).
- `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` (obligatoria en producción).
- `NEXT_RUNTIME` (gating de instrumentation).
- `DATABASE_URL` (SQLite).
- `UPLOAD_DIR` (default `{cwd}/uploads`) — usado en report, config wipe y cron.
- `LOG_DIR` (default `{cwd}/logs`).

---

## Hallazgos / discrepancias notables (para no perder en la migración)

- **`submitReport` no tiene autenticación** — endpoint público que crea `OutReport`, escribe ficheros en disco y dispara correos. La ruta `/reporte` es pública en el middleware.
- **`promoteUserToRole` no exige sesión válida** salvo para el caso `newRole === 'SUPER_ADMIN'`; cualquier otro rol puede asignarse sin control explícito de permisos.
- **Inconsistencia de longitud mínima de contraseña:** reset (`auth.ts`) exige ≥ 8; `updateUserProfile` (`user.ts`) exige ≥ 6; `createMegaAdmin` exige ≥ 1.
- **Inconsistencia `maxReservationDays`:** default del modelo `30`, pero el fallback en `createReservation` es `15` (`|| 15`).
- **`SystemConfig.smtpPass` se almacena en claro** y `getSystemConfig` lo devuelve completo a MEGA/SUPER_ADMIN.
- **`createReservation`** notifica solo a `SUPER_ADMIN` (no MEGA_ADMIN); el solapamiento bloquea cualquier intersección de fechas en la propiedad (incluye reservas de mantenimiento).
- **Acciones del MEGA_ADMIN se registran en `AuditLog` con `userId: null`** (anonimizadas).
- **`deleteReservation`:** cualquier `FAMILY_ADMIN` puede borrar reservas de cualquier grupo (no se restringe al propio grupo).
- **El cron es de proceso único** sin lock distribuido — en despliegues multi-instancia enviaría correos duplicados.

Archivos fuente documentados (rutas absolutas):
- `C:/Users/ignac/OneDrive/Escritorio/sanchezrubal_app-main/legacy-next/src/app/actions/{announcement,auth,config,family,notifications,property,report,reservation,sorteo,user}.ts`
- `C:/Users/ignac/OneDrive/Escritorio/sanchezrubal_app-main/legacy-next/src/lib/{cron,session,rate-limit,prisma,logger}.ts`
- `C:/Users/ignac/OneDrive/Escritorio/sanchezrubal_app-main/legacy-next/src/{middleware,instrumentation}.ts`
- `C:/Users/ignac/OneDrive/Escritorio/sanchezrubal_app-main/legacy-next/prisma/schema.prisma`

> Nota: documenté adicionalmente `src/lib/logger.ts` (no estaba en la lista original pero `instrumentation.ts` lo invoca vía `initLogger()`, requerido por el punto "arranque: logger + cron"). Todos los demás archivos solicitados se leyeron íntegros.
agentId: a294a19158fab2672 (use SendMessage with to: 'a294a19158fab2672' to continue this agent)
<usage>subagent_tokens: 93974
tool_uses: 19
duration_ms: 267837</usage>