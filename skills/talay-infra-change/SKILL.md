---
name: talay-infra-change
description: Talay altyapı Terraform repolarında (talay-cluster, -network, -data, -secrets, -identity, -observability, -gitops) değişiklik yapma kuralları — kubeconfig edinme, Kubernetes state backend, install/configure stack ayrımı, plan/apply onayı, bağımlılık sırası, chart (talay-helm-charts) ve workflow (talay-workflows) değişiklikleri. Platform bileşenini güncelleme/ekleme veya Terraform çalıştırma gerektiğinde kullan.
---

# talay-infra-change

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §2.

## Kubeconfig
Bootstrap dahil bütün state'ler cluster içinde (`terraform-states` ns, Kubernetes backend; yerelde state yok) → Terraform'un geçerli kubeconfig'e ihtiyacı var.
Lokal `~/.kube/config` eski cluster'a ait. Yeni kubeconfig **kullanıcı onayıyla** alınır (cluster-admin credential'ı):
```bash
umask 077
ssh root@152.53.66.101 cat /etc/rancher/k3s/k3s.yaml | sed 's#https://127.0.0.1:6443#https://152.53.66.101:6443#' > ~/.kube/talay.yaml
export KUBECONFIG=~/.kube/talay.yaml KUBE_CONFIG_PATH=~/.kube/talay.yaml
```
Her repoda `backend.hcl` (`backend.hcl.example`'dan; git'e girmez) ve `terraform.tfvars` (example'dan) gerekir. Bu
dosyalar yerelde yoksa example'lardan oluştur, değerleri kullanıcıya doğrulat. Bazı stack'ler `kubeconfig_path`
değişkeni ister → `-var kubeconfig_path=$HOME/.kube/talay.yaml`.

## Bağımlılık sırası
`talay-cluster/bootstrap` → `talay-cluster/base` → `talay-network` → `talay-secrets/install` → (Vault init/unseal, kullanıcı) →
`talay-secrets/configure` → `talay-data` → `talay-identity/install` → `talay-identity/configure` → `talay-observability` → `talay-gitops`.
Bir katmanı değiştirirken yalnız onu ve ona bağlı olanları planla.

## Kurallar
1. Her zaman `terraform fmt -recursive && terraform validate && terraform plan -out=tfplan`. Planı özetle
   (add/change/destroy sayıları + destroy/replace edilen her kaynak). **Destroy/replace varsa açıkça uyar.**
2. Apply yalnız kullanıcı onayıyla, kaydedilmiş planla (`terraform apply tfplan`).
3. Secret'lar tfvars/state'e girmez: Vault/ESO kullan; provider kimlikleri env değişkeniyle (`VAULT_TOKEN`, `KEYCLOAK_USER/PASSWORD`).
4. Modül refactor'larında `moved {}` blokları ile no-op plan hedefle.
5. Helm chart sürüm yükseltmeleri tek tek, release notları okunarak.
6. Değişiklik → branch + PR (talay-workflows `terraform.yaml` CI'ı yoksa lokal fmt/validate yeter) → merge kullanıcıda.

## talay-helm-charts
Chart değişikliği `main`'e merge edildiği anda **tüm** app'lere yansır (Argo chartsRepo revision `main`). Bu yüzden:
`Chart.yaml` version artır, `values.schema.json` güncelle, geriye uyumlu default'lar ver, `helm lint --strict` +
mevcut tüm component'lerle `scripts/verify-environments.sh` (TALAY_CHARTS_DIR ile lokal chart'ı gösterir).

## talay-workflows
Değişiklik sonrası yeni commit SHA'sını app repolarındaki pin'lere taşımak ayrı bir iştir; kullanıcıya sor.
