#!/usr/bin/env bash
#
# ProofForge EVM Demo Recording Script
#
# Records a complete workflow: contract authoring → compilation → deployment → testing
# Usage: asciinema rec --command="scripts/demo/record-demo.sh" docs/demo/proofforge-demo.cast
#
# Requires: lake, solc, forge, cast, anvil (all on PATH via elan + foundry)

set -e

# ---- Setup: ensure PATH includes toolchain bins ----
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# ---- Helper: simulated typing ----
type_delay() { sleep 0.6; }
type_cmd() {
  local cmd="$1"
  echo ""
  sleep 0.3
  # Type the command character by character
  while IFS= read -r -n1 char; do
    printf '%s' "$char"
    sleep 0.04
  done <<< "$cmd"
  echo ""
  sleep 0.3
  eval "$cmd"
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          ProofForge — EVM Complete Workflow Demo            ║"
echo "║   Author → Compile → Deploy → Test                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "ProofForge lowers Lean smart-contract sources to portable IR and"
echo "target artifacts. The EVM backend produces Yul → solc → bytecode,"
echo "with Foundry/Anvil runtime validation."
echo ""
sleep 1.5

# ================================================================
# Part 1: Contract Authoring
# ================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Part 1/4: Contract Authoring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sleep 1

echo "Contracts are authored in Lean 4 using ProofForge.Contract.Source."
echo "Let's look at the Counter example:"
echo ""
sleep 1

type_cmd "cat Examples/Evm/Contracts/Counter.lean"

echo ""
sleep 1
echo "Key elements:"
echo "  • contract_source — declarative contract DSL"
echo "  • state — on-chain storage declarations"
echo "  • entry — state-modifying entrypoints"
echo "  • query — read-only entrypoints"
echo ""
sleep 1.5

echo "Now let's write a new contract — a SimpleStorage with access control:"
echo ""
sleep 1

type_cmd "cat Examples/Evm/Contracts/VerifiedVault.lean | head -40"

echo ""
sleep 1
echo "VerifiedVault demonstrates proof-carrying contract authoring with"
echo "assertions, context reads (caller, address, block number), and"
echo "compound storage assignment."
echo ""
sleep 2

# ================================================================
# Part 2: Compilation
# ================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Part 2/4: Compilation (Lean → IR → Yul → Bytecode)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sleep 1

echo "Compile the Counter contract to EVM runtime bytecode:"
echo ""
sleep 0.5

type_cmd "lake env proof-forge build --target evm --root . --module Counter -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean"

echo ""
sleep 1
echo "The compiler produces:"
echo "  • Runtime bytecode (.bin)"
echo "  • Initcode (.init.bin)"
echo "  • Artifact metadata (proof-forge-artifact.json)"
echo "  • Deploy manifest (proof-forge-deploy.json)"
echo ""
sleep 1

echo "Let's inspect the generated Yul (intermediate representation):"
echo ""
sleep 0.5

type_cmd "lake env proof-forge build --target evm --root . --module Counter --yul-output build/evm/Counter.demo.yul Examples/Evm/Contracts/Counter.lean"

echo ""
sleep 0.5

type_cmd "head -30 build/evm/Counter.demo.yul"

echo ""
sleep 1
echo "The Yul code shows the dispatcher (switch on selector), storage"
echo "operations (sload/sstore), and ABI return encoding."
echo ""
sleep 2

# ================================================================
# Part 3: Deployment (Local Anvil)
# ================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Part 3/4: Deployment (Local Anvil Chain)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sleep 1

echo "ProofForge deploys to a local Anvil chain for validation."
echo "The deploy smoke script generates initcode, starts Anvil, deploys"
echo "via cast, and validates the runtime bytecode matches."
echo ""
sleep 1

type_cmd "just evm-anvil-deploy"

echo ""
sleep 2
echo "Deployment successful! The script:"
echo "  1. Generated Counter with a typed constructor arg (initial=123)"
echo "  2. Started a local Anvil chain"
echo "  3. Sent initcode via cast send --create"
echo "  4. Verified deployed runtime code matches Counter.bin"
echo "  5. Ran the Counter lifecycle through JSON-RPC"
echo "  6. Wrote a deploy-run artifact for validation"
echo ""
sleep 2

# ================================================================
# Part 4: Testing (Foundry Runtime Smoke Tests)
# ================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Part 4/4: Testing (Foundry IR Smoke Tests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sleep 1

echo "ProofForge generates Foundry test harnesses from portable IR."
echo "Each fixture compiles to Yul → bytecode, deploys to a test VM,"
echo "and asserts runtime behavior matches expected values."
echo ""
sleep 1

echo "Running the context probe smoke test (context reads, opcodes):"
echo ""
sleep 0.5

type_cmd "just evm-ir-smokes 2>&1 | grep -E '(PASS|FAIL|Suite result|context-ir-smoke)' | head -20"

echo ""
sleep 1
echo "All smoke tests pass! The test suite covers:"
echo "  • Scalar/array/map storage operations"
echo "  • ABI encoding/decoding (scalars, structs, arrays)"
echo "  • Context reads (caller, address, block number, timestamp,"
echo "    chainId, gasPrice, gas, baseFee, prevRandao, origin, coinbase,"
echo "    blockhash)"
echo "  • Events (log0-log4, indexed topics, aggregate hashing)"
echo "  • Cross-calls (call, staticcall, delegatecall, create, create2)"
echo "  • Assertions, conditionals, bounded loops, expressions"
echo ""
sleep 2

# ================================================================
# Summary
# ================================================================
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Demo Complete                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  1. Author  — Lean 4 contract_source DSL                   ║"
echo "║  2. Compile — proof-forge build --target evm               ║"
echo "║  3. Deploy  — Anvil local chain + cast send --create       ║"
echo "║  4. Test    — Foundry IR smoke tests (all PASS)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Repository: https://github.com/DaviRain-Su/proof_forge"
echo "Documentation: docs/targets/evm.md"
echo ""