import ProofForgeV2.Targets.Icp.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# ICP EmitIRV1 — Plan → structured IR → `.wat` + `.did`

IR is a structured sequential temp-register op list (not String/JSON). The
renderer is the sole producer of the Wasm-text and Candid-interface bytes.

Honesty notes (ICP-2 engineering pilot, not formal / hermetic / deployed):

* MVP heap globals only. State lives in mutable Wasm `global`s with no
  stable-memory persistence across canister upgrade (no
  `canister_pre_upgrade`/`canister_post_upgrade`). A real upgrade would lose
  state; this leaf has no upgrade story.
* The Candid wire codec here is a minimal inline codec scoped to a
  homogeneous integer domain: all-`nat64` (`0x78`) or all-`int64` (`0x79`)
  (zero or more args, zero or one result; zero-entry type table; values as
  little-endian 8-byte payloads; LEB128 only for table/arg counts). Signed
  programs use two's-complement overflow traps on `+`/`-`. Finalize uses
  locked `wat2wasm` only; PocketIC is a separate host-optional ICP-3
  lane (`scripts/icp_runtime_test.sh`), not invoked from Finalize.
* `canister_init` does not call `ic0.msg_reply` (the install path has no
  reply expectation); `canister_update`/`canister_query` methods do.
-/

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .icp message

-- ---------------------------------------------------------------------------
-- Structured sequential-temp IR
-- ---------------------------------------------------------------------------

/-- Sequential-temp ("SSA-ish") operation. Temps are plain i64 Wasm locals;
    `t0..t{paramCount-1}` are the decoded Candid arguments in order. -/
inductive Operation where
  | literal (destination : Nat) (value : UInt64)
  | stateLoad (destination fieldIndex : Nat)
  | unixTimeSeconds (destination : Nat)
  /-- CAP-1b: `ic0.msg_caller_size` → dest (UInt64 length leaf). -/
  | callerPrincipalLen (destination : Nat)
  /-- CAP-1b: body word `wordIndex` of the caller Principal wire. -/
  | callerPrincipalWord (destination wordIndex : Nat)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | compare (destination : Nat) (op : CompareOp) (lhs rhs : Nat)
  | boolAnd (destination lhs rhs : Nat)
  | boolOr (destination lhs rhs : Nat)
  | boolNot (destination operand : Nat)
  | ite (destination cond t e : Nat)
  | assertTrue (condition : Nat)
  /-- CAP-1b: AND of 9 i64 equalities (lhsTemps/rhsTemps length 9). -/
  | principalEq (destination : Nat) (lhsTemps rhsTemps : Array Nat)
  | principalNe (destination : Nat) (lhsTemps rhsTemps : Array Nat)
  | storeState (fieldIndex value : Nat)
  /-- T9a: side-effecting Wasm `if`/`else` (no result type). -/
  | ifThenElse (cond : Nat) (thenOps elseOps : Array Operation)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  mode : MethodMode
  resultKind : ResultKind
  paramCount : Nat
  paramKinds : Array ParamKind
  tempCount : Nat
  operations : Array Operation
  result? : Option Nat
  /-- Aggregate reply temps (Candid positional tuple). Empty for scalars. -/
  resultTemps : Array Nat := #[]
  deriving BEq, Inhabited, Repr

/-- Physical temp layout: each integer param occupies 1 temp; each Principal
    param occupies 9 consecutive temps (len + 8 body words). -/
private structure ParamLayout where
  kinds : Array ParamKind
  bases : Array Nat
  nextTemp : Nat
  deriving Inhabited

private def makeParamLayout (kinds : Array ParamKind) : ParamLayout :=
  Id.run do
    let mut bases : Array Nat := #[]
    let mut t : Nat := 0
    for k in kinds do
      bases := bases.push t
      t := t + match k with
        | .integer => 1
        | .principal => icpPrincipalLeafCountV1
    { kinds, bases, nextTemp := t }

private def paramTemp
    (layout : ParamLayout) (index : Nat) : Nat :=
  match layout.bases[index]? with
  | some b => b
  | none => index

private def paramPrincipalTemp
    (layout : ParamLayout) (index wordIndex : Nat) : Nat :=
  paramTemp layout index + wordIndex

structure IR where
  sourcePlan : Plan
  signedNumeric : Bool
  initializer : MethodIR
  entries : Array MethodIR
  views : Array MethodIR
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Plan Expr/Statement → Operation
-- ---------------------------------------------------------------------------

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

mutual
private partial def lowerExpr (layout : ParamLayout) (next : Nat) : Expr → LoweredExpr
  | .literal value => { operations := #[.literal next value], value := next, next := next + 1 }
  | .param index => { operations := #[], value := paramTemp layout index, next := next }
  | .stateLoad fieldIndex =>
      { operations := #[.stateLoad next fieldIndex], value := next, next := next + 1 }
  | .unixTimeSeconds =>
      { operations := #[.unixTimeSeconds next], value := next, next := next + 1 }
  | .callerPrincipalLen =>
      { operations := #[.callerPrincipalLen next], value := next, next := next + 1 }
  | .callerPrincipalWord wordIndex =>
      {
        operations := #[.callerPrincipalWord next wordIndex]
        value := next
        next := next + 1
      }
  | .paramPrincipalLen index =>
      { operations := #[], value := paramPrincipalTemp layout index 0, next := next }
  | .paramPrincipalWord index wordIndex =>
      {
        operations := #[]
        value := paramPrincipalTemp layout index (wordIndex + 1)
        next := next
      }
  | .principalEq lhs rhs =>
      lowerPrincipalCompare layout next false lhs rhs
  | .principalNe lhs rhs =>
      lowerPrincipalCompare layout next true lhs rhs
  | .checkedAdd lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedAdd r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .checkedSub lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedSub r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .checkedMul lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedMul r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .checkedDiv lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedDiv r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .checkedMod lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedMod r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .compare op lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.compare r.next op l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .boolAnd lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.boolAnd r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .boolOr lhs rhs =>
      let l := lowerExpr layout next lhs
      let r := lowerExpr layout l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.boolOr r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .boolNot operand =>
      let o := lowerExpr layout next operand
      {
        operations := o.operations ++ #[.boolNot o.next o.value]
        value := o.next
        next := o.next + 1
      }
  | .ite cond t e =>
      let c := lowerExpr layout next cond
      let tv := lowerExpr layout c.next t
      let ev := lowerExpr layout tv.next e
      {
        operations :=
          c.operations ++ tv.operations ++ ev.operations ++
            #[.ite ev.next c.value tv.value ev.value]
        value := ev.next
        next := ev.next + 1
      }

private partial def lowerPrincipalCompare
    (layout : ParamLayout) (next : Nat) (negate : Bool)
    (lhs rhs : Array Expr) : LoweredExpr :=
  Id.run do
    let mut ops : Array Operation := #[]
    let mut n := next
    let mut lhsTemps : Array Nat := #[]
    let mut rhsTemps : Array Nat := #[]
    for e in lhs do
      let lv := lowerExpr layout n e
      ops := ops ++ lv.operations
      lhsTemps := lhsTemps.push lv.value
      n := lv.next
    for e in rhs do
      let lv := lowerExpr layout n e
      ops := ops ++ lv.operations
      rhsTemps := rhsTemps.push lv.value
      n := lv.next
    let op :=
      if negate then Operation.principalNe n lhsTemps rhsTemps
      else Operation.principalEq n lhsTemps rhsTemps
    {
      operations := ops.push op
      value := n
      next := n + 1
    }

private partial def lowerStmts (layout : ParamLayout) (next0 : Nat) (body : Array Statement) :
    Array Operation × Option Nat × Array Nat × Nat := Id.run do
  let mut ops : Array Operation := #[]
  let mut next := next0
  let mut result? : Option Nat := none
  let mut resultTemps : Array Nat := #[]
  for stmt in body do
    match stmt with
    | .assert condition =>
        let lv := lowerExpr layout next condition
        ops := ops ++ lv.operations ++ #[.assertTrue lv.value]
        next := lv.next
    | .store fieldIndex value =>
        let lv := lowerExpr layout next value
        ops := ops ++ lv.operations ++ #[.storeState fieldIndex lv.value]
        next := lv.next
    | .ifThenElse condition thenBody elseBody =>
        let lv := lowerExpr layout next condition
        let (thenOps, thenRes, thenTemps, next1) := lowerStmts layout lv.next thenBody
        let (elseOps, elseRes, elseTemps, next2) := lowerStmts layout next1 elseBody
        ops := ops ++ lv.operations ++ #[.ifThenElse lv.value thenOps elseOps]
        result? := thenRes <|> elseRes <|> result?
        resultTemps :=
          if thenTemps.isEmpty then
            if elseTemps.isEmpty then resultTemps else elseTemps
          else thenTemps
        next := next2
    | .returnValue value =>
        let lv := lowerExpr layout next value
        ops := ops ++ lv.operations
        result? := some lv.value
        next := lv.next
    | .returnAggregate leaves =>
        for e in leaves do
          let lv := lowerExpr layout next e
          ops := ops ++ lv.operations
          resultTemps := resultTemps.push lv.value
          next := lv.next
        result? := resultTemps[0]?
    | .returnNone => pure ()
  pure (ops, result?, resultTemps, next)
end

private def lowerBody (layout : ParamLayout) (body : Array Statement) :
    Array Operation × Option Nat × Array Nat × Nat :=
  lowerStmts layout layout.nextTemp body

private def lowerMethod (m : Method) : MethodIR :=
  let layout := makeParamLayout m.paramKinds
  let (ops, result?, resultTemps, tempCount) := lowerBody layout m.body
  {
    name := m.name
    mode := m.mode
    resultKind := m.resultKind
    paramCount := m.params.size
    paramKinds := m.paramKinds
    tempCount
    operations := ops
    result?
    resultTemps
  }

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  pure {
    sourcePlan := plan
    signedNumeric := plan.signedNumeric
    initializer := lowerMethod plan.initializer
    entries := plan.entries.map lowerMethod
    views := plan.views.map lowerMethod
  }

-- ---------------------------------------------------------------------------
-- WAT renderer
-- ---------------------------------------------------------------------------

/-- Scratch buffer offsets inside the sole exported linear memory page
    (64 KiB); ICP-2 argument/result payloads are tiny (all-nat64), so a fixed
    512-byte argument scratch and 512-byte reply scratch are generous. -/
private def argBufOffset : Nat := 0
private def argBufCap : Nat := 512
/-- CAP-1b: scratch for `u32le(len)‖principal-bytes` (4+64). -/
private def callerScratchOffset : Nat := 1024
private def paramScratchOffset : Nat := 1152
private def replyBufOffset : Nat := 4096
/-- Candid `principal` primitive (SLEB128 `-24`, single byte `0x68`). -/
private def candidPrincipalOpcode : Nat := 104

/-- Candid primitive type opcode for `nat64` (SLEB128 `-8`, single byte
    `0x78`) and `int64` (SLEB128 `-7`, `0x79`). A given Plan is homogeneous:
    every integer slot uses exactly one of these opcodes. -/
private def candidNat64Opcode : Nat := 120
private def candidInt64Opcode : Nat := 121
/-- Candid `bool` (SLEB128 `-2`, single byte `0x7e`). -/
private def candidBoolOpcode : Nat := 126

private def candidIntOpcode (signed : Bool) : Nat :=
  if signed then candidInt64Opcode else candidNat64Opcode

private def candidIntName (signed : Bool) : String :=
  if signed then "int64" else "nat64"

private def wasmFuncName (name : String) : String := "$" ++ name

/-- Module-level helper functions shared by every method body: raw byte
    read/write over the reply cursor, the fixed 4-byte "DIDL" magic, and a
    generic unsigned-LEB128 reader/writer. -/
private def preludeWat : String :=
  "  (func $pf_read_byte (result i32)\n" ++
  "    (local $b i32)\n" ++
  "    (local.set $b (i32.load8_u (global.get $pf_cursor)))\n" ++
  "    (global.set $pf_cursor (i32.add (global.get $pf_cursor) (i32.const 1)))\n" ++
  "    (local.get $b)\n" ++
  "  )\n" ++
  "  (func $pf_write_byte (param $b i32)\n" ++
  "    (i32.store8 (global.get $pf_reply_len) (local.get $b))\n" ++
  "    (global.set $pf_reply_len (i32.add (global.get $pf_reply_len) (i32.const 1)))\n" ++
  "  )\n" ++
  "  (func $pf_expect_didl\n" ++
  "    (if (i32.ne (call $pf_read_byte) (i32.const 68)) (then unreachable))\n" ++
  "    (if (i32.ne (call $pf_read_byte) (i32.const 73)) (then unreachable))\n" ++
  "    (if (i32.ne (call $pf_read_byte) (i32.const 68)) (then unreachable))\n" ++
  "    (if (i32.ne (call $pf_read_byte) (i32.const 76)) (then unreachable))\n" ++
  "  )\n" ++
  "  (func $pf_write_didl\n" ++
  "    (call $pf_write_byte (i32.const 68))\n" ++
  "    (call $pf_write_byte (i32.const 73))\n" ++
  "    (call $pf_write_byte (i32.const 68))\n" ++
  "    (call $pf_write_byte (i32.const 76))\n" ++
  "  )\n" ++
  "  (func $pf_leb_read (result i64)\n" ++
  "    (local $result i64) (local $shift i64) (local $byte i32)\n" ++
  "    (block $done\n" ++
  "      (loop $again\n" ++
  "        (local.set $byte (i32.load8_u (global.get $pf_cursor)))\n" ++
  "        (global.set $pf_cursor (i32.add (global.get $pf_cursor) (i32.const 1)))\n" ++
  "        (local.set $result (i64.or (local.get $result)\n" ++
  "          (i64.shl (i64.extend_i32_u (i32.and (local.get $byte) (i32.const 127))) (local.get $shift))))\n" ++
  "        (local.set $shift (i64.add (local.get $shift) (i64.const 7)))\n" ++
  "        (br_if $done (i32.eqz (i32.and (local.get $byte) (i32.const 128))))\n" ++
  "        (br $again)\n" ++
  "      )\n" ++
  "    )\n" ++
  "    (local.get $result)\n" ++
  "  )\n" ++
  "  (func $pf_leb_write (param $v i64)\n" ++
  "    (local $byte i32)\n" ++
  "    (block $done\n" ++
  "      (loop $again\n" ++
  "        (local.set $byte (i32.wrap_i64 (i64.and (local.get $v) (i64.const 127))))\n" ++
  "        (local.set $v (i64.shr_u (local.get $v) (i64.const 7)))\n" ++
  "        (if (i64.eqz (local.get $v))\n" ++
  "          (then\n" ++
  "            (call $pf_write_byte (local.get $byte))\n" ++
  "            (br $done))\n" ++
  "          (else\n" ++
  "            (call $pf_write_byte (i32.or (local.get $byte) (i32.const 128)))))\n" ++
  "        (br $again)\n" ++
  "      )\n" ++
  "    )\n" ++
  "  )\n"

/-- Same-sign add that wraps to the opposite sign is overflow.
    Different-sign sub that does not preserve the lhs sign is overflow. -/
private def renderSignedAddTrap (destination lhs rhs : Nat) : String :=
  s!"    (local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
  s!"    (if (i32.and\n" ++
  s!"          (i64.eqz (i64.xor (i64.shr_s (local.get $t{lhs}) (i64.const 63))\n" ++
  s!"                            (i64.shr_s (local.get $t{rhs}) (i64.const 63))))\n" ++
  s!"          (i32.eqz (i64.eqz (i64.xor (i64.shr_s (local.get $t{lhs}) (i64.const 63))\n" ++
  s!"                                     (i64.shr_s (local.get $t{destination}) (i64.const 63))))))\n" ++
  s!"      (then unreachable))\n"

private def renderSignedSubTrap (destination lhs rhs : Nat) : String :=
  s!"    (local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
  s!"    (if (i32.and\n" ++
  s!"          (i32.eqz (i64.eqz (i64.xor (i64.shr_s (local.get $t{lhs}) (i64.const 63))\n" ++
  s!"                                     (i64.shr_s (local.get $t{rhs}) (i64.const 63)))))\n" ++
  s!"          (i32.eqz (i64.eqz (i64.xor (i64.shr_s (local.get $t{lhs}) (i64.const 63))\n" ++
  s!"                                     (i64.shr_s (local.get $t{destination}) (i64.const 63))))))\n" ++
  s!"      (then unreachable))\n"

private def renderPrincipalCompare
    (destination : Nat) (negate : Bool) (lhsTemps rhsTemps : Array Nat) : String :=
  Id.run do
    let mut out := s!"    (local.set $t{destination} (i64.const 1))\n"
    let n := min lhsTemps.size rhsTemps.size
    for i in [0:n] do
      let l := lhsTemps[i]!
      let r := rhsTemps[i]!
      out := out ++
        s!"    (local.set $t{destination} (i64.and (local.get $t{destination})\n" ++
        s!"      (i64.extend_i32_u (i64.eq (local.get $t{l}) (local.get $t{r})))))\n"
    if negate then
      out := out ++
        s!"    (local.set $t{destination} (i64.xor (local.get $t{destination}) (i64.const 1)))\n"
    pure out

/-- Zero 72 bytes at `$dst`, write ADR-0025 `u32le(len)` at `$dst`, copy
    `len` caller bytes to `$dst+4` via `ic0.msg_caller_copy`. Traps if
    `len = 0` or `len > 29`. Returns length as i64. -/
private def callerHelperWat : String :=
  "  ;; CAP-1b: context.caller Principal wire is ADR-0025-class u32le(len)||bytes\n" ++
  "  ;; (ic0.msg_caller_size / ic0.msg_caller_copy; max 29). Not an account-id.\n" ++
  "  (func $pf_load_msg_caller (param $dst i32) (result i64)\n" ++
  "    (local $len i32)\n" ++
  "    (local.set $len (call $ic0_msg_caller_size))\n" ++
  "    (if (i32.eqz (local.get $len)) (then unreachable))\n" ++
  s!"    (if (i32.gt_u (local.get $len) (i32.const {icpPrincipalMaxPayloadBytesV1})) (then unreachable))\n" ++
  "    (call $pf_zero_principal_scratch (local.get $dst))\n" ++
  "    (i32.store (local.get $dst) (local.get $len))\n" ++
  "    (call $ic0_msg_caller_copy (i32.add (local.get $dst) (i32.const 4)) (i32.const 0) (local.get $len))\n" ++
  "    (i64.extend_i32_u (local.get $len))\n" ++
  "  )\n"

/-- Candid principal value: tag `0x01` + LEB128(len) + bytes. Writes the
    same ADR-0025 scratch layout as `$pf_load_msg_caller`. -/
private def principalDecodeHelperWat : String :=
  "  (func $pf_decode_candid_principal (param $dst i32) (result i64)\n" ++
  "    (local $len i32) (local $i i32)\n" ++
  "    (if (i32.ne (call $pf_read_byte) (i32.const 1)) (then unreachable))\n" ++
  "    (local.set $len (i32.wrap_i64 (call $pf_leb_read)))\n" ++
  "    (if (i32.eqz (local.get $len)) (then unreachable))\n" ++
  s!"    (if (i32.gt_u (local.get $len) (i32.const {icpPrincipalMaxPayloadBytesV1})) (then unreachable))\n" ++
  "    (call $pf_zero_principal_scratch (local.get $dst))\n" ++
  "    (i32.store (local.get $dst) (local.get $len))\n" ++
  "    (local.set $i (i32.const 0))\n" ++
  "    (block $done\n" ++
  "      (loop $copy\n" ++
  "        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))\n" ++
  "        (i32.store8 (i32.add (i32.add (local.get $dst) (i32.const 4)) (local.get $i))\n" ++
  "          (call $pf_read_byte))\n" ++
  "        (local.set $i (i32.add (local.get $i) (i32.const 1)))\n" ++
  "        (br $copy)\n" ++
  "      )\n" ++
  "    )\n" ++
  "    (i64.extend_i32_u (local.get $len))\n" ++
  "  )\n"

private partial def renderOperation (signed : Bool) : Operation → String
  | .literal destination value =>
      s!"    (local.set $t{destination} (i64.const {value.toNat}))\n"
  | .stateLoad destination fieldIndex =>
      s!"    (local.set $t{destination} (global.get $g_state_{fieldIndex}))\n"
  | .unixTimeSeconds destination =>
      -- CAP-1a: ic0.time is nanoseconds; catalog key is whole Unix seconds.
      s!"    (local.set $t{destination} (i64.div_u (call $ic0_time) (i64.const 1000000000)))\n"
  | .callerPrincipalLen destination =>
      s!"    (local.set $t{destination} (call $pf_load_msg_caller (i32.const {callerScratchOffset})))\n"
  | .callerPrincipalWord destination wordIndex =>
      s!"    (drop (call $pf_load_msg_caller (i32.const {callerScratchOffset})))\n" ++
      s!"    (local.set $t{destination} (i64.load offset={4 + wordIndex * 8} (i32.const {callerScratchOffset})))\n"
  | .principalEq destination lhsTemps rhsTemps =>
      renderPrincipalCompare destination false lhsTemps rhsTemps
  | .principalNe destination lhsTemps rhsTemps =>
      renderPrincipalCompare destination true lhsTemps rhsTemps
  | .checkedAdd destination lhs rhs =>
      if signed then
        renderSignedAddTrap destination lhs rhs
      else
        s!"    (local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"    (if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      if signed then
        renderSignedSubTrap destination lhs rhs
      else
        s!"    (if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMul destination lhs rhs =>
      if signed then
        s!"    (local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"    (if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (local.get $t{lhs}) (i64.const -1)) (then (if (i64.ne (i64.div_s (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))))\n"
      else
        s!"    (local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"    (if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (i64.div_u (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))\n"
  | .checkedDiv destination lhs rhs =>
      if signed then
        s!"    (if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (if (i64.eq (local.get $t{lhs}) (i64.const -9223372036854775808)) (then (if (i64.eq (local.get $t{rhs}) (i64.const -1)) (then unreachable))))\n" ++
        s!"    (local.set $t{destination} (i64.div_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
      else
        s!"    (if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMod destination lhs rhs =>
      if signed then
        s!"    (if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (local.set $t{destination} (i64.rem_s (local.get $t{lhs}) (local.get $t{rhs})))\n"
      else
        s!"    (if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .storeState fieldIndex value =>
      s!"    (global.set $g_state_{fieldIndex} (local.get $t{value}))\n"
  | .compare destination op lhs rhs =>
      let insn :=
        match op, signed with
        | .eq, _ => "i64.eq"
        | .ne, _ => "i64.ne"
        | .lt, true => "i64.lt_s"
        | .lt, false => "i64.lt_u"
        | .le, true => "i64.le_s"
        | .le, false => "i64.le_u"
        | .gt, true => "i64.gt_s"
        | .gt, false => "i64.gt_u"
        | .ge, true => "i64.ge_s"
        | .ge, false => "i64.ge_u"
      s!"    (local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .boolAnd destination lhs rhs =>
      s!"    (local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"    (local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolNot destination operand =>
      s!"    (local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{operand}))))\n"
  | .ite destination cond t e =>
      s!"    (local.set $t{destination}\n" ++
      s!"      (if (result i64) (i32.eqz (i64.eqz (local.get $t{cond})))\n" ++
      s!"        (then (local.get $t{t}))\n" ++
      s!"        (else (local.get $t{e}))))\n"
  | .assertTrue condition =>
      s!"    (if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .ifThenElse cond thenOps elseOps =>
      let thenW := String.join (thenOps.map (renderOperation signed)).toList
      let elseW := String.join (elseOps.map (renderOperation signed)).toList
      let elseBlock :=
        if elseOps.isEmpty then ""
        else "      (else\n" ++ elseW ++ "      )\n"
      s!"    (if (i32.eqz (i64.eqz (local.get $t{cond})))\n" ++
        "      (then\n" ++ thenW ++ "      )\n" ++ elseBlock ++ "    )\n"

private def renderLocals (tempCount : Nat) : String :=
  if tempCount == 0 then ""
  else
    let names := (List.range tempCount).map (fun i => s!"(local $t{i} i64)")
    "    " ++ String.intercalate " " names ++ "\n"

/-- Copy the incoming Candid message into the argument scratch buffer,
    validate the "DIDL" magic + empty type table + exact per-param opcode
    sequence, then decode integer values into one temp each and Principal
    values into 9 consecutive temps (len + 8 body words). -/
private def renderArgDecodePrologue
    (signed : Bool) (layout : ParamLayout) : String :=
  Id.run do
  let intOpcode := candidIntOpcode signed
  let paramCount := layout.kinds.size
  let mut out := ""
  out := out ++
    s!"    (if (i32.gt_u (call $ic0_msg_arg_data_size) (i32.const {argBufCap})) (then unreachable))\n"
  out := out ++
    s!"    (call $ic0_msg_arg_data_copy (i32.const {argBufOffset}) (i32.const 0) (call $ic0_msg_arg_data_size))\n"
  out := out ++ s!"    (global.set $pf_cursor (i32.const {argBufOffset}))\n"
  out := out ++ "    (call $pf_expect_didl)\n"
  out := out ++ "    (if (i64.ne (call $pf_leb_read) (i64.const 0)) (then unreachable))\n"
  out := out ++
    s!"    (if (i64.ne (call $pf_leb_read) (i64.const {paramCount})) (then unreachable))\n"
  for k in layout.kinds do
    let opcode :=
      match k with
      | .integer => intOpcode
      | .principal => candidPrincipalOpcode
    out := out ++
      s!"    (if (i32.ne (call $pf_read_byte) (i32.const {opcode})) (then unreachable))\n"
  for i in [0:paramCount] do
    match layout.kinds[i]? with
    | some .principal =>
        let base := paramTemp layout i
        out := out ++
          s!"    (local.set $t{base} (call $pf_decode_candid_principal (i32.const {paramScratchOffset})))\n"
        for w in [0:icpPrincipalDataWordCountV1] do
          out := out ++
            s!"    (local.set $t{base + 1 + w} (i64.load offset={4 + w * 8} (i32.const {paramScratchOffset})))\n"
    | _ =>
        let t := paramTemp layout i
        -- Candid nat64/int64 values are little-endian 8 bytes (not LEB128).
        out := out ++
          s!"    (local.set $t{t} (i64.load (global.get $pf_cursor)))\n"
        out := out ++
          "    (global.set $pf_cursor (i32.add (global.get $pf_cursor) (i32.const 8)))\n"
  pure out

/-- Encode the Candid reply ("DIDL" + empty type table + 0/1 integer result)
    and hand it to the host. -/
private def renderReplyEpilogue
    (signed : Bool) (resultKind : ResultKind) (result? : Option Nat)
    (resultTemps : Array Nat) : String :=
  Id.run do
  let mut out := ""
  out := out ++ s!"    (global.set $pf_reply_len (i32.const {replyBufOffset}))\n"
  out := out ++ "    (call $pf_write_didl)\n"
  out := out ++ "    (call $pf_leb_write (i64.const 0))\n"
  match resultKind, resultTemps, result? with
  | .aggregate n, temps, _ =>
      if temps.size == n then
        out := out ++ s!"    (call $pf_leb_write (i64.const {n}))\n"
        let opcode := candidIntOpcode signed
        for _ in [0:n] do
          out := out ++ s!"    (call $pf_write_byte (i32.const {opcode}))\n"
        for temp in temps do
          out := out ++
            s!"    (i64.store (global.get $pf_reply_len) (local.get $t{temp}))\n"
          out := out ++
            "    (global.set $pf_reply_len (i32.add (global.get $pf_reply_len) (i32.const 8)))\n"
      else
        out := out ++ "    (call $pf_leb_write (i64.const 0))\n"
  | _, _, none =>
      out := out ++ "    (call $pf_leb_write (i64.const 0))\n"
  | _, _, some temp =>
      out := out ++ "    (call $pf_leb_write (i64.const 1))\n"
      if resultKind == .bool then
        out := out ++ s!"    (call $pf_write_byte (i32.const {candidBoolOpcode}))\n"
        out := out ++
          s!"    (call $pf_write_byte (i32.wrap_i64 (local.get $t{temp})))\n"
      else
        let opcode := candidIntOpcode signed
        out := out ++ s!"    (call $pf_write_byte (i32.const {opcode}))\n"
        out := out ++ s!"    (i64.store (global.get $pf_reply_len) (local.get $t{temp}))\n"
        out := out ++
          "    (global.set $pf_reply_len (i32.add (global.get $pf_reply_len) (i32.const 8)))\n"
  out := out ++
    s!"    (call $ic0_msg_reply_data_append (i32.const {replyBufOffset}) (i32.sub (global.get $pf_reply_len) (i32.const {replyBufOffset})))\n"
  out := out ++ "    (call $ic0_msg_reply)\n"
  pure out

private def renderMethodFunc
    (signed : Bool) (m : MethodIR) (funcName : String) (emitReply : Bool) :
    String :=
  Id.run do
    let mut out := s!"  (func {funcName}\n"
    out := out ++ renderLocals m.tempCount
    out := out ++ renderArgDecodePrologue signed (makeParamLayout m.paramKinds)
    for op in m.operations do
      out := out ++ renderOperation signed op
    if emitReply then
      out := out ++ renderReplyEpilogue signed m.resultKind m.result? m.resultTemps
    out := out ++ "  )\n"
    pure out

private partial def opUsesUnixTime : Operation → Bool
  | .unixTimeSeconds _ => true
  | .ifThenElse _ thenOps elseOps =>
      thenOps.any opUsesUnixTime || elseOps.any opUsesUnixTime
  | _ => false

private def methodUsesUnixTime (m : MethodIR) : Bool :=
  m.operations.any opUsesUnixTime

private def irUsesUnixTime (ir : IR) : Bool :=
  methodUsesUnixTime ir.initializer ||
    ir.entries.any methodUsesUnixTime ||
    ir.views.any methodUsesUnixTime

private partial def opUsesCaller : Operation → Bool
  | .callerPrincipalLen _ => true
  | .callerPrincipalWord .. => true
  | .ifThenElse _ thenOps elseOps =>
      thenOps.any opUsesCaller || elseOps.any opUsesCaller
  | _ => false

private def methodUsesCaller (m : MethodIR) : Bool :=
  m.operations.any opUsesCaller

private def irUsesCaller (ir : IR) : Bool :=
  methodUsesCaller ir.initializer ||
    ir.entries.any methodUsesCaller ||
    ir.views.any methodUsesCaller

private def methodUsesPrincipalParam (m : MethodIR) : Bool :=
  m.paramKinds.any (· == .principal)

private def irUsesPrincipalParam (ir : IR) : Bool :=
  methodUsesPrincipalParam ir.initializer ||
    ir.entries.any methodUsesPrincipalParam ||
    ir.views.any methodUsesPrincipalParam

private def renderStateGlobals (states : Array StateField) : String := Id.run do
  let mut out := ""
  for i in [0:states.size] do
    let name := match states[i]? with
      | some st => st.name
      | none => "?"
    out := out ++ s!"  (global $g_state_{i} (mut i64) (i64.const 0)) ;; {name}\n"
  pure out

private def renderModule (ir : IR) : String := Id.run do
  let mut out := "(module\n"
  out := out ++
    s!"  ;; Generated by ProofForge V2 (ICP target, profile {codegenProfileString}).\n"
  out := out ++
    "  ;; ICP-2 engineering pilot: MVP heap globals only (no stable-memory\n"
  out := out ++
    (if ir.signedNumeric then
      "  ;; upgrade persistence); Candid int64 (0x79) inline codec\n"
    else
      "  ;; upgrade persistence); Candid nat64-only inline codec\n")
  out := out ++
    "  ;; (type opcode 0x78/0x79 + LE8 values; LEB128 for table/arg counts);\n"
  out := out ++
    "  ;; not formal; PocketIC engineering gate is a separate host-optional lane.\n"
  out := out ++
    "  (import \"ic0\" \"msg_arg_data_size\" (func $ic0_msg_arg_data_size (result i32)))\n"
  out := out ++
    "  (import \"ic0\" \"msg_arg_data_copy\" (func $ic0_msg_arg_data_copy (param i32 i32 i32)))\n"
  out := out ++
    "  (import \"ic0\" \"msg_reply_data_append\" (func $ic0_msg_reply_data_append (param i32 i32)))\n"
  out := out ++
    "  (import \"ic0\" \"msg_reply\" (func $ic0_msg_reply))\n"
  if irUsesUnixTime ir then
    out := out ++
      "  (import \"ic0\" \"time\" (func $ic0_time (result i64)))\n"
  if irUsesCaller ir then
    out := out ++
      "  (import \"ic0\" \"msg_caller_size\" (func $ic0_msg_caller_size (result i32)))\n"
    out := out ++
      "  (import \"ic0\" \"msg_caller_copy\" (func $ic0_msg_caller_copy (param i32 i32 i32)))\n"
  out := out ++ "  (memory (export \"memory\") 1)\n"
  out := out ++ "  (global $pf_cursor (mut i32) (i32.const 0))\n"
  out := out ++ "  (global $pf_reply_len (mut i32) (i32.const 0))\n"
  out := out ++ renderStateGlobals ir.sourcePlan.states
  out := out ++ preludeWat
  if irUsesCaller ir || irUsesPrincipalParam ir then
    out := out ++
      "  (func $pf_zero_principal_scratch (param $dst i32)\n" ++
      "    (i64.store offset=0 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=8 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=16 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=24 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=32 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=40 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=48 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=56 (local.get $dst) (i64.const 0))\n" ++
      "    (i64.store offset=64 (local.get $dst) (i64.const 0))\n" ++
      "  )\n"
  if irUsesCaller ir then
    out := out ++ callerHelperWat
  if irUsesPrincipalParam ir then
    out := out ++ principalDecodeHelperWat
  out := out ++ renderMethodFunc ir.signedNumeric ir.initializer "$canister_init" false
  out := out ++ "  (export \"canister_init\" (func $canister_init))\n"
  for ent in ir.entries do
    let fn := wasmFuncName ent.name
    out := out ++ renderMethodFunc ir.signedNumeric ent fn true
    out := out ++ s!"  (export \"canister_update {ent.name}\" (func {fn}))\n"
  for v in ir.views do
    let fn := wasmFuncName v.name
    out := out ++ renderMethodFunc ir.signedNumeric v fn true
    out := out ++ s!"  (export \"canister_query {v.name}\" (func {fn}))\n"
  out := out ++ ")\n"
  pure out

-- ---------------------------------------------------------------------------
-- Candid `.did` renderer
-- ---------------------------------------------------------------------------

private def candidArgName (signed : Bool) : ParamKind → String
  | .integer => candidIntName signed
  | .principal => "principal"

private def candidArgList (signed : Bool) (kinds : Array ParamKind) : String :=
  String.intercalate ", " (kinds.toList.map (candidArgName signed))

private def renderCandidService (ir : IR) : String := Id.run do
  let signed := ir.signedNumeric
  let mut out := "service : "
  if !ir.sourcePlan.initializer.params.isEmpty then
    out := out ++
      s!"({candidArgList signed ir.sourcePlan.initializer.paramKinds}) "
  out := out ++ "{\n"
  for ent in ir.entries do
    let resultStr : String := match ent.resultKind with
      | .unit => ""
      | .uint64 => "nat64"
      | .int64 => "int64"
      | .bool => "bool"
      | .aggregate n =>
          String.intercalate ", " (List.replicate n (candidIntName signed))
    out := out ++
      s!"  {ent.name} : ({candidArgList signed ent.paramKinds}) -> ({resultStr});\n"
  for v in ir.views do
    let viewRet := match v.resultKind with
      | .bool => "bool"
      | .int64 => "int64"
      | .aggregate n =>
          String.intercalate ", " (List.replicate n (candidIntName signed))
      | _ => candidIntName signed
    out := out ++
      s!"  {v.name} : ({candidArgList signed v.paramKinds}) -> ({viewRet}) query;\n"
  out := out ++ "}\n"
  pure out

-- ---------------------------------------------------------------------------
-- Public capability surface
-- ---------------------------------------------------------------------------

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  pure #[
    {
      path := s!"{ir.sourcePlan.programName}.wat"
      mediaType := "text/plain"
      contents := renderModule ir
    },
    {
      path := s!"{ir.sourcePlan.programName}.did"
      mediaType := "text/plain"
      contents := renderCandidService ir
    }
  ]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  let expected ← lower ir.sourcePlan
  unless expected.signedNumeric == ir.signedNumeric do
    planError "ICP IR signedNumeric diverges from Plan lowering"
  unless expected.initializer == ir.initializer do
    planError "ICP IR initializer diverges from Plan lowering"
  unless expected.entries == ir.entries do
    planError "ICP IR entries diverge from Plan lowering"
  unless expected.views == ir.views do
    planError "ICP IR views diverge from Plan lowering"
  pure ()

/-- Capability-gated public IR entry. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

/-- Capability-gated public materialize entry. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  validateIR ir
  emitFromIR ir

/-- Unit-test IR entry over retained SemanticProgramV1. -/
def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  let plan ← planFromCompiledSemanticV1 compiled
  validatePlan plan
  lower plan

/-- Unit-test materialize entry. -/
def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCompiledSemanticV1 compiled
  validateIR ir
  emitFromIR ir

end ProofForgeV2.Targets.Icp
