import ProofForge.Cli.Check

namespace ProofForge.Tests.CliCheck

def require (cond : Bool) (msg : String) : IO Unit :=
  unless cond do throw <| IO.userError msg

def main : IO UInt32 := do
  let report : ProofForge.Cli.Check.Report := {
    targetId := "evm"
    fixture? := none
    input? := some "Counter.lean"
    format? := none
    diagnostics := #[{
      severity := .info
      code := "check.passed"
      message := "check: ok"
    }]
    validation := #[("targetResolved", "passed"), ("status", "passed")]
  }
  require (!ProofForge.Cli.Check.hasErrors report) "report should not have errors"
  let json := ProofForge.Cli.Check.reportJson report
  require (json.contains "\"kind\": \"proof-forge-check-report\"") "json kind"
  require (json.contains "\"target\": \"evm\"") "json target"
  require (json.contains "\"status\": \"ok\"") "json status"
  require (ProofForge.Cli.Check.renderText report == "check: ok") "text output"
  let failed : ProofForge.Cli.Check.Report := {
    report with
    diagnostics := #[{
      severity := .error
      code := "capability.unsupported"
      message := "target `wasm-near` does not support capability `crosscall.invoke` on operation `contract_source.crosscall` at `Tests/ContractSource/UnsupportedNear.lean:contract_source.use`"
      file? := ProofForge.Cli.Check.parseDiagnosticSource? "target `wasm-near` does not support capability `crosscall.invoke` on operation `contract_source.crosscall` at `Tests/ContractSource/UnsupportedNear.lean:contract_source.use`"
    }]
    validation := #[("capabilities", "failed"), ("status", "failed")]
  }
  require (ProofForge.Cli.Check.hasErrors failed) "failed report should have errors"
  require (ProofForge.Cli.Check.reportJson failed |>.contains "\"status\": \"failed\"") "failed json status"
  match ProofForge.Cli.Check.parseDiagnosticSource?
      "target `wasm-near` does not support capability `crosscall.invoke` on operation `contract_source.crosscall` at `Tests/ContractSource/UnsupportedNear.lean:contract_source.use`" with
  | some loc =>
      require (loc == "Tests/ContractSource/UnsupportedNear.lean:contract_source.use") "source parse"
  | none => throw <| IO.userError "source parse failed"
  IO.println "CliCheck: ok"
  return 0

end ProofForge.Tests.CliCheck

def main : IO UInt32 :=
  ProofForge.Tests.CliCheck.main
