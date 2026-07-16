/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Portable fixed-point / decimals (gap-analysis route step 4)

Token amounts need decimals. This module is chain-neutral fixed-point math
over `Nat` with an explicit scale (10^decimals). Not EVM-only — no wei
assumptions. Used by TokenSpec `decimals` and amount scaling.
-/
import Init.Data.Nat.Basic

namespace ProofForge.Contract.FixedPoint

/-- Fixed-point scale: amounts are integers with `decimals` fractional digits. -/
structure Scale where
  decimals : Nat
  deriving BEq, DecidableEq, Repr

def Scale.id (s : Scale) : String := s!"fixedPoint.decimals={s.decimals}"

/-- 10^n for scale factor (Nat). -/
def pow10 : Nat → Nat
  | 0 => 1
  | n + 1 => 10 * pow10 n

def Scale.factor (s : Scale) : Nat := pow10 s.decimals

/-- Encode a whole-unit amount as fixed-point integer (`amount * 10^decimals`). -/
def Scale.fromWhole (s : Scale) (whole : Nat) : Nat :=
  whole * s.factor

/-- Truncating convert fixed-point amount back to whole units. -/
def Scale.toWhole (s : Scale) (amount : Nat) : Nat :=
  amount / s.factor

/-- Scale an amount from `fromScale` decimals to `toScale` decimals.

When scaling down, truncates. When scales equal, identity. -/
def rescale (amount : Nat) (fromScale toScale : Scale) : Nat :=
  if fromScale.decimals == toScale.decimals then
    amount
  else if fromScale.decimals < toScale.decimals then
    amount * pow10 (toScale.decimals - fromScale.decimals)
  else
    amount / pow10 (fromScale.decimals - toScale.decimals)

/-- Multiply two fixed-point amounts sharing the same scale; result keeps scale
(`(a * b) / 10^decimals`, truncating). -/
def mulScaled (s : Scale) (a b : Nat) : Nat :=
  (a * b) / s.factor

/-- Divide fixed-point `a / b` keeping scale (`(a * 10^decimals) / b`).
Returns `none` on division by zero. -/
def divScaled? (s : Scale) (a b : Nat) : Option Nat :=
  if b == 0 then none else some ((a * s.factor) / b)

/-- Common token scales. -/
def scale0 : Scale := { decimals := 0 }
def scale6 : Scale := { decimals := 6 }
def scale9 : Scale := { decimals := 9 }
def scale18 : Scale := { decimals := 18 }

/-- Validate TokenSpec-style decimals (0–18 inclusive; product convention). -/
def validateDecimals (decimals : Nat) : Except String Scale :=
  if decimals > 18 then
    .error s!"FixedPoint: decimals={decimals} exceeds max 18"
  else
    .ok { decimals := decimals }

end ProofForge.Contract.FixedPoint
