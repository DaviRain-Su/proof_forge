import ProofForgeV2.Targets.OpenVM.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Targets.Common

/-!
# OpenVM EmitIRV1 — Plan → structured guest IR AST → compilable Rust guest + catalog JSON

IR is a structured Rust guest AST (State struct + init/entry/view functions),
not a raw String template. The renderer is the sole producer of `text/x-rust`
bytes. ADR-0045 O0 + ADR-0046 O1: this base emission (Cargo.toml, openvm.toml,
main.rs) is shared by both profiles and targets an OpenVM-compilable
`no_std`/`no_main` guest shape (`openvm::entry!` + `openvm::io::read` /
`reveal_bytes32`). The default `openvm-guest-source-v1` profile finalizes
zero-tool; the opt-in `openvm-guest-elf-v1` profile (ADR-0046) may build and
transpile this guest with locked `cargo-openvm`. Neither profile invokes
keygen, execute, or any prove/verify toolchain. Overflow/underflow use native
Rust `checked_add`/`checked_sub` on `u64` (unsigned) or `i64` (homogeneous
signed domain); bare assert and zero-payload declared revert become early
`Err` returns.
-/

namespace ProofForgeV2.Targets.OpenVM

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .openvm message

-- ---------------------------------------------------------------------------
-- Structured Rust guest IR AST
-- ---------------------------------------------------------------------------

inductive RCmpOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive RExpr where
  | litU64 (value : UInt64)
  | litBool (value : Bool)
  | name (id : String)
  /-- `(lhs).checked_add(rhs).ok_or(errCode)?` -/
  | checkedAdd (lhs rhs : RExpr) (errCode : Nat)
  /-- `(lhs).checked_sub(rhs).ok_or(errCode)?` -/
  | checkedSub (lhs rhs : RExpr) (errCode : Nat)
  | checkedMul (lhs rhs : RExpr) (errCode : Nat)
  | checkedDiv (lhs rhs : RExpr) (errCode : Nat)
  | checkedMod (lhs rhs : RExpr) (errCode : Nat)
  | compareOp (op : RCmpOp) (lhs rhs : RExpr)
  | boolAnd (lhs rhs : RExpr)
  | boolOr (lhs rhs : RExpr)
  | boolNot (operand : RExpr)
  /-- Dense Map mux: `if cond { t } else { e }`. -/
  | ite (cond t e : RExpr)
  | okUnit
  | okValue (value : RExpr)
  /-- View-only flattened return: guest tuple of u64/i64 leaves. -/
  | tuple (elems : Array RExpr)
  deriving BEq, Inhabited, Repr

inductive RStmt where
  /-- `if !(cond) { return Err(errCode); }` -/
  | guard (cond : RExpr) (errCode : Nat)
  /-- `state.{field} = {value};` -/
  | storeField (field : String) (value : RExpr)
  /-- Trailing expression (last line, no semicolon / no `return`). -/
  | tail (value : RExpr)
  /-- Terminal-revert path: prior guard(s) always return before this line. -/
  | unreachableAfterRevert
  deriving BEq, Inhabited, Repr

inductive StateAccess where
  | none_
  | ref
  | refMut
  deriving BEq, Inhabited, Repr

structure RustFn where
  name : String
  /-- Scalar params render as `u64` or `i64` from `IR.signedNumeric`.
      Bool params remain outside O0. -/
  params : Array String
  stateAccess : StateAccess
  isInit : Bool := false
  retType : String
  stmts : Array RStmt
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  signedNumeric : Bool
  stateFields : Array String
  initFn : RustFn
  entryFns : Array RustFn
  viewFns : Array RustFn
  deriving BEq, Inhabited, Repr

private def numericRustType (signed : Bool) : String :=
  if signed then "i64" else "u64"

-- ---------------------------------------------------------------------------
-- Plan Expr → RExpr
-- ---------------------------------------------------------------------------

private def stateFieldName (plan : Plan) (fieldIndex : Nat) : CompileResult String := do
  match plan.states[fieldIndex]? with
  | some st => pure st.name
  | none => planError "OpenVM IR state field index out of range"

private def paramVar (params : Array String) (index : Nat) : CompileResult String := do
  match params[index]? with
  | some n => pure n
  | none => planError "OpenVM IR parameter index out of range"

private partial def lowerExprToRExpr
    (plan : Plan) (params : Array String) (e : Expr) : CompileResult RExpr := do
  match e with
  | .litU64 v => pure (.litU64 v)
  | .litBool b => pure (.litBool b)
  | .param i => do
      let n ← paramVar params i
      pure (.name n)
  | .stateLoad fi => do
      let n ← stateFieldName plan fi
      pure (.name s!"state.{n}")
  | .arith .add l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedAdd rl rr FailureKind.overflow.code)
  | .arith .sub l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      -- Signed sub overflow (`i64::MIN - 1`) is overflow, not unsigned underflow.
      let code :=
        if plan.signedNumeric then FailureKind.overflow.code
        else FailureKind.underflow.code
      pure (.checkedSub rl rr code)
  | .arith .mul l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedMul rl rr FailureKind.overflow.code)
  | .arith .div l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedDiv rl rr FailureKind.divByZero.code)
  | .arith .mod l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.checkedMod rl rr FailureKind.divByZero.code)
  | .compare op l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      let rop : RCmpOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
      pure (.compareOp rop rl rr)
  | .boolAnd l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.boolAnd rl rr)
  | .boolOr l r => do
      let rl ← lowerExprToRExpr plan params l
      let rr ← lowerExprToRExpr plan params r
      pure (.boolOr rl rr)
  | .boolNot o => do
      let ro ← lowerExprToRExpr plan params o
      pure (.boolNot ro)
  | .ite c t e => do
      let rc ← lowerExprToRExpr plan params c
      let rt ← lowerExprToRExpr plan params t
      let re ← lowerExprToRExpr plan params e
      pure (.ite rc rt re)

/-- Arith overflow/underflow is already encoded in `checked_*` and must not
    also become a redundant guard. Dense Map cap-8 upsert uses `.overflow`
    with a Bool or-tree and must stay an explicit guard. Div-by-zero,
    assertion, declared-revert, and terminal markers stay as early-return
    guards. -/
private def isMapCapacityOverflowCond : Expr → Bool
  | .boolOr _ _ | .boolAnd _ _ | .boolNot _ | .ite _ _ _ => true
  | _ => false

private def guardChecksOf (checks : Array Check) : Array Check :=
  checks.filter fun ck =>
    match ck.kind with
    | .overflow => isMapCapacityOverflowCond ck.condition
    | .underflow => false
    | .divByZero => true
    | .assertion | .declaredRevert _ | .terminalRevert _ => true

private def resultRustType (rk : ResultKind) (leafIsInt : Array Bool := #[]) : String :=
  match rk with
  | .unit => "()"
  | .uint64 => "u64"
  | .int64 => "i64"
  | .bool => "bool"
  | .aggregate n =>
      let tys :=
        (List.range n).map (fun i =>
          if leafIsInt[i]?.getD false then "i64" else "u64")
      "(" ++ String.intercalate ", " tys ++ ")"

private def buildEntryFn (plan : Plan) (ent : PlanEntry) : CompileResult RustFn := do
  let mut stmts : Array RStmt := #[]
  for ck in guardChecksOf ent.checks do
    let rc ← lowerExprToRExpr plan ent.params ck.condition
    stmts := stmts.push (.guard rc ck.kind.code)
  for (fi, e) in ent.stores do
    let fieldName ← stateFieldName plan fi
    let re ← lowerExprToRExpr plan ent.params e
    stmts := stmts.push (.storeField fieldName re)
  if ent.terminalRevert then
    stmts := stmts.push .unreachableAfterRevert
  else
    match ent.result? with
    | none => stmts := stmts.push (.tail .okUnit)
    | some e =>
        let re ← lowerExprToRExpr plan ent.params e
        stmts := stmts.push (.tail (.okValue re))
  pure {
    name := ent.name
    params := ent.params
    stateAccess := .refMut
    retType := s!"Result<{resultRustType ent.resultKind}, u32>"
    stmts
  }

private def buildViewFn (plan : Plan) (v : PlanView) : CompileResult RustFn := do
  let re ← match v.resultKind with
    | .aggregate n => do
        let src := if v.leaves.isEmpty then #[v.value] else v.leaves
        unless src.size == n do
          planError
            s!"OpenVM view '{v.name}' aggregate emit leaf count must be {n}"
        let mut elems : Array RExpr := #[]
        for e in src do
          elems := elems.push (← lowerExprToRExpr plan v.params e)
        pure (RExpr.tuple elems)
    | _ =>
        lowerExprToRExpr plan v.params v.value
  pure {
    name := v.name
    params := v.params
    stateAccess := .ref
    retType := resultRustType v.resultKind v.leafIsInt
    stmts := #[.tail re]
  }

private def buildInitFn (plan : Plan) : CompileResult RustFn := do
  match plan.initializer with
  | some init => do
      let mut stmts : Array RStmt := #[]
      for (fi, e) in init.stores do
        let fieldName ← stateFieldName plan fi
        let re ← lowerExprToRExpr plan init.params e
        stmts := stmts.push (.storeField fieldName re)
      stmts := stmts.push (.tail (.name "state"))
      pure {
        name := init.name
        params := init.params
        stateAccess := .none_
        isInit := true
        retType := "State"
        stmts
      }
  | none =>
      pure {
        name := "init"
        params := #[]
        stateAccess := .none_
        isInit := true
        retType := "State"
        stmts := #[.tail (.name "State::default()")]
      }

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let stateFields := plan.states.map (·.name)
  let initFn ← buildInitFn plan
  let mut entryFns : Array RustFn := #[]
  for ent in plan.entries do
    entryFns := entryFns.push (← buildEntryFn plan ent)
  let mut viewFns : Array RustFn := #[]
  for v in plan.views do
    viewFns := viewFns.push (← buildViewFn plan v)
  pure {
    sourcePlan := plan
    signedNumeric := plan.signedNumeric
    stateFields, initFn, entryFns, viewFns
  }

-- ---------------------------------------------------------------------------
-- Rust renderer
-- ---------------------------------------------------------------------------

private def cmpSym : RCmpOp → String
  | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="

private partial def renderRExpr (signed : Bool) : RExpr → String
  | .litU64 v =>
      if signed then s!"({v}u64 as i64)" else s!"{v}u64"
  | .litBool true => "true"
  | .litBool false => "false"
  | .name id => id
  | .checkedAdd l r code =>
      s!"({renderRExpr signed l}).checked_add({renderRExpr signed r}).ok_or({code}u32)?"
  | .checkedSub l r code =>
      s!"({renderRExpr signed l}).checked_sub({renderRExpr signed r}).ok_or({code}u32)?"
  | .checkedMul l r code =>
      s!"({renderRExpr signed l}).checked_mul({renderRExpr signed r}).ok_or({code}u32)?"
  | .checkedDiv l r code =>
      s!"({renderRExpr signed l}).checked_div({renderRExpr signed r}).ok_or({code}u32)?"
  | .checkedMod l r code =>
      s!"({renderRExpr signed l}).checked_rem({renderRExpr signed r}).ok_or({code}u32)?"
  | .compareOp op l r =>
      s!"({renderRExpr signed l} {cmpSym op} {renderRExpr signed r})"
  | .boolAnd l r => s!"({renderRExpr signed l} && {renderRExpr signed r})"
  | .boolOr l r => s!"({renderRExpr signed l} || {renderRExpr signed r})"
  | .boolNot o => s!"(!{renderRExpr signed o})"
  | .ite c t e =>
      s!"(if {renderRExpr signed c} \{ {renderRExpr signed t} } else \{ {renderRExpr signed e} })"
  | .okUnit => "Ok(())"
  | .okValue v => s!"Ok({renderRExpr signed v})"
  | .tuple elems =>
      let inner := String.intercalate ", " (elems.map (renderRExpr signed)).toList
      "(" ++ inner ++ ")"

private def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

private def renderStmt (signed : Bool) (level : Nat) : RStmt → String
  | .guard cond code =>
      indent level s!"if !({renderRExpr signed cond}) \{ return Err({code}u32); }"
  | .storeField field value =>
      indent level s!"state.{field} = {renderRExpr signed value};"
  | .tail value =>
      indent level (renderRExpr signed value)
  | .unreachableAfterRevert =>
      indent level
        "unreachable!(\"O0 template: a prior guard always returns before this point\")"

private def paramsSig (signed : Bool) (fn : RustFn) : String :=
  let ty := numericRustType signed
  let base := fn.params.map (fun p => s!"{p}: {ty}")
  let withState :=
    match fn.stateAccess with
    | .none_ => base
    | .ref => #["state: &State"] ++ base
    | .refMut => #["state: &mut State"] ++ base
  String.intercalate ", " withState.toList

private def renderFn (signed : Bool) (fn : RustFn) : Array String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push s!"pub fn {fn.name}({paramsSig signed fn}) -> {fn.retType} \{"
  if fn.isInit then
    lines := lines.push (indent 4 "let mut state = State::default();")
  for stmt in fn.stmts do
    lines := lines.push (renderStmt signed 4 stmt)
  lines := lines.push "}"
  pure lines

/-- Flattened `Array UInt64 N`, `Option UInt64`, and dense Map UInt64
    cap-8 leaves arrive as ordinary scalar names (`slots_0`, `o_tag`,
    `o_p0`, `m_0`..`m_23`). The template never emits `[u64; N]`, `Vec`,
    Rust `Option<u64>`, `HashMap`, or `std::collections`. -/
private def renderState (signed : Bool) (fields : Array String) : Array String := Id.run do
  let ty := numericRustType signed
  let mut lines : Array String :=
    #["#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]", "pub struct State {"]
  for f in fields do
    lines := lines.push (indent 4 s!"pub {f}: {ty},")
  lines := lines.push "}"
  pure lines

/-- `let {p}: u64|i64 = openvm::io::read();` — O0 scalar params follow the
    homogeneous numeric domain. -/
private def readParamStmt (signed : Bool) (p : String) : String :=
  indent 4 s!"let {p}: {numericRustType signed} = openvm::io::read();"

private def callArgsList (leading params : Array String) : String :=
  String.intercalate ", " (leading ++ params).toList

/-- `Ok(...) => (1u8, <value as u64>)` match arm, shaped by the first entry's
    actual `ResultKind` so `main` type-checks regardless of Unit/UInt64/Bool. -/
private def okOutcomeArm : ResultKind → String
  | .unit => "Ok(()) => (1u8, 0u64)"
  | .uint64 => "Ok(v) => (1u8, v)"
  | .int64 => "Ok(v) => (1u8, v as u64)"
  | .bool => "Ok(v) => (1u8, if v { 1u64 } else { 0u64 })"
  | .aggregate _ => "Ok(_) => (1u8, 0u64)"

/-- Deterministic `main` body: read init params, construct state, read the
    first entry's params, dispatch it, and reveal a single `[u8; 32]` outcome
    (`byte0`=1 ok/0 err, `bytes[1..9]`=LE value-or-errCode as u64). Plan
    validation guarantees at least one entry, so `entryFn`/`resultKind` are
    always available at this call site. -/
private def renderMainBody (signed : Bool) (initFn entryFn : RustFn)
    (resultKind : ResultKind) : Array String := Id.run do
  let mut lines : Array String := #[]
  for p in initFn.params do
    lines := lines.push (readParamStmt signed p)
  lines := lines.push (indent 4 s!"let mut state = {initFn.name}({callArgsList #[] initFn.params});")
  for p in entryFn.params do
    lines := lines.push (readParamStmt signed p)
  let callArgs := callArgsList #["&mut state"] entryFn.params
  lines := lines.push (indent 4 s!"let (ok, value): (u8, u64) = match {entryFn.name}({callArgs}) \{")
  lines := lines.push (indent 8 s!"{okOutcomeArm resultKind},")
  lines := lines.push (indent 8 "Err(code) => (0u8, code as u64),")
  lines := lines.push (indent 4 "};")
  lines := lines.push (indent 4 "let mut public_output = [0u8; 32];")
  lines := lines.push (indent 4 "public_output[0] = ok;")
  lines := lines.push (indent 4 "public_output[1..9].copy_from_slice(&value.to_le_bytes());")
  lines := lines.push (indent 4 "openvm::io::reveal_bytes32(public_output);")
  pure lines

private def renderMainRs (ir : IR) : String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push
    s!"// Generated by proof-forge-next (OpenVM target, {codegenProfileString})."
  lines := lines.push
    "// ADR-0045 O0 + ADR-0046 O1: this guest source/state-transition surface is"
  lines := lines.push
    "// shared by both profiles. Default finalize is zero-tool; the opt-in"
  lines := lines.push
    "// openvm-guest-elf-v1 profile may build+transpile this guest with locked"
  lines := lines.push
    "// cargo-openvm. No keygen, execute, or prove/verify toolchain is invoked by"
  lines := lines.push
    "// product materialization or finalization."
  lines := lines.push ""
  lines := lines.push "#![no_main]"
  lines := lines.push "#![no_std]"
  lines := lines.push ""
  lines := lines.push "openvm::entry!(main);"
  lines := lines.push ""
  let signed := ir.signedNumeric
  lines := lines ++ renderState signed ir.stateFields
  lines := lines.push ""
  lines := lines ++ renderFn signed ir.initFn
  for fn in ir.entryFns do
    lines := lines.push ""
    lines := lines ++ renderFn signed fn
  for fn in ir.viewFns do
    lines := lines.push ""
    lines := lines ++ renderFn signed fn
  lines := lines.push ""
  lines := lines.push "fn main() {"
  match ir.entryFns[0]?, ir.sourcePlan.entries[0]? with
  | some entryFn, some planEntry =>
      lines := lines ++ renderMainBody signed ir.initFn entryFn planEntry.resultKind
  | _, _ =>
      match ir.viewFns[0]?, ir.sourcePlan.views[0]? with
      | some viewFn, some planView =>
          for p in ir.initFn.params do
            lines := lines.push (readParamStmt signed p)
          lines := lines.push
            (indent 4 s!"let mut state = {ir.initFn.name}({callArgsList #[] ir.initFn.params});")
          for p in viewFn.params do
            lines := lines.push (readParamStmt signed p)
          let callArgs := callArgsList #["&state"] viewFn.params
          let n :=
            match planView.resultKind with
            | .aggregate k => k
            | _ => 1
          if n == 1 then
            lines := lines.push
              (indent 4 s!"let v0 = {viewFn.name}({callArgs});")
          else
            let binds := String.intercalate ", "
              ((List.range n).map (fun i => s!"v{i}"))
            lines := lines.push
              (indent 4 s!"let ({binds}) = {viewFn.name}({callArgs});")
          lines := lines.push (indent 4 "let mut public_output = [0u8; 32];")
          lines := lines.push (indent 4 "public_output[0] = 1;")
          for i in [0:n] do
            let off := 1 + 8 * i
            if off + 8 ≤ 32 then
              let cast :=
                if planView.leafIsInt[i]?.getD false then s!"(v{i} as u64)" else s!"v{i}"
              lines := lines.push
                (indent 4 s!"public_output[{off}..{off+8}].copy_from_slice(&{cast}.to_le_bytes());")
          lines := lines.push (indent 4 "openvm::io::reveal_bytes32(public_output);")
      | _, _ =>
          lines := lines.push
            (indent 4 "// unreachable: OpenVM Plan validation requires an entry or view")
  lines := lines.push "}"
  lines := lines.push ""
  pure (String.intercalate "\n" lines.toList)

-- ---------------------------------------------------------------------------
-- Cargo.toml + catalog JSON
-- ---------------------------------------------------------------------------

/-- Frozen `openvm` guest crate version pin (ADR-0046; exact match with the
    locked `cargo-openvm` 2.0.1 CLI used by the opt-in elf profile). Declared
    text only for the default source profile — no crates.io/registry fetch,
    no cargo build. -/
def openvmVersionV1 : String := "=2.0.1"

private def renderCargoToml (plan : Plan) : String :=
  "[package]\n" ++
  s!"name = \"pf-openvm-guest-{plan.programName}\"\n" ++
  "version = \"0.1.0\"\n" ++
  "edition = \"2021\"\n" ++
  "\n" ++
  "[dependencies]\n" ++
  s!"openvm = \"{openvmVersionV1}\"\n"

/-- Minimal OpenVM VM extension config (ADR-0046): RV32I/RV32M base ISA + io
    extension only. Matches `cargo openvm init`'s default `openvm.toml`. -/
private def renderOpenvmToml : String :=
  "[app_vm_config.rv32i]\n[app_vm_config.rv32m]\n[app_vm_config.io]\n"

private def jsonStringArray (values : Array String) : String :=
  "[" ++ String.intercalate ","
    ((values.map (fun v => "\"" ++ Targets.escapeJson v ++ "\"")).toList) ++ "]"

private def catalogFileList : Array String :=
  #["guest/Cargo.toml", "guest/openvm.toml", "guest/src/main.rs"]

private def renderCatalog (plan : Plan) : String :=
  "{\n" ++
  "  \"schema\": \"proof-forge.openvm-guest.v1\",\n" ++
  s!"  \"profile\": \"{Targets.escapeJson plan.profile}\",\n" ++
  "  \"artifactKind\": \"source-only\",\n" ++
  "  \"proofStatus\": \"not-produced\",\n" ++
  s!"  \"programName\": \"{Targets.escapeJson plan.programName}\",\n" ++
  s!"  \"sourceHash\": \"{Targets.escapeJson plan.sourceHash}\",\n" ++
  s!"  \"semanticHash\": \"{Targets.escapeJson plan.semanticHash}\",\n" ++
  s!"  \"vmConfig\": \"{Targets.escapeJson plan.vmConfig}\",\n" ++
  "  \"enabledExtensions\": [],\n" ++
  "  \"executableCommitment\": null,\n" ++
  "  \"proofMode\": null,\n" ++
  "  \"verifierBinding\": null,\n" ++
  s!"  \"files\": {jsonStringArray catalogFileList}\n" ++
  "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  pure #[
    { path := "guest/Cargo.toml"
      mediaType := "text/x-toml"
      contents := renderCargoToml ir.sourcePlan },
    { path := "guest/openvm.toml"
      mediaType := "text/x-toml"
      contents := renderOpenvmToml },
    { path := "guest/src/main.rs"
      mediaType := "text/x-rust"
      contents := renderMainRs ir },
    { path := s!"{ir.sourcePlan.programName}.openvm-guest.json"
      mediaType := "application/json"
      contents := renderCatalog ir.sourcePlan }
  ]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.signedNumeric == ir.sourcePlan.signedNumeric do
    planError "OpenVM IR signedNumeric diverges from Plan lowering"

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

end ProofForgeV2.Targets.OpenVM
