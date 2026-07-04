import Init.Notation
import Init.System.IO
import Lean
import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.Fixture
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.Target.Registry

open System Lean

namespace ProofForge.Cli.Check

inductive Severity where
  | error
  | warning
  | info
  deriving BEq, Inhabited, Repr

def severityId : Severity → String
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

structure Diagnostic where
  severity : Severity
  code : String
  message : String
  file? : Option String := none
  line? : Option Nat := none
  column? : Option Nat := none
  deriving Inhabited

structure Report where
  targetId : String
  fixture? : Option String := none
  input? : Option String := none
  format? : Option String := none
  diagnostics : Array Diagnostic := #[]
  validation : Array (String × String) := #[]
  deriving Inhabited

def trimAsciiString (s : String) : String :=
  s.trimAscii.toString

def jsonString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def jsonStringOption : Option String → String
  | some value => jsonString value
  | none => "null"

def jsonNatOption : Option Nat → String
  | some value => toString value
  | none => "null"

def jsonArray (items : Array String) : String :=
  "[" ++ String.intercalate ", " items.toList ++ "]"

def jsonObject (fields : Array (String × String)) : String :=
  "{" ++
    String.intercalate ", " (fields.toList.map fun field =>
      jsonString field.fst ++ ": " ++ field.snd) ++
  "}"

def parseDiagnosticSource? (message : String) : Option String :=
  match message.splitOn " at `" with
  | [_] => none
  | parts =>
      let locPart := parts.getLast!
      match locPart.splitOn "`" with
      | [loc, _] => some loc
      | _ => none

def diagnosticFromTarget (diag : ProofForge.Target.Diagnostic) (code : String) (severity : Severity) : Diagnostic :=
  {
    severity := severity
    code := code
    message := diag.message
    file? := parseDiagnosticSource? diag.message
  }

def diagnosticFromCapabilityError (err : ProofForge.Target.CapabilityError) : Diagnostic :=
  diagnosticFromTarget { message := err.render } "capability.unsupported" .error

def pushDiagnostic (diagnostics : Array Diagnostic) (diag : Diagnostic) : Array Diagnostic :=
  diagnostics.push diag

def pushValidation (validation : Array (String × String)) (key value : String) : Array (String × String) :=
  validation.push (key, value)

def hasErrors (report : Report) : Bool :=
  report.diagnostics.any (·.severity == .error)

def diagnosticJson (diag : Diagnostic) : String :=
  jsonObject #[
    ("severity", jsonString (severityId diag.severity)),
    ("code", jsonString diag.code),
    ("message", jsonString diag.message),
    ("file", jsonStringOption diag.file?),
    ("line", jsonNatOption diag.line?),
    ("column", jsonNatOption diag.column?)
  ]

def reportJson (report : Report) : String :=
  let status := if hasErrors report then "failed" else "ok"
  let validationFields := report.validation.map fun field => (field.fst, jsonString field.snd)
  jsonObject #[
    ("schemaVersion", "1"),
    ("kind", jsonString "proof-forge-check-report"),
    ("command", jsonString "check"),
    ("target", jsonString report.targetId),
    ("fixture", jsonStringOption report.fixture?),
    ("input", jsonStringOption report.input?),
    ("format", jsonStringOption report.format?),
    ("status", jsonString status),
    ("diagnostics", jsonArray (report.diagnostics.map diagnosticJson)),
    ("validation", jsonObject validationFields)
  ]

def severityLabel (severity : Severity) : String :=
  match severity with
  | .error => "error"
  | .warning => "warning"
  | .info => "info"

def fileSuffix (file? : Option String) : String :=
  match file? with
  | some file => s!" ({file})"
  | none => ""

def renderDiagnosticLine (diag : Diagnostic) : String :=
  s!"{severityLabel diag.severity}[{diag.code}]{fileSuffix diag.file?}: {diag.message}"

def renderText (report : Report) : String :=
  let visible := report.diagnostics.filter fun diag => diag.severity != .info
  if visible.isEmpty then
    "check: ok"
  else
    String.intercalate "\n" (visible.toList.map renderDiagnosticLine)

def emitWatFixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  match fixtureId with
  | "counter" => some ProofForge.IR.Examples.Counter.module
  | "error-ref" => some ProofForge.IR.Examples.ErrorRefProbe.module
  | "context" => some ProofForge.IR.Examples.ContextProbe.module
  | "hash" => some ProofForge.IR.Examples.HashProbe.module
  | "map" => some ProofForge.IR.Examples.MapProbe.emitWatModule
  | _ => none

def toolOnPath (tool : String) : IO Bool := do
  try
    let r ← IO.Process.output { cmd := "which", args := #[tool] }
    return r.exitCode == 0
  catch _ =>
    return false

def checkToolchain (targetId : String) (profile : ProofForge.Target.TargetProfile)
    (report : Report) : IO Report := do
  let mut next := report
  let mut toolchainStatus := "passed"
  for tool in profile.requiredTools do
    if !(← toolOnPath tool) then
      toolchainStatus := "warning"
      next := {
        next with
        diagnostics := pushDiagnostic next.diagnostics {
          severity := .warning
          code := "toolchain.missing"
          message := s!"required tool '{tool}' not found on PATH for target '{targetId}'"
        }
      }
  pure { next with validation := pushValidation next.validation "toolchain" toolchainStatus }

def checkWasmNearFixture (fixtureId : String) (format : ProofForge.Cli.Fixture.Format)
    (report : Report) : Report :=
  if format != .wat then
    report
  else
    match emitWatFixtureModule? fixtureId with
    | none =>
        { report with
          diagnostics := pushDiagnostic report.diagnostics {
            severity := .error
            code := "fixture.unmapped"
            message := s!"fixture '{fixtureId}' is not mapped to the wasm-near EmitWat backend"
          }
          validation := pushValidation report.validation "lowering" "failed"
        }
    | some module =>
      match ProofForge.Backend.WasmNear.EmitWat.renderModule module with
      | .ok _ =>
          { report with validation := pushValidation report.validation "lowering" "passed" }
      | .error err =>
          { report with
            diagnostics := pushDiagnostic report.diagnostics {
              severity := .error
              code := "lowering.failed"
              message := err.message
            }
            validation := pushValidation report.validation "lowering" "failed"
          }

def checkFixtureCapabilities (profile : ProofForge.Target.TargetProfile) (fixtureId : String)
    (report : Report) : Report :=
  let caps := ProofForge.Cli.Fixture.capabilitiesFor fixtureId
  match ProofForge.Target.requireCapabilities profile caps with
  | .ok _ =>
      { report with validation := pushValidation report.validation "capabilities" "passed" }
  | .error err =>
      { report with
        diagnostics := pushDiagnostic report.diagnostics (diagnosticFromCapabilityError err)
        validation := pushValidation report.validation "capabilities" "failed"
      }

unsafe def checkContractSource (profile : ProofForge.Target.TargetProfile) (input : FilePath)
    (root? : Option FilePath) (moduleName? : Option Name) (report : Report) : IO Report := do
  let mut next := report
  let spec ←
    try
      let spec ← ProofForge.Cli.ContractLoader.loadSpec input root? moduleName?
      pure (Except.ok spec)
    catch e =>
      pure (Except.error (e.toString))
  match spec with
  | .error msg =>
    return {
      next with
      diagnostics := pushDiagnostic next.diagnostics {
        severity := .error
        code := "contract.load"
        message := msg
        file? := some input.toString
      }
      validation := pushValidation next.validation "contractSource" "failed"
    }
      | .ok spec =>
          match ProofForge.Target.resolveSpec profile spec with
          | .error diag =>
            return {
              next with
              diagnostics := pushDiagnostic next.diagnostics (diagnosticFromTarget diag "capability.unsupported" .error)
              validation := pushValidation next.validation "capabilities" "failed"
            }
          | .ok _ =>
            let resolved := { next with validation := pushValidation next.validation "capabilities" "passed" }
            if profile.id == ProofForge.Target.wasmNear.id then
              match ProofForge.Backend.WasmNear.EmitWat.renderModule spec.module with
              | .ok _ =>
                  return { resolved with validation := pushValidation resolved.validation "lowering" "passed" }
              | .error err =>
                return {
                  resolved with
                  diagnostics := pushDiagnostic resolved.diagnostics {
                    severity := .error
                    code := "lowering.failed"
                    message := err.message
                    file? := some input.toString
                  }
                  validation := pushValidation resolved.validation "lowering" "failed"
                }
            else if profile.id == ProofForge.Target.evm.id then
              return { resolved with validation := pushValidation resolved.validation "contractSource" "passed" }
            else
              return { resolved with validation := pushValidation resolved.validation "contractSource" "passed" }

def checkFixture (profile : ProofForge.Target.TargetProfile) (targetId fixtureId : String)
    (format? : Option String) (report : Report) : Except String Report := do
  if !ProofForge.Cli.Fixture.isValidId fixtureId then
    return {
      report with
      diagnostics := pushDiagnostic report.diagnostics {
        severity := .error
        code := "fixture.unknown"
        message := s!"unknown fixture '{fixtureId}'; known fixtures: {ProofForge.Cli.Fixture.listIds}"
      }
      validation := pushValidation report.validation "fixture" "failed"
    }
  let format ← match format? with
  | some fmt =>
      match ProofForge.Cli.Fixture.parseFormat? fmt with
      | some f => pure f
      | none => throw s!"unknown format '{fmt}'"
  | none =>
      match ProofForge.Cli.Fixture.defaultFormatFor targetId fixtureId with
      | some f => pure f
      | none => throw s!"no default format for --target {targetId} --fixture {fixtureId}"
  if !ProofForge.Cli.Fixture.supportsFormat targetId fixtureId format then
    return {
      report with
      diagnostics := pushDiagnostic report.diagnostics {
        severity := .error
        code := "format.unsupported"
        message := s!"fixture '{fixtureId}' does not support format '{format.id}' for target '{targetId}'"
      }
      validation := pushValidation report.validation "format" "failed"
    }
  let mut next := { report with validation := pushValidation report.validation "fixture" "passed" }
  if targetId == ProofForge.Target.wasmNear.id && format == .wat then
    next := checkWasmNearFixture fixtureId format next
  else
    next := checkFixtureCapabilities profile fixtureId next
  pure next

unsafe def runCheck
    (targetId : String) (fixture? input? format? : Option String)
    (root? : Option FilePath) (moduleName? : Option Name) : IO Report := do
  let mut report : Report := {
    targetId := targetId
    fixture? := fixture?
    input? := input?
    format? := format?
    validation := #[("targetResolved", "passed")]
  }
  let profile ← match ProofForge.Target.find? targetId with
  | some profile => pure profile
  | none =>
      return {
        report with
        diagnostics := pushDiagnostic report.diagnostics {
          severity := .error
          code := "target.unknown"
          message := s!"unknown target '{targetId}'; known targets: {String.intercalate ", " ProofForge.Target.knownIds.toList}"
        }
        validation := #[("targetResolved", "failed")]
      }
  match fixture? with
  | some fixtureId =>
      match checkFixture profile targetId fixtureId format? report with
      | .ok next => report := next
      | .error msg =>
          return {
            report with
            diagnostics := pushDiagnostic report.diagnostics {
              severity := .error
              code := "check.invalid"
              message := msg
            }
            validation := pushValidation report.validation "check" "failed"
          }
  | none =>
      match input? with
      | some inputPath =>
          report ← checkContractSource profile (FilePath.mk inputPath) root? moduleName? report
      | none =>
          report := {
            report with
            diagnostics := pushDiagnostic report.diagnostics {
              severity := .info
              code := "check.target-only"
              message := s!"validated target profile '{targetId}'; pass a fixture id or contract_source .lean input for deeper checks"
            }
            validation := pushValidation report.validation "scope" "target-only"
          }
  report ← checkToolchain targetId profile report
  if !hasErrors report then
    pure {
      report with
      diagnostics := pushDiagnostic report.diagnostics {
        severity := .info
        code := "check.passed"
        message := "check: ok"
      }
      validation := pushValidation report.validation "status" "passed"
    }
  else
    pure { report with validation := pushValidation report.validation "status" "failed" }

unsafe def checkCommand
    (targetId : String) (fixture? input? format? reportFormat? : Option String)
    (root? : Option FilePath) (moduleName? : Option Name) : IO UInt32 := do
  let report ← runCheck targetId fixture? input? format? root? moduleName?
  let jsonMode := reportFormat?.getD "text" == "json"
  if jsonMode then
    IO.println (reportJson report)
  else
    let text := renderText report
    if hasErrors report then
      IO.eprintln text
    else
      IO.println text
  return if hasErrors report then 1 else 0

end ProofForge.Cli.Check
