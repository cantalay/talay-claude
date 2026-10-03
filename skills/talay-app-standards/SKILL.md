---
name: talay-app-standards
description: Talay platformunda çalışacak uygulamayı geliştirme/uyumlama standartları — health probe'ları, Prometheus metrics, OpenTelemetry, JSON log, env/runtime config, Keycloak OIDC, DB migration, Redis, non-root/read-only Dockerfile. Yeni servis/web uygulaması yazarken veya mevcut projeyi talay'a deploy edilebilir hale getirirken kullan.
---

# talay-app-standards

Önce `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §5–§9. Stack'e göre ayrıntı:

| Stack | Referans | Dockerfile şablonu |
| --- | --- | --- |
| Java / Spring Boot | `references/java-spring.md` | `templates/docker/java-spring.Dockerfile` |
| Node API / worker | `references/node.md` | `templates/docker/node.Dockerfile` |
| React / Vite / Expo Web | `references/web.md` | `templates/docker/web-static.Dockerfile` |
| Diğer (Go, Python, .NET…) | `references/other-stacks.md` | stack'e göre uyarlanır |

## Zorunlu kontrol listesi (her backend component)

1. **Port**: `PORT`/`SERVER_PORT` env'inden, varsayılan `8080`. `0.0.0.0`'a bind.
2. **Health**: `/health/startup`, `/health/ready` (DB/Redis bağlantısı dahil), `/health/live` (yalnız process).
   Spring'de actuator karşılıkları kabul (`/actuator/health/{liveness,readiness}`), values'ta path'i ona göre yaz.
3. **Metrics**: Prometheus text endpoint (`/metrics` veya `/actuator/prometheus`); HTTP istek süresi histogramı,
   hata sayacı, iş metrikleri `<project>_` önekiyle.
4. **Tracing**: kodda OTel SDK kurma — chart agent/auto-instrumentation'ı env ile açar. Java: hiçbir şey; Node:
   `@opentelemetry/auto-instrumentations-node` **production dependency** (`^0.80` veya üstü; 0.62.x HIGH CVE nedeniyle
   image taramasında düşer). Manuel span gerekiyorsa yalnız `@opentelemetry/api`.
5. **Log**: stdout'a tek satır JSON; `level`, `time`, `msg`, `trace_id`, `span_id`; secret/PII/token loglama yok.
6. **Config**: tüm ayar env'den. Secret'lar Vault → ExternalSecret → env (PLATFORM.md §7 env adları). Varsayılan
   değerler yalnız lokal geliştirme için; prod'da eksik zorunlu env varsa process başlamadan hata versin.
7. **Auth**: Keycloak issuer `https://auth.cantalay.com/realms/<project>`, audience `<project>-api`, roller
   `realm_access.roles`. Doğrulama JWKS ile (introspection değil). Ayrıntı `talay-auth` §App entegrasyonu.
8. **DB**: migration'lar repo içinde, uygulama startup'ında (advisory lock ile tek seferde) veya ayrı komutla çalışır.
   Geriye uyumlu (expand → deploy → contract). Bağlantı havuzu küçük (tek node, paylaşımlı Postgres): max 5–10.
9. **Redis**: `REDIS_URL`'deki DB index'i kullan, tüm key'lere `REDIS_KEY_PREFIX` (`<project>:`) ekle, TTL ver.
10. **Shutdown**: SIGTERM'de yeni istek almayı bırak, açık işleri bitir, ≤30 sn'de çık (chart grace period 45 sn).
11. **Dosya sistemi**: root FS read-only; yalnız `/tmp` yazılabilir. Upload/kalıcı dosya gerekiyorsa kullanıcıya söyle
    (PVC/object storage kararı gerekir).
12. **Container**: multi-stage, non-root UID, pinned base image, `EXPOSE 8080`, `.dockerignore`, HEALTHCHECK yok (k8s probe'ları var).
    Alpine tabanlı final stage'de `apk upgrade --no-cache --available`. Trivy "fixed" sürümü olan bir OS paketini
    bildirirken lokal build temizse sebep CI'daki GHA cache'inin eski `apk upgrade` katmanıdır: o RUN satırını değiştir.
13. **CORS**: izinli origin'ler env (`CORS_ORIGINS`) ile, `*` yok.
14. **Worker**: HTTP health + metrics sunucusu yine açılır (probe ve ServiceMonitor için), ingress yok.

## Web component kontrol listesi
1. Statik build → nginx (talay-web). SPA routing `try_files … /index.html`.
2. Ortam bağımlı ayarlar **runtime**'da `window.__TALAY_CONFIG__`'ten okunur (build-time env yalnız lokal fallback).
3. `public/runtime-config.js` → `window.__TALAY_CONFIG__ = {};` (lokal için boş placeholder).
4. Auth: uygulamanın kendi login/kayıt formu → auth-gateway `https://auth.cantalay.com/auth/<project>/*` (Keycloak sayfası
   gösterilmez); token'ı API'ye `Authorization: Bearer`.
5. Hash'li asset'ler `/assets/` altında (Vite varsayılanı) — nginx immutable cache verir.

## Lokal doğrulama (deploy öncesi)
- Testler + lint + build geçer.
- `docker build -t local/<name> .` ve `docker run --read-only --tmpfs /tmp -p 8080:8080 -e … local/<name>` ile
  health endpoint'leri 200 döner, container non-root (`docker run … id`).
