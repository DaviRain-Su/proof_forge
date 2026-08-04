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

/-- Reference-only Map entry budget for static resource admission.
    Wire `maxMapEntriesV1` (1e6) makes worst-case UInt64/UInt64 Map width exceed
    `maxCanonicalValueBytes`, which blocked product empty-Map state entirely.
    Runtime IndexSet still enforces the wire ceiling via valueBytes validation.
    R-1: 4096 matches maxTypeLength-scale containers. -/
private def maxMapEntriesReferenceBudgetV1 : Nat := 4096

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
  | .commit _ => pure ()

/-- ExternalCall/Schedule arg type shapes admitted for this slice (no Unit).
    R-1 / N-8: all legal UInt/Int widths (not only 8/32/64). -/
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
      -- Map has exactly one admitted constructor: empty, index 0, no args.
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

/-- Prove that every admitted fixed-width value can be materialized within
    the canonical byte, recursive-shape, and cumulative construction-work
    limits. This explicit-stack
    postorder walk avoids host recursion and allocation amplification from compact
    Struct DAG declarations. Wire has already rejected Struct-only cycles;
    unresolved rows still fail closed rather than relying on that premise. -/
private def admitTypeResourceBounds (types : Array TypeDeclV1) :
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
                  unless maxMapEntriesReferenceBudgetV1 == 0 ||
                      8 ≤ maxCanonicalValueBytes / maxMapEntriesReferenceBudgetV1 do
                    return ← admitFail "Map canonical value exceeds byte limit"
              | _ => pure ()
              let headerWidth := match decl.shape with
                | .struct _ | .array _ _ => 0
                | .option _ => 1
                | .map _ _ =>
                    let count := maxMapEntriesReferenceBudgetV1
                    4 + count * 8
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
                    | .map _ _ => maxMapEntriesReferenceBudgetV1
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
                -- Map IndexSet validates the new key/value, traverses the old
                -- map, scans each entry, and writes the complete new map under
                -- one Wire budget. Prove that worst case here (Reference budget).
                match decl.shape with
                | .map _ _ =>
                    unless directChildWork ≤ maxCanonicalProgramBytes - altWork do
                      return ← admitFail "Map canonical update work exceeds limit"
                    altWork := altWork + directChildWork
                    unless maxMapEntriesReferenceBudgetV1 ≤ maxCanonicalProgramBytes - altWork do
                      return ← admitFail "Map canonical update work exceeds limit"
                    altWork := altWork + maxMapEntriesReferenceBudgetV1
                    unless maxMapEntriesReferenceBudgetV1 ≤ maxCanonicalProgramBytes - altWork do
                      return ← admitFail "Map canonical update work exceeds limit"
                    altWork := altWork + maxMapEntriesReferenceBudgetV1
                    unless ownWork ≤ maxCanonicalProgramBytes - altWork do
                      return ← admitFail "Map canonical update work exceeds limit"
                    altWork := altWork + ownWork
                | _ => pure ()
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

/-- Whole-program admission: structure gate then admitted-type/op/kind scan. -/
def admitReferenceProgramSliceV1 (program : SemanticProgramV1) :
    Except ReferenceAdmissionErrorV1 AdmittedReferenceSliceV1 := do
  let data ←
    match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error e => .error (.wire e)
  admitTypes data.types
  let (typeWidths, typeWorks) ← admitTypeResourceBounds data.types
  -- `initialLogicalStateV1` materializes every default plus its u32 length
  -- prefix. Bound that aggregate before any invocation can allocate it.
  -- R-1: Map *defaults* are empty (`u32le(0)` = 4 bytes). Worst-case Map
  -- width/work (maxMapEntriesV1) remains in typeWidths/typeWorks for IndexSet
  -- budgeting, but must not make empty Map state unadmissible.
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
  pure ⟨program, data⟩

/-! ### Internal value helpers -/

private def leBytesToNat (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  let mut place : Nat := 1
  for i in [:bytes.size] do
    -- Loop bound guarantees `i < bytes.size`; byteAt? avoids get! panic path.
    match byteAt? bytes i with
    | some b => n := n + b.toNat * place
    | none => pure ()
    place := place * 256
  pure n

private def natToLeBytes (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

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

private structure MachineV1 where
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

private inductive CandidateV1 where
  | returned (value : Option ReferenceValueV1)
  | reverted (reason : SemanticRevertV1)
  | trapped (fault : SemanticFaultV1)

/-- Instruction/terminator local result: continue machine or halt with candidate. -/
private inductive ExecResult where
  | next (m : MachineV1)
  | done (m : MachineV1) (cand : CandidateV1)

private def maxValueIdInCallable (c : CallableV1) : Nat := Id.run do
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

private def maxEffectIdInCallable (c : CallableV1) : Nat := Id.run do
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

private def emptyEnv (size : Nat) : Array (Option ReferenceValueV1) :=
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

private def finalize (m : MachineV1) (cand : CandidateV1) : OutcomeV1 :=
  if m.responseCursor != m.responses.size then
    .trapped .invalidExternalResponse m.pre
  else
    match cand with
    | .trapped fault => .trapped fault m.pre
    | .reverted reason => .reverted reason m.pre
    | .returned value =>
        let postInit := m.pre.initialized || m.isInitializer
        match encodeLogicalStateValuesV1 m.data postInit m.overlay with
        | .ok post => .returned post value m.effects
        | .error _ => .trapped .internalInvariant m.pre

/-! ### Primitive evaluation -/

private def evalUnary (data : SemanticProgramDataV1) (op : UnaryOpV1)
    (operand : ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except CandidateV1 ReferenceValueV1 :=
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
    Except CandidateV1 ReferenceValueV1 :=
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
    Except CandidateV1 ReferenceValueV1 :=
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
    Except CandidateV1 ReferenceValueV1 := do
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
    Except CandidateV1 ReferenceValueV1 := do
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
    Except CandidateV1 ReferenceValueV1 := do
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
    Except CandidateV1 ReferenceValueV1 := do
  unless resultTypeId == typeId && constructorIndex == 0 && args.isEmpty do
    throw (.trapped .invalidCore)
  unless isUnitType data typeId do throw (.trapped .invalidCore)
  pure { typeId, valueBytes := ByteArray.empty }

private def checkedIndex (data : SemanticProgramDataV1)
    (index : ReferenceValueV1) : Except CandidateV1 Nat := do
  match data.types[index.typeId.toNat]? with
  | some { shape := .uint 32, .. } => pure ()
  | _ => throw (.trapped .invalidCore)
  unless index.valueBytes.size == 4 && valueCanonical data index do
    throw (.trapped .invalidCore)
  pure (leBytesToNat index.valueBytes)

private def evalIndexGet (data : SemanticProgramDataV1) (base index : ReferenceValueV1)
    (resultTypeId : TypeIdV1) : Except CandidateV1 ReferenceValueV1 := do
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
    (resultTypeId : TypeIdV1) : Except CandidateV1 ReferenceValueV1 := do
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
    Except CandidateV1 ReferenceValueV1 := do
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
    (resultTypeId : TypeIdV1) : Except CandidateV1 ReferenceValueV1 := do
  match data.types[resultTypeId.toNat]? with
  | some { shape := .uint 32, .. } => pure ()
  | _ => throw (.trapped .invalidCore)
  match splitCanonicalVariantValueV1 data.types base.typeId base.valueBytes with
  | .ok (tag, _) => pure { typeId := resultTypeId, valueBytes := natToLeBytes tag.toNat 4 }
  | .error _ => throw (.trapped .invalidCore)

private def evalVariantPayload (data : SemanticProgramDataV1)
    (base : ReferenceValueV1) (variantIndex payloadIndex : UInt32)
    (resultTypeId : TypeIdV1) : Except CandidateV1 ReferenceValueV1 := do
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
    (resultTypeId : TypeIdV1) : Except CandidateV1 ReferenceValueV1 := do
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
    Except CandidateV1 ReferenceValueV1 := do
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

private def fromEval (m : MachineV1) (vid : ValueIdV1)
    (r : Except CandidateV1 ReferenceValueV1) : ExecResult :=
  match r with
  | .error cand => .done m cand
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
                        | none, _ => .next m3
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
                  .next { m1 with effects := m1.effects.push eff }
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

private def runMachine (chargeFrameEntry : Bool) :
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

/-! ### Invocation validation -/

private def logicalStateBytesEq (a b : LogicalStateV1) : Bool :=
  a.initialized == b.initialized && bytesEqual a.canonicalValues b.canonicalValues

/-- Gate after shape check: lifecycle candidates still subject to response
    exhaustion; only invalidInvocation bypasses the cursor. -/
private inductive InvocationGateV1 where
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

/-- Shape checks (id/kind/arity/type/context) → invalidInvocation.
    Lifecycle (uninit / alreadyInit / internal) → lifecycle candidate.
    Success → ready. -/
private def gateInvocation
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
    (responses : ExternalResponsesV1) : OutcomeV1 :=
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
          }
          let (_fuelLeft, mEnd, cand) := runMachine false 1000000 m0
          finalize mEnd cand

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

end ProofForgeV2.Semantic.ReferenceV1
