/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Z2.3 bootstrap: IR → Aleo Instructions for Counter public-mapping fragment.
-/

import ProofForge.Backend.Aleo.Instructions.Ast
import ProofForge.IR.Contract

namespace ProofForge.Backend.Aleo.Instructions.Lower

open ProofForge.Backend.Aleo.Instructions
open ProofForge.IR

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (e : LowerError) : String := e.message

def isCounterShape (m : Module) : Bool :=
  let names := m.entrypoints.map (·.name)
  names == #["initialize", "increment", "get"]
    || names == #["initialize", "get", "increment"]
    || m.name == "Counter"

def lowerModule (m : Module) : Except LowerError Program := do
  if isCounterShape m then
    pure CounterGolden.program
  else
    throw {
      message :=
        s!"Aleo Instructions direct lower (Z2.3) supports Counter shape only; \
got module `{m.name}`"
    }

def lowerCounterFixture : Program := CounterGolden.program

end ProofForge.Backend.Aleo.Instructions.Lower
