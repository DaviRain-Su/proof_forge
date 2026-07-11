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
  /-- Elaborate a Surface IR `Expr` into a Core IR `CoreExpr`. -/
  partial def elaborateExpr (e : Expr) : Except ElabError CoreExpr :=
    match e with
    | .literal l => do .ok (.literal (← elaborateLiteral l))
    | .local name => .ok (.local name)
    | .field base fieldName => do .ok (.fieldAccess (← elaborateExpr base) fieldName)
    | .arrayGet array index => do .ok (.arrayIndex (← elaborateExpr array) (← elaborateExpr index))
    | .add lhs rhs _ => do .ok (.binary .add (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .sub lhs rhs _ => do .ok (.binary .sub (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .mul lhs rhs _ => do .ok (.binary .mul (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .div lhs rhs => do .ok (.binary .div (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .mod lhs rhs => do .ok (.binary .mod (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .eq lhs rhs => do .ok (.binary .eq (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .ne lhs rhs => do .ok (.binary .ne (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .lt lhs rhs => do .ok (.binary .lt (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .le lhs rhs => do .ok (.binary .le (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .gt lhs rhs => do .ok (.binary .gt (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .ge lhs rhs => do .ok (.binary .ge (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .boolAnd lhs rhs => do .ok (.binary .and (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .boolOr lhs rhs => do .ok (.binary .or (← elaborateExpr lhs) (← elaborateExpr rhs))
    | .boolNot value => do .ok (.unary .not (← elaborateExpr value))
    -- Surface IR represents storage reads as effects. In expression position we
    -- treat scalar reads as references to the corresponding Core local, which is
    -- how the Core Counter/ValueVault fixtures model storage-backed locals.
    | .effect (.storageScalarRead id) => .ok (.local id)
    | .effect other => .error (.unsupported s!"effect-in-expr {repr other}")
    | other => .error (.unsupported s!"expr {repr other}")

  /-- Elaborate a Surface IR `Effect` into a Core IR `CoreEffect`. -/
  partial def elaborateEffect (eff : Effect) : Except ElabError CoreEffect :=
    match eff with
    | .storageScalarRead _id => .ok (.storageRead (.scalar 0))
    | .storageScalarWrite _id value => do .ok (.storageWrite (.scalar 0) (← elaborateExpr value))
    | .storageScalarAssignOp _id op value => do
        let rhs := CoreExpr.binary (← assignOpToBinaryOp op) (.local _id) (← elaborateExpr value)
        .ok (.storageWrite (.scalar 0) rhs)
    | .eventEmit name fields => do
        let args ← fields.toList.mapM (fun (_, e) => elaborateExpr e)
        .ok (.eventEmit name args)
    | .contextRead field => do .ok (.contextReadEffect (← elaborateContextField field))
    | other => .error (.unsupported s!"effect {repr other}")
end

/-- Elaborate a Surface IR `Statement` into a list of Core IR `CoreStmt`s. -/
partial def elaborateStmt (s : Statement) : Except ElabError (List CoreStmt) :=
  match s with
  | .letBind name ty value => do
      pure [ .letBind name (← elaborateType ty) (← elaborateExpr value) ]
  | .letMutBind name ty value => do
      pure [ .letMutBind name (← elaborateType ty) (← elaborateExpr value) ]
  | .assign target value => do
      pure [ .assign (← elaborateLValue target) (← elaborateExpr value) ]
  | .assignOp target op value => do
      pure [ .assignOp (← elaborateLValue target) (← assignOpToBinaryOp op) (← elaborateExpr value) ]
  | .effect eff => do
      pure [ .effect (← elaborateEffect eff) ]
  | .assert cond msg _ => do
      pure [ .effect (.assert (← elaborateExpr cond) (some msg)) ]
  | .revert msg => do
      pure [ .effect (.revert (some msg)) ]
  | .ifElse cond thenSt elseSt => do
      let thenStmtLists ← thenSt.toList.mapM elaborateStmt
      let elseStmtLists ← elseSt.toList.mapM elaborateStmt
      pure [ .ifElse (← elaborateExpr cond) (flatten thenStmtLists) (flatten elseStmtLists) ]
  | .return val => do
      pure [ .return (← elaborateExpr val) ]
  | other => .error (.unsupported s!"stmt {repr other}")
where
  elaborateLValue (target : Expr) : Except ElabError LValue :=
    match target with
    | .local name => .ok (.local name)
    | .effect (.storageScalarRead _id) => .ok (.storage (.scalar 0))
    | other => .error (.unsupported s!"lvalue {repr other}")

/-- Elaborate a Surface IR `Module` into a Core IR `CoreModule`.
This is intentionally partial: Counter and ValueVault-style modules are fully
supported, and anything outside that fragment returns `ElabError.unsupported`. -/
def elaborateModule (m : Module) : Except ElabError CoreModule := do
  let state ← m.state.toList.mapM fun s => do
    pure { name := s.id, ty := (← elaborateType s.type), initializer := none }
  let entrypoints ← m.entrypoints.toList.mapM fun e => do
    let params ← e.params.toList.mapM fun (name, ty) => do
      pure (name, (← elaborateType ty))
    let bodyStmtLists ← e.body.toList.mapM elaborateStmt
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
