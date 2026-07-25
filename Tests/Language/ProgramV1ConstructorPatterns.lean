import Tests.Language.ParserSession
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1ConstructorPatterns

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source (body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ConstructorPatterns where\n" ++
  "  entry run(flag : Bool) : UInt64 do\n" ++
  body

private unsafe def decodeSource
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-constructor-patterns-" ++ label ++ ">")
      "Tests.ProgramV1ConstructorPatterns" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def decodeEntryStatements
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO (Array StmtV1) := do
  let value ← decodeSource session label body
  match value.program.items[0]? with
  | some (ProgramItemV1.entry declaration) => pure declaration.body.statements
  | other => throw <| IO.userError s!"'{label}' did not decode an entry: {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (source body)
      ("<program-v1-constructor-patterns-negative-" ++ label ++ ">")
      "Tests.ProgramV1ConstructorPatterns" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

private def canonicalBytes (source : ValidatedSourceV1) (label : String) : IO ByteArray :=
  match canonicalValidatedSourceAstBytesV1 source with
  | .ok bytes => pure bytes
  | .error error => throw <| IO.userError s!"{label}: canonical bytes failed: {error}"

private def sourceHash (source : ValidatedSourceV1) (label : String) : IO ProofForgeV2.Core.Common.Digest :=
  match sourceHashV1 source with
  | .ok digest => pure digest
  | .error error => throw <| IO.userError s!"{label}: sourceHashV1 failed: {error}"

private def expectSameProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program == right.program) s!"{label}: ProgramV1 AST changed"
  expect ((← canonicalBytes left (label ++ " left")) ==
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes changed"
  expect ((← sourceHash left (label ++ " left")) ==
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 changed"

private def expectDifferentProgramBytesAndHash
    (left right : ValidatedSourceV1) (label : String) : IO Unit := do
  expect (left.program != right.program) s!"{label}: ProgramV1 AST unexpectedly aliased"
  expect ((← canonicalBytes left (label ++ " left")) !=
    (← canonicalBytes right (label ++ " right")))
    s!"{label}: canonical bytes unexpectedly aliased"
  expect ((← sourceHash left (label ++ " left")) !=
    (← sourceHash right (label ++ " right")))
    s!"{label}: sourceHashV1 unexpectedly aliased"

/-- Test-side shape description so we never need to construct private AST carriers. -/
inductive PatternShape
  | wildcard
  | bind (raw : String)
  | boolLiteral (value : Bool)
  | intLiteral (value : Nat)
  | stringLiteral (value : String)
  | constructor (path : List String) (args : Array PatternShape)
  deriving Repr

private partial def checkPattern (pattern : PatternV1) (shape : PatternShape) (label : String) : IO Unit := do
  match pattern, shape with
  | .wildcard, .wildcard => pure ()
  | .bind name, .bind expected =>
      expect (name.raw == expected) s!"{label}: bind raw '{name.raw}' != '{expected}'"
  | .literal (.bool value), .boolLiteral expected =>
      expect (value == expected) s!"{label}: bool literal changed"
  | .literal (.integer value), .intLiteral expected =>
      expect (value == expected) s!"{label}: integer literal changed"
  | .literal (.string value), .stringLiteral expected =>
      expect (value == expected) s!"{label}: string literal changed"
  | .constructor qualified args, .constructor expectedPath expectedArgs =>
      let raws : List String := Array.toList ((NonEmptyArray.toArray qualified.components).map (·.raw))
      expect (raws == expectedPath)
        s!"{label}: constructor path '{repr raws}' != '{repr expectedPath}'"
      expect (args.size == expectedArgs.size)
        s!"{label}: constructor arg count {args.size} != {expectedArgs.size}"
      let pairs := List.zip args.toList expectedArgs.toList
      let indexed := List.zip (List.range pairs.length) pairs
      for (i, (arg, shape)) in indexed do
        checkPattern arg shape s!"{label}: arg {i}"
  | _, _ =>
      throw <| IO.userError s!"{label}: pattern shape mismatch: got {repr pattern}, expected {repr shape}"

private unsafe def onlyArmPattern
    (session : ProofForgeV2.Language.Loader.ParserSession) (label body : String) :
    IO PatternV1 := do
  let statements ← decodeEntryStatements session label body
  match statements[0]? with
  | some (StmtV1.match_ _ arms) => do
      expect (arms.size == 1) s!"{label}: expected exactly one arm"
      match arms[0]? with
      | some arm => pure arm.pattern
      | none => throw <| IO.userError s!"{label}: missing arm 0"
  | other => throw <| IO.userError s!"{label}: expected match statement, got {repr other}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Empty constructor argument list decodes to #[]
  let emptyCtor ← onlyArmPattern session "empty-ctor"
    ("    match flag with\n" ++
     "    | A.B() => do\n" ++
     "      return 0\n")
  checkPattern emptyCtor (.constructor ["A", "B"] #[]) "empty constructor"

  -- Single bind argument
  let singleBind ← onlyArmPattern session "single-bind"
    ("    match flag with\n" ++
     "    | A.B(x) => do\n" ++
     "      return 0\n")
  checkPattern singleBind (.constructor ["A", "B"] #[.bind "x"]) "single bind arg"

  -- Multiple arguments preserve source order and mix pattern kinds
  let mixedArgs ← onlyArmPattern session "mixed-args"
    ("    match flag with\n" ++
     "    | A.B(_, value, 42, true, \"ok\") => do\n" ++
     "      return 0\n")
  checkPattern mixedArgs (.constructor ["A", "B"]
    #[.wildcard, .bind "value", .intLiteral 42, .boolLiteral true, .stringLiteral "ok"])
    "mixed constructor args"

  -- Nested constructor argument
  let nestedCtor ← onlyArmPattern session "nested-ctor"
    ("    match flag with\n" ++
     "    | Outer.Inner(Option.Some(x), Option.None()) => do\n" ++
     "      return 0\n")
  checkPattern nestedCtor (.constructor ["Outer", "Inner"]
    #[.constructor ["Option", "Some"] #[.bind "x"], .constructor ["Option", "None"] #[]])
    "nested constructor args"

  -- Escaped raw dotted component keeps raw identity
  let escapedCtor ← onlyArmPattern session "escaped-ctor"
    ("    match flag with\n" ++
     "    | A.«foo.bar»(x) => do\n" ++
     "      return 0\n")
  checkPattern escapedCtor (.constructor ["A", "foo.bar"] #[.bind "x"])
    "escaped raw dotted constructor path"

  -- Ordinary and escaped spelling of same raw path canonicalize identically
  expectSameProgramBytesAndHash
    (← decodeSource session "ordinary-spelling"
      ("    match flag with\n" ++
       "    | A.B() => do\n" ++
       "      return 0\n"))
    (← decodeSource session "escaped-spelling"
      ("    match flag with\n" ++
       "    | A.«B»() => do\n" ++
       "      return 0\n"))
    "ordinary/escaped spelling must canonicalize equally"

  -- Hash non-aliasing across shape differences
  let baseA ← decodeSource session "hash-base-a"
    ("    match flag with\n" ++
     "    | A.B(x, y) => do\n" ++
     "      return 0\n")
  let swappedArgs ← decodeSource session "hash-swapped-args"
    ("    match flag with\n" ++
     "    | A.B(y, x) => do\n" ++
     "      return 0\n")
  let differentPath ← decodeSource session "hash-different-path"
    ("    match flag with\n" ++
     "    | A.C(x, y) => do\n" ++
     "      return 0\n")
  let bindInstead ← decodeSource session "hash-bind-instead"
    ("    match flag with\n" ++
     "    | A.B(xy) => do\n" ++
     "      return 0\n")
  let nestedInstead ← decodeSource session "hash-nested-instead"
    ("    match flag with\n" ++
     "    | A.B(Option.Some(x), y) => do\n" ++
     "      return 0\n")
  expectDifferentProgramBytesAndHash baseA swappedArgs "swapped args must not alias"
  expectDifferentProgramBytesAndHash baseA differentPath "different constructor path must not alias"
  expectDifferentProgramBytesAndHash baseA bindInstead "bind vs multi-arg must not alias"
  expectDifferentProgramBytesAndHash baseA nestedInstead "nested arg change must not alias"
  expectDifferentProgramBytesAndHash swappedArgs differentPath "distinct changes must not alias"

  -- Single-component call-like pattern must fail closed as a non-qualified path
  expectReject session "single-component-call-like"
    ("    match flag with\n" ++
     "    | Some(value) => do\n" ++
     "      return 0\n")
    "source qualified id must contain 2..256 components"

  -- Nested single-component call-like argument must fail closed the same way
  expectReject session "nested-single-component-call-like"
    ("    match flag with\n" ++
     "    | A.B(Some(x)) => do\n" ++
     "      return 0\n")
    "source qualified id must contain 2..256 components"

  -- Reserved first component in constructor path fails closed before later components
  expectReject session "reserved-first-path-component"
    ("    match flag with\n" ++
     "    | «let».A() => do\n" ++
     "      return 0\n")
    "reserved portable identifier 'let'"

  -- Reserved component in constructor path fails closed at the first offending component
  expectReject session "reserved-path-component"
    ("    match flag with\n" ++
     "    | A.«let»() => do\n" ++
     "      return 0\n")
    "reserved portable identifier 'let'"

  -- Malformed argument lists fail closed
  expectReject session "missing-close-paren"
    ("    match flag with\n" ++
     "    | A.B(x => do\n" ++
     "      return 0\n")
    "failed to parse file"
  expectReject session "leading-comma"
    ("    match flag with\n" ++
     "    | A.B(, x) => do\n" ++
     "      return 0\n")
    "failed to parse file"
  expectReject session "trailing-comma"
    ("    match flag with\n" ++
     "    | A.B(x, ) => do\n" ++
     "      return 0\n")
    "failed to parse file"
  expectReject session "double-comma"
    ("    match flag with\n" ++
     "    | A.B(x, , y) => do\n" ++
     "      return 0\n")
    "failed to parse file"
  expectReject session "trailing-payload"
    ("    match flag with\n" ++
     "    | A.B() extra => do\n" ++
     "      return 0\n")
    "failed to parse file"

  -- Error priority: path component error precedes argument errors
  expectReject session "path-before-arg"
    ("    match flag with\n" ++
     "    | A.«let»(«if») => do\n" ++
     "      return 0\n")
    "reserved portable identifier 'let'"

  -- Error priority: earlier argument error precedes later argument error
  expectReject session "earlier-arg-before-later"
    ("    match flag with\n" ++
     "    | A.B(«let», «if») => do\n" ++
     "      return 0\n")
    "reserved portable identifier 'let'"

  -- Error priority: arm pattern error precedes body error
  expectReject session "pattern-before-body"
    ("    match flag with\n" ++
     "    | A.«let»() => do\n" ++
     "      return «if»\n")
    "reserved portable identifier 'let'"

  -- Error priority: earlier arm precedes later arm and its body
  expectReject session "earlier-arm-before-later"
    ("    match flag with\n" ++
     "    | A.B() => do\n" ++
     "      return 0\n" ++
     "    | A.«let»() => do\n" ++
     "      return «if»\n")
    "reserved portable identifier 'let'"

end Tests.Language.ProgramV1ConstructorPatterns
