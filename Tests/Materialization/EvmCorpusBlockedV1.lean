/-
  Tests.Materialization.EvmCorpusBlockedV1 — EVMOZ-005 Ownable/context.caller
  (ADR-0031 S1 / ADR-0030 E3 EVM leg: plan OPEN for context.caller).

  Authority:
    * fixture `testdata/evm-corpus/v1/programs/OwnableLike.lean`
    * product Loader → Normalize → Semantic/Reference → EVM planFromCapability

  Proves:
    1. Loader/Typed/Normalize succeed on the honest Ownable-like fixture
    2. Exact Loader/Normalize `sourceHash`/`semanticHash` pins
    3. Semantic retains caller ContextRead + exact `context.caller` requirement
    4. Reference with ADR-0025 canonical `u32le(20)||address20` context:
       authorized mutation succeeds; unauthorized assert rolls back pre-state
    5. EVM capability resolve + plan admit: OwnableLike lowers with
       `callerPrincipalWord` leaves and Yul `caller()` (ADR-0025 encoding)
    6. Historical blocked matcher (ContextRead+caller planInvariant) no longer
       fires on OwnableLike; unrelated planInvariant/toolchain errors still
       do not look like the retired blocked reason

  Non-claims: no OZ/ABI/family credit (F01 OZ observation credit still not
  claimed); not formal D2/D4; no Anvil in this suite (Anvil leg is
  `scripts/evm_caller_anvil_smoke.sh`).
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmCorpusBlockedV1

open System
open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1) :
    CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def digestHex (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s =>
      match s.dropPrefix? "sha256:" with
      | some rest => pure rest.toString
      | none => pure s
  | .error e => throw <| IO.userError e

/-- Fixture identity pins (Loader/Normalize; independent of retired blocked case). -/
private def expectedSourceHash : String :=
  "1056bb66a65115bdbbd38655c85e53b5f9abe84a7a13ada2b7f3bed4d2b9db64"
private def expectedSemanticHash : String :=
  "4874d5f6e5b589a26f3175920fee6aa06d59009be8d8c38a45bdc3bd8c14dd75"

/-- Corpus fixture path (project-relative; sole Ownable-like authority). -/
private def ownableSourcePath : FilePath :=
  FilePath.mk "testdata/evm-corpus/v1/programs/OwnableLike.lean"

private def ownableLogicalPath : String :=
  "testdata/evm-corpus/v1/programs/OwnableLike.lean"

private def ownableModule : String := "Tests.EvmCorpus.OwnableLike"

private def readOwnableSource : IO String := do
  unless ← ownableSourcePath.pathExists do
    throw <| IO.userError s!"missing OwnableLike fixture at {ownableSourcePath}"
  IO.FS.readFile ownableSourcePath

private unsafe def loadOwnable
    (session : Language.Loader.ParserSession) : IO ValidatedSourceV1 := do
  let text ← readOwnableSource
  expect (containsSubstr text "program OwnableLike where")
    "OwnableLike fixture must declare program OwnableLike"
  expect (containsSubstr text "context.caller")
    "OwnableLike fixture must use context.caller (no external caller spoof)"
  expect (containsSubstr text "state owner : Principal")
    "OwnableLike fixture must store Principal owner"
  expect (containsSubstr text "assert context.caller == owner")
    "OwnableLike fixture must enforce only-owner via byte-exact identity compare"
  expect (!containsSubstr text "entry setValue(caller")
    "OwnableLike must not take an external caller parameter"
  match ← session.selectProgramV1 text ownableLogicalPath ownableModule none with
  | .ok validated => pure validated
  | .error e =>
      throw <| IO.userError s!"OwnableLike Loader must succeed: {e.render}"

/-- ADR-0025 EVM caller Principal valueBytes: `u32le(20) || address20`. -/
private def principalCaller20 (fill : UInt8) : ByteArray :=
  let body := ByteArray.mk (Array.replicate 20 fill)
  (encodeU32le 20).append body

private def u64Bytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity 8
  let mut v := n
  for _ in [:8] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def stateSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def emptyResponses : ExternalResponsesV1 := #[]

private def invWithContext (callableId : CallableIdV1)
    (args : Array ReferenceValueV1) (context : Array ContextInputV1) : InvocationV1 :=
  { callableId, args, context }

private def logicalStateEq (a b : LogicalStateV1) : Bool :=
  a.initialized == b.initialized && a.canonicalValues == b.canonicalValues

private def refValueEq (a b : ReferenceValueV1) : Bool :=
  a.typeId == b.typeId && a.valueBytes == b.valueBytes

private def optionRefEq (a b : Option ReferenceValueV1) : Bool :=
  match a, b with
  | none, none => true
  | some x, some y => refValueEq x y
  | _, _ => false

private def expectReturned
    (label : String) (outcome : OutcomeV1)
    (post : LogicalStateV1) (value : Option ReferenceValueV1) : IO Unit := do
  match outcome with
  | .returned post' value' effects' =>
      expect (logicalStateEq post' post)
        s!"{label}: returned post-state mismatch"
      expect (optionRefEq value' value)
        s!"{label}: returned value mismatch"
      expect effects'.isEmpty
        s!"{label}: OwnableLike steps must not emit effects, got {effects'.size}"
  | .reverted reason _ =>
      throw <| IO.userError s!"{label}: expected returned, got reverted {repr reason}"
  | .trapped fault _ =>
      throw <| IO.userError s!"{label}: expected returned, got trapped {repr fault}"

private def expectRevertedStandard
    (label : String) (outcome : OutcomeV1)
    (code : StandardRevertCodeV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .reverted (.standard c) st =>
      expect (c == code) s!"{label}: standard code, got {repr c}"
      expect (logicalStateEq st pre) s!"{label}: revert must keep pre-state"
  | .reverted reason _ =>
      throw <| IO.userError
        s!"{label}: expected standard {repr code}, got {repr reason}"
  | .returned _ _ _ =>
      throw <| IO.userError s!"{label}: expected standard revert, got returned"
  | .trapped fault _ =>
      throw <| IO.userError
        s!"{label}: expected standard revert, got trapped {repr fault}"

/-- Retired blocked-case matcher (pre-S1): typed `.planInvariant .evm` with
    ContextRead + caller. Kept only to prove OwnableLike no longer matches. -/
private def matchesRetiredCallerPlanInvariant (error : CompileError) : Bool :=
  match error with
  | .planInvariant .evm msg =>
      containsSubstr msg "ContextRead" && containsSubstr msg "caller"
  | _ => false

private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

/-- Fixture surface: OwnableLike must keep honest caller-based only-owner. -/
private def testOwnableFixtureSurface : IO Unit := do
  unless ← ownableSourcePath.pathExists do
    throw <| IO.userError s!"missing OwnableLike fixture at {ownableSourcePath}"
  let text ← IO.FS.readFile ownableSourcePath
  expect (containsSubstr text "program OwnableLike where")
    "OwnableLike fixture must declare program OwnableLike"
  expect (containsSubstr text "context.caller")
    "OwnableLike fixture must use context.caller (no external caller spoof)"
  expect (containsSubstr text "state owner : Principal")
    "OwnableLike fixture must store Principal owner"
  expect (containsSubstr text "assert context.caller == owner")
    "OwnableLike fixture must enforce only-owner via byte-exact identity compare"

/-- Product path: Loader → compile → Semantic has caller ContextRead + requirement.
    Exact sourceHash/semanticHash pins must match case/manifest authority. -/
private unsafe def testOwnableNormalizeSemantic
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let validated ← loadOwnable session
  -- Direct Loader sourceHash pin (pre-compile).
  let srcHash ← match sourceHashV1 validated with
    | .ok d => digestHex d
    | .error e => throw <| IO.userError s!"OwnableLike sourceHash: {e}"
  expect (srcHash == expectedSourceHash)
    s!"OwnableLike sourceHash pin mismatch (got {srcHash})"
  -- Normalize path must agree with compile carrier.
  let normalized ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e =>
        throw <| IO.userError s!"OwnableLike Normalize must succeed: {repr e}"
  let normSem ← match semanticHashV1 normalized with
    | .ok d => digestHex d
    | .error e => throw <| IO.userError s!"OwnableLike semanticHash: {repr e}"
  expect (normSem == expectedSemanticHash)
    s!"OwnableLike Normalize semanticHash pin mismatch (got {normSem})"
  let compiled ← liftResult "compile OwnableLike" <|
    compileValidatedSourceV1 validated
  let srcHex ← liftResult "compiled sourceHash" <|
    CompiledSemanticV1.artifactSourceHashHexOf compiled
  let semHex ← liftResult "compiled semanticHash" <|
    CompiledSemanticV1.artifactSemanticHashHexOf compiled
  expect (srcHex == expectedSourceHash)
    s!"compiled sourceHash pin mismatch (got {srcHex})"
  expect (semHex == expectedSemanticHash)
    s!"compiled semanticHash pin mismatch (got {semHex})"
  let carrier := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e =>
        throw <| IO.userError s!"OwnableLike Semantic structure must validate: {repr e}"
  expect (data.requirements.items.any fun r => r.id == callerContextRequirementIdV1)
    "OwnableLike Semantic must carry exact context.caller requirement"
  let hasCallerRead := data.callables.any fun c =>
    c.blocks.any fun b =>
      b.instructions.any fun i =>
        match i.op with
        | .contextRead k => k == callerContextKeyV1
        | _ => false
  expect hasCallerRead
    "OwnableLike Semantic must contain Op.ContextRead proof-forge.context.caller.v1"
  let hasOwnerState := data.logicalState.any fun s => s.name == "owner"
  expect hasOwnerState "OwnableLike Semantic must declare owner state"
  pure compiled

/-- Reference: ADR-0025 20-byte caller principals; authorized/unauthorized outcomes. -/
private unsafe def testOwnableReferenceAuthorizedUnauthorized
    (compiled : CompiledSemanticV1) : IO Unit := do
  let carrier := CompiledSemanticV1.semanticV1Of compiled
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"ref: validate: {repr e}"
  let admitted ← match admitReferenceProgramSliceV1 carrier with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"ref: admit: {repr e}"
  let pTid? := data.types.findSome? fun decl =>
    match decl.name, decl.shape with
    | none, .principal => some decl.id
    | _, _ => none
  let some pTid := pTid? |
    throw <| IO.userError "ref: missing anonymous Principal type"
  let u64Tid? := data.types.findSome? fun decl =>
    match decl.name, decl.shape with
    | none, .uint 64 => some decl.id
    | _, _ => none
  let some u64Tid := u64Tid? |
    throw <| IO.userError "ref: missing anonymous UInt64 type"
  -- ADR-0025 canonical EVM caller form (24-byte valueBytes).
  let ownerBytes := principalCaller20 0x11
  let strangerBytes := principalCaller20 0x22
  expect (ownerBytes.size == 24) "ADR-0025 owner valueBytes must be 24 bytes"
  expect (strangerBytes.size == 24) "ADR-0025 stranger valueBytes must be 24 bytes"
  expect (ownerBytes != strangerBytes) "owner/stranger principals must differ"
  let ownerVal : ReferenceValueV1 := { typeId := pTid, valueBytes := ownerBytes }
  let strangerVal : ReferenceValueV1 := { typeId := pTid, valueBytes := strangerBytes }
  let key := callerContextKeyV1
  let ownerCtx : Array ContextInputV1 := #[{ key, value := ownerVal }]
  let strangerCtx : Array ContextInputV1 := #[{ key, value := strangerVal }]
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"ref: initial: {repr e}"
  -- init records context.caller → owner; value := 0
  let afterInit :=
    stepReferenceSliceV1 admitted initial
      (invWithContext 0 #[] ownerCtx) emptyResponses
  let ownedZero : LogicalStateV1 :=
    { initialized := true
      canonicalValues :=
        (stateSlot ownerBytes).append (stateSlot (u64Bytes 0)) }
  expectReturned "ownable-ref-init" afterInit ownedZero none
  -- authorized setValue(7) as owner
  let seven : ReferenceValueV1 := { typeId := u64Tid, valueBytes := u64Bytes 7 }
  let auth :=
    stepReferenceSliceV1 admitted ownedZero
      (invWithContext 1 #[seven] ownerCtx) emptyResponses
  let ownedSeven : LogicalStateV1 :=
    { initialized := true
      canonicalValues :=
        (stateSlot ownerBytes).append (stateSlot (u64Bytes 7)) }
  expectReturned "ownable-ref-authorized" auth ownedSeven (some seven)
  -- unauthorized setValue(9) as stranger → assertionFailed + rollback
  let nine : ReferenceValueV1 := { typeId := u64Tid, valueBytes := u64Bytes 9 }
  let unauth :=
    stepReferenceSliceV1 admitted ownedSeven
      (invWithContext 1 #[nine] strangerCtx) emptyResponses
  expectRevertedStandard "ownable-ref-unauthorized-rollback" unauth
    .assertionFailed ownedSeven
  -- view getValue needs no context (no ContextRead in view)
  let viewed :=
    stepReferenceSliceV1 admitted ownedSeven
      (invWithContext 2 #[] #[]) emptyResponses
  expectReturned "ownable-ref-view" viewed ownedSeven (some seven)
  pure ()

/-- ADR-0031 S1: EVM Plan admits OwnableLike context.caller (ADR-0025 encoding). -/
private unsafe def testEvmPlanAdmitsCaller
    (compiled : CompiledSemanticV1) : IO Unit := do
  -- Capability resolve must succeed (context.caller is wire-owned binder).
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult "capability" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← match Targets.Evm.planFromCapability capability with
    | .ok p => pure p
    | .error e =>
        throw <| IO.userError
          s!"OwnableLike EVM plan must admit context.caller (ADR-0031 S1), got {e.render}"
  -- Constructor stores owner from caller (9 Principal leaves).
  match plan.constructor with
  | none => throw <| IO.userError "OwnableLike must retain initializer"
  | some ctor =>
      expect (ctor.stores.size == 9 ||
          ctor.body.any fun s =>
            match s with
            | .storeAtomic ops => ops.size == 9
            | _ => false)
        "OwnableLike init must store 9 Principal owner leaves from context.caller"
  -- setValue entry must exist and assert caller==owner.
  expect (plan.entries.any fun e => e.name == "setValue")
    "OwnableLike must retain setValue entry"
  -- Convenience wrapper admits the same plan.
  let plan2 ← liftResult "planEvm OwnableLike" <| planEvm compiled
  expect (plan2.objectName == plan.objectName)
    "planEvm must mirror planFromCapability object name"
  -- Yul must emit CALLER opcode (view-safe).
  let output ← liftResult "materialize OwnableLike" <|
    materializeSelected TargetId.evm compiled
  let some yulFile := (MaterializedArtifactsV1.filesOf output).find?
      (·.path == "OwnableLike.yul") |
    throw <| IO.userError "OwnableLike: missing OwnableLike.yul"
  expect (yulFile.contents.contains "caller()")
    "OwnableLike Yul must contain the caller() opcode (ADR-0025)"
  -- Retired blocked matcher must not fire on the admitted plan path.
  expect (!matchesRetiredCallerPlanInvariant
      (.planInvariant .evm "storage layout overflow"))
    "unrelated planInvariant must not match retired caller matcher"

/-- Unrelated failures must not look like the retired ContextRead+caller block. -/
private unsafe def testForbiddenEarlyFailuresDoNotMatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  expect (!matchesRetiredCallerPlanInvariant
      (.toolchainMismatch "solc" "0.8.34" "0.8.0"))
    "toolchain-mismatch must not satisfy retired caller matcher"
  expect (!matchesRetiredCallerPlanInvariant (.toolchainMissing "solc"))
    "missing-tool must not satisfy retired caller matcher"
  expect (!matchesRetiredCallerPlanInvariant
      (.invalidProgram "type mismatch: expected Bool, got UInt64"))
    "unrelated-type-error must not satisfy retired caller matcher"
  expect (!matchesRetiredCallerPlanInvariant
      (.planInvariant .evm "storage layout overflow"))
    "unrelated planInvariant without ContextRead+caller must not match"
  expect (!matchesRetiredCallerPlanInvariant
      (.planInvariant .solana "ContextRead (context.caller) is not admitted"))
    "non-evm planInvariant must not match (target must be .evm)"
  -- Live parse-error: malformed source fails Loader, never reaches planInvariant.
  let malformed :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Broken where\n" ++
    "  state x : UInt64\n" ++
    "  init() do\n" ++
    "    x :=\n"
  match ← session.selectProgramV1 malformed
      "testdata/evm-corpus/v1/programs/malformed.lean"
      "Tests.EvmCorpus.Malformed" none with
  | .ok _ =>
      throw <| IO.userError "malformed program must fail at Loader/parser"
  | .error _ => pure ()
  -- Live unrelated type error: compiles fail before EVM plan with non-matcher error.
  let typeBad :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program TypeBad where\n" ++
    "  state x : UInt64\n" ++
    "  init() do\n" ++
    "    x := 0\n" ++
    "  entry bad() : UInt64 do\n" ++
    "    assert 1\n" ++
    "    return x\n" ++
    "  view get() : UInt64 do\n" ++
    "    return x\n"
  match ← session.selectProgramV1 typeBad
      "testdata/evm-corpus/v1/programs/type-bad.lean"
      "Tests.EvmCorpus.TypeBad" none with
  | .error e =>
      throw <| IO.userError
        s!"type-bad must load (type error is later): {e.render}"
  | .ok validated =>
      match compileValidatedSourceV1 validated with
      | .ok _ =>
          throw <| IO.userError
            "type-bad must fail compile (assert non-Bool), not succeed"
      | .error e =>
          expect (!matchesRetiredCallerPlanInvariant e)
            s!"unrelated type/compile error must not satisfy retired matcher, got {e.render}"

/-- Suite entry (registered under EVMOZ-006 in Fast / Targets / aggregate). -/
unsafe def run : IO Unit := do
  testOwnableFixtureSurface
  let session ← Tests.Language.ParserSession.shared
  let compiled ← testOwnableNormalizeSemantic session
  testOwnableReferenceAuthorizedUnauthorized compiled
  testEvmPlanAdmitsCaller compiled
  testForbiddenEarlyFailuresDoNotMatch session
  IO.println "Tests.Materialization.EvmCorpusBlockedV1: ok"

end Tests.Materialization.EvmCorpusBlockedV1
