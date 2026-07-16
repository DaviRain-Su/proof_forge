/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Aleo Instructions AST — Counter public-mapping subset (Z2.2).
Models the surface needed for `Counter.golden.aleo` from `leo build`.
-/

namespace ProofForge.Backend.Aleo.Instructions

/-- Literal forms used by Counter. -/
inductive Lit where
  | u64 (n : Nat)
  | u16 (n : Nat)
  deriving Repr, BEq, Inhabited

/-- Operand: register or literal. -/
inductive Operand where
  | reg (n : Nat)
  | lit (l : Lit)
  deriving Repr, BEq, Inhabited

/-- Finalize-body instructions for the Counter public mapping fragment. -/
inductive FinalInst where
  | set (value : Operand) (mapping : String) (key : Operand)
  | getOrUse (mapping : String) (key : Operand) (default : Operand) (dest : Nat)
  | add (a b : Operand) (dest : Nat)
  deriving Repr, BEq, Inhabited

/-- Async function wrapper that only schedules finalize (Counter shape). -/
structure AsyncFunction where
  name : String
  futureReg : Nat := 0
  deriving Repr, BEq, Inhabited

structure FinalizeBlock where
  name : String
  body : Array FinalInst
  deriving Repr, BEq, Inhabited

structure MappingDecl where
  name : String
  keyType : String := "u64.public"
  valueType : String := "u64.public"
  deriving Repr, BEq, Inhabited

structure Program where
  name : String
  mappings : Array MappingDecl
  functions : Array AsyncFunction
  finalizes : Array FinalizeBlock
  constructorEdition : Nat := 0
  deriving Repr, BEq, Inhabited

namespace CounterGolden

/-- Hand-encoded Counter Aleo Instructions matching `Counter.golden.aleo`. -/
def program : Program :=
  {
    name := "counter.aleo"
    mappings := #[{ name := "count" }]
    functions := #[
      { name := "initialize" },
      { name := "increment" },
      { name := "get" }
    ]
    finalizes := #[
      {
        name := "initialize"
        body := #[.set (.lit (.u64 0)) "count" (.lit (.u64 0))]
      },
      {
        name := "increment"
        body := #[
          .getOrUse "count" (.lit (.u64 0)) (.lit (.u64 0)) 0,
          .add (.reg 0) (.lit (.u64 1)) 1,
          .set (.reg 1) "count" (.lit (.u64 0))
        ]
      },
      {
        name := "get"
        body := #[.getOrUse "count" (.lit (.u64 0)) (.lit (.u64 0)) 0]
      }
    ]
    constructorEdition := 0
  }

end CounterGolden

end ProofForge.Backend.Aleo.Instructions
