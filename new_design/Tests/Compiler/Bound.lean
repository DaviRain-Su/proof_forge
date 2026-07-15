import ProofForgeV2.Core.Source
import ProofForgeV2.Compiler.Pipeline

namespace Tests.Compiler.Bound

open ProofForgeV2
open ProofForgeV2.Source

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectBoundFailure (result : CompileResult α) (message : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == "PF-BOUND-001") s!"{message}: got {error.render}"
  | .ok _ => throw <| IO.userError message

private def viewProgram (body : Array Statement) : Program :=
  Program.build "BoundProbe" #[
    .entry {
      name := "run", params := #[], result := .u64, mode := .view,
      body
    }
  ]

/-- TST-BOUND-001: unbounded loop/recursion and illegal bounds fail closed via shipped
`Source.Program.validateLimits` and the `Compiler.compile` entry point. -/
def run : IO Unit := do
  let unbounded := viewProgram #[
    .unboundedLoop #[.returnValue (.literal 0)],
    .returnValue (.literal 1)
  ]
  expectBoundFailure (Program.validateLimits unbounded)
    "unbounded loop must fail validateLimits with PF-BOUND-001"
  expectBoundFailure (Compiler.compile unbounded)
    "unbounded loop must fail Compiler.compile with PF-BOUND-001"

  let zeroBound := viewProgram #[
    .loopBounded 0 #[.returnValue (.literal 0)],
    .returnValue (.literal 1)
  ]
  expectBoundFailure (Program.validateLimits zeroBound)
    "loop bound 0 must fail closed"
  expectBoundFailure (Compiler.compile zeroBound)
    "loop bound 0 must fail compile"

  let overBound := viewProgram #[
    .loopBounded 4097 #[.returnValue (.literal 0)],
    .returnValue (.literal 1)
  ]
  expectBoundFailure (Program.validateLimits overBound)
    "loop bound above 4096 must fail closed"
  expectBoundFailure (Compiler.compile overBound)
    "loop bound above 4096 must fail compile"

  let legal := viewProgram #[
    .loopBounded 1 #[.returnValue (.literal 0)],
    .returnValue (.literal 1)
  ]
  -- Legal bounds pass validateLimits; typed checker still rejects loop forms until
  -- full loop elaboration lands (fail closed at typing with PF-SRC-INVALID).
  match Program.validateLimits legal with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.render
  match Compiler.compile legal with
  | .error error =>
      expect (error.code == "PF-SRC-INVALID")
        s!"legal bounded loop must not report PF-BOUND-001 after limit check: {error.render}"
  | .ok _ => throw <| IO.userError "typed loop elaboration is not yet available"

end Tests.Compiler.Bound
