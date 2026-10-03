---
name: talay-auth
description: Keycloak'ı (auth.cantalay.com) uygulamalara servis olarak sunar — proje realm'i, public PKCE web/mobil client'ları, bearer-only API client'ı, realm rolleri talay-identity Terraform'u ile kod olarak; ve uygulama tarafında JWT doğrulama/rol kontrolü ile web login entegrasyonu. "login ekle", "auth", "keycloak", "rol", "kullanıcı girişi", "SSO", "client oluştur" isteklerinde kullan.
---

# talay-auth

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §8. Repo: `$TALAY_INFRA_DIR/talay-identity`.

## Keycloak tarafı (Terraform, `stacks/configure`)
Modül: `modules/application-identity`. Girdiler:

| Değişken | Anlam |
| --- | --- |
| `realm_name` | proje adı (`<project>`) |
| `display_name` | Login ekranı başlığı |
| `browser_clients` | `map(object({ name, root_url, access_token_lifespan?, extra_redirect_uris? }))` — key → client id `<realm>-<key>` |
| `api_client_enabled` | `<realm>-api` bearer-only client + browser client'lara audience mapper (varsayılan true) |
| `realm_roles` | set(string); `default_role` bunun içinde olmalı |
| `default_role` | yeni kayıtlara otomatik rol (varsayılan `user`) |
| `registration_allowed` | self-registration (varsayılan true) |

### Yeni proje ekleme
1. `stacks/configure/main.tf`'e `module "<project>_identity"` bloğu ekle (vitafinder bloğunu örnek al), URL değişkenlerini
   `variables.tf` + `terraform.tfvars.example`'a ekle; gerçek `terraform.tfvars` git'e girmez (gitignore).
2. `outputs.tf`'e `<project>_clients` output'u ekle (isteğe bağlı).
3. Terraform çalıştırma ön koşulları (`talay-infra-change` skill'i): kubeconfig (state cluster'da),
   `KEYCLOAK_USER`/`KEYCLOAK_PASSWORD` (Vault `platform/keycloak`):
   ```bash
   export KEYCLOAK_USER=$(vault kv get -mount=kv -field=username platform/keycloak)
   export KEYCLOAK_PASSWORD=$(vault kv get -mount=kv -field=password platform/keycloak)
   cd $TALAY_INFRA_DIR/talay-identity/stacks/configure
   terraform init -backend-config=backend.hcl && terraform plan -out=tfplan
   ```
4. Plan'ı kullanıcıya özetle (yalnız yeni realm kaynakları eklenmeli, mevcutlarda değişiklik **olmamalı**). Onay → `terraform apply tfplan`.
5. Değişiklikleri branch + PR olarak talay-identity'ye push et (kullanıcı onayıyla).
6. Doğrula: `curl -fsS https://auth.cantalay.com/realms/<project>/.well-known/openid-configuration | jq .issuer`.

### Rol atama
Yönetim rolleri (admin vb.) Terraform ile **kullanıcıya atanmaz**; operatör Keycloak admin konsolundan atar
(`https://auth.cantalay.com/admin/master/console/#/<project>`). İlk admin kullanıcısını kullanıcıya hatırlat.

## Uygulama tarafı
| | Değer |
| --- | --- |
| Issuer | `https://auth.cantalay.com/realms/<project>` |
| JWKS | `<issuer>/protocol/openid-connect/certs` |
| Audience | `<project>-api` |
| Roller | access token `realm_access.roles` |
| Web client | `<project>-<key>` (public, PKCE S256, redirect `https://<host>/*`) |

- Backend env (config, secret değil): Java `KEYCLOAK_ISSUER_URI`, `KEYCLOAK_AUDIENCE`; Node `KEYCLOAK_ISSUER_URL`, `KEYCLOAK_AUDIENCE`.
- Kod: `talay-app-standards/references/{java-spring,node,web}.md`.
- Backend'in Keycloak admin API'sini çağırması gerekiyorsa (kullanıcı yönetimi): ayrı confidential client + service account
  gerekir; modülde yok → kullanıcıya sor, modüle ekle, client secret'ı Terraform output yerine Keycloak'ta üretip
  Vault `apps/<project>/<component>`'e elle yaz.

## Legacy notu
todogi `auth-gateway` (auth.cantalay.com/auth/*) eski bir gateway'dir; yeni projeler doğrudan Keycloak OIDC kullanır.
