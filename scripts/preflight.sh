#!/usr/bin/env bash
# Talay ön kontrolleri: araçlar, erişimler ve repo çalışma alanı. Hiçbir şey değiştirmez.
set -uo pipefail

TALAY_HOST="${TALAY_HOST:-152.53.66.101}"
TALAY_INFRA_DIR="${TALAY_INFRA_DIR:-$HOME/Documents/infra-lts}"
export VAULT_ADDR="${VAULT_ADDR:-https://vault.cantalay.com}"
fail=0

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }

echo "Araçlar"
for tool in git gh ssh helm kubectl terraform vault jq dig curl docker; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else
    case "$tool" in terraform|docker) warn "$tool yok (yalnız ilgili adımda gerekli)";; *) bad "$tool yok";; esac
  fi
done

echo "Erişim"
if gh auth status >/dev/null 2>&1; then ok "gh auth ($(gh api user --jq .login 2>/dev/null))"; else bad "gh auth login gerekli"; fi
if ssh -o BatchMode=yes -o ConnectTimeout=8 "root@$TALAY_HOST" true 2>/dev/null; then ok "ssh root@$TALAY_HOST"; else bad "ssh root@$TALAY_HOST (key ile) başarısız"; fi
if vault token lookup >/dev/null 2>&1; then ok "vault token ($VAULT_ADDR)"; else warn "vault girişi yok → provisioning öncesi: vault login -method=oidc"; fi
if curl -fsS -o /dev/null --max-time 8 https://auth.cantalay.com/realms/master/.well-known/openid-configuration; then ok "keycloak auth.cantalay.com"; else warn "keycloak erişilemedi"; fi

echo "Çalışma alanı ($TALAY_INFRA_DIR)"
for repo in talay-cluster talay-network talay-data talay-secrets talay-identity talay-observability talay-gitops talay-environments talay-helm-charts talay-workflows; do
  dir="$TALAY_INFRA_DIR/$repo"
  if [[ ! -d "$dir/.git" ]]; then bad "$repo yok (gh repo clone cantalay/$repo $dir)"; continue; fi
  git -C "$dir" fetch -q origin main 2>/dev/null
  behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
  dirty=$(git -C "$dir" status --porcelain | wc -l)
  if [[ "$behind" == "0" && "$dirty" == "0" ]]; then ok "$repo"; else warn "$repo (geride: $behind, değişmiş dosya: $dirty)"; fi
done

exit $fail
