import ProofForge.Target
import ProofForge.Target.Backend
import ProofForge.IR.Examples.Counter
import ProofForge.Cli

namespace ProofForge.Tests.TargetBackend

open ProofForge.Target
open ProofForge.Cli

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireSome {α : Type} (value : Option α) (message : String) : IO α :=
  match value with
  | some x => pure x
  | none => throw <| IO.userError message

/-- PF-P1-01: primary triad and every known target id must resolve via the
backend registry (no silent holes that force a central CLI match edit). -/
def main : IO UInt32 := do
  for id in #["evm", "solana-sbpf-asm", "wasm-near"] do
    let backend ← requireSome (findBackend? id) s!"missing TargetBackend for primary triad target `{id}`"
    require (backend.profile.id == id) s!"backend profile id mismatch for `{id}`"
    require ((findCliDriver? id).isSome)
      s!"missing CLI driver for primary triad target `{id}`"
    require backend.hasValidate
      s!"primary triad `{id}` must register validateModule on TargetBackend"
    require backend.hasPlan
      s!"primary triad `{id}` must register ensurePlan on TargetBackend"
    require backend.hasPackage
      s!"primary triad `{id}` must register ensurePackage on TargetBackend"
    match backend.validateModule ProofForge.IR.Examples.Counter.module with
    | .ok () => pure ()
    | .error err => throw <| IO.userError s!"`{id}` validateModule failed on Counter: {err.message}"
    match backend.ensurePlan ProofForge.IR.Examples.Counter.module with
    | .ok () => pure ()
    | .error err => throw <| IO.userError s!"`{id}` ensurePlan failed on Counter: {err.message}"
    match backend.resolve (ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.Counter.module) with
    | .error err => throw <| IO.userError s!"`{id}` resolve failed on Counter: {err.message}"
    | .ok plan =>
        match backend.ensurePackage ProofForge.IR.Examples.Counter.module plan with
        | .ok () => pure ()
        | .error err => throw <| IO.userError s!"`{id}` ensurePackage failed on Counter: {err.message}"

  for id in knownIds do
    let backend ← requireSome (findBackend? id) s!"knownIds entry `{id}` has no TargetBackend"
    require (backend.profile.id == id) s!"backend/profile id mismatch for `{id}`"

  -- Secondary targets keep profile+resolve until migrated; missing hooks fail closed.
  let cosmwasm ← requireSome (findBackend? "wasm-cosmwasm") "missing cosmwasm backend"
  require (!cosmwasm.hasValidate && !cosmwasm.hasPlan && !cosmwasm.hasPackage)
    "secondary wasm-cosmwasm must not claim unregistered validate/plan/package hooks yet"
  match cosmwasm.validateModule ProofForge.IR.Examples.Counter.module with
  | .ok () => throw <| IO.userError "wasm-cosmwasm validateModule must fail closed without a hook"
  | .error err =>
      require (err.message.contains "no TargetBackend.validateModule hook")
        s!"expected missing-hook diagnostic, got: {err.message}"

  -- Build/emit flag resolution is driver-backed, not a residual central match.
  let evmBuild ← match buildLegacyFlag "evm" (some "Examples/Product/Counter.lean") with
    | .ok flag => pure flag
    | .error err => throw <| IO.userError s!"evm build flag failed: {err}"
  require (evmBuild == "--evm-bytecode") "evm contract_source build must map to --evm-bytecode via driver"

  let solanaBuild ← match buildLegacyFlag "solana-sbpf-asm" (some "Examples/Product/Counter.lean") (format? := some "s") with
    | .ok flag => pure flag
    | .error err => throw <| IO.userError s!"solana build flag failed: {err}"
  require (solanaBuild == "--contract-source-sbpf")
    "solana --format s source build must map to --contract-source-sbpf via driver"

  let nearBuild ← match buildLegacyFlag "wasm-near" (some "Examples/Product/Counter.lean") with
    | .ok flag => pure flag
    | .error err => throw <| IO.userError s!"near build flag failed: {err}"
  require (nearBuild == "--contract-source-emitwat")
    "wasm-near source build must map to --contract-source-emitwat via driver"

  -- Driver parity: public buildLegacyFlag must equal the registered driver's resolveBuild.
  let evmDriver ← requireSome (findCliDriver? "evm") "evm CLI driver missing"
  let req : BuildRequest := {
    input? := some "Examples/Product/Counter.lean"
    fixture? := none
    format? := none
    token := false
  }
  match evmDriver.resolveBuild req, buildLegacyFlag "evm" req.input? with
  | .ok viaDriver, .ok viaPublic =>
      require (viaDriver == viaPublic)
        s!"evm build dispatch must equal driver.resolveBuild (driver={viaDriver}, public={viaPublic})"
  | viaDriver, viaPublic =>
      throw <| IO.userError s!"evm driver/public build parity failed: driver={repr viaDriver} public={repr viaPublic}"

  -- Unknown ids still fail closed (no silent Counter substitution).
  match buildLegacyFlag "not-a-real-target" none with
  | .ok flag => throw <| IO.userError s!"unknown target must fail closed, got {flag}"
  | .error err =>
      require (err.contains "unknown target") s!"unknown target diagnostic missing: {err}"

  IO.println "TargetBackend registry + primary triad validate/plan hooks OK"
  return 0

end ProofForge.Tests.TargetBackend

-- Importing ProofForge.Cli also brings the executable root `main`; exit via
-- #eval so the test body runs instead of printing CLI usage.
#eval (do
  let exitCode ← ProofForge.Tests.TargetBackend.main
  IO.Process.exit exitCode.toUInt8
  pure () : IO Unit)
