import ProofForge.Cli

namespace ProofForge.Tests.CliTargetFirst

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireLegacy (args expected : List String) : IO Unit := do
  let cmd : String := args.head!
  let rest : List String := args.tail
  if cmd.isEmpty then
    throw <| IO.userError "requireLegacy: empty args"
  let state ← match ProofForge.Cli.parseNewOptions rest {} with
    | .ok state => pure state
    | .error err => throw <| IO.userError s!"unexpected CLI parse error: {err}"
  match ProofForge.Cli.newCommandArgsToLegacy state cmd with
  | .ok got =>
      require (got == expected) s!"legacy args mismatch: got {repr got}, expected {repr expected}"
  | .error err =>
      throw <| IO.userError s!"unexpected CLI mapping error: {err}"

def requireErrorContains (args : List String) (needles : Array String) : IO Unit := do
  let cmd : String := args.head!
  let rest : List String := args.tail
  if cmd.isEmpty then
    throw <| IO.userError "requireErrorContains: empty args"
  let state ← match ProofForge.Cli.parseNewOptions rest {} with
    | .ok state => pure state
    | .error err => throw <| IO.userError s!"unexpected CLI parse error: {err}"
  match ProofForge.Cli.newCommandArgsToLegacy state cmd with
  | .ok got =>
      throw <| IO.userError s!"expected CLI mapping error, got {repr got}"
  | .error err =>
      for needle in needles do
        require (err.contains needle) s!"CLI mapping error `{err}` missing `{needle}`"

def main : IO UInt32 := do
  require
    ((ProofForge.Cli.defaultBytecodeYulOutput (System.FilePath.mk "build/evm/Counter.bin")).toString == "build/evm/Counter.yul")
    "EVM bytecode build should default Yul output next to the bytecode output"
  requireLegacy
    ["build", "--target", "evm", "--root", ".", "--module", "contract", "-o", "build/evm/Counter.bin", "Examples/Evm/Contracts/Counter.lean"]
    ["--evm-bytecode", "-o", "build/evm/Counter.bin", "--root", ".", "--module", "contract", "--solc", "solc", "--cast", "cast", "Examples/Evm/Contracts/Counter.lean"]
  requireLegacy
    ["build", "--target", "evm", "--format", "yul", "-o", "build/evm/ValueVault.yul", "Examples/Learn/ValueVault.learn"]
    ["--learn-yul", "-o", "build/evm/ValueVault.yul", "Examples/Learn/ValueVault.learn"]
  requireLegacy
    ["emit", "--target", "evm", "--fixture", "counter", "--format", "yul", "-o", "build/ir/Counter.yul"]
    ["--emit-counter-ir-yul", "-o", "build/ir/Counter.yul"]
  requireLegacy
    ["build", "--target", "evm", "--fixture", "counter", "--format", "bytecode", "-o", "build/sdk/evm"]
    ["--emit-counter-ir-bytecode", "-o", "build/sdk/evm/Counter.bin", "--yul-output", "build/sdk/evm/Counter.yul", "--solc", "solc", "--cast", "cast"]
  requireLegacy
    ["emit", "--target", "evm", "--fixture", "evm-event", "--format", "bytecode", "--yul-output", "build/ir/EventProbe.yul", "--artifact-output", "build/ir/EventProbe.json", "-o", "build/ir/EventProbe.bin"]
    ["--emit-evm-event-ir-bytecode", "-o", "build/ir/EventProbe.bin", "--yul-output", "build/ir/EventProbe.yul", "--artifact-output", "build/ir/EventProbe.json", "--solc", "solc", "--cast", "cast"]
  requireLegacy
    ["build", "--target", "solana-sbpf-asm", "--fixture", "counter", "-o", "build/sdk/solana-sbpf-asm"]
    ["--emit-counter-ir-sbpf", "-o", "build/sdk/solana-sbpf-asm/Counter.s"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "s"]
    ["--emit-solana-system-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi"]
    ["--emit-solana-system-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "elf"]
    ["--solana-system-cpi-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "solana-memo-cpi", "--format", "elf"]
    ["--solana-memo-cpi-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "elf", "--solana-sbpf-arch", "v0"]
    ["--solana-system-cpi-elf", "--solana-sbpf-arch", "v0"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-ops-cpi", "--format", "s"]
    ["--emit-solana-spl-token-ops-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-ops-cpi"]
    ["--emit-solana-spl-token-ops-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-close-account-cpi", "--format", "s"]
    ["--emit-solana-spl-token-close-account-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-close-account-cpi", "--format", "elf"]
    ["--solana-spl-token-close-account-cpi-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-2022-transfer-hook", "--format", "s"]
    ["--emit-solana-spl-token-2022-transfer-hook-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-2022-transfer-hook", "--format", "elf"]
    ["--solana-spl-token-2022-transfer-hook-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "counter", "--format", "elf"]
    ["--solana-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "solana-sdk", "--format", "s"]
    ["--emit-solana-sdk-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "associated-token-cpi", "--format", "s"]
    ["--emit-solana-associated-token-cpi-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "associated-token-cpi", "--format", "elf"]
    ["--solana-associated-token-cpi-elf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "value-vault", "--format", "s"]
    ["--emit-value-vault-ir-sbpf"]
  requireLegacy
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "value-vault", "--format", "elf"]
    ["--value-vault-solana-elf"]
  requireLegacy
    ["emit", "--target", "wasm-near", "--fixture", "counter", "--format", "wat", "-o", "build/wasm-near/counter"]
    ["--emit-counter-emitwat", "-o", "build/wasm-near/counter"]
  requireLegacy
    ["build", "--target", "wasm-near", "--fixture", "context", "--format", "wat", "-o", "build/wasm-near/context"]
    ["--emit-context-emitwat", "-o", "build/wasm-near/context"]
  requireLegacy
    ["build", "--target", "solana-sbpf-asm", "--root", ".", "-o", "build/portable-counter/Counter.s", "Examples/Shared/Counter.lean"]
    ["--contract-source-sbpf", "-o", "build/portable-counter/Counter.s", "--root", ".", "Examples/Shared/Counter.lean"]
  requireLegacy
    ["build", "--target", "wasm-near", "--root", ".", "-o", "build/portable-counter/near", "Examples/Shared/Counter.lean"]
    ["--contract-source-emitwat", "-o", "build/portable-counter/near", "--root", ".", "Examples/Shared/Counter.lean"]
  requireLegacy
    ["emit", "--target", "psy-dpn", "--fixture", "assert", "--format", "psy", "-o", "build/psy/AssertProbe.psy"]
    ["--emit-assert-ir-psy", "-o", "build/psy/AssertProbe.psy"]
  requireLegacy
    ["emit", "--target", "aleo-leo", "--fixture", "pure-math", "--format", "leo", "-o", "build/aleo/PureMath.leo"]
    ["--emit-pure-math-ir-leo", "-o", "build/aleo/PureMath.leo"]
  requireLegacy
    ["emit", "--target", "move-aptos", "--fixture", "counter", "--format", "aptos", "-o", "build/aptos-counter"]
    ["--emit-counter-ir-aptos", "-o", "build/aptos-counter"]
  requireLegacy
    ["build", "--target", "move-sui", "--fixture", "counter", "-o", "build/sdk/move-sui"]
    ["--emit-counter-ir-sui", "-o", "build/sdk/move-sui"]
  requireLegacy
    ["emit", "--target", "move-sui", "--fixture", "counter", "--format", "sui", "-o", "build/sdk/move-sui"]
    ["--emit-counter-ir-sui", "-o", "build/sdk/move-sui"]
  requireErrorContains
    ["emit", "--target", "move-sui", "--fixture", "counter", "--format", "aptos", "-o", "build/sdk/move-sui"]
    #["move-sui", "aptos", "sui"]
  requireErrorContains
    ["build", "--target", "move-sui", "--fixture", "value-vault", "-o", "build/sdk/move-sui"]
    #["move-sui", "value-vault", "not yet implemented"]
  requireErrorContains
    ["emit", "--target", "move-sui", "--fixture", "value-vault", "--format", "sui", "-o", "build/sdk/move-sui"]
    #["move-sui", "value-vault", "not yet mapped"]
  requireErrorContains
    ["build", "--target", "move-sui", "--root", ".", "-o", "build/source-sdk/move-sui", "Examples/Shared/Counter.lean"]
    #["move-sui", "source", "out of scope"]
  requireLegacy
    ["emit", "--target", "wasm-cloudflare-workers", "--fixture", "counter", "--format", "ts"]
    ["--emit-counter-ir-ts"]

  IO.println "cli-target-first: ok"
  return 0

end ProofForge.Tests.CliTargetFirst

-- This test imports the executable CLI module, whose root `main` would otherwise
-- run after elaboration and print usage. Exit from the test result instead.
#eval (do
  let exitCode ← ProofForge.Tests.CliTargetFirst.main
  IO.Process.exit exitCode.toUInt8
  pure () : IO Unit)
