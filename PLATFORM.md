# Talay Platform Sözleşmesi

Bu dosya talay platformunun **tek doğruluk kaynağıdır**. Her `talay-*` skill'i buna göre çalışır.
Burada yazan bir değer ile canlı cluster çelişirse canlı durumu esas al, sonra bu dosyayı güncelle.

Son doğrulama: 2026-10-03 (canlı cluster + repolar; auth-gateway çok-realm geçişi sonrası).

## 1. Topoloji

| Öğe | Değer |
| --- | --- |
| Sunucu | `srv468915`, public IP `45.87.80.10`, Ubuntu 24.04, tek node |
| Kubernetes | K3s `v1.36.4+k3s1`, K3s'in kendi Traefik'i kapalı |
| Kapasite | 2 vCPU, 7.8Gi RAM, swap yok. 2026-10-03: CPU request %54, RAM kullanım ~%75 → **her yeni workload'dan önce kapasite kontrolü** |
| Erişim | `ssh root@45.87.80.10` (SSH key ile). Lokal `~/.kube/config` **eski cluster'a ait, kullanma** |
| Storage | `local-path` (tek disk; PVC'ler sunucu kaybına karşı dayanıklı değil) |

Kubectl her zaman SSH üzerinden: `ssh root@45.87.80.10 'kubectl …'`. Komut değişkeni: `TALAY_KUBECTL="ssh root@45.87.80.10 kubectl"`.

## 2. Repolar

Çalışma alanı: `TALAY_INFRA_DIR` (varsayılan `~/Documents/infra-lts`). Hepsi `github.com/cantalay/<repo>`, `main`.

| Repo | Ne yapar | Ne zaman dokunulur |
| --- | --- | --- |
| `talay-cluster` | K3s kurulum (bootstrap, local state) + namespace/priority class (base) | Neredeyse hiç |
| `talay-network` | Traefik `41.4.0`, cert-manager `v1.21.1`, `ClusterIssuer/letsencrypt`, ExternalDNS (kapalı) | Nadiren |
| `talay-data` | PostgreSQL (bitnami 18.8.16) + Redis (bitnami 28.0.14), ns `data` | Yeni app DB'si → `scripts/provision-app-database.sh` |
| `talay-secrets` | Vault + External Secrets Operator, `ClusterSecretStore/vault` | Nadiren |
| `talay-identity` | Keycloak kurulum (install) + realm/client/rol (configure) | **Yeni app auth'u** → `stacks/configure/main.tf` |
| `talay-observability` | Prometheus, Alertmanager, Loki, Alloy, Tempo, OTel Collector, Grafana | Nadiren (app dashboard'ları env repoda) |
| `talay-gitops` | Argo CD + root `ApplicationSet/talay-applications` | Neredeyse hiç |
| `talay-environments` | **Uygulama desired state** (values, ingress, cert, nginx, dashboard) | **Her deploy** |
| `talay-helm-charts` | `talay-service`, `talay-web`, `talay-common` chartları | Chart özelliği eksikse |
| `talay-workflows` | Reusable GitHub Actions (java/node/web/expo/helm/terraform/promote) | Nadiren |

Terraform state: `talay-cluster/stacks/bootstrap` hariç hepsi cluster içinde `terraform-states` namespace'inde
(Kubernetes backend). Terraform çalıştırmak için geçerli kubeconfig gerekir (bkz. `talay-infra-change`).

## 3. Uygulama teslimat akışı

```
app repo (main push)
  └─ .github/workflows/*.yml → cantalay/talay-workflows/.github/workflows/{java,node,web}.yaml@<SHA>
       └─ test + Trivy + build → ghcr.io/cantalay/<image>:sha-<7 hane commit>
talay-environments (PR/commit: values.yaml image.tag)
  └─ apps/<env>/<project>/<component>/application.yaml
       └─ ApplicationSet talay-applications (ns gitops) → Application "<name>-<env>"
            ├─ chart: talay-helm-charts/<chartPath> @ main + valuesFile
            └─ kustomize: <manifestsPath> (certificate, ingress, nginx ConfigMap, dashboard…)
  └─ Argo CD automated sync (prune + selfHeal, CreateNamespace)
```

- Workflow pin'i: `cantalay/talay-workflows/.github/workflows/<x>.yaml@107e3e43dee30ea1b4874c7bc150f90769b55efc`
  (talay-workflows'ta yeni commit varsa `git -C $TALAY_INFRA_DIR/talay-workflows rev-parse HEAD` ile güncelle).
- Image tag: `sha-<git rev-parse --short=7 HEAD>`. `latest` **yasak**. İsteğe bağlı `image.digest` (sha256) tercih edilir.
- Argo Application adı: `<application.yaml name>-<environment>` (ör. `todogi-backend-prod`).

## 4. talay-environments component sözleşmesi

```
apps/prod/<project>/<component>/
  application.yaml      # name, environment, namespace, chartPath, valuesFile, manifestsPath
  values.yaml           # chart değerleri
  kustomization.yaml    # resources: certificate/…, ingress/…, (dashboard/…), configMapGenerator (nginx)
  certificate/certificate.yaml
  ingress/ingress.yaml
  nginx/default.conf    # yalnız web
  dashboard/…           # opsiyonel Grafana dashboard ConfigMap
```

`schema/app.schema.json`: `name`/`namespace` DNS-1123, `environment ∈ {dev,stage,prod}`,
`chartPath ∈ {charts/talay-service, charts/talay-web}`, `manifestsPath` = application.yaml'ın dizini.

Konvansiyonlar (mevcut app'lerden):
- Namespace: component başına bir namespace, `<project>-<component>` (ör. `vitafinder-api`). İstisna: todogi (`todogi-be`, `todogi-app`, `gateway`).
- `fullnameOverride` = namespace adı ile aynı tutulur → Service DNS: `<fullname>.<ns>.svc.cluster.local:80`.
- `partOf: <project>`; label'lar: `app.kubernetes.io/name: <app name>`, `app.kubernetes.io/part-of: <project>`, `talay.io/environment: prod`.
- Ingress ve Certificate **chart ile değil**, component dizinindeki açık manifestlerle (`ingressClassName: traefik`,
  `ClusterIssuer letsencrypt`, secret `<name>-tls`). Chart'ta `ingress.enabled: false` kalır.
- Service portu 80 → containerPort (varsayılan 8080).

## 5. Chart'lar

### talay-service (Java/Spring veya Node API/worker)
Önemli değerler: `image.{repository,tag,digest}`, `registrySecret.enabled: true` (private GHCR),
`runtime.type: java|node`, `runtime.java.agent.enabled` (OTel Java agent 2.31.1 init container),
`runtime.node.autoInstrumentation.enabled` (`NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register`
→ paket **production dependency** olmalı), `containerPort`, `config` (ConfigMap → envFrom),
`externalSecret.{enabled,remoteKey,targetName}` (**tek** Vault path; `dataFrom.extract` → tüm key'ler env olur),
`observability.{serviceName,samplingRatio}`, `probes.{startup,readiness,liveness}.path`,
`serviceMonitor.{enabled,path}`, `resources`, `networkPolicy.egress`.

Chart'ın pod'a verdiği env: `POD_NAME`, `POD_NAMESPACE`, `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_TRACES_EXPORTER=otlp`, `OTEL_METRICS_EXPORTER=otlp`,
`OTEL_LOGS_EXPORTER=none`, `OTEL_TRACES_SAMPLER=parentbased_traceidratio`, `OTEL_TRACES_SAMPLER_ARG`,
`OTEL_RESOURCE_ATTRIBUTES`, (java) `JAVA_TOOL_OPTIONS`, (node) `NODE_OPTIONS`.

Güvenlik varsayılanları: non-root, `readOnlyRootFilesystem: true` (yazılabilir yalnız `/tmp` emptyDir),
drop ALL caps, seccomp RuntimeDefault, SA token automount kapalı. NetworkPolicy: ingress yalnız aynı namespace,
`ingress-system` ve `monitoring`'den. Egress varsayılan açık.

### talay-web (React/Vite/Expo Web statik)
nginx-unprivileged, port 8080, `/healthz`. `runtimeConfig` → `/runtime-config.js` içinde
`window.__TALAY_CONFIG__ = {…}` (index.html'e nginx sub_filter ile enjekte). Build-time env yerine **runtime config** kullan
(aynı image her ortamda çalışır). Özel nginx: env repoda `nginx/default.conf` + `configMapGenerator` +
`nginx.existingConfigMap` + `nginx.configRevision` (içerik değişince artır).

## 6. Secrets (Vault)

- Adres: `https://vault.cantalay.com`, KV v2 mount `kv`. CLI girişi: `vault login -method=oidc` (Keycloak, `platform-admin` rolü).
- ESO: `ClusterSecretStore/vault`, `kv/data/*` okur.
- Path konvansiyonu:
  - `platform/postgresql` (`postgres-password`, `password`), `platform/redis` (`redis-password`),
    `platform/keycloak` (`username`, `password`), `platform/grafana`, `platform/alertmanager`
  - `platform/registry/ghcr` (`.dockerconfigjson`) → her namespace'te `ghcr-pull`
  - **`apps/<project>/<component>`** → o component'in **tüm** runtime secret'ları (DB, Redis, harici API key'ler).
    Birden çok component aynı secret'a ihtiyaç duyuyorsa her birinin path'ine yazılır.
- Secret değerleri asla Git'e, values'a, tfvars'a, terminal çıktısına yazılmaz. Vault'a yazarken `key=@dosya` (mode 600 temp dosya) kullan.

## 7. Veri (PostgreSQL / Redis)

| | PostgreSQL 18 (bitnami) | Redis (bitnami, standalone) |
| --- | --- | --- |
| Servis | `postgresql.data.svc.cluster.local:5432` | `redis-master.data.svc.cluster.local:6379` |
| Pod | `postgresql-0` (admin parola dosyası `/opt/bitnami/postgresql/secrets/postgres-password`) | `redis-master-0` |
| Model | **App başına database + owner role** | Paylaşımlı instance, tek parola; app başına **DB index** + key prefix `<project>:` |
| Provision | `talay-data/scripts/provision-app-database.sh` | aynı script `--redis-db N` |
| Yedek | günlük `pg_dumpall` CronJob (aynı disk; off-site değil) | yok |

Tablolar/şema **uygulamanın migration'ı** ile oluşur (Java: Flyway; Node: SQL migration runner). Platform şema yönetmez.
Redis DB index tahsis tablosu: `talay-data/README.md`.

Uygulamaya giden env sözleşmesi (Vault `apps/<project>/<component>`):
`DATABASE_URL` (postgresql://…?sslmode=disable), `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`SPRING_DATASOURCE_URL` (jdbc:postgresql://…), `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`,
opsiyonel `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB`, `REDIS_PASSWORD`, `REDIS_KEY_PREFIX`.

## 8. Kimlik (Keycloak as a service, auth-gateway üzerinden)

- **Kullanıcı Keycloak sayfası görmez.** Uygulamalar kendi login/kayıt formundan **auth-gateway**'e konuşur:
  `https://auth.cantalay.com/auth/<realm>/{login,register,refresh,logout,me,change-password,social}`
  (kod: `github.com/cantalay/auth-gateway`, deploy: talay-environments `apps/prod/todogi/auth-gateway`, ns `gateway`).
  Eski `/auth/*` yolları varsayılan realm `todogi`'ye gider.
- Keycloak `https://auth.cantalay.com/realms/*` (gateway yalnız `/auth` path'ini alır). Realm başına proje; realm adı = proje adı,
  **tire/alt çizgi yok**.
- Token: `iss=https://auth.cantalay.com/realms/<realm>`, `aud=<realm>-api`, `azp=<realm>-gateway`, roller `realm_access.roles`;
  JWKS `<iss>/protocol/openid-connect/certs`. API'ler token'ı kendisi doğrular.
- Kod olarak: `talay-identity/stacks/configure/main.tf` → `module "<project>_identity"` (`modules/application-identity`):
  realm, roller (yeni kayıtlara `user`), bearer-only `<realm>-api`, `gateway_client_enabled = true` ile
  `<realm>-gateway` (public, direct grant, API audience) ve `<realm>-gateway-admin` (manage/query/view-users service account).
  Client `access_token_lifespan` **saniye** (`"300"`).
- Gateway realm secret'ı: Vault `kv/apps/todogi/keycloak` → `GATEWAY_REALMS_<REALM>_ADMINCLIENTSECRET`; Terraform'a write-only
  `TF_VAR_gateway_admin_client_secrets` ile verilir (her plan/apply). Gateway'e realm ekleme: values
  `podAnnotations.talay.io/gateway-realms` + `CORS_ALLOWED_ORIGINS`.
- Terraform configure çalıştırma: `KEYCLOAK_USER/PASSWORD` (`identity/keycloak-bootstrap` secret'ı veya Vault `platform/keycloak`),
  `TF_VAR_vault_oidc_client_secret` (sürüm değişmedikçe herhangi bir değer), `TF_VAR_gateway_admin_client_secrets`.
- Gateway önünde Traefik rate limit (IP başına 60/dk, burst 30). Gateway logları parola/token/secret alanlarını maskeler.
- Platform realm'i `monitoring` (Argo CD/Vault/Grafana OIDC) ayrıdır; uygulamalar ona dokunmaz.

## 9. Gözlemlenebilirlik

```
App --OTLP http--> otel-collector.monitoring:4318 --traces--> Tempo
                                                   --metrics--> Prometheus
App stdout/stderr --> Alloy --> Loki
Prometheus --scrape ServiceMonitor--> App /metrics | /actuator/prometheus
Grafana https://grafana.cantalay.com (datasource uid: prometheus, loki, tempo)
```

- Log formatı: stdout'a tek satır JSON, `trace_id`/`span_id` alanlarıyla (Loki→Tempo derived field regex `trace[_-]?id`).
- Dashboard: env repoda ConfigMap, label `grafana_dashboard: "1"` (sidecar tüm namespace'leri tarar).
- Alarm: `PrometheusRule` (kube-prometheus-stack), env repoda.
- Tempo tag'leri: `service.name`, `k8s.namespace.name`.

## 10. Ağ / DNS / TLS

- ExternalDNS **kapalı** → yeni host için DNS sağlayıcısında elle `A <host> 45.87.80.10`. `dig +short <host>` doğrulanmadan
  deploy edilirse cert-manager HTTP-01 başarısız olur.
- Mevcut alan adları: `cantalay.com` (platform + vitafinder), `singlestranger.com` (todogi).
- Platform host'ları: `vault.cantalay.com`, `auth.cantalay.com`, `grafana.cantalay.com`, `argocd.cantalay.com`, `traefik.cantalay.com`.

## 11. Canlı envanter (2026-10-03)

| Argo app | Namespace | Host | Image |
| --- | --- | --- | --- |
| `todogi-web-prod` | todogi-app | todogi.singlestranger.com (+www) | ghcr.io/cantalay/todogi-app |
| `todogi-backend-prod` | todogi-be | api.singlestranger.com/api (+www) | ghcr.io/cantalay/todogi-api |
| `auth-gateway-prod` | gateway | auth.cantalay.com/auth (realm'ler: todogi, hello) | ghcr.io/cantalay/todogi-auth-gateway |
| `vitafinder-storefront-prod` | vitafinder-storefront | vitafinder.cantalay.com | ghcr.io/cantalay/vitafinder-web |
| `vitafinder-admin-prod` | vitafinder-admin | admin.vitafinder.cantalay.com | ghcr.io/cantalay/vitafinder-web |
| `vitafinder-api-prod` | vitafinder-api | api.vitafinder.cantalay.com | ghcr.io/cantalay/vitafinder-core |
| `vitafinder-worker-prod` | vitafinder-worker | — | ghcr.io/cantalay/vitafinder-core |
| `hello-api-prod` | hello-api | api.hello.cantalay.com | ghcr.io/cantalay/talay-hello-api (prova; repo cantalay/talay-hello) |
| `hello-web-prod` | hello-web | hello.cantalay.com | ghcr.io/cantalay/talay-hello-web (prova) |

Veri: `vitafinder` DB'si + Redis index 1 (api, worker), `hello` DB'si (api) provision edildi; Vault `apps/<project>/<component>`.

Bilinen açıklar (2026-10-03):
- VitaFinder kodu henüz `DATABASE_URL`/`REDIS_URL` okumuyor ve migration runner'ı yok; web'i hâlâ Keycloak yönlendirmeli
  OIDC kullanıyor (gateway'e geçirilmedi; vitafinder realm'inde gateway client'ı yok).
- `todogi` realm'i Terraform'da değil, brute-force koruması kapalı. todogi-app'teki Google/Apple girişi mock; forgot/reset
  password ve avatar uçları gateway'de yok.
- Vault pod'u `OnDelete` stratejisinde: CPU request düşüşü (100m→50m) pod yeniden oluşturulunca geçerli olur; yeniden
  başlarsa unseal gerekir.

## 12. Değişmez kurallar

1. Secret'lar yalnız Vault'ta. Git'te yalnız path referansı.
2. `latest` tag yok; immutable `sha-<7>` (+ tercihen digest).
3. Prod'a yazan her adım (Vault yazma, DB oluşturma, Keycloak apply, env repo push) **kullanıcı onayıyla**.
4. Canlı cluster'a `kubectl apply/edit/delete` yok — değişiklik Git üzerinden (Argo selfHeal geri alır zaten).
5. Kapasite: requests toplamı node allocatable'ın %85'ini geçmesin; aşıyorsa kullanıcıya söyle.
6. Her yeni workload: health probe'lar, metrics endpoint, OTel, JSON log, non-root, read-only rootfs.
