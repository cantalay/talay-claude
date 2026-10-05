#!/usr/bin/env bash
# Tek node kapasite kontrolü. Kullanım: capacity.sh [eklenecek_cpu_milicore] [eklenecek_bellek_Mi]
# Requests toplamı + ekleme, allocatable'ın %85'ini aşıyorsa NO_FIT döner (exit 2).
set -euo pipefail
TALAY_HOST="${TALAY_HOST:-152.53.66.101}"
add_cpu="${1:-0}"; add_mem="${2:-0}"
LIMIT_PCT="${TALAY_CAPACITY_PCT:-85}"

ssh -o BatchMode=yes "root@$TALAY_HOST" 'kubectl get nodes -o json; echo "---SPLIT---"; kubectl get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed -o json; echo "---SPLIT---"; kubectl top node --no-headers 2>/dev/null || true' |
python3 -c '
import json, sys
add_cpu, add_mem, limit = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
nodes_raw, pods_raw, top = sys.stdin.read().split("---SPLIT---")
def cpu(v):
    v = str(v); return int(float(v[:-1])) if v.endswith("m") else int(float(v) * 1000)
def mem(v):
    v = str(v); units = {"Ki": 1/1024, "Mi": 1, "Gi": 1024, "Ti": 1024**2, "K": 1/1000/1.048576, "M": 1/1.048576, "G": 1000/1.048576}
    for u, f in units.items():
        if v.endswith(u): return int(float(v[:-len(u)]) * f)
    return int(int(v) / 1024 / 1024)
node = json.loads(nodes_raw)["items"][0]
alloc_cpu, alloc_mem = cpu(node["status"]["allocatable"]["cpu"]), mem(node["status"]["allocatable"]["memory"])
req_cpu = req_mem = 0
for p in json.loads(pods_raw)["items"]:
    for c in p["spec"].get("containers", []):
        r = c.get("resources", {}).get("requests", {})
        req_cpu += cpu(r.get("cpu", "0")); req_mem += mem(r.get("memory", "0"))
print(f"Node allocatable : cpu {alloc_cpu}m, bellek {alloc_mem}Mi")
print(f"Requests toplamı : cpu {req_cpu}m ({req_cpu*100//alloc_cpu}%), bellek {req_mem}Mi ({req_mem*100//alloc_mem}%)")
if top.strip(): 
    f = top.split(); print(f"Gerçek kullanım  : cpu {f[1]} ({f[2]}), bellek {f[3]} ({f[4]})")
new_cpu, new_mem = req_cpu + add_cpu, req_mem + add_mem
print(f"Ekleme sonrası   : cpu {new_cpu}m ({new_cpu*100//alloc_cpu}%), bellek {new_mem}Mi ({new_mem*100//alloc_mem}%)  [sınır %{limit}]")
fits = new_cpu * 100 <= alloc_cpu * limit and new_mem * 100 <= alloc_mem * limit
print("FITS" if fits else "NO_FIT")
sys.exit(0 if fits else 2)
' "$add_cpu" "$add_mem" "$LIMIT_PCT"
