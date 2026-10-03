---
name: talay-secrets
description: Talay'da uygulama secret'larını Vault (vault.cantalay.com, KV v2 mount kv) üzerinden yönetir ve External Secrets ile pod env'ine bağlar — path sözleşmesi, güvenli yazma, ExternalSecret durumu, rotasyon. "secret ekle", "API key", "vault", "env değişkeni gizli", "ExternalSecret" isteklerinde kullan.
---

# talay-secrets

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §6.

## Giriş
```bash
export VAULT_ADDR=https://vault.cantalay.com
vault token lookup >/dev/null 2>&1 || vault login -method=oidc   # tarayıcıda Keycloak girişi (kullanıcı yapar)
```

## Path sözleşmesi
- `kv/apps/<project>/<component>` — component'in bütün runtime secret'ları. Chart `externalSecret.remoteKey` ile
  **tek** path okur ve tüm key'leri env'e açar (`dataFrom.extract`), bu yüzden key adları = env adları (UPPER_SNAKE).
- Ortak secret (ör. iki component aynı SMTP parolasını kullanıyor) → her iki path'e de yaz.
- `platform/*` path'lerine uygulama için yazma.

## Yazma (değer asla sohbete/terminale düşmesin)
Tercih sırası:
1. **Kullanıcı kendisi yazar** — ona komutu ver:
   `vault kv patch -mount=kv apps/<project>/<component> STRIPE_API_KEY=-` (değeri stdin'den ister, history'ye düşmez).
   Path henüz yoksa `patch` yerine `put` (dikkat: `put` mevcut key'leri siler; önce `vault kv get` ile kontrol et).
2. Üretilebilir secret'lar (JWT signing key, webhook secret, rastgele parola) → Claude üretir, mode 600 temp dosyaya yazar:
   ```bash
   umask 077; f=$(mktemp); openssl rand -base64 48 | tr -d '\n' > "$f"
   vault kv patch -mount=kv apps/<project>/<component> SESSION_SECRET=@"$f"; rm -f "$f"
   ```
3. DB/Redis bilgileri → `talay-database` script'i yazar.

Her yazmadan önce path + key adlarını kullanıcıya göster, onay al. Mevcut key'leri listelemek için yalnız
`vault kv get -mount=kv -format=json <path> | jq '.data.data | keys'` (değerleri değil).

## Bağlama (talay-environments values.yaml)
```yaml
externalSecret:
  enabled: true
  remoteKey: apps/<project>/<component>
  targetName: <fullname>-secrets
registrySecret:
  enabled: true            # private GHCR image'ları için
  remoteKey: platform/registry/ghcr
  targetName: ghcr-pull
```
Web (talay-web) secret almaz; tarayıcıya giden her şey zaten herkese açıktır → `runtimeConfig`.

## Durum / rotasyon
- `ssh root@45.87.80.10 kubectl get externalsecret -n <ns>` → `SecretSynced True`. `refreshInterval: 1h`; anında
  çekmek için: `kubectl annotate externalsecret <name> -n <ns> force-sync=$(date +%s) --overwrite` (canlı değişiklik → onay).
- Env'ler pod başlangıcında okunur: secret değişince rollout gerekir (`kubectl rollout restart deploy/<name> -n <ns>`, onayla).
- Hata `SecretSyncedError` → path/key yanlış veya Vault sealed (`talay-status` §Vault).
