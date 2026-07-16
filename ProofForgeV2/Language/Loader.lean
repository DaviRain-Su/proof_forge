import Lean.Parser.Module
import Lean.Util.Path
import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Language.Loader

open Lean Parser ProofForgeV2

private def invalid (message : String) : CompileError :=
  .invalidProgram message

private def currentNamespace (scopes : Array Name) : Name :=
  scopes.foldl (· ++ ·) .anonymous

private def validateHeader (header : Syntax) : Except CompileError Unit := do
  match header with
  | `(Parser.Module.header| $[module%$_]? $[prelude%$_]? $imports*) =>
      unless imports.size == 1 do
        throw <| invalid "source must import exactly ProofForgeV2"
      match imports[0]! with
      | `(Parser.Module.import| import $name:ident) =>
          unless name.getId == `ProofForgeV2 do
            throw <| invalid s!"unsupported import '{name.getId}'; only ProofForgeV2 is allowed"
      | _ => throw <| invalid "public/meta/import-all forms are not allowed in program source"
  | _ => throw <| invalid "invalid Lean module header"

private def validateProgram (contractProgram : Source.Program) : Except CompileError Unit := do
  if contractProgram.entries.isEmpty then
    throw <| invalid s!"program '{contractProgram.qualifiedName}' must declare at least one entry or view"
  let stateNames := contractProgram.state.map (·.name)
  unless stateNames.toList.eraseDups.length == stateNames.size do
    throw <| invalid s!"program '{contractProgram.qualifiedName}' contains duplicate state declarations"
  let entryNames := contractProgram.entries.map (·.name)
  unless entryNames.toList.eraseDups.length == entryNames.size do
    throw <| invalid s!"program '{contractProgram.qualifiedName}' contains duplicate entry declarations"
  for entrypoint in contractProgram.entries do
    let paramNames := entrypoint.params.map (·.name)
    unless paramNames.toList.eraseDups.length == paramNames.size do
      throw <| invalid s!"entry '{entrypoint.name}' contains duplicate parameters"

private def decodeProgram (namespaceName : Name) (command : Syntax) :
    Except CompileError Source.Program := do
  let contractProgram ← match Language.decodeProgramCommand namespaceName command with
    | .ok contractProgram => .ok contractProgram
    | .error message => .error <| invalid message
  validateProgram contractProgram
  return contractProgram

private def processCommands (commands : Array Syntax) :
    Except CompileError (Array Source.Program) := do
  let mut scopes : Array Name := #[]
  let mut programs : Array Source.Program := #[]
  for command in commands do
    if command.isOfKind ``Parser.Command.eoi then
      continue
    match Language.decodeProgramCommand (currentNamespace scopes) command with
    | .ok _ =>
        let contractProgram ← decodeProgram (currentNamespace scopes) command
        if programs.any (·.qualifiedName == contractProgram.qualifiedName) then
          throw <| invalid s!"duplicate program '{contractProgram.qualifiedName}'"
        programs := programs.push contractProgram
    | .error _ =>
        match command with
        | `(command| open ProofForgeV2.Language) => pure ()
        | `(command| namespace $name:ident) =>
            scopes := scopes.push name.getId
        | `(command| end) =>
            if scopes.isEmpty then
              throw <| invalid "unmatched namespace end"
            scopes := scopes.pop
        | `(command| end $name:ident) =>
            if scopes.isEmpty then
              throw <| invalid "unmatched namespace end"
            let expected := scopes.back!
            unless name.getId == expected do
              throw <| invalid s!"namespace end '{name.getId}' does not match '{expected}'"
            scopes := scopes.pop
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

unsafe def parsePrograms (source fileName : String) : IO (Except CompileError (Array Source.Program)) := do
  if source.toUTF8.size > 16 * 1024 * 1024 then
    return .error <| invalid "source exceeds the 16 MiB limit"
  try
    let environment ← parserEnvironment
    let parsedSyntax ← Parser.testParseModule environment fileName source
    match parsedSyntax.getArgs with
    | #[header, commands] =>
        return do
          validateHeader header
          processCommands commands.getArgs
    | _ => return .error <| invalid "Lean parser returned an invalid module syntax tree"
  catch error =>
    return .error <| invalid s!"Lean parser rejected source: {error}"

unsafe def selectProgram (source fileName : String) (requested : Option String) :
    IO (Except CompileError Source.Program) := do
  let parsed ← parsePrograms source fileName
  return parsed >>= fun programs =>
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

end ProofForgeV2.Language.Loader
