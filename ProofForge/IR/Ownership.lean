import ProofForge.IR.Contract

namespace ProofForge.IR.Ownership

open ProofForge.IR

/-! Name-based ownership checks for explicit IR `release` statements.

The checker is intentionally narrower than backend type checking: it only
guards the ownership rules that make `Statement.release` meaningful. Unknown
locals that are unrelated to release are left for the backend/type checker so
existing diagnostics stay stable.
-/

inductive LocalStatus where
  | live
  | released
  deriving Repr, BEq, DecidableEq

structure LocalBinding where
  name : String
  type : ValueType
  ownedHeap : Bool
  status : LocalStatus := .live
  deriving Repr, BEq, DecidableEq

abbrev Env := List LocalBinding

structure OwnershipError where
  entrypoint : String
  message : String
  deriving Repr, BEq, DecidableEq

def OwnershipError.render (error : OwnershipError) : String :=
  s!"entrypoint `{error.entrypoint}` ownership error: {error.message}"

def fail (entrypoint message : String) : Except OwnershipError α :=
  .error { entrypoint := entrypoint, message := message }

def isOwnedHeapBacked : ValueType → Bool
  | .fixedArray _ _ => true
  | .structType _ => true
  | _ => false

def lookup? (env : Env) (name : String) : Option LocalBinding :=
  match env with
  | [] => none
  | binding :: rest =>
      if binding.name == name then
        some binding
      else
        lookup? rest name

def bind (env : Env) (name : String) (type : ValueType) (ownedHeap : Bool) : Env :=
  let next : LocalBinding := { name := name, type := type, ownedHeap := ownedHeap, status := .live }
  match env with
  | [] => [next]
  | binding :: rest =>
      if binding.name == name then
        next :: rest
      else
        binding :: bind rest name type ownedHeap

def setStatus (env : Env) (name : String) (status : LocalStatus) : Env :=
  match env with
  | [] => []
  | binding :: rest =>
      if binding.name == name then
        { binding with status := status } :: rest
      else
        binding :: setStatus rest name status

def initialEnv (entrypoint : Entrypoint) : Env :=
  entrypoint.params.foldl
    (fun env param => bind env param.fst param.snd false)
    []

def ensureNotReleased (entrypoint : String) (env : Env) (name : String) :
    Except OwnershipError Unit :=
  match lookup? env name with
  | some { status := .released, .. } =>
      fail entrypoint s!"use after release of local `{name}`"
  | _ => .ok ()

mutual
  partial def checkExpr (entrypoint : String) (env : Env) : Expr →
      Except OwnershipError Unit
    | .literal _ => .ok ()
    | .local name => ensureNotReleased entrypoint env name
    | .arrayLit _ values =>
        values.foldlM (init := ()) fun _ value => checkExpr entrypoint env value
    | .arrayGet array index => do
        checkExpr entrypoint env array
        checkExpr entrypoint env index
    | .memoryArrayNew _ length =>
        checkExpr entrypoint env length
    | .memoryArrayLength array =>
        checkExpr entrypoint env array
    | .memoryArrayGet array index => do
        checkExpr entrypoint env array
        checkExpr entrypoint env index
    | .structLit _ fields =>
        fields.foldlM (init := ()) fun _ field => checkExpr entrypoint env field.snd
    | .field base _ => checkExpr entrypoint env base
    | .add lhs rhs
    | .sub lhs rhs
    | .mul lhs rhs
    | .div lhs rhs
    | .mod lhs rhs
    | .pow lhs rhs
    | .bitAnd lhs rhs
    | .bitOr lhs rhs
    | .bitXor lhs rhs
    | .shiftLeft lhs rhs
    | .shiftRight lhs rhs
    | .eq lhs rhs
    | .ne lhs rhs
    | .lt lhs rhs
    | .le lhs rhs
    | .gt lhs rhs
    | .ge lhs rhs
    | .boolAnd lhs rhs
    | .boolOr lhs rhs
    | .hashTwoToOne lhs rhs => do
        checkExpr entrypoint env lhs
        checkExpr entrypoint env rhs
    | .cast value _ => checkExpr entrypoint env value
    | .boolNot value => checkExpr entrypoint env value
    | .hashValue a b c d => do
        checkExpr entrypoint env a
        checkExpr entrypoint env b
        checkExpr entrypoint env c
        checkExpr entrypoint env d
    | .hash preimage => checkExpr entrypoint env preimage
    | .nativeValue => .ok ()
    | .crosscallInvoke target methodId args => do
        checkExpr entrypoint env target
        checkExpr entrypoint env methodId
        args.foldlM (init := ()) fun _ arg => checkExpr entrypoint env arg
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ => do
        checkExpr entrypoint env target
        checkExpr entrypoint env methodId
        args.foldlM (init := ()) fun _ arg => checkExpr entrypoint env arg
    | .crosscallInvokeValueTyped target methodId callValue args _ => do
        checkExpr entrypoint env target
        checkExpr entrypoint env methodId
        checkExpr entrypoint env callValue
        args.foldlM (init := ()) fun _ arg => checkExpr entrypoint env arg
    | .crosscallCreate callValue _ => checkExpr entrypoint env callValue
    | .crosscallCreate2 callValue salt _ => do
        checkExpr entrypoint env callValue
        checkExpr entrypoint env salt
    | .effect effect => checkEffect entrypoint env effect

  partial def checkEffect (entrypoint : String) (env : Env) : Effect →
      Except OwnershipError Unit
    | .storageScalarRead _ => .ok ()
    | .storageScalarWrite _ value
    | .storageScalarAssignOp _ _ value
    | .storageStructFieldWrite _ _ value => checkExpr entrypoint env value
    | .storageMapContains _ key
    | .storageMapGet _ key
    | .storageArrayRead _ key
    | .storageArrayStructFieldRead _ key _ => checkExpr entrypoint env key
    | .storageMapInsert _ key value
    | .storageMapSet _ key value
    | .storageArrayWrite _ key value
    | .storageArrayStructFieldWrite _ key _ value => do
        checkExpr entrypoint env key
        checkExpr entrypoint env value
    | .storageDynamicArrayPush _ value => checkExpr entrypoint env value
    | .storageDynamicArrayPop _ => .ok ()
    | .memoryArraySet _ index value => do
        checkExpr entrypoint env index
        checkExpr entrypoint env value
    | .storageStructFieldRead _ _ => .ok ()
    | .storagePathRead _ path =>
        path.foldlM (init := ()) fun _ segment => checkStoragePathSegment entrypoint env segment
    | .storagePathWrite _ path value
    | .storagePathAssignOp _ path _ value => do
        path.foldlM (init := ()) fun _ segment => checkStoragePathSegment entrypoint env segment
        checkExpr entrypoint env value
    | .contextRead _ => .ok ()
    | .eventEmit _ fields =>
        fields.foldlM (init := ()) fun _ field => checkExpr entrypoint env field.snd
    | .eventEmitIndexed _ indexedFields dataFields => do
        indexedFields.foldlM (init := ()) fun _ field => checkExpr entrypoint env field.snd
        dataFields.foldlM (init := ()) fun _ field => checkExpr entrypoint env field.snd

  partial def checkStoragePathSegment (entrypoint : String) (env : Env) :
      StoragePathSegment → Except OwnershipError Unit
    | .field _ => .ok ()
    | .index index => checkExpr entrypoint env index
    | .mapKey key => checkExpr entrypoint env key
end

def releaseLocal (entrypoint : String) (env : Env) (name : String) :
    Except OwnershipError Env :=
  match lookup? env name with
  | none => fail entrypoint s!"release of unknown local `{name}`"
  | some binding =>
      match binding.status with
      | .released => fail entrypoint s!"double release of local `{name}`"
      | .live =>
          if binding.ownedHeap && isOwnedHeapBacked binding.type then
            .ok (setStatus env name .released)
          else
            fail entrypoint
              s!"release expects an owned heap-backed local, got `{name}: {binding.type.name}`"

def statusOf? (env : Env) (name : String) : Option LocalStatus :=
  match lookup? env name with
  | some binding => some binding.status
  | none => none

def mergeBranches (entrypoint : String) (base thenEnv elseEnv : Env) :
    Except OwnershipError Env :=
  base.foldlM (init := base) fun merged binding => do
    let thenStatus := statusOf? thenEnv binding.name
    let elseStatus := statusOf? elseEnv binding.name
    if thenStatus == elseStatus then
      match thenStatus with
      | some status => .ok (setStatus merged binding.name status)
      | none => .ok merged
    else
      fail entrypoint s!"if/else releases local `{binding.name}` on only one branch"

def ensureLoopPreservesOwnership (entrypoint : String) (base bodyEnv : Env) :
    Except OwnershipError Unit :=
  base.foldlM (init := ()) fun _ binding =>
    if statusOf? bodyEnv binding.name == some binding.status then
      .ok ()
    else
      fail entrypoint
        s!"bounded loop body changes ownership of local `{binding.name}`; release inside loops is not currently supported"

mutual
  partial def checkStatement (entrypoint : String) (env : Env) : Statement →
      Except OwnershipError Env
    | .letBind name type value
    | .letMutBind name type value => do
        checkExpr entrypoint env value
        .ok (bind env name type (isOwnedHeapBacked type))
    | .assign target value => do
        checkExpr entrypoint env target
        checkExpr entrypoint env value
        .ok env
    | .assignOp target _ value => do
        checkExpr entrypoint env target
        checkExpr entrypoint env value
        .ok env
    | .effect effect => do
        checkEffect entrypoint env effect
        .ok env
    | .assert condition _ _ => do
        checkExpr entrypoint env condition
        .ok env
    | .assertEq lhs rhs _ _ => do
        checkExpr entrypoint env lhs
        checkExpr entrypoint env rhs
        .ok env
    | .release name => releaseLocal entrypoint env name
    | .revert _ => .ok env
    | .revertWithError _ => .ok env
    | .ifElse condition thenBody elseBody => do
        checkExpr entrypoint env condition
        let thenEnv ← checkStatements entrypoint env thenBody
        let elseEnv ← checkStatements entrypoint env elseBody
        mergeBranches entrypoint env thenEnv elseEnv
    | .boundedFor _ _ _ body => do
        let bodyEnv ← checkStatements entrypoint env body
        ensureLoopPreservesOwnership entrypoint env bodyEnv
        .ok env
    | .whileLoop _ body => do
        let bodyEnv ← checkStatements entrypoint env body
        ensureLoopPreservesOwnership entrypoint env bodyEnv
        .ok env
    | .return value => do
        checkExpr entrypoint env value
        .ok env

  partial def checkStatements (entrypoint : String) (env : Env) (body : Array Statement) :
      Except OwnershipError Env :=
    body.foldlM (init := env) fun current statement =>
      checkStatement entrypoint current statement
end

def checkEntrypoint (entrypoint : Entrypoint) : Except OwnershipError Unit := do
  discard <| checkStatements entrypoint.name (initialEnv entrypoint) entrypoint.body

def checkModule (module : Module) : Except OwnershipError Unit := do
  module.entrypoints.foldlM (init := ()) fun _ entrypoint => checkEntrypoint entrypoint

def checkEntrypointOk (entrypoint : Entrypoint) : Bool :=
  match checkEntrypoint entrypoint with
  | .ok _ => true
  | .error _ => false

def checkModuleOk (module : Module) : Bool :=
  match checkModule module with
  | .ok _ => true
  | .error _ => false

end ProofForge.IR.Ownership
