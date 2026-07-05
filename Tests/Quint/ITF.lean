import ProofForge.Backend.Quint.ITF

namespace Tests.Quint.ITF

open ProofForge.Backend.Quint.ITF

def sampleTrace : String := "{\"#meta\":{\"format\":\"ITF\",\"format-description\":\"https://apalache-mc.org/docs/adr/015adr-trace.html\",\"source\":\"Counter.qnt\",\"status\":\"ok\"},\"vars\":[\"count\",\"mbt::actionTaken\",\"mbt::nondetPicks\"],\"states\":[{\"#meta\":{\"index\":0},\"count\":{\"#bigint\":\"0\"},\"mbt::actionTaken\":\"init\",\"mbt::nondetPicks\":{}},{\"#meta\":{\"index\":1},\"count\":{\"#bigint\":\"1\"},\"mbt::actionTaken\":\"increment\",\"mbt::nondetPicks\":{}}]}"

def main : IO UInt32 := do
  match parse sampleTrace with
  | .error err =>
      IO.eprintln s!"FAIL parse: {err}"
      return 1
  | .ok trace =>
      if trace.states.length != 2 then
        IO.eprintln s!"FAIL expected 2 states, got {trace.states.length}"
        return 1
      let s0 := trace.states[0]!
      if s0.index != 0 then
        IO.eprintln s!"FAIL state 0 index expected 0, got {s0.index}"
        return 1
      if s0.actionTaken != some "init" then
        IO.eprintln s!"FAIL state 0 action expected init, got {s0.actionTaken}"
        return 1
      let s1 := trace.states[1]!
      if s1.actionTaken != some "increment" then
        IO.eprintln s!"FAIL state 1 action expected increment, got {s1.actionTaken}"
        return 1
      IO.println s!"{repr trace}"
      IO.println "PASS"
      return 0

end Tests.Quint.ITF

def main : IO UInt32 := Tests.Quint.ITF.main
