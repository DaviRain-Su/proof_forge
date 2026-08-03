/-
  Tests.Materialization.EvmCorpusBlockedV1 — EVMOZ-005 Ownable/context.caller
  executable blocked case (class=`blocked`); EVMOZ-006 registers + pin locks.

  Authority:
    * fixture `testdata/evm-corpus/v1/programs/OwnableLike.lean`
    * case `testdata/evm-corpus/v1/cases/oz.f01.ownable.onlyowner.blocked.v1.json`
      (bytes bound by `testdata/evm-corpus/v1/manifest.json`)
    * product Loader → Normalize → Semantic/Reference → EVM planFromCapability

  Proves:
    1. Loader/Typed/Normalize succeed on the honest Ownable-like fixture
    2. Exact case pins: pfCommit baseline, Darwin ToolLockV4Digest, and
       Loader/Normalize `sourceHash`/`semanticHash` (no EVM caller lowering)
    3. Semantic retains caller ContextRead + exact `context.caller` requirement
    4. Reference with ADR-0025 canonical `u32le(20)||address20` context:
       authorized mutation succeeds; unauthorized assert rolls back pre-state
    5. EVM capability resolve succeeds; plan fails with typed
       `.planInvariant .evm` whose reason contains `ContextRead` + `caller`
       (before Finalize/ToolLock/Anvil/artifact mint)
    6. Forbidden early failures (toolchain-mismatch / parse-error /
       unrelated-type-error / missing-tool) do not satisfy the blocked matcher

  Non-claims: no OZ/ABI/family credit; F01 remains Blocked; not formal D2/D4;
  no Anvil; no artifact mint; no new EVM caller lowering.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
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

private def digestHex (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s =>
      match s.dropPrefix? "sha256:" with
      | some rest => pure rest.toString
      | none => pure s
  | .error e => throw <| IO.userError e

/-- Case identity pins (hardcoded; case bytes bound by corpus manifest). -/
private def expectedCaseId : String := "oz.f01.ownable.onlyowner.blocked.v1"
private def expectedPfCommit : String :=
  "23798ce65e559134adb0a9dd3504fc2f7e9669b6"
private def expectedToolLockDigest : String :=
  "63eadb99743addf944ce478b3763ca3258dd101a0c3df6a47213e64ff5386edf"
private def expectedSourceHash : String :=
  "1056bb66a65115bdbbd38655c85e53b5f9abe84a7a13ada2b7f3bed4d2b9db64"
private def expectedSemanticHash : String :=
  "4874d5f6e5b589a26f3175920fee6aa06d59009be8d8c38a45bdc3bd8c14dd75"
private def expectedProfile : String := "evm-yul-solc-0.8.34-cancun-v1"
private def expectedHardfork : String := "cancun"

/-- Corpus fixture path (project-relative; sole Ownable-like authority). -/
private def ownableSourcePath : FilePath :=
  FilePath.mk "testdata/evm-corpus/v1/programs/OwnableLike.lean"

private def ownableLogicalPath : String :=
  "testdata/evm-corpus/v1/programs/OwnableLike.lean"

private def ownableCasePath : FilePath :=
  FilePath.mk "testdata/evm-corpus/v1/cases/oz.f01.ownable.onlyowner.blocked.v1.json"

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

/-- Blocked-case matcher: typed `.planInvariant .evm` with ContextRead + caller. -/
private def matchesBlockedCallerPlanInvariant (error : CompileError) : Bool :=
  match error with
  | .planInvariant .evm msg =>
      containsSubstr msg "ContextRead" && containsSubstr msg "caller"
  | _ => false

private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

/-- Case file embeds exact pin surface (bytes also closed by corpus manifest). -/
private def testOwnableCasePinSurface : IO Unit := do
  unless ← ownableCasePath.pathExists do
    throw <| IO.userError s!"missing Ownable blocked case at {ownableCasePath}"
  let text ← IO.FS.readFile ownableCasePath
  expect (containsSubstr text expectedCaseId)
    "blocked case must embed exact case id"
  expect (containsSubstr text "\"class\":\"blocked\"")
    "blocked case must declare class=blocked"
  expect (containsSubstr text expectedPfCommit)
    "blocked case must pin frozen compiler baseline pfCommit"
  expect (containsSubstr text expectedToolLockDigest)
    "blocked case must pin Darwin ToolLockV4Digest (not raw lock SHA)"
  expect (containsSubstr text expectedSourceHash)
    "blocked case must pin real Loader sourceHash"
  expect (containsSubstr text expectedSemanticHash)
    "blocked case must pin real Normalize semanticHash"
  expect (containsSubstr text expectedProfile)
    "blocked case must pin Cancun profile id"
  expect (containsSubstr text expectedHardfork)
    "blocked case must pin hardfork=cancun"
  expect (containsSubstr text "\"runner\":\"lean-focused\"")
    "blocked case runner must be lean-focused"
  expect (containsSubstr text "\"phase\":\"plan\"")
    "blocked body phase must be plan"
  expect (containsSubstr text "ContextRead")
    "blocked diagnosticPatterns must include ContextRead"
  -- Placeholders from pre-EVMOZ-006 draft must not remain.
  expect (!containsSubstr text "0000000000000000000000000000000000000001")
    "blocked case must not retain placeholder pfCommit"
  expect (!containsSubstr text "0000000000000000000000000000000000000000000000000000000000000001")
    "blocked case must not retain placeholder sourceHash"
  expect (!containsSubstr text "0000000000000000000000000000000000000000000000000000000000000003")
    "blocked case must not retain placeholder toolLockDigest"

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

/-- EVM Plan fails closed at planInvariant before Finalize/ToolLock/artifacts. -/
private unsafe def testEvmPlanBlockedCaller
    (compiled : CompiledSemanticV1) : IO Unit := do
  -- Capability resolve must succeed (context.caller is wire-owned binder).
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult "capability" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  -- Plan must fail closed with typed .planInvariant .evm ContextRead+caller.
  match Targets.Evm.planFromCapability capability with
  | .error e =>
      expect (matchesBlockedCallerPlanInvariant e)
        s!"OwnableLike EVM plan must be planInvariant .evm citing ContextRead+caller, got {e.render}"
      -- Bounded reason surface also appears in CompileError.message.
      expect (containsSubstr e.message "ContextRead")
        s!"blocked reason must contain ContextRead, got {e.message}"
      expect (containsSubstr e.message "caller")
        s!"blocked reason must contain caller, got {e.message}"
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"blocked code must be PF-PLAN-INVARIANT, got {e.code}"
  | .ok _ =>
      throw <| IO.userError
        "OwnableLike must not produce an EVM plan while ContextRead caller is fail-closed"
  -- Convenience wrapper matches the same failure (no artifact path).
  match planEvm compiled with
  | .error e =>
      expect (matchesBlockedCallerPlanInvariant e)
        s!"planEvm must mirror planFromCapability blocked matcher, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "planEvm must not produce a plan"

/-- Forbidden early failures must not satisfy the blocked matcher. -/
private unsafe def testForbiddenEarlyFailuresDoNotMatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Synthetic CompileError constructors that must never count as the blocked case.
  expect (!matchesBlockedCallerPlanInvariant
      (.toolchainMismatch "solc" "0.8.34" "0.8.0"))
    "toolchain-mismatch must not satisfy blocked matcher"
  expect (!matchesBlockedCallerPlanInvariant (.toolchainMissing "solc"))
    "missing-tool must not satisfy blocked matcher"
  expect (!matchesBlockedCallerPlanInvariant
      (.invalidProgram "type mismatch: expected Bool, got UInt64"))
    "unrelated-type-error must not satisfy blocked matcher"
  expect (!matchesBlockedCallerPlanInvariant
      (.planInvariant .evm "storage layout overflow"))
    "unrelated planInvariant without ContextRead+caller must not match"
  expect (!matchesBlockedCallerPlanInvariant
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
          expect (!matchesBlockedCallerPlanInvariant e)
            s!"unrelated type/compile error must not satisfy blocked matcher, got {e.render}"
          expect (e.code != "PF-PLAN-INVARIANT" ||
              !(containsSubstr e.message "ContextRead" &&
                containsSubstr e.message "caller"))
            s!"type-bad must not be the ContextRead/caller planInvariant, got {e.render}"

/-- Suite entry (registered under EVMOZ-006 in Fast / Targets / aggregate). -/
unsafe def run : IO Unit := do
  testOwnableCasePinSurface
  let session ← Tests.Language.ParserSession.shared
  let compiled ← testOwnableNormalizeSemantic session
  testOwnableReferenceAuthorizedUnauthorized compiled
  testEvmPlanBlockedCaller compiled
  testForbiddenEarlyFailuresDoNotMatch session
  IO.println "Tests.Materialization.EvmCorpusBlockedV1: ok"

end Tests.Materialization.EvmCorpusBlockedV1
