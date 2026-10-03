# Java/Node/Web dışındaki stack'ler

Platform chart'ları stack'ten bağımsızdır; `talay-service` herhangi bir HTTP container'ı çalıştırır. Fark yalnız
OTel enjeksiyonunda ve CI workflow'undadır.

| Konu | Yaklaşım |
| --- | --- |
| Chart | `talay-service`, `runtime.type: node` seç ama `runtime.node.autoInstrumentation.enabled: false` (NODE_OPTIONS eklenmez). Java agent da kapalı. |
| OTel | Chart `OTEL_*` env'lerini yine verir; uygulama dilin OTel SDK'sını env'den yapılandırır (Go: `otelhttp` + `autoexport`; Python: `opentelemetry-instrument` wrapper'ı Dockerfile CMD'de; .NET: `OpenTelemetry.Extensions.Hosting` + OTLP exporter). |
| Metrics | Dilin Prometheus client'ı, `/metrics`. |
| Log | JSON stdout, `trace_id`/`span_id`. |
| CI | `talay-workflows`'ta karşılık gelen reusable workflow yok. Seçenekler: (a) `node.yaml`'ı image build için uyarlamak yerine `talay-workflows`'a yeni reusable workflow eklemek (önerilen; java.yaml'ı şablon al: secret scan → test → Trivy → build/push `sha-` tag); (b) geçici olarak app repoda aynı adımlarla workflow. Kararı kullanıcıya sor. |
| Container | Non-root, read-only rootfs uyumlu, `/tmp` dışında yazma yok, port 8080. |

Python örneği CMD: `["opentelemetry-instrument", "gunicorn", "-b", "0.0.0.0:8080", "app:app"]`, bağımlılık
`opentelemetry-distro opentelemetry-exporter-otlp` (+ `opentelemetry-bootstrap -a install` build stage'de).
