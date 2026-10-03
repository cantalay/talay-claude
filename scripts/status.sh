#!/usr/bin/env bash
# Talay salt-okunur durum raporu. Kullanım: status.sh [namespace]
set -uo pipefail
TALAY_HOST="${TALAY_HOST:-45.87.80.10}"
ns="${1:-}"

if [[ -z "$ns" ]]; then
ssh -o BatchMode=yes "root@$TALAY_HOST" 'bash -s' <<'REMOTE'
section() { printf '\n== %s\n' "$1"; }
section "Node"
kubectl get nodes -o wide --no-headers | awk "{print \$1, \$2, \$5}"
kubectl top node --no-headers 2>/dev/null
free -h | awk "NR<=2"; df -h / | awk "NR==2 {print \"disk /:\", \$3\"/\"\$2, \$5}"
section "Argo CD applications (Synced/Healthy olmayanlar ! ile)"
kubectl get applications -n gitops -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}' |
  awk '{flag = ($2=="Synced" && $3=="Healthy") ? " " : "!"; printf "%s %-36s %-10s %s\n", flag, $1, $2, $3}'
section "Running/Completed olmayan pod'lar"
kubectl get pods -A --no-headers | awk '$4!="Running" && $4!="Completed" {print}' | grep . || echo "yok"
section "Yeniden başlayan container'lar (restart>0)"
kubectl get pods -A --no-headers | awk '$5+0>0 {print $1, $2, "restart="$5, $6, $7}' | grep . || echo "yok"
section "Ready olmayan sertifikalar"
kubectl get certificates -A --no-headers | awk '$3!="True" {print}' | grep . || echo "yok"
section "Sync olmayan ExternalSecret'lar"
kubectl get externalsecrets -A --no-headers | awk '$7!="True" {print}' | grep . || echo "yok"
section "Vault"
kubectl exec -n vault vault-0 -c vault -- vault status -format=json 2>/dev/null | grep -E '"(sealed|initialized|version)"' || echo "vault status okunamadı"
section "Son Warning event'leri (15)"
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp --no-headers 2>/dev/null | tail -15 | cut -c1-220
REMOTE
else
ssh -o BatchMode=yes "root@$TALAY_HOST" "bash -s -- $ns" <<'REMOTE'
ns="$1"
printf '== %s\n' "$ns"
kubectl get applications -n gitops -o jsonpath='{range .items[*]}{.spec.destination.namespace}{" "}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{" "}{.status.operationState.message}{"\n"}{end}' | awk -v n="$ns" '$1==n'
kubectl get deploy,pods,svc,ingress,certificate,externalsecret -n "$ns" -o wide 2>/dev/null
printf '\n== events\n'; kubectl get events -n "$ns" --sort-by=.lastTimestamp | tail -15 | cut -c1-220
for d in $(kubectl get deploy -n "$ns" -o name); do
  printf '\n== logs %s (son 40)\n' "$d"; kubectl logs -n "$ns" "$d" --tail=40 2>&1 | cut -c1-300
done
REMOTE
fi
