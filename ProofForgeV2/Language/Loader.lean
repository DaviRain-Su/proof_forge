import Lean.Parser.Module
import Lean.Util.Path
import Std.Data.HashSet
import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Language.Loader

open Lean Parser ProofForgeV2

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

private def hasDuplicate (values : Array String) : Bool := Id.run do
  let mut seen : Std.HashSet String := {}
  for value in values do
    let (alreadyPresent, updated) := seen.containsThenInsert value
    if alreadyPresent then
      return true
    seen := updated
  return false

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

private def validateProgram (contractProgram : Source.Program) : Except CompileError Unit := do
  if contractProgram.entries.isEmpty then
    throw <| invalid s!"program '{contractProgram.qualifiedName}' must declare at least one entry or view"
  let stateNames := contractProgram.state.map (·.name)
  if hasDuplicate stateNames then
    throw <| invalid s!"program '{contractProgram.qualifiedName}' contains duplicate state declarations"
  let entryNames := contractProgram.entries.map (·.name)
  if hasDuplicate entryNames then
    throw <| invalid s!"program '{contractProgram.qualifiedName}' contains duplicate entry declarations"
  for entrypoint in contractProgram.entries do
    let paramNames := entrypoint.params.map (·.name)
    if hasDuplicate paramNames then
      throw <| invalid s!"entry '{entrypoint.name}' contains duplicate parameters"

private def processCommands (commands : Array Syntax) :
    Except CompileError (Array Source.Program) := do
  let mut scopes : Array NamespaceFrame := #[]
  -- Keep a materialized namespace only while it can still form a legal
  -- portable program identity. Lean permits deeper transient namespace scopes,
  -- so an overflow state must be restorable instead of rejected eagerly.
  let mut namespaceState : NamespaceState := .bounded .anonymous 0
  let mut programs : Array Source.Program := #[]
  let mut programNames : Std.HashSet String := {}
  for command in commands do
    if command.isOfKind ``Parser.Command.eoi then
      continue
    match command with
    | `(program $_name:ident where $_items:pfItem*) =>
        let currentNamespace := match namespaceState with
          | .bounded name _ => Language.ProgramNamespace.bounded name
          | .overLimit _ _ => Language.ProgramNamespace.overLimit
        let contractProgram ←
          Language.decodeProgramCommandChecked currentNamespace command
        validateProgram contractProgram
        let (alreadyPresent, updatedNames) :=
          programNames.containsThenInsert contractProgram.qualifiedName
        if alreadyPresent then
          throw <| invalid s!"duplicate program '{contractProgram.qualifiedName}'"
        programNames := updatedNames
        programs := programs.push contractProgram
    | `(command| open ProofForgeV2.Language) => pure ()
    | `(command| namespace $name:ident) =>
        let declared := name.getId
        scopes := scopes.push {
          declared
          previous := namespaceState
        }
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
        throw <| invalid s!"Lean command '{command.getKind}' is outside the portable program DSL"
  unless scopes.isEmpty do
    throw <| invalid "unterminated namespace"
  return programs

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

private unsafe def parseProgramsWithEnvironment (environment : Environment)
    (source fileName : String) : IO (Except CompileError (Array Source.Program)) := do
  if let .error error := checkSourceSize source then
    return .error error
  try
    let parsedSyntax ← Parser.testParseModule environment fileName source
    match parsedSyntax.getArgs with
    | #[header, commands] =>
        return do
          validateHeader header
          processCommands commands.getArgs
    | _ => return .error <| invalid "Lean parser returned an invalid module syntax tree"
  catch error =>
    return .error <| invalid s!"Lean parser rejected source: {error}"

private def selectParsedProgram (parsed : Except CompileError (Array Source.Program))
    (requested : Option String) : Except CompileError Source.Program :=
  parsed >>= fun programs =>
    match requested with
    | some name =>
        match programs.find? (·.qualifiedName == name) with
        | some contractProgram => .ok contractProgram
        | none => .error <| invalid s!"program '{name}' was not found"
    | none =>
        match programs with
        | #[contractProgram] => .ok contractProgram
        | #[] => .error <| invalid "source contains no program"
        | _ => .error <| invalid "source contains multiple programs; pass --program <qualified-name>"

/-- Immutable locked Lean parser environment for parsing multiple independent
sources without repeatedly importing the frontend module. Create a session on
one control thread before sharing/reusing it; concurrent creation is unsupported. -/
structure ParserSession where
  private environment : Environment

namespace ParserSession

unsafe def create : IO ParserSession :=
  return { environment := ← parserEnvironment }

unsafe def parsePrograms (session : ParserSession) (source fileName : String) :
    IO (Except CompileError (Array Source.Program)) :=
  parseProgramsWithEnvironment session.environment source fileName

unsafe def selectProgram (session : ParserSession) (source fileName : String)
    (requested : Option String) : IO (Except CompileError Source.Program) := do
  return selectParsedProgram (← session.parsePrograms source fileName) requested

end ParserSession

unsafe def parsePrograms (source fileName : String) :
    IO (Except CompileError (Array Source.Program)) := do
  if let .error error := checkSourceSize source then
    return .error error
  let session ← ParserSession.create
  session.parsePrograms source fileName

unsafe def selectProgram (source fileName : String) (requested : Option String) :
    IO (Except CompileError Source.Program) := do
  return selectParsedProgram (← parsePrograms source fileName) requested

end ProofForgeV2.Language.Loader
