import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Emit

namespace Tests.Quint.CounterModel

open ProofForge.Backend.Quint

def counterModule : Module := {
  name := "CounterModel",
  constants := #[
    { name := "MAX_UINT", type := .int }
  ],
  vars := #[
    { name := "count", type := .int }
  ],
  actions := #[
    {
      name := "init",
      body := .all #[
        .assign (.prime (.local "count")) (.literalInt 0)
      ]
    },
    {
      name := "increment",
      body := .all #[
        .assign (.prime (.local "count")) (.binOp .add (.local "count") (.literalInt 1))
      ]
    },
    {
      name := "step",
      body := .any #[
        .call "increment" #[]
      ]
    }
  ],
  vals := #[
    { name := "countNonNegative", body := .binOp .ge (.local "count") (.literalInt 0) }
  ]
}

def expectedSubstrings : Array String := #[
  "module CounterModel {",
  "const MAX_UINT: int",
  "var count: int",
  "action init = all {",
  "count' = 0",
  "action increment = all {",
  "count' = count + 1",
  "action step = any {",
  "increment",
  "val countNonNegative = count >= 0",
  "}"
]

def checkSubstrings (s : String) (substrings : Array String) : Option String :=
  substrings.findSome? (fun sub =>
    if s.contains sub then none else some s!"missing substring: {sub}")

end Tests.Quint.CounterModel

def main : IO UInt32 := do
  let rendered := ProofForge.Backend.Quint.Emit.emitModule Tests.Quint.CounterModel.counterModule
  IO.println rendered
  match Tests.Quint.CounterModel.checkSubstrings rendered Tests.Quint.CounterModel.expectedSubstrings with
  | some err =>
      IO.eprintln s!"FAIL: {err}"
      return 1
  | none =>
      -- Also typecheck the generated model with `quint` if available.
      let tmpPath := "/tmp/quint-test-CounterModel.qnt"
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
