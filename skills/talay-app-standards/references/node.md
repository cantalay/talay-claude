# Node API / worker standardı

Referans uygulama: `cantalay/vitafinder-core` (pnpm monorepo, Fastify + pino, api ve worker tek image,
`VITAFINDER_PROCESS_TYPE` ile seçim, distroless runtime).

## Bağımlılıklar (production)
- HTTP: `fastify` (tercih) veya `express`
- Log: `pino` (Fastify yerleşik) — OTel pino instrumentation log'a `trace_id`/`span_id` ekler
- Metrics: `prom-client`
- OTel: `@opentelemetry/auto-instrumentations-node` (**dependencies**, devDependencies değil). Chart
  `NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register` verir; `runtime.node.autoInstrumentation.enabled: true`.
  Monorepo/pnpm deploy'da paket runtime `node_modules`'ta çözülebilmeli (`NODE_PATH` gerekirse config'te).
- JWT: `jose` (`createRemoteJWKSet`, `jwtVerify`)
- DB: `pg` (+ tercihen `kysely`/`drizzle`); Redis: `ioredis`
- Config doğrulama: `zod`

## İskelet
```ts
const env = z.object({
  PORT: z.coerce.number().default(8080),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().optional(),
  REDIS_KEY_PREFIX: z.string().default(''),
  KEYCLOAK_ISSUER_URL: z.string().url(),
  KEYCLOAK_AUDIENCE: z.string(),
  CORS_ORIGINS: z.string().default(''),
}).parse(process.env);

const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? 'info' } });
let ready = false;
app.get('/health/live', async () => ({ status: 'ok' }));
app.get('/health/startup', async (_, r) => (ready ? { status: 'ok' } : r.code(503).send({ status: 'starting' })));
app.get('/health/ready', async (_, r) => {
  try { await pool.query('select 1'); return { status: 'ok' }; } catch { return r.code(503).send({ status: 'degraded' }); }
});
app.get('/metrics', async (_, r) => r.type(register.contentType).send(await register.metrics()));
await runMigrations(pool);   // advisory lock'lu
await app.listen({ host: '0.0.0.0', port: env.PORT });
ready = true;
for (const s of ['SIGTERM', 'SIGINT']) process.once(s, async () => { ready = false; await app.close(); await pool.end(); process.exit(0); });
```

## Auth middleware
```ts
const jwks = createRemoteJWKSet(new URL(`${env.KEYCLOAK_ISSUER_URL}/protocol/openid-connect/certs`));
async function authenticate(req) {
  const token = req.headers.authorization?.replace(/^Bearer /, '');
  if (!token) throw httpError(401);
  const { payload } = await jwtVerify(token, jwks, { issuer: env.KEYCLOAK_ISSUER_URL, audience: env.KEYCLOAK_AUDIENCE });
  req.user = { id: payload.sub, roles: (payload.realm_access as any)?.roles ?? [] };
}
const requireRole = (role) => async (req) => { if (!req.user.roles.includes(role)) throw httpError(403); };
```

## Migration
`db/migrations/0001_init.sql`, `0002_…sql` (vitafinder-core düzeni). Runner:
```ts
async function runMigrations(pool) {
  const c = await pool.connect();
  try {
    await c.query('select pg_advisory_lock(hashtext($1))', ['migrations']);
    await c.query('create table if not exists schema_migrations (version text primary key, applied_at timestamptz default now())');
    for (const file of (await readdir(dir)).filter(f => f.endsWith('.sql')).sort()) {
      const { rowCount } = await c.query('select 1 from schema_migrations where version=$1', [file]);
      if (rowCount) continue;
      await c.query('begin'); await c.query(await readFile(join(dir, file), 'utf8'));
      await c.query('insert into schema_migrations(version) values($1)', [file]); await c.query('commit');
    }
  } catch (e) { await c.query('rollback').catch(() => {}); throw e; }
  finally { await c.query('select pg_advisory_unlock(hashtext($1))', ['migrations']).catch(() => {}); c.release(); }
}
```
Migration dosyaları image'a kopyalanmalı (Dockerfile). Hazır kütüphane tercih edilirse `node-pg-migrate`/`drizzle-kit migrate`.
API ve worker aynı DB'yi kullanıyorsa migration'ı yalnız API çalıştırır; worker `schema_migrations`'ı bekler veya readiness'te kontrol eder.

## Worker
Aynı health/metrics sunucusunu açar (ör. port 8080/3001), kuyruk/cron işini ayrı döngüde yürütür. Values'ta ingress yok,
`networkPolicy.allowSameNamespace: true`.

## Values özeti
```yaml
runtime: { type: node, node: { autoInstrumentation: { enabled: true } } }
containerPort: 8080
probes: { startup: { path: /health/startup }, readiness: { path: /health/ready }, liveness: { path: /health/live } }
serviceMonitor: { enabled: true, path: /metrics }
resources: { requests: { cpu: 25m, memory: 128Mi }, limits: { memory: 384Mi } }
```
