---
name: talay-deploy
description: Bir uygulama component'ini talay-environments reposu üzerinden Argo CD ile prod'a deploy eder veya yeni image sürümünü promote eder — component dizini (application/values/kustomization/certificate/ingress/nginx), DNS ve kapasite kontrolü, lokal render doğrulaması, commit/PR, Argo sync ve sağlık doğrulaması, rollback. "deploy", "yeni sürümü yayınla", "tag güncelle", "rollback", "ingress/domain ekle" isteklerinde kullan.
---

# talay-deploy

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §3–§5, §10. Şablonlar: `${CLAUDE_PLUGIN_ROOT}/templates/environments/{service,web}/`.
Repo: `$TALAY_INFRA_DIR/talay-environments` (önce `git pull --ff-only`).

## Yeni component
1. **Kapasite**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/capacity.sh <eklenecek cpu m> <eklenecek bellek Mi>` → `FITS` değilse kullanıcıya
   seçenekleri sun (requests'i küçült, başka workload'u kapat, sunucu büyüt).
2. **DNS**: `dig +short <host> @1.1.1.1` = `45.87.80.10`. Değilse A kaydını kullanıcıya söyle, bekle.
3. **Dizin**: `apps/prod/<project>/<component>/` — şablonu kopyala, `__PLACEHOLDER__`'ları `talay.yaml`'dan doldur:
   - `application.yaml`: `name: <project>-<component>`, `namespace: <project>-<component>`, chartPath, valuesFile, manifestsPath.
   - `values.yaml`: `fullnameOverride` = namespace; image repository + tag (`sha-<7>`) + digest; `partOf: <project>`;
     externalSecret (`apps/<project>/<component>`), probes, serviceMonitor, resources, config/runtimeConfig.
   - `certificate/certificate.yaml` + `ingress/ingress.yaml` (yalnız host varsa; worker'da ikisini de sil ve kustomization'dan çıkar).
   - Web: `nginx/default.conf` (talay-web varsayılanı yeterliyse sil, values'tan `nginx.existingConfigMap`'i kaldır ve
     kustomization'daki configMapGenerator'ı sil).
   - Dashboard/alarmlar: `talay-observability`.
4. **Doğrula**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-environments.sh` (CI'daki verify.yml'in aynısı + schema kontrolü).
5. **Diff'i göster**, onay al → commit (`feat(prod): deploy <project> <component>`) → `git push origin main`
   (talay-environments'ta branch protection yok; kullanıcı PR isterse branch + `gh pr create`).
6. **Takip** (her 15–30 sn, en fazla ~10 dk):
   ```bash
   ssh root@45.87.80.10 "kubectl get application -n gitops <project>-<component>-prod -o jsonpath='{.status.sync.status} {.status.health.status}{\"\n\"}'"
   ssh root@45.87.80.10 "kubectl get pods,certificate,externalsecret,ingress -n <ns>"
   ```
   Argo 3 dk'da bir poll eder; beklemek istemezsen: `kubectl annotate application -n gitops <app> argocd.argoproj.io/refresh=normal --overwrite`.
7. **Doğrulama**: `curl -fsS https://<host><health>`; sertifika `Ready`; pod restart 0. Takılırsa `talay-status` §Arıza reçeteleri.

## Yeni sürüm (mevcut component)
1. CI'ın ürettiği tag/digest'i al (`talay-ci` §Akış 5).
2. `values.yaml`'da `image.tag` (+ `image.digest`) güncelle. Aynı image'ı kullanan tüm component'leri birlikte güncelle
   (ör. vitafinder api + worker).
3. verify → commit `chore(prod): promote <project>/<component> to sha-xxxxxxx` → push → takip/doğrulama.

## Rollback
`git log -p -- apps/prod/<project>/<component>/values.yaml` → önceki tag/digest'e dönen commit (veya `git revert <sha>`) → push.
DB migration geri alınmaz; şema uyumsuzsa kullanıcıyı uyar.

## Kaldırma
Component dizinini sil + push → Argo app'i (finalizer ile) kaynaklarıyla birlikte siler. Namespace ve Vault/DB/Keycloak
kaynakları kalır — kullanıcıya ayrıca temizlemek isteyip istemediğini sor.

## Kurallar
- `latest` yok; `image.tag` her zaman `sha-<7>`.
- Chart'ta `ingress.enabled: false`; ingress/cert component manifestlerinde.
- Canlıya `kubectl apply` yok. Acil durumda bile önce Git.
- Talay-helm-charts `main`'i izlenir: chart değişikliği tüm app'leri etkiler → chart değişikliğinde tüm component'leri
  `verify-environments.sh` ile render et.
