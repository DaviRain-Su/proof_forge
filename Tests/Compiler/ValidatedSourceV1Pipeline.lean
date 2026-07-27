import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Compiler.ValidatedSourceV1Pipeline

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

/-- Detail string from any product CompileError (CheckV1 gate may surface
    invalidProgram / effectDisallowed / visibilityViolation / resourceBound). -/
private def errorDetail : CompileResult α → Option String
  | .error e => some e.message
  | _ => none

private def expectInvalid (label want : String) (r : CompileResult α) : IO Unit :=
  expect (errorDetail r == some want)
    s!"{label}: expected {want}, got {errorDetail r}"

private def expectRender (label want : String) (r : CompileResult α) : IO Unit :=
  match r with
  | .error e =>
      expect (e.render == want) s!"{label}: expected render {want}, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error render {want}"

private def n (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def q (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 parts)

private def block (statements : Array StmtV1) : BlockV1 := { statements }
private def ret (value : ExprV1) : BlockV1 := block #[.return_ (some value)]
private def u (value : Nat) : ExprV1 := .literal (.integer value)
private def var (name : SourceNameComponentV1) : ExprV1 := .place (.name name)
private def param (name : SourceNameComponentV1) (type_ : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : ParamV1 := { visibility, name, type_ }
private def entry (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : EntryDeclV1 :=
  { name, params, result, body }
private def view (name : SourceNameComponentV1) (body : BlockV1)
    (params : Array ParamV1 := #[]) (result : TypeV1 := .uint 64) : ViewDeclV1 :=
  { name, params, result, body }
private def state (name : SourceNameComponentV1) (type_ : TypeV1 := .uint 64)
    (visibility : VisibilityV1 := .public_) : StateDeclV1 := { visibility, name, type_ }

private def validated (module identity : SourceQualifiedNameV1)
    (name : SourceNameComponentV1) (items : Array ProgramItemV1) : IO ValidatedSourceV1 :=
  lift "validate" (validateSourceV1 module identity { name, items })

private def compileOk (label : String) (source : ValidatedSourceV1) : IO Semantic.Program :=
  match (Compiler.compileValidatedSourceV1 source : CompileResult Semantic.Program) with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def unsupported (tag : String) : String :=
  s!"validated ProgramV1 lowering does not support {tag}"

/-- D1-PA-109 RED: validated ProgramV1 lowering, order, identity, hash, and
complete reachable fail-closed constructor matrix. -/
def run : IO Unit := do
  let demo ← n "Demo"; let x ← n "x"; let y ← n "y"; let seed ← n "seed"; let runN ← n "run"
  let getN ← n "get"; let peer ← q #["Peer", "go"]
  let moduleName ← q #["Tests", "Pipeline"]; let identity ← q #["Tests", "Pipeline", "Demo"]
  let quotedModule ← q #["Root"]
  let quotedIdentity ← q #["Root", "A.B", "C"]
  let acceptedTypes : Array TypeV1 := #[.bool, .uint 8, .uint 16, .uint 32, .uint 64,
    .uint 128, .uint 256, .int 8, .int 16, .int 32, .int 64, .int 128, .int 256,
    .principal, .unit, .bytes 0, .bytes 4096, .array (.option (.uint 64)) 0,
    .array (.option (.array (.bool) 2)) 4096, .field (← n "bn254_fr")]
  let acceptedItems : Array ProgramItemV1 := #[
    .state (state x (.uint 64) .public_), .state (state y .bool .private_),
    .state (state (← n "z") .bool .commitment),
    .init { params := #[param seed], body := block #[.assign (.name x) (var seed)] },
    .entry (entry runN (block #[
      .assign (.name x) (.binary .add (var x) (u 18446744073709551615)),
      .call { callee := peer, args := #[] }, .return_ (some (var x))]) #[param y]),
    .view (view getN (ret (var x)))]
  let source ← validated moduleName identity demo acceptedItems
  let semantic ← compileOk "accepted subset" source
  let digest ← lift "source hash" (sourceHashV1 source)
  let rendered ← lift "render digest" (renderDigest digest)
  expect (semantic.name == "Demo" && semantic.qualifiedName == "Tests.Pipeline.Demo")
    "program names must use raw short name and one full pure Name rendering"
  expect (semantic.sourceHash.length == 64 && rendered == "sha256:" ++ semantic.sourceHash)
    "semantic sourceHash must be the exact lowercase sourceHashV1 suffix"
  match parseDigest ("sha256:" ++ semantic.sourceHash) with
  | .ok parsed => expect (parsed == digest) "parsed source hash digest mismatch"
  | .error error => throw <| IO.userError s!"semantic sourceHash did not parse: {error}"
  expect (semantic.state.map (·.name) == #["x", "y", "z"])
    "state bucket must retain relative source order"
  expect (semantic.entries.map (·.name) == #["run", "get"])
    "entry and view must share relative source order"
  expect semantic.initializer.isSome "unique initializer must be preserved"
  expect (semantic.entries[0]!.params[0]!.name == "y") "parameter names must remain raw"
  match semantic.entries[0]!.body[1]? with
  | some (Semantic.Statement.synchronousCall callee) => expect (callee == "Peer.go") "callee identity rendering"
  | other => throw <| IO.userError s!"zero-argument call was not lowered: {repr other}"
  expect (semantic.requirements.contains .synchronousCall &&
      semantic.requirements.contains .privateState &&
      semantic.requirements.contains .commitmentState)
    "call and state visibility requirements must derive from lowered semantics"

  let cName ← n "C"
  let quoted ← validated quotedModule quotedIdentity cName #[.entry (entry runN (ret (u 0)))]
  let quotedSem ← compileOk "quoted component" quoted
  expect (quotedSem.qualifiedName != semantic.qualifiedName && quotedSem.qualifiedName ==
      (Lean.Name.str (Lean.Name.str (Lean.Name.str .anonymous "Root") "A.B") "C").toString)
    "quoted identity components must be rendered once as a pure Name chain"
  let bcName ← n "B.C"
  let collision ← validated quotedModule (← q #["Root", "A", "B.C"]) bcName
    #[.entry (entry runN (ret (u 0)))]
  let collisionSem ← compileOk "identity collision twin" collision
  expect (quotedSem.qualifiedName != collisionSem.qualifiedName && collisionSem.name == "B.C")
    "raw component boundaries and short names must remain distinct"
  let minimal ← validated quotedModule (← q #["Root", "C"]) cName
    #[.entry (entry runN (ret (u 0)))]
  let minimalSem ← compileOk "minimum identity" minimal
  expect (minimalSem.qualifiedName == "Root.C") "minimum two-component identity must lower"
  let dottedState ← n "state.value"; let dottedParam ← n "arg.value"
  let dottedEntry ← n "run.call"
  let rawNames ← validated moduleName identity demo #[
    .state (state dottedState),
    .entry (entry dottedEntry (ret (var dottedParam)) #[param dottedParam])]
  let rawSem ← compileOk "raw unqualified names" rawNames
  expect (rawSem.state[0]!.name == "state.value" &&
      rawSem.entries[0]!.name == "run.call" && rawSem.entries[0]!.params[0]!.name == "arg.value")
    "unqualified names must use raw components"
  let calleeA ← q #["Peer", "A.B", "C"]
  let calleeB ← q #["Peer", "A", "B.C"]
  let callSource (callee : SourceQualifiedNameV1) := validated moduleName identity demo
    #[.entry (entry runN (block #[.call { callee, args := #[] }, .return_ (some (u 0))]))]
  let callA ← compileOk "quoted callee A" (← callSource calleeA)
  let callB ← compileOk "quoted callee B" (← callSource calleeB)
  match callA.entries[0]!.body[0]?, callB.entries[0]!.body[0]? with
  | some (Semantic.Statement.synchronousCall a),
      some (Semantic.Statement.synchronousCall b) =>
      expect (a == (Lean.Name.str (Lean.Name.str (Lean.Name.str .anonymous "Peer") "A.B") "C").toString &&
          b == (Lean.Name.str (Lean.Name.str (Lean.Name.str .anonymous "Peer") "A") "B.C").toString && a != b)
        "qualified callees must preserve raw component boundaries"
  | _, _ => throw <| IO.userError "quoted callees were not preserved"
  for type_ in acceptedTypes do
    let typed ← validated moduleName identity demo #[.entry (entry runN (ret (u 0)) #[param y type_])]
    let _ ← compileOk "accepted type table" typed
  let maxLiteral ← validated moduleName identity demo #[.entry (entry runN (ret (u 18446744073709551615)))]
  let _ ← compileOk "UInt64.max" maxLiteral

  let reordered ← validated moduleName identity demo #[
    .entry (entry runN (ret (u 0))), .state (state x), .view (view getN (ret (var x)))]
  let original ← validated moduleName identity demo #[
    .state (state x), .entry (entry runN (ret (u 0))), .view (view getN (ret (var x)))]
  let a ← compileOk "order original" original; let b ← compileOk "order twin" reordered
  expect (a.sourceHash != b.sourceHash) "cross-kind source reorder must change sourceHash"
  expect ({ a with sourceHash := "" } == { b with sourceHash := "" })
    "cross-kind reorder must not alter other Semantic fields"
  expect (a.canonicalBytes == b.canonicalBytes && a.semanticHash == b.semanticHash)
    "Semantic canonical bytes and hash must ignore source-order provenance"

  -- Top-level alternatives: CheckV1 runs first. Constructors that are well-typed
  -- still fail alpha shape; hostile/ill-typed children surface CheckV1 messages.
  let hostile := .literal (.string "HOSTILE")
  let digest0 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let topCases : Array (String × Array ProgramItemV1 × String) := #[
    ("StructDecl", #[.struct { name := x, fields := #[{ name := y, type_ := .map .bool .bool }] }],
      unsupported "StructDecl"),
    ("EnumDecl", #[.enum { name := x, variants := #[{ name := y, payloadTypes := #[.map .bool .bool] }] }],
      unsupported "EnumDecl"),
    ("ConstDecl", #[.const { name := x, type_ := .map .bool .bool, value := hostile }],
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("EventDecl", #[.event { name := x, params := #[param y (.map .bool .bool)] }],
      unsupported "EventDecl"),
    ("ErrorDecl", #[.error { name := x, params := #[param y (.map .bool .bool)] }],
      unsupported "ErrorDecl"),
    ("FnDecl",
      #[ProgramItemV1.fn {
          name := x
          params := #[param y (.map .bool .bool)]
          result := .map .bool .bool
          body := ret hostile
        }],
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("InvariantDecl", #[.invariant { name := x, predicate := hostile }],
      "type mismatch: expected Bool, got string literal"),
    ("ExtensionReq", #[.extensionReq { id := peer, version := "1.0.0", digest := digest0 }],
      unsupported "ExtensionReq"),
    ("ProofDecl", #[.proof { invariant := x, theorem_ := peer },
      .invariant { name := x, predicate := hostile }],
      "type mismatch: expected Bool, got string literal")]
  for (tag, itemPrefix, want) in topCases do
    let bad ← validated moduleName identity demo (itemPrefix.push (.entry (entry runN (ret (u 0)))))
    expectInvalid s!"top {tag}" want (Compiler.compileValidatedSourceV1 bad)

  -- Named types fail CheckV1 resolution (state name `x` is wrong-category as a type);
  -- Map-shaped types still reach alpha shape rejection.
  let typeCases : Array (String × TypeV1 × String) := #[
    ("Type.Named", .named x, "name 'x' resolved to state but expected type"),
    ("Type.Map", .map .bool .bool, unsupported "Type.Map"),
    ("Type.Named nested", .option (.array (.named x) 1),
      "name 'x' resolved to state but expected type"),
    ("Type.Map nested", .array (.option (.map .bool .bool)) 1, unsupported "Type.Map")]
  for (tag, type_, want) in typeCases do
    let bad ← validated moduleName identity demo #[.state (state x type_), .entry (entry runN (ret (u 0)))]
    expectInvalid s!"type {tag}" want (Compiler.compileValidatedSourceV1 bad)

  let patterns : Array PatternV1 := #[.wildcard, .bind x, .literal (.bool true), .constructor peer #[]]
  let exprArms := patterns.map fun p => { pattern := p, value := hostile }
  let mut exprCases : Array (String × ExprV1 × String) := #[
    ("Literal.Bool", .literal (.bool true), "type mismatch: expected UInt64, got Bool"),
    ("Literal.String", hostile, "type mismatch: expected UInt64, got string literal"),
    ("Place.Field", .place (.field (.name x) y), "unknown name 'x' (expected value)"),
    ("Place.Index", .place (.index (.name x) hostile), "unknown name 'x' (expected value)"),
    ("Expr.Constructor", .constructor peer #[hostile],
      "unknown name 'Peer' (expected constructor enum)"),
    ("Expr.Unary.neg", .unary .neg hostile,
      "type mismatch: expected expected type, got string literal"),
    ("Expr.Unary.not", .unary .not hostile, "type mismatch: expected Bool, got string literal"),
    ("Expr.Unary.bitNot", .unary .bitNot hostile,
      "type mismatch: expected expected type, got string literal"),
    ("Expr.LocalCall", .localCall x #[hostile], "unknown name 'x' (expected function)"),
    ("Expr.Match", .match_ hostile exprArms, "unknown name 'Peer' (expected constructor enum)")]
  let arithBinary : Array (String × BinaryOpV1) := #[
    ("BinaryOp.Sub", .sub), ("BinaryOp.Mul", .mul), ("BinaryOp.Div", .div),
    ("BinaryOp.Mod", .mod), ("BinaryOp.BitAnd", .bitAnd), ("BinaryOp.BitOr", .bitOr),
    ("BinaryOp.BitXor", .bitXor)]
  for (tag, op) in arithBinary do
    exprCases := exprCases.push (tag, .binary op hostile hostile,
      "type mismatch: expected UInt64, got string literal")
  -- Equality / compare / logical / shift: first operand typing with no integer width.
  -- String-with-no-expected uses the TypeCheckV1 wording "expected type" inside
  -- `expectedActualDiagnostic`, yielding "expected expected type".
  exprCases := exprCases.push ("BinaryOp.Eq", .binary .eq hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Ne", .binary .ne hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Lt", .binary .lt hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Le", .binary .le hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Gt", .binary .gt hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.Ge", .binary .ge hostile hostile,
    "type mismatch: expected expected type, got string literal")
  exprCases := exprCases.push ("BinaryOp.And", .binary .logicalAnd hostile hostile,
    "type mismatch: expected Bool, got string literal")
  exprCases := exprCases.push ("BinaryOp.Or", .binary .logicalOr hostile hostile,
    "type mismatch: expected Bool, got string literal")
  exprCases := exprCases.push ("BinaryOp.Shl", .binary .shl hostile hostile,
    "type mismatch: expected UInt64, got string literal")
  exprCases := exprCases.push ("BinaryOp.Shr", .binary .shr hostile hostile,
    "type mismatch: expected UInt64, got string literal")
  for (tag, expression, want) in exprCases do
    let bad ← validated moduleName identity demo #[.entry (entry runN (ret expression))]
    expectInvalid s!"expression {tag}" want (Compiler.compileValidatedSourceV1 bad)
  let huge ← validated moduleName identity demo #[.entry (entry runN (ret (u (2^64))))]
  expectInvalid "integer range"
    "type mismatch: expected UInt64, got integer literal 18446744073709551616 out of range"
    (Compiler.compileValidatedSourceV1 huge)

  -- Statement families: CheckV1 resolution/type before alpha shape.
  let stmtArms := patterns.map fun p => { pattern := p, body := ret hostile }
  let stmtCases : Array (String × StmtV1 × String) := #[
    ("Stmt.Let", .let_ x (some (.map .bool .bool)) hostile,
      "type mismatch: expected Map (Bool) (Bool), got string literal"),
    ("Stmt.Assign.field", .assign (.field (.name x) y) hostile, "unknown name 'x' (expected value)"),
    ("Stmt.Assign.index", .assign (.index (.name x) hostile) hostile, "unknown name 'x' (expected value)"),
    ("Stmt.If", .if_ hostile (ret hostile) (some (ret hostile)),
      "type mismatch: expected Bool, got string literal"),
    ("Stmt.Match", .match_ hostile stmtArms, "unknown name 'Peer' (expected constructor enum)"),
    ("Stmt.For", .for_ x hostile hostile 1 (ret hostile),
      "type mismatch: expected expected type, got string literal"),
    ("Stmt.Assert", .assert_ hostile none, "type mismatch: expected Bool, got string literal"),
    ("Stmt.Assert.error", .assert_ hostile (some x), "unknown name 'x' (expected error)"),
    ("Stmt.Revert", .revert x #[hostile], "unknown name 'x' (expected error)"),
    ("Stmt.Emit", .emit x #[hostile], "unknown name 'x' (expected event)"),
    ("Stmt.Return", .return_ none, "type mismatch: expected UInt64, got empty return"),
    ("Stmt.Schedule", .schedule { callee := peer, args := #[hostile] },
      "type mismatch: expected expected type, got string literal")]
  for (tag, statement, want) in stmtCases do
    let bad ← validated moduleName identity demo #[.entry (entry runN (block #[statement, .return_ (some (u 0))]))]
    expectInvalid s!"statement {tag}" want (Compiler.compileValidatedSourceV1 bad)
  let callArgs ← validated moduleName identity demo #[.entry (entry runN
    (block #[.call { callee := peer, args := #[hostile] }, .return_ (some (u 0))]))]
  expectInvalid "call arguments" "type mismatch: expected expected type, got string literal"
    (Compiler.compileValidatedSourceV1 callArgs)

  -- Phase-order priority under CheckV1-first product gate.
  let priority : Array (String × Array ProgramItemV1 × String) := #[
    ("item order", #[.entry (entry runN (ret hostile)),
      .struct { name := x, fields := #[{ name := y, type_ := .bool }] }],
      "type mismatch: expected UInt64, got string literal"),
    ("add lhs", #[.entry (entry runN (ret (.binary .add hostile (.literal (.bool true)))))],
      "type mismatch: expected UInt64, got string literal"),
    ("assign target", #[.state (state x), .entry (entry runN (block #[
      .assign (.field (.name x) y) hostile, .return_ (some (u 0))]))],
      "type mismatch: expected struct type, got UInt64"),
    ("resolution before type", #[.entry (entry runN (block #[
      .return_ (some (var y)), .return_ (some hostile)]))],
      "unknown name 'y' (expected value)")]
  for (label, items, want) in priority do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

  -- Product Typed gate: CheckV1 (incl. EffectCheckV1) wins when it fires.
  -- Alpha residual shape rules cover missing/after-return only; view write/call
  -- allowlists are EffectCheckV1-only (PF-EFFECT-001), not TypedV1 alpha strings.
  let typedCases : Array (String × Array ProgramItemV1 × String) := #[
    ("unknown", #[.entry (entry runN (ret (var y)))], "unknown name 'y' (expected value)"),
    ("assign", #[.entry (entry runN (block #[.assign (.name y) (u 1), .return_ (some (u 1))]))],
      "unknown name 'y' (expected value)"),
    ("view write", #[.state (state x), .view (view getN (block #[
      .assign (.name x) (u 1), .return_ (some (var x))]))],
      "view 'get' does not allow effect 'state.write'"),
    ("view call", #[.view (view getN (block #[
      .call { callee := peer, args := #[] }, .return_ (some (u 0))]))],
      "view 'get' does not allow effect 'external.call.sync'"),
    ("non-u64 add", #[.state (state x .bool), .entry (entry runN (ret (.binary .add (var x) (u 1))))],
      "type mismatch: expected UInt64, got Bool"),
    ("init return", #[.init { params := #[], body := block #[.return_ (some (u 0))] },
      .entry (entry runN (ret (u 0)))],
      "type mismatch: expected Unit, got integer literal"),
    ("missing return", #[.entry (entry runN (block #[.call { callee := peer, args := #[] }]))],
      "entry 'run' is missing a return value"),
    ("after return", #[.entry (entry runN (block #[
      .return_ (some (u 0)), .call { callee := peer, args := #[] }]))],
      "entry 'run' contains a statement after return"),
    ("return mismatch", #[.entry (entry runN (ret (u 0)) #[] .bool)],
      "type mismatch: expected Bool, got integer literal")]
  for (label, items, want) in typedCases do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

  -- Wire codes for effect-only product failures.
  expectRender "view write wire"
    "PF-EFFECT-001: view 'get' does not allow effect 'state.write'"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.state (state x), .view (view getN (block #[.assign (.name x) (u 1), .return_ (some (var x))]))]))
  expectRender "view call wire"
    "PF-EFFECT-001: view 'get' does not allow effect 'external.call.sync'"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.view (view getN (block #[.call { callee := peer, args := #[] }, .return_ (some (u 0))]))]))

  -- Bound-only product wire: well-typed triple-nested for product overflow maps
  -- DiagnosticCodeV1.resourceBound → CompileError.resourceBound (PF-BOUND-001).
  let total ← n "total"; let startN ← n "start"; let stopN ← n "stop"
  let i ← n "i"; let j ← n "j"; let k ← n "k"
  let tripleNest : BlockV1 := block #[
    .for_ i (var startN) (var stopN) 4096 (block #[
      .for_ j (var startN) (var stopN) 4096 (block #[
        .for_ k (var startN) (var stopN) 4096 (block #[
          .assign (.name total) (var i)])])])]
  expectRender "bound loop product wire"
    "PF-BOUND-001: loop bound product overflows UInt32 in entry 'run' (bound 4096)"
    (Compiler.compileValidatedSourceV1 (← validated moduleName identity demo
      #[.state (state total), .state (state startN), .state (state stopN),
        .entry (entry runN tripleNest #[] .unit)]))

end Tests.Compiler.ValidatedSourceV1Pipeline
