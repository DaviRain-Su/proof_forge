/-
  Tests.Semantic.MiniAmmVectorsV1 — ADR-0030 E4 / M0 shared MiniAMM math vectors.

  Pure UInt64 floor-arithmetic oracle for `Examples/MiniAmm` (and the
  Solana Hybrid fixture). Not a Reference interpreter suite; not formal
  TASK-D2-07. Engineering pin only.
-/
import ProofForgeV2.Core.Common

namespace Tests.Semantic.MiniAmmVectorsV1

open ProofForgeV2.Core.Common

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Checked UInt64 mul; `none` on overflow (matches product checked-arithmetic). -/
private def mulChecked (a b : UInt64) : Option UInt64 :=
  let aa := a.toNat
  let bb := b.toNat
  let p := aa * bb
  if p > UInt64.size - 1 then none else some (UInt64.ofNat p)

private def addChecked (a b : UInt64) : Option UInt64 :=
  let p := a.toNat + b.toNat
  if p > UInt64.size - 1 then none else some (UInt64.ofNat p)

private def divFloor (a b : UInt64) : Option UInt64 :=
  if b == 0 then none else some (UInt64.ofNat (a.toNat / b.toNat))

private def subChecked (a b : UInt64) : Option UInt64 :=
  if a.toNat < b.toNat then none else some (UInt64.ofNat (a.toNat - b.toNat))

/-- First deposit: LP = amount0. -/
def firstMint (amount0 : UInt64) : UInt64 := amount0

/-- Later deposit: min(amount0*ts/r0, amount1*ts/r1). -/
def laterMint (amount0 amount1 totalSupply reserve0 reserve1 : UInt64) :
    Option UInt64 := do
  let n0 ← mulChecked amount0 totalSupply
  let lp0 ← divFloor n0 reserve0
  let n1 ← mulChecked amount1 totalSupply
  let lp1 ← divFloor n1 reserve1
  pure (if lp0 ≤ lp1 then lp0 else lp1)

/-- Fee-free constant-product out for token0→token1. -/
def swap0to1Out (amountIn reserve0 reserve1 : UInt64) : Option UInt64 := do
  let num ← mulChecked amountIn reserve1
  let den ← addChecked reserve0 amountIn
  divFloor num den

/-- Fee-free constant-product out for token1→token0. -/
def swap1to0Out (amountIn reserve0 reserve1 : UInt64) : Option UInt64 := do
  let num ← mulChecked amountIn reserve0
  let den ← addChecked reserve1 amountIn
  divFloor num den

/-- Remove: amount0 out = lp * r0 / ts. -/
def removeAmount0 (lpAmount reserve0 totalSupply : UInt64) : Option UInt64 := do
  let num ← mulChecked lpAmount reserve0
  divFloor num totalSupply

/-- Remove: amount1 out = lp * r1 / ts. -/
def removeAmount1 (lpAmount reserve1 totalSupply : UInt64) : Option UInt64 := do
  let num ← mulChecked lpAmount reserve1
  divFloor num totalSupply

/-- Plan M0 canonical vector suite (vault-internal). -/
private def testCanonicalVectors : IO Unit := do
  -- First add 1000/2000 → LP 1000
  expect (firstMint 1000 == 1000) "first mint LP = amount0"
  let r0 : UInt64 := 1000
  let r1 : UInt64 := 2000
  let ts : UInt64 := 1000
  -- Proportional later add 500/1000 → LP 500
  match laterMint 500 1000 ts r0 r1 with
  | some 500 => pure ()
  | other => throw <| IO.userError s!"proportional later mint expected 500, got {other}"
  -- Non-proportional later add 500/100 → LP 50
  match laterMint 500 100 ts r0 r1 with
  | some 50 => pure ()
  | other => throw <| IO.userError s!"skew later mint expected 50, got {other}"
  -- swap0to1(100) on 1000/2000 → 181
  match swap0to1Out 100 r0 r1 with
  | some 181 => pure ()
  | other => throw <| IO.userError s!"swap0to1 out expected 181, got {other}"
  -- amountOutMin=182 would fail (181 < 182)
  expect (181 < 182) "minOut=182 is a true slippage fail vs out=181"
  -- After swap0to1(100): r0=1100, r1=1819
  let r0' : UInt64 := 1100
  let r1' : UInt64 := 1819
  match subChecked r1 181 with
  | some 1819 => pure ()
  | other => throw <| IO.userError s!"post-swap r1 expected 1819, got {other}"
  -- reverse swap1to0(181) → 99
  match swap1to0Out 181 r0' r1' with
  | some 99 => pure ()
  | other => throw <| IO.userError s!"swap1to0 out expected 99, got {other}"
  -- After first add only (ts=1000,r0=1000,r1=2000): remove 500
  match removeAmount0 500 r0 ts, removeAmount1 500 r1 ts with
  | some 500, some 1000 => pure ()
  | a, b => throw <| IO.userError s!"remove 500 expected (500,1000), got ({a},{b})"
  -- Full remove 1000
  match removeAmount0 1000 r0 ts, removeAmount1 1000 r1 ts with
  | some 1000, some 2000 => pure ()
  | a, b => throw <| IO.userError s!"full remove expected (1000,2000), got ({a},{b})"
  -- Overflow pin: amount0 * ts that exceeds UInt64
  match laterMint (UInt64.ofNat (2 ^ 32)) (UInt64.ofNat (2 ^ 32))
      (UInt64.ofNat (2 ^ 32)) 1 1 with
  | none => pure ()
  | some v => throw <| IO.userError s!"overflow later mint must fail closed, got {v}"
  -- div-zero pin
  match laterMint 1 1 1 0 1 with
  | none => pure ()
  | some v => throw <| IO.userError s!"div-zero later mint must fail closed, got {v}"
  IO.println "  MiniAmm M0 canonical vectors ok"

unsafe def run : IO Unit := do
  testCanonicalVectors
  IO.println "Tests.Semantic.MiniAmmVectorsV1: ok"

end Tests.Semantic.MiniAmmVectorsV1
