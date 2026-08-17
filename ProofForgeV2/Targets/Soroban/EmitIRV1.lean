import ProofForgeV2.Targets.Soroban.ValidatePlanV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Soroban EmitIRV1 — Plan → structured IR AST → `.rs` Rust source

IR is a structured Soroban Rust AST (not String). The renderer is the sole
producer of `text/x-rust` bytes. Soroban S0 source recipe; not a deployable
Wasm claim; zero-tool finalize.
-/

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.EnvelopeV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .soroban message

-- ---------------------------------------------------------------------------
-- Structured Soroban Rust IR AST
-- ---------------------------------------------------------------------------

inductive RBinOp where
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or
  deriving BEq, Inhabited, Repr

inductive RUnaryOp where
  | not
  deriving BEq, Inhabited, Repr

inductive RExpr where
  | name (id : String)
  | u64Lit (value : String)
  | boolLit (value : Bool)
  | binary (op : RBinOp) (lhs rhs : RExpr)
  | unary (op : RUnaryOp) (operand : RExpr)
  | checkedArith (method : String) (receiver arg : RExpr) (panicMsg : String)
  | storageGet (key : String)
  | storageSet (key : String) (value : RExpr)
  /-- CAP-3: `env.ledger().timestamp()` (u64 Unix seconds). -/
  | ledgerTimestamp
  /-- CAP-3: `u64::from(env.ledger().sequence())` (u32 → u64). -/
  | ledgerSequence
  /-- CAP-4: 32-byte `soroban_sdk::Bytes` from four Semantic UInt256 LE limbs. -/
  | bytesFromU64LimbsLe (l0 l1 l2 l3 : RExpr)
  /-- CAP-4: `env.crypto().sha256(&bytes)`. -/
  | cryptoSha256 (bytes : RExpr)
  /-- CAP-4: one LE u64 limb of a `Hash<32>` / `BytesN<32>` digest. -/
  | u64LimbFromHashLe (hash : RExpr) (limbIndex : Nat)
  | ifExpr (cond thenE elseE : RExpr)
  | panic (msg : String)
  | unit
  /-- View-only flattened return: Rust tuple of u64/i64. -/
  | tuple (elems : Array RExpr)
  deriving BEq, Inhabited, Repr

inductive RStatement where
  | letBind (name : String) (value : RExpr)
  | expr (value : RExpr)
  | returnExpr (value : RExpr)
  | ifThenElse (cond : RExpr) (thenBody elseBody : Array RStatement)
  deriving BEq, Inhabited, Repr

structure RFn where
  name : String
  params : Array (String × String)
  returnType : Option String
  body : Array RStatement
  deriving BEq, Inhabited, Repr

structure RContract where
  contractName : String
  fns : Array RFn
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  contract : RContract
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Plan Expr → RExpr
-- ---------------------------------------------------------------------------

/-- Instance keys go through `symbol_short!` (≤ 9 UTF-8 bytes). Never
    truncate: a 10+ byte flattened leaf must fail closed with a named
    diagnostic. `slots_0`..`slots_7` fit; `abcdefghij_0` does not. -/
private def stateKey (plan : Plan) (fieldIndex : Nat) : CompileResult String := do
  match plan.states[fieldIndex]? with
  | some st =>
      let key := st.name
      unless key.toUTF8.size ≤ 9 do
        planError
          s!"unsupported Soroban semantic shape: instance key '{key}' exceeds symbol_short! 9-byte limit"
      pure key
  | none => planError "Soroban IR state field index out of range"

private def paramName (_params : Array String) (index : Nat) : CompileResult String := do
  match _params[index]? with
  | some n => pure n
  | none => planError "Soroban IR parameter index out of range"

/-- Complete Rust numeric token. Unsigned stays `{n}_u64`. Signed uses the
    UInt64 two's-complement bit pattern as `i64` (special-case `i64::MIN`). -/
private def rustNumericLit (signed : Bool) (v : UInt64) : String :=
  if !signed then
    s!"{v.toNat}_u64"
  else
    let n := v.toNat
    if n < 9223372036854775808 then
      s!"{n}_i64"
    else if n == 9223372036854775808 then
      "i64::MIN"
    else
      let mag := (0 - v).toNat
      s!"-{mag}_i64"

private def rustZeroLit (signed : Bool) : String :=
  if signed then "0_i64" else "0_u64"

private def rustNumericTy (signed : Bool) : String :=
  if signed then "i64" else "u64"

private partial def lowerExpr
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (e : Expr) : CompileResult RExpr := do
  let signed := plan.signedNumeric
  match e with
  | .litU64 v => pure (.u64Lit (rustNumericLit signed v))
  | .litBool b => pure (.boolLit b)
  | .param i => do
      let n ← paramName params i
      pure (.name n)
  | .stateLoad fi => do
      match stateLocals[fi]? with
      | some n => pure (.name n)
      | none => do
          let key ← stateKey plan fi
          pure (.storageGet key)
  | .unixTimeSeconds => pure .ledgerTimestamp
  | .blockHeight => pure .ledgerSequence
  | .sha256Limb siteIndex limbIndex =>
      unless limbIndex < 4 do
        planError "Soroban IR sha256 limb index must be 0..3"
      pure (.name s!"pf_sha256_{siteIndex}_l{limbIndex}")
  | .arith op l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      match op with
      | .add => pure (.checkedArith "checked_add" rl rr "overflow")
      | .sub =>
          let msg := if signed then "overflow" else "underflow"
          pure (.checkedArith "checked_sub" rl rr msg)
      | .mul => pure (.checkedArith "checked_mul" rl rr "overflow")
      | .div =>
          let zero := .u64Lit (rustZeroLit signed)
          let nz : RExpr := .binary .ne rr zero
          let cond : RExpr :=
            if signed then
              .binary .and nz
                (.unary .not
                  (.binary .and
                    (.binary .eq rl (.u64Lit "i64::MIN"))
                    (.binary .eq rr (.u64Lit "-1_i64"))))
            else
              nz
          pure (.ifExpr cond (.binary .div rl rr) (.panic "division by zero"))
      | .mod =>
          pure (.ifExpr
            (.binary .ne rr (.u64Lit (rustZeroLit signed)))
            (.binary .mod rl rr)
            (.panic "division by zero"))
  | .compare op l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      let rop : RBinOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
      pure (.binary rop rl rr)
  | .boolAnd l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      pure (.binary .and rl rr)
  | .boolOr l r => do
      let rl ← lowerExpr plan params stateLocals l
      let rr ← lowerExpr plan params stateLocals r
      pure (.binary .or rl rr)
  | .boolNot o => do
      let ro ← lowerExpr plan params stateLocals o
      pure (.unary .not ro)
  | .ite cond t e => do
      let rc ← lowerExpr plan params stateLocals cond
      let rt ← lowerExpr plan params stateLocals t
      let re ← lowerExpr plan params stateLocals e
      pure (.ifExpr rc rt re)

/-- Arith overflow/underflow is already encoded in `checked_add`/`checked_sub`.
    Dense Map cap-8 upsert uses `.overflow` with a Bool or-tree and must stay
    an explicit guard. -/
private def isMapCapacityOverflowCond : Expr → Bool
  | .boolOr _ _ | .boolAnd _ _ | .boolNot _ | .ite _ _ _ => true
  | _ => false

private def emitAssertChecks
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (checks : Array Check) :
    CompileResult (Array RStatement) := do
  let mut stmts : Array RStatement := #[]
  for ck in checks do
    -- Overflow/underflow/divZero from checked_* / guarded arith stay
    -- skipped. Map cap-8 `okInsert` is a Bool/ite tree and is emitted.
    match ck.kind with
    | .underflow | .divByZero => pure ()
    | .overflow =>
        if isMapCapacityOverflowCond ck.condition then
          let cond ← lowerExpr plan params stateLocals ck.condition
          stmts := stmts.push
            (.expr (.ifExpr (.unary .not cond) (.panic "overflow") .unit))
        else
          pure ()
    | .assertion | .declaredRevert _ | .terminalRevert _ => do
        let cond ← lowerExpr plan params stateLocals ck.condition
        let msg := match ck.kind with
          | .assertion => "assertion failed"
          | .declaredRevert idx => s!"revert({idx})"
          | .terminalRevert idx => s!"revert({idx})"
          | _ => "failure"
        stmts := stmts.push (.expr (.ifExpr (.unary .not cond) (.panic msg) .unit))
  pure stmts

private def emitStores
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (stores : Array (Nat × Expr)) :
    CompileResult (Array RStatement) := do
  let mut stmts : Array RStatement := #[]
  for (fi, e) in stores do
    let key ← stateKey plan fi
    let re ← lowerExpr plan params stateLocals e
    stmts := stmts.push (.expr (.storageSet key re))
  pure stmts

/-- CAP-4: emit each sha256 site as Bytes←4×u64 LE, `env.crypto().sha256`,
    then four LE result limbs. Limb packing is always unsigned. -/
private def emitSha256Sites
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (sites : Array Sha256Site) :
    CompileResult (Array RStatement) := do
  let unsignedPlan := { plan with signedNumeric := false }
  let mut stmts : Array RStatement := #[]
  for i in [0:sites.size] do
    let some site := sites[i]? |
      planError "Soroban IR sha256 site index out of range"
    let r0 ← lowerExpr unsignedPlan params stateLocals site.input0
    let r1 ← lowerExpr unsignedPlan params stateLocals site.input1
    let r2 ← lowerExpr unsignedPlan params stateLocals site.input2
    let r3 ← lowerExpr unsignedPlan params stateLocals site.input3
    let bytesName := s!"pf_sha256_{i}_bytes"
    let digestName := s!"pf_sha256_{i}_digest"
    stmts := stmts.push (.letBind bytesName (.bytesFromU64LimbsLe r0 r1 r2 r3))
    stmts := stmts.push (.letBind digestName (.cryptoSha256 (.name bytesName)))
    for limb in [0:4] do
      stmts := stmts.push
        (.letBind s!"pf_sha256_{i}_l{limb}"
          (.u64LimbFromHashLe (.name digestName) limb))
  pure stmts

private partial def emitPlanStatements
    (plan : Plan) (params : Array String) (stateLocals : Array String)
    (stmts : Array Statement) : CompileResult (Array RStatement) := do
  let mut out : Array RStatement := #[]
  for stmt in stmts do
    match stmt with
    | .store fi e =>
        let key ← stateKey plan fi
        let re ← lowerExpr plan params stateLocals e
        out := out.push (.expr (.storageSet key re))
    | .ifThenElse cond thenBody elseBody =>
        let c ← lowerExpr plan params stateLocals cond
        let t ← emitPlanStatements plan params stateLocals thenBody
        let e ← emitPlanStatements plan params stateLocals elseBody
        out := out.push (.ifThenElse c t e)
    | .switchOn scrut cases defaultBody =>
        let folded : Array Statement :=
          cases.foldr
            (fun (v, body) acc =>
              #[.ifThenElse (.compare .eq scrut (.litU64 v)) body acc])
            defaultBody
        let sw ← emitPlanStatements plan params stateLocals folded
        out := out ++ sw
    | .returnValue e =>
        let re ← lowerExpr plan params stateLocals e
        out := out.push (.returnExpr re)
    | .returnAggregate leaves =>
        let mut elems : Array RExpr := #[]
        for e in leaves do
          elems := elems.push (← lowerExpr plan params stateLocals e)
        out := out.push (.returnExpr (RExpr.tuple elems))
    | .returnNone =>
        out := out.push (.returnExpr .unit)
  pure out

private def resultTypeStr (rk : ResultKind) (leafIsInt : Array Bool) : Option String :=
  match rk with
  | .unit => none
  | .uint64 => some "u64"
  | .int64 => some "i64"
  | .bool => some "bool"
  | .aggregate n =>
      let tys :=
        (List.range n).map (fun i =>
          if leafIsInt[i]?.getD false then "i64" else "u64")
      some ("(" ++ String.intercalate ", " tys ++ ")")

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let numericTy := rustNumericTy plan.signedNumeric
  let mut fns : Array RFn := #[]
  -- Initializer
  match plan.initializer with
  | some init => do
      let mut fnParams : Array (String × String) := #[("env", "Env")]
      for p in init.params do
        fnParams := fnParams.push (p, numericTy)
      let shaStmts ← emitSha256Sites plan init.params #[] init.sha256Sites
      let storeStmts ← emitStores plan init.params #[] init.stores
      fns := fns.push {
        name := "init"
        params := fnParams
        returnType := none
        body := shaStmts ++ storeStmts
      }
  | none => pure ()
  -- Entries
  for ent in plan.entries do
    let mut fnParams : Array (String × String) := #[("env", "Env")]
    for p in ent.params do
      fnParams := fnParams.push (p, numericTy)
    let mut body : Array RStatement := #[]
    -- Load pre-state into locals so Plan stateLoad nodes stay snapshot-stable
    -- across subsequent stores (single-block overlay honesty).
    let mut stateLocals : Array String := #[]
    for i in [0:plan.states.size] do
      match plan.states[i]? with
      | some st => do
          let key ← stateKey plan i
          let localName := s!"st_{st.name}"
          body := body.push (.letBind localName (.storageGet key))
          stateLocals := stateLocals.push localName
      | none => pure ()
    let shaStmts ← emitSha256Sites plan ent.params stateLocals ent.sha256Sites
    body := body ++ shaStmts
    let checkStmts ← emitAssertChecks plan ent.params stateLocals ent.checks
    body := body ++ checkStmts
    if !ent.body.isEmpty then
      let cfgStmts ← emitPlanStatements plan ent.params stateLocals ent.body
      body := body ++ cfgStmts
    else
      let storeStmts ← emitStores plan ent.params stateLocals ent.stores
      body := body ++ storeStmts
      match ent.resultKind, ent.result? with
      | .unit, _ => pure ()
      | .aggregate n, _ => do
          let src := if ent.leaves.isEmpty then
            match ent.result? with | some e => #[e] | none => #[]
          else ent.leaves
          unless src.size == n do
            planError
              s!"Soroban entry '{ent.name}' aggregate emit leaf count must be {n}"
          let mut elems : Array RExpr := #[]
          for e in src do
            elems := elems.push (← lowerExpr plan ent.params stateLocals e)
          body := body.push (.returnExpr (RExpr.tuple elems))
      | .uint64, some e | .int64, some e | .bool, some e => do
          let re ← lowerExpr plan ent.params stateLocals e
          body := body.push (.returnExpr re)
      | _, _ => pure ()
    fns := fns.push {
      name := ent.name
      params := fnParams
      returnType := resultTypeStr ent.resultKind ent.leafIsInt
      body
    }
  -- Views
  for v in plan.views do
    let mut fnParams : Array (String × String) := #[("env", "Env")]
    for p in v.params do
      fnParams := fnParams.push (p, numericTy)
    let re ← match v.resultKind with
      | .aggregate n => do
          let src := if v.leaves.isEmpty then #[v.value] else v.leaves
          unless src.size == n do
            planError
              s!"Soroban view '{v.name}' aggregate emit leaf count must be {n}"
          let mut elems : Array RExpr := #[]
          for e in src do
            elems := elems.push (← lowerExpr plan v.params #[] e)
          pure (RExpr.tuple elems)
      | _ =>
          lowerExpr plan v.params #[] v.value
    fns := fns.push {
      name := v.name
      params := fnParams
      returnType := resultTypeStr v.resultKind v.leafIsInt
      body := #[.returnExpr re]
    }
  let contract : RContract := {
    contractName := plan.programName
    fns
  }
  pure { sourcePlan := plan, contract }

-- ---------------------------------------------------------------------------
-- Renderer
-- ---------------------------------------------------------------------------

private def binOpStr : RBinOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .and => "&&"
  | .or => "||"

private partial def renderExpr (signed : Bool) : RExpr → String
  | .name id => id
  | .u64Lit v => v
  | .boolLit true => "true"
  | .boolLit false => "false"
  | .binary op l r =>
      s!"({renderExpr signed l} {binOpStr op} {renderExpr signed r})"
  | .unary .not o =>
      s!"(!{renderExpr signed o})"
  | .checkedArith method receiver arg panicMsg =>
      s!"{renderExpr signed receiver}.{method}({renderExpr signed arg}).expect(\"{panicMsg}\")"
  | .storageGet key =>
      let zero := rustZeroLit signed
      s!"env.storage().instance().get(&symbol_short!(\"{key}\")).unwrap_or({zero})"
  | .storageSet key value =>
      s!"env.storage().instance().set(&symbol_short!(\"{key}\"), &{renderExpr signed value})"
  | .ledgerTimestamp =>
      "env.ledger().timestamp()"
  | .ledgerSequence =>
      "u64::from(env.ledger().sequence())"
  | .bytesFromU64LimbsLe l0 l1 l2 l3 =>
      -- Semantic UInt256 valueBytes are 32-byte little-endian. Each limb
      -- is one LE u64; concatenating limb0..limb3 reconstructs the wire
      -- bytes that `pf.crypto.sha256` hashes (not EVM mstore big-endian).
      let e0 := renderExpr signed l0
      let e1 := renderExpr signed l1
      let e2 := renderExpr signed l2
      let e3 := renderExpr signed l3
      "{\n" ++
      s!"            let l0 = ({e0}).to_le_bytes();\n" ++
      s!"            let l1 = ({e1}).to_le_bytes();\n" ++
      s!"            let l2 = ({e2}).to_le_bytes();\n" ++
      s!"            let l3 = ({e3}).to_le_bytes();\n" ++
      "            soroban_sdk::Bytes::from_array(&env, &[\n" ++
      "                l0[0], l0[1], l0[2], l0[3], l0[4], l0[5], l0[6], l0[7],\n" ++
      "                l1[0], l1[1], l1[2], l1[3], l1[4], l1[5], l1[6], l1[7],\n" ++
      "                l2[0], l2[1], l2[2], l2[3], l2[4], l2[5], l2[6], l2[7],\n" ++
      "                l3[0], l3[1], l3[2], l3[3], l3[4], l3[5], l3[6], l3[7],\n" ++
      "            ])\n" ++
      "        }"
  | .cryptoSha256 bytes =>
      -- Host returns Hash<32>; to_array() is the 32-byte digest, still
      -- Semantic-LE when split back into four u64 limbs.
      s!"env.crypto().sha256(&{renderExpr signed bytes}).to_array()"
  | .u64LimbFromHashLe hash limbIndex =>
      let base := limbIndex * 8
      let h := renderExpr signed hash
      "u64::from_le_bytes([" ++
        s!"{h}[{base}], {h}[{base + 1}], {h}[{base + 2}], {h}[{base + 3}], " ++
        s!"{h}[{base + 4}], {h}[{base + 5}], {h}[{base + 6}], {h}[{base + 7}]])"
  | .ifExpr cond thenE elseE =>
      s!"if {renderExpr signed cond} \{ {renderExpr signed thenE} } else \{ {renderExpr signed elseE} }"
  | .panic msg => s!"panic!(\"{msg}\")"
  | .unit => "()"
  | .tuple elems =>
      let inner := String.intercalate ", " (elems.map (renderExpr signed)).toList
      "(" ++ inner ++ ")"

private def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

private partial def renderStatementLines (signed : Bool) (ind : Nat)
    (s : RStatement) : Array String :=
  match s with
  | .letBind name value =>
      #[indent ind s!"let {name} = {renderExpr signed value};"]
  | .expr value =>
      #[indent ind s!"{renderExpr signed value};"]
  | .returnExpr value =>
      #[indent ind (renderExpr signed value)]
  | .ifThenElse cond thenBody elseBody => Id.run do
      let mut lines := #[indent ind ("if " ++ renderExpr signed cond ++ " {")]
      for stmt in thenBody do
        lines := lines ++ renderStatementLines signed (ind + 4) stmt
      if elseBody.isEmpty then
        lines := lines.push (indent ind "}")
      else
        lines := lines.push (indent ind "} else {")
        for stmt in elseBody do
          lines := lines ++ renderStatementLines signed (ind + 4) stmt
        lines := lines.push (indent ind "}")
      lines

private def renderFn (signed : Bool) (f : RFn) : Array String := Id.run do
  let mut lines : Array String := #[]
  let params := String.intercalate ", "
    (f.params.map (fun (n, t) => if n == "env" then s!"{n}: {t}" else s!"{n}: {t}")).toList
  let retSig := match f.returnType with
    | some t => s!" -> {t}"
    | none => ""
  lines := lines.push (indent 4 s!"pub fn {f.name}({params}){retSig} \{")
  for i in [0:f.body.size] do
    match f.body[i]? with
    | some stmt =>
        lines := lines ++ renderStatementLines signed 8 stmt
    | none => pure ()
  lines := lines.push (indent 4 "}")
  pure lines

private def renderContract
    (c : RContract) (sourceHash semanticHash : String) (signed : Bool) : String := Id.run do
  let mut lines : Array String := #[]
  lines := lines.push "// ProofForge Soroban S0 source recipe; not a deployable Wasm claim; zero-tool finalize."
  lines := lines.push s!"// source: {sourceHash}"
  lines := lines.push s!"// semantic: {semanticHash}"
  lines := lines.push "#![no_std]"
  lines := lines.push "use soroban_sdk::{contract, contractimpl, symbol_short, Env};"
  lines := lines.push ""
  lines := lines.push "#[contract]"
  lines := lines.push s!"pub struct {c.contractName};"
  lines := lines.push ""
  lines := lines.push "#[contractimpl]"
  lines := lines.push s!"impl {c.contractName} \{"
  for f in c.fns do
    lines := lines.push ""
    lines := lines ++ renderFn signed f
  lines := lines.push "}"
  lines := lines.push ""
  pure (String.intercalate "\n" lines.toList)

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderContract ir.contract ir.sourcePlan.sourceHash
    ir.sourcePlan.semanticHash ir.sourcePlan.signedNumeric
  pure #[{
    path := s!"{ir.sourcePlan.programName}.rs"
    mediaType := "text/x-rust"
    contents := source
  }]

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless isAsciiIdentifier 240 ir.contract.contractName do
    planError "Soroban IR contract name is not a safe identifier"
  pure ()

def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lower plan

def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  validateIR ir
  emitFromIR ir

def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  let plan ← planFromCompiledSemanticV1 compiled
  validatePlan plan
  lower plan

def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCompiledSemanticV1 compiled
  validateIR ir
  emitFromIR ir

end ProofForgeV2.Targets.Soroban
