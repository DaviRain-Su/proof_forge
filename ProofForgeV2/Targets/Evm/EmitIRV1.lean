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
  | 128 => "0xffffffffffffffffffffffffffffffff"
  | 256 => "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
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

/-- ADR-0031 S1 / ADR-0025: nested Yul for one LE body word of
    `context.caller` Principal (`u32le(20)||addr20`).

    EVM `caller()` returns a right-aligned 20-byte address in a 32-byte word
    (byte indices 12..31 = network-order address bytes 0..19). Body words pack
    those bytes little-endian into 8×UInt64 (words 3..7 = 0; word 2 high 32
    bits = 0). Matches `principal_words_from_addr` / T10 leaf layout.

    Yul `byte` argument order is EVM-native `byte(i, x)` (index first) — the
    locked solc 0.8.34 builtin matches the BYTE opcode stack order, not the
    older docs spelling `byte(x, i)`. Using the wrong order makes every BYTE
    see index=address (>32) and return 0. -/
private def yulCallerPrincipalWordNested (wordIndex : Nat) : String :=
  if wordIndex ≥ 3 then
    "0"
  else
    -- Pack up to 8 network-order address bytes starting at body offset
    -- `wordIndex * 8` into one LE UInt64 via `byte(12+off, caller())`.
    let base : Nat := wordIndex * 8
    let nBytes : Nat := if wordIndex == 2 then 4 else 8
    Id.run do
      let mut acc := s!"byte({12 + base}, caller())"
      for k in [1:nBytes] do
        acc := s!"or({acc}, shl({8 * k}, byte({12 + base + k}, caller())))"
      acc

/-- M2 key/value scratch above `storeAtomic` spill (`0x10000..`).
    Layout: 9 key words at `base+32*i`, value at `base+32*9`. -/
private def mapPrincipalKeyMemBaseV1 : Nat := 0x20000

/-- M2: key equality using keys loaded from `keyMem` (9 words).
    Built iteratively so nesting parens stay exact (9 leaves → 8 `and`s). -/
private def yulPrincipalKeyEqFromMem (b keyMem : String) : String := Id.run do
  let leaf (i : Nat) : String :=
    s!"eq(sload(add({b}, {1 + i})), mload(add({keyMem}, {32 * i})))"
  let mut acc := leaf 0
  for i in [1:9] do
    acc := s!"and({acc}, {leaf i})"
  acc

/-- M2 compact Principal Map Yul helpers. Dense cap-4 layout:
    entry `e` at `base + 11*e`: occ, k0..k8, val.
    Keys/value live in memory (`keyMem` → 9 key words + value) so helpers stay
    within solc stack limits (no 9+ parameter lists). -/
private def renderPrincipalMapHelpers (indent : String) : String :=
  let keq := yulPrincipalKeyEqFromMem "b" "keyMem"
  -- Lookup: (base, keyMem) → tag, payload
  indent ++
    "function pf_map_p_lookup(base, keyMem) -> tag, payload {\n" ++
  indent ++ "  tag := 0\n" ++
  indent ++ "  payload := 0\n" ++
  indent ++ "  for { let e := 0 } lt(e, 4) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 11))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    if occ {\n" ++
  indent ++ s!"      if {keq} \{\n" ++
  indent ++ "        tag := 1\n" ++
  indent ++ "        payload := sload(add(b, 10))\n" ++
  indent ++ "      }\n" ++
  indent ++ "    }\n" ++
  indent ++ "  }\n" ++
  indent ++ "}\n" ++
  -- Full upsert: write 44 result leaves to outMem; revert when map full.
  indent ++
    "function pf_map_p_upsert(base, keyMem, outMem) {\n" ++
  indent ++ "  let anyMatch := 0\n" ++
  indent ++ "  let firstEmpty := 4\n" ++
  indent ++ "  for { let e := 0 } lt(e, 4) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 11))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    if occ {\n" ++
  indent ++ s!"      if {keq} \{ anyMatch := 1 }\n" ++
  indent ++ "    }\n" ++
  indent ++ "    if and(iszero(occ), eq(firstEmpty, 4)) { firstEmpty := e }\n" ++
  indent ++ "  }\n" ++
  indent ++ "  if iszero(or(anyMatch, lt(firstEmpty, 4))) { revert(0, 0) }\n" ++
  indent ++ "  let val := mload(add(keyMem, 288))\n" ++
  indent ++ "  for { let e := 0 } lt(e, 4) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 11))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    let matchHit := 0\n" ++
  indent ++ "    if occ {\n" ++
  indent ++ s!"      if {keq} \{ matchHit := 1 }\n" ++
  indent ++ "    }\n" ++
  indent ++ "    let insertHere := and(iszero(anyMatch), eq(e, firstEmpty))\n" ++
  indent ++ "    let write := or(matchHit, insertHere)\n" ++
  indent ++ "    let out := add(outMem, mul(mul(e, 11), 32))\n" ++
  indent ++ "    mstore(out, or(occ, write))\n" ++
  indent ++ "    for { let k := 0 } lt(k, 9) { k := add(k, 1) } {\n" ++
  indent ++ "      let want := mload(add(keyMem, mul(k, 32)))\n" ++
  indent ++ "      let stored := sload(add(b, add(1, k)))\n" ++
  indent ++ "      mstore(add(out, mul(add(1, k), 32)), add(mul(write, want), mul(iszero(write), stored)))\n" ++
  indent ++ "    }\n" ++
  indent ++ "    let oldV := sload(add(b, 10))\n" ++
  indent ++ "    mstore(add(out, 320), add(mul(write, val), mul(iszero(write), oldV)))\n" ++
  indent ++ "  }\n" ++
  indent ++ "}\n" ++
  -- Single-leaf view of full upsert (for non-batch Expr uses): write all 44
  -- into a private scratch then return leafIdx. Scratch at keyMem+320.
  indent ++
    "function pf_map_p_upsert_leaf(base, leafIdx, keyMem) -> r {\n" ++
  indent ++ "  let scratch := add(keyMem, 320)\n" ++
  indent ++ "  pf_map_p_upsert(base, keyMem, scratch)\n" ++
  indent ++ "  r := mload(add(scratch, mul(leafIdx, 32)))\n" ++
  indent ++ "}\n"

/-- M2b compact Map UInt64 Yul helpers. Dense cap-8 layout:
    entry `e` at `base + 3*e`: occ, key, val. Single UInt64 key as arg. -/
private def renderMapUInt64Helpers (indent : String) : String :=
  indent ++
    "function pf_map_u64_lookup(base, key) -> tag, payload {\n" ++
  indent ++ "  tag := 0\n" ++
  indent ++ "  payload := 0\n" ++
  indent ++ "  for { let e := 0 } lt(e, 8) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 3))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    if and(occ, eq(sload(add(b, 1)), key)) {\n" ++
  indent ++ "      tag := 1\n" ++
  indent ++ "      payload := sload(add(b, 2))\n" ++
  indent ++ "    }\n" ++
  indent ++ "  }\n" ++
  indent ++ "}\n" ++
  indent ++
    "function pf_map_u64_upsert(base, key, val, outMem) {\n" ++
  indent ++ "  let anyMatch := 0\n" ++
  indent ++ "  let firstEmpty := 8\n" ++
  indent ++ "  for { let e := 0 } lt(e, 8) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 3))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    if and(occ, eq(sload(add(b, 1)), key)) { anyMatch := 1 }\n" ++
  indent ++ "    if and(iszero(occ), eq(firstEmpty, 8)) { firstEmpty := e }\n" ++
  indent ++ "  }\n" ++
  indent ++ "  if iszero(or(anyMatch, lt(firstEmpty, 8))) { revert(0, 0) }\n" ++
  indent ++ "  for { let e := 0 } lt(e, 8) { e := add(e, 1) } {\n" ++
  indent ++ "    let b := add(base, mul(e, 3))\n" ++
  indent ++ "    let occ := sload(b)\n" ++
  indent ++ "    let matchHit := and(occ, eq(sload(add(b, 1)), key))\n" ++
  indent ++ "    let insertHere := and(iszero(anyMatch), eq(e, firstEmpty))\n" ++
  indent ++ "    let write := or(matchHit, insertHere)\n" ++
  indent ++ "    let out := add(outMem, mul(mul(e, 3), 32))\n" ++
  indent ++ "    mstore(out, or(occ, write))\n" ++
  indent ++ "    mstore(add(out, 32), add(mul(write, key), mul(iszero(write), sload(add(b, 1)))))\n" ++
  indent ++ "    mstore(add(out, 64), add(mul(write, val), mul(iszero(write), sload(add(b, 2)))))\n" ++
  indent ++ "  }\n" ++
  indent ++ "}\n" ++
  indent ++
    "function pf_map_u64_upsert_leaf(base, leafIdx, key, val) -> r {\n" ++
  indent ++ "  let scratch := 0x18000\n" ++
  indent ++ "  pf_map_u64_upsert(base, key, val, scratch)\n" ++
  indent ++ "  r := mload(add(scratch, mul(leafIdx, 32)))\n" ++
  indent ++ "}\n"

/-- Nested Yul expression form (no intermediate lets). Used for for-loop
    condition/update slots that require expression positions. Storage loads
    and checked overflow guards are not nested here — callers pre-render
    loop-invariant subtrees with the statement form. -/
private partial def renderExprNested (paramPrefix : String) : Expr → String
  | .literal value => toString value
  | .bigLiteral value => toString value
  | .param wordIndex => s!"{paramPrefix}{wordIndex}"
  | .narrowParam bitWidth wordIndex =>
      s!"and({paramPrefix}{wordIndex}, {yulUintMask bitWidth})"
  | .temp tempIndex => s!"t{tempIndex}"
  | .timestamp => "timestamp()"
  | .blockNumber => "number()"
  | .selfBalance => "selfbalance()"
  | .callerPrincipalWord wordIndex =>
      -- Nested form: assemble one LE body word of ADR-0025
      -- `u32le(20)||addr20` from `caller()`. wordIndex ≥ 3 → 0.
      yulCallerPrincipalWordNested wordIndex
  -- M2/M2b compact map ops are statement-form only (helpers need lets).
  | .mapPrincipalLookupTag .. | .mapPrincipalLookupPayload ..
  | .mapPrincipalUpsertLeaf ..
  | .mapUInt64LookupTag .. | .mapUInt64LookupPayload ..
  | .mapUInt64UpsertLeaf .. => "0"
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
  | .narrowSignedCheckedAdd _bitWidth lhs rhs =>
      s!"add({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .narrowSignedCheckedSub _bitWidth lhs rhs =>
      s!"sub({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .narrowSignedCheckedMul _bitWidth lhs rhs =>
      s!"mul({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .narrowSignedCheckedDiv _bitWidth lhs rhs =>
      s!"sdiv({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .narrowSignedCheckedMod _bitWidth lhs rhs =>
      s!"smod({renderExprNested paramPrefix lhs}, {renderExprNested paramPrefix rhs})"
  | .narrowSignedCompare _bitWidth op lhs rhs =>
      let l := renderExprNested paramPrefix lhs
      let r := renderExprNested paramPrefix rhs
      match op with
      | .eq => s!"eq({l}, {r})"
      | .ne => s!"iszero(eq({l}, {r}))"
      | .lt => s!"slt({l}, {r})"
      | .le => s!"iszero(sgt({l}, {r}))"
      | .gt => s!"sgt({l}, {r})"
      | .ge => s!"iszero(slt({l}, {r}))"
  | .narrowCheckedNeg _bitWidth operand =>
      s!"sub(0, {renderExprNested paramPrefix operand})"
  | .narrowSar _bitWidth lhs rhs =>
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


/-- T9c: signextend byte index = byteWidth - 1. -/
private def signedSignextendByte (bitWidth : Nat) : Nat := bitWidth / 8 - 1

/-- Low-width mask hex for and(_, mask). -/
private def signedMaskHex (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "0xff"
  | 16 => "0xffff"
  | 32 => "0xffffffff"
  | _ => "0xffffffffffffffff"

/-- Sign-extended intMin as i256 hex (for slt range gate and intMin div-by-neg1).
    Full 256-bit two's-complement after signextend from the given width. -/
private def signedIntMinHex (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80"
  | 16 => "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8000"
  | 32 => "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff80000000"
  | _ => "0xffffffffffffffffffffffffffffffff8000000000000000"

/-- Sign-extended intMax as i256 hex (for sgt range gate). -/
private def signedIntMaxHex (bitWidth : Nat) : String :=
  match bitWidth with
  | 8 => "0x7f"
  | 16 => "0x7fff"
  | 32 => "0x7fffffff"
  | _ => "0x7fffffffffffffff"

private partial def renderExpr (indent paramPrefix : String) (next : Nat) : Expr → RenderedExpr
  | .literal value =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {value}\n", value := name, next := next + 1 }
  | .bigLiteral value =>
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
  | .timestamp =>
      -- B-CTX-OPEN: block timestamp seconds with the UInt64 range guard
      -- (same discipline as storageLoad).
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := timestamp()\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .blockNumber =>
      -- ADR-0031 S2: block height via NUMBER / Yul `number()` with the
      -- UInt64 range guard (same discipline as timestamp / storageLoad).
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := number()\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .selfBalance =>
      -- ADR-0030 E2-3: SELFBALANCE opcode with the UInt64 range guard.
      -- `selfbalance()` returns the contract's ETH balance; for a freshly
      -- funded contract this is ≤ UInt64 in all engineering test scenarios.
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := selfbalance()\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .callerPrincipalWord wordIndex =>
      -- ADR-0031 S1 / ADR-0025: one LE body word of caller Principal.
      -- View-safe (`caller()` is readable under STATICCALL). Length leaf
      -- is `.literal 20` elsewhere; this tag only covers body words 0..7.
      let name := s!"expr{next}"
      let rhs := yulCallerPrincipalWordNested wordIndex
      { code := s!"{indent}let {name} := {rhs}\n",
        value := name, next := next + 1 }
  | .mapPrincipalLookupTag mapBaseSlot keyLeaves => Id.run do
      -- M2: spill 9 key words to fixed keyMem, helper returns tag+payload.
      let mut code := ""
      let mut next := next
      let keyMem := mapPrincipalKeyMemBaseV1
      for i in [0:keyLeaves.size] do
        let some k := keyLeaves[i]? | pure ()
        let rendered := renderExpr indent paramPrefix next k
        code := code ++ rendered.code
        next := rendered.next
        code := code ++ s!"{indent}mstore({keyMem + 32 * i}, {rendered.value})\n"
      let tagName := s!"expr{next}"
      let payloadName := s!"expr{next + 1}"
      { code := code ++
          s!"{indent}let {tagName}, {payloadName} := pf_map_p_lookup({mapBaseSlot}, {keyMem})\n",
        value := tagName, next := next + 2 }
  | .mapPrincipalLookupPayload mapBaseSlot keyLeaves => Id.run do
      let mut code := ""
      let mut next := next
      let keyMem := mapPrincipalKeyMemBaseV1
      for i in [0:keyLeaves.size] do
        let some k := keyLeaves[i]? | pure ()
        let rendered := renderExpr indent paramPrefix next k
        code := code ++ rendered.code
        next := rendered.next
        code := code ++ s!"{indent}mstore({keyMem + 32 * i}, {rendered.value})\n"
      let tagName := s!"expr{next}"
      let payloadName := s!"expr{next + 1}"
      { code := code ++
          s!"{indent}let {tagName}, {payloadName} := pf_map_p_lookup({mapBaseSlot}, {keyMem})\n",
        value := payloadName, next := next + 2 }
  | .mapPrincipalUpsertLeaf mapBaseSlot keyLeaves value leafIndex => Id.run do
      -- Non-batch path: spill keys+value, full upsert to scratch, load leaf.
      let mut code := ""
      let mut next := next
      let keyMem := mapPrincipalKeyMemBaseV1
      for i in [0:keyLeaves.size] do
        let some k := keyLeaves[i]? | pure ()
        let rendered := renderExpr indent paramPrefix next k
        code := code ++ rendered.code
        next := rendered.next
        code := code ++ s!"{indent}mstore({keyMem + 32 * i}, {rendered.value})\n"
      let valR := renderExpr indent paramPrefix next value
      code := code ++ valR.code
      next := valR.next
      code := code ++ s!"{indent}mstore({keyMem + 288}, {valR.value})\n"
      let name := s!"expr{next}"
      { code := code ++
          s!"{indent}let {name} := pf_map_p_upsert_leaf({mapBaseSlot}, {leafIndex}, {keyMem})\n",
        value := name, next := next + 1 }
  | .mapUInt64LookupTag mapBaseSlot key =>
      let keyR := renderExpr indent paramPrefix next key
      let tagName := s!"expr{keyR.next}"
      let payloadName := s!"expr{keyR.next + 1}"
      { code := keyR.code ++
          s!"{indent}let {tagName}, {payloadName} := pf_map_u64_lookup({mapBaseSlot}, {keyR.value})\n",
        value := tagName, next := keyR.next + 2 }
  | .mapUInt64LookupPayload mapBaseSlot key =>
      let keyR := renderExpr indent paramPrefix next key
      let tagName := s!"expr{keyR.next}"
      let payloadName := s!"expr{keyR.next + 1}"
      { code := keyR.code ++
          s!"{indent}let {tagName}, {payloadName} := pf_map_u64_lookup({mapBaseSlot}, {keyR.value})\n",
        value := payloadName, next := keyR.next + 2 }
  | .mapUInt64UpsertLeaf mapBaseSlot key value leafIndex =>
      let keyR := renderExpr indent paramPrefix next key
      let valR := renderExpr indent paramPrefix keyR.next value
      let name := s!"expr{valR.next}"
      { code := keyR.code ++ valR.code ++
          s!"{indent}let {name} := pf_map_u64_upsert_leaf({mapBaseSlot}, {leafIndex}, {keyR.value}, {valR.value})\n",
        value := name, next := valR.next + 1 }
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
  | .narrowSignedCheckedAdd bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let lo := signedIntMinHex bitWidth
      let hi := signedIntMaxHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}let {r} := add({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, {lo}), sgt({r}, {hi})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := rhs.next + 1 }
  | .narrowSignedCheckedSub bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let lo := signedIntMinHex bitWidth
      let hi := signedIntMaxHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}let {r} := sub({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, {lo}), sgt({r}, {hi})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := rhs.next + 1 }
  | .narrowSignedCheckedMul bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let lo := signedIntMinHex bitWidth
      let hi := signedIntMaxHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}let {r} := mul({a}, {b})\n" ++
          s!"{indent}if or(slt({r}, {lo}), sgt({r}, {hi})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := rhs.next + 1 }
  | .narrowSignedCheckedDiv bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let lo := signedIntMinHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}if iszero({b}) \{ revert(0, 0) }\n" ++
          s!"{indent}if and(eq({a}, {lo}), eq({b}, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := sdiv({a}, {b})\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := rhs.next + 1 }
  | .narrowSignedCheckedMod bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}if iszero({b}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := smod({a}, {b})\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := rhs.next + 1 }
  | .narrowSignedCompare bitWidth op lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let b := s!"b{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let yul := match op with
        | .eq => s!"eq({a}, {b})"
        | .ne => s!"iszero(eq({a}, {b}))"
        | .lt => s!"slt({a}, {b})"
        | .le => s!"iszero(sgt({a}, {b}))"
        | .gt => s!"sgt({a}, {b})"
        | .ge => s!"iszero(slt({a}, {b}))"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {b} := signextend({sx}, and({rhs.value}, {mask}))\n" ++
          s!"{indent}let {name} := {yul}\n",
        value := name, next := rhs.next + 1 }
  | .narrowCheckedNeg bitWidth operand =>
      let operand := renderExpr indent paramPrefix next operand
      let name := s!"expr{operand.next}"
      let a := s!"a{operand.next}"
      let r := s!"r{operand.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      let lo := signedIntMinHex bitWidth
      { code := operand.code ++
          s!"{indent}let {a} := signextend({sx}, and({operand.value}, {mask}))\n" ++
          s!"{indent}if eq({a}, {lo}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {r} := sub(0, {a})\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
        value := name, next := operand.next + 1 }
  | .narrowSar bitWidth lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let a := s!"a{rhs.next}"
      let r := s!"r{rhs.next}"
      let sx := signedSignextendByte bitWidth
      let mask := signedMaskHex bitWidth
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if iszero(lt({rhs.value}, {bitWidth})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {a} := signextend({sx}, and({lhs.value}, {mask}))\n" ++
          s!"{indent}let {r} := sar({rhs.value}, {a})\n" ++
          s!"{indent}let {name} := and({r}, {mask})\n",
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

/-- Reserved high memory base for `storeAtomic` leaf spill (B-EVM-MAP-STACK).

    Layout: leaf `i` lands at `base + 32*i` (one EVM word per leaf).
    Dense Map pilot uses 24 leaves → span `[0x10000, 0x10000 + 24*32) =
    [0x10000, 0x10300)`. Principal is 9 leaves; Array/Bytes N ≤ product caps.

    Safety (does not overwrite live expression data in this emitter):
    * ABI / return / event / external-call scratch uses **low** absolute
      addresses only: `mstore(0, …)`, `mstore(32*i, …)`, `mstore(4+32*i, …)`.
    * Solidity free-memory pointer slot `0x40` is unused for persistent data
      by this emitter (no free-mem bump for returns/events/calls).
    * Spill→sstore finishes before the next statement, so the same base is
      safely reused across consecutive `storeAtomic` batches and after return
      to low-address ABI encoding.

    Fixed base (not free-mem alloc): keeps addresses deterministic, avoids
    free-pointer interaction, and never changes call/return/event ABI layout. -/
private def storeAtomicSpillBaseV1 : Nat := 0x10000

private def storeAtomicSpillAddrV1 (leafIndex : Nat) : Nat :=
  storeAtomicSpillBaseV1 + 32 * leafIndex

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
    | .storeAtomic operations =>
        -- B-EVM-MAP-STACK / B-MAP-STRUCT-PIN / M2:
        -- Default path: Phase 1 (compute + spill) each leaf in its own nested
        -- Yul block; Phase 2 contiguous sstore from spill.
        -- M2 fast path: when all 44 leaves are `mapPrincipalUpsertLeaf` for the
        -- same (base, keys, value) with leafIndex==i, spill keys once, call
        -- `pf_map_p_upsert` into storeAtomic spill, then sstore — avoids
        -- 44× full-table rescans and keeps solc stack flat.
        let isPrincipalUpsertBatch : Bool := Id.run do
          if operations.size != 44 then return false
          let some first := operations[0]? | return false
          match first.value with
          | .mapPrincipalUpsertLeaf base0 keys0 val0 0 =>
              for i in [0:44] do
                match operations[i]? with
                | none => return false
                | some st =>
                    match st.value with
                    | .mapPrincipalUpsertLeaf base keys val leafIdx =>
                        unless base == base0 && leafIdx == i &&
                            keys == keys0 && val == val0 do
                          return false
                    | _ => return false
              return true
          | _ => return false
        let isUInt64UpsertBatch : Bool := Id.run do
          if operations.size != 24 then return false
          let some first := operations[0]? | return false
          match first.value with
          | .mapUInt64UpsertLeaf base0 key0 val0 0 =>
              for i in [0:24] do
                match operations[i]? with
                | none => return false
                | some st =>
                    match st.value with
                    | .mapUInt64UpsertLeaf base key val leafIdx =>
                        unless base == base0 && leafIdx == i &&
                            key == key0 && val == val0 do
                          return false
                    | _ => return false
              return true
          | _ => return false
        if isPrincipalUpsertBatch then
          let some first := operations[0]? | pure ()
          match first.value with
          | .mapPrincipalUpsertLeaf mapBaseSlot keyLeaves value _ =>
              let keyMem := mapPrincipalKeyMemBaseV1
              let outMem := storeAtomicSpillBaseV1
              for i in [0:keyLeaves.size] do
                let some k := keyLeaves[i]? | pure ()
                let rendered := renderExpr indent paramPrefix next k
                output := output ++ rendered.code
                next := rendered.next
                output := output ++
                  s!"{indent}mstore({keyMem + 32 * i}, {rendered.value})\n"
              let valR := renderExpr indent paramPrefix next value
              output := output ++ valR.code
              next := valR.next
              output := output ++
                s!"{indent}mstore({keyMem + 288}, {valR.value})\n" ++
                s!"{indent}pf_map_p_upsert({mapBaseSlot}, {keyMem}, {outMem})\n"
              for i in [0:operations.size] do
                match operations[i]? with
                | none => pure ()
                | some store =>
                    let loaded := s!"mload({storeAtomicSpillAddrV1 i})"
                    output := output ++
                      renderMaskedSstore indent store.slot loaded store.byteWidth
          | _ => pure ()
        else if isUInt64UpsertBatch then
          let some first := operations[0]? | pure ()
          match first.value with
          | .mapUInt64UpsertLeaf mapBaseSlot key value _ =>
              let outMem := storeAtomicSpillBaseV1
              let keyR := renderExpr indent paramPrefix next key
              output := output ++ keyR.code
              next := keyR.next
              let valR := renderExpr indent paramPrefix next value
              output := output ++ valR.code
              next := valR.next
              output := output ++
                s!"{indent}pf_map_u64_upsert({mapBaseSlot}, {keyR.value}, {valR.value}, {outMem})\n"
              for i in [0:operations.size] do
                match operations[i]? with
                | none => pure ()
                | some store =>
                    let loaded := s!"mload({storeAtomicSpillAddrV1 i})"
                    output := output ++
                      renderMaskedSstore indent store.slot loaded store.byteWidth
          | _ => pure ()
        else
          let nested := indent ++ "  "
          for i in [0:operations.size] do
            match operations[i]? with
            | none => pure ()
            | some store =>
                let rendered := renderExpr nested paramPrefix next store.value
                let addr := storeAtomicSpillAddrV1 i
                output := output ++ s!"{indent}\{\n" ++
                  rendered.code ++
                  s!"{nested}mstore({addr}, {rendered.value})\n" ++
                  s!"{indent}}\n"
                next := rendered.next
          for i in [0:operations.size] do
            match operations[i]? with
            | none => pure ()
            | some store =>
                let loaded := s!"mload({storeAtomicSpillAddrV1 i})"
                output := output ++
                  renderMaskedSstore indent store.slot loaded store.byteWidth
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
    | .returnAggregate leaves leafIsInt =>
        for index in [0:leaves.size] do
          let rendered := renderExpr indent paramPrefix next leaves[index]!
          output := output ++ rendered.code ++
            s!"{indent}mstore({32 * index}, {rendered.value})\n"
          next := rendered.next
        output := output ++ s!"{indent}return(0, {32 * leaves.size})\n"
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
    | .externalCall callee args =>
        -- Static QualifiedName → fixed CALL address + selector (AddressBearing).
        -- Target path = all but last component (joined by "."); method = last.
        -- Address = last 20 bytes of keccak256(UTF-8 target path).
        -- Selector = first 4 bytes of keccak256("method(uint64,...)").
        let method := callee[callee.size - 1]!
        let targetParts := callee.extract 0 (callee.size - 1)
        let targetPath := String.intercalate "." targetParts.toList
        -- Address = last 20 bytes of keccak256(UTF-8 target path) as hex.
        let addrHex := Keccak.keccak256Hex targetPath.toUTF8
        let addr20 := addrHex.drop 24
        let sel := Keccak.selector method (Array.replicate args.size "uint64")
        let padded := sel ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        let okName := s!"callOk{next}"
        next := next + 1
        output := output ++
          s!"{indent}let {okName} := call(gas(), 0x{addr20}, 0, 0, {4 + 32 * args.size}, 0, 0)\n" ++
          s!"{indent}if iszero({okName}) \{ revert(0, 0) }\n"
    | .externalCallResult callee args resultTemp =>
        -- N-CALL-RET/B-CALL-SEM: real CALL with 32-byte returndata capture,
        -- RETURNDATASIZE guard, first-word read, UInt64 range check. Same
        -- static address/selector derivation and failure-revert discipline
        -- as the void path.
        let method := callee[callee.size - 1]!
        let targetParts := callee.extract 0 (callee.size - 1)
        let targetPath := String.intercalate "." targetParts.toList
        let addrHex := Keccak.keccak256Hex targetPath.toUTF8
        let addr20 := addrHex.drop 24
        let sel := Keccak.selector method (Array.replicate args.size "uint64")
        let padded := sel ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        let okName := s!"callOk{next}"
        next := next + 1
        output := output ++
          s!"{indent}let {okName} := call(gas(), 0x{addr20}, 0, 0, {4 + 32 * args.size}, 0, 32)\n" ++
          s!"{indent}if iszero({okName}) \{ revert(0, 0) }\n" ++
          s!"{indent}if lt(returndatasize(), 32) \{ revert(0, 0) }\n" ++
          s!"{indent}let t{resultTemp} := mload(0)\n" ++
          s!"{indent}if gt(t{resultTemp}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
    | .schedule callee args =>
        -- Fire-and-forget: same static address/selector, CALL success ignored.
        let method := callee[callee.size - 1]!
        let targetParts := callee.extract 0 (callee.size - 1)
        let targetPath := String.intercalate "." targetParts.toList
        let addrHex := Keccak.keccak256Hex targetPath.toUTF8
        let addr20 := addrHex.drop 24
        let sel := Keccak.selector method (Array.replicate args.size "uint64")
        let padded := sel ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        let okName := s!"schedOk{next}"
        next := next + 1
        -- pop success: assign then discard (Yul requires the value be consumed)
        output := output ++
          s!"{indent}let {okName} := call(gas(), 0x{addr20}, 0, 0, {4 + 32 * args.size}, 0, 0)\n" ++
          s!"{indent}pop({okName})\n"
    | .nativeDeposit amount =>
        -- ADR-0029 B2: exact callvalue == amount (pinned; not >=).
        let rendered := renderExpr indent paramPrefix next amount
        output := output ++ rendered.code
        next := rendered.next
        output := output ++
          s!"{indent}if iszero(eq(callvalue(), {rendered.value})) \{ revert(0, 0) }\n"
    | .nativeTransfer dstLen dstBodyWords amount =>
        -- ADR-0029 B2: Principal wire identity → 20B address + value CALL.
        -- loweringContract: full gas, empty calldata, success-checked;
        -- dst must be exact u32le(20)||addr20; opaque-effect reentrancy honesty.
        let lenR := renderExpr indent paramPrefix next dstLen
        output := output ++ lenR.code
        next := lenR.next
        output := output ++
          s!"{indent}if iszero(eq({lenR.value}, 20)) \{ revert(0, 0) }\n"
        -- Render 8 body words (LE-packed opaque Principal body).
        let mut bodyVals : Array String := #[]
        for w in dstBodyWords do
          let wr := renderExpr indent paramPrefix next w
          output := output ++ wr.code
          next := wr.next
          bodyVals := bodyVals.push wr.value
        -- High limbs past 20 body bytes must be zero (exact shape gate).
        -- w2 high 32 bits + w3..w7.
        if bodyVals.size == 8 then
          output := output ++
            s!"{indent}if iszero(eq(shr(32, {bodyVals[2]!}), 0)) \{ revert(0, 0) }\n"
          for i in [3:8] do
            output := output ++
              s!"{indent}if iszero(eq({bodyVals[i]!}, 0)) \{ revert(0, 0) }\n"
          -- Assemble network-order 20B address into a right-aligned 32B word.
          output := output ++ s!"{indent}mstore(0, 0)\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({12 + i}, and(shr({8 * i}, {bodyVals[0]!}), 0xff))\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({20 + i}, and(shr({8 * i}, {bodyVals[1]!}), 0xff))\n"
          for i in [0:4] do
            output := output ++
              s!"{indent}mstore8({28 + i}, and(shr({8 * i}, {bodyVals[2]!}), 0xff))\n"
          let addrName := s!"xferAddr{next}"
          next := next + 1
          output := output ++ s!"{indent}let {addrName} := mload(0)\n"
          let amtR := renderExpr indent paramPrefix next amount
          output := output ++ amtR.code
          next := amtR.next
          let okName := s!"xferOk{next}"
          next := next + 1
          -- Full gas + empty calldata; success=false → revert (failure propagate).
          -- Recipient code may execute (re-entrancy possible); opaque effect.
          output := output ++
            s!"{indent}let {okName} := call(gas(), {addrName}, {amtR.value}, 0, 0, 0, 0)\n" ++
            s!"{indent}if iszero({okName}) \{ revert(0, 0) }\n"
        else
          -- Defensive: Plan validation should have fixed 8 body words.
          output := output ++ s!"{indent}revert(0, 0)\n"
    | .tokenTransfer mintLen mintBodyWords dstLen dstBodyWords amount =>
        -- ADR-0030 E1a: controlled dynamic callee (ERC-20 transfer).
        -- mint Principal → 20B token-contract address (CALL target);
        -- dst Principal → 20B recipient address (calldata);
        -- calldata = 4B selector + 32B address + 32B amount = 68 bytes;
        -- return value: returndatasize==0 → ok; ≥32 → first word != 0;
        -- CALL success==false → revert.
        --
        -- Memory layout (deterministic, no free-mem pointer interaction):
        --   [0, 68)   — calldata (selector + dst address + amount)
        --   0x10000   — temp 32B word for token-contract address assembly
        let tokenBase : Nat := 0x10000
        -- Render mint Principal leaves (len + 8 body words).
        let mintLenR := renderExpr indent paramPrefix next mintLen
        output := output ++ mintLenR.code
        next := mintLenR.next
        output := output ++
          s!"{indent}if iszero(eq({mintLenR.value}, 20)) \{ revert(0, 0) }\n"
        let mut mintVals : Array String := #[]
        for w in mintBodyWords do
          let wr := renderExpr indent paramPrefix next w
          output := output ++ wr.code
          next := wr.next
          mintVals := mintVals.push wr.value
        if mintVals.size == 8 then
          -- High limbs past 20 body bytes must be zero (exact shape gate).
          output := output ++
            s!"{indent}if iszero(eq(shr(32, {mintVals[2]!}), 0)) \{ revert(0, 0) }\n"
          for i in [3:8] do
            output := output ++
              s!"{indent}if iszero(eq({mintVals[i]!}, 0)) \{ revert(0, 0) }\n"
          -- Assemble token contract address into temp word at tokenBase.
          output := output ++ s!"{indent}mstore({tokenBase}, 0)\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 12 + i}, and(shr({8 * i}, {mintVals[0]!}), 0xff))\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 20 + i}, and(shr({8 * i}, {mintVals[1]!}), 0xff))\n"
          for i in [0:4] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 28 + i}, and(shr({8 * i}, {mintVals[2]!}), 0xff))\n"
          let tokenAddrName := s!"tokenAddr{next}"
          next := next + 1
          output := output ++ s!"{indent}let {tokenAddrName} := mload({tokenBase})\n"
          -- Render dst Principal leaves (len + 8 body words).
          let dstLenR := renderExpr indent paramPrefix next dstLen
          output := output ++ dstLenR.code
          next := dstLenR.next
          output := output ++
            s!"{indent}if iszero(eq({dstLenR.value}, 20)) \{ revert(0, 0) }\n"
          let mut dstVals : Array String := #[]
          for w in dstBodyWords do
            let wr := renderExpr indent paramPrefix next w
            output := output ++ wr.code
            next := wr.next
            dstVals := dstVals.push wr.value
          if dstVals.size == 8 then
            -- High limbs past 20 body bytes must be zero.
            output := output ++
              s!"{indent}if iszero(eq(shr(32, {dstVals[2]!}), 0)) \{ revert(0, 0) }\n"
            for i in [3:8] do
              output := output ++
                s!"{indent}if iszero(eq({dstVals[i]!}, 0)) \{ revert(0, 0) }\n"
            -- Build calldata at [0, 68):
            --   [0, 4)   selector 0xa9059cbb
            --   [4, 36)  dst address (12B zero pad + 20B address)
            --   [36, 68) amount (32B big-endian)
            -- Selector: left-aligned 4 bytes via padded 32B mstore at offset 0.
            output := output ++
              s!"{indent}mstore(0, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)\n"
            -- Assemble dst address into calldata [4, 36): zero-pad region
            -- [4, 16) is already zero from the padded selector mstore (the
            -- selector's high 28 bytes are zero). Write 20 address bytes to
            -- [16, 36).
            for i in [0:8] do
              output := output ++
                s!"{indent}mstore8({16 + i}, and(shr({8 * i}, {dstVals[0]!}), 0xff))\n"
            for i in [0:8] do
              output := output ++
                s!"{indent}mstore8({24 + i}, and(shr({8 * i}, {dstVals[1]!}), 0xff))\n"
            for i in [0:4] do
              output := output ++
                s!"{indent}mstore8({32 + i}, and(shr({8 * i}, {dstVals[2]!}), 0xff))\n"
            -- Amount at [36, 68).
            let amtR := renderExpr indent paramPrefix next amount
            output := output ++ amtR.code
            next := amtR.next
            output := output ++ s!"{indent}mstore(36, {amtR.value})\n"
            -- CALL: full gas, zero value, calldata [0, 68), ret [0, 32).
            let okName := s!"tokOk{next}"
            next := next + 1
            output := output ++
              s!"{indent}let {okName} := call(gas(), {tokenAddrName}, 0, 0, 68, 0, 32)\n" ++
              s!"{indent}if iszero({okName}) \{ revert(0, 0) }\n"
            -- Return-value predicate:
            --   returndatasize==0 → ok (USDT-style no-return contracts)
            --   returndatasize==32 → first word must be nonzero (bool false → revert)
            --   returndatasize ∉ {0, 32} → revert (1..31 or >32 fail closed)
            let rdsName := s!"tokRds{next}"
            next := next + 1
            output := output ++
              s!"{indent}let {rdsName} := returndatasize()\n" ++
              s!"{indent}switch {rdsName}\n" ++
              s!"{indent}case 0 \{ }\n" ++
              s!"{indent}case 32 \{ if iszero(mload(0)) \{ revert(0, 0) } }\n" ++
              s!"{indent}default \{ revert(0, 0) }\n"
          else
            -- Defensive: Plan validation should have fixed 8 body words.
            output := output ++ s!"{indent}revert(0, 0)\n"
        else
          -- Defensive: Plan validation should have fixed 8 body words.
          output := output ++ s!"{indent}revert(0, 0)\n"
    | .tokenBalanceOf mintLen mintBodyWords resultTemp =>
        -- ADR-0030 E2-3: read-only STATICCALL to mint address for
        -- `balanceOf(address)` (selector 0x70a08231 ++ 32B self address).
        -- Memory layout (deterministic, no free-mem pointer interaction):
        --   [0, 4)   selector 0x70a08231
        --   [4, 36)  self address (12B zero pad + 20B address())
        --   0x10000  temp 32B word for token-contract address assembly
        -- STATICCALL: full gas, zero value, calldata [0, 36), ret [0, 32).
        -- Require returndatasize==32, high 192 bits zero (UInt64), decode
        -- low 8 bytes. STATICCALL failure reverts.
        let tokenBase : Nat := 0x10000
        -- Render mint Principal leaves (len + 8 body words).
        let mintLenR := renderExpr indent paramPrefix next mintLen
        output := output ++ mintLenR.code
        next := mintLenR.next
        output := output ++
          s!"{indent}if iszero(eq({mintLenR.value}, 20)) \{ revert(0, 0) }\n"
        let mut mintVals : Array String := #[]
        for w in mintBodyWords do
          let wr := renderExpr indent paramPrefix next w
          output := output ++ wr.code
          next := wr.next
          mintVals := mintVals.push wr.value
        if mintVals.size == 8 then
          -- High limbs past 20 body bytes must be zero (exact shape gate).
          output := output ++
            s!"{indent}if iszero(eq(shr(32, {mintVals[2]!}), 0)) \{ revert(0, 0) }\n"
          for i in [3:8] do
            output := output ++
              s!"{indent}if iszero(eq({mintVals[i]!}, 0)) \{ revert(0, 0) }\n"
          -- Assemble token contract address into temp word at tokenBase.
          output := output ++ s!"{indent}mstore({tokenBase}, 0)\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 12 + i}, and(shr({8 * i}, {mintVals[0]!}), 0xff))\n"
          for i in [0:8] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 20 + i}, and(shr({8 * i}, {mintVals[1]!}), 0xff))\n"
          for i in [0:4] do
            output := output ++
              s!"{indent}mstore8({tokenBase + 28 + i}, and(shr({8 * i}, {mintVals[2]!}), 0xff))\n"
          let tokenAddrName := s!"balTokenAddr{next}"
          next := next + 1
          output := output ++ s!"{indent}let {tokenAddrName} := mload({tokenBase})\n"
          -- Build calldata at [0, 36):
          --   [0, 4)   selector 0x70a08231
          --   [4, 36)  self address: 12B zero pad + 20B address()
          -- Selector: left-aligned 4 bytes via padded 32B mstore at offset 0.
          output := output ++
            s!"{indent}mstore(0, 0x70a0823100000000000000000000000000000000000000000000000000000000)\n"
          -- Write self address() at offset 4: mstore(4, address()) writes a
          -- 32-byte word [4, 36) = 12B zero pad + 20B address() (right-aligned).
          -- This overwrites the zero-pad region [4, 16) from the selector mstore
          -- with the correct left-padding, and places the 20B address at [16, 36).
          output := output ++ s!"{indent}mstore(4, address())\n"
          -- STATICCALL: full gas, zero value, calldata [0, 36), ret [0, 32).
          let okName := s!"balOk{next}"
          next := next + 1
          output := output ++
            s!"{indent}let {okName} := staticcall(gas(), {tokenAddrName}, 0, 36, 0, 32)\n" ++
            s!"{indent}if iszero({okName}) \{ revert(0, 0) }\n" ++
            s!"{indent}if iszero(eq(returndatasize(), 32)) \{ revert(0, 0) }\n"
          -- High 192 bits must be zero (UInt64 result); decode low 8 bytes.
          let retName := s!"balRet{next}"
          next := next + 1
          output := output ++
            s!"{indent}let {retName} := mload(0)\n" ++
            s!"{indent}if iszero(eq(shr(64, {retName}), 0)) \{ revert(0, 0) }\n" ++
            s!"{indent}let t{resultTemp} := and({retName}, 0xffffffffffffffff)\n"
        else
          -- Defensive: Plan validation should have fixed 8 body words.
          output := output ++ s!"{indent}revert(0, 0)\n"
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

/-- True when any entry is payable (ADR-0029 B2 deposit). When true the global
    runtime callvalue guard is removed and non-payable/view entries each get
    an entry-local `callvalue() == 0` check so existing non-payable programs
    stay byte-identical (global guard path). -/
private def planHasPayableEntry (plan : Plan) : Bool :=
  plan.entries.any (·.mutability == .payable)

private def renderEntry (plan : Plan) (entry : Entry) (hasPayable : Bool) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  -- Per-entry non-payable discipline when the program also has payable entries
  -- (global runtime guard is then absent).
  if hasPayable && entry.mutability != .payable then
    output := output ++ "        if callvalue() { revert(0, 0) }\n"
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

/-- Shared walker: which compact Map families appear in a Plan expr. -/
private structure CompactMapUsesV1 where
  principal : Bool := false
  uint64 : Bool := false
  deriving Inhabited

private def mergeMapUses (a b : CompactMapUsesV1) : CompactMapUsesV1 :=
  { principal := a.principal || b.principal, uint64 := a.uint64 || b.uint64 }

private partial def exprCompactMapUsesV1 : Expr → CompactMapUsesV1
  | .mapPrincipalLookupTag .. | .mapPrincipalLookupPayload ..
  | .mapPrincipalUpsertLeaf .. => { principal := true }
  | .mapUInt64LookupTag .. | .mapUInt64LookupPayload ..
  | .mapUInt64UpsertLeaf .. => { uint64 := true }
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .add l r | .compare _ l r | .signedCompare _ l r
  | .bitAnd l r | .bitOr l r | .bitXor l r | .shl l r | .shr l r | .sar l r
  | .logicalAnd l r | .logicalOr l r
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r | .narrowSar _ l r
  | .signedCheckedAdd l r | .signedCheckedSub l r | .signedCheckedMul l r
  | .signedCheckedDiv l r | .signedCheckedMod l r
  | .narrowSignedCheckedAdd _ l r | .narrowSignedCheckedSub _ l r
  | .narrowSignedCheckedMul _ l r | .narrowSignedCheckedDiv _ l r
  | .narrowSignedCheckedMod _ l r | .narrowSignedCompare _ _ l r
  | .fieldAdd l r | .fieldSub l r | .fieldMul l r | .fieldDiv l r =>
      mergeMapUses (exprCompactMapUsesV1 l) (exprCompactMapUsesV1 r)
  | .bitNot o | .boolNot o | .narrowBitNot _ o | .checkedNeg o
  | .narrowCheckedNeg _ o | .fieldNeg o => exprCompactMapUsesV1 o
  | .indexedStorageLoad _ _ index _ => exprCompactMapUsesV1 index
  | .boundsCheckedIndex index _ => exprCompactMapUsesV1 index
  | .arrayIndexGet index leaves =>
      leaves.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e))
        (exprCompactMapUsesV1 index)
  | .callFn _ args =>
      args.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {}
  | _ => {}

private partial def statementCompactMapUsesV1 : Statement → CompactMapUsesV1
  | .store s => exprCompactMapUsesV1 s.value
  | .storeAtomic ops =>
      ops.foldl (fun acc s => mergeMapUses acc (exprCompactMapUsesV1 s.value)) {}
  | .returnValue v => exprCompactMapUsesV1 v
  | .returnAggregate leaves _ =>
      leaves.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {}
  | .assert c => exprCompactMapUsesV1 c
  | .emitEvent _ args | .revertError _ args =>
      args.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {}
  | .externalCall _ args | .schedule _ args | .externalCallResult _ args _ =>
      args.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {}
  | .nativeDeposit a => exprCompactMapUsesV1 a
  | .nativeTransfer dl dw a =>
      mergeMapUses (exprCompactMapUsesV1 dl)
        (mergeMapUses
          (dw.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {})
          (exprCompactMapUsesV1 a))
  | .tokenTransfer ml mw dl dw a =>
      mergeMapUses (exprCompactMapUsesV1 ml)
        (mergeMapUses
          (mw.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {})
          (mergeMapUses (exprCompactMapUsesV1 dl)
            (mergeMapUses
              (dw.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {})
              (exprCompactMapUsesV1 a))))
  | .tokenBalanceOf ml mw _ =>
      mergeMapUses (exprCompactMapUsesV1 ml)
        (mw.foldl (fun acc e => mergeMapUses acc (exprCompactMapUsesV1 e)) {})
  | .ifThenElse c t e =>
      mergeMapUses (exprCompactMapUsesV1 c)
        (mergeMapUses
          (t.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) {})
          (e.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) {}))
  | .switchOn s cases d =>
      mergeMapUses (exprCompactMapUsesV1 s)
        (mergeMapUses
          (cases.foldl (fun acc (_, b) =>
            b.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) acc) {})
          (d.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) {}))
  | .forLoop _ _ _ init cond update body =>
      mergeMapUses (exprCompactMapUsesV1 init)
        (mergeMapUses (exprCompactMapUsesV1 cond)
          (mergeMapUses (exprCompactMapUsesV1 update)
            (body.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) {})))
  | .returnNone => {}

private def planCompactMapUsesV1 (plan : Plan) : CompactMapUsesV1 :=
  let ctor :=
    match plan.constructor with
    | some c =>
        mergeMapUses
          (c.body.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) {})
          (c.stores.foldl (fun acc s => mergeMapUses acc (exprCompactMapUsesV1 s.value)) {})
    | none => {}
  let entries :=
    plan.entries.foldl (fun acc e =>
      e.body.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) acc) {}
  let fns :=
    plan.fns.foldl (fun acc f =>
      f.body.foldl (fun acc s => mergeMapUses acc (statementCompactMapUsesV1 s)) acc) {}
  mergeMapUses ctor (mergeMapUses entries fns)

private def renderYul (plan : Plan) : String :=
  let hasPayable := planHasPayableEntry plan
  let entries := plan.entries.foldl
    (fun output entry => output ++ renderEntry plan entry hasPayable) ""
  let ctorFns := renderFnDefs "    " plan
  let runtimeFns := renderFnDefs "      " plan
  let uses := planCompactMapUsesV1 plan
  let mapHelpersCtor :=
    (if uses.principal then renderPrincipalMapHelpers "    " else "") ++
    (if uses.uint64 then renderMapUInt64Helpers "    " else "")
  let mapHelpersRuntime :=
    (if uses.principal then renderPrincipalMapHelpers "      " else "") ++
    (if uses.uint64 then renderMapUInt64Helpers "      " else "")
  -- Keep global callvalue guard when no entry is payable (byte-identical with
  -- historical Counter/Guarded goldens). Payable programs drop the global
  -- guard; non-payable/view arms carry entry-local guards instead.
  let runtimeCallvalueGuard :=
    if hasPayable then ""
    else "      if callvalue() { revert(0, 0) }\n"
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    ctorFns ++
    mapHelpersCtor ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    runtimeCallvalueGuard ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    runtimeFns ++
    mapHelpersRuntime ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  let ty := abiParamTypeString param
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"{ty}\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def leafAbiTypeString (leaf : LeafAbiType) : String :=
  if leaf.isInt then "int64" else "uint64"

private def resultKindAbiType (kind : ResultKind) : String :=
  match kind with
  | .uint64 => "uint64"
  | .bool => "bool"
  | .int64 => "int64"
  | .field => "uint256"
  | .uint8 => "uint8"
  | .uint16 => "uint16"
  | .uint32 => "uint32"
  | .uint128 => "uint128"
  | .uint256 => "uint256"
  | .int8 => "int8"
  | .int16 => "int16"
  | .int32 => "int32"
  | .aggregate leaves =>
      -- B-RET-ABI: Solidity tuple type, e.g. "(uint64,int64)".
      "(" ++ String.intercalate "," (leaves.map leafAbiTypeString).toList ++ ")"

/-- B-RET-ABI: render aggregate return outputs as a Solidity tuple with
`components`. Scalar kinds keep the single-output form. -/
private def renderEntryOutputsAbi (entry : Entry) : String :=
  match entry.resultKind with
  | .aggregate leaves =>
      let comps := leaves.map fun leaf =>
        "{\"name\":\"\",\"type\":\"" ++ leafAbiTypeString leaf ++ "\"}"
      "{\"name\":\"\",\"type\":\"" ++ resultKindAbiType entry.resultKind ++
        "\",\"components\":[" ++ String.intercalate "," comps.toList ++ "]}"
  | _ =>
      "{\"name\":\"\",\"type\":\"" ++ resultKindAbiType entry.resultKind ++ "\"}"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
    | .payable => "payable"
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[" ++ renderEntryOutputsAbi entry ++ "]}"

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
