import ProofForge.Backend.Evm.IR
import ProofForge.IR.Contract

namespace ProofForge.Cli.Evm

/-- Render an EVM IR module to Yul through the CLI adapter boundary. -/
def renderYul (module : ProofForge.IR.Module) :
    Except ProofForge.Backend.Evm.IR.LowerError String :=
  ProofForge.Backend.Evm.IR.renderModule module

/-- Render an EVM IR module to Yul with CLI-friendly IO errors. -/
def renderYulIO (module : ProofForge.IR.Module) : IO String := do
  match renderYul module with
  | .ok yul => pure yul
  | .error err => throw <| IO.userError err.render

end ProofForge.Cli.Evm
