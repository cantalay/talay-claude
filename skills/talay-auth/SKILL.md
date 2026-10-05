---
name: talay-auth
description: Uygulamalara Keycloak'ı auth-gateway üzerinden servis olarak sunar — kullanıcı Keycloak sayfası görmeden uygulamanın kendi formundan login/kayıt/refresh/logout/profil/parola (https://auth.cantalay.com/auth/<realm>/...). Proje realm'i, gateway client'ları, API audience ve roller talay-identity Terraform'u ile; gateway'e realm ekleme; backend JWT doğrulama ve rol kontrolü. "login ekle", "auth", "kayıt", "keycloak", "rol", "kullanıcı girişi", "auth-gateway" isteklerinde kullan.
---

# talay-auth

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §8. Repolar: `$TALAY_INFRA_DIR/talay-identity`, `$TALAY_INFRA_DIR/talay-environments`
(gateway: `apps/prod/todogi/auth-gateway`), gateway kodu `github.com/cantalay/auth-gateway`.

## Model (varsayılan)
- Kullanıcı **asla Keycloak sayfası görmez.** Web/mobil uygulama kendi formundan auth-gateway'e konuşur:
  `POST https://auth.cantalay.com/auth/<realm>/login {email,password}` → Keycloak token yanıtı
  (`access_token`, `refresh_token`, `expires_in`).
- Diğer uçlar: `/register` (201; 409 var; 400 parola politikası), `/refresh {refreshToken}`, `/logout` (Bearer + `{refreshToken}`),
  `GET|PATCH /me`, `/change-password`, `/social {code, redirectUri}`.
- Token: `iss=https://auth.cantalay.com/realms/<realm>`, `aud=<realm>-api`, `azp=<realm>-gateway`, roller `realm_access.roles`.
- Backend API'ler token'ı JWKS ile kendisi doğrular (gateway'e sormaz).
- Gateway'de olmayanlar: parola sıfırlama (forgot/reset), avatar. Gerekirse gateway'e eklenmeli; Keycloak'ın e-posta
  linkleri Keycloak sayfası açar, kullanıcıya bunu söyle.

## Yeni proje için auth kurulumu
Realm adı = proje adı, **`-` ve `_` içeremez** (gateway env anahtarı `GATEWAY_REALMS_<REALM>_*`).

### 1. Keycloak (talay-identity, `stacks/configure`)
```hcl
module "<project>_identity" {
  source       = "../../modules/application-identity"
  keycloak_url = var.keycloak_url
  realm_name   = "<project>"
  display_name = "<Görünen Ad>"
  browser_clients = { web = { root_url = var.<project>_web_url } }   # PKCE client; gateway modelinde yedek
  realm_roles  = ["user", "admin"]
  gateway_client_enabled      = true
  gateway_admin_client_secret = lookup(var.gateway_admin_client_secrets, "<project>", null)
}
```
`access_token_lifespan` değerleri **saniye** (`"300"`). `"5m"` Keycloak'ta token üretirken 500'e yol açar (modül doğrular).

### 2. Gateway admin secret'ı (Terraform'dan önce)
```bash
export VAULT_ADDR=https://vault.cantalay.com
umask 077; f=$(mktemp); openssl rand -hex 32 | tr -d '\n' > "$f"
vault kv patch -mount=kv apps/todogi/keycloak GATEWAY_REALMS_<PROJECT>_ADMINCLIENTSECRET=@"$f"; rm -f "$f"
```

### 3. Plan / apply
Configure stack her plan/apply'da şunları ister (write-only/ephemeral; state'e girmez):
```bash
cd $TALAY_INFRA_DIR/talay-identity/stacks/configure
J=$(ssh root@152.53.66.101 "kubectl get secret -n identity keycloak-bootstrap -o jsonpath='{.data}'")   # veya Vault platform/keycloak
export KEYCLOAK_USER=$(printf '%s' "$J" | python3 -c "import json,sys,base64;print(base64.b64decode(json.load(sys.stdin)['KC_BOOTSTRAP_ADMIN_USERNAME']).decode())")
export KEYCLOAK_PASSWORD=$(printf '%s' "$J" | python3 -c "import json,sys,base64;print(base64.b64decode(json.load(sys.stdin)['KC_BOOTSTRAP_ADMIN_PASSWORD']).decode())"); unset J
export TF_VAR_vault_oidc_client_secret=unused-write-only     # sürümü değişmedikçe gönderilmez
export TF_VAR_gateway_admin_client_secrets="{$(for r in <gateway realm listesi>; do R=$(echo $r | tr a-z A-Z); printf '"%s":"%s",' $r "$(vault kv get -mount=kv -field=GATEWAY_REALMS_${R}_ADMINCLIENTSECRET apps/todogi/keycloak)"; done | sed 's/,$//')}"
terraform init -backend-config=backend.hcl && terraform plan -out=tfplan
```
Planı özetle (yalnız yeni realm kaynakları), onay → `terraform apply tfplan` (aynı shell'de, değişkenler tanımlıyken).
Değişikliği branch + PR olarak push et.

### 4. Gateway'e realm ekle (talay-environments `apps/prod/todogi/auth-gateway/values.yaml`)
- `podAnnotations.talay.io/gateway-realms`: listeye realm'i ekle (`"vitafinder,<project>"`) → rollout tetikler, yeni secret env'e girer.
- `config.CORS_ALLOWED_ORIGINS`: web origin'ini ekle.
- Gerekirse önce ExternalSecret'ı tazele: `kubectl annotate externalsecret -n gateway auth-gateway-secrets force-sync=$(date +%s) --overwrite`.

### 5. Doğrulama (geçici kullanıcıyla, sonra sil)
```bash
G=https://auth.cantalay.com/auth/<project>
curl -s -o /dev/null -w '%{http_code}' -X POST $G/register -H 'Content-Type: application/json' -d '{"email":"talay-smoke-1@example.com","password":"<güçlü>","firstName":"T","lastName":"S"}'   # 201
curl -s -X POST $G/login -H 'Content-Type: application/json' -d '{"email":"…","password":"…"}'   # access_token; aud=<project>-api
curl -H "Authorization: Bearer <token>" https://api.<project>.cantalay.com/<korumalı uç>              # 200
```
Test kullanıcılarını admin API ile sil (`DELETE /admin/realms/<project>/users/<id>`).

## Uygulama tarafı
- Web: `talay-app-standards/references/web.md` §Auth (gateway formu; referans `cantalay/vitafinder-web` `packages/shared/src/auth.ts`).
- Backend: issuer + audience ile JWT doğrula (java-spring.md / node.md). Rol kontrolü backend'de.
- Mobil: aynı gateway uçları; refresh token'ı güvenli depoda (expo-secure-store) tut.

## Rol atama
Yönetim rolleri (admin vb.) Keycloak admin konsolundan atanır (`https://auth.cantalay.com/admin/master/console/#/<project>`).

## Bilinen durumlar
- `todogi` realm'i Terraform'da değil (elle kurulmuş): login client `auth`, admin `auth-gateway-admin`, brute-force koruması kapalı.
  Gateway `/auth/*` (eski) ve `/auth/todogi/*` ikisini de sunar.
- Gateway önünde Traefik rate limit: IP başına dakikada 60 istek, burst 30.
