import ProofForge.Backend.Quint.Scenario

namespace Tests.Quint.Scenario

open ProofForge.Backend.Quint.Scenario

def sampleToml : String := String.intercalate "\n" [
  "# Counter scenario: small integer domain for fast model checking.",
  "max_uint = 3",
  "users = [\"alice\", \"bob\"]",
  "max_steps = 5",
  "n_traces = 20",
  "",
  "[invariants]",
  "counterNonNegative = \"counter >= 0\"",
  "counterBounded = \"counter <= MAX_UINT\""
]

def main : IO UInt32 := do
  match parse sampleToml with
  | .error err =>
      IO.eprintln s!"FAIL parse: {err}"
      return 1
  | .ok cfg =>
      if cfg.maxUint != 3 then
        IO.eprintln s!"FAIL maxUint expected 3, got {cfg.maxUint}"
        return 1
      if cfg.users != #["alice", "bob"] then
        IO.eprintln s!"FAIL users mismatch: {cfg.users}"
        return 1
      if cfg.maxSteps != 5 then
        IO.eprintln s!"FAIL maxSteps expected 5, got {cfg.maxSteps}"
        return 1
      if cfg.nTraces != 20 then
        IO.eprintln s!"FAIL nTraces expected 20, got {cfg.nTraces}"
        return 1
      if cfg.invariants.size != 2 then
        IO.eprintln s!"FAIL invariants size expected 2, got {cfg.invariants.size}"
        return 1
      let invNames := cfg.invariants.map Prod.fst
      if invNames != #["counterNonNegative", "counterBounded"] then
        IO.eprintln s!"FAIL invariant names mismatch: {invNames}"
        return 1
      let pureDefs := cfg.quintPureDefs
      if pureDefs.size != 2 then
        IO.eprintln s!"FAIL expected 2 pure defs, got {pureDefs.size}"
        return 1
      IO.println s!"{repr cfg}"
      IO.println "PASS"
      return 0

end Tests.Quint.Scenario

def main : IO UInt32 := Tests.Quint.Scenario.main