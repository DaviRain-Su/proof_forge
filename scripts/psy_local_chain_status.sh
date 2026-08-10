#!/usr/bin/env bash
# Probe whether a Psy local/public coordinator from config answers.
# Does NOT start Scylla/NATS/Redis/node fabric (host-heavy; see psy-node README).
set -euo pipefail
export PATH="${HOME}/.psy/bin:${PATH}"
cfg="${RPC_CONFIG:-${HOME}/.psy/config.json}"
[[ -f "$cfg" ]] || { echo "missing $cfg"; exit 2; }
python3 - <<PY
import json, subprocess, os
from pathlib import Path
cfg=Path(os.environ.get("RPC_CONFIG", str(Path.home()/".psy/config.json")))
c=json.loads(cfg.read_text())
urls=[]
nets=c.get("networks") or {}
for name in ("localhost","sepolia"):
    n=nets.get(name) or {}
    for block in n.get("coordinator_configs") or []:
        for u in block.get("rpc_url") or []:
            urls.append((name,u))
if not urls and c.get("services",{}).get("coordinator_rpc"):
    urls.append(("public", c["services"]["coordinator_rpc"]))
print(f"rpc_config={cfg}")
any_up=False
for name,u in urls:
    try:
        r=subprocess.run(["curl","-sS","-o","/dev/null","-m","2","-w","%{http_code}",u],capture_output=True,text=True)
        code=r.stdout.strip() or "000"
        up = r.returncode==0 and code!="000"
    except Exception:
        up, code = False, "err"
    any_up = any_up or up
    print(f"  [{name}] {u} -> http={code} up={up}")
print(f"any_up={any_up}")
if not any_up:
    print("hint: start official local cluster (psy-node locSetup / psy_node_cli) or use sepolia endpoints")
    print("      then: pf deploy -t psy --network local --broadcast --private-key-env KEY")
raise SystemExit(0 if any_up else 1)
PY
