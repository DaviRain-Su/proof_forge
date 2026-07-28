import Lean
import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.SpanJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.ProgramV1SpanJoin

open Lean
open ProofForgeV2
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.SpanJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private unsafe def selectWithSpans (session : Language.Loader.ParserSession)
    (source : String) (requested : Option String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans source "<spans>" "SpanJoin" requested with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

/-- A representative ProgramV1 source that exercises every major node family. -/
private def baseSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "\n" ++
  "program SpanJoin where\n" ++
  "  state public myState : Array Bool 1\n" ++
  "  state public myMap : Map UInt8 Int8\n" ++
  "  state public myRecord : MyStruct\n" ++
  "  struct MyStruct where\n" ++
  "    fld : UInt8\n" ++
  "    opt : Option Bool\n" ++
  "    arr : Array Bool 1\n" ++
  "  enum MyEnum where\n" ++
  "    | A(UInt8)\n" ++
  "    | B\n" ++
  "  const myConst : Option Bool := true\n" ++
  "  event MyEvent(public evtArg : Bool)\n" ++
  "  error MyError(public errArg : UInt8)\n" ++
  "  init() do\n" ++
  "    let initLet : Bool := true\n" ++
  "    return\n" ++
  "  entry myEntry(public entArg : Bool) : Map UInt8 Int8 do\n" ++
  "    match entArg with\n" ++
  "    | true => do\n" ++
  "        call Remote.perform(false)\n" ++
  "    | false => do\n" ++
  "        return myConst\n" ++
  "    return myConst\n" ++
  "  view myView() : Option Bool do\n" ++
  "    schedule Remote.perform(true)\n" ++
  "    return myConst\n" ++
  "  fn myFn(public fnArg : Field bn254_fr) : Bytes 32 do\n" ++
  "    let localVal : UInt8 := 5\n" ++
  "    myState[0] := localVal\n" ++
  "    myRecord.fld := localVal\n" ++
  "    if localVal == 5 then\n" ++
  "      assert true\n" ++
  "      return\n" ++
  "    else\n" ++
  "      revert MyError(localVal)\n" ++
  "    for loopIdx in 0 ..< 10 bounded 2 do\n" ++
  "      emit MyEvent(loopIdx < 5)\n" ++
  "    let negVal : Int8 := -1\n" ++
  "    let notVal : Bool := !false\n" ++
  "    let bitNot : UInt8 := ~0\n" ++
  "    let shifted : UInt8 := localVal << 1\n" ++
  "    let cmp : Bool := (localVal > 0) && (localVal < 10)\n" ++
  "    let bits : UInt8 := (localVal & 1) ^ 2\n" ++
  "    let mixed : UInt8 := bits | 4\n" ++
  "    let strExpr := \"hello\"\n" ++
  "    return\n" ++
  "      match MyEnum.A(1) with\n" ++
  "      | MyEnum.A(_) => true\n" ++
  "      | B => false\n" ++
  "      | _ => false\n" ++
  "  invariant myInvariant : myState[0] == 0\n" ++
  "  requires extension com.example.ext version \"1.0.0\"\n" ++
  "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
  "  proof myInvariant using SpanJoin.thm\n"

/-- Same program with a leading comment that shifts every program span. -/
private def commentedSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "\n" ++
  "-- leading comment shifts spans\n" ++
  "program SpanJoin where\n" ++
  "  state public myState : Array Bool 1\n" ++
  "  state public myMap : Map UInt8 Int8\n" ++
  "  state public myRecord : MyStruct\n" ++
  "  struct MyStruct where\n" ++
  "    fld : UInt8\n" ++
  "    opt : Option Bool\n" ++
  "    arr : Array Bool 1\n" ++
  "  enum MyEnum where\n" ++
  "    | A(UInt8)\n" ++
  "    | B\n" ++
  "  const myConst : Option Bool := true\n" ++
  "  event MyEvent(public evtArg : Bool)\n" ++
  "  error MyError(public errArg : UInt8)\n" ++
  "  init() do\n" ++
  "    let initLet : Bool := true\n" ++
  "    return\n" ++
  "  entry myEntry(public entArg : Bool) : Map UInt8 Int8 do\n" ++
  "    match entArg with\n" ++
  "    | true => do\n" ++
  "        call Remote.perform(false)\n" ++
  "    | false => do\n" ++
  "        return myConst\n" ++
  "    return myConst\n" ++
  "  view myView() : Option Bool do\n" ++
  "    schedule Remote.perform(true)\n" ++
  "    return myConst\n" ++
  "  fn myFn(public fnArg : Field bn254_fr) : Bytes 32 do\n" ++
  "    let localVal : UInt8 := 5\n" ++
  "    myState[0] := localVal\n" ++
  "    myRecord.fld := localVal\n" ++
  "    if localVal == 5 then\n" ++
  "      assert true\n" ++
  "      return\n" ++
  "    else\n" ++
  "      revert MyError(localVal)\n" ++
  "    for loopIdx in 0 ..< 10 bounded 2 do\n" ++
  "      emit MyEvent(loopIdx < 5)\n" ++
  "    let negVal : Int8 := -1\n" ++
  "    let notVal : Bool := !false\n" ++
  "    let bitNot : UInt8 := ~0\n" ++
  "    let shifted : UInt8 := localVal << 1\n" ++
  "    let cmp : Bool := (localVal > 0) && (localVal < 10)\n" ++
  "    let bits : UInt8 := (localVal & 1) ^ 2\n" ++
  "    let mixed : UInt8 := bits | 4\n" ++
  "    let strExpr := \"hello\"\n" ++
  "    return\n" ++
  "      match MyEnum.A(1) with\n" ++
  "      | MyEnum.A(_) => true\n" ++
  "      | B => false\n" ++
  "      | _ => false\n" ++
  "  invariant myInvariant : myState[0] == 0\n" ++
  "  requires extension com.example.ext version \"1.0.0\"\n" ++
  "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
  "  proof myInvariant using SpanJoin.thm\n"

/-- Same program but a single token (`fld`) is renamed, changing only spans that
contain that token. -/
private def mutatedSource : String :=
  baseSource.replace "  let strExpr := \"hello\"" "  let strExrr := \"hello\""

private def spanStart (span : SourceByteSpanV1) : Nat := span.startByte.toNat
private def spanEnd (span : SourceByteSpanV1) : Nat := span.endByte.toNat

private def findSubbytes (haystack needle : ByteArray) : Option Nat := do
  if needle.isEmpty then return 0
  let last := haystack.size - needle.size + 1
  for start in [0:last] do
    let candidate := haystack.extract start (start + needle.size)
    if candidate == needle then
      return start
  none

private unsafe def parserEnvironment : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot "lean")
  importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

private unsafe def parseProgramCommand (source : String) : IO Syntax := do
  let env ← parserEnvironment
  let moduleStx ← Parser.testParseModule env "<spans>" source
  match moduleStx.getArgs with
  | #[_header, commands] =>
      match commands.getArgs.find? (·.isOfKind `ProofForgeV2.Language.programDecl) with
      | some command => pure command
      | none => throw <| IO.userError "source contains no program command"
  | _ => throw <| IO.userError "Lean parser returned an invalid module syntax tree"

private def expectSpanJoinError (label : String) (result : Except String α) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

/-- D1-01 span/NodeId origin-join slice: immutable parser snapshot → canonical node preorder. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (baseSourceUnit, baseSpans) ← selectWithSpans session baseSource none

  -- Every span corresponds to exactly one canonical-node visit with the same
  -- path and tag order.
  let expected ← liftResult "canonical visits"
    (canonicalNodeVisitsV1 baseSourceUnit.program)
  expect (baseSpans.size == expected.size)
    s!"span count {baseSpans.size} must equal canonical visit count {expected.size}"
  for ((path, _), visit) in baseSpans.zip expected do
    expect (path == visit.path)
      s!"span path must match canonical path at {visit.constructorTag}"
  for ((_, _), visit) in baseSpans.zip expected do
    let visitTag := visit.constructorTag
    expect (baseSpans.any fun (path, _) =>
      expected.any fun v => v.path == path && v.constructorTag == visitTag)
      s!"span tag must match canonical tag at {visitTag}"

  -- All spans lie within the program command span.
  let cmdSpan ← match baseSpans[0]? with
    | some (_, span) => pure span
    | none => throw <| IO.userError "span table is empty"
  for (_, span) in baseSpans do
    expect (cmdSpan.startByte ≤ span.startByte && span.endByte ≤ cmdSpan.endByte)
      "every span must lie inside the program command span"

  -- Start bytes are monotonic in canonical preorder.
  let mut prevStart : Nat := 0
  let mut first := true
  for (_, span) in baseSpans do
    unless first do
      expect (prevStart ≤ spanStart span)
        "span start bytes must be monotonic in canonical preorder"
    first := false
    prevStart := spanStart span

  -- Comment/layout variant: identical program, bytes, and hash; spans shift.
  let (variantUnit, variantSpans) ← selectWithSpans session commentedSource none
  expect (baseSourceUnit.program == variantUnit.program)
    "comment variant must decode to the same ProgramV1"
  let baseBytes ← liftResult "base canonical bytes"
    (canonicalValidatedSourceAstBytesV1 baseSourceUnit)
  let variantBytes ← liftResult "variant canonical bytes"
    (canonicalValidatedSourceAstBytesV1 variantUnit)
  expect (baseBytes == variantBytes)
    "comment variant must have identical canonical bytes"
  let baseHash ← liftResult "base source hash" (sourceHashV1 baseSourceUnit)
  let variantHash ← liftResult "variant source hash" (sourceHashV1 variantUnit)
  expect (baseHash == variantHash)
    "comment variant must have identical source hash"
  let variantCmdSpan ← match variantSpans[0]? with
    | some (_, span) => pure span
    | none => throw <| IO.userError "variant span table is empty"
  let delta := (spanStart variantCmdSpan : Int) - (spanStart cmdSpan : Int)
  expect (baseSpans.size == variantSpans.size)
    "comment variant must preserve span count"
  for ((basePath, baseSpan), (variantPath, variantSpan)) in baseSpans.zip variantSpans do
    expect (basePath == variantPath)
      "comment variant must preserve syntactic path order"
    let expectedStart := (spanStart baseSpan : Int) + delta
    let expectedEnd := (spanEnd baseSpan : Int) + delta
    expect (spanStart variantSpan == expectedStart.toNat)
      "comment variant must shift span starts by the program-command delta"
    expect (spanEnd variantSpan == expectedEnd.toNat)
      "comment variant must shift span ends by the program-command delta"

  -- Same-length token rename: identity (ProgramV1/bytes/hash) tracks content,
  -- but no span moves. The renamed token must still be covered by a span.
  let (mutatedUnit, mutatedSpans) ← selectWithSpans session mutatedSource none
  expect (mutatedUnit.program != baseSourceUnit.program)
    "same-length rename must change the decoded ProgramV1"
  let mutatedBytes ← liftResult "mutated canonical bytes"
    (canonicalValidatedSourceAstBytesV1 mutatedUnit)
  expect (mutatedBytes != baseBytes)
    "same-length rename must change canonical bytes"
  expect (mutatedSpans.size == baseSpans.size)
    "same-length rename must preserve span count"
  for ((basePath, baseSpan), (mutatedPath, mutatedSpan)) in baseSpans.zip mutatedSpans do
    expect (basePath == mutatedPath)
      "same-length rename must preserve syntactic path order"
    expect (baseSpan == mutatedSpan)
      "same-length rename must not move any span"
  let renamedToken := "strExrr".toUTF8
  let renamedStart ← match findSubbytes mutatedSource.toUTF8 renamedToken with
    | some start => pure start
    | none => throw <| IO.userError "renamed token not found in mutated source"
  let renamedEnd := renamedStart + renamedToken.size
  expect (mutatedSpans.any fun (_, span) =>
      span.startByte.toNat ≤ renamedStart && renamedEnd ≤ span.endByte.toNat)
    "a span must cover the renamed token"

  -- Synthetic/missing-position command syntax must fail closed.
  let syntheticCommand := Syntax.node SourceInfo.none nullKind #[]
  expectSpanJoinError "synthetic command span"
    (spanJoinV1 baseSource syntheticCommand baseSourceUnit.program)

  -- Count mismatch against a tampered AST must fail closed.
  let commandStx ← parseProgramCommand baseSource
  let firstItem ← match baseSourceUnit.program.items[0]? with
    | some item => pure item
    | none => throw <| IO.userError "base program has no items"
  let tamperedProgram : ProgramV1 := {
    name := baseSourceUnit.program.name
    items := baseSourceUnit.program.items.push firstItem
  }
  expectSpanJoinError "tampered program count"
    (spanJoinV1 baseSource commandStx tamperedProgram)

  -- Recursive Type surface (Array Map / Option Map / deeper nesting) must
  -- join exact spans for every TypeV1 node without a second type interpretation.
  let recursiveTypeSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "\n" ++
    "program RecursiveTypes where\n" ++
    "  state public arrMap : Array Map UInt64 Bool 4\n" ++
    "  state public optMap : Option Map UInt64 Bool\n" ++
    "  state public deep : Option Array Map UInt8 Int8 2\n" ++
    "  entry ok() : UInt64 do\n" ++
    "    return 0\n"
  let (recursiveUnit, recursiveSpans) ←
    selectWithSpans session recursiveTypeSource none
  let recursiveExpected ← liftResult "recursive type visits"
    (canonicalNodeVisitsV1 recursiveUnit.program)
  expect (recursiveSpans.size == recursiveExpected.size)
    s!"recursive type span count {recursiveSpans.size} must equal visit count {recursiveExpected.size}"
  for ((path, _), visit) in recursiveSpans.zip recursiveExpected do
    expect (path == visit.path)
      s!"recursive type span path must match at {visit.constructorTag}"
  -- Type constructor tags for nested Map/Array/Option must appear.
  let typeTags := recursiveExpected.map (·.constructorTag)
  expect (typeTags.any (· == "Type.Array"))
    "recursive type program must emit Type.Array spans"
  expect (typeTags.any (· == "Type.Map"))
    "recursive type program must emit Type.Map spans"
  expect (typeTags.any (· == "Type.Option"))
    "recursive type program must emit Type.Option spans"
  -- Nested Array Map must contribute both outer Array and inner Map type nodes
  -- under the first state declaration type field.
  let arrayMapTypePaths := recursiveExpected.filter fun visit =>
    visit.constructorTag == "Type.Array" || visit.constructorTag == "Type.Map" ||
      visit.constructorTag == "Type.Option"
  expect (arrayMapTypePaths.size ≥ 6)
    s!"expected ≥6 nested container type nodes, got {arrayMapTypePaths.size}"

  -- Nested type spans must equal visit count and be path-identical (already
  -- checked above); additionally Map key span must precede value span.
  let mapKeyValuePairs := recursiveExpected.zipIdx.filterMap fun (visit, idx) =>
    if visit.constructorTag == "Type.Map" then some (visit, idx) else none
  for (mapVisit, mapIdx) in mapKeyValuePairs do
    let keyPath := mapVisit.path.push {
      parentTag := "Type.Map", fieldTag := "key", index := 0
    }
    let valuePath := mapVisit.path.push {
      parentTag := "Type.Map", fieldTag := "value", index := 0
    }
    let keyIdx ← match recursiveExpected.findIdx? fun v => v.path == keyPath with
      | some i => pure i
      | none => throw <| IO.userError "recursive Map key path missing"
    let valueIdx ← match recursiveExpected.findIdx? fun v => v.path == valuePath with
      | some i => pure i
      | none => throw <| IO.userError "recursive Map value path missing"
    expect (mapIdx < keyIdx && keyIdx < valueIdx)
      "Map visit order must be Map then key then value"
    let keySpan ← match recursiveSpans[keyIdx]? with
      | some (_, span) => pure span
      | none => throw <| IO.userError "recursive Map key span missing"
    let valueSpan ← match recursiveSpans[valueIdx]? with
      | some (_, span) => pure span
      | none => throw <| IO.userError "recursive Map value span missing"
    expect (spanStart keySpan ≤ spanStart valueSpan)
      "Map key span start must precede or equal value span start in source order"

  -- Same-node-count tampered TypeV1 must fail closed on tag/path/count:
  -- Array ↔ Option (both two type nodes when element is a leaf) and Map
  -- key/value swap (three type nodes preserved).
  let arrayStateSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "\n" ++
    "program TamperTypes where\n" ++
    "  state public arr : Array Bool 1\n" ++
    "  state public mp : Map UInt8 Int8\n" ++
    "  entry ok() : UInt64 do\n" ++
    "    return 0\n"
  let (arrayStateUnit, _) ← selectWithSpans session arrayStateSource none
  let arrayStateCmd ← parseProgramCommand arrayStateSource
  let tamperedArrayToOption : ProgramV1 :=
    match arrayStateUnit.program.items.toList with
    | [.state s0, .state s1, rest] =>
        {
          name := arrayStateUnit.program.name
          items := #[
            .state { s0 with type_ := .option .bool },
            .state s1,
            rest
          ]
        }
    | _ => arrayStateUnit.program
  expectSpanJoinError "same-count Array↔Option type tag"
    (spanJoinV1 arrayStateSource arrayStateCmd tamperedArrayToOption)
  let tamperedMapKeyValue : ProgramV1 :=
    match arrayStateUnit.program.items.toList with
    | [.state s0, .state s1, rest] =>
        {
          name := arrayStateUnit.program.name
          items := #[
            .state s0,
            .state { s1 with type_ := .map (.int 8) (.uint 8) },
            rest
          ]
        }
    | _ => arrayStateUnit.program
  expectSpanJoinError "same-count Map key/value swap"
    (spanJoinV1 arrayStateSource arrayStateCmd tamperedMapKeyValue)

  IO.println "Tests.Language.ProgramV1SpanJoin: ok"

end Tests.Language.ProgramV1SpanJoin
