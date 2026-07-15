/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana asm immediate rendering (sbpf-compatible)

Large hash4 limb constants must not print as unsigned decimals ≥ 2^63.
-/
import ProofForge.Backend.Solana.Asm

namespace ProofForge.Tests.Backend.Solana.AsmImm

open ProofForge.Backend.Solana.Asm

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO UInt32 := do
  require (numStr 0 == "0") "zero"
  require (numStr 42 == "42") "small decimal"
  require (numStr 9223372036854775807 == "9223372036854775807") "i64 max stays decimal"
  -- limb0-style constant that previously broke `sbpf build` as decimal mov64 imm
  let big : Nat := 11400714785074694791
  let s := numStr big
  require (s.startsWith "0x") s!"expected hex for ≥2^63, got {s}"
  require (s == "0x9e3779b185ebca87") s!"hex mismatch got {s}"
  require (Imm.render (.num big) == s) "Imm.render"
  IO.println "solana-asm-imm: ok"
  pure 0

end ProofForge.Tests.Backend.Solana.AsmImm

def main : IO UInt32 :=
  ProofForge.Tests.Backend.Solana.AsmImm.main
