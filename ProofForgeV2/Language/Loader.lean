import Lean.Parser.Module
import Lean.Util.Path
import Std.Data.HashSet
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Syntax
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanJoinV1

namespace ProofForgeV2.Language.Loader

open Lean Parser ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.SpanJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def renderSourceQualified (name : SourceQualifiedNameV1) : String :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Name.str acc component.raw) .anonymous |>.toString

/-- Internal Loader error shape.  `parserBoundary` and `duplicateProgram` carry an
optional `SourceByteSpanV1` when a trustworthy source position is available;
decoder-internal failures carry no span. -/
private inductive LoaderError where
  | parserBoundary (message : String) (span? : Option SourceByteSpanV1)
  | invalidProgram (message : String)
  | resourceBound (message : String)
  | duplicateProgram (name : SourceQualifiedNameV1) (span? : Option SourceByteSpanV1)
  deriving Inhabited

private def toCompileError (err : LoaderError) : CompileError :=
  match err with
  | .parserBoundary message _ =>
      .invalidProgram s!"Lean parser rejected source: {message}"
  | .invalidProgram message => .invalidProgram message
  | .resourceBound message => .resourceBound message
  | .duplicateProgram name _ =>
      .invalidProgram s!"duplicate program '{renderSourceQualified name}'"

private def spanFromLineCol? (source : String) (line col : Nat) :
    Option SourceByteSpanV1 := do
  let fmap := FileMap.ofString source
  let pos := fmap.ofPosition ⟨line, col⟩
  let startByte := pos.byteIdx
  unless startByte < UInt64.size do
    none
  pure {
    startByte := UInt64.ofNat startByte,
    endByte := UInt64.ofNat startByte
  }

private def messageSpan? (source : String) (msg : Message) :
    Option SourceByteSpanV1 := do
  let startSpan ← spanFromLineCol? source msg.pos.line msg.pos.column
  let endByte := match msg.endPos with
    | some endPos =>
      match spanFromLineCol? source endPos.line endPos.column with
      | some endSpan => if endSpan.endByte ≥ startSpan.startByte then endSpan.endByte else startSpan.startByte
      | none => startSpan.startByte
    | none => startSpan.startByte
  pure { startByte := startSpan.startByte, endByte := endByte }

private def parserBoundaryFromMessage (source : String) (msg : Message) :
    LoaderError :=
  .parserBoundary "failed to parse file" (messageSpan? source msg)

private def commandSpan? (source : String) (stx : Syntax) : Option SourceByteSpanV1 :=
  match originalSyntaxByteSpanV1 source stx with
  | .ok span => some span
  | .error _ => none

/-- Build a diagnostic primary origin from a trustworthy source span.
    Pre-node parser/duplicate locations use explicit `nodeId = none` (B7a;
    zero-sentinel retired). Decoder-internal/no-span remains primary `none`. -/
private def primaryFromSpan? (fileName : String) (span? : Option SourceByteSpanV1) :
    Option DiagnosticOriginV1 :=
  match span? with
  | none => none
  | some span =>
    match parseProjectRelativePath fileName with
    | .error _ => none
    | .ok sourcePath => some {
        sourcePath := sourcePath,
        startByte := span.startByte,
        endByte := span.endByte,
        nodeId := none
      }

private def toDiagnosticV1 (fileName : String) (err : LoaderError) : DiagnosticV1 :=
  match err with
  | .parserBoundary message span? =>
      DiagnosticV1.make .sourceInvalid
        s!"Lean parser rejected source: {message}"
        (primary := primaryFromSpan? fileName span?)
  | .invalidProgram message =>
      DiagnosticV1.make .sourceInvalid message
  | .resourceBound message =>
      DiagnosticV1.make .resourceBound message
  | .duplicateProgram name span? =>
      DiagnosticV1.make .sourceInvalid
        s!"duplicate program '{renderSourceQualified name}'"
        (primary := primaryFromSpan? fileName span?)

/-- Public-safe PF-INTERNAL bundle for SpanJoin/OriginJoin impossibilities.
    Stable token only — no `repr`, hashes, absolute paths, or source text. -/
private def internalJoinBundle (stable : String) : DiagnosticBundleV1 :=
  mkFailureBundleV1 #[
    DiagnosticV1.make .internal "source origin materialization failed"
      (actual := some (PfJson.string stable))]

private def loaderErrorBundle (logicalSourcePath : String) (err : LoaderError) :
    DiagnosticBundleV1 :=
  mkFailureBundleV1 #[toDiagnosticV1 logicalSourcePath err]

/-- Decoder errors from `Language.decodeProgramCommandV1Checked` are only
`invalidProgram` or `resourceBound` in the ProgramV1 product slice.  All other
`CompileError` variants are intentionally collapsed to `invalidProgram` because
they cannot originate from source decoding in this Loader path. -/
private def compileErrorToLoaderError (err : CompileError) : LoaderError :=
  match err with
  | .resourceBound msg => .resourceBound msg
  | .invalidProgram msg => .invalidProgram msg
  | _ => .invalidProgram err.message

private def invalidL (message : String) : LoaderError :=
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

private def validateHeader (header : Syntax) : Except LoaderError Unit := do
  match header with
  | `(Parser.Module.header| $[module%$_]? $[prelude%$_]? $imports*) =>
      unless imports.size == 1 do
        throw <| invalidL "source must import exactly ProofForgeV2"
      match imports[0]! with
      | `(Parser.Module.import| import $name:ident) =>
          unless namesEqual name.getId `ProofForgeV2 do
            throw <| invalidL "unsupported import; only ProofForgeV2 is allowed"
      | _ => throw <| invalidL "public/meta/import-all forms are not allowed in program source"
  | _ => throw <| invalidL "invalid Lean module header"

private def sourceQualifiedKey (name : SourceQualifiedNameV1) : String :=
  String.intercalate "\u0000"
    ((NonEmptyArray.toArray name.components).map (·.raw) |>.toList)

private def sourceQualifiedNameV1ToLeanName (name : SourceQualifiedNameV1) : Name :=
  (NonEmptyArray.toArray name.components).foldl
    (fun acc component => Name.str acc component.raw) .anonymous

private def parseSourceQualifiedInput (environment : Environment)
    (label value : String) : Except LoaderError SourceQualifiedNameV1 := do
  let parsedIdent ← match Parser.runParserCategory environment `term value with
    | .ok parsedIdent => pure parsedIdent
    | .error _ => throw <| invalidL s!"{label} must be one exact Lean identifier"
  unless parsedIdent.isIdent do
    throw <| invalidL s!"{label} must be one exact Lean identifier"
  match sourceQualifiedNameV1FromLeanName parsedIdent.getId with
  | .ok name => pure name
  | .error message => throw <| invalidL s!"invalid {label}: {message}"

/-- Whether the command walker collects same-file adjacent theorem inventory.

    * `legacy` — historical portable surface: theorems are outside the DSL
      (proof refs without adjacent theorems keep working).
    * `inventory` — after each program, consume exact proof-order theorems
      `theorem QN : Program.Proof.Inv := by …`; any proof requires full
      invariant/proof/theorem bijection; no proof forbids adjacent theorems. -/
private inductive TheoremCollectMode where
  | legacy
  | inventory
  deriving Inhabited, BEq

private def theoremInventoryError (e : TheoremInventoryErrorV1) : LoaderError :=
  invalidL (renderTheoremInventoryErrorV1 e)

/- ProgramV1 product command walker, retaining the original command syntax for span joining.
   When `mode = .inventory`, also collects per-program adjacent theorem inventories. -/
private def processCommandsV1WithSyntaxAndTheorems (source : String)
    (moduleName : SourceQualifiedNameV1)
    (commands : Array Syntax)
    (mode : TheoremCollectMode) :
    Except LoaderError (Array (ValidatedSourceV1 × Syntax × TheoremInventoryV1)) := do
  let mut scopes : Array NamespaceFrame := #[]
  let mut namespaceState : NamespaceState := .bounded .anonymous 0
  let mut programs : Array (ValidatedSourceV1 × Syntax × TheoremInventoryV1) := #[]
  let mut programKeys : Std.HashSet String := {}
  let mut idx : Nat := 0
  while idx < commands.size do
    let command := commands[idx]!
    idx := idx + 1
    if command.isOfKind ``Parser.Command.eoi then
      continue
    match command with
    | `(program $_name:ident where $_items:pfItem*) =>
        let moduleNameLean := sourceQualifiedNameV1ToLeanName moduleName
        let currentNamespace := match namespaceState with
          | .bounded nsName _ =>
              Language.ProgramNamespace.bounded (nsName.replacePrefix moduleNameLean .anonymous)
          | .overLimit _ _ => Language.ProgramNamespace.overLimit
        let validated ←
          match Language.decodeProgramCommandV1Checked moduleName currentNamespace command with
          | .ok value => pure value
          | .error e => throw <| compileErrorToLoaderError e
        let key := sourceQualifiedKey validated.programIdentity
        let (alreadyPresent, updatedKeys) := programKeys.containsThenInsert key
        if alreadyPresent then
          let span? := commandSpan? source command
          throw <| .duplicateProgram validated.programIdentity span?
        programKeys := updatedKeys
        let inventory ← match mode with
          | .legacy => pure emptyTheoremInventoryV1
          | .inventory => do
              let expected ←
                match expectedTheoremsFromProgramV1 validated.program.name.raw validated with
                | .ok value => pure value
                | .error e => throw <| theoremInventoryError e
              -- Remaining commands after this program (excluding already-advanced idx).
              let remaining := commands.extract idx commands.size
              match consumeAdjacentTheoremsV1 expected remaining with
              | .error e => throw <| theoremInventoryError e
              | .ok (bindings, tail) =>
                  -- Advance idx past consumed theorems.
                  idx := commands.size - tail.size
                  pure (mintTheoremInventoryV1 bindings)
        programs := programs.push (validated, command, inventory)
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
          throw <| invalidL "unmatched namespace end"
        let frame := scopes.back!
        scopes := scopes.pop
        namespaceState := frame.previous
    | `(command| end $name:ident) =>
        if scopes.isEmpty then
          throw <| invalidL "unmatched namespace end"
        let frame := scopes.back!
        unless namesEqual name.getId frame.declared do
          throw <| invalidL "namespace end does not match the active namespace"
        scopes := scopes.pop
        namespaceState := frame.previous
    | _ =>
        throw <| invalidL "Lean command is outside the portable program DSL"
  unless scopes.isEmpty do
    throw <| invalidL "unterminated namespace"
  pure programs

private def processCommandsV1WithSyntax (source : String)
    (moduleName : SourceQualifiedNameV1)
    (commands : Array Syntax) :
    Except LoaderError (Array (ValidatedSourceV1 × Syntax)) := do
  let units ← processCommandsV1WithSyntaxAndTheorems source moduleName commands .legacy
  pure (units.map fun (src, stx, _) => (src, stx))

private def processCommandsV1 (source : String)
    (moduleName : SourceQualifiedNameV1)
    (commands : Array Syntax) : Except LoaderError (Array ValidatedSourceV1) := do
  let programs ← processCommandsV1WithSyntax source moduleName commands
  pure (programs.map Prod.fst)

private unsafe def parserEnvironment : IO Environment := do
  enableInitializersExecution
  initSearchPath (← findSysroot "lean")
  importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

private def checkSourceSize (source : String) : Except LoaderError Unit :=
  if source.toUTF8.size > 16 * 1024 * 1024 then
    -- SPEC-DIAG-001 assigns the 16 MiB source cap to `PF-SRC-INVALID`; the typed
    -- diagnostics API must stay byte-identical with the legacy loader here.
    .error <| invalidL "source exceeds the 16 MiB limit"
  else
    .ok ()

/-- Parse the Lean module while preserving the first error position.  This mirrors
`Lean.Parser.testParseModule` but returns the first `Message` instead of printing
it and throwing a generic string, so the Loader can construct a `SourceOrigin`. -/
private def firstErrorMessage? (messages : MessageLog) : Option Message :=
  (messages.toArray.filter (·.severity matches .error))[0]?

private unsafe def parseModuleV1 (environment : Environment)
    (source fileName : String) :
    IO (Except LoaderError (Syntax × Array Syntax)) := do
  try
    let inputCtx := mkInputContext source fileName
    let (header, parserState, messages) ← parseHeader inputCtx
    if let some msg := firstErrorMessage? messages then
      return .error <| parserBoundaryFromMessage source msg
    let rec loop (parserState : ModuleParserState) (messages : MessageLog)
        (commands : Array Syntax) : IO (Except LoaderError (Array Syntax)) := do
      let (cmd, parserState, messages) :=
        parseCommand inputCtx { env := environment, options := {} } parserState messages
      if isTerminalCommand cmd then
        if let some msg := firstErrorMessage? messages then
          return .error <| parserBoundaryFromMessage source msg
        else
          return .ok (commands.push cmd)
      else
        loop parserState messages (commands.push cmd)
    match ← loop parserState messages #[] with
    | .error e => return .error e
    | .ok commands =>
        let moduleStx := mkNode `Lean.Parser.Module.module #[header, mkListNode commands]
        return .ok (moduleStx, commands)
  catch e =>
    return .error <| .parserBoundary e.toString none

private unsafe def parseProgramsV1WithEnvironment' (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except LoaderError (Array ValidatedSourceV1)) := do
  if let .error error := checkSourceSize source then
    return .error error
  let moduleName ← match parseSourceQualifiedInput environment "--module" moduleInput with
    | .ok moduleName => pure moduleName
    | .error error => return .error error
  match ← parseModuleV1 environment source fileName with
  | .error error => return .error error
  | .ok (moduleStx, commands) =>
      match moduleStx.getArgs with
      | #[header, _] =>
          return do
            validateHeader header
            processCommandsV1 source moduleName commands
      | _ => return .error <| invalidL "Lean parser returned an invalid module syntax tree"

private unsafe def parseProgramsV1WithEnvironment (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) := do
  let result ← parseProgramsV1WithEnvironment' environment source fileName moduleInput
  pure (result.mapError toCompileError)

private def selectParsedProgramV1 (environment : Environment)
    (parsed : Except LoaderError (Array ValidatedSourceV1))
    (requested : Option String) : Except LoaderError ValidatedSourceV1 := do
  let programs ← parsed
  match requested with
  | some input =>
      let requestedName ← parseSourceQualifiedInput environment "--program" input
      match programs.find? (·.programIdentity == requestedName) with
      | some source => pure source
      | none => throw <| invalidL s!"program '{input}' was not found"
  | none =>
      match programs with
      | #[source] => pure source
      | #[] => throw <| invalidL "source contains no program"
      | _ => throw <| invalidL (
          "source contains multiple programs; pass --program <qualified-name>")

private def selectParsedProgramV1WithSyntax (environment : Environment)
    (parsed : Except LoaderError (Array (ValidatedSourceV1 × Syntax)))
    (requested : Option String) : Except LoaderError (ValidatedSourceV1 × Syntax) := do
  let programs ← parsed
  match requested with
  | some input =>
      let requestedName ← parseSourceQualifiedInput environment "--program" input
      match programs.find? (·.1.programIdentity == requestedName) with
      | some source => pure source
      | none => throw <| invalidL s!"program '{input}' was not found"
  | none =>
      match programs with
      | #[source] => pure source
      | #[] => throw <| invalidL "source contains no program"
      | _ => throw <| invalidL (
          "source contains multiple programs; pass --program <qualified-name>")

private unsafe def parseProgramsV1WithEnvironmentWithSyntax' (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except LoaderError (Array (ValidatedSourceV1 × Syntax))) := do
  if let .error error := checkSourceSize source then
    return .error error
  let moduleName ← match parseSourceQualifiedInput environment "--module" moduleInput with
    | .ok moduleName => pure moduleName
    | .error error => return .error error
  match ← parseModuleV1 environment source fileName with
  | .error error => return .error error
  | .ok (moduleStx, commands) =>
      match moduleStx.getArgs with
      | #[header, _] =>
          return do
            validateHeader header
            processCommandsV1WithSyntax source moduleName commands
      | _ => return .error <| invalidL "Lean parser returned an invalid module syntax tree"

private unsafe def parseProgramsV1WithEnvironmentWithSyntax (environment : Environment)
    (source fileName moduleInput : String) :
    IO (Except CompileError (Array (ValidatedSourceV1 × Syntax))) := do
  let result ← parseProgramsV1WithEnvironmentWithSyntax' environment source fileName moduleInput
  pure (result.mapError toCompileError)

private unsafe def parseProgramsV1WithEnvironmentWithTheorems'
    (environment : Environment) (source fileName moduleInput : String) :
    IO (Except LoaderError (Array (ValidatedSourceV1 × Syntax × TheoremInventoryV1))) := do
  if let .error error := checkSourceSize source then
    return .error error
  let moduleName ← match parseSourceQualifiedInput environment "--module" moduleInput with
    | .ok moduleName => pure moduleName
    | .error error => return .error error
  match ← parseModuleV1 environment source fileName with
  | .error error => return .error error
  | .ok (moduleStx, commands) =>
      match moduleStx.getArgs with
      | #[header, _] =>
          return do
            validateHeader header
            processCommandsV1WithSyntaxAndTheorems source moduleName commands .inventory
      | _ => return .error <| invalidL "Lean parser returned an invalid module syntax tree"

private def selectParsedProgramV1WithTheorems (environment : Environment)
    (parsed : Except LoaderError (Array (ValidatedSourceV1 × Syntax × TheoremInventoryV1)))
    (requested : Option String) :
    Except LoaderError (ValidatedSourceV1 × Syntax × TheoremInventoryV1) := do
  let programs ← parsed
  match requested with
  | some input =>
      let requestedName ← parseSourceQualifiedInput environment "--program" input
      match programs.find? (fun (src, _, _) => src.programIdentity == requestedName) with
      | some unit => pure unit
      | none => throw <| invalidL s!"program '{input}' was not found"
  | none =>
      match programs with
      | #[unit] => pure unit
      | #[] => throw <| invalidL "source contains no program"
      | _ => throw <| invalidL (
          "source contains multiple programs; pass --program <qualified-name>")

/-- Immutable locked Lean parser environment for parsing multiple independent
sources without repeatedly importing the frontend module. Create a session on
one control thread before sharing/reusing it; concurrent creation is unsupported. -/
structure ParserSession where
  private environment : Environment

namespace ParserSession

/-- Read-only access to the session's parser environment, so callers can reuse
    the same immutable environment (e.g. parse a module command for span-join
    tests) without constructing a second full `ProofForgeV2.Language.Syntax`
    environment. -/
def sessionEnvironment (session : ParserSession) : Environment :=
  session.environment

unsafe def create : IO ParserSession :=
  return { environment := ← parserEnvironment }

unsafe def parseProgramsV1 (session : ParserSession) (source fileName moduleName : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) :=
  parseProgramsV1WithEnvironment session.environment source fileName moduleName

unsafe def selectProgramV1 (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError ValidatedSourceV1) := do
  let result ← parseProgramsV1WithEnvironment' session.environment source fileName moduleName
  return (selectParsedProgramV1 session.environment result requested).mapError toCompileError

unsafe def selectProgramV1WithSpans (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))) := do
  let parsed ← parseProgramsV1WithEnvironmentWithSyntax session.environment source fileName moduleName
  match parsed with
  | .error error => return .error error
  | .ok programs =>
      match selectParsedProgramV1WithSyntax session.environment (.ok programs) requested with
      | .error error => return .error <| toCompileError error
      | .ok (src, commandStx) =>
          match spanJoinV1 source commandStx src.program with
          | .ok spans => return .ok (src, spans)
          | .error message => return .error <| .invalidProgram message

/-- Additive Source origin inventory: single decoder → SpanJoin → OriginJoin.
    Invalid caller project-relative path → `invalidProgram` / PF-SRC-INVALID.
    Same-snapshot join/inventory failure (impossible for a successful WithSpans
    pair) → `invalidProgram` with an internal fail-closed message (CompileError
    has no dedicated internal variant; code stays PF-SRC-INVALID wire via
    invalidProgram, message classifies the fault). No parser/decoder
    duplication, fallback, caller-supplied spans, or trusted inventory.

    Non-product library surface. Product paths must use `selectProgramV1Product`. -/
unsafe def selectProgramV1WithOrigins (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × OriginInventoryV1)) := do
  match ← session.selectProgramV1WithSpans source fileName moduleName requested with
  | .error error => return .error error
  | .ok (src, spans) =>
      match parseProjectRelativePath fileName with
      | .error detail =>
          return .error <| .invalidProgram detail
      | .ok sourcePath =>
          match joinOriginsV1 src sourcePath spans with
          | .ok inv => return .ok (src, inv)
          | .error e =>
              return .error <| .invalidProgram
                s!"internal origin inventory join failed: {repr e}"

/-- Single syntax-preserving parse/select/SpanJoin snapshot shared by the
    B8b product Loader and the B10 standalone frontend worker. This helper is
    the only structured-bundle path to `(ValidatedSourceV1 × path/span table)`;
    callers may join origins or transport preorder spans, but never reparse. -/
private unsafe def selectProgramV1ProductSnapshot
    (session : ParserSession)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1
      (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))) := do
  let parsed ←
    parseProgramsV1WithEnvironmentWithSyntax' session.environment
      source logicalSourcePath moduleName
  match parsed with
  | .error err =>
      pure (.error (loaderErrorBundle logicalSourcePath err))
  | .ok programs =>
      match selectParsedProgramV1WithSyntax session.environment (.ok programs) requested with
      | .error err =>
          pure (.error (loaderErrorBundle logicalSourcePath err))
      | .ok (src, commandStx) =>
          match spanJoinV1 source commandStx src.program with
          | .error _ => pure (.error (internalJoinBundle "spanJoin"))
          | .ok spans => pure (.ok (src, spans))

/-- Additive B10 worker payload entry.

    Returns complete Loader diagnostics or canonical-preorder spans from the
    same immutable parser snapshot. Paths are intentionally stripped only after
    SpanJoin; the worker protocol reconstructs them from NodeAssignmentV1. This
    API performs no file I/O, worker orchestration, or OriginInventory join. -/
unsafe def selectProgramV1FrontendPayload (session : ParserSession)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1 (ValidatedSourceV1 × Array SourceByteSpanV1)) := do
  match ← selectProgramV1ProductSnapshot session source logicalSourcePath moduleName requested with
  | .error bundle => pure (.error bundle)
  | .ok (src, pathSpans) => pure (.ok (src, pathSpans.map (·.2)))

/-- Sole product Loader entry (B8b), sharing the B10 snapshot helper.

    Parses source **exactly once**, selects from the same parser snapshot, then
    runs SpanJoin and OriginJoin. `logicalSourcePath` is project-relative.
    SpanJoin/OriginJoin impossibilities fail closed as public-safe PF-INTERNAL.
    No raw diagnostic-array carrier, fallback, or reparse. -/
unsafe def selectProgramV1Product (session : ParserSession)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1 (ValidatedSourceV1 × OriginInventoryV1)) := do
  match ← selectProgramV1ProductSnapshot session source logicalSourcePath moduleName requested with
  | .error bundle => pure (.error bundle)
  | .ok (src, spans) =>
      match parseProjectRelativePath logicalSourcePath with
      | .error detail =>
          pure (.error (mkFailureBundleV1 #[
            DiagnosticV1.make .sourceInvalid detail]))
      | .ok sourcePath =>
          match joinOriginsV1 src sourcePath spans with
          | .ok inv => pure (.ok (src, inv))
          | .error _ => pure (.error (internalJoinBundle "originJoin"))

/-- Additive inventory-aware multi-program parse.

    Single parse; after each program consumes exact proof-order adjacent theorems
    when any proof exists. Returns private-ctor `ProgramTheoremSnapshotV1`.
    ProgramV1 canonical bytes / sourceHash / identity are unchanged from legacy
    parse of the same program command. Non-product library surface. -/
unsafe def parseProgramsV1WithTheoremInventory (session : ParserSession)
    (source fileName moduleName : String) :
    IO (Except CompileError ProgramTheoremSnapshotV1) := do
  match ← parseProgramsV1WithEnvironmentWithTheorems'
      session.environment source fileName moduleName with
  | .error error => return .error (toCompileError error)
  | .ok units =>
      let pairs := units.map fun (src, _, inv) => (src, inv)
      return .ok (mintProgramTheoremSnapshotV1 pairs)

/-- Additive inventory-aware select.

    Same single-parse inventory rules as `parseProgramsV1WithTheoremInventory`,
    then select by optional `--program`. Returns validated source plus opaque
    theorem inventory for the selected program. -/
unsafe def selectProgramV1WithTheoremInventory (session : ParserSession)
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × TheoremInventoryV1)) := do
  let parsed ← parseProgramsV1WithEnvironmentWithTheorems'
    session.environment source fileName moduleName
  match selectParsedProgramV1WithTheorems session.environment parsed requested with
  | .error error => return .error (toCompileError error)
  | .ok (src, _, inv) => return .ok (src, inv)

/-- Additive product-shaped inventory entry: product origin join + theorem inventory.

    Parses once under inventory mode, selects, SpanJoins/OriginJoins the program
    command only (theorem commands do not enter ProgramV1 span/origin tables),
    and returns `(source × origins × theorems)`. Non-product until CLI cutover. -/
unsafe def selectProgramV1ProductWithTheoremInventory (session : ParserSession)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1
      (ValidatedSourceV1 × OriginInventoryV1 × TheoremInventoryV1)) := do
  let parsed ← parseProgramsV1WithEnvironmentWithTheorems'
    session.environment source logicalSourcePath moduleName
  match selectParsedProgramV1WithTheorems session.environment parsed requested with
  | .error err => pure (.error (loaderErrorBundle logicalSourcePath err))
  | .ok (src, commandStx, theorems) =>
      match spanJoinV1 source commandStx src.program with
      | .error _ => pure (.error (internalJoinBundle "spanJoin"))
      | .ok spans =>
          match parseProjectRelativePath logicalSourcePath with
          | .error detail =>
              pure (.error (mkFailureBundleV1 #[
                DiagnosticV1.make .sourceInvalid detail]))
          | .ok sourcePath =>
              match joinOriginsV1 src sourcePath spans with
              | .ok origins => pure (.ok (src, origins, theorems))
              | .error _ => pure (.error (internalJoinBundle "originJoin"))

end ParserSession

/-- Product parser/elaboration session whose package module root is derived from
    the running executable layout, never from `LEAN_PATH`. The constructor is
    private so callers cannot relabel an ambient development `ParserSession` as
    product authority. The trusted Lean sysroot remains part of the compiler
    runtime TCB; user/project `.olean` search entries are excluded. -/
structure ProductParserSessionV1 where
  private mk ::
  private session_ : ParserSession

namespace ProductParserSessionV1

/-- Locked module imported for both ProgramV1 inventory parsing and adjacent
    theorem elaboration. It contains the `program` elaborator plus the exact
    proof ABI, without relying on a caller-resolved umbrella `.olean`. -/
def lockedFrontendModuleV1 : Name :=
  `ProofForgeV2.Language.ProgramElaborationV1

private def packageOleanRootV1 : IO System.FilePath := do
  let appDir ← IO.appDir
  let buildDir ← match appDir.parent with
    | some value => pure value
    | none => throw (IO.userError
        "PF-INTERNAL: product executable has no build-root parent")
  let root := buildDir / "lib" / "lean"
  let moduleFile := root / "ProofForgeV2" / "Language" /
    "ProgramElaborationV1.olean"
  unless ← moduleFile.pathExists do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof frontend module is missing")
  let rootMetadata ← root.symlinkMetadata
  unless rootMetadata.type == .dir do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof module root is not a directory")
  let realRoot ← IO.FS.realPath root
  unless realRoot == root do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof module root must not traverse a symlink")
  pure root

/-- Read-only ParserSession projection. The opaque product wrapper remains the
    authority passed to the certifier. -/
def parserSession (value : ProductParserSessionV1) : ParserSession :=
  value.session_

/-- Exact immutable Environment shared by product Loader parsing and proof
    command elaboration. -/
def sessionEnvironment (value : ProductParserSessionV1) : Environment :=
  ParserSession.sessionEnvironment value.session_

/-- Mint the product session from an executable-sibling package module root and
    the trusted Lean runtime sysroot. This writes the process-global search path
    exactly once on the caller's control thread and deliberately ignores
    `LEAN_PATH`; concurrent session creation remains unsupported. -/
unsafe def create : IO ProductParserSessionV1 := do
  let packageRoot ← packageOleanRootV1
  let leanSysroot ← findSysroot "lean"
  let builtinRoots ← getBuiltinSearchPath leanSysroot
  searchPathRef.set ([packageRoot] ++ builtinRoots)
  enableInitializersExecution
  let environment ← importModules #[{ module := lockedFrontendModuleV1 }] {} 0
    (loadExts := true)
  pure ⟨{ environment }⟩

unsafe def selectProgramV1Product
    (session : ProductParserSessionV1)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1 (ValidatedSourceV1 × OriginInventoryV1)) :=
  session.session_.selectProgramV1Product
    source logicalSourcePath moduleName requested

unsafe def selectProgramV1ProductWithTheoremInventory
    (session : ProductParserSessionV1)
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1
      (ValidatedSourceV1 × OriginInventoryV1 × TheoremInventoryV1)) :=
  session.session_.selectProgramV1ProductWithTheoremInventory
    source logicalSourcePath moduleName requested

end ProductParserSessionV1

unsafe def parseProgramsV1 (source fileName moduleName : String) :
    IO (Except CompileError (Array ValidatedSourceV1)) := do
  if let .error error := checkSourceSize source then
    return .error <| toCompileError error
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

unsafe def selectProgramV1WithOrigins (source fileName moduleName : String)
    (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × OriginInventoryV1)) := do
  let session ← ParserSession.create
  session.selectProgramV1WithOrigins source fileName moduleName requested

/-- Top-level B10 worker payload entry; see the ParserSession method. -/
unsafe def selectProgramV1FrontendPayload
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1 (ValidatedSourceV1 × Array SourceByteSpanV1)) := do
  let session ← ParserSession.create
  session.selectProgramV1FrontendPayload source logicalSourcePath moduleName requested

/-- Top-level product Loader entry; uses the package-owned product parser
    authority and excludes ambient `LEAN_PATH`. -/
unsafe def selectProgramV1Product (source logicalSourcePath moduleName : String)
    (requested : Option String) :
    IO (DiagnosticResultV1 (ValidatedSourceV1 × OriginInventoryV1)) := do
  let session ← ProductParserSessionV1.create
  session.selectProgramV1Product source logicalSourcePath moduleName requested

/-- Top-level additive inventory parse; see ParserSession method. -/
unsafe def parseProgramsV1WithTheoremInventory
    (source fileName moduleName : String) :
    IO (Except CompileError ProgramTheoremSnapshotV1) := do
  let session ← ParserSession.create
  session.parseProgramsV1WithTheoremInventory source fileName moduleName

/-- Top-level additive inventory select; see ParserSession method. -/
unsafe def selectProgramV1WithTheoremInventory
    (source fileName moduleName : String) (requested : Option String) :
    IO (Except CompileError (ValidatedSourceV1 × TheoremInventoryV1)) := do
  let session ← ParserSession.create
  session.selectProgramV1WithTheoremInventory source fileName moduleName requested

/-- Top-level product inventory entry; uses the package-owned product parser
    authority and excludes ambient `LEAN_PATH`. Callers that also certify an
    adjacent theorem must retain an explicitly created `ProductParserSessionV1`
    so parsing and elaboration share the same immutable Environment. -/
unsafe def selectProgramV1ProductWithTheoremInventory
    (source logicalSourcePath moduleName : String) (requested : Option String) :
    IO (DiagnosticResultV1
      (ValidatedSourceV1 × OriginInventoryV1 × TheoremInventoryV1)) := do
  let session ← ProductParserSessionV1.create
  session.selectProgramV1ProductWithTheoremInventory
    source logicalSourcePath moduleName requested

end ProofForgeV2.Language.Loader
