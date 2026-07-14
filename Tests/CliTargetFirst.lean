import ProofForge.Cli
import ProofForge.Cli.LegacyArgs

namespace ProofForge.Tests.CliTargetFirst

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireLegacyArgs (args expected : List String) : IO Unit := do
  let cmd : String := args.head!
  let rest : List String := args.tail
  if cmd.isEmpty then
    throw <| IO.userError "requireLegacyArgs: empty args"
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

def requireBuildErrorContains (args : List String) (needles : Array String) : IO Unit := do
  let state ← match ProofForge.Cli.parseNewOptions args {} with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"parse failed: {e}"
  let (target, req) ← match ProofForge.Cli.resolveBuildRequest state with
    | .ok r => pure r
    | .error e => throw <| IO.userError e
  match ProofForge.Cli.resolveBuild target req with
  | .ok r =>
      throw <| IO.userError s!"expected build resolve error, got {repr r}"
  | .error e =>
      for needle in needles do
        require (e.contains needle) s!"build resolve error `{e}` missing `{needle}`"

def requireNftNative (target : String) (input : String) : IO Unit := do
  let state ← match ProofForge.Cli.parseNewOptions ["--target", target, "--nft", input] {} with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"parse failed: {e}"
  let (gotTarget, req) ← match ProofForge.Cli.resolveBuildRequest state with
    | .ok r => pure r
    | .error e => throw <| IO.userError e
  unless gotTarget == target do
    throw <| IO.userError s!"target mismatch: {gotTarget} != {target}"
  match ProofForge.Cli.resolveBuild gotTarget req with
  | .ok { dispatchKind := .native, nativeOp? := some op, .. } =>
      let expectedOp ← match target with
        | "evm" => pure ProofForge.Cli.NativeBuildOp.nftEvmBytecode
        | "solana-sbpf-asm" => pure ProofForge.Cli.NativeBuildOp.nftSolanaSbpf
        | "wasm-near" => pure ProofForge.Cli.NativeBuildOp.nftNearEmitWat
        | _ => throw <| IO.userError s!"unexpected native target {target}"
      unless op == expectedOp do
        throw <| IO.userError s!"native op mismatch for {target}: {repr op}"
  | .ok other =>
      throw <| IO.userError s!"expected native dispatch for {target}, got {repr other}"
  | .error e =>
      throw <| IO.userError s!"resolve failed for {target}: {e}"

def requireEvmCanonicalYulNative (input : String) : IO Unit := do
  let state ← match ProofForge.Cli.parseNewOptions
      ["--target", "evm", "--format", "yul", input] {} with
    | .ok state => pure state
    | .error error => throw <| IO.userError s!"parse failed: {error}"
  let (target, request) ← match ProofForge.Cli.resolveBuildRequest state with
    | .ok result => pure result
    | .error error => throw <| IO.userError error
  match ProofForge.Cli.resolveBuild target request with
  | .ok { dispatchKind := .native, nativeOp? := some .evmCanonicalYul, .. } =>
      let opts ← match ProofForge.Cli.buildNativeOptions state .evmCanonicalYul with
        | .ok opts => pure opts
        | .error error => throw <| IO.userError error
      require (!opts.nft) "canonical EVM Yul dispatch must not set the NFT source mode"
      require (opts.mode == .yul) "canonical EVM Yul dispatch selected the wrong compiler mode"
  | .ok other =>
      throw <| IO.userError s!"expected native canonical EVM Yul dispatch, got {repr other}"
  | .error error => throw <| IO.userError error

def requireLegacy (target : String) (fixture? : Option String := none) : IO Unit := do
  let args := ["--target", target] ++ fixture?.toList.flatMap (fun f => ["--fixture", f])
  let state ← match ProofForge.Cli.parseNewOptions args {} with
    | .ok s => pure s
    | .error e => throw <| IO.userError e
  let (gotTarget, req) ← match ProofForge.Cli.resolveBuildRequest state with
    | .ok r => pure r
    | .error e => throw <| IO.userError e
  match ProofForge.Cli.resolveBuild gotTarget req with
  | .ok { dispatchKind := .legacy, legacyFlag? := some _, .. } => pure ()
  | .ok other => throw <| IO.userError s!"expected legacy dispatch for {target}, got {repr other}"
  | .error e => throw <| IO.userError e

def requireEmitWatTarget
    (targetId? : Option String)
    (expectedId : String)
    (expectedBridge : ProofForge.Target.HostBridge) : IO Unit := do
  match ProofForge.Cli.resolveEmitWatTarget { targetId? := targetId? } with
  | .ok (profile, bridge) =>
      require (profile.id == expectedId && bridge == expectedBridge)
        s!"EmitWat target resolution mismatch for {repr targetId?}"
  | .error err =>
      throw <| IO.userError s!"unexpected EmitWat target error for {repr targetId?}: {err}"

def requireEmitWatTargetError (targetId : String) : IO Unit := do
  match ProofForge.Cli.resolveEmitWatTarget { targetId? := some targetId } with
  | .ok (profile, _) =>
      throw <| IO.userError s!"invalid EmitWat target {targetId} resolved as {profile.id}"
  | .error err =>
      require (err.contains "EmitWat target")
        s!"invalid EmitWat target {targetId} returned unrelated error: {err}"

def requireEmitWatPlanTargetCheck
    (profileId planTargetId : String) (shouldPass : Bool) : IO Unit := do
  let profile ← match ProofForge.Cli.resolveEmitWatTarget { targetId? := some profileId } with
    | .ok (profile, _) => pure profile
    | .error err => throw <| IO.userError s!"unexpected profile resolution error: {err}"
  let result := ProofForge.Cli.requireEmitWatPlanTarget profile {
    targetId := planTargetId
    calls := #[]
  }
  match result, shouldPass with
  | .ok (), true => pure ()
  | .error err, false =>
      require (err.contains planTargetId && err.contains profileId)
        s!"plan-target mismatch diagnostic lacks both targets: {err}"
  | .ok (), false =>
      throw <| IO.userError s!"EmitWat plan target {planTargetId} unexpectedly matched {profileId}"
  | .error err, true =>
      throw <| IO.userError s!"EmitWat plan target {planTargetId} unexpectedly rejected: {err}"

def main : IO UInt32 := do
  requireEvmCanonicalYulNative "Examples/Product/Canonical/Counter.lean"
  match ProofForge.Cli.parseArgs
      ["--emit-error-ref-emitwat", "--target", "wasm-near"] {} with
  | .ok opts =>
      require (opts.mode == .errorRefEmitWat && opts.targetId? == some "wasm-near")
        "error-ref EmitWat mode rejected or lost --target"
  | .error err =>
      throw <| IO.userError s!"error-ref EmitWat mode rejected --target: {err}"
  requireEmitWatTarget none "wasm-near" .near
  requireEmitWatTarget (some "wasm-near") "wasm-near" .near
  requireEmitWatTarget (some "wasm-cosmwasm") "wasm-cosmwasm" .cosmWasm
  requireEmitWatTarget (some "wasm-stellar-soroban") "wasm-stellar-soroban" .soroban
  for targetId in #["not-a-target", "evm-core", "solana-sbpf-asm-core", "wasm-near-core",
      "evm", "wasm-cloudflare-workers"] do
    requireEmitWatTargetError targetId
  requireEmitWatPlanTargetCheck "wasm-near" "wasm-near" true
  requireEmitWatPlanTargetCheck "wasm-near" "wasm-cosmwasm" false
  requireErrorContains
    ["check", "--target", "evm"]
    #["native dispatch", "does not use the legacy mapper"]
  require
    ((ProofForge.Cli.defaultBytecodeYulOutput (System.FilePath.mk "build/evm/Counter.bin")).toString == "build/evm/Counter.yul")
    "EVM bytecode build should default Yul output next to the bytecode output"
  require
    (ProofForge.Cli.Fixture.isWasmNearFixture "context" &&
      !ProofForge.Cli.Fixture.isWasmNearFixture "value-vault")
    "Wasm-NEAR fixture helper should preserve the target-first legacy mapping boundary"
  require
    (ProofForge.Cli.Fixture.supportsFormat "solana-sbpf-asm" "system-cpi" .elf &&
      ProofForge.Cli.Fixture.supportsFormat "psy-dpn" "assert" .psy &&
      !ProofForge.Cli.Fixture.supportsFormat "psy-dpn" "assert" .wat)
    "fixture support helpers should preserve Solana/Psy format boundaries"
  requireLegacyArgs
    ["build", "--target", "evm", "--root", ".", "--module", "contract", "-o", "build/evm/Counter.bin", "Examples/Backend/Evm/Contracts/Counter.lean"]
    ["--evm-bytecode", "-o", "build/evm/Counter.bin", "--root", ".", "--module", "contract", "--solc", "solc", "--cast", "cast", "Examples/Backend/Evm/Contracts/Counter.lean"]
  requireLegacyArgs
    ["build", "--target", "evm", "--format", "yul", "-o", "build/evm/ValueVault.yul", "Examples/Backend/Learn/ValueVault.learn"]
    ["--learn-yul", "-o", "build/evm/ValueVault.yul", "Examples/Backend/Learn/ValueVault.learn"]
  requireLegacyArgs
    ["emit", "--target", "evm", "--fixture", "counter", "--format", "yul", "-o", "build/ir/Counter.yul"]
    ["--emit-counter-ir-yul", "-o", "build/ir/Counter.yul"]
  requireLegacyArgs
    ["build", "--target", "evm", "--fixture", "counter", "--format", "bytecode", "-o", "build/sdk/evm"]
    ["--emit-counter-ir-bytecode", "-o", "build/sdk/evm/Counter.bin", "--yul-output", "build/sdk/evm/Counter.yul", "--solc", "solc", "--cast", "cast"]
  requireLegacyArgs
    ["emit", "--target", "evm", "--fixture", "value-vault", "--format", "bytecode",
      "--yul-output", "build/ir/ValueVault.yul", "--artifact-output", "build/ir/ValueVault.json",
      "-o", "build/ir/ValueVault.bin"]
    ["--emit-value-vault-ir-bytecode", "-o", "build/ir/ValueVault.bin",
      "--yul-output", "build/ir/ValueVault.yul", "--artifact-output", "build/ir/ValueVault.json",
      "--solc", "solc", "--cast", "cast"]
  requireLegacyArgs
    ["emit", "--target", "evm", "--fixture", "evm-event", "--format", "bytecode", "--yul-output", "build/ir/EventProbe.yul", "--artifact-output", "build/ir/EventProbe.json", "-o", "build/ir/EventProbe.bin"]
    ["--emit-evm-event-ir-bytecode", "-o", "build/ir/EventProbe.bin", "--yul-output", "build/ir/EventProbe.yul", "--artifact-output", "build/ir/EventProbe.json", "--solc", "solc", "--cast", "cast"]
  requireLegacyArgs
    ["build", "--target", "solana-sbpf-asm", "--fixture", "counter", "-o", "build/sdk/solana-sbpf-asm"]
    ["--emit-counter-ir-sbpf", "-o", "build/sdk/solana-sbpf-asm/Counter.s"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "s"]
    ["--emit-solana-system-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi"]
    ["--emit-solana-system-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "elf"]
    ["--solana-system-cpi-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "solana-memo-cpi", "--format", "elf"]
    ["--solana-memo-cpi-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "system-cpi", "--format", "elf", "--solana-sbpf-arch", "v0"]
    ["--solana-system-cpi-elf", "--solana-sbpf-arch", "v0"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-ops-cpi", "--format", "s"]
    ["--emit-solana-spl-token-ops-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-ops-cpi"]
    ["--emit-solana-spl-token-ops-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-close-account-cpi", "--format", "s"]
    ["--emit-solana-spl-token-close-account-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-close-account-cpi", "--format", "elf"]
    ["--solana-spl-token-close-account-cpi-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-2022-transfer-hook", "--format", "s"]
    ["--emit-solana-spl-token-2022-transfer-hook-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "spl-token-2022-transfer-hook", "--format", "elf"]
    ["--solana-spl-token-2022-transfer-hook-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "counter", "--format", "elf"]
    ["--solana-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "solana-sdk", "--format", "s"]
    ["--emit-solana-sdk-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "associated-token-cpi", "--format", "s"]
    ["--emit-solana-associated-token-cpi-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "associated-token-cpi", "--format", "elf"]
    ["--solana-associated-token-cpi-elf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "value-vault", "--format", "s"]
    ["--emit-value-vault-ir-sbpf"]
  requireLegacyArgs
    ["emit", "--target", "solana-sbpf-asm", "--fixture", "value-vault", "--format", "elf"]
    ["--value-vault-solana-elf"]
  requireLegacyArgs
    ["emit", "--target", "wasm-near", "--fixture", "counter", "--format", "wat", "-o", "build/wasm-near/counter"]
    ["--emit-counter-emitwat", "-o", "build/wasm-near/counter"]
  requireLegacyArgs
    ["build", "--target", "wasm-near", "--fixture", "context", "--format", "wat", "-o", "build/wasm-near/context"]
    ["--emit-context-emitwat", "-o", "build/wasm-near/context"]
  requireLegacyArgs
    ["build", "--target", "solana-sbpf-asm", "--format", "s", "--root", ".", "-o", "build/portable-counter/Counter.s", "Examples/Product/Counter.lean"]
    ["--contract-source-sbpf", "-o", "build/portable-counter/Counter.s", "--root", ".", "Examples/Product/Counter.lean"]
  requireLegacyArgs
    ["build", "--target", "solana-sbpf-asm", "--format", "elf", "--root", ".", "-o", "build/portable-counter/Counter.so", "Examples/Product/Counter.lean"]
    ["--contract-source-solana-elf", "-o", "build/portable-counter/Counter.so", "--root", ".", "Examples/Product/Counter.lean"]
  requireLegacyArgs
    ["build", "--target", "solana-sbpf-asm", "--root", ".", "-o", "build/portable-counter/Counter.so", "Examples/Product/Counter.lean"]
    ["--contract-source-solana-elf", "-o", "build/portable-counter/Counter.so", "--root", ".", "Examples/Product/Counter.lean"]
  requireLegacyArgs
    ["build", "--target", "wasm-near", "--root", ".", "-o", "build/portable-counter/near", "Examples/Product/Counter.lean"]
    -- Host bridge (NEAR vs Soroban) is selected from --target on EmitWat path.
    ["--contract-source-emitwat", "-o", "build/portable-counter/near", "--root", ".", "--target", "wasm-near",
      "Examples/Product/Counter.lean"]
  requireLegacyArgs
    ["emit", "--target", "psy-dpn", "--fixture", "assert", "--format", "psy", "-o", "build/psy/AssertProbe.psy"]
    ["--emit-assert-ir-psy", "-o", "build/psy/AssertProbe.psy"]
  requireLegacyArgs
    ["emit", "--target", "aleo-leo", "--fixture", "pure-math", "--format", "leo", "-o", "build/aleo/PureMath.leo"]
    ["--emit-pure-math-ir-leo", "-o", "build/aleo/PureMath.leo"]
  requireLegacyArgs
    ["emit", "--target", "move-aptos", "--fixture", "counter", "--format", "aptos", "-o", "build/aptos-counter"]
    ["--emit-counter-ir-aptos", "-o", "build/aptos-counter"]
  requireLegacyArgs
    ["build", "--target", "move-sui", "--fixture", "counter", "-o", "build/sdk/move-sui"]
    ["--emit-counter-ir-sui", "-o", "build/sdk/move-sui"]
  requireLegacyArgs
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
    ["build", "--target", "move-sui", "--root", ".", "-o", "build/source-sdk/move-sui", "Examples/Product/Counter.lean"]
    #["move-sui", "source input is not supported"]
  -- PF-P3-02: CosmWasm accepts contract_source Lean modules (HostBridge.cosmWasm).
  requireLegacyArgs
    ["build", "--target", "wasm-cosmwasm", "--root", ".", "-o", "build/source-sdk/cosmwasm",
      "Examples/Product/Counter.lean"]
    ["--contract-source-emitwat", "-o", "build/source-sdk/cosmwasm", "--root", ".", "--target",
      "wasm-cosmwasm", "Examples/Product/Counter.lean"]
  -- PF-P0-01: remaining fixture-only build routes must not accept Lean sources.
  requireErrorContains
    ["build", "--target", "psy-dpn", "--root", ".", "-o", "build/source-sdk/vault.psy",
      "Examples/Product/ValueVault.lean"]
    #["psy-dpn", "source input is not supported"]
  requireErrorContains
    ["build", "--target", "aleo-leo", "--root", ".", "-o", "build/source-sdk/vault.leo",
      "Examples/Product/ValueVault.lean"]
    #["aleo-leo", "source input is not supported"]
  requireErrorContains
    ["build", "--target", "move-aptos", "--root", ".", "-o", "build/source-sdk/move-aptos",
      "Examples/Product/ValueVault.lean"]
    #["move-aptos", "source input is not supported"]
  requireErrorContains
    ["build", "--target", "wasm-cloudflare-workers", "--root", ".", "-o", "build/source-sdk/workers",
      "Examples/Product/ValueVault.lean"]
    #["wasm-cloudflare-workers", "source input is not supported"]
  -- Fixture emit remains available for the CosmWasm region/cosmwasm-check spike.
  requireLegacyArgs
    ["build", "--target", "wasm-cosmwasm", "-o", "build/cosmwasm/Counter.wat"]
    ["--emit-counter-ir-cosmwasm", "-o", "build/cosmwasm/Counter.wat"]
  requireLegacyArgs
    ["emit", "--target", "wasm-cloudflare-workers", "--fixture", "counter", "--format", "ts"]
    ["--emit-counter-ir-ts"]
  requireNftNative "evm" "Examples/Product/Nft.lean"
  requireNftNative "solana-sbpf-asm" "Examples/Product/Nft.lean"
  requireNftNative "wasm-near" "Examples/Product/Nft.lean"
  requireBuildErrorContains
    ["--target", "not-a-target", "--nft", "Examples/Product/Nft.lean"]
    #["unknown target"]
  requireBuildErrorContains
    ["--target", "evm", "--nft", "--fixture", "counter"]
    #["requires a .lean NFTSpec source"]
  requireLegacy "evm" (some "counter")
  requireLegacy "solana-sbpf-asm" (some "counter")
  requireLegacy "wasm-near" (some "counter")

  IO.println "cli-target-first: ok"
  return 0

end ProofForge.Tests.CliTargetFirst

-- This test imports the executable CLI module, whose root `main` would otherwise
-- run after elaboration and print usage. Exit from the test result instead.
#eval (do
  let exitCode ← ProofForge.Tests.CliTargetFirst.main
  IO.Process.exit exitCode.toUInt8
  pure () : IO Unit)
