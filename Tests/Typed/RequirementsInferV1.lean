/-
  Tests.Typed.RequirementsInferV1 — sole target-neutral requirement contribution
  analysis + Semantic.RequirementsV1 freeze integration.

  The contribution engine preserves source-order first-seen identities. The
  Semantic layer is its sole product consumer and owns closed-catalog rejection,
  request metadata, and canonical wire sorting. No alpha ProgramRequirement or
  Semantic.deriveRequirements parity path exists.
-/
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.RequirementsInferV1
import Tests.Language.ParserSession

namespace Tests.Typed.RequirementsInferV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.RequirementsInferV1

/-- Sole list authority (RequirementIdsV1); Array consumer stays RequirementsV1. -/
private abbrev s2CatalogList :=
  ProofForgeV2.Semantic.RequirementIdsV1.s2CatalogIdsWireOrderListV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def moduleName : String := "Tests.RequirementsInferV1"

private def contributionIds
    (contributions : Array RequirementContributionV1) : Array String :=
  contributions.map RequirementContributionV1.idOf

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source ("<req-infer-" ++ label ++ ">") moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private unsafe def inferSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × Array String) := do
  let validated ← loadSource session label source
  pure (validated, contributionIds (inferRequirementContributionsFromSourceV1 validated))

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private def fixtureProgramName (label : String) : String :=
  "Req_" ++ String.ofList (label.toList.map fun c => if c == '-' then '_' else c)

private def expectFreezeIds
    (label : String) (source : ValidatedSourceV1) (expected : Array String) : IO Unit := do
  match freezeProgramRequirementsFromSourceV1 source with
  | .error error => throw <| IO.userError s!"{label}: freeze failed: {error}"
  | .ok requirements =>
      expect (requirements.items.map (·.id) == expected)
        s!"{label}: frozen ids {requirements.items.map (·.id)}"
      for item in requirements.items do
        expect (item.version == s2RequirementVersionV1 && item.predicates.isEmpty)
          s!"{label}: version/predicate metadata for {item.id}"
        let digest ← match engineeringRequirementDigestV1 item.id with
          | .ok value => pure value
          | .error error => throw <| IO.userError s!"{label}: digest {error}"
        expect (item.digest == digest) s!"{label}: digest metadata for {item.id}"

private def expectFreezeReject
    (label expected : String) (source : ValidatedSourceV1) : IO Unit :=
  match freezeProgramRequirementsFromSourceV1 source with
  | .error error => expect (error == expected) s!"{label}: got {error}"
  | .ok _ => throw <| IO.userError s!"{label}: foreign contribution unexpectedly froze"

private unsafe def testCounterLike
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqCounter" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, ids) ← inferSource session "counter" source
  expect (ids == #["state.persistent", "value.checked-arithmetic",
      "failure.atomic-rollback"])
    s!"counter contribution order: {ids}"
  expectFreezeIds "counter" validated
    #["failure.atomic-rollback", "state.persistent", "value.checked-arithmetic"]

private unsafe def testForeignContributions
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- N1: private/commitment state+params are legal product surfaces; their
  -- infer-only disclosure ids are SKIPPED at freeze (never frozen, never
  -- rejected) — product disclosure is CheckV1/DisclosureCheck sole authority.
  let skipCases : Array (String × String × Array String × Array String) := #[
    ("private-state",
      "  state private value : UInt64\n  entry ping() : UInt64 do\n    return 0\n",
      #["state.persistent", "disclosure.private-state"],
      #["state.persistent"]),
    ("commitment-state",
      "  state commitment value : UInt64\n  entry ping() : UInt64 do\n    return 0\n",
      #["state.persistent", "disclosure.commitment-state"],
      #["state.persistent"]),
    ("private-param",
      "  entry run(private secret : UInt64) : UInt64 do\n    return 0\n",
      #["disclosure.private-witness"],
      #[]),
    ("commitment-param",
      "  entry run(commitment secret : UInt64) : UInt64 do\n    return 0\n",
      #["disclosure.commitment"],
      #[])]
  for testCase in skipCases do
    let label := testCase.1
    let body := testCase.2.1
    let expectedIds := testCase.2.2.1
    let frozenIds := testCase.2.2.2
    let (validated, ids) ← inferSource session label (wrap (fixtureProgramName label) body)
    expect (ids == expectedIds) s!"{label}: contribution ids {ids}"
    expectFreezeIds label validated frozenIds
  -- N2b: Field type contribution is infer-only and freeze-skipped (exact
  -- modular arithmetic is covered by value.checked-arithmetic when ops appear).
  let (fieldValidated, fieldIds) ← inferSource session "field"
    (wrap (fixtureProgramName "field")
      "  entry run(x : Field bn254_fr) : Field bn254_fr do\n    return x\n")
  expect (fieldIds == #["value.field.bn254-fr"])
    s!"field: contribution ids {fieldIds}"
  expectFreezeIds "field" fieldValidated #[]

  -- Wave I: call/schedule contributions are catalog members and freeze.
  let callCases : Array (String × String × Array String × Array String) := #[
    ("call",
      "  entry run() : UInt64 do\n    call External.Use()\n    return 0\n",
      #["effect.synchronous-call", "failure.atomic-rollback"],
      #["effect.synchronous-call", "failure.atomic-rollback"]),
    ("schedule",
      "  entry run() : UInt64 do\n    schedule External.Later()\n    return 0\n",
      #["effect.asynchronous-workflow"],
      #["effect.asynchronous-workflow"])]
  for testCase in callCases do
    let label := testCase.1
    let body := testCase.2.1
    let expectedIds := testCase.2.2.1
    let expectedFrozen := testCase.2.2.2
    let (validated, ids) ← inferSource session label (wrap (fixtureProgramName label) body)
    expect (ids == expectedIds) s!"{label}: contribution ids {ids}"
    expectFreezeIds label validated expectedFrozen

private unsafe def testCatalogAndDedup
    (session : Language.Loader.ParserSession) : IO Unit := do
  let publicSource := wrap "ReqPublic" <|
    "  state value : UInt64\n" ++
    "  entry ping(x : UInt64) : UInt64 do\n" ++
    "    return x\n"
  let (publicValidated, publicIds) ← inferSource session "public" publicSource
  expect (publicIds == #["state.persistent"])
    s!"public state contribution ids: {publicIds}"
  expectFreezeIds "public" publicValidated #["state.persistent"]

  -- Bool type carriers contribute catalog value.bool and now freeze.
  let boolSource := wrap "ReqBool" <|
    "  entry run(flag : Bool) : Bool do\n" ++
    "    return flag\n"
  let (boolValidated, boolIds) ← inferSource session "bool" boolSource
  expect (boolIds == #["value.bool"])
    s!"bool carrier contribution ids: {boolIds}"
  expectFreezeIds "bool" boolValidated #["value.bool"]

  -- Emit statements contribute catalog effect.event and now freeze.
  let emitSource := wrap "ReqEmit" <|
    "  event Ev()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    emit Ev()\n" ++
    "    return 0\n"
  let (emitValidated, emitIds) ← inferSource session "emit" emitSource
  expect (emitIds == #["effect.event"])
    s!"emit contribution ids: {emitIds}"
  expectFreezeIds "emit" emitValidated #["effect.event"]

  let rollbackSource := wrap "ReqRollback" <|
    "  error Boom()\n" ++
    "  entry run(x : Bool) : UInt64 do\n" ++
    "    assert x\n" ++
    "    revert Boom()\n" ++
    "    return 0\n"
  let (_, rollbackIds) ← inferSource session "rollback" rollbackSource
  expect (rollbackIds == #["value.bool", "failure.atomic-rollback"])
    s!"duplicate rollback contribution must be first-seen unique: {rollbackIds}"
  let (rollbackValidated, _) ← inferSource session "rollback-freeze" rollbackSource
  expectFreezeIds "rollback-freeze" rollbackValidated
    #["failure.atomic-rollback", "value.bool"]

private unsafe def testIdempotent
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqIdempotent" <|
    "  state count : UInt64\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"
  let (_, first) ← inferSource session "idem-a" source
  let (_, second) ← inferSource session "idem-b" source
  expect (first == second) s!"idempotent contribution ids: {first} vs {second}"

private unsafe def testCounterAuthority
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1 Examples.counterSourceText
      "<req-infer-counter-authority>" Examples.counterModuleNameV1 none with
  | .error error => throw <| IO.userError error.render
  | .ok source =>
      let ids := contributionIds (inferRequirementContributionsFromSourceV1 source)
      expect (ids == #["state.persistent", "value.checked-arithmetic",
          "failure.atomic-rollback"])
        s!"Counter contribution authority: {ids}"
      expectFreezeIds "Counter authority" source
        #["failure.atomic-rollback", "state.persistent", "value.checked-arithmetic"]

/-- T-3: context.caller / context.unixTimeSeconds / commit contribute wire ids
    (first-seen); freeze skips them (Normalize merges wire rows). -/
private unsafe def testContextCommitContributions
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ReqCtxCommit" <|
    "  state commitment sealed : UInt64\n" ++
    "  init() do\n" ++
    "    sealed := 0\n" ++
    "  entry both(x : UInt64) : UInt64 do\n" ++
    "    let t : UInt64 := context.unixTimeSeconds\n" ++
    "    sealed := commit(x)\n" ++
    "    let _who : Principal := context.caller\n" ++
    "    return t\n"
  let (validated, ids) ← inferSource session "ctx-commit-infer" source
  expect (ids.contains "context.unix-time-seconds")
    s!"T-3 missing unix-time contribution: {ids}"
  expect (ids.contains "context.caller")
    s!"T-3 missing caller contribution: {ids}"
  expect (ids.contains "disclosure.commitment")
    s!"T-3 missing commit contribution: {ids}"
  -- Freeze must not invent S2 rows for wire-owned keys.
  expectFreezeIds "ctx-commit-freeze" validated
    #["state.persistent"]

/-- Committed runtime parity: pinned S2 digests match independent
    `domainSeparatedSha256`, catalog Array/List identity, and near-neighbor
    unknown membership is false. No kernel SHA reduction required. -/
private def testS2CatalogDigestParity : IO Unit := do
  -- Sole list authority and Array projection must agree exactly.
  expect (s2CatalogList.toArray == s2CatalogIdsWireOrderV1)
    "S2 catalog Array must be List.toArray of sole wire-order list"
  expect (s2CatalogIdsWireOrderV1.size == 7)
    s!"S2 catalog size must be 7, got {s2CatalogIdsWireOrderV1.size}"
  expect (s2CatalogList.length == 7)
    s!"S2 catalog list length must be 7, got {s2CatalogList.length}"
  -- Membership positives for every catalog id; negatives for near neighbors.
  for id in s2CatalogIdsWireOrderV1 do
    expect (isS2CatalogIdV1 id)
      s!"catalog member must be accepted: {id}"
    expect (s2CatalogList.contains id)
      s!"list authority must contain catalog id: {id}"
  let unknownNeighbors : Array String := #[
    "value.boolx", "value.boole", "xvalue.bool", "value.bool ", " value.bool",
    "Value.bool", "value.Bool", "", "value.bool\n",
    "effect.asynchronous-workflowx", "effect.event.",
    "failure.atomic-rollbac", "state.persistents",
    "value.checked-arithmeti", "value.checked-arithmeticx",
    -- wire/infer-only ids must not enter the S2 membership gate
    "disclosure.commitment", "disclosure.private-state",
    "context.unix-time-seconds", "context.caller",
    "value.field.bn254-fr"
  ]
  for id in unknownNeighbors do
    expect (!isS2CatalogIdV1 id)
      s!"near-neighbor/unknown must be rejected: {repr id}"
    expect (!s2CatalogList.contains id)
      s!"list authority must reject near-neighbor: {repr id}"
  -- Pinned engineering digests equal independent pure SHA path (32B sha256).
  for id in s2CatalogIdsWireOrderV1 do
    let pinned ← match engineeringRequirementDigestV1 id with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"pinned digest {id}: {e}"
    let independent ← match
        domainSeparatedSha256 engineeringRequirementKeyDomainV1 id.toUTF8 with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"independent digest {id}: {e}"
    expect (pinned.algorithm == DigestAlgorithm.sha256)
      s!"pinned algorithm must be sha256 for {id}"
    expect (independent.algorithm == DigestAlgorithm.sha256)
      s!"independent algorithm must be sha256 for {id}"
    expect (pinned.bytes.size == 32)
      s!"pinned digest must be 32 bytes for {id}, got {pinned.bytes.size}"
    expect (independent.bytes.size == 32)
      s!"independent digest must be 32 bytes for {id}, got {independent.bytes.size}"
    expect (pinned == independent)
      s!"pinned digest must equal domainSeparatedSha256 for {id}"
    expect (pinned.bytes == independent.bytes)
      s!"pinned digest bytes must equal independent bytes for {id}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testCounterLike session
  testForeignContributions session
  testCatalogAndDedup session
  testIdempotent session
  testCounterAuthority session
  testContextCommitContributions session
  testS2CatalogDigestParity
  IO.println "Tests.Typed.RequirementsInferV1: ok"

end Tests.Typed.RequirementsInferV1
