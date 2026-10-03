---
name: talay-ship
description: Bir projeyi (analiz/isterlerden ya da mevcut repodan) Talay platformuna uygun geliştirip uçtan uca prod'a çıkarır — Vault secret'ları, PostgreSQL/Redis provisioning ve migration, Keycloak realm/client/rol, OTel/metrics/log, CI, DNS/TLS, Argo CD deploy ve doğrulama. "deploy et", "yayına al", "prod'a çıkar", "talay'a deploy", "bu projeyi platforma ekle", "yeni proje başlat ve deploy et" gibi isteklerde kullan.
---

# talay-ship — uçtan uca golden path

Plugin kökü: `${CLAUDE_PLUGIN_ROOT}` (bu dosyanın iki üst dizini). Önce `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` dosyasını
**tamamen oku**; bütün değerler ve kurallar orada. Altyapı repoları: `${TALAY_INFRA_DIR:-$HOME/Documents/infra-lts}`.

Teknoloji bağımsızdır: Java/Spring, Node (Express/Fastify/Nest), React/Vite, Expo Web desteklenir. Bunlar dışındaki
bir stack (Go, Python, .NET…) için `talay-app-standards/references/other-stacks.md`'ye bak.

## Faz 0 — Ön kontrol
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` çalıştır. Eksik araç/erişim varsa kullanıcıya söyle; Vault girişi
gerekiyorsa provisioning fazına kadar ertele. `git -C $TALAY_INFRA_DIR/<repo> pull --ff-only` ile 10 talay reposunu güncelle.

## Faz 1 — Analiz
Girdi: kullanıcının proje analizi/isterleri ve (varsa) app repo(ları). Çıkar:
- Bileşenler: `api` (talay-service), `worker` (talay-service, ingress yok), `web` (talay-web), mobil (Expo EAS, k8s'e gitmez).
- Stack, build aracı, paket yöneticisi, monorepo mu.
- Veri: PostgreSQL gerekli mi, Redis gerekli mi (cache/queue/session), hangi component'ler erişiyor.
- Auth: kim giriş yapıyor, roller neler, hangi endpoint hangi rolü istiyor, self-registration açık mı.
- Harici secret'lar (SMTP, ödeme, 3. parti API key'ler).
- Domain(ler). Varsayılan öneri: web `<project>.cantalay.com`, api `api.<project>.cantalay.com`, admin `admin.<project>.cantalay.com`.
- Kaynak tahmini (requests/limits) — tek node kapasitesi kısıtlı.

Belirsiz kalan **iş kararlarını** (domain, roller, self-registration, hangi component'ler) tek seferde AskUserQuestion ile sor.

## Faz 2 — Deploy manifestosu (`talay.yaml`)
App reposunun köküne (monorepo değilse ana repoya) `talay.yaml` yaz; format: `${CLAUDE_PLUGIN_ROOT}/templates/talay.yaml`.
Bu dosya sonraki fazların **tek girdisi**dir ve repo ile birlikte commit edilir (secret değeri içermez).
Kullanıcıya özetle göster ve onay al.

## Faz 3 — Geliştirme / uyumlama
`talay-app-standards` skill'ini uygula. Yeni projede isterleri bu standartlarla geliştir; mevcut projede eksikleri tamamla:
health endpoint'leri, metrics, OTel, JSON log, env ile config, OIDC (talay-auth §App entegrasyonu), migration
(talay-database §Migration), Dockerfile, `.dockerignore`. Lokal test + build + `docker build` geçmeli.

## Faz 4 — CI ve image
`talay-ci` skill'i: caller workflow ekle, commit + push (kullanıcı onayı), `gh run watch` ile bekle, image tag'ini
(`sha-<7>`) ve digest'i al. CI kırmızıysa düzelt ve tekrarla.

## Faz 5 — Provisioning (her adım öncesi onay)
Sıra önemlidir:
1. **DB/Redis** → `talay-database` (Vault `apps/<project>/<component>` içine DB/Redis env'leri yazılır).
2. **Kimlik** → `talay-auth` (Keycloak realm/client/rol, Terraform plan → onay → apply).
3. **Diğer secret'lar** → `talay-secrets` (kullanıcıdan değerleri güvenli yolla iste; asla sohbete yazdırma —
   `vault kv patch` komutunu kullanıcının kendisi çalıştırabilir).

## Faz 6 — DNS
Her host için `dig +short <host>` → `45.87.80.10` değilse kullanıcıya eklemesi gereken A kayıtlarını listele ve bekle.
Doğrulanmadan Faz 7'ye geçme.

## Faz 7 — Deploy
`talay-deploy` skill'i: kapasite kontrolü (`scripts/capacity.sh`), talay-environments component dizinleri,
dashboard/alarmlar (`talay-observability`), `scripts/verify-environments.sh`, commit + push (onay), Argo sync ve doğrulama.

## Faz 8 — Doğrulama ve teslim
- Argo `Synced/Healthy`, Certificate `Ready`, ExternalSecret `SecretSynced`, pod `Running` restart'sız.
- `curl -fsS https://<host>/<health>` 200; web için index + `/runtime-config.js`.
- Auth: `https://auth.cantalay.com/realms/<project>/.well-known/openid-configuration` 200; korumalı endpoint token'sız 401.
- Gözlem: Tempo'da `service.name=<svc>` trace'i, Prometheus'ta `up{namespace="<ns>"}==1`, Loki'de `{namespace="<ns>"}` log
  (`talay-observability` §Doğrulama sorguları).
- Kullanıcıya özet: URL'ler, Argo app'leri, Vault path'leri, Keycloak client'ları, Grafana dashboard linki,
  yapılmayan/ertelenen adımlar.

## Güncelleme (mevcut, zaten deploy edilmiş proje)
Kod değişti → Faz 3 (gerekirse) → Faz 4 → `talay-deploy` §Yeni sürüm (yalnız tag/digest güncelle). Yeni secret/rol/DB
gerektiyse ilgili Faz 5 adımı. `talay.yaml`'ı güncel tut.

## Geri alma
Önceki `image.tag`/`digest`'e dönen commit (talay-environments) → Argo uygular. Migration'lar geriye uyumlu (expand/contract)
yazıldığı için image rollback güvenlidir; değilse kullanıcıyı uyar.

## Kurallar
- Prod'a yazan her adımdan önce ne yapılacağını göster, onay al (PLATFORM.md §12).
- Canlıya `kubectl apply` yok; her şey Git + Terraform + script üzerinden.
- Bir faz başarısızsa durma noktası ve sebebi net söyle; sonraki faza geçme.
