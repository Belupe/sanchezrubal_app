#!/usr/bin/env python3
"""Dibuja el esquema `public` como un PNG, al estilo del visor de Supabase.

Existe porque ese visor no deja capturar el árbol entero: para que quepa hay
que alejar el zoom del navegador y la imagen sale ilegible.

Imita su aspecto a propósito —tarjetas oscuras con cabecera, una fila por
columna con su tipo a la derecha y conectores en ángulo recto que salen de la
clave ajena y entran en la primaria— porque es el que resulta familiar y se lee
bien. La diferencia es que aquí sale nítido y de una pieza.

No necesita instalar nada: genera un SVG y lo convierte con `qlmanage`, que
viene con macOS. En este equipo no hay node, ni Pillow, ni un navegador con el
que renderizar, así que las vías habituales no servían.

    python3 scripts/esquema-png.py

Las posiciones están escritas a mano: un algoritmo de colocación reparte 16
tablas peor que el ojo, y esto se mira mucho más de lo que se cambia.
"""
import subprocess, sys, os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, 'docs', 'capturas', 'esquema-base-de-datos.png')

LADO = 2600            # cuadrado: ver la nota de main()
ANCHO = 380
CABECERA = 46
FILA = 35

FONDO     = '#fbfbfc'
TARJETA   = '#1c1c1c'
CAB_FONDO = '#2b2b2b'
BORDE     = '#3a3a3a'
SEPARA    = '#272727'
TINTA     = '#e8e8e8'
TIPO      = '#8a8a8a'
LINEA     = '#8d939e'
LLAVE     = '#3ecf8e'   # el verde de Supabase

# tabla -> [(columna, tipo, pk, fk, obligatoria)], leído de la base real.
T = {
 'profiles': [('id','uuid',1,1,1),('email','text',0,0,0),('name','text',0,0,1),
   ('role','text',0,0,1),('ui_preferences','jsonb',0,0,0),('image','text',0,0,0),
   ('created_at','timestamptz',0,0,1),('updated_at','timestamptz',0,0,1)],
 'family_groups': [('id','uuid',1,0,1),('name','text',0,0,1),('color','text',0,0,1),
   ('owner_id','uuid',0,1,0),('created_at','timestamptz',0,0,1),('updated_at','timestamptz',0,0,1)],
 'group_members': [('group_id','uuid',1,1,1),('user_id','uuid',1,1,1),
   ('role','text',0,0,1),('created_at','timestamptz',0,0,1)],
 'properties': [('id','uuid',1,0,1),('name','text',0,0,1),('description','text',0,0,0),
   ('image','text',0,0,0),('created_at','timestamptz',0,0,1),('updated_at','timestamptz',0,0,1)],
 'reservations': [('id','uuid',1,0,1),('property_id','uuid',0,1,1),('family_group_id','uuid',0,1,0),
   ('created_by_id','uuid',0,1,1),('start_date','timestamptz',0,0,1),('end_date','timestamptz',0,0,1),
   ('guest_count','int4',0,0,1),('guests_list','jsonb',0,0,0),('notes','text',0,0,0),
   ('is_maintenance','bool',0,0,1),('created_at','timestamptz',0,0,1),('updated_at','timestamptz',0,0,1)],
 'reservation_waitlist': [('id','uuid',1,0,1),('property_id','uuid',0,1,1),
   ('requested_by_id','uuid',0,1,1),('family_group_id','uuid',0,1,0),
   ('start_date','timestamptz',0,0,1),('end_date','timestamptz',0,0,1),('guest_count','int4',0,0,1),
   ('notes','text',0,0,0),('status','text',0,0,1),('created_at','timestamptz',0,0,1),
   ('updated_at','timestamptz',0,0,1)],
 'out_reports': [('id','uuid',1,0,1),('property_id','uuid',0,1,1),('reservation_id','uuid',0,1,0),
   ('check_in','timestamptz',0,0,1),('check_out','timestamptz',0,0,1),('general_status','text',0,0,1),
   ('damages','text',0,0,0),('missing_items','text',0,0,0),('notes','text',0,0,0),
   ('media_urls','jsonb',0,0,0),('rating','int4',0,0,0),('checklist','jsonb',0,0,0),
   ('created_at','timestamptz',0,0,1)],
 'announcements': [('id','uuid',1,0,1),('title','text',0,0,1),('content','text',0,0,1),
   ('author_id','uuid',0,1,1),('created_at','timestamptz',0,0,1)],
 'announcement_properties': [('announcement_id','uuid',1,1,1),('property_id','uuid',1,1,1)],
 'sorteos': [('id','uuid',1,0,1),('name','text',0,0,1),('created_by_id','uuid',0,1,1),
   ('created_at','timestamptz',0,0,1)],
 'sorteo_resultados': [('id','uuid',1,0,1),('sorteo_id','uuid',0,1,1),
   ('family_group_id','uuid',0,1,1),('premio','text',0,0,1)],
 'device_tokens': [('id','uuid',1,0,1),('user_id','uuid',0,1,1),('token','text',0,0,1),
   ('platform','text',0,0,0),('created_at','timestamptz',0,0,1)],
 'support_log_sends': [('id','uuid',1,0,1),('user_id','uuid',0,1,1),('es_fallo','bool',0,0,1),
   ('bytes','int4',0,0,0),('created_at','timestamptz',0,0,1)],
 'audit_logs': [('id','uuid',1,0,1),('action','text',0,0,1),('entity_type','text',0,0,1),
   ('entity_id','uuid',0,0,0),('details','jsonb',0,0,0),('user_id','uuid',0,1,0),
   ('created_at','timestamptz',0,0,1)],
 'notification_templates': [('id','uuid',1,0,1),('type','text',0,0,1),('subject','text',0,0,1),
   ('body','text',0,0,1),('updated_at','timestamptz',0,0,1)],
 'system_config': [('id','text',1,0,1),('smtp_host','text',0,0,0),('smtp_port','int4',0,0,0),
   ('smtp_user','text',0,0,0),('smtp_pass','text',0,0,0),('smtp_secure','bool',0,0,1),
   ('base_url','text',0,0,0),('max_reservation_days','int4',0,0,1),
   ('max_reservation_days_cap','int4',0,0,1),('updated_at','timestamptz',0,0,1)],
}

# Esquina superior izquierda. Cinco columnas y, dentro, las tablas apiladas: los
# conectores viven en los pasillos verticales y no cruzan por encima de nadie.
# Las que solo cuelgan de `profiles` van a la izquierda; el núcleo, en medio.
POS = {
 'device_tokens':          (  60,  230), 'support_log_sends':      (  60,  620),
 'audit_logs':             (  60, 1010), 'announcements':          (  60, 1560),
 'announcement_properties':(  60, 2000),
 'sorteos':                ( 540,  230), 'sorteo_resultados':      ( 540,  580),
 'notification_templates': (1540, 1700), 'system_config':          (2080, 1620),
 'profiles':               (1030,  230), 'family_groups':          (1030,  790),
 'group_members':          (1030, 1330),
 'reservations':           (1540,  230), 'reservation_waitlist':   (1540, 1010),
 'properties':             (2080,  230), 'out_reports':            (2080,  700),
}

# (tabla, columna con la clave ajena, tabla a la que apunta)
REL = [
 ('profiles','id','auth.users'),
 ('family_groups','owner_id','profiles'),
 ('group_members','group_id','family_groups'), ('group_members','user_id','profiles'),
 ('reservations','property_id','properties'), ('reservations','family_group_id','family_groups'),
 ('reservations','created_by_id','profiles'),
 ('reservation_waitlist','property_id','properties'),
 ('reservation_waitlist','requested_by_id','profiles'),
 ('reservation_waitlist','family_group_id','family_groups'),
 ('out_reports','property_id','properties'), ('out_reports','reservation_id','reservations'),
 ('announcements','author_id','profiles'),
 ('announcement_properties','announcement_id','announcements'),
 ('announcement_properties','property_id','properties'),
 ('sorteos','created_by_id','profiles'),
 ('sorteo_resultados','sorteo_id','sorteos'),
 ('sorteo_resultados','family_group_id','family_groups'),
 ('device_tokens','user_id','profiles'), ('support_log_sends','user_id','profiles'),
 ('audit_logs','user_id','profiles'),
]

# auth.users no es del esquema public. Se dibuja como etiqueta suelta, igual que
# hace Supabase, para que se vea de dónde cuelga profiles sin fingir que es una
# tabla más de las nuestras.
AUTH = (1030, 600)


def alto(t):     return CABECERA + FILA * len(T[t])
def y_pk(t):     return POS[t][1] + CABECERA + FILA / 2


def fila_y(t, col):
    """Centro vertical de la fila de esa columna: donde se engancha la línea."""
    for i, f in enumerate(T[t]):
        if f[0] == col:
            return POS[t][1] + CABECERA + FILA * i + FILA / 2
    return y_pk(t)


def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def tarjeta(p, t):
    x, y = POS[t]
    h = alto(t)
    p.append(f'<rect x="{x}" y="{y+3}" width="{ANCHO}" height="{h}" rx="11" fill="#00000018"/>')
    p.append(f'<rect x="{x}" y="{y}" width="{ANCHO}" height="{h}" rx="11" fill="{TARJETA}" '
             f'stroke="{BORDE}" stroke-width="1.5"/>')
    p.append(f'<path d="M{x},{y+CABECERA} v-{CABECERA-11} a11,11 0 0 1 11,-11 h{ANCHO-22} '
             f'a11,11 0 0 1 11,11 v{CABECERA-11} z" fill="{CAB_FONDO}"/>')
    # Iconito de tabla: un rectángulo con una raya, como el de Supabase.
    p.append(f'<rect x="{x+18}" y="{y+15}" width="15" height="15" rx="2.5" fill="none" '
             f'stroke="{TINTA}" stroke-width="1.5"/>')
    p.append(f'<line x1="{x+18}" y1="{y+21}" x2="{x+33}" y2="{y+21}" stroke="{TINTA}" stroke-width="1.2"/>')
    p.append(f'<text x="{x+44}" y="{y+29}" font-size="18.5" fill="{TINTA}" font-weight="600">{esc(t)}</text>')

    for i, (col, tipo, pk, fk, obl) in enumerate(T[t]):
        fy = y + CABECERA + FILA * i
        if i:
            p.append(f'<line x1="{x+1.5}" y1="{fy}" x2="{x+ANCHO-1.5}" y2="{fy}" '
                     f'stroke="{SEPARA}" stroke-width="1"/>')
        cy = fy + FILA / 2
        if pk:   # llave: anilla con paletón
            p.append(f'<circle cx="{x+23}" cy="{cy}" r="4.2" fill="none" stroke="{LLAVE}" stroke-width="1.7"/>')
            p.append(f'<line x1="{x+27}" y1="{cy}" x2="{x+35}" y2="{cy}" stroke="{LLAVE}" stroke-width="1.7"/>')
            p.append(f'<line x1="{x+33}" y1="{cy}" x2="{x+33}" y2="{cy+3.5}" stroke="{LLAVE}" stroke-width="1.7"/>')
        # Rombo relleno = obligatoria (NOT NULL); hueco = admite nulos.
        p.append(f'<path d="M{x+48},{cy-5} L{x+53},{cy} L{x+48},{cy+5} L{x+43},{cy} Z" '
                 f'fill="{TINTA if obl else "none"}" stroke="{TINTA}" stroke-width="1.3"/>')
        p.append(f'<text x="{x+64}" y="{cy+6}" font-size="16" fill="{LLAVE if fk else TINTA}">{esc(col)}</text>')
        p.append(f'<text x="{x+ANCHO-14}" y="{cy+5.5}" font-size="13" fill="{TIPO}" '
                 f'text-anchor="end" font-family="Menlo,monospace">{esc(tipo)}</text>')


def conector(p, o, col, d):
    """Ángulo recto de la clave ajena a la primaria de destino."""
    y1, ox = fila_y(o, col), POS[o][0]
    if d == 'auth.users':
        # Sale por la IZQUIERDA y baja: la etiqueta está justo debajo, y por la
        # derecha la línea cruzaría por encima de media tabla de reservas.
        x1, x2, y2 = ox, AUTH[0], AUTH[1] + 21
        p.append(f'<path d="M{x1},{y1:.0f} H{x1-45} V{y2} H{x2}" fill="none" '
                 f'stroke="{LINEA}" stroke-width="1.8"/>')
        p.append(f'<circle cx="{x1}" cy="{y1:.0f}" r="4" fill="{LINEA}"/>')
        return
    y2, dx = y_pk(d), POS[d][0]
    x1, x2 = (ox + ANCHO, dx) if dx > ox else (ox, dx + ANCHO)
    mx = (x1 + x2) / 2
    p.append(f'<path d="M{x1},{y1:.0f} H{mx:.0f} V{y2:.0f} H{x2}" fill="none" '
             f'stroke="{LINEA}" stroke-width="1.8" opacity="0.9"/>')
    p.append(f'<circle cx="{x1}" cy="{y1:.0f}" r="4" fill="{LINEA}"/>')
    p.append(f'<circle cx="{x2}" cy="{y2:.0f}" r="4" fill="{LINEA}"/>')


def svg():
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{LADO}" height="{LADO}" '
         f'viewBox="0 0 {LADO} {LADO}">',
         f'<rect width="{LADO}" height="{LADO}" fill="{FONDO}"/>',
         '<style>text{font-family:Helvetica,Arial,sans-serif}</style>',
         f'<text x="60" y="88" font-size="40" font-weight="bold" fill="#18181b">'
         f'Portal Familia <tspan fill="#9a9aa2">— esquema public</tspan></text>',
         f'<text x="60" y="128" font-size="19" fill="#6b6b75">'
         f'16 tablas · 21 relaciones · leído de la base de datos, no de las migraciones</text>']

    for o, col, d in REL:              # las líneas van debajo de las tarjetas
        conector(p, o, col, d)

    p.append(f'<rect x="{AUTH[0]}" y="{AUTH[1]}" width="210" height="42" rx="9" fill="{TARJETA}" '
             f'stroke="{BORDE}" stroke-width="1.5" stroke-dasharray="5 4"/>')
    p.append(f'<text x="{AUTH[0]+105}" y="{AUTH[1]+27}" font-size="16.5" fill="{TIPO}" '
             f'text-anchor="middle">auth.users.id</text>')

    for t in T:
        tarjeta(p, t)

    ly = LADO - 130
    p.append(f'<circle cx="70" cy="{ly-5}" r="4.2" fill="none" stroke="{LLAVE}" stroke-width="1.7"/>')
    p.append(f'<line x1="74" y1="{ly-5}" x2="82" y2="{ly-5}" stroke="{LLAVE}" stroke-width="1.7"/>')
    p.append(f'<text x="95" y="{ly}" font-size="17" fill="#5b5b63">clave primaria</text>')
    p.append(f'<path d="M255,{ly-10} L260,{ly-5} L255,{ly} L250,{ly-5} Z" fill="#5b5b63"/>')
    p.append(f'<text x="272" y="{ly}" font-size="17" fill="#5b5b63">obligatoria</text>')
    p.append(f'<path d="M405,{ly-10} L410,{ly-5} L405,{ly} L400,{ly-5} Z" fill="none" stroke="#5b5b63" stroke-width="1.4"/>')
    p.append(f'<text x="422" y="{ly}" font-size="17" fill="#5b5b63">admite nulos</text>')
    p.append(f'<text x="580" y="{ly}" font-size="17" fill="{LLAVE}">en verde</text>')
    p.append(f'<text x="668" y="{ly}" font-size="17" fill="#5b5b63">, las columnas que apuntan a otra tabla</text>')
    p.append('</svg>')
    return '\n'.join(p)


def main():
    tmp = '/tmp/esquema-portal-familia.svg'
    open(tmp, 'w').write(svg())
    os.makedirs(os.path.dirname(SALIDA), exist_ok=True)
    # El lienzo es CUADRADO porque qlmanage no respeta la proporción: encaja lo
    # que le des dentro de un cuadrado y recorta lo que sobra. Peleándose con él
    # el diagrama salía ampliado y cortado; dándole ya un cuadrado, sale 1:1.
    subprocess.run(['qlmanage', '-t', '-s', str(LADO), '-o', '/tmp', tmp], capture_output=True)
    bruto = '/tmp/' + os.path.basename(tmp) + '.png'
    if not os.path.exists(bruto):
        sys.exit('qlmanage no generó el PNG')
    subprocess.run(['cp', bruto, SALIDA], check=True)
    print('escrito:', SALIDA)


if __name__ == '__main__':
    main()
