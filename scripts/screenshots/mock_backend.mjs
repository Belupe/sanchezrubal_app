// Backend simulado para generar las capturas de la App Store.
//
// La app que se fotografía es la REAL: sus pantallas, sus widgets y sus
// consultas sin tocar. Lo único que se sustituye es el servidor al que
// pregunta, para no sacar datos de la familia en una captura pública y para que
// las capturas salgan siempre igual (mismos datos, mismas fechas relativas).
//
// Habla lo justo de tres protocolos:
//   · GoTrue      /auth/v1/…        inicio de sesión
//   · PostgREST   /rest/v1/<tabla>  consultas de DataService
//   · Functions   /functions/v1/…   media-sign
//
// Además sirve `build/web` en el MISMO origen, así el navegador no ve ninguna
// petición entre orígenes y no hace falta CORS.
//
// Uso:  node mock_backend.mjs <raiz-web> [puerto]
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, normalize } from 'node:path';
import { deflateSync } from 'node:zlib';

const WEB_ROOT = process.argv[2] ?? 'build/web';
const PORT = Number(process.argv[3] ?? 8787);

// ---------------------------------------------------------------------------
//  Fechas: todo se genera relativo a HOY para que las capturas no envejezcan.
// ---------------------------------------------------------------------------
const HOY = new Date();
HOY.setHours(12, 0, 0, 0);

const dia = (n) => {
  const d = new Date(HOY);
  d.setDate(d.getDate() + n);
  return d;
};
const iso = (d) => d.toISOString();
const fecha = (n) => iso(dia(n)).slice(0, 10);

/// Cuánto se aparta Madrid de UTC ese día: +1 en invierno, +2 en verano.
const desfaseMadrid = (d) =>
  (new Date(d.toLocaleString('en-US', { timeZone: 'Europe/Madrid' }))
    - new Date(d.toLocaleString('en-US', { timeZone: 'UTC' })))
  / 3_600_000;

/// Un instante dado por su hora DE MADRID, que es la que enseñará la captura.
/// Sin esto la hora saldría corrida según dónde se ejecute el guion, y en los
/// registros aparecían reservas creadas a las cinco de la mañana.
const momento = (diasAtras, hora, minuto = 0) => {
  const d = dia(-diasAtras);
  const aprox = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), hora, minuto));
  return iso(new Date(aprox.getTime() - desfaseMadrid(aprox) * 3_600_000));
};

// ---------------------------------------------------------------------------
//  Datos de demostración
// ---------------------------------------------------------------------------
const UID = '11111111-1111-4111-8111-111111111111';
const EMAIL = 'demo@sanchezrubal.net';
const PASSWORD = 'demo-capturas';

const GRUPOS = [
  { id: 'g1', name: 'Familia Sánchez', color: '#2563eb' },
  { id: 'g2', name: 'Familia Rubal', color: '#16a34a' },
  { id: 'g3', name: 'Familia Bas', color: '#f59e0b' },
  { id: 'g4', name: 'Familia Moreno', color: '#db2777' },
  { id: 'g5', name: 'Familia Ortega', color: '#7c3aed' },
  { id: 'g6', name: 'Familia Delgado', color: '#0891b2' },
];

const PERSONAS = [
  { id: UID, name: 'Ignacio Sánchez', email: EMAIL, role: 'MEGA_ADMIN', g: 'g1', gr: 'FAMILY_ADMIN' },
  { id: 'u2', name: 'Marta Rubal', email: 'marta@sanchezrubal.net', role: 'PRINCIPAL_ADMIN', g: 'g2', gr: 'FAMILY_ADMIN' },
  { id: 'u3', name: 'Javier Sánchez', email: 'javier@sanchezrubal.net', role: 'USER', g: 'g1', gr: 'MEMBER' },
  { id: 'u4', name: 'Lucía Sánchez', email: 'lucia@sanchezrubal.net', role: 'USER', g: 'g1', gr: 'FAMILY_SECOND_ADMIN' },
  { id: 'u5', name: 'Carmen Bas', email: 'carmen@sanchezrubal.net', role: 'USER', g: 'g3', gr: 'FAMILY_ADMIN' },
  { id: 'u6', name: 'Pablo Moreno', email: 'pablo@sanchezrubal.net', role: 'USER', g: 'g4', gr: 'FAMILY_ADMIN' },
  { id: 'u7', name: 'Elena Rubal', email: 'elena@sanchezrubal.net', role: 'USER', g: 'g2', gr: 'MEMBER' },
  { id: 'u8', name: 'Andrés Bas', email: 'andres@sanchezrubal.net', role: 'USER', g: 'g3', gr: 'MEMBER' },
  { id: 'u9', name: 'Rocío Moreno', email: 'rocio@sanchezrubal.net', role: 'USER', g: 'g4', gr: 'FAMILY_SECOND_ADMIN' },
  { id: 'u10', name: 'Teresa Ortega', email: 'teresa@sanchezrubal.net', role: 'USER', g: 'g5', gr: 'FAMILY_ADMIN' },
  { id: 'u11', name: 'Miguel Ortega', email: 'miguel@sanchezrubal.net', role: 'USER', g: 'g5', gr: 'MEMBER' },
  { id: 'u12', name: 'Rosa Delgado', email: 'rosa@sanchezrubal.net', role: 'USER', g: 'g6', gr: 'FAMILY_ADMIN' },
  { id: 'u13', name: 'Álvaro Delgado', email: 'alvaro@sanchezrubal.net', role: 'USER', g: 'g6', gr: 'MEMBER' },
  { id: 'u14', name: 'Nuria Rubal', email: 'nuria@sanchezrubal.net', role: 'USER', g: 'g2', gr: 'FAMILY_SECOND_ADMIN' },
];

const grupo = (id) => GRUPOS.find((g) => g.id === id);

const PROPIEDADES = [
  {
    id: 'p1',
    name: 'Casa de Zahara',
    description: 'Playa de los Alemanes. 8 plazas, 4 dormitorios y porche con barbacoa.',
    image: null,
  },
  {
    id: 'p2',
    name: 'Cortijo de Ronda',
    description: 'En la sierra, a 12 km del pueblo. 10 plazas, piscina y chimenea.',
    image: null,
  },
  {
    id: 'p3',
    name: 'Sierra Nevada',
    description: 'Pradollano, a pie de pista. 6 plazas y garaje cubierto.',
    image: null,
  },
  {
    id: 'p4',
    name: 'Casa de Sanlúcar',
    description: 'Barrio Alto, junto a la plaza. 6 plazas y patio andaluz.',
    image: null,
  },
  {
    id: 'p5',
    name: 'Piso del Puerto',
    description: 'El Puerto de Santa María, a 5 min de la playa. 4 plazas.',
    image: null,
  },
  {
    id: 'p6',
    name: 'Casa de Conil',
    description: 'Playa de la Fontanilla, a 10 min andando. 6 plazas.',
    image: null,
  },
];

const propiedad = (id) => PROPIEDADES.find((p) => p.id === id);

/// `properties(name)` y `family_groups(name, color)` tal y como los devuelve
/// PostgREST cuando la consulta pide esos recursos anidados.
const reserva = ({ id, p, g, by, desde, hasta, personas, notas, mant = false }) => ({
  id,
  property_id: p,
  family_group_id: g,
  created_by_id: by,
  start_date: fecha(desde),
  end_date: fecha(hasta),
  guest_count: personas,
  notes: notas ?? null,
  is_maintenance: mant,
  properties: { name: propiedad(p).name },
  family_groups: g ? { name: grupo(g).name, color: grupo(g).color } : null,
});

const RESERVAS = [
  reserva({ id: 'r1', p: 'p1', g: 'g1', by: UID, desde: -3, hasta: 6, personas: 6, notas: 'Llegamos el viernes por la tarde.' }),
  reserva({ id: 'r2', p: 'p1', g: 'g2', by: 'u2', desde: 8, hasta: 15, personas: 4 }),
  reserva({ id: 'r3', p: 'p1', g: 'g3', by: 'u5', desde: 17, hasta: 24, personas: 7 }),
  reserva({ id: 'r4', p: 'p2', g: 'g4', by: 'u6', desde: 1, hasta: 9, personas: 8, notas: 'Cumpleaños de Pablo el día 3.' }),
  reserva({ id: 'r5', p: 'p2', g: 'g1', by: 'u4', desde: 12, hasta: 19, personas: 5 }),
  reserva({ id: 'r6', p: 'p3', g: 'g2', by: 'u7', desde: 4, hasta: 8, personas: 3 }),
  reserva({ id: 'r7', p: 'p4', g: 'g3', by: 'u8', desde: -1, hasta: 4, personas: 6 }),
  reserva({ id: 'r8', p: 'p4', g: 'g4', by: 'u6', desde: 21, hasta: 28, personas: 5 }),
  reserva({ id: 'r9', p: 'p1', g: null, by: UID, desde: 27, hasta: 30, personas: 2, notas: 'Revisión de la caldera y pintura del porche.', mant: true }),
  reserva({ id: 'r10', p: 'p5', g: 'g5', by: 'u10', desde: 2, hasta: 7, personas: 4 }),
  reserva({ id: 'r11', p: 'p5', g: 'g6', by: 'u12', desde: 11, hasta: 18, personas: 4, notas: 'Venimos con el perro.' }),
  reserva({ id: 'r12', p: 'p3', g: 'g6', by: 'u13', desde: 15, hasta: 20, personas: 5 }),
  reserva({ id: 'r13', p: 'p2', g: 'g5', by: 'u11', desde: 22, hasta: 29, personas: 6 }),
  reserva({ id: 'r14', p: 'p6', g: 'g3', by: 'u5', desde: 5, hasta: 12, personas: 6 }),
  reserva({ id: 'r15', p: 'p6', g: 'g1', by: 'u3', desde: 19, hasta: 26, personas: 4 }),
];

const COLA = [
  {
    id: 'w1',
    property_id: 'p1',
    requested_by_id: 'u6',
    family_group_id: 'g4',
    start_date: fecha(8),
    end_date: fecha(15),
    guest_count: 5,
    notes: null,
    status: 'waiting',
    created_at: iso(dia(-6)),
    profiles: { name: 'Pablo Moreno' },
    properties: { name: 'Casa de Zahara' },
  },
  {
    id: 'w2',
    property_id: 'p1',
    requested_by_id: 'u5',
    family_group_id: 'g3',
    start_date: fecha(8),
    end_date: fecha(15),
    guest_count: 7,
    notes: null,
    status: 'waiting',
    created_at: iso(dia(-4)),
    profiles: { name: 'Carmen Bas' },
    properties: { name: 'Casa de Zahara' },
  },
  {
    id: 'w3',
    property_id: 'p2',
    requested_by_id: UID,
    family_group_id: 'g1',
    start_date: fecha(1),
    end_date: fecha(9),
    guest_count: 4,
    notes: null,
    status: 'waiting',
    created_at: iso(dia(-2)),
    profiles: { name: 'Ignacio Sánchez' },
    properties: { name: 'Cortijo de Ronda' },
  },
];

const ANUNCIOS = [
  {
    id: 'a1',
    title: 'La piscina del Cortijo estará cerrada del 12 al 14',
    content:
      'Vienen a cambiar la depuradora. Son tres días y no afecta al resto de la '
      + 'casa: quien tenga la reserva de esa semana puede seguir usándolo todo '
      + 'menos la piscina. Volverá a estar lista el jueves por la mañana.',
    created_at: iso(dia(-1)),
    profiles: { name: 'Ignacio Sánchez' },
    announcement_properties: [{ properties: { name: 'Cortijo de Ronda' } }],
  },
  {
    id: 'a2',
    title: 'Ya está el sorteo de las quincenas de verano',
    content:
      'Lo hemos hecho esta mañana con las seis familias. Podéis ver el '
      + 'resultado en la pestaña de Sorteos. Si a alguien no le viene bien su '
      + 'quincena, se puede cambiar hablándolo entre vosotros.',
    created_at: iso(dia(-4)),
    profiles: { name: 'Marta Rubal' },
    announcement_properties: [
      { properties: { name: 'Casa de Zahara' } },
      { properties: { name: 'Cortijo de Ronda' } },
    ],
  },
  {
    id: 'a3',
    title: 'Recordatorio: la inspección de salida son 5 minutos',
    content:
      'Antes de iros, abrid la app y haced las fotos de las habitaciones y del '
      + 'salón. Así quien entra después sabe cómo se dejó la casa y no hay '
      + 'discusiones por cosas que ya venían rotas.',
    created_at: iso(dia(-9)),
    profiles: { name: 'Ignacio Sánchez' },
    announcement_properties: [],
  },
  {
    id: 'a4',
    title: 'Nuevas llaves del Piso del Puerto',
    content:
      'Hemos cambiado la cerradura. Las llaves nuevas están en el cajetín de '
      + 'siempre; el código os lo he mandado por correo. Las viejas ya no abren.',
    created_at: iso(dia(-16)),
    profiles: { name: 'Teresa Ortega' },
    announcement_properties: [{ properties: { name: 'Piso del Puerto' } }],
  },
];

const SORTEOS = [
  {
    id: 's1',
    name: 'Quincenas de verano 2026',
    created_at: iso(dia(-4)),
    profiles: { name: 'Marta Rubal' },
    sorteo_resultados: [
      { premio: '1.ª de julio', family_groups: { name: 'Familia Bas' } },
      { premio: '2.ª de julio', family_groups: { name: 'Familia Sánchez' } },
      { premio: '1.ª de agosto', family_groups: { name: 'Familia Moreno' } },
      { premio: '2.ª de agosto', family_groups: { name: 'Familia Rubal' } },
      { premio: '1.ª de septiembre', family_groups: { name: 'Familia Ortega' } },
      { premio: '2.ª de septiembre', family_groups: { name: 'Familia Delgado' } },
    ],
  },
  {
    id: 's2',
    name: 'Puentes y Semana Santa 2026',
    created_at: iso(dia(-96)),
    profiles: { name: 'Ignacio Sánchez' },
    sorteo_resultados: [
      { premio: 'Semana Santa', family_groups: { name: 'Familia Rubal' } },
      { premio: 'Puente de mayo', family_groups: { name: 'Familia Sánchez' } },
      { premio: 'Puente de diciembre', family_groups: { name: 'Familia Bas' } },
      { premio: 'Fin de año', family_groups: { name: 'Familia Ortega' } },
    ],
  },
];

const INSPECCIONES = [
  {
    id: 'o1',
    reservation_id: 'r7',
    general_status: 'Todo correcto',
    notes: 'Casa recogida y nevera vacía. Dejamos el toldo bajado por el levante.',
    media_urls: [
      { type: 'image', key: 'r7/salon.png' },
      { type: 'image', key: 'r7/cocina.png' },
      { type: 'image', key: 'r7/patio.png' },
    ],
    rating: 9,
    check_out: iso(dia(-1)),
    created_at: iso(dia(-1)),
    properties: { name: 'Casa de Sanlúcar' },
  },
  {
    id: 'o2',
    general_status: 'Con incidencias',
    reservation_id: 'r4',
    notes: 'La persiana del dormitorio pequeño no sube. Aviso al técnico del pueblo.',
    media_urls: [
      { type: 'image', key: 'r4/persiana.png' },
      { type: 'image', key: 'r4/dormitorio.png' },
    ],
    rating: 6,
    check_out: iso(dia(-6)),
    created_at: iso(dia(-6)),
    properties: { name: 'Cortijo de Ronda' },
  },
  {
    id: 'o3',
    reservation_id: 'r6',
    general_status: 'Todo correcto',
    notes: 'Sin novedad. Hemos repuesto la sal y el café.',
    media_urls: [{ type: 'image', key: 'r6/entrada.png' }],
    rating: 10,
    check_out: iso(dia(-13)),
    created_at: iso(dia(-13)),
    properties: { name: 'Sierra Nevada' },
  },
  {
    id: 'o4',
    reservation_id: 'r10',
    general_status: 'Todo correcto',
    notes: 'Todo en orden. La lavadora vuelve a ir bien desde el arreglo de junio.',
    media_urls: [
      { type: 'image', key: 'r10/salon.png' },
      { type: 'image', key: 'r10/terraza.png' },
    ],
    rating: 9,
    check_out: iso(dia(-19)),
    created_at: iso(dia(-19)),
    properties: { name: 'Piso del Puerto' },
  },
  {
    id: 'o5',
    reservation_id: 'r5',
    general_status: 'Con incidencias',
    notes: 'Se rompió un vaso y falta una toalla de playa. Lo repongo yo la semana que viene.',
    media_urls: [{ type: 'image', key: 'r5/cocina.png' }],
    rating: 7,
    check_out: iso(dia(-24)),
    created_at: iso(dia(-24)),
    properties: { name: 'Cortijo de Ronda' },
  },
];

const registro = (action, who, desde, hasta, diasAtras, hora, minuto) => ({
  action,
  entity_type: 'reservation',
  entity_id: `r-${diasAtras}-${hora}`,
  details: { new: { start_date: fecha(desde), end_date: fecha(hasta) } },
  created_at: momento(diasAtras, hora, minuto),
  profiles: { name: who },
});

const REGISTROS = [
  registro('CREATE', 'Carmen Bas', 17, 24, 0, 10, 12),
  registro('UPDATE', 'Marta Rubal', 8, 15, 0, 9, 4),
  registro('CREATE', 'Pablo Moreno', 21, 28, 1, 22, 41),
  registro('DELETE', 'Elena Rubal', 4, 8, 1, 18, 27),
  registro('CREATE', 'Ignacio Sánchez', -3, 6, 2, 20, 55),
  registro('UPDATE', 'Lucía Sánchez', 12, 19, 3, 13, 8),
  registro('CREATE', 'Andrés Bas', -1, 4, 4, 21, 33),
  registro('CREATE', 'Teresa Ortega', 2, 7, 5, 12, 19),
  registro('CREATE', 'Marta Rubal', 1, 9, 6, 17, 2),
  registro('UPDATE', 'Rosa Delgado', 11, 18, 7, 19, 46),
];

/// `profiles` con la pertenencia anidada, como la consulta con join a
/// `group_members`.
const perfilFila = (p) => ({
  id: p.id,
  name: p.name,
  email: p.email,
  role: p.role,
  image: null,
  ui_preferences: { theme: 'light' },
  group_members: [{ group_id: p.g, role: p.gr }],
});

const TABLAS = {
  profiles: PERSONAS.map(perfilFila),

  family_groups: GRUPOS.map((g) => ({
    id: g.id,
    name: g.name,
    color: g.color,
    owner_id: PERSONAS.find((p) => p.g === g.id && p.gr === 'FAMILY_ADMIN')?.id ?? null,
    group_members: PERSONAS.filter((p) => p.g === g.id).map((p) => ({
      group_id: g.id,
      role: p.gr,
      profiles: { id: p.id, name: p.name, email: p.email, role: p.role },
    })),
  })),

  properties: PROPIEDADES,
  reservations: RESERVAS,
  // La vista de ocupación: mismas filas sin las notas privadas [A-04].
  calendar_occupancy: RESERVAS.map(({ notes, ...r }) => ({ ...r, notes: null })),
  reservation_waitlist: COLA,
  waitlist_occupancy: COLA.map(({ notes, ...w }) => ({ ...w, notes: null })),
  announcements: ANUNCIOS,
  sorteos: SORTEOS,
  out_reports: INSPECCIONES,
  audit_logs: REGISTROS,

  system_config: [
    {
      id: 'global',
      smtp_host: 'smtp.sanchezrubal.net',
      smtp_port: 587,
      smtp_user: 'avisos@sanchezrubal.net',
      smtp_secure: true,
      max_reservation_days: 14,
      max_reservation_days_cap: 31,
    },
  ],

  notification_templates: [
    { type: 'RESERVATION_CREATED', subject: 'Reserva confirmada en {{casa}}', body: 'Hola {{nombre}}, tu reserva del {{desde}} al {{hasta}} está confirmada.' },
    { type: 'PRE_STAY', subject: 'Tu estancia en {{casa}} empieza en 3 días', body: 'Recuerda revisar las normas de la casa antes de llegar.' },
    { type: 'WAITLIST_PROMOTED', subject: 'Las fechas son tuyas', body: '{{quien}} ha cancelado y te hemos asignado el {{desde}} → {{hasta}}.' },
  ],

  device_tokens: [],
};

// ---------------------------------------------------------------------------
//  GoTrue
// ---------------------------------------------------------------------------
const b64url = (obj) =>
  Buffer.from(JSON.stringify(obj)).toString('base64url');

/// JWT con la forma que espera el cliente. La firma es de adorno: nadie la
/// comprueba en el navegador, y este servidor solo existe en la máquina que
/// genera las capturas.
const jwt = () => {
  const ahora = Math.floor(Date.now() / 1000);
  const payload = {
    iss: `http://127.0.0.1:${PORT}/auth/v1`,
    sub: UID,
    aud: 'authenticated',
    role: 'authenticated',
    email: EMAIL,
    // aal1 sin factores verificados = no hay desafío de 2FA que completar.
    aal: 'aal1',
    amr: [{ method: 'password', timestamp: ahora }],
    session_id: '22222222-2222-4222-8222-222222222222',
    app_metadata: { provider: 'email', providers: ['email'] },
    user_metadata: {},
    iat: ahora,
    exp: ahora + 3600,
  };
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(payload)}.capturas`;
};

const usuario = () => ({
  id: UID,
  aud: 'authenticated',
  role: 'authenticated',
  email: EMAIL,
  email_confirmed_at: iso(dia(-400)),
  confirmed_at: iso(dia(-400)),
  last_sign_in_at: iso(HOY),
  phone: '',
  app_metadata: { provider: 'email', providers: ['email'] },
  user_metadata: {},
  identities: [],
  factors: [],
  is_anonymous: false,
  created_at: iso(dia(-400)),
  updated_at: iso(HOY),
});

const sesion = () => ({
  access_token: jwt(),
  token_type: 'bearer',
  expires_in: 3600,
  expires_at: Math.floor(Date.now() / 1000) + 3600,
  refresh_token: 'refresh-capturas',
  user: usuario(),
});

// ---------------------------------------------------------------------------
//  PNG de relleno para las fotos de las inspecciones
// ---------------------------------------------------------------------------
const crc32 = (buf) => {
  let c = ~0;
  for (const b of buf) {
    c ^= b;
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
};

const chunk = (tipo, datos) => {
  const largo = Buffer.alloc(4);
  largo.writeUInt32BE(datos.length);
  const cuerpo = Buffer.concat([Buffer.from(tipo, 'ascii'), datos]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(cuerpo));
  return Buffer.concat([largo, cuerpo, crc]);
};

/// Degradado suave, distinto para cada `key`. No pretende parecer una foto: es
/// el hueco de una, para que la pantalla de inspecciones tenga algo que enseñar.
const png = (key, w = 480, h = 360) => {
  let semilla = 0;
  for (const ch of key) semilla = (semilla * 31 + ch.charCodeAt(0)) >>> 0;
  const tono = semilla % 360;

  const hsl = (hh, s, l) => {
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((hh / 60) % 2) - 1));
    const m = l - c / 2;
    const [r, g, b] =
      hh < 60 ? [c, x, 0] : hh < 120 ? [x, c, 0] : hh < 180 ? [0, c, x]
        : hh < 240 ? [0, x, c] : hh < 300 ? [x, 0, c] : [c, 0, x];
    return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
  };

  const filas = [];
  for (let y = 0; y < h; y++) {
    const fila = Buffer.alloc(1 + w * 3);
    fila[0] = 0; // filtro None
    for (let x = 0; x < w; x++) {
      const t = (x / w) * 0.5 + (y / h) * 0.5;
      const [r, g, b] = hsl((tono + t * 40) % 360, 0.28, 0.58 - t * 0.22);
      fila[1 + x * 3] = r;
      fila[2 + x * 3] = g;
      fila[3 + x * 3] = b;
    }
    filas.push(fila);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bits por canal
  ihdr[9] = 2; // color RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(filas))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
};

// ---------------------------------------------------------------------------
//  PostgREST
// ---------------------------------------------------------------------------
const RESERVADOS = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'columns']);

/// Filtros de PostgREST que usa la app: `col=eq.valor`, y de propina los que
/// podría usar cualquier pantalla nueva sin que esto se caiga.
const pasaFiltro = (fila, col, expr) => {
  const i = expr.indexOf('.');
  const op = i === -1 ? 'eq' : expr.slice(0, i);
  const valor = i === -1 ? expr : expr.slice(i + 1);
  const actual = fila[col];
  switch (op) {
    case 'eq': return String(actual) === valor;
    case 'neq': return String(actual) !== valor;
    case 'is': return valor === 'null' ? actual == null : String(actual) === valor;
    case 'in': return valor.replace(/^\(|\)$/g, '').split(',').includes(String(actual));
    case 'gte': return actual >= valor;
    case 'lte': return actual <= valor;
    case 'gt': return actual > valor;
    case 'lt': return actual < valor;
    default: return true;
  }
};

const consultar = (tabla, params) => {
  let filas = (TABLAS[tabla] ?? []).map((f) => ({ ...f }));

  for (const [col, expr] of params) {
    if (RESERVADOS.has(col)) continue;
    filas = filas.filter((f) => pasaFiltro(f, col, expr));
  }

  const orden = params.get('order');
  if (orden) {
    const [col, ...resto] = orden.split('.');
    const desc = resto.includes('desc');
    filas.sort((a, b) => {
      const x = a[col] ?? '';
      const y = b[col] ?? '';
      return (x < y ? -1 : x > y ? 1 : 0) * (desc ? -1 : 1);
    });
  }

  const limite = Number(params.get('limit') ?? 0);
  return limite > 0 ? filas.slice(0, limite) : filas;
};

// ---------------------------------------------------------------------------
//  Espejo con caché de los tipos de letra de respaldo
//
//  Roboto no trae todos los caracteres que usa la app (la flecha "→" de los
//  rangos de fechas, el "⭐" de las valoraciones). En el móvil los pone el
//  sistema; en el navegador el motor de Flutter los descarga de Google Fonts.
//  `flutter_bootstrap.js` lo apunta aquí, y aquí se descargan UNA vez y se
//  guardan en disco: a partir de la segunda ejecución no hace falta internet.
//
//  Se usa `curl` a propósito y no `fetch`: en entornos con proxy corporativo,
//  curl ya lo tiene configurado y Node no.
// ---------------------------------------------------------------------------
const CACHE = process.env.CACHE_FUENTES
  ?? join(tmpdir(), 'portal-familia-fuentes-respaldo');

async function fuenteDeRespaldo(relativa) {
  // Solo rutas de Google Fonts: nada de subir por el árbol.
  if (!/^[A-Za-z0-9_.\-/]+$/.test(relativa) || relativa.includes('..')) return null;

  const enDisco = join(CACHE, relativa.replaceAll('/', '_'));
  try {
    return await readFile(enDisco);
  } catch {
    // no estaba en la caché
  }

  try {
    const datos = execFileSync(
      'curl',
      ['-sSL', '--max-time', '25', `https://fonts.gstatic.com/s/${relativa}`],
      { maxBuffer: 64 * 1024 * 1024, encoding: 'buffer' },
    );
    if (!datos?.length) return null;
    await mkdir(CACHE, { recursive: true });
    await writeFile(enDisco, datos);
    return datos;
  } catch (e) {
    console.error(`no se pudo traer la fuente ${relativa}: ${e.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
//  Servidor
// ---------------------------------------------------------------------------
const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.symbols': 'application/octet-stream',
};

const json = (res, cuerpo, code = 200) => {
  const texto = JSON.stringify(cuerpo);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(texto),
    // El SDK envía cabeceras propias; en el mismo origen no hay preflight,
    // pero esto deja la puerta abierta a servir la app desde otro puerto.
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': '*',
  });
  res.end(texto);
};

const cuerpoDe = (req) =>
  new Promise((resolve) => {
    let datos = '';
    req.on('data', (c) => (datos += c));
    req.on('end', () => {
      try {
        resolve(datos ? JSON.parse(datos) : {});
      } catch {
        resolve({});
      }
    });
  });

const servidor = createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const ruta = url.pathname;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'access-control-allow-origin': '*',
      'access-control-allow-headers': '*',
      'access-control-allow-methods': '*',
    });
    return res.end();
  }

  // --- GoTrue -------------------------------------------------------------
  if (ruta.startsWith('/auth/v1/')) {
    const cuerpo = await cuerpoDe(req);

    if (ruta === '/auth/v1/token') {
      const tipo = url.searchParams.get('grant_type');
      if (tipo === 'password' && cuerpo.password !== PASSWORD) {
        return json(res, { error: 'invalid_grant', error_description: 'Credenciales no válidas' }, 400);
      }
      return json(res, sesion());
    }
    if (ruta === '/auth/v1/user') return json(res, usuario());
    if (ruta === '/auth/v1/logout') { res.writeHead(204); return res.end(); }
    if (ruta === '/auth/v1/factors') return json(res, []);
    return json(res, {});
  }

  // --- Edge Functions -----------------------------------------------------
  if (ruta.startsWith('/functions/v1/')) {
    const cuerpo = await cuerpoDe(req);
    const nombre = ruta.slice('/functions/v1/'.length);
    if (nombre === 'media-sign') {
      return json(res, { url: `http://127.0.0.1:${PORT}/demo-media/${encodeURIComponent(cuerpo.key ?? 'x')}` });
    }
    return json(res, { ok: true });
  }

  // --- Fotos de relleno ---------------------------------------------------
  if (ruta.startsWith('/demo-media/')) {
    const imagen = png(decodeURIComponent(ruta.slice('/demo-media/'.length)));
    res.writeHead(200, { 'content-type': 'image/png', 'content-length': imagen.length });
    return res.end(imagen);
  }

  // --- Espejo de los tipos de letra de respaldo ---------------------------
  if (ruta.startsWith('/gfonts/')) {
    const datos = await fuenteDeRespaldo(ruta.slice('/gfonts/'.length));
    if (!datos) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, {
      'content-type': ruta.endsWith('.woff2')
        ? 'font/woff2'
        : ruta.endsWith('.otf')
          ? 'font/otf'
          : 'font/ttf',
      'content-length': datos.length,
      'access-control-allow-origin': '*',
    });
    return res.end(datos);
  }

  // --- PostgREST ----------------------------------------------------------
  if (ruta.startsWith('/rest/v1/')) {
    const recurso = ruta.slice('/rest/v1/'.length);

    if (recurso.startsWith('rpc/')) {
      await cuerpoDe(req);
      return json(res, {});
    }

    if (req.method !== 'GET') {
      // Las capturas no escriben nada; si alguna pantalla lo intenta, se le
      // responde que fue bien para que no enseñe un error.
      await cuerpoDe(req);
      const unico = (req.headers.accept ?? '').includes('vnd.pgrst.object');
      return json(res, unico ? {} : [], 201);
    }

    const filas = consultar(recurso, url.searchParams);
    const unico = (req.headers.accept ?? '').includes('vnd.pgrst.object');
    if (!unico) return json(res, filas);
    if (filas.length === 0) {
      return json(res, { code: 'PGRST116', message: 'No rows found', details: null, hint: null }, 406);
    }
    return json(res, filas[0]);
  }

  // --- La app compilada ---------------------------------------------------
  const rel = ruta === '/' ? '/index.html' : ruta;
  const destino = join(WEB_ROOT, normalize(rel).replace(/^(\.\.[/\\])+/, ''));
  try {
    const datos = await readFile(destino);
    res.writeHead(200, {
      'content-type': TIPOS[extname(destino)] ?? 'application/octet-stream',
      'content-length': datos.length,
      // Flutter web con CanvasKit/skwasm necesita estas dos para poder usar
      // SharedArrayBuffer; sin ellas cae al camino lento.
      'cross-origin-opener-policy': 'same-origin',
      'cross-origin-embedder-policy': 'require-corp',
      'cache-control': 'no-store',
    });
    res.end(datos);
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('404');
  }
});

// El cliente de Supabase abre Realtime nada más entrar. No hace falta que
// funcione (las capturas son estáticas), pero si el socket se rechaza el
// cliente reintenta en bucle y llena la consola de errores: se acepta el
// apretón de manos y se deja la conexión abierta sin decir nada.
servidor.on('upgrade', (req, socket) => {
  const clave = req.headers['sec-websocket-key'];
  if (!clave) return socket.destroy();
  const aceptar = createHash('sha1')
    .update(clave + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${aceptar}\r\n\r\n`,
  );
  socket.on('data', () => {});
  socket.on('error', () => socket.destroy());
});

servidor.listen(PORT, '127.0.0.1', () => {
  console.log(`backend simulado + app en http://127.0.0.1:${PORT}`);
});
