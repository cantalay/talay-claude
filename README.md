# talay-claude

Talay platformu için Claude Code plugin'i. Platform bilgisini (`PLATFORM.md`), adımları (`skills/`), golden-path
dosyalarını (`templates/`) ve yardımcı script'leri (`scripts/`) paketler; Claude her projede bunları otomatik yükler.

## Kurulum (makine başına bir kez)

```bash
# 1. Altyapı repoları (skill'ler bu dizini kullanır; farklıysa TALAY_INFRA_DIR ayarla)
mkdir -p ~/Documents/infra-lts && cd ~/Documents/infra-lts
for r in cluster network data secrets identity observability gitops environments helm-charts workflows; do
  gh repo clone cantalay/talay-$r
done
```

Claude Code içinde:

```text
/plugin marketplace add cantalay/talay-claude
/plugin install talay-platform@talay
```

Gerekenler: `gh` (login), `ssh root@45.87.80.10` key erişimi, `helm`, `kubectl`, `vault`, `jq`, `dig`, `python3` (+PyYAML);
Keycloak/Terraform adımları için `terraform ~> 1.16`. Kontrol: `scripts/preflight.sh`.

## Skill'ler

| Skill | Ne zaman |
| --- | --- |
| `/talay-ship` | Proje analizi/isterlerden ya da mevcut repodan uçtan uca prod'a çıkış (orkestratör) |
| `/talay-app-standards` | Uygulamayı platforma uygun geliştirme (health, metrics, OTel, log, auth, migration, Dockerfile) |
| `/talay-database` | PostgreSQL DB + role, Redis index, Vault'a bağlantı bilgisi |
| `/talay-auth` | Keycloak realm/client/rol (Terraform) ve uygulama entegrasyonu |
| `/talay-secrets` | Vault path sözleşmesi, güvenli secret yazma, ExternalSecret |
| `/talay-ci` | talay-workflows caller workflow'ları, GHCR image |
| `/talay-deploy` | talay-environments component'i, DNS, kapasite, Argo sync, yeni sürüm, rollback |
| `/talay-observability` | Dashboard, alarmlar, trace/metric/log doğrulama |
| `/talay-status` | Salt-okunur canlı durum ve arıza teşhisi |
| `/talay-infra-change` | talay-* Terraform repolarında değişiklik kuralları |

Skill'ler isimleriyle çağrılabilir ya da istek açıklamasıyla eşleşince Claude tarafından otomatik seçilir.

## Script'ler

| Script | Açıklama |
| --- | --- |
| `scripts/preflight.sh` | Araç, erişim ve repo güncelliği kontrolü |
| `scripts/verify-environments.sh [dir…]` | talay-environments CI doğrulamasının lokal karşılığı + şema/placeholder/`latest` kontrolü |
| `scripts/capacity.sh <cpu_m> <mem_Mi>` | Tek node'a yeni workload sığar mı |
| `scripts/status.sh [namespace]` | Platform veya tek uygulama durum raporu |

## Güncelleme

Bu repoda değişiklik → push → Claude Code'da `/plugin marketplace update talay`.
Platformda bir şey değişirse önce `PLATFORM.md`'yi güncelle; skill'ler değerleri oradan okur.
