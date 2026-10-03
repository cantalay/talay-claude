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
type RuntimeConfig = { API_URL: string; AUTH_URL: string; AUTH_REALM: string };
const runtime = (window as typeof window & { __TALAY_CONFIG__?: Partial<RuntimeConfig> }).__TALAY_CONFIG__ ?? {};
export const config: RuntimeConfig = {
  API_URL: runtime.API_URL ?? import.meta.env.VITE_API_URL ?? 'http://localhost:8080',
  AUTH_URL: runtime.AUTH_URL ?? import.meta.env.VITE_AUTH_URL ?? 'https://auth.cantalay.com',
  AUTH_REALM: runtime.AUTH_REALM ?? import.meta.env.VITE_AUTH_REALM ?? '<project>',
};
```
nginx (`talay-web` varsayılanı veya env repodaki `nginx/default.conf`) `</head>` öncesine `<script src="/runtime-config.js">`
enjekte eder; values'taki `runtimeConfig` map'i bu dosyayı üretir. Expo'da `EXPO_PUBLIC_*` anahtarları kullanılabilir (todogi:
`EXPO_PUBLIC_AUTH_URL`, `EXPO_PUBLIC_AUTH_REALM`).

## Auth (auth-gateway, Keycloak sayfası yok)
Uygulama kendi login/kayıt formunu gösterir ve auth-gateway'e konuşur (talay-auth). Referans:
`cantalay/talay-hello` → `web/src/auth.ts` (login/register/refresh/logout + oturum) ve `web/src/App.tsx` (form).
```ts
const gatewayUrl = (path: string) => `${config.AUTH_URL}/auth/${encodeURIComponent(config.AUTH_REALM)}${path}`;
// POST /login {email,password} -> {access_token, refresh_token, expires_in}
// POST /register {email,password,firstName,lastName} -> 201 (sonra login)
// POST /refresh {refreshToken}; POST /logout (Bearer) {refreshToken}
// Hata gövdesi: {success:false, error:{status, message}} -> message'ı kullanıcıya göster
```
- API çağrısından önce access token'ın süresi < 30 sn ise `/refresh`.
- Oturumu `sessionStorage`'da tut (sekme kapanınca biter); "beni hatırla" isteniyorsa kullanıcıya XSS riskini söyle.
- Parola kuralı (realm politikası): en az 12 karakter, büyük/küçük harf, rakam, özel karakter, kullanıcı adı değil.
- Rol kontrolü UI'da yalnız görünürlük içindir, asıl yetki API'de.
- CSP kullanılıyorsa `connect-src` içine `https://auth.cantalay.com` ve API host'u eklenmeli.

## Build / container
- Vite: `base: '/'`; birden çok app tek image'da ise `base: '/admin/'` vb. ve nginx `root` alt dizine (vitafinder-web).
- Dockerfile: `templates/docker/web-static.Dockerfile` (nginx-unprivileged, UID 101, port 8080, `/healthz`).
- CI: `talay-workflows/web.yaml`.

## Values özeti
```yaml
containerPort: 8080
runtimeConfig: { API_URL: https://api.<project>.cantalay.com, AUTH_URL: https://auth.cantalay.com, AUTH_REALM: <project> }
nginx: { existingConfigMap: <fullname>-nginx, configRevision: "1" }   # özel nginx gerekiyorsa
securityHeaders.contentSecurityPolicy: "default-src 'self'; connect-src 'self' https://api.<project>.cantalay.com https://auth.cantalay.com; …"
networkPolicy: { enabled: true, denyEgress: true }
```

## Mobil (Expo native)
Kubernetes'e gitmez. `talay-workflows/expo.yaml` (EAS build/submit), `EXPO_TOKEN` repo secret'ı. Login aynı auth-gateway
uçlarıyla yapılır; refresh token `expo-secure-store`'da tutulur. Google/Apple girişi için gateway `/social`
(authorization code + `kc_idp_hint`) kullanılır ve talay-identity'de `gateway_redirect_uris` ile `<scheme>://callback`
izinli olmalıdır (araya Google sayfası girer, Keycloak sayfası girmez).
