import ProofForge.IR.Examples.Counter
import ProofForge.Backend.Quint.Lower
import ProofForge.Backend.Quint.Scenario

namespace Tests.Quint.CounterLower

def expectedSubstrings : Array String := #[
  "module CounterModel {",
  "pure def MAX_UINT: int = 3",
  "pure def USERS: Set[str] = Set(\"alice\", \"bob\", \"charlie\")",
  "var count: int",
  "action init = all {",
  "count' = 0",
  "action initialize: bool = all {",
  "count' = 0",
  "action increment: bool = all {",
  "count' = count + 1",
  "action get_: bool = all {",
  "(count == count)",
  "count' = count",
  "action step = any {",
  "initialize",
  "increment",
  "get_",
  "val countNonNegative = count >= 0"
]

def checkSubstrings (s : String) (substrings : Array String) : Option String :=
  substrings.findSome? (fun sub =>
    if s.contains sub then none else some s!"missing substring: {sub}")

def main : IO UInt32 := do
  let scenario : ProofForge.Backend.Quint.Scenario.Config := {}
  match ProofForge.Backend.Quint.Lower.renderModule ProofForge.IR.Examples.Counter.module scenario with
  | .error err =>
      IO.eprintln s!"FAIL lower: {err.message}"
      return 1
  | .ok rendered =>
      IO.println rendered
      match checkSubstrings rendered expectedSubstrings with
      | some err =>
          IO.eprintln s!"FAIL: {err}"
          return 1
      | none =>
          let tmpPath := "/tmp/quint-test-CounterLower.qnt"
          IO.FS.writeFile tmpPath rendered
          let quintResult ← IO.Process.output {
            cmd := "quint",
            args := #["typecheck", tmpPath]
          }
          if quintResult.exitCode != 0 then
            IO.eprintln s!"quint typecheck failed:\n{quintResult.stderr}"
            return 1
          IO.println "PASS"
          return 0

end Tests.Quint.CounterLower

def main : IO UInt32 := Tests.Quint.CounterLower.main
