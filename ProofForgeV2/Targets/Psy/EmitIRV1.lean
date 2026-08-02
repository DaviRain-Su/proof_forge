import ProofForgeV2.Targets.Psy.ValidatePlanV1

/-!
# Psy EmitIRV1 — Plan → `.psy` source emission

Target-owned Psy AST/renderer (ported from the old Compiler/Psy surface for
the V2 envelope) and capability-internal `lower`/`emitFromIR`.

Checked u64 arithmetic is realized with explicit assert guards. Psy `Felt`
is Goldilocks (p = 2^64−2^32+1): every decimal literal is reduced into
`0..p-1`, and overflow uses field-wrap detection (`sum >= lhs` for add;
exact inverse for mul) rather than an illegal `2^64` bound. Bitwise/shift
use native Psy Felt operators; `count < 64` guards protect shifts. Revert →
`assert(false, ...)`. Emit → `__emit([...])`. Call/schedule →
`__invoke_sync#<Felt>(targetHash, methodHash, [args])` with deterministic
component hashes reduced mod p (V2 qualified callees have no runtime Felt
contract/method ids).
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler

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
    deriving BEq, Inhabited, Repr

  inductive PsyStmt where
    | letBind (name : String) (typeName : String) (value : PsyExpr)
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
  /-- Native Psy `u32` parameter (2026-08-02 u32 slice). -/
  isU32 : Bool := false
  deriving BEq, Inhabited, Repr

structure PsyMethod where
  name : String
  params : Array PsyParam
  resultIsBool : Bool
  resultIsUnit : Bool
  /-- Native Psy `u32` result (2026-08-02 u32 slice; `-> u32`). -/
  resultIsU32 : Bool := false
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

  private partial def operandExpr (e : PsyExpr) : String :=
    match e with
    | .literal _ | .local _ | .storageScalarRead _ | .call _ _ | .crosscallInvoke _ _ _ =>
        exprStr e
    | _ => s!"({exprStr e})"

  private partial def stmtLines (level : Nat) (s : PsyStmt) : Array String :=
    match s with
    | .letBind name typeName value =>
        #[indent level s!"let {name}: {typeName} = {exprStr value};"]
    | .localAssign target value =>
        #[indent level s!"{target} = {exprStr value};"]
    | .storageWrite stateId value =>
        #[indent level s!"c.{stateId} = {exprStr value};"]
    | .assert condition message =>
        #[indent level s!"assert({exprStr condition}, {stringLiteral message});"]
    | .assertEq lhs rhs message =>
        #[indent level s!"assert_eq({exprStr lhs}, {exprStr rhs}, {stringLiteral message});"]
    | .ifElse condition thenBody elseBody =>
        let thenLines := thenBody.flatMap (stmtLines (level + 1))
        let elseLines := elseBody.flatMap (stmtLines (level + 1))
        let hasElse := !elseBody.isEmpty
        #[indent level (s!"if {exprStr condition} " ++ "{")]
          ++ thenLines
          ++ (if hasElse then
                #[indent level "} else {"] ++ elseLines
              else #[])
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
  s!"{p.name}: {if p.isBool then "bool" else if p.isU32 then "u32" else "Felt"}"

/-- Render a contract method with the correct `Ref::new` line. -/
private def renderContractMethod (refName : String) (m : PsyMethod) : String :=
  let returnSuffix :=
    if m.resultIsUnit then ""
    else if m.resultIsBool then " -> bool"
    else if m.resultIsU32 then " -> u32"
    else " -> Felt"
  let paramList := String.intercalate ", " (m.params.map renderParam).toList
  let header := indent 1 "#[contract_method]"
  let signature :=
    indent 1 (s!"pub fn {m.name}({paramList}){returnSuffix} " ++ "{")
  let newRef := indent 2 s!"let c = {refName}::new(ContractMetadata::current());"
  let bodyLines := m.body.flatMap (stmtLines 2)
  String.intercalate "\n"
    (#[header, signature, newRef] ++ bodyLines ++ #[indent 1 "}"]).toList

private def renderHelper (m : PsyMethod) : String :=
  let returnSuffix :=
    if m.resultIsUnit then ""
    else if m.resultIsBool then " -> bool"
    else if m.resultIsU32 then " -> u32"
    else " -> Felt"
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

private def exprTypeName : Expr → String
  | .boolLiteral _ => "bool"
  | .compare _ _ _ | .signedCompare _ _ _ => "bool"
  | .logicalAnd _ _ | .logicalOr _ _ => "bool"
  | .boolNot _ => "bool"
  | .bitNot _ => "u32"
  | .checkedBitNot _ => "Felt"
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
  | .shl l r => do
      -- Count < 64 only. The prior product < 2^64 bound was not a legal Felt
      -- literal under Goldilocks; field wrap of the shift is left to the VM.
      -- A UInt32 literal count (u32 slice) is folded to its Felt value here
      -- (the Felt shift op needs a Felt count; the lowerer admits only
      -- literal UInt32 counts).
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
  | .bitNot operand => do
      -- UInt32 bitwise-not as `x ^ 4294967295u32` (XOR with the 2^32−1 mask;
      -- the `u32` suffix is required so dargo types the literal as u32, and
      -- the result is verified faithful on the real VM: 5→4294967290,
      -- 4294967295→0, 0→4294967295). Mask-subtraction is NOT used — the VM's
      -- u32 sub is checked with a bug and panics on `4294967295u32 -
      -- 4294967295u32` ("u32 sub value too low").
      let (ls1, o', ctx1) ← lowerExprStmt ctx operand
      let (name, ctx2) := freshName ctx1
      pure (ls1 ++
        #[.letBind name "u32" (.binary o' .bitXor (.literal (.u32 4294967295)))],
        .local name, ctx2)
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
    | .assert condition => do
        let (exprStmts, c', ctx1) ← lowerExprStmt ctx condition
        out := out ++ exprStmts ++ #[.assert c' "assert failed"]
        ctx := ctx1
    | .returnValue value => do
        let (exprStmts, psy, ctx1) ← lowerExprStmt ctx value
        out := out ++ exprStmts ++ #[.returnExpr psy]
        ctx := ctx1
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
        let (startStmts, sLeo, ctx1) ← lowerExprStmt ctx start
        let (endStmts, eLeo, ctx2) ← lowerExprStmt ctx1 endExclusive
        let startName := s!"pf_start{loopDepth}"
        let endName := s!"pf_end{loopDepth}"
        let indexName := s!"pf_c{loopDepth}"
        let iName := s!"pf_i{loopDepth}"
        let (bodyStmts, ctx3) ← emitStatements ctx2 body (loopDepth + 1)
        -- Bound guard: if start < end { assert(end - start <= N) }
        let guardCond : PsyExpr :=
          .binary (.local startName) .lt (.local endName)
        let span : PsyExpr :=
          .binary (.local endName) .sub (.local startName)
        let fits : PsyExpr :=
          .binary span .le (feltLit maxIter)
        let counterAsFelt : PsyExpr :=
          .cast (.local indexName) "Felt"
        let induction : PsyExpr :=
          .binary (.local startName) .add counterAsFelt
        let innerGuard : PsyExpr :=
          .binary (.local iName) .lt (.local endName)
        let bodyInner :=
          #[.letBind iName "Felt" induction] ++
          #[.ifElse innerGuard bodyStmts #[]]
        let loopStmt : PsyStmt :=
          .boundedFor indexName 0 maxIter bodyInner
        out := out ++ startStmts ++ endStmts ++
          #[.letBind startName "Felt" sLeo,
            .letBind endName "Felt" eLeo,
            .ifElse guardCond #[.assert fits "boundExceeded"] #[],
            loopStmt]
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
        unless args.isEmpty do
          planError "unsupported Psy semantic shape: revert with error arguments cannot be expressed on the Psy surface"
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
        -- No deferred crosscall intrinsic exists in the Psy toolchain surface
        -- (the old port only ever had __invoke_sync#<Felt>; the upstream VM's
        -- InvokeExternalContractFunctionDeferred has no emitted form). Alias
        -- sync would change fire-and-forget semantics, so schedule fails
        -- closed here AND the capability matrix declines
        -- effect.asynchronous-workflow (resolver PF-REQ-UNSUPPORTED first).
        throw <| .planInvariant .psy
          "unsupported Psy semantic shape: schedule has no deferred crosscall form"
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
    { name := s!"p{p.sourceIndex}", isBool := p.isBool, isU32 := p.isU32 }
  let (body, ctx1) ← emitStatements ctx fn.body 0
  pure ({
    name := fn.name
    params
    resultIsBool := fn.resultIsBool
    resultIsUnit := fn.resultIsUnit
    resultIsU32 := fn.resultIsU32
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
  let module_ : PsyModule := {
    contractName
    headerComment :=
      "// Generated by proof-forge-next (Psy target, " ++ psyToolchain ++ ").\n" ++
      "// This is Psy source intended for the official Dargo/Psy compiler toolchain."
    state := plan.stateFieldNames.map fun n => { name := n }
    methods
    helpers
    testName := s!"test_{asciiLower plan.programName}_fixture"
    testBody := #["// source-only fixture placeholder; no runtime claims"]
  }
  pure { sourcePlan := plan, module_ }

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  let source := renderModule ir.module_
  let pathName := ir.module_.contractName
  pure #[{
    path := s!"{pathName}.psy"
    mediaType := "text/plain"
    contents := source
  }]

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
