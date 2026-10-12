// Enrutador de las Edge Functions en el Supabase autoalojado. Es el main del
// compose oficial con un cambio: la verificación del JWT es por función, como
// en la nube. Las de FUNCTIONS_PUBLIC se autentican solas (secreto propio) o
// son públicas; el resto exige un JWT válido.
import * as jose from 'jsr:@panva/jose@6'

const JWT_SECRET = Deno.env.get('JWT_SECRET')
const JWKS = parseJwks(Deno.env.get('SUPABASE_JWKS'))
const LOCAL_JWKS = JWKS ? jose.createLocalJWKSet(JWKS) : null
const VERIFY_JWT = Deno.env.get('VERIFY_JWT') === 'true'
const PUBLICAS = new Set(
  (Deno.env.get('FUNCTIONS_PUBLIC') ?? '').split(',').map((s) => s.trim()).filter(Boolean),
)

function parseJwks(raw: string | undefined): jose.JSONWebKeySet | null {
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed?.keys) && parsed.keys.length > 0 ? parsed : null
  } catch {
    return null
  }
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function jwtValido(req: Request): Promise<boolean> {
  const [esquema, token, ...resto] = (req.headers.get('authorization') ?? '').trim().split(/\s+/)
  if (esquema?.toLowerCase() !== 'bearer' || !token || resto.length > 0) return false
  try {
    const alg = jose.decodeProtectedHeader(token).alg
    if (alg === 'HS256' && JWT_SECRET) {
      await jose.jwtVerify(token, new TextEncoder().encode(JWT_SECRET))
      return true
    }
    if ((alg === 'ES256' || alg === 'RS256') && LOCAL_JWKS) {
      await jose.jwtVerify(token, LOCAL_JWKS)
      return true
    }
  } catch {
    // firma, caducidad o formato inválidos
  }
  return false
}

Deno.serve(async (req: Request) => {
  const nombre = new URL(req.url).pathname.split('/')[1] ?? ''
  if (!/^[a-z0-9][a-z0-9-]*$/.test(nombre) || nombre === 'main') {
    return json({ msg: 'missing function name in request' }, 400)
  }

  if (VERIFY_JWT && req.method !== 'OPTIONS' && !PUBLICAS.has(nombre)) {
    if (!(await jwtValido(req))) return json({ code: 401, message: 'Invalid JWT' }, 401)
  }

  const env = { ...Deno.env.toObject(), SUPABASE_FUNCTION_SLUG: nombre }
  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath: `/home/deno/functions/${nombre}`,
      memoryLimitMb: 150,
      workerTimeoutMs: 60 * 1000,
      noModuleCache: false,
      importMapPath: '/home/deno/functions/deno.jsonc',
      envVars: Object.entries(env),
    })
    return await worker.fetch(req)
  } catch (e) {
    return json({ msg: String(e) }, 500)
  }
})
