# Documentación de Producto / UX — App de Gestión Familiar (Next.js legacy)

> Esta documentación captura con fidelidad la UI del módulo `(dashboard)` de la app legacy. Se organiza por sección. Incluye lo que muestra cada pantalla, lo que puede hacer el usuario, el flujo paso a paso, cada formulario con todos sus campos, las validaciones de cliente, la server action que invoca cada botón y las condiciones por rol.

---

## 0. Marco general (Layout y navegación)

Archivo: `(dashboard)/layout.tsx`, `(dashboard)/sidebar.tsx`

### 0.1 Qué muestra

El layout envuelve todas las páginas del dashboard. Estructura:

- **Barra lateral fija (SideNavBar)** — visible solo en escritorio (`hidden md:flex`), ancho fijo 288px (`w-72`), a la izquierda.
- **Lienzo principal (main)** — desplazable, con margen izquierdo en escritorio (`md:ml-72`).
- **TopAppBar (cabecera superior)** — pegajosa (`sticky top-0`), muestra:
  - Saludo: **"Hola, {nombre del usuario}"** (si no hay nombre, queda "Hola, ").
  - Avatar circular con las **2 primeras letras** del nombre del usuario en mayúsculas (solo si hay usuario autenticado).
  - **Botón "Cerrar Sesión"** (ícono `logout`, color error). Invoca la server action `logout()` (de `@/app/actions/auth`) vía un `<form action>` inline con `"use server"`.
- **BottomNavBar (solo móvil)** — `md:hidden`, fija abajo, en grid de 4 columnas.

### 0.2 Carga de sesión

El layout lee la cookie `session`, la desencripta con `decrypt()` y, si hay `userId`, carga el `currentUser` desde Prisma (`prisma.user.findUnique`). Ese usuario se pasa a la `SideNavBar`.

### 0.3 Navegación lateral (escritorio) — `sidebar.tsx`

Cabecera de marca: **"Gestión Familiar"** con subtítulo **"Panel de Control"**.

Enlaces de navegación (en orden), cada uno con ícono Material Symbols:

| Etiqueta | Ruta (href) | Ícono | Visible para |
|---|---|---|---|
| Inicio | `/` | `home` | Todos |
| Domicilios | `/casas` | `calendar_month` | Todos |
| Grupos | `/usuarios` | `group` | Todos |
| Inspecciones | `/reportes` | `fact_check` | Todos |
| Sorteos | `/sorteos` | `casino` | **Solo** `SUPER_ADMIN` o `MEGA_ADMIN` |
| Configuración | `/configuracion` | `admin_panel_settings` | Todos |

- **Estado activo**: un enlace se marca activo si `pathname === href`, o (para href distinto de `/`) si `pathname.startsWith(href)`. El activo se resalta con fondo `bg-primary/20` y texto primario en negrita.
- **Pie de la barra lateral**: si hay `currentUser`, muestra una tarjeta-enlace a `/perfil` (ícono `account_circle`) con el **nombre** del usuario y su **rol** (texto literal del rol, p. ej. `SUPER_ADMIN`).

### 0.4 Navegación inferior (móvil) — en `layout.tsx`

Grid de 4 accesos directos:

| Etiqueta | Ruta | Ícono |
|---|---|---|
| Casas | `/casas` | `event` |
| Grupo | `/usuarios` | `group` |
| Perfil | `/perfil` | `account_circle` |
| Admin | `/configuracion` | `admin_panel_settings` (resaltado en color primario y negrita) |

> Nota: la barra inferior móvil NO aplica condicionales de rol; muestra los 4 accesos a todos. La barra lateral de escritorio sí oculta "Sorteos" a roles no-admin.

### 0.5 Roles existentes en el sistema (inferidos del código)

- `MEGA_ADMIN` — máximo nivel. Es también superadmin.
- `SUPER_ADMIN` — administrador global.
- `FAMILY_ADMIN` — administrador de su grupo familiar.
- Usuario estándar (cualquier otro rol / sin rol admin).

Definiciones de "superadmin" reutilizadas:
- `isSuperAdmin = (role === 'SUPER_ADMIN' || role === 'MEGA_ADMIN')`
- `isMegaAdmin = (role === 'MEGA_ADMIN')`
- `isFamilyAdmin = (role === 'FAMILY_ADMIN' || isSuperAdmin)`

---

## 1. Sección "Inicio" / Centro de Control (Tablón de Anuncios)

Archivos: `(dashboard)/page.tsx`, `announcement-form.tsx`, `delete-announcement-form.tsx`

### 1.1 Qué muestra

Ruta `/`. Título grande **"Centro de Control"** con subtítulo **"Bienvenido, {nombre}. Consulta el tablón general de la familia."**

Sección **"Tablón de Anuncios Global"**:
- Lista de anuncios (`prisma.announcement.findMany`, ordenados por `createdAt` descendente). Cada anuncio incluye su autor (`author.name`) y las propiedades asociadas (`properties.name`).
- Cada **tarjeta de anuncio** muestra:
  - **Título** del anuncio.
  - Una **etiqueta (chip)**:
    - Si el anuncio tiene propiedades asociadas → chip azul (primary) con los **nombres de las propiedades unidos por comas**.
    - Si no tiene propiedades → chip "**Anuncio General**" (color secundario).
  - **Contenido** del anuncio (respeta saltos de línea: `whitespace-pre-wrap`).
  - Pie: **"Publicado por {autor} el {fecha local} a las {hora local HH:MM}"**.
  - **Botón de eliminar** (ícono `delete_forever`, color error) — solo si es superadmin.
- **Estado vacío** (cuando no hay anuncios): ícono `campaign` y texto "No hay comunicados oficiales de la administración en este momento."

### 1.2 Condiciones por rol

- El **botón "Publicar Noticia"** (que abre el formulario de creación) se muestra **solo si `isSuperAdmin`** (`SUPER_ADMIN` o `MEGA_ADMIN`).
- El **botón de eliminar** en cada anuncio se muestra **solo si `isSuperAdmin`**.
- Los usuarios estándar solo ven la lista (lectura).

### 1.3 Datos cargados

- `properties = prisma.property.findMany({ select: { id, name } })` — se pasan al formulario para poder asociar el anuncio a domicilios.
- `user` — usuario actual (para el saludo).

### 1.4 Flujo de uso: Publicar un anuncio (solo superadmin)

1. El admin pulsa **"Publicar Noticia"** (botón azul, ícono `add_alert`).
2. Se abre un **modal** (overlay oscuro) titulado **"Nuevo Comunicado"** con un botón de cerrar (ícono `close`).
3. Rellena el formulario (ver 1.5).
4. Pulsa **"Publicar Ahora"** → se invoca `createAnnouncement(formData)` (de `@/app/actions/announcement`). Al terminar, el modal se cierra y se limpia la selección de propiedades.
5. Puede cancelar con **"Cancelar"** o con la X (cierra el modal sin enviar).

### 1.5 Formulario: "Nuevo Comunicado" (AnnouncementForm)

Server action: **`createAnnouncement(formData)`**.

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Título Breve | `title` | `input[type=text]` | **Sí** (`required`) | Placeholder: "Ej. Mantenimiento del Sistema" |
| Seleccionar Domicilios (Opcional) | `propertyIds` | Botones toggle → `input[type=hidden]` múltiples | No | Un botón por cada propiedad. Al seleccionar, se renderiza un `<input type="hidden" name="propertyIds" value={id}>` por cada propiedad elegida. Se pueden elegir varias. |
| Cuerpo de la Noticia | `content` | `textarea` (5 filas) | **Sí** (`required`) | Placeholder: "Escribe todos los detalles importantes para la familia..." |

**Comportamiento de la selección de domicilios:**
- Los domicilios se muestran como chips/botones (`type="button"`). Al pulsarlos se alternan (toggle) en el estado `selectedProperties`.
- Chip seleccionado: fondo primario. No seleccionado: fondo neutro.
- Si **ninguno** está seleccionado, aparece el aviso: *"Ninguno seleccionado. Será un anuncio global para todas las casas."*
- Por cada id seleccionado se inyecta un hidden input `propertyIds`.

**Validaciones de cliente:** `title` y `content` son `required` (validación nativa HTML). La selección de domicilios es opcional.

**Botones del formulario:**
- **"Cancelar"** (`type=button`) → cierra el modal, no envía.
- **X** (cabecera) → cierra el modal.
- **"Publicar Ahora"** (`type=submit`) → ejecuta `createAnnouncement(fd)`, luego `setOpen(false)` y `setSelectedProperties([])`.

### 1.6 Formulario: Eliminar anuncio (DeleteAnnouncementForm)

Server action: **`deleteAnnouncement`** (de `@/app/actions/announcement`).

- Es un `<form action={deleteAnnouncement}>` con un único campo oculto:

| Campo | name | Tipo | Obligatorio | Valor |
|---|---|---|---|---|
| ID del anuncio | `id` | `input[type=hidden]` | Sí | El id del anuncio |

- Botón submit con ícono `delete_forever` (title: "Eliminar Comunicado"). No hay confirmación previa (se envía directo). Visible solo a superadmin.

---

## 2. Sección "Domicilios" / Casas (listado)

Archivos: `(dashboard)/casas/page.tsx`, `casas/new-property-form.tsx`

### 2.1 Qué muestra

Ruta `/casas`. Título **"Domicilios"** con subtítulo **"Selecciona un domicilio para consultar y gestionar su disponibilidad."**

- **Grid de tarjetas de propiedades** (`prisma.property.findMany`, ordenadas por `name` ascendente). Responsive: 1 / 2 / 3 columnas.
- Cada **tarjeta de domicilio** muestra:
  - Ícono `other_houses`.
  - **Nombre** del domicilio (enlace a `/casas/{id}`).
  - **Descripción** si existe (recortada a 2 líneas, `line-clamp-2`).
  - Enlace **"Gestionar Calendario"** (con flecha `arrow_forward`) → `/casas/{id}`.
  - **Botón de eliminar** (ícono `delete`, fondo error) — solo superadmin.
- **Estado vacío** (sin propiedades): ícono `maps_home_work`, título **"Ausencia de Activos Inmobiliarios"** y texto explicativo.

### 2.2 Condiciones por rol

- **Botón "Añadir Domicilio"** (que abre el formulario de alta) → solo si `isSuperAdmin`.
- **Botón de eliminar** en cada tarjeta → solo si `isSuperAdmin`.
- Usuarios estándar solo ven el listado y pueden entrar a cada calendario.

### 2.3 Flujo: Eliminar un domicilio (solo superadmin)

- Cada tarjeta (para superadmin) tiene un `<form>` inline con `"use server"` que importa dinámicamente `deleteProperty` desde `@/app/actions/property` y lo ejecuta.
- Campo oculto: `id` = id de la propiedad.
- Botón submit (ícono `delete`, title "Eliminar Domicilio"). Sin diálogo de confirmación; se envía directo.
- Server action: **`deleteProperty(formData)`**.

### 2.4 Flujo: Añadir un domicilio (solo superadmin) — NewPropertyForm

1. El admin pulsa **"Añadir Domicilio"** (botón azul, ícono `add_business`).
2. Se abre un **modal** (overlay con blur) titulado **"Nuevo Domicilio"**, subtítulo "Expanda su red de domicilios administrables", con botón de cerrar (ícono `close`).
3. Rellena los campos.
4. Pulsa **"Guardar Domicilio"**.

**Mecánica de envío:** El submit está interceptado (`onSubmit`, `e.preventDefault()`). Usa `useTransition` y llama a `createProperty({}, formData)`. Si la respuesta trae `res.error`, lo muestra; si no, cierra el modal (`setIsOpen(false)`).

### 2.5 Formulario: "Nuevo Domicilio" (NewPropertyForm)

Server action: **`createProperty(prevState, formData)`** (de `@/app/actions/property`).

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Nombre del Domicilio | `name` | `Input` (texto) | **Sí** (`required`) | Placeholder: "Ej. Residencia Costera Marina" |
| Notas (Opcional) | `description` | `Input` (texto) | No | Placeholder: "Ej. Disposición de 4 habitaciones..." |

**Validaciones de cliente:** `name` es `required` (HTML). Cualquier error del servidor se muestra en un bloque rojo con ícono `error` y el texto de `res.error`.

**Estados del botón submit:**
- Normal: **"Guardar Domicilio"** (ícono `domain_verification`).
- Pendiente (`isPending`): **"Guardando..."** con spinner (`progress_activity` animado), botón deshabilitado.

**Botón cerrar (X):** cierra el modal sin enviar.

---

## 3. Sección "Detalle de Casa" / Calendario de un domicilio

Archivos: `casas/[id]/page.tsx`, `casas/[id]/interactive-calendar.tsx`, `casas/[id]/audit-log-viewer.tsx`

### 3.1 Qué muestra

Ruta `/casas/{id}`. Carga:
- La **propiedad** (`prisma.property.findUnique`). Si no existe → `notFound()` (404).
- Las **reservas** de la propiedad (`prisma.reservation.findMany`), incluyendo `familyGroup` y `createdBy`.
- Los **logs de auditoría** (`prisma.auditLog.findMany`, las 50 más recientes, orden descendente), con el `user` (name, role).

Cálculo de roles en esta página:
- `isSuperAdmin = SUPER_ADMIN || MEGA_ADMIN`
- `isFamilyAdmin = FAMILY_ADMIN || isSuperAdmin`

Carga de **miembros de familia** (para el selector de invitados):
- Si el usuario tiene `familyGroupId` → carga los usuarios de ese grupo (`prisma.user.findMany({ where: { familyGroupId } })`).
- Si no tiene grupo pero es superadmin → carga **todos** los usuarios (`prisma.user.findMany()`).
- En otro caso → lista vacía.

Cabecera: botón "volver" (flecha izquierda → `/casas`), **nombre de la propiedad** y su **descripción** (o el texto por defecto "Calendario de ocupación y reservas familiares.").

Componentes principales:
1. **InteractiveCalendar** (calendario interactivo).
2. **AuditLogViewer** (historial de auditoría).

> Importante: la página pasa **`canReserve={true}`** de forma fija al calendario. Por tanto, en la práctica, cualquier usuario que llegue a esta página puede crear/cancelar reservas desde el calendario. La distinción de rol relevante aquí es `isSuperAdmin`, que habilita el bloqueo por mantenimiento.

### 3.2 Calendario interactivo (InteractiveCalendar)

Props recibidas: `propertyId`, `reservations`, `canReserve` (=true), `isSuperAdmin`, `myFamilyGroupId`, `familyMembers`.

**Qué muestra:**
- Título **"Calendario de Ocupación"**.
- Botón **"Crear Reserva"** (ícono `+`) — visible si `canReserve`.
- Un **FullCalendar** (`@fullcalendar/react`) con plugins `dayGrid` e `interaction`:
  - Vista inicial: mes (`dayGridMonth`).
  - Idioma español (`locale="es"`), botón "Hoy" y "Mes".
  - **Seleccionable** (`selectable`) si `canReserve && !isSidebarOpen`.
  - Toolbar: a la izquierda el título; a la derecha `today prev,next`.
  - Altura: `65vh`.
- **Eventos** = reservas mapeadas:
  - **Título del evento**: "Mantenimiento" si `isMaintenance`; si no, el nombre del grupo familiar (`familyGroup.name`), o "Reserva Privada" si no hay grupo.
  - **Color de fondo**: naranja `#FF9500` si mantenimiento; si no, el color del grupo familiar (`familyGroup.color`) o azul `#4D8AF0` por defecto.
- **Leyenda** (abajo): lista de grupos únicos presentes (nombre + color). Si no hay eventos: "No hay estadias marcadas".

**Interacciones que abren el panel lateral:**
- **Seleccionar un rango** de días en el calendario (`select`) → abre el panel en modo "Nueva Estancia" con ese rango. (Solo si `canReserve`.)
- **Clic en un evento existente** (`eventClick`) → abre el panel en modo "Detalle de Reserva". (Solo si `canReserve`.)
- **Botón "Crear Reserva"** (`openManualBooking`) → abre el panel en modo "Nueva Estancia" con rango por defecto **hoy → mañana**.

#### 3.2.1 Panel lateral — Modo "Detalle de Reserva" (ver evento existente)

Se muestra cuando se hace clic sobre un evento. Contenido (solo lectura):
- Círculo de color del grupo + **título** del evento.
- **"Creado por {createdBy.name}"**.
- **Entrada** (fecha de inicio, formato `es-ES`) y **Salida** (fecha de fin).
- **"Asistentes ({guestCount})"** con el texto `guestsList` (o "Sin especificar").
- **Botón "Cancelar y Eliminar"** (ícono `Trash2`) — visible si `canReserve`.
  - Al pulsarlo (`handleDelete`): llama a **`deleteReservation(selectedEventId)`** (de `@/app/actions/reservation`).
  - Estados: "Procesando..." con spinner mientras `saving`. Si `res.error`, muestra el error en el panel; si no, cierra el panel.

#### 3.2.2 Panel lateral — Modo "Nueva Estancia" (crear reserva) — FORMULARIO

Server action: **`createReservation(formData)`** (de `@/app/actions/reservation`).

Mecánica de envío (`handleSave`, con `e.preventDefault()`):
- Agrega al FormData: `propertyId`.
- Calcula `startDate`/`endDate` a partir de los inputs de fecha (o del rango seleccionado), y los agrega como ISO string (`startDate`, `endDate`).
- Construye `guestsList` combinando: (a) los nombres de los miembros seleccionados visualmente, y (b) el texto manual de "Otros Invitados", unidos con `" | "`.
- Llama a `createReservation(formData)`. Si `res.error`, lo muestra en el panel; si no, cierra el panel y limpia selección.

**Campos del formulario:**

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Desde (Llegada) | `startDateInput` | `input[type=date]` | **Sí** (`required`) | Valor por defecto: inicio del rango seleccionado (YYYY-MM-DD) |
| Hasta (Salida) | `endDateInput` | `input[type=date]` | **Sí** (`required`) | Valor por defecto: fin del rango seleccionado |
| Integrantes (selección rápida) | (no envía name propio) | Chips toggle de miembros | No | Cada miembro de `familyMembers` es un chip con avatar (imagen o iniciales) y primer nombre. Al pulsar, se alterna en `selectedGuests`. El contador muestra `selectedGuests.length`. Si no hay miembros: "No hay usuarios vinculados a este circuito para selección rápida." |
| Otros Invitados Adicionales | `guestsListManual` | `Input` (texto) | No | Placeholder: "Ej. Abuelo, Mascota..." |
| (oculto) Conteo de invitados | `guestCount` | `input[type=number]` (readOnly, contenedor `hidden`) | — | Valor = `selectedGuests.length` si >0, si no 1 |
| Bloqueo por Mantenimiento | `isMaintenance` | `input[type=checkbox]`, value `"true"` | No | **Solo visible si `isSuperAdmin`.** Etiqueta "Bloqueo por Mantenimiento"; descripción: "Esta fecha aparecerá cerrada al sistema familiar, reservado para directivos." |

**Datos derivados que se envían (no son inputs visibles con ese name):**
- `propertyId` (añadido en código).
- `startDate`, `endDate` (ISO, derivados de los inputs de fecha).
- `guestsList` (combinación de invitados visuales + manuales, unidos por `" | "`).

**Validaciones de cliente:** `startDateInput` y `endDateInput` son `required`. El resto es opcional. Los errores del servidor se muestran en un bloque rojo dentro del panel.

**Botón submit:**
- Normal: **"Confirmar Reserva"** (ícono `calendar_add_on`).
- Pendiente (`saving`): **"Registrando..."** con spinner. Deshabilitado mientras guarda.

**Cerrar panel:** botón X (arriba derecha) cierra el panel sin enviar.

#### 3.2.3 Condiciones por rol en el calendario

- **Crear / ver / cancelar reservas**: gobernado por `canReserve`, que la página fija en `true` → disponible para todos los que acceden.
- **Checkbox "Bloqueo por Mantenimiento"**: solo `isSuperAdmin` (`SUPER_ADMIN`/`MEGA_ADMIN`).
- **Selector de integrantes**: depende de `familyMembers`, que sale del grupo del usuario (o de todos los usuarios si es superadmin sin grupo).

### 3.3 Historial de Auditoría (AuditLogViewer)

Props: `logs`, `isSuperAdmin`.

**Qué muestra:**
- Botón inicial (colapsado): **"Consultar Historial de Auditoría"** (ícono `history`). Al pulsarlo, abre un panel.
- **Panel lateral derecho** (overlay) titulado **"Registro de Trazabilidad"** (ícono `policy`), con botón de cerrar.
- **Línea de tiempo** de logs. Cada entrada muestra:
  - Un **punto de color** según la acción: azul (primary) si `CREAR_RESERVA`, rojo (error) si `CANCELAR_RESERVA`, color secundario en otro caso.
  - **Etiqueta** de la acción (el valor `log.action` con guion bajo reemplazado por espacio).
  - **Fecha y hora** locales.
  - **Detalle** (`log.details`).
  - **Autor**: `log.user.name`, o (si no hay usuario) el texto en cursiva **"Autoridad Anónima"** (en color error).
- **Estado vacío**: "No hay registros de actividad recientes."

> Nota: el prop `isSuperAdmin` se pasa al componente, pero el render del historial no lo usa para ocultar contenido (cualquiera que vea la página puede abrir el historial). Las acciones reconocidas explícitamente con color propio son `CREAR_RESERVA` y `CANCELAR_RESERVA`.

---

## 4. Sección "Configuración" / Ajustes Integrales

Archivos: `configuracion/page.tsx`, `config-tabs.tsx`, `smtp-form.tsx`, `notification-form.tsx`, `templates-form.tsx`, `limits-form.tsx`. (También existe `config-form.tsx` y `preferences-form.tsx`, ver notas más abajo.)

### 4.1 Qué muestra y carga

Ruta `/configuracion`. Título **"Ajustes Integrales"**, subtítulo "Control total sobre la arquitectura del portal de domicilios."

Cálculo de roles:
- `isMegaAdmin = (role === 'MEGA_ADMIN')`
- `isSuperAdmin = (role === 'SUPER_ADMIN' || isMegaAdmin)`

Carga condicional de datos:
- `config = isMegaAdmin ? getSystemConfig() : null` — configuración del sistema (solo mega admin).
- `notifSettings = isSuperAdmin ? getMyNotificationSettings() : []` — ajustes de notificación del usuario.
- `templates = isMegaAdmin ? prisma.notificationTemplate.findMany() : []` — plantillas de correo.

La página renderiza `ConfigTabsWrapper` pasándole como props las pestañas ya construidas:
- `SmtpTab` = `<SmtpForm initialConfig={config} />` (solo si hay `config`).
- `NotifTab` = `<NotificationForm settings={notifSettings} />`.
- `TemplatesTab` = `<TemplatesForm templates={templates} />`.
- `LimitsTab` = `<LimitsForm initialConfig={config} />` (solo si hay `config`).

### 4.2 Pestañas (ConfigTabsWrapper) y visibilidad por rol

Estado inicial de pestaña activa: `'smtp'` si `isMegaAdmin`, si no `'notif'`.

| Pestaña (botón) | Etiqueta visible | Ícono | Color activo | Visible para | Clave interna |
|---|---|---|---|---|---|
| Plataforma (SMTP) | "Plataforma (SMTP)" | `Shield` | error (rojo) | **Solo `isMegaAdmin`** | `smtp` |
| Notificaciones PUSH | "Notificaciones PUSH" | `Bell` | tertiary | `isSuperAdmin` (incluye mega) | `notif` |
| Plantillas de Correo | "Plantillas de Correo" | `Palette` | primary | **Solo `isMegaAdmin`** | `templates` |
| Límites | "Límites" | `Shield` | secondary | **Solo `isMegaAdmin`** | `limits` |

Render del contenido por pestaña:
- `templates` (solo mega): tarjeta contenedora con `TemplatesForm`.
- `smtp` (solo mega): `SmtpForm`.
- `limits` (solo mega): `LimitsForm`.
- `notif` (superadmin): tarjeta con título **"Centro de Alertas"** y `NotificationForm`.

**Resumen de acceso a Configuración:**
- **Usuario estándar / FAMILY_ADMIN**: aunque la ruta exista en el menú, no recibe `config` ni `notifSettings` (no es superadmin), por lo que **no ve ninguna pestaña** (todas son super/mega). En la práctica la pantalla queda sin pestañas para ellos.
- **SUPER_ADMIN (no mega)**: ve solo la pestaña **Notificaciones PUSH**.
- **MEGA_ADMIN**: ve las 4 pestañas (SMTP, Notificaciones PUSH, Plantillas, Límites).

---

### 4.3 Pestaña "Plataforma (SMTP)" — SmtpForm (solo MEGA_ADMIN)

Dos bloques: la **Pasarela SMTP** (formulario) y la **Zona de Destrucción**.

Server actions usadas: **`updateSystemConfig(null, formData)`**, **`testSmtpConnection()`**, **`wipeStorage()`** (todas de `@/app/actions/config`).

#### 4.3.1 Formulario "Pasarela SMTP"

Mecánica: `onSubmit` con `e.preventDefault()`, usa `useTransition`. Llama `updateSystemConfig(null, formData)`. Si `res.error`, muestra mensaje de error; si no, "Configuración guardada."

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| URL Externa (Obligatoria para Links) | `baseUrl` | `Input` (texto) | **Sí** (`required`) | Placeholder: "Ej. https://tu-dominio.com" |
| Host SMTP | `smtpHost` | `Input` (texto) | **Sí** (`required`) | Placeholder: "smtp.mailgun.org" |
| Puerto | `smtpPort` | `Input[type=number]` | **Sí** (`required`) | Default mostrado: `587` |
| Usuario SMTP | `smtpUser` | `Input` (texto) | **Sí** (`required`) | — |
| Contraseña SMTP | `smtpPass` | `Input[type=password]` | **Sí** (`required`) | — |
| Conexión segura (SSL/TLS - Puerto 465) | `smtpSecure` | `input[type=checkbox]` | No | `defaultChecked` según `initialConfig.smtpSecure`. Etiqueta: "Usar conexión segura (SSL/TLS - Puerto 465)" |

**Validaciones de cliente:** `baseUrl`, `smtpHost`, `smtpPort`, `smtpUser`, `smtpPass` son `required`. El mensaje de resultado (éxito/error) se muestra en un bloque coloreado.

**Botones:**
- **"Guardar"** (ícono `Save`, submit) → `updateSystemConfig`. Estado pendiente: "Guardando...". Deshabilitado si hay guardado o test en curso.
- **"Probar Conexión"** (ícono `ShieldCheck`, `type=button`) → `testSmtpConnection()` (sin argumento de email en esta variante). Estado: spinner `RefreshCw` mientras prueba. Muestra `res.message`/`res.error`.

#### 4.3.2 Bloque "Zona de Destrucción" (dentro de SmtpForm)

- Título **"Zona de Destrucción"** (ícono `warning`, rojo).
- Subtítulo **"Purgar Formularios y Multimedia"** con la advertencia: *"Esta acción borrará físicamente TODAS LAS FOTOS subidas a tu disco y ELIMINARÁ para siempre las encuestas de Salida en la base de datos."*
- **Botón "Purgar Servidor"** (ícono `ShieldCheck`, `type=button`) → `handleWipe` → **`wipeStorage()`**.
  - Estado pendiente: "Destruyendo..." con spinner. **No hay diálogo de confirmación**; se ejecuta directo.
  - Resultado (`wipeResult`) se muestra en un bloque coloreado (éxito/error) con `message`/`error`.

---

### 4.4 Pestaña "Notificaciones PUSH" — NotificationForm (SUPER_ADMIN y MEGA_ADMIN)

Renderizada dentro de la tarjeta **"Centro de Alertas"**.

Server action: **`saveNotificationSetting(prevState, formData)`** (de `@/app/actions/notifications`), vía `useActionState`.

Datos: busca en `settings` el ajuste con `type === 'PRE_STAY'` (`preStaySetting`).

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| (oculto) Tipo | `type` | `input[type=hidden]` | Sí | Valor fijo `"PRE_STAY"` |
| Habilitar Despacho de "Alerta Previa (1 Día)" | `isActive` | `input[type=checkbox]` | No | `defaultChecked = preStaySetting.isActive ?? true` (activado por defecto) |
| Incrustación de Reglas de Casa (Cuerpo de Correo) | `customText` | `textarea` (mín. 140px alto) | No | Default = `preStaySetting.customText`. Placeholder: "Ej: Las llaves maestras están bajo la maceta azul. El código del portón es 3345." |

**Texto de ayuda:** "Este fragmento se adjuntará automáticamente en el correo enviado a las familias 24 horas antes de su llegada."

**Botón submit:** **"Consolidar Autómata"** (ícono `verified`). Estado pendiente: "Procesando Parámetros..." con spinner. Deshabilitado mientras `isPending`.

**Validaciones de cliente:** ninguna obligatoria (no hay `required`). El `type` va siempre como hidden con valor `PRE_STAY`.

**Propósito funcional:** configura la notificación **pre-estancia** (alerta 1 día antes / 24 horas antes de la llegada), pudiendo activarla/desactivarla y adjuntar un texto con "reglas de casa".

---

### 4.5 Pestaña "Plantillas de Correo" — TemplatesForm (solo MEGA_ADMIN)

Server action: **`updateTemplate(formData)`** (de `@/app/actions/config`).

**Qué muestra:** título **"Editores de Plantillas Abiertas"** y dos editores de plantilla. Botón global **"Guardar Plantillas"** (ícono `save`).

Mecánica: `handleAction(formData)` → `setLoading(true)` → `await updateTemplate(formData)` → muestra mensaje de éxito durante 3 segundos ("Las Plantillas de Correo se han sincronizado con la Base de Datos.").

La función `getTemplate(type)` busca la plantilla por tipo; si no existe en BD, usa **valores por defecto** (ver abajo).

#### 4.5.1 Plantilla "Post-Estancia (Formulario)" — `type: POST_STAY`

Descripción: "Enviada a todos los miembros de la familia 1 día después del CheckOut instándoles a rellenar el estado de la casa."

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Asunto del Correo | `POST_STAY_subject` | `input[type=text]` | No | Default si no hay BD: `🏡 Queremos evaluar tu estancia en {{PropertyName}}` |
| Cuerpo Analítico (HTML Permitido) | `POST_STAY_body` | `textarea` (6 filas, fuente mono) | No | HTML por defecto (ver abajo). Variables indicadas en la UI: `{{PropertyName}} {userName} {{FormLink}}` |

**Placeholders/variables soportadas (Post-Estancia):** `{{PropertyName}}`, `{{UserName}}`, `{{FormLink}}`.
> Nota fiel al código: la etiqueta de variables en la UI muestra literalmente `{userName}` (una sola llave), pero el cuerpo HTML por defecto usa `{{UserName}}`. El placeholder real en el contenido por defecto es `{{UserName}}`.

**Cuerpo HTML por defecto (POST_STAY):**
```html
<div style="font-family: Arial; padding: 20px;"><h2>¡Esperamos que lo hayas pasado en grande!</h2><p>Hola {{UserName}},</p><p>Tu estancia en <strong>{{PropertyName}}</strong> ha finalizado formalmente. Para mantener nuestras instalaciones en perfecto estado, necesitamos que nos envíes tu evaluación de salida rellenando <a href="{{FormLink}}" ...>este formulario seguro</a>.</p><p>Podrás subir fotografías que certifiquen el estado en que dejaste la vivienda.</p></div>
```

#### 4.5.2 Plantilla "Recordatorio Mensual" — `type: MONTHLY_REMINDER`

Descripción: "Enviada el Día 1 de cada mes a los que dispongan de fechas de estancia activas en el mes actual."

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Asunto del Correo | `MONTHLY_REMINDER_subject` | `input[type=text]` | No | Default si no hay BD: `📅 Tienes reservas activas para este mes` |
| Cuerpo Analítico (HTML Permitido) | `MONTHLY_REMINDER_body` | `textarea` (6 filas, fuente mono) | No | HTML por defecto (ver abajo). Variables indicadas en la UI: `{{PropertyName}} {userName} {{StartDate}}` |

**Placeholders/variables soportadas (Recordatorio Mensual):** `{{PropertyName}}`, `{{UserName}}`, `{{StartDate}}`.

**Cuerpo HTML por defecto (MONTHLY_REMINDER):**
```html
<div style="font-family: Arial; padding: 20px;"><h2>¡Este mes viajas a {{PropertyName}}!</h2><p>Hola {{UserName}},</p><p>Te recordamos que tienes una reserva de calendario programada para el día <strong>{{StartDate}}</strong>.</p><p>Asegúrate de llevar todo lo necesario para tu viaje con la familia.</p></div>
```

**Botón submit (global de plantillas):** **"Guardar Plantillas"** (ícono `save`). Estado pendiente: "Sincronizando...". Deshabilitado mientras carga. Ambas plantillas se guardan en el mismo envío (un solo `updateTemplate`).

**Validaciones de cliente:** ninguna obligatoria. Se admite HTML en los cuerpos.

> Detalle fiel: el ícono del bloque Post-Estancia usa el nombre `event_Available` (con A mayúscula) — probable typo del original; igualmente se documenta tal cual.

---

### 4.6 Pestaña "Límites" — LimitsForm (solo MEGA_ADMIN)

Server action: **`updateSystemConfig(prevState, formData)`** (vía `useActionState`).

**Qué muestra:** título **"Límites de Plataforma"**, subtítulo "Restricciones dinámicas para las operaciones de calendarios y fechas."

Bloque **"Intervalo Máximo de Estadía"**: "Obliga a que ninguna familia pueda apropiarse del domicilio por más de X días ininterrumpidos en una misma reserva."

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Días Permitidos | `maxReservationDays` | `input[type=number]` | No (sin `required`) | `defaultValue = initialConfig.maxReservationDays || 15`; **mínimo `1`** (`min={1}`) |

**Campos ocultos obligatorios para la action** (porque `updateSystemConfig` requiere todos los parámetros del sistema; se reenvían sin cambios):
- `baseUrl` (hidden) = `initialConfig.baseUrl`
- `smtpHost` (hidden) = `initialConfig.smtpHost`
- `smtpPort` (hidden) = `initialConfig.smtpPort`
- `smtpUser` (hidden) = `initialConfig.smtpUser`
- `smtpPass` (hidden) = `initialConfig.smtpPass`
- `smtpSecure` (hidden, value `"on"`) — solo si `initialConfig.smtpSecure` es verdadero.

**Mensajes de resultado:**
- Error: bloque rojo con `state.error`.
- Éxito: bloque verde "Límites actualizados rigurosamente." (ícono `check_circle`).

**Botón submit:** **"Guardar Restricciones"**. Estado pendiente: spinner. Deshabilitado mientras `isPending`.

**Validaciones de cliente:** `maxReservationDays` tiene `min=1` (entero positivo). No es `required`.

---

## 5. Componentes auxiliares de Configuración presentes pero no montados por la página

Estos dos archivos están en la carpeta pero **no son referenciados por `configuracion/page.tsx`** (la página usa `SmtpForm`, no `ConfigForm`; y `PreferencesForm` no se importa en ninguno de los archivos leídos). Se documentan por completitud porque forman parte de la UI legacy a borrar.

### 5.1 ConfigForm (`config-form.tsx`) — variante alternativa del formulario de sistema

Server actions: **`updateSystemConfig`** (vía `useActionState`), **`testSmtpConnection(testEmail)`**, **`wipeStorage()`**.

Estructura en tres bloques:

**Bloque "Directorio Principal":**
| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| URL Base de Emisión | `baseUrl` | `Input` (texto) | No (sin `required`) | Default `initialData.baseUrl`. Placeholder "https://familia.midominio.com". Ayuda: "Requerido para generar anclas (links) precisas en las invitaciones por email." |

**Bloque "Protocolo de Despacho (SMTP)":**
| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Host de Conexión | `smtpHost` | `Input` (texto) | No | Placeholder "smtp.gmail.com" |
| Puerto de Salida | `smtpPort` | `Input[type=number]` | No | Placeholder "587" |
| Buzón Remitente Oficial | `smtpUser` | `Input` (texto) | No | Placeholder "notificaciones@dominio.com" |
| Contraseña de Aplicación Segura | `smtpPass` | `Input[type=password]` | No | Placeholder "••••••••••••" |
| Forzar encriptación estricta (SSL/TLS para puerto 465) | `smtpSecure` | `input[type=checkbox]` | No | `defaultChecked = initialData.smtpSecure` |

**Acciones (bloque inferior):**
- **"Establecer Parámetros"** (submit, ícono `save`) → `updateSystemConfig`.
- **"Diagnóstico de Red SMTP"** (`type=button`, ícono `electrical_services`) → `testSmtpConnection(testEmail)`. Estado: "Comprobando..." con spinner.
- **Campo de email de prueba**: `Input[type=email]`, estado controlado `testEmail`, **valor inicial `contacto@belucm.me`**, placeholder "Correo de destino (test)...". (No tiene `name`; se pasa como argumento directo a la action.)
- Resultado del test se muestra en bloque coloreado con `message`/`error`.

**Bloque "Zona de Destrucción":** idéntico al de SmtpForm — botón **"Purgar Servidor"** → `wipeStorage()`, con la misma advertencia sobre borrado de fotos y encuestas de salida. Sin confirmación.

### 5.2 PreferencesForm (`preferences-form.tsx`) — escala tipográfica

Server action: **`updateFontSize(prevState, formData)`** (de `@/app/actions/user`), vía `useActionState`.

**Qué hace:** permite al usuario elegir el tamaño de fuente global mediante un **deslizador (range)** con vista previa en tiempo real (modifica `document.documentElement.style.fontSize` al instante).

| Campo | name | Tipo | Obligatorio | Valores / Notas |
|---|---|---|---|---|
| Deslizador de escala | `fontSizeSlider` (solo UI, no se envía) | `input[type=range]` | — | `min=0`, `max=4`, `step=1`. Controla el índice. |
| (oculto) Tamaño de fuente | `fontSize` | `input[type=hidden]` | Sí (se envía) | Valor = una de las clases: `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl` |

**Escala (índice → etiqueta → px aplicados en vivo):**
| Índice | Etiqueta | Clase (`fontSize`) | px en vivo |
|---|---|---|---|
| 0 | Ultra Compacta | `text-sm` | 14px |
| 1 (inicial) | Compacta | `text-base` | 16px |
| 2 | Móvil / Estándar | `text-lg` | 18px |
| 3 | Expandida | `text-xl` | 20px |
| 4 | Gigante | `text-2xl` | 24px |

**Mensaje de éxito:** "¡Escala de sistema guardada para tus futuras sesiones!" (ícono `check_circle`).

**Botón submit:** **"Consolidar Preferencia Visual"** (ícono `format_size`). Estado pendiente: "Sincronizando Sistema..." con spinner. Deshabilitado mientras `isPending`.

**Validaciones de cliente:** ninguna obligatoria; el valor enviado siempre es una de las 5 clases.

---

## 6. Sección "Anuncios" (resumen consolidado)

> Los anuncios viven dentro de la pantalla de **Inicio** (`/`), no en una ruta propia. Se consolida aquí su comportamiento completo para referencia.

- **Visualización (todos los usuarios):** tablón "Tablón de Anuncios Global" con tarjetas. Cada tarjeta: título, chip (propiedades asociadas o "Anuncio General"), contenido con saltos de línea, y pie "Publicado por {autor} el {fecha} a las {hora}". Estado vacío con ícono `campaign`.
- **Crear (solo `SUPER_ADMIN`/`MEGA_ADMIN`):** botón "Publicar Noticia" → modal "Nuevo Comunicado" → action **`createAnnouncement`**. Campos: `title` (req.), `propertyIds` (multi, opcional), `content` (req.). Sin propiedades = anuncio global.
- **Eliminar (solo `SUPER_ADMIN`/`MEGA_ADMIN`):** botón `delete_forever` en cada tarjeta → action **`deleteAnnouncement`** con `id`. Sin confirmación.

---

## 7. Tabla maestra de Server Actions por botón

| Sección | Botón / Disparador | Server action | Módulo |
|---|---|---|---|
| Layout | Cerrar Sesión | `logout()` | `@/app/actions/auth` |
| Inicio | Publicar Ahora (Nuevo Comunicado) | `createAnnouncement(fd)` | `@/app/actions/announcement` |
| Inicio | Eliminar anuncio (`delete_forever`) | `deleteAnnouncement(fd)` | `@/app/actions/announcement` |
| Casas | Guardar Domicilio | `createProperty({}, fd)` | `@/app/actions/property` |
| Casas | Eliminar domicilio (`delete`) | `deleteProperty(fd)` | `@/app/actions/property` |
| Detalle casa | Confirmar Reserva | `createReservation(fd)` | `@/app/actions/reservation` |
| Detalle casa | Cancelar y Eliminar (reserva) | `deleteReservation(id)` | `@/app/actions/reservation` |
| Config · SMTP | Guardar | `updateSystemConfig(null, fd)` | `@/app/actions/config` |
| Config · SMTP | Probar Conexión | `testSmtpConnection()` / `testSmtpConnection(testEmail)` (en ConfigForm) | `@/app/actions/config` |
| Config · SMTP / Zona Destrucción | Purgar Servidor | `wipeStorage()` | `@/app/actions/config` |
| Config · Notificaciones | Consolidar Autómata | `saveNotificationSetting(prev, fd)` | `@/app/actions/notifications` |
| Config · Plantillas | Guardar Plantillas | `updateTemplate(fd)` | `@/app/actions/config` |
| Config · Límites | Guardar Restricciones | `updateSystemConfig(prev, fd)` | `@/app/actions/config` |
| Preferencias (no montado) | Consolidar Preferencia Visual | `updateFontSize(prev, fd)` | `@/app/actions/user` |

---

## 8. Resumen de visibilidad por rol (matriz)

| Funcionalidad | Estándar | FAMILY_ADMIN | SUPER_ADMIN | MEGA_ADMIN |
|---|---|---|---|---|
| Ver Inicio / anuncios | Sí | Sí | Sí | Sí |
| Publicar / eliminar anuncios | No | No | Sí | Sí |
| Ver listado de Domicilios | Sí | Sí | Sí | Sí |
| Añadir / eliminar Domicilio | No | No | Sí | Sí |
| Ver calendario de un domicilio | Sí | Sí | Sí | Sí |
| Crear / cancelar reservas (panel) | Sí¹ | Sí¹ | Sí | Sí |
| Marcar "Bloqueo por Mantenimiento" | No | No | Sí | Sí |
| Ver Historial de Auditoría | Sí | Sí | Sí | Sí |
| Menú lateral "Sorteos" | No | No | Sí | Sí |
| Config · pestaña Notificaciones PUSH | No | No | Sí | Sí |
| Config · pestaña SMTP | No | No | No | Sí |
| Config · pestaña Plantillas de Correo | No | No | No | Sí |
| Config · pestaña Límites | No | No | No | Sí |
| Purgar Servidor (wipeStorage) | No | No | No² | Sí |

¹ Habilitado porque la página de detalle pasa `canReserve={true}` a todos. La restricción real por rol del lado servidor (si existe) reside en las server actions.
² La pestaña SMTP (que contiene el botón Purgar) solo la ve MEGA_ADMIN; por tanto el botón Purgar en la UI montada es exclusivo de MEGA_ADMIN.

---

### Notas finales de fidelidad

- Las server actions referenciadas (`@/app/actions/*`) se documentan en `01-backend-funciones-datos.md`. Toda validación descrita aquí es de **cliente** (atributos HTML `required`/`min`, y manejo de `res.error`).
- Inconsistencias del original conservadas tal cual: la etiqueta de variables de plantillas muestra `{userName}` (una llave) mientras el cuerpo usa `{{UserName}}`; el ícono `event_Available` con mayúscula; la barra inferior móvil no filtra por rol; y los archivos `config-form.tsx` y `preferences-form.tsx` existen pero no están montados por `configuracion/page.tsx`.
- Email por defecto precargado en campos de prueba/estado: `contacto@belucm.me` (en `config-form.tsx`).
