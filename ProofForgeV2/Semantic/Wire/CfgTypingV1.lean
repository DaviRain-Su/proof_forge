import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1
import ProofForgeV2.Semantic.Wire.CfgShapeV1

/-!
  ProofForgeV2.Semantic.Wire.CfgTypingV1 — def-site TypeId range, terminator
  typing, per-op type/result contract, and per-callable CFG shape orchestration
  (SPEC §6.2 layers h–j + validateCallableCfgShape).

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-! ### Def-site TypeId range + terminator typing (SPEC §6.2 — CFG layers h/i)

    Step h: every block-param TypeId and every instruction-result ValueDef
    TypeId is in `[0, types.size)`. Callable `ParameterV1.typeId` and
    `CallableResultV1.typeId` are already checked at step 2 of
    `validateSemanticProgramStructureV1`; do NOT duplicate. Failure →
    `.badReference` (same as `checkTypeIdInRange`).

    Step i: terminator typing against a ValueId→TypeId table built from def
    sites. Branch condition must be the Bool TypeId; switch case TypeId must
    equal the scrutinee's TypeId; jump/branch/switch target args must match
    the target block params positionally; `return_ (some v)` must match the
    callable result TypeId. `Term.Revert` errorId must resolve and args must
    positionally match ErrorDecl fields. `return_ none` / `trap` need no
    additional type check. All step i failures → `.badCfg`. Bounded,
    non-recursive, total. Emit/externalCall/schedule declaration joins,
    TypeKey anonymous ranking, and provenance join remain out of scope. -/

/-- Collect every ValueId → TypeId definition in the same three global
    SPEC §6 passes as `collectValueDefSites`: callable params; all block params;
    all instruction results. Bounded and non-recursive. Production reaches this
    only after step-f canonical assignment; no duplicate check is repeated. -/
def collectValueTypeDefs (c : CallableV1) : Array (ValueIdV1 × TypeIdV1) :=
  Id.run do
    let mut defs : Array (ValueIdV1 × TypeIdV1) := #[]
    for p in c.params do
      defs := defs.push (p.valueId, p.typeId)
    for b in c.blocks do
      for bp in b.params do
        defs := defs.push (bp.valueId, bp.typeId)
    for b in c.blocks do
      for instr in b.instructions do
        match instr.result with
        | some vdef => defs := defs.push (vdef.valueId, vdef.typeId)
        | none => pure ()
    pure defs

/-- The unique TypeId whose shape satisfies `pred`, if exactly one exists.
    Bounded, non-recursive. Zero or multiple matches yield `none`. Shared by
    `boolTypeId` / `uint32TypeId` / `uint8TypeId` as defense-in-depth relative
    to the earlier primitive anonymous TypeKey gate (duplicates fail there as
    `.nonCanonical` before step j). -/
def uniqueShapeTypeId (types : Array TypeDeclV1)
    (pred : TypeShapeV1 → Bool) : Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut dup : Bool := false
  let mut i : Nat := 0
  for t in types do
    if pred t.shape then
      match r with
      | none => r := some (UInt32.ofNat i)
      | some _ => dup := true
    i := i + 1
  if dup then pure none else pure r

/-- The unique TypeId whose shape is `.bool`, if exactly one exists.
    Bounded, non-recursive. Defense-in-depth relative to the earlier
    primitive anonymous TypeKey gate (duplicates fail there as
    `.nonCanonical`). -/
def boolTypeId (types : Array TypeDeclV1) : Option TypeIdV1 :=
  uniqueShapeTypeId types fun
    | .bool => true
    | _ => false

/-- The unique TypeId whose shape is `.uint 32`, if exactly one exists.
    Bounded, non-recursive. Defense-in-depth relative to the earlier
    primitive anonymous TypeKey gate (duplicates fail there as
    `.nonCanonical` before step j). This helper still fails closed for direct
    internal use; recursive/full TypeKey closure and ranking remain pending. -/
def uint32TypeId (types : Array TypeDeclV1) : Option TypeIdV1 :=
  uniqueShapeTypeId types fun
    | .uint 32 => true
    | _ => false

/-- The unique TypeId whose shape is `.uint 8`, if exactly one exists.
    Bounded and non-recursive. Bytes IndexGet/IndexSet require the unique
    structurally interned UInt8 TypeId. The earlier primitive anonymous
    TypeKey gate rejects duplicates as `.nonCanonical`; this defensive helper
    still returns `none` for zero or duplicate matches. -/
def uint8TypeId (types : Array TypeDeclV1) : Option TypeIdV1 :=
  uniqueShapeTypeId types fun
    | .uint 8 => true
    | _ => false

/-! ### Shared per-callable op/terminator typing environment

    Built once after `collectValueTypeDefs` inside `validateCallableCfgShape`
    and shared by step i (terminator typing) and step j (per-op typing).
    Uniqueness-gated Bool/UInt32/UInt8 resolvers are materialised once;
    ValueId→TypeId and TypeId→shape lookups reuse the same defTypes/types. -/

/-- Per-callable typing environment for CFG steps i–j. -/
structure OpTypingEnv where
  /-- ValueId→TypeId def-site table (exactly-once by step f). -/
  defTypes : Array (ValueIdV1 × TypeIdV1)
  /-- Program type table (shared with `data.types`). -/
  types : Array TypeDeclV1
  /-- Full program data for declaration-table joins (constant/state/…). -/
  data : SemanticProgramDataV1
  /-- Unique Bool TypeId, if exactly one exists. -/
  boolT : Option TypeIdV1
  /-- Unique UInt32 TypeId, if exactly one exists. -/
  u32T : Option TypeIdV1
  /-- Unique UInt8 TypeId, if exactly one exists. -/
  u8T : Option TypeIdV1

/-- Mint the per-callable typing environment once after step h's defTypes. -/
private def mkOpTypingEnv (defTypes : Array (ValueIdV1 × TypeIdV1))
    (data : SemanticProgramDataV1) : OpTypingEnv :=
  let types := data.types
  {
    defTypes := defTypes
    types := types
    data := data
    boolT := boolTypeId types
    u32T := uint32TypeId types
    u8T := uint8TypeId types
  }

/-- Bounded ValueId→TypeId lookup (defTypes is exactly-once by step f). -/
private def OpTypingEnv.typeOf (env : OpTypingEnv) (vid : ValueIdV1) :
    Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  for (v, t) in env.defTypes do
    if v == vid then
      r := some t
      break
  pure r

/-- Shape of a TypeId, if in range. -/
private def OpTypingEnv.shapeOf (env : OpTypingEnv) (tid : TypeIdV1) :
    Option TypeShapeV1 := Id.run do
  let mut r : Option TypeShapeV1 := none
  let n := tid.toNat
  if n < env.types.size then
    match env.types[n]? with
    | some d => r := some d.shape
    | none => pure ()
  pure r

/-- Resolve a ValueId operand's TypeId (missing def → `.badCfg`). -/
private def requireOperand (env : OpTypingEnv) (vid : ValueIdV1) :
    Except SemanticWireErrorV1 TypeIdV1 :=
  match env.typeOf vid with
  | none => err .badCfg
  | some t => pure t

/-- Require result present and equal to `tid` (SPEC §4.3/§5.1). -/
private def requireResultEq (result? : Option ValueDefV1) (tid : TypeIdV1) :
    Except SemanticWireErrorV1 Unit :=
  match result? with
  | some vdef => unless vdef.typeId == tid do err .badCfg
  | none => err .badCfg

/-- Require result present (presence-only value-producing ops). -/
private def requireResultPresent (result? : Option ValueDefV1) :
    Except SemanticWireErrorV1 Unit :=
  match result? with
  | some _ => pure ()
  | none => err .badCfg

/-- Require void op carries `result := none`. -/
private def requireVoid (result? : Option ValueDefV1) :
    Except SemanticWireErrorV1 Unit :=
  match result? with
  | some _ => err .badCfg
  | none => pure ()

/-- Resolve shape of `tid` and project via `pred` (any miss → `.badCfg`). -/
private def requireShape {α : Type} (env : OpTypingEnv) (tid : TypeIdV1)
    (pred : TypeShapeV1 → Option α) : Except SemanticWireErrorV1 α :=
  match env.shapeOf tid with
  | none => err .badCfg
  | some shape =>
      match pred shape with
      | none => err .badCfg
      | some a => pure a

/-- Exact-size positional arg type check against expected TypeIds. -/
private def checkArgsPositional (env : OpTypingEnv)
    (args : Array ValueIdV1) (expected : Array TypeIdV1) :
    Except SemanticWireErrorV1 Unit := do
  unless args.size == expected.size do
    return ← err .badCfg
  if args.isEmpty then return
  let mut i : Nat := 0
  while i < args.size do
    let argT ← requireOperand env args[i]!
    match expected[i]? with
    | none => return ← err .badCfg
    | some expT => unless argT == expT do return ← err .badCfg
    i := i + 1
  pure ()

private theorem checkArgsPositional_empty_eq_ok (env : OpTypingEnv) :
    checkArgsPositional env #[] #[] = .ok () := by
  rfl

/-- Exact-size positional arg type check against interface fields
    (Term.Revert / Op.Assert(some) / Op.Emit). Identical modulo table lookup. -/
private def checkInterfaceArgs (env : OpTypingEnv)
    (fields : Array InterfaceFieldV1) (args : Array ValueIdV1) :
    Except SemanticWireErrorV1 Unit := do
  unless args.size == fields.size do
    return ← err .badCfg
  let mut i : Nat := 0
  while i < args.size do
    let argT ← requireOperand env args[i]!
    match fields[i]? with
    | none => return ← err .badCfg
    | some field => unless argT == field.typeId do return ← err .badCfg
    i := i + 1
  pure ()

/-- Step h: every def-site TypeId (block params + instruction results) is in
    `[0, typeCount)`. Callable param/result TypeIds are already checked at
    step 2; do NOT duplicate. Failure → `.badReference`. -/
def checkDefSiteTypeIdsInRange (defTypes : Array (ValueIdV1 × TypeIdV1))
    (typeCount : Nat) : Except SemanticWireErrorV1 Unit := do
  for (_, tid) in defTypes do
    checkTypeIdInRange tid typeCount

/-- Step i: terminator typing against a shared `OpTypingEnv` plus the
    ErrorDecl table for Term.Revert. Bounded lookup of `typeOf vid`; missing
    def → `.badCfg` (step f owns existence, but we stay total). All failures
    → `.badCfg`. -/
def checkTerminatorTyping (c : CallableV1) (env : OpTypingEnv) :
    Except SemanticWireErrorV1 Unit := do
  -- Block params of block id `bid`, if in range (step c owns OOR).
  let blockParams (bid : BlockIdV1) : Array BlockParameterV1 := Id.run do
    let mut r : Array BlockParameterV1 := #[]
    let n := bid.toNat
    if n < c.blocks.size then
      match c.blocks[n]? with
      | some b => r := b.params
      | none => pure ()
    pure r
  -- Positional arg-type check against target block params (min-length guard
  -- to stay total; arity is owned by step c.5). Distinct from the exact-size
  -- `checkArgsPositional` used by op contracts.
  let checkTargetArgs (target : JumpTargetV1) :
      Except SemanticWireErrorV1 Unit := do
    let params := blockParams target.blockId
    let n := min target.args.size params.size
    let mut i : Nat := 0
    while i < n do
      let argT ← requireOperand env target.args[i]!
      match params[i]? with
      | none => return ← err .badCfg
      | some bp =>
          unless argT == bp.typeId do
            return ← err .badCfg
      i := i + 1
    pure ()
  for b in c.blocks do
    match b.terminator with
    | .jump target => checkTargetArgs target
    | .branch cond thenT elseT => do
        -- condition must be the Bool TypeId
        match env.boolT with
        | none => return ← err .badCfg
        | some boolId =>
            let condT ← requireOperand env cond
            unless condT == boolId do return ← err .badCfg
        checkTargetArgs thenT
        checkTargetArgs elseT
    | .switch scrut cases default => do
        -- scrutinee type
        let scrutT ← requireOperand env scrut
        -- every case typeId == scrutinee type
        for cs in cases do
          unless cs.typeId == scrutT do
            return ← err .badCfg
          checkTargetArgs cs.target
        match default with
        | some dt => checkTargetArgs dt
        | none => pure ()
    | .return_ (some v) =>
        let vt ← requireOperand env v
        unless vt == c.result.typeId do return ← err .badCfg
    | .revert errorId args =>
        -- Exact declared-error join: errorId must resolve and args must
        -- match ErrorDecl fields positionally by TypeId.
        match env.data.errors[errorId.toNat]? with
        | none => return ← err .badCfg
        | some errorDecl => checkInterfaceArgs env errorDecl.fields args
    | .return_ none | .trap _ => pure ()
  pure ()

/-! ### Per-op type/result contract (SPEC-SEM-WIRE-001 §4.3/§5.1 — CFG layer j)

    Step j: every value-producing op MUST carry `result := some _`
    (SPEC §4.3). The typed families (literal/constant/stateLoad/construct/
    fieldGet/indexGet/unary/binary/pureCall/fieldSet/variantTag/
    variantPayload/indexSet) must additionally have a result TypeId matching
    the op's exact type contract,
    with ValueId operand types matching the declared operand contract.
    `Op.FieldSet` carries the full §5.1 contract (base resolves to Struct,
    fieldIndex in range, type(value) == selected field.typeId,
    result.typeId == type(base)). `Op.VariantTag` carries the full §5.1
    contract (base resolves to Enum or Option, result.typeId == the unique
    structurally interned UInt32 TypeId) plus the static VariantPayload
    Enum/Option index/result contract plus the exact static IndexSet
    Array/Bytes/Map operand/result contract and CheckedCast UInt/Int
    source/destination/result contract. StateStore resolves stateId, requires
    type(value) == state.typeId, and carries no result. Assert requires a Bool
    condition plus an exact optional ErrorDecl/args join and carries no result.
    Emit resolves eventId, matches args positionally against EventDecl fields,
    and carries no result. `Op.ContextRead` carries result presence here plus
    the §5.1 same-key result-TypeId global consistency pass (a separate
    post-CFG gate), followed by its closed key/result/requirement catalog.
    `Op.Commit` requires its operand to resolve and its result TypeId to equal
    the operand TypeId; its exact disclosure requirement row is checked after
    generic requirement validation.
    ExternalCall/
    Schedule MUST carry `result := none` and a callee with at least two
    qualified-name components; a spurious result, short callee, or missing
    result on a value-producing op is an invalid Core trap → `.badCfg`. All
    step j failures → `.badCfg`. Bounded, non-recursive, total. Out of scope:
    ExternalCall/Schedule argument serializability, recursive/full TypeKey
    closure/ranking/reachability,
    provenance join, normalizer, product wire. -/

/-- First TypeId whose shape is `.option element` with the given element
    TypeId, if any. Bounded, non-recursive. Used by `indexGet` on Map to
    resolve the unique `Option(map.value)` result TypeId. -/
def optionTypeId (types : Array TypeDeclV1) (element : TypeIdV1) :
    Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut i : Nat := 0
  for t in types do
    if r.isNone then
      match t.shape with
      | .option e => if e == element then r := some (UInt32.ofNat i) else pure ()
      | _ => pure ()
    i := i + 1
  pure r

/-- Whether a TypeId resolves to a shape that is a valid `eq`/`ne` operand
    (SPEC §5.1 'serializable'): Bool/UInt/Int/Principal/Bytes/Field, or a
    Struct/Enum whose recursively-referenced types are all serializable.
    Array/Map/Option/Unit are NOT serializable. Bounded, fuel-bounded
    recursion (fuel = types.size). Out-of-range TypeId → false (caller owns
    range via step h). -/
private def serializableType (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Bool
  | 0 => false
  | fuel + 1 =>
    match types[typeId.toNat]? with
    | none => false
    | some decl =>
      match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .string | .bytes _ | .field _ => true
      | .struct fields =>
          fields.all (fun f => serializableType types f.typeId fuel)
      | .enum variants =>
          variants.all (fun v =>
            v.payloadTypes.all (fun t => serializableType types t fuel))
      | .array _ _ | .map _ _ | .option _ | .unit => false

/-- Step j: per-op type/result contract for one instruction. Consumes a
    shared per-callable `OpTypingEnv` (defTypes/types/data + uniqueness-gated
    Bool/UInt32/UInt8). Value-producing ops (`Literal`/`Constant`/`StateLoad`/
    `Construct`/`FieldGet`/`IndexGet`/`Unary`/`Binary`/`PureCall`) MUST carry
    `result := some _` and the result TypeId must equal the op's exact result
    type; a missing result or mismatched TypeId is `.badCfg`
    (SPEC-SEM-WIRE-001 §4.3/§5.1).
    `Op.StateStore` resolves stateId, requires type(value) == state.typeId, and
    MUST carry `result := none`. `Op.Assert` requires a Bool condition,
    `errorId = none` with empty args or an exact ErrorDecl/args join, and no
    result. `Op.Emit` resolves eventId, matches args exactly against EventDecl
    fields, and requires no result. The other void ops (`ExternalCall`/
    `Schedule`) also require no result and require a callee with at least two
    qualified-name components; a spurious result or short callee is `.badCfg`.
    Their argument serializability contract remains deferred.
    `Op.FieldSet` carries the full §5.1 contract (base must resolve to a Struct, fieldIndex in
    range, type(value) == selected field.typeId, result.typeId == type(base));
    a missing result or any mismatch is `.badCfg`. `Op.VariantTag` carries
    the full §5.1 contract (base must resolve to an Enum or Option,
    result.typeId == the unique UInt32 TypeId). Duplicate anonymous UInt32
    declarations are rejected earlier by primitive TypeKey interning as
    `.nonCanonical`; step j reports `.badCfg` for a missing UInt32 closure
    type, missing result, non-Enum/Option base, or wrong result type. The remaining
    `Op.VariantPayload` carries its static §5.1 contract (Enum variant/payload
    indices or Option `(1,0)`, with the selected payload/element result type).
    `Op.IndexSet` and `Op.CheckedCast` carry their exact static contracts.
    `Op.ContextRead` MUST carry `result := some _` presence-only here and
    additionally
    carries the §5.1 same-key result-TypeId consistency pass (a separate
    post-CFG global catalog gate). `Op.Commit` resolves its operand and requires
    `result.typeId == type(value)`; its exact disclosure requirement binding
    remains deferred to later slices.
    All failures → `.badCfg`. Bounded, non-recursive (serializableType is
    fuel-bounded). Each op family keeps its own contract; shared combinators
    only eliminate typeOf/shapeOf/result/operand/args boilerplate. -/
def checkOpTyping (instr : InstructionV1) (env : OpTypingEnv) :
    Except SemanticWireErrorV1 Unit := do
  let types := env.types
  let typeCount := types.size
  let data := env.data
  match instr.op with
  | .literal tid _ =>
      -- result.typeId == op.typeId; no ValueId uses.
      requireResultEq instr.result tid
  | .constant cid =>
      -- constantId in range → result.typeId == constants[cid].typeId.
      match data.constants[cid.toNat]? with
      | none => err .badCfg
      | some c => requireResultEq instr.result c.typeId
  | .stateLoad sid =>
      -- stateId in range → result.typeId == logicalState[sid].typeId.
      match data.logicalState[sid.toNat]? with
      | none => err .badCfg
      | some s => requireResultEq instr.result s.typeId
  | .construct tid ctorIdx args =>
      -- op.typeId in range; resolve type shape; reject primitives that
      -- cannot be Constructed.
      match env.shapeOf tid with
      | none => err .badCfg
      | some shape =>
        match shape with
        | .struct fields =>
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == fields.size do return ← err .badCfg
            let expected := fields.map (·.typeId)
            checkArgsPositional env args expected
            requireResultEq instr.result tid
        | .enum variants =>
            unless ctorIdx.toNat < variants.size do return ← err .badCfg
            match variants[ctorIdx.toNat]? with
            | none => err .badCfg
            | some v =>
                unless args.size == v.payloadTypes.size do return ← err .badCfg
                checkArgsPositional env args v.payloadTypes
                requireResultEq instr.result tid
        | .array element length =>
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == length.toNat do return ← err .badCfg
            let expected := Array.mk (List.replicate args.size element)
            checkArgsPositional env args expected
            requireResultEq instr.result tid
        | .option element =>
            match ctorIdx.toNat with
            | 0 =>
                -- none: args == #[]
                unless args.size == 0 do return ← err .badCfg
                requireResultEq instr.result tid
            | 1 =>
                -- some: args.count == 1, arg type == element
                unless args.size == 1 do return ← err .badCfg
                checkArgsPositional env args #[element]
                requireResultEq instr.result tid
            | _ => err .badCfg
        | .unit =>
            -- Unit shape: constructorIndex==0, args==#[].
            -- (Map construction — empty or flattened key/value pairs — is
            -- handled under .map below.)
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == 0 do return ← err .badCfg
            requireResultEq instr.result tid
        | .map keyType valueType =>
            -- N-MAP-CONSTRUCT: constructorIndex 0; args are a flattened
            -- key/value pair sequence (even count; empty = Map.empty).
            -- Semantics: empty map + sequential upsert in arg order
            -- (duplicate key last-wins, matching IndexSet), so runtime
            -- computed keys are admitted and no static order is required.
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size % 2 == 0 do return ← err .badCfg
            let expected := (List.range (args.size / 2)).foldl
              (fun acc _ => acc ++ #[keyType, valueType]) #[]
            checkArgsPositional env args expected
            requireResultEq instr.result tid
        | .bool | .uint _ | .int _ | .principal | .string | .bytes _ | .field _ =>
            -- primitives/Bytes/Principal/String/Field/uint/int/bool cannot be Constructed
            err .badCfg
  | .fieldGet base fieldIdx =>
      -- base ValueId type resolves to Struct via defTypes; fieldIndex < fields.size;
      -- result.typeId == fields[fieldIdx].typeId.
      let baseT ← requireOperand env base
      let fields ← requireShape (α := Array StructFieldV1) env baseT fun
        | .struct fs => some fs
        | _ => none
      unless fieldIdx.toNat < fields.size do return ← err .badCfg
      match fields[fieldIdx.toNat]? with
      | none => err .badCfg
      | some f => requireResultEq instr.result f.typeId
  | .indexGet base index =>
      -- base ValueId type resolves to Array/Bytes/Map; index type and result
      --   depend on base kind.
    let baseT ← requireOperand env base
    let idxT ← requireOperand env index
    match env.shapeOf baseT with
    | none => err .badCfg
    | some (.array element _length) =>
        -- index must be the unique UInt32 TypeId; result == element.
        match env.u32T with
        | none => err .badCfg
        | some u32 =>
            unless idxT == u32 do return ← err .badCfg
            requireResultEq instr.result element
    | some (.bytes _length) =>
        -- index UInt32; result == unique UInt8 TypeId.
        match env.u32T, env.u8T with
        | some u32, some u8 =>
            unless idxT == u32 do return ← err .badCfg
            requireResultEq instr.result u8
        | _, _ => err .badCfg
    | some (.map key value) =>
        -- index type == map.key TypeId; result == unique Option(map.value).
        unless idxT == key do return ← err .badCfg
        match optionTypeId types value with
        | none => err .badCfg
        | some optT => requireResultEq instr.result optT
    | some _ => err .badCfg
  | .unary op operand =>
      let opT ← requireOperand env operand
      match op with
      | .neg =>
          -- operand type Int or Field; result == operand type.
          match env.shapeOf opT with
          | some (.int _) | some (.field _) => requireResultEq instr.result opT
          | _ => err .badCfg
      | .not =>
          -- operand type Bool; result == Bool.
          match env.shapeOf opT with
          | some .bool => requireResultEq instr.result opT
          | _ => err .badCfg
      | .bitNot =>
          -- operand type UInt or Int; result == operand type.
          match env.shapeOf opT with
          | some (.uint _) | some (.int _) => requireResultEq instr.result opT
          | _ => err .badCfg
  | .binary op lhs rhs =>
      let lhsT ← requireOperand env lhs
      let rhsT ← requireOperand env rhs
      match op with
      | .add | .sub | .mul | .div | .mod =>
          -- arithmetic: lhs==rhs same UInt/Int (Field only add/sub/mul/div);
          --   result == lhs type.
          let lhsShape := env.shapeOf lhsT
          let okArith : Bool :=
            lhsT == rhsT &&
            (match lhsShape with
             | some (.uint _) | some (.int _) => true
             | some (.field _) =>
                 -- Field allows add/sub/mul/div but NOT mod.
                 match op with | .mod => false | _ => true
             | _ => false)
          unless okArith do return ← err .badCfg
          requireResultEq instr.result lhsT
      | .eq | .ne =>
          -- lhs==rhs same serializable type; result == Bool.
          unless lhsT == rhsT do return ← err .badCfg
          unless serializableType types lhsT typeCount do return ← err .badCfg
          match env.boolT with
          | none => err .badCfg
          | some boolT => requireResultEq instr.result boolT
      | .lt | .le | .gt | .ge =>
          -- lhs==rhs same UInt/Int; result == Bool.
          let sameInt : Bool := lhsT == rhsT &&
            (match env.shapeOf lhsT with
             | some (.uint _) | some (.int _) => true
             | _ => false)
          unless sameInt do return ← err .badCfg
          match env.boolT with
          | none => err .badCfg
          | some boolT => requireResultEq instr.result boolT
      | .and | .or =>
          -- lhs==rhs Bool; result == Bool.
          let bothBool : Bool := lhsT == rhsT &&
            (match env.shapeOf lhsT with | some .bool => true | _ => false)
          unless bothBool do return ← err .badCfg
          match env.boolT with
          | none => err .badCfg
          | some boolT => requireResultEq instr.result boolT
      | .bitAnd | .bitOr | .bitXor =>
          -- lhs==rhs same UInt/Int; result == lhs type.
          let sameInt : Bool := lhsT == rhsT &&
            (match env.shapeOf lhsT with
             | some (.uint _) | some (.int _) => true
             | _ => false)
          unless sameInt do return ← err .badCfg
          requireResultEq instr.result lhsT
      | .shl | .shr =>
          -- lhs UInt/Int, rhs UInt32; result == lhs type.
          let lhsInt : Bool :=
            match env.shapeOf lhsT with
            | some (.uint _) | some (.int _) => true
            | _ => false
          unless lhsInt do return ← err .badCfg
          match env.u32T with
          | none => err .badCfg
          | some u32 =>
              unless rhsT == u32 do return ← err .badCfg
              requireResultEq instr.result lhsT
  | .pureCall calleeId args =>
      -- calleeId in range, callee.kind == .pureFn, args count == params size,
      --   each arg type == params[i].typeId; result == callee.result.typeId.
    match data.callables[calleeId.toNat]? with
    | none => err .badCfg
    | some callee =>
        unless callee.kind == .pureFn do return ← err .badCfg
        unless args.size == callee.params.size do return ← err .badCfg
        let expected := callee.params.map (·.typeId)
        checkArgsPositional env args expected
        requireResultEq instr.result callee.result.typeId
  -- Op.StateStore (SPEC-SEM-WIRE-001 §5.1): stateId MUST resolve, the value
  --   operand TypeId MUST exactly equal the selected state.typeId, and this
  --   op is void (`Instruction.result = none`). Any mismatch → `.badCfg`.
  | .stateStore stateId value => do
      requireVoid instr.result
      match data.logicalState[stateId.toNat]? with
      | none => err .badCfg
      | some state =>
          let valueT ← requireOperand env value
          unless valueT == state.typeId do return ← err .badCfg
          pure ()
  -- Op.Assert (SPEC-SEM-WIRE-001 §5.1/§6): result MUST be none; condition
  --   MUST be Bool. `errorId = none` requires no args; `some errorId` MUST
  --   resolve and args MUST match ErrorDecl fields positionally and exactly.
  | .assert_ condition errorId args => do
      requireVoid instr.result
      let conditionT ← requireOperand env condition
      match env.shapeOf conditionT with
      | some .bool =>
          match errorId with
          | none =>
              unless args.isEmpty do return ← err .badCfg
              pure ()
          | some eid =>
              match data.errors[eid.toNat]? with
              | none => err .badCfg
              | some errorDecl =>
                  checkInterfaceArgs env errorDecl.fields args
      | _ => err .badCfg
  -- Op.Emit (SPEC-SEM-WIRE-001 §5.1): result MUST be none; eventId MUST
  --   resolve; args MUST match EventDecl fields positionally and exactly.
  --   EffectId canonical numbering/uniqueness is owned by CFG step e.5.
  | .emit _effectId eventId args => do
      requireVoid instr.result
      match data.events[eventId.toNat]? with
      | none => err .badCfg
      | some eventDecl =>
          checkInterfaceArgs env eventDecl.fields args
  -- SPEC §5.1/§6 + N-CALL-RET: Schedule is genuinely void. ExternalCall may
  --   carry a result (value-position sync call); when present its typeId MUST
  --   resolve to a serializable scalar (Bool / legal UInt/Int width / Bytes
  --   within maxTypeLengthV1). Result shape is checked before callee shape to
  --   preserve the existing fail-closed order. Arg serializability is a later
  --   slice; EffectId canonical assignment is owned by CFG step e.5.
  | .externalCall _effectId callee _args => do
      match instr.result with
      | none => pure ()
      | some vd =>
          let legal :=
            match env.shapeOf vd.typeId with
            | some .bool => true
            | some (.uint w) | some (.int w) =>
                w == 8 || w == 16 || w == 32 || w == 64 || w == 128 || w == 256
            | some (.bytes n) => n.toNat ≤ maxTypeLengthV1
            | _ => false
          unless legal do return ← err .badCfg
      unless 2 ≤ callee.components.toArray.size do return ← err .badCfg
      pure ()
  | .schedule _effectId callee _args => do
      requireVoid instr.result
      unless 2 ≤ callee.components.toArray.size do return ← err .badCfg
      pure ()
  -- Op.FieldSet (SPEC-SEM-WIRE-001 §5.1): base ValueId type MUST resolve to
  --   a Struct; fieldIndex MUST be in range; type(value) MUST exactly equal
  --   the selected field.typeId; `Instruction.result` MUST be present and
  --   its typeId MUST exactly equal type(base) (the whole struct). Any
  --   failure → `.badCfg`. (Presence is enforced by `requireResultEq … baseT`,
  --   which fails `.badCfg` on a missing result, preserving the prior
  --   missing-result gate.)
  | .fieldSet base fieldIndex value =>
      let baseT ← requireOperand env base
      let fields ← requireShape (α := Array StructFieldV1) env baseT fun
        | .struct fs => some fs
        | _ => none
      unless fieldIndex.toNat < fields.size do return ← err .badCfg
      match fields[fieldIndex.toNat]? with
      | none => err .badCfg
      | some f =>
          let valueT ← requireOperand env value
          unless valueT == f.typeId do return ← err .badCfg
          requireResultEq instr.result baseT
  -- Op.VariantTag (SPEC-SEM-WIRE-001 §5.1): base ValueId type MUST resolve
  --   to a Type.Enum or Type.Option; the unique UInt32 TypeId (resolved via
  --   the `uint32TypeId` helper, which returns `some` only when exactly one
  --   `.uint 32` declaration exists) MUST exist; `Instruction.result` MUST
  --   be present and its typeId MUST exactly equal that UInt32 TypeId. Any
  --   failure → `.badCfg`. (Presence is enforced by `requireResultEq … u32`,
  --   which fails `.badCfg` on a missing result, preserving the prior
  --   missing-result gate.)
  | .variantTag base =>
      let baseT ← requireOperand env base
      match env.shapeOf baseT with
      | some (.enum _) | some (.option _) =>
          match env.u32T with
          | none => err .badCfg
          | some u32 => requireResultEq instr.result u32
      | _ => err .badCfg
  -- Op.VariantPayload (SPEC-SEM-WIRE-001 §5.1): Enum bases require an
  --   in-range variantIndex and payloadIndex and return the selected payload
  --   TypeId. Option bases permit only `(variantIndex=1,payloadIndex=0)` and
  --   return the element TypeId. Agreement between an Enum value's runtime
  --   tag and `variantIndex` is not checked here; D2-07 must implement it as
  --   an interpreter trap. This gate validates the static contract. Failure →
  --   `.badCfg`; `requireResultEq` preserves the exact result-presence gate.
  | .variantPayload base variantIndex payloadIndex =>
      let baseT ← requireOperand env base
      match env.shapeOf baseT with
      | some (.enum variants) =>
          unless variantIndex.toNat < variants.size do return ← err .badCfg
          match variants[variantIndex.toNat]? with
          | none => err .badCfg
          | some variant =>
              unless payloadIndex.toNat < variant.payloadTypes.size do
                return ← err .badCfg
              match variant.payloadTypes[payloadIndex.toNat]? with
              | none => err .badCfg
              | some payloadT => requireResultEq instr.result payloadT
      | some (.option element) =>
          unless variantIndex.toNat == 1 && payloadIndex.toNat == 0 do
            return ← err .badCfg
          requireResultEq instr.result element
      | _ => err .badCfg
  -- Op.IndexSet (SPEC-SEM-WIRE-001 §5.1): Array/Bytes indices must be the
  --   unique UInt32 TypeId; Array values match element, Bytes values match
  --   UInt8; Map key/value operands match the declared key/value TypeIds.
  --   Every valid IndexSet returns type(base). Runtime bounds are not checked
  --   here and must be handled by D2-07. Any static mismatch → `.badCfg`.
  | .indexSet base index value =>
      let baseT ← requireOperand env base
      let indexT ← requireOperand env index
      let valueT ← requireOperand env value
      match env.shapeOf baseT with
      | some (.array element _) =>
          match env.u32T with
          | none => err .badCfg
          | some u32 =>
              unless indexT == u32 && valueT == element do
                return ← err .badCfg
              requireResultEq instr.result baseT
      | some (.bytes _) =>
          match env.u32T, env.u8T with
          | some u32, some u8 =>
              unless indexT == u32 && valueT == u8 do
                return ← err .badCfg
              requireResultEq instr.result baseT
          | _, _ => err .badCfg
      | some (.map key mapValue) =>
          unless indexT == key && valueT == mapValue do
            return ← err .badCfg
          requireResultEq instr.result baseT
      | _ => err .badCfg
  -- Op.CheckedCast (SPEC-SEM-WIRE-001 §5.1): both the source ValueId type
  --   and `toType` MUST resolve to UInt/Int shapes, and the instruction
  --   result TypeId MUST exactly equal `toType`. Runtime representability is
  --   not a static property and remains a D2-07 checked-revert concern.
  | .checkedCast value toType =>
      let valueT ← requireOperand env value
      let sourceIsInteger : Bool :=
        match env.shapeOf valueT with
        | some (.uint _) | some (.int _) => true
        | _ => false
      let destinationIsInteger : Bool :=
        match env.shapeOf toType with
        | some (.uint _) | some (.int _) => true
        | _ => false
      unless sourceIsInteger && destinationIsInteger do
        return ← err .badCfg
      requireResultEq instr.result toType
  -- Op.Commit (SPEC-SEM-WIRE-001 §5.1): the operand ValueId MUST resolve and
  --   the result TypeId MUST exactly equal type(value). Every structure-valid
  --   TypeShape has canonical value bytes, so this branch deliberately does
  --   not reuse the narrower Eq/Ne `serializableType` predicate. The exact
  --   disclosure requirement row is enforced after generic requirements.
  | .commit value =>
      let valueT ← requireOperand env value
      requireResultEq instr.result valueT
  -- ContextRead carries presence-only local typing; its exact key/type and
  --   requirement binding are enforced by the later closed-catalog passes.
  | .contextRead _ => requireResultPresent instr.result

/-- Production callable-CFG steps a–d. Returns the exact reachability table
    consumed by the later dominance phase. -/
def validateCallableCfgShapeReachability (c : CallableV1) :
    Except SemanticWireErrorV1 (Array Bool) := do
  let blockCount := c.blocks.size
  unless c.entryBlock.toNat == 0 do
    return ← err .badCfg
  if blockCount == 0 then
    return ← err .badCfg
  let mut idx : Nat := 0
  for b in c.blocks do
    unless b.id.toNat == idx do
      return ← err .badCfg
    idx := idx + 1
  for b in c.blocks do
    match b.terminator with
    | .switch _ cases _ =>
        if cases.isEmpty then return ← err .badCfg
        validateSwitchCaseValuesUnique cases
    | _ => pure ()
  for b in c.blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      checkBlockIdInRange succ blockCount
  for b in c.blocks do
    for target in terminatorJumpTargets (BlockV1.terminator b) do
      checkJumpTargetArity c.blocks blockCount target
  let reachable : Array Bool :=
    let visited0 : Array Bool := Array.mk (List.replicate blockCount false)
    let visited1 := visited0.set! 0 true
    cfgReachFixpoint c.blocks blockCount blockCount visited1
  for v in reachable do
    unless v do
      return ← err .badCfg
  pure reachable

/-- Production callable-CFG steps f–g. The canonical def-site table and
    dominator implementation remain internal to this coherent phase. -/
def validateCallableCfgValueFlow (c : CallableV1) (reachable : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let defSites := collectValueDefSites c
  checkValueIdCanonicalAssignment defSites
  checkValueIdUsesExist c defSites
  validateCallableDominanceOfUse c defSites reachable

/-- Compose production value-flow success while pinning the canonical def-site
    table built once and shared by assignment, use, and dominance checks. -/
theorem validateCallableCfgValueFlow_eq_ok_of_phases
    (c : CallableV1) (reachable : Array Bool)
    (defSites : Array (ValueIdV1 × BlockIdV1))
    (hDefSites : collectValueDefSites c = defSites)
    (hAssignment : checkValueIdCanonicalAssignment defSites = .ok ())
    (hUses : checkValueIdUsesExist c defSites = .ok ())
    (hDominance : validateCallableDominanceOfUse c defSites reachable = .ok ()) :
    validateCallableCfgValueFlow c reachable = .ok () := by
  simp only [validateCallableCfgValueFlow, hDefSites, hAssignment, hUses,
    hDominance, Bind.bind, Except.bind]

/-- Production callable-CFG steps h–j. The def-type table and canonical typing
    environment remain internal and are shared by terminator and op typing. -/
def validateCallableCfgTypingPhases (c : CallableV1) (typeCount : Nat)
    (data : SemanticProgramDataV1) : Except SemanticWireErrorV1 Unit := do
  let defTypes := collectValueTypeDefs c
  checkDefSiteTypeIdsInRange defTypes typeCount
  let env := mkOpTypingEnv defTypes data
  checkTerminatorTyping c env
  for b in c.blocks do
    for instr in b.instructions do
      checkOpTyping instr env

/-- A one-block, parameter-free callable that returns the result of a
    parameter-free PureCall satisfies the exact production h–j typing phases
    when the callee join and result TypeId are pinned. -/
theorem validateCallableCfgTypingPhases_single_nullary_pureCall_eq_ok
    (c callee : CallableV1) (data : SemanticProgramDataV1)
    (typeCount : Nat) (calleeId : CallableIdV1) (resultType : TypeIdV1)
    (hparams : c.params = #[])
    (hresult : c.result.typeId = resultType)
    (hblocks : c.blocks = #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId := resultType }
        op := .pureCall calleeId #[]
      }]
      terminator := .return_ (some 0)
    }])
    (hcallee : data.callables[calleeId.toNat]? = some callee)
    (hkind : (callee.kind == .pureFn) = true)
    (hcalleeParams : callee.params = #[])
    (hcalleeResult : callee.result.typeId = resultType)
    (hrange : checkTypeIdInRange resultType typeCount = .ok ()) :
    validateCallableCfgTypingPhases c typeCount data = .ok () := by
  simp [validateCallableCfgTypingPhases, collectValueTypeDefs,
    checkDefSiteTypeIdsInRange, checkTerminatorTyping, checkOpTyping,
    mkOpTypingEnv, OpTypingEnv.typeOf, requireOperand, requireResultEq,
    checkArgsPositional_empty_eq_ok, hparams, hresult, hblocks, hcallee, hkind,
    hcalleeParams, hcalleeResult, hrange, Id.run,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Per-callable CFG shape + reachability + loopBounds + EffectId assignment
    + ValueId SSA def-table + dominance-of-use + def-site TypeId range +
    terminator typing + per-op type/result contract. Deterministic, bounded.
    Steps a–e are CFG shape (including Switch cases nonempty and typed-value
    uniqueness), reachability, arity, and loopBounds; step e.5 checks
    per-callable EffectIds; step f runs
    the ValueId SSA def-table
    (exactly-once def + use-existence); step g runs dominance-of-use;
    step h runs def-site TypeId range (`.badReference`); step i runs
    terminator typing (`.badCfg`); step j runs the per-op type/result
    contract (§5.1, `.badCfg`) for value-producing ops. The reachability
    array computed in step d is shared with step g; the `defTypes` table
    built in step h is shared with steps i and j. -/
def validateCallableCfgShape (c : CallableV1)
    (typeCount : Nat) (_types : Array TypeDeclV1)
    (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let reachable ← validateCallableCfgShapeReachability c
  -- e) loopBounds back-edge coverage (SPEC §6 / §6.2)
  validateCallableLoopBounds c
  -- e.5) EffectId assignment: Emit/ExternalCall/Schedule IDs are contiguous
  --   from zero in BlockId/instruction order, independently per callable.
  validateCallableEffectIds c
  validateCallableCfgValueFlow c reachable
  validateCallableCfgTypingPhases c typeCount data

/-- Compose success of the sole production callable-CFG validator from its
    exact coherent production phases. The reachability witness is pinned by
    the a–d result; def-site, dominator, def-type, and typing environments stay
    internal to their owning phases. -/
theorem validateCallableCfgShape_eq_ok_of_phases
    (c : CallableV1) (typeCount : Nat) (types : Array TypeDeclV1)
    (data : SemanticProgramDataV1) (reachable : Array Bool)
    (hShapeReach : validateCallableCfgShapeReachability c = .ok reachable)
    (hLoopBounds : validateCallableLoopBounds c = .ok ())
    (hEffectIds : validateCallableEffectIds c = .ok ())
    (hValueFlow : validateCallableCfgValueFlow c reachable = .ok ())
    (hTyping : validateCallableCfgTypingPhases c typeCount data = .ok ()) :
    validateCallableCfgShape c typeCount types data = .ok () := by
  simp only [validateCallableCfgShape, hShapeReach, hLoopBounds, hEffectIds,
    hValueFlow, hTyping, Bind.bind, Except.bind]

end ProofForgeV2.Semantic.WireV1
