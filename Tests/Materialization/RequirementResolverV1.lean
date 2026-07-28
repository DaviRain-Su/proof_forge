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
open ProofForgeV2.Targets.RequirementResolverV1
open Lean
open Lean.Elab.Command

/-! Synthetic dual-arg probes for Environment reflection self-test.
    Declared early so later `run_cmd` gates observe them. Product
    `ProofForgeV2` prefix gate must never include these. -/
namespace DualArgProbe

def probeSimple
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

def «probeEscaped»
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

noncomputable def probeNoncomputable
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

protected def probeProtected
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

mutual
  def probeMutualA
      (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Nat :=
    0
  def probeMutualB
      (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Nat :=
    0
end

/-- Single-carrier control: must **not** appear in dual-arg hits. -/
def probeOnlySelection (_s : ResolvedBuildSelectionV1) : Unit := ()

/-- Single-carrier control: must **not** appear in dual-arg hits. -/
def probeOnlyCompiled (_c : CompiledProgramV1) : Unit := ()

/-- Public structure whose constructor type carries both carriers. -/
structure DualCtorProbe where
  selection : ResolvedBuildSelectionV1
  compiled : CompiledProgramV1

/-- Public structure constructor control: selection only. -/
structure SingleSelCtorProbe where
  selection : ResolvedBuildSelectionV1

/-- Carrier aliases (`abbrev` → ReducibilityHints.abbrev). -/
abbrev SelectionAlias := ResolvedBuildSelectionV1
abbrev CompiledAlias := CompiledProgramV1

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
@[reducible] def CompiledReducible := CompiledProgramV1

def probeViaReducible
    (_s : SelectionReducible) (_c : CompiledReducible) : Unit :=
  ()

/-- Dual API whose **name** ends with `_spec` (must not be filtered by spelling). -/
def probe_spec
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

/-- Dual API whose **name** starts with `sizeOf` (must not be filtered by spelling). -/
def sizeOfProbe
    (_s : ResolvedBuildSelectionV1) (_c : CompiledProgramV1) : Unit :=
  ()

/-- Single-carrier control with `_spec` suffix name. -/
def single_spec (_s : ResolvedBuildSelectionV1) : Unit := ()

/-- Single-carrier control with `sizeOf` prefix name. -/
def sizeOfOnlySelection (_s : ResolvedBuildSelectionV1) : Unit := ()

end DualArgProbe

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
  expect (rows.size == 4) "exactly four support rows"
  let expectedKeys := #[
    ("evm", "evm-yul-solc-0.8.34-v1"),
    ("near", "near-wasm-raw-u64-v1"),
    ("noir", "noir-source-u64-relations-v1"),
    ("solana", "solana-sbpf-plan-v1")
  ]
  let mut i : Nat := 0
  while i < 4 do
    match rows[i]?, expectedKeys[i]? with
    | some row, some (tid, prof) =>
        expect (row.targetId.toString == tid) s!"row {i} targetId"
        expect (row.codegenProfile.toString == prof) s!"row {i} profile"
        expect (row.supported.size == 3) s!"row {i} S2 trio size"
        expect (row.supported.map (·.id) == s2CatalogIdsWireOrderV1)
          s!"row {i} S2 ids wire order"
        for item in row.supported do
          expect (item.version == s2RequirementVersionV1) s!"row {i} version 1.0.0"
          expect (item.predicates.isEmpty) s!"row {i} empty predicates"
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
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio
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
  -- Unknown requirement id (replace first with garbage but keep size)
  let unknown : RequirementRequestV1 := {
    id := "effect.event"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  let unkTrio := #[unknown, r1, r2]
  let unkRows := #[
    mkRow .evm CodegenProfileId.evmYulSolc0834V1 unkTrio,
    mkRow .near CodegenProfileId.nearWasmRawU64V1 trio,
    mkRow .noir CodegenProfileId.noirSourceU64RelationsV1 trio,
    mkRow .solana CodegenProfileId.solanaSbpfPlanV1 trio
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
  expect (insp.supported.size == 3) "DI inspection S2 trio"

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
  -- Full S2 trio success
  match inspectResolveRequestsV1 supported { items := trio } with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"full trio should succeed: {e.render}"
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
    ResolvedBuildSelectionV1 → CompiledProgramV1 →
      CompileResult Targets.ResolvedEngineeringBuildV1 :=
  Targets.resolveEngineeringRequirementsV1

#check (Targets.resolveEngineeringRequirementsV1 :
  ResolvedBuildSelectionV1 → CompiledProgramV1 →
    CompileResult Targets.ResolvedEngineeringBuildV1)

private unsafe def testProductFourTargets : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-counter>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let residual := CompiledProgramV1.alphaResidualOf compiled
  -- Retained frozen requirements from dual-carrier SemanticProgramV1.
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"Counter SemanticProgramV1 invalid: {repr e}"
  expect (frozen.items.map (·.id) == s2CatalogIdsWireOrderV1)
    "Counter retained requirements are the S2 trio"
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
    expect (accepted.items.map (·.id) == s2CatalogIdsWireOrderV1)
      s!"accepted S2 trio for {tid}"
    let output ← liftResult <| Targets.materializeResult capability
    expect (!output.files.isEmpty) s!"{tid} materialize via capability"
    expect (output.manifest.target == tid) s!"manifest target {tid}"
    expect (output.manifest.sourceHash == residual.sourceHash)
      s!"sourceHash {tid}"
    expect (output.manifest.semanticHash == residual.semanticHash)
      s!"semanticHash {tid}"
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
    mint those CompiledProgramV1 shapes). -/
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
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
  let frozen ← match validateSemanticProgramV1 semanticV1 with
    | .ok d => pure d.requirements
    | .error e => throw <| IO.userError s!"Echo SemanticProgramV1 invalid: {repr e}"
  expect frozen.items.isEmpty
    "Echo retained SemanticProgramV1 requirements must be empty (anti-hardcode S2 trio)"
  let residual := CompiledProgramV1.alphaResidualOf compiled
  expect residual.requirements.isEmpty
    "Echo residual alpha requirements must be empty"
  -- Capability success on all four implemented targets (sole mint / anti-hardcode).
  -- Residual backends for empty-state fragments (documented, not resolver bugs):
  --   * Solana: state-account plan requires initializer
  --   * Near: profile requires non-empty state (+ initializer)
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
        expect (!output.files.isEmpty)
          s!"{tid} empty-req materialize produces files"
        expect (output.manifest.target == tid)
          s!"Echo empty-req manifest target {tid}"
        expect (output.manifest.sourceHash == residual.sourceHash)
          s!"Echo empty-req sourceHash {tid}"
        materialized := materialized.push tid
    | .error e =>
        let msg := e.render
        let solanaLimited :=
          tid == TargetId.solana && hasSubstr msg "initializer"
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
    "Echo empty-req documents Solana residual initializer requirement"
  expect (backendLimited.any (fun s => hasSubstr s "near"))
    "Echo empty-req documents Near residual non-empty-state requirement"

private unsafe def testStateOnlySubsetCapability : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    stateOnlyHoldSourceText "<req-resolver-hold>"
    stateOnlyHoldModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
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
    expect (!output.files.isEmpty) s!"{tid} state-only subset materialize"

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
      expect
        (text ==
          "target=evm\nprofile=evm-yul-solc-0.8.34-v1\nrequirements=#[failure.atomic-rollback, state.persistent, value.checked-arithmetic]")
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
  let implReg : StaticBuildRegistrationV1 := {
    targetId := TargetId.evm
    kind := .evm
    implemented := true
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := some CodegenProfileId.evmYulSolc0834V1
    maturityLabel := "ok"
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
    id := "effect.synchronous-call"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[.boolEquals "flag" true]
  }
  expectErrorCode
    (inspectResolveRequestsV1 supported { items := #[unknownWithPred] })
    "PF-REQ-UNSUPPORTED" "inspection non-catalog + predicates is unsupported"

/-- Characterization: alpha Common.resolve still rejects unsupported requirements.
    Not a product aggregate path. Reuses real residual alpha from Counter and
    injects an unsupported requirement locally via `{ p with requirements := … }`. -/
private unsafe def testBackendAlphaDefense : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<req-resolver-backend-def>"
    Examples.counterModuleNameV1 none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let base := CompiledProgramV1.alphaResidualOf compiled
  let tainted : SemanticProgram := { base with requirements := #[.privateWitness] }
  match Targets.resolve .evm Targets.Evm.descriptor tainted with
  | .error (.unsupportedRequirement .privateWitness .evm) => pure ()
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"backend defense must report PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "EVM resolve must not accept privateWitness as supported"

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
    #["ProofForgeV2"] "Registry.lean"
    "sole mint ResolvedEngineeringBuild capability"
  rgExpectOneContaining ("CompiledProgramV1" ++ "\\.mk")
    #["ProofForgeV2"] "Pipeline.lean"
    "sole mint CompiledProgram carrier"

private unsafe def testCapabilityMintUniqueness : IO Unit := do
  -- Private-ctor sole mint: only resolveEngineeringRequirementsV1 may call .mk.
  rgExpectOneContaining ("ResolvedEngineeringBuildV1" ++ "\\.mk")
    #["ProofForgeV2"] "Registry.lean"
    "sole mint capability constructor"
  -- CompiledProgramV1.mk sole mint in Compiler/Pipeline.lean (compileValidatedSourceV1).
  rgExpectOneContaining ("CompiledProgramV1" ++ "\\.mk")
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
  let semanticV1 := CompiledProgramV1.semanticV1Of compiled
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
  testBackendAlphaDefense
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
- All typed ConstantInfo kinds scanned; **metadata-only** skip (no sizeOf/_spec/
  inj/noConfusion **spelling** filters): `isAuxRecursor`, `isNoConfusion`, kernel
  `.recInfo`, non-ctor nested under `Environment.isConstructor` parent
- Type walk: shared total node budget worklist; alias expand (abbrev / reducible)
  costs budget; expanded-name cycle set; no opaque/regular bulk unfold
- Early success when both carriers observed; hits sorted by `Name.lt`
-/

/-- Full constant name of the selection carrier (must match Environment). -/
private def dualArgSelectionCarrierN : Name :=
  ``ProofForgeV2.Targets.BuildSelectionV1.ResolvedBuildSelectionV1

/-- Full constant name of the compiled dual-carrier (must match Environment). -/
private def dualArgCompiledCarrierN : Name :=
  ``ProofForgeV2.Compiler.CompiledProgramV1

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

/-- Result of a shared-budget dual-carrier type scan. -/
private inductive DualCarrierTypeScan where
  | mentionsBoth
  | doesNotMentionBoth
  | budgetExhausted

private def DualCarrierTypeScan.toReport : DualCarrierTypeScan → String
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
    (env : Environment) (budget : Nat) (root : Expr) : DualCarrierTypeScan :=
  Id.run do
    let mut queue : Array Expr := #[root]
    let mut qi : Nat := 0
    let mut remaining : Nat := budget
    let mut hasSel : Bool := false
    let mut hasComp : Bool := false
    let mut expanded : NameSet := {}
    while qi < queue.size do
      if hasSel && hasComp then
        return DualCarrierTypeScan.mentionsBoth
      if remaining == 0 then
        return DualCarrierTypeScan.budgetExhausted
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
            return DualCarrierTypeScan.mentionsBoth
          -- Alias expand only when not already a bare carrier and not yet expanded.
          if n != dualArgSelectionCarrierN && n != dualArgCompiledCarrierN
              && !expanded.contains n then
            match tryUnfoldCarrierAlias env n with
            | none => pure ()
            | some value =>
                if remaining == 0 then
                  return DualCarrierTypeScan.budgetExhausted
                remaining := remaining - 1
                expanded := expanded.insert n
                queue := queue.push value
      | _ =>
          queue := enqueueExprChildren queue e
    if hasSel && hasComp then
      DualCarrierTypeScan.mentionsBoth
    else
      DualCarrierTypeScan.doesNotMentionBoth

/-- Metadata-backed generated eliminators only (no name-spelling filters).
    - `isAuxRecursor` — casesOn/recOn/… (env tag)
    - `isNoConfusion` — noConfusion family (env extension)
    - kernel `.recInfo`
    Nested lemmas under a **constructor** name (inj/injEq/sizeOf_spec/_flat_ctor)
    are identified via `Environment.isConstructor` on the parent (constructor
    metadata), not via sizeOf/_spec/inj string matching. That keeps user APIs
    named `probe_spec` / `sizeOfProbe` visible. -/
private def isMetadataGeneratedEliminator
    (env : Environment) (n : Name) (info : ConstantInfo) : Bool :=
  isAuxRecursor env n
    || isNoConfusion env n
    || match info with
       | .recInfo _ => true
       | _ => false
    || match n with
       | .str parent _ =>
           -- Any non-ctor decl nested under a constructor (Lean generates
           -- inj/injEq/sizeOf_spec/_flat_ctor here). Public dual-field `.mk`
           -- itself remains a constructor and is not excluded.
           env.isConstructor parent
             && !(match info with | .ctorInfo _ => true | _ => false)
       | _ => false

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

/-- Collect public dual-carrier type hits under `namePrefix`, sorted. -/
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
      .error "private-ctor filter: expected at least one private dual-carrier ctor (ResolvedEngineeringBuildV1.mk)"
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

/-- Synthetic dual-carrier type: `ResolvedBuildSelectionV1 → CompiledProgramV1 → Unit`. -/
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

end Tests.Materialization.RequirementResolverV1
