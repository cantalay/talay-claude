---
name: talay-status
description: Talay cluster'ının (152.53.66.101) ve uygulamaların canlı durumunu SSH üzerinden salt-okunur kontrol eder — node kaynakları, Argo CD app sync/health, pod'lar, sertifikalar, ExternalSecret'lar, Vault seal, son olaylar — ve sık arızalar için teşhis reçeteleri verir. "durum", "status", "çalışıyor mu", "neden açılmıyor", "pod crash", "sertifika", "sync olmadı" isteklerinde kullan.
---

# talay-status

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md`. Tüm komutlar **salt-okunur**; değişiklik gerekiyorsa Git/Terraform yoluyla ve onayla.

## Genel durum
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh            # tüm platform özeti
bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh <namespace> # tek app ayrıntısı (pods, events, son loglar)
```
Rapor: node CPU/RAM, Argo app'leri (Synced/Healthy olmayanlar vurgulu), Running olmayan pod'lar, Ready olmayan
cert'ler, sync olmayan ExternalSecret'lar, Vault seal durumu, son Warning event'leri.

## Tek app teşhisi
```bash
K="ssh root@152.53.66.101 kubectl"
$K get application -n gitops <app>-prod -o jsonpath='{.status.sync.status} {.status.health.status} {.status.operationState.message}'
$K get pods -n <ns> -o wide
$K describe pod -n <ns> <pod> | tail -30
$K logs -n <ns> deploy/<name> --tail=100 [--previous]
$K get events -n <ns> --sort-by=.lastTimestamp | tail -20
```
Log'larda secret değeri görürsen kullanıcıya yansıtma; bunu bir bulgu olarak raporla.

## Arıza reçeteleri
| Belirti | Olası sebep | Çözüm yolu |
| --- | --- | --- |
| Argo `OutOfSync`/`ComparisonError` | values/kustomize render hatası | `scripts/verify-environments.sh`, düzelt, push |
| Argo `Degraded`, pod `ImagePullBackOff` | tag yok / `ghcr-pull` yok | tag'i GHCR'da doğrula; `kubectl get externalsecret ghcr-pull -n <ns>`; `registrySecret.enabled: true` |
| `CreateContainerConfigError` | env'in istediği Secret yok | ExternalSecret durumu; Vault path/key (talay-secrets) |
| `CrashLoopBackOff` | config eksik, DB bağlantısı, migration hatası | `logs --previous`; DB → talay-database §Sorun giderme |
| Startup probe fail | yavaş JVM / yanlış path | `probes.startup.failureThreshold` artır veya path düzelt |
| `OOMKilled` | limit düşük | `resources.limits.memory` artır (kapasite kontrolü) |
| Pod `Pending` | kapasite yetersiz | `scripts/capacity.sh`; requests küçült |
| Certificate `Ready=False` | DNS yanlış / HTTP-01 erişilemiyor | `dig`; `kubectl get challenge,order -n <ns>`; `kubectl describe challenge` |
| ExternalSecret `SecretSyncedError` | path/key yok veya Vault sealed | `vault kv get`; Vault seal kontrolü |
| Vault `sealed: true` | sunucu restart sonrası | Unseal anahtarları kullanıcıda; ona `vault operator unseal` adımlarını söyle (Claude unseal key istemez) |
| 404 (Traefik) | ingress host/path yanlış, ingressClassName eksik | ingress manifesti |
| 502/503 | Service'e endpoint yok (readiness fail) | readiness log'u |

## Vault
```bash
ssh root@152.53.66.101 "kubectl exec -n vault vault-0 -- vault status -format=json" | jq '{sealed, initialized, version}'
```
