import ProofForge.IR.Contract
import ProofForge.IR.Core
import ProofForge.IR.Core.Error

namespace ProofForge.IR.Elaborate

open ProofForge.IR
open ProofForge.IR.Core
open ProofForge.IR.Core.Error

/-- Inhabited instances so that partial recursive elaborators over the mutual
Surface IR `Expr`/`Effect` types can compile. -/
instance : Inhabited StoragePath where default := .scalar 0
instance : Inhabited LValue where default := .local ""
instance : Inhabited CoreExpr where default := .literal .unitLit
instance : Inhabited CoreEffect where default := .assert default none
instance : Inhabited CoreStmt where default := .effect default

/-- Flatten a list of lists (local helper to avoid relying on a particular
`List` namespace member being available). -/
def flatten (xss : List (List α)) : List α :=
  xss.foldr List.append []

/-- Look up the storage slot index for a state variable name. Unknown names
now surface as `ElabError.unknownState` instead of silently using slot `0`. -/
def stateSlot (stateSlots : List (String × Nat)) (name : String) : Except ElabError Nat :=
  match stateSlots.find? (fun (n, _) => n == name) with
  | some (_, idx) => .ok idx
  | none => .error (.unknownState name)

/-- Map a Surface IR `ValueType` to the chain-neutral Core IR `CoreType`. -/
def elaborateType (t : ValueType) : Except ElabError CoreType :=
  match t with
  | .unit => .ok .unit
  | .bool => .ok .bool
  | .u8 => .ok .u8
  | .u32 => .ok .u32
  | .u64 => .ok .u64
  | .u128 => .ok .u128
  | .address => .ok .address
  | .bytes => .ok .bytes
  | .string => .ok .string
  | .hash => .ok .hash
  | .fixedArray e n => do .ok (.fixedArray (← elaborateType e) n)
  | .structType n => .ok (.structType n)
  | .array e => do .ok (.array (← elaborateType e))

/-- Map a Surface IR `Literal` to a Core IR `CoreLiteral`. -/
def elaborateLiteral (l : Literal) : Except ElabError CoreLiteral :=
  match l with
  | .u8 n => .ok (.u8Lit n.toUInt8)
  | .u32 n => .ok (.u32Lit n.toUInt32)
  | .u64 n => .ok (.u64Lit n.toUInt64)
  | .u128 n => .ok (.u128Lit (BitVec.ofNat 128 n))
  | .bool b => .ok (.boolLit b)
  | .hash4 _ _ _ _ => .error (.unsupported "hash4 literal")
  | .address _ => .error (.unsupported "address literal")

/-- Map Surface `AssignOp` to the corresponding Core `BinaryOp`. -/
def assignOpToBinaryOp (op : AssignOp) : Except ElabError BinaryOp :=
  match op with
  | .add => .ok .add
  | .sub => .ok .sub
  | .mul => .ok .mul
  | .div => .ok .div
  | .mod => .ok .mod
  | .bitAnd => .ok .and
  | .bitOr => .ok .or
  | .bitXor => .ok .xor
  | .shiftLeft => .ok .shl
  | .shiftRight => .ok .shr

/-- Map a Surface IR `ContextField` to a Core IR `ContextKind`.
Only the fields needed for Counter/ValueVault-style modules are handled; all
others are rejected with `ElabError.unsupported`. -/
def elaborateContextField (field : ContextField) : Except ElabError ContextKind :=
  match field with
  | .userId => .ok .sender
  | .contractId => .ok .contractAddress
  | .timestamp => .ok .blockTimestamp
  | .checkpointId => .ok .blockNumber
  | other => .error (.unsupported s!"context field {repr other}")

mutual
  /-- Elaborate a Surface IR `Expr` into a Core IR `CoreExpr`. `stateSlots`
maps declared state-variable names to their target-neutral scalar slot index. -/
  partial def elaborateExpr (stateSlots : List (String × Nat)) (e : Expr) : Except ElabError CoreExpr :=
    match e with
    | .literal l => do .ok (.literal (← elaborateLiteral l))
    | .local name => .ok (.local name)
    | .field base fieldName => do .ok (.fieldAccess (← elaborateExpr stateSlots base) fieldName)
    | .arrayGet array index => do .ok (.arrayIndex (← elaborateExpr stateSlots array) (← elaborateExpr stateSlots index))
    | .add lhs rhs _ => do .ok (.binary .add (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .sub lhs rhs _ => do .ok (.binary .sub (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .mul lhs rhs _ => do .ok (.binary .mul (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .div lhs rhs => do .ok (.binary .div (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .mod lhs rhs => do .ok (.binary .mod (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .eq lhs rhs => do .ok (.binary .eq (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .ne lhs rhs => do .ok (.binary .ne (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .lt lhs rhs => do .ok (.binary .lt (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .le lhs rhs => do .ok (.binary .le (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .gt lhs rhs => do .ok (.binary .gt (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .ge lhs rhs => do .ok (.binary .ge (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .boolAnd lhs rhs => do .ok (.binary .and (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .boolOr lhs rhs => do .ok (.binary .or (← elaborateExpr stateSlots lhs) (← elaborateExpr stateSlots rhs))
    | .boolNot value => do .ok (.unary .not (← elaborateExpr stateSlots value))
    -- Surface IR represents storage reads and context reads as effects. In
    -- expression position we lift them to the corresponding Core expression so
    -- target lowering can emit the actual load/context read.
    | .effect (.storageScalarRead id) => do .ok (.storageRead (.scalar (← stateSlot stateSlots id)))
    | .effect (.contextRead field) => do .ok (.contextRead (← elaborateContextField field))
    | .effect other => .error (.unsupported s!"effect-in-expr {repr other}")
    | other => .error (.unsupported s!"expr {repr other}")

  /-- Elaborate a Surface IR `Effect` into a Core IR `CoreEffect`. -/
  partial def elaborateEffect (stateSlots : List (String × Nat)) (eff : Effect) : Except ElabError CoreEffect :=
    match eff with
    | .storageScalarRead id => do .ok (.storageRead (.scalar (← stateSlot stateSlots id)))
    | .storageScalarWrite id value => do .ok (.storageWrite (.scalar (← stateSlot stateSlots id)) (← elaborateExpr stateSlots value))
    | .storageScalarAssignOp id op value => do
        let slot ← stateSlot stateSlots id
        let rhs := CoreExpr.binary (← assignOpToBinaryOp op) (.storageRead (.scalar slot)) (← elaborateExpr stateSlots value)
        .ok (.storageWrite (.scalar slot) rhs)
    | .eventEmit name fields => do
        let args ← fields.toList.mapM (fun (_, e) => elaborateExpr stateSlots e)
        .ok (.eventEmit name args)
    | .contextRead field => do .ok (.contextReadEffect (← elaborateContextField field))
    | other => .error (.unsupported s!"effect {repr other}")
end

/-- Elaborate a Surface IR `Statement` into a list of Core IR `CoreStmt`s. -/
partial def elaborateStmt (stateSlots : List (String × Nat)) (s : Statement) : Except ElabError (List CoreStmt) :=
  match s with
  | .letBind name ty value => do
      pure [ .letBind name (← elaborateType ty) (← elaborateExpr stateSlots value) ]
  | .letMutBind name ty value => do
      pure [ .letMutBind name (← elaborateType ty) (← elaborateExpr stateSlots value) ]
  | .assign target value => do
      pure [ .assign (← elaborateLValue stateSlots target) (← elaborateExpr stateSlots value) ]
  | .assignOp target op value => do
      pure [ .assignOp (← elaborateLValue stateSlots target) (← assignOpToBinaryOp op) (← elaborateExpr stateSlots value) ]
  | .effect eff => do
      pure [ .effect (← elaborateEffect stateSlots eff) ]
  | .assert cond msg _ => do
      pure [ .effect (.assert (← elaborateExpr stateSlots cond) (some msg)) ]
  | .revert msg => do
      pure [ .effect (.revert (some msg)) ]
  | .ifElse cond thenSt elseSt => do
      let thenStmtLists ← thenSt.toList.mapM (elaborateStmt stateSlots)
      let elseStmtLists ← elseSt.toList.mapM (elaborateStmt stateSlots)
      pure [ .ifElse (← elaborateExpr stateSlots cond) (flatten thenStmtLists) (flatten elseStmtLists) ]
  | .return val => do
      pure [ .return (← elaborateExpr stateSlots val) ]
  | other => .error (.unsupported s!"stmt {repr other}")
where
  elaborateLValue (stateSlots : List (String × Nat)) (target : Expr) : Except ElabError LValue :=
    match target with
    | .local name => .ok (.local name)
    | .effect (.storageScalarRead id) => do .ok (.storage (.scalar (← stateSlot stateSlots id)))
    | other => .error (.unsupported s!"lvalue {repr other}")

/-- Elaborate a Surface IR `Module` into a Core IR `CoreModule`.
This is intentionally partial: Counter and ValueVault-style modules are fully
supported, and anything outside that fragment returns `ElabError.unsupported`. -/
def elaborateModule (m : Module) : Except ElabError CoreModule := do
  let stateSlots := m.state.zipIdx.toList.map (fun (s, i) => (s.id, i))
  let state ← m.state.toList.mapM fun s => do
    pure { name := s.id, ty := (← elaborateType s.type), initializer := none }
  let entrypoints ← m.entrypoints.toList.mapM fun e => do
    let params ← e.params.toList.mapM fun (name, ty) => do
      pure (name, (← elaborateType ty))
    let bodyStmtLists ← e.body.toList.mapM (elaborateStmt stateSlots)
    let bodyStmts := flatten bodyStmtLists
    pure
      { name := e.name
      , params := params
      , retTy := (← elaborateType e.returns)
      , body := bodyStmts
      }
  pure
    { name := m.name
    , structs := []
    , state := state
    , entrypoints := entrypoints
    , events := []
    }

end ProofForge.IR.Elaborate
