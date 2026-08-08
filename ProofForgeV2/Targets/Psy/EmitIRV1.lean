import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

/-!
# Psy EmitIRV1 — Plan → product artifacts (DPN JSON + transitional `.psy`)

Target-owned Psy AST/renderer (ported from the old Compiler/Psy surface for
the V2 envelope) and capability-internal `lower`/`emitFromIR`.

**PSY-DPN-7 product dual-write + PSY-DPN-G5-HARD honesty**: primary artifact is
`{contract}.dpn.json` (dargo-shaped package of `DPNFunctionCircuitDefinition`)
when Plan→DPN lower succeeds; `{contract}.psy` remains a transitional/debug
text emission for dargo compile lanes. **G5-HARD**: non-residual DPN lower
failures fail materialize with stable `PSY-DPN-G5-HARD` (no silent incomplete
product). Explicit residual allowlist (`PSY-DPN-G5-MATRIX` residual families —
narrow bitwise/shift, Int signed, pureFn/callFn, UInt64 shl/shr, checkedBitNot,
Field residual; **R-NARROW UInt8/16/32 arith admitted to DPN**) may still emit
transitional `.psy` only until remaining families gain true DPN lower; full
hard-require (zero allowlist) is deferred. `deployable=false` unchanged.

Checked u64 arithmetic is realized with explicit assert guards. Psy `Felt`
is Goldilocks (p = 2^64−2^32+1): every decimal literal is reduced into
`0..p-1`, and overflow uses field-wrap detection (`sum >= lhs` for add;
exact inverse for mul) rather than an illegal `2^64` bound.

**T8 multi-width (UInt{8,16,32})**: values are Felt-carried (not native Psy
uN — dargo u32 arith/shift is unfaithful to Reference). After each add/mul/
shl the emitter asserts `result < 2^w`; sub checks underflow; shifts check
`count < w`; bitNot is `x ^ (2^w−1)` as Felt. Narrow ops cannot wrap mod p
when operands are in-range (`(2^32−1)^2 < p`), so width bounds alone recover
checked semantics. Entry params with `uintWidth ∈ {8,16,32}` get a range
assert at method start. Results are `-> Felt` (single Felt, documented width).

Bitwise/shift use native Psy Felt operators; UInt64 shifts use `count < 64`.
Revert → `assert(false, ...)`. Emit → `__emit([...])` (**source intrinsic
only** — product Finalize has no ordered-event runtime gate). Void call →
`__invoke_sync#<Felt>(targetHash, methodHash, [args])` with deterministic
component hashes reduced mod p (**source-only** static-QN hash; no deployment
address / response binding / product runtime gate). Schedule stays fail
closed (no deferred form). Result-bearing call is Plan-FC before emit.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
open ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

-- ---------------------------------------------------------------------------
-- Psy surface AST (envelope subset of the old Compiler/Psy AST)
-- ---------------------------------------------------------------------------

inductive PsyBinaryOp where
  | add | sub | mul | div | mod
  | bitAnd | bitOr | bitXor
  | shiftLeft | shiftRight
  | eq | ne | lt | le | gt | ge
  | boolAnd | boolOr
  deriving BEq, Inhabited, Repr

inductive PsyUnaryOp where
  | not
  deriving BEq, Inhabited, Repr

inductive PsyLiteral where
  | felt (value : Nat)
  | bool (value : Bool)
  | u32 (value : Nat)
  deriving BEq, Inhabited, Repr

mutual
  inductive PsyExpr where
    | literal (value : PsyLiteral)
    | local (name : String)
    | binary (lhs : PsyExpr) (op : PsyBinaryOp) (rhs : PsyExpr)
    | unary (op : PsyUnaryOp) (rhs : PsyExpr)
    | cast (value : PsyExpr) (targetType : String)
    | storageScalarRead (stateId : String)
    | crosscallInvoke (target methodId : PsyExpr) (args : Array PsyExpr)
    | call (name : String) (args : Array PsyExpr)
    /-- B-RET-ABI: fixed-length Felt array literal `[e0, e1, …]` — honest
        multi-leaf return form on the Psy surface (`-> [Felt; N]`). -/
    | arrayLit (elems : Array PsyExpr)
    /-- Expression-form if/else (Psy `if cond { a } else { b }` as a value).
        Used when match/switch arms are pure returns: dargo rejects `return`
        inside an IfExpr statement, so return-only arms lower to
        `return if … { … } else { … };` instead. -/
    | ifExpr (condition thenE elseE : PsyExpr)
    deriving BEq, Inhabited, Repr

  inductive PsyStmt where
    | letBind (name : String) (typeName : String) (value : PsyExpr)
    | letMutBind (name : String) (typeName : String) (value : PsyExpr)
    | localAssign (target : String) (value : PsyExpr)
    | storageWrite (stateId : String) (value : PsyExpr)
    | assert (condition : PsyExpr) (message : String)
    | assertEq (lhs rhs : PsyExpr) (message : String)
    | ifElse (condition : PsyExpr) (thenBody elseBody : Array PsyStmt)
    | boundedFor (indexName : String) (start stopExclusive : Nat)
        (body : Array PsyStmt)
    | returnExpr (value : PsyExpr)
    | returnUnit
    | eventEmit (name : String) (args : Array PsyExpr)
    | crosscall (target methodId : PsyExpr) (args : Array PsyExpr)
        (isSchedule : Bool) (calleeNote : String)
    | abort (message : String)
    deriving BEq, Inhabited, Repr
end

structure PsyParam where
  name : String
  isBool : Bool
  /-- Entry range-check width for Felt-carried narrow params (8/16/32); 0 = none. -/
  uintWidth : Nat := 0
  deriving BEq, Inhabited, Repr

structure PsyMethod where
  name : String
  params : Array PsyParam
  resultIsBool : Bool
  resultIsUnit : Bool
  /-- B-RET-ABI: `some N` → method signature `-> [Felt; N]` (multi-leaf
      aggregate return). Mutually exclusive with the scalar flags. -/
  resultLeafCount : Option Nat := none
  /-- Contract entrypoint (`#[contract_method]`) vs pure helper `fn`. -/
  isContractMethod : Bool
  body : Array PsyStmt
  deriving BEq, Inhabited, Repr

structure PsyStateField where
  name : String
  deriving BEq, Inhabited, Repr

structure PsyModule where
  contractName : String
  headerComment : String
  state : Array PsyStateField
  methods : Array PsyMethod
  helpers : Array PsyMethod
  testName : String
  testBody : Array String
  deriving BEq, Inhabited, Repr

structure IR where
  sourcePlan : Plan
  module_ : PsyModule
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Printer (deterministic pure rendering)
-- ---------------------------------------------------------------------------

private def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

private def stringLiteral (value : String) : String :=
  let escaped := value.toList.foldl (init := "") fun acc c =>
    if c == '"' then acc ++ "\\\""
    else if c == '\\' then acc ++ "\\\\"
    else if c == '\n' then acc ++ "\\n"
    else acc.push c
  s!"\"{escaped}\""

private def binaryOpSymbol : PsyBinaryOp → String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .mod => "%"
  | .bitAnd => "&"
  | .bitOr => "|"
  | .bitXor => "^"
  | .shiftLeft => "<<"
  | .shiftRight => ">>"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .boolAnd => "&&"
  | .boolOr => "||"

private def literalStr : PsyLiteral → String
  | .felt value => toString value
  | .bool true => "true"
  | .bool false => "false"
  | .u32 value => s!"{value}u32"

mutual
  private partial def exprStr : PsyExpr → String
    | .literal v => literalStr v
    | .local name => name
    | .binary lhs op rhs =>
        match op with
        | .eq | .ne | .lt | .le | .gt | .ge | .boolAnd | .boolOr =>
            s!"({exprStr lhs} {binaryOpSymbol op} {exprStr rhs})"
        | _ => s!"{operandExpr lhs} {binaryOpSymbol op} {operandExpr rhs}"
    | .unary .not rhs => s!"!{operandExpr rhs}"
    | .cast value ty => s!"{operandExpr value} as {ty}"
    | .storageScalarRead stateId => s!"c.{stateId}.get()"
    | .crosscallInvoke target methodId args =>
        let argStr := String.intercalate ", " (args.map exprStr).toList
        s!"__invoke_sync#<Felt>({exprStr target}, {exprStr methodId}, [{argStr}])"
    | .call name args =>
        let argStr := String.intercalate ", " (args.map exprStr).toList
        s!"{name}({argStr})"
    | .arrayLit elems =>
        let argStr := String.intercalate ", " (elems.map exprStr).toList
        s!"[{argStr}]"
    | .ifExpr condition thenE elseE =>
        -- Expression if; braced branches keep nested ifExpr readable.
        "if " ++ exprStr condition ++ " { " ++ exprStr thenE ++
          " } else { " ++ exprStr elseE ++ " }"

  private partial def operandExpr (e : PsyExpr) : String :=
    match e with
    | .literal _ | .local _ | .storageScalarRead _ | .call _ _ | .crosscallInvoke _ _ _
    | .arrayLit _ | .ifExpr _ _ _ =>
        exprStr e
    | _ => s!"({exprStr e})"

  /-- When a statement body is a pure return (or nested return-only if/else),
      recover the returned expression so match/switch arms can emit Psy
      expression-form `return if …` (dargo forbids `return` inside IfExpr). -/
  private partial def pureReturnExpr (body : Array PsyStmt) : Option PsyExpr :=
    if body.size != 1 then none
    else
      match body[0]! with
      | .returnExpr e => some e
      | .ifElse c t e =>
          match pureReturnExpr t, pureReturnExpr e with
          | some te, some ee => some (.ifExpr c te ee)
          | _, _ => none
      | _ => none

  private partial def stmtLines (level : Nat) (s : PsyStmt) : Array String :=
    match s with
    | .letBind name typeName value =>
        #[indent level s!"let {name}: {typeName} = {exprStr value};"]
    | .letMutBind name typeName value =>
        #[indent level s!"let mut {name}: {typeName} = {exprStr value};"]
    | .localAssign target value =>
        #[indent level s!"{target} = {exprStr value};"]
    | .storageWrite stateId value =>
        #[indent level s!"c.{stateId} = {exprStr value};"]
    | .assert condition message =>
        #[indent level s!"assert({exprStr condition}, {stringLiteral message});"]
    | .assertEq lhs rhs message =>
        #[indent level s!"assert_eq({exprStr lhs}, {exprStr rhs}, {stringLiteral message});"]
    | .ifElse condition thenBody elseBody =>
        -- Prefer expression-form when both arms are pure returns (match/switch
        -- on Enum/Option tags). Otherwise emit statement-form if/else without
        -- a trailing semicolon (statement, not IfExpr expression-statement).
        match pureReturnExpr thenBody, pureReturnExpr elseBody with
        | some te, some ee =>
            -- dargo accepts `let r = if … { a } else { b }; return r;` and
            -- rejects bare `return` inside IfExpr statement arms.
            let tmp := "pf_ret"
            #[indent level
                ("let " ++ tmp ++ ": Felt = if " ++ exprStr condition ++
                  " { " ++ exprStr te ++ " } else { " ++ exprStr ee ++ " };"),
              indent level ("return " ++ tmp ++ ";")]
        | _, _ =>
            -- dargo v0.1.0: statement-form `if` requires both `else` and a
            -- trailing `;` when more statements follow (otherwise KeywordLet
            -- is a parse error after `}`). Always emit `else { … };`.
            let thenLines := thenBody.flatMap (stmtLines (level + 1))
            let elseLines := elseBody.flatMap (stmtLines (level + 1))
            #[indent level (s!"if {exprStr condition} " ++ "{")]
              ++ thenLines
              ++ #[indent level "} else {"]
              ++ elseLines
              ++ #[indent level "};"]
    | .boundedFor indexName start stopExclusive body =>
        let bodyLines := body.flatMap (stmtLines (level + 1))
        #[indent level (s!"for {indexName} in {start}u32..{stopExclusive}u32 " ++ "{")]
          ++ bodyLines
          ++ #[indent level "}"]
    | .returnExpr value =>
        #[indent level s!"return {exprStr value};"]
    | .returnUnit =>
        #[]
    | .eventEmit name args =>
        let argStr := String.intercalate ", " (args.map exprStr).toList
        #[indent level s!"__emit([{argStr}]); // event `{name}`"]
    | .crosscall target methodId args isSchedule calleeNote =>
        let argStr := String.intercalate ", " (args.map exprStr).toList
        let tag := if isSchedule then "schedule" else "call"
        #[indent level
            s!"__invoke_sync#<Felt>({exprStr target}, {exprStr methodId}, [{argStr}]); // {tag} `{calleeNote}`"]
    | .abort message =>
        #[indent level s!"assert(false, {stringLiteral message});"]
end

private def renderParam (p : PsyParam) : String :=
  -- All non-Bool params are Felt (narrow UInt{8,16,32} are Felt-carried).
  s!"{p.name}: {if p.isBool then "bool" else "Felt"}"

/-- Method return type suffix. UInt{8,16,32,64} and Field are `-> Felt`;
    B-RET-ABI aggregates render as `-> [Felt; N]` (honest multi-leaf form). -/
private def renderReturnSuffix (m : PsyMethod) : String :=
  if m.resultIsUnit then ""
  else if m.resultIsBool then " -> bool"
  else match m.resultLeafCount with
    | some n => s!" -> [Felt; {n}]"
    | none => " -> Felt"

/-- Render a contract method with the correct `Ref::new` line. -/
private def renderContractMethod (refName : String) (m : PsyMethod) : String :=
  let returnSuffix := renderReturnSuffix m
  let paramList := String.intercalate ", " (m.params.map renderParam).toList
  let header := indent 1 "#[contract_method]"
  let signature :=
    indent 1 (s!"pub fn {m.name}({paramList}){returnSuffix} " ++ "{")
  let newRef := indent 2 s!"let c = {refName}::new(ContractMetadata::current());"
  let bodyLines := m.body.flatMap (stmtLines 2)
  String.intercalate "\n"
    (#[header, signature, newRef] ++ bodyLines ++ #[indent 1 "}"]).toList

private def renderHelper (m : PsyMethod) : String :=
  let returnSuffix := renderReturnSuffix m
  let paramList := String.intercalate ", " (m.params.map renderParam).toList
  let signature := s!"fn {m.name}({paramList}){returnSuffix} " ++ "{"
  let bodyLines := m.body.flatMap (stmtLines 1)
  String.intercalate "\n" (#[signature] ++ bodyLines ++ #["}"]).toList

private def renderModule (mod : PsyModule) : String :=
  let refName := s!"{mod.contractName}Ref"
  let stateLines :=
    if mod.state.isEmpty then
      #[indent 1 "pub _proof_forge_marker: Felt,"]
    else
      mod.state.map fun s => indent 1 s!"pub {s.name}: Felt,"
  let methodBlocks := mod.methods.map (renderContractMethod refName)
  let helperBlocks := mod.helpers.map renderHelper
  let helperSection :=
    if helperBlocks.isEmpty then #[]
    else #["", String.intercalate "\n\n" helperBlocks.toList]
  let testLines := mod.testBody.map (indent 1)
  let parts : Array String :=
    #[mod.headerComment, "",
      "#[contract]",
      "#[derive(Storage)]",
      s!"pub struct {mod.contractName} " ++ "{"] ++
    stateLines ++
    #["}", "", s!"impl {refName} " ++ "{"] ++
    (if methodBlocks.isEmpty then #[]
     else #[String.intercalate "\n" methodBlocks.toList]) ++
    #["}"] ++
    helperSection ++
    #["", "#[test]", s!"fn {mod.testName}() " ++ "{"] ++
    testLines ++
    #["}", ""]
  String.intercalate "\n" parts.toList

-- ---------------------------------------------------------------------------
-- Plan → Psy IR
-- ---------------------------------------------------------------------------

/-- Goldilocks prime p = 2^64 − 2^32 + 1 = 0xFFFFFFFF00000001.
    Psy `Felt` is a plonky2 Goldilocks field element; every emitted decimal
    literal must lie in `0 .. p-1` or `psyup`/`dargo` rejects it with
    `number too large to fit in target type`. 2^64 itself is **not**
    representable (and 2^64 ≡ 2^32−1 (mod p) would be the wrong overflow
    bound). Checked u64 add/mul therefore use field-wrap guards matching
    the official Psy template, not a 2^64 comparison. -/
private def goldilocksPrime : Nat := 0xFFFFFFFF00000001

/-- Reduce a Nat into the exclusive Goldilocks range `[0, p)`. -/
private def feltNat (n : Nat) : Nat := n % goldilocksPrime

/-- Felt literal guaranteed to be accepted by dargo (always `< p`). -/
private def feltLit (n : Nat) : PsyExpr :=
  .literal (.felt (feltNat n))

private structure EmitCtx where
  next : Nat
  stateNames : Array String
  eventNames : Array String
  errorNames : Array String
  deriving Inhabited

private def freshName (ctx : EmitCtx) : String × EmitCtx :=
  (s!"pf_e{ctx.next}", { ctx with next := ctx.next + 1 })

private def wideUintMulLimbName (operationId limbIndex : Nat) : String :=
  s!"pf_w{operationId}_{limbIndex}"

private def wideUInt128DivModPrefix (operationId : Nat) : String :=
  s!"pf_d{operationId}"

private def wideUintDivModLimbName
    (resultKind : WideUInt128DivModResultV1) (operationId limbIndex : Nat) : String :=
  let tag := match resultKind with
    | .quotient => "q"
    | .remainder => "r"
  s!"{wideUInt128DivModPrefix operationId}_{tag}{limbIndex}"

private def wideUInt128ShiftPrefix (operationId : Nat) : String :=
  s!"pf_s{operationId}"

private def wideUintShiftLimbName
    (kind : WideUInt128ShiftKindV1) (operationId limbIndex : Nat) : String :=
  let tag := match kind with
    | .shl => "l"
    | .shr => "r"
  s!"{wideUInt128ShiftPrefix operationId}_{tag}{limbIndex}"

/-- Deterministic FNV-1a-ish 64-bit hash of a string → Nat for Felt literals.
    Reduced mod Goldilocks so the emitted decimal is always in range. -/
private def hashComponent (s : String) : Nat := Id.run do
  let prime : UInt64 := 1099511628211
  let mut h : UInt64 := 14695981039346656037
  for c in s.toList do
    h := (h ^^^ c.toNat.toUInt64) * prime
  pure (feltNat h.toNat)

private def hashCallee (comps : Array String) : PsyExpr × PsyExpr × String :=
  let note := String.intercalate "." comps.toList
  let target :=
    match comps[0]? with
    | some c => feltLit (hashComponent c)
    | none => feltLit 0
  let method :=
    match comps[1]? with
    | some c => feltLit (hashComponent c)
    | none => feltLit 0
  (target, method, note)

/-- 2^bitWidth as a Felt-legal Nat (only called for w ∈ {8,16,32}). -/
private def narrowBound (bitWidth : Nat) : Nat :=
  match bitWidth with
  | 8 => 256
  | 16 => 65536
  | 32 => 4294967296
  | _ => 0

/-- (2^bitWidth − 1) all-ones mask as Felt-legal Nat. -/
private def narrowMask (bitWidth : Nat) : Nat :=
  match bitWidth with
  | 8 => 255
  | 16 => 65535
  | 32 => 4294967295
  | _ => 0

private def exprTypeName : Expr → String
  | .boolLiteral _ => "bool"
  | .compare _ _ _ | .signedCompare _ _ _ | .narrowSignedCompare _ _ _ _ => "bool"
  | .logicalAnd _ _ | .logicalOr _ _ => "bool"
  | .boolNot _ => "bool"
  | .u32Literal _ => "u32"
  | _ => "Felt"

private partial def lowerExprStmt
    (ctx : EmitCtx) (expr : Expr) :
    CompileResult (Array PsyStmt × PsyExpr × EmitCtx) := do
  let leaf (e : PsyExpr) : CompileResult (Array PsyStmt × PsyExpr × EmitCtx) :=
    pure (#[], e, ctx)
  match expr with
  | .literal value => leaf (feltLit value.toNat)
  | .u32Literal value => leaf (.literal (.u32 value.toNat))
  | .boolLiteral value => leaf (.literal (.bool value))
  | .fieldLiteral value => leaf (feltLit value.toNat)
  | .param inputIndex => leaf (.local s!"p{inputIndex}")
  | .loopVar depth => leaf (.local s!"pf_i{depth}")
  | .stateLoad fieldIndex => do
      let name ← match ctx.stateNames[fieldIndex]? with
        | some n => pure n
        | none => planError "Psy emission: stateLoad references a missing field"
      leaf (.storageScalarRead name)
  | .wideUintMulLimb bitWidth operationId limbIndex => do
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy emission: wide mul bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy emission: wide multiplication result limb index out of range"
      leaf (.local (wideUintMulLimbName operationId limbIndex))
  | .wideUintDivModLimb resultKind bitWidth operationId limbIndex => do
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy emission: wide div/mod bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy emission: wide div/mod result limb index out of range"
      leaf (.local (wideUintDivModLimbName resultKind operationId limbIndex))
  | .wideUintShiftLimb kind bitWidth operationId limbIndex => do
      unless bitWidth == 128 || bitWidth == 256 do
        planError "Psy emission: wide shift bitWidth must be 128 or 256"
      unless limbIndex < bitWidth / 32 do
        planError "Psy emission: wide shift result limb index out of range"
      leaf (.local (wideUintShiftLimbName kind operationId limbIndex))
  | .limbAdd l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++ #[.letBind name "Felt" (.binary l' .add r')],
        .local name, ctx3)
  | .limbSub l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++ #[.letBind name "Felt" (.binary l' .sub r')],
        .local name, ctx3)
  | .select condition thenValue elseValue => do
      let (cs, c', ctx1) ← lowerExprStmt ctx condition
      let (ts, t', ctx2) ← lowerExprStmt ctx1 thenValue
      let (es, e', ctx3) ← lowerExprStmt ctx2 elseValue
      let (name, ctx4) := freshName ctx3
      pure (cs ++ ts ++ es ++ #[.letBind name "Felt" (.ifExpr c' t' e')],
        .local name, ctx4)
  | .checkedAdd l r => do
      -- Field-wrap overflow (official Psy template style): sum >= lhs
      -- detects Goldilocks wrap. A 2^64 bound is not a legal Felt literal.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' .add r'),
          .assert (.binary (.local name) .ge l') "u64 add overflow"],
        .local name, ctx3)
  | .checkedSub l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary l' .ge r') "u64 sub underflow",
          .letBind name "Felt" (.binary l' .sub r')],
        .local name, ctx3)
  | .checkedMul l r => do
      -- Exact inverse check: lhs == 0 || product / lhs == rhs. Catches field
      -- wrap without needing a 2^64 bound literal.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let zero := feltLit 0
      let noWrap : PsyExpr :=
        .binary
          (.binary l' .eq zero)
          .boolOr
          (.binary (.binary (.local name) .div l') .eq r')
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' .mul r'),
          .assert noWrap "u64 mul overflow"],
        .local name, ctx3)
  | .checkedDiv l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne (feltLit 0)) "u64 div by zero",
          .letBind name "Felt" (.binary l' .div r')],
        .local name, ctx3)
  | .checkedMod l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne (feltLit 0)) "u64 mod by zero",
          .letBind name "Felt" (.binary l' .mod r')],
        .local name, ctx3)
  -- T8 multi-width: Felt-carried UInt{8,16,32}. Max product of two UInt32
  -- values is (2^32−1)^2 < Goldilocks p, so field wrap cannot occur when
  -- operands are in-range — only an explicit `result < 2^w` width guard is
  -- required (vs u64 field-wrap detection).
  | .narrowCheckedAdd w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let bound := feltLit (narrowBound w)
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' .add r'),
          .assert (.binary (.local name) .lt bound) s!"u{w} add overflow"],
        .local name, ctx3)
  | .narrowCheckedSub w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary l' .ge r') s!"u{w} sub underflow",
          .letBind name "Felt" (.binary l' .sub r')],
        .local name, ctx3)
  | .narrowCheckedMul w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let bound := feltLit (narrowBound w)
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' .mul r'),
          .assert (.binary (.local name) .lt bound) s!"u{w} mul overflow"],
        .local name, ctx3)
  | .narrowCheckedDiv w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne (feltLit 0)) s!"u{w} div by zero",
          .letBind name "Felt" (.binary l' .div r')],
        .local name, ctx3)
  | .narrowCheckedMod w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne (feltLit 0)) s!"u{w} mod by zero",
          .letBind name "Felt" (.binary l' .mod r')],
        .local name, ctx3)
  | .narrowBitAnd _w l r | .narrowBitOr _w l r | .narrowBitXor _w l r => do
      let psyOp := match expr with
        | .narrowBitAnd _ _ _ => PsyBinaryOp.bitAnd
        | .narrowBitOr _ _ _ => .bitOr
        | _ => .bitXor
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' psyOp r')],
        .local name, ctx3)
  | .narrowShl w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let bound := feltLit (narrowBound w)
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .lt (feltLit w)) s!"invalidShift: count >= {w}",
          .letBind name "Felt" (.binary l' .shiftLeft r'),
          .assert (.binary (.local name) .lt bound) s!"u{w} shl overflow"],
        .local name, ctx3)
  | .narrowShr w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .lt (feltLit w)) s!"invalidShift: count >= {w}",
          .letBind name "Felt" (.binary l' .shiftRight r')],
        .local name, ctx3)
  | .narrowBitNot w operand => do
      -- Felt-carried mask XOR: `x ^ (2^w−1)`. Mask is always a legal Felt
      -- literal (255 / 65535 / 4294967295 all < p). Not native u32 — dargo
      -- u32 sub is buggy and native uN is not the T8 surface.
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++
        #[.letBind name "Felt" (.binary o' .bitXor (feltLit (narrowMask w)))],
        .local name, ctx2)
  | .shl l r => do
      -- Count < 64 only. The prior product < 2^64 bound was not a legal Felt
      -- literal under Goldilocks; field wrap of the shift is left to the VM.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let count :=
        match r with
        | .u32Literal v => feltLit v.toNat
        | _ => r'
      pure (ls1 ++ ls2 ++
        #[.assert (.binary count .lt (feltLit 64)) "invalidShift: count >= 64",
          .letBind name "Felt" (.binary l' .shiftLeft count)],
        .local name, ctx3)
  | .shr l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      let count :=
        match r with
        | .u32Literal v => feltLit v.toNat
        | _ => r'
      pure (ls1 ++ ls2 ++
        #[.assert (.binary count .lt (feltLit 64)) "invalidShift: count >= 64",
          .letBind name "Felt" (.binary l' .shiftRight count)],
        .local name, ctx3)
  | .compare op l r => do
      let psyOp := match op with
        | .eq => PsyBinaryOp.eq | .ne => .ne | .lt => .lt
        | .le => .le | .gt => .gt | .ge => .ge
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "bool" (.binary l' psyOp r')],
        .local name, ctx3)
  | .checkedBitNot operand => do
      -- Exact UInt64 bitNot with Felt representability guard.
      -- bitNot x = (2^64−1) − x is a legal Felt iff x ≥ 2^32−1 (result < p).
      -- 2^64−1 itself is not a legal Felt literal (≡ 2^32−2 mod p); emission
      -- therefore uses the reduced mask 2^32−2 as a wrapping Felt sub:
      --   assert x >= 2^32−1;  result = (2^32−2) − x   (field sub wraps)
      -- When the guard holds, field wrap recovers exact (2^64−1)−x.
      -- When x ≤ 2^32−2 the exact result is ≥ p and cannot be a Felt — trap
      -- like checked-arith (never silent mod-p bitNot).
      -- Boundary: x=0 / x=2^32−2 trap; x=2^32−1 → p−1; UInt64.max is outside
      -- the Felt domain [0,p) so is not a runtime input on this surface.
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      let threshold := feltLit 4294967295   -- 2^32 − 1
      let mask := feltLit 4294967294        -- 2^32 − 2 ≡ (2^64−1) (mod p)
      pure (ls1 ++
        #[.assert (.binary o' .ge threshold) "u64 bitNot result not representable in Felt",
          .letBind name "Felt" (.binary mask .sub o')],
        .local name, ctx2)
  | .bitAnd l r | .bitOr l r | .bitXor l r => do
      let psyOp := match expr with
        | .bitAnd _ _ => PsyBinaryOp.bitAnd
        | .bitOr _ _ => .bitOr
        | _ => .bitXor
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' psyOp r')],
        .local name, ctx3)
  | .logicalAnd l r | .logicalOr l r => do
      let psyOp := match expr with
        | .logicalAnd _ _ => PsyBinaryOp.boolAnd
        | _ => .boolOr
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "bool" (.binary l' psyOp r')],
        .local name, ctx3)
  | .boolNot operand => do
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++ #[.letBind name "bool" (.unary .not o')], .local name, ctx2)
  | .checkedNeg operand => do
      -- Int64 intMin (2^63) reverts; otherwise field negation `0 - x`.
      -- (2^64 − x is not expressible: 2^64 is not a legal Goldilocks literal.
      -- Felt values already live in [0, p); field negation is the native
      -- inverse and keeps every emitted literal in range.)
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      let intMin : PsyExpr := feltLit 9223372036854775808
      pure (ls1 ++
        #[.assert (.binary o' .ne intMin) "i64 neg overflow (intMin)",
          .letBind name "Felt" (.binary (feltLit 0) .sub o')],
        .local name, ctx2)
  | .fieldBinary op l r => do
      -- T14 catalog v2 (Goldilocks): native Felt field arithmetic. Felt ops
      -- are exact mod Goldilocks, so no checked-overflow guard is emitted.
      let psyOp := match op with
        | .add => PsyBinaryOp.add | .sub => .sub | .mul => .mul | .div => .div
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "Felt" (.binary l' psyOp r')],
        .local name, ctx3)
  | .fieldCompare op l r => do
      -- T14 catalog v2 (Goldilocks): native Felt field equality (eq/ne only).
      let psyOp := match op with
        | .eq => PsyBinaryOp.eq | .ne => .ne
        | _ => PsyBinaryOp.eq  -- unreachable: Normalize rejects Field ordering
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (name, ctx3) := freshName ctx2
      pure (ls1 ++ ls2 ++
        #[.letBind name "bool" (.binary l' psyOp r')],
        .local name, ctx3)
  | .fieldNeg operand => do
      -- T14 catalog v2 (Goldilocks): native Felt field negation `0 - x`
      -- (Goldilocks inverse; every Felt is in [0,p) so no intMin revert).
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++
        #[.letBind name "Felt" (.binary (feltLit 0) .sub o')],
        .local name, ctx2)
  | .signedCompare op l r => do
      -- Signed compare of Int64 bit patterns: subtract bias 2^63 then unsigned cmp.
      -- 2^63 < Goldilocks p, so the bias is a legal Felt literal.
      let psyOp := match op with
        | .eq => PsyBinaryOp.eq | .ne => .ne | .lt => .lt
        | .le => .le | .gt => .gt | .ge => .ge
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (nl, ctx3) := freshName ctx2
      let (nr, ctx4) := freshName ctx3
      let (name, ctx5) := freshName ctx4
      let bias : PsyExpr := feltLit 9223372036854775808
      pure (ls1 ++ ls2 ++
        #[.letBind nl "Felt" (.binary l' .add bias),
          .letBind nr "Felt" (.binary r' .add bias),
          .letBind name "bool" (.binary (.local nl) psyOp (.local nr))],
        .local name, ctx5)
  | .narrowSignedCompare w op l r => do
      -- Two's-complement bit patterns in 0..2^w-1; bias by 2^(w-1) then unsigned.
      let psyOp := match op with
        | .eq => PsyBinaryOp.eq | .ne => .ne | .lt => .lt
        | .le => .le | .gt => .gt | .ge => .ge
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (nl, ctx3) := freshName ctx2
      let (nr, ctx4) := freshName ctx3
      let (name, ctx5) := freshName ctx4
      let bias := feltLit (Nat.pow 2 (w - 1))
      pure (ls1 ++ ls2 ++
        #[.letBind nl "Felt" (.binary l' .add bias),
          .letBind nr "Felt" (.binary r' .add bias),
          .letBind name "bool" (.binary (.local nl) psyOp (.local nr))],
        .local name, ctx5)
  | .narrowCheckedNeg w operand => do
      -- Two's-complement negation: intMin traps; else (0 - x) mod 2^w.
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      let zero := feltLit 0
      pure (ls1 ++
        #[.assert (.binary o' .ne half) s!"i{w} neg overflow (intMin)",
          .letBind name "Felt"
            (.ifExpr (.binary o' .eq zero) zero
              (.binary bound .sub o'))],
        .local name, ctx2)
  | .narrowSignedCheckedAdd w l r => do
      -- Modular two's-complement add + same-sign overflow trap.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (sumN, ctx3) := freshName ctx2
      let (wrapN, ctx4) := freshName ctx3
      let (saN, ctx5) := freshName ctx4
      let (sbN, ctx6) := freshName ctx5
      let (srN, ctx7) := freshName ctx6
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      pure (ls1 ++ ls2 ++
        #[.letBind sumN "Felt" (.binary l' .add r'),
          .letBind wrapN "Felt"
            (.ifExpr (.binary (.local sumN) .ge bound)
              (.binary (.local sumN) .sub bound) (.local sumN)),
          .letBind saN "bool" (.binary l' .ge half),
          .letBind sbN "bool" (.binary r' .ge half),
          .letBind srN "bool" (.binary (.local wrapN) .ge half),
          .assert
            (.unary .not
              (.binary
                (.binary (.binary (.local saN) .boolAnd (.local sbN))
                  .boolOr
                  (.binary (.unary .not (.local saN)) .boolAnd
                    (.unary .not (.local sbN))))
                .boolAnd
                (.binary (.local saN) .ne (.local srN))))
            s!"i{w} add overflow"],
        .local wrapN, ctx7)
  | .narrowSignedCheckedSub w l r => do
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let (diffN, ctx3) := freshName ctx2
      let (saN, ctx4) := freshName ctx3
      let (sbN, ctx5) := freshName ctx4
      let (srN, ctx6) := freshName ctx5
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      pure (ls1 ++ ls2 ++
        #[.letBind diffN "Felt"
            (.ifExpr (.binary l' .ge r') (.binary l' .sub r')
              (.binary (.binary l' .add bound) .sub r')),
          .letBind saN "bool" (.binary l' .ge half),
          .letBind sbN "bool" (.binary r' .ge half),
          .letBind srN "bool" (.binary (.local diffN) .ge half),
          .assert
            (.unary .not
              (.binary
                (.binary
                  (.binary (.local saN) .boolAnd (.unary .not (.local sbN)))
                  .boolOr
                  (.binary (.unary .not (.local saN)) .boolAnd (.local sbN)))
                .boolAnd
                (.binary (.local saN) .ne (.local srN))))
            s!"i{w} sub overflow"],
        .local diffN, ctx6)
  | .narrowSignedCheckedMul w l r => do
      -- Magnitude product in Felt (≤ (2^(w-1))^2 < p for w≤32) then re-sign.
      -- intMin has no positive abs in w bits: only allow *0/*1/*-1 specials.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      let zero := feltLit 0
      let one := feltLit 1
      let negOne := feltLit (Nat.pow 2 w - 1)
      let (saN, ctx3) := freshName ctx2
      let (sbN, ctx4) := freshName ctx3
      let (absA, ctx5) := freshName ctx4
      let (absB, ctx6) := freshName ctx5
      let (prodAbs, ctx7) := freshName ctx6
      let (qN, ctx8) := freshName ctx7
      pure (ls1 ++ ls2 ++
        #[.letBind saN "bool" (.binary l' .ge half),
          .letBind sbN "bool" (.binary r' .ge half),
          -- Reject intMin unless the other factor is 0, 1, or -1 (exact cases).
          .assert
            (.unary .not
              (.binary (.binary l' .eq half) .boolAnd
                (.unary .not
                  (.binary (.binary r' .eq zero) .boolOr
                    (.binary (.binary r' .eq one) .boolOr (.binary r' .eq negOne))))))
            s!"i{w} mul overflow (intMin)",
          .assert
            (.unary .not
              (.binary (.binary r' .eq half) .boolAnd
                (.unary .not
                  (.binary (.binary l' .eq zero) .boolOr
                    (.binary (.binary l' .eq one) .boolOr (.binary l' .eq negOne))))))
            s!"i{w} mul overflow (intMin)",
          .letBind absA "Felt"
            (.ifExpr (.local saN)
              (.ifExpr (.binary l' .eq half) half (.binary bound .sub l')) l'),
          .letBind absB "Felt"
            (.ifExpr (.local sbN)
              (.ifExpr (.binary r' .eq half) half (.binary bound .sub r')) r'),
          .letBind prodAbs "Felt" (.binary (.local absA) .mul (.local absB)),
          -- Magnitude must fit in signed range: prodAbs < half, or intMin exact
          -- when result is negative and prodAbs == half.
          .assert
            (.binary
              (.binary (.local prodAbs) .lt half)
              .boolOr
              (.binary (.binary (.local prodAbs) .eq half) .boolAnd
                (.binary
                  (.binary (.local saN) .boolAnd (.unary .not (.local sbN)))
                  .boolOr
                  (.binary (.unary .not (.local saN)) .boolAnd (.local sbN)))))
            s!"i{w} mul overflow",
          .letBind qN "Felt"
            (.ifExpr (.binary (.local prodAbs) .eq zero) zero
              (.ifExpr
                (.binary
                  (.binary (.local saN) .boolAnd (.unary .not (.local sbN)))
                  .boolOr
                  (.binary (.unary .not (.local saN)) .boolAnd (.local sbN)))
                (.ifExpr (.binary (.local prodAbs) .eq half) half
                  (.binary bound .sub (.local prodAbs)))
                (.local prodAbs)))],
        .local qN, ctx8)
  | .narrowSignedCheckedDiv w l r => do
      -- Signed division on two's-complement bit patterns via bias to nonneg domain is hard;
      -- implement trunc-toward-zero using absolute values in Felt.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      let zero := feltLit 0
      let (saN, ctx3) := freshName ctx2
      let (sbN, ctx4) := freshName ctx3
      let (absA, ctx5) := freshName ctx4
      let (absB, ctx6) := freshName ctx5
      let (qAbs, ctx7) := freshName ctx6
      let (qN, ctx8) := freshName ctx7
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne zero) s!"i{w} div by zero",
          -- intMin / -1 overflows
          .assert
            (.unary .not
              (.binary (.binary l' .eq half) .boolAnd (.binary r' .eq
                (.binary bound .sub (feltLit 1)))))
            s!"i{w} div overflow (intMin / -1)",
          .letBind saN "bool" (.binary l' .ge half),
          .letBind sbN "bool" (.binary r' .ge half),
          .letBind absA "Felt"
            (.ifExpr (.local saN) (.binary bound .sub l') l'),
          .letBind absB "Felt"
            (.ifExpr (.local sbN) (.binary bound .sub r') r'),
          .letBind qAbs "Felt" (.binary (.local absA) .div (.local absB)),
          .letBind qN "Felt"
            (.ifExpr
              (.binary
                (.binary (.local saN) .boolAnd (.unary .not (.local sbN)))
                .boolOr
                (.binary (.unary .not (.local saN)) .boolAnd (.local sbN)))
              (.ifExpr (.binary (.local qAbs) .eq zero) zero
                (.binary bound .sub (.local qAbs)))
              (.local qAbs))],
        .local qN, ctx8)
  | .narrowSignedCheckedMod w l r => do
      -- a % b with trunc-toward-zero: remainder has sign of dividend.
      let (ls1, l', ctx1) ← lowerExprStmt ctx l
      let (ls2, r', ctx2) ← lowerExprStmt ctx1 r
      let bound := feltLit (Nat.pow 2 w)
      let half := feltLit (Nat.pow 2 (w - 1))
      let zero := feltLit 0
      let (saN, ctx3) := freshName ctx2
      let (absA, ctx4) := freshName ctx3
      let (absB, ctx5) := freshName ctx4
      let (rAbs, ctx6) := freshName ctx5
      let (rN, ctx7) := freshName ctx6
      pure (ls1 ++ ls2 ++
        #[.assert (.binary r' .ne zero) s!"i{w} mod by zero",
          .letBind saN "bool" (.binary l' .ge half),
          .letBind absA "Felt"
            (.ifExpr (.local saN) (.binary bound .sub l') l'),
          .letBind absB "Felt"
            (.ifExpr (.binary r' .ge half) (.binary bound .sub r') r'),
          .letBind rAbs "Felt" (.binary (.local absA) .mod (.local absB)),
          .letBind rN "Felt"
            (.ifExpr (.local saN)
              (.ifExpr (.binary (.local rAbs) .eq zero) zero
                (.binary bound .sub (.local rAbs)))
              (.local rAbs))],
        .local rN, ctx7)
  | .callFn fnName args => do
      let mut stmts : Array PsyStmt := #[]
      let mut args' : Array PsyExpr := #[]
      let mut ctx' := ctx
      for arg in args do
        let (ls, a', ctx1) ← lowerExprStmt ctx' arg
        stmts := stmts ++ ls
        args' := args'.push a'
        ctx' := ctx1
      let (name, ctx2) := freshName ctx'
      pure (stmts ++ #[.letBind name "Felt" (.call fnName args')], .local name, ctx2)

private def appendFeltBinding
    (out : Array PsyStmt) (ctx : EmitCtx) (value : PsyExpr) :
    Array PsyStmt × PsyExpr × EmitCtx :=
  let (name, ctx') := freshName ctx
  (out.push (.letBind name "Felt" value), .local name, ctx')

/-- Emit the frozen checked UInt128 multiplication algorithm.

The physical ABI remains 4×UInt32 Felt limbs. Each limb is split into two
UInt16 digits. Products are normalized one at a time rather than summing a
whole convolution column: Psy v0.1.0 routes Felt bit operations through its
u32 circuit ops, so every operand to `& 65535` / `>> 16` is kept strictly
below 2^32. For B=2^16, each digit product is <B^2, `low + productLow` is
<2B, and the running carry remains <8B. Consequently every Felt add/mul is
also far below Goldilocks and cannot reduce modulo p. -/
private def emitWideUintMul
    (ctx : EmitCtx) (bitWidth operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult (Array PsyStmt × EmitCtx) := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "Psy emission: wide mul bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  let digitCount := limbCount * 2
  let productDigits := digitCount * 2
  unless lhs.size == limbCount && rhs.size == limbCount do
    planError s!"Psy emission: bindWideUintMul requires two {limbCount}-limb operands"
  let mask := feltLit 65535
  let shift := feltLit 16
  let base := feltLit 65536
  let zero := feltLit 0
  let mut out : Array PsyStmt := #[]
  let mut ctx' := ctx
  let mut lhsLimbs : Array PsyExpr := #[]
  let mut rhsLimbs : Array PsyExpr := #[]

  -- Snapshot all physical limbs before any derived arithmetic.
  for value in lhs do
    let (exprStmts, lowered, ctx1) ← lowerExprStmt ctx' value
    out := out ++ exprStmts
    let (out1, snapshot, ctx2) := appendFeltBinding out ctx1 lowered
    out := out1
    lhsLimbs := lhsLimbs.push snapshot
    ctx' := ctx2
  for value in rhs do
    let (exprStmts, lowered, ctx1) ← lowerExprStmt ctx' value
    out := out ++ exprStmts
    let (out1, snapshot, ctx2) := appendFeltBinding out ctx1 lowered
    out := out1
    rhsLimbs := rhsLimbs.push snapshot
    ctx' := ctx2

  -- UInt32 limbs → little-endian UInt16 digits per operand.
  let mut lhsDigits : Array PsyExpr := #[]
  let mut rhsDigits : Array PsyExpr := #[]
  for limb in lhsLimbs do
    let (out1, lo, ctx1) :=
      appendFeltBinding out ctx' (.binary limb .bitAnd mask)
    let (out2, hi, ctx2) :=
      appendFeltBinding out1 ctx1 (.binary limb .shiftRight shift)
    out := out2
    lhsDigits := lhsDigits.push lo |>.push hi
    ctx' := ctx2
  for limb in rhsLimbs do
    let (out1, lo, ctx1) :=
      appendFeltBinding out ctx' (.binary limb .bitAnd mask)
    let (out2, hi, ctx2) :=
      appendFeltBinding out1 ctx1 (.binary limb .shiftRight shift)
    out := out2
    rhsDigits := rhsDigits.push lo |>.push hi
    ctx' := ctx2

  -- Full double-width product, base 2^16. Sequential product normalization
  -- keeps every bit-operation operand below 2^32.
  let mut digits : Array PsyExpr := #[]
  let mut carry : PsyExpr := zero
  for k in [0:productDigits] do
    let (out1, low0, ctx1) :=
      appendFeltBinding out ctx' (.binary carry .bitAnd mask)
    let (out2, carry0, ctx2) :=
      appendFeltBinding out1 ctx1 (.binary carry .shiftRight shift)
    out := out2
    ctx' := ctx2
    let mut low := low0
    let mut nextCarry := carry0
    for i in [0:digitCount] do
      if i ≤ k then
        let j := k - i
        if j < digitCount then
          let a ← match lhsDigits[i]? with
            | some value => pure value
            | none => planError "Psy emission: wide mul lhs digit is missing"
          let b ← match rhsDigits[j]? with
            | some value => pure value
            | none => planError "Psy emission: wide mul rhs digit is missing"
          let (out3, product, ctx3) :=
            appendFeltBinding out ctx' (.binary a .mul b)
          let (out4, productLow, ctx4) :=
            appendFeltBinding out3 ctx3 (.binary product .bitAnd mask)
          let (out5, productHigh, ctx5) :=
            appendFeltBinding out4 ctx4 (.binary product .shiftRight shift)
          let (out6, sum, ctx6) :=
            appendFeltBinding out5 ctx5 (.binary low .add productLow)
          let (out7, carryBit, ctx7) :=
            appendFeltBinding out6 ctx6 (.binary sum .shiftRight shift)
          let (out8, normalizedLow, ctx8) :=
            appendFeltBinding out7 ctx7 (.binary sum .bitAnd mask)
          let carrySum :=
            .binary (.binary nextCarry .add productHigh) .add carryBit
          let (out9, normalizedCarry, ctx9) :=
            appendFeltBinding out8 ctx8 carrySum
          out := out9
          ctx' := ctx9
          low := normalizedLow
          nextCarry := normalizedCarry
    digits := digits.push low
    carry := nextCarry

  -- Checked wide mul: upper base-2^16 digits and final carry must be zero.
  let overflowMsg := if bitWidth == 256 then "u256 mul overflow" else "u128 mul overflow"
  let mut noOverflow : PsyExpr := .binary carry .eq zero
  for i in [digitCount:productDigits] do
    let digit ← match digits[i]? with
      | some value => pure value
      | none => planError "Psy emission: wide product digit is missing"
    noOverflow := .binary noOverflow .boolAnd (.binary digit .eq zero)
  out := out.push (.assert noOverflow overflowMsg)

  -- Repack the low UInt16 digits into UInt32 Felt limbs.
  for limbIndex in [0:limbCount] do
    let loIndex := limbIndex * 2
    let hiIndex := loIndex + 1
    let lo ← match digits[loIndex]? with
      | some value => pure value
      | none => planError "Psy emission: wide mul low result digit is missing"
    let hi ← match digits[hiIndex]? with
      | some value => pure value
      | none => planError "Psy emission: wide mul high result digit is missing"
    let (out1, scaledHigh, ctx1) :=
      appendFeltBinding out ctx' (.binary hi .mul base)
    out := out1.push
      (.letBind (wideUintMulLimbName operationId limbIndex) "Felt"
        (.binary lo .add scaledHigh))
    ctx' := ctx1
  pure (out, ctx')

private def emitWideUInt128Mul
    (ctx : EmitCtx) (operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult (Array PsyStmt × EmitCtx) :=
  emitWideUintMul ctx 128 operationId lhs rhs

private def wideDivLexGe
    (remainder divisor : Array PsyExpr) : CompileResult PsyExpr := do
  let limbCount := divisor.size
  unless remainder.size == limbCount + 1 do
    planError "Psy emission: wide div comparison remainder must be one limb wider than divisor"
  -- Lexicographic >= from low limb upward, then high remainder limb.
  let zero := feltLit 0
  let mut acc : PsyExpr := .binary remainder[0]! .ge divisor[0]!
  for i in [1:limbCount] do
    let limbGt := .binary remainder[i]! .gt divisor[i]!
    let limbEq := .binary remainder[i]! .eq divisor[i]!
    acc := .binary limbGt .boolOr (.binary limbEq .boolAnd acc)
  pure <| .binary (.binary remainder[limbCount]! .ne zero) .boolOr acc

/-- One fixed 32-step region of the wide restoring divider. -/
private def emitWideUintDivLoop
    (operationId limbCount sourceIndex : Nat) (source divisorZero : PsyExpr)
    (divisor : Array PsyExpr) : CompileResult (Array PsyStmt) := do
  unless sourceIndex < limbCount && divisor.size == limbCount do
    planError "Psy emission: wide div loop shape mismatch"
  let nameRoot := wideUInt128DivModPrefix operationId
  let tag := s!"a{sourceIndex}"
  let n (suffix : String) : String := s!"{nameRoot}_{suffix}_{tag}"
  let mut rNames : Array String := #[]
  for i in [0:limbCount + 1] do
    rNames := rNames.push s!"{nameRoot}_r{i}"
  let mut qNames : Array String := #[]
  for i in [0:limbCount] do
    qNames := qNames.push s!"{nameRoot}_q{i}"
  let remainder := rNames.map PsyExpr.local
  let quotient := qNames.map PsyExpr.local
  let zero := feltLit 0
  let one := feltLit 1
  let base := feltLit 4294967296
  let shiftOne := feltLit 1
  let shiftTop := feltLit 31
  let workName := s!"{nameRoot}_work_{tag}"
  let loopIndex := s!"{nameRoot}_i_{tag}"
  let bitName := n "bit"
  let mut body : Array PsyStmt := #[]
  body := body.push (.letBind bitName "Felt"
    (.binary (.local workName) .shiftRight shiftTop))
  body := body.push (.localAssign workName
    (.binary (.local workName) .shiftLeft shiftOne))

  let mut carryNames : Array String := #[]
  for i in [0:limbCount] do
    let carryName := n s!"rc{i}"
    body := body.push (.letBind carryName "Felt"
      (.binary remainder[i]! .shiftRight shiftTop))
    carryNames := carryNames.push carryName
  body := body.push (.localAssign rNames[0]!
    (.binary (.binary remainder[0]! .shiftLeft shiftOne) .bitOr (.local bitName)))
  for i in [1:limbCount] do
    body := body.push (.localAssign rNames[i]!
      (.binary (.binary remainder[i]! .shiftLeft shiftOne) .bitOr
        (.local carryNames[i - 1]!)))
  body := body.push (.localAssign rNames[limbCount]! (.local carryNames[limbCount - 1]!))

  let takeName := n "take"
  let takeExpr ← wideDivLexGe (rNames.map PsyExpr.local) divisor
  body := body.push (.letBind takeName "bool" takeExpr)
  let take := PsyExpr.local takeName

  let mut borrow : PsyExpr := zero
  let mut diffNames : Array String := #[]
  for i in [0:limbCount] do
    let subName := n s!"sub{i}"
    let underName := n s!"under{i}"
    let directName := n s!"direct{i}"
    let wrappedName := n s!"wrapped{i}"
    let diffName := n s!"diff{i}"
    let borrowName := n s!"borrow{i + 1}"
    body := body.push (.letBind subName "Felt" (.binary divisor[i]! .add borrow))
    body := body.push (.letBind underName "bool"
      (.binary (.local rNames[i]!) .lt (.local subName)))
    body := body.push (.letBind directName "Felt"
      (.binary (.local rNames[i]!) .sub (.local subName)))
    body := body.push (.letBind wrappedName "Felt"
      (.binary (.binary (.local rNames[i]!) .add base) .sub (.local subName)))
    body := body.push (.letBind diffName "Felt"
      (.ifExpr (.local underName) (.local wrappedName) (.local directName)))
    body := body.push (.letBind borrowName "Felt"
      (.ifExpr (.local underName) one zero))
    diffNames := diffNames.push diffName
    borrow := .local borrowName

  let highOkName := n "high_ok"
  body := body.push (.letBind highOkName "bool"
    (.binary (.unary .not take) .boolOr
      (.binary (.local rNames[limbCount]!) .eq borrow)))
  body := body.push (.assert
    (.binary divisorZero .boolOr (.local highOkName))
    "u128 div internal high borrow")
  let highDiffName := n "high_diff"
  body := body.push (.letBind highDiffName "Felt"
    (.binary (.local rNames[limbCount]!) .sub borrow))
  for i in [0:limbCount] do
    body := body.push (.localAssign rNames[i]!
      (.ifExpr take (.local diffNames[i]!) (.local rNames[i]!)))
  body := body.push (.localAssign rNames[limbCount]!
    (.ifExpr take (.local highDiffName) (.local rNames[limbCount]!)))
  body := body.push (.assert
    (.binary divisorZero .boolOr (.binary (.local rNames[limbCount]!) .eq zero))
    "u128 div internal remainder high")

  let qbitName := n "qbit"
  body := body.push (.letBind qbitName "Felt" (.ifExpr take one zero))
  let mut qCarryNames : Array String := #[]
  for i in [0:limbCount] do
    let carryName := n s!"qc{i}"
    body := body.push (.letBind carryName "Felt"
      (.binary quotient[i]! .shiftRight shiftTop))
    qCarryNames := qCarryNames.push carryName
  body := body.push (.localAssign qNames[0]!
    (.binary (.binary quotient[0]! .shiftLeft shiftOne) .bitOr (.local qbitName)))
  for i in [1:limbCount] do
    body := body.push (.localAssign qNames[i]!
      (.binary (.binary quotient[i]! .shiftLeft shiftOne) .bitOr
        (.local qCarryNames[i - 1]!)))
  body := body.push (.assert
    (.binary divisorZero .boolOr (.binary (.local qCarryNames[limbCount - 1]!) .eq zero))
    "u128 div internal quotient overflow")
  pure #[.letMutBind workName "Felt" source,
    .boundedFor loopIndex 0 32 body]

private def emitWideUintDivMod
    (ctx : EmitCtx) (resultKind : WideUInt128DivModResultV1)
    (bitWidth operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult (Array PsyStmt × EmitCtx) := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "Psy emission: wide div bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  unless lhs.size == limbCount && rhs.size == limbCount do
    planError s!"Psy emission: bindWideUintDivMod requires two {limbCount}-limb operands"
  let nameRoot := wideUInt128DivModPrefix operationId
  let base := feltLit 4294967296
  let zero := feltLit 0
  let mut out : Array PsyStmt := #[]
  let mut ctx' := ctx
  let mut left : Array PsyExpr := #[]
  let mut right : Array PsyExpr := #[]
  let rangeMsg := if bitWidth == 256 then "u256 div operand limb out of range"
    else "u128 div operand limb out of range"
  let zeroMessage := match resultKind, bitWidth with
    | .quotient, 256 => "u256 div by zero"
    | .remainder, 256 => "u256 mod by zero"
    | .quotient, _ => "u128 div by zero"
    | .remainder, _ => "u128 mod by zero"

  for i in [0:limbCount] do
    let value ← match lhs[i]? with
      | some found => pure found
      | none => planError "Psy emission: wide dividend limb is missing"
    let (exprStmts, lowered, ctx1) ← lowerExprStmt ctx' value
    let rawName := s!"{nameRoot}_a{i}_raw"
    let safeName := s!"{nameRoot}_a{i}"
    let inRange := PsyExpr.binary (.local rawName) .lt base
    out := out ++ exprStmts ++
      #[.letBind rawName "Felt" lowered,
        .assert inRange rangeMsg,
        .letBind safeName "Felt" (.ifExpr inRange (.local rawName) zero)]
    left := left.push (.local safeName)
    ctx' := ctx1
  for i in [0:limbCount] do
    let value ← match rhs[i]? with
      | some found => pure found
      | none => planError "Psy emission: wide divisor limb is missing"
    let (exprStmts, lowered, ctx1) ← lowerExprStmt ctx' value
    let rawName := s!"{nameRoot}_b{i}_raw"
    let safeName := s!"{nameRoot}_b{i}"
    let inRange := PsyExpr.binary (.local rawName) .lt base
    out := out ++ exprStmts ++
      #[.letBind rawName "Felt" lowered,
        .assert inRange rangeMsg,
        .letBind safeName "Felt" (.ifExpr inRange (.local rawName) zero)]
    right := right.push (.local safeName)
    ctx' := ctx1

  let divisorZeroName := s!"{nameRoot}_divisor_zero"
  let mut divisorZero : PsyExpr := .binary right[0]! .eq zero
  for i in [1:limbCount] do
    divisorZero := .binary divisorZero .boolAnd (.binary right[i]! .eq zero)
  out := out.push (.letBind divisorZeroName "bool" divisorZero)
  let divisorZeroLocal := PsyExpr.local divisorZeroName
  out := out.push (.assert (.unary .not divisorZeroLocal) zeroMessage)

  for i in [0:limbCount + 1] do
    out := out.push (.letMutBind s!"{nameRoot}_r{i}" "Felt" zero)
  for i in [0:limbCount] do
    out := out.push (.letMutBind s!"{nameRoot}_q{i}" "Felt" zero)
  -- MSB-first: highest limb index down to 0
  for sourceIndex in List.range limbCount |>.reverse do
    let loopStmts ← emitWideUintDivLoop operationId limbCount sourceIndex
      left[sourceIndex]! divisorZeroLocal right
    out := out ++ loopStmts
  pure (out, ctx')

private def emitWideUInt128DivMod
    (ctx : EmitCtx) (resultKind : WideUInt128DivModResultV1)
    (operationId : Nat) (lhs rhs : Array Expr) :
    CompileResult (Array PsyStmt × EmitCtx) :=
  emitWideUintDivMod ctx resultKind 128 operationId lhs rhs

/-- Exact wide logical shift with fixed bitWidth-step one-bit walk. -/
private def emitWideUintShift
    (ctx : EmitCtx) (kind : WideUInt128ShiftKindV1)
    (bitWidth operationId : Nat) (value : Array Expr) (count : Expr) :
    CompileResult (Array PsyStmt × EmitCtx) := do
  unless bitWidth == 128 || bitWidth == 256 do
    planError "Psy emission: wide shift bitWidth must be 128 or 256"
  let limbCount := bitWidth / 32
  unless value.size == limbCount do
    planError s!"Psy emission: bindWideUintShift requires {limbCount} value limbs"
  let nameRoot := wideUInt128ShiftPrefix operationId
  let tag := match kind with | .shl => "l" | .shr => "r"
  let mut limbNames : Array String := #[]
  for i in [0:limbCount] do
    limbNames := limbNames.push s!"{nameRoot}_{tag}{i}"
  let base := feltLit 4294967296
  let zero := feltLit 0
  let one := feltLit 1
  let shiftOne := feltLit 1
  let shiftTop := feltLit 31
  let rangeMsg := if bitWidth == 256 then "u256 shift operand limb out of range"
    else "u128 shift operand limb out of range"
  let overflowMsg := if bitWidth == 256 then "u256 shl overflow" else "u128 shl overflow"
  let mut out : Array PsyStmt := #[]
  let mut ctx' := ctx

  for i in [0:limbCount] do
    let leaf ← match value[i]? with
      | some found => pure found
      | none => planError "Psy emission: wide shift value limb is missing"
    let (exprStmts, lowered, ctx1) ← lowerExprStmt ctx' leaf
    let rawName := s!"{nameRoot}_v{i}_raw"
    let inRange := PsyExpr.binary (.local rawName) .lt base
    out := out ++ exprStmts ++
      #[.letBind rawName "Felt" lowered,
        .assert inRange rangeMsg,
        .letMutBind limbNames[i]! "Felt"
          (.ifExpr inRange (.local rawName) zero)]
    ctx' := ctx1

  let (countStmts, countExpr, ctx2) ← lowerExprStmt ctx' count
  let countRaw := s!"{nameRoot}_count_raw"
  -- `for i in 0u32..N` binds `i : u32`. Compare against a u32 count
  -- (count already asserted < bitWidth ≤ 256) — Felt vs u32 is a dargo TypeMismatch.
  let countName := s!"{nameRoot}_count"
  out := out ++ countStmts ++
    #[.letBind countRaw "Felt" countExpr,
      .assert (.binary (.local countRaw) .lt (feltLit bitWidth))
        s!"invalidShift: count >= {bitWidth}",
      .letBind countName "u32" (.cast (.local countRaw) "u32")]
  ctx' := ctx2
  let countLocal := PsyExpr.local countName

  let loopIndex := s!"{nameRoot}_i"
  let takeName := s!"{nameRoot}_take"
  let mut body : Array PsyStmt := #[]
  body := body.push (.letBind takeName "bool"
    (.binary (.local loopIndex) .lt countLocal))
  let take := PsyExpr.local takeName
  match kind with
  | .shl => do
      let mut carryNames : Array String := #[]
      for i in [0:limbCount] do
        let carryName := s!"{nameRoot}_c{i}"
        body := body.push (.letBind carryName "Felt"
          (.binary (.local limbNames[i]!) .shiftRight shiftTop))
        carryNames := carryNames.push carryName
      body := body.push (.assert
        (.binary (.unary .not take) .boolOr
          (.binary (.local carryNames[limbCount - 1]!) .eq zero))
        overflowMsg)
      body := body.push (.localAssign limbNames[0]!
        (.ifExpr take
          (.binary (.local limbNames[0]!) .shiftLeft shiftOne)
          (.local limbNames[0]!)))
      for i in [1:limbCount] do
        body := body.push (.localAssign limbNames[i]!
          (.ifExpr take
            (.binary
              (.binary (.local limbNames[i]!) .shiftLeft shiftOne)
              .bitOr (.local carryNames[i - 1]!))
            (.local limbNames[i]!)))
  | .shr => do
      let mut lowBitNames : Array String := #[]
      for i in [0:limbCount] do
        let lowName := s!"{nameRoot}_lb{i}"
        body := body.push (.letBind lowName "Felt"
          (.binary (.local limbNames[i]!) .bitAnd one))
        lowBitNames := lowBitNames.push lowName
      body := body.push (.localAssign limbNames[limbCount - 1]!
        (.ifExpr take
          (.binary (.local limbNames[limbCount - 1]!) .shiftRight shiftOne)
          (.local limbNames[limbCount - 1]!)))
      for i in [0:limbCount - 1] do
        let idx := limbCount - 2 - i
        body := body.push (.localAssign limbNames[idx]!
          (.ifExpr take
            (.binary
              (.binary (.local limbNames[idx]!) .shiftRight shiftOne)
              .bitOr
              (.binary (.local lowBitNames[idx + 1]!) .shiftLeft shiftTop))
            (.local limbNames[idx]!)))
  out := out.push (.boundedFor loopIndex 0 bitWidth body)
  pure (out, ctx')

private def emitWideUInt128Shift
    (ctx : EmitCtx) (kind : WideUInt128ShiftKindV1) (operationId : Nat)
    (value : Array Expr) (count : Expr) :
    CompileResult (Array PsyStmt × EmitCtx) :=
  emitWideUintShift ctx kind 128 operationId value count

private partial def emitStatements
    (ctx : EmitCtx) (stmts : Array Statement) (loopDepth : Nat) :
    CompileResult (Array PsyStmt × EmitCtx) := do
  let mut out : Array PsyStmt := #[]
  let mut ctx := ctx
  for stmt in stmts do
    match stmt with
    | .store fieldIndex value => do
        let (exprStmts, psy, ctx1) ← lowerExprStmt ctx value
        let name ← match ctx1.stateNames[fieldIndex]? with
          | some n => pure n
          | none => planError "Psy emission: store references a missing state field"
        out := out ++ exprStmts ++ #[.storageWrite name psy]
        ctx := ctx1
    | .storeAggregate fieldIndices values => do
        unless fieldIndices.size > 1 && fieldIndices.size == values.size do
          planError "Psy emission: storeAggregate field/value shape mismatch"
        -- Evaluate and snapshot every leaf before the first storage write.
        -- This preserves aggregate atomicity when later leaf expressions read
        -- earlier fields from the same logical state (notably UInt128 carry).
        let mut evalStmts : Array PsyStmt := #[]
        let mut snapshots : Array PsyExpr := #[]
        let mut ctx' := ctx
        for value in values do
          let (exprStmts, psy, ctx1) ← lowerExprStmt ctx' value
          let (snapshotName, ctx2) := freshName ctx1
          evalStmts := evalStmts ++ exprStmts ++
            #[.letBind snapshotName "Felt" psy]
          snapshots := snapshots.push (.local snapshotName)
          ctx' := ctx2
        out := out ++ evalStmts
        for i in [0:fieldIndices.size] do
          let some fieldIndex := fieldIndices[i]? |
            planError "Psy emission: storeAggregate field index missing"
          let some snapshot := snapshots[i]? |
            planError "Psy emission: storeAggregate snapshot missing"
          let name ← match ctx'.stateNames[fieldIndex]? with
            | some n => pure n
            | none => planError "Psy emission: storeAggregate references a missing state field"
          out := out.push (.storageWrite name snapshot)
        ctx := ctx'
    | .bindWideUintMul bitWidth operationId lhs rhs => do
        let (mulStmts, ctx1) ← emitWideUintMul ctx bitWidth operationId lhs rhs
        out := out ++ mulStmts
        ctx := ctx1
    | .bindWideUintDivMod resultKind bitWidth operationId lhs rhs => do
        let (divStmts, ctx1) ← emitWideUintDivMod ctx resultKind bitWidth operationId lhs rhs
        out := out ++ divStmts
        ctx := ctx1
    | .bindWideUintShift kind bitWidth operationId value count => do
        let (shiftStmts, ctx1) ← emitWideUintShift ctx kind bitWidth operationId value count
        out := out ++ shiftStmts
        ctx := ctx1
    | .assert condition => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c' "assert failed"]
        ctx := ctx1
    | .assertWithMessage condition message => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c' message]
        ctx := ctx1
    | .returnValue value => do
        let (exprStmts, psy, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts ++ #[.returnExpr psy]
        ctx := ctx1
    | .returnAggregate leaves _leafIsInt => do
        -- B-RET-ABI: lower each preorder leaf independently, pack as `[Felt; N]`.
        -- Int64 leaves are also Felt on the Psy surface (signed interpretation
        -- is emission-time for compares only); leafIsInt is Plan ABI metadata.
        let mut stmts : Array PsyStmt := #[]
        let mut elems : Array PsyExpr := #[]
        let mut ctx' := ctx
        for leaf in leaves do
          let (ls, e', ctx1) ← lowerExprStmt ctx' leaf
          stmts := stmts ++ ls
          elems := elems.push e'
          ctx' := ctx1
        out := out ++ stmts ++ #[.returnExpr (.arrayLit elems)]
        ctx := ctx'
    | .returnNone =>
        out := out.push .returnUnit
    | .ifThenElse condition thenBody elseBody => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        let (thenStmts, ctx2) ← emitStatements ctx1 thenBody loopDepth
        let (elseStmts, ctx3) ← emitStatements ctx2 elseBody loopDepth
        out := out ++ exprStmts ++ #[.ifElse c' thenStmts elseStmts]
        ctx := ctx3
    | .switchOn scrutinee cases defaultBody => do
        let (exprStmts, s', ctx1) ← lowerExprStmt ctx scrutinee
        out := out ++ exprStmts
        let mut caseList : List (PsyExpr × Array PsyStmt) := []
        let mut ctx' := ctx1
        for (value, caseBody) in cases do
          let (caseStmts, ctx2) ← emitStatements ctx' caseBody loopDepth
          caseList := caseList ++
            [((.binary s' .eq (feltLit value.toNat)), caseStmts)]
          ctx' := ctx2
        let (defaultStmts, ctx2) ← emitStatements ctx' defaultBody loopDepth
        ctx := ctx2
        let combined := caseList.foldr
          (fun (cond, caseStmts) acc => #[.ifElse cond caseStmts acc]) defaultStmts
        out := out ++ combined
    | .forLoop start endExclusive maxIter body => do
        -- PSY-LOOP: dargo v0.1.0 rejects the `for` keyword (UnrecognizedToken
        -- KeywordFor). Exact bounded semantics are preserved by *static
        -- unrolling* of `maxIterations` guarded steps:
        --   if start < end { assert(end - start <= N) }
        --   for k in 0..N-1:  i = start + k; if i < end { body }
        -- Cap unroll so emitted source stays finite; larger bounds FC.
        let maxUnroll : Nat := 64
        unless maxIter ≤ maxUnroll do
          planError
            s!"unsupported Psy semantic shape: bounded for maxIterations={maxIter} exceeds dargo unroll budget {maxUnroll} (dargo rejects for-syntax; PSY-LOOP)"
        let (startStmts, sLeo, ctx1) ← lowerExprStmt ctx start
        let (endStmts, eLeo, ctx2) ← lowerExprStmt ctx1 endExclusive
        let startName := s!"pf_start{loopDepth}"
        let endName := s!"pf_end{loopDepth}"
        let iName := s!"pf_i{loopDepth}"
        let (bodyStmts, ctx3) ← emitStatements ctx2 body (loopDepth + 1)
        let guardCond : PsyExpr :=
          .binary (.local startName) .lt (.local endName)
        let span : PsyExpr :=
          .binary (.local endName) .sub (.local startName)
        let fits : PsyExpr :=
          .binary span .le (feltLit maxIter)
        -- Body was emitted with loopVar → `pf_i{depth}`. Rebind that name
        -- only once by rewriting each unrolled step to a unique induction
        -- temp and substituting into a cloned body (dargo rejects re-let).
        let mut unrolled : Array PsyStmt := #[]
        for k in [0:maxIter] do
          let stepI := s!"{iName}_{k}"
          let induction : PsyExpr :=
            .binary (.local startName) .add (feltLit k)
          let stepGuard : PsyExpr :=
            .binary (.local stepI) .lt (.local endName)
          -- Substitute pf_i{depth} → pf_i{depth}_{k} in body statements by
          -- emitting body with a one-step rename via let alias inside the arm:
          --   let pf_i0: Felt = pf_i0_k; body...
          let bodyWithAlias :=
            #[.letBind iName "Felt" (.local stepI)] ++ bodyStmts
          unrolled := unrolled ++
            #[.letBind stepI "Felt" induction,
              .ifElse stepGuard bodyWithAlias #[]]
        out := out ++ startStmts ++ endStmts ++
          #[.letBind startName "Felt" sLeo,
            .letBind endName "Felt" eLeo,
            .ifElse guardCond #[.assert fits "boundExceeded"] #[]] ++
          unrolled
        ctx := ctx3
    | .emitEvent eventIndex args => do
        let evName ← match ctx.eventNames[eventIndex]? with
          | some n => pure n
          | none => planError "Psy emission: emit references a missing event"
        let mut stmts : Array PsyStmt := #[]
        let mut args' : Array PsyExpr := #[]
        let mut ctx' := ctx
        for arg in args do
          let (ls, a', ctx1) ← lowerExprStmt ctx' arg
          stmts := stmts ++ ls
          args' := args'.push a'
          ctx' := ctx1
        out := out ++ stmts ++ #[.eventEmit evName args']
        ctx := ctx'
    | .revertError errorIndex args => do
        -- PSY-TYPED-ERROR: Plan lower already rejects nonempty args; Emit
        -- depth-defends and tags zero-payload reverts as `revert:Name`.
        unless args.isEmpty do
          planError
            "unsupported Psy semantic shape: revert with error payload arguments is not admitted on Psy (PSY-TYPED-ERROR FC)"
        let errName := ctx.errorNames[errorIndex]?.getD "revert"
        out := out.push (.abort s!"revert:{errName}")
    | .bareRevert =>
        out := out.push (.abort "revert")
    | .externalCall callee args => do
        let (target, method, note) := hashCallee callee
        let mut stmts : Array PsyStmt := #[]
        let mut args' : Array PsyExpr := #[]
        let mut ctx' := ctx
        for arg in args do
          let (ls, a', ctx1) ← lowerExprStmt ctx' arg
          stmts := stmts ++ ls
          args' := args'.push a'
          ctx' := ctx1
        out := out ++ stmts ++ #[.crosscall target method args' false note]
        ctx := ctx'
    | .schedule _callee _args =>
        -- Depth defense: Plan lower already FC; never emit deferred-as-sync.
        throw <| .planInvariant .psy
          "unsupported Psy semantic shape: schedule is not admitted on Psy (no deferred crosscall form; PSY-CALL-EVENT FC)"
  pure (out, ctx)

private def asciiTitle (value : String) : String :=
  match value.toList with
  | [] => "Program"
  | c :: rest =>
      let upper :=
        let code := c.toNat
        if 97 <= code && code <= 122 then Char.ofNat (code - 32) else c
      String.ofList (upper :: rest)

private def asciiLower (value : String) : String :=
  String.ofList <| value.toList.map fun c =>
    let code := c.toNat
    if 65 <= code && code <= 90 then Char.ofNat (code + 32) else c

private def isSafeIdent (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      let isAlpha (c : Char) : Bool :=
        let code := c.toNat
        (65 <= code && code <= 90) || (97 <= code && code <= 122)
      let isDigit (c : Char) : Bool :=
        let code := c.toNat
        48 <= code && code <= 57
      (isAlpha first || first == '_') &&
        rest.all (fun c => isAlpha c || isDigit c || c == '_')

private def emitFunction (ctx : EmitCtx) (fn : PlanFunction) :
    CompileResult (PsyMethod × EmitCtx) := do
  unless isSafeIdent fn.name do
    planError s!"Psy function name '{fn.name}' is not a safe identifier"
  let params := fn.params.map fun p =>
    { name := s!"p{p.sourceIndex}", isBool := p.isBool, uintWidth := p.uintWidth }
  let resultLeafCount : Option Nat :=
    match fn.resultKind with
    | .aggregate leaves => some leaves.size
    | _ => none
  let (bodyCore, ctx1) ← emitStatements ctx fn.body 0
  -- Entry range checks for Felt-carried narrow params: reject high bits so
  -- external inputs cannot silently exceed the documented width.
  let mut rangeGuards : Array PsyStmt := #[]
  for p in params do
    if isNarrowUintWidth p.uintWidth then
      let bound := feltLit (narrowBound p.uintWidth)
      rangeGuards := rangeGuards.push
        (.assert (.binary (.local p.name) .lt bound)
          s!"u{p.uintWidth} param out of range")
  let body := rangeGuards ++ bodyCore
  pure ({
    name := fn.name
    params
    resultIsBool := fn.resultIsBool
    resultIsUnit := fn.resultIsUnit
    resultLeafCount
    isContractMethod := fn.kind != .pureHelper
    body
  }, ctx1)

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let contractName := asciiTitle plan.programName
  unless isSafeIdent contractName do
    planError s!"'{plan.programName}' cannot form a legal Psy contract name"
  let ctx0 : EmitCtx := {
    next := 0
    stateNames := plan.stateFieldNames
    eventNames := plan.events.map (·.name)
    errorNames := plan.errors.map (·.name)
  }
  let mut methods : Array PsyMethod := #[]
  let mut helpers : Array PsyMethod := #[]
  let mut ctx := ctx0
  for fn in plan.functions do
    let (m, ctx1) ← emitFunction ctx fn
    ctx := ctx1
    if fn.kind == .pureHelper then
      helpers := helpers.push m
    else
      methods := methods.push m
  let toolchainLabel := match plan.profileMode with
    | .sourceU64 => psyToolchain
    | .dargo010Vm => psyVmToolchain
  let module_ : PsyModule := {
    contractName
    headerComment :=
      "// Generated by proof-forge-next (Psy target, " ++ toolchainLabel ++ ").\n" ++
      "// This is Psy source intended for the official Dargo/Psy compiler toolchain."
    state := plan.stateFieldNames.map fun n => { name := n }
    methods
    helpers
    testName := s!"test_{asciiLower plan.programName}_fixture"
    testBody := #["// source-only fixture placeholder; no runtime claims"]
  }
  pure { sourcePlan := plan, module_ }

/-- PSY-DPN-G5-HARD residual allowlist (explicit gated policy).

    True only for stable `PSY-DPN-G5-MATRIX` residual diagnostics that document
    Plan-admit shapes not yet DPN-lowered (product may emit transitional
    `.psy` only). R-NARROW UInt8/16/32 checked arith is **not** residual
    (DPN-lowered). Remaining residual: narrow bitwise/shift, Int signed,
    pureFn/callFn, UInt64 shl/shr, checkedBitNot, Field. All other DPN lower
    failures must fail materialize — never silent incomplete product. -/
def isPsyDpnG5HardResidualAllowlistV1 (message : String) : Bool :=
  -- Residual matrix families pin the `.psy dual-write only` / residual wording.
  message.contains "PSY-DPN-G5-MATRIX" &&
    (message.contains "residual" || message.contains ".psy dual-write only")

/-- PSY-DPN-7 dual-write + G5-HARD honesty from retained Plan + PsyModule.
    * Primary: `{name}.dpn.json` when `lowerPlanToPackageV1` succeeds
    * Transitional/debug: `{name}.psy` always on DPN success
    * Residual allowlist (G5-MATRIX residual): `.psy` only (no false DPN claim)
    * Non-allowlisted DPN failure: stable `PSY-DPN-G5-HARD` materialize FC
    Prefer evidence FC inside LowerPlan over inventing DPN ops. -/
private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderModule ir.module_
  let pathName := ir.module_.contractName
  let psyFile : OutputFile := {
    path := s!"{pathName}.psy"
    mediaType := "text/plain"
    contents := source
  }
  match lowerPlanToPackageV1 ir.sourcePlan with
  | .ok pkg =>
      let dpnFile : OutputFile := {
        path := s!"{pathName}.dpn.json"
        mediaType := "application/json"
        contents := encodePackageCompact pkg
      }
      -- DPN package first (product authority), .psy second (transition/debug).
      pure #[dpnFile, psyFile]
  | .error (.planInvariant .psy msg) =>
      if isPsyDpnG5HardResidualAllowlistV1 msg then
        -- Explicit residual: transitional .psy only (documented allowlist).
        pure #[psyFile]
      else
        -- G5-HARD: Plan admitted but DPN lower failed for a non-residual reason.
        planError s!"PSY-DPN-G5-HARD: Plan admitted but DPN lower failed \
(no silent .psy-only): {msg}"
  | .error e =>
      -- Non-planInvariant DPN path should not occur; fail closed as-is.
      .error e

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless isSafeIdent ir.module_.contractName do
    planError "Psy IR contract name is not a safe identifier"
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
  emitFromIR ir

/-- Engineering/test materialize from a retained `Plan` under G5-HARD policy
    (validate → IR lower → dual-write / residual allowlist / hard-fail). -/
def buildFromPlanV1 (plan : Plan) : CompileResult (Array OutputFile) := do
  validatePlan plan
  let ir ← lower plan
  emitFromIR ir

/-- Pre-P-B / unit-test IR entry over retained SemanticProgramV1. -/
def irFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult IR := do
  let plan ← planFromCompiledSemanticV1 compiled
  validatePlan plan
  lower plan

/-- Pre-P-B / unit-test materialize entry. -/
def buildFromCompiledSemanticV1 (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCompiledSemanticV1 compiled
  emitFromIR ir

end ProofForgeV2.Targets.Psy
