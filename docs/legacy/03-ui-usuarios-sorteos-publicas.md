# Documentación de Producto / UX — App Legacy (Next.js) "Portal Familia"

> **Nota de alcance:** Las *server actions* (`createFamilyGroup`, `runSorteo`, `submitReport`, `login`, etc.) se invocan desde estos componentes pero su implementación se documenta en `01-backend-funciones-datos.md`. Aquí se documenta el contrato observable desde la UI (campos de `FormData`, parámetros, estado de retorno) y el flujo de uso.

---

## Modelo de roles (transversal)

| Rol | Etiqueta UI mostrada | Notas |
|---|---|---|
| `MEGA_ADMIN` | "Mega Admin" (badge rojo `bg-error/20`) | Control absoluto. No se puede eliminar ni degradar desde la tabla. |
| `SUPER_ADMIN` | "Super Admin" (badge azul `bg-primary/20`) | Privilegios globales. |
| `FAMILY_ADMIN` | "Admin de Grupo" / "Admin Principal" (badge `bg-secondary-container`) | Administra su propio grupo familiar. |
| `MEMBER` | "Miembro" / "Hijo / Integrante" (badge gris) | Usuario estándar. |

**Concepto `isSuperAdmin`** (usado repetidamente): es `true` cuando `session.role === 'SUPER_ADMIN' || session.role === 'MEGA_ADMIN'`.

La sesión se obtiene en server components con `decrypt(cookieStore.get('session')?.value)` (cookie `session`).

---

## SECCIÓN 1 — Usuarios y Grupos

**Ruta:** `/(dashboard)/usuarios` → `page.tsx` (Server Component, `async`)
**Título visible:** "Grupos" — subtítulo "Gestiona la lista de grupos familiares y usuarios."

### 1.1 Qué muestra y datos que carga

Carga desde Prisma:
- `session` (cookie) y, si hay `userId`, el `user` actual (`prisma.user.findUnique`).
- `families`: `prisma.familyGroup.findMany` con `include: { members: true }`.
  - **Condicional por rol:** si `isSuperAdmin` → trae **todas** las familias (`where: undefined`); si no → solo la familia del usuario (`where: { id: user?.familyGroupId || '' }`).
- `allUsers`: solo si `isSuperAdmin` → `prisma.user.findMany({ include: { familyGroup: true }, orderBy: { createdAt: 'desc' } })`. Si no es super admin, `allUsers = []`.
- `superAdminsList`: `prisma.user.findMany` filtrando `role in ['SUPER_ADMIN','MEGA_ADMIN']`, seleccionando `name` y `email`.

Estadísticas calculadas:
- `totalGrupos = families.length`
- `totalUsuarios` = suma de `members.length` de todas las familias.

### 1.2 Estructura de la página

**a) Header.** A la derecha:
- Si `isSuperAdmin`: se renderizan los botones `<NewIndividualUserForm />` y `<NewGroupForm />`.
- Si NO: se muestra un aviso "Para crear un grupo, contacta a:" seguido de chips con `nombre (email)` de cada super admin de `superAdminsList`.

**b) Ribbon de estadísticas (3 tarjetas):**
1. "Total Grupos" → `totalGrupos`.
2. "Usuarios Vinculados" → `totalUsuarios`.
3. "Privilegios Máximos" → texto `'Ilimitado'` si `isSuperAdmin`, si no `'Limitado'`.

**c) Sección "Grupos Familiares" (tarjetas).** Una tarjeta por cada `family`:
- Cabecera con color de fondo `family.color`.
- Nombre `family.name`.
- **Botón eliminar familia** (icono papelera, rojo): solo si `isSuperAdmin`. Es un `<form action={deleteFamilyGroup}>` con `<input hidden name="groupId" value={family.id}>`.
- **Responsable:** se calcula como `family.members.find(m => m.role === 'FAMILY_ADMIN')` o, en su defecto, `family.members[0]`. Muestra iniciales (2 letras del nombre) y nombre, o "Sin Admin".
- Badge fijo "Activo".
- **Acción inferior (condicional por rol):**
  - Si `isSuperAdmin` **O** (`user.familyGroupId === family.id` **Y** `user.role === 'FAMILY_ADMIN'`) → renderiza `<GroupManagementModal family={family} isSuperAdmin={isSuperAdmin} />` (botón "Gestionar Familia").
  - En cualquier otro caso → bloque inerte "Sólo Visualización".

**d) Sección "Ecosistema Analítico / Todos los Usuarios"** (tabla). **Solo si `isSuperAdmin`.** Tabla con columnas: *Usuario Registrado* (avatar de iniciales, nombre, email), *Nivel de Privilegios* (badge según rol), *Asociación Grupal* (`u.familyGroup?.name || 'Sistema Global'`), *Acciones*.
- **Acciones por fila (condicional):** solo si `u.role !== 'MEGA_ADMIN'`.
  - **Botón ascender/relegar:** solo si `session.role` es `MEGA_ADMIN` o `SUPER_ADMIN`. Es un `<form>` con una **server action inline** (`"use server"`) que ejecuta:
    ```
    prisma.user.update({ where:{id:u.id}, data:{ role: u.role === 'SUPER_ADMIN' ? 'FAMILY_ADMIN' : 'SUPER_ADMIN' }})
    ```
    y después `revalidatePath('/usuarios')`. El texto del botón es **"Relegar"** si el usuario ya es `SUPER_ADMIN`, o **"Ascender a Súper Admin"** en caso contrario. (Alterna entre SUPER_ADMIN ↔ FAMILY_ADMIN.)
  - **Botón "Dar de Baja"** (papelera): `<form action={deleteUser}>` con `<input hidden name="userId" value={u.id}>`.
- Si `allUsers.length === 0`: muestra "Cargando base de datos segura...".

### 1.3 Formulario: Crear Grupo Familiar (`new-group-form.tsx`)

Botón disparador (solo super admin): **"Crear Grupo Familiar"** (icono `group_add`). Abre un modal overlay (estado `isOpen`).
Título modal: "Nuevo Grupo" — "Añadir cuenta y administrador del grupo."

**Envío:** `onSubmit` hace `preventDefault`, construye `FormData` y llama `createFamilyGroup({}, formData)` dentro de `startTransition`. Si `res.error` → muestra error inline; si no → cierra modal.

| Campo (name) | Etiqueta | Tipo | Obligatorio | Placeholder |
|---|---|---|---|---|
| `groupName` | Nombre del Grupo | text (Input) | **Sí** (`required`) | "Ej: Descendencia García" |
| `adminName` | Nombre Completo (sección "Credenciales del Administrador") | text | **Sí** | "Roberto García" |
| `adminEmail` | Correo Electrónico | email | **Sí** | "roberto@email.com" |

- Bloque visual "Credenciales del Administrador" (icono `admin_panel_settings`).
- Botón submit: "Crear Grupo y Administrador" (estado pending: "Procesando...").
- **Server action:** `createFamilyGroup(prevState, formData)` → crea grupo + usuario administrador.

### 1.4 Formulario: Alta Usuario Individual (`new-individual-user-form.tsx`)

Botón disparador (solo super admin): **"Alta Usuario Individual"** (icono `UserPlus`). Usa `<dialog>` nativo (`showModal()`/`close()`).
Título: "Registro Individual" — "Sin grupo familiar asignado" (icono `Briefcase`).

**Estado:** `useActionState(registerIndividualUser, null)`. Si `state.success` → cierra el diálogo.

| Campo (name) | Etiqueta | Tipo | Obligatorio | Opciones |
|---|---|---|---|---|
| `name` | Nombre Completo | text | **Sí** (`required`) | — |
| `email` | Correo Electrónico | email | **Sí** | — |
| `role` | Nivel de Rango | select | (default primera opción) | `MEMBER` → "Miembro Estándar"; `FAMILY_ADMIN` → "Administrador Independiente"; `SUPER_ADMIN` → "Súper Administrador Global" |

- Botones: "Cancelar" (cierra) y "Crear Usuario" (con spinner si `isPending`).
- **Server action:** `registerIndividualUser(prevState, formData)` → crea usuario sin grupo, con el rol elegido. Retorna `{ success }` o `{ error }`.

### 1.5 Modal: Gestionar Familia (`group-management-modal.tsx`)

Disponible para super admins y para el `FAMILY_ADMIN` del propio grupo. Botón: **"Gestionar Familia"** (icono `Settings2`).
Título modal: "Núcleo Familiar". Muestra punto de color `family.color`.

3 sub-bloques:

**a) Editar nombre del grupo ("Denominación Oficial").** `<form action={editAction}>` con `useActionState(updateFamilyGroupName, {})`.
- `<input hidden name="groupId" value={family.id}>`
- Campo `newName` (Input, `defaultValue={family.name}`, **`required`**).
- Botón "Actualizar". **Server action:** `updateFamilyGroupName(prevState, formData)`.

**b) Lista de integrantes ("Integrantes Registrados (N)").** Por cada `member`:
- Avatar (`m.image` o iniciales), nombre `m.name`, email `m.email`.
- **Select de rol** (cambia al instante con `onChange`):
  - `defaultValue`: si el rol es `SUPER_ADMIN`/`MEGA_ADMIN` se fuerza a mostrar `FAMILY_ADMIN`; si no, el rol real.
  - **`disabled`** si hay operación pendiente **o** si el miembro es `SUPER_ADMIN`/`MEGA_ADMIN`.
  - Opciones: `MEMBER` → "Hijo / Integrante"; `FAMILY_ADMIN` → "Admin Principal".
  - Al cambiar: `handleRoleChange(m.id, value)` → `FormData` con `userId` + `newRole` → `promoteUserToRole(formData)`.
- **Botón eliminar miembro** (papelera): `handleDeleteUser(m.id)` → `FormData` con `userId` → `deleteUser(formData)`.

**c) Añadir integrante (inline).** Renderiza `<NewMemberForm familyGroupId={family.id} inlineMode={true} isSuperAdmin={isSuperAdmin} />`.

**Server actions del modal:** `updateFamilyGroupName`, `deleteUser`, `promoteUserToRole` (de `@/app/actions/family`).

### 1.6 Formulario: Nuevo Miembro de Familia (`new-member-form.tsx`)

Componente reutilizable con dos modos:
- **`inlineMode={true}`**: formulario directo (dentro del modal de gestión). Tras éxito hace `reset()`.
- **`inlineMode={false}`** (por defecto): botón "Añadir Miembro Manualmente" que abre un modal "Registro de Familiar". Tras éxito cierra el modal.

**Envío:** `onSubmit` → `addFamilyMember({}, formData)` en `startTransition`.

| Campo (name) | Etiqueta | Tipo | Obligatorio | Opciones |
|---|---|---|---|---|
| `familyGroupId` | — | hidden | — | valor inyectado por prop |
| `name` | Nombre o Parentesco | text | **Sí** | placeholder "Ej. Tío Roberto" |
| `email` | Correo Electrónico | email | **Sí** | placeholder "roberto@email.com" |
| `role` | Asignar Rol | select | (default primera opción) | `MEMBER` → "Hijo / Integrante"; `FAMILY_ADMIN` → "Admin Principal de Familia" |

- Botón submit: "Enviar Clave e Invitar" (pending: "Creando Usuario..."). El texto sugiere que el alta envía credenciales por correo.
- **Server action:** `addFamilyMember(prevState, formData)`.

---

## SECCIÓN 2 — Perfil

**Ruta:** `/(dashboard)/perfil` → `page.tsx` (Server Component). Si no hay `session.userId` → `null`. Carga `user` por `session.userId`.

**Estructura:** cabecera con avatar de iniciales + "Mi Perfil". Dos secciones:
1. **"Datos Personales"** (icono `fingerprint`) → `<ProfileForm user={user} />`.
2. **"Ajustes Visuales"** (icono `palette`) → `<PreferencesForm />` (escala tipográfica; ver `02-...md` §5.2).

### 2.1 Formulario de Perfil (`profile-form.tsx`)

**Estado:** `useActionState(updateUserProfile, {})`. Avatar manejado en cliente (`avatar`, inicial `user.image`).

**Subida de avatar (cliente):** input `file` (`accept="image/*"`, oculto, disparado por overlay "Modificar"). `handleFileChange` lee con `FileReader.readAsDataURL` → guarda el **data URL** en estado → se envía vía `<input hidden name="image">`. (La imagen viaja como **base64** en el form, no como binario.)

| Campo (name) | Etiqueta | Tipo | Obligatorio | Notas |
|---|---|---|---|---|
| `image` | Foto de Perfil | hidden (data URL base64) | No | Se llena al elegir archivo |
| `name` | Nombre Completo | text | **Sí** (`required`) | `defaultValue={user.name}` |
| `email` | Correo Electrónico | email | **Sí** | `defaultValue={user.email}` |
| `password` | Cambiar la contraseña | password | No | `minLength={6}`; ayuda: "Déjalo en blanco si no quieres cambiarla." |

- Mensajes: `state.error` / `state.success` → "¡Datos guardados!".
- Botón submit: "Guardar Perfil".
- **Server action:** `updateUserProfile(prevState, formData)` de `@/app/actions/user`.

---

## SECCIÓN 3 — Reportes (Bóveda de Inspecciones)

**Ruta:** `/(dashboard)/reportes` → `page.tsx` (Server Component).
**Control de acceso:** si `session.role` **no** es `MEGA_ADMIN` ni `SUPER_ADMIN` → `redirect('/')`. **Solo administradores superiores.**

**Datos:** `prisma.outReport.findMany` con `include: { property: true, reservation: { include: { createdBy: true, familyGroup: true } } }`, orden `createdAt desc`.

**Qué muestra:** título "Bóveda de Inspecciones". Grid de tarjetas, una por `outReport`:
- Nombre de la propiedad + badge con `report.generalStatus`.
- **Huésped:** `report.reservation?.createdBy?.name`.
- **Familia:** `report.reservation?.familyGroup?.name || 'Independiente'`.
- **Salida:** `report.checkOut` formateada.
- **Comentarios / Notas:** `report.notes || 'Sin comentarios adicionales.'`
- **Evidencia Fotográfica:** parsea `report.imageUrls` como JSON (`JSON.parse(report.imageUrls || '[]')` con try/catch). Por cada imagen, enlace "Ver Foto" a `/api/uploads/{img}` (pestaña nueva). Muestra conteo "N Archivos".
- Si no hay reportes: "No existen revisiones activas en curso."

Esta página **solo visualiza** (sin formularios de escritura).

---

## SECCIÓN 4 — Sorteos (asignación)

**Ruta:** `/(dashboard)/sorteos` → `page.tsx` (Server Component).
**Control de acceso:** si no hay sesión o `session.role` no es `SUPER_ADMIN`/`MEGA_ADMIN` → `redirect('/')`.

**Datos:**
- `families`: `prisma.familyGroup.findMany({ select: { id, name }, orderBy: { name: 'asc' } })`.
- `history`: `prisma.sorteo.findMany({ orderBy: { createdAt: 'desc' }, include: { resultados: { include: { familyGroup: true } }, createdBy: { select:{name} } } })`.

**Estructura:**
- Título "Sorteos Recreativos". Componente `<SorteadorClient families={families} />`.
- **"Archivo de Sorteos Históricos":** por cada `sorteo`: nombre, fecha (`date-fns`, locale `es`: `"d 'de' MMMM yyyy, HH:mm"`), botón eliminar (`<form action={deleteSorteo}>` con `<input hidden name="id">`), lista de `resultados` (familia + badge `premio`), pie "Avalado por: {createdBy.name}". Vacío: "Sin antecedentes."

### 4.1 El sorteador (`sorteador.tsx`) — entradas

**Estado de cliente:**
- `selectedFamilies`: inicia con **todas** las familias seleccionadas.
- `quincenas`: lista `{id, text}`, inicia con una entrada vacía.
- `sorteoName`: texto.

**Controles:**
- **Evento / Título** (`sorteoName`): texto. Placeholder "Ej: Sorteo de Verano Ag/Jul".
- **Bolsa de Quincenas:** lista dinámica de inputs. Botón **"+ Añadir Boleto"**; cada fila tiene Input + botón eliminar (si hay >1). Ayuda clave: *"Ingresa en texto la quincena o periodo a sortear. **Puedes repetir un texto para sortear dos iguales.**"* → cada string es un premio/boleto independiente; se permiten duplicados.
- **Familias Disponibles ({sel}/{total}):** checkboxes (todas marcadas por defecto).
- **Botón "Iniciar Sorteo Justo"** (pending: "Validando Suerte..."), deshabilitado si no hay familias.

**Validaciones de cliente:**
1. `validQuincenas` = quincenas con texto no vacío.
2. `sorteoName` vacío → "Indica un nombre para referenciar el sorteo."
3. Sin quincenas válidas → "Agrega al menos una quincena válida."
4. Sin familias → "Selecciona al menos una familia participante."

**Invocación:** `runSorteo({ name: sorteoName, quincenas: validQuincenas, familyGroupIds: selectedFamilies })` (**objeto, no FormData**). Si éxito → limpia nombre y quincenas.

> El algoritmo real de asignación (barajado Fisher-Yates, emparejamiento familia↔premio, persistencia de `Sorteo` + `SorteoResultado`) está en `01-backend-funciones-datos.md` (`runSorteo` de `@/app/actions/sorteo`). **Server actions:** `runSorteo` (objeto) y `deleteSorteo` (`FormData` con `id`).

---

## SECCIÓN 5 — Login e Inicialización del Mega Admin

**Ruta:** `/login` → `page.tsx`. Llama `checkMegaAdminExists()`:
- Si **existe** → "Portal Familia" / "Inicia sesión..." → `<LoginForm />`.
- Si **no existe** → "Bienvenido al Portal" / "...inicializar la cuenta del Mega Administrador." → `<InitForm />`.

**Cloudflare Turnstile:** `siteKey = process.env.TURNSTILE_SITE_KEY || NEXT_PUBLIC_TURNSTILE_SITE_KEY`. Si existe, carga el script y ambos formularios renderizan `<div class="cf-turnstile" data-sitekey={siteKey}>`.

### 5.1 Login (`login-form.tsx`) — `useActionState(login, { error: '' })`

| Campo (name) | Etiqueta | Tipo | Obligatorio |
|---|---|---|---|
| `emailOrName` | Usuario o Email | text | **Sí** — placeholder "ej. MegaAdmin o juan@email.com" |
| `password` | Contraseña | password | **Sí** |
| (turnstile) | — | widget | condicional |

- Enlace "¿Has olvidado tu clave?" → `/forgot-password`. Botón "Iniciar Sesión".
- **Server action:** `login(prevState, formData)`. Acepta login por **nombre o email**.

### 5.2 Inicialización Mega Admin (`init-form.tsx`)

Aviso: *"Esta cuenta tendrá el control absoluto del sistema (SMTP, URL Base, nombramiento de Super Administradores). No la olvides."*

| Campo (name) | Etiqueta | Tipo | Obligatorio |
|---|---|---|---|
| `name` | Nombre de Usuario Master | text | **Sí** — "ej. FuncionarioJefe" |
| `password` | Contraseña Maestra | password | **Sí** |
| (turnstile) | — | widget | condicional |

- Botón "Crear Mega Administrador". **Server action:** `createMegaAdmin(prevState, formData)` (solo cuando aún no existe Mega Admin).

---

## SECCIÓN 6 — Recuperar / Restablecer Contraseña

### 6.1 Recuperar (`forgot-password/...`) — `useActionState(sendPasswordReset, { error: '' })`

Pública. Título "Recuperar Ingreso". Éxito (`state.success`): "Enlace Enviado" — *"Revisa la bandeja (y spam). **Tienes 15 minutos**..."* + botón "Volver al inicio".

| Campo (name) | Etiqueta | Tipo | Obligatorio |
|---|---|---|---|
| `email` | Correo Electrónico Registrado | email | **Sí** |

- Botón "Solicitar Enlace". **Server action:** `sendPasswordReset(prevState, formData)` (token con validez **15 minutos**).

### 6.2 Restablecer (`reset-password/...`) — `useActionState(resetPassword, { error: '' })`

Lee `searchParams` `{ token, email }`. Si falta alguno → "Enlace Roto". Si ok → "Nueva Clave" + `<ResetForm token email />`.

| Campo (name) | Etiqueta | Tipo | Obligatorio |
|---|---|---|---|
| `token` | — | hidden | (de la URL) |
| `email` | — | hidden | (de la URL) |
| `password` | Tu nueva contraseña | password | **Sí** |

- Éxito: "¡Clave Actualizada!" + botón "Ingresar al portal". **Server action:** `resetPassword(prevState, formData)`.

---

## SECCIÓN 7 — Checkout (Formulario de Salida simple)

**Ruta:** `/checkout/[id]` → `page.tsx`. **Pública** (acceso por enlace con `id` de reserva).

**Datos:** `prisma.reservation.findUnique({ where:{id}, include:{ property:true, outReport:true } })`.

**Estados:**
1. No existe la reserva → "Reserva no encontrada".
2. La reserva **ya tiene `outReport`** → "Reporte Completado" — "Ya se ha rellenado el formulario..." (bloquea reenvío).
3. Si no → muestra el formulario.

**Formulario** (`<form action={submitReport}>`):

| Campo (name) | Etiqueta | Tipo | Obligatorio | Notas |
|---|---|---|---|---|
| `reservationId` | — | hidden | — | `reservation.id` |
| `propertyId` | — | hidden | — | `reservation.propertyId` |
| `notes` | Comentarios de la Estancia | textarea (min-h 200px) | No | "Escribe aquí tus comentarios o incidencias..." |
| `images` | Fotografías (Opcional) | file (`accept="image/*"`, `multiple`) | No | "hasta 5 fotografías (Máximo 30MB por archivo)" |

- Botón "Enviar Formulario". **Server action:** `submitReport(formData)` de `@/app/actions/report`.
- **Importante:** esta variante envía **menos campos** que el post-estancia completo (solo `notes` + `images` + ids; **no** `rating`, `damages`, `missingItems`, `checkIn`, `checkOut`). Misma action `submitReport` reutilizada.

> Existen **dos** formularios que crean el mismo `outReport`: `/checkout/[id]` (simple) y `/reportes/nuevo/[id]` (inspección detallada). Ambos bloquean duplicados.

---

## SECCIÓN 8 — Formulario Post-Estancia / Inspección de Cierre

**Ruta:** `/reportes/nuevo/[id]` → `page.tsx`. **Pública** por enlace con `id` de reserva.

**Datos:** `prisma.reservation.findUnique({ where:{id}, include:{ property:true } })`; si no existe → `notFound()`. Comprueba `existing = prisma.outReport.findUnique({ where:{ reservationId:id } })`.

**Estados:** si **ya existe** reporte → "Reporte completado" (bloquea). Si no → `<PostStayForm reservationId propertyId checkIn={startDate} checkOut={endDate} />`.

### 8.1 Formulario de inspección (`post-stay-form.tsx`) — TODOS los campos

**Manejo de archivos (cliente):**
- Máximo **5** archivos en total → error "Máximo 5 fotografías permitidas."
- **30MB por archivo** (`30 * 1024 * 1024`) → error "La imagen {nombre} supera los 30MB permitidos."
- Miniaturas con botón para quitar cada archivo.

**Envío:** añade `reservationId`, `propertyId`, `checkIn` (ISO), `checkOut` (ISO), y cada archivo como `images`; llama `submitReport(fd)`.

| Campo (name) | Etiqueta | Tipo | Obligatorio | Restricciones / Opciones |
|---|---|---|---|---|
| `reservationId` | — | (añadido en submit) | — | de prop |
| `propertyId` | — | (añadido en submit) | — | de prop |
| `checkIn` | — | (añadido en submit) | — | ISO de `reservation.startDate` |
| `checkOut` | — | (añadido en submit) | — | ISO de `reservation.endDate` |
| `rating` | Calificación de la Casa (1 al 10) | number | **Sí** (`required`) | `min=1`, `max=10`, placeholder "Ej. 10" |
| `damages` | Declaración de Daños Ocasionales | textarea (3 filas) | No | "Indica cualquier rotura, mancha o daño..." |
| `missingItems` | Notificaciones de Artículos Faltantes o Perdidos | textarea (3 filas) | No | "¿Te has dejado algo? ¿Faltaba algo al llegar?..." |
| `images` | Evidencia Fotográfica | file (`multiple`, `accept="image/*"`) | No | Máx **5 archivos · 30MB c/u**; contador "N / 5" |

- **NO existe** un "checklist" de ítems ni un select de "estado general"; el estado se expresa con `rating` (1–10) + textos libres. El `generalStatus` que se ve en la Bóveda de Inspecciones se **deriva en la server action**, no se captura como campo.
- Botón: "Enviar Reporte al Departamento" (pending: "Procesando Documentos..."). **Server action:** `submitReport(formData)` (misma que checkout, aquí con el set completo).

---

## SECCIÓN 9 — Componentes UI base

Envoltorios estilizados con Tailwind (tema oscuro zinc) y `React.forwardRef`. Helper `cn(...inputs) = twMerge(clsx(inputs))` (definido en `button.tsx`).

### 9.1 `Button` (`button.tsx`)
- Extiende `React.ButtonHTMLAttributes`. **No** define variantes ni tamaños; una apariencia base sobrescribible vía `className`.
- Base: `inline-flex items-center justify-center rounded-md text-sm font-medium disabled:opacity-50 bg-zinc-100 text-zinc-900 hover:bg-zinc-200 h-10 px-4 py-2`. Exporta `cn` y el tipo `ButtonProps`.

### 9.2 `Input` (`input.tsx`)
- Extiende `React.InputHTMLAttributes`. Importa `cn` de `./button`.
- Base: `flex h-10 w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 placeholder:text-zinc-500 focus-visible:ring-1 disabled:opacity-50`.

### 9.3 `Label` (`label.tsx`)
- Extiende `React.LabelHTMLAttributes`. Importa `cn` de `./button`.
- Base: `text-sm font-medium leading-none text-zinc-300 peer-disabled:opacity-70`.

**Observación:** muchas pantallas sobreescriben el estilo zinc con el design system propio (`bg-surface-*`, `text-on-surface`, `rounded-xl`); las páginas de login usan el zinc por defecto. Algunos formularios (post-estancia, alta individual, checkout) usan `<input>`/`<select>`/`<textarea>` nativos.

---

## Resumen de Server Actions invocadas (contrato observable)

| Server action | Origen | Entrada | Usada en |
|---|---|---|---|
| `createFamilyGroup` | `actions/family` | `({}, FormData)` con `groupName`, `adminName`, `adminEmail` | Crear grupo |
| `registerIndividualUser` | `actions/family` | `(prev, FormData)` con `name`, `email`, `role` | Alta usuario individual |
| `addFamilyMember` | `actions/family` | `({}, FormData)` con `familyGroupId`, `name`, `email`, `role` | Nuevo miembro |
| `updateFamilyGroupName` | `actions/family` | `(prev, FormData)` con `groupId`, `newName` | Modal gestión |
| `promoteUserToRole` | `actions/family` | `FormData` con `userId`, `newRole` | Cambio de rol en modal |
| `deleteUser` | `actions/family` | `FormData` con `userId` | Tabla usuarios / modal |
| `deleteFamilyGroup` | `actions/family` | `FormData` con `groupId` | Tarjeta familia |
| (inline en `usuarios/page.tsx`) | inline `"use server"` | cambia `role` SUPER_ADMIN↔FAMILY_ADMIN + `revalidatePath` | Tabla usuarios |
| `updateUserProfile` | `actions/user` | `(prev, FormData)` con `name`, `email`, `password?`, `image?` (base64) | Perfil |
| `runSorteo` | `actions/sorteo` | **objeto** `{ name, quincenas: string[], familyGroupIds: string[] }` | Sorteador |
| `deleteSorteo` | `actions/sorteo` | `FormData` con `id` | Historial sorteos |
| `submitReport` | `actions/report` | `FormData` — checkout: `reservationId`,`propertyId`,`notes`,`images`; post-estancia: + `rating`,`damages`,`missingItems`,`checkIn`,`checkOut` | Checkout y Post-estancia |
| `login` | `actions/auth` | `(prev, FormData)` con `emailOrName`, `password`, turnstile | Login |
| `createMegaAdmin` | `actions/auth` | `(prev, FormData)` con `name`, `password`, turnstile | Init |
| `checkMegaAdminExists` | `actions/auth` | — | LoginPage (decide Login vs Init) |
| `sendPasswordReset` | `actions/auth` | `(prev, FormData)` con `email` | Forgot |
| `resetPassword` | `actions/auth` | `(prev, FormData)` con `token`, `email`, `password` | Reset |
