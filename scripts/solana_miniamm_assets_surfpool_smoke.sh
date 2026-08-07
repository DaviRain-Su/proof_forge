#!/usr/bin/env bash
# Surfpool local-chain smoke: MiniAmmAssets product ELF deploy + program show.
#
# Flow:
#   1. lake product build Examples/MiniAmmAssets → solana-sbpf-cpi-elf-v1 .so
#   2. start Surfpool (offline by default)
#   3. solana program deploy with local program keypair
#   4. solana program show / getAccountInfo executable check
#   5. tear down Surfpool
#
# Engineering only — not Mollusk multi-role CPI differential, not formal/mainnet.
# Full dual-mint invoke remains on runtime-tests/solana/tests/miniamm_assets.rs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() { echo "solana-miniamm-assets-surfpool: FAIL: $*" >&2; exit 1; }

# Prefer official Surfpool installer binary (1.x) over stale cargo 0.10.x.
if [[ -x "${HOME}/.local/bin/surfpool" ]]; then
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
fi
# Prefer Solana CLI matching Surfpool core (4.x). active_release after
# `sh -c "$(curl -sSfL https://release.anza.xyz/v4.1.2/install)"`.
if [[ -d "${HOME}/.local/share/solana/install/active_release/bin" ]]; then
  PATH="${HOME}/.local/share/solana/install/active_release/bin:${PATH}"
  export PATH
fi
for tool in surfpool solana solana-keygen; do
  command -v "$tool" >/dev/null 2>&1 || die "missing $tool on PATH"
done
echo "solana-miniamm-assets-surfpool: surfpool=$(command -v surfpool) $($(command -v surfpool) --version 2>/dev/null | head -1)" >&2
echo "solana-miniamm-assets-surfpool: solana=$(command -v solana) $(solana --version 2>/dev/null | head -1)" >&2
# Soft version gate: Surfpool 1.5 embeds solana-core 4.1.x; CLI 3.x cannot deploy SBPFv3 ELFs.
solana_ver="$(solana --version 2>/dev/null || true)"
if [[ "$solana_ver" != *"4."* && "$solana_ver" != *"5."* ]]; then
  die "need Solana CLI 4.x+ matching Surfpool core (got: $solana_ver); install: sh -c \"\$(curl -sSfL https://release.anza.xyz/v4.1.2/install)\""
fi

cli="$root/.lake/build/bin/proof-forge-next"
if [[ ! -x "$cli" ]]; then
  echo "solana-miniamm-assets-surfpool: building proof-forge-next..." >&2
  lake build proof_forge_next || die "lake build proof_forge_next failed"
fi
[[ -x "$cli" ]] || die "proof-forge-next missing after build"

case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *) die "unsupported host $(uname -s)" ;;
esac
tool_root="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
[[ -x "$tool_root/sbpf" || -f "$tool_root/sbpf" ]] || die "sbpf missing under $tool_root"

out_rel="build/v2/solana-miniamm-assets-surfpool"
out="$root/$out_rel"
program_name="MiniAmmAssets"
elf="$out/${program_name}.so"

# --- product build ----------------------------------------------------------
if [[ -n "${PROOF_FORGE_MINIAMM_ASSETS_OUT:-}" && -f "${PROOF_FORGE_MINIAMM_ASSETS_OUT}/${program_name}.so" ]]; then
  out="$PROOF_FORGE_MINIAMM_ASSETS_OUT"
  elf="$out/${program_name}.so"
  echo "solana-miniamm-assets-surfpool: reusing product tree $out" >&2
else
  echo "solana-miniamm-assets-surfpool: building MiniAmmAssets (cpi-elf) → $out_rel" >&2
  rm -rf "$out"
  lake env "$cli" build Examples/MiniAmmAssets.lean \
    --module Examples.MiniAmmAssets \
    --target solana \
    --profile solana-sbpf-cpi-elf-v1 \
    -o "$out_rel" \
    || die "product build failed"
fi
[[ -f "$elf" ]] || die "missing $elf"
# ELF magic
head_bytes="$(xxd -p -l 4 "$elf" 2>/dev/null || od -An -tx1 -N4 "$elf" | tr -d ' \n')"
echo "$head_bytes" | grep -qi '7f454c46' || die "not an ELF: $elf"
elf_size="$(wc -c <"$elf" | tr -d ' ')"
echo "solana-miniamm-assets-surfpool: elf=${elf_size}B" >&2

surf_dir="$root/runtime-tests/solana/surfpool"
# Always stop on exit.
cleanup() {
  bash "$root/scripts/solana_surfpool_down.sh" || true
}
trap cleanup EXIT

# --- start Surfpool ---------------------------------------------------------
export SURFPOOL_NETWORK="${SURFPOOL_NETWORK:-offline}"
# Diagnostics on stderr; authoritative RPC is written to rpc-url.txt.
bash "$root/scripts/solana_surfpool_up.sh" >/dev/null
rpc_file="$surf_dir/rpc-url.txt"
[[ -f "$rpc_file" ]] || die "missing $rpc_file after surfpool up"
rpc="$(tr -d '[:space:]' <"$rpc_file")"
[[ "$rpc" == http://* || "$rpc" == https://* ]] || die "bad rpc url: $rpc"
payer_kp="$surf_dir/keys/payer.json"
program_kp="$surf_dir/keys/program.json"
[[ -f "$payer_kp" && -f "$program_kp" ]] || die "keypairs missing after up"
program_id="$(solana-keygen pubkey "$program_kp")"
payer_pk="$(solana-keygen pubkey "$payer_kp")"

echo "solana-miniamm-assets-surfpool: rpc=$rpc program_id=$program_id" >&2

# Balance check (airdrop should have funded payer).
bal="$(solana balance "$payer_pk" --url "$rpc" 2>/dev/null | awk '{print $1}')"
echo "solana-miniamm-assets-surfpool: payer balance=${bal:-?} SOL" >&2

# --- deploy -----------------------------------------------------------------
echo "solana-miniamm-assets-surfpool: deploying $elf ..." >&2
deploy_log="$(mktemp "${TMPDIR:-/tmp}/pf-surf-deploy.XXXXXX.log")"
set +e
# With surfpool ≥1.x + --features-all (see solana_surfpool_up.sh), SBPFv3 is
# active and product ELFs deploy without --skip-feature-verify.
solana program deploy "$elf" \
  --url "$rpc" \
  --keypair "$payer_kp" \
  --program-id "$program_kp" \
  --max-len "$((elf_size + 65536))" \
  >"$deploy_log" 2>&1
deploy_rc=$?
set -e
if [[ "$deploy_rc" -ne 0 ]]; then
  echo "solana-miniamm-assets-surfpool: deploy failed (rc=$deploy_rc):" >&2
  cat "$deploy_log" >&2
  rm -f "$deploy_log"
  exit 1
fi
# Capture signature if present.
sig="$(rg -o 'Signature: *\S+' "$deploy_log" | awk '{print $2}' | head -1 || true)"
rm -f "$deploy_log"
echo "solana-miniamm-assets-surfpool: deploy ok program_id=$program_id sig=${sig:-n/a}" >&2

# --- program show / executable account --------------------------------------
show_out="$(solana program show "$program_id" --url "$rpc" --keypair "$payer_kp" 2>&1)" \
  || die "program show failed: $show_out"
echo "$show_out" | head -20 >&2
echo "$show_out" | grep -qi 'Program Id' || die "program show missing Program Id"
# getAccountInfo must report executable.
info_json="$(curl -sS "$rpc" -X POST -H 'Content-Type: application/json' -d "{
  \"jsonrpc\":\"2.0\",\"id\":1,
  \"method\":\"getAccountInfo\",
  \"params\":[\"$program_id\",{\"encoding\":\"base64\"}]
}")"
/usr/bin/python3 -I -S -c "
import json,sys
d=json.load(sys.stdin)
val=(d.get('result') or {}).get('value')
assert val is not None, f'account missing: {d}'
# Program account may be the program data; Loader often stores executable=true on the program id.
exec_flag = val.get('executable')
# Accept either executable program account or non-null owner (BPF loader).
owner = val.get('owner') or ''
ok = bool(exec_flag) or owner in (
  'BPFLoaderUpgradeab1e11111111111111111111111',
  'BPFLoader2111111111111111111111111111111111',
  'BPFLoader1111111111111111111111111111111111',
)
assert ok, f'not a program account: executable={exec_flag} owner={owner}'
print('account_ok executable=%s owner=%s' % (exec_flag, owner))
" <<<"$info_json" || die "getAccountInfo check failed: $info_json"

# Record deploy for operators.
record="$surf_dir/deployed.json"
/usr/bin/python3 -I -S -c "
import json
print(json.dumps({
  'programId': '''$program_id''',
  'payer': '''$payer_pk''',
  'rpc': '''$rpc''',
  'elf': '''$elf''',
  'elfBytes': int('''$elf_size'''),
  'signature': '''${sig:-}''' or None,
  'networkMode': '''$SURFPOOL_NETWORK''',
  'source': 'Examples/MiniAmmAssets.lean',
  'profile': 'solana-sbpf-cpi-elf-v1',
  'note': 'engineering Surfpool deploy smoke; not Mollusk CPI differential',
}, indent=2))
" >"$record"
echo "solana-miniamm-assets-surfpool: wrote $record" >&2

echo "solana-miniamm-assets-surfpool: ok (deploy + show on Surfpool)" >&2
echo "solana-miniamm-assets-surfpool: engineering only; multi-role invoke = Mollusk miniamm_assets" >&2
