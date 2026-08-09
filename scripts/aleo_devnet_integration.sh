# Aleo DevNet 集成（非 smoke）：DevNet → 产品 build → 链上 deploy/execute → mapping 观测

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Not smoke: real devnet, real broadcast to local Aleo validators.
echo "integration(aleo-devnet): starting devnet (snarkos test_network)"
bash scripts/aleo_devnet.sh stop >/dev/null 2>&1 || true
bash scripts/aleo_devnet.sh start

# Wait until devnet reaches latest consensus (V18) before deploy. Broadcasting
# while the node is still ramping gets rejected at inclusion ("missing program
# checksum"), so the gate is on latest, not V9.
wait_consensus() {
  for _i in $(seq 1 60); do
    cv="$(curl -sf --max-time 3 http://127.0.0.1:3030/testnet/consensus_version 2>/dev/null || echo 0)"
    if [[ "$cv" =~ ^[0-9]+$ && "$cv" -ge 18 ]]; then
      echo "integration(aleo-devnet): consensus_version=$cv"
      return 0
    fi
    sleep 3
  done
  echo "integration(aleo-devnet): consensus version never reached V18" >&2
  return 1
}
wait_consensus

DEV_KEY="APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH"

echo "integration(aleo-devnet): product build + Instructions pin + deploy + execute"
bash scripts/aleo_network.sh \
  --broadcast \
  --execute \
  --devnet \
  --network testnet \
  --endpoint http://127.0.0.1:3030 \
  --private-key "$DEV_KEY" \
  --priority-fees 200000 \
  --no-golden-pin

# If the program is already deployed on a *persistent* devnet, deploy would fail
# with "Program ID already deployed". For a fresh integration run this should
# not happen; if it does, report the node state instead of silently skipping.

echo "integration(aleo-devnet): mapping observation (expected 3u64 after init 1 + inc 2)"
# Mapping finalization lags execute broadcast; poll until visible.
wait_mapping() {
  local url="$1" expect="$2"
  for _i in $(seq 1 40); do
    v="$(curl -sf --max-time 3 "$url" 2>/dev/null || true)"
    if [[ "$v" == "$expect" ]]; then
      return 0
    fi
    sleep 3
  done
  echo "integration(aleo-devnet): timeout waiting $url == $expect (last=$v)" >&2
  return 1
}

wait_mapping "http://127.0.0.1:3030/testnet/program/counter.aleo/mapping/pf_state_0/0u8" '"3u64"'
wait_mapping "http://127.0.0.1:3030/testnet/program/counter.aleo/mapping/initialized/0u8" '"true"'

echo "integration(aleo-devnet): PASS pf_state_0=3u64 initialized=true"
