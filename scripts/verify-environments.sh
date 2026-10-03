#!/usr/bin/env bash
# talay-environments/.github/workflows/verify.yml'in lokal karşılığı + application.yaml şema kontrolü.
# Kullanım: verify-environments.sh [apps/prod/<project>/<component> ...]   (argümansız: hepsi)
# TALAY_CHARTS_DIR verilirse chart'lar oradan (lokal değişiklik testi), yoksa talay-helm-charts main'in güncel klonundan.
set -euo pipefail

TALAY_INFRA_DIR="${TALAY_INFRA_DIR:-$HOME/Documents/infra-lts}"
ENV_DIR="${TALAY_ENV_DIR:-$TALAY_INFRA_DIR/talay-environments}"
CHARTS_DIR="${TALAY_CHARTS_DIR:-}"

if [[ -z "$CHARTS_DIR" ]]; then
  CHARTS_DIR="$(mktemp -d)"
  trap 'rm -rf "$CHARTS_DIR"' EXIT
  git clone -q --depth 1 https://github.com/cantalay/talay-helm-charts.git "$CHARTS_DIR"
fi

cd "$ENV_DIR"
shopt -s nullglob
if [[ $# -gt 0 ]]; then
  applications=(); for d in "$@"; do applications+=("${d%/}/application.yaml"); done
else
  applications=(apps/*/*/*/application.yaml)
fi
[[ ${#applications[@]} -gt 0 ]] || { echo "application.yaml bulunamadı" >&2; exit 1; }

declare -A built=()
status=0
for application in "${applications[@]}"; do
  echo "==> $application"
  read -r name environment namespace chart_path values_file manifests_path < <(
    python3 - "$application" <<'PY'
import json, re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
schema = json.load(open("schema/app.schema.json"))
allowed = set(schema["properties"])
extra = set(doc) - allowed
missing = [k for k in schema["required"] if k not in doc]
if extra or missing:
    sys.exit(f"schema: fazla={sorted(extra)} eksik={missing}")
for key, rule in schema["properties"].items():
    value = doc[key]
    if "enum" in rule and value not in rule["enum"]:
        sys.exit(f"schema: {key}={value!r} izinli değil {rule['enum']}")
    if "pattern" in rule and not re.search(rule["pattern"], str(value)):
        sys.exit(f"schema: {key}={value!r} pattern {rule['pattern']} ile uyuşmuyor")
print(doc["name"], doc["environment"], doc["namespace"], doc["chartPath"], doc["valuesFile"], doc["manifestsPath"])
PY
  ) || { status=1; continue; }

  if [[ "$manifests_path" != "$(dirname "$application")" ]]; then echo "manifestsPath dizinle uyuşmuyor" >&2; status=1; continue; fi
  [[ -f "$values_file" ]] || { echo "values yok: $values_file" >&2; status=1; continue; }
  if grep -nE '__[A-Z0-9_]+__' "$values_file" "$manifests_path"/*.yaml "$manifests_path"/*/*.yaml 2>/dev/null | grep -v '__TALAY_CONFIG__'; then
    echo "doldurulmamış şablon yer tutucusu var" >&2; status=1; continue
  fi
  if grep -nE '^\s*tag:\s*"?latest"?\s*$' "$values_file"; then echo "latest tag yasak" >&2; status=1; continue; fi

  chart="$CHARTS_DIR/$chart_path"
  if [[ -z "${built[$chart]:-}" ]]; then helm dependency build "$chart" >/dev/null; built[$chart]=1; fi
  helm lint --strict "$chart" -f "$values_file" >/dev/null || { helm lint --strict "$chart" -f "$values_file"; status=1; continue; }
  helm template "$name" "$chart" --namespace "$namespace" -f "$values_file" >/dev/null || { status=1; continue; }
  kubectl kustomize "$manifests_path" >/dev/null || { status=1; continue; }
  echo "    OK ($name-$environment → ns $namespace)"
done
exit $status
