import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.ReferenceV1 — D2-07 admitted primitive/effect reference
  execution engine (engineering subset; not formal `step` / TST-SEM-002/003).

  Owns closed runtime carriers (`ReferenceValueV1` … `OutcomeV1`), independent
  whole-program admission (`admitReferenceProgramSliceV1`), and the pure total
  machine `stepReferenceSliceV1`.

  Admitted surface:
    * types: Bool / UInt8 / UInt32 / UInt64 / Unit / Bytes
    * ops: Literal, Constant, StateLoad/Store, Unary/Binary on admitted shapes,
      CheckedCast (UInt↔UInt), Assert, Emit, ExternalCall, Schedule
    * terminators: Jump / Branch / Switch / Return / Revert / Trap
    * ExternalCall/Schedule args: Bool / UInt8/32/64 / Bytes only (no Unit)
    * view: no StateStore / Emit / ExternalCall / Schedule
    * pureFn body: no StateLoad/Store / Emit / ExternalCall / Schedule
      (PureCall itself rejected); pureFn may still be declared
    * root invocation of pureFn/invariant is `.invalidInvocation`

  Rejected at admission (never masquerade as runtime invalidCore; only
  internalInvariant defense if admission is bypassed):
    Int / Field / Array / Map / Option / Struct / Enum,
    Construct / Field* / Variant* / Index* / PureCall / ContextRead / Commit,
    view/pureFn effect-or-state violations, ExternalCall/Schedule Unit args.

  Semantics (SPEC-SEM-001 engineering):
    * dense ValueId env, state overlay, per-EffectId occurrence counters,
      response cursor, ordered provisional effects, fuel, loop-bound counters
    * external call consumes exactly one matching occurrence response
    * unique terminal finalizer: cursor exhaustion before publish; trailing
      responses → `.invalidExternalResponse` and discard overlay/effects
    * only `.returned` commits overlay/effects; init success sets
      `initialized=true`; revert/trap return pre byte-for-byte

  No `partial` / `unsafe` / `IO`. Does not import alpha Core.Semantics /
  SemanticIR. Does not export formal `step`.
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

private def typeShapeAdmitted (shape : TypeShapeV1) :
    Except ReferenceAdmissionErrorV1 Unit :=
  match shape with
  | .bool => pure ()
  | .uint 8 | .uint 32 | .uint 64 => pure ()
  | .uint w =>
      admitFail s!"unsupported UInt width {w} (admitted: 8/32/64)"
  | .unit => pure ()
  | .bytes _ => pure ()
  | .int w => admitFail s!"unsupported Int{w}"
  | .field _ => admitFail "unsupported Field"
  | .array _ _ => admitFail "unsupported aggregate Array"
  | .map _ _ => admitFail "unsupported aggregate Map"
  | .option _ => admitFail "unsupported aggregate Option"
  | .struct _ => admitFail "unsupported aggregate Struct"
  | .enum _ => admitFail "unsupported aggregate Enum"
  | .principal => admitFail "unsupported Principal"

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
  | .construct _ _ _ => admitFail "unsupported op Construct"
  | .fieldGet _ _ => admitFail "unsupported op FieldGet"
  | .fieldSet _ _ _ => admitFail "unsupported op FieldSet"
  | .variantTag _ => admitFail "unsupported op VariantTag"
  | .variantPayload _ _ _ => admitFail "unsupported op VariantPayload"
  | .indexGet _ _ => admitFail "unsupported IndexGet (Array/Map/Bytes index)"
  | .indexSet _ _ _ => admitFail "unsupported IndexSet (Array/Map/Bytes index)"
  | .pureCall _ _ => pure ()
  | .contextRead _ => admitFail "unsupported op ContextRead"
  | .commit _ => admitFail "unsupported op Commit"

/-- ExternalCall/Schedule arg type shapes admitted for this slice (no Unit). -/
private def externalArgShapeAdmitted (shape : TypeShapeV1) :
    Except ReferenceAdmissionErrorV1 Unit :=
  match shape with
  | .bool => pure ()
  | .uint 8 | .uint 32 | .uint 64 => pure ()
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
      -- pureFn: no state / effects (PureCall itself already rejected)
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

/-- Whole-program admission: structure gate then admitted-type/op/kind scan. -/
def admitReferenceProgramSliceV1 (program : SemanticProgramV1) :
    Except ReferenceAdmissionErrorV1 AdmittedReferenceSliceV1 := do
  let data ←
    match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error e => .error (.wire e)
  admitTypes data.types
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

private def uintByteLen (width : Nat) : Nat := width / 8

private def uintMax (width : Nat) : Nat := Nat.pow 2 width

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
      match uintWidth data operand.typeId, uintWidth data resultTypeId with
      | some w, some w' =>
          if !(w == w' && operand.typeId == resultTypeId) then
            .error (.trapped .invalidCore)
          else
            let len := uintByteLen w
            if operand.valueBytes.size != len then
              .error (.trapped .invalidCore)
            else
              let mask := uintMax w - 1
              let n := leBytesToNat operand.valueBytes
              .ok {
                typeId := resultTypeId
                valueBytes := natToLeBytes (mask - n) len
              }
      | _, _ => .error (.trapped .invalidCore)
  | .neg => .error (.trapped .invalidCore)

private def evalBinary (data : SemanticProgramDataV1) (op : BinaryOpV1)
    (lhs rhs : ReferenceValueV1) (resultTypeId : TypeIdV1) :
    Except CandidateV1 ReferenceValueV1 :=
  match op with
  | .add | .sub | .mul | .div | .mod =>
      match uintWidth data lhs.typeId, uintWidth data rhs.typeId,
            uintWidth data resultTypeId with
      | some w, some wr, some wres =>
          if !(w == wr && w == wres && lhs.typeId == rhs.typeId &&
              lhs.typeId == resultTypeId) then
            .error (.trapped .invalidCore)
          else
            let len := uintByteLen w
            if !(lhs.valueBytes.size == len && rhs.valueBytes.size == len) then
              .error (.trapped .invalidCore)
            else
              let a := leBytesToNat lhs.valueBytes
              let b := leBytesToNat rhs.valueBytes
              let maxV := uintMax w
              match op with
              | .add =>
                  let s := a + b
                  if s ≥ maxV then
                    .error (.reverted (.standard .arithmeticOverflow))
                  else
                    .ok { typeId := resultTypeId, valueBytes := natToLeBytes s len }
              | .sub =>
                  if a < b then
                    .error (.reverted (.standard .arithmeticUnderflow))
                  else
                    .ok {
                      typeId := resultTypeId
                      valueBytes := natToLeBytes (a - b) len
                    }
              | .mul =>
                  let p := a * b
                  if p ≥ maxV then
                    .error (.reverted (.standard .arithmeticOverflow))
                  else
                    .ok { typeId := resultTypeId, valueBytes := natToLeBytes p len }
              | .div =>
                  if b == 0 then
                    .error (.reverted (.standard .divisionByZero))
                  else
                    .ok {
                      typeId := resultTypeId
                      valueBytes := natToLeBytes (a / b) len
                    }
              | .mod =>
                  if b == 0 then
                    .error (.reverted (.standard .divisionByZero))
                  else
                    .ok {
                      typeId := resultTypeId
                      valueBytes := natToLeBytes (a % b) len
                    }
              | _ => .error (.trapped .internalInvariant)
      | _, _, _ => .error (.trapped .invalidCore)
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
      match uintWidth data lhs.typeId, uintWidth data rhs.typeId with
      | some w, some wr =>
          if !(w == wr && lhs.typeId == rhs.typeId && isBoolType data resultTypeId) then
            .error (.trapped .invalidCore)
          else
            let a := leBytesToNat lhs.valueBytes
            let b := leBytesToNat rhs.valueBytes
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
      | _, _ => .error (.trapped .invalidCore)
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
      match uintWidth data lhs.typeId, uintWidth data rhs.typeId,
            uintWidth data resultTypeId with
      | some w, some wr, some wres =>
          if !(w == wr && w == wres && lhs.typeId == rhs.typeId &&
              lhs.typeId == resultTypeId) then
            .error (.trapped .invalidCore)
          else
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
      | _, _, _ => .error (.trapped .invalidCore)
  | .shl | .shr =>
      match uintWidth data lhs.typeId, uintWidth data resultTypeId with
      | some w, some wres =>
          if !(w == wres && lhs.typeId == resultTypeId) then
            .error (.trapped .invalidCore)
          else
            match uintWidth data rhs.typeId with
            | some 32 =>
                let shift := leBytesToNat rhs.valueBytes
                if shift ≥ w then
                  .error (.reverted (.standard .invalidShift))
                else
                  let len := uintByteLen w
                  let a := leBytesToNat lhs.valueBytes
                  let maxV := uintMax w
                  match op with
                  | .shl =>
                      let r := Nat.shiftLeft a shift
                      if r ≥ maxV then
                        .error (.reverted (.standard .arithmeticOverflow))
                      else
                        .ok {
                          typeId := resultTypeId
                          valueBytes := natToLeBytes r len
                        }
                  | .shr =>
                      .ok {
                        typeId := resultTypeId
                        valueBytes := natToLeBytes (Nat.shiftRight a shift) len
                      }
                  | _ => .error (.trapped .internalInvariant)
            | _ => .error (.trapped .invalidCore)
      | _, _ => .error (.trapped .invalidCore)

private def evalCheckedCast (data : SemanticProgramDataV1) (src : ReferenceValueV1)
    (toType : TypeIdV1) (resultTypeId : TypeIdV1) :
    Except CandidateV1 ReferenceValueV1 :=
  if resultTypeId != toType then
    .error (.trapped .invalidCore)
  else
    match uintWidth data src.typeId, uintWidth data toType with
    | some _sw, some tw =>
        let sn := leBytesToNat src.valueBytes
        if sn ≥ uintMax tw then
          .error (.reverted (.standard .castOutOfRange))
        else
          .ok {
            typeId := toType
            valueBytes := natToLeBytes sn (uintByteLen tw)
          }
    | _, _ => .error (.trapped .invalidCore)

private def storeResult (m : MachineV1) (vid : ValueIdV1) (v : ReferenceValueV1) :
    ExecResult :=
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
          fromEval m vd.valueId (evalCheckedCast m.data src toType vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .unary op operandId =>
      match instr.result, envGet m.env operandId with
      | some vd, some operand =>
          fromEval m vd.valueId (evalUnary m.data op operand vd.typeId)
      | _, _ => .done m (.trapped .invalidCore)
  | .binary op lhsId rhsId =>
      match instr.result, envGet m.env lhsId, envGet m.env rhsId with
      | some vd, some lhs, some rhs =>
          fromEval m vd.valueId (evalBinary m.data op lhs rhs vd.typeId)
      | _, _, _ => .done m (.trapped .invalidCore)
  | .assert_ condId errorId args =>
      match instr.result with
      | some _ => .done m (.trapped .invalidCore)
      | none =>
          match envGet m.env condId with
          | none => .done m (.trapped .invalidCore)
          | some cond =>
              if !isBoolType m.data cond.typeId then
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
                        | .returned => .next m3
                        | .reverted =>
                            .done m3 (.reverted (.externalCallReverted occ))
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
  | .construct _ _ _ | .fieldGet _ _ | .fieldSet _ _ _ | .variantTag _
  | .variantPayload _ _ _ | .indexGet _ _ | .indexSet _ _ _
  | .pureCall _ _ | .contextRead _ | .commit _ =>
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
                          if v.typeId != bp.typeId then
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
          if !isBoolType m.data cond.typeId then
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
                if v.typeId != m.callable.result.typeId then
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

private def runMachine : (fuel : Nat) → MachineV1 → Nat × MachineV1 × CandidateV1
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
                        if callee.kind != .pureFn then (0, m, .trapped .invalidCore) else
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
                                runMachine fuel { m with
                                  callable := callee
                                  isInitializer := false
                                  env := calleeEnv
                                  loopCounts := Array.replicate callee.loopBounds.size (0 : UInt32)
                                  blockId := callee.entryBlock
                                  instrIdx := 0
                                  frames := m.frames.push frame }
                | _, _ =>
                    match execInstruction m instr with
                    | .done m' cand => (0, m', cand)
                    | .next m1 =>
                        runMachine fuel { m1 with instrIdx := m1.instrIdx + 1 }
          else
            match block.terminator, m.frames.back? with
            | .return_ value?, some frame =>
                -- Pop the pure-call frame: the callee result continues the
                -- suspended caller (pureFn always returns a value).
                match value? with
                | none => (0, m, .trapped .invalidCore)
                | some vid =>
                    match envGet m.env vid with
                    | none => (0, m, .trapped .invalidCore)
                    | some v =>
                        match envSet frame.env frame.resultValueId v with
                        | none => (0, m, .trapped .invalidCore)
                        | some env' =>
                            runMachine fuel { m with
                              callable := frame.callable
                              isInitializer := m.isInitializer
                              env := env'
                              loopCounts := frame.loopCounts
                              blockId := frame.blockId
                              instrIdx := frame.instrIdx
                              frames := m.frames.pop }
            | _, _ =>
                match execTerminator m block.terminator with
                | .done m' cand => (0, m', cand)
                | .next mNext => runMachine fuel mNext

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
      (isInitializer : Bool)

/-- Shape checks (id/kind/arity/type/context) → invalidInvocation.
    Lifecycle (uninit / alreadyInit / internal) → lifecycle candidate.
    Success → ready. -/
private def gateInvocation
    (admitted : AdmittedReferenceSliceV1) (pre : LogicalStateV1)
    (invocation : InvocationV1) : InvocationGateV1 :=
  let data := admitted.data
  let program := admitted.program
  if !invocation.context.isEmpty then
    .invalidInvocation
  else
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
            let isInit := callable.kind == .initializer
            match initialLogicalStateV1 program with
            | .error _ =>
                -- Admitted program always validates; treat as lifecycle fault.
                .lifecycle (.trapped .internalInvariant)
            | .ok initial =>
                if isInit then
                  if logicalStateBytesEq pre initial then
                    match decodeLogicalStateValuesV1 data pre with
                    | .ok overlay => .ready callable overlay true
                    | .error _ =>
                        .lifecycle (.trapped .internalInvariant)
                  else if pre.initialized && stateConformsBoolV1 program pre then
                    .lifecycle (.reverted (.standard .alreadyInitialized))
                  else
                    .invalidInvocation
                else if pre.initialized && stateConformsBoolV1 program pre then
                  match decodeLogicalStateValuesV1 data pre with
                  | .ok overlay => .ready callable overlay false
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
  | .ready callable overlay isInitializer =>
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
          let (_fuelLeft, mEnd, cand) := runMachine 1000000 m0
          finalize mEnd cand

end ProofForgeV2.Semantic.ReferenceV1
