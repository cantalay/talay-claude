---
name: talay-observability
description: Talay'da uygulama gözlemlenebilirliği — OTel trace/metric (otel-collector → Tempo/Prometheus), ServiceMonitor scrape, Alloy→Loki log, Grafana dashboard ConfigMap'i ve PrometheusRule alarmları; deploy sonrası sinyallerin geldiğini doğrulama ve sorgu örnekleri. "metrik", "dashboard", "grafana", "trace", "log", "alarm", "neden yavaş" isteklerinde kullan.
---

# talay-observability

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §9. Şablonlar: `${CLAUDE_PLUGIN_ROOT}/templates/observability/`.

## Uygulama tarafı
Chart halleder: OTEL env'leri, Java agent/Node auto-instrumentation, ServiceMonitor (`serviceMonitor.path`).
Uygulama sağlar: metrics endpoint, JSON log + trace_id, anlamlı `observability.serviceName` (= fullname),
`samplingRatio` (API 0.25, worker 0.10, düşük trafik 1.0).

## Dashboard
1. `templates/observability/dashboard.json`'ı kopyala; `__SERVICE__` (OTEL service.name), `__NAMESPACE__`, `__TITLE__` doldur.
   Panel'ler: istek hızı, hata oranı, p95 süre (OTel `http_server_request_duration_seconds` — agent/auto-instr. metriği
   otel-collector üzerinden Prometheus'a gelir), pod CPU/bellek, restart, log hacmi (Loki), son hatalı trace'ler (Tempo).
2. Component dizininde `dashboard/dashboard.json` + kustomization:
   ```yaml
   configMapGenerator:
     - name: <fullname>-dashboard
       files: [<project>-<component>.json=dashboard/dashboard.json]
       options:
         labels: { grafana_dashboard: "1" }
         annotations: { grafana_folder: <project> }
   ```
   (`generatorOptions.disableNameSuffixHash: true` zaten varsa tekrar ekleme.) Grafana sidecar tüm namespace'leri tarar.
3. Bir projeye tek dashboard yeter; en çok kullanılan component'e (genelde api) koy.

## Alarmlar
`templates/observability/prometheusrule.yaml` → component dizininde `alerts/prometheusrule.yaml`, kustomization'a ekle.
Varsayılanlar: pod down (up==0 5 dk), crashloop (restart artışı), 5xx oranı >%5 10 dk, p95 > 1 sn 10 dk.
Alertmanager config'i Vault `platform/alertmanager`'da (alıcılar oradan); app'e özel route gerekiyorsa kullanıcıya söyle.

## Doğrulama sorguları (deploy sonrası)
Kubernetes API server service proxy'si ile (exec gerekmez; Grafana image'ında shell yok):
```bash
R='ssh root@45.87.80.10 kubectl get --raw /api/v1/namespaces/monitoring/services'
# ServiceMonitor scrape (1 = ayakta)
$R'/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=up%7Bnamespace%3D%22<ns>%22%7D'
# OTel metrikleri (otel-collector → Prometheus; etiketler: k8s_namespace_name, exported_job="<ns>/<svc>")
$R'/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=sum(rate(http_server_request_duration_seconds_count%7Bk8s_namespace_name%3D%22<ns>%22%7D%5B5m%5D))'
# Tempo trace araması
$R'/tempo:3200/proxy/api/search?tags=service.name%3D<svc>&limit=5'
# Loki (etiketler: namespace, app, container, pod, service_name)
$R'/loki-gateway:80/proxy/loki/api/v1/query_range?query=%7Bnamespace%3D%22<ns>%22%7D&limit=5'
```
Metrik adlarını tahmin etme; önce `…/proxy/api/v1/label/__name__/values` ile bak. Görsel inceleme için
`https://grafana.cantalay.com/explore`.

Mevcut OTel metrikleri (2026-10-03): `http_server_request_duration_seconds_{bucket,count,sum}`
(etiketler `http_route`, `http_request_method`, `http_response_status_code`), `http_server_active_requests`,
`db_client_connections_*`, JVM metrikleri (Java agent).

## Sorun → bakılacak yer
| Belirti | Kontrol |
| --- | --- |
| Trace yok | Pod env'inde `OTEL_*` var mı; Node'da auto-instrumentations paketi runtime'da mı (`Cannot find module` log'u); otel-collector log'u |
| Metrik yok | ServiceMonitor path doğru mu; NetworkPolicy monitoring'e açık (chart açar); endpoint 200 mü |
| Log trace'e bağlanmıyor | Log JSON'da `trace_id` alanı var mı |
