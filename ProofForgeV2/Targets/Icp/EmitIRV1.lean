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
* The Candid wire codec here is a minimal inline codec scoped to an
  all-`nat64` argument/result domain (zero or more `nat64` args, zero or one
  `nat64` result; zero-entry type table; type opcode `0x78`; values as
  little-endian 8-byte payloads; LEB128 only for table/arg counts). Finalize
  uses locked `wat2wasm` only; PocketIC is a separate host-optional ICP-3
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
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | storeState (fieldIndex value : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  mode : MethodMode
  resultKind : ResultKind
  paramCount : Nat
  tempCount : Nat
  operations : Array Operation
  result? : Option Nat
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
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

private partial def lowerExpr (next : Nat) : Expr → LoweredExpr
  | .literal value => { operations := #[.literal next value], value := next, next := next + 1 }
  | .param index => { operations := #[], value := index, next := next }
  | .stateLoad fieldIndex =>
      { operations := #[.stateLoad next fieldIndex], value := next, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let l := lowerExpr next lhs
      let r := lowerExpr l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedAdd r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }
  | .checkedSub lhs rhs =>
      let l := lowerExpr next lhs
      let r := lowerExpr l.next rhs
      {
        operations := l.operations ++ r.operations ++ #[.checkedSub r.next l.value r.value]
        value := r.next
        next := r.next + 1
      }

private def lowerBody (paramCount : Nat) (body : Array Statement) :
    Array Operation × Option Nat × Nat := Id.run do
  let mut ops : Array Operation := #[]
  let mut next := paramCount
  let mut result? : Option Nat := none
  for stmt in body do
    match stmt with
    | .store fieldIndex value =>
        let lv := lowerExpr next value
        ops := ops ++ lv.operations ++ #[.storeState fieldIndex lv.value]
        next := lv.next
    | .returnValue value =>
        let lv := lowerExpr next value
        ops := ops ++ lv.operations
        result? := some lv.value
        next := lv.next
    | .returnNone => pure ()
  pure (ops, result?, next)

private def lowerMethod (m : Method) : MethodIR :=
  let (ops, result?, tempCount) := lowerBody m.params.size m.body
  {
    name := m.name
    mode := m.mode
    resultKind := m.resultKind
    paramCount := m.params.size
    tempCount
    operations := ops
    result?
  }

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  pure {
    sourcePlan := plan
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
private def replyBufOffset : Nat := 4096

/-- Candid primitive type opcode for `nat64` (SLEB128 `-8`, single byte
    `0x78`). ICP-2's declared type domain is nat64-only, so every type-code
    slot in the header is this exact byte. -/
private def candidNat64Opcode : Nat := 120

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

private def renderOperation : Operation → String
  | .literal destination value =>
      s!"    (local.set $t{destination} (i64.const {value.toNat}))\n"
  | .stateLoad destination fieldIndex =>
      s!"    (local.set $t{destination} (global.get $g_state_{fieldIndex}))\n"
  | .checkedAdd destination lhs rhs =>
      s!"    (local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
      s!"    (if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      s!"    (if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
      s!"    (local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .storeState fieldIndex value =>
      s!"    (global.set $g_state_{fieldIndex} (local.get $t{value}))\n"

private def renderLocals (tempCount : Nat) : String :=
  if tempCount == 0 then ""
  else
    let names := (List.range tempCount).map (fun i => s!"(local $t{i} i64)")
    "    " ++ String.intercalate " " names ++ "\n"

/-- Copy the incoming Candid message into the argument scratch buffer,
    validate the "DIDL" magic + empty type table + exact `nat64`×paramCount
    argument-type sequence, then decode the values into `t0..t{paramCount-1}`
    in order. -/
private def renderArgDecodePrologue (paramCount : Nat) : String := Id.run do
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
  for _ in [0:paramCount] do
    out := out ++
      s!"    (if (i32.ne (call $pf_read_byte) (i32.const {candidNat64Opcode})) (then unreachable))\n"
  for i in [0:paramCount] do
    -- Candid nat64 values are little-endian 8 bytes (not LEB128).
    out := out ++
      s!"    (local.set $t{i} (i64.load (global.get $pf_cursor)))\n"
    out := out ++
      "    (global.set $pf_cursor (i32.add (global.get $pf_cursor) (i32.const 8)))\n"
  pure out

/-- Encode the Candid reply ("DIDL" + empty type table + 0/1 `nat64` result)
    and hand it to the host. -/
private def renderReplyEpilogue (result? : Option Nat) : String := Id.run do
  let mut out := ""
  out := out ++ s!"    (global.set $pf_reply_len (i32.const {replyBufOffset}))\n"
  out := out ++ "    (call $pf_write_didl)\n"
  out := out ++ "    (call $pf_leb_write (i64.const 0))\n"
  match result? with
  | none =>
      out := out ++ "    (call $pf_leb_write (i64.const 0))\n"
  | some temp =>
      out := out ++ "    (call $pf_leb_write (i64.const 1))\n"
      out := out ++ s!"    (call $pf_write_byte (i32.const {candidNat64Opcode}))\n"
      -- Candid nat64 payload: little-endian 8 bytes at the reply cursor.
      out := out ++ s!"    (i64.store (global.get $pf_reply_len) (local.get $t{temp}))\n"
      out := out ++
        "    (global.set $pf_reply_len (i32.add (global.get $pf_reply_len) (i32.const 8)))\n"
  out := out ++
    s!"    (call $ic0_msg_reply_data_append (i32.const {replyBufOffset}) (i32.sub (global.get $pf_reply_len) (i32.const {replyBufOffset})))\n"
  out := out ++ "    (call $ic0_msg_reply)\n"
  pure out

private def renderMethodFunc (m : MethodIR) (funcName : String) (emitReply : Bool) : String :=
  Id.run do
    let mut out := s!"  (func {funcName}\n"
    out := out ++ renderLocals m.tempCount
    out := out ++ renderArgDecodePrologue m.paramCount
    for op in m.operations do
      out := out ++ renderOperation op
    if emitReply then
      out := out ++ renderReplyEpilogue m.result?
    out := out ++ "  )\n"
    pure out

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
    "  ;; upgrade persistence); Candid nat64-only inline codec (type opcode\n"
  out := out ++
    "  ;; 0x78 + LE8 values; LEB128 for table/arg counts; no compound types);\n"
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
  out := out ++ "  (memory (export \"memory\") 1)\n"
  out := out ++ "  (global $pf_cursor (mut i32) (i32.const 0))\n"
  out := out ++ "  (global $pf_reply_len (mut i32) (i32.const 0))\n"
  out := out ++ renderStateGlobals ir.sourcePlan.states
  out := out ++ preludeWat
  out := out ++ renderMethodFunc ir.initializer "$canister_init" false
  out := out ++ "  (export \"canister_init\" (func $canister_init))\n"
  for ent in ir.entries do
    let fn := wasmFuncName ent.name
    out := out ++ renderMethodFunc ent fn true
    out := out ++ s!"  (export \"canister_update {ent.name}\" (func {fn}))\n"
  for v in ir.views do
    let fn := wasmFuncName v.name
    out := out ++ renderMethodFunc v fn true
    out := out ++ s!"  (export \"canister_query {v.name}\" (func {fn}))\n"
  out := out ++ ")\n"
  pure out

-- ---------------------------------------------------------------------------
-- Candid `.did` renderer
-- ---------------------------------------------------------------------------

private def natArgList (paramCount : Nat) : String :=
  String.intercalate ", " (List.replicate paramCount "nat64")

private def renderCandidService (ir : IR) : String := Id.run do
  let mut out := "service : "
  if !ir.sourcePlan.initializer.params.isEmpty then
    out := out ++ s!"({natArgList ir.sourcePlan.initializer.params.size}) "
  out := out ++ "{\n"
  for ent in ir.entries do
    let resultStr : String := match ent.resultKind with
      | .unit => ""
      | .uint64 => "nat64"
    out := out ++ s!"  {ent.name} : ({natArgList ent.paramCount}) -> ({resultStr});\n"
  for v in ir.views do
    out := out ++ s!"  {v.name} : ({natArgList v.paramCount}) -> (nat64) query;\n"
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
