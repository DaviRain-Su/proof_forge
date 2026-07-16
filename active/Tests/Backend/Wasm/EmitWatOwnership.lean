import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Ownership

namespace ProofForge.Tests.EmitWatOwnership

open ProofForge.IR

def entrypoint (name : String) (body : Array Statement) : Entrypoint := {
  name := name
  returns := .u64
  body := body
}

def moduleOf (entrypoint : Entrypoint) : Module := {
  name := "EmitWatOwnershipProbe"
  state := #[]
  entrypoints := #[entrypoint]
}

def xsLiteral : Expr :=
  .arrayLit .u64 #[.literal (.u64 1), .literal (.u64 2)]

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

def renderError? (module : ProofForge.IR.Module) : Option String :=
  match ProofForge.Backend.WasmHost.EmitWat.renderModule module with
  | .ok _ => none
  | .error error => some error.message

def requireError (name : String) (module : ProofForge.IR.Module) (expected : String) :
    IO Bool := do
  match renderError? module with
  | some actual =>
      if actual == expected then
        IO.println s!"emitwat-ownership: ok: {name}"
        pure true
      else
        IO.eprintln s!"emitwat-ownership: FAILED: {name}"
        IO.eprintln s!"  expected: {expected}"
        IO.eprintln s!"  actual:   {actual}"
        pure false
  | none =>
      IO.eprintln s!"emitwat-ownership: FAILED: {name}"
      IO.eprintln "  expected EmitWat to reject the module"
      pure false

def main : IO UInt32 := do
  let mut failures := 0
  let cases : Array (IO Bool) := #[
    requireError "double release"
      (moduleOf doubleRelease)
      "EmitWat: entrypoint `double_release` ownership error: double release of local `xs`",
    requireError "use after release"
      (moduleOf useAfterRelease)
      "EmitWat: entrypoint `use_after_release` ownership error: use after release of local `xs`"
  ]
  for test in cases do
    let ok ← test
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"emitwat-ownership: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"emitwat-ownership: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.EmitWatOwnership

def main : IO UInt32 :=
  ProofForge.Tests.EmitWatOwnership.main
