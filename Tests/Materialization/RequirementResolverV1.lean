/-
  D3/S5 engineering exact requirement resolver vertical tests.
  Not SupportClaim / formal TargetRegistryV1 / formal resolver.

  Durable dual-arg API authority: Lean Environment reflection over public
  ConstantInfo.type Exprs (not a source lexer). Product gate and reflection
  self-test run at elaboration (`run_cmd`) so lake build / Fast / full tests
  all execute them.

  Environment coverage:
  - `import ProofForgeV2` (library umbrella)
  - `import ProofForgeV2.CLI.Main` (shipped CLI root; not forced into umbrella)
  Gate still filters by public `ProofForgeV2` Name prefix only.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Main
import ProofForgeV2.Core.SemanticIR
import Tests.Language.ParserSession
import Lean
import Lean.Elab.Command

namespace Tests.Materialization.RequirementResolverV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open Lean
open Lean.Elab.Command

/-! Synthetic dual-arg probes for Environment reflection self-test.
    Declared early so later `run_cmd` gates observe them. Product
    `ProofForgeV2` prefix gate must never include these. -/
namespace DualArgProbe

def probeSimple
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

def «probeEscaped»
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

noncomputable def probeNoncomputable
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

protected def probeProtected
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

mutual
  def probeMutualA
      (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Nat :=
    0
  def probeMutualB
      (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Nat :=
    0
end

/-- Single-carrier control: must **not** appear in dual-arg hits. -/
def probeOnlySelection (_s : ResolvedBuildSelectionV1) : Unit := ()

/-- Single-carrier control: must **not** appear in dual-arg hits. -/
def probeOnlyCompiled (_c : CompiledSemanticV1) : Unit := ()

/-- Public structure whose constructor type carries both carriers. -/
structure DualCtorProbe where
  selection : ResolvedBuildSelectionV1
  compiled : CompiledSemanticV1

/-- Public structure constructor control: selection only. -/
structure SingleSelCtorProbe where
  selection : ResolvedBuildSelectionV1

/-- Carrier aliases (`abbrev` → ReducibilityHints.abbrev). -/
abbrev SelectionAlias := ResolvedBuildSelectionV1
abbrev CompiledAlias := CompiledSemanticV1

/-- Alias chain (two abbrev hops). -/
abbrev SelectionAliasChain := SelectionAlias

/-- Dual API whose signature uses abbrev aliases (not bare carrier names). -/
def probeViaAlias (_s : SelectionAlias) (_c : CompiledAlias) : Unit := ()

/-- Dual API through a two-step abbrev chain on the selection side. -/
def probeAliasChain (_s : SelectionAliasChain) (_c : CompiledAlias) : Unit := ()

/-- Single-carrier control via alias. -/
def probeOnlySelectionAlias (_s : SelectionAlias) : Unit := ()

/-- Optional reducible-def alias (attribute reducible, not opaque/regular-only). -/
@[reducible] def SelectionReducible := ResolvedBuildSelectionV1
@[reducible] def CompiledReducible := CompiledSemanticV1

def probeViaReducible
    (_s : SelectionReducible) (_c : CompiledReducible) : Unit :=
  ()

/-- Dual API whose **name** ends with `_spec` (must not be filtered by spelling). -/
def probe_spec
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

/-- Dual API whose **name** starts with `sizeOf` (must not be filtered by spelling). -/
def sizeOfProbe
    (_s : ResolvedBuildSelectionV1) (_c : CompiledSemanticV1) : Unit :=
  ()

/-- Single-carrier control with `_spec` suffix name. -/
def single_spec (_s : ResolvedBuildSelectionV1) : Unit := ()

/-- Single-carrier control with `sizeOf` prefix name. -/
def sizeOfOnlySelection (_s : ResolvedBuildSelectionV1) : Unit := ()

end DualArgProbe

/-! Synthetic residual emission-bypass probes. These deliberately shape public
    types as capability-free SemanticProgram→Plan / Plan→IR / IR→files chains.
    The product gate under `ProofForgeV2` must reject renames/aliases of this form;
    probes live under Tests prefix and prove the scanner catches them. -/
namespace ResidualBypassProbe

/-- Opaque stand-ins so probes do not import private target Residual APIs. -/
structure ProbePlan where
  tag : Unit := ()
  deriving Inhabited
structure ProbeIR where
  tag : Unit := ()
  deriving Inhabited

/-- Capability-free SemanticProgram → Plan (forbidden product shape). -/
def probeSemToPlan (_p : SemanticProgram) : CompileResult ProbePlan :=
  .ok {}

/-- Capability-free Plan → IR (forbidden product shape). -/
def probePlanToIR (_plan : ProbePlan) : CompileResult ProbeIR :=
  .ok {}

/-- Capability-free IR → OutputFile array (forbidden product shape). -/
def probeIRToFiles (_ir : ProbeIR) : CompileResult (Array OutputFile) :=
  .ok #[]

/-- Renamed residual planFromAlpha shape (must still be caught by type scan). -/
def planFromAlphaRenamed (_p : SemanticProgram) : CompileResult ProbePlan :=
  .ok {}

/-- Reducible alias of SemanticProgram (alias expand must catch). -/
abbrev SemanticAlias := SemanticProgram

def probeViaSemanticAlias (_p : SemanticAlias) : CompileResult ProbePlan :=
  .ok {}

/-- Result-type alias of CompileResult ProbePlan (result expand must catch). -/
abbrev PlanResultAlias := CompileResult ProbePlan

def probeViaResultAlias (_p : SemanticProgram) : PlanResultAlias :=
  .ok {}

/-- Two-step abbrev chain on the input carrier. -/
abbrev SemanticAliasChain := SemanticAlias

def probeViaAbbrevChain (_p : SemanticAliasChain) : CompileResult ProbePlan :=
  .ok {}

/-- Reducible-def chain (attribute reducible, not opaque). -/
@[reducible] def SemanticReducible := SemanticProgram
@[reducible] def PlanResultReducible := CompileResult ProbePlan

def probeViaReducibleChain (_p : SemanticReducible) : PlanResultReducible :=
  .ok {}

/-- Opaque function with forbidden Semantic→Plan type (must be scanned as opaqueInfo). -/
opaque opaqueSemToPlan (_p : SemanticProgram) : CompileResult ProbePlan

/-- Direct public constructor whose field type embeds a forbidden emission chain.
    Scanner must walk ctor field types (not only top-level defnInfo). -/
structure DirectCtorBypass where
  planFromAlpha : SemanticProgram → CompileResult ProbePlan

/-- Direct mandatory capability binder: authorized (not residual bypass). -/
def probeCapabilityPlan
    (_c : Targets.ResolvedEngineeringBuildV1) : CompileResult ProbePlan :=
  .ok {}

/-- Direct mandatory capability binder → IR: authorized. -/
def probeCapabilityIR
    (_c : Targets.ResolvedEngineeringBuildV1) : CompileResult ProbeIR :=
  .ok {}

/-- Direct mandatory capability binder + later ordinary mandatory params: authorized. -/
def probeCapabilityThenPlan
    (_c : Targets.ResolvedEngineeringBuildV1) (_extra : Nat) : CompileResult ProbeIR :=
  .ok {}

/-- Transparent alias of capability; direct binder of alias is authorized after expand. -/
abbrev CapabilityAlias := Targets.ResolvedEngineeringBuildV1

def probeViaCapabilityAlias
    (_c : CapabilityAlias) : CompileResult ProbeIR :=
  .ok {}

/-- Result-only capability mention + IR (no direct capability *input* binder).
    Capability appears only in the result type; Plan→IR remains forbidden. -/
def probeResultOnlyCapIR (_plan : ProbePlan) :
    CompileResult (Targets.ResolvedEngineeringBuildV1 → ProbeIR) :=
  .ok (fun _ => {})

/-- Option-wrapped capability binder is NOT direct mandatory capability authorization.
    Plan→IR emission remains forbidden. -/
def probeOptionCapBinder
    (_c : Option Targets.ResolvedEngineeringBuildV1) (_plan : ProbePlan) :
    CompileResult ProbeIR :=
  .ok {}
/-- Pure validation control (Semantic → Unit): not an emission chain. -/
def probeValidateOnly (_p : SemanticProgram) : CompileResult Unit :=
  .ok ()

/-- Capability-bearing structure ctor control: first field is direct mandatory
    capability binder on `.mk` → authorized. -/
structure CapabilityCtorControl where
  capability : Targets.ResolvedEngineeringBuildV1
  plan : ProbePlan

/-- Structure providing a real constructor parent name `CtorParentProbe.mk`. -/
structure CtorParentProbe where
  tag : Unit := ()
  deriving Inhabited

/-- User-declared forbidden emission under constructor-name parent
    `CtorParentProbe.mk.*`. Hierarchical name is intentional: must be scanned
    (narrow Lean-generated leaf list must not swallow this user API). -/
def CtorParentProbe.mk.planFromAlphaNested (_p : SemanticProgram) :
    CompileResult ProbePlan :=
  .ok {}

/-- Transparent alias whose expansion body is a nested forbidden Pi.
    Classifier must expand the alias and discover Semantic→Plan. -/
abbrev NestedSemToPlan := SemanticProgram → CompileResult ProbePlan

def probeViaNestedAliasPi (_f : NestedSemToPlan) : Unit := ()

/-- Reducible alias expansion body is nested forbidden Pi. -/
@[reducible] def NestedSemToPlanReducible := SemanticProgram → CompileResult ProbePlan

def probeViaNestedReduciblePi (_f : NestedSemToPlanReducible) : Unit := ()

/-- Pure (unwrapped) Semantic→Plan — forbidden without capability. -/
def probePureSemToPlan (_p : SemanticProgram) : ProbePlan := {}

/-- Pure Plan→IR — forbidden without capability. -/
def probePurePlanToIR (_plan : ProbePlan) : ProbeIR := {}

/-- IR → Array OutputFile (wrapper-independent files chain) — forbidden. -/
def probeIRToArrayFiles (_ir : ProbeIR) : Array OutputFile := #[]

/-- IR → IO (Array OutputFile) — forbidden. -/
def probeIRToIOArrayFiles (_ir : ProbeIR) : IO (Array OutputFile) :=
  pure #[]

/-- IR → IO MaterializedArtifactsV1 (carrier appears under IO) — forbidden. -/
def probeIRToIOMaterializedArtifacts
    (_ir : ProbeIR) : IO (Option MaterializedArtifactsV1) :=
  pure none

/-- Capability-gated IR → Array OutputFile — allowed. -/
def probeCapIRToArrayFiles
    (_c : Targets.ResolvedEngineeringBuildV1) (_ir : ProbeIR) : Array OutputFile :=
  #[]

/-- Capability-gated IR → IO (Array OutputFile) — allowed. -/
def probeCapIRToIOArrayFiles
    (_c : Targets.ResolvedEngineeringBuildV1) (_ir : ProbeIR) :
    IO (Array OutputFile) :=
  pure #[]

/-- Capability-gated IR → IO MaterializedArtifactsV1 — allowed. -/
def probeCapIRToIOMaterializedArtifacts
    (_c : Targets.ResolvedEngineeringBuildV1) (_ir : ProbeIR) :
    IO (Option MaterializedArtifactsV1) :=
  pure none

/-- Capability-gated pure Plan→IR — allowed. -/
def probeCapPurePlanToIR
    (_c : Targets.ResolvedEngineeringBuildV1) (_plan : ProbePlan) : ProbeIR :=
  {}

/-- Synthetic carrier-like structure whose public ctor field is a forbidden
    Plan→IR function. Environment scan must not skip this ctor; classifier on
    the full ctor type must report forbidden. -/
structure ProbePlanCarrier where
  lowerPlan : ProbePlan → ProbeIR

end ResidualBypassProbe

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectErrorCode (result : CompileResult α) (code : String) (message : String) :
    IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code) s!"{message}: got {error.code}: {error.message}"
  | .ok _ => throw <| IO.userError s!"{message}: expected error {code}"

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def s2Trio : IO (Array RequirementRequestV1) := do
  let mut items : Array RequirementRequestV1 := #[]
  for id in s2CatalogIdsWireOrderV1 do
    match mkS2RequirementRequestV1 id with
    | .ok req => items := items.push req
    | .error e => throw <| IO.userError e
  pure items

private def mkRow (kind : TargetKind) (profile : CodegenProfileId)
    (supported : Array RequirementRequestV1) : StaticRequirementSupportRowV1 :=
  {
    targetId := TargetId.ofKind kind
    codegenProfile := profile
    kind
    supported
  }

private def zeroDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 0) }

private def emptyProgramRequirements : ProgramRequirementsV1 := { items := #[] }

private def testFourRowTable : IO Unit := do
  let rows ← liftResult productSupportRowsV1
  expect (rows.size == 5) "exactly five support rows"
  let expectedKeys := #[
    ("aleo", "aleo-leo-4.0.2-u64-v1", 4),
    ("evm", "evm-yul-solc-0.8.34-v1", 5),
    ("near", "near-wasm-raw-u64-v1", 6),
    ("noir", "noir-source-u64-relations-v1", 7),
    ("solana", "solana-sbpf-plan-v1", 5)
  ]
  let mut i : Nat := 0
  while i < 5 do
    match rows[i]?, expectedKeys[i]? with
    | some row, some (tid, prof, supportCount) =>
        expect (row.targetId.toString == tid) s!"row {i} targetId"
        expect (row.codegenProfile.toString == prof) s!"row {i} profile"
        expect (row.supported.size == supportCount)
          s!"row {i} support count"
        -- Every row is a wire-order subset of the S2 catalog; only Noir
        -- currently supports both external-call keys, and NEAR the async one.
        let ids := row.supported.map (·.id)
        expect (ids.all isS2CatalogIdV1) s!"row {i} ids are catalog members"
        expect (row.supported.all fun item =>
            item.version == s2RequirementVersionV1 && item.predicates.isEmpty)
          s!"row {i} version/predicates"
        let expectCalls := row.targetId == TargetId.noir
        expect ((ids.contains "effect.synchronous-call") == expectCalls &&
            (ids.contains "effect.asynchronous-workflow") ==
              (expectCalls || row.targetId == TargetId.near))
          s!"row {i} capability gate shape"
        for item in row.supported do
          match engineeringRequirementDigestV1 item.id with
          | .ok d => expect (item.digest == d) s!"row {i} digest for {item.id}"
          | .error e => throw <| IO.userError e
    | _, _ => throw <| IO.userError s!"row {i} missing"
    i := i + 1

private def testIndexValidationNegatives : IO Unit := do
  let trio ← s2Trio
  -- Empty index
  expectErrorCode (createStaticRequirementSupportIndexV1 #[])
    "PF-REGISTRY-INVALID" "empty support index"
  -- Duplicate row key
  let dupRows := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 dupRows)
    "PF-REGISTRY-DUPLICATE" "duplicate support row"
  -- Wrong order (solana before evm)
  let wrongOrder := #[
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 wrongOrder)
    "PF-REGISTRY-INVALID" "non-ascending support rows"
  -- Missing a row
  let missing := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 missing)
    "PF-REGISTRY-INVALID" "missing implemented profile"
  -- Extra / design-only openvm row (size mismatch with expected 4)
  let withDesign := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .openvm CodegenProfileId.evmYulSolc0834V1 trio
  ]
  -- openvm row uses wrong profile relative to expected last solana pair → size ok but
  -- content diverges; also kind/target may fail. Prefer size-extra first:
  let extra := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 trio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio,
    mkRow .aleo CodegenProfileId.evmYulSolc0834V1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 extra)
    "PF-REGISTRY-INVALID" "extra design-only row"
  expectErrorCode (createStaticRequirementSupportIndexV1 withDesign)
    "PF-REGISTRY-INVALID" "wrong-kind/cross-profile row"
  -- Wrong kind on matching target/profile position
  let wrongKind : StaticRequirementSupportRowV1 := {
    targetId := TargetId.evm
    codegenProfile := CodegenProfileId.evmYulSolc0834V1
    kind := .near
    supported := trio
  }
  let wrongKindRows := #[
    wrongKind,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 wrongKindRows)
    "PF-REGISTRY-INVALID" "wrong kind on support row"
  -- Cross-profile: near profile under evm target at first slot
  let cross : StaticRequirementSupportRowV1 := {
    targetId := TargetId.evm
    codegenProfile := CodegenProfileId.nearWasmRawU64V1
    kind := .evm
    supported := trio
  }
  let crossRows := #[
    cross,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 crossRows)
    "PF-REGISTRY-INVALID" "cross-profile support row"
  -- Requirement non-canonical order inside row
  let r0 ← match trio[0]? with | some r => pure r | none => throw <| IO.userError "trio0"
  let r1 ← match trio[1]? with | some r => pure r | none => throw <| IO.userError "trio1"
  let r2 ← match trio[2]? with | some r => pure r | none => throw <| IO.userError "trio2"
  let reversed := #[r2, r1, r0]
  let revRows := #[
    mkRow .aleo CodegenProfileId.aleoLeoU64V1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 reversed,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 revRows)
    "PF-REGISTRY-INVALID" "non-canonical requirement order"
  -- Duplicate requirement id
  let dupReq := #[r0, r0, r1]
  let dupReqRows := #[
    mkRow .aleo CodegenProfileId.aleoLeoU64V1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 dupReq,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 dupReqRows)
    "PF-REGISTRY-DUPLICATE" "duplicate requirement in support row"
  -- Wrong version
  let badVer := { r0 with version := { major := 2, minor := 0, patch := 0 } }
  let badVerTrio := #[badVer, r1, r2]
  let badVerRows := #[
    mkRow .aleo CodegenProfileId.aleoLeoU64V1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 badVerTrio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 badVerRows)
    "PF-REGISTRY-INVALID" "wrong requirement version in support row"
  -- Wrong digest
  let badDig := { r0 with digest := zeroDigest }
  let badDigTrio := #[badDig, r1, r2]
  let badDigRows := #[
    mkRow .aleo CodegenProfileId.aleoLeoU64V1 trio,
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 badDigTrio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 badDigRows)
    "PF-REGISTRY-INVALID" "wrong requirement digest in support row"
  -- Nonempty predicates
  let withPred := { r0 with predicates := #[.boolEquals "x" true] }
  let predTrio := #[withPred, r1, r2]
  let predRows := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 predTrio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 predRows)
    "PF-REGISTRY-INVALID" "nonempty predicates in support row"
  -- Unknown requirement id (swap the last item for a non-catalog id that
  -- keeps wire order; the unknown-id check must fire, not dup/order/digest).
  let unknown : RequirementRequestV1 := {
    id := "effect.zzz"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  let unkTrio ← do
    let full ← s2Trio
    let some first := full[0]? | throw <| IO.userError "trio0"
    let some second := full[1]? | throw <| IO.userError "trio1"
    pure #[first, second, unknown]
  let unkRows := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 unkTrio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 unkTrio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 unkTrio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 unkTrio
  ]
  expectErrorCode (createStaticRequirementSupportIndexV1 unkRows)
    "PF-REGISTRY-INVALID" "unknown requirement id in support row"

private def testSeedPrecedence : IO Unit := do
  let sentinel : CompileResult StaticRequirementSupportIndexV1 :=
    .error (.registryInvalid "sentinel-support-seed")
  expectErrorCode (supportRowsWithSeedV1 sentinel)
    "PF-REGISTRY-INVALID" "seed error first on supportRows"
  expectErrorCode
    (inspectSupportWithSeedV1 sentinel TargetId.evm CodegenProfileId.evmYulSolc0834V1)
    "PF-REGISTRY-INVALID" "seed error first on inspectSupport"
  expectErrorCode
    (inspectResolveWithSeedV1 sentinel TargetId.evm CodegenProfileId.evmYulSolc0834V1
      emptyProgramRequirements)
    "PF-REGISTRY-INVALID" "seed error first on inspectResolve"
  -- DI success returns inspection, never capability.
  let insp ← liftResult <|
    inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
      TargetId.evm CodegenProfileId.evmYulSolc0834V1
  expect (insp.targetId == TargetId.evm) "DI inspection target"
  -- EVM declines both external-call keys: five of the seven catalog ids.
  expect (insp.supported.size == 5 &&
      !insp.supported.any (·.id == "effect.synchronous-call") &&
      !insp.supported.any (·.id == "effect.asynchronous-workflow"))
    "DI inspection EVM capability gate"

private def testRequestInspectionErrors : IO Unit := do
  let trio ← s2Trio
  let rows ← liftResult productSupportRowsV1
  let supported ← match rows[0]? with
    | some row => pure row.supported
    | none => throw <| IO.userError "missing first support row"
  let r0 ← match trio[0]? with | some r => pure r | none => throw <| IO.userError "trio0"
  -- Zero requirements success
  match inspectResolveRequestsV1 supported emptyProgramRequirements with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"zero reqs should succeed: {e.render}"
  -- Full S2 catalog succeeds only against the all-capable Noir row...
  let noirSupported ← match rows[2]? with
    | some row => pure row.supported
    | none => throw <| IO.userError "missing noir support row"
  match inspectResolveRequestsV1 noirSupported { items := trio } with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"full trio on noir should succeed: {e.render}"
  -- ...while EVM's capability gate declines the external-call keys.
  expectErrorCode (inspectResolveRequestsV1 supported { items := trio })
    "PF-REQ-UNSUPPORTED" "evm declines external-call keys"
  -- Unknown id
  let unknown : RequirementRequestV1 := {
    id := "disclosure.private-witness"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  expectErrorCode (inspectResolveRequestsV1 supported { items := #[unknown] })
    "PF-REQ-UNSUPPORTED" "unknown request id"
  -- Wrong version
  let badVer := { r0 with version := { major := 9, minor := 0, patch := 0 } }
  expectErrorCode (inspectResolveRequestsV1 supported { items := #[badVer] })
    "PF-REQ-UNSUPPORTED" "wrong request version"
  -- Wrong digest
  let badDig := { r0 with digest := zeroDigest }
  expectErrorCode (inspectResolveRequestsV1 supported { items := #[badDig] })
    "PF-REQ-UNSUPPORTED" "wrong request digest"
  -- Nonempty predicate (known S2 only → PRECONDITION)
  let withPred := { r0 with predicates := #[.uintAtLeast "n" 1] }
  expectErrorCode (inspectResolveRequestsV1 supported { items := #[withPred] })
    "PF-REQ-PRECONDITION" "nonempty predicate"
  -- Non-catalog id + nonempty predicates → UNSUPPORTED (known-id before predicates)
  let unknownWithPred : RequirementRequestV1 := {
    id := "disclosure.private-witness"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[.boolEquals "x" true]
  }
  expectErrorCode (inspectResolveRequestsV1 supported { items := #[unknownWithPred] })
    "PF-REQ-UNSUPPORTED" "non-catalog + predicates is unsupported not precondition"
  -- Reverse-order request ids → UNSUPPORTED
  let r1 ← match trio[1]? with | some r => pure r | none => throw <| IO.userError "trio1"
  let r2 ← match trio[2]? with | some r => pure r | none => throw <| IO.userError "trio2"
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[r2, r1, r0] })
    "PF-REQ-UNSUPPORTED" "reverse-order request ids"
  -- Duplicate request
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[r0, r0] })
    "PF-REQ-UNSUPPORTED" "duplicate request id"
  -- No exact support for unknown selection
  expectErrorCode
    (inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
      TargetId.openvm CodegenProfileId.evmYulSolc0834V1)
    "PF-REQ-UNSUPPORTED" "no exact support for design-only"

/-- Product sole-mint type surface: exactly `(selection, compiled)`.
    An extra caller `ProgramRequirementsV1` / `requested?` parameter must fail
    to typecheck (regression guard for the deleted override surface). -/
private def resolveEngineeringRequirementsV1TypeAscription :
    ResolvedBuildSelectionV1 → CompiledSemanticV1 →
      CompileResult Targets.ResolvedEngineeringBuildV1 :=
  Targets.resolveEngineeringRequirementsV1

#check (Targets.resolveEngineeringRequirementsV1 :
  ResolvedBuildSelectionV1 → CompiledSemanticV1 →
    CompileResult Targets.ResolvedEngineeringBuildV1)

private unsafe def testProductFourTargets : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-counter>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  -- Frozen requirements come from the sole retained SemanticProgramV1.
  let semanticV1 := CompiledSemanticV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"Counter SemanticProgramV1 invalid: {repr e}"
  -- Counter contributes three of the four catalog ids (no Bool carrier).
  let counterCatalogTrio : Array String :=
    #["failure.atomic-rollback", "state.persistent", "value.checked-arithmetic"]
  expect (frozen.items.map (·.id) == counterCatalogTrio)
    "Counter retained requirements are its contributed catalog ids"
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult <| resolveBuildSelectionV1 tid none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    expect (Targets.ResolvedEngineeringBuildV1.targetIdOf capability == tid)
      s!"capability target {tid}"
    expect
      (Targets.ResolvedEngineeringBuildV1.codegenProfileOf capability ==
        selection.codegenProfile)
      s!"capability profile {tid}"
    let accepted := Targets.ResolvedEngineeringBuildV1.requirementsOf capability
    -- Capability stores exact retained frozen requirements (no empty/subset).
    expect (accepted == frozen)
      s!"capability.requirements exact retained freeze for {tid}"
    expect (accepted.items.map (·.id) == counterCatalogTrio)
      s!"accepted contributed catalog ids for {tid}"
    let output ← liftResult <| Targets.materializeResult capability
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
      s!"{tid} materialize via capability"
    expect (MaterializedArtifactsV1.targetIdOf output == tid)
      s!"carrier target {tid}"
    expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest)
      s!"source digest {tid}"
    expect (MaterializedArtifactsV1.semanticDigestOf output == semanticDigest)
      s!"semantic digest {tid}"
  -- Zero-request success is inspection-only (not a product capability override).
  let rows ← liftResult productSupportRowsV1
  let supported ← match rows[0]? with
    | some row => pure row.supported
    | none => throw <| IO.userError "missing first support row"
  match inspectResolveRequestsV1 supported emptyProgramRequirements with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"inspection-only zero request must succeed: {e.render}"
  match inspectResolveWithSeedV1 initialStaticRequirementSupportIndexV1Result
      TargetId.evm CodegenProfileId.evmYulSolc0834V1 emptyProgramRequirements with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"inspection-only zero request (with seed) must succeed: {e.render}"

/-- S1-compilable stateless identity ProgramV1 (entry echo param → return param).
    Real sole-mint path: compileValidatedSourceV1 → empty retained requirements →
    resolveEngineeringRequirementsV1 → capability.requirements empty → materialize.
    Catches a resolver that hardcodes the S2 trio instead of reading retained freeze.
    Wrong version/digest/predicate remain inspection-only (private compiler cannot
    mint those CompiledSemanticV1 shapes). -/
private def identityEchoSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Echo where\n" ++
  "  entry echo(x : UInt64) : UInt64 do\n" ++
  "    return x\n\n" ++
  "end ProofForgeV2.Examples\n"

private def identityEchoModuleNameV1 : String := "Examples.Echo"

/-- Distinct proper subset of S2: public state + init + view, no arithmetic/assert.
    Retained freeze is exactly `state.persistent` (not empty, not full trio). -/
private def stateOnlyHoldSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Hold where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def stateOnlyHoldModuleNameV1 : String := "Examples.Hold"

private unsafe def testEmptyRequirementsCapability : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    identityEchoSourceText "<req-resolver-echo>"
    identityEchoModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let semanticV1 := CompiledSemanticV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"Echo SemanticProgramV1 invalid: {repr e}"
  expect frozen.items.isEmpty
    "Echo retained SemanticProgramV1 requirements must be empty (anti-hardcode S2 trio)"
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  -- Capability success on all four implemented targets (sole mint / anti-hardcode).
  -- Target-native profiles may reject this empty-state fragment after capability mint:
  --   * Solana: the explicit state-account profile requires non-empty state
  --   * Near: the host key-value profile requires non-empty state (+ initializer)
  -- EVM/Noir must still produce real materialize output for empty-req capability.
  let mut materialized : Array TargetId := #[]
  let mut backendLimited : Array String := #[]
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult <| resolveBuildSelectionV1 tid none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    let accepted := Targets.ResolvedEngineeringBuildV1.requirementsOf capability
    expect (accepted == frozen)
      s!"Echo capability.requirements exact empty retained for {tid}"
    expect accepted.items.isEmpty
      s!"Echo capability must not invent requirements for {tid}"
    match Targets.materializeResult capability with
    | .ok output =>
        expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
          s!"{tid} empty-req materialize produces files"
        expect (MaterializedArtifactsV1.targetIdOf output == tid)
          s!"Echo empty-req carrier target {tid}"
        expect (MaterializedArtifactsV1.sourceDigestOf output == sourceDigest)
          s!"Echo empty-req source digest {tid}"
        materialized := materialized.push tid
    | .error e =>
        let msg := e.render
        let solanaLimited :=
          tid == TargetId.solana &&
            (hasSubstr msg "state count" || hasSubstr msg "initializer")
        let nearLimited :=
          tid == TargetId.near &&
            (hasSubstr msg "state count" || hasSubstr msg "initializer")
        if solanaLimited || nearLimited then
          backendLimited := backendLimited.push s!"{tid}:{e.code}:{msg}"
        else
          throw <| IO.userError
            s!"{tid} materialize after empty-req capability failed: {msg}"
  expect (materialized.any (· == TargetId.evm))
    "Echo empty-req capability must materialize on EVM"
  expect (materialized.any (· == TargetId.noir))
    "Echo empty-req capability must materialize on Noir"
  expect (backendLimited.any (fun s => hasSubstr s "solana"))
    "Echo empty-req documents Solana target-native non-empty-state requirement"
  expect (backendLimited.any (fun s => hasSubstr s "near"))
    "Echo empty-req documents Near target-native non-empty-state requirement"

private unsafe def testStateOnlySubsetCapability : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    stateOnlyHoldSourceText "<req-resolver-hold>"
    stateOnlyHoldModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let semanticV1 := CompiledSemanticV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"Hold SemanticProgramV1 invalid: {repr e}"
  expect (frozen.items.map (·.id) == #["state.persistent"])
    "Hold retained freeze is exactly state.persistent (distinct subset, not full S2)"
  for tid in #[TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let selection ← liftResult <| resolveBuildSelectionV1 tid none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    let accepted := Targets.ResolvedEngineeringBuildV1.requirementsOf capability
    expect (accepted == frozen)
      s!"Hold capability.requirements exact retained subset for {tid}"
    expect (accepted.items.map (·.id) == #["state.persistent"])
      s!"Hold capability must not expand to full S2 trio for {tid}"
    let output ← liftResult <| Targets.materializeResult capability
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
      s!"{tid} state-only subset materialize"

private unsafe def testCliEmitAndDescribe : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-cli>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let outputDir := System.FilePath.mk "build/v2/req-resolver-emit"
  if ← outputDir.pathExists then IO.FS.removeDirAll outputDir
  let manifest ← ProofForgeV2.CLI.emitProgram capability outputDir
  expect (manifest.target == TargetId.evm) "CLI emit via capability"
  expect (manifest.codegenProfile == CodegenProfileId.evmYulSolc0834V1)
    "CLI emit profile"
  match ProofForgeV2.CLI.describeTargetText "evm" with
  | .ok text =>
      let expectedIds := String.intercalate ", "
        ((s2CatalogIdsWireOrderV1.filter fun id =>
          id != "effect.asynchronous-workflow" &&
            id != "effect.synchronous-call").toList)
      expect
        (text ==
          s!"target=evm\nprofile=evm-yul-solc-0.8.34-v1\nrequirements=#[{expectedIds}]")
        s!"describe-target exact S2 stdout, got {text}"
  | .error e => throw <| IO.userError e.render
  match ProofForgeV2.CLI.describeTargetText "noir" with
  | .ok text =>
      expect (hasSubstr text "failure.atomic-rollback") "noir describe S2"
      expect (!hasSubstr text "privateWitness")
        "noir describe must not surface privateWitness"
      expect (!hasSubstr text "ProgramRequirement")
        "noir describe uses S2 ids"
  | .error e => throw <| IO.userError e.render

private def testDescriptorParityNegatives : IO Unit := do
  -- describeImplementedJoin join-checks residual descriptor target/profile with
  -- the same equality predicates as Registry.resolveEngineeringRequirementsV1
  -- step 4. Product selection is private-ctor-only and always matches shipped
  -- descriptorForKind? for implemented kinds, so describe-join is the DI-
  -- visible path for those PF-REGISTRY-INVALID messages without a second
  -- product mint/factory seam.
  let implReg : ProofForgeV2.Targets.TargetRegistryV1.TargetRegistrationDataV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    displayName := "EVM"
    acceptanceProfileId := "phase1.evm-u64.v1"
    maturityLabel := "runtime-validated-alpha"
    semantics := {
      targetId := TargetId.evm
      executionHost := .evm
      commitModel := .transactionAtomic
      stateBinding := .contractStorage
      callModel := .synchronousMessage
      proofModel := .noProof
      settlementModel := .evmChain
    }
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
  }
  let wrongTargetDesc := { Targets.Evm.descriptor with targetId := TargetId.near }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongTargetDesc)
    "PF-REGISTRY-INVALID" "describe join target mismatch"
  let wrongProfileDesc :=
    { Targets.Evm.descriptor with codegenProfile := CodegenProfileId.nearWasmRawU64V1 }
  expectErrorCode
    (ProofForgeV2.CLI.describeImplementedJoin implReg wrongProfileDesc)
    "PF-REGISTRY-INVALID" "describe join profile mismatch"

/-- Arbitrary request matrices (unknown/version/digest/predicates/dup/order)
    are only legal on non-capability inspection seams. Product mint has no
    `requested?` surface after exact-resolver repair. -/
private def testRequestResolveNegativesOnInspection : IO Unit := do
  let trio ← s2Trio
  let r0 ← match trio[0]? with | some r => pure r | none => throw <| IO.userError "trio0"
  let r1 ← match trio[1]? with | some r => pure r | none => throw <| IO.userError "trio1"
  let r2 ← match trio[2]? with | some r => pure r | none => throw <| IO.userError "trio2"
  let rows ← liftResult productSupportRowsV1
  let supported ← match rows[0]? with
    | some row => pure row.supported
    | none => throw <| IO.userError "missing first support row"
  let unknown : RequirementRequestV1 := {
    id := "effect.synchronous-call"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[unknown] })
    "PF-REQ-UNSUPPORTED" "inspection unknown request"
  expectErrorCode
    (inspectResolveWithSeedV1 initialStaticRequirementSupportIndexV1Result
      TargetId.evm CodegenProfileId.evmYulSolc0834V1 { items := #[unknown] })
    "PF-REQ-UNSUPPORTED" "inspection-with-seed unknown request"
  let badVer := { r0 with version := { major := 0, minor := 0, patch := 1 } }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[badVer] })
    "PF-REQ-UNSUPPORTED" "inspection wrong version"
  let badDig := { r0 with digest := zeroDigest }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[badDig] })
    "PF-REQ-UNSUPPORTED" "inspection wrong digest"
  let withPred := { r0 with predicates := #[.boolEquals "flag" false] }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[withPred] })
    "PF-REQ-PRECONDITION" "inspection nonempty predicate"
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[r0, r0] })
    "PF-REQ-UNSUPPORTED" "inspection duplicate request"
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[r2, r1, r0] })
    "PF-REQ-UNSUPPORTED" "inspection reverse-order requests"
  let unknownWithPred : RequirementRequestV1 := {
    id := "disclosure.private-witness"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[.boolEquals "flag" true]
  }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[unknownWithPred] })
    "PF-REQ-UNSUPPORTED" "inspection non-catalog + predicates is unsupported"

/-- S6: product support authority rejects unsupported request matrices on the
    inspection seam; public residual Common.resolve is gone (deletion contract).
    The single-semantic Counter carrier mints capability only for the exact retained freeze. -/
private unsafe def testBackendSupportDefense : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-backend-def>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  -- Product path succeeds for exact retained freeze.
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.evm)
    "capability mint for Counter on EVM"
  -- Unsupported non-catalog id is rejected on inspection (not residual resolve).
  let unknown : RequirementRequestV1 := {
    id := "effect.synchronous-call"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  let rows ← liftResult productSupportRowsV1
  let supported ← match rows[0]? with
    | some row => pure row.supported
    | none => throw <| IO.userError "missing first support row"
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[unknown] })
    "PF-REQ-UNSUPPORTED" "inspection rejects unsupported requirement class"
  -- Public residual resolve/makePlan absence is asserted in testDeletionContract.

/-- Run `rg` over product/test trees; exit 0 with empty stdout = no matches. -/
private def rgExpectEmpty (pattern : String) (paths : Array String) (label : String) :
    IO Unit := do
  let args := #["--glob", "*.lean", "-n", "--no-heading", pattern] ++ paths
  let output ← IO.Process.output { cmd := "rg", args }
  -- rg exits 1 when no matches; that is success for a forbid gate.
  if output.exitCode == 0 then
    throw <| IO.userError
      s!"{label}: forbidden pattern still present:\n{output.stdout}"
  else if output.exitCode == 1 then
    pure ()
  else
    throw <| IO.userError
      s!"{label}: rg failed (exit {output.exitCode}): {output.stderr}"

/-- Run `rg` and require exactly one match whose line contains `mustContain`. -/
private def rgExpectOneContaining (pattern : String) (paths : Array String)
    (mustContain : String) (label : String) : IO Unit := do
  let args := #["--glob", "*.lean", "-n", "--no-heading", pattern] ++ paths
  let output ← IO.Process.output { cmd := "rg", args }
  unless output.exitCode == 0 do
    throw <| IO.userError
      s!"{label}: expected one match for '{pattern}', rg exit {output.exitCode}: {output.stderr}"
  let lines := (output.stdout.splitOn "\n").filter (fun l => !l.isEmpty)
  match lines with
  | [line] =>
      expect (hasSubstr line mustContain)
        s!"{label}: sole match must contain '{mustContain}', got: {line}"
  | _ =>
      throw <| IO.userError
        s!"{label}: expected exactly one match, got {lines.length}:\n{output.stdout}"

/-- Text-level deletion contract (no `just` re-entry — avoids recipe/suite cycles).
    Dual-arg sole API authority is the Lean Environment reflection gate below
    (`run_cmd`); just `requirement-resolver-deletion-gate` keeps the same
    checkSupport/materialize/emit/sole-mint greps and builds this module. -/
private def testDeletionContract : IO Unit := do
  -- Patterns for deleted call-sites are assembled so this suite does not embed
  -- the forbidden identifier sequences as contiguous source text (just gate
  -- also greps Tests/).
  let targetsCheckSupportPat := "\\bTargets\\." ++ "checkSupport\\b"
  rgExpectEmpty ("^\\s*def " ++ "checkSupport\\b") #["ProofForgeV2", "Tests"]
    "deletion: no checkSupport definition"
  rgExpectEmpty targetsCheckSupportPat #["ProofForgeV2", "Tests"]
    "deletion: no Targets checkSupport call-site"
  rgExpectEmpty ("^\\s*def materializeResult " ++ "\\(selection") #["ProofForgeV2"]
    "deletion: no selection-parameter materializeResult"
  rgExpectEmpty ("^\\s*def materialize " ++ "\\(selection") #["ProofForgeV2"]
    "deletion: no selection-parameter materialize"
  rgExpectEmpty ("^\\s*def emitProgram " ++ "\\(selection") #["ProofForgeV2"]
    "deletion: no selection-parameter emitProgram"
  rgExpectOneContaining ("ResolvedEngineeringBuildV1" ++ "\\.mk")
    #["ProofForgeV2"] "EngineeringBuildV1.lean"
    "sole mint ResolvedEngineeringBuild capability"
  rgExpectOneContaining ("CompiledSemanticV1" ++ "\\.mk")
    #["ProofForgeV2"] "Pipeline.lean"
    "sole mint CompiledSemantic carrier"
  -- S6: public residual resolve / validateResolved / makePlan closed.
  rgExpectEmpty ("^\\s*def " ++ "resolve\\b") #["ProofForgeV2/Targets/Common.lean"]
    "deletion: no public Common.resolve"
  rgExpectEmpty ("^\\s*def " ++ "validateResolved\\b") #["ProofForgeV2"]
    "deletion: no public validateResolved"
  rgExpectEmpty ("^\\s*def " ++ "makePlan\\b") #["ProofForgeV2/Targets"]
    "deletion: no public makePlan"
  rgExpectEmpty ("^\\s*def " ++ "lower\\b") #["ProofForgeV2/Targets"]
    "deletion: no public lower"
  rgExpectEmpty ("^\\s*def " ++ "emit\\b") #["ProofForgeV2/Targets"]
    "deletion: no public emit"
  rgExpectEmpty ("^\\s*def " ++ "planFromResidualAlpha\\b") #["ProofForgeV2/Targets"]
    "deletion: no public planFromResidualAlpha"
  rgExpectEmpty ("^\\s*def " ++ "planFromAlpha\\b") #["ProofForgeV2/Targets"]
    "deletion: no public planFromAlpha residual bypass"
  rgExpectEmpty ("^\\s*def " ++ "lowerPlan\\b") #["ProofForgeV2/Targets"]
    "deletion: no public lowerPlan residual bypass"
  rgExpectEmpty ("^\\s*def " ++ "filesFromIR\\b") #["ProofForgeV2/Targets"]
    "deletion: no public filesFromIR residual emit bypass"
  rgExpectEmpty ("namespace Residual") #["ProofForgeV2/Targets"]
    "deletion: no Residual characterization emission namespace"
  rgExpectEmpty ("^\\s*structure " ++ "ResolvedProgram\\b") #["ProofForgeV2"]
    "deletion: no public ResolvedProgram residual carrier"
  rgExpectEmpty ("supported" ++ "Requirements\\b") #["ProofForgeV2"]
    "deletion: TargetDescriptor has no residual supportedRequirements field"

private unsafe def testCapabilityMintUniqueness : IO Unit := do
  -- Private-ctor sole mint: only resolveEngineeringRequirementsV1 may call .mk.
  rgExpectOneContaining ("ResolvedEngineeringBuildV1" ++ "\\.mk")
    #["ProofForgeV2"] "EngineeringBuildV1.lean"
    "sole mint capability constructor"
  -- CompiledSemanticV1.mk sole mint in Compiler/Pipeline.lean (finishCompiledSemanticV1).
  rgExpectOneContaining ("CompiledSemanticV1" ++ "\\.mk")
    #["ProofForgeV2"] "Pipeline.lean"
    "sole mint carrier constructor"
  -- Positive product path still mints via the sole API (not a second factory).
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-mint>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.evm)
    "sole-mint product capability"
  -- Capability requirements accessor binds retained freeze (not a caller subset).
  let semanticV1 := CompiledSemanticV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"mint retained invalid: {repr e}"
  expect (Targets.ResolvedEngineeringBuildV1.requirementsOf capability == frozen)
    "sole-mint capability.requirements == retained freeze"

unsafe def run : IO Unit := do
  testFourRowTable
  testIndexValidationNegatives
  testSeedPrecedence
  testRequestInspectionErrors
  testProductFourTargets
  testEmptyRequirementsCapability
  testStateOnlySubsetCapability
  testCliEmitAndDescribe
  testDescriptorParityNegatives
  testRequestResolveNegativesOnInspection
  testBackendSupportDefense
  testDeletionContract
  testCapabilityMintUniqueness
  IO.println "Tests.Materialization.RequirementResolverV1: ok"

/-!
## Lean Environment dual-arg API reflection gate

Public product declarations under `ProofForgeV2` whose `ConstantInfo.type`
mentions **both** carrier FQNames (directly or via abbrev/`@[reducible]` alias)
may only be `ProofForgeV2.Targets.resolveEngineeringRequirementsV1`.

- Environment: library umbrella + shipped CLI root (`CLI.Main`)
- Public = name prefix + not private-mangled (`isPrivateName`)
- All typed ConstantInfo kinds scanned; **metadata-only** skip via authoritative
  Lean flags only: `isAuxRecursor`, `isNoConfusion`, kernel `.recInfo`
  (no broad parent-is-constructor exclusion)
- Type walk: shared total node budget worklist; alias expand (abbrev / reducible)
  costs budget; expanded-name cycle set; no opaque/regular bulk unfold
- Early success when both carriers observed; hits sorted by `Name.lt`
-/

/-- Full constant name of the selection carrier (must match Environment). -/
private def dualArgSelectionCarrierN : Name :=
  ``ProofForgeV2.Targets.BuildSelectionV1.ResolvedBuildSelectionV1

/-- Full constant name of the compiled semantic carrier (must match Environment). -/
private def dualArgCompiledCarrierN : Name :=
  ``ProofForgeV2.Compiler.CompiledSemanticV1

/-- Sole allowed product dual-arg public API (verified FQName). -/
private def dualArgProductAllowedN : Name :=
  ``ProofForgeV2.Targets.resolveEngineeringRequirementsV1

/-- Umbrella library coverage witness (ReferenceV1; outside old selected imports). -/
private def dualArgUmbrellaCoverageWitnessN : Name :=
  ``ProofForgeV2.Semantic.ReferenceV1.admitReferenceProgramSliceV1

/-- CLI root coverage witness (requires `import ProofForgeV2.CLI.Main`). -/
private def dualArgCliCoverageWitnessN : Name :=
  ``ProofForgeV2.CLI.run

/-- Resource ceilings for deterministic, fail-closed environment walks.
    Documented max values (not soft hints):
    - `dualArgMaxEnvConstants` — total `Environment.constants` entries visited
    - `dualArgMaxPrefixDecls` — public prefix surface candidates inspected
    - `dualArgMaxTypeExprNodes` — shared total Expr nodes + alias expands per type -/
private def dualArgMaxEnvConstants : Nat := 2_000_000
private def dualArgMaxPrefixDecls : Nat := 100_000
private def dualArgMaxTypeExprNodes : Nat := 100_000

/-- Result of a shared-budget dual-argument carrier type scan. -/
private inductive DualArgTypeScan where
  | mentionsBoth
  | doesNotMentionBoth
  | budgetExhausted

private def DualArgTypeScan.toReport : DualArgTypeScan → String
  | .mentionsBoth => "mentionsBoth"
  | .doesNotMentionBoth => "doesNotMentionBoth"
  | .budgetExhausted => "budgetExhausted"

/-- Enqueue all immediate Expr children (every constructor handled). -/
private def enqueueExprChildren (queue : Array Expr) : Expr → Array Expr
  | .bvar _ | .fvar _ | .mvar _ | .sort _ | .const _ _ | .lit _ =>
      queue
  | .app f a =>
      queue.push f |>.push a
  | .lam _ t b _ | .forallE _ t b _ =>
      queue.push t |>.push b
  | .letE _ t v b _ =>
      queue.push t |>.push v |>.push b
  | .mdata _ b | .proj _ _ b =>
      queue.push b

/-- Unfold only Lean `abbrev` (kernel hints.abbrev) or `@[reducible]` defs.
    Does **not** unfold opaque / non-reducible regular definitions. -/
private def tryUnfoldCarrierAlias (env : Environment) (n : Name) : Option Expr :=
  match env.find? n with
  | some (.defnInfo v) =>
      let status := getReducibilityStatusCore env n
      if v.hints.isAbbrev || status == .reducible then
        some v.value
      else
        none
  | _ => none

/-- Shared total-node budget type walk with abbrev/reducible alias awareness.
    - Each Expr pop costs 1
    - Each successful alias expand costs 1 more and enqueues the value
    - `expanded` NameSet prevents re-expand cycles (deterministic)
    - Early `mentionsBoth` when both bare carrier FQNames are observed -/
private def typeMentionsBothCarriers
    (env : Environment) (budget : Nat) (root : Expr) : DualArgTypeScan :=
  Id.run do
    let mut queue : Array Expr := #[root]
    let mut qi : Nat := 0
    let mut remaining : Nat := budget
    let mut hasSel : Bool := false
    let mut hasComp : Bool := false
    let mut expanded : NameSet := {}
    while qi < queue.size do
      if hasSel && hasComp then
        return DualArgTypeScan.mentionsBoth
      if remaining == 0 then
        return DualArgTypeScan.budgetExhausted
      let e := queue[qi]!
      qi := qi + 1
      remaining := remaining - 1
      match e with
      | .const n _ =>
          if n == dualArgSelectionCarrierN then
            hasSel := true
          if n == dualArgCompiledCarrierN then
            hasComp := true
          if hasSel && hasComp then
            return DualArgTypeScan.mentionsBoth
          -- Alias expand only when not already a bare carrier and not yet expanded.
          if n != dualArgSelectionCarrierN && n != dualArgCompiledCarrierN
              && !expanded.contains n then
            match tryUnfoldCarrierAlias env n with
            | none => pure ()
            | some value =>
                if remaining == 0 then
                  return DualArgTypeScan.budgetExhausted
                remaining := remaining - 1
                expanded := expanded.insert n
                queue := queue.push value
      | _ =>
          queue := enqueueExprChildren queue e
    if hasSel && hasComp then
      DualArgTypeScan.mentionsBoth
    else
      DualArgTypeScan.doesNotMentionBoth

/-- Metadata-backed generated eliminators (authoritative Lean flags + narrow
    enumeration of Lean-generated constructor children only).
    - `isAuxRecursor` / `isNoConfusion` / kernel `.recInfo`
    - Exact leaf under a constructor parent: `inj` | `injEq` | `sizeOf_spec` |
      `_flat_ctor` only (not every nested name under a constructor).
    User APIs under `Ctor.mk.planFromAlphaNested` remain visible. -/
private def isLeanGeneratedCtorChild (env : Environment) (n : Name) : Bool :=
  match n with
  | .str parent leaf =>
      env.isConstructor parent
        && (leaf == "inj" || leaf == "injEq" || leaf == "sizeOf_spec"
            || leaf == "_flat_ctor")
  | _ => false

private def isMetadataGeneratedEliminator
    (env : Environment) (n : Name) (info : ConstantInfo) : Bool :=
  isAuxRecursor env n
    || isNoConfusion env n
    || match info with
       | .recInfo _ => true
       | _ => false
    || isLeanGeneratedCtorChild env n

/-- Candidate: every public typed ConstantInfo under `namePrefix`, except private
    mangled names and metadata-confirmed generated eliminators. -/
private def isDualArgSurfaceCandidate
    (env : Environment) (namePrefix : Name) (n : Name) (info : ConstantInfo) : Bool :=
  !isPrivateName n
    && namePrefix.isPrefixOf n
    && !isMetadataGeneratedEliminator env n info

private structure DualArgFoldState where
  hits : Array Name := #[]
  prefixDecls : Nat := 0
  envConstants : Nat := 0

/-- Collect public dual-argument carrier type hits under `namePrefix`, sorted. -/
private def collectDualArgSurface
    (env : Environment) (namePrefix : Name) : Except String (Array Name) :=
  let acc : Except String DualArgFoldState :=
    env.constants.fold
      (fun acc n info =>
        match acc with
        | .error e => .error e
        | .ok st =>
            let st := { st with envConstants := st.envConstants + 1 }
            if st.envConstants > dualArgMaxEnvConstants then
              .error s!"resource: environment constant count exceeded {dualArgMaxEnvConstants}"
            else if !isDualArgSurfaceCandidate env namePrefix n info then
              .ok st
            else
              let st := { st with prefixDecls := st.prefixDecls + 1 }
              if st.prefixDecls > dualArgMaxPrefixDecls then
                .error s!"resource: public prefix decl count exceeded {dualArgMaxPrefixDecls}"
              else
                match typeMentionsBothCarriers env dualArgMaxTypeExprNodes info.type with
                | .budgetExhausted =>
                    .error s!"resource: type expr shared node budget exceeded for {n} (max {dualArgMaxTypeExprNodes})"
                | .mentionsBoth =>
                    .ok { st with hits := st.hits.push n }
                | .doesNotMentionBoth =>
                    .ok st)
      (Except.ok {})
  match acc with
  | .error e => .error e
  | .ok st =>
      .ok (st.hits.qsort Name.lt)

/-- Extra hits not in the sorted allowlist. -/
private def dualArgUnexpected
    (hits : Array Name) (allowedSorted : Array Name) : Array Name :=
  hits.filter fun n => !allowedSorted.any (· == n)

/-- Missing allowlist entries not present in sorted hits. -/
private def dualArgMissing
    (hits : Array Name) (allowedSorted : Array Name) : Array Name :=
  allowedSorted.filter fun n => !hits.any (· == n)

private def formatNameList (names : Array Name) : String :=
  String.intercalate ", " (names.toList.map Name.toString)

/-- Umbrella + CLI root coverage witnesses. -/
private def assertEnvironmentCoverage (env : Environment) : Except String Unit :=
  if !env.contains dualArgUmbrellaCoverageWitnessN then
    .error s!"env coverage: missing library umbrella witness {dualArgUmbrellaCoverageWitnessN}"
  else if !env.contains dualArgCliCoverageWitnessN then
    .error s!"env coverage: missing CLI root witness {dualArgCliCoverageWitnessN} (import ProofForgeV2.CLI.Main required)"
  else
    .ok ()

/-- Product private capability ctor must stay private-mangled and never appear
    as a public dual-arg hit (validates `isPrivateName` filter). -/
private def assertPrivateCapabilityCtorFiltered
    (env : Environment) (productHits : Array Name) : Except String Unit :=
  -- Public (non-mangled) name must not appear; the real ctor is private-mangled.
  if productHits.any fun n =>
      n == `ProofForgeV2.Targets.ResolvedEngineeringBuildV1.mk then
    .error "private-ctor filter: public ResolvedEngineeringBuildV1.mk must not be a dual-arg hit"
  else
    let privateDualCtors : Array Name :=
      env.constants.fold
        (fun acc n info =>
          if isPrivateName n
              && match info with | .ctorInfo _ => true | _ => false then
            match typeMentionsBothCarriers env dualArgMaxTypeExprNodes info.type with
            | .mentionsBoth => acc.push n
            | _ => acc
          else
            acc)
        #[]
    if privateDualCtors.isEmpty then
      .error "private-ctor filter: expected at least one private dual-argument ctor (ResolvedEngineeringBuildV1.mk)"
    else if privateDualCtors.any fun n => productHits.any (· == n) then
      .error s!"private-ctor filter: private dual ctor leaked into public hits: {formatNameList privateDualCtors}"
    else
      .ok ()

/-- Product gate: only the sole dual-arg mint under `ProofForgeV2`. -/
private def assertProductDualArgSurface (env : Environment) : Except String Unit :=
  match assertEnvironmentCoverage env with
  | .error e => .error e
  | .ok () =>
      match collectDualArgSurface env (Name.mkSimple "ProofForgeV2") with
      | .error e => .error e
      | .ok hits =>
          match assertPrivateCapabilityCtorFiltered env hits with
          | .error e => .error e
          | .ok () =>
              let allowed := #[dualArgProductAllowedN].qsort Name.lt
              let unexpected := dualArgUnexpected hits allowed
              let missing := dualArgMissing hits allowed
              if !unexpected.isEmpty then
                .error s!"dual-arg product surface: unexpected public declaration(s): {formatNameList unexpected}"
              else if !missing.isEmpty then
                .error s!"dual-arg product surface: missing allowed declaration(s): {formatNameList missing}"
              else
                .ok ()

/-- Reflection self-test probe prefix (must never enter product `ProofForgeV2` gate). -/
private def dualArgProbePrefix : Name :=
  `Tests.Materialization.RequirementResolverV1.DualArgProbe

private def dualArgExpectedProbes : Array Name :=
  #[
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeSimple,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeEscaped,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeNoncomputable,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeProtected,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeMutualA,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeMutualB,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.DualCtorProbe.mk,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeViaAlias,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeAliasChain,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeViaReducible,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probe_spec,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.sizeOfProbe
  ].qsort Name.lt

private def dualArgSingleTypeProbes : Array Name :=
  #[
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeOnlySelection,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeOnlyCompiled,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.SingleSelCtorProbe.mk,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.probeOnlySelectionAlias,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.single_spec,
    `Tests.Materialization.RequirementResolverV1.DualArgProbe.sizeOfOnlySelection
  ]

/-- Check single-type probes are present, not dual-arg hits, and type-not-dual. -/
private partial def checkDualArgSingleTypeProbes
    (env : Environment) (hits : Array Name) (i : Nat) : Except String Unit :=
  if h : i < dualArgSingleTypeProbes.size then
    let n := dualArgSingleTypeProbes[i]
    if hits.any (· == n) then
      .error s!"dual-arg self-test: single-type probe must not hit: {n}"
    else
      match env.find? n with
      | none =>
          .error s!"dual-arg self-test: missing single-type probe constant {n}"
      | some info =>
          match typeMentionsBothCarriers env dualArgMaxTypeExprNodes info.type with
          | .budgetExhausted =>
              .error s!"dual-arg self-test: shared node budget exhausted on single-type probe {n}"
          | .mentionsBoth =>
              .error s!"dual-arg self-test: single-type probe type wrongly dual: {n}"
          | .doesNotMentionBoth =>
              checkDualArgSingleTypeProbes env hits (i + 1)
  else
    .ok ()

/-- Self-test: probe prefix finds exactly the dual synthetic set; singles miss. -/
private def assertDualArgReflectionSelfTest (env : Environment) : Except String Unit :=
  match collectDualArgSurface env (Name.mkSimple "ProofForgeV2") with
  | .error e => .error e
  | .ok productHits =>
      if productHits.any dualArgProbePrefix.isPrefixOf then
        let leaked := productHits.filter dualArgProbePrefix.isPrefixOf
        .error s!"dual-arg self-test: product gate leaked Tests probe(s): {formatNameList leaked}"
      else
        match collectDualArgSurface env dualArgProbePrefix with
        | .error e => .error e
        | .ok hits =>
            let unexpected := dualArgUnexpected hits dualArgExpectedProbes
            let missing := dualArgMissing hits dualArgExpectedProbes
            if !unexpected.isEmpty then
              .error s!"dual-arg self-test: unexpected probe hit(s): {formatNameList unexpected}"
            else if !missing.isEmpty then
              .error s!"dual-arg self-test: missing expected probe(s): {formatNameList missing}"
            else
              checkDualArgSingleTypeProbes env hits 0

/-- Wide shallow Nat const app-spine for budget self-test (no dual carriers).
    `leafCount` leaves ⇒ `2 * leafCount - 1` nodes for leafCount ≥ 1. -/
private def mkNatAppSpine (leafCount : Nat) : Expr :=
  match leafCount with
  | 0 => Expr.const ``Nat []
  | n + 1 =>
      let rec go (i : Nat) (acc : Expr) : Expr :=
        match i with
        | 0 => acc
        | i + 1 => go i (Expr.app acc (Expr.const ``Nat []))
      go n (Expr.const ``Nat [])

private def natAppSpineNodeCount (leafCount : Nat) : Nat :=
  match leafCount with
  | 0 => 1
  | n + 1 => 2 * (n + 1) - 1

/-- Synthetic dual-argument carrier type: `ResolvedBuildSelectionV1 → CompiledSemanticV1 → Unit`. -/
private def mkSyntheticDualCarrierType : Expr :=
  Expr.forallE `selection
    (Expr.const dualArgSelectionCarrierN [])
    (Expr.forallE `compiled
      (Expr.const dualArgCompiledCarrierN [])
      (Expr.const ``Unit [])
      BinderInfo.default)
    BinderInfo.default

/-- Synthetic single-carrier type: `ResolvedBuildSelectionV1 → Unit`. -/
private def mkSyntheticSelectionOnlyType : Expr :=
  Expr.forallE `selection
    (Expr.const dualArgSelectionCarrierN [])
    (Expr.const ``Unit [])
    BinderInfo.default

/-- Synthetic dual type via abbrev aliases (exercises alias expand). -/
private def mkSyntheticAliasDualType : Expr :=
  Expr.forallE `selection
    (Expr.const ``Tests.Materialization.RequirementResolverV1.DualArgProbe.SelectionAlias [])
    (Expr.forallE `compiled
      (Expr.const ``Tests.Materialization.RequirementResolverV1.DualArgProbe.CompiledAlias [])
      (Expr.const ``Unit [])
      BinderInfo.default)
    BinderInfo.default

/-- Shared-budget + alias scanner self-test. -/
private def assertTypeScanBudgetSelfTest (env : Environment) : Except String Unit :=
  let leaves : Nat := 12
  let nodes := natAppSpineNodeCount leaves
  let wide := mkNatAppSpine leaves
  if nodes ≤ 1 then
    .error "budget self-test: internal node-count fixture invalid"
  else
    match typeMentionsBothCarriers env (nodes - 1) wide with
    | .budgetExhausted =>
        match typeMentionsBothCarriers env nodes wide with
        | .doesNotMentionBoth =>
            match typeMentionsBothCarriers env dualArgMaxTypeExprNodes
                mkSyntheticDualCarrierType with
            | .mentionsBoth =>
                match typeMentionsBothCarriers env dualArgMaxTypeExprNodes
                    mkSyntheticSelectionOnlyType with
                | .doesNotMentionBoth =>
                    match typeMentionsBothCarriers env dualArgMaxTypeExprNodes
                        mkSyntheticAliasDualType with
                    | .mentionsBoth =>
                        match typeMentionsBothCarriers env 1 mkSyntheticDualCarrierType with
                        | .budgetExhausted =>
                            -- Tiny budget on alias dual must exhaust (need expand + both).
                            match typeMentionsBothCarriers env 2 mkSyntheticAliasDualType with
                            | .budgetExhausted => .ok ()
                            | .mentionsBoth =>
                                .error "budget self-test: alias dual must not succeed with budget 2"
                            | .doesNotMentionBoth =>
                                .error "budget self-test: alias dual budget 2 must exhaust, not soft-miss"
                        | .mentionsBoth =>
                            .error "budget self-test: dual type must not succeed with budget 1"
                        | .doesNotMentionBoth =>
                            .error "budget self-test: dual type with budget 1 must exhaust, not soft-miss"
                    | other =>
                        .error s!"budget self-test: alias dual type expected mentionsBoth, got {other.toReport}"
                | other =>
                    .error s!"budget self-test: selection-only type expected non-dual, got {other.toReport}"
            | other =>
                .error s!"budget self-test: synthetic dual type expected mentionsBoth, got {other.toReport}"
        | .budgetExhausted =>
            .error s!"budget self-test: exact node budget {nodes} must accept wide spine"
        | .mentionsBoth =>
            .error "budget self-test: wide Nat spine must not mention both carriers"
    | .mentionsBoth =>
        .error "budget self-test: under-budget wide spine must not report dual"
    | .doesNotMentionBoth =>
        .error s!"budget self-test: under-budget ({nodes - 1} < {nodes}) wide spine must exhaust"

/-!
## Residual emission-bypass type-chain reflection gate (S6 repair)

Public `ProofForgeV2` declarations (defn / opaque / ctor) whose types form
capability-free SemanticProgram→Plan, Plan→IR, or IR→OutputFile/MaterializedArtifactsV1
chains are forbidden.

### Single worklist / state machine

One classifier, one shared state, one explicit stack. No separate multi-function
telescope re-scan paths.

**State**
- `remaining` — deterministic total **traversal-step** ceiling (not unique-node
  exactness; charged duplicate visits are allowed and count)
- `inputNames` / `resultNames` — const names seen in function domains vs codomains
- `expanded` — transparent abbrev/`@[reducible]` aliases already scheduled
- `directMandatoryCap` — a top-level explicit mandatory binder domain peels to
  exact `ResolvedEngineeringBuildV1`

**Frames**
- `topTelescope` — walking the top-level Π-spine body chain
- `input` — scanning a function domain (top-level binder or nested)
- `output` — scanning a function codomain / result

**Rules**
1. Every stack pop charges **1** fuel first.
2. `forall` / `app` / `lam` / `let` / `proj` / `mdata` children and alias-expansion
   bodies are pushed on the **same** stack (no uncharged Expr recursion).
3. Start frame is `topTelescope`. Top-level `forall`: domain is scanned as
   `input` (and, when `BinderInfo.default`, a charged head-peel checks exact
   capability authorization); body continues as `topTelescope`. Nested `forall`
   (not topTelescope): domain→`input`, body→`output`.
4. Authorization: only domain head after transparent alias peel is exactly
   `ResolvedEngineeringBuildV1`. `Option`/`Prod`/result-only capability do not
   authorize. Finding capability does **not** early-return; full type is always
   scanned to the fuel boundary.
5. Alias expansion uses the shared `expanded` set; expansion body is pushed on
   the stack (never mark-and-drop).
6. After the stack drains, forbid when `!directMandatoryCap` and collected
   input/result names form an effectful Semantic→Plan, Plan→IR, or IR→files chain.

`residualMaxTraversalSteps` is the per-declaration traversal-step ceiling.
-/

private def residualCapabilityN : Name :=
  ``ProofForgeV2.Targets.ResolvedEngineeringBuildV1

private def residualSemanticProgramN : Name :=
  ``ProofForgeV2.SemanticProgram

private def residualOutputFileN : Name :=
  ``ProofForgeV2.OutputFile

private def residualMaterializedArtifactsN : Name :=
  ``ProofForgeV2.MaterializedArtifactsV1

private def residualProbePlanN : Name :=
  ``Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.ProbePlan

private def residualProbeIRN : Name :=
  ``Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.ProbeIR

/-- Per-declaration deterministic traversal-step ceiling (charged pops + expands). -/
private def residualMaxTraversalSteps : Nat := 100_000

/-- Backward-compatible name used by older comments/tests. -/
private def residualMaxTypeNodes : Nat := residualMaxTraversalSteps

private def residualPlanNames : Array Name :=
  #[
    residualProbePlanN,
    ``ProofForgeV2.Targets.Evm.Plan,
    ``ProofForgeV2.Targets.Solana.Plan,
    ``ProofForgeV2.Targets.Near.Plan,
    ``ProofForgeV2.Targets.Noir.Plan
  ]

private def residualIRNames : Array Name :=
  #[
    residualProbeIRN,
    ``ProofForgeV2.Targets.Evm.IR,
    ``ProofForgeV2.Targets.Solana.IR,
    ``ProofForgeV2.Targets.Near.IR,
    ``ProofForgeV2.Targets.Noir.IR
  ]

private def nameSetHasAny (names : NameSet) (cands : Array Name) : Bool :=
  cands.any names.contains

/-- Scan context for a worklist frame. -/
private inductive ResidualFrameCtx where
  | topTelescope
  | input
  | output
  deriving BEq, Repr, Inhabited

private structure ResidualFrame where
  expr : Expr
  ctx : ResidualFrameCtx
  deriving Inhabited

private structure ResidualClassifierState where
  remaining : Nat
  inputNames : NameSet := {}
  resultNames : NameSet := {}
  expanded : NameSet := {}
  directMandatoryCap : Bool := false

/-- Instrumentation for O(1)-stack scaling regressions (test-only).
    `currentDepth` / `maxStack` are maintained by ±1 / +n on pop/push — never
    via container `.length`. `steps` counts every charged fuel unit (worklist
    pop, alias expand, capability peel). -/
private structure ResidualWorklistStats where
  currentDepth : Nat := 0
  maxStack : Nat := 0
  pushes : Nat := 0
  pops : Nat := 0
  steps : Nat := 0

private def ResidualClassifierState.recordConst (st : ResidualClassifierState)
    (ctx : ResidualFrameCtx) (n : Name) : ResidualClassifierState :=
  match ctx with
  | .topTelescope =>
      -- Non-Π content under topTelescope is the top-level result.
      { st with resultNames := st.resultNames.insert n }
  | .input =>
      { st with inputNames := st.inputNames.insert n }
  | .output =>
      { st with resultNames := st.resultNames.insert n }

/-- Charged head-peel for top-level mandatory binder domains.
    Each step consumes 1 fuel from `st.remaining`. Transparent aliases use a
    **local** expand set only (does not poison the worklist `expanded` set so
    the subsequent full domain scan still pushes expansion bodies). App peels
    follow the function side only. Returns updated state and peel fuel units
    charged (for stats.steps). -/
private def peelBinderRootForCapability (env : Environment)
    (st : ResidualClassifierState) (domain : Expr) :
    Except String (ResidualClassifierState × Nat) :=
  Id.run do
    let mut remaining := st.remaining
    let mut e := domain
    let mut localExpanded : NameSet := {}
    let mut charged : Nat := 0
    let mut guard : Nat := 0
    while guard ≤ residualMaxTraversalSteps do
      if remaining == 0 then
        return .error "residual type scan: shared traversal budget exhausted"
      remaining := remaining - 1
      charged := charged + 1
      guard := guard + 1
      match e with
      | .mdata _ b =>
          e := b
      | .app f _ =>
          e := f
      | .const n _ =>
          if localExpanded.contains n then
            return .ok ({
              st with
              remaining
              directMandatoryCap := st.directMandatoryCap || (n == residualCapabilityN)
            }, charged)
          else
            match tryUnfoldCarrierAlias env n with
            | none =>
                return .ok ({
                  st with
                  remaining
                  directMandatoryCap := st.directMandatoryCap || (n == residualCapabilityN)
                }, charged)
            | some value =>
                if remaining == 0 then
                  return .error "residual type scan: budget exhausted on alias expand"
                remaining := remaining - 1
                charged := charged + 1
                localExpanded := localExpanded.insert n
                e := value
      | _ =>
          return .ok ({ st with remaining }, charged)
    .error "residual type scan: binder peel step ceiling exceeded"
/-- Core residual type classifier: single worklist + shared state.
    Stack is a **List** (cons/pop-head) so push/pop are O(1) — never
    `Array.extract` prefix copies. Returns
    `(isForbiddenEmission, worklistStats)`.

    Chain detection is **wrapper-independent**: Semantic→Plan, Plan→IR, and
    IR→OutputFile/MaterializedArtifactsV1 depend only on `inputNames`/`resultNames` carrier
    presence (IO/Array/CompileResult/Except wrappers are traversed so carriers
    inside them still count; wrappers themselves are not required). -/
private def classifyResidualTypeWithStats (env : Environment) (budget : Nat)
    (root : Expr) : Except String (Bool × ResidualWorklistStats) :=
  Id.run do
    let mut st : ResidualClassifierState := { remaining := budget }
    -- LIFO List: cons/pop-head O(1). Depth tracked by counters only (no .length).
    let mut stack : List ResidualFrame :=
      [{ expr := root, ctx := .topTelescope }]
    let mut stats : ResidualWorklistStats :=
      { currentDepth := 1, maxStack := 1, pushes := 1, pops := 0, steps := 0 }
    while !stack.isEmpty do
      if st.remaining == 0 then
        return .error "residual type scan: shared traversal budget exhausted"
      let frame := stack.head!
      stack := stack.tail!
      -- Pop: depth −1, fuel −1, steps +1 (worklist pop).
      stats := {
        stats with
        pops := stats.pops + 1
        steps := stats.steps + 1
        currentDepth := stats.currentDepth - 1
      }
      st := { st with remaining := st.remaining - 1 }
      let e := frame.expr
      let ctx : ResidualFrameCtx :=
        match e, frame.ctx with
        | .forallE .., .topTelescope => .topTelescope
        | _, .topTelescope => .output
        | _, c => c
      match e with
      | .forallE _ d b bi =>
          match ctx with
          | .topTelescope =>
              if bi == BinderInfo.default then
                match peelBinderRootForCapability env st d with
                | .error err => return .error err
                | .ok (st', peelSteps) =>
                    st := st'
                    stats := { stats with steps := stats.steps + peelSteps }
              stack := { expr := b, ctx := .topTelescope } :: stack
              stack := { expr := d, ctx := .input } :: stack
              stats := {
                stats with
                pushes := stats.pushes + 2
                currentDepth := stats.currentDepth + 2
                maxStack := max stats.maxStack (stats.currentDepth + 2)
              }
          | .input | .output =>
              stack := { expr := b, ctx := .output } :: stack
              stack := { expr := d, ctx := .input } :: stack
              stats := {
                stats with
                pushes := stats.pushes + 2
                currentDepth := stats.currentDepth + 2
                maxStack := max stats.maxStack (stats.currentDepth + 2)
              }
      | .const n _ =>
          st := ResidualClassifierState.recordConst st ctx n
          if !st.expanded.contains n then
            match tryUnfoldCarrierAlias env n with
            | none => pure ()
            | some value =>
                if st.remaining == 0 then
                  return .error "residual type scan: budget exhausted on alias expand"
                st := {
                  st with
                  remaining := st.remaining - 1
                  expanded := st.expanded.insert n
                }
                stack := { expr := value, ctx } :: stack
                stats := {
                  stats with
                  steps := stats.steps + 1
                  pushes := stats.pushes + 1
                  currentDepth := stats.currentDepth + 1
                  maxStack := max stats.maxStack (stats.currentDepth + 1)
                }
      | .app f a =>
          stack := { expr := a, ctx } :: stack
          stack := { expr := f, ctx } :: stack
          stats := {
            stats with
            pushes := stats.pushes + 2
            currentDepth := stats.currentDepth + 2
            maxStack := max stats.maxStack (stats.currentDepth + 2)
          }
      | .lam _ t b _ =>
          stack := { expr := b, ctx } :: stack
          stack := { expr := t, ctx } :: stack
          stats := {
            stats with
            pushes := stats.pushes + 2
            currentDepth := stats.currentDepth + 2
            maxStack := max stats.maxStack (stats.currentDepth + 2)
          }
      | .letE _ t v b _ =>
          stack := { expr := b, ctx } :: stack
          stack := { expr := v, ctx } :: stack
          stack := { expr := t, ctx } :: stack
          stats := {
            stats with
            pushes := stats.pushes + 3
            currentDepth := stats.currentDepth + 3
            maxStack := max stats.maxStack (stats.currentDepth + 3)
          }
      | .mdata _ b =>
          stack := { expr := b, ctx } :: stack
          stats := {
            stats with
            pushes := stats.pushes + 1
            currentDepth := stats.currentDepth + 1
            maxStack := max stats.maxStack (stats.currentDepth + 1)
          }
      | .proj _ _ b =>
          stack := { expr := b, ctx } :: stack
          stats := {
            stats with
            pushes := stats.pushes + 1
            currentDepth := stats.currentDepth + 1
            maxStack := max stats.maxStack (stats.currentDepth + 1)
          }
      | .bvar _ | .fvar _ | .mvar _ | .sort _ | .lit _ =>
          pure ()
    -- Depth must drain; pushes − pops = 0 net frames.
    if stats.currentDepth != 0 || stats.pushes != stats.pops then
      return .error s!"residual worklist invariant: depth={stats.currentDepth} pushes={stats.pushes} pops={stats.pops}"
    if st.directMandatoryCap then
      return .ok (false, stats)
    let hasSemIn := st.inputNames.contains residualSemanticProgramN
    let hasPlanIn := nameSetHasAny st.inputNames residualPlanNames
    let hasIRIn := nameSetHasAny st.inputNames residualIRNames
    let hasPlanOut := nameSetHasAny st.resultNames residualPlanNames
    let hasIROut := nameSetHasAny st.resultNames residualIRNames
    let hasOutOut :=
      st.resultNames.contains residualOutputFileN
        || st.resultNames.contains residualMaterializedArtifactsN
    let semToPlan := hasSemIn && hasPlanOut
    let planToIR := hasPlanIn && hasIROut
    let irToFiles := hasIRIn && hasOutOut
    .ok (semToPlan || planToIR || irToFiles, stats)

/-- Core residual type classifier (boolean only). -/
private def classifyResidualType (env : Environment) (budget : Nat) (root : Expr) :
    Except String Bool :=
  match classifyResidualTypeWithStats env budget root with
  | .error e => .error e
  | .ok (b, _) => .ok b

/-- Public API name kept for tests/gates. -/
private def typeContainsForbiddenEmissionChain (env : Environment) (budget : Nat)
    (root : Expr) : Except String Bool :=
  classifyResidualType env budget root

/-- Public typed ConstantInfo kinds subject to residual emission-chain scanning. -/
private def isResidualScanKind (info : ConstantInfo) : Bool :=
  match info with
  | .defnInfo _ | .opaqueInfo _ | .ctorInfo _ => true
  | _ => false

private def residualScanDecl
    (env : Environment) (n : Name) (info : ConstantInfo) : Except String Bool :=
  if isPrivateName n then
    .ok false
  else if isMetadataGeneratedEliminator env n info then
    .ok false
  else if !isResidualScanKind info then
    .ok false
  else
    -- All public defn/opaque/ctor types use the same classifier (no packaging skip).
    classifyResidualType env residualMaxTraversalSteps info.type
private def residualProductForbidden (env : Environment) : Except String (Array Name) :=
  let acc : Except String (Array Name) :=
    env.constants.fold
      (fun acc n info =>
        match acc with
        | .error e => .error e
        | .ok hits =>
            if !(Name.mkSimple "ProofForgeV2").isPrefixOf n then .ok hits
            else
              match residualScanDecl env n info with
              | .error e => .error e
              | .ok true => .ok (hits.push n)
              | .ok false => .ok hits)
      (Except.ok #[])
  match acc with
  | .error e => .error e
  | .ok hits => .ok (hits.qsort Name.lt)

private def residualExpectedProbes : Array Name :=
  #[
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeSemToPlan,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probePlanToIR,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeIRToFiles,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.planFromAlphaRenamed,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaSemanticAlias,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaResultAlias,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaAbbrevChain,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaReducibleChain,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.opaqueSemToPlan,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.DirectCtorBypass.mk,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.DirectCtorBypass.planFromAlpha,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeResultOnlyCapIR,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeOptionCapBinder,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.CtorParentProbe.mk.planFromAlphaNested,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaNestedAliasPi,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaNestedReduciblePi,
    -- Wrapper-independent pure / files chains.
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probePureSemToPlan,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probePurePlanToIR,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeIRToArrayFiles,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeIRToIOArrayFiles,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeIRToIOMaterializedArtifacts,
    -- Ctor with function-valued forbidden field (full type scan, no packaging skip).
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.ProbePlanCarrier.mk,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.ProbePlanCarrier.lowerPlan
  ].qsort Name.lt

private def residualAllowedControls : Array Name :=
  #[
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapabilityPlan,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapabilityIR,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapabilityThenPlan,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaCapabilityAlias,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeValidateOnly,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.CapabilityCtorControl.mk,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapIRToArrayFiles,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapIRToIOArrayFiles,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapIRToIOMaterializedArtifacts,
    `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeCapPurePlanToIR
  ]

private def assertResidualBypassProductGate (env : Environment) : Except String Unit :=
  match residualProductForbidden env with
  | .error e => .error e
  | .ok hits =>
      if hits.isEmpty then
        .ok ()
      else
        .error s!"residual emission-bypass product surface: forbidden public declaration(s): {formatNameList hits}"

private def assertResidualBypassProbeSelfTest (env : Environment) : Except String Unit :=
  let probePrefix := `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe
  let acc : Except String (Array Name) :=
    env.constants.fold
      (fun acc n info =>
        match acc with
        | .error e => .error e
        | .ok hits =>
            if !probePrefix.isPrefixOf n then .ok hits
            else
              match residualScanDecl env n info with
              | .error e => .error e
              | .ok true => .ok (hits.push n)
              | .ok false => .ok hits)
      (Except.ok #[])
  match acc with
  | .error e => .error e
  | .ok hits =>
      let hits := hits.qsort Name.lt
      let unexpected := dualArgUnexpected hits residualExpectedProbes
      let missing := dualArgMissing hits residualExpectedProbes
      if !unexpected.isEmpty then
        .error s!"residual bypass self-test: unexpected probe hit(s): {formatNameList unexpected}"
      else if !missing.isEmpty then
        .error s!"residual bypass self-test: missing expected probe(s): {formatNameList missing}"
      else
        let leaked := residualAllowedControls.filter fun n => hits.any (· == n)
        if !leaked.isEmpty then
          .error s!"residual bypass self-test: allowed control wrongly hit: {formatNameList leaked}"
        else
          -- Presence of opaque/ctor kinds in expected set proves multi-kind scan.
          let hasOpaque := hits.any (· ==
            `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.opaqueSemToPlan)
          let hasCtor := hits.any (· ==
            `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.DirectCtorBypass.mk)
          if !hasOpaque || !hasCtor then
            .error "residual bypass self-test: expected opaqueInfo + ctorInfo hits"
          else
            .ok ()

-- Elaboration-time product dual-arg gate (lake build / Fast / full).
run_cmd do
  match assertProductDualArgSurface (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

-- Elaboration-time reflection self-test (probes + product isolation).
run_cmd do
  match assertDualArgReflectionSelfTest (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

-- Elaboration-time shared-budget + alias type-scan self-test.
run_cmd do
  match assertTypeScanBudgetSelfTest (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

/-- Build `d0 → d1 → … → result` (explicit mandatory binders). -/
private def mkForallSpine (domains : List Expr) (result : Expr) : Expr :=
  match domains with
  | [] => result
  | d :: rest =>
      Expr.forallE `x d (mkForallSpine rest result) BinderInfo.default

/-- Independent hand count for `Nat → Nat → Nat → Nat` under the shipped worklist:
    3× top-level forall pop + 3× charged binder-root peels (const Nat) +
    3× domain const pops + 1× result const pop = 10 traversal steps. -/
private def residualNatArrow3ExactSteps : Nat := 10

/-- Left-associated app spine: `((Nat Nat) Nat) …` — pending stack width grows
    with spine length (observable maxStack). -/
private def mkLeftAppSpine (leafCount : Nat) : Expr :=
  match leafCount with
  | 0 => Expr.const ``Nat []
  | n + 1 =>
      let rec go (i : Nat) (acc : Expr) : Expr :=
        match i with
        | 0 => acc
        | i + 1 => go i (Expr.app acc (Expr.const ``Nat []))
      go n (Expr.const ``Nat [])

/-- Balanced binary app tree over `leafCount` Nat leaves (maxStack ~ log). -/
private partial def mkBalancedAppTree (leafCount : Nat) : Expr :=
  if leafCount ≤ 1 then
    Expr.const ``Nat []
  else
    let mid := leafCount / 2
    Expr.app (mkBalancedAppTree mid) (mkBalancedAppTree (leafCount - mid))

/-- Focused residual budget / capability / O(1)-stack scale self-tests against the
    **shipped** `classifyResidualTypeWithStats` worklist only. -/
private def assertResidualBudgetSelfTest (env : Environment) : Except String Unit :=
  let natTy := Expr.const ``Nat []
  let tyA := mkForallSpine [natTy, natTy, natTy] natTy
  let stepsA := residualNatArrow3ExactSteps
  match classifyResidualTypeWithStats env stepsA tyA with
  | .error e =>
      .error s!"residual budget A: exact steps {stepsA} must succeed, got {e}"
  | .ok (true, _) =>
      .error "residual budget A: Nat arrows must not be classified as emission chains"
  | .ok (false, statsA) =>
      -- steps include peels+pops; depth/push-pop invariants.
      if statsA.steps != stepsA then
        .error s!"residual budget A: expected steps={stepsA}, got {statsA.steps}"
      else if statsA.currentDepth != 0 || statsA.pushes != statsA.pops then
        .error s!"residual budget A: depth/push-pop invariant failed depth={statsA.currentDepth} p={statsA.pushes}/{statsA.pops}"
      else if statsA.pops != 7 then
        .error s!"residual budget A: expected worklist pops=7, got {statsA.pops}"
      else
        match classifyResidualType env (stepsA - 1) tyA with
        | .ok _ =>
            .error "residual budget A: steps-1 must exhaust"
        | .error msg =>
            if (msg.splitOn "budget").length ≤ 1 then
              .error s!"residual budget A: expected budget error, got {msg}"
            else
              let capTy := Expr.const residualCapabilityN []
              let tyB := mkForallSpine [capTy] natTy
              let stepsB : Nat := 4
              match classifyResidualTypeWithStats env stepsB tyB with
              | .error e =>
                  .error s!"residual budget B: exact steps {stepsB} must succeed, got {e}"
              | .ok (true, _) =>
                  .error "residual budget B: direct capability binder must authorize"
              | .ok (false, statsB) =>
                  if statsB.steps != stepsB || statsB.currentDepth != 0 || statsB.pushes != statsB.pops then
                    .error s!"residual budget B: steps/depth invariant failed steps={statsB.steps}"
                  else
                    match classifyResidualType env (stepsB - 1) tyB with
                    | .ok _ =>
                        .error "residual budget B: capability type steps-1 must exhaust"
                    | .error msgB =>
                        if (msgB.splitOn "budget").length ≤ 1 then
                          .error s!"residual budget B: expected budget error, got {msgB}"
                        else
                          let checkSpine (leaves : Nat) : Except String ResidualWorklistStats :=
                            let spine := mkLeftAppSpine leaves
                            let need := natAppSpineNodeCount leaves
                            if need ≥ residualMaxTraversalSteps then
                              .error s!"spine {leaves} exceeds ceiling"
                            else
                              match classifyResidualTypeWithStats env residualMaxTraversalSteps spine with
                              | .error e => .error e
                              | .ok (true, _) =>
                                  .error s!"spine {leaves} must not be an emission chain"
                              | .ok (false, s) =>
                                  if s.currentDepth != 0 || s.pushes != s.pops then
                                    .error s!"spine {leaves}: depth/push-pop invariant"
                                  else if s.pops > 4 * leaves + 8 || s.pushes > 4 * leaves + 8 then
                                    .error s!"spine {leaves}: ops not linear pops={s.pops} pushes={s.pushes}"
                                  else if s.steps > 4 * leaves + 8 then
                                    .error s!"spine {leaves}: steps {s.steps} not linear"
                                  else if s.maxStack > leaves + 4 then
                                    .error s!"spine {leaves}: maxStack {s.maxStack} exceeds linear bound"
                                  else
                                    .ok s
                          match checkSpine 10000 with
                          | .error e => .error s!"residual scale 10k: {e}"
                          | .ok s10 =>
                              match checkSpine 20000 with
                              | .error e => .error s!"residual scale 20k: {e}"
                              | .ok s20 =>
                                  if s20.pops > 3 * s10.pops || s20.steps > 3 * s10.steps then
                                    .error s!"residual scale: superlinear 10k→20k pops {s10.pops}→{s20.pops} steps {s10.steps}→{s20.steps}"
                                  else
                                    let bal := mkBalancedAppTree 10000
                                    match classifyResidualTypeWithStats env residualMaxTraversalSteps bal with
                                    | .error e => .error s!"residual balanced 10k: {e}"
                                    | .ok (true, _) =>
                                        .error "residual balanced 10k must not be emission chain"
                                    | .ok (false, sb) =>
                                        if sb.currentDepth != 0 || sb.pushes != sb.pops then
                                          .error "residual balanced: depth/push-pop invariant"
                                        else if sb.maxStack ≥ s10.maxStack then
                                          .error s!"residual balanced maxStack {sb.maxStack} should be < left-spine {s10.maxStack}"
                                        else if sb.pops > 4 * 10000 + 8 || sb.steps > 4 * 10000 + 8 then
                                          .error s!"residual balanced ops not linear"
                                        else
                                          .ok ()

/-- C) Alias expansion body embeds nested forbidden Pi — residualScanDecl must hit. -/
private def assertResidualNestedAliasProbe (env : Environment) : Except String Unit :=
  let n := `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaNestedAliasPi
  match env.find? n with
  | none => .error s!"residual nested-alias probe missing: {n}"
  | some info =>
      match residualScanDecl env n info with
      | .error e => .error s!"residual nested-alias scan error: {e}"
      | .ok false =>
          .error "residual nested-alias: expected forbidden emission chain hit"
      | .ok true =>
          let n2 := `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.probeViaNestedReduciblePi
          match env.find? n2 with
          | none => .error s!"residual nested-reducible probe missing: {n2}"
          | some info2 =>
              match residualScanDecl env n2 info2 with
              | .error e => .error s!"residual nested-reducible scan error: {e}"
              | .ok false =>
                  .error "residual nested-reducible: expected forbidden emission chain hit"
              | .ok true =>
                  -- Synthetic carrier-like ctor with function-valued forbidden field.
                  let n3 := `Tests.Materialization.RequirementResolverV1.ResidualBypassProbe.ProbePlanCarrier.mk
                  match env.find? n3 with
                  | none => .error s!"residual ProbePlanCarrier.mk missing"
                  | some info3 =>
                      match residualScanDecl env n3 info3 with
                      | .error e => .error s!"residual ProbePlanCarrier.mk scan: {e}"
                      | .ok false =>
                          -- Fallback: direct shipped classifier on full ctor type.
                          match classifyResidualType env residualMaxTraversalSteps info3.type with
                          | .error e => .error e
                          | .ok false =>
                              .error "residual ProbePlanCarrier.mk: expected forbidden Plan→IR field chain"
                          | .ok true => .ok ()
                      | .ok true => .ok ()

-- S6 residual emission-bypass type-chain product gate.
run_cmd do
  match assertResidualBypassProductGate (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

-- Residual bypass synthetic renamed/alias probe self-test.
run_cmd do
  match assertResidualBypassProbeSelfTest (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

-- Residual type-scan shared total traversal-step self-test (A/B/F).
run_cmd do
  match assertResidualBudgetSelfTest (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

-- Nested alias/reducible Pi discovery via residualScanDecl (C).
run_cmd do
  match assertResidualNestedAliasProbe (← getEnv) with
  | .ok () => pure ()
  | .error message => throwError message

end Tests.Materialization.RequirementResolverV1
