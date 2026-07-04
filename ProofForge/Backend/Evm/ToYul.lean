import ProofForge.Backend.Evm.Plan
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def slotExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.num slot

def helperCall (helper : Helper) (args : Array Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call helper.name args

def checkedAddName : String := "__pf_checked_add"
def checkedSubName : String := "__pf_checked_sub"
def checkedMulName : String := "__pf_checked_mul"

def checkedArithExpr (op : AssignOp) (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  match op with
  | .add => Lean.Compiler.Yul.call checkedAddName #[lhs, rhs]
  | .sub => Lean.Compiler.Yul.call checkedSubName #[lhs, rhs]
  | .mul => Lean.Compiler.Yul.call checkedMulName #[lhs, rhs]
  | .div => Lean.Compiler.Yul.builtin "div" #[lhs, rhs]
  | .mod => Lean.Compiler.Yul.builtin "mod" #[lhs, rhs]
  | .bitAnd => Lean.Compiler.Yul.builtin "and" #[lhs, rhs]
  | .bitOr => Lean.Compiler.Yul.builtin "or" #[lhs, rhs]
  | .bitXor => Lean.Compiler.Yul.builtin "xor" #[lhs, rhs]
  | .shiftLeft => Lean.Compiler.Yul.builtin "shl" #[rhs, lhs]
  | .shiftRight => Lean.Compiler.Yul.builtin "shr" #[rhs, lhs]

def contextExpr : ContextField → Lean.Compiler.Yul.Expr
  | .userId => Lean.Compiler.Yul.builtin "caller" #[]
  | .contractId => Lean.Compiler.Yul.builtin "address" #[]
  | .checkpointId => Lean.Compiler.Yul.builtin "number" #[]
  | .timestamp => Lean.Compiler.Yul.builtin "timestamp" #[]
  | .chainId => Lean.Compiler.Yul.builtin "chainid" #[]
  | .gasPrice => Lean.Compiler.Yul.builtin "gasprice" #[]
  | .gasLeft => Lean.Compiler.Yul.builtin "gas" #[]
  | .baseFee => Lean.Compiler.Yul.builtin "basefee" #[]
  | .prevRandao => Lean.Compiler.Yul.builtin "prevrandao" #[]
  | .origin => Lean.Compiler.Yul.builtin "origin" #[]
  | .coinbase => Lean.Compiler.Yul.builtin "coinbase" #[]
  | .blockHash _ => Lean.Compiler.Yul.builtin "blockhash" #[]

def calldataWordExpr (paramIndex : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num (4 + paramIndex * 32)]

def hashPackExpr
    (a b c d : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "or" #[
    Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 192, a],
    Lean.Compiler.Yul.builtin "or" #[
      Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 128, b],
      Lean.Compiler.Yul.builtin "or" #[
        Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 64, c],
        d
      ]
    ]
  ]

def lowerValuePlan
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    ValuePlan → Except ε Lean.Compiler.Yul.Expr
  | .irExpr expr => lowerExpr expr

def lowerMapValueSlotExpr
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  let mut current := slotExpr rootSlot
  for key in keys do
    current := helperCall Helper.mapSlot #[current, ← lowerValuePlan lowerExpr key]
  .ok current

def lowerMapPresenceSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  match keys.toList.reverse with
  | [] => .error (mkError "EVM map presence slot plan requires at least one key")
  | last :: parentKeysReversed =>
      let mut parent := slotExpr rootSlot
      for key in parentKeysReversed.reverse do
        parent := helperCall Helper.mapSlot #[parent, ← lowerValuePlan lowerExpr key]
      .ok (helperCall Helper.mapPresenceSlot #[parent, ← lowerValuePlan lowerExpr last])

def storageSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StorageSlotPlan → Except ε Lean.Compiler.Yul.Expr
  | .scalarSlot slot => .ok (slotExpr slot)
  | .fixedSlot slotHex => .ok (Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex slotHex))
  | .mapValueSlot rootSlot keys =>
      if keys.isEmpty then
        .error (mkError "EVM map value slot plan requires at least one key")
      else
        lowerMapValueSlotExpr lowerExpr rootSlot keys
  | .mapPresenceSlot rootSlot keys =>
      lowerMapPresenceSlotExpr mkError lowerExpr rootSlot keys
  | .arraySlot rootSlot length index => do
      .ok (helperCall Helper.arraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        ← lowerValuePlan lowerExpr index
      ])
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset index => do
      .ok (helperCall Helper.structArraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        Lean.Compiler.Yul.Expr.num fieldCount,
        Lean.Compiler.Yul.Expr.num fieldOffset,
        ← lowerValuePlan lowerExpr index
      ])

partial def exprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    ExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
  | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
  | .calldataWord paramIndex => .ok (calldataWordExpr paramIndex)
  | .storageLoad slot => do
      .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])
  | .builtin name args => do
      .ok (Lean.Compiler.Yul.builtin name (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .helperCall helper args => do
      .ok (helperCall helper (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .checkedArith op lhs rhs => do
      .ok (checkedArithExpr op
        (← exprPlanExpr mkError lowerExpr lowerEffect lhs)
        (← exprPlanExpr mkError lowerExpr lowerEffect rhs))
  | .hashPack a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .context field =>
      .ok (contextExpr field)
  | .crosscall .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support crosscall plans yet")
  | .create .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support create plans yet")
  | .cast source _ =>
      exprPlanExpr mkError lowerExpr lowerEffect source
  | .localAbiWords .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support ABI word expansion plans yet")
  | .localCrosscallWords .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support crosscall word expansion plans yet")
  | .structField .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support struct field plans yet")
  | .arrayGet .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support array get plans yet")
  | .localArrayGet .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support local array get plans yet")
  | .arrayLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support array literal plans yet")
  | .structLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support struct literal plans yet")
  | .hashValue a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .hash preimage => do
      .ok (helperCall Helper.hashWord #[← exprPlanExpr mkError lowerExpr lowerEffect preimage])
  | .hashTwoToOne lhs rhs => do
      .ok (helperCall Helper.hashPair #[
        ← exprPlanExpr mkError lowerExpr lowerEffect lhs,
        ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      ])
  | .nativeValue =>
      .ok (Lean.Compiler.Yul.builtin "callvalue" #[])
  | .effect effect =>
      lowerEffect effect

/-! ## Plan-driven helper requirements

`StorageSlotPlan.requiredHelpers` lets the plan declare which EVM helper functions
a given slot plan needs, without `ToYul` re-discovering them from Yul text. -/

def slotHelperRequirements (slot : StorageSlotPlan) : HelperSet :=
  slot.requiredHelpers

def storageLayoutHelpers (layout : StorageLayout) : HelperSet :=
  layout.states.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map _ _ => HelperSet.insert (HelperSet.insert acc Helper.mapSlot) Helper.mapPresenceSlot
    | _ => acc

end ProofForge.Backend.Evm.ToYul
