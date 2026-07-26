import Lean.Parser.Module
import Lean.Util.Path
import Std.Data.HashSet
import ProofForgeV2.Language.Syntax
import ProofForgeV2.Source.SpanJoinV1

namespace ProofForgeV2.Language.Loader

open Lean Parser ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def invalid (message : String) : CompileError :=
  .invalidProgram message

private inductive NamespaceState where
  | bounded (name : Name) (parts : Nat)
  | overLimit (name : Name) (parts : Nat)
  deriving Inhabited

private structure NamespaceFrame where
  declared : Name
  previous : NamespaceState
  deriving Inhabited

private def namesEqual (left right : Name) : Bool := Id.run do
  let mut left := left
  let mut right := right
  let mut equal := true
  let mut done := false
  while !done do
    match left, right with
    | .anonymous, .anonymous => done := true
    | .str leftPrefix leftPart, .str rightPrefix rightPart =>
        if leftPart != rightPart then
          equal := false
          done := true
        else
          left := leftPrefix
          right := rightPrefix
    | .num leftPrefix leftPart, .num rightPrefix rightPart =>
        if leftPart != rightPart then
          equal := false
          done := true
        else
          left := leftPrefix
          right := rightPrefix
    | _, _ =>
        equal := false
        done := true
  return equal

private def validateHeader (header : Syntax) : Except CompileError Unit := do
  match header with
  | `(Parser.Module.header| $[module%$_]? $[prelude%$_]? $imports*) =>
      unless imports.size == 1 do
        throw <| invalid "source must import exactly ProofForgeV2"
      match imports[0]! with
      | `(Parser.Module.import| import $name:ident) =>
          unless namesEqual name.getId `ProofForgeV2 do
            throw <| invalid "unsupported import; only ProofForgeV2 is allowed"
      | _ => throw <| invalid "public/meta/import-all forms are not allowed in program source"
  | _ => throw <| invalid "invalid Lean module header"

private def sourceQualifiedKey (name : SourceQualifiedNameV1) : String :=
  String.intercalate "\u0000"
    ((NonEmptyArray.toArray name.components).map (·.raw) |>.toList)

private def renderSourceQualified (name : SourceQualifiedNameV1) : String :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Name.str acc component.raw) .anonymous |>.toString

private def sourceQualifiedNameV1ToLeanName (name : SourceQualifiedNameV1) : Name :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Name.str acc component.raw) .anonymous

private def parseSourceQualifiedInput (environment : Environment)
    (label value : String) : Except CompileError SourceQualifiedNameV1 := do
  let parsedIdent ← match Parser.runParserCategory environment `term value with
    | .ok parsedIdent => pure parsedIdent
    | .error _ => throw <| invalid s!"{label} must be one exact Lean identifier"
  unless parsedIdent.isIdent do
    throw <| invalid s!"{label} must be one exact Lean identifier"
  match sourceQualifiedNameV1FromLeanName parsedIdent.getId with
  | .ok name => pure name
  | .error message => throw <| invalid s!"invalid {label}: {message}"

/- ProgramV1 product command walker, retaining the original command syntax for span joining. -/
private def processCommandsV1WithSyntax (moduleName : SourceQualifiedNameV1)
    (commands : Array Syntax) : Except CompileError (Array (ValidatedSourceV1 × Syntax)) := do
  let mut scopes : Array NamespaceFrame := #[]
  let mut namespaceState : NamespaceState := .bounded .anonymous 0
  let mut programs : Array (ValidatedSourceV1 × Syntax) := #[]
  let mut programKeys : Std.HashSet String := {}
  for command in commands do
    if command.isOfKind ``Parser.Command.eoi then
      continue
    match command with
    | `(program $_name:ident where $_items:pfItem*) =>
        let moduleNameLean := sourceQualifiedNameV1ToLeanName moduleName
        let currentNamespace := match namespaceState with
          | .bounded name _ => Language.ProgramNamespace.bounded (name.replacePrefix moduleNameLean .anonymous)
          | .overLimit _ _ => Language.ProgramNamespace.overLimit
        let source ←
          Language.decodeProgramCommandV1Checked moduleName currentNamespace command
        let key := sourceQualifiedKey source.programIdentity
        let (alreadyPresent, updatedKeys) := programKeys.containsThenInsert key
        if alreadyPresent then
          throw <| invalid s!"duplicate program '{renderSourceQualified source.programIdentity}'"
        programKeys := updatedKeys
        programs := programs.push (source, command)
    | `(command| open ProofForgeV2.Language) => pure ()
    | `(command| namespace $name:ident) =>
        let declared := name.getId
        scopes := scopes.push { declared, previous := namespaceState }
        match namespaceState with
        | .bounded currentName currentParts =>
            match Language.boundedNamePartCount
                (Language.maxSyntaxNesting - currentParts) declared with
            | some addedParts =>
                namespaceState := .bounded
                  (currentName ++ declared) (currentParts + addedParts)
            | none =>
                namespaceState := .overLimit currentName currentParts
        | .overLimit currentName currentParts =>
            namespaceState := .overLimit currentName currentParts
    | `(command| end) =>
        if scopes.isEmpty then
          throw <| invalid "unmatched namespace end"
        let frame := scopes.back!
        scopes := scopes.pop
        namespaceState := frame.previous
    | `(command| end $name:ident) =>
        if scopes.isEmpty then
          throw <| invalid "unmatched namespace end"
        let frame := scopes.back!
        unless namesEqual name.getId frame.declared do
          throw <| invalid "namespace end does not match the active namespace"
        scopes := scopes.pop
        namespaceState := frame.previous
    | _ =>
        throw <| invalid "Lean command is outside the portable program DSL"
  unless scopes.isEmpty do
    throw <| invalid "unterminated namespace"
  pure programs

private def processCommandsV1 (moduleName : SourceQualifiedNameV1)
    (commands : Array Syntax) : Except CompileError (Array ValidatedSourceV1) := do
  let programs ← processCommandsV1WithSyntax moduleName commands
  pure (programs.map Prod.fst)

private unsafe def parserEnvironment : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot "lean")
  importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

private def checkSourceSize (source : String) : Except CompileError Unit :=
  if source.toUTF8.size > 16 * 1024 * 1024 then
    .error <| invalid "source exceeds the 16 MiB limit"
  else
    .ok ()

private unsafe def parseProgramsV1WithEnvironment (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) := do
  if let .error error := checkSourceSize source then
    return .error error
  let moduleName ← match parseSourceQualifiedInput environment "--module" moduleInput with
    | .ok moduleName => pure moduleName
    | .error error => return .error error
  try
    let parsedSyntax ← Parser.testParseModule environment fileName source
    match parsedSyntax.getArgs with
    | #[header, commands] =>
        return do
          validateHeader header
          processCommandsV1 moduleName commands.getArgs
    | _ => return .error <| invalid "Lean parser returned an invalid module syntax tree"
  catch error =>
    return .error <| invalid s!"Lean parser rejected source: {error}"

private def selectParsedProgramV1 (environment : Environment)
    (parsed : Except CompileError (Array ValidatedSourceV1))
    (requested : Option String) : Except CompileError ValidatedSourceV1 := do
  let programs ← parsed
  match requested with
  | some input =>
      let requestedName ← parseSourceQualifiedInput environment "--program" input
      match programs.find? (·.programIdentity == requestedName) with
      | some source => pure source
      | none => throw <| invalid s!"program '{input}' was not found"
  | none =>
      match programs with
      | #[source] => pure source
      | #[] => throw <| invalid "source contains no program"
      | _ => throw <| invalid (
          "source contains multiple programs; pass --program <qualified-name>")

private def selectParsedProgramV1WithSyntax (environment : Environment)
    (parsed : Except CompileError (Array (ValidatedSourceV1 × Syntax)))
    (requested : Option String) : Except CompileError (ValidatedSourceV1 × Syntax) := do
  let programs ← parsed
  match requested with
  | some input =>
      let requestedName ← parseSourceQualifiedInput environment "--program" input
      match programs.find? (·.1.programIdentity == requestedName) with
      | some source => pure source
      | none => throw <| invalid s!"program '{input}' was not found"
  | none =>
      match programs with
      | #[source] => pure source
      | #[] => throw <| invalid "source contains no program"
      | _ => throw <| invalid (
          "source contains multiple programs; pass --program <qualified-name>")

private unsafe def parseProgramsV1WithEnvironmentWithSyntax (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except CompileError (Array (ValidatedSourceV1 × Syntax))) := do
  if let .error error := checkSourceSize source then
    return .error error
  let moduleName ← match parseSourceQualifiedInput environment "--module" moduleInput with
    | .ok moduleName => pure moduleName
    | .error error => return .error error
  try
    let parsedSyntax ← Parser.testParseModule environment fileName source
    match parsedSyntax.getArgs with
    | #[header, commands] =>
        return do
          validateHeader header
          processCommandsV1WithSyntax moduleName commands.getArgs
    | _ => return .error <| invalid "Lean parser returned an invalid module syntax tree"
  catch error =>
    return .error <| invalid s!"Lean parser rejected source: {error}"

/-- Immutable locked Lean parser environment for parsing multiple independent
sources without repeatedly importing the frontend module. Create a session on
one control thread before sharing/reusing it; concurrent creation is unsupported. -/
structure ParserSession where
  private environment : Environment

namespace ParserSession

unsafe def create : IO ParserSession :=
  return { environment := ← parserEnvironment }

unsafe def parseProgramsV1 (session : ParserSession) (source fileName moduleName : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) :=
  parseProgramsV1WithEnvironment session.environment source fileName moduleName

unsafe def selectProgramV1 (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError ValidatedSourceV1) := do
  return selectParsedProgramV1 session.environment
    (← session.parseProgramsV1 source fileName moduleName) requested

unsafe def selectProgramV1WithSpans (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))) := do
  let parsed ← parseProgramsV1WithEnvironmentWithSyntax session.environment source fileName moduleName
  match parsed with
  | .error error => return .error error
  | .ok programs =>
      match selectParsedProgramV1WithSyntax session.environment (.ok programs) requested with
      | .error error => return .error error
      | .ok (src, commandStx) =>
          match spanJoinV1 source commandStx src.program with
          | .ok spans => return .ok (src, spans)
          | .error message => return .error <| invalid message

end ParserSession

unsafe def parseProgramsV1 (source fileName moduleName : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) := do
  if let .error error := checkSourceSize source then
    return .error error
  let session ← ParserSession.create
  session.parseProgramsV1 source fileName moduleName

unsafe def selectProgramV1 (source fileName moduleName : String)
    (requested : Option String) : IO (Except CompileError ValidatedSourceV1) := do
  let session ← ParserSession.create
  session.selectProgramV1 source fileName moduleName requested

unsafe def selectProgramV1WithSpans (source fileName moduleName : String)
    (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))) := do
  let session ← ParserSession.create
  session.selectProgramV1WithSpans source fileName moduleName requested

end ProofForgeV2.Language.Loader
