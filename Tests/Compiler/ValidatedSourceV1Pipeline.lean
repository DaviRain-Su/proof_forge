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

private def invalidMessage : CompileResult α → Option String
  | .error (.invalidProgram message) => some message
  | _ => none

private def expectInvalid (label want : String) (r : CompileResult α) : IO Unit :=
  expect (invalidMessage r == some want) s!"{label}: expected {want}"

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
  expect (quotedSem.qualifiedName != collisionSem.qualifiedName) "raw component boundaries must not collide"
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

  -- All nine unsupported top-level alternatives. Hostile children prove the
  -- rejected record is not traversed.
  let hostile := .literal (.string "HOSTILE")
  let digest0 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let topCases : Array (String × Array ProgramItemV1) := #[
    ("StructDecl", #[.struct { name := x, fields := #[{ name := y, type_ := .map .bool .bool }] }]),
    ("EnumDecl", #[.enum { name := x, variants := #[{ name := y, payloadTypes := #[.map .bool .bool] }] }]),
    ("ConstDecl", #[.const { name := x, type_ := .map .bool .bool, value := hostile }]),
    ("EventDecl", #[.event { name := x, params := #[param y (.map .bool .bool)] }]),
    ("ErrorDecl", #[.error { name := x, params := #[param y (.map .bool .bool)] }]),
    ("FnDecl", #[.fn { name := x, params := #[param y (.map .bool .bool)], result := .map .bool .bool, body := ret hostile }]),
    ("InvariantDecl", #[.invariant { name := x, predicate := hostile }]),
    ("ExtensionReq", #[.extensionReq { id := peer, version := "1.0.0", digest := digest0 }]),
    ("ProofDecl", #[.proof { invariant := x, theorem_ := peer },
      .invariant { name := x, predicate := hostile }])]
  for (tag, prefix) in topCases do
    let bad ← validated moduleName identity demo (prefix.push (.entry (entry runN (ret (u 0)))))
    expectInvalid s!"top {tag}" (unsupported tag) (Compiler.compileValidatedSourceV1 bad)

  let typeCases : Array (String × TypeV1) := #[
    ("Type.Named", .named x), ("Type.Map", .map .bool .bool),
    ("Type.Named", .option (.array (.named x) 1)),
    ("Type.Map", .array (.option (.map .bool .bool)) 1)]
  for (tag, type_) in typeCases do
    let bad ← validated moduleName identity demo #[.state (state x type_), .entry (entry runN (ret (u 0)))]
    expectInvalid s!"type {tag}" (unsupported tag) (Compiler.compileValidatedSourceV1 bad)

  let patterns : Array PatternV1 := #[.wildcard, .bind x, .literal (.bool true), .constructor peer #[]]
  let exprArms := patterns.map fun p => { pattern := p, value := hostile }
  let mut exprCases : Array (String × ExprV1) := #[
    ("Literal.Bool", .literal (.bool true)), ("Literal.String", hostile),
    ("Place.Field", .place (.field (.name x) y)),
    ("Place.Index", .place (.index (.name x) hostile)),
    ("Expr.Constructor", .constructor peer #[hostile]),
    ("Expr.Unary", .unary .neg hostile), ("Expr.Unary", .unary .not hostile),
    ("Expr.Unary", .unary .bitNot hostile),
    ("Expr.LocalCall", .localCall x #[hostile]),
    ("Expr.Match", .match_ hostile exprArms)]
  let binaryCases : Array (String × BinaryOpV1) := #[
    ("BinaryOp.Sub", .sub), ("BinaryOp.Mul", .mul), ("BinaryOp.Div", .div),
    ("BinaryOp.Mod", .mod), ("BinaryOp.Eq", .eq), ("BinaryOp.Ne", .ne),
    ("BinaryOp.Lt", .lt), ("BinaryOp.Le", .le), ("BinaryOp.Gt", .gt),
    ("BinaryOp.Ge", .ge), ("BinaryOp.And", .logicalAnd), ("BinaryOp.Or", .logicalOr),
    ("BinaryOp.BitAnd", .bitAnd), ("BinaryOp.BitOr", .bitOr),
    ("BinaryOp.BitXor", .bitXor), ("BinaryOp.Shl", .shl), ("BinaryOp.Shr", .shr)]
  for (tag, op) in binaryCases do
    exprCases := exprCases.push (tag, .binary op hostile hostile)
  for (tag, expression) in exprCases do
    let bad ← validated moduleName identity demo #[.entry (entry runN (ret expression))]
    expectInvalid s!"expression {tag}" (unsupported tag) (Compiler.compileValidatedSourceV1 bad)
  let huge ← validated moduleName identity demo #[.entry (entry runN (ret (u (2^64))))]
  expectInvalid "integer range" "validated ProgramV1 lowering requires a UInt64 integer literal"
    (Compiler.compileValidatedSourceV1 huge)

  -- Every unsupported statement family; hostile pattern/arm/block children
  -- are sentinels and therefore intentionally need not form useful programs.
  let stmtArms := patterns.map fun p => { pattern := p, body := ret hostile }
  let stmtCases : Array (String × StmtV1) := #[
    ("Stmt.Let", .let_ x (some (.map .bool .bool)) hostile),
    ("Stmt.Assign", .assign (.field (.name x) y) hostile),
    ("Stmt.Assign", .assign (.index (.name x) hostile) hostile),
    ("Stmt.If", .if_ hostile (ret hostile) (some (ret hostile))),
    ("Stmt.Match", .match_ hostile stmtArms),
    ("Stmt.For", .for_ x hostile hostile 1 (ret hostile)),
    ("Stmt.Assert", .assert_ hostile none), ("Stmt.Assert", .assert_ hostile (some x)),
    ("Stmt.Revert", .revert x #[hostile]), ("Stmt.Emit", .emit x #[hostile]),
    ("Stmt.Return", .return_ none),
    ("Stmt.Schedule", .schedule { callee := peer, args := #[hostile] })]
  for (tag, statement) in stmtCases do
    let bad ← validated moduleName identity demo #[.entry (entry runN (block #[statement, .return_ (some (u 0))]))]
    expectInvalid s!"statement {tag}" (unsupported tag) (Compiler.compileValidatedSourceV1 bad)
  let callArgs ← validated moduleName identity demo #[.entry (entry runN
    (block #[.call { callee := peer, args := #[hostile] }, .return_ (some (u 0))]))]
  expectInvalid "call arguments" "validated ProgramV1 lowering requires zero external call arguments"
    (Compiler.compileValidatedSourceV1 callArgs)

  -- Fixed traversal: source order, constructor before child, lhs before rhs,
  -- assignment target before value, and all lowering before Typed.
  let priority : Array (String × Array ProgramItemV1 × String) := #[
    ("item order", #[.entry (entry runN (ret hostile)),
      .struct { name := x, fields := #[{ name := y, type_ := .bool }] }], unsupported "Literal.String"),
    ("add lhs", #[.entry (entry runN (ret (.binary .add hostile (.literal (.bool true)))))], unsupported "Literal.String"),
    ("assign target", #[.state (state x), .entry (entry runN (block #[.assign (.field (.name x) y) hostile, .return_ (some (u 0))]))], unsupported "Stmt.Assign"),
    ("lowering before Typed", #[.entry (entry runN (block #[.return_ (some (var y)), .return_ (some hostile)]))], unsupported "Literal.String")]
  for (label, items, want) in priority do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

  -- Accepted lowering reaches Typed unchanged: preserve its exact diagnostics.
  let typedCases : Array (String × Array ProgramItemV1 × String) := #[
    ("unknown", #[.entry (entry runN (ret (var y)))], "unknown value 'y' in run"),
    ("assign", #[.entry (entry runN (block #[.assign (.name y) (u 1), .return_ (some (u 1))]))], "assignment target 'y' in run is not declared state"),
    ("view write", #[.state (state x), .view (view getN (block #[.assign (.name x) (u 1), .return_ (some (var x))]))], "view 'get' cannot write state 'x'"),
    ("view call", #[.view (view getN (block #[.call { callee := peer, args := #[] }, .return_ (some (u 0))]))], "view 'get' cannot perform synchronous call 'Peer.go'"),
    ("non-u64 add", #[.state (state x .bool), .entry (entry runN (ret (.binary .add (var x) (u 1))))], "checked addition in run requires two UInt64 operands"),
    ("init return", #[.init { params := #[], body := block #[.return_ (some (u 0))] }, .entry (entry runN (ret (u 0)))], "initializer cannot return a value"),
    ("missing return", #[.entry (entry runN (block #[.call { callee := peer, args := #[] }]))], "entry 'run' is missing a return value"),
    ("after return", #[.entry (entry runN (block #[.return_ (some (u 0)), .call { callee := peer, args := #[] }]))], "entry 'run' contains a statement after return"),
    ("return mismatch", #[.entry (entry runN (ret (u 0)) #[] .bool)], "entry 'run' return type does not match its declaration")]
  for (label, items, want) in typedCases do
    let bad ← validated moduleName identity demo items
    expectInvalid label want (Compiler.compileValidatedSourceV1 bad)

end Tests.Compiler.ValidatedSourceV1Pipeline
