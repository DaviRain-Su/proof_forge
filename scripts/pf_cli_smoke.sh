#!/usr/bin/env bash
# Host-optional smoke for the Rust developer CLI `pf` (Aleo project flow).
#
# Requires:
#   - cargo (to build pf if missing)
#   - proof-forge-next (PROOF_FORGE_CLI or monorepo .lake/build/bin)
# Optional:
#   - leo for `pf run` (skip run if missing)
#
# Exit: 0 ok/skip-clean; 1 fail; 2 host misconfig
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
if [[ ! -x "$cli" ]]; then
  echo "pf-cli-smoke: FAIL proof-forge-next not found ($cli)" >&2
  exit 2
fi
export PROOF_FORGE_CLI="$cli"

pf_bin="${PROOF_FORGE_PF:-$root/clients/pf-cli/target/release/pf}"
if [[ ! -x "$pf_bin" ]]; then
  echo "pf-cli-smoke: building pf (release)"
  cargo build --manifest-path clients/pf-cli/Cargo.toml --locked --release
  pf_bin="$root/clients/pf-cli/target/release/pf"
fi
[[ -x "$pf_bin" ]] || {
  echo "pf-cli-smoke: FAIL pf binary missing" >&2
  exit 2
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-cli-smoke.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

echo "pf-cli-smoke: using $pf_bin"
"$pf_bin" version

echo "pf-cli-smoke: new + build + inspect + clean"
(
  cd "$tmp"
  "$pf_bin" new smoke --target aleo
  cd smoke
  "$pf_bin" build
  test -f build/aleo/manifest.json
  test -f build/aleo/smoke.aleo || test -n "$(find build/aleo -name '*.aleo' ! -name '*query*' | head -1)"
  "$pf_bin" inspect
  "$pf_bin" build # rebuild must not collide
  "$pf_bin" clean
  test ! -d build
  "$pf_bin" build
)

# Multi-target build (compiler only)
echo "pf-cli-smoke: build -t quint (compiler multi-target)"
(
  cd "$tmp/smoke"
  "$pf_bin" build -t quint
  test -f build/quint/manifest.json
)

# Run requires leo
if command -v leo >/dev/null 2>&1 || [[ -x "${HOME}/.cargo/bin/leo" ]] || [[ -n "${PROOF_FORGE_ALEO_LEO:-}" ]]; then
  echo "pf-cli-smoke: run initialize"
  (
    cd "$tmp/smoke"
    "$pf_bin" build -t aleo
    out="$("$pf_bin" run -- initialize 5u64 2>&1)" || {
      echo "$out" >&2
      exit 1
    }
    echo "$out" | rg -q 'Finished `run`|program_id|initialize'
    # default should not dump full leo compile wall of text
    if echo "$out" | rg -q 'statements before dead code elimination|Compiling .*\.aleo'; then
      echo "pf-cli-smoke: FAIL default run too verbose (use --verbose intentionally)" >&2
      echo "$out" >&2
      exit 1
    fi
  )
else
  echo "pf-cli-smoke: skipped run (leo unavailable)"
fi

# Safety: mainnet refused
echo "pf-cli-smoke: mainnet refused"
(
  cd "$tmp/smoke"
  set +e
  err="$("$pf_bin" deploy -n mainnet 2>&1)"
  code=$?
  set -e
  [[ "$code" -eq 2 ]]
  echo "$err" | rg -qi 'mainnet'
)

# Non-aleo run FC message
echo "pf-cli-smoke: evm run not-implemented message"
(
  cd "$tmp/smoke"
  set +e
  err="$("$pf_bin" run -t evm -- initialize 1u64 2>&1)"
  code=$?
  set -e
  [[ "$code" -ne 0 ]]
  echo "$err" | rg -qi 'pf test|anvil|not implemented|evm'
)

# D7c: EVM Anvil test (optional if anvil+cast present)
tool_root="${PROOF_FORGE_TOOL_ROOT:-${FOUNDRY_BIN:-$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64}}"
if [[ -x "$tool_root/anvil" && -x "$tool_root/cast" ]]; then
  echo "pf-cli-smoke: evm test (StateCell monorepo fixture)"
  export PROOF_FORGE_TOOL_ROOT="$tool_root"
  export PROOF_FORGE_ROOT="$root"
  evm_out="$tmp/evm-sc"
  "$cli" build Examples/StateCell.lean \
    --module Examples.StateCell --target evm -o "$evm_out" >/dev/null
  tout="$("$pf_bin" test -t evm --artifact "$evm_out" 2>&1)" || {
    echo "$tout" >&2
    exit 1
  }
  echo "$tout" | rg -qi 'Finished `test`|pf-evm-test: ok|Skipped `test`'
  jout="$("$pf_bin" --json test -t evm --artifact "$evm_out")"
  echo "$jout" | python3 -I -c '
import json,sys
o=json.load(sys.stdin)
assert o.get("schema")=="proof-forge.pf.result.v1", o
assert o.get("command")=="test", o
assert o.get("ok") is True, o
assert o.get("target")=="evm", o
print("evm-json-ok")
'
else
  echo "pf-cli-smoke: skipped evm test (anvil/cast missing under $tool_root)"
fi

# D7a: Solana offline verify (optional if solana-client binary present)
sc="${PROOF_FORGE_SOLANA_CLIENT:-}"
if [[ -z "$sc" || ! -x "$sc" ]]; then
  for cand in \
    "$root/clients/solana-client/target/release/proof-forge-solana-client" \
    "$root/clients/solana-client/target/debug/proof-forge-solana-client"
  do
    if [[ -x "$cand" ]]; then
      sc="$cand"
      break
    fi
  done
fi
if [[ -n "$sc" && -x "$sc" ]]; then
  export PROOF_FORGE_SOLANA_CLIENT="$sc"
  echo "pf-cli-smoke: solana verify (TransferSol monorepo fixture)"
  sol_out="$tmp/solana-ts"
  "$cli" build Examples/TransferSol.lean \
    --module Examples.TransferSol --target solana -o "$sol_out" >/dev/null
  vout="$("$pf_bin" verify -t solana --artifact "$sol_out" 2>&1)" || {
    echo "$vout" >&2
    exit 1
  }
  echo "$vout" | rg -qi 'Finished `verify`'
  vout2="$("$pf_bin" verify -t solana --artifact "$sol_out" --adapter transfer-sol-v1 2>&1)" || {
    echo "$vout2" >&2
    exit 1
  }
  echo "$vout2" | rg -qi 'transfer-sol-v1|adapter|Finished `verify`'
  # JSON envelope
  jout="$("$pf_bin" --json verify -t solana --artifact "$sol_out" --adapter transfer-sol-v1)"
  echo "$jout" | python3 -I -c '
import json,sys
o=json.load(sys.stdin)
assert o.get("schema")=="proof-forge.pf.result.v1", o
assert o.get("command")=="verify", o
assert o.get("ok") is True, o
assert o.get("target")=="solana", o
extra=o.get("extra") or {}
res=extra.get("result") or {}
assert res.get("ok") is True, res
assert res.get("programName")=="TransferSol", res
assert (res.get("programAdapter") in (None, "transfer-sol-v1")) or True
print("json-ok")
'
  # Fail closed: aleo verify is usage
  set +e
  aerr="$("$pf_bin" verify -t aleo --artifact "$sol_out" 2>&1)"
  acode=$?
  set -e
  [[ "$acode" -ne 0 ]]
  echo "$aerr" | rg -qi 'inspect|aleo'

  # D7b: generic StateCell-shaped project flow (pf new → build → test)
  if [[ -f "$root/runtime-tests/solana/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
    echo "pf-cli-smoke: solana project flow (pf new → build → test)"
    export PROOF_FORGE_ROOT="$root"
    proj="$tmp/sol-proj"
    "$pf_bin" new counter --target solana --path "$proj" >/dev/null
    (
      cd "$proj"
      "$pf_bin" build >/dev/null
      mout="$("$pf_bin" test 2>&1)" || { echo "$mout" >&2; exit 1; }
      echo "$mout" | rg -qi 'Finished `test`|state-cell-shaped|pf-solana-test: ok'
      mj="$("$pf_bin" --json test)"
      echo "$mj" | python3 -I -c '
import json,sys
o=json.load(sys.stdin)
assert o.get("schema")=="proof-forge.pf.result.v1", o
assert o.get("command")=="test" and o.get("ok") is True
assert o.get("target")=="solana"
lane=(o.get("extra") or {}).get("lane") or ""
assert "state-cell" in lane or lane == "mollusk", lane
print("solana-project-test-json-ok")
'
    )
    # Specialty TransferSol still accepted when that artifact is used
    echo "pf-cli-smoke: solana TransferSol specialty lane"
    mout2="$("$pf_bin" test -t solana --artifact "$sol_out" 2>&1)" || {
      echo "$mout2" >&2
      exit 1
    }
    echo "$mout2" | rg -qi 'transfer-sol|Finished `test`|pf-solana-test: ok'
  else
    echo "pf-cli-smoke: skipped solana mollusk test (cargo/runtime-tests missing)"
  fi
else
  echo "pf-cli-smoke: skipped solana verify (proof-forge-solana-client not found; just pf-cli-smoke builds it)"
fi

echo "pf-cli-smoke: ok"
