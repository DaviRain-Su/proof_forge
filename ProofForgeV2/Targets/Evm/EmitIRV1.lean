import ProofForgeV2.Targets.Evm.ValidatePlanV1
import ProofForgeV2.Targets.Evm.ValidateIRV1

/-!
# Evm EmitIRV1 — Plan → IR (Yul + ABI) emission

Target-owned Yul/ABI renderer and capability-internal `lower`/`emitFromIR`.
`lower` runs `validatePlan` then structural `validateEvmTargetIRV1` so invalid
IR never reaches emit/finalize (M4 engineering slice; not formal TargetIR).
-/

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

structure IR where
  objectName : String
  yul : String
  abi : String
  deriving BEq, Inhabited, Repr

/-- Yul mask for an admitted body UInt width (`2^w - 1` as hex literal). -/
private def yulUintMask (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "0xff"
  | 16 => "0xffff"
  | 32 => "0xffffffff"
  | 64 => "0xffffffffffffffff"
  | _ => "0xffffffffffffffff"

/-- Exact bn254 Fr modulus as a Yul hex literal (SPEC `bn254FrModulusBEV1`). -/
private def bn254FrModulusYulV1 : String :=
  "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"

/-- Exact `p - 2` exponent for Fermat inverse `b^(p-2) ≡ b⁻¹ (mod p)`.

    Cost profile (engineering note): each Field div expands to one zero-check
    plus a square-and-multiply loop over this 254-bit exponent. Worst case
    ≈ 254 `mulmod` squarings + ≈ 128 `mulmod` multiplies (plus one final
    `mulmod` for `a * inv`), deterministic and independent of the dividend.
    Prefer targets with native field ops (Noir) when circuit cost matters;
    EVM uses ADDMOD/MULMOD only. -/
private def bn254FrFermatExpYulV1 : String :=
  "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593efffffff"

/-- Nested Yul expression form (no intermediate lets). Used for for-loop
    condition/update slots that require expression positions. Storage loads
    and checked overflow guards are not nested here — callers pre-render
    loop-invariant subtrees with the statement form. -/
private partial def renderExprNested (paramPrefix : String) : Expr → String
  | .literal value => toString value
  | .param wordIndex => s!"{paramPrefix}{wordIndex}"
  | .narrowParam bitWidth wordIndex =>
      s!"and({paramPrefix}{wordIndex}, {yulUintMask bitWidth})"
  | .temp tempIndex => s!"t{tempIndex}"
  | .storageLoad slot => s!"sload({slot})"
  | .narrowStorageLoad bitWidth slot =>
      s!"and(sload({slot}), {yulUintMask bitWidth})"
  | .checkedAdd lhs rhs | .narrowCheckedAdd _ lhs rhs | .add lhs rhs =>
      s!"add({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedSub lhs rhs | .narrowCheckedSub _ lhs rhs =>
      s!"sub({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .compare op lhs rhs =>
      let l := renderExprNested paramPrefix lhs
      let r := renderExprNested paramPrefix rhs
      match op with
      | .eq => s!"eq({l}, {r})"
      | .ne => s!"iszero(eq({l}, {r}))"
      | .lt => s!"lt({l}, {r})"
      | .le => s!"iszero(gt({l}, {r}))"
      | .gt => s!"gt({l}, {r})"
      | .ge => s!"iszero(lt({l}, {r}))"
  | .checkedMul lhs rhs | .narrowCheckedMul _ lhs rhs =>
      s!"mul({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedDiv lhs rhs | .narrowCheckedDiv _ lhs rhs =>
      s!"div({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .checkedMod lhs rhs | .narrowCheckedMod _ lhs rhs =>
      s!"mod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitNot operand =>
      s!"and(not({renderExprNested paramPrefix operand}), 0xffffffffffffffff)"
  | .narrowBitNot bitWidth operand =>
      s!"and(not({renderExprNested paramPrefix operand}), {yulUintMask bitWidth})"
  | .boolNot operand => s!"iszero({renderExprNested paramPrefix operand})"
  | .bitAnd lhs rhs | .narrowBitAnd _ lhs rhs =>
      s!"and({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitOr lhs rhs | .narrowBitOr _ lhs rhs =>
      s!"or({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .bitXor lhs rhs | .narrowBitXor _ lhs rhs =>
      s!"xor({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .shl lhs rhs | .narrowShl _ lhs rhs =>
      s!"shl({renderExprNested paramPrefix rhs}, {renderExprNested paramPrefix lhs})"
  | .shr lhs rhs | .narrowShr _ lhs rhs =>
      s!"shr({renderExprNested paramPrefix rhs}, {renderExprNested paramPrefix lhs})"
  | .logicalAnd lhs rhs =>
      s!"and({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .logicalOr lhs rhs =>
      s!"or({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  -- Nested form for signed ops is only used in for-loop slots (not Int64);
  -- fall through to the modular op identity so the match is exhaustive.
  | .signedCheckedAdd lhs rhs =>
      s!"add({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .signedCheckedSub lhs rhs =>
      s!"sub({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .signedCheckedMul lhs rhs =>
      s!"mul({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .signedCheckedDiv lhs rhs =>
      s!"sdiv({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .signedCheckedMod lhs rhs =>
      s!"smod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .signedCompare op lhs rhs =>
      let l := renderExprNested paramPrefix lhs
      let r := renderExprNested paramPrefix rhs
      match op with
      | .eq => s!"eq({l}, {r})"
      | .ne => s!"iszero(eq({l}, {r}))"
      | .lt => s!"slt({l}, {r})"
      | .le => s!"iszero(sgt({l}, {r}))"
      | .gt => s!"sgt({l}, {r})"
      | .ge => s!"iszero(slt({l}, {r}))"
  | .checkedNeg operand =>
      s!"sub(0, {renderExprNested paramPrefix operand})"
  | .sar lhs rhs =>
      s!"sar({renderExprNested paramPrefix rhs}, {renderExprNested paramPrefix lhs})"
  | .fieldAdd lhs rhs =>
      s!"addmod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs}, {bn254FrModulusYulV1})"
  | .fieldSub lhs rhs =>
      -- (a + (p - (b mod p))) mod p = (a - b) mod p; the inner addmod(b,0,p)
      -- reduces b so sub(p, _) cannot wrap (EVM SUB is mod 2^256, and
      -- 2^256 mod bn254-p != 0, so sub(0, b) would be wrong).
      s!"addmod({renderExprNested paramPrefix lhs}, sub({bn254FrModulusYulV1}, addmod({renderExprNested paramPrefix rhs}, 0, {bn254FrModulusYulV1})), {bn254FrModulusYulV1})"
  | .fieldMul lhs rhs =>
      s!"mulmod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs}, {bn254FrModulusYulV1})"
  | .fieldDiv lhs rhs =>
      -- Unreachable for validated plans: nested slots (loop conds/updates,
      -- Bool conditions) are UInt-typed, so a Field-typed .fieldDiv cannot
      -- appear here; statement form emits the Fermat inverse. Emit a marker
      -- that validateIR rejects, so this can never silently become a multiply.
      s!"pf_unsupported_nested_field_div()"
  | .fieldNeg operand =>
      -- (0 + (p - (a mod p))) mod p = (-a) mod p; see fieldSub for the
      -- sub-wrapping rationale.
      s!"addmod(0, sub({bn254FrModulusYulV1}, addmod({renderExprNested paramPrefix operand}, 0, {bn254FrModulusYulV1})), {bn254FrModulusYulV1})"
  | .fieldStorageLoad slot => s!"sload({slot})"
  -- Nested form for Array index ops is only used in for-loop slots; statement
  -- form carries the bounds guards. Emit the core addressing so nested use
  -- remains deterministic (bounds are enforced when the expr is top-level).
  | .indexedStorageLoad baseSlot _length index byteWidth =>
      let slot := s!"add({baseSlot}, {renderExprNested paramPrefix index})"
      if byteWidth == 8 then s!"sload({slot})"
      else s!"and(sload({slot}), {yulUintMask (bitWidthOfByteWidth byteWidth)})"
  | .arrayIndexGet index leaves =>
      -- Nested fallback: fold mul/eq select without bounds (top-level form
      -- enforces bounds). Deterministic left-fold over leaves.
      Id.run do
        let idx := renderExprNested paramPrefix index
        let mut acc := "0"
        for i in [0:leaves.size] do
          match leaves[i]? with
          | some leaf =>
              let l := renderExprNested paramPrefix leaf
              acc := s!"add(mul(eq({idx}, {i}), {l}), mul(iszero(eq({idx}, {i})), {acc}))"
          | none => pure ()
        acc
  | .boundsCheckedIndex index _length =>
      renderExprNested paramPrefix index
  | .callFn fnIndex args =>
      let argsJoined := String.intercalate ", "
        (args.toList.map (renderExprNested paramPrefix))
      s!"pf_fn{fnIndex}({argsJoined})"

private structure RenderedExpr where
  code : String
  value : String
  next : Nat
  deriving Inhabited

private partial def renderExpr (indent paramPrefix : String) (next : Nat) : Expr → RenderedExpr
  | .literal value =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {value}\n", value := name, next := next + 1 }
  | .param wordIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {paramPrefix}{wordIndex}\n", value := name, next := next + 1 }
  | .narrowParam bitWidth wordIndex =>
      let name := s!"expr{next}"
      let mask := yulUintMask bitWidth
      { code := s!"{indent}let {name} := and({paramPrefix}{wordIndex}, {mask})\n",
        value := name, next := next + 1 }
  | .temp tempIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := t{tempIndex}\n", value := name, next := next + 1 }
  | .storageLoad slot =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := sload({slot})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .narrowStorageLoad bitWidth slot =>
      let name := s!"expr{next}"
      let mask := yulUintMask bitWidth
      { code := s!"{indent}let {name} := and(sload({slot}), {mask})\n",
        value := name, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if gt({lhs.value}, sub(0xffffffffffffffff, {rhs.value})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedAdd bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if gt({lhs.value}, sub({mask}, {rhs.value})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .add lhs rhs =>
      -- Unchecked add: only for bounded-for induction `i + 1` (cannot overflow).
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if lt({lhs.value}, {rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := sub({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedSub _bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if lt({lhs.value}, {rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := sub({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .compare op lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let yul := match op with
        | .eq => s!"eq({lhs.value}, {rhs.value})"
        | .ne => s!"iszero(eq({lhs.value}, {rhs.value}))"
        | .lt => s!"lt({lhs.value}, {rhs.value})"
        | .le => s!"iszero(gt({lhs.value}, {rhs.value}))"
        | .gt => s!"gt({lhs.value}, {rhs.value})"
        | .ge => s!"iszero(lt({lhs.value}, {rhs.value}))"
      { code := lhs.code ++ rhs.code ++ s!"{indent}let {name} := {yul}\n",
        value := name, next := rhs.next + 1 }
  | .checkedMul lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := mul({lhs.value}, {rhs.value})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedMul bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := mul({lhs.value}, {rhs.value})\n" ++
          s!"{indent}if gt({name}, {mask}) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .checkedDiv lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := div({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedDiv _bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := div({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .checkedMod lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := mod({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedMod _bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := mod({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .bitNot operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      { code := operand.code ++
          s!"{indent}let {name} := and(not({operand.value}), 0xffffffffffffffff)\n",
        value := name, next := operand.next + 1 }
  | .narrowBitNot bitWidth operand =>
      let mask := yulUintMask bitWidth
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      { code := operand.code ++
          s!"{indent}let {name} := and(not({operand.value}), {mask})\n",
        value := name, next := operand.next + 1 }
  | .boolNot operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      { code := operand.code ++
          s!"{indent}let {name} := iszero({operand.value})\n",
        value := name, next := operand.next + 1 }
  | .bitAnd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowBitAnd bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and(and({lhs.value}, {rhs.value}), {mask})\n",
        value := name, next := rhs.next + 1 }
  | .bitOr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := or({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowBitOr bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and(or({lhs.value}, {rhs.value}), {mask})\n",
        value := name, next := rhs.next + 1 }
  | .bitXor lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := xor({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowBitXor bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and(xor({lhs.value}, {rhs.value}), {mask})\n",
        value := name, next := rhs.next + 1 }
  | .shl lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, 64)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shl({rhs.value}, {lhs.value})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .narrowShl bitWidth lhs rhs =>
      let mask := yulUintMask bitWidth
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, {bitWidth})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shl({rhs.value}, {lhs.value})\n" ++
          s!"{indent}if gt({name}, {mask}) \{ revert(0, 0) }\n",
        value := name, next := rhs.next + 1 }
  | .shr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, 64)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shr({rhs.value}, {lhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .narrowShr bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, {bitWidth})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := shr({rhs.value}, {lhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .logicalAnd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := and({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .logicalOr lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := or({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .signedCheckedAdd lhs rhs =>
      -- Sign-extend i64 operands, add in i256, range-check int64 bounds, mask.
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {r} := add({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, 0xffffffffffffffff8000000000000000), sgt({r}, 0x7fffffffffffffff)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .signedCheckedSub lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {r} := sub({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, 0xffffffffffffffff8000000000000000), sgt({r}, 0x7fffffffffffffff)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .signedCheckedMul lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {r} := mul({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, 0xffffffffffffffff8000000000000000), sgt({r}, 0x7fffffffffffffff)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .signedCheckedDiv lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      -- intMin = 0x8000…0000; -1 as i256 = all-ones.
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}if iszero({b}) \{ revert(0, 0) }\n" ++
          s!"{indent}if and(eq({a}, 0xffffffffffffffff8000000000000000), eq({b}, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := sdiv({a}, {b})\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .signedCheckedMod lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}if iszero({b}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := smod({a}, {b})\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .signedCompare op lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let yul := match op with
        | .eq => s!"eq({a}, {b})"
        | .ne => s!"iszero(eq({a}, {b}))"
        | .lt => s!"slt({a}, {b})"
        | .le => s!"iszero(sgt({a}, {b}))"
        | .gt => s!"sgt({a}, {b})"
        | .ge => s!"iszero(slt({a}, {b}))"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {b} := signextend(7, and({rhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {name} := {yul}\n",
        value := name, next := rhs.next + 1 }
  | .checkedNeg operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      let a := s!"a{operand.next}"
      let r := s!"r{operand.next}"
      { code := operand.code ++
          s!"{indent}let {a} := signextend(7, and({operand.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}if eq({a}, 0xffffffffffffffff8000000000000000) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := sub(0, {a})\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := operand.next + 1 }
  | .sar lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let r := s!"r{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, 64)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {a} := signextend(7, and({lhs.value}, 0xffffffffffffffff))\n" ++
          s!"{indent}let {r} := sar({rhs.value}, {a})\n" ++
          s!"{indent}let {name} := and({r}, 0xffffffffffffffff)\n",
        value := name, next := rhs.next + 1 }
  | .fieldAdd lhs rhs =>
      let p := bn254FrModulusYulV1
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := addmod({lhs.value}, {rhs.value}, {p})\n",
        value := name, next := rhs.next + 1 }
  | .fieldSub lhs rhs =>
      -- (a + (p - (b mod p))) mod p = (a - b) mod p. The inner addmod(b,0,p)
      -- reduces b so sub(p, _) cannot wrap: EVM SUB is mod 2^256 and
      -- 2^256 mod bn254-p != 0, so sub(0, b) would NOT equal p - b.
      let p := bn254FrModulusYulV1
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := addmod({lhs.value}, sub({p}, addmod({rhs.value}, 0, {p})), {p})\n",
        value := name, next := rhs.next + 1 }
  | .fieldMul lhs rhs =>
      let p := bn254FrModulusYulV1
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {name} := mulmod({lhs.value}, {rhs.value}, {p})\n",
        value := name, next := rhs.next + 1 }
  | .fieldDiv lhs rhs =>
      -- mulmod(a, inv(b), p) with inv = b^(p-2) via square-and-multiply.
      -- Zero divisor reverts (Reference divisionByZero). Cost: ~254 squarings
      -- + ~128 multiplies of mulmod (see bn254FrFermatExpYulV1 note).
      let p := bn254FrModulusYulV1
      let expLit := bn254FrFermatExpYulV1
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let inv := s!"inv{rhs.next}"
      let base := s!"base{rhs.next}"
      let exp := s!"exp{rhs.next}"
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero({rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {inv} := 1\n" ++
          s!"{indent}let {base} := {rhs.value}\n" ++
          s!"{indent}for \{ let {exp} := {expLit} } {exp} \{\n" ++
          s!"{indent}  {exp} := shr(1, {exp})\n" ++
          s!"{indent}  {base} := mulmod({base}, {base}, {p})\n" ++
          s!"{indent}} \{\n" ++
          s!"{indent}  if and({exp}, 1) \{ {inv} := mulmod({inv}, {base}, {p}) }\n" ++
          s!"{indent}}\n" ++
          s!"{indent}let {name} := mulmod({lhs.value}, {inv}, {p})\n",
        value := name, next := rhs.next + 1 }
  | .fieldNeg operand =>
      -- (0 + (p - (a mod p))) mod p = (-a) mod p; see fieldSub for the
      -- sub-wrapping rationale (EVM SUB is mod 2^256, not mod p).
      let p := bn254FrModulusYulV1
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      { code := operand.code ++
          s!"{indent}let {name} := addmod(0, sub({p}, addmod({operand.value}, 0, {p})), {p})\n",
        value := name, next := operand.next + 1 }
  | .fieldStorageLoad slot =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := sload({slot})\n",
        value := name, next := next + 1 }
  | .indexedStorageLoad baseSlot length index byteWidth =>
      -- Exact Yul pins: bounds guard + sload(add(base,idx)) (+ narrow mask).
      let index := renderExpr indent paramPrefix next index
      let name := s!"expr{index.next}"
      let slotTmp := s!"slot{index.next}"
      let maskCode :=
        if byteWidth == 8 then
          s!"{indent}let {name} := sload({slotTmp})\n" ++
            s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
        else
          let mask := yulUintMask (bitWidthOfByteWidth byteWidth)
          s!"{indent}let {name} := and(sload({slotTmp}), {mask})\n"
      { code := index.code ++
          s!"{indent}if iszero(lt({index.value}, {length})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {slotTmp} := add({baseSlot}, {index.value})\n" ++
          maskCode,
        value := name, next := index.next + 1 }
  | .arrayIndexGet index leaves => Id.run do
      let index := renderExpr indent paramPrefix next index
      let mut code := index.code ++
        s!"{indent}if iszero(lt({index.value}, {leaves.size})) \{ revert(0, 0) }\n"
      let mut next := index.next
      let mut leafNames : Array String := #[]
      for leaf in leaves do
        let rendered := renderExpr indent paramPrefix next leaf
        code := code ++ rendered.code
        next := rendered.next
        leafNames := leafNames.push rendered.value
      -- Left-fold arithmetic select: sum_i mul(eq(idx,i), leaf_i)
      let acc0 := s!"expr{next}"
      code := code ++ s!"{indent}let {acc0} := 0\n"
      next := next + 1
      let mut acc := acc0
      for i in [0:leafNames.size] do
        match leafNames[i]? with
        | some ln =>
            let nextAcc := s!"expr{next}"
            code := code ++
              s!"{indent}let {nextAcc} := add(mul(eq({index.value}, {i}), {ln}), {acc})\n"
            acc := nextAcc
            next := next + 1
        | none => pure ()
      { code := code, value := acc, next }
  | .boundsCheckedIndex index length =>
      let index := renderExpr indent paramPrefix next index
      let name := s!"expr{index.next}"
      { code := index.code ++
          s!"{indent}if iszero(lt({index.value}, {length})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := {index.value}\n",
        value := name, next := index.next + 1 }
  | .callFn fnIndex args => Id.run do
      let mut code := ""
      let mut next := next
      let mut argValues : Array String := #[]
      for arg in args do
        let rendered := renderExpr indent paramPrefix next arg
        code := code ++ rendered.code
        next := rendered.next
        argValues := argValues.push rendered.value
      let name := s!"expr{next}"
      let argsJoined := String.intercalate ", " argValues.toList
      { code := code ++ s!"{indent}let {name} := pf_fn{fnIndex}({argsJoined})\n",
        value := name, next := next + 1 }

/-- Mask a stored word to `byteWidth` low bytes before `sstore` (narrow ABI).
    UInt64/Int64 (`byteWidth == 8`) and Field (`byteWidth == 32`) store the
    full word unmasked; narrow UInt{8,16,32} mask to the admitted width. -/
private def renderMaskedSstore (indent : String) (slot : Nat) (value : String)
    (byteWidth : Nat) : String :=
  if byteWidth == 8 || byteWidth == 32 then
    s!"{indent}sstore({slot}, {value})\n"
  else
    let mask := yulUintMask (byteWidth * 8)
    s!"{indent}sstore({slot}, and({value}, {mask}))\n"

private def renderStores (indent paramPrefix : String) (stores : Array Store) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for store in stores do
    let rendered := renderExpr indent paramPrefix next store.value
    output := output ++ rendered.code ++
      renderMaskedSstore indent store.slot rendered.value store.byteWidth
    next := rendered.next
  return output

private structure RenderedBody where
  code : String
  next : Nat
  deriving Inhabited

/-- Render a statement list. `returnVar = none` is the contract path
    (`mstore` + `return`); `some r` is a Yul function path that assigns `r`. -/
private structure PeeledForCondV1 where
  code : String
  cond : String
  next : Nat
  deriving Inhabited

/-- Peel `compare op (.temp varTemp) endExpr` so the end bound is evaluated once
    (with overflow guards) before the Yul for; otherwise nest the full cond. -/
private def peelForCondV1 (indent paramPrefix : String) (next varTemp : Nat)
    (cond : Expr) : PeeledForCondV1 :=
  match cond with
  | .compare op (.temp t) endExpr =>
      if t == varTemp then
        let endR := renderExpr indent paramPrefix next endExpr
        let yul := match op with
          | .eq => s!"eq(t{varTemp}, {endR.value})"
          | .ne => s!"iszero(eq(t{varTemp}, {endR.value}))"
          | .lt => s!"lt(t{varTemp}, {endR.value})"
          | .le => s!"iszero(gt(t{varTemp}, {endR.value}))"
          | .gt => s!"gt(t{varTemp}, {endR.value})"
          | .ge => s!"iszero(lt(t{varTemp}, {endR.value}))"
        { code := endR.code, cond := yul, next := endR.next }
      else
        { code := "", cond := renderExprNested paramPrefix cond, next }
  | _ =>
      { code := "", cond := renderExprNested paramPrefix cond, next }

private partial def renderBody (indent paramPrefix : String) (next : Nat)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (returnVar : Option String)
    (body : Array Statement) : RenderedBody := Id.run do
  let mut output := ""
  let mut next := next
  for statement in body do
    match statement with
    | .store store =>
        let rendered := renderExpr indent paramPrefix next store.value
        output := output ++ rendered.code ++
          renderMaskedSstore indent store.slot rendered.value store.byteWidth
        next := rendered.next
    | .assert condition =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code ++
          s!"{indent}if iszero({rendered.value}) \{ revert(0, 0) }\n"
        next := rendered.next
    | .returnValue value =>
        let rendered := renderExpr indent paramPrefix next value
        match returnVar with
        | none =>
            output := output ++ rendered.code ++
              s!"{indent}mstore(0, {rendered.value})\n{indent}return(0, 32)\n"
        | some r =>
            output := output ++ rendered.code ++
              s!"{indent}{r} := {rendered.value}\n"
        next := rendered.next
    | .returnNone =>
        -- Valid only as the constructor body's final statement (validated);
        -- falling off the body reaches the deployment epilogue on this path.
        pure ()
    | .emitEvent eventIndex args =>
        let binding := events[eventIndex]!
        let signature := Keccak.signature binding.name
          (Array.replicate binding.fieldCount "uint64")
        let topic0 := Keccak.keccak256Hex signature.toUTF8
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}log1(0, {32 * args.size}, 0x{topic0})\n"
    | .revertError errorIndex args =>
        let binding := errors[errorIndex]!
        let selector := Keccak.selector binding.name
          (Array.replicate binding.fieldCount "uint64")
        let padded := selector ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        output := output ++ s!"{indent}revert(0, {4 + 32 * args.size})\n"
    | .ifThenElse condition thenBody elseBody =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code
        let thenRendered := renderBody (indent ++ "  ") paramPrefix rendered.next
          events errors returnVar thenBody
        output := output ++ s!"{indent}if {rendered.value} \{\n" ++
          thenRendered.code ++ s!"{indent}}\n"
        next := thenRendered.next
        if !elseBody.isEmpty then
          let elseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar elseBody
          output := output ++ s!"{indent}if iszero({rendered.value}) \{\n" ++
            elseRendered.code ++ s!"{indent}}\n"
          next := elseRendered.next
    | .switchOn scrutinee cases defaultBody =>
        let rendered := renderExpr indent paramPrefix next scrutinee
        let scrutName := s!"expr{rendered.next}"
        output := output ++ rendered.code ++
          s!"{indent}let {scrutName} := {rendered.value}\n"
        next := rendered.next + 1
        let mut guard : String := ""
        for (caseValue, caseBody) in cases do
          let caseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar caseBody
          output := output ++
            s!"{indent}if eq({scrutName}, {caseValue}) \{\n" ++
            caseRendered.code ++ s!"{indent}}\n"
          next := caseRendered.next
          let eqExpr := s!"eq({scrutName}, {caseValue})"
          guard := if guard.isEmpty then eqExpr else s!"or({guard}, {eqExpr})"
        if !defaultBody.isEmpty then
          let defaultRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar defaultBody
          output := output ++ s!"{indent}if iszero({guard}) \{\n" ++
            defaultRendered.code ++ s!"{indent}}\n"
          next := defaultRendered.next
    | .forLoop varTemp counterTemp maxIterations initial cond update body =>
        -- Init and loop-invariant end bound are rendered once before the for.
        -- Condition uses nested expression form. Induction `i + 1` is unchecked
        -- (see Expr.add): body only runs while i < end ≤ UInt64.max.
        -- Back-edge post (after body, before next cond): bound check then
        -- counter++ then update — the (N+1)-th body runs, then reverts.
        let initR := renderExpr indent paramPrefix next initial
        output := output ++ initR.code
        next := initR.next
        let peeled := peelForCondV1 indent paramPrefix next varTemp cond
        output := output ++ peeled.code
        next := peeled.next
        let updateNested := renderExprNested paramPrefix update
        let bodyR := renderBody (indent ++ "  ") paramPrefix next
          events errors returnVar body
        let postIndent := indent ++ "  "
        let bound := toString maxIterations.toNat
        let tV := "t" ++ toString varTemp
        let tC := "t" ++ toString counterTemp
        output := output ++
          indent ++ "for { let " ++ tV ++ " := " ++ initR.value ++
          " let " ++ tC ++ " := 0 } " ++ peeled.cond ++ " {\n" ++
          postIndent ++ "if eq(" ++ tC ++ ", " ++ bound ++ ") { revert(0, 0) }\n" ++
          postIndent ++ tC ++ " := add(" ++ tC ++ ", 1)\n" ++
          postIndent ++ tV ++ " := " ++ updateNested ++ "\n" ++
          indent ++ "} {\n" ++
          bodyR.code ++
          indent ++ "}\n"
        next := bodyR.next
  return { code := output, next }

/-- Emit `function pf_fn{i}(...) -> r { ... }` definitions. Duplicated into both
    Yul objects because each object is self-contained. -/
private def renderFnDefs (indent : String) (plan : Plan) : String := Id.run do
  if plan.fns.isEmpty then
    return ""
  let mut output := ""
  for index in [0:plan.fns.size] do
    let fn := plan.fns[index]!
    let mut paramList := ""
    for i in [0:fn.params.size] do
      if i > 0 then paramList := paramList ++ ", "
      paramList := paramList ++ s!"arg{i}"
    let body := renderBody (indent ++ "  ") "arg" 0 plan.events plan.errors (some "r") fn.body
    output := output ++
      s!"{indent}function pf_fn{index}({paramList}) -> r \{\n" ++
      body.code ++
      s!"{indent}}\n"
  return output

private def renderConstructor (plan : Plan) : String := Id.run do
  let constructor := plan.constructor.getD { params := #[], stores := #[] }
  let argumentBytes := constructor.params.size * 32
  let mut output :=
    s!"    if callvalue() \{ revert(0, 0) }\n" ++
    s!"    let programSize := datasize(\"{plan.objectName}\")\n" ++
    s!"    if iszero(eq(codesize(), add(programSize, {argumentBytes}))) \{ revert(0, 0) }\n"
  if argumentBytes > 0 then
    output := output ++ s!"    codecopy(0, programSize, {argumentBytes})\n"
  for param in constructor.params do
    let raw := s!"mload({param.wordIndex * 32})"
    if param.byteWidth == 32 then
      -- Field: full 32-byte ABI word (no UInt64 range gate).
      output := output ++
        s!"    let ctor_arg{param.wordIndex} := {raw}\n"
    else if param.byteWidth == 8 then
      output := output ++
        s!"    let ctor_arg{param.wordIndex} := {raw}\n" ++
        s!"    if gt(ctor_arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
    else
      let mask := yulUintMask (param.byteWidth * 8)
      output := output ++
        s!"    let ctor_arg{param.wordIndex} := and({raw}, {mask})\n"
  -- Store-only constructors keep body empty for byte-identical Yul via stores.
  output := output ++
    (if constructor.body.isEmpty then
      renderStores "    " "ctor_arg" constructor.stores
    else
      (renderBody "    " "ctor_arg" 0 plan.events plan.errors none constructor.body).code)
  return output ++
    s!"    datacopy(0, dataoffset(\"{plan.runtimeObjectName}\"), datasize(\"{plan.runtimeObjectName}\"))\n" ++
    s!"    return(0, datasize(\"{plan.runtimeObjectName}\"))\n"

private def renderEntry (plan : Plan) (entry : Entry) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  for param in entry.params do
    let offset := 4 + param.wordIndex * 32
    let raw := s!"calldataload({offset})"
    if param.byteWidth == 32 then
      -- Field: full 32-byte ABI word (no UInt64 range gate).
      output := output ++
        s!"        let arg{param.wordIndex} := {raw}\n"
    else if param.byteWidth == 8 then
      output := output ++
        s!"        let arg{param.wordIndex} := {raw}\n" ++
        s!"        if gt(arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
    else
      let mask := yulUintMask (param.byteWidth * 8)
      output := output ++
        s!"        let arg{param.wordIndex} := and({raw}, {mask})\n"
  output := output ++
    (renderBody "        " "arg" 0 plan.events plan.errors none entry.body).code
  return output ++ "      }\n"

private def renderYul (plan : Plan) : String :=
  let entries := plan.entries.foldl (fun output entry => output ++ renderEntry plan entry) ""
  let ctorFns := renderFnDefs "    " plan
  let runtimeFns := renderFnDefs "      " plan
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    ctorFns ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    runtimeFns ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  let ty := abiParamTypeString param
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{ty}\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def resultKindAbiType (kind : ResultKind) : String :=
  match kind with
  | .uint64 => "uint64"
  | .bool => "bool"
  | .int64 => "int64"
  | .field => "uint256"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
  let resultType := resultKindAbiType entry.resultKind
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[{\"name\":\"\",\"type\":\"" ++ resultType ++ "\"}]}"

private def renderInterfaceBindingAbi (kind : String) (binding : InterfaceBinding) : String :=
  let inputs := (List.range binding.fieldCount).map fun index =>
    "{\"name\":\"arg" ++ toString index ++ "\",\"type\":\"uint64\"}"
  "{\"type\":\"" ++ kind ++ "\",\"name\":\"" ++ Targets.escapeJson binding.name ++
    "\",\"inputs\":[" ++ String.intercalate "," inputs ++ "]}"

private def renderAbi (plan : Plan) : String :=
  let constructor := plan.constructor.map (fun value => #[renderConstructorAbi value]) |>.getD #[]
  let entries := plan.entries.map renderEntryAbi
  let events := plan.events.map (renderInterfaceBindingAbi "event")
  let errors := plan.errors.map (renderInterfaceBindingAbi "error")
  let items := constructor ++ entries ++ events ++ errors
  "[\n  " ++ String.intercalate ",\n  " items.toList ++ "\n]\n"

/-- Public IR structural gate (Yul+ABI text). Thin wrapper over
    `validateEvmTargetIRV1` for the typed `IR` carrier. -/
def validateIR (ir : IR) : CompileResult Unit :=
  validateEvmTargetIRV1 ir.objectName ir.yul ir.abi

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let ir : IR := {
    objectName := plan.objectName
    yul := renderYul plan
    abi := renderAbi plan
  }
  validateIR ir
  return ir

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    { path := s!"{ir.objectName}.yul", mediaType := "text/yul", contents := ir.yul },
    { path := s!"{ir.objectName}.abi.json", mediaType := "application/json", contents := ir.abi }
  ]


/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. Chain: materialize → validatePlan → render →
    validateIR. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  lower plan

/-- Capability-gated public materialize entry. Sole path from the retained
    SemanticProgramV1-native EVM Plan body to emitted files for this target.
    Chain: irFromCapability (includes validateIR) → emitFromIR (re-checks IR). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

end ProofForgeV2.Targets.Evm
