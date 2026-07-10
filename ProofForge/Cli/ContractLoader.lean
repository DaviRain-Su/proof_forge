import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Contract.Spec
import ProofForge.Contract.Token

namespace ProofForge.Cli.ContractLoader

open Lean

/-- PF-P3-03: opt-in flag for a future hosted/cloud compiler path.

When set to a truthy value (`1`, `true`, `yes`, case-insensitive),
the shared frontend executor refuses to elaborate. Local `enableInitializersExecution` +
frontend evaluation is a **trusted local** path only — it is not an isolation
boundary for hostile source. -/
def hostedIsolationEnvVar : String := "PROOF_FORGE_HOSTED_ISOLATION"

def hostedIsolationRefusedMessage : String :=
  "proof-forge: hosted isolation is not ready; local Lean frontend elaboration " ++
  "(initializers enabled) is a trusted local path only, not a cloud worker " ++
  "boundary (PF-P3-03). Unset PROOF_FORGE_HOSTED_ISOLATION for trusted local builds."

/-- Truthy env values that request the hosted isolation gate. -/
def isHostedIsolationRequested (value : String) : Bool :=
  let v := value.trimAscii.toString.toLower
  v == "1" || v == "true" || v == "yes" || v == "on"

/-- Read the hosted-isolation gate from the process environment. -/
def hostedIsolationRequested : IO Bool := do
  match ← IO.getEnv hostedIsolationEnvVar with
  | none => pure false
  | some v => pure (isHostedIsolationRequested v)

/-- Enforce that initializer-enabled Lean elaboration only runs on the trusted
local path. All source loaders must call the shared frontend executor below. -/
def requireTrustedLocalFrontend : IO Unit := do
  if ← hostedIsolationRequested then
    throw <| IO.userError hostedIsolationRefusedMessage

/-- The sole initializer-enabled frontend boundary used by CLI source loaders. -/
unsafe def runTrustedLocalFrontend
    (input : System.FilePath) (root? : Option System.FilePath) (moduleName? : Option Name) :
    IO (Environment × Name) := do
  requireTrustedLocalFrontend
  enableInitializersExecution
  initSearchPath (← findSysroot "lean")
  let source ← IO.FS.readFile input
  let modName ← match moduleName? with
    | some name => pure name
    | none => moduleNameOfFileName input root?
  let frontendOpts := Elab.async.set {} false
  let env? ← Elab.runFrontend
    source
    frontendOpts
    input.toString
    modName
    (trustLevel := 0)
    (oleanFileName? := none)
    (ileanFileName? := none)
    (jsonOutput := false)
    (errorOnKinds := #[])
    (plugins := #[])
    (printStats := false)
    (setup? := none)
  let some env := env?
    | throw <| IO.userError s!"Lean frontend failed for `{input.toString}`"
  pure (env, modName)

private def specConstName (modName : Name) : Name :=
  modName ++ `spec

private def candidateSpecNames (modName : Name) : List Name :=
  let lastComponent :=
    match modName.components.reverse with
    | last :: _ => last
    | [] => Name.anonymous
  [modName ++ `spec, lastComponent ++ `spec, `spec]

private def isContractSpecConst (env : Environment) (constName : Name) : Bool :=
  match env.find? constName with
  | some info =>
      match info.type with
      | Expr.const `ProofForge.Contract.ContractSpec _ => true
      | _ => false
  | none => false

private def resolveSpecConstName (env : Environment) (modName : Name) : Option Name :=
  (candidateSpecNames modName).find? fun candidate =>
    env.constants.contains candidate && isContractSpecConst env candidate

/-- True when `spec` is a `TokenSpec` (TokenSpec modules must use `--token`). -/
private def isTokenSpecConst (env : Environment) (constName : Name) : Bool :=
  match env.find? constName with
  | some info =>
      match info.type with
      | Expr.const `ProofForge.Contract.Token.TokenSpec _ => true
      | _ => false
  | none => false

private def resolveTokenSpecConstName (env : Environment) (modName : Name) : Option Name :=
  (candidateSpecNames modName).find? fun candidate =>
    env.constants.contains candidate && isTokenSpecConst env candidate

/-- N1.3: point TokenSpec authors at `--token` instead of a bare ContractSpec miss. -/
def missingContractSpecMessage (modName : Name) (hasTokenSpec : Bool) : String :=
  if hasTokenSpec then
    s!"module `{modName}` defines `spec : ProofForge.Contract.Token.TokenSpec`, not ContractSpec; \
use `proof-forge build --target <id> --token …` (or `just product-token-near` / product-token-solana) \
for TokenSpec modules"
  else
    s!"no `spec : ProofForge.Contract.ContractSpec` found while loading module `{modName}`; \
define one with `contract_source` or `def spec : ProofForge.Contract.ContractSpec` \
(TokenSpec modules need `--token`)"

unsafe def loadSpecFromEnv (env : Environment) (modName : Name) : IO ProofForge.Contract.ContractSpec := do
  let some constName := resolveSpecConstName env modName
    | throw <| IO.userError
        (missingContractSpecMessage modName (resolveTokenSpecConstName env modName).isSome)
  match env.evalConstCheck ProofForge.Contract.ContractSpec {} `ProofForge.Contract.ContractSpec constName with
  | .ok spec => pure spec
  | .error msg => throw <| IO.userError msg

unsafe def loadSpec
    (input : System.FilePath) (root? : Option System.FilePath) (moduleName? : Option Name) :
    IO ProofForge.Contract.ContractSpec := do
  let (env, modName) ← runTrustedLocalFrontend input root? moduleName?
  loadSpecFromEnv env modName

end ProofForge.Cli.ContractLoader
