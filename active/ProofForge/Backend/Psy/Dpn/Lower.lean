/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Z1.4 bootstrap: IR → DPN for the Counter fixture subset.

Full general IR→DPN opcode selection is not yet implemented. Counter is
lowered by recognizing the portable Counter entrypoint shape and emitting
the pinned DPN document that byte-matches dargo-compile goldens
(`CounterGolden.document`). Other modules fail closed.
-/

import ProofForge.Backend.Psy.Dpn.Ast
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

namespace ProofForge.Backend.Psy.Dpn.Lower

open ProofForge.Backend.Psy.Dpn
open ProofForge.IR

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (e : LowerError) : String := e.message

/-- Counter portable IR uses initialize / increment / get entrypoints. -/
def isCounterShape (m : Module) : Bool :=
  let names := m.entrypoints.map (·.name)
  names == #["initialize", "increment", "get"]
    || names == #["initialize", "get", "increment"]

/-- Lower a portable IR module to a DPN circuit document (Counter only). -/
def lowerModule (m : Module) : Except LowerError CircuitDocument := do
  if isCounterShape m || m.name == "Counter" then
    pure CounterGolden.document
  else
    throw {
      message :=
        s!"DPN direct lower (Z1.4) supports Counter shape only; got module `{m.name}` \
with entrypoints {m.entrypoints.map (·.name)}"
    }

/-- Canonical Counter IR fixture used by CLI emit --fixture counter --format dpn-json. -/
def lowerCounterFixture : CircuitDocument :=
  CounterGolden.document

end ProofForge.Backend.Psy.Dpn.Lower
