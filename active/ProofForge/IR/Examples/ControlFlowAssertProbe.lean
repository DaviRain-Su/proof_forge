import ProofForge.IR.Contract

/-!
# Control-Flow + Assertion Coverage Probe

This portable IR module exists to exercise the control-flow and assertion
statement shapes that any target backend must lower:

  * `.ifElse`   — statement-level branch then/else bodies
  * `.assert`   — runtime predicate that reverts on `false`
  * `.assertEq` — runtime equality check that reverts when not equal
  * comparison expressions (`.eq`, `.lt`, …) and boolean expressions that
    produce the predicates the above statements consume
  * nested arithmetic and compound assignment paths that require distinct
    stack temporaries while lowering RHS expressions

The module is chain-neutral; it lowers through both the EVM/Yul and the
Solana sBPF assembly backends. It is the fixture behind the Solana sBPF
control-flow + assertion validation gate (V-GATE-SOLANA-08), which checks
that the emitted `.s` rounds through `sbpf build` and the Mollusk harness
observes the expected success, `assert` revert (exit code 2), and
`assertEq` revert (exit code 3) paths.

The three entrypoints map to sBPF instruction discriminants 0/1/2:

  0 `.lifecycle`       — deterministic storage → 10 and asserts the result.
  1 `.guarded_increment` — asserts `count < 5`, then `count += 1`.
  2 `.equality_guard`  — asserts `count == 7` and returns it.
-/

namespace ProofForge.IR.Examples.ControlFlowAssertProbe

open ProofForge.IR

def stateCount : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def readCount : Expr :=
  .effect (.storageScalarRead "count")

/-- Tag 0 — pure conditional + assertEq success path. -/
def lifecycle : Entrypoint := {
  name := "lifecycle"
  selector? := some "cf01fefe"
  returns := .u64
  body := #[
    .effect (.storageScalarWrite "count" (felt 0)),
    .ifElse (.eq (felt 4) (felt 4)) #[
      .letBind "seed" .u64 (felt 4),
      .effect (.storageScalarWrite "count" (.local "seed"))
    ] #[
      .effect (.storageScalarWrite "count" (felt 99))
    ],
    .ifElse (.lt readCount (felt 3)) #[
      .effect (.storageScalarWrite "count" (felt 100))
    ] #[
      .letBind "next" .u64 (.add readCount (felt 6)),
      .effect (.storageScalarWrite "count" (.local "next"))
    ],
    .letBind "nestedProduct" .u64 (.mul
      (.add (felt 2) (felt 3))
      (.sub (felt 10) (felt 4))),
    .assertEq (.local "nestedProduct") (felt 30) "nested RHS temp slots do not clobber outer LHS",
    .letBind "orderedExpr" .u64 (.mod
      (.sub (felt 30) (.div (felt 12) (felt 2)))
      (felt 5)),
    .assertEq (.local "orderedExpr") (felt 4) "sub/div/mod preserve lhs op rhs order",
    .effect (.storageScalarWrite "count" (felt 40)),
    .effect (.storageScalarAssignOp "count" .sub (felt 7)),
    .effect (.storageScalarAssignOp "count" .div (felt 3)),
    .effect (.storageScalarAssignOp "count" .mod (felt 5)),
    .assertEq readCount (felt 1) "storage compound assignment preserves lhs op rhs order",
    .letMutBind "localTotal" .u64 (felt 40),
    .assignOp (.local "localTotal") .sub (felt 7),
    .assignOp (.local "localTotal") .div (felt 3),
    .assignOp (.local "localTotal") .mod (felt 5),
    .assertEq (.local "localTotal") (felt 1) "local compound assignment lowers through AST",
    .effect (.storageScalarWrite "count" (felt 10)),
    .assertEq readCount (felt 10) "branches land on ten",
    .return readCount
  ]
}

/-- Tag 1 — `assert` revert path: fails when count >= 5. -/
def guardedIncrement : Entrypoint := {
  name := "guarded_increment"
  selector? := some "cf02feed"
  returns := .u64
  body := #[
    .letBind "n" .u64 readCount,
    .assert (.lt (.local "n") (felt 5)) "guard: count under five",
    .letBind "nextVal" .u64 (.add (.local "n") (felt 1)),
    .effect (.storageScalarWrite "count" (.local "nextVal")),
    .return (.local "nextVal")
  ]
}

/-- Tag 2 — `assertEq` revert path: fails unless count == 7. -/
def equalityGuard : Entrypoint := {
  name := "equality_guard"
  selector? := some "cf0307be"
  returns := .u64
  body := #[
    .letBind "n" .u64 readCount,
    .assertEq (.local "n") (felt 7) "guard: count must be seven",
    .return (.local "n")
  ]
}

def module : Module := {
  name := "ControlFlowAssertProbe"
  state := #[stateCount]
  entrypoints := #[lifecycle, guardedIncrement, equalityGuard]
}

end ProofForge.IR.Examples.ControlFlowAssertProbe
