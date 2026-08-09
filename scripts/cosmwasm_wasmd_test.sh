#!/usr/bin/env bash
# CosmWasm engineering wasmd tx-level differential (BL-26 rung 1):
#   product CLI build → StateCell.wasm + ScheduleFlow.wasm
#   → docker cosmwasm/wasmd:v0.70.3 local chain
#   → store / instantiate / execute / raw-state assert
#
# Covers:
#   - StateCell init(7) → state 7; increment(5) → state 12;
#     overflow increment → tx fails, state holds 12
#   - ScheduleFlow later() → SubMsg to static QN stub "ledger.daily"
#     fails bech32 validation under ReplyNever; whole tx aborts; state holds
#     (SRC-CW-002 / CW-ABI-FREEZE wasmd v0.70.3 dispatcher semantics)
#
# Not mainnet, not formal Stage-0 / hermetic release evidence / CI-registered
# shard (main agent decides just recipe wiring). mock cosmwasm-vm suite remains
# scripts/cosmwasm_runtime_test.sh — this script is the first real wasmd rung.
#
# Image pin:
#   tag:    cosmwasm/wasmd:v0.70.3
#   digest: sha256:3741178a4d747fd5cf281550ab4ac30d771163af1c543f9da503c411a1691773
#           (Docker Hub repo digest observed 2026-08-03 for linux/amd64;
#            config digest sha256:adefc9ebbe1cafab3c646f88e3f2dc23defabb66f3ed2118142d7a09b4543c93)
#
# Host notes:
#   - Bind-mounts of host paths into colima-x86 are unreliable; this script uses
#     `docker cp` into a long-lived container and keeps wasmd home inside it.
#   - Product smart-query ABI is MVP non-Binary {"ok":"<decimal>"}; wasmd
#     `contract-state smart` fails closed. Assertions use contract-state raw on
#     pf:cw:v1:state:0 (LE u64), matching runtime-tests/cosmwasm mock layout.
#
# Requires:
#   - docker on PATH with a working daemon
#   - lake / Lean toolchain on PATH
#   - wat2wasm (PROOF_FORGE_TOOL_ROOT or PATH) for finalize fallback
#   - network on first pull of the wasmd image (~90MB)
#
# Exit codes:
#   0 success (or skip-clean when docker/image/lake/wat2wasm absent)
#   1 product build / wasmd assertion failure
#   2 unsupported host platform (hard miss)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

WASMD_IMAGE_TAG="cosmwasm/wasmd:v0.70.3"
# Repo digest (tag resolution on Docker Hub for linux/amd64).
WASMD_IMAGE_DIGEST="sha256:3741178a4d747fd5cf281550ab4ac30d771163af1c543f9da503c411a1691773"
WASMD_IMAGE="${WASMD_IMAGE:-$WASMD_IMAGE_TAG}"

CONTAINER_NAME="${PROOF_FORGE_WASMD_CONTAINER:-pf-wasmd-bl26}"
IN_CONTAINER_TEST="runtime-tests/cosmwasm-wasmd/run_chain_tests.sh"

die() {
  echo "cosmwasm-wasmd-test: $*" >&2
  exit 1
}

missing() {
  echo "cosmwasm-wasmd-test: $*" >&2
  exit 2
}

skip_clean() {
  echo "cosmwasm-wasmd-test: skipped: $*" >&2
  exit 0
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    missing "unsupported host platform: $(uname -s)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

resolve_tool() {
  local name="$1"
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/$name" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/$name"
    return 0
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  if [[ -x "/opt/homebrew/bin/$name" ]]; then
    echo "/opt/homebrew/bin/$name"
    return 0
  fi
  if [[ -x "/usr/local/bin/$name" ]]; then
    echo "/usr/local/bin/$name"
    return 0
  fi
  return 1
}

if ! command -v docker >/dev/null 2>&1; then
  skip_clean "docker not on PATH"
fi
if ! docker info >/dev/null 2>&1; then
  skip_clean "docker daemon not reachable"
fi
if ! command -v lake >/dev/null 2>&1; then
  skip_clean "lake not on PATH"
fi
if ! wat2wasm="$(resolve_tool wat2wasm)"; then
  skip_clean "wat2wasm unavailable (set PROOF_FORGE_TOOL_ROOT or install wabt)"
fi

cleanup() {
  local ec=$?
  if [[ -n "${CONTAINER_NAME:-}" ]]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  exit "$ec"
}
trap cleanup EXIT INT TERM

echo "cosmwasm-wasmd-test: image=$WASMD_IMAGE (pin tag v0.70.3; expected digest $WASMD_IMAGE_DIGEST)"

# Pull if needed; skip-clean when pull fails (offline / registry).
if ! docker image inspect "$WASMD_IMAGE" >/dev/null 2>&1; then
  echo "cosmwasm-wasmd-test: pulling $WASMD_IMAGE ..."
  if ! docker pull "$WASMD_IMAGE"; then
    skip_clean "unable to pull $WASMD_IMAGE (network/registry)"
  fi
fi

# Soft-verify repo digest when the local image reports one.
if observed="$(docker image inspect "$WASMD_IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"; then
  if [[ -n "$observed" && "$observed" != *"$WASMD_IMAGE_DIGEST"* ]]; then
    echo "cosmwasm-wasmd-test: warn: RepoDigests=$observed (expected contains $WASMD_IMAGE_DIGEST)" >&2
  else
    echo "cosmwasm-wasmd-test: RepoDigests=${observed:-none}"
  fi
fi

cli="$root/.lake/build/bin/proof-forge-next"
out_dir="${PROOF_FORGE_RUNTIME_OUT:-$root/build/v2/cosmwasm-wasmd}"

programs=(
  "Examples/StateCell.lean:Examples.StateCell:StateCell"
  "runtime-tests/cosmwasm/fixtures/ScheduleFlow.lean:Examples.ScheduleFlow:ScheduleFlow"
)

echo "cosmwasm-wasmd-test: building proof-forge-next (lake build proof_forge_next)"
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "cosmwasm-wasmd-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "cosmwasm-wasmd-test: wat2wasm=$wat2wasm ($("$wat2wasm" --version 2>&1 | head -1 || true))"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION).
rm -rf "$out_dir"
mkdir -p "$out_dir"

normalize_wasm() {
  local name="$1"
  local fixture_out="$2"
  local wasm=""
  if [[ -f "$fixture_out/${name}.wasm" ]]; then
    wasm="$fixture_out/${name}.wasm"
  else
    wasm="$(find "$fixture_out" -name "${name}.wasm" -type f 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$wasm" || ! -f "$wasm" ]]; then
    local wat=""
    if [[ -f "$fixture_out/${name}.wat" ]]; then
      wat="$fixture_out/${name}.wat"
    else
      wat="$(find "$fixture_out" -name "${name}.wat" -type f 2>/dev/null | head -n 1 || true)"
    fi
    [[ -n "$wat" && -f "$wat" ]] || return 1
    wasm="$fixture_out/${name}.wasm"
    if ! "$wat2wasm" "$wat" -o "$wasm" 2>"$out_dir/${name}.wat2wasm.err"; then
      echo "cosmwasm-wasmd-test: wat2wasm failed for $name" >&2
      cat "$out_dir/${name}.wat2wasm.err" >&2 || true
      return 1
    fi
  fi
  if [[ "$(cd "$(dirname "$wasm")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$wasm" "$fixture_out/${name}.wasm"
  fi
  [[ -f "$fixture_out/${name}.wasm" ]] || return 1
  echo "cosmwasm-wasmd-test: ${name}.wasm=$(wc -c <"$fixture_out/${name}.wasm" | tr -d ' ') bytes"
  return 0
}

for entry in "${programs[@]}"; do
  IFS=':' read -r rel_src module name <<<"$entry"
  src="$root/$rel_src"
  [[ -f "$src" ]] || die "source missing: $src"
  fixture_out="$out_dir/$name"
  echo "cosmwasm-wasmd-test: build $rel_src --module $module --target cosmwasm -o $fixture_out"
  if ! lake env "$cli" build \
    "$rel_src" \
    --module "$module" \
    --target cosmwasm \
    -o "$fixture_out"; then
    die "proof-forge-next build failed for $name"
  fi
  normalize_wasm "$name" "$fixture_out" || die "${name}.wasm not found under $fixture_out"
done

# Fresh container (no host bind-mount of wasmd home — colima-x86 bind mounts are flaky).
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
echo "cosmwasm-wasmd-test: starting container $CONTAINER_NAME from $WASMD_IMAGE"
if ! docker run -d --name "$CONTAINER_NAME" "$WASMD_IMAGE" sleep infinity >/dev/null; then
  die "docker run failed for $WASMD_IMAGE"
fi

docker exec "$CONTAINER_NAME" mkdir -p /artifacts /opt/pf-tests
docker cp "$out_dir/StateCell/StateCell.wasm" "$CONTAINER_NAME:/artifacts/StateCell.wasm"
docker cp "$out_dir/ScheduleFlow/ScheduleFlow.wasm" "$CONTAINER_NAME:/artifacts/ScheduleFlow.wasm"
docker cp "$root/$IN_CONTAINER_TEST" "$CONTAINER_NAME:/opt/pf-tests/run_chain_tests.sh"
docker exec "$CONTAINER_NAME" chmod +x /opt/pf-tests/run_chain_tests.sh

echo "cosmwasm-wasmd-test: chain genesis (wasmd init / keys / gentx; keyring=test)"
# Mirrors /opt/setup_wasmd.sh from the image, with non-interactive test keyring.
docker exec "$CONTAINER_NAME" sh -c '
  set -eu
  STAKE=ustake
  FEE=ucosm
  CHAIN_ID=testing
  MONIKER=node001
  # Quiet noisy JSON dumps from init/gentx/collect (errors still surface via set -e).
  wasmd init --chain-id "$CHAIN_ID" "$MONIKER" >/tmp/wasmd-init.json
  # Official setup renames bond/fee tokens this way.
  sed -i "s/\"stake\"/\"$STAKE\"/" /root/.wasmd/config/genesis.json
  sed -i "s/\"time_iota_ms\": \"1000\"/\"time_iota_ms\": \"10\"/" /root/.wasmd/config/genesis.json
  wasmd config set client chain-id "$CHAIN_ID"
  wasmd config set client keyring-backend test
  wasmd keys add validator --keyring-backend test >/tmp/wasmd-key.json
  ADDR=$(wasmd keys show validator -a --keyring-backend test)
  wasmd genesis add-genesis-account "$ADDR" "1000000000$STAKE,1000000000$FEE"
  wasmd genesis gentx validator "250000000$STAKE" \
    --chain-id="$CHAIN_ID" --amount="250000000$STAKE" --keyring-backend test >/tmp/wasmd-gentx.json
  wasmd genesis collect-gentxs >/tmp/wasmd-collect.json
  sed -i "s/^minimum-gas-prices =.*/minimum-gas-prices = \"0.025ucosm\"/" /root/.wasmd/config/app.toml
  echo "validator=$ADDR"
'

echo "cosmwasm-wasmd-test: starting wasmd node"
docker exec -d "$CONTAINER_NAME" wasmd start --rpc.laddr tcp://0.0.0.0:26657

# Wait until status reports a positive height.
echo "cosmwasm-wasmd-test: waiting for RPC/blocks ..."
ready=0
for i in $(seq 1 90); do
  if st="$(docker exec "$CONTAINER_NAME" wasmd status --output json 2>/dev/null || true)"; then
    if echo "$st" | grep -q '"latest_block_height":"[1-9]'; then
      ready=1
      echo "cosmwasm-wasmd-test: node ready (attempt $i)"
      break
    fi
  fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || die "wasmd node did not become ready within timeout"

echo "cosmwasm-wasmd-test: running in-container assertions"
if ! docker exec "$CONTAINER_NAME" sh /opt/pf-tests/run_chain_tests.sh; then
  die "wasmd chain assertions failed (see output above)"
fi

echo "cosmwasm-wasmd-test: ok (engineering wasmd tx differential; not mainnet/formal Stage-0)"
