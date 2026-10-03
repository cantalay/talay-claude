# React / Vite / Expo Web standardı

Referanslar: `cantalay/vitafinder-web` (pnpm monorepo, storefront + admin tek image, alt dizinler),
`cantalay/todogi-app` (Expo, web export + EAS mobil).

## Runtime config
`public/runtime-config.js`:
```js
window.__TALAY_CONFIG__ = {};
```
`src/config.ts`:
```ts
type RuntimeConfig = { API_URL: string; AUTH_URL: string; AUTH_REALM: string; AUTH_CLIENT_ID: string };
const runtime = (window as typeof window & { __TALAY_CONFIG__?: Partial<RuntimeConfig> }).__TALAY_CONFIG__ ?? {};
export const config: RuntimeConfig = {
  API_URL: runtime.API_URL ?? import.meta.env.VITE_API_URL ?? 'http://localhost:8080',
  AUTH_URL: runtime.AUTH_URL ?? import.meta.env.VITE_AUTH_URL ?? 'https://auth.cantalay.com',
  AUTH_REALM: runtime.AUTH_REALM ?? import.meta.env.VITE_AUTH_REALM ?? '',
  AUTH_CLIENT_ID: runtime.AUTH_CLIENT_ID ?? import.meta.env.VITE_AUTH_CLIENT_ID ?? '',
};
```
nginx (`talay-web` varsayılanı veya env repodaki `nginx/default.conf`) `</head>` öncesine `<script src="/runtime-config.js">`
enjekte eder; values'taki `runtimeConfig` map'i bu dosyayı üretir. Expo'da `EXPO_PUBLIC_*` anahtarları kullanılabilir (todogi).

## Auth (OIDC + PKCE)
`oidc-client-ts` (+ `react-oidc-context`) veya `keycloak-js`:
```ts
const userManager = new UserManager({
  authority: `${config.AUTH_URL}/realms/${config.AUTH_REALM}`,
  client_id: config.AUTH_CLIENT_ID,
  redirect_uri: `${location.origin}/auth/callback`,
  post_logout_redirect_uri: location.origin,
  response_type: 'code',
  scope: 'openid profile email',
  automaticSilentRenew: true,
});
```
Keycloak client'ında redirect `https://<host>/*`, web origin `https://<host>` (talay-auth bunu Terraform'la ayarlar).
Token'ı memory/sessionStorage'da tut; API çağrılarına `Authorization: Bearer`. Rol kontrolü UI'da yalnız görünürlük içindir,
asıl yetki API'de.

## Build / container
- Vite: `base: '/'`; birden çok app tek image'da ise `base: '/admin/'` vb. ve nginx `root` alt dizine (vitafinder-web).
- Dockerfile: `templates/docker/web-static.Dockerfile` (nginx-unprivileged, UID 101, port 8080, `/healthz`).
- CI: `talay-workflows/web.yaml`.

## Values özeti
```yaml
containerPort: 8080
runtimeConfig: { API_URL: https://api.<project>.cantalay.com, AUTH_URL: https://auth.cantalay.com, AUTH_REALM: <project>, AUTH_CLIENT_ID: <project>-web }
nginx: { existingConfigMap: <fullname>-nginx, configRevision: "1" }   # özel nginx gerekiyorsa
securityHeaders.contentSecurityPolicy: "default-src 'self'; connect-src 'self' https://api.<project>.cantalay.com https://auth.cantalay.com; …"
networkPolicy: { enabled: true, denyEgress: true }
```

## Mobil (Expo native)
Kubernetes'e gitmez. `talay-workflows/expo.yaml` (EAS build/submit), `EXPO_TOKEN` repo secret'ı. Keycloak'ta ayrı public
client + custom scheme redirect (`<scheme>://auth/callback`) gerekir — talay-auth'ta browser client olarak root_url yerine
redirect ile eklenmesi için modülde `extra_redirect_uris` kullan.
