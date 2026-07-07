#!/usr/bin/env bash
set -euo pipefail

# Deploy Counter through `proof-forge deploy` on a local Anvil chain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
RUN_DIR="${EVM_ANVIL_RUN_DIR:-$ROOT/build/anvil-deploy-smoke}"
CHAIN_ID="${EVM_ANVIL_CHAIN_ID:-31337}"
if [[ -n "${EVM_ANVIL_CHAIN_PROFILE+x}" ]]; then
  CHAIN_PROFILE="$EVM_ANVIL_CHAIN_PROFILE"
elif [[ "$CHAIN_ID" == "31337" ]]; then
  CHAIN_PROFILE="anvil-local"
else
  CHAIN_PROFILE=""
fi
CONSTRUCTOR_ARGS_HEX="${EVM_ANVIL_CONSTRUCTOR_ARGS_HEX-}"
if [[ -n "${EVM_ANVIL_CONSTRUCTOR_ARG+x}" ]]; then
  CONSTRUCTOR_ARG="$EVM_ANVIL_CONSTRUCTOR_ARG"
elif [[ -n "$CONSTRUCTOR_ARGS_HEX" ]]; then
  CONSTRUCTOR_ARG=""
else
  CONSTRUCTOR_ARG=""
fi
CONSTRUCTOR_PARAM="${EVM_ANVIL_CONSTRUCTOR_PARAM-}"
if [[ -n "${EVM_ANVIL_CONSTRUCTOR_ARG+x}" && -n "$CONSTRUCTOR_ARG" && -n "$CONSTRUCTOR_ARGS_HEX" ]]; then
  echo "anvil-deploy-smoke: set either EVM_ANVIL_CONSTRUCTOR_ARG or EVM_ANVIL_CONSTRUCTOR_ARGS_HEX, not both" >&2
  exit 2
fi
if [[ -n "$CONSTRUCTOR_ARG" ]]; then
  CONSTRUCTOR_ARGS_SOURCE="--evm-constructor-arg"
elif [[ -n "$CONSTRUCTOR_ARGS_HEX" ]]; then
  CONSTRUCTOR_ARGS_SOURCE="--evm-constructor-args-hex"
else
  CONSTRUCTOR_ARGS_SOURCE=""
fi

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v cast >/dev/null 2>&1; then
  echo "anvil-deploy-smoke: cast not found. Install Foundry, then re-run this script." >&2
  exit 127
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "anvil-deploy-smoke: python3 not found on PATH." >&2
  exit 127
fi

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

(cd "$ROOT" && lake build proof-forge Examples.Shared.Counter >/dev/null)

rebuild_counter_with_profile() {
  local proof_forge_args=(
    build
    --target evm
    --root .
    --yul-output "$OUT_DIR/Counter.yul"
    --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json"
    -o "$OUT_DIR/Counter.bin"
    Examples/Evm/Contracts/Counter.lean
  )
  if [[ -n "$CHAIN_PROFILE" ]]; then
    proof_forge_args+=(--evm-chain-profile "$CHAIN_PROFILE")
  fi
  (
    cd "$ROOT"
    "${proof_forge[@]}" "${proof_forge_args[@]}"
    diff -u Examples/Evm/Contracts/Counter.golden.yul "$OUT_DIR/Counter.yul"
    metadata_validator=(
      python3 "$ROOT/scripts/evm/validate-artifact-metadata.py"
      --root "$ROOT"
      --expect-fixture Counter
      --expect-source-kind contract-sdk
    )
    if [[ -n "$CHAIN_PROFILE" ]]; then
      metadata_validator+=(--expect-chain-profile "$CHAIN_PROFILE" --expect-chain-id "$CHAIN_ID")
    fi
    metadata_validator+=("$OUT_DIR/Counter.proof-forge-artifact.json")
    "${metadata_validator[@]}"
  )
}

rebuild_counter_with_profile

if [[ -n "$CONSTRUCTOR_ARG" || -n "$CONSTRUCTOR_ARGS_HEX" ]]; then
  proof_forge_args=(
    build
    --target evm
    --root .
    --yul-output "$OUT_DIR/Counter.yul"
    --artifact-output "$OUT_DIR/Counter.proof-forge-artifact.json"
  )
  if [[ -n "$CHAIN_PROFILE" ]]; then
    proof_forge_args+=(--evm-chain-profile "$CHAIN_PROFILE")
  fi
  if [[ -n "$CONSTRUCTOR_PARAM" ]]; then
    proof_forge_args+=(--evm-constructor-param "$CONSTRUCTOR_PARAM")
  fi
  if [[ -n "$CONSTRUCTOR_ARG" ]]; then
    proof_forge_args+=(--evm-constructor-arg "$CONSTRUCTOR_ARG")
  fi
  if [[ -n "$CONSTRUCTOR_ARGS_HEX" ]]; then
    proof_forge_args+=(--evm-constructor-args-hex "$CONSTRUCTOR_ARGS_HEX")
  fi
  proof_forge_args+=(-o "$OUT_DIR/Counter.bin" Examples/Evm/Contracts/Counter.lean)

  (
    cd "$ROOT"
    "${proof_forge[@]}" "${proof_forge_args[@]}"
    diff -u Examples/Evm/Contracts/Counter.golden.yul "$OUT_DIR/Counter.yul"
    metadata_validator=(
      python3 "$ROOT/scripts/evm/validate-artifact-metadata.py"
      --root "$ROOT"
      --expect-fixture Counter
      --expect-source-kind contract-sdk
    )
    if [[ -n "$CHAIN_PROFILE" ]]; then
      metadata_validator+=(--expect-chain-profile "$CHAIN_PROFILE" --expect-chain-id "$CHAIN_ID")
    fi
    if [[ ( -n "$CONSTRUCTOR_ARG" || -n "$CONSTRUCTOR_ARGS_HEX" ) && -n "$CONSTRUCTOR_PARAM" ]]; then
      metadata_validator+=(--expect-constructor-param "$CONSTRUCTOR_PARAM")
    fi
    if [[ -n "$CONSTRUCTOR_ARGS_SOURCE" ]]; then
      metadata_validator+=("--expect-constructor-args-source=$CONSTRUCTOR_ARGS_SOURCE")
    fi
    metadata_validator+=(
      "$OUT_DIR/Counter.proof-forge-artifact.json"
    )
    "${metadata_validator[@]}"
  )
fi

mkdir -p "$RUN_DIR"
DEPLOY_MANIFEST="$OUT_DIR/Counter.proof-forge-deploy.json"
DEPLOY_RUN="$RUN_DIR/Counter.proof-forge-deploy-run.json"

deploy_args=(
  deploy
  --target evm
  --root "$ROOT"
  --deploy-manifest "$DEPLOY_MANIFEST"
  --output "$DEPLOY_RUN"
  --start-anvil
)
if [[ -n "$CHAIN_PROFILE" ]]; then
  deploy_args+=(--evm-chain-profile "$CHAIN_PROFILE")
fi
if [[ -n "${EVM_ANVIL_PORT:-}" ]]; then
  deploy_args+=(--anvil-port "$EVM_ANVIL_PORT")
fi

(
  cd "$ROOT"
  "${proof_forge[@]}" "${deploy_args[@]}"
)

deploy_run_validator=(
  python3 "$ROOT/scripts/evm/validate-deploy-run.py"
  --root "$ROOT" \
  --expect-fixture Counter \
  --expect-chain-id "$CHAIN_ID"
)
if [[ -n "$CHAIN_PROFILE" ]]; then
  deploy_run_validator+=(--expect-chain-profile "$CHAIN_PROFILE")
fi
if [[ ( -n "$CONSTRUCTOR_ARG" || -n "$CONSTRUCTOR_ARGS_HEX" ) && -n "$CONSTRUCTOR_PARAM" ]]; then
  deploy_run_validator+=(--expect-constructor-param "$CONSTRUCTOR_PARAM")
fi
if [[ -n "$CONSTRUCTOR_ARGS_SOURCE" ]]; then
  deploy_run_validator+=("--expect-constructor-args-source=$CONSTRUCTOR_ARGS_SOURCE")
fi
deploy_run_validator+=(
  "$DEPLOY_RUN"
)
"${deploy_run_validator[@]}"

CONTRACT_ADDRESS="$(python3 - "$DEPLOY_RUN" <<'PY'
import json
import sys

run = json.load(open(sys.argv[1], encoding="utf-8"))
print(run["transaction"]["contractAddress"])
PY
)"

echo "anvil-deploy-smoke: deployed Counter to $CONTRACT_ADDRESS on Anvil chain $CHAIN_ID"
echo "anvil-deploy-smoke: ProofForge deploy-run artifact $DEPLOY_RUN"
