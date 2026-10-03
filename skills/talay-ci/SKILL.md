---
name: talay-ci
description: Uygulama reposuna Talay'ın ortak GitHub Actions workflow'larını (talay-workflows java/node/web/expo) pinned SHA ile bağlar, GHCR image'ını sha-<commit> tag'iyle üretir ve CI sonucunu takip eder. "CI ekle", "pipeline", "image build", "GHCR", "workflow kırıldı" isteklerinde kullan.
---

# talay-ci

Bağlam: `${CLAUDE_PLUGIN_ROOT}/PLATFORM.md` §3. Şablonlar: `${CLAUDE_PLUGIN_ROOT}/templates/ci/`.

## Pin
Şablonlarda `@__TALAY_WORKFLOWS_SHA__` yer tutucusu var. Değer:
`git -C $TALAY_INFRA_DIR/talay-workflows rev-parse HEAD` (pull'dan sonra). Mevcut app'ler `107e3e43dee30ea1b4874c7bc150f90769b55efc` kullanıyor.

## Workflow seçimi
| Component | Şablon | Önemli input'lar |
| --- | --- | --- |
| Java/Spring | `ci/java.yml` | `java-version` (21/25), `build-tool` (maven/gradle), `image-name`, `dockerfile` |
| Node API/worker | `ci/node.yml` | `package-manager` (npm/pnpm/yarn), `pnpm-version`, `test-command`, `build-command`, `image-name` |
| Web (Vite/Expo Web) | `ci/web.yml` | `package-manager`, `build-command`, `image-name`, `dockerfile` |
| Expo mobil | `ci/expo.yml` | `EXPO_TOKEN` repo secret'ı |

Hepsi PR'da test + Trivy (HIGH/CRITICAL build'i durdurur) + secret scan; yalnız `main` push'unda image publish:
`ghcr.io/cantalay/<image>:sha-<7>` (+ SBOM/provenance). Image adı = `talay.yaml` component `image`.

Monorepo'da birden çok image → her biri için ayrı job, ayrı `image-name`/`dockerfile`.
`node.yaml`'ın `dockerfile` input'u yoktur: her zaman repo kökündeki `Dockerfile` + context `.` kullanılır
(birden çok Node image'ı gerekiyorsa tek image + process type env'i deseni — vitafinder-core — ya da talay-workflows'a input ekle).

## Akış
1. Şablonu `.github/workflows/<ad>.yml` olarak kopyala, yer tutucuları doldur.
2. Repo private ve package ilk kez oluşuyorsa: GHCR package ilk push'ta repo'ya bağlanır. Eski/merkezi package'larda
   `GITHUB_TOKEN` yetmezse `GHCR_TOKEN: ${{ secrets.GHCR_PAT }}` geçir (talay-workflows README).
3. Commit + push (kullanıcı onayı). `gh run list -R cantalay/<repo> -L 1` → `gh run watch <id> -R cantalay/<repo> --exit-status`.
4. Kırmızıysa `gh run view <id> --log-failed` ile sebebi bul, düzelt, tekrar:
   - Trivy bağımlılık bulgusu → `npm outdated`/`mvn versions:display-dependency-updates`, yalnız etkilenen paketi yükselt.
   - Trivy OS paketi bulgusu ("fixed" sürüm var) → GHA cache eski `apk upgrade` katmanını kullanıyor; o RUN satırını değiştir.
   - Secret scan bulgusu → dosyayı kaldır ve secret'ı döndür.
5. Tag ve digest (gh token'ında `read:packages` yok; digest'i CI logundan al):
   ```bash
   gh run view <id> -R cantalay/<repo> --log | grep -oE "ghcr.io/cantalay/<image>:sha-[0-9a-f]{7}@sha256:[0-9a-f]{64}" | sort -u
   ```
   Çıkan `sha256:…` → values `image.digest`.

## Deploy'u otomatikleştirme (opsiyonel)
`talay-workflows/promote-image.yaml` image tag'ini talay-environments'a PR olarak yazar, ama GitHub App
(`APP_ID`, `APP_PRIVATE_KEY`) gerektirir ve şu an hiçbir repoda kurulu değil. Kullanıcı isterse: GitHub App oluştur
(contents+pull_requests write, yalnız talay-environments), secret'ları app repolarına ekle, CI'a promote job'u ekle.
Kurulana kadar promotion `talay-deploy` §Yeni sürüm ile yapılır.
