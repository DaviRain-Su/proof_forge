import ProofForge.IR.Core
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.CorePlan

open ProofForge.IR.Core
open Lean.Compiler.Yul

structure StorageSlotPlan where
  path : StoragePath
  slotExpr : Yul.Expr
  deriving Repr

structure ExprPlan where
  expr : Yul.Expr
  deriving Repr

structure StmtPlan where
  stmts : List Yul.Statement
  deriving Repr

-- Placeholder event plan; refine in Task 5.
structure EventPlan where
  name : String
  topicCount : Nat
  deriving Repr

structure EntrypointPlan where
  name : String
  selector : UInt32
  params : List (String × CoreType)
  body : List Yul.Statement
  deriving Repr

structure EvmCorePlan where
  moduleName : String
  stateSlots : List StorageSlotPlan
  entrypoints : List EntrypointPlan
  events : List EventPlan
  constructor : Option (List Yul.Statement)
  deriving Repr

def buildEvmCorePlan (m : CoreModule) : EvmCorePlan :=
  let stateSlots := m.state.enum.map fun (i, _s) =>
    { path := StoragePath.scalar i, slotExpr := Yul.Expr.num i }
  let entrypoints := m.entrypoints.map fun e =>
    { name := e.name
    , selector := 0 -- TODO: compute selector from signature in Task 5
    , params := e.params
    , body := []    -- TODO: lower body in Task 5
    }
  { moduleName := m.name
  , stateSlots := stateSlots
  , entrypoints := entrypoints
  , events := []
  , constructor := .none
  }

end ProofForge.Backend.Evm.CorePlan
