import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.InvariantFoundationV1
import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.ReferenceMachineV1 — lower D2-07 admitted reference
  execution engine and invariant reference slice (engineering subset; not
  formal `step`, `evalInvariantV1`, or TST-SEM-002/003). Public declarations
  retain the `ProofForgeV2.Semantic.ReferenceV1` namespace.

  Owns closed runtime carriers (`ReferenceValueV1` … `OutcomeV1`), independent
  whole-program admission (`admitReferenceProgramSliceV1`), and the pure total
  machine `stepReferenceSliceV1`. `runInvariantCallableV1` is the lower
  selected-callable seam for the later formal InvariantABI evaluator; it does
  not depend on whole-program engineering admission.

  Admitted surface:
    * types: Bool / all Wire UInt/Int widths / BN254 Field / Unit / Bytes / Principal /
      String / fixed Array / Map / Struct / Option / Enum over acyclic recursively
      admitted payload types
    * ops: Literal, Constant, StateLoad/Store, Unary/Binary on admitted shapes,
      CheckedCast (UInt/Int combinations), Struct Construct/FieldGet/FieldSet,
      Option/Enum Construct/VariantTag/VariantPayload, PureCall, Assert, Emit,
      ExternalCall, Schedule, Unit/Array Construct, Map Construct (empty or
      flattened key/value pairs, upsert-fold last-wins — N-MAP-CONSTRUCT),
      Array/Bytes/Map IndexGet/IndexSet, ContextRead, Commit
    * terminators: Jump / Branch / Switch / Return / Revert / Trap
    * ExternalCall/Schedule args: Bool / legal UInt/Int widths / Bytes (no Unit;
      R-1 widens beyond UInt8/32/64 to match N-8 Normalize)
    * view: no StateStore / Emit / ExternalCall / Schedule
    * pureFn body: no StateLoad/Store / Emit / ExternalCall / Schedule;
      pureFn-to-pureFn PureCall is admitted
    * root invocation of pureFn/invariant is `.invalidInvocation`

  Rejected at admission (never masquerade as runtime invalidCore; only
  internalInvariant defense if admission is bypassed):
    recursive Struct/Array/Map/Option/Enum type graphs,
    Map Construct with odd arg count or nonzero constructor index,
    view/pureFn effect-or-state violations, ExternalCall/Schedule Unit args.
  Principal and String are identity-admitted leaves (N-2 / N4); resource
  bounds use worst-case `4 + maxTypeLengthV1` length-prefixed payloads.

  Semantics (SPEC-SEM-001 engineering):
    * dense ValueId env, state overlay, per-EffectId occurrence counters,
      response cursor, ordered provisional effects, fuel, loop-bound counters
    * external call consumes exactly one matching occurrence response
    * unique terminal finalizer: cursor exhaustion before publish; trailing
      responses → `.invalidExternalResponse` and discard overlay/effects
    * only `.returned` commits overlay/effects; init success sets
      `initialized=true`; revert/trap return pre byte-for-byte

  N5b/N-2 ContextRead / Commit step contract (engineering; product surface via
  Normalize `context.unixTimeSeconds` / `context.caller` / bare `commit(x)`):
    * ContextRead closed keys:
      - `proof-forge.context.unix-time-seconds.v1` → anonymous UInt64
      - `proof-forge.context.caller.v1` → anonymous Principal (N-2)
      - `proof-forge.context.block-height.v1` → anonymous UInt64 (ADR-0031 S2)
      Invocation gate collects the exact key/result-TypeId set reachable from
      the selected root through static PureCall edges; supplied
      `InvocationV1.context` must be strict key-ascending, exact membership,
      TypeId match, and canonical valueBytes, else `invalidInvocation`
      (before lifecycle and responses). Runtime looks up the immutable
      Machine-level context snapshot (not copied into PureCall frames);
      missing/TypeId mismatch after the gate is `internalInvariant`. Context
      never enters overlay or ordered effects.
    * Commit: label-only identity (SPEC wire). Result binds the operand's
      exact TypeId and canonical valueBytes unchanged; no hash, salt, or
      re-encode; no overlay/effect mutation. Cryptographic commitment
      realization remains target capability/materialization.
    * Rollback: ContextRead and Commit do not publish state. Any provisional
      StateStore after Commit, or any ContextRead on a path that later
      assert-fails / reverts / traps, discards the overlay with the standard
      terminal rule — pre-state byte-for-byte, zero committed effects.
    * Invariant roots and reachable pureFn closure still forbid ContextRead
      and Commit at the Wire structure gate; `runInvariantCallableV1` uses an
      empty context array.

  No `partial` / `unsafe` / `IO`. Does not import alpha Core.Semantics /
  SemanticIR or the upper InvariantABI façade. Does not export formal `step`.
-/

namespace ProofForgeV2.Semantic.ReferenceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.WireV1

/-! ### Local Repr helpers (ByteArray / LogicalState not fully Repr in deps) -/

private instance : Repr ByteArray where
  reprPrec bytes _ :=
    (Std.Format.text "ByteArray.size=").append (repr bytes.size)

private instance : Repr LogicalStateV1 where
  reprPrec s _ :=
    ((Std.Format.text "LogicalStateV1(initialized=")
      |>.append (repr s.initialized)
      |>.append (Std.Format.text ",canonicalValues.size=")
      |>.append (repr s.canonicalValues.size)
      |>.append (Std.Format.text ")"))

private def byteAt? (bytes : ByteArray) (i : Nat) : Option UInt8 :=
  if i < bytes.size then some (bytes.get! i) else none

/-! ### Runtime carriers (structural equality) -/

structure ReferenceValueV1 where
  typeId     : TypeIdV1
  valueBytes : ByteArray
  deriving BEq, Repr

structure ContextInputV1 where
  key   : SchemaId
  value : ReferenceValueV1
  deriving BEq, Repr

structure InvocationV1 where
  callableId : CallableIdV1
  args       : Array ReferenceValueV1
  context    : Array ContextInputV1
  deriving BEq, Repr

inductive ExternalResponseDispositionV1 where
  | returned
  | reverted
  deriving BEq, Repr, DecidableEq

structure ExternalResponseV1 where
  occurrence  : EffectOccurrenceV1
  disposition : ExternalResponseDispositionV1
  /-- N-CALL-RET: value produced by the callee when `disposition = returned`
      and the program binds the call result; `none` for void calls. Runtime
      checks the type against the instruction result when bound. -/
  returnValue? : Option ReferenceValueV1 := none
  deriving BEq, Repr

abbrev ExternalResponsesV1 := Array ExternalResponseV1

inductive OrderedEffectPayloadV1 where
  | event        (eventId : EventIdV1) (args : Array ReferenceValueV1)
  | externalCall (callee : QualifiedName) (args : Array ReferenceValueV1)
  | schedule     (callee : QualifiedName) (args : Array ReferenceValueV1)
  deriving BEq, Repr

structure OrderedEffectV1 where
  occurrence : EffectOccurrenceV1
  payload    : OrderedEffectPayloadV1
  deriving BEq, Repr

inductive StandardRevertCodeV1 where
  | arithmeticOverflow
  | arithmeticUnderflow
  | divisionByZero
  | invalidShift
  | castOutOfRange
  | indexOutOfBounds
  | boundExceeded
  | assertionFailed
  | uninitialized
  | alreadyInitialized
  deriving BEq, Repr, DecidableEq

inductive SemanticRevertV1 where
  | declared (errorId : ErrorIdV1) (args : Array ReferenceValueV1)
  | standard (code : StandardRevertCodeV1)
  | externalCallReverted (occurrence : EffectOccurrenceV1)
  deriving BEq, Repr

inductive SemanticFaultV1 where
  | invalidInvocation
  | invalidExternalResponse
  | invalidCore
  | resourceExhausted
  | unreachable
  | internalInvariant
  deriving BEq, Repr, DecidableEq

inductive OutcomeV1 where
  | returned
      (postState : LogicalStateV1)
      (value : Option ReferenceValueV1)
      (effects : Array OrderedEffectV1)
  | reverted (reason : SemanticRevertV1) (unchangedState : LogicalStateV1)
  | trapped (fault : SemanticFaultV1) (unchangedState : LogicalStateV1)
  deriving BEq, Repr

/-- Failure-state projection for the production outcome surface. Returned
    outcomes impose no claim; revert/trap must carry the exact supplied pre-state. -/
def OutcomeFailureStateUnchangedV1
    (pre : LogicalStateV1) (outcome : OutcomeV1) : Prop :=
  match outcome with
  | .returned _ _ _ => True
  | .reverted _ unchanged => unchanged = pre
  | .trapped _ unchanged => unchanged = pre

/-- ADR-0030 E2: minimal self-vault interpreter seed. `native` is the program's
    own native balance in base units at invocation start; `token` maps mint
    Principal canonical valueBytes to the program's own token balance. Inbound
    external transfers are not observable in this model — the seed is the sole
    source of truth at step start; within a step, deposit/transfer/transferAsync
    and the env-read family keep the vault coherent. -/
structure ReferenceVaultSeedV1 where
  native : UInt64 := 0
  token : Array (ByteArray × UInt64) := #[]
  deriving BEq, Repr

/-! ### Admission -/

inductive ReferenceAdmissionErrorV1 where
  | wire (error : SemanticWireErrorV1)
  | unsupported (detail : String)
  deriving BEq, Repr

/-- Opaque admitted slice: structure-validated carrier + decoded data. -/
structure AdmittedReferenceSliceV1 where
  private mk ::
    program : SemanticProgramV1
    data    : SemanticProgramDataV1

private def admitFail (detail : String) :
    Except ReferenceAdmissionErrorV1 α :=
  .error (.unsupported detail)

/- A Map is a self-bounded canonical envelope. Each Wire helper validates one
   complete value (including heterogeneous aggregate entries) under the shared
   `maxCanonicalValueBytes` / `maxCanonicalProgramBytes` budgets and
   `maxMapEntriesV1`; Reference admission therefore publishes those exact
   per-value ceilings instead of deriving a second entry capacity or sampling
   a few key/value packing profiles. This is not a whole-step cumulative-work
   receipt: helpers such as multi-pair Map Construct may start fresh budgets.
   Empty Map state defaults are accounted separately as the exact four-byte
   count header. -/
private def typeShapeAdmitted (shape : TypeShapeV1) :
    Except ReferenceAdmissionErrorV1 Unit :=
  match shape with
  | .bool => pure ()
  | .uint _ | .int _ => pure ()
  | .unit => pure ()
  | .bytes _ => pure ()
  | .field _ => pure ()
  | .array _ _ => pure ()
  | .map _ _ => pure ()
  | .option _ => pure ()
  | .struct _ => pure ()
  | .enum _ => pure ()
  | .principal => pure ()  -- N-2: identity-only Principal (context.caller / state)
  | .string => pure ()  -- N4: identity valueBytes; eq/ne via byte compare

/-- Family-level op admission. Unsupported ops never reach runtime (only
    internalInvariant defense remains if admission is bypassed). -/
private def opAdmitted (op : SemanticOpV1) : Except ReferenceAdmissionErrorV1 Unit :=
  match op with
  | .literal _ _ => pure ()
  | .constant _ => pure ()
  | .stateLoad _ => pure ()
  | .stateStore _ _ => pure ()
  | .checkedCast _ _ => pure ()
  | .unary _ _ => pure ()
  | .binary _ _ _ => pure ()
  | .assert_ _ _ _ => pure ()
  | .emit _ _ _ => pure ()
  | .externalCall _ _ _ => pure ()
  | .schedule _ _ _ => pure ()
  | .construct _ _ _ => pure ()
  | .fieldGet _ _ => pure ()
  | .fieldSet _ _ _ => pure ()
  | .variantTag _ => pure ()
  | .variantPayload _ _ _ => pure ()
  | .indexGet _ _ => pure ()
  | .indexSet _ _ _ => pure ()
  | .pureCall _ _ => pure ()
  | .contextRead _ => pure ()
  | .envRead _ _ => pure ()
  | .commit _ => pure ()

/-- ExternalCall/Schedule arg type shapes admitted for this slice (no Unit).
    R-1 / N-8: all legal UInt/Int widths (not only 8/32/64) plus Principal
    (N-8 Normalize call/schedule arg parity — opaque identity only; no
    address mapping). ADR-0029 A4 pf.assets transfer args use Principal. -/
private def externalArgShapeAdmitted (shape : TypeShapeV1) :
    Except ReferenceAdmissionErrorV1 Unit :=
  match shape with
  | .bool => pure ()
  | .uint w | .int w =>
      if w == 8 || w == 16 || w == 32 || w == 64 || w == 128 || w == 256 then
        pure ()
      else
        admitFail "unsupported ExternalCall/Schedule integer width"
  | .bytes _ => pure ()
  | .principal => pure ()
  | .unit =>
      admitFail "unsupported ExternalCall/Schedule Unit argument"
  | _ =>
      admitFail "unsupported ExternalCall/Schedule argument type"

/-- Local ValueId → TypeId from callable defs (params, block params, results). -/
private def callableValueTypeOf (c : CallableV1) (vid : ValueIdV1) : Option TypeIdV1 :=
  Id.run do
    for p in c.params do
      if p.valueId == vid then return some p.typeId
    for block in c.blocks do
      for bp in block.params do
        if bp.valueId == vid then return some bp.typeId
      for instr in block.instructions do
        match instr.result with
        | some vd => if vd.valueId == vid then return some vd.typeId
        | none => pure ()
    pure none

/-- Kind-scoped op restrictions + ExternalCall/Schedule arg serializability. -/
private def admitCallableBody (data : SemanticProgramDataV1) (c : CallableV1) :
    Except ReferenceAdmissionErrorV1 Unit := do
  for block in c.blocks do
    for instr in block.instructions do
      opAdmitted instr.op
      -- Map has exactly one constructor index (0); its args are a flattened
      -- key/value sequence, with the empty sequence representing Map.empty.
      match instr.op with
      | .construct tid _ _ =>
          match data.types[tid.toNat]? with
          | some { shape := .struct _, .. }
          | some { shape := .array _ _, .. }
          | some { shape := .unit, .. }
          | some { shape := .option _, .. }
          | some { shape := .enum _, .. } => pure ()
          | some { shape := .map _ _, .. } =>
              -- N-MAP-CONSTRUCT: ctor 0 with a flattened key/value pair
              -- sequence (even count; empty = Map.empty). Positional types
              -- are enforced by the structure gate; eval is upsert-fold.
              match instr.op with
              | .construct _ 0 args =>
                  if args.size % 2 == 0 then pure ()
                  else admitFail "Map Construct args must be flattened key/value pairs (even count)"
              | _ => admitFail "Map Construct admits only constructor 0"
          | some _ => admitFail "unsupported non-Struct/Array/Option/Enum Construct shape"
          | none => admitFail "Construct typeId out of range"
      | _ => pure ()
      -- view: no state write / effects (runtime has no view-snapshot model)
      match c.kind, instr.op with
      | .view, .stateStore _ _ =>
          admitFail "view unsupported stateStore"
      | .view, .emit _ _ _ =>
          admitFail "view unsupported Emit"
      | .view, .externalCall _ _ _ =>
          admitFail "view unsupported ExternalCall"
      | .view, .schedule _ _ _ =>
          admitFail "view unsupported Schedule"
      -- pureFn: no state / effects; pureFn-to-pureFn PureCall is admitted.
      | .pureFn, .stateLoad _ =>
          admitFail "pureFn unsupported StateLoad"
      | .pureFn, .stateStore _ _ =>
          admitFail "pureFn unsupported StateStore"
      | .pureFn, .emit _ _ _ =>
          admitFail "pureFn unsupported Emit"
      | .pureFn, .externalCall _ _ _ =>
          admitFail "pureFn unsupported ExternalCall"
      | .pureFn, .schedule _ _ _ =>
          admitFail "pureFn unsupported Schedule"
      | _, _ => pure ()
      -- PureCall: callee must be a declared pureFn with matching arity (the
      -- structure gate already checks kinds/types; this is defense in depth).
      match instr.op with
      | .pureCall calleeId args =>
          match data.callables[calleeId.toNat]? with
          | none => admitFail "PureCall callee out of range after structure gate"
          | some callee =>
              if callee.kind != .pureFn then
                admitFail "PureCall callee is not a pure function"
              else if args.size != callee.params.size then
                admitFail "PureCall argument count mismatch"
              else pure ()
      | _ => pure ()
      -- ExternalCall/Schedule args: only Bool/UInt8/32/64/Bytes (reject Unit)
      match instr.op with
      | .externalCall _ _ args | .schedule _ _ args =>
          for argVid in args do
            match callableValueTypeOf c argVid with
            | none =>
                admitFail
                  "ExternalCall/Schedule arg ValueId has no local type def"
            | some tid =>
                match data.types[tid.toNat]? with
                | none =>
                    admitFail "ExternalCall/Schedule arg typeId out of range"
                | some decl => externalArgShapeAdmitted decl.shape
      | _ => pure ()

private def admitTypes (types : Array TypeDeclV1) :
    Except ReferenceAdmissionErrorV1 Unit := do
  for t in types do
    typeShapeAdmitted t.shape

/-- Bound each admitted type under canonical byte, recursive-shape, and
    per-value Wire work envelopes. This explicit-stack postorder walk avoids
    host recursion and allocation amplification from compact Struct DAG
    declarations. It does not certify one cumulative budget for an entire
    Reference step; runtime helpers may independently restart Wire work budgets.
    Wire has already rejected Struct-only cycles; unresolved rows still fail
    closed rather than relying on that premise. -/
private def admitTypeResourceBoundsFallback (types : Array TypeDeclV1) :
    Except ReferenceAdmissionErrorV1 (Array Nat × Array Nat) := do
  let n := types.size
  let mut color : Array Nat := Array.replicate n 0
  let mut widths : Array Nat := Array.replicate n 0
  let mut depths : Array Nat := Array.replicate n 0
  let mut works : Array Nat := Array.replicate n 0
  let mut stack : Array (Nat × Nat) := #[]
  let mut root := 0
  while root < n do
    if color[root]! == 0 then
      stack := stack.push (0, root)
      while !stack.isEmpty do
        let (kind, tid) := stack.back!
        stack := stack.pop
        if kind == 1 then
          match types[tid]? with
          | some decl =>
              let alternatives : Array (Array TypeIdV1) :=
                match decl.shape with
                | .struct fields => #[fields.map (·.typeId)]
                | .array element _ =>
                    -- Array is handled arithmetically below; never expand length.
                    #[#[element]]
                | .map key value => #[#[key, value]]
                | .option element => #[#[], #[element]]
                | .enum variants => variants.map (·.payloadTypes)
                | _ => #[]
              unless !alternatives.isEmpty do
                return ← admitFail "aggregate resource bounds could not be resolved"
              let mut total := 0
              let mut childDepth := 0
              let mut totalWork := 0
              match decl.shape with
              | .map _ _ =>
                  -- A Map owns one per-canonical-value Wire envelope regardless
                  -- of how heterogeneous its entries are. Resolve children only
                  -- for acyclicity/depth; do not multiply maxMapEntriesV1 by
                  -- child maxima or sample selected entry profiles. This bound
                  -- intentionally says nothing about cumulative whole-step work.
                  for children in alternatives do
                    for childId in children do
                      let child := childId.toNat
                      unless child < n && color[child]! == 2 do
                        return ← admitFail
                          "aggregate resource bounds could not be resolved"
                      childDepth := max childDepth depths[child]!
                  total := maxCanonicalValueBytes
                  totalWork := maxCanonicalProgramBytes
              | _ =>
                let headerWidth := match decl.shape with
                  | .struct _ | .array _ _ => 0
                  | .option _ => 1
                  | _ => 4
                for children in alternatives do
                  let mut altWidth := headerWidth
                  -- Match Wire's cumulative decoder: one node-entry unit,
                  -- every child occurrence, then this node's canonical output.
                  let mut altWork := 1
                  let mut directChildWork := 0
                  for childId in children do
                    let child := childId.toNat
                    unless child < n && color[child]! == 2 do
                      return ← admitFail "aggregate resource bounds could not be resolved"
                    let width := widths[child]!
                    let count := match decl.shape with
                      | .array _ length => length.toNat
                      | _ => 1
                    unless count == 0 || width ≤ maxCanonicalValueBytes / count do
                      return ← admitFail "aggregate canonical value exceeds byte limit"
                    let addedWidth := count * width
                    unless addedWidth ≤ maxCanonicalValueBytes - altWidth do
                      return ← admitFail "aggregate canonical value exceeds byte limit"
                    altWidth := altWidth + addedWidth
                    childDepth := max childDepth depths[child]!
                    let work := works[child]!
                    unless work ≤ maxCanonicalProgramBytes - directChildWork do
                      return ← admitFail "aggregate canonical construction work exceeds limit"
                    directChildWork := directChildWork + work
                    -- Every occurrence is charged, including zero-width values.
                    unless count == 0 || work ≤ maxCanonicalProgramBytes / count do
                      return ← admitFail "aggregate canonical construction work exceeds limit"
                    let addedWork := count * work
                    unless addedWork ≤ maxCanonicalProgramBytes - altWork do
                      return ← admitFail "aggregate canonical construction work exceeds limit"
                    altWork := altWork + addedWork
                  let ownWork := max 1 altWidth
                  unless ownWork ≤ maxCanonicalProgramBytes - altWork do
                    return ← admitFail "aggregate canonical construction work exceeds limit"
                  altWork := altWork + ownWork
                  total := max total altWidth
                  totalWork := max totalWork altWork
              let depth := childDepth + 1
              unless depth ≤ maxNesting do
                return ← admitFail "aggregate canonical value exceeds nesting limit"
              widths := widths.set! tid total
              depths := depths.set! tid depth
              works := works.set! tid totalWork
              color := color.set! tid 2
          | _ => return ← admitFail "aggregate resource bounds could not be resolved"
        else
          match color[tid]! with
          | 2 => pure ()
          | 1 =>
              return ← admitFail
                "recursive Struct/Array/Map/Option/Enum resource bounds unsupported"
          | _ =>
              match types[tid]? with
              | some { shape := .bool, .. } =>
                  widths := widths.set! tid 1
                  depths := depths.set! tid 1
                  works := works.set! tid 2
                  color := color.set! tid 2
              | some { shape := .uint width, .. }
              | some { shape := .int width, .. } =>
                  let bytes := width.toNat / 8
                  widths := widths.set! tid bytes
                  depths := depths.set! tid 1
                  works := works.set! tid (1 + max 1 bytes)
                  color := color.set! tid 2
              | some { shape := .field spec, .. } =>
                  let bytes := spec.modulusBE.size
                  widths := widths.set! tid bytes
                  depths := depths.set! tid 1
                  works := works.set! tid (1 + max 1 bytes)
                  color := color.set! tid 2
              | some { shape := .unit, .. } =>
                  depths := depths.set! tid 1
                  works := works.set! tid 2
                  color := color.set! tid 2
              | some { shape := .bytes length, .. } =>
                  widths := widths.set! tid length.toNat
                  depths := depths.set! tid 1
                  works := works.set! tid (1 + max 1 length.toNat)
                  color := color.set! tid 2
              | some { shape := .principal, .. }
              | some { shape := .string, .. } =>
                  -- Length-prefixed identity payload: u32le(len) || body,
                  -- body ≤ maxTypeLengthV1 (Wire valueBytes gate).
                  let bytes := 4 + maxTypeLengthV1
                  widths := widths.set! tid bytes
                  depths := depths.set! tid 1
                  works := works.set! tid (1 + max 1 bytes)
                  color := color.set! tid 2
              | some { shape := .struct fields, .. } =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  let mut i := fields.size
                  while i > 0 do
                    i := i - 1
                    match fields[i]? with
                    | some field => stack := stack.push (0, field.typeId.toNat)
                    | none =>
                        return ← admitFail
                          "Struct resource bounds could not be resolved"
              | some { shape := .array element _, .. } =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  stack := stack.push (0, element.toNat)
              | some { shape := .map key value, .. } =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  stack := stack.push (0, value.toNat)
                  stack := stack.push (0, key.toNat)
              | some { shape := .option element, .. } =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  stack := stack.push (0, element.toNat)
              | some { shape := .enum variants, .. } =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  let mut vi := variants.size
                  while vi > 0 do
                    vi := vi - 1
                    match variants[vi]? with
                    | none => return ← admitFail "Enum resource bounds could not be resolved"
                    | some variant =>
                        let mut pi := variant.payloadTypes.size
                        while pi > 0 do
                          pi := pi - 1
                          match variant.payloadTypes[pi]? with
                          | some child => stack := stack.push (0, child.toNat)
                          | none => return ← admitFail "Enum resource bounds could not be resolved"
              | _ => return ← admitFail "aggregate resource bounds unsupported type"
    root := root + 1
  pure (widths, works)

/-- Closed primitive-leaf resource calculation. Aggregate shapes return `none`
    and continue through the existing explicit-stack fallback. This branch is
    definitionally transparent for kernel certificates while preserving the
    fallback as the sole aggregate authority. -/
private def primitiveTypeResourceBoundV1 (shape : TypeShapeV1) :
    Option (Nat × Nat) :=
  match shape with
  | .bool => some (1, 2)
  | .uint width | .int width =>
      let byteWidth := width.toNat / 8
      some (byteWidth, 1 + max 1 byteWidth)
  | .field spec =>
      let byteWidth := spec.modulusBE.size
      some (byteWidth, 1 + max 1 byteWidth)
  | .unit => some (0, 2)
  | .bytes length =>
      let byteWidth := length.toNat
      some (byteWidth, 1 + max 1 byteWidth)
  | .principal | .string =>
      let byteWidth := 4 + maxTypeLengthV1
      some (byteWidth, 1 + max 1 byteWidth)
  | .array _ _ | .map _ _ | .option _ | .struct _ | .enum _ => none

private def primitiveTypeResourceBoundsListV1 :
    List TypeDeclV1 → Option (List Nat × List Nat)
  | [] => some ([], [])
  | decl :: rest => do
      let (width, work) ← primitiveTypeResourceBoundV1 decl.shape
      let (widths, works) ← primitiveTypeResourceBoundsListV1 rest
      pure (width :: widths, work :: works)

private def admitTypeResourceBounds (types : Array TypeDeclV1) :
    Except ReferenceAdmissionErrorV1 (Array Nat × Array Nat) :=
  match primitiveTypeResourceBoundsListV1 types.toList with
  | some (widths, works) => .ok (widths.toArray, works.toArray)
  | none => admitTypeResourceBoundsFallback types

/-- Data-only half of Reference admission. This is the exact check called by
    `admitReferenceProgramSliceV1`; it does not mint the private admitted
    capability and therefore cannot bypass carrier validation. Exposing the
    check result lets kernel proofs compose a positive admission witness without
    duplicating the admission scan or constructing `AdmittedReferenceSliceV1`. -/
def validateReferenceProgramDataAdmissionV1 (data : SemanticProgramDataV1) :
    Except ReferenceAdmissionErrorV1 Unit := do
  admitTypes data.types
  let (typeWidths, typeWorks) ← admitTypeResourceBounds data.types
  -- `initialLogicalStateV1` materializes every default plus its u32 length
  -- prefix. Bound that aggregate before any invocation can allocate it.
  -- R-1: Map *defaults* are empty (`u32le(0)` = 4 bytes). Parent-facing Map
  -- width/work is the complete Wire value/work ceiling, but empty Map state
  -- defaults stay 4-byte / O(1) so empty Map state remains admissible.
  let mut stateBytes := 0
  let mut stateWork := 0
  for state in data.logicalState do
    match typeWidths[state.typeId.toNat]?, typeWorks[state.typeId.toNat]?,
          data.types[state.typeId.toNat]? with
    | some width, some typeWork, some decl =>
        let (defWidth, defWork) :=
          match decl.shape with
          | .map _ _ =>
              -- Empty Map default: 4-byte count header; construction work is
              -- O(1) relative to the worst-case filled-map budget.
              (4, 6)
          | _ => (width, typeWork)
        let slotWidth := defWidth + 4
        unless slotWidth ≤ maxCanonicalProgramBytes - stateBytes do
          return ← admitFail "logical state defaults exceed aggregate byte limit"
        -- Default construction, recursive canonical validation, slot-prefix
        -- append, and append into the growing aggregate all contribute to
        -- host work.
        let appendWork := stateBytes + slotWidth
        unless defWork ≤ maxCanonicalProgramBytes - stateWork do
          return ← admitFail "logical state defaults exceed aggregate work limit"
        stateWork := stateWork + defWork
        unless defWork ≤ maxCanonicalProgramBytes - stateWork do
          return ← admitFail "logical state defaults exceed aggregate work limit"
        stateWork := stateWork + defWork
        unless slotWidth ≤ maxCanonicalProgramBytes - stateWork do
          return ← admitFail "logical state defaults exceed aggregate work limit"
        stateWork := stateWork + slotWidth
        unless appendWork ≤ maxCanonicalProgramBytes - stateWork do
          return ← admitFail "logical state defaults exceed aggregate work limit"
        stateWork := stateWork + appendWork
        stateBytes := stateBytes + slotWidth
    | _, _, _ =>
        return ← admitFail "logical state type resource bounds missing"
  for c in data.constants do
    match data.types[c.typeId.toNat]? with
    | none => admitFail "constant typeId out of range after structure gate"
    | some decl => typeShapeAdmitted decl.shape
  for s in data.logicalState do
    match data.types[s.typeId.toNat]? with
    | none => admitFail "state typeId out of range after structure gate"
    | some decl => typeShapeAdmitted decl.shape
  for c in data.callables do
    admitCallableBody data c
  pure ()

/-- Executable success projection of the sole data-only admission check. This
    does not reimplement admission; it only erases the closed error detail for
    kernel-decidable proof composition. -/
def referenceProgramDataAdmissionOkV1 (data : SemanticProgramDataV1) : Bool :=
  match validateReferenceProgramDataAdmissionV1 data with
  | .ok () => true
  | .error _ => false

/-- Recover the exact successful admission check from its executable success
    projection. -/
theorem validateReferenceProgramDataAdmissionV1_eq_ok_of_bool
    (data : SemanticProgramDataV1)
    (hok : referenceProgramDataAdmissionOkV1 data = true) :
    validateReferenceProgramDataAdmissionV1 data = .ok () := by
  unfold referenceProgramDataAdmissionOkV1 at hok
  generalize hcheck : validateReferenceProgramDataAdmissionV1 data = check at hok ⊢
  cases check with
  | error error => contradiction
  | ok value => cases value; rfl

/-- Whole-program admission: structure gate, exact data-only admission check,
    then the sole private capability mint. -/
def admitReferenceProgramSliceV1 (program : SemanticProgramV1) :
    Except ReferenceAdmissionErrorV1 AdmittedReferenceSliceV1 := do
  let data ←
    match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error e => .error (.wire e)
  validateReferenceProgramDataAdmissionV1 data
  pure ⟨program, data⟩

/-- Exact positive admission from sole production validation and the data-only
    admission check. The private constructor remains confined to this module. -/
theorem admitReferenceProgramSliceV1_eq_ok_of_checks
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hcheck : validateReferenceProgramDataAdmissionV1 data = .ok ()) :
    admitReferenceProgramSliceV1 program = .ok ⟨program, data⟩ := by
  simp only [admitReferenceProgramSliceV1, hvalidate, hcheck, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

/-- Compose a positive admission existential from the sole production carrier
    validation and the exact data-only admission check. -/
theorem admitReferenceProgramSliceV1_exists_of_checks
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hcheck : validateReferenceProgramDataAdmissionV1 data = .ok ()) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 program = .ok admitted :=
  ⟨⟨program, data⟩,
    admitReferenceProgramSliceV1_eq_ok_of_checks program data hvalidate hcheck⟩

/-- Admitted program projection equals the validated input carrier. -/
theorem AdmittedReferenceSliceV1.program_eq
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1) :
    (⟨program, data⟩ : AdmittedReferenceSliceV1).program = program :=
  rfl

/-- Admitted data projection equals the validated decoded table. -/
theorem AdmittedReferenceSliceV1.data_eq
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1) :
    (⟨program, data⟩ : AdmittedReferenceSliceV1).data = data :=
  rfl

/-- Successful whole-program admission recovers the validated carrier identity. -/
theorem admitReferenceProgramSliceV1_ok_implies
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (admitted : AdmittedReferenceSliceV1)
    (hvalidate : validateSemanticProgramV1 program = .ok data)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    admitted.program = program ∧ admitted.data = data := by
  unfold admitReferenceProgramSliceV1 at hadmit
  rw [hvalidate] at hadmit
  simp only [Bind.bind, Pure.pure, Except.bind, Except.pure] at hadmit
  generalize hcheck : validateReferenceProgramDataAdmissionV1 data = check at hadmit
  cases check with
  | error error =>
      -- hadmit : error _ = ok admitted
      exact False.elim (nomatch hadmit)
  | ok unit =>
      cases unit
      -- hadmit : ok ⟨program, data⟩ = ok admitted
      cases hadmit
      constructor <;> rfl

/-- Successful admission alone recovers both the exact program projection and
    the production validation equality for the admitted data projection. This
    is the proof-facing inversion used when callers retain only the positive
    admission equality rather than a separate decoded-data witness. -/
theorem admitReferenceProgramSliceV1_ok_implies_validate
    (program : SemanticProgramV1)
    (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted) :
    admitted.program = program ∧
      validateSemanticProgramV1 program = .ok admitted.data := by
  cases hvalidate : validateSemanticProgramV1 program with
  | error error =>
      unfold admitReferenceProgramSliceV1 at hadmit
      rw [hvalidate] at hadmit
      simp only [Bind.bind, Pure.pure, Except.bind, Except.pure] at hadmit
      exact False.elim (nomatch hadmit)
  | ok data =>
      have hidentity :=
        admitReferenceProgramSliceV1_ok_implies
          program data admitted hvalidate hadmit
      refine ⟨hidentity.1, ?_⟩
      rw [hidentity.2]

/-! ### Internal value helpers -/

/-- Little-endian unsigned decode. List recursion is definitionally transparent
    for closed byte vectors while remaining the same place-value algorithm. -/
private def leBytesToNatList (bytes : List UInt8) (place : Nat := 1) : Nat :=
  match bytes with
  | [] => 0
  | b :: rest => b.toNat * place + leBytesToNatList rest (place * 256)

private def leBytesToNat (bytes : ByteArray) : Nat :=
  leBytesToNatList bytes.data.toList

/-- Public little-endian unsigned decode — exact same algorithm as the private
    machine helper. Exported so instance proofs can state parity premises without
    re-implementing place-value decoding. -/
def leBytesToNatV1 (bytes : ByteArray) : Nat :=
  leBytesToNat bytes

/-- Little-endian unsigned encode of exact length `len`. -/
private def natToLeBytesList (n len : Nat) : List UInt8 :=
  match len with
  | 0 => []
  | len + 1 =>
      UInt8.ofNat (n % 256) :: natToLeBytesList (n / 256) len

private def natToLeBytes (n : Nat) (len : Nat) : ByteArray :=
  ByteArray.mk (natToLeBytesList n len).toArray

/-- Public little-endian unsigned encode of exact length — same algorithm as the
    private machine helper. -/
def natToLeBytesV1 (n : Nat) (len : Nat) : ByteArray :=
  natToLeBytes n len

private theorem natToLeBytesList_length (n len : Nat) :
    (natToLeBytesList n len).length = len := by
  induction len generalizing n with
  | zero => rfl
  | succ len ih =>
      simp [natToLeBytesList, ih]

/-- Encoded little-endian payload has exact requested width. -/
theorem natToLeBytesV1_size (n len : Nat) :
    (natToLeBytesV1 n len).size = len := by
  simp [natToLeBytesV1, natToLeBytes, ByteArray.size, natToLeBytesList_length]

private def bytesEqual (a b : ByteArray) : Bool := a == b

private def shapeOf (data : SemanticProgramDataV1) (tid : TypeIdV1) :
    Option TypeShapeV1 :=
  match data.types[tid.toNat]? with
  | some d => some d.shape
  | none => none

private def isUnitType (data : SemanticProgramDataV1) (tid : TypeIdV1) : Bool :=
  match shapeOf data tid with
  | some .unit => true
  | _ => false

private def isBoolType (data : SemanticProgramDataV1) (tid : TypeIdV1) : Bool :=
  match shapeOf data tid with
  | some .bool => true
  | _ => false

private def uintWidth (data : SemanticProgramDataV1) (tid : TypeIdV1) : Option Nat :=
  match shapeOf data tid with
  | some (.uint w) => some w.toNat
  | _ => none

private def intWidth (data : SemanticProgramDataV1) (tid : TypeIdV1) : Option Nat :=
  match shapeOf data tid with
  | some (.int w) => some w.toNat
  | _ => none

private def beBytesToNat (bytes : ByteArray) : Nat := Id.run do
  let mut value := 0
  for byte in bytes do
    value := value * 256 + byte.toNat
  pure value

private def fieldModulus (data : SemanticProgramDataV1) (tid : TypeIdV1) : Option Nat :=
  match shapeOf data tid with
  | some (.field spec) => some (beBytesToNat spec.modulusBE)
  | _ => none

private def uintByteLen (width : Nat) : Nat := width / 8

private def uintMax (width : Nat) : Nat := Nat.pow 2 width

private def leBytesToInt (bytes : ByteArray) (width : Nat) : Int :=
  let bits := leBytesToNat bytes
  let signBoundary := Nat.pow 2 (width - 1)
  if bits < signBoundary then
    Int.ofNat bits
  else
    Int.ofNat bits - Int.ofNat (uintMax width)

private def intMin (width : Nat) : Int :=
  -(Int.ofNat (Nat.pow 2 (width - 1)))

private def intMax (width : Nat) : Int :=
  Int.ofNat (Nat.pow 2 (width - 1)) - 1

private def intInRange (value : Int) (width : Nat) : Bool :=
  intMin width ≤ value && value ≤ intMax width

private def intToLeBytes (value : Int) (width : Nat) : ByteArray :=
  let bits :=
    if value < 0 then
      (value + Int.ofNat (uintMax width)).toNat
    else
      value.toNat
  natToLeBytes bits (uintByteLen width)

private def fieldPow (base exponent modulus : Nat) : Nat := Id.run do
  let mut result := 1
  let mut factor := base % modulus
  let mut remaining := exponent
  -- The sole v1 field is 254-bit; use a fixed bound rather than host bigint
  -- inversion so execution remains deterministic and total.
  for _ in [:256] do
    if remaining % 2 == 1 then
      result := (result * factor) % modulus
    factor := (factor * factor) % modulus
    remaining := remaining / 2
  pure result

private def valueCanonical (data : SemanticProgramDataV1) (v : ReferenceValueV1) : Bool :=
  match validateValueBytesV1 data.types v.typeId v.valueBytes with
  | .ok _ => true
  | .error _ => false

private theorem valueCanonical_eq_true_iff
    (data : SemanticProgramDataV1)
    (value : ReferenceValueV1) :
    valueCanonical data value = true ↔
      validateValueBytesV1 data.types value.typeId value.valueBytes = .ok () := by
  unfold valueCanonical
  cases hvalidate :
      validateValueBytesV1 data.types value.typeId value.valueBytes with
  | error error => simp
  | ok unit =>
      cases unit
      simp

/-- A Reference return value matches one exact callable result row. Unit uses
    the canonical `none` carrier; every other result carries the exact lowered
    TypeId and bytes accepted by the production value validator. This is a
    proof predicate over the production carrier, not another result codec. -/
def ReferenceResultConformsV1
    (data : SemanticProgramDataV1)
    (result : CallableResultV1)
    (value : Option ReferenceValueV1) : Prop :=
  let resultIsUnit :=
    match data.types[result.typeId.toNat]? with
    | some { shape := .unit, .. } => true
    | _ => false
  match value with
  | none => resultIsUnit = true
  | some returned =>
      resultIsUnit = false ∧
        returned.typeId = result.typeId ∧
        validateValueBytesV1 data.types returned.typeId returned.valueBytes = .ok ()

private theorem referenceResultConformsV1_none_iff
    (data : SemanticProgramDataV1)
    (result : CallableResultV1) :
    ReferenceResultConformsV1 data result none ↔
      isUnitType data result.typeId = true := by
  unfold ReferenceResultConformsV1 isUnitType shapeOf
  cases htype : data.types[result.typeId.toNat]? with
  | none => simp
  | some typeDecl =>
      cases typeDecl with
      | mk id name shape =>
          cases shape <;> simp

private theorem referenceResultConformsV1_some_iff
    (data : SemanticProgramDataV1)
    (result : CallableResultV1)
    (value : ReferenceValueV1) :
    ReferenceResultConformsV1 data result (some value) ↔
      isUnitType data result.typeId = false ∧
        value.typeId = result.typeId ∧ valueCanonical data value = true := by
  unfold ReferenceResultConformsV1 isUnitType shapeOf
  cases hresult : data.types[result.typeId.toNat]? with
  | none => simp [valueCanonical_eq_true_iff]
  | some typeDecl =>
      cases typeDecl with
      | mk id name shape =>
          cases shape <;> simp [valueCanonical_eq_true_iff]

/-! ### Machine -/

/-- Suspended caller state while a pure-fn callee runs. The callee cannot
    touch state/effects, so only the frame-local fields need saving. -/
private structure CallFrameV1 where
  callable : CallableV1
  env : Array (Option ReferenceValueV1)
  loopCounts : Array UInt32
  blockId : BlockIdV1
  instrIdx : Nat
  resultValueId : ValueIdV1

/-- Body interpreter machine state (engineering; not formal State). -/
structure MachineV1 where
  data           : SemanticProgramDataV1
  pre            : LogicalStateV1
  callable       : CallableV1
  isInitializer  : Bool
  context        : Array ContextInputV1
  overlay        : Array ByteArray
  env            : Array (Option ReferenceValueV1)
  effects        : Array OrderedEffectV1
  occCounts      : Array UInt32
  responseCursor : Nat
  responses      : ExternalResponsesV1
  loopCounts     : Array UInt32
  blockId        : BlockIdV1
  instrIdx       : Nat
  frames         : Array CallFrameV1
  /-- ADR-0030 E2: self-vault native balance (base units). -/
  vaultNative    : UInt64
  /-- ADR-0030 E2: self-vault token balances, keyed by mint Principal
      canonical valueBytes; absent key reads as zero. -/
  vaultToken     : Array (ByteArray × UInt64)

/-- Result row of the outermost callable. A suspended pure-call stack stores
    the outermost caller in its first frame; an empty stack uses the active
    callable. This projection is proof-only and does not affect execution. -/
private def rootCallableResultV1 (m : MachineV1) : CallableResultV1 :=
  match m.frames[0]? with
  | some frame => frame.callable.result
  | none => m.callable.result

private theorem rootCallableResultV1_enterPureCall
    (m : MachineV1)
    (callee : CallableV1)
    (calleeEnv : Array (Option ReferenceValueV1))
    (frame : CallFrameV1)
    (hcaller : frame.callable = m.callable) :
    rootCallableResultV1 {
      m with
      callable := callee
      env := calleeEnv
      loopCounts := Array.replicate callee.loopBounds.size (0 : UInt32)
      blockId := callee.entryBlock
      instrIdx := 0
      frames := m.frames.push frame
    } = rootCallableResultV1 m := by
  unfold rootCallableResultV1
  rw [Array.getElem?_push]
  by_cases hempty : m.frames.size = 0
  · have hframes : m.frames = #[] := Array.size_eq_zero_iff.mp hempty
    rw [hframes]
    simp [hcaller]
  · have hnonzero : 0 ≠ m.frames.size := Ne.symm hempty
    have hfirst := Array.getElem?_eq_getElem (Nat.pos_of_ne_zero hempty)
    simp [hnonzero, hfirst]

private theorem rootCallableResultV1_leavePureCall
    (m : MachineV1)
    (frame : CallFrameV1)
    (env : Array (Option ReferenceValueV1))
    (hback : m.frames.back? = some frame) :
    rootCallableResultV1 {
      m with
      callable := frame.callable
      env
      loopCounts := frame.loopCounts
      blockId := frame.blockId
      instrIdx := frame.instrIdx
      frames := m.frames.pop
    } = rootCallableResultV1 m := by
  obtain ⟨frames, hframes⟩ := Array.back?_eq_some_iff.mp hback
  unfold rootCallableResultV1
  rw [hframes, Array.pop_push, Array.getElem?_push]
  by_cases hempty : frames.size = 0
  · have hframes : frames = #[] := Array.size_eq_zero_iff.mp hempty
    rw [hframes]
    rfl
  · have hnonzero : 0 ≠ frames.size := Ne.symm hempty
    have hfirst := Array.getElem?_eq_getElem (Nat.pos_of_ne_zero hempty)
    simp [hnonzero, hfirst]

private theorem rootCallableResultV1_eq_of_callStack_eq
    (before after : MachineV1)
    (hcallable : after.callable = before.callable)
    (hframes : after.frames = before.frames) :
    rootCallableResultV1 after = rootCallableResultV1 before := by
  unfold rootCallableResultV1
  rw [hframes, hcallable]

/-- Body halt candidate before `finalize` reattaches pre on failure. -/
inductive CandidateV1 where
  | returned (value : Option ReferenceValueV1)
  | reverted (reason : SemanticRevertV1)
  | trapped (fault : SemanticFaultV1)

/-- Private instruction-local failure channel. Evaluators and vault helpers
    can only revert or trap; successful contract return remains exclusive to a
    terminator. Conversion at the execution boundary preserves the existing
    `CandidateV1` surface and observable machine semantics. -/
private inductive LocalFailureV1 where
  | reverted (reason : SemanticRevertV1)
  | trapped (fault : SemanticFaultV1)

private def LocalFailureV1.toCandidateV1 : LocalFailureV1 → CandidateV1
  | .reverted reason => .reverted reason
  | .trapped fault => .trapped fault

/-- Instruction/terminator local result: continue machine or halt with candidate. -/
private inductive ExecResult where
  | next (m : MachineV1)
  | done (m : MachineV1) (cand : CandidateV1)

/-- Proof-only projection invariant for machine-local execution results. -/
private def ExecResultPreservesDataV1
    (data : SemanticProgramDataV1) : ExecResult → Prop
  | .next m => m.data = data
  | .done m _ => m.data = data

/-- Instruction-local execution preserves the active callable/call stack while
    it continues and cannot manufacture a successful contract return. -/
private def ExecResultPreservesCallStackFailureV1
    (callable : CallableV1)
    (frames : Array CallFrameV1) : ExecResult → Prop
  | .next after =>
      after.callable = callable ∧ after.frames = frames
  | .done _ (.returned _) => False
  | .done _ (.reverted _) => True
  | .done _ (.trapped _) => True

private def ExecTerminatorContractV1
    (m : MachineV1) : ExecResult → Prop
  | .next after =>
      after.callable = m.callable ∧ after.frames = m.frames
  | .done _ (.returned value) =>
      ReferenceResultConformsV1 m.data m.callable.result value
  | .done _ (.reverted _) => True
  | .done _ (.trapped _) => True

private def CandidateResultConformsV1
    (data : SemanticProgramDataV1)
    (result : CallableResultV1) : CandidateV1 → Prop
  | .returned value => ReferenceResultConformsV1 data result value
  | .reverted _ => True
  | .trapped _ => True

private theorem candidateResultConformsV1_congr
    {data₁ data₂ : SemanticProgramDataV1}
    {result₁ result₂ : CallableResultV1}
    {candidate : CandidateV1}
    (hdata : data₁ = data₂)
    (hresult : result₁ = result₂)
    (hconforms : CandidateResultConformsV1 data₁ result₁ candidate) :
    CandidateResultConformsV1 data₂ result₂ candidate := by
  subst data₂
  subst result₂
  exact hconforms

/-- Proof-only projection invariant for helpers which may return a machine. -/
private def ExceptMachinePreservesDataV1
    (data : SemanticProgramDataV1) : Except LocalFailureV1 MachineV1 → Prop
  | .error _ => True
  | .ok m => m.data = data

private def ExceptMachinePreservesCallStackV1
    (callable : CallableV1)
    (frames : Array CallFrameV1) : Except LocalFailureV1 MachineV1 → Prop
  | .error _ => True
  | .ok after =>
      after.callable = callable ∧ after.frames = frames

def maxValueIdInCallable (c : CallableV1) : Nat := Id.run do
  let mut m : Nat := 0
  for p in c.params do
    if p.valueId.toNat > m then m := p.valueId.toNat
  for block in c.blocks do
    for bp in block.params do
      if bp.valueId.toNat > m then m := bp.valueId.toNat
    for instr in block.instructions do
      match instr.result with
      | some vd => if vd.valueId.toNat > m then m := vd.valueId.toNat
      | none => pure ()
  pure m

def maxEffectIdInCallable (c : CallableV1) : Nat := Id.run do
  let mut m : Nat := 0
  let mut found : Bool := false
  for block in c.blocks do
    for instr in block.instructions do
      match instr.op with
      | .emit eid _ _ | .externalCall eid _ _ | .schedule eid _ _ =>
          found := true
          if eid.toNat > m then m := eid.toNat
      | _ => pure ()
  if found then pure m else pure 0

def emptyEnv (size : Nat) : Array (Option ReferenceValueV1) :=
  Array.replicate size none

private def envGet (env : Array (Option ReferenceValueV1)) (vid : ValueIdV1) :
    Option ReferenceValueV1 :=
  match env[vid.toNat]? with
  | some (some v) => some v
  | _ => none

private def envSet (env : Array (Option ReferenceValueV1)) (vid : ValueIdV1)
    (v : ReferenceValueV1) : Option (Array (Option ReferenceValueV1)) :=
  let i := vid.toNat
  if h : i < env.size then
    some (env.set i (some v))
  else
    none

private def lookupArgs (env : Array (Option ReferenceValueV1))
    (ids : Array ValueIdV1) : Option (Array ReferenceValueV1) := Id.run do
  let mut out : Array ReferenceValueV1 := Array.emptyWithCapacity ids.size
  for id in ids do
    match envGet env id with
    | none => return none
    | some v => out := out.push v
  pure (some out)

private def arraySetU32 (a : Array UInt32) (i : Nat) (v : UInt32) :
    Option (Array UInt32) :=
  if h : i < a.size then some (a.set i v) else none

private def nextOccurrence (m : MachineV1) (effectId : EffectIdV1) :
    Option (MachineV1 × EffectOccurrenceV1) :=
  let i := effectId.toNat
  match m.occCounts[i]? with
  | none => none
  | some cur =>
      if cur == UInt32.ofNat (UInt32.size - 1) then
        none
      else
        let occ : EffectOccurrenceV1 := { effectId, occurrence := cur }
        match arraySetU32 m.occCounts i (cur + 1) with
        | none => none
        | some counts => some ({ m with occCounts := counts }, occ)

private def findLoopBoundIdx (c : CallableV1) (header backFrom : BlockIdV1) :
    Option Nat := Id.run do
  let mut i : Nat := 0
  for lb in c.loopBounds do
    if lb.header == header && lb.backEdgeFrom == backFrom then
      return some i
    i := i + 1
  pure none

private def noteBackEdge (m : MachineV1) (fromBlock toBlock : BlockIdV1) :
    ExecResult :=
  match findLoopBoundIdx m.callable toBlock fromBlock with
  | none => .next m
  | some idx =>
      match m.loopCounts[idx]?, m.callable.loopBounds[idx]? with
      | some count, some lb =>
          if count >= lb.maxIterations then
            .done m (.reverted (.standard .boundExceeded))
          else
            match arraySetU32 m.loopCounts idx (count + 1) with
            | none => .done m (.trapped .internalInvariant)
            | some counts => .next { m with loopCounts := counts }
      | _, _ => .done m (.trapped .internalInvariant)

/-- Terminal outcome packaging. Failure paths always reattach the exact
    invocation `pre` (not a derived machine field), matching the Reference
    rollback contract: trap/revert leave business state unchanged. Public for
    L1 preservation step packing. -/
def finalize (m : MachineV1) (cand : CandidateV1)
    (pre : LogicalStateV1) : OutcomeV1 :=
  if m.responseCursor != m.responses.size then
    .trapped .invalidExternalResponse pre
  else
    match cand with
    | .trapped fault => .trapped fault pre
    | .reverted reason => .reverted reason pre
    | .returned value =>
        let postInit := pre.initialized || m.isInitializer
        match encodeLogicalStateValuesV1 m.data postInit m.overlay with
        | .ok post => .returned post value m.effects
        | .error _ => .trapped .internalInvariant pre

/-! ### Primitive evaluation -/

private def evalUnary (data : SemanticProgramDataV1) (op : UnaryOpV1)
    (operand : ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 :=
  match op with
  | .not =>
      if !(isBoolType data operand.typeId && isBoolType data resultTypeId) then
        .error (.trapped .invalidCore)
      else
        match byteAt? operand.valueBytes 0 with
        | some 0 => .ok { typeId := resultTypeId, valueBytes := encodeU8 1 }
        | some 1 => .ok { typeId := resultTypeId, valueBytes := encodeU8 0 }
        | _ => .error (.trapped .invalidCore)
  | .bitNot =>
      if !(operand.typeId == resultTypeId && valueCanonical data operand) then
        .error (.trapped .invalidCore)
      else
        let width? :=
          match uintWidth data operand.typeId with
          | some w => some w
          | none => intWidth data operand.typeId
        match width? with
        | some w =>
            let mask := uintMax w - 1
            let bits := leBytesToNat operand.valueBytes
            .ok {
              typeId := resultTypeId
              valueBytes := natToLeBytes (mask - bits) (uintByteLen w)
            }
        | none => .error (.trapped .invalidCore)
  | .neg =>
      if !(operand.typeId == resultTypeId && valueCanonical data operand) then
        .error (.trapped .invalidCore)
      else
        match intWidth data operand.typeId with
        | some w =>
            let value := leBytesToInt operand.valueBytes w
            if value == intMin w then
              .error (.reverted (.standard .arithmeticOverflow))
            else
              .ok {
                typeId := resultTypeId
                valueBytes := intToLeBytes (-value) w
              }
        | none =>
            match fieldModulus data operand.typeId with
            | some modulus =>
                let value := leBytesToNat operand.valueBytes
                .ok {
                  typeId := resultTypeId
                  valueBytes := natToLeBytes ((modulus - value) % modulus)
                    operand.valueBytes.size
                }
            | none => .error (.trapped .invalidCore)

private def evalBinary (data : SemanticProgramDataV1) (op : BinaryOpV1)
    (lhs rhs : ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 :=
  match op with
  | .add | .sub | .mul | .div | .mod =>
      if !(lhs.typeId == rhs.typeId && lhs.typeId == resultTypeId &&
          valueCanonical data lhs && valueCanonical data rhs) then
        .error (.trapped .invalidCore)
      else
        match uintWidth data lhs.typeId, intWidth data lhs.typeId with
        | some w, _ =>
            let len := uintByteLen w
            let a := leBytesToNat lhs.valueBytes
            let b := leBytesToNat rhs.valueBytes
            let maxV := uintMax w
            match op with
            | .add =>
                let value := a + b
                if value ≥ maxV then
                  .error (.reverted (.standard .arithmeticOverflow))
                else
                  .ok { typeId := resultTypeId, valueBytes := natToLeBytes value len }
            | .sub =>
                if a < b then
                  .error (.reverted (.standard .arithmeticUnderflow))
                else
                  .ok { typeId := resultTypeId, valueBytes := natToLeBytes (a - b) len }
            | .mul =>
                let value := a * b
                if value ≥ maxV then
                  .error (.reverted (.standard .arithmeticOverflow))
                else
                  .ok { typeId := resultTypeId, valueBytes := natToLeBytes value len }
            | .div =>
                if b == 0 then
                  .error (.reverted (.standard .divisionByZero))
                else
                  .ok { typeId := resultTypeId, valueBytes := natToLeBytes (a / b) len }
            | .mod =>
                if b == 0 then
                  .error (.reverted (.standard .divisionByZero))
                else
                  .ok { typeId := resultTypeId, valueBytes := natToLeBytes (a % b) len }
            | _ => .error (.trapped .internalInvariant)
        | _, some w =>
            let a := leBytesToInt lhs.valueBytes w
            let b := leBytesToInt rhs.valueBytes w
            if (op == .div || op == .mod) && b == 0 then
              .error (.reverted (.standard .divisionByZero))
            else if op == .div && a == intMin w && b == -1 then
              .error (.reverted (.standard .arithmeticOverflow))
            else
              let value :=
                match op with
                | .add => a + b
                | .sub => a - b
                | .mul => a * b
                | .div => a.tdiv b
                | .mod => a.tmod b
                | _ => 0
              if value < intMin w then
                .error (.reverted (.standard .arithmeticUnderflow))
              else if value > intMax w then
                .error (.reverted (.standard .arithmeticOverflow))
              else
                .ok { typeId := resultTypeId, valueBytes := intToLeBytes value w }
        | _, _ =>
            match fieldModulus data lhs.typeId with
            | some modulus =>
                if op == .mod then
                  .error (.trapped .invalidCore)
                else
                  let a := leBytesToNat lhs.valueBytes
                  let b := leBytesToNat rhs.valueBytes
                  if op == .div && b == 0 then
                    .error (.reverted (.standard .divisionByZero))
                  else
                    let value :=
                      match op with
                      | .add => (a + b) % modulus
                      | .sub => (a + modulus - b) % modulus
                      | .mul => (a * b) % modulus
                      | .div => (a * fieldPow b (modulus - 2) modulus) % modulus
                      | _ => 0
                    .ok {
                      typeId := resultTypeId
                      valueBytes := natToLeBytes value lhs.valueBytes.size
                    }
            | none => .error (.trapped .invalidCore)
  | .eq | .ne =>
      if !(lhs.typeId == rhs.typeId && isBoolType data resultTypeId) then
        .error (.trapped .invalidCore)
      else
        let eq := bytesEqual lhs.valueBytes rhs.valueBytes
        let bit : UInt8 :=
          match op with
          | .eq => if eq then 1 else 0
          | .ne => if eq then 0 else 1
          | _ => 0
        .ok { typeId := resultTypeId, valueBytes := encodeU8 bit }
  | .lt | .le | .gt | .ge =>
      if !(lhs.typeId == rhs.typeId && isBoolType data resultTypeId &&
          valueCanonical data lhs && valueCanonical data rhs) then
        .error (.trapped .invalidCore)
      else
        let values? : Option (Int × Int) :=
          match uintWidth data lhs.typeId, intWidth data lhs.typeId with
          | some _, _ =>
              some (Int.ofNat (leBytesToNat lhs.valueBytes),
                Int.ofNat (leBytesToNat rhs.valueBytes))
          | _, some w =>
              some (leBytesToInt lhs.valueBytes w, leBytesToInt rhs.valueBytes w)
          | _, _ => none
        match values? with
        | some (a, b) =>
            let flag : Bool :=
              match op with
              | .lt => a < b
              | .le => a ≤ b
              | .gt => a > b
              | .ge => a ≥ b
              | _ => false
            .ok {
              typeId := resultTypeId
              valueBytes := encodeU8 (if flag then 1 else 0)
            }
        | none => .error (.trapped .invalidCore)
  | .and | .or =>
      if !(isBoolType data lhs.typeId && isBoolType data rhs.typeId &&
          isBoolType data resultTypeId) then
        .error (.trapped .invalidCore)
      else
        match byteAt? lhs.valueBytes 0, byteAt? rhs.valueBytes 0 with
        | some lb, some rb =>
            let l := lb != 0
            let r := rb != 0
            let flag :=
              match op with
              | .and => l && r
              | .or => l || r
              | _ => false
            .ok {
              typeId := resultTypeId
              valueBytes := encodeU8 (if flag then 1 else 0)
            }
        | _, _ => .error (.trapped .invalidCore)
  | .bitAnd | .bitOr | .bitXor =>
      if !(lhs.typeId == rhs.typeId && lhs.typeId == resultTypeId &&
          valueCanonical data lhs && valueCanonical data rhs) then
        .error (.trapped .invalidCore)
      else
        let width? :=
          match uintWidth data lhs.typeId with
          | some w => some w
          | none => intWidth data lhs.typeId
        match width? with
        | some w =>
            let len := uintByteLen w
            let a := leBytesToNat lhs.valueBytes
            let b := leBytesToNat rhs.valueBytes
            let r :=
              match op with
              | .bitAnd => Nat.land a b
              | .bitOr => Nat.lor a b
              | .bitXor => Nat.xor a b
              | _ => 0
            .ok { typeId := resultTypeId, valueBytes := natToLeBytes r len }
        | none => .error (.trapped .invalidCore)
  | .shl | .shr =>
      if !(lhs.typeId == resultTypeId && uintWidth data rhs.typeId == some 32 &&
          valueCanonical data lhs && valueCanonical data rhs) then
        .error (.trapped .invalidCore)
      else
        let shift := leBytesToNat rhs.valueBytes
        match uintWidth data lhs.typeId, intWidth data lhs.typeId with
        | some w, _ =>
            if shift ≥ w then
              .error (.reverted (.standard .invalidShift))
            else
              let a := leBytesToNat lhs.valueBytes
              match op with
              | .shl =>
                  let value := Nat.shiftLeft a shift
                  if value ≥ uintMax w then
                    .error (.reverted (.standard .arithmeticOverflow))
                  else
                    .ok {
                      typeId := resultTypeId
                      valueBytes := natToLeBytes value (uintByteLen w)
                    }
              | .shr =>
                  .ok {
                    typeId := resultTypeId
                    valueBytes := natToLeBytes (Nat.shiftRight a shift) (uintByteLen w)
                  }
              | _ => .error (.trapped .internalInvariant)
        | _, some w =>
            if shift ≥ w then
              .error (.reverted (.standard .invalidShift))
            else
              let a := leBytesToInt lhs.valueBytes w
              let divisor := Int.ofNat (Nat.pow 2 shift)
              let value :=
                match op with
                | .shl => a * divisor
                | .shr => a.ediv divisor
                | _ => 0
              if value < intMin w then
                .error (.reverted (.standard .arithmeticUnderflow))
              else if value > intMax w then
                .error (.reverted (.standard .arithmeticOverflow))
              else
                .ok { typeId := resultTypeId, valueBytes := intToLeBytes value w }
        | _, _ => .error (.trapped .invalidCore)

private def evalCheckedCast (data : SemanticProgramDataV1) (src : ReferenceValueV1)
    (toType : TypeIdV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 :=
  if resultTypeId != toType then
    .error (.trapped .invalidCore)
  else if !valueCanonical data src then
    .error (.trapped .invalidCore)
  else
    let value? : Option Int :=
      match uintWidth data src.typeId, intWidth data src.typeId with
      | some _, _ => some (Int.ofNat (leBytesToNat src.valueBytes))
      | _, some sw => some (leBytesToInt src.valueBytes sw)
      | _, _ => none
    match value?, uintWidth data toType, intWidth data toType with
    | some value, some tw, _ =>
        if value < 0 || value ≥ Int.ofNat (uintMax tw) then
          .error (.reverted (.standard .castOutOfRange))
        else
          .ok {
            typeId := toType
            valueBytes := natToLeBytes value.toNat (uintByteLen tw)
          }
    | some value, _, some tw =>
        if !intInRange value tw then
          .error (.reverted (.standard .castOutOfRange))
        else
          .ok { typeId := toType, valueBytes := intToLeBytes value tw }
    | _, _, _ => .error (.trapped .invalidCore)

private def evalStructConstruct (data : SemanticProgramDataV1)
    (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == typeId && constructorIndex == 0 do
    throw (.trapped .invalidCore)
  let fields ←
    match data.types[typeId.toNat]? with
    | some { shape := .struct fields, .. } => pure fields
    | _ => .error (.trapped .invalidCore)
  unless args.size == fields.size do
    throw (.trapped .invalidCore)
  let mut chunks : Array ByteArray := #[]
  let mut i := 0
  while i < fields.size do
    match fields[i]?, args[i]? with
    | some field, some arg =>
        unless arg.typeId == field.typeId && valueCanonical data arg do
          throw (.trapped .invalidCore)
        chunks := chunks.push arg.valueBytes
    | _, _ => throw (.trapped .invalidCore)
    i := i + 1
  match encodeCanonicalStructValueV1 data.types typeId chunks with
  | .ok bytes => pure { typeId, valueBytes := bytes }
  | .error _ => .error (.trapped .invalidCore)

private def evalArrayConstruct (data : SemanticProgramDataV1)
    (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == typeId && constructorIndex == 0 do
    throw (.trapped .invalidCore)
  let (element, length) ←
    match data.types[typeId.toNat]? with
    | some { shape := .array element length, .. } => pure (element, length.toNat)
    | _ => throw (.trapped .invalidCore)
  unless args.size == length do throw (.trapped .invalidCore)
  let mut chunks := #[]
  for arg in args do
    unless arg.typeId == element && valueCanonical data arg do
      throw (.trapped .invalidCore)
    chunks := chunks.push arg.valueBytes
  match encodeCanonicalArrayValueV1 data.types typeId chunks with
  | .ok bytes => pure { typeId, valueBytes := bytes }
  | .error _ => throw (.trapped .invalidCore)

private def evalMapConstruct (data : SemanticProgramDataV1)
    (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  -- N-MAP-CONSTRUCT: ctor 0 with flattened key/value pairs. Semantics:
  -- empty map + sequential upsert in arg order (duplicate key last-wins,
  -- matching IndexSet; canonical value stays sorted via the upsert helper).
  unless resultTypeId == typeId && constructorIndex == 0 && args.size % 2 == 0 do
    throw (.trapped .invalidCore)
  let mut bytes := ←
    match encodeCanonicalEmptyMapValueV1 data.types typeId with
    | .ok empty => pure empty
    | .error _ => throw (.trapped .invalidCore)
  let mut i := 0
  while i < args.size do
    match args[i]?, args[i + 1]? with
    | some key, some value =>
        match upsertCanonicalMapValueV1 data.types typeId bytes
            key.valueBytes value.valueBytes with
        | .ok updated => bytes := updated
        | .error .resourceExhausted => throw (.trapped .resourceExhausted)
        | .error (.invalidInput _) => throw (.trapped .invalidCore)
    | _, _ => throw (.trapped .invalidCore)
    i := i + 2
  pure { typeId, valueBytes := bytes }

private def evalUnitConstruct (data : SemanticProgramDataV1)
    (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == typeId && constructorIndex == 0 && args.isEmpty do
    throw (.trapped .invalidCore)
  unless isUnitType data typeId do throw (.trapped .invalidCore)
  pure { typeId, valueBytes := ByteArray.empty }

private def checkedIndex (data : SemanticProgramDataV1)
    (index : ReferenceValueV1) : Except LocalFailureV1 Nat := do
  match data.types[index.typeId.toNat]? with
  | some { shape := .uint 32, .. } => pure ()
  | _ => throw (.trapped .invalidCore)
  unless index.valueBytes.size == 4 && valueCanonical data index do
    throw (.trapped .invalidCore)
  pure (leBytesToNat index.valueBytes)

private def evalIndexGet (data : SemanticProgramDataV1) (base index : ReferenceValueV1)
    (resultTypeId : TypeIdV1) : Except LocalFailureV1 ReferenceValueV1 := do
  match data.types[base.typeId.toNat]? with
  | some { shape := .array element _, .. } =>
      unless valueCanonical data base do throw (.trapped .invalidCore)
      let i ← checkedIndex data index
      unless resultTypeId == element do throw (.trapped .invalidCore)
      match splitCanonicalArrayValueV1 data.types base.typeId base.valueBytes with
      | .ok chunks =>
          match chunks[i]? with
          | some bytes => pure { typeId := element, valueBytes := bytes }
          | none => throw (.reverted (.standard .indexOutOfBounds))
      | .error _ => throw (.trapped .invalidCore)
  | some { shape := .bytes _, .. } =>
      unless valueCanonical data base do throw (.trapped .invalidCore)
      let i ← checkedIndex data index
      match data.types[resultTypeId.toNat]? with
      | some { shape := .uint 8, .. } =>
          match byteAt? base.valueBytes i with
          | some b => pure { typeId := resultTypeId, valueBytes := ByteArray.mk #[b] }
          | none => throw (.reverted (.standard .indexOutOfBounds))
      | _ => throw (.trapped .invalidCore)
  | some { shape := .map keyType valueType, .. } =>
      unless index.typeId == keyType do
        throw (.trapped .invalidCore)
      match data.types[resultTypeId.toNat]? with
      | some { shape := .option element, .. } =>
          unless element == valueType do throw (.trapped .invalidCore)
          match lookupCanonicalMapValueV1 data.types base.typeId base.valueBytes index.valueBytes with
          | .error _ => throw (.trapped .invalidCore)
          | .ok none =>
              match encodeCanonicalVariantValueV1 data.types resultTypeId 0 #[] with
              | .ok bytes => pure { typeId := resultTypeId, valueBytes := bytes }
              | .error _ => throw (.trapped .invalidCore)
          | .ok (some valueBytes) =>
              match encodeCanonicalVariantValueV1 data.types resultTypeId 1 #[valueBytes] with
              | .ok bytes => pure { typeId := resultTypeId, valueBytes := bytes }
              | .error _ => throw (.trapped .invalidCore)
      | _ => throw (.trapped .invalidCore)
  | _ => throw (.trapped .invalidCore)

private def evalIndexSet (data : SemanticProgramDataV1) (base index value : ReferenceValueV1)
    (resultTypeId : TypeIdV1) : Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == base.typeId do throw (.trapped .invalidCore)
  match data.types[base.typeId.toNat]? with
  | some { shape := .array element _, .. } =>
      unless valueCanonical data base && valueCanonical data value do
        throw (.trapped .invalidCore)
      let i ← checkedIndex data index
      unless value.typeId == element do throw (.trapped .invalidCore)
      match splitCanonicalArrayValueV1 data.types base.typeId base.valueBytes with
      | .ok chunks =>
          if h : i < chunks.size then
            match encodeCanonicalArrayValueV1 data.types base.typeId
                (chunks.set i value.valueBytes) with
            | .ok bytes => pure { typeId := base.typeId, valueBytes := bytes }
            | .error _ => throw (.trapped .invalidCore)
          else throw (.reverted (.standard .indexOutOfBounds))
      | .error _ => throw (.trapped .invalidCore)
  | some { shape := .bytes _, .. } =>
      unless valueCanonical data base && valueCanonical data value do
        throw (.trapped .invalidCore)
      let i ← checkedIndex data index
      match data.types[value.typeId.toNat]? with
      | some { shape := .uint 8, .. } =>
          match byteAt? value.valueBytes 0 with
          | some b =>
              if i < base.valueBytes.size then
                let bytes := (base.valueBytes.extract 0 i).append
                  ((ByteArray.mk #[b]).append (base.valueBytes.extract (i + 1) base.valueBytes.size))
                pure { typeId := base.typeId, valueBytes := bytes }
              else throw (.reverted (.standard .indexOutOfBounds))
          | none => throw (.trapped .invalidCore)
      | _ => throw (.trapped .invalidCore)
  | some { shape := .map keyType valueType, .. } =>
      unless index.typeId == keyType && value.typeId == valueType do
        throw (.trapped .invalidCore)
      match upsertCanonicalMapValueV1 data.types base.typeId base.valueBytes
          index.valueBytes value.valueBytes with
      | .ok bytes => pure { typeId := base.typeId, valueBytes := bytes }
      | .error .resourceExhausted => throw (.trapped .resourceExhausted)
      | .error (.invalidInput _) => throw (.trapped .invalidCore)
  | _ => throw (.trapped .invalidCore)

private def evalVariantConstruct (data : SemanticProgramDataV1)
    (typeId : TypeIdV1) (constructorIndex : UInt32)
    (args : Array ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == typeId do throw (.trapped .invalidCore)
  let payloadTypes ←
    match data.types[typeId.toNat]? with
    | some { shape := .option element, .. } =>
        if constructorIndex == 0 then pure #[]
        else if constructorIndex == 1 then pure #[element]
        else throw (.trapped .invalidCore)
    | some { shape := .enum variants, .. } =>
        match variants[constructorIndex.toNat]? with
        | some variant => pure variant.payloadTypes
        | none => throw (.trapped .invalidCore)
    | _ => throw (.trapped .invalidCore)
  unless args.size == payloadTypes.size do throw (.trapped .invalidCore)
  let mut chunks := #[]
  for i in [:payloadTypes.size] do
    match args[i]?, payloadTypes[i]? with
    | some arg, some payloadType =>
        unless arg.typeId == payloadType && valueCanonical data arg do
          throw (.trapped .invalidCore)
        chunks := chunks.push arg.valueBytes
    | _, _ => throw (.trapped .invalidCore)
  match encodeCanonicalVariantValueV1 data.types typeId constructorIndex chunks with
  | .ok bytes => pure { typeId, valueBytes := bytes }
  | .error _ => throw (.trapped .invalidCore)

private def evalVariantTag (data : SemanticProgramDataV1) (base : ReferenceValueV1)
    (resultTypeId : TypeIdV1) : Except LocalFailureV1 ReferenceValueV1 := do
  match data.types[resultTypeId.toNat]? with
  | some { shape := .uint 32, .. } => pure ()
  | _ => throw (.trapped .invalidCore)
  match splitCanonicalVariantValueV1 data.types base.typeId base.valueBytes with
  | .ok (tag, _) => pure { typeId := resultTypeId, valueBytes := natToLeBytes tag.toNat 4 }
  | .error _ => throw (.trapped .invalidCore)

private def evalVariantPayload (data : SemanticProgramDataV1)
    (base : ReferenceValueV1) (variantIndex payloadIndex : UInt32)
    (resultTypeId : TypeIdV1) : Except LocalFailureV1 ReferenceValueV1 := do
  let expectedType ←
    match data.types[base.typeId.toNat]? with
    | some { shape := .option element, .. } =>
        if variantIndex == 1 && payloadIndex == 0 then pure element
        else throw (.trapped .invalidCore)
    | some { shape := .enum variants, .. } =>
        match variants[variantIndex.toNat]? with
        | some variant =>
            match variant.payloadTypes[payloadIndex.toNat]? with
            | some tid => pure tid
            | none => throw (.trapped .invalidCore)
        | none => throw (.trapped .invalidCore)
    | _ => throw (.trapped .invalidCore)
  unless resultTypeId == expectedType do throw (.trapped .invalidCore)
  match splitCanonicalVariantValueV1 data.types base.typeId base.valueBytes with
  | .ok (runtimeTag, chunks) =>
      unless runtimeTag == variantIndex do throw (.trapped .invalidCore)
      match chunks[payloadIndex.toNat]? with
      | some bytes => pure { typeId := expectedType, valueBytes := bytes }
      | none => throw (.trapped .invalidCore)
  | .error _ => throw (.trapped .invalidCore)

private def evalStructFieldGet (data : SemanticProgramDataV1)
    (base : ReferenceValueV1) (fieldIndex : UInt32)
    (resultTypeId : TypeIdV1) : Except LocalFailureV1 ReferenceValueV1 := do
  let fields ←
    match data.types[base.typeId.toNat]? with
    | some { shape := .struct fields, .. } => pure fields
    | _ => .error (.trapped .invalidCore)
  match fields[fieldIndex.toNat]? with
  | none => .error (.trapped .invalidCore)
  | some field =>
      unless resultTypeId == field.typeId do
        throw (.trapped .invalidCore)
      match splitCanonicalStructValueV1 data.types base.typeId base.valueBytes with
      | .error _ => .error (.trapped .invalidCore)
      | .ok chunks =>
          match chunks[fieldIndex.toNat]? with
          | some bytes => pure { typeId := field.typeId, valueBytes := bytes }
          | none => .error (.trapped .invalidCore)

private def evalStructFieldSet (data : SemanticProgramDataV1)
    (base : ReferenceValueV1) (fieldIndex : UInt32)
    (value : ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except LocalFailureV1 ReferenceValueV1 := do
  unless resultTypeId == base.typeId do
    throw (.trapped .invalidCore)
  let fields ←
    match data.types[base.typeId.toNat]? with
    | some { shape := .struct fields, .. } => pure fields
    | _ => .error (.trapped .invalidCore)
  match fields[fieldIndex.toNat]? with
  | none => .error (.trapped .invalidCore)
  | some field =>
      unless value.typeId == field.typeId && valueCanonical data value do
        throw (.trapped .invalidCore)
      match splitCanonicalStructValueV1 data.types base.typeId base.valueBytes with
      | .error _ => .error (.trapped .invalidCore)
      | .ok chunks =>
          if h : fieldIndex.toNat < chunks.size then
            let updated := chunks.set fieldIndex.toNat value.valueBytes
            match encodeCanonicalStructValueV1 data.types base.typeId updated with
            | .ok bytes => pure { typeId := base.typeId, valueBytes := bytes }
            | .error _ => .error (.trapped .invalidCore)
          else
            .error (.trapped .invalidCore)

private def storeResult (m : MachineV1) (vid : ValueIdV1) (v : ReferenceValueV1) :
    ExecResult :=
  if !valueCanonical m.data v then
    .done m (.trapped .invalidCore)
  else
    match envSet m.env vid v with
    | none => .done m (.trapped .internalInvariant)
    | some env' => .next { m with env := env' }

/-! ### ADR-0030 E2: minimal self-vault interpreter helpers -/

/-- Exact catalog-QN equality (pf.assets family). -/
private def qnEqualsV1 (callee : QualifiedName) (expected : String) : Bool :=
  String.intercalate "." callee.components.toArray.toList == expected

/-- Decode a canonical 8-byte LE UInt64 argument value to Nat (defensive:
    non-8-byte encodings trap via the caller's `none` branch). -/
private def vaultArgAmountV1 (v : ReferenceValueV1) : Option Nat :=
  if v.valueBytes.size == 8 then some (leBytesToNat v.valueBytes) else none

/-- Mint-keyed token vault read; absent key is zero. -/
private def vaultTokenBalanceV1 (vault : Array (ByteArray × UInt64))
    (key : ByteArray) : UInt64 := Id.run do
  let mut bal : UInt64 := 0
  for (k, v) in vault do
    if k == key then
      bal := v
  pure bal

/-- Mint-keyed token vault debit. Absent key has balance zero: a zero amount
    debits to zero, a positive amount is an underflow (`none`). -/
private def vaultTokenDebitV1 (vault : Array (ByteArray × UInt64)) (key : ByteArray)
    (amount : UInt64) : Option (Array (ByteArray × UInt64)) := Id.run do
  let mut out := vault
  let mut found := false
  let mut idx : Nat := 0
  let mut failed := false
  for (k, v) in vault do
    if k == key then
      found := true
      if v < amount then
        failed := true
      else if h : idx < out.size then
        out := out.set idx (k, v - amount) h
  if failed then
    pure none
  else if found then
    pure (some out)
  else if amount == 0 then
    pure (some out)
  else
    pure none

/-- Deterministic self-vault sufficiency gate + immediate debit for the sync
    catalog transfer QNs (`pf.assets.native.transfer` /
    `pf.assets.token.transfer`). Underflow reverts as an external-call
    failure. Called only after a `.returned` response was consumed, so the
    response-cursor discipline (every ExternalCall consumes exactly one
    response row) stays uniform. Non-transfer QNs pass through. -/
private def vaultTransferOut (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) (occ : EffectOccurrenceV1) :
    Except LocalFailureV1 MachineV1 :=
  if qnEqualsV1 callee "pf.assets.native.transfer" then
    match argVals[1]? with
    | some amountV =>
        match vaultArgAmountV1 amountV with
        | none => .error (.trapped .invalidCore)
        | some amount =>
            if amount ≤ m.vaultNative.toNat then
              .ok { m with vaultNative := UInt64.ofNat (m.vaultNative.toNat - amount) }
            else
              .error (.reverted (.externalCallReverted occ))
    | none => .error (.trapped .invalidCore)
  else if qnEqualsV1 callee "pf.assets.token.transfer" then
    match argVals[0]?, argVals[2]? with
    | some mintV, some amountV =>
        match vaultArgAmountV1 amountV with
        | none => .error (.trapped .invalidCore)
        | some amount =>
            match vaultTokenDebitV1 m.vaultToken mintV.valueBytes (UInt64.ofNat amount) with
            | some vault' => .ok { m with vaultToken := vault' }
            | none => .error (.reverted (.externalCallReverted occ))
    | _, _ => .error (.trapped .invalidCore)
  else
    .ok m

/-- Self-vault credit for a successful `pf.assets.native.deposit` (checked
    add; overflow is a harness inconsistency and traps invalidCore).
    Non-deposit QNs pass through. -/
private def vaultDepositIn (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) : Except LocalFailureV1 MachineV1 :=
  if qnEqualsV1 callee "pf.assets.native.deposit" then
    match argVals[0]? with
    | some amountV =>
        match vaultArgAmountV1 amountV with
        | none => .error (.trapped .invalidCore)
        | some amount =>
            if amount ≤ (UInt64.size - 1) - m.vaultNative.toNat then
              .ok { m with vaultNative := UInt64.ofNat (m.vaultNative.toNat + amount) }
            else
              .error (.trapped .invalidCore)
    | none => .error (.trapped .invalidCore)
  else
    .ok m

/-- Fire-and-forget async debit for the catalog transferAsync QNs. A remote
    failure is invisible to the program, so an underfunded async transfer
    leaves the vault unchanged (the funds never left). -/
private def vaultAsyncOut (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) : MachineV1 :=
  if qnEqualsV1 callee "pf.assets.native.transferAsync" then
    match argVals[1]? with
    | some amountV =>
        match vaultArgAmountV1 amountV with
        | none => m
        | some amount =>
            if amount ≤ m.vaultNative.toNat then
              { m with vaultNative := UInt64.ofNat (m.vaultNative.toNat - amount) }
            else m
    | none => m
  else if qnEqualsV1 callee "pf.assets.token.transferAsync" then
    match argVals[0]?, argVals[2]? with
    | some mintV, some amountV =>
        match vaultArgAmountV1 amountV with
        | none => m
        | some amount =>
            match vaultTokenDebitV1 m.vaultToken mintV.valueBytes (UInt64.ofNat amount) with
            | some vault' => { m with vaultToken := vault' }
            | none => m
    | _, _ => m
  else m

private def fromEval (m : MachineV1) (vid : ValueIdV1)
    (r : Except LocalFailureV1 ReferenceValueV1) : ExecResult :=
  match r with
  | .error failure => .done m failure.toCandidateV1
  | .ok v => storeResult m vid v

/-! ### Instruction / terminator -/

private def execInstruction (m : MachineV1) (instr : InstructionV1) : ExecResult :=
  match instr.op with
  | .literal tid bytes =>
      match instr.result with
      | none => .done m (.trapped .invalidCore)
      | some vd =>
          if vd.typeId != tid then
            .done m (.trapped .invalidCore)
          else
            let v : ReferenceValueV1 := { typeId := tid, valueBytes := bytes }
            if !valueCanonical m.data v then
              .done m (.trapped .invalidCore)
            else
              storeResult m vd.valueId v
  | .constant cid =>
      match instr.result, m.data.constants[cid.toNat]? with
      | some vd, some c =>
          if vd.typeId != c.typeId then
            .done m (.trapped .invalidCore)
          else
            storeResult m vd.valueId
              { typeId := c.typeId, valueBytes := c.valueBytes }
      | _, _ => .done m (.trapped .invalidCore)
  | .stateLoad sid =>
      match instr.result, m.data.logicalState[sid.toNat]?, m.overlay[sid.toNat]? with
      | some vd, some decl, some bytes =>
          if vd.typeId != decl.typeId then
            .done m (.trapped .invalidCore)
          else
            storeResult m vd.valueId
              { typeId := decl.typeId, valueBytes := bytes }
      | _, _, _ => .done m (.trapped .invalidCore)
  | .stateStore sid valueId =>
      match instr.result with
      | some _ => .done m (.trapped .invalidCore)
      | none =>
          match m.data.logicalState[sid.toNat]?, envGet m.env valueId with
          | some decl, some v =>
              if v.typeId != decl.typeId then
                .done m (.trapped .invalidCore)
              else if !valueCanonical m.data v then
                .done m (.trapped .invalidCore)
              else
                let i := sid.toNat
                if h : i < m.overlay.size then
                  .next { m with overlay := m.overlay.set i v.valueBytes }
                else
                  .done m (.trapped .internalInvariant)
          | _, _ => .done m (.trapped .invalidCore)
  | .checkedCast valueId toType =>
      match instr.result, envGet m.env valueId with
      | some vd, some src =>
          if !valueCanonical m.data src then
            .done m (.trapped .invalidCore)
          else
            fromEval m vd.valueId (evalCheckedCast m.data src toType vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .unary op operandId =>
      match instr.result, envGet m.env operandId with
      | some vd, some operand =>
          if !valueCanonical m.data operand then
            .done m (.trapped .invalidCore)
          else
            fromEval m vd.valueId (evalUnary m.data op operand vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .binary op lhsId rhsId =>
      match instr.result, envGet m.env lhsId, envGet m.env rhsId with
      | some vd, some lhs, some rhs =>
          if !valueCanonical m.data lhs || !valueCanonical m.data rhs then
            .done m (.trapped .invalidCore)
          else
            fromEval m vd.valueId (evalBinary m.data op lhs rhs vd.typeId)
      | _, _, _ => .done m (.trapped .invalidCore)
  | .assert_ condId errorId args =>
      match instr.result with
      | some _ => .done m (.trapped .invalidCore)
      | none =>
          match envGet m.env condId with
          | none => .done m (.trapped .invalidCore)
          | some cond =>
              if !isBoolType m.data cond.typeId || !valueCanonical m.data cond then
                .done m (.trapped .invalidCore)
              else
                match byteAt? cond.valueBytes 0 with
                | some 1 => .next m
                | some 0 =>
                    match errorId with
                    | none =>
                        if args.isEmpty then
                          .done m (.reverted (.standard .assertionFailed))
                        else
                          .done m (.trapped .invalidCore)
                    | some eid =>
                        match lookupArgs m.env args, m.data.errors[eid.toNat]? with
                        | some argVals, some _ =>
                            .done m (.reverted (.declared eid argVals))
                        | _, _ => .done m (.trapped .invalidCore)
                | _ => .done m (.trapped .invalidCore)
  | .emit effectId eventId args =>
      match instr.result with
      | some _ => .done m (.trapped .invalidCore)
      | none =>
          match lookupArgs m.env args, m.data.events[eventId.toNat]? with
          | some argVals, some _ =>
              match nextOccurrence m effectId with
              | none => .done m (.trapped .resourceExhausted)
              | some (m1, occ) =>
                  let eff : OrderedEffectV1 := {
                    occurrence := occ
                    payload := .event eventId argVals
                  }
                  .next { m1 with effects := m1.effects.push eff }
          | _, _ => .done m (.trapped .invalidCore)
  | .externalCall effectId callee args =>
      match lookupArgs m.env args with
      | none => .done m (.trapped .invalidCore)
      | some argVals =>
          match nextOccurrence m effectId with
          | none => .done m (.trapped .resourceExhausted)
          | some (m1, occ) =>
              let eff : OrderedEffectV1 := {
                occurrence := occ
                payload := .externalCall callee argVals
              }
              let m2 := { m1 with effects := m1.effects.push eff }
              match m2.responses[m2.responseCursor]? with
              | none => .done m2 (.trapped .invalidExternalResponse)
              | some resp =>
                  let okPair :=
                    resp.occurrence.effectId == occ.effectId &&
                    resp.occurrence.occurrence == occ.occurrence
                  if !okPair then
                    .done m2 (.trapped .invalidExternalResponse)
                  else
                    let m3 :=
                      { m2 with responseCursor := m2.responseCursor + 1 }
                    match resp.disposition with
                    | .reverted =>
                        .done m3 (.reverted (.externalCallReverted occ))
                    | .returned =>
                        -- N-CALL-RET: a bound result requires a typed return
                        -- value; a void call discards any (test-supplied)
                        -- return value by contract.
                        match instr.result, resp.returnValue? with
                        | some vd, some rv =>
                            if rv.typeId == vd.typeId then
                              storeResult m3 vd.valueId rv
                            else
                              .done m3 (.trapped .invalidExternalResponse)
                        | none, _ =>
                            -- ADR-0030 E2: catalog vault interpreter — a
                            -- returned deposit credits the native vault; a
                            -- returned sync transfer debits native/token
                            -- vaults when sufficient (underflow overrides the
                            -- returned disposition with a revert); a returned
                            -- async transferAsync debits when sufficient and
                            -- is vault-neutral otherwise (remote failure is
                            -- invisible locally); other QNs are vault-neutral.
                            match vaultDepositIn m3 callee argVals with
                            | .error failure => .done m3 failure.toCandidateV1
                            | .ok m4 =>
                            match vaultTransferOut m4 callee argVals occ with
                            | .error failure => .done m3 failure.toCandidateV1
                            | .ok m5 => .next (vaultAsyncOut m5 callee argVals)
                        | some _, none => .done m3 (.trapped .invalidExternalResponse)
  | .schedule effectId callee args =>
      match instr.result with
      | some _ => .done m (.trapped .invalidCore)
      | none =>
          match lookupArgs m.env args with
          | none => .done m (.trapped .invalidCore)
          | some argVals =>
              match nextOccurrence m effectId with
              | none => .done m (.trapped .resourceExhausted)
              | some (m1, occ) =>
                  let eff : OrderedEffectV1 := {
                    occurrence := occ
                    payload := .schedule callee argVals
                  }
                  -- ADR-0030 E2: fire-and-forget async debit (remote failure
                  -- is invisible locally and leaves the vault unchanged).
                  let m2 := vaultAsyncOut m1 callee argVals
                  .next { m2 with effects := m2.effects.push eff }
  | .envRead key args =>
      -- ADR-0030 E2: read-only self-vault observation. Result is the UInt64
      -- balance; canonicality/type exactness rides on storeResult and the
      -- structure gate (result typeId is the unique UInt64).
      match instr.result with
      | none => .done m (.trapped .invalidCore)
      | some vd =>
          match key with
          | .nativeVaultBalance =>
              if args.isEmpty then
                storeResult m vd.valueId
                  { typeId := vd.typeId
                    valueBytes := natToLeBytes m.vaultNative.toNat 8 }
              else
                .done m (.trapped .invalidCore)
          | .tokenVaultBalance =>
              match lookupArgs m.env args with
              | some #[mintV] =>
                  match m.data.types[mintV.typeId.toNat]? with
                  | some { shape := .principal, .. } =>
                      let bal := vaultTokenBalanceV1 m.vaultToken mintV.valueBytes
                      storeResult m vd.valueId
                        { typeId := vd.typeId
                          valueBytes := natToLeBytes bal.toNat 8 }
                  | _ => .done m (.trapped .invalidCore)
              | _ => .done m (.trapped .invalidCore)
  | .construct typeId constructorIndex argIds =>
      match instr.result, lookupArgs m.env argIds with
      | some vd, some args =>
          let evaluated :=
            match m.data.types[typeId.toNat]? with
            | some { shape := .struct _, .. } =>
                evalStructConstruct m.data typeId constructorIndex args vd.typeId
            | some { shape := .array _ _, .. } =>
                evalArrayConstruct m.data typeId constructorIndex args vd.typeId
            | some { shape := .map _ _, .. } =>
                evalMapConstruct m.data typeId constructorIndex args vd.typeId
            | some { shape := .unit, .. } =>
                evalUnitConstruct m.data typeId constructorIndex args vd.typeId
            | some { shape := .option _, .. } | some { shape := .enum _, .. } =>
                evalVariantConstruct m.data typeId constructorIndex args vd.typeId
            | _ => .error (.trapped .invalidCore)
          fromEval m vd.valueId evaluated
      | _, _ => .done m (.trapped .invalidCore)
  | .fieldGet baseId fieldIndex =>
      match instr.result, envGet m.env baseId with
      | some vd, some base =>
          fromEval m vd.valueId
            (evalStructFieldGet m.data base fieldIndex vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .fieldSet baseId fieldIndex valueId =>
      match instr.result, envGet m.env baseId, envGet m.env valueId with
      | some vd, some base, some value =>
          fromEval m vd.valueId
            (evalStructFieldSet m.data base fieldIndex value vd.typeId)
      | _, _, _ => .done m (.trapped .invalidCore)
  | .variantTag baseId =>
      match instr.result, envGet m.env baseId with
      | some vd, some base => fromEval m vd.valueId (evalVariantTag m.data base vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .variantPayload baseId variantIndex payloadIndex =>
      match instr.result, envGet m.env baseId with
      | some vd, some base =>
          fromEval m vd.valueId
            (evalVariantPayload m.data base variantIndex payloadIndex vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .indexGet baseId indexId =>
      match instr.result, envGet m.env baseId, envGet m.env indexId with
      | some vd, some base, some index =>
          fromEval m vd.valueId (evalIndexGet m.data base index vd.typeId)
      | _, _, _ => .done m (.trapped .invalidCore)
  | .indexSet baseId indexId valueId =>
      match instr.result, envGet m.env baseId, envGet m.env indexId, envGet m.env valueId with
      | some vd, some base, some index, some value =>
          fromEval m vd.valueId (evalIndexSet m.data base index value vd.typeId)
      | _, _, _, _ => .done m (.trapped .invalidCore)
  | .contextRead key =>
      match instr.result with
      | none => .done m (.trapped .invalidCore)
      | some vd =>
          match m.context.find? fun row => row.key == key with
          | none => .done m (.trapped .internalInvariant)
          | some row =>
              if row.value.typeId != vd.typeId then
                .done m (.trapped .internalInvariant)
              else
                storeResult m vd.valueId row.value
  | .commit valueId =>
      match instr.result, envGet m.env valueId with
      | some vd, some value =>
          if vd.typeId != value.typeId then
            .done m (.trapped .internalInvariant)
          else
            storeResult m vd.valueId value
      | _, _ => .done m (.trapped .internalInvariant)
  | .pureCall _ _ =>
      .done m (.trapped .internalInvariant)

/-- Simultaneous jump-arg bind: gather all source values from the pre-write
    env, then write target block params (no sequential aliasing). -/
private def bindJumpTarget (m : MachineV1) (target : JumpTargetV1) : ExecResult :=
  match m.callable.blocks[target.blockId.toNat]? with
  | none => .done m (.trapped .invalidCore)
  | some block =>
      if target.args.size != block.params.size then
        .done m (.trapped .invalidCore)
      else
        match noteBackEdge m m.blockId target.blockId with
        | .done m' cand => .done m' cand
        | .next mEdge =>
            Id.run do
              -- Phase 1: gather from original env (before any param write).
              let srcEnv := mEdge.env
              let mut gathered : Array ReferenceValueV1 :=
                Array.emptyWithCapacity block.params.size
              let mut i : Nat := 0
              let mut fault : Option SemanticFaultV1 := none
              for bp in block.params do
                if fault.isNone then
                  match target.args[i]? with
                  | none => fault := some .invalidCore
                  | some srcId =>
                      match envGet srcEnv srcId with
                      | none => fault := some .invalidCore
                      | some v =>
                          if v.typeId != bp.typeId || !valueCanonical m.data v then
                            fault := some .invalidCore
                          else
                            gathered := gathered.push v
                i := i + 1
              match fault with
              | some f => pure (.done mEdge (.trapped f))
              | none =>
                  -- Phase 2: write all gathered values into target params.
                  let mut env := srcEnv
                  let mut j : Nat := 0
                  let mut writeFault : Option SemanticFaultV1 := none
                  for bp in block.params do
                    if writeFault.isNone then
                      match gathered[j]? with
                      | none => writeFault := some .internalInvariant
                      | some v =>
                          match envSet env bp.valueId v with
                          | none => writeFault := some .internalInvariant
                          | some env' => env := env'
                    j := j + 1
                  match writeFault with
                  | some f => pure (.done mEdge (.trapped f))
                  | none =>
                      pure (.next {
                        mEdge with
                        env := env
                        blockId := target.blockId
                        instrIdx := 0
                      })

private def execTerminator (m : MachineV1) (term : TerminatorV1) : ExecResult :=
  match term with
  | .jump target => bindJumpTarget m target
  | .branch condId thenT elseT =>
      match envGet m.env condId with
      | none => .done m (.trapped .invalidCore)
      | some cond =>
          if !isBoolType m.data cond.typeId || !valueCanonical m.data cond then
            .done m (.trapped .invalidCore)
          else
            match byteAt? cond.valueBytes 0 with
            | some 1 => bindJumpTarget m thenT
            | some 0 => bindJumpTarget m elseT
            | _ => .done m (.trapped .invalidCore)
  | .switch scrut cases defaultT =>
      match envGet m.env scrut with
      | none => .done m (.trapped .invalidCore)
      | some sv =>
          if !valueCanonical m.data sv then
            .done m (.trapped .invalidCore)
          else
            let matched : Option JumpTargetV1 := Id.run do
              let mut matched : Option JumpTargetV1 := none
              for sc in cases do
                if matched.isNone && sc.typeId == sv.typeId &&
                    bytesEqual sc.valueBytes sv.valueBytes then
                  matched := some sc.target
              pure matched
            match matched with
            | some t => bindJumpTarget m t
            | none =>
                match defaultT with
                | some t => bindJumpTarget m t
                -- Miss without default is control-flow unreachability, not bad Core.
                | none => .done m (.trapped .unreachable)
  | .return_ valueId? =>
      match valueId? with
      | none =>
          -- Only `return_ none` yields returned Unit (none value).
          if isUnitType m.data m.callable.result.typeId then
            .done m (.returned none)
          else
            .done m (.trapped .invalidCore)
      | some vid =>
          -- Unit result with `return_ (some v)` is invalidCore (not laundered).
          if isUnitType m.data m.callable.result.typeId then
            .done m (.trapped .invalidCore)
          else
            match envGet m.env vid with
            | none => .done m (.trapped .invalidCore)
            | some v =>
                if v.typeId != m.callable.result.typeId || !valueCanonical m.data v then
                  .done m (.trapped .invalidCore)
                else
                  .done m (.returned (some v))
  | .revert errorId args =>
      match lookupArgs m.env args, m.data.errors[errorId.toNat]? with
      | some argVals, some _ =>
          .done m (.reverted (.declared errorId argVals))
      | _, _ => .done m (.trapped .invalidCore)
  | .trap code =>
      let fault : SemanticFaultV1 :=
        match code with
        | .unreachable => .unreachable
        | .invalidExternalResponse => .invalidExternalResponse
        | .resourceExhausted => .resourceExhausted
        | .internalInvariant => .internalInvariant
      .done m (.trapped fault)

private theorem nextOccurrence_preserves_data
    (m : MachineV1) (effectId : EffectIdV1) :
    match nextOccurrence m effectId with
    | none => True
    | some (m', _) => m'.data = m.data := by
  grind [nextOccurrence]

private theorem noteBackEdge_preserves_data
    (m : MachineV1) (fromBlock toBlock : BlockIdV1) :
    ExecResultPreservesDataV1 m.data (noteBackEdge m fromBlock toBlock) := by
  grind [ExecResultPreservesDataV1, noteBackEdge]

private theorem storeResult_preserves_data
    (m : MachineV1) (vid : ValueIdV1) (v : ReferenceValueV1) :
    ExecResultPreservesDataV1 m.data (storeResult m vid v) := by
  grind [ExecResultPreservesDataV1, storeResult]

private theorem vaultTransferOut_preserves_data
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) (occ : EffectOccurrenceV1) :
    ExceptMachinePreservesDataV1 m.data
      (vaultTransferOut m callee argVals occ) := by
  grind [ExceptMachinePreservesDataV1, vaultTransferOut]

private theorem vaultDepositIn_preserves_data
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) :
    ExceptMachinePreservesDataV1 m.data (vaultDepositIn m callee argVals) := by
  grind [ExceptMachinePreservesDataV1, vaultDepositIn]

private theorem vaultAsyncOut_preserves_data
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) :
    (vaultAsyncOut m callee argVals).data = m.data := by
  grind [vaultAsyncOut]

private theorem returnedVoidVaultPipeline_preserves_data
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) (occ : EffectOccurrenceV1) :
    ExecResultPreservesDataV1 m.data
      (match vaultDepositIn m callee argVals with
      | .error failure => .done m failure.toCandidateV1
      | .ok m4 =>
          match vaultTransferOut m4 callee argVals occ with
          | .error failure => .done m failure.toCandidateV1
          | .ok m5 => .next (vaultAsyncOut m5 callee argVals)) := by
  cases hdeposit : vaultDepositIn m callee argVals with
  | error candidate =>
      simp only
      rfl
  | ok m4 =>
      simp only
      have hm4 : m4.data = m.data := by
        have hpreserves := vaultDepositIn_preserves_data m callee argVals
        simpa [ExceptMachinePreservesDataV1, hdeposit] using hpreserves
      cases htransfer : vaultTransferOut m4 callee argVals occ with
      | error candidate =>
          simp only
          rfl
      | ok m5 =>
          simp only
          have hm5 : m5.data = m4.data := by
            have hpreserves :=
              vaultTransferOut_preserves_data m4 callee argVals occ
            simpa [ExceptMachinePreservesDataV1, htransfer] using hpreserves
          exact (vaultAsyncOut_preserves_data m5 callee argVals).trans
            (hm5.trans hm4)

private theorem fromEval_preserves_data
    (m : MachineV1) (vid : ValueIdV1)
    (r : Except LocalFailureV1 ReferenceValueV1) :
    ExecResultPreservesDataV1 m.data (fromEval m vid r) := by
  cases r with
  | error candidate => rfl
  | ok value => exact storeResult_preserves_data m vid value

private theorem nextOccurrence_preserves_callStack
    (m : MachineV1) (effectId : EffectIdV1) :
    match nextOccurrence m effectId with
    | none => True
    | some (m', _) =>
        m'.callable = m.callable ∧ m'.frames = m.frames := by
  grind [nextOccurrence]

private theorem noteBackEdge_preserves_callStackFailure
    (m : MachineV1) (fromBlock toBlock : BlockIdV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (noteBackEdge m fromBlock toBlock) := by
  grind [ExecResultPreservesCallStackFailureV1, noteBackEdge]

private theorem storeResult_preserves_callStackFailure
    (m : MachineV1) (vid : ValueIdV1) (value : ReferenceValueV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (storeResult m vid value) := by
  grind [ExecResultPreservesCallStackFailureV1, storeResult]

private theorem vaultTransferOut_preserves_callStack
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) (occ : EffectOccurrenceV1) :
    ExceptMachinePreservesCallStackV1 m.callable m.frames
      (vaultTransferOut m callee argVals occ) := by
  grind [ExceptMachinePreservesCallStackV1, vaultTransferOut]

private theorem vaultDepositIn_preserves_callStack
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) :
    ExceptMachinePreservesCallStackV1 m.callable m.frames
      (vaultDepositIn m callee argVals) := by
  grind [ExceptMachinePreservesCallStackV1, vaultDepositIn]

private theorem vaultAsyncOut_preserves_callStack
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) :
    (vaultAsyncOut m callee argVals).callable = m.callable ∧
      (vaultAsyncOut m callee argVals).frames = m.frames := by
  grind [vaultAsyncOut]

private theorem returnedVoidVaultPipeline_preserves_callStackFailure
    (m : MachineV1) (callee : QualifiedName)
    (argVals : Array ReferenceValueV1) (occ : EffectOccurrenceV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (match vaultDepositIn m callee argVals with
      | .error failure => .done m failure.toCandidateV1
      | .ok m4 =>
          match vaultTransferOut m4 callee argVals occ with
          | .error failure => .done m failure.toCandidateV1
          | .ok m5 => .next (vaultAsyncOut m5 callee argVals)) := by
  cases hdeposit : vaultDepositIn m callee argVals with
  | error failure =>
      simp only [hdeposit]
      cases failure <;>
        simp [ExecResultPreservesCallStackFailureV1,
          LocalFailureV1.toCandidateV1]
  | ok m4 =>
      simp only [hdeposit]
      have hm4 : m4.callable = m.callable ∧ m4.frames = m.frames := by
        have hpreserves := vaultDepositIn_preserves_callStack m callee argVals
        simpa [ExceptMachinePreservesCallStackV1, hdeposit] using hpreserves
      cases htransfer : vaultTransferOut m4 callee argVals occ with
      | error failure =>
          simp only [htransfer]
          cases failure <;>
            simp [ExecResultPreservesCallStackFailureV1,
              LocalFailureV1.toCandidateV1]
      | ok m5 =>
          simp only [htransfer]
          have hm5 :
              m5.callable = m4.callable ∧ m5.frames = m4.frames := by
            have hpreserves :=
              vaultTransferOut_preserves_callStack m4 callee argVals occ
            simpa [ExceptMachinePreservesCallStackV1, htransfer] using hpreserves
          have hasync := vaultAsyncOut_preserves_callStack m5 callee argVals
          exact ⟨hasync.1.trans (hm5.1.trans hm4.1),
            hasync.2.trans (hm5.2.trans hm4.2)⟩

private theorem fromEval_preserves_callStackFailure
    (m : MachineV1) (vid : ValueIdV1)
    (result : Except LocalFailureV1 ReferenceValueV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (fromEval m vid result) := by
  cases result with
  | error failure =>
      cases failure <;>
        simp [fromEval, ExecResultPreservesCallStackFailureV1,
          LocalFailureV1.toCandidateV1]
  | ok value =>
      exact storeResult_preserves_callStackFailure m vid value

private theorem execInstruction_preserves_data
    (m : MachineV1) (instr : InstructionV1) :
    ExecResultPreservesDataV1 m.data (execInstruction m instr) := by
  cases instr
  case mk result op =>
    cases op
    case envRead key args =>
      change ExecResultPreservesDataV1 m.data
        (match result with
        | none => .done m (.trapped .invalidCore)
        | some resultDef =>
            match key with
            | .nativeVaultBalance =>
                if args.isEmpty then
                  storeResult m resultDef.valueId
                    { typeId := resultDef.typeId
                      valueBytes := natToLeBytes m.vaultNative.toNat 8 }
                else
                  .done m (.trapped .invalidCore)
            | .tokenVaultBalance =>
                match lookupArgs m.env args with
                | some #[mintValue] =>
                    match m.data.types[mintValue.typeId.toNat]? with
                    | some { shape := .principal, .. } =>
                        storeResult m resultDef.valueId
                          { typeId := resultDef.typeId
                            valueBytes := natToLeBytes
                              (vaultTokenBalanceV1 m.vaultToken mintValue.valueBytes).toNat 8 }
                    | _ => .done m (.trapped .invalidCore)
                | _ => .done m (.trapped .invalidCore))
      cases result with
      | none => rfl
      | some resultDef =>
          cases key with
          | nativeVaultBalance =>
              change ExecResultPreservesDataV1 m.data
                (if args.isEmpty then
                  storeResult m resultDef.valueId
                    { typeId := resultDef.typeId
                      valueBytes := natToLeBytes m.vaultNative.toNat 8 }
                else
                  .done m (.trapped .invalidCore))
              by_cases hisEmpty : args.isEmpty
              · rw [if_pos hisEmpty]
                exact storeResult_preserves_data m resultDef.valueId _
              · rw [if_neg hisEmpty]
                rfl
          | tokenVaultBalance =>
              change ExecResultPreservesDataV1 m.data
                (match lookupArgs m.env args with
                | some #[mintValue] =>
                    match m.data.types[mintValue.typeId.toNat]? with
                    | some { shape := .principal, .. } =>
                        storeResult m resultDef.valueId
                          { typeId := resultDef.typeId
                            valueBytes := natToLeBytes
                              (vaultTokenBalanceV1 m.vaultToken mintValue.valueBytes).toNat 8 }
                    | _ => .done m (.trapped .invalidCore)
                | _ => .done m (.trapped .invalidCore))
              cases hargs : lookupArgs m.env args with
              | none => rfl
              | some values =>
                  cases values with
                  | mk valuesList =>
                      cases valuesList with
                      | nil => rfl
                      | cons mint rest =>
                          cases rest with
                          | nil =>
                              change ExecResultPreservesDataV1 m.data
                                (match m.data.types[mint.typeId.toNat]? with
                                | some { shape := .principal, .. } =>
                                    storeResult m resultDef.valueId
                                      { typeId := resultDef.typeId
                                        valueBytes := natToLeBytes
                                          (vaultTokenBalanceV1 m.vaultToken
                                            mint.valueBytes).toNat 8 }
                                | _ => .done m (.trapped .invalidCore))
                              cases htype : m.data.types[mint.typeId.toNat]? with
                              | none => rfl
                              | some typeDecl =>
                                  cases typeDecl with
                                  | mk id name shape =>
                                      cases shape <;> try rfl
                                      exact storeResult_preserves_data
                                        m resultDef.valueId _
                          | cons next tail => rfl
    case assert_ condition errorId args =>
      dsimp only [execInstruction]
      repeat
        first
        | rfl
        | split
    case externalCall effectId callee args =>
      dsimp only [execInstruction]
      cases hargs : lookupArgs m.env args with
      | none => rfl
      | some argVals =>
          cases hoccurrence : nextOccurrence m effectId with
          | none => rfl
          | some occurrenceResult =>
              cases occurrenceResult with
              | mk m1 occurrence =>
                  have hm1 : m1.data = m.data := by
                    have hpreserves :=
                      nextOccurrence_preserves_data m effectId
                    simpa [hoccurrence] using hpreserves
                  rw [← hm1]
                  simp only
                  repeat
                    first
                    | rfl
                    | exact storeResult_preserves_data _ _ _
                    | exact returnedVoidVaultPipeline_preserves_data _ _ _ _
                    | split
    all_goals
      dsimp only [execInstruction]
    all_goals
      grind [ExecResultPreservesDataV1,
        nextOccurrence_preserves_data, storeResult_preserves_data,
        vaultTransferOut_preserves_data, vaultDepositIn_preserves_data,
        vaultAsyncOut_preserves_data, fromEval_preserves_data]

private theorem execInstruction_preserves_callStackFailure
    (m : MachineV1) (instr : InstructionV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (execInstruction m instr) := by
  cases instr
  case mk result op =>
    cases op
    case envRead key args =>
      change ExecResultPreservesCallStackFailureV1 m.callable m.frames
        (match result with
        | none => .done m (.trapped .invalidCore)
        | some resultDef =>
            match key with
            | .nativeVaultBalance =>
                if args.isEmpty then
                  storeResult m resultDef.valueId
                    { typeId := resultDef.typeId
                      valueBytes := natToLeBytes m.vaultNative.toNat 8 }
                else
                  .done m (.trapped .invalidCore)
            | .tokenVaultBalance =>
                match lookupArgs m.env args with
                | some #[mintValue] =>
                    match m.data.types[mintValue.typeId.toNat]? with
                    | some { shape := .principal, .. } =>
                        storeResult m resultDef.valueId
                          { typeId := resultDef.typeId
                            valueBytes := natToLeBytes
                              (vaultTokenBalanceV1 m.vaultToken mintValue.valueBytes).toNat 8 }
                    | _ => .done m (.trapped .invalidCore)
                | _ => .done m (.trapped .invalidCore))
      cases result with
      | none => trivial
      | some resultDef =>
          cases key with
          | nativeVaultBalance =>
              change ExecResultPreservesCallStackFailureV1 m.callable m.frames
                (if args.isEmpty then
                  storeResult m resultDef.valueId
                    { typeId := resultDef.typeId
                      valueBytes := natToLeBytes m.vaultNative.toNat 8 }
                else
                  .done m (.trapped .invalidCore))
              by_cases hisEmpty : args.isEmpty
              · rw [if_pos hisEmpty]
                exact storeResult_preserves_callStackFailure
                  m resultDef.valueId _
              · rw [if_neg hisEmpty]
                trivial
          | tokenVaultBalance =>
              change ExecResultPreservesCallStackFailureV1 m.callable m.frames
                (match lookupArgs m.env args with
                | some #[mintValue] =>
                    match m.data.types[mintValue.typeId.toNat]? with
                    | some { shape := .principal, .. } =>
                        storeResult m resultDef.valueId
                          { typeId := resultDef.typeId
                            valueBytes := natToLeBytes
                              (vaultTokenBalanceV1 m.vaultToken
                                mintValue.valueBytes).toNat 8 }
                    | _ => .done m (.trapped .invalidCore)
                | _ => .done m (.trapped .invalidCore))
              cases hargs : lookupArgs m.env args with
              | none => trivial
              | some values =>
                  cases values with
                  | mk valuesList =>
                      cases valuesList with
                      | nil => trivial
                      | cons mint rest =>
                          cases rest with
                          | nil =>
                              change ExecResultPreservesCallStackFailureV1
                                m.callable m.frames
                                (match m.data.types[mint.typeId.toNat]? with
                                | some { shape := .principal, .. } =>
                                    storeResult m resultDef.valueId
                                      { typeId := resultDef.typeId
                                        valueBytes := natToLeBytes
                                          (vaultTokenBalanceV1 m.vaultToken
                                            mint.valueBytes).toNat 8 }
                                | _ => .done m (.trapped .invalidCore))
                              cases htype : m.data.types[mint.typeId.toNat]? with
                              | none => trivial
                              | some typeDecl =>
                                  cases typeDecl with
                                  | mk id name shape =>
                                      cases shape <;> try trivial
                                      exact storeResult_preserves_callStackFailure
                                        m resultDef.valueId _
                          | cons next tail => trivial
    case assert_ condition errorId args =>
      dsimp only [execInstruction]
      repeat
        first
        | trivial
        | split
    case externalCall effectId callee args =>
      dsimp only [execInstruction]
      cases hargs : lookupArgs m.env args with
      | none => trivial
      | some argVals =>
          cases hoccurrence : nextOccurrence m effectId with
          | none => trivial
          | some occurrenceResult =>
              cases occurrenceResult with
              | mk m1 occurrence =>
                  have hm1 :
                      m1.callable = m.callable ∧ m1.frames = m.frames := by
                    have hpreserves :=
                      nextOccurrence_preserves_callStack m effectId
                    simpa [hoccurrence] using hpreserves
                  rw [← hm1.1, ← hm1.2]
                  simp only
                  repeat
                    first
                    | trivial
                    | exact storeResult_preserves_callStackFailure _ _ _
                    | exact
                        returnedVoidVaultPipeline_preserves_callStackFailure
                          _ _ _ _
                    | split
    all_goals
      dsimp only [execInstruction]
    all_goals
      grind [ExecResultPreservesCallStackFailureV1,
        nextOccurrence_preserves_callStack,
        storeResult_preserves_callStackFailure,
        vaultTransferOut_preserves_callStack,
        vaultDepositIn_preserves_callStack,
        vaultAsyncOut_preserves_callStack,
        fromEval_preserves_callStackFailure]

private theorem bindJumpTarget_preserves_data
    (m : MachineV1) (target : JumpTargetV1) :
    ExecResultPreservesDataV1 m.data (bindJumpTarget m target) := by
  unfold bindJumpTarget
  cases hblock : m.callable.blocks[target.blockId.toNat]? with
  | none =>
      simp only
      rfl
  | some block =>
      simp only
      split <;> try rfl
      cases hedge : noteBackEdge m m.blockId target.blockId with
      | done m' candidate =>
          simp only
          have hpreserves :=
            noteBackEdge_preserves_data m m.blockId target.blockId
          simpa [ExecResultPreservesDataV1, hedge] using hpreserves
      | next mEdge =>
          simp only
          have hmEdge : mEdge.data = m.data := by
            have hpreserves :=
              noteBackEdge_preserves_data m m.blockId target.blockId
            simpa [ExecResultPreservesDataV1, hedge] using hpreserves
          simp only [Id.run_bind, Id.run_pure]
          split
          · exact hmEdge
          · simp only [Id.run_bind, Id.run_pure]
            split <;> exact hmEdge

private theorem bindJumpTarget_preserves_callStackFailure
    (m : MachineV1) (target : JumpTargetV1) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (bindJumpTarget m target) := by
  unfold bindJumpTarget
  cases hblock : m.callable.blocks[target.blockId.toNat]? with
  | none =>
      trivial
  | some block =>
      simp only
      split <;> try trivial
      cases hedge : noteBackEdge m m.blockId target.blockId with
      | done m' candidate =>
          have hpreserves :=
            noteBackEdge_preserves_callStackFailure
              m m.blockId target.blockId
          simpa [ExecResultPreservesCallStackFailureV1, hedge]
            using hpreserves
      | next mEdge =>
          have hmEdge :
              mEdge.callable = m.callable ∧ mEdge.frames = m.frames := by
            have hpreserves :=
              noteBackEdge_preserves_callStackFailure
                m m.blockId target.blockId
            simpa [ExecResultPreservesCallStackFailureV1, hedge]
              using hpreserves
          simp only [Id.run_bind, Id.run_pure]
          split
          · first | trivial | exact hmEdge
          · simp only [Id.run_bind, Id.run_pure]
            split <;> first | trivial | exact hmEdge

private theorem execTerminator_preserves_data
    (m : MachineV1) (term : TerminatorV1) :
    ExecResultPreservesDataV1 m.data (execTerminator m term) := by
  cases term <;> dsimp only [execTerminator]
  all_goals
    repeat
      first
      | rfl
      | exact bindJumpTarget_preserves_data _ _
      | split

private theorem bindJumpTarget_terminatorContract
    (m : MachineV1) (target : JumpTargetV1) :
    ExecTerminatorContractV1 m (bindJumpTarget m target) := by
  have hpreserves := bindJumpTarget_preserves_callStackFailure m target
  cases hbind : bindJumpTarget m target with
  | next after =>
      simpa [ExecTerminatorContractV1,
        ExecResultPreservesCallStackFailureV1, hbind] using hpreserves
  | done after candidate =>
      cases candidate with
      | returned value =>
          have : False := by
            simpa [ExecResultPreservesCallStackFailureV1, hbind]
              using hpreserves
          contradiction
      | reverted reason => trivial
      | trapped fault => trivial

private theorem execTerminator_contract
    (m : MachineV1) (term : TerminatorV1) :
    ExecTerminatorContractV1 m (execTerminator m term) := by
  cases term <;> dsimp only [execTerminator]
  all_goals
    repeat
      first
      | trivial
      | exact bindJumpTarget_terminatorContract _ _
      | exact (referenceResultConformsV1_none_iff _ _).2 (by assumption)
      | exact (referenceResultConformsV1_some_iff _ _ _).2
          ⟨by assumption, by assumption, by assumption⟩
      | split
  all_goals
    apply (referenceResultConformsV1_some_iff _ _ _).2
    refine ⟨Bool.eq_false_iff.mpr (by assumption), ?_, ?_⟩
    all_goals simp_all

private theorem execTerminator_preserves_callStackFailure_of_not_return
    (m : MachineV1) (term : TerminatorV1)
    (hnotReturn : ∀ value, term ≠ .return_ value) :
    ExecResultPreservesCallStackFailureV1 m.callable m.frames
      (execTerminator m term) := by
  cases term <;> dsimp only [execTerminator]
  case return_ value => exact False.elim (hnotReturn value rfl)
  all_goals
    repeat
      first
      | trivial
      | exact bindJumpTarget_preserves_callStackFailure _ _
      | split

/-- Fuel-bounded body interpreter (engineering; not formal `step`). -/
def runMachine (chargeFrameEntry : Bool) :
    (fuel : Nat) → MachineV1 → Nat × MachineV1 × CandidateV1
  | 0, m => (0, m, .trapped .resourceExhausted)
  | fuel + 1, m =>
      match m.callable.blocks[m.blockId.toNat]? with
      | none => (0, m, .trapped .invalidCore)
      | some block =>
          if m.instrIdx < block.instructions.size then
            match block.instructions[m.instrIdx]? with
            | none => (0, m, .trapped .internalInvariant)
            | some instr =>
                match instr.result, instr.op with
                | some resultDef, .pureCall calleeId argVids =>
                    -- Push a pure-fn call frame: bind params into a fresh env
                    -- and enter the callee. One fuel step for the call itself.
                    match m.data.callables[calleeId.toNat]? with
                    | none => (0, m, .trapped .invalidCore)
                    | some callee =>
                        if callee.kind != .pureFn ||
                            resultDef.typeId != callee.result.typeId ||
                            argVids.size != callee.params.size then
                          (0, m, .trapped .invalidCore)
                        else
                        match lookupArgs m.env argVids with
                        | none => (0, m, .trapped .invalidCore)
                        | some argVals =>
                            let envSize := maxValueIdInCallable callee + 1
                            let bound := Id.run do
                              let mut env := emptyEnv envSize
                              let mut i : Nat := 0
                              for p in callee.params do
                                match argVals[i]? with
                                | none => return none
                                | some arg =>
                                    if arg.typeId != p.typeId || !valueCanonical m.data arg then
                                      return none
                                    else
                                      match envSet env p.valueId arg with
                                      | none => return none
                                      | some env' => env := env'
                                i := i + 1
                              pure (some env)
                            match bound with
                            | none => (0, m, .trapped .invalidCore)
                            | some calleeEnv =>
                                let frame : CallFrameV1 := {
                                  callable := m.callable
                                  env := m.env
                                  loopCounts := m.loopCounts
                                  blockId := m.blockId
                                  instrIdx := m.instrIdx + 1
                                  resultValueId := resultDef.valueId
                                }
                                let calleeMachine := { m with
                                  callable := callee
                                  env := calleeEnv
                                  loopCounts := Array.replicate callee.loopBounds.size (0 : UInt32)
                                  blockId := callee.entryBlock
                                  instrIdx := 0
                                  frames := m.frames.push frame }
                                -- Formal invariant fuel separately carries the
                                -- callee frame-entry step. The ordinary engineering
                                -- runner preserves its pre-existing fixed-cap policy.
                                if chargeFrameEntry then
                                  match fuel with
                                  | 0 => (0, calleeMachine, .trapped .resourceExhausted)
                                  | calleeFuel + 1 =>
                                      runMachine chargeFrameEntry calleeFuel calleeMachine
                                else
                                  runMachine chargeFrameEntry fuel calleeMachine
                | _, _ =>
                    match execInstruction m instr with
                    | .done m' cand => (0, m', cand)
                    | .next m1 =>
                        runMachine chargeFrameEntry fuel
                          { m1 with instrIdx := m1.instrIdx + 1 }
          else
            match block.terminator, m.frames.back? with
            | .return_ value?, some frame =>
                -- Pop the pure-call frame: the callee result continues the
                -- suspended caller. Unit is represented by canonical empty
                -- bytes in the caller's required PureCall result slot.
                let result? : Option ReferenceValueV1 :=
                  match value? with
                  | none =>
                      if isUnitType m.data m.callable.result.typeId then
                        some { typeId := m.callable.result.typeId, valueBytes := ByteArray.empty }
                      else none
                  | some vid =>
                      if isUnitType m.data m.callable.result.typeId then none
                      else
                        match envGet m.env vid with
                        | some v =>
                            if v.typeId == m.callable.result.typeId && valueCanonical m.data v then
                              some v
                            else none
                        | none => none
                match result? with
                | none => (0, m, .trapped .invalidCore)
                | some result =>
                    match envSet frame.env frame.resultValueId result with
                    | none => (0, m, .trapped .invalidCore)
                    | some env' =>
                        runMachine chargeFrameEntry fuel { m with
                          callable := frame.callable
                          env := env'
                          loopCounts := frame.loopCounts
                          blockId := frame.blockId
                          instrIdx := frame.instrIdx
                          frames := m.frames.pop }
            | _, _ =>
                match execTerminator m block.terminator with
                | .done m' cand => (0, m', cand)
                | .next mNext => runMachine chargeFrameEntry fuel mNext

/-- Body execution never replaces the structure-validated semantic data
    carried by its initial machine. -/
theorem runMachine_data_eq
    (chargeFrameEntry : Bool) (fuel : Nat) (m : MachineV1) :
    (runMachine chargeFrameEntry fuel m).2.1.data = m.data := by
  induction fuel using Nat.strongRecOn generalizing m with
  | ind totalFuel ih =>
      cases totalFuel with
      | zero => rfl
      | succ fuel =>
          have instructionTail (instr : InstructionV1) :
              (match execInstruction m instr with
              | .done m' cand => (0, m', cand)
              | .next m1 =>
                  runMachine chargeFrameEntry fuel
                    { m1 with instrIdx := m1.instrIdx + 1 }).2.1.data =
                m.data := by
            cases hexec : execInstruction m instr with
            | done m' candidate =>
                have hpreserves := execInstruction_preserves_data m instr
                simpa [ExecResultPreservesDataV1, hexec] using hpreserves
            | next m1 =>
                have hm1 : m1.data = m.data := by
                  have hpreserves := execInstruction_preserves_data m instr
                  simpa [ExecResultPreservesDataV1, hexec] using hpreserves
                exact (ih fuel (Nat.lt_succ_self fuel)
                  { m1 with instrIdx := m1.instrIdx + 1 }).trans hm1
          have terminatorTail (term : TerminatorV1) :
              (match execTerminator m term with
              | .done m' cand => (0, m', cand)
              | .next mNext =>
                  runMachine chargeFrameEntry fuel mNext).2.1.data =
                m.data := by
            cases hterm : execTerminator m term with
            | done m' candidate =>
                have hpreserves := execTerminator_preserves_data m term
                simpa [ExecResultPreservesDataV1, hterm] using hpreserves
            | next mNext =>
                have hmNext : mNext.data = m.data := by
                  have hpreserves := execTerminator_preserves_data m term
                  simpa [ExecResultPreservesDataV1, hterm] using hpreserves
                exact (ih fuel (Nat.lt_succ_self fuel) mNext).trans hmNext
          simp only [runMachine]
          cases hblock : m.callable.blocks[m.blockId.toNat]? with
          | none => rfl
          | some block =>
              simp only
              by_cases hinstructions : m.instrIdx < block.instructions.size
              · rw [if_pos hinstructions]
                cases hinstr : block.instructions[m.instrIdx]? with
                | none => rfl
                | some instr =>
                    simp only
                    cases hresult : instr.result with
                    | none =>
                        simpa [hresult] using instructionTail instr
                    | some resultDef =>
                        cases hop : instr.op <;>
                          try { simpa [hresult, hop] using instructionTail instr }
                        case pureCall calleeId argVids =>
                          simp only
                          cases hcallee : m.data.callables[calleeId.toNat]? with
                          | none => rfl
                          | some callee =>
                              simp only
                              by_cases hvalid :
                                  callee.kind != .pureFn ||
                                    resultDef.typeId != callee.result.typeId ||
                                    argVids.size != callee.params.size
                              · rw [if_pos hvalid]
                              · rw [if_neg hvalid]
                                cases hargs : lookupArgs m.env argVids with
                                | none => rfl
                                | some argVals =>
                                    simp only
                                    generalize hbound :
                                        (Id.run do
                                          let mut env := emptyEnv
                                            (maxValueIdInCallable callee + 1)
                                          let mut i : Nat := 0
                                          for p in callee.params do
                                            match argVals[i]? with
                                            | none => return none
                                            | some arg =>
                                                if arg.typeId != p.typeId ||
                                                    !valueCanonical m.data arg then
                                                  return none
                                                else
                                                  match envSet env p.valueId arg with
                                                  | none => return none
                                                  | some env' => env := env'
                                            i := i + 1
                                          pure (some env)) = bound
                                    cases bound with
                                    | none => rfl
                                    | some calleeEnv =>
                                        cases hcharge : chargeFrameEntry with
                                        | false =>
                                            simp only [Bool.false_eq_true,
                                              ↓reduceIte]
                                            simpa [hcharge] using
                                              ih fuel (Nat.lt_succ_self fuel) _
                                        | true =>
                                            simp only [↓reduceIte]
                                            cases fuel with
                                            | zero => rfl
                                            | succ calleeFuel =>
                                                simpa [hcharge] using
                                                  ih calleeFuel (by omega) _
              · rw [if_neg hinstructions]
                grind (config := { gen := 8 })

/-- Every successful body result conforms to the outermost callable result row
    that was active when execution began. Pure-call frame entry/exit changes
    only the active callable; the proof follows the production frame stack. -/
private theorem runMachine_candidateResultConformsV1
    (chargeFrameEntry : Bool) (fuel : Nat) (m : MachineV1) :
    CandidateResultConformsV1 m.data (rootCallableResultV1 m)
      (runMachine chargeFrameEntry fuel m).2.2 := by
  induction fuel using Nat.strongRecOn generalizing m with
  | ind totalFuel ih =>
      cases totalFuel with
      | zero => trivial
      | succ fuel =>
          have instructionTail (instr : InstructionV1) :
              CandidateResultConformsV1 m.data (rootCallableResultV1 m)
                (match execInstruction m instr with
                | .done m' cand => (0, m', cand)
                | .next m1 =>
                    runMachine chargeFrameEntry fuel
                      { m1 with instrIdx := m1.instrIdx + 1 }).2.2 := by
            cases hexec : execInstruction m instr with
            | done m' candidate =>
                cases candidate with
                | returned value =>
                    have hpreserves :=
                      execInstruction_preserves_callStackFailure m instr
                    have : False := by
                      simpa [ExecResultPreservesCallStackFailureV1, hexec]
                        using hpreserves
                    contradiction
                | reverted reason => trivial
                | trapped fault => trivial
            | next m1 =>
                have hdata : m1.data = m.data := by
                  have hpreserves := execInstruction_preserves_data m instr
                  simpa [ExecResultPreservesDataV1, hexec] using hpreserves
                have hstack :
                    m1.callable = m.callable ∧ m1.frames = m.frames := by
                  have hpreserves :=
                    execInstruction_preserves_callStackFailure m instr
                  simpa [ExecResultPreservesCallStackFailureV1, hexec]
                    using hpreserves
                have hroot :
                    rootCallableResultV1 m1 = rootCallableResultV1 m :=
                  rootCallableResultV1_eq_of_callStack_eq m m1
                    hstack.1 hstack.2
                have htail := ih fuel (Nat.lt_succ_self fuel)
                  { m1 with instrIdx := m1.instrIdx + 1 }
                have hupdatedRoot :
                    rootCallableResultV1
                        { m1 with instrIdx := m1.instrIdx + 1 } =
                      rootCallableResultV1 m := by
                  apply rootCallableResultV1_eq_of_callStack_eq
                  · exact hstack.1
                  · exact hstack.2
                have hconforms := candidateResultConformsV1_congr
                  hdata hupdatedRoot htail
                simpa only [hexec] using hconforms
          have terminatorTail (term : TerminatorV1)
              (hroot : m.callable.result = rootCallableResultV1 m) :
              CandidateResultConformsV1 m.data (rootCallableResultV1 m)
                (match execTerminator m term with
                | .done m' cand => (0, m', cand)
                | .next mNext =>
                    runMachine chargeFrameEntry fuel mNext).2.2 := by
            cases hterm : execTerminator m term with
            | done m' candidate =>
                cases candidate with
                | returned value =>
                    have hcontract := execTerminator_contract m term
                    have hconforms :
                        ReferenceResultConformsV1 m.data
                          m.callable.result value := by
                      simpa [ExecTerminatorContractV1, hterm]
                        using hcontract
                    simpa [CandidateResultConformsV1, hroot] using hconforms
                | reverted reason => trivial
                | trapped fault => trivial
            | next mNext =>
                have hdata : mNext.data = m.data := by
                  have hpreserves := execTerminator_preserves_data m term
                  simpa [ExecResultPreservesDataV1, hterm] using hpreserves
                have hstack :
                    mNext.callable = m.callable ∧
                      mNext.frames = m.frames := by
                  have hcontract := execTerminator_contract m term
                  simpa [ExecTerminatorContractV1, hterm] using hcontract
                have hnextRoot :
                    rootCallableResultV1 mNext = rootCallableResultV1 m :=
                  rootCallableResultV1_eq_of_callStack_eq m mNext
                    hstack.1 hstack.2
                have htail := ih fuel (Nat.lt_succ_self fuel) mNext
                simpa [CandidateResultConformsV1, hdata, hnextRoot] using htail
          have terminatorFailureTail (term : TerminatorV1)
              (hnotReturn : ∀ value, term ≠ .return_ value) :
              CandidateResultConformsV1 m.data (rootCallableResultV1 m)
                (match execTerminator m term with
                | .done m' cand => (0, m', cand)
                | .next mNext =>
                    runMachine chargeFrameEntry fuel mNext).2.2 := by
            cases hterm : execTerminator m term with
            | done m' candidate =>
                cases candidate with
                | returned value =>
                    have hpreserves :=
                      execTerminator_preserves_callStackFailure_of_not_return
                        m term hnotReturn
                    have : False := by
                      simpa [ExecResultPreservesCallStackFailureV1, hterm]
                        using hpreserves
                    contradiction
                | reverted reason => trivial
                | trapped fault => trivial
            | next mNext =>
                have hdata : mNext.data = m.data := by
                  have hpreserves := execTerminator_preserves_data m term
                  simpa [ExecResultPreservesDataV1, hterm] using hpreserves
                have hstack :
                    mNext.callable = m.callable ∧
                      mNext.frames = m.frames := by
                  have hpreserves :=
                    execTerminator_preserves_callStackFailure_of_not_return
                      m term hnotReturn
                  simpa [ExecResultPreservesCallStackFailureV1, hterm]
                    using hpreserves
                have hnextRoot :
                    rootCallableResultV1 mNext = rootCallableResultV1 m :=
                  rootCallableResultV1_eq_of_callStack_eq m mNext
                    hstack.1 hstack.2
                have htail := ih fuel (Nat.lt_succ_self fuel) mNext
                simpa [CandidateResultConformsV1, hdata, hnextRoot] using htail
          simp only [runMachine]
          cases hblock : m.callable.blocks[m.blockId.toNat]? with
          | none => trivial
          | some block =>
              simp only
              by_cases hinstructions : m.instrIdx < block.instructions.size
              · rw [if_pos hinstructions]
                cases hinstr : block.instructions[m.instrIdx]? with
                | none => trivial
                | some instr =>
                    simp only
                    cases hresult : instr.result with
                    | none =>
                        simpa [hresult] using instructionTail instr
                    | some resultDef =>
                        cases hop : instr.op <;>
                          try { simpa [hresult, hop] using instructionTail instr }
                        case pureCall calleeId argVids =>
                          simp only
                          cases hcallee : m.data.callables[calleeId.toNat]? with
                          | none => trivial
                          | some callee =>
                              simp only
                              by_cases hvalid :
                                  callee.kind != .pureFn ||
                                    resultDef.typeId != callee.result.typeId ||
                                    argVids.size != callee.params.size
                              · rw [if_pos hvalid]
                                trivial
                              · rw [if_neg hvalid]
                                cases hargs : lookupArgs m.env argVids with
                                | none => trivial
                                | some argVals =>
                                    simp only
                                    generalize hbound :
                                        (Id.run do
                                          let mut env := emptyEnv
                                            (maxValueIdInCallable callee + 1)
                                          let mut i : Nat := 0
                                          for p in callee.params do
                                            match argVals[i]? with
                                            | none => return none
                                            | some arg =>
                                                if arg.typeId != p.typeId ||
                                                    !valueCanonical m.data arg then
                                                  return none
                                                else
                                                  match envSet env p.valueId arg with
                                                  | none => return none
                                                  | some env' => env := env'
                                            i := i + 1
                                          pure (some env)) = bound
                                    cases bound with
                                    | none => trivial
                                    | some calleeEnv =>
                                        let frame : CallFrameV1 := {
                                          callable := m.callable
                                          env := m.env
                                          loopCounts := m.loopCounts
                                          blockId := m.blockId
                                          instrIdx := m.instrIdx + 1
                                          resultValueId := resultDef.valueId
                                        }
                                        let calleeMachine : MachineV1 := { m with
                                          callable := callee
                                          env := calleeEnv
                                          loopCounts := Array.replicate
                                            callee.loopBounds.size (0 : UInt32)
                                          blockId := callee.entryBlock
                                          instrIdx := 0
                                          frames := m.frames.push frame }
                                        have hroot :
                                            rootCallableResultV1 calleeMachine =
                                              rootCallableResultV1 m := by
                                          exact rootCallableResultV1_enterPureCall
                                            m callee calleeEnv frame rfl
                                        cases hcharge : chargeFrameEntry with
                                        | false =>
                                            simp only [Bool.false_eq_true,
                                              ↓reduceIte]
                                            have htail := ih fuel
                                              (Nat.lt_succ_self fuel) calleeMachine
                                            simpa [hcharge, frame, calleeMachine,
                                              CandidateResultConformsV1, hroot]
                                              using htail
                                        | true =>
                                            simp only [↓reduceIte]
                                            cases fuel with
                                            | zero => trivial
                                            | succ calleeFuel =>
                                                have htail := ih calleeFuel
                                                  (by omega) calleeMachine
                                                simpa [hcharge, frame,
                                                  calleeMachine,
                                                  CandidateResultConformsV1,
                                                  hroot] using htail
              · rw [if_neg hinstructions]
                cases hterm : block.terminator with
                | jump target =>
                    simpa [hterm] using
                      terminatorFailureTail (.jump target) (by simp)
                | branch condition thenTarget elseTarget =>
                    simpa [hterm] using
                      terminatorFailureTail
                        (.branch condition thenTarget elseTarget) (by simp)
                | switch scrut cases defaultTarget =>
                    simpa [hterm] using
                      terminatorFailureTail
                        (.switch scrut cases defaultTarget) (by simp)
                | return_ valueId =>
                    cases hback : m.frames.back? with
                    | none =>
                        have hframes : m.frames = #[] :=
                          Array.back?_eq_none_iff.mp hback
                        have hroot :
                            m.callable.result = rootCallableResultV1 m := by
                          unfold rootCallableResultV1
                          rw [hframes]
                          rfl
                        simpa [hterm, hback] using
                          terminatorTail (.return_ valueId) hroot
                    | some frame =>
                        simp only [hterm, hback]
                        generalize hresult :
                            (match valueId with
                            | none =>
                                if isUnitType m.data
                                    m.callable.result.typeId then
                                  some ({
                                    typeId := m.callable.result.typeId
                                    valueBytes := ByteArray.empty
                                  } : ReferenceValueV1)
                                else none
                            | some vid =>
                                if isUnitType m.data
                                    m.callable.result.typeId then
                                  none
                                else
                                  match envGet m.env vid with
                                  | some value =>
                                      if value.typeId ==
                                          m.callable.result.typeId &&
                                          valueCanonical m.data value then
                                        some value
                                      else none
                                  | none => none) = result?
                        cases result? with
                        | none => simp [hresult, CandidateResultConformsV1]
                        | some result =>
                            simp only [hresult]
                            cases henv : envSet frame.env
                                frame.resultValueId result with
                            | none => simp [CandidateResultConformsV1]
                            | some env' =>
                                let callerMachine : MachineV1 := { m with
                                  callable := frame.callable
                                  env := env'
                                  loopCounts := frame.loopCounts
                                  blockId := frame.blockId
                                  instrIdx := frame.instrIdx
                                  frames := m.frames.pop }
                                have hcallerRoot :
                                    rootCallableResultV1 callerMachine =
                                      rootCallableResultV1 m := by
                                  exact rootCallableResultV1_leavePureCall
                                    m frame env' hback
                                have hcallerData : callerMachine.data = m.data := rfl
                                have htail := ih fuel (Nat.lt_succ_self fuel)
                                  callerMachine
                                rw [hcallerRoot, hcallerData] at htail
                                exact htail
                | revert errorId args =>
                    simpa [hterm] using
                      terminatorFailureTail (.revert errorId args) (by simp)
                | trap code =>
                    simpa [hterm] using
                      terminatorFailureTail (.trap code) (by simp)

/-- A completed top-level machine can expose only the canonical production
    result carrier declared by its callable. The empty-frame premise marks a
    top-level invocation; nested PureCall frames are discharged internally. -/
theorem runMachine_returned_resultConformsV1_of_empty_frames
    (chargeFrameEntry : Bool)
    (fuel : Nat)
    (m : MachineV1)
    (value : Option ReferenceValueV1)
    (hframes : m.frames = #[])
    (hrun :
      (runMachine chargeFrameEntry fuel m).2.2 = .returned value) :
    ReferenceResultConformsV1 m.data m.callable.result value := by
  have hconforms :=
    runMachine_candidateResultConformsV1 chargeFrameEntry fuel m
  rw [hrun] at hconforms
  simpa [CandidateResultConformsV1, rootCallableResultV1, hframes]
    using hconforms

/-! ### Invocation validation -/

private def logicalStateBytesEq (a b : LogicalStateV1) : Bool :=
  a.initialized == b.initialized && bytesEqual a.canonicalValues b.canonicalValues

/-- Gate after shape check: lifecycle candidates still subject to response
    exhaustion; only invalidInvocation bypasses the cursor.

    Public for contract-agnostic L1 preservation step packaging;
    sole production authority remains `stepReferenceSliceV1`. -/
inductive InvocationGateV1 where
  | invalidInvocation
  | lifecycle (cand : CandidateV1)
  | ready
      (callable : CallableV1)
      (overlay : Array ByteArray)
      (context : Array ContextInputV1)
      (isInitializer : Bool)

private def compareBytesLex (left right : ByteArray) : Ordering := Id.run do
  let common := Nat.min left.size right.size
  for i in [:common] do
    let l := left[i]!
    let r := right[i]!
    if l < r then return .lt
    if l > r then return .gt
  pure (compare left.size right.size)

private def compareContextKey (left right : SchemaId) : Ordering :=
  compareBytesLex left.value.toUTF8 right.value.toUTF8

/-- Collect the exact ContextRead key/type set reachable from the selected
    invocation root through static PureCall edges. Wire validation has already
    proved that every edge targets an in-range pureFn and that equal keys use
    one TypeId; this bounded traversal rechecks both facts fail closed. -/
private def requiredInvocationContext
    (data : SemanticProgramDataV1) (root : CallableV1) :
    Option (Array (SchemaId × TypeIdV1)) := Id.run do
  let mut visited := Array.replicate data.callables.size false
  let rootIndex := root.id.toNat
  if h : rootIndex < visited.size then
    visited := visited.set rootIndex true
  else
    return none
  let mut worklist : Array Nat := #[rootIndex]
  let mut cursor : Nat := 0
  let mut required : Array (SchemaId × TypeIdV1) := #[]
  while cursor < worklist.size do
    let callerIndex := worklist[cursor]!
    cursor := cursor + 1
    match data.callables[callerIndex]? with
    | none => return none
    | some caller =>
        for block in caller.blocks do
          for instr in block.instructions do
            match instr.op with
            | .contextRead key =>
                match instr.result with
                | none => return none
                | some vd =>
                    match required.find? fun row => row.1 == key with
                    | none => required := required.push (key, vd.typeId)
                    | some row => if row.2 != vd.typeId then return none
            | .pureCall calleeId _ =>
                let calleeIndex := calleeId.toNat
                match data.callables[calleeIndex]? with
                | none => return none
                | some callee =>
                    if callee.kind != .pureFn then return none
                    if h : calleeIndex < visited.size then
                      unless visited[calleeIndex]! do
                        visited := visited.set calleeIndex true
                        worklist := worklist.push calleeIndex
                    else
                      return none
            | _ => pure ()
  pure (some (required.qsort fun left right =>
    compareContextKey left.1 right.1 == .lt))

/-- Validate canonical key order and exact key/type/value membership, returning
    the supplied immutable snapshot unchanged for machine execution. -/
private def validateInvocationContext
    (data : SemanticProgramDataV1) (root : CallableV1)
    (supplied : Array ContextInputV1) : Option (Array ContextInputV1) :=
  match requiredInvocationContext data root with
  | none => none
  | some required => Id.run do
      let mut previous : Option SchemaId := none
      for row in supplied do
        match previous with
        | some key =>
            unless compareContextKey key row.key == .lt do return none
        | none => pure ()
        previous := some row.key
      unless supplied.size == required.size do return none
      for i in [:required.size] do
        match required[i]?, supplied[i]? with
        | some expected, some actual =>
            unless actual.key == expected.1 &&
                actual.value.typeId == expected.2 &&
                valueCanonical data actual.value do
              return none
        | _, _ => return none
      pure (some supplied)

/-- Sole production invocation gate (shape + lifecycle + decode overlay).
    Shape checks → invalidInvocation; lifecycle halt → lifecycle candidate;
    success → ready. Public for L1 preservation step packing. -/
def gateInvocation
    (admitted : AdmittedReferenceSliceV1) (pre : LogicalStateV1)
    (invocation : InvocationV1) : InvocationGateV1 :=
  let data := admitted.data
  let program := admitted.program
  match data.callables[invocation.callableId.toNat]? with
    | none => .invalidInvocation
    | some callable =>
        let kindOk :=
          callable.kind == .initializer ||
          callable.kind == .entry ||
          callable.kind == .view
        if !kindOk then
          .invalidInvocation
        else if invocation.args.size != callable.params.size then
          .invalidInvocation
        else
          let argsOk : Bool := Id.run do
            let mut argsOk : Bool := true
            let mut i : Nat := 0
            for p in callable.params do
              if argsOk then
                match invocation.args[i]? with
                | none => argsOk := false
                | some arg =>
                    if arg.typeId != p.typeId || !valueCanonical data arg then
                      argsOk := false
              i := i + 1
            pure argsOk
          if !argsOk then
            .invalidInvocation
          else
            match validateInvocationContext data callable invocation.context with
            | none => .invalidInvocation
            | some context =>
                let isInit := callable.kind == .initializer
                match initialLogicalStateV1 program with
                | .error _ =>
                    -- Admitted program always validates; treat as lifecycle fault.
                    .lifecycle (.trapped .internalInvariant)
                | .ok initial =>
                    if isInit then
                      if logicalStateBytesEq pre initial then
                        match decodeLogicalStateValuesV1 data pre with
                        | .ok overlay => .ready callable overlay context true
                        | .error _ =>
                            .lifecycle (.trapped .internalInvariant)
                      else if pre.initialized && stateConformsBoolV1 program pre then
                        .lifecycle (.reverted (.standard .alreadyInitialized))
                      else
                        .invalidInvocation
                    else if pre.initialized && stateConformsBoolV1 program pre then
                      match decodeLogicalStateValuesV1 data pre with
                      | .ok overlay => .ready callable overlay context false
                      | .error _ =>
                          .lifecycle (.trapped .internalInvariant)
                    else if logicalStateBytesEq pre initial then
                      .lifecycle (.reverted (.standard .uninitialized))
                    else
                      .invalidInvocation

/-- Lifecycle / terminal candidates with cursor==0: any trailing responses
    override to invalidExternalResponse (same finalizer rule as body halt). -/
private def finalizeLifecycle
    (pre : LogicalStateV1) (responses : ExternalResponsesV1)
    (cand : CandidateV1) : OutcomeV1 :=
  if responses.size != 0 then
    .trapped .invalidExternalResponse pre
  else
    match cand with
    | .trapped fault => .trapped fault pre
    | .reverted reason => .reverted reason pre
    | .returned _ => .trapped .internalInvariant pre

/-- Pure total admitted-slice step (engineering; not formal `step`). -/
def stepReferenceSliceV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {}) : OutcomeV1 :=
  match gateInvocation admitted pre invocation with
  -- Shape failure: ignore responses entirely (cursor never starts).
  | .invalidInvocation => .trapped .invalidInvocation pre
  -- Valid invocation shape; lifecycle halt still exhausts responses.
  | .lifecycle cand => finalizeLifecycle pre responses cand
  | .ready callable overlay context isInitializer =>
      let envSize := maxValueIdInCallable callable + 1
      let bindResult : Option (Array (Option ReferenceValueV1)) := Id.run do
        let mut env := emptyEnv envSize
        let mut i : Nat := 0
        for p in callable.params do
          match invocation.args[i]? with
          | none => return none
          | some arg =>
              match envSet env p.valueId arg with
              | none => return none
              | some env' => env := env'
          i := i + 1
        pure (some env)
      match bindResult with
      | none =>
          -- Valid invocation reached bind; treat as lifecycle internal fault.
          finalizeLifecycle pre responses (.trapped .internalInvariant)
      | some env =>
          let effCap := maxEffectIdInCallable callable + 1
          let m0 : MachineV1 := {
            data := admitted.data
            pre
            callable
            isInitializer
            context
            overlay
            env
            effects := #[]
            occCounts := Array.replicate effCap (0 : UInt32)
            responseCursor := 0
            responses
            loopCounts := Array.replicate callable.loopBounds.size (0 : UInt32)
            blockId := callable.entryBlock
            instrIdx := 0
            frames := #[]
            vaultNative := vaultSeed.native
            vaultToken := vaultSeed.token
          }
          let (_fuelLeft, mEnd, cand) := runMachine false 1000000 m0
          finalize mEnd cand pre

private theorem finalizeLifecycle_failureStateUnchangedV1
    (pre : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (cand : CandidateV1) :
    OutcomeFailureStateUnchangedV1 pre (finalizeLifecycle pre responses cand) := by
  unfold finalizeLifecycle
  cases h : (responses.size != 0) with
  | false =>
      simp only [Bool.false_eq_true, ↓reduceIte]
      cases cand with
      | trapped fault =>
          change OutcomeFailureStateUnchangedV1 pre (.trapped fault pre)
          exact rfl
      | reverted reason =>
          change OutcomeFailureStateUnchangedV1 pre (.reverted reason pre)
          exact rfl
      | returned value =>
          change OutcomeFailureStateUnchangedV1 pre
            (.trapped .internalInvariant pre)
          exact rfl
  | true =>
      simp only [↓reduceIte]
      change OutcomeFailureStateUnchangedV1 pre
        (.trapped .invalidExternalResponse pre)
      exact rfl

private theorem finalize_failureStateUnchangedV1
    (m : MachineV1)
    (cand : CandidateV1)
    (pre : LogicalStateV1) :
    OutcomeFailureStateUnchangedV1 pre (finalize m cand pre) := by
  unfold finalize
  cases h : (m.responseCursor != m.responses.size) with
  | false =>
      simp only [Bool.false_eq_true, ↓reduceIte]
      cases cand with
      | trapped fault =>
          change OutcomeFailureStateUnchangedV1 pre (.trapped fault pre)
          exact rfl
      | reverted reason =>
          change OutcomeFailureStateUnchangedV1 pre (.reverted reason pre)
          exact rfl
      | returned value =>
          cases hencode : encodeLogicalStateValuesV1 m.data
            (pre.initialized || m.isInitializer) m.overlay with
          | error _ =>
              change OutcomeFailureStateUnchangedV1 pre
                (.trapped .internalInvariant pre)
              exact rfl
          | ok post =>
              change OutcomeFailureStateUnchangedV1 pre
                (.returned post value m.effects)
              exact trivial
  | true =>
      simp only [↓reduceIte]
      change OutcomeFailureStateUnchangedV1 pre
        (.trapped .invalidExternalResponse pre)
      exact rfl

/-- A successful final outcome exposes the exact returned candidate and the
    sole production logical-state encoding that produced its post-state. This
    is an inverse law for `finalize`, not another execution path. -/
theorem finalize_returned_implies_encodeV1
    (m : MachineV1)
    (cand : CandidateV1)
    (pre post : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hfinalize : finalize m cand pre = .returned post value effects) :
    cand = .returned value ∧
      m.effects = effects ∧
      encodeLogicalStateValuesV1 m.data
          (pre.initialized || m.isInitializer) m.overlay = .ok post := by
  unfold finalize at hfinalize
  cases hcursor : (m.responseCursor != m.responses.size) with
  | true =>
      simp only [hcursor, ↓reduceIte] at hfinalize
      cases hfinalize
  | false =>
      simp only [hcursor, Bool.false_eq_true, ↓reduceIte] at hfinalize
      cases cand with
      | trapped fault => cases hfinalize
      | reverted reason => cases hfinalize
      | returned returnedValue =>
          cases hencode : encodeLogicalStateValuesV1 m.data
              (pre.initialized || m.isInitializer) m.overlay with
          | error error =>
              simp only [hencode] at hfinalize
              cases hfinalize
          | ok encoded =>
              simp only [hencode] at hfinalize
              cases hfinalize
              exact ⟨rfl, rfl, rfl⟩

/-- Finalization from an initialized pre-state can return only a production-
    conforming post-state for the exact validated machine data. This closes the
    final state-codec seam without asserting that arbitrary machine values were
    created by admission. -/
theorem finalize_returned_stateConformsV1_of_initialized
    (program : SemanticProgramV1)
    (m : MachineV1)
    (cand : CandidateV1)
    (pre post : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hvalidate : validateSemanticProgramV1 program = .ok m.data)
    (hinitialized : pre.initialized = true)
    (hfinalize : finalize m cand pre = .returned post value effects) :
    StateConformsV1 program post := by
  obtain ⟨_hcandidate, _heffects, hencode⟩ :=
    finalize_returned_implies_encodeV1 m cand pre post value effects hfinalize
  have hencodeInitialized :
      encodeLogicalStateValuesV1 m.data true m.overlay = .ok post := by
    simpa [hinitialized] using hencode
  apply stateConformsV1_intro_of_validate_eq_ok
    program m.data post m.overlay hvalidate
  · exact post.initialized_of_encodeLogicalStateValuesV1
      m.data true m.overlay hencodeInitialized
  · exact decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
      m.data true m.overlay post hencodeInitialized

private theorem finalizeLifecycle_ne_returnedV1
    (pre post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (cand : CandidateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1) :
    finalizeLifecycle pre responses cand ≠ .returned post value effects := by
  unfold finalizeLifecycle
  split
  · simp
  · cases cand <;> simp

/-- A successful ready invocation returns exactly the canonical carrier of the
    callable selected by the production invocation gate. This theorem covers
    result encoding only; initializer state lifecycle remains separate from
    initialized entry/view preservation. -/
theorem stepReferenceSliceV1_returned_resultConformsV1
    (admitted : AdmittedReferenceSliceV1)
    (pre post : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1)
    (callable : CallableV1)
    (overlay : Array ByteArray)
    (context : Array ContextInputV1)
    (isInitializer : Bool)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready callable overlay context isInitializer)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
        .returned post value effects) :
    ReferenceResultConformsV1 admitted.data callable.result value := by
  unfold stepReferenceSliceV1 at hstep
  simp only [hgate] at hstep
  generalize hbind :
      (Id.run do
        let mut env := emptyEnv (maxValueIdInCallable callable + 1)
        let mut i : Nat := 0
        for p in callable.params do
          match invocation.args[i]? with
          | none => return none
          | some arg =>
              match envSet env p.valueId arg with
              | none => return none
              | some env' => env := env'
          i := i + 1
        pure (some env)) = bindResult at hstep
  cases bindResult with
  | none =>
      simp only at hstep
      exact False.elim
        (finalizeLifecycle_ne_returnedV1
          pre post responses (.trapped .internalInvariant)
            value effects hstep)
  | some env =>
      simp only at hstep
      let m0 : MachineV1 := {
        data := admitted.data
        pre
        callable
        isInitializer
        context
        overlay
        env
        effects := #[]
        occCounts := Array.replicate
          (maxEffectIdInCallable callable + 1) (0 : UInt32)
        responseCursor := 0
        responses
        loopCounts := Array.replicate callable.loopBounds.size (0 : UInt32)
        blockId := callable.entryBlock
        instrIdx := 0
        frames := #[]
        vaultNative := vaultSeed.native
        vaultToken := vaultSeed.token
      }
      change finalize (runMachine false 1000000 m0).2.1
          (runMachine false 1000000 m0).2.2 pre =
        .returned post value effects at hstep
      obtain ⟨hcandidate, _heffects, _hencode⟩ :=
        finalize_returned_implies_encodeV1
          (runMachine false 1000000 m0).2.1
          (runMachine false 1000000 m0).2.2
          pre post value effects hstep
      have hconforms :=
        runMachine_returned_resultConformsV1_of_empty_frames
          false 1000000 m0 value (by rfl) hcandidate
      simpa [m0] using hconforms

/-- A returned initialized entry/view step preserves production state
    conformance for the exact admitted program. The theorem follows the sole
    executable path (`stepReferenceSliceV1` → `runMachine` → `finalize`) and
    does not introduce a second transition relation. Initializer post-state
    conformance remains a separate lifecycle theorem. -/
theorem stepReferenceSliceV1_returned_stateConformsV1_of_initialized
    (program : SemanticProgramV1)
    (admitted : AdmittedReferenceSliceV1)
    (pre post : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hadmit : admitReferenceProgramSliceV1 program = .ok admitted)
    (hinitialized : pre.initialized = true)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
        .returned post value effects) :
    StateConformsV1 program post := by
  obtain ⟨_hprogram, hvalidate⟩ :=
    admitReferenceProgramSliceV1_ok_implies_validate program admitted hadmit
  unfold stepReferenceSliceV1 at hstep
  cases hgate : gateInvocation admitted pre invocation with
  | invalidInvocation =>
      simp only [hgate] at hstep
      cases hstep
  | lifecycle cand =>
      simp only [hgate] at hstep
      exact False.elim
        (finalizeLifecycle_ne_returnedV1
          pre post responses cand value effects hstep)
  | ready callable overlay context isInitializer =>
      simp only [hgate] at hstep
      generalize hbind :
          (Id.run do
            let mut env := emptyEnv (maxValueIdInCallable callable + 1)
            let mut i : Nat := 0
            for p in callable.params do
              match invocation.args[i]? with
              | none => return none
              | some arg =>
                  match envSet env p.valueId arg with
                  | none => return none
                  | some env' => env := env'
              i := i + 1
            pure (some env)) = bindResult at hstep
      cases bindResult with
      | none =>
          simp only at hstep
          exact False.elim
            (finalizeLifecycle_ne_returnedV1
              pre post responses (.trapped .internalInvariant)
                value effects hstep)
      | some env =>
          simp only at hstep
          let m0 : MachineV1 := {
            data := admitted.data
            pre
            callable
            isInitializer
            context
            overlay
            env
            effects := #[]
            occCounts := Array.replicate
              (maxEffectIdInCallable callable + 1) (0 : UInt32)
            responseCursor := 0
            responses
            loopCounts := Array.replicate callable.loopBounds.size (0 : UInt32)
            blockId := callable.entryBlock
            instrIdx := 0
            frames := #[]
            vaultNative := vaultSeed.native
            vaultToken := vaultSeed.token
          }
          change finalize (runMachine false 1000000 m0).2.1
              (runMachine false 1000000 m0).2.2 pre =
            .returned post value effects at hstep
          have hrunData := runMachine_data_eq false 1000000 m0
          have hvalidateEnd :
              validateSemanticProgramV1 program =
                .ok (runMachine false 1000000 m0).2.1.data := by
            rw [hrunData]
            exact hvalidate
          exact finalize_returned_stateConformsV1_of_initialized
            program (runMachine false 1000000 m0).2.1
              (runMachine false 1000000 m0).2.2
              pre post value effects hvalidateEnd hinitialized hstep

/-- Shape-invalid invocations trap with the exact pre-state. -/
theorem stepReferenceSliceV1_invalidInvocation_eq
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {})
    (hgate : gateInvocation admitted pre invocation = .invalidInvocation) :
    stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
      .trapped .invalidInvocation pre := by
  unfold stepReferenceSliceV1
  rw [hgate]

/-- Lifecycle-gate outcomes finalize with the exact pre-state carrier. -/
theorem stepReferenceSliceV1_lifecycle_eq
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {})
    (cand : CandidateV1)
    (hgate : gateInvocation admitted pre invocation = .lifecycle cand) :
    stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
      finalizeLifecycle pre responses cand := by
  unfold stepReferenceSliceV1
  rw [hgate]

/-- A ready gate recovers the callable row looked up in `admitted.data`, and
    packages `isInitializer` exactly as `callable.kind == .initializer`. -/
theorem gateInvocation_ready_callable_lookup
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (callable : CallableV1)
    (overlay : Array ByteArray)
    (context : Array ContextInputV1)
    (isInitializer : Bool)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready callable overlay context isInitializer) :
    admitted.data.callables[invocation.callableId.toNat]? = some callable ∧
      isInitializer = (callable.kind == CallableKindV1.initializer) := by
  unfold gateInvocation at hgate
  cases hlookup : admitted.data.callables[invocation.callableId.toNat]? with
  | none =>
      simp [hlookup] at hgate
  | some c =>
      simp only [hlookup] at hgate
      cases hkind :
          (c.kind == CallableKindV1.initializer ||
            c.kind == CallableKindV1.entry ||
            c.kind == CallableKindV1.view) with
      | false => simp [hkind] at hgate
      | true =>
          simp only [hkind, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at hgate
          cases harity : (invocation.args.size != c.params.size) with
          | true => simp [harity] at hgate
          | false =>
              simp only [harity, Bool.false_eq_true, ↓reduceIte] at hgate
              generalize hargsOk :
                (Id.run do
                  let mut argsOk : Bool := true
                  let mut i : Nat := 0
                  for p in c.params do
                    if argsOk then
                      match invocation.args[i]? with
                      | none => argsOk := false
                      | some arg =>
                          if arg.typeId != p.typeId ||
                              !valueCanonical admitted.data arg then
                            argsOk := false
                    i := i + 1
                  pure argsOk) = aok at hgate
              cases haok : aok with
              | false => simp [haok] at hgate
              | true =>
                  simp only [hargsOk, haok, Bool.not_true, Bool.false_eq_true,
                    ↓reduceIte] at hgate
                  cases hctx : validateInvocationContext admitted.data c
                      invocation.context with
                  | none => simp [hctx] at hgate
                  | some ctx =>
                      simp only [hctx] at hgate
                      cases hinitLS :
                          initialLogicalStateV1 admitted.program with
                      | error e => simp [hinitLS] at hgate
                      | ok initial =>
                          simp only [hinitLS] at hgate
                          cases his :
                              (c.kind == CallableKindV1.initializer) with
                          | true =>
                              simp only [his, ↓reduceIte] at hgate
                              cases heq : logicalStateBytesEq pre initial with
                              | true =>
                                  simp only [heq, ↓reduceIte] at hgate
                                  cases hdec :
                                      decodeLogicalStateValuesV1
                                        admitted.data pre with
                                  | error e => simp [hdec] at hgate
                                  | ok ov =>
                                      simp only [hdec] at hgate
                                      cases hgate
                                      -- After cases, c = callable and lookup is refl.
                                      exact ⟨rfl, by simp [his]⟩
                              | false =>
                                  simp only [heq, Bool.false_eq_true,
                                    ↓reduceIte] at hgate
                                  cases hconf :
                                      (pre.initialized &&
                                        stateConformsBoolV1 admitted.program
                                          pre) with
                                  | true => simp [hconf] at hgate
                                  | false => simp [hconf] at hgate
                          | false =>
                              simp only [his, Bool.false_eq_true, ↓reduceIte]
                                at hgate
                              cases hconf :
                                  (pre.initialized &&
                                    stateConformsBoolV1 admitted.program pre)
                                with
                              | false =>
                                  simp only [hconf, Bool.false_eq_true,
                                    ↓reduceIte] at hgate
                                  cases heq : logicalStateBytesEq pre initial with
                                  | true => simp [heq] at hgate
                                  | false => simp [heq] at hgate
                              | true =>
                                  simp only [hconf, ↓reduceIte] at hgate
                                  cases hdec :
                                      decodeLogicalStateValuesV1
                                        admitted.data pre with
                                  | error e => simp [hdec] at hgate
                                  | ok ov =>
                                      simp only [hdec] at hgate
                                      cases hgate
                                      exact ⟨rfl, by simp [his]⟩

/-- Non-initializer ready gate is produced only from a successful decode of
    `pre` under initialized+conforming state. -/
theorem gateInvocation_ready_noninit_decode
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (callable : CallableV1)
    (overlay : Array ByteArray)
    (context : Array ContextInputV1)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready callable overlay context false) :
    decodeLogicalStateValuesV1 admitted.data pre = .ok overlay ∧
      pre.initialized = true ∧
      stateConformsBoolV1 admitted.program pre = true := by
  unfold gateInvocation at hgate
  cases hlookup : admitted.data.callables[invocation.callableId.toNat]? with
  | none =>
      simp [hlookup] at hgate
  | some c =>
      simp only [hlookup] at hgate
      cases hkind :
          (c.kind == CallableKindV1.initializer ||
            c.kind == CallableKindV1.entry ||
            c.kind == CallableKindV1.view) with
      | false =>
          simp [hkind] at hgate
      | true =>
          simp only [hkind, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
            at hgate
          cases harity : (invocation.args.size != c.params.size) with
          | true =>
              simp [harity] at hgate
          | false =>
              simp only [harity, Bool.false_eq_true, ↓reduceIte] at hgate
              generalize hargsOk :
                (Id.run do
                  let mut argsOk : Bool := true
                  let mut i : Nat := 0
                  for p in c.params do
                    if argsOk then
                      match invocation.args[i]? with
                      | none => argsOk := false
                      | some arg =>
                          if arg.typeId != p.typeId ||
                              !valueCanonical admitted.data arg then
                            argsOk := false
                    i := i + 1
                  pure argsOk) = aok at hgate
              cases haok : aok with
              | false =>
                  simp [haok] at hgate
              | true =>
                  simp only [hargsOk, haok, Bool.not_true, Bool.false_eq_true,
                    ↓reduceIte] at hgate
                  cases hctx : validateInvocationContext admitted.data c
                      invocation.context with
                  | none =>
                      simp [hctx] at hgate
                  | some ctx =>
                      simp only [hctx] at hgate
                      cases hinitLS :
                          initialLogicalStateV1 admitted.program with
                      | error e =>
                          simp [hinitLS] at hgate
                      | ok initial =>
                          simp only [hinitLS] at hgate
                          cases his :
                              (c.kind == CallableKindV1.initializer) with
                          | true =>
                              -- Ready would set isInitializer=true; contradicts false.
                              simp only [his, ↓reduceIte] at hgate
                              cases heq : logicalStateBytesEq pre initial with
                              | true =>
                                  simp only [heq, ↓reduceIte] at hgate
                                  cases hdec :
                                      decodeLogicalStateValuesV1
                                        admitted.data pre with
                                  | error e =>
                                      simp [hdec] at hgate
                                  | ok ov =>
                                      simp [hdec] at hgate
                              | false =>
                                  simp only [heq, Bool.false_eq_true,
                                    ↓reduceIte] at hgate
                                  cases hconf :
                                      (pre.initialized &&
                                        stateConformsBoolV1 admitted.program
                                          pre) with
                                  | true =>
                                      simp [hconf] at hgate
                                  | false =>
                                      simp [hconf] at hgate
                          | false =>
                              simp only [his, Bool.false_eq_true, ↓reduceIte]
                                at hgate
                              cases hconf :
                                  (pre.initialized &&
                                    stateConformsBoolV1 admitted.program pre)
                                with
                              | false =>
                                  simp only [hconf, Bool.false_eq_true,
                                    ↓reduceIte] at hgate
                                  cases heq : logicalStateBytesEq pre initial with
                                  | true =>
                                      simp [heq] at hgate
                                  | false =>
                                      simp [heq] at hgate
                              | true =>
                                  simp only [hconf, ↓reduceIte] at hgate
                                  cases hdec :
                                      decodeLogicalStateValuesV1
                                        admitted.data pre with
                                  | error e =>
                                      simp [hdec] at hgate
                                  | ok ov =>
                                      simp only [hdec] at hgate
                                      -- ready c ov ctx false = ready callable overlay context false
                                      cases hgate
                                      have hand :
                                          pre.initialized = true ∧
                                            stateConformsBoolV1 admitted.program
                                              pre = true := by
                                        simpa [Bool.and_eq_true] using hconf
                                      exact ⟨rfl, hand.1, hand.2⟩

/-- Nullary ready gate: param bind is the empty env of the callable's max
    value id, then ordinary `runMachine` + `finalize`. -/
theorem stepReferenceSliceV1_ready_nullary_eq
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {})
    (callable : CallableV1)
    (overlay : Array ByteArray)
    (context : Array ContextInputV1)
    (isInitializer : Bool)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready callable overlay context isInitializer)
    (hparams : callable.params = #[]) :
    let m0 : MachineV1 := {
      data := admitted.data
      pre
      callable
      isInitializer
      context
      overlay
      env := emptyEnv (maxValueIdInCallable callable + 1)
      effects := #[]
      occCounts :=
        Array.replicate (maxEffectIdInCallable callable + 1) (0 : UInt32)
      responseCursor := 0
      responses
      loopCounts := Array.replicate callable.loopBounds.size (0 : UInt32)
      blockId := callable.entryBlock
      instrIdx := 0
      frames := #[]
      vaultNative := vaultSeed.native
      vaultToken := vaultSeed.token
    }
    stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
      finalize (runMachine false 1000000 m0).2.1
        (runMachine false 1000000 m0).2.2 pre := by
  let m0 : MachineV1 := {
    data := admitted.data
    pre
    callable
    isInitializer
    context
    overlay
    env := emptyEnv (maxValueIdInCallable callable + 1)
    effects := #[]
    occCounts :=
      Array.replicate (maxEffectIdInCallable callable + 1) (0 : UInt32)
    responseCursor := 0
    responses
    loopCounts := Array.replicate callable.loopBounds.size (0 : UInt32)
    blockId := callable.entryBlock
    instrIdx := 0
    frames := #[]
    vaultNative := vaultSeed.native
    vaultToken := vaultSeed.token
  }
  -- Goal uses the `let m0` from the statement; align with local.
  change stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
    finalize (runMachine false 1000000 m0).2.1
      (runMachine false 1000000 m0).2.2 pre
  unfold stepReferenceSliceV1
  rw [hgate]
  -- Nullary: forIn over `[]` is identity; bind is `some emptyEnv`.
  simp [hparams, m0]

/-- Lifecycle finalization never rewrites the pre-state on trap/revert. -/
theorem finalizeLifecycle_failureStateUnchanged_publicV1
    (pre : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (cand : CandidateV1) :
    OutcomeFailureStateUnchangedV1 pre (finalizeLifecycle pre responses cand) :=
  finalizeLifecycle_failureStateUnchangedV1 pre responses cand

/-- Every production Reference step carries the exact pre-state on revert or
    trap. Failure packaging uses the invocation `pre` argument directly
    (see `finalize` / `finalizeLifecycle`), not a derived machine field. -/
theorem stepReferenceSliceV1_failureStateUnchangedV1
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {}) :
    OutcomeFailureStateUnchangedV1 pre
      (stepReferenceSliceV1 admitted pre invocation responses vaultSeed) := by
  unfold stepReferenceSliceV1
  generalize hgate : gateInvocation admitted pre invocation = gate
  cases gate with
  | invalidInvocation => exact rfl
  | lifecycle cand =>
      exact finalizeLifecycle_failureStateUnchangedV1 pre responses cand
  | ready callable overlay context isInitializer =>
      dsimp only
      generalize hbind : (Id.run do
        let mut env := emptyEnv (maxValueIdInCallable callable + 1)
        let mut i : Nat := 0
        for p in callable.params do
          match invocation.args[i]? with
          | none => return none
          | some arg =>
              match envSet env p.valueId arg with
              | none => return none
              | some env' => env := env'
          i := i + 1
        pure (some env)) = bindResult
      cases bindResult with
      | none =>
          exact finalizeLifecycle_failureStateUnchangedV1 pre responses
            (.trapped .internalInvariant)
      | some env =>
          let m0 : MachineV1 := {
            data := admitted.data
            pre
            callable
            isInitializer
            context
            overlay
            env
            effects := #[]
            occCounts := Array.replicate (maxEffectIdInCallable callable + 1) 0
            responseCursor := 0
            responses
            loopCounts := Array.replicate callable.loopBounds.size 0
            blockId := callable.entryBlock
            instrIdx := 0
            frames := #[]
            vaultNative := vaultSeed.native
            vaultToken := vaultSeed.token
          }
          exact finalize_failureStateUnchangedV1
            (runMachine false 1000000 m0).2.1
            (runMachine false 1000000 m0).2.2
            pre

/-- Reverted outcomes from the sole production step carry the exact pre-state. -/
theorem stepReferenceSliceV1_reverted_state_eq
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {})
    (reason : SemanticRevertV1)
    (unchanged : LogicalStateV1)
    (h :
      stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
        .reverted reason unchanged) :
    unchanged = pre := by
  have hfail :=
    stepReferenceSliceV1_failureStateUnchangedV1 admitted pre invocation
      responses vaultSeed
  rw [h] at hfail
  exact hfail

/-- Trapped outcomes from the sole production step carry the exact pre-state. -/
theorem stepReferenceSliceV1_trapped_state_eq
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vaultSeed : ReferenceVaultSeedV1 := {})
    (fault : SemanticFaultV1)
    (unchanged : LogicalStateV1)
    (h :
      stepReferenceSliceV1 admitted pre invocation responses vaultSeed =
        .trapped fault unchanged) :
    unchanged = pre := by
  have hfail :=
    stepReferenceSliceV1_failureStateUnchangedV1 admitted pre invocation
      responses vaultSeed
  rw [h] at hfail
  exact hfail

/-! ### Invariant reference slice -/

/-- Execute one structure-validated invariant callable using its exact carried
    fuel, without consulting the narrower whole-program engineering admission.

    This lower machine seam deliberately does not select an invariant ordinal
    or validate a `SemanticProgramV1`; those remain responsibilities of its
    upper caller. It defensively checks initialized canonical state, callable
    identity/signature, and carried fuel before constructing the private
    machine. It is not the formal InvariantABI-owned `evalInvariantV1`. -/
def runInvariantCallableV1
    (data : SemanticProgramDataV1)
    (callableId : CallableIdV1)
    (state : LogicalStateV1) : InvariantEvalResultV1 :=
  if !state.initialized then
    .trapped
  else
    match data.callables[callableId.toNat]? with
    | none => .trapped
    | some callable =>
      match callable.invariantSteps with
      | none => .trapped
      | some steps =>
        if callable.kind != .invariant || !callable.params.isEmpty ||
            !callable.loopBounds.isEmpty || !isBoolType data callable.result.typeId then
          .trapped
        else
          match decodeLogicalStateValuesV1 data state with
          | .error _ => .trapped
          | .ok overlay =>
            let m0 : MachineV1 := {
              data
              pre := state
              callable
              isInitializer := false
              context := #[]
              overlay
              env := emptyEnv (maxValueIdInCallable callable + 1)
              effects := #[]
              occCounts := Array.replicate (maxEffectIdInCallable callable + 1) (0 : UInt32)
              responseCursor := 0
              responses := #[]
              loopCounts := #[]
              blockId := callable.entryBlock
              instrIdx := 0
              frames := #[]
              -- Invariant callables cannot env-read (structure gate); the
              -- invariant machine runs with the zero vault.
              vaultNative := 0
              vaultToken := #[]
            }
            -- `invariantSteps` includes the root frame-entry charge in
            -- addition to every instruction, terminator, and callee entry.
            let (_, _, cand) :=
              match steps.toNat with
              | 0 => (0, m0, CandidateV1.trapped .resourceExhausted)
              | machineFuel + 1 => runMachine true machineFuel m0
            match cand with
            | .reverted _ => .reverted
            | .trapped _ => .trapped
            | .returned (some value) =>
                if value.typeId != callable.result.typeId then .trapped
                else if value.valueBytes == encodeU8 1 then .returnedTrue
                else if value.valueBytes == encodeU8 0 then .returnedFalse
                else .trapped
            | .returned none => .trapped

private theorem maxValueIdInCallable_eq_zero_of_single_result_zero
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (op : SemanticOpV1)
    (terminator : TerminatorV1)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId }
        op
      }]
      terminator
    }]) :
    maxValueIdInCallable callable = 0 := by
  simp [maxValueIdInCallable, hparams, hblocks]

/-- Increment-shaped body: four value results (0..3) plus one void store. -/
private theorem maxValueIdInCallable_eq_three_of_increment_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (stateId : StateIdV1)
    (twoBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId }, op := .stateLoad stateId },
        { result := some { valueId := 1, typeId }, op := .literal typeId twoBytes },
        { result := some { valueId := 2, typeId }, op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId }, op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]) :
    maxValueIdInCallable callable = 3 := by
  simp [maxValueIdInCallable, hparams, hblocks]

private theorem maxEffectIdInCallable_eq_zero_of_get_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (stateId : StateIdV1)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]) :
    maxEffectIdInCallable callable = 0 := by
  simp [maxEffectIdInCallable, hparams, hblocks]

private theorem maxEffectIdInCallable_eq_zero_of_increment_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (stateId : StateIdV1)
    (twoBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId }, op := .stateLoad stateId },
        { result := some { valueId := 1, typeId }, op := .literal typeId twoBytes },
        { result := some { valueId := 2, typeId }, op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId }, op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]) :
    maxEffectIdInCallable callable = 0 := by
  simp [maxEffectIdInCallable, hparams, hblocks]

private theorem maxValueIdInCallable_eq_four_of_five_results
    (callable : CallableV1)
    (typeId0 typeId1 typeId2 typeId3 typeId4 : TypeIdV1)
    (op0 op1 op2 op3 op4 : SemanticOpV1)
    (terminator : TerminatorV1)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := typeId0 }, op := op0 },
        { result := some { valueId := 1, typeId := typeId1 }, op := op1 },
        { result := some { valueId := 2, typeId := typeId2 }, op := op2 },
        { result := some { valueId := 3, typeId := typeId3 }, op := op3 },
        { result := some { valueId := 4, typeId := typeId4 }, op := op4 }
      ]
      terminator
    }]) :
    maxValueIdInCallable callable = 4 := by
  simp [maxValueIdInCallable, hparams, hblocks]

private theorem leBytesToNat_zero8 :
    leBytesToNat (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = 0 := by
  simp [leBytesToNat, leBytesToNatList]

private theorem leBytesToNat_two8 :
    leBytesToNat (ByteArray.mk #[2, 0, 0, 0, 0, 0, 0, 0]) = 2 := by
  simp [leBytesToNat, leBytesToNatList]

private theorem natToLeBytes_zero8 :
    natToLeBytes 0 8 = ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0] := by
  simp [natToLeBytes, natToLeBytesList]

private theorem natToLeBytes_two8 :
    natToLeBytes 2 8 = ByteArray.mk #[2, 0, 0, 0, 0, 0, 0, 0] := by
  simp [natToLeBytes, natToLeBytesList]

/-- Closed eight-byte LE zero payload used by the UInt64 parity micro-path. -/
def zero8BytesV1 : ByteArray :=
  ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]

/-- Closed eight-byte LE one payload used by the UInt64 parity micro-path. -/
def one8BytesV1 : ByteArray :=
  ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0]

/-- Closed eight-byte LE two payload used by the UInt64 parity micro-path. -/
def two8BytesV1 : ByteArray :=
  ByteArray.mk #[2, 0, 0, 0, 0, 0, 0, 0]

/-- Public closed LE zero payload decodes to Nat 0. -/
theorem leBytesToNatV1_zero8BytesV1 :
    leBytesToNatV1 zero8BytesV1 = 0 := by
  simpa [zero8BytesV1, leBytesToNatV1] using leBytesToNat_zero8

/-- Public closed LE two payload decodes to Nat 2. -/
theorem leBytesToNatV1_two8BytesV1 :
    leBytesToNatV1 two8BytesV1 = 2 := by
  simpa [two8BytesV1, leBytesToNatV1] using leBytesToNat_two8

/-! ### UInt64 parity invariant micro-path -/

private theorem envSet_of_lt
    (env : Array (Option ReferenceValueV1)) (vid : ValueIdV1)
    (v : ReferenceValueV1) (h : vid.toNat < env.size) :
    envSet env vid v = some (env.set vid.toNat (some v) h) := by
  simp [envSet, h]

private theorem emptyEnv_size (n : Nat) : (emptyEnv n).size = n := by
  simp [emptyEnv]

private theorem evalBinary_mod_uint64_zero_two
    (data : SemanticProgramDataV1) (uint64TypeId : TypeIdV1)
    (htype : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ()) :
    evalBinary data .mod
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
      uint64TypeId =
      .ok { typeId := uint64TypeId, valueBytes := zero8BytesV1 } := by
  have hvcZ :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by simp [valueCanonical, hcanZero]
  have hvcT :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by simp [valueCanonical, hcanTwo]
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hwidth : uintWidth data uint64TypeId = some 64 := by
    simp [uintWidth, shapeOf, htype]
  have hz : leBytesToNat zero8BytesV1 = 0 := by
    simpa [zero8BytesV1] using leBytesToNat_zero8
  have ht : leBytesToNat two8BytesV1 = 2 := by
    simpa [two8BytesV1] using leBytesToNat_two8
  have hnat0 : natToLeBytes 0 8 = zero8BytesV1 := by
    simpa [zero8BytesV1] using natToLeBytes_zero8
  have hnz : ((2 : Nat) == 0) = false := by decide
  simp only [evalBinary, hvcZ, hvcT, htid, Bool.and_self, Bool.and_true,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte, hwidth, intWidth, shapeOf,
    htype, uintByteLen, hz, ht, hnz, hnat0]

private theorem evalBinary_eq_uint64_zero_zero
    (data : SemanticProgramDataV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool }) :
    evalBinary data .eq
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
      boolTypeId =
      .ok { typeId := boolTypeId, valueBytes := encodeU8 1 } := by
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hbool : isBoolType data boolTypeId = true := by
    simp [isBoolType, shapeOf, htypeB]
  have hbeq : (zero8BytesV1 == zero8BytesV1) = true := by
    change (ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0] ==
        ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = true
    decide
  simp only [evalBinary, htid, hbool, bytesEqual, hbeq]
  rfl

private theorem storeResult_envSet
    (m : MachineV1) (vid : ValueIdV1) (v : ReferenceValueV1)
    (env' : Array (Option ReferenceValueV1))
    (hcan : valueCanonical m.data v = true)
    (hset : envSet m.env vid v = some env') :
    storeResult m vid v = .next { m with env := env' } := by
  unfold storeResult
  simp only [hcan, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hset]

/-- Controlled production refinement: nullary UInt64 parity invariant on the
    exact zero overlay (`stateLoad; lit 2; mod; lit 0; eq; return`, fuel 7).
    Sole private machine path; not a second evaluator. -/
theorem runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_zero
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[zero8BytesV1])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .mod 0 1 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 4, typeId := boolTypeId },
            op := .binary .eq 2 3 }
        ]
        terminator := .return_ (some 4)
      }]
      loopBounds := #[]
      invariantSteps := some 7
    })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hcanTrue :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ()) :
    runInvariantCallableV1 data rootId state = .returnedTrue := by
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }]
    loopBounds := #[]
    invariantSteps := some 7
  }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 4 :=
    maxValueIdInCallable_eq_four_of_five_results root
      uint64TypeId uint64TypeId uint64TypeId uint64TypeId boolTypeId
      (.stateLoad stateId) (.literal uint64TypeId two8BytesV1)
      (.binary .mod 0 1) (.literal uint64TypeId zero8BytesV1)
      (.binary .eq 2 3) (.return_ (some 4)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 7 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htypeB]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hseven : 7 % 2 ^ 64 = (7 : Nat) := by decide
  have htrueBytes : (encodeU8 1 == encodeU8 1) = true := by decide
  have hvcZero :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by
    simp [valueCanonical, hcanZero]
  have hvcTwo :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by
    simp [valueCanonical, hcanTwo]
  have hvcTrue :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 1 } =
        true := by
    simp [valueCanonical, hcanTrue]
  have hmod :=
    evalBinary_mod_uint64_zero_two data uint64TypeId htypeU hcanZero hcanTwo
  have heq :=
    evalBinary_eq_uint64_zero_zero data uint64TypeId boolTypeId htypeB
  -- Closed reference values and env chain via sole envSet.
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := two8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v3 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v4 : ReferenceValueV1 :=
    { typeId := boolTypeId, valueBytes := encodeU8 1 }
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 5).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 5).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 5) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 5) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set (2 : ValueIdV1).toNat (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  have hs3 : (3 : ValueIdV1).toNat < e3.size := by
    simp [e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e4 := e3.set (3 : ValueIdV1).toNat (some v3) hs3
  have hset3 : envSet e3 3 v3 = some e4 := by
    simpa [e4] using envSet_of_lt e3 (3 : ValueIdV1) v3 hs3
  have hs4 : (4 : ValueIdV1).toNat < e4.size := by
    simp [e4, e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e5 := e4.set (4 : ValueIdV1).toNat (some v4) hs4
  have hset4 : envSet e4 4 v4 = some e5 := by
    simpa [e5] using envSet_of_lt e4 (4 : ValueIdV1) v4 hs4
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre := state, callable := root, isInitializer := false,
    context := #[], overlay := #[zero8BytesV1], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable root + 1) 0,
    responseCursor := 0, responses := #[], loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := 0, vaultToken := #[]
  }
  -- Gate prefix → candidate extraction over runMachine true 6 m0.
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hseven]
  simp only [Bool.false_eq_true, ↓reduceIte]
  change (match (runMachine true 6 (mk (emptyEnv 5) 0)).2.2 with
    | .reverted _ => InvariantEvalResultV1.reverted
    | .trapped _ => InvariantEvalResultV1.trapped
    | .returned (some value) =>
        if value.typeId != root.result.typeId then .trapped
        else if value.valueBytes == encodeU8 1 then .returnedTrue
        else if value.valueBytes == encodeU8 0 then .returnedFalse
        else .trapped
    | .returned none => .trapped) = .returnedTrue
  have hexec0 :
      execInstruction (mk (emptyEnv 5) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[zero8BytesV1] : Array ByteArray)[stateId.toNat]? =
          some zero8BytesV1 := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty, ↓reduceIte]
    have hstore := storeResult_envSet (mk (emptyEnv 5) 0) 0 v0 e1 hvcZero hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine true 6 (mk (emptyEnv 5) 0) =
      runMachine true 5 (mk e1 1) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := two8BytesV1 } = true := hvcTwo
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2
      (by simpa [mk, v1] using hvcTwo) hset1
  have step1 : runMachine true 5 (mk e1 1) = runMachine true 4 (mk e2 2) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec1]
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 } =
        .next (mk e3 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    have hvc0' : valueCanonical data v0 = true := by simpa [v0] using hvcZero
    have hvc1' : valueCanonical data v1 = true := by simpa [v1] using hvcTwo
    have hmod' : evalBinary data .mod v0 v1 uint64TypeId = .ok v2 := by
      simpa [v0, v1, v2] using hmod
    simp only [mk, execInstruction, hg0, hg1, hvc0', hvc1', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, hmod', fromEval]
    have hstore := storeResult_envSet (mk e2 2) 2 v2 e3
      (by simpa [v2] using hvcZero) hset2
    simpa [mk, e3, v2] using hstore
  have step2 : runMachine true 4 (mk e2 2) = runMachine true 3 (mk e3 3) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec2]
  have hexec3 :
      execInstruction (mk e3 3)
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e4 3) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e3 3) 3 v3 e4
      (by simpa [mk, v3] using hvcZero) hset3
  have step3 : runMachine true 3 (mk e3 3) = runMachine true 2 (mk e4 4) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec3]
  have hexec4 :
      execInstruction (mk e4 4)
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 } =
        .next (mk e5 4) := by
    have hg2 : envGet e4 2 = some v2 := by
      have hne :
          (e3.set (3 : ValueIdV1).toNat (some v3) hs3)[2]? = e3[2]? :=
        Array.getElem?_set_ne hs3 (by decide : (3 : Nat) ≠ 2)
      have h2 : e3[2]? = some (some v2) := Array.getElem?_set_self hs2
      change envGet (e3.set (3 : ValueIdV1).toNat (some v3) hs3) 2 = some v2
      simp [envGet, hne, h2]
    have hg3 : envGet e4 3 = some v3 := by
      have h3 : e4[(3 : ValueIdV1).toNat]? = some (some v3) :=
        Array.getElem?_set_self hs3
      simp [envGet, e4, h3, UInt32.toNat]
    have hvc2' : valueCanonical data v2 = true := by simpa [v2] using hvcZero
    have hvc3' : valueCanonical data v3 = true := by simpa [v3] using hvcZero
    have heq' : evalBinary data .eq v2 v3 boolTypeId = .ok v4 := by
      simpa [v2, v3, v4] using heq
    simp only [mk, execInstruction, hg2, hg3, hvc2', hvc3', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, heq', fromEval]
    have hstore := storeResult_envSet (mk e4 4) 4 v4 e5
      (by simpa [v4] using hvcTrue) hset4
    simpa [mk, e5, v4] using hstore
  have step4 : runMachine true 2 (mk e4 4) = runMachine true 1 (mk e5 5) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec4]
  have hg4 : envGet e5 4 = some v4 := by
    have h4 : e5[(4 : ValueIdV1).toNat]? = some (some v4) :=
      Array.getElem?_set_self hs4
    simp [envGet, e5, h4, UInt32.toNat]
  have hret :
      execTerminator (mk e5 5) (.return_ (some 4)) =
        .done (mk e5 5) (.returned (some v4)) := by
    have hunit : isUnitType data root.result.typeId = false := by
      simp [isUnitType, shapeOf, hrootResult, htypeB]
    have hty :
        (v4.typeId != root.result.typeId || !valueCanonical data v4) = false := by
      have hbeq : (v4.typeId != root.result.typeId) = false := by
        simp [v4, hrootResult, BEq.beq, bne]
      have hcan : valueCanonical data v4 = true := by simpa [v4] using hvcTrue
      simp [hbeq, hcan]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg4, hty, ↓reduceIte, v4]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT : runMachine true 1 (mk e5 5) =
      (0, mk e5 5, CandidateV1.returned (some v4)) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hret]
  rw [step0, step1, step2, step3, step4, stepT]
  -- Returned Bool true closes the invariant runner.
  have htyEq : (v4.typeId != root.result.typeId) = false := by
    simp [v4, hrootResult, BEq.beq, bne]
  simp [htyEq, htrueBytes, v4]

private theorem evalBinary_mod_uint64_even_two
    (data : SemanticProgramDataV1) (uint64TypeId : TypeIdV1)
    (countBytes : ByteArray)
    (htype : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (heven : leBytesToNatV1 countBytes % 2 = 0) :
    evalBinary data .mod
      { typeId := uint64TypeId, valueBytes := countBytes }
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
      uint64TypeId =
      .ok { typeId := uint64TypeId, valueBytes := zero8BytesV1 } := by
  have hvcC :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by simp [valueCanonical, hcanCount]
  have hvcT :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by simp [valueCanonical, hcanTwo]
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hwidth : uintWidth data uint64TypeId = some 64 := by
    simp [uintWidth, shapeOf, htype]
  have ht : leBytesToNat two8BytesV1 = 2 := by
    simpa [two8BytesV1] using leBytesToNat_two8
  have hnat0 : natToLeBytes 0 8 = zero8BytesV1 := by
    simpa [zero8BytesV1] using natToLeBytes_zero8
  have hnz : ((2 : Nat) == 0) = false := by decide
  have hmod :
      natToLeBytes (leBytesToNat countBytes % 2) 8 = zero8BytesV1 := by
    have heven' : leBytesToNat countBytes % 2 = 0 := heven
    rw [heven', hnat0]
  simp only [evalBinary, hvcC, hvcT, htid, Bool.and_self,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte, hwidth, intWidth, shapeOf,
    htype, uintByteLen, ht, hnz, hmod]

/-- Controlled production refinement: nullary UInt64 parity invariant on any
    even overlay payload (`stateLoad; lit 2; mod; lit 0; eq; return`, fuel 7).
    Sole private machine path; not a second evaluator. -/
theorem runInvariantCallableV1_eq_returnedTrue_of_uint64_parity_even
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .mod 0 1 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 4, typeId := boolTypeId },
            op := .binary .eq 2 3 }
        ]
        terminator := .return_ (some 4)
      }]
      loopBounds := #[]
      invariantSteps := some 7
    })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanTrue :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ())
    (heven : leBytesToNatV1 countBytes % 2 = 0) :
    runInvariantCallableV1 data rootId state = .returnedTrue := by
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }]
    loopBounds := #[]
    invariantSteps := some 7
  }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 4 :=
    maxValueIdInCallable_eq_four_of_five_results root
      uint64TypeId uint64TypeId uint64TypeId uint64TypeId boolTypeId
      (.stateLoad stateId) (.literal uint64TypeId two8BytesV1)
      (.binary .mod 0 1) (.literal uint64TypeId zero8BytesV1)
      (.binary .eq 2 3) (.return_ (some 4)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 7 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htypeB]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hseven : 7 % 2 ^ 64 = (7 : Nat) := by decide
  have htrueBytes : (encodeU8 1 == encodeU8 1) = true := by decide
  have hvcCount :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by
    simp [valueCanonical, hcanCount]
  have hvcTwo :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by
    simp [valueCanonical, hcanTwo]
  have hvcZero :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by
    simp [valueCanonical, hcanZero]
  have hvcTrue :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 1 } =
        true := by
    simp [valueCanonical, hcanTrue]
  have hmod :=
    evalBinary_mod_uint64_even_two data uint64TypeId countBytes htypeU
      hcanCount hcanTwo heven
  have heq :=
    evalBinary_eq_uint64_zero_zero data uint64TypeId boolTypeId htypeB
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := two8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v3 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v4 : ReferenceValueV1 :=
    { typeId := boolTypeId, valueBytes := encodeU8 1 }
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 5).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 5).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 5) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 5) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set (2 : ValueIdV1).toNat (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  have hs3 : (3 : ValueIdV1).toNat < e3.size := by
    simp [e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e4 := e3.set (3 : ValueIdV1).toNat (some v3) hs3
  have hset3 : envSet e3 3 v3 = some e4 := by
    simpa [e4] using envSet_of_lt e3 (3 : ValueIdV1) v3 hs3
  have hs4 : (4 : ValueIdV1).toNat < e4.size := by
    simp [e4, e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e5 := e4.set (4 : ValueIdV1).toNat (some v4) hs4
  have hset4 : envSet e4 4 v4 = some e5 := by
    simpa [e5] using envSet_of_lt e4 (4 : ValueIdV1) v4 hs4
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre := state, callable := root, isInitializer := false,
    context := #[], overlay := #[countBytes], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable root + 1) 0,
    responseCursor := 0, responses := #[], loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := 0, vaultToken := #[]
  }
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hseven]
  simp only [Bool.false_eq_true, ↓reduceIte]
  change (match (runMachine true 6 (mk (emptyEnv 5) 0)).2.2 with
    | .reverted _ => InvariantEvalResultV1.reverted
    | .trapped _ => InvariantEvalResultV1.trapped
    | .returned (some value) =>
        if value.typeId != root.result.typeId then .trapped
        else if value.valueBytes == encodeU8 1 then .returnedTrue
        else if value.valueBytes == encodeU8 0 then .returnedFalse
        else .trapped
    | .returned none => .trapped) = .returnedTrue
  have hexec0 :
      execInstruction (mk (emptyEnv 5) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[countBytes] : Array ByteArray)[stateId.toNat]? =
          some countBytes := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty, ↓reduceIte]
    have hstore := storeResult_envSet (mk (emptyEnv 5) 0) 0 v0 e1 hvcCount hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine true 6 (mk (emptyEnv 5) 0) =
      runMachine true 5 (mk e1 1) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := two8BytesV1 } = true := hvcTwo
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2
      (by simpa [mk, v1] using hvcTwo) hset1
  have step1 : runMachine true 5 (mk e1 1) = runMachine true 4 (mk e2 2) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec1]
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 } =
        .next (mk e3 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    have hvc0' : valueCanonical data v0 = true := by simpa [v0] using hvcCount
    have hvc1' : valueCanonical data v1 = true := by simpa [v1] using hvcTwo
    have hmod' : evalBinary data .mod v0 v1 uint64TypeId = .ok v2 := by
      simpa [v0, v1, v2] using hmod
    simp only [mk, execInstruction, hg0, hg1, hvc0', hvc1', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, hmod', fromEval]
    have hstore := storeResult_envSet (mk e2 2) 2 v2 e3
      (by simpa [v2] using hvcZero) hset2
    simpa [mk, e3, v2] using hstore
  have step2 : runMachine true 4 (mk e2 2) = runMachine true 3 (mk e3 3) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec2]
  have hexec3 :
      execInstruction (mk e3 3)
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e4 3) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e3 3) 3 v3 e4
      (by simpa [mk, v3] using hvcZero) hset3
  have step3 : runMachine true 3 (mk e3 3) = runMachine true 2 (mk e4 4) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec3]
  have hexec4 :
      execInstruction (mk e4 4)
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 } =
        .next (mk e5 4) := by
    have hg2 : envGet e4 2 = some v2 := by
      have hne :
          (e3.set (3 : ValueIdV1).toNat (some v3) hs3)[2]? = e3[2]? :=
        Array.getElem?_set_ne hs3 (by decide : (3 : Nat) ≠ 2)
      have h2 : e3[2]? = some (some v2) := Array.getElem?_set_self hs2
      change envGet (e3.set (3 : ValueIdV1).toNat (some v3) hs3) 2 = some v2
      simp [envGet, hne, h2]
    have hg3 : envGet e4 3 = some v3 := by
      have h3 : e4[(3 : ValueIdV1).toNat]? = some (some v3) :=
        Array.getElem?_set_self hs3
      simp [envGet, e4, h3, UInt32.toNat]
    have hvc2' : valueCanonical data v2 = true := by simpa [v2] using hvcZero
    have hvc3' : valueCanonical data v3 = true := by simpa [v3] using hvcZero
    have heq' : evalBinary data .eq v2 v3 boolTypeId = .ok v4 := by
      simpa [v2, v3, v4] using heq
    simp only [mk, execInstruction, hg2, hg3, hvc2', hvc3', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, heq', fromEval]
    have hstore := storeResult_envSet (mk e4 4) 4 v4 e5
      (by simpa [v4] using hvcTrue) hset4
    simpa [mk, e5, v4] using hstore
  have step4 : runMachine true 2 (mk e4 4) = runMachine true 1 (mk e5 5) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec4]
  have hg4 : envGet e5 4 = some v4 := by
    have h4 : e5[(4 : ValueIdV1).toNat]? = some (some v4) :=
      Array.getElem?_set_self hs4
    simp [envGet, e5, h4, UInt32.toNat]
  have hret :
      execTerminator (mk e5 5) (.return_ (some 4)) =
        .done (mk e5 5) (.returned (some v4)) := by
    have hunit : isUnitType data root.result.typeId = false := by
      simp [isUnitType, shapeOf, hrootResult, htypeB]
    have hty :
        (v4.typeId != root.result.typeId || !valueCanonical data v4) = false := by
      have hbeq : (v4.typeId != root.result.typeId) = false := by
        simp [v4, hrootResult, BEq.beq, bne]
      have hcan : valueCanonical data v4 = true := by simpa [v4] using hvcTrue
      simp [hbeq, hcan]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg4, hty, ↓reduceIte, v4]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT : runMachine true 1 (mk e5 5) =
      (0, mk e5 5, CandidateV1.returned (some v4)) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hret]
  rw [step0, step1, step2, step3, step4, stepT]
  have htyEq : (v4.typeId != root.result.typeId) = false := by
    simp [v4, hrootResult, BEq.beq, bne]
  simp [htyEq, htrueBytes, v4]

private theorem leBytesToNat_one8 :
    leBytesToNat (ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0]) = 1 := by
  simp [leBytesToNat, leBytesToNatList]

private theorem natToLeBytes_one8 :
    natToLeBytes 1 8 = ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0] := by
  simp [natToLeBytes, natToLeBytesList]

private theorem evalBinary_mod_uint64_odd_two
    (data : SemanticProgramDataV1) (uint64TypeId : TypeIdV1)
    (countBytes : ByteArray)
    (htype : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hodd : leBytesToNatV1 countBytes % 2 = 1) :
    evalBinary data .mod
      { typeId := uint64TypeId, valueBytes := countBytes }
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
      uint64TypeId =
      .ok { typeId := uint64TypeId, valueBytes := one8BytesV1 } := by
  have hvcC :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by simp [valueCanonical, hcanCount]
  have hvcT :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by simp [valueCanonical, hcanTwo]
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hwidth : uintWidth data uint64TypeId = some 64 := by
    simp [uintWidth, shapeOf, htype]
  have ht : leBytesToNat two8BytesV1 = 2 := by
    simpa [two8BytesV1] using leBytesToNat_two8
  have hnat1 : natToLeBytes 1 8 = one8BytesV1 := by
    simpa [one8BytesV1] using natToLeBytes_one8
  have hnz : ((2 : Nat) == 0) = false := by decide
  have hmod :
      natToLeBytes (leBytesToNat countBytes % 2) 8 = one8BytesV1 := by
    have hodd' : leBytesToNat countBytes % 2 = 1 := hodd
    rw [hodd', hnat1]
  simp only [evalBinary, hvcC, hvcT, htid, Bool.and_self,
    Bool.not_true, Bool.false_eq_true, ↓reduceIte, hwidth, intWidth, shapeOf,
    htype, uintByteLen, ht, hnz, hmod]

private theorem evalBinary_eq_uint64_one_zero
    (data : SemanticProgramDataV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool }) :
    evalBinary data .eq
      { typeId := uint64TypeId, valueBytes := one8BytesV1 }
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
      boolTypeId =
      .ok { typeId := boolTypeId, valueBytes := encodeU8 0 } := by
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hbool : isBoolType data boolTypeId = true := by
    simp [isBoolType, shapeOf, htypeB]
  have hbeq : (one8BytesV1 == zero8BytesV1) = false := by
    change (ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0] ==
        ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]) = false
    decide
  simp only [evalBinary, htid, hbool, bytesEqual, hbeq]
  rfl

/-- Controlled production refinement: nullary UInt64 parity invariant on any
    odd overlay payload returns false (same closed micro-path as the even case). -/
theorem runInvariantCallableV1_eq_returnedFalse_of_uint64_parity_odd
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .mod 0 1 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 4, typeId := boolTypeId },
            op := .binary .eq 2 3 }
        ]
        terminator := .return_ (some 4)
      }]
      loopBounds := #[]
      invariantSteps := some 7
    })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanFalse :
      validateValueBytesV1 data.types boolTypeId (encodeU8 0) = .ok ())
    (hodd : leBytesToNatV1 countBytes % 2 = 1) :
    runInvariantCallableV1 data rootId state = .returnedFalse := by
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }]
    loopBounds := #[]
    invariantSteps := some 7
  }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 4 :=
    maxValueIdInCallable_eq_four_of_five_results root
      uint64TypeId uint64TypeId uint64TypeId uint64TypeId boolTypeId
      (.stateLoad stateId) (.literal uint64TypeId two8BytesV1)
      (.binary .mod 0 1) (.literal uint64TypeId zero8BytesV1)
      (.binary .eq 2 3) (.return_ (some 4)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 7 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 }
      ]
      terminator := .return_ (some 4)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htypeB]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hseven : 7 % 2 ^ 64 = (7 : Nat) := by decide
  have hfalseBytes : (encodeU8 0 == encodeU8 1) = false := by decide
  have hfalseBytes0 : (encodeU8 0 == encodeU8 0) = true := by decide
  have hvcCount :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by
    simp [valueCanonical, hcanCount]
  have hvcTwo :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by
    simp [valueCanonical, hcanTwo]
  have hvcZero :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by
    simp [valueCanonical, hcanZero]
  have hvcFalse :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 0 } =
        true := by
    simp [valueCanonical, hcanFalse]
  have hmod :=
    evalBinary_mod_uint64_odd_two data uint64TypeId countBytes htypeU
      hcanCount hcanTwo hodd
  have heq :=
    evalBinary_eq_uint64_one_zero data uint64TypeId boolTypeId htypeB
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := two8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := one8BytesV1 }
  let v3 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v4 : ReferenceValueV1 :=
    { typeId := boolTypeId, valueBytes := encodeU8 0 }
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 5).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 5).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 5) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 5) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set (2 : ValueIdV1).toNat (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  have hs3 : (3 : ValueIdV1).toNat < e3.size := by
    simp [e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e4 := e3.set (3 : ValueIdV1).toNat (some v3) hs3
  have hset3 : envSet e3 3 v3 = some e4 := by
    simpa [e4] using envSet_of_lt e3 (3 : ValueIdV1) v3 hs3
  have hs4 : (4 : ValueIdV1).toNat < e4.size := by
    simp [e4, e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e5 := e4.set (4 : ValueIdV1).toNat (some v4) hs4
  have hset4 : envSet e4 4 v4 = some e5 := by
    simpa [e5] using envSet_of_lt e4 (4 : ValueIdV1) v4 hs4
  have hvcOne :
      valueCanonical data { typeId := uint64TypeId, valueBytes := one8BytesV1 } =
        true := by
    -- one8 is a fixed 8-byte UInt64 payload; validate via the public wire rule.
    have hone :
        validateValueBytesV1 data.types uint64TypeId one8BytesV1 = .ok () := by
      have h := validateValueBytesV1_uint64_eq_ok data.types uint64TypeId
        { id := uint64TypeId, name := none, shape := .uint 64 }
        1 0 0 0 0 0 0 0 htypeU rfl
      simpa [one8BytesV1] using h
    simp [valueCanonical, hone]
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre := state, callable := root, isInitializer := false,
    context := #[], overlay := #[countBytes], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable root + 1) 0,
    responseCursor := 0, responses := #[], loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := 0, vaultToken := #[]
  }
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hseven]
  simp only [Bool.false_eq_true, ↓reduceIte]
  change (match (runMachine true 6 (mk (emptyEnv 5) 0)).2.2 with
    | .reverted _ => InvariantEvalResultV1.reverted
    | .trapped _ => InvariantEvalResultV1.trapped
    | .returned (some value) =>
        if value.typeId != root.result.typeId then .trapped
        else if value.valueBytes == encodeU8 1 then .returnedTrue
        else if value.valueBytes == encodeU8 0 then .returnedFalse
        else .trapped
    | .returned none => .trapped) = .returnedFalse
  have hexec0 :
      execInstruction (mk (emptyEnv 5) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[countBytes] : Array ByteArray)[stateId.toNat]? =
          some countBytes := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty, ↓reduceIte]
    have hstore := storeResult_envSet (mk (emptyEnv 5) 0) 0 v0 e1 hvcCount hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine true 6 (mk (emptyEnv 5) 0) =
      runMachine true 5 (mk e1 1) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := two8BytesV1 } = true := hvcTwo
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2
      (by simpa [mk, v1] using hvcTwo) hset1
  have step1 : runMachine true 5 (mk e1 1) = runMachine true 4 (mk e2 2) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec1]
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .mod 0 1 } =
        .next (mk e3 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    have hvc0' : valueCanonical data v0 = true := by simpa [v0] using hvcCount
    have hvc1' : valueCanonical data v1 = true := by simpa [v1] using hvcTwo
    have hmod' : evalBinary data .mod v0 v1 uint64TypeId = .ok v2 := by
      simpa [v0, v1, v2] using hmod
    simp only [mk, execInstruction, hg0, hg1, hvc0', hvc1', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, hmod', fromEval]
    have hstore := storeResult_envSet (mk e2 2) 2 v2 e3
      (by simpa [v2] using hvcOne) hset2
    simpa [mk, e3, v2] using hstore
  have step2 : runMachine true 4 (mk e2 2) = runMachine true 3 (mk e3 3) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec2]
  have hexec3 :
      execInstruction (mk e3 3)
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e4 3) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e3 3) 3 v3 e4
      (by simpa [mk, v3] using hvcZero) hset3
  have step3 : runMachine true 3 (mk e3 3) = runMachine true 2 (mk e4 4) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec3]
  have hexec4 :
      execInstruction (mk e4 4)
        { result := some { valueId := 4, typeId := boolTypeId },
          op := .binary .eq 2 3 } =
        .next (mk e5 4) := by
    have hg2 : envGet e4 2 = some v2 := by
      have hne :
          (e3.set (3 : ValueIdV1).toNat (some v3) hs3)[2]? = e3[2]? :=
        Array.getElem?_set_ne hs3 (by decide : (3 : Nat) ≠ 2)
      have h2 : e3[2]? = some (some v2) := Array.getElem?_set_self hs2
      change envGet (e3.set (3 : ValueIdV1).toNat (some v3) hs3) 2 = some v2
      simp [envGet, hne, h2]
    have hg3 : envGet e4 3 = some v3 := by
      have h3 : e4[(3 : ValueIdV1).toNat]? = some (some v3) :=
        Array.getElem?_set_self hs3
      simp [envGet, e4, h3, UInt32.toNat]
    have hvc2' : valueCanonical data v2 = true := by simpa [v2] using hvcOne
    have hvc3' : valueCanonical data v3 = true := by simpa [v3] using hvcZero
    have heq' : evalBinary data .eq v2 v3 boolTypeId = .ok v4 := by
      simpa [v2, v3, v4] using heq
    simp only [mk, execInstruction, hg2, hg3, hvc2', hvc3', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, heq', fromEval]
    have hstore := storeResult_envSet (mk e4 4) 4 v4 e5
      (by simpa [v4] using hvcFalse) hset4
    simpa [mk, e5, v4] using hstore
  have step4 : runMachine true 2 (mk e4 4) = runMachine true 1 (mk e5 5) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec4]
  have hg4 : envGet e5 4 = some v4 := by
    have h4 : e5[(4 : ValueIdV1).toNat]? = some (some v4) :=
      Array.getElem?_set_self hs4
    simp [envGet, e5, h4, UInt32.toNat]
  have hret :
      execTerminator (mk e5 5) (.return_ (some 4)) =
        .done (mk e5 5) (.returned (some v4)) := by
    have hunit : isUnitType data root.result.typeId = false := by
      simp [isUnitType, shapeOf, hrootResult, htypeB]
    have hty :
        (v4.typeId != root.result.typeId || !valueCanonical data v4) = false := by
      have hbeq : (v4.typeId != root.result.typeId) = false := by
        simp [v4, hrootResult, BEq.beq, bne]
      have hcan : valueCanonical data v4 = true := by simpa [v4] using hvcFalse
      simp [hbeq, hcan]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg4, hty, ↓reduceIte, v4]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT : runMachine true 1 (mk e5 5) =
      (0, mk e5 5, CandidateV1.returned (some v4)) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hret]
  rw [step0, step1, step2, step3, step4, stepT]
  have htyEq : (v4.typeId != root.result.typeId) = false := by
    simp [v4, hrootResult, BEq.beq, bne]
  simp [htyEq, hfalseBytes, hfalseBytes0, v4]

/-- Returned-true on the closed UInt64 parity invariant forces even overlay. -/
theorem leBytesToNatV1_even_of_runInvariantCallableV1_returnedTrue_uint64_parity
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .mod 0 1 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 4, typeId := boolTypeId },
            op := .binary .eq 2 3 }
        ]
        terminator := .return_ (some 4)
      }]
      loopBounds := #[]
      invariantSteps := some 7
    })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanTrue :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ())
    (hcanFalse :
      validateValueBytesV1 data.types boolTypeId (encodeU8 0) = .ok ())
    (hrun : runInvariantCallableV1 data rootId state = .returnedTrue) :
    leBytesToNatV1 countBytes % 2 = 0 := by
  by_cases heven : leBytesToNatV1 countBytes % 2 = 0
  · exact heven
  · have hodd : leBytesToNatV1 countBytes % 2 = 1 := by
      have hmod := Nat.mod_two_eq_zero_or_one (leBytesToNatV1 countBytes)
      cases hmod with
      | inl h => exact (heven h).elim
      | inr h => exact h
    have hfalse :=
      runInvariantCallableV1_eq_returnedFalse_of_uint64_parity_odd
        data state countBytes rootId uint64TypeId boolTypeId stateId rootName
        visibility stateName hinitialized hdecode htypeU htypeB hstateId hstate
        hroot hcanCount hcanTwo hcanZero hcanFalse hodd
    rw [hfalse] at hrun
    cases hrun

/-- Normalize/source `invariant name : true` shape: nullary invariant with a
    single Bool literal `true` instruction and exact fuel 3. -/
theorem runInvariantCallableV1_eq_returnedTrue_of_single_nullary_literal_true
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (overlay : Array ByteArray)
    (rootId : CallableIdV1)
    (boolTypeId : TypeIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok overlay)
    (htype : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := typeName, shape := .bool })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := boolTypeId }
          op := .literal boolTypeId (encodeU8 1)
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := some 3
    })
    (hcanonical :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ()) :
    runInvariantCallableV1 data rootId state = .returnedTrue := by
  -- Reduce to the proved pureCall shape by treating the literal body as an
  -- inlined leaf of fuel 3 (no PureCall). Same private machine path.
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .literal boolTypeId (encodeU8 1)
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := some 3
  }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero root boolTypeId
      (.literal boolTypeId (encodeU8 1)) (.return_ (some 0)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 3 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .literal boolTypeId (encodeU8 1)
      }]
      terminator := .return_ (some 0)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htype]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hthree : 3 % 2 ^ 64 = (3 : Nat) := by decide
  have htrueBytes : (encodeU8 1 == encodeU8 1) = true := by decide
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hthree]
  simp only [Bool.false_eq_true, ↓reduceIte]
  -- Same rewrite cadence as the pureCall leaf micro-path (literal then return).
  have henvSize : (emptyEnv 1).size = 1 := by
    simp [emptyEnv]
  have hvc :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 1 } = true := by
    simp [valueCanonical, hcanonical]
  have hstore :
      storeResult
        {
          data
          pre := state
          callable := root
          isInitializer := false
          context := #[]
          overlay
          env := emptyEnv 1
          effects := #[]
          occCounts := Array.replicate (maxEffectIdInCallable root + 1) (0 : UInt32)
          responseCursor := 0
          responses := #[]
          loopCounts := #[]
          blockId := 0
          instrIdx := 0
          frames := #[]
          vaultNative := 0
          vaultToken := #[]
        }
        0 { typeId := boolTypeId, valueBytes := encodeU8 1 } =
        .next {
          data
          pre := state
          callable := root
          isInitializer := false
          context := #[]
          overlay
          env := (emptyEnv 1).set 0
            (some { typeId := boolTypeId, valueBytes := encodeU8 1 })
          effects := #[]
          occCounts := Array.replicate (maxEffectIdInCallable root + 1) (0 : UInt32)
          responseCursor := 0
          responses := #[]
          loopCounts := #[]
          blockId := 0
          instrIdx := 0
          frames := #[]
          vaultNative := 0
          vaultToken := #[]
        } := by
    simp [storeResult, hvc, envSet, henvSize]
  have hexec :
      execInstruction
        {
          data
          pre := state
          callable := root
          isInitializer := false
          context := #[]
          overlay
          env := emptyEnv 1
          effects := #[]
          occCounts := Array.replicate (maxEffectIdInCallable root + 1) (0 : UInt32)
          responseCursor := 0
          responses := #[]
          loopCounts := #[]
          blockId := 0
          instrIdx := 0
          frames := #[]
          vaultNative := 0
          vaultToken := #[]
        }
        {
          result := some { valueId := 0, typeId := boolTypeId }
          op := .literal boolTypeId (encodeU8 1)
        } =
        .next {
          data
          pre := state
          callable := root
          isInitializer := false
          context := #[]
          overlay
          env := (emptyEnv 1).set 0
            (some { typeId := boolTypeId, valueBytes := encodeU8 1 })
          effects := #[]
          occCounts := Array.replicate (maxEffectIdInCallable root + 1) (0 : UInt32)
          responseCursor := 0
          responses := #[]
          loopCounts := #[]
          blockId := 0
          instrIdx := 0
          frames := #[]
          vaultNative := 0
          vaultToken := #[]
        } := by
    simp [execInstruction, hvc, hstore]
  rw [runMachine.eq_def]
  simp [hrootBlocks, hexec]
  -- After literal: instrIdx becomes 1, fuel 1, then terminator return.
  rw [runMachine.eq_def]
  simp [hrootBlocks, hrootResult, isUnitType, shapeOf, htype, execTerminator,
    envGet, valueCanonical, hcanonical, htrueBytes]

/-- A controlled refinement of the sole production invariant runner for the
    canonical straight-line proof shape: a nullary invariant calls a nullary
    pure function whose single instruction returns Bool `true`. The theorem
    exposes no private machine state and adds no alternate executable path. -/
theorem runInvariantCallableV1_eq_returnedTrue_of_single_nullary_pureCall_true
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (overlay : Array ByteArray)
    (rootId leafId : CallableIdV1)
    (boolTypeId : TypeIdV1)
    (rootName leafName : Option String)
    (visibility : VisibilityV1)
    (typeName : Option String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok overlay)
    (htype : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := typeName, shape := .bool })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := boolTypeId }
          op := .pureCall leafId #[]
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := some 6
    })
    (hleaf : data.callables[leafId.toNat]? = some {
      id := leafId
      kind := .pureFn
      name := leafName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := boolTypeId }
          op := .literal boolTypeId (encodeU8 1)
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := some 3
    })
    (hcanonical :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ()) :
    runInvariantCallableV1 data rootId state = .returnedTrue := by
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .pureCall leafId #[]
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := some 6
  }
  let leaf : CallableV1 := {
    id := leafId
    kind := .pureFn
    name := leafName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .literal boolTypeId (encodeU8 1)
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := some 3
  }
  change data.callables[rootId.toNat]? = some root at hroot
  change data.callables[leafId.toNat]? = some leaf at hleaf
  have hrootMax : maxValueIdInCallable root = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero root boolTypeId
      (.pureCall leafId #[]) (.return_ (some 0)) (by rfl) (by rfl)
  have hleafMax : maxValueIdInCallable leaf = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero leaf boolTypeId
      (.literal boolTypeId (encodeU8 1)) (.return_ (some 0)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 6 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .pureCall leafId #[]
      }]
      terminator := .return_ (some 0)
    }] := by rfl
  have hleafKind : leaf.kind = .pureFn := by rfl
  have hleafParams : leaf.params = #[] := by rfl
  have hleafResult : leaf.result.typeId = boolTypeId := by rfl
  have hleafEntry : leaf.entryBlock = 0 := by rfl
  have hleafLoops : leaf.loopBounds = #[] := by rfl
  have hleafBlocks : leaf.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := boolTypeId }
        op := .literal boolTypeId (encodeU8 1)
      }]
      terminator := .return_ (some 0)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htype]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hpureBne : (CallableKindV1.pureFn != .pureFn) = false := by decide
  have hsix : 6 % 2 ^ 64 = (6 : Nat) := by decide
  have htrueBytes : (encodeU8 1 == encodeU8 1) = true := by decide
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hsix]
  simp only [Bool.false_eq_true, ↓reduceIte]
  rw [runMachine]
  simp [hrootBlocks, hleaf, hleafKind, hleafParams, hleafResult, hleafEntry,
    hleafLoops, hleafMax]
  simp [lookupArgs, emptyEnv]
  rw [runMachine]
  simp [hleafBlocks, execInstruction, valueCanonical, hcanonical, storeResult,
    envSet]
  simp only [hpureBne, Bool.false_eq_true, ↓reduceIte]
  rw [runMachine]
  simp [hleafBlocks, hleafResult, isUnitType, shapeOf, htype, envGet,
    valueCanonical, hcanonical, envSet]
  rw [runMachine]
  simp [hrootBlocks, hrootResult, isUnitType, shapeOf, htype, execTerminator,
    envGet, valueCanonical, hcanonical, htrueBytes]

/-! ### Increment-by-two returned branch: parity preservation -/

private theorem finalizeLifecycle_not_returned
    (pre : LogicalStateV1) (responses : ExternalResponsesV1)
    (cand : CandidateV1) (post : LogicalStateV1)
    (value : Option ReferenceValueV1) (effects : Array OrderedEffectV1) :
    finalizeLifecycle pre responses cand ≠ .returned post value effects := by
  unfold finalizeLifecycle
  cases h : (responses.size != 0) with
  | true =>
      simp only [↓reduceIte]
      intro hfalse; cases hfalse
  | false =>
      simp only [Bool.false_eq_true, ↓reduceIte]
      cases cand with
      | trapped fault => intro hfalse; cases hfalse
      | reverted reason => intro hfalse; cases hfalse
      | returned v => intro hfalse; cases hfalse

private theorem pow_256_eight_eq_pow_two_sixty_four :
    (256 : Nat) ^ 8 = 2 ^ 64 := by
  decide

private theorem UInt8_toNat_ofNat_mod256 (k : Nat) :
    (UInt8.ofNat (k % 256)).toNat = k % 256 := by
  have : k % 256 < 256 := Nat.mod_lt _ (by decide)
  simp [UInt8.toNat, UInt8.ofNat, Nat.mod_eq_of_lt this]

/-- Scaling the place argument multiplies the decoded Nat. -/
private theorem leBytesToNatList_mul_place
    (bytes : List UInt8) (place : Nat) :
    leBytesToNatList bytes place = place * leBytesToNatList bytes 1 := by
  induction bytes generalizing place with
  | nil =>
      simp [leBytesToNatList]
  | cons b rest ih =>
      change
        b.toNat * place + leBytesToNatList rest (place * 256) =
          place * (b.toNat * 1 + leBytesToNatList rest 256)
      rw [ih (place * 256), ih 256, Nat.mul_one]
      -- Goal: b*place + (place*256)*x = place*(b + 256*x)
      rw [Nat.mul_comm b.toNat place]
      -- place*b + (place*256)*x
      have hassoc : place * 256 * leBytesToNatList rest 1 =
          place * (256 * leBytesToNatList rest 1) := by
        rw [Nat.mul_assoc]
      rw [hassoc, ← Nat.mul_add]

private theorem leBytesToNatList_lt_pow_length (bytes : List UInt8) :
    leBytesToNatList bytes < 256 ^ bytes.length := by
  induction bytes with
  | nil => simp [leBytesToNatList]
  | cons byte rest ih =>
      simp only [leBytesToNatList, List.length_cons]
      rw [leBytesToNatList_mul_place rest 256, Nat.pow_succ]
      have hbyte : byte.toNat < 256 := UInt8.toNat_lt_size byte
      omega

private theorem natToLeBytesList_leBytesToNatList
    (bytes : List UInt8) :
    natToLeBytesList (leBytesToNatList bytes) bytes.length = bytes := by
  induction bytes with
  | nil => rfl
  | cons byte rest ih =>
      have hdecode :
          leBytesToNatList (byte :: rest) =
            byte.toNat + 256 * leBytesToNatList rest := by
        simp only [leBytesToNatList]
        rw [leBytesToNatList_mul_place]
        simp
      have hbyte : byte.toNat < 256 := UInt8.toNat_lt_size byte
      have hmod :
          leBytesToNatList (byte :: rest) % 256 = byte.toNat := by
        rw [hdecode]
        omega
      have hdiv :
          leBytesToNatList (byte :: rest) / 256 = leBytesToNatList rest := by
        rw [hdecode]
        omega
      simp only [List.length_cons, natToLeBytesList]
      have hhead :
          UInt8.ofNat (leBytesToNatList (byte :: rest) % 256) = byte := by
        apply UInt8.toNat_inj.1
        rw [UInt8_toNat_ofNat_mod256, hmod]
      rw [hhead, hdiv, ih]

/-- Little-endian place-value roundtrip for any width: if `n < 256^len` then
    decoding the `len`-byte encoding recovers `n`. -/
private theorem leBytesToNatList_natToLeBytesList
    (n len : Nat) (hn : n < 256 ^ len) :
    leBytesToNatList (natToLeBytesList n len) = n := by
  induction len generalizing n with
  | zero =>
      have hn0 : n = 0 := by
        have : n < 1 := by simpa using hn
        exact Nat.lt_one_iff.mp this
      simp [natToLeBytesList, leBytesToNatList, hn0]
  | succ len ih =>
      have hmod : (UInt8.ofNat (n % 256)).toNat = n % 256 :=
        UInt8_toNat_ofNat_mod256 n
      have hdiv : n / 256 < 256 ^ len := by
        have hpow : 256 ^ (len + 1) = 256 * 256 ^ len := by
          rw [Nat.pow_succ, Nat.mul_comm]
        rw [hpow] at hn
        exact (Nat.div_lt_iff_lt_mul (by decide : (0 : Nat) < 256)).mpr
          (by simpa [Nat.mul_comm] using hn)
      have ih' : leBytesToNatList (natToLeBytesList (n / 256) len) = n / 256 :=
        ih (n / 256) hdiv
      change
        (UInt8.ofNat (n % 256)).toNat * 1 +
            leBytesToNatList (natToLeBytesList (n / 256) len) (1 * 256) = n
      rw [hmod, Nat.mul_one, show (1 : Nat) * 256 = 256 from rfl]
      have hscale :
          leBytesToNatList (natToLeBytesList (n / 256) len) 256 =
            256 * leBytesToNatList (natToLeBytesList (n / 256) len) :=
        leBytesToNatList_mul_place (natToLeBytesList (n / 256) len) 256
      rw [hscale, ih']
      -- n % 256 + 256 * (n / 256) = n
      omega

private theorem leBytesToNat_natToLeBytes_of_lt
    (n len : Nat) (hn : n < 256 ^ len) :
    leBytesToNat (natToLeBytes n len) = n := by
  simp only [leBytesToNat, natToLeBytes]
  -- After unfolding, goal is the list roundtrip (ByteArray.mk reduces away).
  exact leBytesToNatList_natToLeBytesList n len hn

private theorem leBytesToNat_natToLeBytes_uint64
    (n : Nat) (hn : n < 2 ^ 64) :
    leBytesToNat (natToLeBytes n 8) = n := by
  have hn' : n < 256 ^ 8 := by
    simpa [pow_256_eight_eq_pow_two_sixty_four] using hn
  exact leBytesToNat_natToLeBytes_of_lt n 8 hn'

private theorem leBytesToNatV1_natToLeBytesV1_uint64
    (n : Nat) (hn : n < 2 ^ 64) :
    leBytesToNatV1 (natToLeBytesV1 n 8) = n :=
  leBytesToNat_natToLeBytes_uint64 n hn

/-- The Reference machine's fixed-width UInt64 writer is byte-for-byte the
    production Wire UInt64 encoder. This exposes codec alignment without
    adding a model-only scalar format. -/
theorem natToLeBytesV1_uint64_eq_encodeU64le (value : UInt64) :
    natToLeBytesV1 value.toNat 8 = encodeU64le value := by
  apply ByteArray.ext
  simp [natToLeBytesV1, natToLeBytes, natToLeBytesList, encodeU64le,
    Nat.div_div_eq_div_mul]

/-- Reading bytes emitted by the production Wire UInt64 encoder through the
    sole Reference unsigned interpretation recovers the original scalar. -/
theorem leBytesToNatV1_encodeU64le (value : UInt64) :
    leBytesToNatV1 (encodeU64le value) = value.toNat := by
  rw [← natToLeBytesV1_uint64_eq_encodeU64le]
  exact leBytesToNatV1_natToLeBytesV1_uint64 value.toNat value.toNat_lt

/-- Every exact-width UInt64 payload is recovered byte-for-byte after the
    Reference machine's unsigned interpretation and the production Wire
    encoder. This is a codec alignment law, not a second scalar codec. -/
theorem encodeU64le_uint64OfLeBytesToNatV1_of_size
    (bytes : ByteArray)
    (hsize : bytes.size = 8) :
    encodeU64le (UInt64.ofNat (leBytesToNatV1 bytes)) = bytes := by
  have hdataSize : bytes.data.size = 8 := by
    exact hsize
  have hlength : bytes.data.toList.length = 8 := by
    simpa only [Array.length_toList] using hdataSize
  have hbound : leBytesToNatV1 bytes < 2 ^ 64 := by
    have h := leBytesToNatList_lt_pow_length bytes.data.toList
    change leBytesToNatList bytes.data.toList < 2 ^ 64
    rw [← pow_256_eight_eq_pow_two_sixty_four]
    simpa only [hlength] using h
  rw [← natToLeBytesV1_uint64_eq_encodeU64le]
  have htoNat :
      (UInt64.ofNat (leBytesToNatV1 bytes)).toNat = leBytesToNatV1 bytes := by
    simpa [UInt64.toNat_ofNat, Nat.mod_eq_of_lt hbound]
  rw [htoNat]
  apply ByteArray.ext
  change
    (natToLeBytesList (leBytesToNatList bytes.data.toList) 8).toArray =
      bytes.data
  rw [← hlength, natToLeBytesList_leBytesToNatList]

private theorem evalBinary_add_uint64_two
    (data : SemanticProgramDataV1) (uint64TypeId : TypeIdV1)
    (countBytes : ByteArray)
    (htype : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    evalBinary data .add
      { typeId := uint64TypeId, valueBytes := countBytes }
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
      uint64TypeId =
      .ok {
        typeId := uint64TypeId
        valueBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
      } := by
  have hvcC :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by simp [valueCanonical, hcanCount]
  have hvcT :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by simp [valueCanonical, hcanTwo]
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hwidth : uintWidth data uint64TypeId = some 64 := by
    simp [uintWidth, shapeOf, htype]
  have ht : leBytesToNat two8BytesV1 = 2 := by
    simpa [two8BytesV1] using leBytesToNat_two8
  have hmax : uintMax 64 = 2 ^ 64 := by
    simp [uintMax]
  simp only [evalBinary, hvcC, hvcT, htid, Bool.and_self, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, hwidth, intWidth, shapeOf, htype,
    uintByteLen, ht, hmax, ge_iff_le]
  have hle : (2 ^ 64 ≤ leBytesToNat countBytes + 2) = False := by
    simp only [eq_iff_iff, iff_false]
    exact Nat.not_le_of_gt hnoOverflow
  simp only [hle, ↓reduceIte]
  -- Align public aliases with private helpers: 64/8 = 8 and leBytesToNatV1.
  rfl

/-- Adding the even literal 2 preserves parity. -/
theorem add_two_preserves_even
    (n : Nat) (heven : n % 2 = 0) : (n + 2) % 2 = 0 := by
  have h2 : (2 : Nat) % 2 = 0 := by decide
  simpa [Nat.add_mod, heven, h2] using (rfl : (0 : Nat) % 2 = 0)

/-- Successful UInt64 +2 encode bytes remain size-8 and even when the sum does
    not overflow. Used by increment finalize packaging. -/
theorem add_two_uint64_sum_bytes_even
    (countBytes : ByteArray)
    (_hsize : countBytes.size = 8)
    (heven : leBytesToNatV1 countBytes % 2 = 0)
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes :=
      natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    sumBytes.size = 8 ∧
      leBytesToNatV1 sumBytes % 2 = 0 ∧
      leBytesToNatV1 sumBytes = leBytesToNatV1 countBytes + 2 := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  have hsz : sumBytes.size = 8 := natToLeBytesV1_size _ 8
  have hround :
      leBytesToNatV1 sumBytes = leBytesToNatV1 countBytes + 2 :=
    leBytesToNatV1_natToLeBytesV1_uint64
      (leBytesToNatV1 countBytes + 2) hnoOverflow
  have heven' : leBytesToNatV1 sumBytes % 2 = 0 := by
    rw [hround]
    exact add_two_preserves_even _ heven
  exact ⟨hsz, heven', hround⟩

/-- Finalizer of a lifecycle gate never produces a successful return outcome. -/
theorem finalizeLifecycle_ne_returned_publicV1
    (pre : LogicalStateV1) (responses : ExternalResponsesV1)
    (cand : CandidateV1) (post : LogicalStateV1)
    (value : Option ReferenceValueV1) (effects : Array OrderedEffectV1) :
    finalizeLifecycle pre responses cand ≠ .returned post value effects :=
  finalizeLifecycle_not_returned pre responses cand post value effects

/-! ### Nullary view (get) micro-path: stateLoad + return

    Follows the closed invariant micro-path style: a local `mk` pins
    `blockId`/`frames`/`overlay` definitionally so `runMachine.eq_def` reduces.
-/

/-- Closed nullary view body (`stateLoad; return`). Any fuel of the form
    `fuel + 2` (production step uses 1_000_000) ends in `.returned` with the
    loaded slot; overlay and response cursor are unchanged. Responses and vault
    are carried but never read by this body. -/
private theorem runMachine_nullary_stateLoad_return
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (fuel : Nat)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ()) :
    let getCallable : CallableV1 := {
      id := callableId
      kind := .view
      name := viewName
      params := #[]
      result := { typeId := uint64TypeId, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := uint64TypeId }
          op := .stateLoad stateId
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := none
    }
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := countBytes }
    let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
      data, pre, callable := getCallable, isInitializer := false,
      context, overlay := #[countBytes], env,
      effects := #[],
      occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
      responseCursor := 0, responses, loopCounts := #[],
      blockId := 0, instrIdx := idx, frames := #[],
      vaultNative, vaultToken
    }
    ∃ (e1 : Array (Option ReferenceValueV1)),
      envSet (emptyEnv 1) 0 v0 = some e1 ∧
      runMachine false (fuel + 2) (mk (emptyEnv 1) 0) =
        (0, mk e1 1, CandidateV1.returned (some v0)) := by
  -- Bind the statement `let`s into the proof context.
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[countBytes], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative, vaultToken
  }
  have hblocks : getCallable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }] := by rfl
  have hresult : getCallable.result =
      { typeId := uint64TypeId, visibility := .public_ } := by rfl
  have hvc : valueCanonical data v0 = true := by
    simp [valueCanonical, v0, hcan]
  have heff : maxEffectIdInCallable getCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_get_shape getCallable uint64TypeId stateId
      (by rfl) (by rfl)
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 1).size := by
    simp [emptyEnv]
  let e1 := (emptyEnv 1).set 0 (some v0) hs0
  have hset0 : envSet (emptyEnv 1) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 1) (0 : ValueIdV1) v0 hs0
  have hexec0 :
      execInstruction (mk (emptyEnv 1) 0)
        { result := some { valueId := 0, typeId := uint64TypeId }
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[countBytes] : Array ByteArray)[stateId.toNat]? = some countBytes := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty]
    have hstore :=
      storeResult_envSet (mk (emptyEnv 1) 0) 0 v0 e1 hvc hset0
    -- storeResult keeps instrIdx; mk e1 0 shares all fields except env.
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine false (fuel + 2) (mk (emptyEnv 1) 0) =
      runMachine false (fuel + 1) (mk e1 1) := by
    have hfu : fuel + 2 = (fuel + 1).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec0]
  have hg0 : envGet e1 0 = some v0 := by
    have h0 : e1[(0 : ValueIdV1).toNat]? = some (some v0) :=
      Array.getElem?_set_self hs0
    simp [envGet, e1, h0, UInt32.toNat]
  have hret :
      execTerminator (mk e1 1) (.return_ (some 0)) =
        .done (mk e1 1) (.returned (some v0)) := by
    have hunit : isUnitType data getCallable.result.typeId = false := by
      simp [isUnitType, shapeOf, hresult, htypeU]
    have hbeq : (v0.typeId != getCallable.result.typeId) = false := by
      simp [v0, hresult, BEq.beq, bne]
    have hcond :
        (v0.typeId != getCallable.result.typeId || !valueCanonical data v0) =
          false := by
      simp [hbeq, hvc]
    simp only [mk, execTerminator, hg0]
    simp only [hunit, Bool.false_eq_true, ↓reduceIte, hcond, ↓reduceIte]
  have stepT : runMachine false (fuel + 1) (mk e1 1) =
      (0, mk e1 1, CandidateV1.returned (some v0)) := by
    have hfu : fuel + 1 = fuel.succ := by omega
    rw [hfu, runMachine]
    -- blockId=0, frames=[], instrIdx=1 ≥ size 1 → terminator.
    simp [mk, hblocks, hret]
  refine ⟨e1, hset0, ?_⟩
  rw [step0, stepT]

/-- Finalize a returned candidate with exhausted empty responses and a successful
    overlay encode. -/
private theorem finalize_returned_of_encode
    (m : MachineV1)
    (pre : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (post : LogicalStateV1)
    (hcursor : m.responseCursor = 0)
    (hrespEmpty : m.responses.size = 0)
    (hencode :
      encodeLogicalStateValuesV1 m.data (pre.initialized || m.isInitializer)
        m.overlay = .ok post) :
    finalize m (.returned value) pre = .returned post value m.effects := by
  unfold finalize
  have hne : (m.responseCursor != m.responses.size) = false := by
    simp [hcursor, hrespEmpty, bne, BEq.beq]
  simp only [hne, Bool.false_eq_true, ↓reduceIte, hencode]

/-- Get-shaped ready machine that returns keeps the overlay bytes in the encoded
    post-state when responses are exhausted (empty). Vault/responses fields are
    carried through the body but never read. -/
theorem runMachine_get_finalize_returned
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (fuel : Nat)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post)
    (hrespEmpty : responses.size = 0) :
    let getCallable : CallableV1 := {
      id := callableId
      kind := .view
      name := viewName
      params := #[]
      result := { typeId := uint64TypeId, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := uint64TypeId }
          op := .stateLoad stateId
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := none
    }
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := countBytes }
    let m0 : MachineV1 := {
      data, pre, callable := getCallable, isInitializer := false,
      context, overlay := #[countBytes], env := emptyEnv 1,
      effects := #[],
      occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
      responseCursor := 0, responses, loopCounts := #[],
      blockId := 0, instrIdx := 0, frames := #[],
      vaultNative, vaultToken
    }
    ∃ mEnd,
      runMachine false (fuel + 2) m0 =
        (0, mEnd, CandidateV1.returned (some v0)) ∧
      mEnd.overlay = #[countBytes] ∧
      mEnd.effects = #[] ∧
      mEnd.responseCursor = 0 ∧
      mEnd.responses = responses ∧
      finalize mEnd (.returned (some v0)) pre =
        .returned post (some v0) #[] := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let m0 : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 1,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative, vaultToken
  }
  have hrun :=
    runMachine_nullary_stateLoad_return data pre countBytes uint64TypeId
      stateId stateName callableId viewName fuel responses vaultNative vaultToken
      context htypeU hstate hstateId hcan
  rcases hrun with ⟨e1, _hset, hrunEq⟩
  have hrun' :
      runMachine false (fuel + 2) m0 =
        (0,
          { m0 with env := e1, instrIdx := 1 },
          CandidateV1.returned (some v0)) := by
    simpa [m0, getCallable, v0] using hrunEq
  let mEnd : MachineV1 := { m0 with env := e1, instrIdx := 1 }
  have hoverlay : mEnd.overlay = #[countBytes] := by simp [mEnd, m0]
  have heffects : mEnd.effects = #[] := by simp [mEnd, m0]
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd, m0]
  have hresp : mEnd.responses = responses := by simp [mEnd, m0]
  have hencode' :
      encodeLogicalStateValuesV1 mEnd.data
        (pre.initialized || mEnd.isInitializer) mEnd.overlay = .ok post := by
    simp [mEnd, m0, hinit, hoverlay, hencode]
  have hfin :=
    finalize_returned_of_encode mEnd pre (some v0) post hcursor
      (by simpa [hresp] using hrespEmpty) hencode'
  refine ⟨mEnd, hrun', hoverlay, heffects, hcursor, hresp, ?_⟩
  simpa [heffects] using hfin

/-- Production step for a ready nullary get-shaped view: empty responses yield
    the encode of the overlay; vault/context are carried but unused by the body. -/
theorem stepReferenceSliceV1_ready_get_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[countBytes] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := viewName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some { valueId := 0, typeId := uint64TypeId }
              op := .stateLoad stateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := countBytes }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  have hparams : getCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      getCallable #[countBytes] context false hgate hparams
  have hfuel : (999998 : Nat) + 2 = 1000000 := by decide
  have hmax : maxValueIdInCallable getCallable = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero getCallable uint64TypeId
      (.stateLoad stateId) (.return_ (some 0)) (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable getCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_get_shape getCallable uint64TypeId stateId
      (by rfl) (by rfl)
  have hrun :=
    runMachine_get_finalize_returned data pre countBytes uint64TypeId stateId
      stateName callableId viewName 999998 post responses vault.native
      vault.token context htypeU hstate hstateId hcan hinit hencode hrespEmpty
  rcases hrun with ⟨mEnd, hrunEq, _hoverlay, heffects, _hcursor, _hresp, hfin⟩
  let mGet : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 1,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  have hrun1000000 :
      runMachine false 1000000 mGet =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mGet, getCallable, v0] using hrunEq
  have hfin' :
      finalize mEnd (.returned (some v0)) pre =
        .returned post (some v0) #[] := by
    simpa [heffects] using hfin
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mGet).2.1
          (runMachine false 1000000 mGet).2.2 pre := by
    simpa [mGet, hadmitted_data, hmax, heff0, getCallable] using hnull
  rw [hnull', hrun1000000]
  exact hfin'

/-- Get body leaves the response cursor at 0; nonempty responses therefore
    finalize as `invalidExternalResponse` with exact pre. -/
theorem stepReferenceSliceV1_ready_get_nonempty_responses_traps
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hrespNe : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := viewName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some { valueId := 0, typeId := uint64TypeId }
              op := .stateLoad stateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  have hparams : getCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      getCallable #[countBytes] context false hgate hparams
  have hfuel : (999998 : Nat) + 2 = 1000000 := by decide
  have hmax : maxValueIdInCallable getCallable = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero getCallable uint64TypeId
      (.stateLoad stateId) (.return_ (some 0)) (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable getCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_get_shape getCallable uint64TypeId stateId
      (by rfl) (by rfl)
  have hrun :=
    runMachine_nullary_stateLoad_return data pre countBytes uint64TypeId
      stateId stateName callableId viewName 999998 responses vault.native
      vault.token context htypeU hstate hstateId hcan
  rcases hrun with ⟨e1, _hset, hrunEq⟩
  let mGet : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 1,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  let mEnd : MachineV1 := { mGet with env := e1, instrIdx := 1 }
  have hrun1000000 :
      runMachine false 1000000 mGet =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mGet, mEnd, getCallable, v0] using hrunEq
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mGet).2.1
          (runMachine false 1000000 mGet).2.2 pre := by
    simpa [mGet, hadmitted_data, hmax, heff0, getCallable] using hnull
  have hfin :
      finalize mEnd (.returned (some v0)) pre =
        .trapped .invalidExternalResponse pre := by
    unfold finalize
    have hne : (mEnd.responseCursor != mEnd.responses.size) = true := by
      have hcur : mEnd.responseCursor = 0 := by simp [mEnd, mGet]
      have hsz : mEnd.responses.size = responses.size := by simp [mEnd, mGet]
      have hdec : decide (0 = responses.size) = false := by
        rw [decide_eq_false_iff_not]
        exact Ne.symm hrespNe
      simp [hcur, hsz, bne, BEq.beq, hdec]
    simp only [hne, ↓reduceIte]
  rw [hnull', hrun1000000]
  exact hfin


/-! ### Nullary entry (increment) micro-path: load; lit 2; add; store; reload; return

    Success path only under explicit non-overflow. Overlay becomes the +2 sum
    bytes; finalize packaging is separate (caller supplies encode of that overlay).
-/

/-- Closed nullary increment body under non-overflowing UInt64 +2.
    Fuel of the form `fuel + 6` matches production's 1_000_000 budget.
    Responses/vault are carried and unused by the body. -/
private theorem runMachine_increment_add_two_return
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (fuel : Nat)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    let sumBytes :=
      natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    let incCallable : CallableV1 := {
      id := callableId
      kind := .entry
      name := entryName
      params := #[]
      result := { typeId := uint64TypeId, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .add 0 1 },
          { result := none, op := .stateStore stateId 2 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .stateLoad stateId }
        ]
        terminator := .return_ (some 3)
      }]
      loopBounds := #[]
      invariantSteps := none
    }
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := countBytes }
    let v1 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
    let v2 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := sumBytes }
    let mk (env : Array (Option ReferenceValueV1)) (overlay : Array ByteArray)
        (idx : Nat) : MachineV1 := {
      data, pre, callable := incCallable, isInitializer := false,
      context, overlay, env,
      effects := #[],
      occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
      responseCursor := 0, responses, loopCounts := #[],
      blockId := 0, instrIdx := idx, frames := #[],
      vaultNative, vaultToken
    }
    ∃ (eFinal : Array (Option ReferenceValueV1)),
      runMachine false (fuel + 6)
          (mk (emptyEnv 4) #[countBytes] 0) =
        (0, mk eFinal #[sumBytes] 5, CandidateV1.returned (some v2)) ∧
      envGet eFinal 3 = some v2 := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  let incCallable : CallableV1 := {
    id := callableId
    kind := .entry
    name := entryName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := two8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := sumBytes }
  let mk (env : Array (Option ReferenceValueV1)) (overlay : Array ByteArray)
      (idx : Nat) : MachineV1 := {
    data, pre, callable := incCallable, isInitializer := false,
    context, overlay, env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative, vaultToken
  }
  have hblocks : incCallable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }] := by rfl
  have hresult : incCallable.result =
      { typeId := uint64TypeId, visibility := .public_ } := by rfl
  have hvc0 : valueCanonical data v0 = true := by
    simp [valueCanonical, v0, hcan]
  have hvc1 : valueCanonical data v1 = true := by
    simp [valueCanonical, v1, hcanTwo]
  have hszSum : sumBytes.size = 8 := natToLeBytesV1_size _ 8
  have hcanSum :
      validateValueBytesV1 data.types uint64TypeId sumBytes = .ok () :=
    validateValueBytesV1_uint64_of_size data.types uint64TypeId
      { id := uint64TypeId, name := none, shape := .uint 64 }
      sumBytes htypeU rfl hszSum
  have hvc2 : valueCanonical data v2 = true := by
    simp [valueCanonical, v2, hcanSum]
  have hadd :
      evalBinary data .add v0 v1 uint64TypeId = .ok v2 := by
    have h :=
      evalBinary_add_uint64_two data uint64TypeId countBytes htypeU hcan hcanTwo
        hnoOverflow
    simpa [v0, v1, v2, sumBytes] using h
  have heff : maxEffectIdInCallable incCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  -- Env ladder: emptyEnv 4 → set 0,1,2,3
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 4).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 4).set 0 (some v0) hs0
  have hset0 : envSet (emptyEnv 4) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 4) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set 1 (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set 2 (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  have hs3 : (3 : ValueIdV1).toNat < e3.size := by
    simp [e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e4 := e3.set 3 (some v2) hs3
  have hset3 : envSet e3 3 v2 = some e4 := by
    simpa [e4] using envSet_of_lt e3 (3 : ValueIdV1) v2 hs3
  -- Overlay after store
  have hoverlay0 :
      (#[countBytes] : Array ByteArray)[stateId.toNat]? = some countBytes := by
    simp [hstateId]
  have hov_lt : (0 : Nat) < (#[countBytes] : Array ByteArray).size := by
    simp
  let overlay1 : Array ByteArray :=
    (#[countBytes] : Array ByteArray).set 0 sumBytes hov_lt
  have hoverlay1_eq : overlay1 = #[sumBytes] := by
    apply Array.ext
    · simp [overlay1, Array.size_set]
    · intro i hi hi'
      have hi0 : i = 0 := by
        have : i < 1 := by simpa [overlay1, Array.size_set] using hi
        omega
      subst hi0
      simp [overlay1, Array.getElem_set_self]
  -- Step 0: stateLoad
  have hexec0 :
      execInstruction (mk (emptyEnv 4) #[countBytes] 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 #[countBytes] 0) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay0, hty]
    have hstore :=
      storeResult_envSet (mk (emptyEnv 4) #[countBytes] 0) 0 v0 e1 hvc0 hset0
    simpa [mk, e1, v0] using hstore
  have step0 :
      runMachine false (fuel + 6) (mk (emptyEnv 4) #[countBytes] 0) =
        runMachine false (fuel + 5) (mk e1 #[countBytes] 1) := by
    have hfu : fuel + 6 = (fuel + 5).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec0]
  -- Step 1: literal 2
  have hexec1 :
      execInstruction (mk e1 #[countBytes] 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 } =
        .next (mk e2 #[countBytes] 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := two8BytesV1 } = true := by
      simpa [v1] using hvc1
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 #[countBytes] 1) 1 v1 e2
      (by simpa [v1] using hvc1) hset1
  have step1 :
      runMachine false (fuel + 5) (mk e1 #[countBytes] 1) =
        runMachine false (fuel + 4) (mk e2 #[countBytes] 2) := by
    have hfu : fuel + 5 = (fuel + 4).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec1]
  -- Step 2: binary add
  have hexec2 :
      execInstruction (mk e2 #[countBytes] 2)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 } =
        .next (mk e3 #[countBytes] 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    simp only [mk, execInstruction, hg0, hg1, hvc0, hvc1, Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, hadd, fromEval]
    have hstore := storeResult_envSet (mk e2 #[countBytes] 2) 2 v2 e3 hvc2 hset2
    simpa [mk, e3, v2] using hstore
  have step2 :
      runMachine false (fuel + 4) (mk e2 #[countBytes] 2) =
        runMachine false (fuel + 3) (mk e3 #[countBytes] 3) := by
    have hfu : fuel + 4 = (fuel + 3).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec2]
  -- Step 3: stateStore
  have hexec3 :
      execInstruction (mk e3 #[countBytes] 3)
        { result := none, op := .stateStore stateId 2 } =
        .next (mk e3 overlay1 3) := by
    have hg2 : envGet e3 2 = some v2 := by
      have h2 : e3[(2 : ValueIdV1).toNat]? = some (some v2) :=
        Array.getElem?_set_self hs2
      simp [envGet, e3, h2, UInt32.toNat]
    have hty : (v2.typeId != uint64TypeId) = false := by
      simp [v2, BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hg2, hty, hvc2, Bool.not_true,
      Bool.false_eq_true, ↓reduceIte]
    -- residual: if 0 < overlay.size then next with set
    have hlt : stateId.toNat < (#[countBytes] : Array ByteArray).size := by
      simp [hstateId]
    simp only [hlt, ↓reduceDIte, hstateId]
    -- Goal: next { m with overlay := set 0 sumBytes } = next (mk e3 overlay1 3)
    simp [mk, overlay1, v2, hstateId]
  have step3 :
      runMachine false (fuel + 3) (mk e3 #[countBytes] 3) =
        runMachine false (fuel + 2) (mk e3 overlay1 4) := by
    have hfu : fuel + 3 = (fuel + 2).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec3]
  -- Step 4: stateLoad from updated overlay
  have hexec4 :
      execInstruction (mk e3 overlay1 4)
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e4 overlay1 4) := by
    have hoverlay :
        overlay1[stateId.toNat]? = some sumBytes := by
      simp [overlay1, hstateId, Array.getElem?_set_self]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty]
    have hstore :=
      storeResult_envSet (mk e3 overlay1 4) 3 v2 e4 hvc2 hset3
    simpa [mk, e4, v2, sumBytes] using hstore
  have step4 :
      runMachine false (fuel + 2) (mk e3 overlay1 4) =
        runMachine false (fuel + 1) (mk e4 overlay1 5) := by
    have hfu : fuel + 2 = (fuel + 1).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec4]
  -- Terminator: return v2
  have hg3 : envGet e4 3 = some v2 := by
    have h3 : e4[(3 : ValueIdV1).toNat]? = some (some v2) :=
      Array.getElem?_set_self hs3
    simp [envGet, e4, h3, UInt32.toNat]
  have hret :
      execTerminator (mk e4 overlay1 5) (.return_ (some 3)) =
        .done (mk e4 overlay1 5) (.returned (some v2)) := by
    have hunit : isUnitType data incCallable.result.typeId = false := by
      simp [isUnitType, shapeOf, hresult, htypeU]
    have hbeq : (v2.typeId != incCallable.result.typeId) = false := by
      simp [v2, hresult, BEq.beq, bne]
    have hcond :
        (v2.typeId != incCallable.result.typeId || !valueCanonical data v2) =
          false := by
      simp [hbeq, hvc2]
    simp only [mk, execTerminator, hg3]
    simp only [hunit, Bool.false_eq_true, ↓reduceIte, hcond, ↓reduceIte]
  have stepT :
      runMachine false (fuel + 1) (mk e4 overlay1 5) =
        (0, mk e4 overlay1 5, CandidateV1.returned (some v2)) := by
    have hfu : fuel + 1 = fuel.succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hret]
  -- Chain
  have hchain :
      runMachine false (fuel + 6) (mk (emptyEnv 4) #[countBytes] 0) =
        (0, mk e4 overlay1 5, CandidateV1.returned (some v2)) := by
    rw [step0, step1, step2, step3, step4, stepT]
  -- Rewrite overlay1 to #[sumBytes]
  refine ⟨e4, ?_, hg3⟩
  -- Goal uses sumBytes spelling of overlay
  have hov : overlay1 = #[sumBytes] := hoverlay1_eq
  simpa [hov, sumBytes, v2] using hchain

/-- Increment-shaped ready machine under non-overflow: returned post encodes the
    +2 overlay when responses are empty. Vault/responses are carried unused. -/
theorem runMachine_increment_finalize_returned
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (fuel : Nat)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8] = .ok post)
    (hrespEmpty : responses.size = 0) :
    let sumBytes :=
      natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    let incCallable : CallableV1 := {
      id := callableId
      kind := .entry
      name := entryName
      params := #[]
      result := { typeId := uint64TypeId, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId two8BytesV1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .binary .add 0 1 },
          { result := none, op := .stateStore stateId 2 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .stateLoad stateId }
        ]
        terminator := .return_ (some 3)
      }]
      loopBounds := #[]
      invariantSteps := none
    }
    let v2 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := sumBytes }
    let m0 : MachineV1 := {
      data, pre, callable := incCallable, isInitializer := false,
      context, overlay := #[countBytes], env := emptyEnv 4,
      effects := #[],
      occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
      responseCursor := 0, responses, loopCounts := #[],
      blockId := 0, instrIdx := 0, frames := #[],
      vaultNative, vaultToken
    }
    ∃ mEnd,
      runMachine false (fuel + 6) m0 =
        (0, mEnd, CandidateV1.returned (some v2)) ∧
      mEnd.overlay = #[sumBytes] ∧
      mEnd.effects = #[] ∧
      mEnd.responseCursor = 0 ∧
      mEnd.responses = responses ∧
      finalize mEnd (.returned (some v2)) pre =
        .returned post (some v2) #[] := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  let incCallable : CallableV1 := {
    id := callableId
    kind := .entry
    name := entryName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := sumBytes }
  let m0 : MachineV1 := {
    data, pre, callable := incCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 4,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative, vaultToken
  }
  have hrun :=
    runMachine_increment_add_two_return data pre countBytes uint64TypeId
      stateId stateName callableId entryName fuel responses vaultNative
      vaultToken context htypeU hstate hstateId hcan hcanTwo hnoOverflow
  rcases hrun with ⟨eFinal, hrunEq, _hg3⟩
  have hrun' :
      runMachine false (fuel + 6) m0 =
        (0,
          { m0 with env := eFinal, overlay := #[sumBytes], instrIdx := 5 },
          CandidateV1.returned (some v2)) := by
    simpa [m0, incCallable, v2, sumBytes] using hrunEq
  let mEnd : MachineV1 :=
    { m0 with env := eFinal, overlay := #[sumBytes], instrIdx := 5 }
  have hoverlay : mEnd.overlay = #[sumBytes] := by simp [mEnd]
  have heffects : mEnd.effects = #[] := by simp [mEnd, m0]
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd, m0]
  have hresp : mEnd.responses = responses := by simp [mEnd, m0]
  have hencode' :
      encodeLogicalStateValuesV1 mEnd.data
        (pre.initialized || mEnd.isInitializer) mEnd.overlay = .ok post := by
    simp [mEnd, m0, hinit, hoverlay, hencode, sumBytes]
  have hfin :=
    finalize_returned_of_encode mEnd pre (some v2) post hcursor
      (by simpa [hresp] using hrespEmpty) hencode'
  refine ⟨mEnd, hrun', hoverlay, heffects, hcursor, hresp, ?_⟩
  simpa [heffects] using hfin

/-- Production step for a ready nullary increment-shaped entry under
    non-overflow and empty responses: returns encode of sum. -/
theorem stepReferenceSliceV1_ready_increment_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .stateLoad stateId },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .literal uint64TypeId two8BytesV1 },
              { result := some { valueId := 2, typeId := uint64TypeId },
                op := .binary .add 0 1 },
              { result := none, op := .stateStore stateId 2 },
              { result := some { valueId := 3, typeId := uint64TypeId },
                op := .stateLoad stateId }
            ]
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
    let v2 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := sumBytes }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v2) #[] := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  let incCallable : CallableV1 := {
    id := callableId
    kind := .entry
    name := entryName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := sumBytes }
  have hparams : incCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      incCallable #[countBytes] context false hgate hparams
  have hfuel : (999994 : Nat) + 6 = 1000000 := by decide
  have hmax : maxValueIdInCallable incCallable = 3 :=
    maxValueIdInCallable_eq_three_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable incCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_increment_finalize_returned data pre countBytes uint64TypeId
      stateId stateName callableId entryName 999994 post responses vault.native
      vault.token context htypeU hstate hstateId hcan hcanTwo hnoOverflow hinit
      hencode hrespEmpty
  rcases hrun with ⟨mEnd, hrunEq, _hoverlay, heffects, _hcursor, _hresp, hfin⟩
  let mInc : MachineV1 := {
    data, pre, callable := incCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 4,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  have hrun1000000 :
      runMachine false 1000000 mInc =
        (0, mEnd, CandidateV1.returned (some v2)) := by
    simpa [hfuel, mInc, incCallable, v2, sumBytes] using hrunEq
  have hfin' :
      finalize mEnd (.returned (some v2)) pre =
        .returned post (some v2) #[] := by
    simpa [heffects] using hfin
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mInc).2.1
          (runMachine false 1000000 mInc).2.2 pre := by
    simpa [mInc, hadmitted_data, hmax, heff0, incCallable] using hnull
  rw [hnull', hrun1000000]
  exact hfin'

/-- Increment body leaves the response cursor at 0; nonempty responses therefore
    finalize as `invalidExternalResponse` with exact pre (non-overflow path). -/
theorem stepReferenceSliceV1_ready_increment_nonempty_responses_traps
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hnoOverflow : leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hrespNe : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .stateLoad stateId },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .literal uint64TypeId two8BytesV1 },
              { result := some { valueId := 2, typeId := uint64TypeId },
                op := .binary .add 0 1 },
              { result := none, op := .stateStore stateId 2 },
              { result := some { valueId := 3, typeId := uint64TypeId },
                op := .stateLoad stateId }
            ]
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  let sumBytes := natToLeBytesV1 (leBytesToNatV1 countBytes + 2) 8
  let incCallable : CallableV1 := {
    id := callableId
    kind := .entry
    name := entryName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v2 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := sumBytes }
  have hparams : incCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      incCallable #[countBytes] context false hgate hparams
  have hfuel : (999994 : Nat) + 6 = 1000000 := by decide
  have hmax : maxValueIdInCallable incCallable = 3 :=
    maxValueIdInCallable_eq_three_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable incCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_increment_add_two_return data pre countBytes uint64TypeId
      stateId stateName callableId entryName 999994 responses vault.native
      vault.token context htypeU hstate hstateId hcan hcanTwo hnoOverflow
  rcases hrun with ⟨eFinal, hrunEq, _hg3⟩
  let mInc : MachineV1 := {
    data, pre, callable := incCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 4,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  let mEnd : MachineV1 :=
    { mInc with env := eFinal, overlay := #[sumBytes], instrIdx := 5 }
  have hrun1000000 :
      runMachine false 1000000 mInc =
        (0, mEnd, CandidateV1.returned (some v2)) := by
    simpa [hfuel, mInc, mEnd, incCallable, v2, sumBytes] using hrunEq
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mInc).2.1
          (runMachine false 1000000 mInc).2.2 pre := by
    simpa [mInc, hadmitted_data, hmax, heff0, incCallable] using hnull
  have hfin :
      finalize mEnd (.returned (some v2)) pre =
        .trapped .invalidExternalResponse pre := by
    unfold finalize
    have hne : (mEnd.responseCursor != mEnd.responses.size) = true := by
      have hcur : mEnd.responseCursor = 0 := by simp [mEnd, mInc]
      have hsz : mEnd.responses.size = responses.size := by simp [mEnd, mInc]
      have hdec : decide (0 = responses.size) = false := by
        rw [decide_eq_false_iff_not]
        exact Ne.symm hrespNe
      simp [hcur, hsz, bne, BEq.beq, hdec]
    simp only [hne, ↓reduceIte]
  rw [hnull', hrun1000000]
  exact hfin

/-- UInt64 +2 under overflow yields the standard arithmeticOverflow revert. -/
theorem evalBinary_add_uint64_two_overflow
    (data : SemanticProgramDataV1) (uint64TypeId : TypeIdV1)
    (countBytes : ByteArray)
    (htype : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hoverflow : ¬ leBytesToNatV1 countBytes + 2 < 2 ^ 64) :
    evalBinary data .add
      { typeId := uint64TypeId, valueBytes := countBytes }
      { typeId := uint64TypeId, valueBytes := two8BytesV1 }
      uint64TypeId =
      .error (.reverted (.standard .arithmeticOverflow)) := by
  have hvcC :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by simp [valueCanonical, hcanCount]
  have hvcT :
      valueCanonical data { typeId := uint64TypeId, valueBytes := two8BytesV1 } =
        true := by simp [valueCanonical, hcanTwo]
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hwidth : uintWidth data uint64TypeId = some 64 := by
    simp [uintWidth, shapeOf, htype]
  have ht : leBytesToNat two8BytesV1 = 2 := by
    simpa [two8BytesV1] using leBytesToNat_two8
  have hmax : uintMax 64 = 2 ^ 64 := by simp [uintMax]
  simp only [evalBinary, hvcC, hvcT, htid, Bool.and_self, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, hwidth, intWidth, shapeOf, htype,
    uintByteLen, ht, hmax, ge_iff_le]
  have hge : 2 ^ 64 ≤ leBytesToNat countBytes + 2 := by
    -- Public alias is definitionally the private decoder.
    change 2 ^ 64 ≤ leBytesToNatV1 countBytes + 2
    omega
  simp only [hge, ↓reduceIte]

/-- Production step for ready increment under overflow cannot return: the add
    halts as arithmeticOverflow, and finalize either reverts or traps on
    trailing responses — both keep exact pre and never produce `.returned`. -/
theorem stepReferenceSliceV1_ready_increment_overflow_not_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (post : LogicalStateV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanTwo :
      validateValueBytesV1 data.types uint64TypeId two8BytesV1 = .ok ())
    (hoverflow : ¬ leBytesToNatV1 countBytes + 2 < 2 ^ 64)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .stateLoad stateId },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .literal uint64TypeId two8BytesV1 },
              { result := some { valueId := 2, typeId := uint64TypeId },
                op := .binary .add 0 1 },
              { result := none, op := .stateStore stateId 2 },
              { result := some { valueId := 3, typeId := uint64TypeId },
                op := .stateLoad stateId }
            ]
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault ≠
      .returned post value effects := by
  let incCallable : CallableV1 := {
    id := callableId
    kind := .entry
    name := entryName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := two8BytesV1 }
  have hparams : incCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      incCallable #[countBytes] context false hgate hparams
  have hmax : maxValueIdInCallable incCallable = 3 :=
    maxValueIdInCallable_eq_three_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable incCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_increment_shape incCallable uint64TypeId
      stateId two8BytesV1 (by rfl) (by rfl)
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre, callable := incCallable, isInitializer := false,
    context, overlay := #[countBytes], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable incCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 (mk (emptyEnv 4) 0)).2.1
          (runMachine false 1000000 (mk (emptyEnv 4) 0)).2.2 pre := by
    simpa [mk, hadmitted_data, hmax, heff0, incCallable] using hnull
  have hvc0 : valueCanonical data v0 = true := by simp [valueCanonical, v0, hcan]
  have hvc1 : valueCanonical data v1 = true := by
    simp [valueCanonical, v1, hcanTwo]
  have hblocks : incCallable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 },
        { result := none, op := .stateStore stateId 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 3)
    }] := by rfl
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 4).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 4).set 0 (some v0) hs0
  have hset0 : envSet (emptyEnv 4) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 4) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set 1 (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hoverlay0 :
      (#[countBytes] : Array ByteArray)[stateId.toNat]? = some countBytes := by
    simp [hstateId]
  have hexec0 :
      execInstruction (mk (emptyEnv 4) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay0, hty]
    have hstore :=
      storeResult_envSet (mk (emptyEnv 4) 0) 0 v0 e1 hvc0 hset0
    simpa [mk, e1, v0] using hstore
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId two8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := two8BytesV1 } = true := by
      simpa [v1] using hvc1
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2 hvc1 hset1
  have haddErr :
      evalBinary data .add v0 v1 uint64TypeId =
        .error (.reverted (.standard .arithmeticOverflow)) := by
    simpa [v0, v1] using
      evalBinary_add_uint64_two_overflow data uint64TypeId countBytes htypeU
        hcan hcanTwo hoverflow
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .binary .add 0 1 } =
        .done (mk e2 2) (.reverted (.standard .arithmeticOverflow)) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    simp only [mk, execInstruction, hg0, hg1, hvc0, hvc1, Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, haddErr, fromEval,
      LocalFailureV1.toCandidateV1]
  have step0 :
      runMachine false 1000000 (mk (emptyEnv 4) 0) =
        runMachine false 999999 (mk e1 1) := by
    change runMachine false (999999 + 1) (mk (emptyEnv 4) 0) =
      runMachine false 999999 (mk e1 1)
    rw [runMachine]
    simp [mk, hblocks, hexec0]
  have step1 :
      runMachine false 999999 (mk e1 1) =
        runMachine false 999998 (mk e2 2) := by
    change runMachine false (999998 + 1) (mk e1 1) =
      runMachine false 999998 (mk e2 2)
    rw [runMachine]
    simp [mk, hblocks, hexec1]
  have step2 :
      runMachine false 999998 (mk e2 2) =
        (0, mk e2 2, CandidateV1.reverted (.standard .arithmeticOverflow)) := by
    change runMachine false (999997 + 1) (mk e2 2) =
      (0, mk e2 2, CandidateV1.reverted (.standard .arithmeticOverflow))
    rw [runMachine]
    simp [mk, hblocks, hexec2]
  have hrun :
      runMachine false 1000000 (mk (emptyEnv 4) 0) =
        (0, mk e2 2, CandidateV1.reverted (.standard .arithmeticOverflow)) := by
    rw [step0, step1, step2]
  have hfin_ne :
      finalize (mk e2 2) (.reverted (.standard .arithmeticOverflow)) pre ≠
        .returned post value effects := by
    unfold finalize
    by_cases hcur : ((mk e2 2).responseCursor != (mk e2 2).responses.size)
    · simp only [hcur, ↓reduceIte]
      intro h
      cases h
    · simp only [hcur, Bool.false_eq_true, ↓reduceIte]
      intro h
      cases h
  intro hstep
  rw [hnull', hrun] at hstep
  exact hfin_ne hstep


/-! ### UInt64 equality-to-zero and store-zero micro-paths

    Second L1 instance packaging. Sole production step/runInvariant machine;
    not a second evaluator.
-/

/-- Three value-producing results (0..2) for the zero-eq invariant shape. -/
private theorem maxValueIdInCallable_eq_two_of_three_results
    (callable : CallableV1)
    (typeId0 typeId1 typeId2 : TypeIdV1)
    (op0 op1 op2 : SemanticOpV1)
    (terminator : TerminatorV1)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := typeId0 }, op := op0 },
        { result := some { valueId := 1, typeId := typeId1 }, op := op1 },
        { result := some { valueId := 2, typeId := typeId2 }, op := op2 }
      ]
      terminator
    }]) :
    maxValueIdInCallable callable = 2 := by
  simp [maxValueIdInCallable, hparams, hblocks]

/-- Clear-shaped body: literal + void store + reload (max valueId 1). -/
private theorem maxValueIdInCallable_eq_one_of_clear_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (stateId : StateIdV1)
    (zeroBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 1)
    }]) :
    maxValueIdInCallable callable = 1 := by
  simp [maxValueIdInCallable, hparams, hblocks]

private theorem maxEffectIdInCallable_eq_zero_of_clear_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (stateId : StateIdV1)
    (zeroBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId },
          op := .stateLoad stateId }
      ]
      terminator := .return_ (some 1)
    }]) :
    maxEffectIdInCallable callable = 0 := by
  simp [maxEffectIdInCallable, hparams, hblocks]

/-- Nullary UInt64 eq-zero invariant on the exact zero overlay
    (`stateLoad; lit 0; eq; return`, fuel 5). -/
theorem runInvariantCallableV1_eq_returnedTrue_of_uint64_eq_zero
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[zero8BytesV1])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 2, typeId := boolTypeId },
            op := .binary .eq 0 1 }
        ]
        terminator := .return_ (some 2)
      }]
      loopBounds := #[]
      invariantSteps := some 5
    })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanTrue :
      validateValueBytesV1 data.types boolTypeId (encodeU8 1) = .ok ()) :
    runInvariantCallableV1 data rootId state = .returnedTrue := by
  let root : CallableV1 := {
    id := rootId
    kind := .invariant
    name := rootName
    params := #[]
    result := { typeId := boolTypeId, visibility }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 }
      ]
      terminator := .return_ (some 2)
    }]
    loopBounds := #[]
    invariantSteps := some 5
  }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 2 :=
    maxValueIdInCallable_eq_two_of_three_results root
      uint64TypeId uint64TypeId boolTypeId
      (.stateLoad stateId) (.literal uint64TypeId zero8BytesV1)
      (.binary .eq 0 1) (.return_ (some 2)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 5 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 }
      ]
      terminator := .return_ (some 2)
    }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htypeB]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hfive : 5 % 2 ^ 64 = (5 : Nat) := by decide
  have htrueBytes : (encodeU8 1 == encodeU8 1) = true := by decide
  have hvcZero :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by
    simp [valueCanonical, hcanZero]
  have hvcTrue :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 1 } =
        true := by
    simp [valueCanonical, hcanTrue]
  have heq :=
    evalBinary_eq_uint64_zero_zero data uint64TypeId boolTypeId htypeB
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := boolTypeId, valueBytes := encodeU8 1 }
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 3).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 3).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 3) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 3) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set (2 : ValueIdV1).toNat (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre := state, callable := root, isInitializer := false,
    context := #[], overlay := #[zero8BytesV1], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable root + 1) 0,
    responseCursor := 0, responses := #[], loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := 0, vaultToken := #[]
  }
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hfive]
  simp only [Bool.false_eq_true, ↓reduceIte]
  change (match (runMachine true 4 (mk (emptyEnv 3) 0)).2.2 with
    | .reverted _ => InvariantEvalResultV1.reverted
    | .trapped _ => InvariantEvalResultV1.trapped
    | .returned (some value) =>
        if value.typeId != root.result.typeId then .trapped
        else if value.valueBytes == encodeU8 1 then .returnedTrue
        else if value.valueBytes == encodeU8 0 then .returnedFalse
        else .trapped
    | .returned none => .trapped) = .returnedTrue
  have hexec0 :
      execInstruction (mk (emptyEnv 3) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[zero8BytesV1] : Array ByteArray)[stateId.toNat]? =
          some zero8BytesV1 := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty, ↓reduceIte]
    have hstore := storeResult_envSet (mk (emptyEnv 3) 0) 0 v0 e1 hvcZero hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine true 4 (mk (emptyEnv 3) 0) =
      runMachine true 3 (mk e1 1) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2
      (by simpa [mk, v1] using hvcZero) hset1
  have step1 : runMachine true 3 (mk e1 1) = runMachine true 2 (mk e2 2) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec1]
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 } =
        .next (mk e3 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne, h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    have hvc0' : valueCanonical data v0 = true := by simpa [v0] using hvcZero
    have hvc1' : valueCanonical data v1 = true := by simpa [v1] using hvcZero
    have heq' : evalBinary data .eq v0 v1 boolTypeId = .ok v2 := by
      simpa [v0, v1, v2] using heq
    simp only [mk, execInstruction, hg0, hg1, hvc0', hvc1', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, heq', fromEval]
    have hstore := storeResult_envSet (mk e2 2) 2 v2 e3
      (by simpa [v2] using hvcTrue) hset2
    simpa [mk, e3, v2] using hstore
  have step2 : runMachine true 2 (mk e2 2) = runMachine true 1 (mk e3 3) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec2]
  have hg2 : envGet e3 2 = some v2 := by
    have h2 : e3[(2 : ValueIdV1).toNat]? = some (some v2) :=
      Array.getElem?_set_self hs2
    simp [envGet, e3, h2, UInt32.toNat]
  have hret :
      execTerminator (mk e3 3) (.return_ (some 2)) =
        .done (mk e3 3) (.returned (some v2)) := by
    have hunit : isUnitType data root.result.typeId = false := by
      simp [isUnitType, shapeOf, hrootResult, htypeB]
    have hbeq : (v2.typeId != root.result.typeId) = false := by
      simp [v2, hrootResult, BEq.beq, bne]
    have hcond :
        (v2.typeId != root.result.typeId || !valueCanonical data v2) = false := by
      simp [hbeq, hvcTrue, v2]
    simp only [mk, execTerminator, hg2]
    simp only [hunit, Bool.false_eq_true, ↓reduceIte, hcond, ↓reduceIte]
  have stepT : runMachine true 1 (mk e3 3) =
      (0, mk e3 3, CandidateV1.returned (some v2)) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hret]
  rw [step0, step1, step2, stepT]
  have htyEq : (v2.typeId != root.result.typeId) = false := by
    simp [v2, hrootResult, BEq.beq, bne]
  simp [htyEq, htrueBytes, v2]


/-- Closed nullary clear body: lit 0; store; reload; return. Overlay becomes zero. -/
private theorem runMachine_clear_store_zero_return
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (fuel : Nat)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ()) :
    let clearCallable : CallableV1 := {
      id := callableId, kind := .entry, name := entryName, params := #[],
      result := { typeId := uint64TypeId, visibility := .public_ },
      entryBlock := 0,
      blocks := #[{
        id := 0, params := #[],
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := none, op := .stateStore stateId 0 },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .stateLoad stateId }],
        terminator := .return_ (some 1) }],
      loopBounds := #[], invariantSteps := none }
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    ∃ eFinal,
      runMachine false (fuel + 4)
        { data, pre, callable := clearCallable, isInitializer := false,
          context, overlay := #[countBytes], env := emptyEnv 2,
          effects := #[],
          occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
          responseCursor := 0, responses, loopCounts := #[],
          blockId := 0, instrIdx := 0, frames := #[],
          vaultNative, vaultToken } =
        (0,
          { data, pre, callable := clearCallable, isInitializer := false,
            context, overlay := #[zero8BytesV1], env := eFinal,
            effects := #[],
            occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
            responseCursor := 0, responses, loopCounts := #[],
            blockId := 0, instrIdx := 3, frames := #[],
            vaultNative, vaultToken },
          CandidateV1.returned (some v0)) := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .stateLoad stateId }],
      terminator := .return_ (some 1) }],
    loopBounds := #[], invariantSteps := none }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hvcZero : valueCanonical data v0 = true := by
    simp [v0, valueCanonical, hcanZero]
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 2).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 2).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 2) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 2) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v0) hs1
  have hset1 : envSet e1 1 v0 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v0 hs1
  have hov_lt : (0 : Nat) < (#[countBytes] : Array ByteArray).size := by simp
  let overlay1 : Array ByteArray :=
    (#[countBytes] : Array ByteArray).set 0 zero8BytesV1 hov_lt
  have hoverlay1_eq : overlay1 = #[zero8BytesV1] := by
    apply Array.ext
    · simp [overlay1, Array.size_set]
    · intro i hi hi'
      have hi0 : i = 0 := by
        have : i < 1 := by simpa [overlay1, Array.size_set] using hi
        omega
      subst hi0
      simp [overlay1, Array.getElem_set_self]
  let mk (env : Array (Option ReferenceValueV1))
      (overlay : Array ByteArray) (idx : Nat) : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay, env, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative, vaultToken }
  have hblocks : clearCallable.blocks = #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .stateLoad stateId }],
      terminator := .return_ (some 1) }] := by rfl
  have hresult : clearCallable.result.typeId = uint64TypeId := by rfl
  have hexec0 :
      execInstruction (mk (emptyEnv 2) #[countBytes] 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e1 #[countBytes] 0) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := by
      simpa [v0] using hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk (emptyEnv 2) #[countBytes] 0) 0 v0 e1
      (by simpa [mk, v0] using hvcZero) hset0
  have step0 :
      runMachine false (fuel + 4) (mk (emptyEnv 2) #[countBytes] 0) =
        runMachine false (fuel + 3) (mk e1 #[countBytes] 1) := by
    have hfu : fuel + 4 = (fuel + 3).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 #[countBytes] 1)
        { result := none, op := .stateStore stateId 0 } =
        .next (mk e1 overlay1 1) := by
    have hg0 : envGet e1 0 = some v0 := by
      have h0 : e1[(0 : ValueIdV1).toNat]? = some (some v0) :=
        Array.getElem?_set_self hs0
      simp [envGet, e1, h0, UInt32.toNat]
    have hty : (v0.typeId != uint64TypeId) = false := by simp [v0, BEq.beq, bne]
    have hvc0' : valueCanonical data v0 = true := hvcZero
    simp only [mk, execInstruction, hstate, hg0, hty, hvc0', Bool.not_true,
      Bool.false_eq_true, ↓reduceIte]
    have hlt : stateId.toNat < (#[countBytes] : Array ByteArray).size := by
      simp [hstateId]
    simp only [hlt, ↓reduceDIte, hstateId]
    simp [mk, overlay1, v0, hstateId]
  have step1 :
      runMachine false (fuel + 3) (mk e1 #[countBytes] 1) =
        runMachine false (fuel + 2) (mk e1 overlay1 2) := by
    have hfu : fuel + 3 = (fuel + 2).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec1]
  have hexec2 :
      execInstruction (mk e1 overlay1 2)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e2 overlay1 2) := by
    have hoverlay : overlay1[stateId.toNat]? = some zero8BytesV1 := by
      simp [overlay1, hstateId, Array.getElem?_set_self]
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty]
    have hstore := storeResult_envSet (mk e1 overlay1 2) 1 v0 e2 hvcZero hset1
    simpa [mk, e2, v0] using hstore
  have step2 :
      runMachine false (fuel + 2) (mk e1 overlay1 2) =
        runMachine false (fuel + 1) (mk e2 overlay1 3) := by
    have hfu : fuel + 2 = (fuel + 1).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec2]
  have hg1 : envGet e2 1 = some v0 := by
    have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v0) :=
      Array.getElem?_set_self hs1
    simp [envGet, e2, h1, UInt32.toNat]
  have hret :
      execTerminator (mk e2 overlay1 3) (.return_ (some 1)) =
        .done (mk e2 overlay1 3) (.returned (some v0)) := by
    have hunit : isUnitType data clearCallable.result.typeId = false := by
      simp [isUnitType, shapeOf, hresult, htypeU]
    have hty :
        (v0.typeId != clearCallable.result.typeId || !valueCanonical data v0) =
          false := by
      have hbeq : (v0.typeId != clearCallable.result.typeId) = false := by
        simp [v0, hresult, BEq.beq, bne]
      simp [hbeq, hvcZero]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg1, hty, ↓reduceIte, v0]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT :
      runMachine false (fuel + 1) (mk e2 overlay1 3) =
        (0, mk e2 overlay1 3, CandidateV1.returned (some v0)) := by
    have hfu : fuel + 1 = fuel.succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hret]
  refine ⟨e2, ?_⟩
  have hchain :
      runMachine false (fuel + 4) (mk (emptyEnv 2) #[countBytes] 0) =
        (0, mk e2 overlay1 3, CandidateV1.returned (some v0)) := by
    rw [step0, step1, step2, stepT]
  simpa [hoverlay1_eq, mk] using hchain


theorem stepReferenceSliceV1_ready_clear_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore stateId 0 },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .stateLoad stateId }
            ]
            terminator := .return_ (some 1)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .stateLoad stateId }],
      terminator := .return_ (some 1) }],
    loopBounds := #[], invariantSteps := none }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hparams : clearCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      clearCallable #[countBytes] context false hgate hparams
  have hfuel : (999996 : Nat) + 4 = 1000000 := by decide
  have hmax : maxValueIdInCallable clearCallable = 1 :=
    maxValueIdInCallable_eq_one_of_clear_shape clearCallable uint64TypeId
      stateId zero8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable clearCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_clear_shape clearCallable uint64TypeId
      stateId zero8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_clear_store_zero_return data pre countBytes uint64TypeId stateId
      stateName callableId entryName 999996 responses vault.native vault.token
      context htypeU hstate hstateId hcanZero
  rcases hrun with ⟨eFinal, hrunEq⟩
  let mClr : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 2, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  let mEnd : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[zero8BytesV1], env := eFinal, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 3, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  have hrun1000000 :
      runMachine false 1000000 mClr =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mClr, mEnd, clearCallable, v0] using hrunEq
  have heffects : mEnd.effects = #[] := by simp [mEnd]
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd]
  have hresp : mEnd.responses = responses := by simp [mEnd]
  have hencode' :
      encodeLogicalStateValuesV1 mEnd.data
        (pre.initialized || mEnd.isInitializer) mEnd.overlay = .ok post := by
    simp [mEnd, hinit, hencode]
  have hfin :=
    finalize_returned_of_encode mEnd pre (some v0) post hcursor
      (by simpa [hresp] using hrespEmpty) hencode'
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mClr).2.1
          (runMachine false 1000000 mClr).2.2 pre := by
    simpa [mClr, hadmitted_data, hmax, heff0, clearCallable] using hnull
  rw [hnull', hrun1000000]
  simpa [heffects] using hfin

theorem stepReferenceSliceV1_ready_clear_nonempty_responses_traps
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (countBytes : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 0)
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hrespNe : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore stateId 0 },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .stateLoad stateId }
            ]
            terminator := .return_ (some 1)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[countBytes] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore stateId 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .stateLoad stateId }],
      terminator := .return_ (some 1) }],
    loopBounds := #[], invariantSteps := none }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hparams : clearCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      clearCallable #[countBytes] context false hgate hparams
  have hfuel : (999996 : Nat) + 4 = 1000000 := by decide
  have hmax : maxValueIdInCallable clearCallable = 1 :=
    maxValueIdInCallable_eq_one_of_clear_shape clearCallable uint64TypeId
      stateId zero8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable clearCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_clear_shape clearCallable uint64TypeId
      stateId zero8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_clear_store_zero_return data pre countBytes uint64TypeId stateId
      stateName callableId entryName 999996 responses vault.native vault.token
      context htypeU hstate hstateId hcanZero
  rcases hrun with ⟨eFinal, hrunEq⟩
  let mClr : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[countBytes], env := emptyEnv 2, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  let mEnd : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[zero8BytesV1], env := eFinal, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 3, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  have hrun1000000 :
      runMachine false 1000000 mClr =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mClr, mEnd, clearCallable, v0] using hrunEq
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mClr).2.1
          (runMachine false 1000000 mClr).2.2 pre := by
    simpa [mClr, hadmitted_data, hmax, heff0, clearCallable] using hnull
  have hfin :
      finalize mEnd (.returned (some v0)) pre =
        .trapped .invalidExternalResponse pre := by
    unfold finalize
    have hne : (mEnd.responseCursor != mEnd.responses.size) = true := by
      have hcur : mEnd.responseCursor = 0 := by simp [mEnd]
      have hsz : mEnd.responses.size = responses.size := by simp [mEnd]
      have hdec : decide (0 = responses.size) = false := by
        rw [decide_eq_false_iff_not]
        exact Ne.symm hrespNe
      simp [hcur, hsz, bne, BEq.beq, hdec]
    simp only [hne, ↓reduceIte]
  rw [hnull', hrun1000000]
  exact hfin


private theorem evalBinary_eq_uint64_bytes_ne_zero
    (data : SemanticProgramDataV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (countBytes : ByteArray)
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hne : (countBytes == zero8BytesV1) = false) :
    evalBinary data .eq
      { typeId := uint64TypeId, valueBytes := countBytes }
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
      boolTypeId =
      .ok { typeId := boolTypeId, valueBytes := encodeU8 0 } := by
  have htid : (uint64TypeId == uint64TypeId) = true := by simp [BEq.beq]
  have hbool : isBoolType data boolTypeId = true := by
    simp [isBoolType, shapeOf, htypeB]
  simp only [evalBinary, htid, hbool, bytesEqual, hne]
  rfl

/-- Nullary UInt64 eq-zero invariant returns false when the overlay is not zero. -/
theorem runInvariantCallableV1_eq_returnedFalse_of_uint64_ne_zero
    (data : SemanticProgramDataV1)
    (state : LogicalStateV1)
    (countBytes : ByteArray)
    (rootId : CallableIdV1)
    (uint64TypeId boolTypeId : TypeIdV1)
    (stateId : StateIdV1)
    (rootName : Option String)
    (visibility : VisibilityV1)
    (stateName : String)
    (hinitialized : state.initialized = true)
    (hdecode : decodeLogicalStateValuesV1 data state = .ok #[countBytes])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (htypeB : data.types[boolTypeId.toNat]? = some {
      id := boolTypeId, name := none, shape := .bool })
    (hstateId : stateId = 0)
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hroot : data.callables[rootId.toNat]? = some {
      id := rootId
      kind := .invariant
      name := rootName
      params := #[]
      result := { typeId := boolTypeId, visibility }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .stateLoad stateId },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := some { valueId := 2, typeId := boolTypeId },
            op := .binary .eq 0 1 }
        ]
        terminator := .return_ (some 2)
      }]
      loopBounds := #[]
      invariantSteps := some 5
    })
    (hcanCount :
      validateValueBytesV1 data.types uint64TypeId countBytes = .ok ())
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hcanFalse :
      validateValueBytesV1 data.types boolTypeId (encodeU8 0) = .ok ())
    (hne : (countBytes == zero8BytesV1) = false) :
    runInvariantCallableV1 data rootId state = .returnedFalse := by
  let root : CallableV1 := {
    id := rootId, kind := .invariant, name := rootName, params := #[],
    result := { typeId := boolTypeId, visibility }, entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 }],
      terminator := .return_ (some 2) }],
    loopBounds := #[], invariantSteps := some 5 }
  change data.callables[rootId.toNat]? = some root at hroot
  have hrootMax : maxValueIdInCallable root = 2 :=
    maxValueIdInCallable_eq_two_of_three_results root
      uint64TypeId uint64TypeId boolTypeId
      (.stateLoad stateId) (.literal uint64TypeId zero8BytesV1)
      (.binary .eq 0 1) (.return_ (some 2)) (by rfl) (by rfl)
  have hrootSteps : root.invariantSteps = some 5 := by rfl
  have hrootKind : root.kind = .invariant := by rfl
  have hrootParams : root.params = #[] := by rfl
  have hrootLoops : root.loopBounds = #[] := by rfl
  have hrootResult : root.result.typeId = boolTypeId := by rfl
  have hrootEntry : root.entryBlock = 0 := by rfl
  have hrootBlocks : root.blocks = #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 }],
      terminator := .return_ (some 2) }] := by rfl
  have hbool : isBoolType data root.result.typeId = true := by
    simp [isBoolType, shapeOf, hrootResult, htypeB]
  have hkindBne : (CallableKindV1.invariant != .invariant) = false := by decide
  have hfive : 5 % 2 ^ 64 = (5 : Nat) := by decide
  have hfalseBytes : (encodeU8 0 == encodeU8 0) = true := by decide
  have hvcCount :
      valueCanonical data { typeId := uint64TypeId, valueBytes := countBytes } =
        true := by simp [valueCanonical, hcanCount]
  have hvcZero :
      valueCanonical data { typeId := uint64TypeId, valueBytes := zero8BytesV1 } =
        true := by simp [valueCanonical, hcanZero]
  have hvcFalse :
      valueCanonical data { typeId := boolTypeId, valueBytes := encodeU8 0 } =
        true := by simp [valueCanonical, hcanFalse]
  have heq :=
    evalBinary_eq_uint64_bytes_ne_zero data uint64TypeId boolTypeId countBytes
      htypeB hne
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := countBytes }
  let v1 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  let v2 : ReferenceValueV1 :=
    { typeId := boolTypeId, valueBytes := encodeU8 0 }
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 3).size := by
    simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 3).set (0 : ValueIdV1).toNat (some v0) hs0
  have hset0 : envSet (emptyEnv 3) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 3) (0 : ValueIdV1) v0 hs0
  have hs1 : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set (1 : ValueIdV1).toNat (some v1) hs1
  have hset1 : envSet e1 1 v1 = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) v1 hs1
  have hs2 : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set (2 : ValueIdV1).toNat (some v2) hs2
  have hset2 : envSet e2 2 v2 = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) v2 hs2
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre := state, callable := root, isInitializer := false,
    context := #[], overlay := #[countBytes], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable root + 1) 0,
    responseCursor := 0, responses := #[], loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative := 0, vaultToken := #[] }
  rw [runInvariantCallableV1]
  simp only [hinitialized, Bool.not_true, Bool.false_eq_true, ↓reduceIte, hroot]
  simp only [hrootSteps, hrootKind, hrootParams, Array.isEmpty_empty,
    hrootLoops, hbool, Bool.not_true, Bool.or_false]
  rw [hdecode]
  simp only [UInt64.toNat_ofNat, hrootMax, hrootEntry, hkindBne, hfive]
  simp only [Bool.false_eq_true, ↓reduceIte]
  have hexec0 :
      execInstruction (mk (emptyEnv 3) 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[countBytes] : Array ByteArray)[stateId.toNat]? = some countBytes := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty, ↓reduceIte]
    have hstore := storeResult_envSet (mk (emptyEnv 3) 0) 0 v0 e1
      (by simpa [v0] using hvcCount) hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine true 4 (mk (emptyEnv 3) 0) =
      runMachine true 3 (mk e1 1) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec0]
  have hexec1 :
      execInstruction (mk e1 1)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e2 1) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := hvcZero
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 1) 1 v1 e2
      (by simpa [v1] using hvcZero) hset1
  have step1 : runMachine true 3 (mk e1 1) = runMachine true 2 (mk e2 2) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec1]
  have hexec2 :
      execInstruction (mk e2 2)
        { result := some { valueId := 2, typeId := boolTypeId },
          op := .binary .eq 0 1 } =
        .next (mk e3 2) := by
    have hg0 : envGet e2 0 = some v0 := by
      have hne' :
          (e1.set (1 : ValueIdV1).toNat (some v1) hs1)[0]? = e1[0]? :=
        Array.getElem?_set_ne hs1 (by decide : (1 : Nat) ≠ 0)
      have h0 : e1[0]? = some (some v0) := Array.getElem?_set_self hs0
      change envGet (e1.set (1 : ValueIdV1).toNat (some v1) hs1) 0 = some v0
      simp [envGet, hne', h0]
    have hg1 : envGet e2 1 = some v1 := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some v1) :=
        Array.getElem?_set_self hs1
      simp [envGet, e2, h1, UInt32.toNat]
    have hvc0' : valueCanonical data v0 = true := by simpa [v0] using hvcCount
    have hvc1' : valueCanonical data v1 = true := by simpa [v1] using hvcZero
    have heq' : evalBinary data .eq v0 v1 boolTypeId = .ok v2 := by
      simpa [v0, v1, v2] using heq
    simp only [mk, execInstruction, hg0, hg1, hvc0', hvc1', Bool.not_true,
      Bool.or_false, Bool.false_eq_true, ↓reduceIte, heq', fromEval]
    have hstore := storeResult_envSet (mk e2 2) 2 v2 e3
      (by simpa [v2] using hvcFalse) hset2
    simpa [mk, e3, v2] using hstore
  have step2 : runMachine true 2 (mk e2 2) = runMachine true 1 (mk e3 3) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hexec2]
  have hg2 : envGet e3 2 = some v2 := by
    have h2 : e3[(2 : ValueIdV1).toNat]? = some (some v2) :=
      Array.getElem?_set_self hs2
    simp [envGet, e3, h2, UInt32.toNat]
  have hret :
      execTerminator (mk e3 3) (.return_ (some 2)) =
        .done (mk e3 3) (.returned (some v2)) := by
    have hunit : isUnitType data root.result.typeId = false := by
      simp [isUnitType, shapeOf, hrootResult, htypeB]
    have hty :
        (v2.typeId != root.result.typeId || !valueCanonical data v2) = false := by
      have hbeq : (v2.typeId != root.result.typeId) = false := by
        simp [v2, hrootResult, BEq.beq, bne]
      have hcan : valueCanonical data v2 = true := by simpa [v2] using hvcFalse
      simp [hbeq, hcan]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg2, hty, ↓reduceIte, v2]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT : runMachine true 1 (mk e3 3) =
      (0, mk e3 3, CandidateV1.returned (some v2)) := by
    rw [runMachine.eq_def]; simp [mk, hrootBlocks, hret]
  rw [step0, step1, step2, stepT]
  have htyEq : (v2.typeId != root.result.typeId) = false := by
    simp [v2, hrootResult, BEq.beq, bne]
  -- returned false: first if type ok, second if == encodeU8 1 is false, third == encodeU8 0
  have hneTrue : (encodeU8 0 == encodeU8 1) = false := by decide
  simp [htyEq, hneTrue, hfalseBytes, v2]

/-- Evaluate one admitted invariant using its structure-validated exact fuel.
    This deliberately bypasses `InvocationV1`: normal root invocation of an
    invariant remains invalid, and invariant execution never publishes an
    overlay or effects. This is an engineering reference API, not the formal
    InvariantABI-owned `evalInvariantV1`. -/
def evalInvariantReferenceSliceV1
    (admitted : AdmittedReferenceSliceV1)
    (ordinal : InvariantOrdinalV1)
    (state : LogicalStateV1) : InvariantEvalResultV1 :=
  let data := admitted.data
  if !stateConformsBoolV1 admitted.program state then
    .trapped
  else
    match data.invariants[ordinal.toNat]? with
    | none => .trapped
    | some decl =>
      runInvariantCallableV1 data decl.callableId state


/-! ### Triple-UInt64 multi-state ready micro-paths (L1 multi-slot packaging)

    Program-agnostic step packaging for three public UInt64 slots.
    Sole production `stepReferenceSliceV1` / `runMachine` path; not a second
    evaluator. Used by MiniAmm empty-pool and any future 3-slot L1 instance.
-/

/-- Max valueId for clear-triple shape: lit/store ×3 + final load (ids 0..3). -/
private theorem maxValueIdInCallable_eq_three_of_clear_triple_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (zeroBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId },
          op := .stateLoad 2 }
      ]
      terminator := .return_ (some 3)
    }]) :
    maxValueIdInCallable callable = 3 := by
  simp [maxValueIdInCallable, hparams, hblocks]

private theorem maxEffectIdInCallable_eq_zero_of_clear_triple_shape
    (callable : CallableV1)
    (typeId : TypeIdV1)
    (zeroBytes : ByteArray)
    (hparams : callable.params = #[])
    (hblocks : callable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[
        { result := some { valueId := 0, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId },
          op := .literal typeId zeroBytes },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId },
          op := .stateLoad 2 }
      ]
      terminator := .return_ (some 3)
    }]) :
    maxEffectIdInCallable callable = 0 := by
  simp [maxEffectIdInCallable, hparams, hblocks]

/-- Nullary view load of slot 2 from a three-UInt64 overlay. -/
private theorem runMachine_nullary_stateLoad_triple_slot2_return
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (fuel : Nat)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ()) :
    let getCallable : CallableV1 := {
      id := callableId
      kind := .view
      name := viewName
      params := #[]
      result := { typeId := uint64TypeId, visibility := .public_ }
      entryBlock := 0
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[{
          result := some { valueId := 0, typeId := uint64TypeId }
          op := .stateLoad stateId
        }]
        terminator := .return_ (some 0)
      }]
      loopBounds := #[]
      invariantSteps := none
    }
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := b2 }
    let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
      data, pre, callable := getCallable, isInitializer := false,
      context, overlay := #[b0, b1, b2], env,
      effects := #[],
      occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
      responseCursor := 0, responses, loopCounts := #[],
      blockId := 0, instrIdx := idx, frames := #[],
      vaultNative, vaultToken
    }
    ∃ (e1 : Array (Option ReferenceValueV1)),
      envSet (emptyEnv 1) 0 v0 = some e1 ∧
      runMachine false (fuel + 2) (mk (emptyEnv 1) 0) =
        (0, mk e1 1, CandidateV1.returned (some v0)) := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := b2 }
  let mk (env : Array (Option ReferenceValueV1)) (idx : Nat) : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[b0, b1, b2], env,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative, vaultToken
  }
  have hblocks : getCallable.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }] := by rfl
  have hresult : getCallable.result =
      { typeId := uint64TypeId, visibility := .public_ } := by rfl
  have hvc : valueCanonical data v0 = true := by
    simp [valueCanonical, v0, hcan]
  have hs0 : (0 : ValueIdV1).toNat < (emptyEnv 1).size := by
    simp [emptyEnv]
  let e1 := (emptyEnv 1).set 0 (some v0) hs0
  have hset0 : envSet (emptyEnv 1) 0 v0 = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 1) (0 : ValueIdV1) v0 hs0
  have hexec0 :
      execInstruction (mk (emptyEnv 1) 0)
        { result := some { valueId := 0, typeId := uint64TypeId }
          op := .stateLoad stateId } =
        .next (mk e1 0) := by
    have hoverlay :
        (#[b0, b1, b2] : Array ByteArray)[stateId.toNat]? = some b2 := by
      simp [hstateId]
    have hty : (uint64TypeId != uint64TypeId) = false := by
      simp [BEq.beq, bne]
    simp only [mk, execInstruction, hstate, hoverlay, hty]
    have hstore :=
      storeResult_envSet (mk (emptyEnv 1) 0) 0 v0 e1 hvc hset0
    simpa [mk, e1, v0] using hstore
  have step0 : runMachine false (fuel + 2) (mk (emptyEnv 1) 0) =
      runMachine false (fuel + 1) (mk e1 1) := by
    have hfu : fuel + 2 = (fuel + 1).succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hexec0]
  have hg0 : envGet e1 0 = some v0 := by
    have h0 : e1[(0 : ValueIdV1).toNat]? = some (some v0) :=
      Array.getElem?_set_self hs0
    simp [envGet, e1, h0, UInt32.toNat]
  have hret :
      execTerminator (mk e1 1) (.return_ (some 0)) =
        .done (mk e1 1) (.returned (some v0)) := by
    have hunit : isUnitType data getCallable.result.typeId = false := by
      simp [isUnitType, shapeOf, hresult, htypeU]
    have hbeq : (v0.typeId != getCallable.result.typeId) = false := by
      simp [v0, hresult, BEq.beq, bne]
    have hcond :
        (v0.typeId != getCallable.result.typeId || !valueCanonical data v0) =
          false := by
      simp [hbeq, hvc]
    simp only [mk, execTerminator, hg0]
    simp only [hunit, Bool.false_eq_true, ↓reduceIte, hcond, ↓reduceIte]
  have stepT : runMachine false (fuel + 1) (mk e1 1) =
      (0, mk e1 1, CandidateV1.returned (some v0)) := by
    have hfu : fuel + 1 = fuel.succ := by omega
    rw [hfu, runMachine]
    simp [mk, hblocks, hret]
  refine ⟨e1, hset0, ?_⟩
  rw [step0, stepT]

/-- Ready get of triple-UInt64 slot 2 returns and re-encodes the full overlay. -/
theorem stepReferenceSliceV1_ready_get_triple_slot2_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true #[b0, b1, b2] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := viewName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some { valueId := 0, typeId := uint64TypeId }
              op := .stateLoad stateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[b0, b1, b2] context false) :
    let v0 : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := b2 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some v0) #[] := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := b2 }
  have hparams : getCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      getCallable #[b0, b1, b2] context false hgate hparams
  have hfuel : (999998 : Nat) + 2 = 1000000 := by decide
  have hmax : maxValueIdInCallable getCallable = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero getCallable uint64TypeId
      (.stateLoad stateId) (.return_ (some 0)) (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable getCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_get_shape getCallable uint64TypeId stateId
      (by rfl) (by rfl)
  have hrun :=
    runMachine_nullary_stateLoad_triple_slot2_return data pre b0 b1 b2
      uint64TypeId stateId stateName callableId viewName 999998 responses
      vault.native vault.token context htypeU hstate hstateId hcan
  rcases hrun with ⟨e1, _hset, hrunEq⟩
  let mGet : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[b0, b1, b2], env := emptyEnv 1,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  let mEnd : MachineV1 := { mGet with env := e1, instrIdx := 1 }
  have hrun1000000 :
      runMachine false 1000000 mGet =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mGet, mEnd, getCallable, v0] using hrunEq
  have heffects : mEnd.effects = #[] := by simp [mEnd, mGet]
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd, mGet]
  have hresp : mEnd.responses = responses := by simp [mEnd, mGet]
  have hencode' :
      encodeLogicalStateValuesV1 mEnd.data
        (pre.initialized || mEnd.isInitializer) mEnd.overlay = .ok post := by
    simp [mEnd, mGet, hinit, hencode]
  have hfin :=
    finalize_returned_of_encode mEnd pre (some v0) post hcursor
      (by simpa [hresp] using hrespEmpty) hencode'
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mGet).2.1
          (runMachine false 1000000 mGet).2.2 pre := by
    simpa [mGet, hadmitted_data, hmax, heff0, getCallable] using hnull
  rw [hnull', hrun1000000]
  simpa [heffects] using hfin

/-- Nonempty responses after a triple-slot-2 get trap with exact pre. -/
theorem stepReferenceSliceV1_ready_get_triple_slot2_nonempty_responses_traps
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (stateId : StateIdV1)
    (stateName : String)
    (callableId : CallableIdV1)
    (viewName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hstate : data.logicalState[stateId.toNat]? = some {
      id := stateId, name := stateName, typeId := uint64TypeId,
      visibility := .public_ })
    (hstateId : stateId = 2)
    (hcan :
      validateValueBytesV1 data.types uint64TypeId b2 = .ok ())
    (hrespNe : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .view
          name := viewName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0
            params := #[]
            instructions := #[{
              result := some { valueId := 0, typeId := uint64TypeId }
              op := .stateLoad stateId
            }]
            terminator := .return_ (some 0)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[b0, b1, b2] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  let getCallable : CallableV1 := {
    id := callableId
    kind := .view
    name := viewName
    params := #[]
    result := { typeId := uint64TypeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := uint64TypeId }
        op := .stateLoad stateId
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }
  let v0 : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := b2 }
  have hparams : getCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      getCallable #[b0, b1, b2] context false hgate hparams
  have hfuel : (999998 : Nat) + 2 = 1000000 := by decide
  have hmax : maxValueIdInCallable getCallable = 0 :=
    maxValueIdInCallable_eq_zero_of_single_result_zero getCallable uint64TypeId
      (.stateLoad stateId) (.return_ (some 0)) (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable getCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_get_shape getCallable uint64TypeId stateId
      (by rfl) (by rfl)
  have hrun :=
    runMachine_nullary_stateLoad_triple_slot2_return data pre b0 b1 b2
      uint64TypeId stateId stateName callableId viewName 999998 responses
      vault.native vault.token context htypeU hstate hstateId hcan
  rcases hrun with ⟨e1, _hset, hrunEq⟩
  let mGet : MachineV1 := {
    data, pre, callable := getCallable, isInitializer := false,
    context, overlay := #[b0, b1, b2], env := emptyEnv 1,
    effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable getCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token
  }
  let mEnd : MachineV1 := { mGet with env := e1, instrIdx := 1 }
  have hrun1000000 :
      runMachine false 1000000 mGet =
        (0, mEnd, CandidateV1.returned (some v0)) := by
    simpa [hfuel, mGet, mEnd, getCallable, v0] using hrunEq
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd, mGet]
  have hresp : mEnd.responses = responses := by simp [mEnd, mGet]
  have hfin :
      finalize mEnd (.returned (some v0)) pre =
        .trapped .invalidExternalResponse pre := by
    unfold finalize
    have hne : (mEnd.responseCursor != mEnd.responses.size) = true := by
      simp [hcursor, hresp, bne, BEq.beq]
      exact Ne.symm hrespNe
    simp only [hne, ↓reduceIte]
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mGet).2.1
          (runMachine false 1000000 mGet).2.2 pre := by
    simpa [mGet, hadmitted_data, hmax, heff0, getCallable] using hnull
  rw [hnull', hrun1000000]
  exact hfin

/-! ### Clear-triple multi-state store-zero packaging -/

/-- Run the clear-triple body: zero all three overlay slots then return slot 2. -/
private theorem runMachine_clear_triple_store_zero_return
    (data : SemanticProgramDataV1)
    (pre : LogicalStateV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (fuel : Nat)
    (responses : ExternalResponsesV1 := #[])
    (vaultNative : UInt64 := 0)
    (vaultToken : Array (ByteArray × UInt64) := #[])
    (context : Array ContextInputV1 := #[])
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ()) :
    let clearCallable : CallableV1 := {
      id := callableId, kind := .entry, name := entryName, params := #[],
      result := { typeId := uint64TypeId, visibility := .public_ },
      entryBlock := 0,
      blocks := #[{
        id := 0, params := #[],
        instructions := #[
          { result := some { valueId := 0, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := none, op := .stateStore 0 0 },
          { result := some { valueId := 1, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := none, op := .stateStore 1 1 },
          { result := some { valueId := 2, typeId := uint64TypeId },
            op := .literal uint64TypeId zero8BytesV1 },
          { result := none, op := .stateStore 2 2 },
          { result := some { valueId := 3, typeId := uint64TypeId },
            op := .stateLoad 2 }],
        terminator := .return_ (some 3) }],
      loopBounds := #[], invariantSteps := none }
    let vZ : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    ∃ eFinal,
      runMachine false (fuel + 8)
        { data, pre, callable := clearCallable, isInitializer := false,
          context, overlay := #[b0, b1, b2], env := emptyEnv 4,
          effects := #[],
          occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
          responseCursor := 0, responses, loopCounts := #[],
          blockId := 0, instrIdx := 0, frames := #[],
          vaultNative, vaultToken } =
        (0,
          { data, pre, callable := clearCallable, isInitializer := false,
            context, overlay := #[zero8BytesV1, zero8BytesV1, zero8BytesV1],
            env := eFinal, effects := #[],
            occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
            responseCursor := 0, responses, loopCounts := #[],
            blockId := 0, instrIdx := 7, frames := #[],
            vaultNative, vaultToken },
          CandidateV1.returned (some vZ)) := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad 2 }],
      terminator := .return_ (some 3) }],
    loopBounds := #[], invariantSteps := none }
  let vZ : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hvc : valueCanonical data vZ = true := by
    simp [vZ, valueCanonical, hcanZero]
  have hblocks : clearCallable.blocks = #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad 2 }],
      terminator := .return_ (some 3) }] := by rfl
  have hresult : clearCallable.result.typeId = uint64TypeId := by rfl
  -- env progression
  have hs0e : (0 : ValueIdV1).toNat < (emptyEnv 4).size := by simp [emptyEnv, UInt32.toNat]
  let e1 := (emptyEnv 4).set 0 (some vZ) hs0e
  have hset0 : envSet (emptyEnv 4) 0 vZ = some e1 := by
    simpa [e1] using envSet_of_lt (emptyEnv 4) (0 : ValueIdV1) vZ hs0e
  have hs1e : (1 : ValueIdV1).toNat < e1.size := by
    simp [e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e2 := e1.set 1 (some vZ) hs1e
  have hset1 : envSet e1 1 vZ = some e2 := by
    simpa [e2] using envSet_of_lt e1 (1 : ValueIdV1) vZ hs1e
  have hs2e : (2 : ValueIdV1).toNat < e2.size := by
    simp [e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e3 := e2.set 2 (some vZ) hs2e
  have hset2 : envSet e2 2 vZ = some e3 := by
    simpa [e3] using envSet_of_lt e2 (2 : ValueIdV1) vZ hs2e
  have hs3e : (3 : ValueIdV1).toNat < e3.size := by
    simp [e3, e2, e1, emptyEnv, Array.size_set, UInt32.toNat]
  let e4 := e3.set 3 (some vZ) hs3e
  have hset3 : envSet e3 3 vZ = some e4 := by
    simpa [e4] using envSet_of_lt e3 (3 : ValueIdV1) vZ hs3e
  -- overlay progression
  have hov0_lt : (0 : Nat) < (#[b0, b1, b2] : Array ByteArray).size := by simp
  let ov1 : Array ByteArray := (#[b0, b1, b2] : Array ByteArray).set 0 zero8BytesV1 hov0_lt
  have hov1_lt : (1 : Nat) < ov1.size := by simp [ov1, Array.size_set]
  let ov2 : Array ByteArray := ov1.set 1 zero8BytesV1 hov1_lt
  have hov2_lt : (2 : Nat) < ov2.size := by simp [ov2, ov1, Array.size_set]
  let ov3 : Array ByteArray := ov2.set 2 zero8BytesV1 hov2_lt
  have h0? : ov3[0]? = some zero8BytesV1 := by
    have hne20 : (2 : Nat) ≠ 0 := by decide
    have hne10 : (1 : Nat) ≠ 0 := by decide
    simp only [ov3]
    rw [Array.getElem?_set_ne hov2_lt hne20]
    simp only [ov2]
    rw [Array.getElem?_set_ne hov1_lt hne10]
    simp only [ov1]
    exact Array.getElem?_set_self hov0_lt
  have h1? : ov3[1]? = some zero8BytesV1 := by
    have hne21 : (2 : Nat) ≠ 1 := by decide
    simp only [ov3]
    rw [Array.getElem?_set_ne hov2_lt hne21]
    simp only [ov2]
    exact Array.getElem?_set_self hov1_lt
  have h2? : ov3[2]? = some zero8BytesV1 := by
    simp only [ov3]
    exact Array.getElem?_set_self hov2_lt
  have hov3_eq : ov3 = #[zero8BytesV1, zero8BytesV1, zero8BytesV1] := by
    refine Array.ext_getElem? (fun i => ?_)
    match i with
    | 0 =>
        have : (#[zero8BytesV1, zero8BytesV1, zero8BytesV1] : Array ByteArray)[0]? =
            some zero8BytesV1 := by simp
        exact h0?.trans this.symm
    | 1 =>
        have : (#[zero8BytesV1, zero8BytesV1, zero8BytesV1] : Array ByteArray)[1]? =
            some zero8BytesV1 := by simp
        exact h1?.trans this.symm
    | 2 =>
        have : (#[zero8BytesV1, zero8BytesV1, zero8BytesV1] : Array ByteArray)[2]? =
            some zero8BytesV1 := by simp
        exact h2?.trans this.symm
    | n + 3 =>
        have hl' : ov3[n + 3]? = none := by
          apply Array.getElem?_eq_none
          simp [ov3, ov2, ov1, Array.size_set]
        have hr :
            (#[zero8BytesV1, zero8BytesV1, zero8BytesV1] : Array ByteArray)[n + 3]? =
              none := by
          apply Array.getElem?_eq_none
          simp
        exact hl'.trans hr.symm
  let mk (env : Array (Option ReferenceValueV1))
      (overlay : Array ByteArray) (idx : Nat) : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay, env, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := idx, frames := #[],
    vaultNative, vaultToken }
  -- Step 0: literal → e1
  have hexec0 :
      execInstruction (mk (emptyEnv 4) #[b0, b1, b2] 0)
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e1 #[b0, b1, b2] 0) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := by
      simpa [vZ] using hvc
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk (emptyEnv 4) #[b0, b1, b2] 0) 0 vZ e1
      (by simpa [mk, vZ] using hvc) hset0
  have step0 :
      runMachine false (fuel + 8) (mk (emptyEnv 4) #[b0, b1, b2] 0) =
        runMachine false (fuel + 7) (mk e1 #[b0, b1, b2] 1) := by
    have hfu : fuel + 8 = (fuel + 7).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec0]
  -- Step 1: store 0
  have hexec1 :
      execInstruction (mk e1 #[b0, b1, b2] 1)
        { result := none, op := .stateStore 0 0 } =
        .next (mk e1 ov1 1) := by
    have hg0 : envGet e1 0 = some vZ := by
      have h0 : e1[(0 : ValueIdV1).toNat]? = some (some vZ) :=
        Array.getElem?_set_self hs0e
      simp [envGet, e1, h0, UInt32.toNat]
    have hty : (vZ.typeId != uint64TypeId) = false := by simp [vZ, BEq.beq, bne]
    have hvc0' : valueCanonical data vZ = true := hvc
    have hst0' :
        data.logicalState[(0 : StateIdV1).toNat]? = some {
          id := 0, name := name0, typeId := uint64TypeId, visibility := .public_
        } := by
      simpa using hst0
    simp only [mk, execInstruction, hst0', hg0, hty, hvc0', Bool.not_true,
      Bool.false_eq_true, ↓reduceIte]
    have hlt :
        (0 : StateIdV1).toNat < (#[b0, b1, b2] : Array ByteArray).size := by
      simp [UInt32.toNat]
    simp only [hlt, ↓reduceDIte]
    -- set index (0:StateId).toNat = 0
    simp [mk, ov1, vZ, UInt32.toNat]
  have step1 :
      runMachine false (fuel + 7) (mk e1 #[b0, b1, b2] 1) =
        runMachine false (fuel + 6) (mk e1 ov1 2) := by
    have hfu : fuel + 7 = (fuel + 6).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec1]
  -- Step 2: literal → e2
  have hexec2 :
      execInstruction (mk e1 ov1 2)
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e2 ov1 2) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := by
      simpa [vZ] using hvc
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e1 ov1 2) 1 vZ e2
      (by simpa [mk, vZ] using hvc) hset1
  have step2 :
      runMachine false (fuel + 6) (mk e1 ov1 2) =
        runMachine false (fuel + 5) (mk e2 ov1 3) := by
    have hfu : fuel + 6 = (fuel + 5).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec2]
  -- Step 3: store 1
  have hexec3 :
      execInstruction (mk e2 ov1 3)
        { result := none, op := .stateStore 1 1 } =
        .next (mk e2 ov2 3) := by
    have hg1 : envGet e2 1 = some vZ := by
      have h1 : e2[(1 : ValueIdV1).toNat]? = some (some vZ) :=
        Array.getElem?_set_self hs1e
      simp [envGet, e2, h1, UInt32.toNat]
    have hty : (vZ.typeId != uint64TypeId) = false := by simp [vZ, BEq.beq, bne]
    have hvc0' : valueCanonical data vZ = true := hvc
    have hst1' :
        data.logicalState[(1 : StateIdV1).toNat]? = some {
          id := 1, name := name1, typeId := uint64TypeId, visibility := .public_
        } := by
      simpa using hst1
    simp only [mk, execInstruction, hst1', hg1, hty, hvc0', Bool.not_true,
      Bool.false_eq_true, ↓reduceIte]
    have hlt : (1 : StateIdV1).toNat < ov1.size := by
      simp [ov1, Array.size_set, UInt32.toNat]
    simp only [hlt, ↓reduceDIte]
    simp [mk, ov2, vZ, UInt32.toNat]
  have step3 :
      runMachine false (fuel + 5) (mk e2 ov1 3) =
        runMachine false (fuel + 4) (mk e2 ov2 4) := by
    have hfu : fuel + 5 = (fuel + 4).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec3]
  -- Step 4: literal → e3
  have hexec4 :
      execInstruction (mk e2 ov2 4)
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 } =
        .next (mk e3 ov2 4) := by
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hcan' : valueCanonical data
        { typeId := uint64TypeId, valueBytes := zero8BytesV1 } = true := by
      simpa [vZ] using hvc
    simp only [mk, execInstruction, hty, ↓reduceIte, hcan', Bool.not_true,
      Bool.false_eq_true]
    exact storeResult_envSet (mk e2 ov2 4) 2 vZ e3
      (by simpa [mk, vZ] using hvc) hset2
  have step4 :
      runMachine false (fuel + 4) (mk e2 ov2 4) =
        runMachine false (fuel + 3) (mk e3 ov2 5) := by
    have hfu : fuel + 4 = (fuel + 3).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec4]
  -- Step 5: store 2
  have hexec5 :
      execInstruction (mk e3 ov2 5)
        { result := none, op := .stateStore 2 2 } =
        .next (mk e3 ov3 5) := by
    have hg2 : envGet e3 2 = some vZ := by
      have h2 : e3[(2 : ValueIdV1).toNat]? = some (some vZ) :=
        Array.getElem?_set_self hs2e
      simp [envGet, e3, h2, UInt32.toNat]
    have hty : (vZ.typeId != uint64TypeId) = false := by simp [vZ, BEq.beq, bne]
    have hvc0' : valueCanonical data vZ = true := hvc
    have hst2' :
        data.logicalState[(2 : StateIdV1).toNat]? = some {
          id := 2, name := name2, typeId := uint64TypeId, visibility := .public_
        } := by
      simpa using hst2
    simp only [mk, execInstruction, hst2', hg2, hty, hvc0', Bool.not_true,
      Bool.false_eq_true, ↓reduceIte]
    have hlt : (2 : StateIdV1).toNat < ov2.size := by
      simp [ov2, ov1, Array.size_set, UInt32.toNat]
    simp only [hlt, ↓reduceDIte]
    simp [mk, ov3, vZ, UInt32.toNat]
  have step5 :
      runMachine false (fuel + 3) (mk e3 ov2 5) =
        runMachine false (fuel + 2) (mk e3 ov3 6) := by
    have hfu : fuel + 3 = (fuel + 2).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec5]
  -- Step 6: load 2 → e4
  have hexec6 :
      execInstruction (mk e3 ov3 6)
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad 2 } =
        .next (mk e4 ov3 6) := by
    have hoverlay :
        ov3[(2 : StateIdV1).toNat]? = some zero8BytesV1 := by
      simp [hov3_eq, UInt32.toNat]
    have hty : (uint64TypeId != uint64TypeId) = false := by simp [BEq.beq, bne]
    have hst2' :
        data.logicalState[(2 : StateIdV1).toNat]? = some {
          id := 2, name := name2, typeId := uint64TypeId, visibility := .public_
        } := by
      simpa using hst2
    simp only [mk, execInstruction, hst2', hoverlay, hty]
    have hstore := storeResult_envSet (mk e3 ov3 6) 3 vZ e4 hvc hset3
    simpa [mk, e4, vZ] using hstore
  have step6 :
      runMachine false (fuel + 2) (mk e3 ov3 6) =
        runMachine false (fuel + 1) (mk e4 ov3 7) := by
    have hfu : fuel + 2 = (fuel + 1).succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hexec6]
  -- Terminator return 3
  have hg3 : envGet e4 3 = some vZ := by
    have h3 : e4[(3 : ValueIdV1).toNat]? = some (some vZ) :=
      Array.getElem?_set_self hs3e
    simp [envGet, e4, h3, UInt32.toNat]
  have hret :
      execTerminator (mk e4 ov3 7) (.return_ (some 3)) =
        .done (mk e4 ov3 7) (.returned (some vZ)) := by
    have hunit : isUnitType data clearCallable.result.typeId = false := by
      simp [isUnitType, shapeOf, hresult, htypeU]
    have hty :
        (vZ.typeId != clearCallable.result.typeId || !valueCanonical data vZ) =
          false := by
      have hbeq : (vZ.typeId != clearCallable.result.typeId) = false := by
        simp [vZ, hresult, BEq.beq, bne]
      simp [hbeq, hvc]
    simp only [mk, execTerminator, hunit, ↓reduceIte, hg3, hty, ↓reduceIte, vZ]
    simp only [Bool.false_eq_true, ↓reduceIte]
  have stepT :
      runMachine false (fuel + 1) (mk e4 ov3 7) =
        (0, mk e4 ov3 7, CandidateV1.returned (some vZ)) := by
    have hfu : fuel + 1 = fuel.succ := by omega
    rw [hfu, runMachine]; simp [mk, hblocks, hret]
  refine ⟨e4, ?_⟩
  have hchain :
      runMachine false (fuel + 8) (mk (emptyEnv 4) #[b0, b1, b2] 0) =
        (0, mk e4 ov3 7, CandidateV1.returned (some vZ)) := by
    rw [step0, step1, step2, step3, step4, step5, step6, stepT]
  simpa [hov3_eq, mk] using hchain

/-- Ready clear-triple zeroes three UInt64 slots and returns zero from slot 2. -/
theorem stepReferenceSliceV1_ready_clear_triple_returned
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hinit : pre.initialized = true)
    (hencode :
      encodeLogicalStateValuesV1 data true
        #[zero8BytesV1, zero8BytesV1, zero8BytesV1] = .ok post)
    (hrespEmpty : responses.size = 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0, params := #[],
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 0 0 },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 1 1 },
              { result := some { valueId := 2, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 2 2 },
              { result := some { valueId := 3, typeId := uint64TypeId },
                op := .stateLoad 2 }],
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[b0, b1, b2] context false) :
    let vZ : ReferenceValueV1 :=
      { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .returned post (some vZ) #[] := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad 2 }],
      terminator := .return_ (some 3) }],
    loopBounds := #[], invariantSteps := none }
  let vZ : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hparams : clearCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      clearCallable #[b0, b1, b2] context false hgate hparams
  have hfuel : (999992 : Nat) + 8 = 1000000 := by decide
  have hmax : maxValueIdInCallable clearCallable = 3 :=
    maxValueIdInCallable_eq_three_of_clear_triple_shape clearCallable
      uint64TypeId zero8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable clearCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_clear_triple_shape clearCallable
      uint64TypeId zero8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_clear_triple_store_zero_return data pre b0 b1 b2 uint64TypeId
      name0 name1 name2 callableId entryName 999992 responses vault.native
      vault.token context htypeU hst0 hst1 hst2 hcanZero
  rcases hrun with ⟨eFinal, hrunEq⟩
  let mClr : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[b0, b1, b2], env := emptyEnv 4, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  let mEnd : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[zero8BytesV1, zero8BytesV1, zero8BytesV1],
    env := eFinal, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 7, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  have hrun1000000 :
      runMachine false 1000000 mClr =
        (0, mEnd, CandidateV1.returned (some vZ)) := by
    simpa [hfuel, mClr, mEnd, clearCallable, vZ] using hrunEq
  have heffects : mEnd.effects = #[] := by simp [mEnd]
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd]
  have hresp : mEnd.responses = responses := by simp [mEnd]
  have hencode' :
      encodeLogicalStateValuesV1 mEnd.data
        (pre.initialized || mEnd.isInitializer) mEnd.overlay = .ok post := by
    simp [mEnd, hinit, hencode]
  have hfin :=
    finalize_returned_of_encode mEnd pre (some vZ) post hcursor
      (by simpa [hresp] using hrespEmpty) hencode'
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mClr).2.1
          (runMachine false 1000000 mClr).2.2 pre := by
    simpa [mClr, hadmitted_data, hmax, heff0, clearCallable] using hnull
  rw [hnull', hrun1000000]
  simpa [heffects] using hfin

/-- Nonempty responses after clear-triple trap with exact pre. -/
theorem stepReferenceSliceV1_ready_clear_triple_nonempty_responses_traps
    (admitted : AdmittedReferenceSliceV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (data : SemanticProgramDataV1)
    (b0 b1 b2 : ByteArray)
    (uint64TypeId : TypeIdV1)
    (name0 name1 name2 : String)
    (callableId : CallableIdV1)
    (entryName : Option String)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (hadmitted_data : admitted.data = data)
    (htypeU : data.types[uint64TypeId.toNat]? = some {
      id := uint64TypeId, name := none, shape := .uint 64 })
    (hst0 : data.logicalState[0]? = some {
      id := 0, name := name0, typeId := uint64TypeId, visibility := .public_ })
    (hst1 : data.logicalState[1]? = some {
      id := 1, name := name1, typeId := uint64TypeId, visibility := .public_ })
    (hst2 : data.logicalState[2]? = some {
      id := 2, name := name2, typeId := uint64TypeId, visibility := .public_ })
    (hcanZero :
      validateValueBytesV1 data.types uint64TypeId zero8BytesV1 = .ok ())
    (hrespNe : responses.size ≠ 0)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready {
          id := callableId
          kind := .entry
          name := entryName
          params := #[]
          result := { typeId := uint64TypeId, visibility := .public_ }
          entryBlock := 0
          blocks := #[{
            id := 0, params := #[],
            instructions := #[
              { result := some { valueId := 0, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 0 0 },
              { result := some { valueId := 1, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 1 1 },
              { result := some { valueId := 2, typeId := uint64TypeId },
                op := .literal uint64TypeId zero8BytesV1 },
              { result := none, op := .stateStore 2 2 },
              { result := some { valueId := 3, typeId := uint64TypeId },
                op := .stateLoad 2 }],
            terminator := .return_ (some 3)
          }]
          loopBounds := #[]
          invariantSteps := none
        } #[b0, b1, b2] context false) :
    stepReferenceSliceV1 admitted pre invocation responses vault =
      .trapped .invalidExternalResponse pre := by
  let clearCallable : CallableV1 := {
    id := callableId, kind := .entry, name := entryName, params := #[],
    result := { typeId := uint64TypeId, visibility := .public_ },
    entryBlock := 0,
    blocks := #[{
      id := 0, params := #[],
      instructions := #[
        { result := some { valueId := 0, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 0 0 },
        { result := some { valueId := 1, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 1 1 },
        { result := some { valueId := 2, typeId := uint64TypeId },
          op := .literal uint64TypeId zero8BytesV1 },
        { result := none, op := .stateStore 2 2 },
        { result := some { valueId := 3, typeId := uint64TypeId },
          op := .stateLoad 2 }],
      terminator := .return_ (some 3) }],
    loopBounds := #[], invariantSteps := none }
  let vZ : ReferenceValueV1 :=
    { typeId := uint64TypeId, valueBytes := zero8BytesV1 }
  have hparams : clearCallable.params = #[] := rfl
  have hnull :=
    stepReferenceSliceV1_ready_nullary_eq admitted pre invocation responses vault
      clearCallable #[b0, b1, b2] context false hgate hparams
  have hfuel : (999992 : Nat) + 8 = 1000000 := by decide
  have hmax : maxValueIdInCallable clearCallable = 3 :=
    maxValueIdInCallable_eq_three_of_clear_triple_shape clearCallable
      uint64TypeId zero8BytesV1 (by rfl) (by rfl)
  have heff0 : maxEffectIdInCallable clearCallable = 0 :=
    maxEffectIdInCallable_eq_zero_of_clear_triple_shape clearCallable
      uint64TypeId zero8BytesV1 (by rfl) (by rfl)
  have hrun :=
    runMachine_clear_triple_store_zero_return data pre b0 b1 b2 uint64TypeId
      name0 name1 name2 callableId entryName 999992 responses vault.native
      vault.token context htypeU hst0 hst1 hst2 hcanZero
  rcases hrun with ⟨eFinal, hrunEq⟩
  let mClr : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[b0, b1, b2], env := emptyEnv 4, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 0, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  let mEnd : MachineV1 := {
    data, pre, callable := clearCallable, isInitializer := false,
    context, overlay := #[zero8BytesV1, zero8BytesV1, zero8BytesV1],
    env := eFinal, effects := #[],
    occCounts := Array.replicate (maxEffectIdInCallable clearCallable + 1) 0,
    responseCursor := 0, responses, loopCounts := #[],
    blockId := 0, instrIdx := 7, frames := #[],
    vaultNative := vault.native, vaultToken := vault.token }
  have hrun1000000 :
      runMachine false 1000000 mClr =
        (0, mEnd, CandidateV1.returned (some vZ)) := by
    simpa [hfuel, mClr, mEnd, clearCallable, vZ] using hrunEq
  have hcursor : mEnd.responseCursor = 0 := by simp [mEnd]
  have hresp : mEnd.responses = responses := by simp [mEnd]
  have hfin :
      finalize mEnd (.returned (some vZ)) pre =
        .trapped .invalidExternalResponse pre := by
    unfold finalize
    have hne : (mEnd.responseCursor != mEnd.responses.size) = true := by
      simp [hcursor, hresp, bne, BEq.beq]
      exact Ne.symm hrespNe
    simp only [hne, ↓reduceIte]
  have hnull' :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        finalize (runMachine false 1000000 mClr).2.1
          (runMachine false 1000000 mClr).2.2 pre := by
    simpa [mClr, hadmitted_data, hmax, heff0, clearCallable] using hnull
  rw [hnull', hrun1000000]
  exact hfin

end ProofForgeV2.Semantic.ReferenceV1
