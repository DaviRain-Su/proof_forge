/-
  Tests.Semantic.AttachedValueContextV1 — ADR-0031 S4 shared-core pin.

  Source `context.attachedValue` → UInt64 ContextRead through Normalize +
  public `step` + OutcomeWire. Shared-core pin only; EVM Plan/Yul is
  SYS-S4-EVM (`Tests.Materialization.EvmSmoke`). Other targets stay FC.

  LH-27: invariant predicate reading `context.attachedValue` fails closed at
  Normalize (CheckV1 admits the surface; Wire/admit/step not reached).
  Wire InvariantClosure also forbids `.contextRead` on invariant roots
  (`.badCfg`) if a carrier were hand-built past Normalize.

  Not formal / not Anvil.
-/
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.OutcomeWireV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CheckV1
import Tests.Language.ParserSession

namespace Tests.Semantic.AttachedValueContextV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.OutcomeWireV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CheckV1

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

private def refU64 (tid : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId := tid, valueBytes := u64Bytes n }

/-- S4 positive: entry ContextRead attachedValue via Normalize + step. -/
private unsafe def testAttachedValueEntryOk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "S4Attached" <|
    "  state paid : UInt64\n" ++
    "  init() do\n" ++
    "    paid := 0\n" ++
    "  entry collect() : UInt64 do\n" ++
    "    paid := context.attachedValue\n" ++
    "    return paid\n"
  let validated ←
    match ← session.selectProgramV1 src
        "Tests/Semantic/AttachedValueContextV1.lean" "S4Attached" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"S4Attached load: {e.render}"
  let carrier ←
    match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"S4Attached normalize: {repr e}"
  let data ←
    match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"S4Attached validate: {repr e}"
  expect (data.requirements.items.any (fun r => r.id == wireContextAttachedValueIdV1))
    "S4 shared: Normalize must freeze context.attached-value requirement"
  let u64 : TypeIdV1 :=
    match data.types.findIdx? fun t =>
        t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
    | some i => UInt32.ofNat i
    | none => 0
  let mut initId : CallableIdV1 := 0
  let mut collectId : CallableIdV1 := 0
  let mut i : Nat := 0
  for c in data.callables do
    match c.name with
    | none => initId := UInt32.ofNat i
    | some "collect" => collectId := UInt32.ofNat i
    | _ => pure ()
    i := i + 1
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"S4Attached initial: {repr e}"
  let afterInit := step carrier initial
    { callableId := initId, args := #[], context := #[] } #[]
  let post ←
    match afterInit with
    | .returned s _ _ => pure s
    | other => throw <| IO.userError s!"S4Attached init: {repr other}"
  let missing := step carrier post
    { callableId := collectId, args := #[], context := #[] } #[]
  match missing with
  | .trapped .invalidInvocation _ => pure ()
  | other => throw <| IO.userError s!"S4Attached missing ctx: {repr other}"
  let ctx : Array ContextInputV1 :=
    #[{ key := attachedValueContextKeyV1, value := refU64 u64 42 }]
  let ok := step carrier post
    { callableId := collectId, args := #[], context := ctx } #[]
  match ok with
  | .returned _ (some v) _ =>
      expect (v.valueBytes == u64Bytes 42) "S4 shared: attachedValue result 42"
  | other => throw <| IO.userError s!"S4Attached collect: {repr other}"
  match mintReferenceOutcomeArtifactV1 ok with
  | .ok a =>
      match decodeReferenceOutcomeArtifactV1 a.canonicalBytes with
      | .ok again =>
          expect (again.canonicalBytes == a.canonicalBytes)
            "S4 shared: OutcomeWire identity"
      | .error e => throw <| IO.userError s!"S4 decode: {repr e}"
  | .error e => throw <| IO.userError s!"S4 mint: {repr e}"

/-- LH-27: invariant body ContextRead of attachedValue fails closed at Normalize.
    Mirrors CheckV1 N5 pureFn ContextRead FC; product boundary is Normalize
    (not Check, admit, or step). -/
private unsafe def testInvariantAttachedValueFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "InvAttached" <|
    "  state paid : UInt64\n" ++
    "  init() do\n" ++
    "    paid := 0\n" ++
    "  entry collect() : UInt64 do\n" ++
    "    paid := context.attachedValue\n" ++
    "    return paid\n" ++
    "  invariant noCtx : context.attachedValue == 0\n"
  let validated ←
    match ← session.selectProgramV1 src
        "Tests/Semantic/AttachedValueContextV1.lean" "InvAttached" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"InvAttached load: {e.render}"
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok
    s!"InvAttached: CheckV1 expected ok, got {typed.diagnostics.map (·.message)}"
  match normalizeProgramV1 validated with
  | .ok _ =>
      throw <| IO.userError
        "InvAttached: expected Normalize fail closed for invariant ContextRead"
  | .error (.unsupported detail) =>
      -- Place lowering hits allowContextCommit=false first (same string as
      -- pureFn); backup is "S1 invariant predicate must not use ContextRead…".
      expect
        (detail.contains "ContextRead" ||
          detail.contains "pureFn" ||
          detail.contains "invariant predicate")
        s!"InvAttached: unexpected detail {detail}"
  | .error e =>
      throw <| IO.userError s!"InvAttached: unexpected error {repr e}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testAttachedValueEntryOk session
  testInvariantAttachedValueFailClosed session
  IO.println "Tests.Semantic.AttachedValueContextV1: ok (S4 shared; Plans still FC)"

end Tests.Semantic.AttachedValueContextV1
