import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Psy.Plan
import ProofForge.Compiler.Psy.AST
import ProofForge.Compiler.Psy.Printer
import ProofForge.Backend.Psy.IR.Common
import ProofForge.Backend.Psy.IR.Validate

namespace ProofForge.Backend.Psy.IR

open ProofForge.IR
open ProofForge.Target

open Lean.Compiler.Psy hiding Module AssignOp Expr Stmt Effect ContextField Literal TypeName StorageTarget StoragePathSegment Method StructDecl StructField StateDecl Test

/-- Map a portable IR `AssignOp` to the Psy AST `AssignOp`. -/
def mapAssignOp : AssignOp → Lean.Compiler.Psy.AssignOp
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight

/-- Map a portable IR `ContextField` to the Psy AST `ContextField`, rejecting
unsupported context fields. -/
def mapContextField : IR.ContextField → Except LowerError Lean.Compiler.Psy.ContextField
  | .userId => .ok .userId
  | .contractId => .ok .contractId
  | .checkpointId => .ok .checkpointId
  | field => .error { message := s!"Psy IR v0 context read `{field.name}` is not supported; only userId, contractId, and checkpointId are available" }

/-- Map a portable IR `Literal` to the Psy AST `Literal`. -/
def buildLiteral : IR.Literal → Lean.Compiler.Psy.Literal
  | .u32 value => .u32 value
  | .u64 value => .felt value
  | .bool value => .bool value
  | .hash4 a b c d => .hash4 a b c d
  | .u8 value => .u8 value
  | .u128 value => .u128 value
  | .address value => .address (toString value)

/-- Build a `Lean.Compiler.Psy.TypeName` from a portable `ValueType` via `valueTypeName`. -/
def typeName (type : ValueType) : Except LowerError Lean.Compiler.Psy.TypeName :=
  match valueTypeName type with
  | .ok text => .ok { text }
  | .error err => .error err

mutual
  /-- Build a `Lean.Compiler.Psy.Expr` from a portable IR `Expr`. Storage/state validation is
  performed by the type-checking pass before this runs; the builder only folds
  the validated shape into the AST. -/
  partial def buildExpr (ctx : BuildContext) : IR.Expr → Except LowerError Lean.Compiler.Psy.Expr
    | .literal value => .ok <| .literal (buildLiteral value)
    | .local name => .ok <| .local name
    | .arrayLit elementType values => do
        if values.isEmpty then
          .error { message := s!"empty fixed array literals are not supported by Psy IR v0 for `{← valueTypeName elementType}`" }
        let elementTypeName ← typeName elementType
        let items ← values.mapM (buildExpr ctx)
        .ok <| .arrayLit elementTypeName items
    | .arrayGet array index => do
        .ok <| .arrayGet (← buildExpr ctx array) (← buildExpr ctx index)
    | .memoryArrayNew _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayLength _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .memoryArrayGet _ _ =>
        .error { message := "memory arrays are not supported by Psy IR v0" }
    | .structLit structName fields => do
        if fields.isEmpty then
          .error { message := s!"struct literal `{structName}` must have at least one field" }
        let items ← fields.mapM fun (n, v) => do
          .ok (n, ← buildExpr ctx v)
        .ok <| .structLit structName items
    | .field base fieldName => do
        .ok <| .field (← buildExpr ctx base) fieldName
    | .add lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .add (← buildExpr ctx rhs)
    | .sub lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .sub (← buildExpr ctx rhs)
    | .mul lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .mul (← buildExpr ctx rhs)
    | .div lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .div (← buildExpr ctx rhs)
    | .mod lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .mod (← buildExpr ctx rhs)
    | .pow lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .pow (← buildExpr ctx rhs)
    | .bitAnd lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitAnd (← buildExpr ctx rhs)
    | .bitOr lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitOr (← buildExpr ctx rhs)
    | .bitXor lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .bitXor (← buildExpr ctx rhs)
    | .shiftLeft lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .shiftLeft (← buildExpr ctx rhs)
    | .shiftRight lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .shiftRight (← buildExpr ctx rhs)
    | .cast value targetType => do
        let targetTypeName ← typeName targetType
        .ok <| .cast (← buildExpr ctx value) targetTypeName
    | .eq lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .eq (← buildExpr ctx rhs)
    | .ne lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .ne (← buildExpr ctx rhs)
    | .lt lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .lt (← buildExpr ctx rhs)
    | .le lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .le (← buildExpr ctx rhs)
    | .gt lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .gt (← buildExpr ctx rhs)
    | .ge lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .ge (← buildExpr ctx rhs)
    | .boolAnd lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .boolAnd (← buildExpr ctx rhs)
    | .boolOr lhs rhs => do .ok <| .binary (← buildExpr ctx lhs) .boolOr (← buildExpr ctx rhs)
    | .boolNot value => do .ok <| .unary .not (← buildExpr ctx value)
    | .hashValue a b c d => do .ok <| .hashValue (← buildExpr ctx a) (← buildExpr ctx b) (← buildExpr ctx c) (← buildExpr ctx d)
    | .hash preimage => do .ok <| .hash (← buildExpr ctx preimage)
    | .hashTwoToOne lhs rhs => do .ok <| .hashTwoToOne (← buildExpr ctx lhs) (← buildExpr ctx rhs)
    | .nativeValue =>
        .error { message := "native value inspection is not supported by Psy IR v0" }
    | .crosscallInvoke target methodId args => do
        .ok <| .crosscallInvoke (← buildExpr ctx target) (← buildExpr ctx methodId) (← args.mapM (buildExpr ctx))
    | .crosscallInvokeTyped _ _ _ returnType =>
        .error { message := s!"typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeValueTyped _ _ _ _ returnType =>
        .error { message := s!"value-bearing typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeStaticTyped _ _ _ returnType =>
        .error { message := s!"static typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallInvokeDelegateTyped _ _ _ returnType =>
        .error { message := s!"delegate typed crosscall return `{returnType.name}` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets" }
    | .crosscallCreate _ _ =>
        .error { message := "EVM contract creation is not supported by Psy IR v0" }
    | .crosscallCreate2 _ _ _ =>
        .error { message := "EVM deterministic contract creation is not supported by Psy IR v0" }
    | .nearPromiseThen _ _ _ _
    | .nearCrosscallInvokePool _ _ _ _
    | .nearPromiseResultsCount
    | .nearPromiseResultStatus _
    | .nearPromiseResultU64 _ =>
        .error { message := "NEAR promise API is not supported by Psy IR v0" }
    | .effect effect => buildEffectExpr ctx effect

  /-- Build a `Lean.Compiler.Psy.Expr` from a portable IR `Effect` in expression position. -/
  partial def buildEffectExpr (ctx : BuildContext) : IR.Effect → Except LowerError Lean.Compiler.Psy.Expr
    | .storageScalarRead stateId => do
        requireScalarStateCtx ctx stateId
        .ok <| .storageScalarRead stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapContains stateId (← buildExpr ctx key)
    | .storageMapGet stateId key => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapGet stateId (← buildExpr ctx key)
    | .storageMapInsert stateId key value => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapInsert stateId (← buildExpr ctx key) (← buildExpr ctx value)
    | .storageMapSet stateId key value => do
        requireMapStateCtx ctx stateId
        .ok <| .storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value)
    | .storageArrayRead stateId index => do
        requireArrayStateCtx ctx stateId
        let feltBacked := isFeltBackedU32ArrayCtx ctx stateId
        .ok <| .storageArrayRead stateId (← buildExpr ctx index) feltBacked
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        requireStructArrayStateCtx ctx stateId fieldName
        .ok <| .storageArrayStructFieldRead stateId (← buildExpr ctx index) fieldName
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageDynamicArrayPush _ _ =>
        .error { message := "storage.dynamic.array.push is a statement effect, not an expression" }
    | .storageDynamicArrayPop _ =>
        .error { message := "storage.dynamic.array.pop is a statement effect, not an expression" }
    | .memoryArraySet _ _ _ =>
        .error { message := "memory.array.set is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        requireStructScalarStateCtx ctx stateId fieldName
        .ok <| .storageStructFieldRead stateId fieldName
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path => do
        discard <| resolveStoragePathTypeCtx ctx stateId path
        match lookupState? ctx stateId with
        | some { shape := .map _ _ _, .. } =>
            match path.toList with
            | .mapKey key :: [] => .ok <| .storageMapGet stateId (← buildExpr ctx key)
            | .mapKey _ :: _ => .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
            | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
        | some _ =>
            let pathType ← resolveStoragePathTypeCtx ctx stateId path
            let feltBacked := storagePathFeltBacked ctx stateId pathType
            .ok <| .storagePathRead stateId (← buildStoragePath ctx path) feltBacked
        | none => .error { message := s!"unknown storage path state `{stateId}`" }
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead field => do
        .ok <| .contextRead (← mapContextField field)
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }

  /-- Build `Lean.Compiler.Psy.StoragePathSegment` array from portable IR path segments. -/
  partial def buildStoragePath (ctx : BuildContext) : Array IR.StoragePathSegment → Except LowerError (Array Lean.Compiler.Psy.StoragePathSegment)
    | #[] => .ok #[]
    | arr => arr.mapM fun
      | .field fieldName => .ok <| .field fieldName
      | .index index => do .ok <| .index (← buildExpr ctx index)
      | .mapKey _ => .error { message := "storage path map key lowering is handled at the map state boundary" }

  /-- Check whether an assignment target's root is a storage state (vs a local). -/
  partial def isStorageTargetRoot (ctx : BuildContext) : IR.Expr → Bool
    | .local name => lookupState? ctx name |>.isSome
    | .field base _ => isStorageTargetRoot ctx base
    | .arrayGet base _ => isStorageTargetRoot ctx base
    | _ => false

  /-- Resolve the root storage form of an assignment target expression. -/
  partial def resolveStorageTargetRoot (ctx : BuildContext) : IR.Expr → Except LowerError Lean.Compiler.Psy.StorageTarget
    | .local stateId =>
        match lookupState? ctx stateId with
        | some _ => .ok <| .scalar stateId
        | none => .error { message := s!"unknown storage target `{stateId}`" }
    | .field base fieldName => do
        match ← resolveStorageTargetRoot ctx base with
        | .scalar stateId => .ok <| .structField stateId fieldName
        | .arrayIndex stateId index _ => .ok <| .arrayStructField stateId index fieldName
        | .path stateId segs _ => .ok <| .path stateId (segs.push (.field fieldName)) false
        | .structField stateId baseField =>
            .ok <| .path stateId #[.field baseField, .field fieldName] false
        | .arrayStructField stateId index baseField =>
            .ok <| .path stateId #[.index index, .field baseField, .field fieldName] false
    | .arrayGet base index => do
        match ← resolveStorageTargetRoot ctx base with
        | .scalar stateId =>
            let feltBacked := match lookupState? ctx stateId with
              | some { shape := .array .u32 _ true, .. } => true
              | _ => false
            .ok <| .arrayIndex stateId (← buildExpr ctx index) feltBacked
        | .arrayIndex stateId baseIndex feltBacked =>
            .ok <| .path stateId #[.index baseIndex, .index (← buildExpr ctx index)] feltBacked
        | .path stateId segs feltBacked =>
            .ok <| .path stateId (segs.push (.index (← buildExpr ctx index))) feltBacked
        | .structField _ _ => .error { message := "struct field is not an array assignment target" }
        | .arrayStructField _ _ _ => .error { message := "array struct field is not an array assignment target" }
    | _ => .error { message := "assignment target must be a local, array index, or field path" }
end

/-- Build a `Lean.Compiler.Psy.Stmt` from a portable IR `Effect` in statement position. -/
def buildEffectStmt (ctx : BuildContext) : IR.Effect → Except LowerError Lean.Compiler.Psy.Stmt
  | .storageScalarRead _ => .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      requireScalarStateCtx ctx stateId
      .ok <| .effect (.storageScalarWrite stateId (← buildExpr ctx value))
  | .storageScalarAssignOp stateId op value => do
      requireScalarStateCtx ctx stateId
      .ok <| .effect (.storageScalarAssignOp stateId (mapAssignOp op) (← buildExpr ctx value))
  | .storageMapContains _ _ => .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ => .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      requireMapStateCtx ctx stateId
      .ok <| .effect (.storageMapInsert stateId (← buildExpr ctx key) (← buildExpr ctx value))
  | .storageMapSet stateId key value => do
      requireMapStateCtx ctx stateId
      .ok <| .effect (.storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value))
  | .storageArrayRead _ _ => .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      requireArrayStateCtx ctx stateId
      let feltBacked := match lookupState? ctx stateId with
        | some { shape := .array .u32 _ true, .. } => true
        | _ => false
      .ok <| .effect (.storageArrayWrite stateId (← buildExpr ctx index) (← buildExpr ctx value) feltBacked)
  | .storageArrayStructFieldRead _ _ _ => .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      requireStructArrayStateCtx ctx stateId fieldName
      .ok <| .effect (.storageArrayStructFieldWrite stateId (← buildExpr ctx index) fieldName (← buildExpr ctx value))
  | .storageDynamicArrayPush _ _ => .error { message := "storage.dynamic.array.push is not supported by Psy IR v0" }
  | .storageDynamicArrayPop _ => .error { message := "storage.dynamic.array.pop is not supported by Psy IR v0" }
  | .memoryArraySet _ _ _ =>
      .error { message := "memory arrays are not supported by Psy IR v0" }
  | .storageStructFieldRead _ _ => .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      requireStructScalarStateCtx ctx stateId fieldName
      .ok <| .effect (.storageStructFieldWrite stateId fieldName (← buildExpr ctx value))
  | .storagePathRead _ _ => .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      discard <| resolveStoragePathTypeCtx ctx stateId path
      match lookupState? ctx stateId with
      | some { shape := .map _ _ _, .. } =>
          match path.toList with
          | .mapKey key :: [] => do .ok <| .effect (.storageMapSet stateId (← buildExpr ctx key) (← buildExpr ctx value))
          | .mapKey _ :: _ => .error { message := s!"storage path state `{stateId}` map values support direct key access only" }
          | _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | some _ =>
          let pathType ← resolveStoragePathTypeCtx ctx stateId path
          let feltBacked := storagePathFeltBacked ctx stateId pathType
          .ok <| .effect (.storagePathWrite stateId (← buildStoragePath ctx path) (← buildExpr ctx value) feltBacked)
      | none => .error { message := s!"unknown storage path state `{stateId}`" }
  | .storagePathAssignOp stateId path op value => do
      discard <| resolveStoragePathTypeCtx ctx stateId path
      let pathType ← resolveStoragePathTypeCtx ctx stateId path
      match lookupState? ctx stateId with
      | some { shape := .map _ _ _, .. } => .error { message := s!"storage path state `{stateId}` map values do not support compound assignment" }
      | some { shape := .array .u32 _ _, .. } =>
          if storagePathFeltBacked ctx stateId pathType then
            let segs ← buildStoragePath ctx path
            let target := Lean.Compiler.Psy.StorageTarget.path stateId segs false
            let read := Lean.Compiler.Psy.Expr.storagePathRead stateId segs true
            let rhs := Lean.Compiler.Psy.Expr.cast
              (Lean.Compiler.Psy.Expr.binary read ((mapAssignOp op).toBinaryOp) (← buildExpr ctx value))
              { text := psyFeltTypeName }
            .ok <| .assign target rhs
          else
            .ok <| .effect (.storagePathAssignOp stateId (← buildStoragePath ctx path) (mapAssignOp op) (← buildExpr ctx value))
      | some _ => do .ok <| .effect (.storagePathAssignOp stateId (← buildStoragePath ctx path) (mapAssignOp op) (← buildExpr ctx value))
      | none => .error { message := s!"unknown storage path state `{stateId}`" }
  | .contextRead _ => .error { message := "context.read must be used as an expression" }
  | .eventEmit name fields => do
      let fieldExprs ← fields.mapM fun (n, v) => do .ok (n, ← buildExpr ctx v)
      .ok <| .effect (.eventEmit name fieldExprs)
  | .eventEmitIndexed name _ _ => .error { message := s!"event `{name}` uses indexed fields, which are not supported by Psy IR v0" }

mutual
  /-- Collect else-if chain from a nested if/else body.

  Given the `elseBody` of an IR `.ifElse`, if the body is a single
  `.ifElse` statement, lift it into an `elseIfs` entry and recurse into its
  else body. This lets the printer emit `} else if cond {` instead of
  `} else { if cond { ... } else { ... } }`. -/
  partial def collectElseIfs (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array (Lean.Compiler.Psy.Expr × Array Lean.Compiler.Psy.Stmt) × Array Lean.Compiler.Psy.Stmt)
    | #[.ifElse cond thenBody nestedElseBody] => do
        let condExpr ← buildExpr ctx cond
        let thenStmts ← buildBody ctx thenBody
        let (nestedElseIfs, finalElse) ← collectElseIfs ctx nestedElseBody
        .ok (#[(condExpr, thenStmts)] ++ nestedElseIfs, finalElse)
    | other => do
        let elseStmts ← buildBody ctx other
        .ok (#[], elseStmts)

  /-- Build a `Lean.Compiler.Psy.Stmt` from a portable IR `Statement`. -/
  partial def buildStmt (ctx : BuildContext) : IR.Statement → Except LowerError Lean.Compiler.Psy.Stmt
    | .letBind name type value => do
        .ok <| .letBind name (← typeName type) (← buildExpr ctx value)
    | .letMutBind name type value => do
        .ok <| .letMutBind name (← typeName type) (← buildExpr ctx value)
    | .assign target value => do
        if isStorageTargetRoot ctx target then
          do .ok <| .assign (← resolveStorageTargetRoot ctx target) (← buildExpr ctx value)
        else
          do .ok <| .localAssign (← buildExpr ctx target) (← buildExpr ctx value)
    | .assignOp target op value => do
        if isStorageTargetRoot ctx target then
          do .ok <| .assignOp (← resolveStorageTargetRoot ctx target) (mapAssignOp op) (← buildExpr ctx value)
        else
          do .ok <| .localAssignOp (← buildExpr ctx target) (mapAssignOp op) (← buildExpr ctx value)
    | .effect effect => buildEffectStmt ctx effect
    | .assert condition message _ => do .ok <| .assert (← buildExpr ctx condition) message
    | .assertEq lhs rhs message _ => do .ok <| .assertEq (← buildExpr ctx lhs) (← buildExpr ctx rhs) message
    | .release _ => .error { message := "release statements are not supported by Psy IR v0" }
    | .revert message => .ok <| .revert message
    | .revertWithError _ => .ok <| .revert "revertWithError"
    | .ifElse condition thenBody elseBody => do
        let condExpr ← buildExpr ctx condition
        let thenStmts ← buildBody ctx thenBody
        let (elseIfs, finalElse) ← collectElseIfs ctx elseBody
        .ok <| .ifElse condExpr thenStmts elseIfs finalElse
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        .ok <| .boundedFor indexName start stopExclusive (← buildBody ctx body)
    | .whileLoop _ _ =>
        .error { message := "while loops are not supported by Psy IR v0" }
    | .return value => do .ok <| .returnExpr (← buildExpr ctx value)

  /-- Build an array of `Lean.Compiler.Psy.Stmt` from a portable IR body. -/
  partial def buildBody (ctx : BuildContext) : Array IR.Statement → Except LowerError (Array Lean.Compiler.Psy.Stmt)
    | #[] => .ok #[]
    | arr => arr.mapM (buildStmt ctx)
end

/-- Build a `Lean.Compiler.Psy.Method` from a portable IR `Entrypoint`. -/
def buildMethod (ctx : BuildContext) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Psy.Method := do
  let params ← entrypoint.params.mapM fun (n, t) => do
    let tn ← typeName t
    .ok (n, tn)
  let returns ← match entrypoint.returns with
    | .unit => .ok none
    | other => do .ok (some (← typeName other))
  let body ← buildBody ctx entrypoint.body
  .ok { name := entrypoint.name, params, returns, body }

/-- Build a `Lean.Compiler.Psy.StructDecl` from a portable IR struct declaration. -/
def buildStructDecl (decl : IR.StructDecl) : Except LowerError Lean.Compiler.Psy.StructDecl := do
  let fields ← decl.fields.mapM fun field => do
    let tn ← typeName field.type
    .ok { id := field.id, type := tn, isPublic := field.isPublic, isRef := field.isRef }
  .ok { name := decl.name, isPublic := decl.isPublic, deriveStorage := decl.deriveStorage, fields }

/-- Build a `Lean.Compiler.Psy.StateDecl` from a portable IR state declaration. -/
def buildStateDecl (state : IR.StateDecl) : Except LowerError Lean.Compiler.Psy.StateDecl := do
  match state.kind with
  | .scalar =>
      match state.type with
      | .structType _ => do .ok <| .structRef state.id (← typeName state.type)
      | _ => do .ok <| .scalar state.id (← typeName state.type)
  | .map keyType capacity => do .ok <| .map state.id (← typeName keyType) (← typeName state.type) capacity
  | .array length =>
      let feltBacked := state.type == .u32
      .ok <| .array state.id (← typeName state.type) length feltBacked
  | .dynamicArray =>
      .error { message := s!"state `{state.id}` is storage.dynamicArray; Psy IR v0 does not lower portable dynamic array storage" }


/-- Build a `Lean.Compiler.Psy.Module` from a portable IR `Module` and its
semantic plan. The plan carries the test body, storage layout, and other
resolved shapes; the builder only folds IR into the AST. -/

def buildModuleWithPlan (module : Module) (plan : ProofForge.Backend.Psy.Plan.PsyModulePlan) : Except LowerError Lean.Compiler.Psy.Module := do
  let ctx := { module, layout := plan.storage }
  let structs ← module.structs.mapM buildStructDecl
  let state ← module.state.mapM buildStateDecl
  let methods ← module.entrypoints.mapM (buildMethod ctx)
  let headerComment := s!"// Generated by ProofForge from the portable {module.name} IR.\n// This is Psy source intended for the official Dargo/Psy compiler toolchain."
  .ok {
    name := module.name,
    headerComment,
    structs,
    contractName := module.name,
    state,
    refName := ProofForge.Backend.Psy.Plan.capitalizedRefName module,
    methods,
    test := { name := plan.test.functionName, body := plan.test.bodyLines }
  }

/-- Build a `Lean.Compiler.Psy.Module` from a portable IR `Module`. -/
def buildModule (module : Module) : Except LowerError Lean.Compiler.Psy.Module := do
  match ProofForge.Backend.Psy.Plan.buildModulePlan module with
  | .ok plan => buildModuleWithPlan module plan
  | .error err => .error { message := err.message }

/-- Render a portable IR `Module` to `.psy` source text.

This is the public entrypoint. It validates the module, builds the semantic
plan, lowers the IR + plan to a `Lean.Compiler.Psy.Module` AST, and renders
the AST to source text via `Lean.Compiler.Psy.Printer.module`. -/
def renderModule (module : Module) : Except LowerError String := do
  validateCapabilities module
  validateIdentifiers module
  validateStructs module
  validateEntrypoints module
  validateState module
  validateEntrypointBodies module
  let plan ← match ProofForge.Backend.Psy.Plan.buildModulePlan module with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  let ast ← buildModuleWithPlan module plan
  .ok (Lean.Compiler.Psy.Printer.module ast)

end ProofForge.Backend.Psy.IR
