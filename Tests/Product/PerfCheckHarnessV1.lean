/-
  Tests.Product.PerfCheckHarnessV1 — PERF-1 harness pin (engineering).

  Pins that the PERF-1 generator/script contract exists as a product-adjacent
  measurement path: a multi-state public-UInt64 program still product-compiles
  and `check` stays a finite cold path. Does **not** claim NFR-007 p95 budgets,
  PerformanceProfileV1 host receipt, or incremental compilation.
-/
import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

namespace Tests.Product.PerfCheckHarnessV1

open ProofForgeV2.Compiler

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Engineering ~node-pressure fixture: many public states + multi-term add.
    Counts are well below formal 1000-syntax-node fixture; the Python harness
    scales states/terms for wall measurement. -/
private def perfSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program PerfThousand where\n" ++
  "  state s0 : UInt64\n" ++
  "  state s1 : UInt64\n" ++
  "  state s2 : UInt64\n" ++
  "  state s3 : UInt64\n" ++
  "  init(seed : UInt64) do\n" ++
  "    s0 := seed\n" ++
  "  entry run(p0 : UInt64, p1 : UInt64, p2 : UInt64, p3 : UInt64) : UInt64 do\n" ++
  "    return s0 + p0 + p1 + p2 + p3 + s0 + p0 + p1\n" ++
  "  view get() : UInt64 do\n" ++
  "    return s0\n\n" ++
  "end Examples\n"

private unsafe def testProductCompileFinite : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.selectProgramV1 perfSourceText
      "<perf-thousand>" "Examples.PerfThousand" none with
  | .error e =>
      throw <| IO.userError s!"PerfThousand select must succeed: {e.render}"
  | .ok source =>
      match compileValidatedSourceV1 source with
      | .error e =>
          throw <| IO.userError s!"PerfThousand product compile must succeed: {e.render}"
      | .ok _ => pure ()

/-- Script presence pin (path relative to package root). -/
private def testHarnessScriptPresent : IO Unit := do
  let path := System.FilePath.mk "scripts/perf_check_harness.py"
  unless ← path.pathExists do
    throw <| IO.userError "scripts/perf_check_harness.py must exist (PERF-1)"

unsafe def run : IO Unit := do
  testHarnessScriptPresent
  testProductCompileFinite
  IO.println "Tests.Product.PerfCheckHarnessV1: ok"

end Tests.Product.PerfCheckHarnessV1
