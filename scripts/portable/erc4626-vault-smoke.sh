#!/usr/bin/env bash
# Wave ε Layer C: ERC-4626 stdlib vault body multi-target smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${PROOF_FORGE_ERC4626_OUT:-build/portable/erc4626-vault}"
DRIVER="$OUT/emit.lean"

fail() { echo "FAIL: $1" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing $1"; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$3 missing '$2' in $1"; }

command -v lake >/dev/null 2>&1 || fail "lake not on PATH"
rm -rf "$OUT"
mkdir -p "$OUT/evm" "$OUT/solana" "$OUT/near"

echo "=== product-erc4626-vault: build stdlib ==="
lake build ProofForge.Contract.Stdlib.ERC4626 ProofForge.Backend.Evm.IR \
  ProofForge.Backend.Solana.SbpfAsm ProofForge.Backend.WasmHost.EmitWat >/dev/null \
  || fail "lake build ERC4626 failed"

cat >"$DRIVER" <<'EOF'
import ProofForge.Contract.Stdlib.ERC4626
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat

def require (c : Bool) (m : String) : IO Unit :=
  if c then pure () else throw (IO.userError m)

def main : IO Unit := do
  let m := ProofForge.Contract.Stdlib.ERC4626.module
  require (m.entrypoints.any (·.name == "deposit")) "has deposit"
  require (m.entrypoints.any (·.name == "withdraw")) "has withdraw"
  require (m.entrypoints.any (·.name == "convertToShares")) "has convertToShares"
  require (m.entrypoints.any (·.name == "totalAssets")) "has totalAssets"
  require (m.entrypoints.any (·.name == "asset")) "has asset"
  -- deposit must mention IERC20 transferFrom selector path (remote)
  require (m.capabilities.any (· == .crosscallInvoke)) "deposit pulls via crosscall"
  require (m.state.any (fun s => s.id == "totalAssets")) "totalAssets state"
  require (m.state.any (fun s => s.id == "shareBalances") ||
    m.state.any (fun s => s.id == "totalSupply")) "share state"
  -- EVM plan
  match ProofForge.Backend.Evm.Plan.buildModulePlan m with
  | .error e => throw (IO.userError s!"EVM plan: {e.message}")
  | .ok _ => pure ()
  -- Pin selectors for Yul emit (product modules are name-only)
  let mEvm : ProofForge.IR.Module := {
    m with
    entrypoints := m.entrypoints.map fun ep =>
      match ep.name with
      | "init" => { ep with selector? := some "4b180da9" }
      | "deposit" => { ep with selector? := some "6e553f65" }
      | "mint" => { ep with selector? := some "94bf804d" }
      | "withdraw" => { ep with selector? := some "b460af94" }
      | "redeem" => { ep with selector? := some "ba087652" }
      | "convertToShares" => { ep with selector? := some "c6e6f592" }
      | "convertToAssets" => { ep with selector? := some "07a2d13a" }
      | "totalAssets" => { ep with selector? := some "01e1d114" }
      | "asset" => { ep with selector? := some "38d52e0f" }
      | "totalSupply" => { ep with selector? := some "18160ddd" }
      | "balanceOf" => { ep with selector? := some "70a08231" }
      | "maxDeposit" => { ep with selector? := some "402d267d" }
      | "maxMint" => { ep with selector? := some "c63d75b6" }
      | "maxWithdraw" => { ep with selector? := some "ce96cb77" }
      | "maxRedeem" => { ep with selector? := some "d905777e" }
      | "previewDeposit" => { ep with selector? := some "ef8b30f7" }
      | "previewMint" => { ep with selector? := some "b3d7f6b9" }
      | "previewWithdraw" => { ep with selector? := some "0a28a477" }
      | "previewRedeem" => { ep with selector? := some "4cdad506" }
      -- non-standard fee surface (fixture pins only)
      | "feeBps" => { ep with selector? := some "f0fdf834" }
      | "feeRecipient" => { ep with selector? := some "46904840" }
      | "transfer" => { ep with selector? := some "a9059cbb" }
      | "approve" => { ep with selector? := some "095ea7b3" }
      | _ => ep
  }
  match ProofForge.Backend.Evm.IR.renderModule mEvm with
  | .error e => throw (IO.userError s!"EVM Yul: {e.message}")
  | .ok yul =>
      IO.FS.writeFile "build/portable/erc4626-vault/evm/ERC4626.yul" yul
      -- transferFrom selector 0x23b872dd = 599290589
      require (yul.contains "599290589")
        "yul should pack IERC20 transferFrom remote for deposit pull"
      -- balanceOf selector 0x70a08231 = 1889567281 (fee-on-transfer delta)
      require (yul.contains "1889567281")
        "yul should pack IERC20 balanceOf for FOT delta measure"
      -- pro-rata convert uses mul/div (not identity-only)
      require (yul.contains "mul(" || yul.contains "mul ")
        "yul should emit mul for pro-rata convert"
      require (yul.contains "div(" || yul.contains "div ")
        "yul should emit div for pro-rata convert"
  match ProofForge.Backend.Solana.SbpfAsm.renderModule m with
  | .ok _ => throw (IO.userError "Solana should reject EVM-primary IERC20 selector remotes")
  | .error e =>
      require (e.message.contains "peer" || e.message.contains "remote" ||
          e.message.contains "PortableHonesty")
        s!"Solana diagnostic: {e.message}"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule m with
  | .ok _ => throw (IO.userError "NEAR should honest-reject selector remotes without string pool")
  | .error e =>
      require (e.message.contains "nearCrosscallStrings" || e.message.contains "crosscall" ||
          e.message.contains "Address")
        s!"NEAR diagnostic: {e.message}"
  IO.println "erc4626-vault emit: ok"
EOF

echo "=== product-erc4626-vault: multi-target emit ==="
lake env lean --run "$DRIVER" || fail "emit driver failed"
require_file "$OUT/evm/ERC4626.yul"
# transferFrom selector decimal
require_contains "$OUT/evm/ERC4626.yul" "599290589" "EVM IERC20 transferFrom selector in deposit"

echo "product-erc4626-vault: ok (EVM body; Solana/NEAR non-native body honest reject)"
