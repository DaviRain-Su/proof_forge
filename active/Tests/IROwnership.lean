import ProofForge.IR.Ownership
import ProofForge.IR.Examples.ArrayProbe

namespace ProofForge.Tests.IROwnership

open ProofForge.IR
open ProofForge.IR.Ownership

def entrypoint (name : String) (body : Array Statement) : Entrypoint := {
  name := name
  returns := .u64
  body := body
}

def moduleOf (entrypoint : Entrypoint) : Module := {
  name := "OwnershipProbe"
  state := #[]
  entrypoints := #[entrypoint]
}

def xsLiteral : Expr :=
  .arrayLit .u64 #[.literal (.u64 1), .literal (.u64 2)]

def validRelease : Entrypoint :=
  entrypoint "valid_release" #[
    .letBind "xs" (.fixedArray .u64 2) xsLiteral,
    .release "xs",
    .letBind "ys" (.fixedArray .u64 2) xsLiteral,
    .return (.arrayGet (.local "ys") (.literal (.u64 0)))
  ]

def doubleRelease : Entrypoint :=
  entrypoint "double_release" #[
    .letBind "xs" (.fixedArray .u64 2) xsLiteral,
    .release "xs",
    .release "xs",
    .return (.literal (.u64 0))
  ]

def useAfterRelease : Entrypoint :=
  entrypoint "use_after_release" #[
    .letBind "xs" (.fixedArray .u64 2) xsLiteral,
    .release "xs",
    .return (.arrayGet (.local "xs") (.literal (.u64 0)))
  ]

def scalarRelease : Entrypoint :=
  entrypoint "scalar_release" #[
    .letBind "x" .u64 (.literal (.u64 1)),
    .release "x",
    .return (.literal (.u64 0))
  ]

def branchMismatch : Entrypoint :=
  entrypoint "branch_mismatch" #[
    .letBind "xs" (.fixedArray .u64 2) xsLiteral,
    .ifElse (.literal (.bool true)) #[
      .release "xs"
    ] #[],
    .return (.literal (.u64 0))
  ]

def requireOk (name : String) (result : Except OwnershipError Unit) : IO Bool := do
  match result with
  | .ok _ =>
      IO.println s!"ir-ownership: ok: {name}"
      pure true
  | .error error =>
      IO.eprintln s!"ir-ownership: FAILED: {name}"
      IO.eprintln s!"  expected success, got: {error.render}"
      pure false

def requireError (name : String) (result : Except OwnershipError Unit) (expected : String) :
    IO Bool := do
  match result with
  | .error error =>
      let actual := error.render
      if actual == expected then
        IO.println s!"ir-ownership: ok: {name}"
        pure true
      else
        IO.eprintln s!"ir-ownership: FAILED: {name}"
        IO.eprintln s!"  expected: {expected}"
        IO.eprintln s!"  actual:   {actual}"
        pure false
  | .ok _ =>
      IO.eprintln s!"ir-ownership: FAILED: {name}"
      IO.eprintln "  expected an ownership error"
      pure false

def main : IO UInt32 := do
  let mut failures := 0
  let cases : Array (IO Bool) := #[
    requireOk "release_then_sum fixture"
      (checkEntrypoint ProofForge.IR.Examples.ArrayProbe.releaseThenSum),
    requireOk "valid release" (checkEntrypoint validRelease),
    requireError "double release" (checkEntrypoint doubleRelease)
      "entrypoint `double_release` ownership error: double release of local `xs`",
    requireError "use after release" (checkEntrypoint useAfterRelease)
      "entrypoint `use_after_release` ownership error: use after release of local `xs`",
    requireError "scalar release" (checkEntrypoint scalarRelease)
      "entrypoint `scalar_release` ownership error: release expects an owned heap-backed local, got `x: U64`",
    requireError "branch mismatch" (checkEntrypoint branchMismatch)
      "entrypoint `branch_mismatch` ownership error: if/else releases local `xs` on only one branch"
  ]
  for test in cases do
    let ok ← test
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"ir-ownership: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"ir-ownership: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.IROwnership

def main : IO UInt32 :=
  ProofForge.Tests.IROwnership.main
