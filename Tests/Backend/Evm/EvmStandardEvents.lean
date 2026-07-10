import ProofForge.Backend.Evm.Metadata
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Event
import ProofForge.Contract.Stdlib.ERC1155
import ProofForge.Contract.Stdlib.ERC4626
import ProofForge.Contract.Stdlib.ERC721
import ProofForge.Contract.Stdlib.UUPSUpgradeable
import ProofForge.Cli.EvmAbi
import ProofForge.IR.Portability

namespace ProofForge.Tests.Backend.Evm.StandardEvents

open ProofForge.Backend.Evm.Metadata
open ProofForge.Backend.Evm.Plan

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requirePlan (module : ProofForge.IR.Module) : IO ModulePlan := do
  let hydrated ← ProofForge.Cli.hydrateEvmSelectors "cast" module
  match ProofForge.Backend.Evm.Lower.buildFullModulePlan hydrated with
  | .ok plan => pure plan
  | .error err => throw <| IO.userError err.message

def requirePlanErrorContains
    (module : ProofForge.IR.Module) (expected : String) : IO Unit := do
  let hydrated ← ProofForge.Cli.hydrateEvmSelectors "cast" module
  match ProofForge.Backend.Evm.Lower.buildFullModulePlan hydrated with
  | .ok _ => throw <| IO.userError s!"expected event ABI error containing `{expected}`"
  | .error err =>
      require (err.message.contains expected)
        s!"expected event ABI error `{expected}`, got `{err.message}`"

def requireEvent
    (plan : ModulePlan)
    (name signature : String)
    (fieldTypes : Array String) : IO Unit := do
  let some event := plan.events.find? (fun event => event.name == name)
    | throw <| IO.userError s!"missing event `{name}`"
  require (event.signature == signature)
    s!"event `{name}` signature: expected `{signature}`, got `{event.signature}`"
  let descriptor := abiEventDescriptor event
  require (descriptor.fields.map (·.type) == fieldTypes)
    s!"event `{name}` ABI field types do not match `{fieldTypes}`"
  let topicStatements := ProofForge.Backend.Evm.ToYul.eventSignatureTopicStatements event
  let expectedLength := signature.toUTF8.size
  match topicStatements[topicStatements.size - 1]? with
  | some (Lean.Compiler.Yul.Statement.varDecl _
      (some (Lean.Compiler.Yul.Expr.builtin "keccak256" args))) =>
      match args[1]? with
      | some (Lean.Compiler.Yul.Expr.lit literal) =>
          require (literal.value == toString expectedLength)
            s!"event `{name}` topic0 input length must be {expectedLength}"
      | _ => throw <| IO.userError s!"event `{name}` topic0 length is not literal"
  | _ => throw <| IO.userError s!"event `{name}` does not lower topic0 through keccak256"

def main : IO UInt32 := do
  let uups ← requirePlan ProofForge.Contract.Stdlib.UUPSUpgradeable.module
  requireEvent uups "Upgraded" "Upgraded(address)" #["address"]
  require (!ProofForge.Contract.Stdlib.UUPSUpgradeable.module.eventAbiWords.isEmpty)
    "UUPS module must retain event ABI declarations from its mixin"

  let erc721 ← requirePlan ProofForge.Contract.Stdlib.ERC721.module
  requireEvent erc721 "Transfer" "Transfer(address,address,uint256)"
    #["address", "address", "uint256"]

  let erc1155 ← requirePlan ProofForge.Contract.Stdlib.ERC1155.module
  requireEvent erc1155 "ApprovalForAll" "ApprovalForAll(address,address,bool)"
    #["address", "address", "bool"]
  requireEvent erc1155 "TransferSingle"
    "TransferSingle(address,address,address,uint256,uint256)"
    #["address", "address", "address", "uint256", "uint256"]

  let erc4626 ← requirePlan ProofForge.Contract.Stdlib.ERC4626.module
  requireEvent erc4626 "Deposit" "Deposit(address,address,uint256,uint256)"
    #["address", "address", "uint256", "uint256"]
  requireEvent erc4626 "Withdraw"
    "Withdraw(address,address,address,uint256,uint256)"
    #["address", "address", "address", "uint256", "uint256"]

  let uupsModule := ProofForge.Contract.Stdlib.UUPSUpgradeable.module
  let some implementationOverride := uupsModule.eventAbiWords[0]?
    | throw <| IO.userError "missing UUPS implementation event ABI override"
  requirePlanErrorContains
    { uupsModule with
      eventAbiWords := uupsModule.eventAbiWords.push implementationOverride }
    "duplicate ABI overrides"
  requirePlanErrorContains
    { uupsModule with
      eventAbiWords := #[{ implementationOverride with eventName := "MissingEvent" }] }
    "unknown event"
  requirePlanErrorContains
    { uupsModule with
      eventAbiWords := #[{ implementationOverride with fieldName := "missingField" }] }
    "unknown field"
  requirePlanErrorContains
    { uupsModule with
      eventAbiWords := #[{ implementationOverride with abiWord := "bytes32" }] }
    "incompatible EVM ABI override"

  let portability := ProofForge.IR.Portability.classifyModule uupsModule
  require
    (portability.any fun finding => finding.path == "module.eventAbiWords")
    "event ABI overrides must be reported as EVM target metadata"

  IO.println "evm-standard-events: ok"
  pure 0

end ProofForge.Tests.Backend.Evm.StandardEvents

def main : IO UInt32 :=
  ProofForge.Tests.Backend.Evm.StandardEvents.main
