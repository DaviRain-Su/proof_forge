/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Aleo/Leo IR Lowering

Lowers the portable contract IR (`ProofForge.IR`) into a Leo program AST
(`ProofForge.Compiler.Leo.AST`), then renders it to `.leo` source via
`ProofForge.Compiler.Leo.Printer`. This is the `aleo-leo` counterpart of
`ProofForge.Backend.Psy.IR` and follows the same shape:

1. `Common` owns shared helpers (types, identifiers, storage, effect detection).
2. `Validate` runs capability + identifier + struct + state + entrypoint-body
   validation before lowering, so the builder only folds validated shapes.
3. This module owns the builder: `buildExpr` / `buildStmt` / `buildFunction` /
   `buildModule`, and the public `renderModule` entrypoint
   (`validate → build → print`).

Leo-specific lowering rules:

- **Async/finalize split.** Any entrypoint that touches on-chain storage (its
  body `hasEffect`) lowers its entire body into a `return final { … };` block
  and returns `Final` (Leo's on-chain finalize model). Pure entrypoints lower
  as ordinary `fn(params) -> T { body }`.
- **Scalar→mapping rewrite.** Leo 4.x has no scalar on-chain storage, so a
  portable scalar state (`state id: scalar T`) becomes a single-slot Leo
  `mapping id: u64 => T`, read via `Mapping::get_or_use(id, 0u64, <zero>)` and
  written via `Mapping::set(id, 0u64, value)`. Map states lower directly.
-/

import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Compiler.Leo.AST
import ProofForge.Compiler.Leo.Printer
import ProofForge.Backend.Aleo.IR.Common
import ProofForge.Backend.Aleo.IR.Validate

namespace ProofForge.Backend.Aleo.IR

open ProofForge.IR hiding Statement Literal
open ProofForge.Compiler.Leo.AST

/-! ### Leo mapping-call builders -/

/-- Build a `Mapping::get_or_use(id, key, default)` call expression. -/
def mappingGetOrUse (id : Identifier) (key default : Expression) : Expression :=
  .call ⟨#["Mapping", "get_or_use"], #[], #[.identifier id, key, default]⟩

/-- Build a `Mapping::set(id, key, value)` call expression. -/
def mappingSet (id : Identifier) (key value : Expression) : Expression :=
  .call ⟨#["Mapping", "set"], #[], #[.identifier id, key, value]⟩

/-- Build a `Mapping::contains(id, key)` call expression. -/
def mappingContains (id : Identifier) (key : Expression) : Expression :=
  .call ⟨#["Mapping", "contains"], #[], #[.identifier id, key]⟩

/-! ### ZK hash helpers (RFC 0015: Aleo `Hash ≡ field`, native Poseidon2) -/

/-- `Poseidon2::hash_to_field(x)` — the Aleo-native ZK hash to a field digest.
Verified against ProvableHQ/leo operators/crypto (`Poseidon2::hash_to_field(2i64)`). -/
def poseidonHashToField (x : Expression) : Expression :=
  .call ⟨#["Poseidon2", "hash_to_field"], #[], #[x]⟩

/-- Domain-separated, ordered encoding of two values into one field digest.

The previous `H(H(l) + H(r))` encoding was commutative. Multiplying the left
lane by a fixed non-zero field coefficient preserves operand position; adding a
pair-domain tag keeps this construction distinct from single-value hashing. -/
def poseidonHashTwo (l r : Expression) : Expression :=
  let leftLane := .binary ⟨.mul, poseidonHashToField l, .literal (.field "1315423911field")⟩
  let orderedPair := .binary ⟨.add, leftLane, poseidonHashToField r⟩
  poseidonHashToField (.binary ⟨.add, orderedPair, .literal (.field "2field")⟩)

/-- Find the first address that would need an invented storage fallback.
The field path makes nested value-struct failures actionable. -/
partial def storageDefaultAddressPath? (ctx : BuildContext) (type : ValueType)
    (path : Array String := #[]) (visiting : Array String := #[]) : Option (Array String) :=
  match type with
  | .address => some path
  | .fixedArray element _ | .array element =>
      storageDefaultAddressPath? ctx element (path.push "[]") visiting
  | .structType name =>
      if visiting.contains name then none
      else
        match findStruct? ctx.module name with
        | none => none
        | some decl =>
            if decl.semantics != .value then none
            else
              let structPath := if path.isEmpty then path.push name else path
              decl.fields.findSome? fun field =>
                storageDefaultAddressPath? ctx field.type (structPath.push field.id)
                  (visiting.push name)
  | _ => none

def storageDefaultAddressError (path : Array String) : LowerError :=
  let location :=
    if path.isEmpty then ""
    else s!" at `{String.intercalate "." path.toList}`"
  { message :=
      s!"Leo 4.0.2 has no honest `address` storage default for `Mapping::get_or_use`{location}; `none` is not an address and ProofForge refuses to forge a zero address" }

/-- Construct a storage fallback after address safety has been checked. -/
partial def defaultExprCore (ctx : BuildContext) (type : ValueType)
    (visiting : Array String := #[]) : Except LowerError Expression :=
  match type with
  | .u8 => .ok (.literal (.integer .u8 0))
  | .u32 => .ok (.literal (.integer .u32 0))
  | .u64 => .ok (.literal (.integer .u64 0))
  | .u128 => .ok (.literal (.integer .u128 0))
  | .hash => .ok (.literal (.field "0field"))  -- RFC 0015: Hash ≡ field
  | .bool => .ok (.literal (.boolean false))
  | .address => .error (storageDefaultAddressError #[])
  | .structType name => do
      let some decl := findStruct? ctx.module name
        | .error { message := s!"Leo IR v0 default: unknown struct `{name}`" }
      if visiting.contains name then
        .error { message := s!"Leo IR v0 has no finite storage default for recursive value struct `{name}`" }
      let fs ← decl.fields.mapM fun field => do
        .ok (field.id, ← defaultExprCore ctx field.type (visiting.push name))
      .ok (.composite name fs)
  | other => .error { message := s!"Leo IR v0 has no default literal for `{other.name}` storage" }

/-- The zero/empty default expression used by `Mapping::get_or_use`. Numeric
types use typed zero and Bool uses false. Leo 4.0.2 has no honest address
fallback, including addresses nested in ordinary value structs, so those
shapes fail closed instead of emitting the non-address literal `none`. -/
def defaultExpr (ctx : BuildContext) (type : ValueType) : Except LowerError Expression := do
  match storageDefaultAddressPath? ctx type with
  | some path => .error (storageDefaultAddressError path)
  | none => defaultExprCore ctx type

/-! ### Expression / statement lowering -/

mutual
  partial def buildExpr (ctx : BuildContext) : IR.Expr → Except LowerError Expression
    | .literal (.hash4 ..) =>
        -- RFC 0015: a `hash4` literal is an EVM keccak digest (4×u64 limbs); it has
        -- no Aleo `field` meaning. Aleo hashes field/u64 VALUES via `.hash`.
        .error { message := "Leo IR v0 does not lower `hash4` literals (EVM 4×u64 digest); hash a field/u64 value with `.hash` instead" }
    | .literal l => .ok (.literal (leoLiteral l))
    | .local name => .ok (.identifier name)
    | .add lhs rhs overflowChecked => do
        let op := if overflowChecked then BinaryOperation.add else .addWrapped
        .ok (.binary ⟨op, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .sub lhs rhs overflowChecked => do
        let op := if overflowChecked then BinaryOperation.sub else .subWrapped
        .ok (.binary ⟨op, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .mul lhs rhs overflowChecked => do
        let op := if overflowChecked then BinaryOperation.mul else .mulWrapped
        .ok (.binary ⟨op, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .div lhs rhs => do .ok (.binary ⟨.div, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .mod lhs rhs => do .ok (.binary ⟨.mod, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .pow lhs rhs => do .ok (.binary ⟨.pow, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .bitAnd lhs rhs => do .ok (.binary ⟨.bitwiseAnd, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .bitOr lhs rhs => do .ok (.binary ⟨.bitwiseOr, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .bitXor lhs rhs => do .ok (.binary ⟨.xor, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .shiftLeft lhs rhs => do .ok (.binary ⟨.shl, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .shiftRight lhs rhs => do .ok (.binary ⟨.shr, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .eq lhs rhs => do .ok (.binary ⟨.eq, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .ne lhs rhs => do .ok (.binary ⟨.neq, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .lt lhs rhs => do .ok (.binary ⟨.lt, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .le lhs rhs => do .ok (.binary ⟨.lte, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .gt lhs rhs => do .ok (.binary ⟨.gt, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .ge lhs rhs => do .ok (.binary ⟨.gte, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .boolAnd lhs rhs => do .ok (.binary ⟨.and, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .boolOr lhs rhs => do .ok (.binary ⟨.or, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩)
    | .boolNot value => do .ok (.unary ⟨.not, ← buildExpr ctx value⟩)
    | .cast value target => do .ok (.cast ⟨← buildExpr ctx value, ← valueType target⟩)
    | .structLit typeName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{typeName}` must have at least one field" }
        let fs ← fields.mapM fun (n, e) => do .ok (n, ← buildExpr ctx e)
        .ok (.composite typeName fs)
    | .field base fieldName => do .ok (.memberAccess ⟨← buildExpr ctx base, fieldName⟩)
    | .arrayGet array index => do
        .ok (.arrayAccess ⟨← buildExpr ctx array, ← buildExpr ctx index⟩)
    | .arrayLit _ values => do
        if values.isEmpty then
          .error { message := "Leo IR v0 does not support empty fixed-array literals" }
        let vs ← values.mapM (buildExpr ctx)
        .ok (.array vs)
    | .hashValue a b c d => do
        -- RFC 0015: tree-fold four inputs pairwise into one field digest.
        let ab := poseidonHashTwo (← buildExpr ctx a) (← buildExpr ctx b)
        let cd := poseidonHashTwo (← buildExpr ctx c) (← buildExpr ctx d)
        .ok (poseidonHashTwo ab cd)
    | .hash preimage => do .ok (poseidonHashToField (← buildExpr ctx preimage))
    | .hashTwoToOne l r => do .ok (poseidonHashTwo (← buildExpr ctx l) (← buildExpr ctx r))
    | .ecrecover _ _ _ _ | .eip712PermitDigest _ _ _ _ _ _ =>
        .error { message := "ecrecover / EIP-712 is EVM-specific and not supported by Leo IR v0" }
    | .crosscallAbiPacked .. =>
        .error { message := "ABI-packed crosscall (Call[]) is EVM-specific and not supported by Leo IR v0" }
    | .crosscallInvoke _ _ _ | .crosscallInvokeTyped _ _ _ _
    | .crosscallInvokeValueTyped _ _ _ _ _ | .crosscallInvokeStaticTyped _ _ _ _
    | .crosscallInvokeDelegateTyped _ _ _ _ =>
        .error { message := "typed crosscall is not supported by Leo IR v0; zk-circuit cross calls are Road 2" }
    | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ =>
        .error { message := "contract creation is not supported by Leo IR v0" }
    | .crosscallNamed programId method args _ => do
        -- RFC 0015 D4: static qualified cross-program call `programId::method(args)`.
        let args' ← args.mapM (buildExpr ctx)
        .ok (.call ⟨#[programId, method], #[], args'⟩)
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Leo IR v0" }
    | .nearPromiseThen _ _ _ _ | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by Leo IR v0" }
    | .memoryArrayNew _ _ | .memoryArrayLength _ | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by Leo IR v0" }
    | .effect effect => buildEffectExpr ctx effect

  partial def buildEffectExpr (ctx : BuildContext) : IR.Effect → Except LowerError Expression
    | .storageScalarRead stateId => do
        let t ← requireScalarState ctx stateId
        let d ← defaultExpr ctx t
        .ok (mappingGetOrUse stateId scalarSlotKey d)
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        discard <| requireMapState ctx stateId
        .ok (mappingContains stateId (← buildExpr ctx key))
    | .storageMapGet stateId key => do
        let (_, valueType) ← requireMapState ctx stateId
        let d ← defaultExpr ctx valueType
        .ok (mappingGetOrUse stateId (← buildExpr ctx key) d)
    | .storageMapInsert _ _ _ | .storageMapSet _ _ _ =>
        .error { message := "storage.map.insert/set are statement effects, not expressions" }
    | .storageArrayRead _ _ | .storageArrayWrite _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageArrayStructFieldRead _ _ _ | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageDynamicArrayPush _ _ | .storageDynamicArrayPop _ =>
        .error { message := "Leo IR v0 does not support dynamic array storage" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory arrays are not supported by Leo IR v0" }
    | .storageStructFieldRead stateId fieldName => do
        let t ← requireScalarState ctx stateId
        let d ← defaultExpr ctx t
        .ok (.memberAccess ⟨mappingGetOrUse stateId scalarSlotKey d, fieldName⟩)
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        discard <| resolveStoragePathType ctx.module stateId path
        let rootType ← requireScalarState ctx stateId
        let d ← defaultExpr ctx rootType
        let base := mappingGetOrUse stateId scalarSlotKey d
        let result ← path.foldlM (init := base) fun acc seg => do
          match seg with
          | .field fieldName => .ok (.memberAccess ⟨acc, fieldName⟩)
          | .index index => .ok (.arrayAccess ⟨acc, ← buildExpr ctx index⟩)
          | .mapKey _ => .error { message := s!"storage path into state `{stateId}` uses a map key, which Leo IR v0 lowers only for map state" }
        .ok result
    | .storagePathWrite _ _ _ | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.write/assign_op are statement effects, not expressions" }
    | .contextRead field => do
        let (_, e) ← mapContextField field
        .ok e
    | .eventEmit _ _ | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not an expression on Leo" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not an expression on Leo" }
    | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
        .error { message := "checkErc1155BatchReceived is EVM-only (PF-P2-02); not an expression on host" }

  /-- Lower an `Effect` in statement position to Leo statements (storage writes). -/
  partial def buildEffectStmt (ctx : BuildContext) : IR.Effect → Except LowerError (Array Statement)
    | .storageScalarRead _ =>
        .error { message := "storage.scalar.read must be used as an expression" }
    | .storageScalarWrite stateId value => do
        let t ← requireScalarState ctx stateId
        discard <| valueType t
        .ok #[.expression (mappingSet stateId scalarSlotKey (← buildExpr ctx value))]
    | .storageScalarAssignOp stateId op value => do
        let t ← requireScalarState ctx stateId
        let d ← defaultExpr ctx t
        let lhs := mappingGetOrUse stateId scalarSlotKey d
        let rhs : Expression := .binary ⟨assignOpToBinaryForMode ctx.module.overflowChecked op, lhs, ← buildExpr ctx value⟩
        .ok #[.expression (mappingSet stateId scalarSlotKey rhs)]
    | .storageMapContains _ _ | .storageMapGet _ _ =>
        .error { message := "storage.map.contains/get must be used as expressions" }
    | .storageMapInsert stateId key value | .storageMapSet stateId key value => do
        .ok #[.expression (mappingSet stateId (← buildExpr ctx key) (← buildExpr ctx value))]
    | .storageArrayRead _ _ | .storageArrayWrite _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageArrayStructFieldRead _ _ _ | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "Leo IR v0 does not support array storage" }
    | .storageDynamicArrayPush _ _ | .storageDynamicArrayPop _ =>
        .error { message := "Leo IR v0 does not support dynamic array storage" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory arrays are not supported by Leo IR v0" }
    | .storageStructFieldRead _ _ =>
        .error { message := "storage.struct.field.read must be used as an expression" }
    | .storageStructFieldWrite stateId fieldName value => do
        -- Read-modify-write. Leo 4.0.2 has no `..base` struct-update spread (that
        -- is newer than 4.0.2), so read into a temp local and rebuild the whole
        -- struct: `let __t = read; Mapping::set(id, 0, Name { f1: __t.f1, …, field: value, … });`.
        let t ← requireScalarState ctx stateId
        let structName ← match t with
          | .structType n => .ok n
          | other => .error { message := s!"state `{stateId}` has scalar type `{other.name}`, not struct storage" }
        let some decl := findStruct? ctx.module structName
          | .error { message := s!"state `{stateId}` references unknown struct `{structName}`" }
        let d ← defaultExpr ctx t
        let v ← buildExpr ctx value
        let tmp := "pf_" ++ stateId
        let readStmt := .definition (.single tmp) (some (← valueType t)) (mappingGetOrUse stateId scalarSlotKey d)
        let fields := decl.fields.map fun f =>
          if f.id == fieldName then (f.id, v) else (f.id, (.memberAccess ⟨.identifier tmp, f.id⟩))
        let setStmt := .expression (mappingSet stateId scalarSlotKey (.composite structName fields))
        .ok #[readStmt, setStmt]
    | .storagePathRead _ _ =>
        .error { message := "storage.path.read must be used as an expression" }
    | .storagePathWrite _ _ _ | .storagePathAssignOp _ _ _ _ =>
        .error { message := "Leo IR v0 does not lower storage-path writes (Road 2)" }
    | .contextRead _ =>
        .error { message := "context.read must be used as an expression" }
    | .eventEmit _ _ | .eventEmitIndexed _ _ _ =>
        .error { message := "Leo IR v0 does not lower event emit (Leo events are Road 2)" }
    | .checkErc721Received _ _ _ _ =>
        .error { message := "checkErc721Received is EVM-only (PF-P2-02); not supported by Leo IR v0" }
    | .checkErc1155Received _ _ _ _ _ =>
        .error { message := "checkErc1155Received is EVM-only (PF-P2-02); not supported by Leo IR v0" }
    | .checkErc1155BatchReceived _ _ _ _ _ _ _ =>
        .error { message := "checkErc1155BatchReceived is EVM-only (PF-P2-02); not an expression on host" }

  /-- Lower a portable IR statement to zero or more Leo statements. -/
  partial def buildStmt (ctx : BuildContext) : IR.Statement → Except LowerError (Array Statement)
    | .letBind name ty value => do
        let v ← buildExpr ctx value
        .ok #[.definition (.single name) (some (← valueType ty)) v]
    | .letMutBind name ty value => do
        let v ← buildExpr ctx value
        .ok #[.definition (.single name) (some (← valueType ty)) v]
    | .assign target value => do
        let v ← buildExpr ctx value
        let place ← buildAssignPlace ctx target
        .ok #[.assign place v]
    | .assignOp target op value => do
        let v ← buildExpr ctx value
        let lhs ← buildAssignPlace ctx target
        .ok #[.assign lhs (.binary ⟨assignOpToBinaryForMode ctx.module.overflowChecked op, lhs, v⟩)]
    | .effect effect => buildEffectStmt ctx effect
    | .assert condition _ _ => do
        .ok #[.assert (← buildExpr ctx condition) none]
    | .assertEq lhs rhs _ _ => do
        .ok #[.assert (.binary ⟨.eq, ← buildExpr ctx lhs, ← buildExpr ctx rhs⟩) none]
    | .release _ =>
        .error { message := "release statements are not supported by Leo IR v0" }
    | .revert _ =>
        .ok #[.assert (.literal (.boolean false)) none]
    | .revertWithError _ =>
        .ok #[.assert (.literal (.boolean false)) none]
    | .ifElse condition thenBody elseBody => do
        let c ← buildExpr ctx condition
        let thenStmts ← buildBody ctx thenBody
        let elseStmts ← buildBody ctx elseBody
        .ok #[.conditional c { statements := thenStmts } (some (.block { statements := elseStmts }))]
    | .boundedFor name start stop body => do
        let bodyStmts ← buildBody ctx body
        .ok #[.iteration name (some (.integer .u64))
                (.literal (.integer .u64 start)) (.literal (.integer .u64 stop))
                false { statements := bodyStmts }]
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by Leo IR v0; use bounded for" }
    | .return value => do
        let v ← buildExpr ctx value
        .ok #[.returnSt (some v)]

  /-- Lower an assignment-target expression to a Leo place expression. -/
  partial def buildAssignPlace (ctx : BuildContext) : IR.Expr → Except LowerError Expression
    | .local name => .ok (.identifier name)
    | .field base fieldName => do .ok (.memberAccess ⟨← buildAssignPlace ctx base, fieldName⟩)
    | .arrayGet base index => do
        .ok (.arrayAccess ⟨← buildAssignPlace ctx base, ← buildExpr ctx index⟩)
    | _ =>
        .error { message := "assignment target must be a local, field, or array index" }

  /-- Lower a body of portable statements to a flat array of Leo statements. -/
  partial def buildBody (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array Statement)
    | arr => do
      let mut result := #[]
      for stmt in arr do
        let ss ← buildStmt ctx stmt
        result := result ++ ss
      .ok result

  /-- Lower a stateful entrypoint body into the Leo `final { … }` block.

  Storage effects lower as usual; a terminal `.return value` whose value carries
  an effect (e.g. a storage read) is emitted as a plain expression statement
  (the read still runs on-chain); a pure return is dropped, since the inline
  finalize model cannot surface a value to the caller (Road 2). -/
  partial def buildFinalizeBody (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array Statement)
    | arr => do
      let mut result := #[]
      for stmt in arr do
        match stmt with
        | .return value => do
            -- The Final path does not surface the return value to the caller.
            -- Emit the value as a statement only when it is a function call
            -- (Leo 4.0.2 requires expression statements to be calls); arithmetic /
            -- struct / etc. are dropped (storage reads are state no-ops).
            let e ← buildExpr ctx value
            match e with
            | .call _ => result := result.push (.expression e)
            | _ => pure ()
        | other =>
            let ss ← buildStmt ctx other
            result := result ++ ss
      .ok result
end

/-! ### Function / module builders -/

/-- Build a Leo `Input` from a portable `(name, type)` parameter. -/
def makeInput (name : String) (ty : ValueType) : Except LowerError Input := do
  -- Leo's no-keyword default is `private` (proof-context). Portable IR params
  -- carry no public/private mode, so default to private; an explicit `public`
  -- surfaces only if a future IR mode sets `Input.mode := .public_`.
  .ok { name := name, ty := ← valueType ty, mode := .private_ }

/-- The Leo 4.x return type used for stateful (async/finalize) entrypoints. -/
def finalizeReturnType : LeoType :=
  .future #[] .unit

/-- The Leo 4.x mixed return type `(T, Final)` for a function that returns a
value AND runs on-chain finalize (verified against `functions/transfer_inline`). -/
def mixedReturnType (valueType : LeoType) : LeoType :=
  .tuple #[valueType, finalizeReturnType]

/-- Lower the mixed `(value, Final)` body: pure (non-storage) statements run
off-chain in order; storage-effect statements run inside `final {}` in order;
the pure return value is paired with the async finalize block. -/
def buildMixedBody (ctx : BuildContext) (ep : Entrypoint) : Except LowerError (Array Statement) := do
  let plan ← planMixedBody ep
  let offChain ← buildBody ctx plan.offChain
  let finalStmts ← buildBody ctx plan.finalBody
  let returnValue ← buildExpr ctx plan.returnValue
  let asyncBlock : Block := { statements := finalStmts }
  let ret := .returnSt (some (.tuple #[returnValue, .async asyncBlock]))
  .ok (offChain.push ret)

/-- Build a Leo entrypoint `Function` from a portable `Entrypoint`.

Cases (Leo 4.0.2 — `view fn` is newer than 4.0.2, so mapping reads must run in
`final`):

- **write + pure return value** → `fn … -> (T, Final) { …; return (value, final { … }); }`
  (mixed: off-chain compute + on-chain finalize);
- **Unit-returning storage effects** →
  `fn … -> Final { return final { … }; }` (reads/writes run in `final`);
- **state-derived non-Unit return** → rejected, because Leo 4.0.2 cannot
  surface a value computed inside `final` without changing the portable ABI;
- **pure** (no state effects) → `fn … -> T`. -/
def buildFunction (ctx : BuildContext) (ep : Entrypoint) : Except LowerError Function := do
  let inputs ← ep.params.mapM fun (n, t) => makeInput n t
  match ← planFunction ep with
  | .valueAndFinal =>
    let ret ← valueType ep.returns
    let bodyStmts ← buildMixedBody ctx ep
    .ok {
      annotations := #[]
      variant := .entryPoint
      identifier := ep.name
      constParameters := #[]
      input := inputs
      output := #[]
      outputType := mixedReturnType ret
      block := { statements := bodyStmts }
    }
  | .finalOnly =>
    let bodyStmts ← buildFinalizeBody ctx ep.body
    let asyncBlock : Block := { statements := bodyStmts }
    .ok {
      annotations := #[]
      variant := .entryPoint
      identifier := ep.name
      constParameters := #[]
      input := inputs
      output := #[]
      outputType := finalizeReturnType
      block := { statements := #[.returnSt (some (.async asyncBlock))] }
    }
  | .pure =>
    let ret ← valueType ep.returns
    let bodyStmts ← buildBody ctx ep.body
    .ok {
      annotations := #[]
      variant := .entryPoint
      identifier := ep.name
      constParameters := #[]
      input := inputs
      output := #[]
      outputType := ret
      block := { statements := bodyStmts }
    }

/-- Build a Leo `Mapping` declaration from a portable `StateDecl`.

Scalar states rewrite to a single-slot `mapping id: u64 => T`; map states lower
directly to `mapping id: K => V`. -/
def buildMapping (state : StateDecl) : Except LowerError Mapping := do
  match state.kind with
  | .scalar =>
      let vt ← valueType state.type
      .ok { identifier := state.id, keyType := .integer .u64, valueType := vt }
  | .map keyType _ =>
      .ok { identifier := state.id, keyType := ← valueType keyType, valueType := ← valueType state.type }
  | .array _ =>
      .error { message := s!"state `{state.id}` is array storage; Leo IR v0 does not lower fixed-array storage" }
  | .dynamicArray =>
      .error { message := s!"state `{state.id}` is dynamic array storage; Leo IR v0 does not lower dynamic-array storage" }

/-- Build a Leo `Composite` (record/struct) declaration from a portable struct. -/
def buildComposite (decl : StructDecl) : Except LowerError (Identifier × Composite) := do
  let members ← decl.fields.mapM fun field => do
    .ok { name := field.id, ty := ← valueType field.type }
  .ok (decl.name, { identifier := decl.name, members, isRecord := decl.isRecord })

/-- The `@noupgrade constructor()` required by Leo 4.x programs. -/
def constructor : Constructor :=
  { annotations := #[{ name := "noupgrade" }], block := { statements := #[] } }

def crosscallImports (module : Module) : Array Import :=
  let ids := module.entrypoints.flatMap fun ep =>
    (analyzeBody ep.body).namedCrosscalls.map (·.programId)
  let dedup := ids.foldl (fun acc p => if acc.contains p then acc else acc.push p) #[]
  dedup.map fun pid => { programId := pid }

/-- Emit a full portable IR module as a Leo `Program` AST. -/
def buildModule (module : Module) : Except LowerError Program := do
  let ctx : BuildContext := { module }
  let mappings ← module.state.mapM buildMapping
  let composites ← module.structs.mapM buildComposite
  let functions ← module.entrypoints.mapM (buildFunction ctx)
  let scope : ProgramScope := {
    programId := module.name.toLower ++ ".aleo"
    parents := #[]
    consts := #[]
    composites := composites
    mappings := mappings.map (fun m => (m.identifier, m))
    storageVariables := #[]
    functions := functions.map (fun f => (f.identifier, f))
    interfaces := #[]
    constructor := some constructor
  }
  .ok {
    imports := crosscallImports module
    scopes := #[(module.name.toLower, scope)]
  }

/-- Render a portable IR module to `.leo` source text.

Public entrypoint: validate the module (`Validate.validateModule`), lower it to
a Leo `Program` AST (`buildModule`), and print it
(`Leo.Printer.printProgram`). -/
def renderModule (module : Module) : Except LowerError String := do
  validateModule module
  let p ← buildModule module
  match ProofForge.Compiler.Leo.Printer.printProgram p with
  | .ok s => .ok s
  | .error e => .error { message := e.message }

end ProofForge.Backend.Aleo.IR
