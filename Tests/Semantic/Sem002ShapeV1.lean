/-
  Tests.Semantic.Sem002ShapeV1 — engineering TST-SEM-002 *shape* pin.

  Uses the public `step` façade + retained OutcomeWire. Pins:
    * Examples/Counter no-initializer default state (initialized=true)
    * Counter-shaped initializer default (initialized=false → init)
    * context key/type/exact membership (missing / wrong / extra / duplicate / exact)
    * synchronous external-call returned/reverted response + exact occurrence
    * duplicate/reordered external responses → invalidExternalResponse
    * wrong callable kind/arity/type/noncanonical arg → invalidInvocation
    * context same-key wrong TypeId (Bool vs UInt64) → invalidInvocation
    * same-key different Core result TypeId → structure `.badCfg` (step unseen)
    * response missing / extra (exhaustion) → invalidExternalResponse
    * emit effect occurrence 0 + normalized UInt64 result bytes

  Does **not** close formal TASK-D2-07 / TST-SEM-002. Does **not** edit
  docs/04-task-breakdown.md or docs/05-test-spec.md status.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.OutcomeWireV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import Tests.Language.ParserSession

namespace Tests.Semantic.Sem002ShapeV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.OutcomeWireV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private def u64Bytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity 8
  let mut v := n
  for _ in [:8] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def logicalSlot (valueBytes : ByteArray) : ByteArray :=
  (encodeU32le (UInt32.ofNat valueBytes.size)).append valueBytes

private def refU64 (tid : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId := tid, valueBytes := u64Bytes n }

private def inv (id : CallableIdV1) (args : Array ReferenceValueV1)
    (context : Array ContextInputV1 := #[]) : InvocationV1 :=
  { callableId := id, args, context }

private def mintDigest (label : String) (outcome : OutcomeV1) : IO String := do
  let artifact ← match mintReferenceOutcomeArtifactV1 outcome with
    | .ok a => pure a
    | .error e => throw <| IO.userError s!"{label}: mint: {repr e}"
  match decodeReferenceOutcomeArtifactV1 artifact.canonicalBytes with
  | .ok again => do
      expect (again.canonicalBytes == artifact.canonicalBytes)
        s!"{label}: carrier identity"
      match outcomeOfArtifactV1 again with
      | .ok decoded =>
          expect (decoded == outcome) s!"{label}: structural outcome identity"
      | .error e =>
          throw <| IO.userError s!"{label}: outcome decode: {repr e}"
  | .error e =>
      throw <| IO.userError s!"{label}: decode: {repr e}"
  match renderDigest (referenceOutcomeDigestV1 artifact) with
  | .ok s =>
      match s.dropPrefix? "sha256:" with
      | some rest => pure rest.toString
      | none => pure s
  | .error e => throw <| IO.userError e

private def findU64 (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous UInt64"

private def findBool (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .bool => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous Bool"

private def findCallable (data : SemanticProgramDataV1) (name : Option String) :
    IO CallableIdV1 := do
  let mut i : Nat := 0
  for c in data.callables do
    match name, c.name with
    | none, none => return UInt32.ofNat i
    | some want, some got =>
        if got == want then return UInt32.ofNat i
    | _, _ => pure ()
    i := i + 1
  throw <| IO.userError s!"callable not found: {repr name}"

private unsafe def loadNormalize
    (session : Language.Loader.ParserSession)
    (relPath moduleName src : String) :
    IO (SemanticProgramV1 × SemanticProgramDataV1 × TypeIdV1) := do
  let validated ←
    match ← session.selectProgramV1 src relPath moduleName none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"{moduleName}: load: {e.render}"
  let carrier ←
    match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{moduleName}: normalize: {repr e}"
  let data ←
    match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{moduleName}: validate: {repr e}"
  let u64 ← findU64 data
  pure (carrier, data, u64)

private def expectReturnedValue
    (label : String) (outcome : OutcomeV1) (tid : TypeIdV1) (n : Nat) : IO Unit := do
  match outcome with
  | .returned _ (some v) _ =>
      expect (v.typeId == tid) s!"{label}: result typeId"
      expect (v.valueBytes == u64Bytes n) s!"{label}: result valueBytes"
  | .returned _ none _ =>
      throw <| IO.userError s!"{label}: expected some return value"
  | .reverted _ _ => throw <| IO.userError s!"{label}: expected returned"
  | .trapped f _ => throw <| IO.userError s!"{label}: trapped {repr f}"

private def expectTrappedInvocation
    (label : String) (outcome : OutcomeV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .trapped .invalidInvocation unchanged =>
      expect (unchanged == pre) s!"{label}: exact pre-state"
  | other =>
      throw <| IO.userError s!"{label}: expected invalidInvocation, got {repr other}"

private def expectTrappedExternalResponse
    (label : String) (outcome : OutcomeV1) (pre : LogicalStateV1) : IO Unit := do
  match outcome with
  | .trapped .invalidExternalResponse unchanged =>
      expect (unchanged == pre) s!"{label}: exact pre-state"
  | other =>
      throw <| IO.userError
        s!"{label}: expected invalidExternalResponse, got {repr other}"

/-- Counter-shaped no-initializer program (Examples/Counter business surface
    without the same-file Lean theorem, which is outside the portable DSL). -/
private unsafe def testNoInitProductCounter
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "CounterShape" <|
    "  state count : UInt64\n" ++
    "  entry increment() : UInt64 do\n" ++
    "    count := count + 2\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (carrier, data, u64) ←
    loadNormalize session "Tests/Semantic/Sem002ShapeV1.lean" "CounterShape" src
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Counter initial: {repr e}"
  expect (initial.initialized == true)
    "SEM-002 shape: no-init default initialized=true"
  expect (initial.canonicalValues == logicalSlot (u64Bytes 0))
    "SEM-002 shape: no-init default count=0"
  let incId ← findCallable data (some "increment")
  let getId ← findCallable data (some "get")
  let afterInc := step carrier initial (inv incId #[]) #[]
  expectReturnedValue "Counter/increment" afterInc u64 2
  let dInc ← mintDigest "Counter/increment" afterInc
  let post :=
    match afterInc with
    | .returned s _ _ => s
    | .reverted _ s => s
    | .trapped _ s => s
  expect (post.initialized == true) "Counter post initialized"
  expect (post.canonicalValues == logicalSlot (u64Bytes 2))
    "SEM-002 shape: increment writes count=2"
  let afterGet := step carrier post (inv getId #[]) #[]
  expectReturnedValue "Counter/get" afterGet u64 2
  let dGet ← mintDigest "Counter/get" afterGet
  expect (dInc == dGet)
    "SEM-002 shape: increment and follow-up get share the same returned Outcome"

/-- Initializer present ⇒ initialized=false default; init then increment. -/
private unsafe def testInitDefaultCounter
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Sem002Init" <|
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (carrier, data, u64) ←
    loadNormalize session "Tests/Semantic/Sem002ShapeV1.lean" "Sem002Init" source
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Sem002Init initial: {repr e}"
  expect (initial.initialized == false)
    "SEM-002 shape: initializer default initialized=false"
  expect (initial.canonicalValues == logicalSlot (u64Bytes 0))
    "SEM-002 shape: initializer still encodes default slot 0"
  let initId ← findCallable data none
  let incId ← findCallable data (some "increment")
  let afterInit := step carrier initial (inv initId #[refU64 u64 7]) #[]
  match afterInit with
  | .returned post none effects =>
      expect (post.initialized == true) "init sets initialized"
      expect (post.canonicalValues == logicalSlot (u64Bytes 7)) "init writes 7"
      expect (effects.isEmpty) "init has no effects"
  | other => throw <| IO.userError s!"init outcome: {repr other}"
  let _ ← mintDigest "Sem002Init/init" afterInit
  let postInit :=
    match afterInit with
    | .returned s _ _ => s
    | .reverted _ s => s
    | .trapped _ s => s
  let afterInc := step carrier postInit (inv incId #[refU64 u64 5]) #[]
  expectReturnedValue "Sem002Init/increment" afterInc u64 12

/-- context.unixTimeSeconds: missing / wrong type fail; exact key+UInt64 succeeds. -/
private unsafe def testContextKeyType
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Sem002Ctx" <|
    "  state t : UInt64\n" ++
    "  init() do\n" ++
    "    t := 0\n" ++
    "  entry stamp() : UInt64 do\n" ++
    "    t := context.unixTimeSeconds\n" ++
    "    return t\n" ++
    -- Intern anonymous Bool so the same-key wrong-TypeId case is canonical.
    "  fn flag(x : UInt64) : Bool do\n" ++
    "    return x == 0\n"
  let (carrier, data, u64) ←
    loadNormalize session "Tests/Semantic/Sem002ShapeV1.lean" "Sem002Ctx" source
  let initId ← findCallable data none
  let stampId ← findCallable data (some "stamp")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Sem002Ctx initial: {repr e}"
  let afterInit := step carrier initial (inv initId #[]) #[]
  let post ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"ctx init failed: {repr other}"
  let missing := step carrier post (inv stampId #[]) #[]
  expectTrappedInvocation "ctx/missing" missing post
  let _ ← mintDigest "ctx/missing" missing
  let wrong : Array ContextInputV1 :=
    #[{ key := unixTimeSecondsContextKeyV1,
        value := { typeId := u64, valueBytes := ByteArray.empty } }]
  let badType := step carrier post (inv stampId #[] wrong) #[]
  expectTrappedInvocation "ctx/wrong-bytes" badType post
  let clockRow : ContextInputV1 :=
    { key := unixTimeSecondsContextKeyV1, value := refU64 u64 99 }
  -- Canonically sorted, but contains one non-required UInt64 key. This isolates
  -- exact membership/cardinality rather than ordering or value-type rejection.
  let extra : Array ContextInputV1 := #[
    { key := blockHeightContextKeyV1, value := refU64 u64 1 },
    clockRow
  ]
  let extraOut := step carrier post (inv stampId #[] extra) #[]
  expectTrappedInvocation "ctx/extra" extraOut post
  let _ ← mintDigest "ctx/extra" extraOut
  let boolTid ← findBool data
  expect (boolTid != u64) "ctx: Bool and UInt64 TypeIds differ"
  let boolTrue : ReferenceValueV1 :=
    { typeId := boolTid, valueBytes := ByteArray.mk #[1] }
  match validateValueBytesV1 data.types boolTid boolTrue.valueBytes with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"ctx: canonical Bool rejected: {repr e}"
  let wrongType : Array ContextInputV1 :=
    #[{ key := unixTimeSecondsContextKeyV1, value := boolTrue }]
  let wrongTypeOut := step carrier post (inv stampId #[] wrongType) #[]
  expectTrappedInvocation "ctx/wrong-type" wrongTypeOut post
  let _ ← mintDigest "ctx/wrong-type" wrongTypeOut
  let duplicate : Array ContextInputV1 := #[clockRow, clockRow]
  let duplicateOut := step carrier post (inv stampId #[] duplicate) #[]
  expectTrappedInvocation "ctx/duplicate" duplicateOut post
  let _ ← mintDigest "ctx/duplicate" duplicateOut
  let clock : Array ContextInputV1 := #[clockRow]
  let ok := step carrier post (inv stampId #[] clock) #[]
  expectReturnedValue "ctx/stamp" ok u64 99
  let _ ← mintDigest "ctx/stamp" ok

/-- Source `call` with exact returned/reverted responses through the public
    façade. Returned commits the call effect; reverted preserves the exact
    pre-state and has no committed-effects field. -/
private unsafe def testExternalResponsesAndInvocationShape
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Sem002External" <|
    "  entry relay(value : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(value)\n" ++
    "    return value\n" ++
    "  entry relayTwice(value : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(value)\n" ++
    "    call Oracle.audit(value)\n" ++
    "    return value\n" ++
    -- Bool result intern (params remain non-Bool per Normalize declaration gate).
    "  fn flag(x : UInt64) : Bool do\n" ++
    "    return x == 0\n"
  let (carrier, data, u64) ←
    loadNormalize session "Tests/Semantic/Sem002ShapeV1.lean" "Sem002External" source
  let bool ← findBool data
  let relayId ← findCallable data (some "relay")
  let relayTwiceId ← findCallable data (some "relayTwice")
  let flagId ← findCallable data (some "flag")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Sem002External initial: {repr e}"
  expect initial.initialized "external: no-init program starts initialized"
  expect initial.canonicalValues.isEmpty "external: no logical state slots"
  let occurrence : EffectOccurrenceV1 := { effectId := 0, occurrence := 0 }
  let returnedResponses : ExternalResponsesV1 := #[{
    occurrence
    disposition := .returned
    returnValue? := none
  }]
  let returnedOut :=
    step carrier initial (inv relayId #[refU64 u64 7]) returnedResponses
  match returnedOut with
  | .returned post (some value) effects =>
      expect (post == initial) "external/returned: unchanged no-state post"
      expect (value == refU64 u64 7) "external/returned: normalized result"
      match effects.toList with
      | [effect] =>
          expect (effect.occurrence == occurrence)
            "external/returned: exact effect occurrence"
          match effect.payload with
          | .externalCall _ args =>
              expect (args == #[refU64 u64 7])
                "external/returned: exact call arguments"
          | _ => throw <| IO.userError "external/returned: expected externalCall effect"
      | _ =>
          throw <| IO.userError s!"external/returned: expected one effect, got {effects.size}"
  | other =>
      throw <| IO.userError s!"external/returned: unexpected outcome {repr other}"
  let returnedDigest ← mintDigest "external/returned" returnedOut

  let revertedResponses : ExternalResponsesV1 := #[{
    occurrence
    disposition := .reverted
    returnValue? := none
  }]
  let revertedOut :=
    step carrier initial (inv relayId #[refU64 u64 7]) revertedResponses
  match revertedOut with
  | .reverted (.externalCallReverted got) unchanged =>
      expect (got == occurrence) "external/reverted: exact response occurrence"
      expect (unchanged == initial) "external/reverted: exact pre-state"
  | other =>
      throw <| IO.userError s!"external/reverted: unexpected outcome {repr other}"
  let revertedDigest ← mintDigest "external/reverted" revertedOut
  expect (returnedDigest != revertedDigest)
    "external: returned/reverted OutcomeWire digests must differ"

  -- Valid invocation + empty responses: cursor missing, not invalidInvocation.
  let missingOut :=
    step carrier initial (inv relayId #[refU64 u64 7]) #[]
  expectTrappedExternalResponse "responses/missing" missingOut initial
  let missingDigest ← mintDigest "responses/missing" missingOut

  -- One call + two returned rows: first pair matches, exhaustion traps extra.
  let extraOccurrence : EffectOccurrenceV1 := { effectId := 1, occurrence := 0 }
  let extraResponses : ExternalResponsesV1 := #[
    { occurrence, disposition := .returned, returnValue? := none },
    { occurrence := extraOccurrence, disposition := .returned, returnValue? := none }
  ]
  let extraOut :=
    step carrier initial (inv relayId #[refU64 u64 7]) extraResponses
  expectTrappedExternalResponse "responses/extra" extraOut initial
  let extraDigest ← mintDigest "responses/extra" extraOut
  expect (missingDigest == extraDigest)
    "responses: missing/extra encode the same exact trapped Outcome"

  let wrongArity := step carrier initial (inv relayId #[]) #[]
  expectTrappedInvocation "invocation/wrong-arity" wrongArity initial
  let _ ← mintDigest "invocation/wrong-arity" wrongArity

  let boolTrue : ReferenceValueV1 :=
    { typeId := bool, valueBytes := ByteArray.mk #[1] }
  expect (bool != u64) "invocation: Bool and UInt64 TypeIds differ"
  match validateValueBytesV1 data.types bool boolTrue.valueBytes with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"invocation: canonical Bool rejected: {repr e}"

  -- Root pureFn is not an invocable public callable kind. Its argument is
  -- otherwise exact, isolating the kind gate from arity/type/value encoding.
  let wrongKind := step carrier initial (inv flagId #[boolTrue]) #[]
  expectTrappedInvocation "invocation/wrong-kind-pure-fn" wrongKind initial
  let _ ← mintDigest "invocation/wrong-kind-pure-fn" wrongKind

  -- Canonical Bool supplied where relay requires UInt64: exact TypeId mismatch.
  let wrongType := step carrier initial (inv relayId #[boolTrue]) #[]
  expectTrappedInvocation "invocation/wrong-arg-type" wrongType initial
  let _ ← mintDigest "invocation/wrong-arg-type" wrongType

  -- Correct UInt64 TypeId with a one-byte payload is noncanonical UInt64.
  let malformedU64 := ByteArray.mk #[1]
  match validateValueBytesV1 data.types u64 malformedU64 with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError "invocation: short UInt64 unexpectedly canonical"
  let noncanonical := step carrier initial
    (inv relayId #[{ typeId := u64, valueBytes := malformedU64 }]) #[]
  expectTrappedInvocation "invocation/noncanonical-arg-bytes" noncanonical initial
  let _ ← mintDigest "invocation/noncanonical-arg-bytes" noncanonical

  -- Establish the two-call fixture's exact cursor order before its negatives.
  let occurrenceSecond : EffectOccurrenceV1 := { effectId := 1, occurrence := 0 }
  let orderedResponses : ExternalResponsesV1 := #[
    { occurrence, disposition := .returned, returnValue? := none },
    { occurrence := occurrenceSecond, disposition := .returned, returnValue? := none }
  ]
  let orderedOut :=
    step carrier initial (inv relayTwiceId #[refU64 u64 7]) orderedResponses
  match orderedOut with
  | .returned unchanged (some value) effects =>
      expect (unchanged == initial) "responses/ordered: exact no-state post"
      expect (value == refU64 u64 7) "responses/ordered: exact return value"
      match effects.toList with
      | [first, second] =>
          expect (first.occurrence == occurrence)
            "responses/ordered: first occurrence"
          expect (second.occurrence == occurrenceSecond)
            "responses/ordered: second occurrence"
      | _ =>
          throw <| IO.userError
            s!"responses/ordered: expected two effects, got {effects.size}"
  | other =>
      throw <| IO.userError s!"responses/ordered: unexpected outcome {repr other}"
  let _ ← mintDigest "responses/ordered-control" orderedOut

  -- Duplicate and swapped response rows now exercise cursor order exactly.
  let duplicateResponses : ExternalResponsesV1 := #[
    { occurrence, disposition := .returned, returnValue? := none },
    { occurrence, disposition := .returned, returnValue? := none }
  ]
  let duplicateOut :=
    step carrier initial (inv relayTwiceId #[refU64 u64 7]) duplicateResponses
  expectTrappedExternalResponse "responses/duplicate-occurrence" duplicateOut initial
  let duplicateDigest ← mintDigest "responses/duplicate-occurrence" duplicateOut

  let reorderedResponses : ExternalResponsesV1 := #[
    { occurrence := occurrenceSecond, disposition := .returned, returnValue? := none },
    { occurrence, disposition := .returned, returnValue? := none }
  ]
  let reorderedOut :=
    step carrier initial (inv relayTwiceId #[refU64 u64 7]) reorderedResponses
  expectTrappedExternalResponse "responses/reordered-occurrence" reorderedOut initial
  let reorderedDigest ← mintDigest "responses/reordered-occurrence" reorderedOut
  expect (duplicateDigest == reorderedDigest)
    "responses: duplicate/reordered encode the same exact trapped Outcome"

/-- emit Tick: effect occurrence 0 and normalized result. -/
private unsafe def testEffectOccurrence
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "Sem002Emit" <|
    "  state c : UInt64\n" ++
    "  event Tick(n : UInt64)\n" ++
    "  init() do\n" ++
    "    c := 0\n" ++
    "  entry pulse() : UInt64 do\n" ++
    "    emit Tick(c)\n" ++
    "    c := c + 1\n" ++
    "    return c\n"
  let (carrier, data, u64) ←
    loadNormalize session "Tests/Semantic/Sem002ShapeV1.lean" "Sem002Emit" source
  let initId ← findCallable data none
  let pulseId ← findCallable data (some "pulse")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"Sem002Emit initial: {repr e}"
  let afterInit := step carrier initial (inv initId #[]) #[]
  let post ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"emit init failed: {repr other}"
  let pulsed := step carrier post (inv pulseId #[]) #[]
  match pulsed with
  | .returned s (some v) effects =>
      expect (v.typeId == u64) "emit result type"
      expect (v.valueBytes == u64Bytes 1) "emit result = 1"
      expect (s.canonicalValues == logicalSlot (u64Bytes 1)) "emit state = 1"
      match effects.toList with
      | [e] =>
          expect (e.occurrence.effectId == 0) "effectId 0"
          expect (e.occurrence.occurrence == 0) "occurrence 0"
          match e.payload with
          | .event eid args =>
              expect (eid == 0) "eventId 0"
              expect (args.size == 1) "Tick arity 1"
              match args.toList with
              | [a] =>
                  expect (a.valueBytes == u64Bytes 0)
                    "Tick arg is pre-increment c"
              | _ => throw <| IO.userError "Tick args"
          | _ => throw <| IO.userError "expected event payload"
      | _ => throw <| IO.userError s!"expected one effect, got {effects.size}"
  | other => throw <| IO.userError s!"pulse outcome: {repr other}"
  let _ ← mintDigest "Sem002Emit/pulse" pulsed

/-- Hand-built ContextRead pair on `unixTimeSeconds`. `sameType=true` is the
    legal same-key / same Core TypeId control; `false` is the TST-SEM-002
    leftover (UInt64 then Bool). Normalize cannot emit this mismatch. -/
private def ctxCoreTypeIdPair (sameType : Bool) : IO SemanticProgramDataV1 := do
  let qn ← match parseQualifiedName #["Tests", "Sem002CtxCore"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"ctx/core-type qn: {e}"
  let req ← match unixTimeSecondsContextRequirementV1 with
    | .ok row => pure row
    | .error e => throw <| IO.userError s!"ctx/core-type req: {e}"
  let boolTid : TypeIdV1 := 0
  let u64Tid : TypeIdV1 := 1
  let secondTid := if sameType then u64Tid else boolTid
  let ctxRead (vid : ValueIdV1) (tid : TypeIdV1) : InstructionV1 :=
    { result := some { valueId := vid, typeId := tid }
      op := .contextRead unixTimeSecondsContextKeyV1 }
  let runCallable : CallableV1 := {
    id := 0
    kind := .entry
    name := some "run"
    params := #[]
    result := { typeId := boolTid, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[ctxRead 0 u64Tid, ctxRead 1 secondTid]
      terminator := .return_ none
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  pure {
    qualifiedName := qn
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 64 }]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[runCallable]
    invariants := #[]
    requirements := { items := #[req] }
  }

/-- TST-SEM-002 leftover: same ContextRead key with two different Core result
    TypeIds is a structure-gate `.badCfg`. Encoder fails the same way, so no
    `SemanticProgramV1` carrier exists and `step` never sees the program.
    Do not weaken the wire gate to surface this at the invocation layer. -/
private def testSameKeyDifferentCoreResultTypeId : IO Unit := do
  let ok ← ctxCoreTypeIdPair true
  match validateSemanticProgramStructureV1 ok with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"ctx/core-type control structure: {repr e}"
  match encodeSemanticProgramDataV1 ok with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"ctx/core-type control encode: {repr e}"
  let bad ← ctxCoreTypeIdPair false
  match validateSemanticProgramStructureV1 bad with
  | .error .badCfg => pure ()
  | other =>
      throw <| IO.userError
        s!"ctx/core-type: expected .badCfg structure, got {repr other}"
  match encodeSemanticProgramDataV1 bad with
  | .error .badCfg => pure ()
  | other =>
      throw <| IO.userError
        s!"ctx/core-type: expected .badCfg encode, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testNoInitProductCounter session
  testInitDefaultCounter session
  testContextKeyType session
  testExternalResponsesAndInvocationShape session
  testEffectOccurrence session
  testSameKeyDifferentCoreResultTypeId
  IO.println "Tests.Semantic.Sem002ShapeV1: ok (engineering; not formal TST-SEM-002)"

end Tests.Semantic.Sem002ShapeV1
