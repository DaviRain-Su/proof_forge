import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.SourceNodeTraversalV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def expectError (label expected : String) (result : Except String α) : IO Unit :=
  match result with
  | .error detail => expect (detail == expected) s!"{label}: expected {expected}, got {detail}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private structure FixtureNames where
  name : SourceNameComponentV1
  qualified : SourceQualifiedNameV1

private structure ExprInventory where
  literal : ExprV1
  place : ExprV1
  constructorExpr : ExprV1
  unary : ExprV1
  binary : ExprV1
  localCall : ExprV1
  matchExpr : ExprV1

private def exprLeaf : ExprV1 :=
  .literal (.integer 1)

private def returnBlock (present : Bool := true) : BlockV1 := {
  statements := #[.return_ (if present then some exprLeaf else none)]
}

private def typeInventory (names : FixtureNames) : Array TypeV1 := #[
  .bool, .uint 8, .int 8, .principal, .unit, .named names.name,
  .array (.bool) 1,
  .map (.uint 8) (.int 8),
  .option .principal,
  .bytes 1,
  .field names.name
]

private def richPattern (names : FixtureNames) : PatternV1 :=
  .constructor names.qualified #[
    .wildcard,
    .bind names.name,
    .literal (.integer 1),
    .constructor names.qualified #[]
  ]

private def placeTree (names : FixtureNames) : PlaceV1 :=
  .index (.field (.name names.name) names.name) exprLeaf

private def expressionInventory (names : FixtureNames) : ExprInventory :=
  let literal := exprLeaf
  let place := ExprV1.place (placeTree names)
  let constructorExpr := ExprV1.constructor names.qualified #[
    exprLeaf, .place (.name names.name)
  ]
  let unary := ExprV1.unary .neg exprLeaf
  let binary := ExprV1.binary .add exprLeaf exprLeaf
  let localCall := ExprV1.localCall names.name #[exprLeaf, unary]
  let matchExpr := ExprV1.match_ exprLeaf #[
    { pattern := richPattern names, value := binary },
    { pattern := .wildcard, value := .localCall names.name #[] }
  ]
  { literal, place, constructorExpr, unary, binary, localCall, matchExpr }

private def allExpressions (values : ExprInventory) : Array ExprV1 := #[
  values.literal, values.place, values.constructorExpr, values.unary,
  values.binary, values.localCall, values.matchExpr
]

private def richBlock (names : FixtureNames) : BlockV1 :=
  let values := expressionInventory names
  let externalAll : ExternalCallExprV1 := {
    callee := names.qualified
    args := allExpressions values
  }
  let matchStmt := StmtV1.match_ exprLeaf #[
    {
      pattern := richPattern names
      body := { statements := #[.assert_ exprLeaf none] }
    },
    { pattern := .bind names.name, body := returnBlock }
  ]
  {
    statements := #[
      .let_ names.name (some (.option .bool)) values.constructorExpr,
      .assign (placeTree names) values.binary,
      .if_ exprLeaf returnBlock (some (returnBlock false)),
      matchStmt,
      .for_ names.name exprLeaf values.binary 1 {
        statements := #[.emit names.name #[exprLeaf, values.unary]]
      },
      .assert_ values.place none,
      .revert names.name #[exprLeaf, values.constructorExpr],
      .emit names.name #[values.localCall, values.matchExpr],
      .return_ (some values.unary),
      .call externalAll,
      .schedule { callee := names.qualified, args := #[exprLeaf] }
    ]
  }

private def comprehensiveProgram (names : FixtureNames) : ProgramV1 :=
  let mapType := TypeV1.map (.uint 8) (.int 8)
  let values := expressionInventory names
  let field (type_ : TypeV1) : FieldDeclV1 := { name := names.name, type_ }
  let param (visibility : VisibilityV1) (type_ : TypeV1) : ParamV1 := {
    visibility, name := names.name, type_
  }
  {
    name := names.name
    items := #[
      .state { visibility := .public_, name := names.name, type_ := .array (.bool) 1 },
      .struct { name := names.name, fields := #[field .bool, field mapType] },
      .enum { name := names.name, variants := #[
        { name := names.name, payloadTypes := typeInventory names },
        { name := names.name, payloadTypes := #[] }
      ] },
      .const { name := names.name, type_ := .option .bool, value := values.matchExpr },
      .event { name := names.name, params := #[
        param .public_ .bool,
        param .private_ (.array (.uint 8) 1)
      ] },
      .error { name := names.name, params := #[param .commitment mapType] },
      .init {
        params := #[
          param .public_ (.named names.name),
          param .private_ .principal
        ]
        body := richBlock names
      },
      .entry {
        name := names.name
        params := #[param .public_ .bool]
        result := mapType
        body := returnBlock
      },
      .view {
        name := names.name
        params := #[param .public_ .unit]
        result := .option .bool
        body := returnBlock false
      },
      .fn {
        name := names.name
        params := #[param .public_ (.field names.name)]
        result := .bytes 1
        body := returnBlock
      },
      .invariant { name := names.name, predicate := values.place },
      .extensionReq {
        id := names.qualified
        version := "1.0.0"
        digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
      },
      .proof { invariant := names.name, theorem_ := names.qualified }
    ]
  }

private def absenceProgram (names : FixtureNames) : ProgramV1 := {
  name := names.name
  items := #[.init {
    params := #[]
    body := { statements := #[
      .let_ names.name none exprLeaf,
      .if_ exprLeaf (returnBlock false) none,
      .return_ none,
      .revert names.name #[]
    ] }
  }]
}

private def pathText (path : NormalizedSyntacticPathV1) : String :=
  String.intercalate "/" <| path.toList.map fun segment =>
    s!"{segment.parentTag}.{segment.fieldTag}[{segment.index.toNat}]"

private def inventoryText (visits : Array NodeVisitV1) : String :=
  visits.foldl (fun output visit =>
    output ++ visit.constructorTag ++ "|" ++ pathText visit.path ++ "\n") ""

private def inventorySha256 (visits : Array NodeVisitV1) : String :=
  Crypto.sha256Hex (inventoryText visits).toUTF8

private def nodeTags : Array String := #[
  "Program", "StateDecl", "StructDecl", "EnumDecl", "ConstDecl", "EventDecl",
  "ErrorDecl", "InitDecl", "EntryDecl", "ViewDecl", "FnDecl", "InvariantDecl",
  "ExtensionReq", "ProofDecl", "Param", "FieldDecl", "EnumVariant", "Block",
  "StmtMatchArm", "ExprMatchArm", "ExternalCallExpr", "Type.Bool", "Type.UInt",
  "Type.Int", "Type.Principal", "Type.Unit", "Type.Named", "Type.Array", "Type.Map",
  "Type.Option", "Type.Bytes", "Type.Field", "Stmt.Let", "Stmt.Assign", "Stmt.If",
  "Stmt.Match", "Stmt.For", "Stmt.Assert", "Stmt.Revert", "Stmt.Emit", "Stmt.Return",
  "Stmt.Call", "Stmt.Schedule", "Expr.Literal", "Expr.Place", "Expr.Constructor",
  "Expr.Unary", "Expr.Binary", "Expr.LocalCall", "Expr.Match", "Place.Name",
  "Place.Field", "Place.Index", "Pattern.Wildcard", "Pattern.Bind", "Pattern.Literal",
  "Pattern.Constructor"
]

private def edgePairs : Array (String × String) := #[
  ("Program", "items"), ("StateDecl", "type"), ("StructDecl", "fields"),
  ("EnumDecl", "variants"), ("ConstDecl", "type"), ("ConstDecl", "value"),
  ("EventDecl", "params"), ("ErrorDecl", "params"), ("InitDecl", "params"),
  ("InitDecl", "body"), ("EntryDecl", "params"), ("EntryDecl", "result"),
  ("EntryDecl", "body"), ("ViewDecl", "params"), ("ViewDecl", "result"),
  ("ViewDecl", "body"), ("FnDecl", "params"), ("FnDecl", "result"),
  ("FnDecl", "body"), ("InvariantDecl", "predicate"), ("Param", "type"),
  ("FieldDecl", "type"), ("EnumVariant", "payloadTypes"), ("Block", "statements"),
  ("StmtMatchArm", "pattern"), ("StmtMatchArm", "body"),
  ("ExprMatchArm", "pattern"), ("ExprMatchArm", "value"),
  ("ExternalCallExpr", "args"), ("Type.Array", "element"), ("Type.Map", "key"),
  ("Type.Map", "value"), ("Type.Option", "element"), ("Stmt.Let", "typeAnn"),
  ("Stmt.Let", "value"), ("Stmt.Assign", "target"), ("Stmt.Assign", "value"),
  ("Stmt.If", "condition"), ("Stmt.If", "thenBlock"), ("Stmt.If", "elseBlock"),
  ("Stmt.Match", "scrutinee"), ("Stmt.Match", "arms"), ("Stmt.For", "start"),
  ("Stmt.For", "endExclusive"), ("Stmt.For", "body"),
  ("Stmt.Assert", "condition"), ("Stmt.Revert", "args"), ("Stmt.Emit", "args"),
  ("Stmt.Return", "value"), ("Stmt.Call", "call"), ("Stmt.Schedule", "call"),
  ("Expr.Place", "place"), ("Expr.Constructor", "args"),
  ("Expr.Unary", "operand"), ("Expr.Binary", "lhs"), ("Expr.Binary", "rhs"),
  ("Expr.LocalCall", "args"), ("Expr.Match", "scrutinee"), ("Expr.Match", "arms"),
  ("Place.Field", "base"), ("Place.Index", "base"), ("Place.Index", "index"),
  ("Pattern.Constructor", "args")
]

private def hasPair (visits : Array NodeVisitV1) (pair : String × String) : Bool :=
  visits.any fun visit => visit.path.any fun segment =>
    segment.parentTag == pair.1 && segment.fieldTag == pair.2

private def nestedOptionProgram (names : FixtureNames) (count : Nat) : ProgramV1 :=
  let nested := (List.range count).foldl (fun value _ => TypeV1.option value) .bool
  {
    name := names.name
    items := #[.state { visibility := .public_, name := names.name, type_ := nested }]
  }

private def wideProgram (names : FixtureNames) (itemCount : Nat) : ProgramV1 :=
  let leaf := ProgramItemV1.extensionReq {
    id := names.qualified
    version := "1.0.0"
    digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  }
  { name := names.name, items := Array.replicate itemCount leaf }

private def simpleOrderProgram (names : FixtureNames) : ProgramV1 := {
  name := names.name
  items := #[.const {
    name := names.name
    type_ := .map (.bool) (.uint 8)
    value := .binary .add exprLeaf exprLeaf
  }]
}

private def scalarTwinProgram
    (names : FixtureNames) (visibility : VisibilityV1) (width : UInt16) : ProgramV1 := {
  name := names.name
  items := #[.state { visibility, name := names.name, type_ := .uint width }]
}

/-- D1-PA-121: exact ProgramV1 node-bearing preorder and resource boundaries. -/
def run : IO Unit := do
  let name ← liftResult "fixture name" (parseSourceNameComponentV1 "n")
  let qualified ← liftResult "fixture qid" (parseSourceQualifiedNameV1 #["M", "n"])
  let names := { name, qualified }
  let moduleName ← liftResult "module" (parseSourceQualifiedNameV1 #["M"])

  let visits ← liftResult "comprehensive traversal"
    (canonicalNodeVisitsV1 (comprehensiveProgram names))
  expect (visits.size == 214) s!"comprehensive visit count: {visits.size}"
  expect (inventorySha256 visits ==
      "b7ff1648d1679d5a598621dc6f83101c51ffce57a86c804c13b00d117396b3e0")
    s!"comprehensive inventory digest: {inventorySha256 visits}"
  expect (nodeTags.size == 57 && edgePairs.size == 63) "closed inventory sizes"
  for tag in nodeTags do
    expect (visits.any fun visit => visit.constructorTag == tag) s!"missing tag {tag}"
  for visit in visits do
    expect (nodeTags.contains visit.constructorTag) s!"unknown tag {visit.constructorTag}"
  for pair in edgePairs do
    expect (hasPair visits pair) s!"missing edge {pair.1}.{pair.2}"
  expect (visits.any fun visit => visit.path.any fun segment =>
      segment.parentTag == "Program" && segment.fieldTag == "items" &&
        segment.index == 12)
    "root item source-order index 12 must be preserved"
  expect (visits.any fun visit => visit.path.any fun segment =>
      segment.parentTag == "StructDecl" && segment.fieldTag == "fields" &&
        segment.index == 1)
    "nested array source-order index 1 must be preserved"
  for visit in visits do
    for segment in visit.path do
      expect (edgePairs.contains (segment.parentTag, segment.fieldTag))
        s!"unknown edge {segment.parentTag}.{segment.fieldTag}"
    let _ ← liftResult s!"path {visit.constructorTag}"
      (nodeIdPreimageV1 moduleName qualified visit.path)
  let mut seen : Array NormalizedSyntacticPathV1 := #[]
  for visit in visits do
    expect (!seen.contains visit.path) s!"duplicate path {pathText visit.path}"
    seen := seen.push visit.path
  match visits.toList with
  | root :: _ =>
      expect (root.constructorTag == "Program" && root.path.isEmpty)
        "Program must be the empty-path first visit"
  | [] => throw <| IO.userError "comprehensive traversal returned no root"

  let table ← liftResult "comprehensive assignment"
    (assignNodeIdsV1 moduleName qualified (comprehensiveProgram names))
  let assignments := nodeAssignmentsPreorderV1 table
  expect (assignments.size == 214)
    s!"comprehensive assignment count: {assignments.size}"
  expect (assignments.map (fun assignment =>
      (assignment.constructorTag, assignment.path)) ==
    visits.map (fun visit => (visit.constructorTag, visit.path)))
    "assignment table must preserve canonical visit preorder"
  let mut seenNodeIds : Array ByteArray := #[]
  for assignment in assignments do
    let expected ← liftResult s!"assignment {assignment.constructorTag}"
      (nodeIdV1 moduleName qualified assignment.path)
    expect (decide (assignment.nodeId = expected))
      s!"assignment NodeId mismatch at {pathText assignment.path}"
    expect (!seenNodeIds.contains assignment.nodeId.bytes)
      s!"duplicate production NodeId at {pathText assignment.path}"
    seenNodeIds := seenNodeIds.push assignment.nodeId.bytes
  match assignments.toList with
  | root :: _ =>
      let rendered ← liftResult "assigned root render" (renderNodeId root.nodeId)
      expect (root.constructorTag == "Program" && root.path.isEmpty &&
          rendered == "nodeid:4f5e39282b8397030068bc51210cd28c")
        s!"assigned root mismatch: {rendered}"
  | [] => throw <| IO.userError "assignment table returned no root"

  let simple ← liftResult "simple order" (canonicalNodeVisitsV1 (simpleOrderProgram names))
  expect (simple.map (·.constructorTag) == #[
    "Program", "ConstDecl", "Type.Map", "Type.Bool", "Type.UInt",
    "Expr.Binary", "Expr.Literal", "Expr.Literal"
  ]) "mixed direct fields must use wire-field preorder"

  -- Public canonical TypeV1 visits: Map key before value, including nested Map.
  -- Align with simpleOrderProgram's ConstDecl type: Map Bool UInt8.
  let mapType := TypeV1.map .bool (.uint 8)
  let mapRootPath : NormalizedSyntacticPathV1 := #[{
    parentTag := "ConstDecl", fieldTag := "type", index := 0
  }]
  let mapVisits ← liftResult "canonical type visits Map"
    (canonicalTypeVisitsV1 mapType mapRootPath)
  expect (mapVisits.map (·.constructorTag) == #["Type.Map", "Type.Bool", "Type.UInt"])
    "Map type visits must be tag preorder Map then key then value"
  expect (mapVisits.size == 3) "Map type visit count"
  match mapVisits[0]?, mapVisits[1]?, mapVisits[2]? with
  | some mapVisit, some keyVisit, some valueVisit =>
      expect (mapVisit.path == mapRootPath) "Map root path identity"
      expect (keyVisit.path == mapRootPath.push {
        parentTag := "Type.Map", fieldTag := "key", index := 0
      }) "Map key path must precede value and use fieldTag key"
      expect (valueVisit.path == mapRootPath.push {
        parentTag := "Type.Map", fieldTag := "value", index := 0
      }) "Map value path must follow key with fieldTag value"
  | _, _, _ => throw <| IO.userError "Map type visits incomplete"

  let nestedMapType :=
    TypeV1.map (.map .bool (.uint 8)) (.option (.map (.int 8) .principal))
  let nestedMapVisits ← liftResult "canonical type visits nested Map"
    (canonicalTypeVisitsV1 nestedMapType mapRootPath)
  expect (nestedMapVisits.map (·.constructorTag) == #[
    "Type.Map",
    "Type.Map", "Type.Bool", "Type.UInt",
    "Type.Option", "Type.Map", "Type.Int", "Type.Principal"
  ]) "nested Map key-before-value preorder must recurse"
  -- Key subtree must appear before value subtree: first Type.Map child is key.
  let nestedKeyPath := mapRootPath.push {
    parentTag := "Type.Map", fieldTag := "key", index := 0
  }
  let nestedValuePath := mapRootPath.push {
    parentTag := "Type.Map", fieldTag := "value", index := 0
  }
  expect (nestedMapVisits.any fun v =>
      v.constructorTag == "Type.Map" && v.path == nestedKeyPath)
    "nested Map key child path"
  expect (nestedMapVisits.any fun v =>
      v.constructorTag == "Type.Option" && v.path == nestedValuePath)
    "nested Map value child path"
  let keyIdx ← match nestedMapVisits.findIdx? fun v => v.path == nestedKeyPath with
    | some i => pure i
    | none => throw <| IO.userError "nested Map key index missing"
  let valueIdx ← match nestedMapVisits.findIdx? fun v => v.path == nestedValuePath with
    | some i => pure i
    | none => throw <| IO.userError "nested Map value index missing"
  expect (keyIdx < valueIdx) "Map key visit must precede value visit"

  -- Leaf/container tag helper must match program preorder tags.
  expect (typeConstructorTagV1 .bool == "Type.Bool") "tag Bool"
  expect (typeConstructorTagV1 (.uint 8) == "Type.UInt") "tag UInt"
  expect (typeConstructorTagV1 (.array .bool 1) == "Type.Array") "tag Array"
  expect (typeConstructorTagV1 (.option .bool) == "Type.Option") "tag Option"
  expect (typeConstructorTagV1 mapType == "Type.Map") "tag Map"
  expect (typeConstructorTagV1 (.bytes 1) == "Type.Bytes") "tag Bytes"
  expect (typeConstructorTagV1 (.field names.name) == "Type.Field") "tag Field"

  -- Public Type visits must agree with full program preorder on the Map subtree
  -- tags/relative edges (full program paths include Program/items prefix).
  let simpleMapRootPath ← match simple.findSome? fun visit =>
      if visit.constructorTag == "Type.Map" then some visit.path else none with
    | some path => pure path
    | none => throw <| IO.userError "simple program missing Type.Map visit"
  let mapSubtreeFromProgram := simple.filter fun visit =>
    visit.path.size ≥ simpleMapRootPath.size &&
      (visit.path.extract 0 simpleMapRootPath.size) == simpleMapRootPath
  expect (mapSubtreeFromProgram.map (·.constructorTag) ==
      mapVisits.map (·.constructorTag))
    "public Type visits must match program preorder Map subtree tags"
  expect (mapSubtreeFromProgram.size == mapVisits.size)
    "public Type visits must match program preorder Map subtree count"
  -- Relative edges under the Map root must match (ignore absolute path prefix).
  for (progVisit, typeVisit) in mapSubtreeFromProgram.zip mapVisits do
    let progRel := progVisit.path.extract simpleMapRootPath.size progVisit.path.size
    let typeRel := typeVisit.path.extract mapRootPath.size typeVisit.path.size
    expect (progRel == typeRel)
      s!"Map subtree relative path mismatch at {progVisit.constructorTag}"

  let absent ← liftResult "absent children" (canonicalNodeVisitsV1 (absenceProgram names))
  expect (inventorySha256 absent ==
      "5fcb4463c92481e6514a8600721fc53d6b119e4eae95dbdd4c4a8130750fbcd2")
    s!"absent inventory digest: {inventorySha256 absent}"
  for forbidden in #[
      ("Stmt.Let", "typeAnn"), ("Stmt.If", "elseBlock"),
      ("Stmt.Return", "value"), ("Stmt.Revert", "args")] do
    expect (!hasPair absent forbidden)
      s!"absent/empty child emitted {forbidden.1}.{forbidden.2}"

  let scalarA ← liftResult "scalar twin A"
    (canonicalNodeVisitsV1 (scalarTwinProgram names .public_ 8))
  let scalarB ← liftResult "scalar twin B"
    (canonicalNodeVisitsV1 (scalarTwinProgram names .commitment 256))
  expect (scalarA == scalarB) "visibility and integer width are not visits"

  let stateItem := ProgramItemV1.state {
    visibility := VisibilityV1.public_
    name := names.name
    type_ := TypeV1.bool
  }
  let proofItem := ProgramItemV1.proof {
    invariant := names.name
    theorem_ := names.qualified
  }
  let orderProgramA : ProgramV1 := {
    name := names.name, items := #[stateItem, proofItem]
  }
  let orderProgramB : ProgramV1 := {
    name := names.name, items := #[proofItem, stateItem]
  }
  let orderA ← liftResult "source order A" (canonicalNodeVisitsV1 orderProgramA)
  let orderB ← liftResult "source order B" (canonicalNodeVisitsV1 orderProgramB)
  expect (orderA.map (·.constructorTag) ==
      #["Program", "StateDecl", "Type.Bool", "ProofDecl"])
    "source-order twin A"
  expect (orderB.map (·.constructorTag) ==
      #["Program", "ProofDecl", "StateDecl", "Type.Bool"])
    "source-order twin B"
  let orderTableA ← liftResult "source order table A"
    (assignNodeIdsV1 moduleName qualified orderProgramA)
  let orderTableB ← liftResult "source order table B"
    (assignNodeIdsV1 moduleName qualified orderProgramB)
  expect ((nodeAssignmentsPreorderV1 orderTableA).map (·.constructorTag) ==
      #["Program", "StateDecl", "Type.Bool", "ProofDecl"])
    "assignment source-order twin A"
  expect ((nodeAssignmentsPreorderV1 orderTableB).map (·.constructorTag) ==
      #["Program", "ProofDecl", "StateDecl", "Type.Bool"])
    "assignment source-order twin B"

  let atDepth ← liftResult "depth 256"
    (canonicalNodeVisitsV1 (nestedOptionProgram names 253))
  expect (atDepth.size == 256) s!"depth-limit visit count: {atDepth.size}"
  expectError "depth 257" "source node traversal exceeds the nesting bound"
    (canonicalNodeVisitsV1 (nestedOptionProgram names 254))
  let wrongIdentity ← liftResult "wrong identity"
    (parseSourceQualifiedNameV1 #["Elsewhere", "n"])
  expectError "assignment identity before depth"
    "program identity must begin with the exact module name components"
    (assignNodeIdsV1 moduleName wrongIdentity (nestedOptionProgram names 254))
  expectError "assignment depth 257" "source node traversal exceeds the nesting bound"
    (assignNodeIdsV1 moduleName qualified (nestedOptionProgram names 254))

  let atNodes ← liftResult "nodes 100000"
    (canonicalNodeVisitsV1 (wideProgram names 99999))
  expect (atNodes.size == 100000) s!"node-limit visit count: {atNodes.size}"
  expectError "nodes 100001" "source node traversal exceeds the node limit"
    (canonicalNodeVisitsV1 (wideProgram names 100000))

end Tests.Language.SourceNodeTraversalV1
