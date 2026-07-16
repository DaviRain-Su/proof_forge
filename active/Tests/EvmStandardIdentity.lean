import ProofForge.Cli.EvmAbi
import ProofForge.Contract.Stdlib.AccessControl
import ProofForge.Contract.Stdlib.ERC165
import ProofForge.Contract.Stdlib.Ownable

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireSignature (module : Module) (name expected : String) : IO Unit := do
  let some entrypoint := module.entrypoints.find? (·.name == name)
    | throw <| IO.userError s!"missing entrypoint `{name}`"
  let actual ← match ProofForge.Cli.entrypointSoliditySignature module entrypoint with
    | .ok signature => pure signature
    | .error error => throw <| IO.userError error
  require (actual == expected) s!"{name} signature `{actual}`, expected `{expected}`"

partial def statementEmits (eventName : String) : Statement → Bool
  | .effect (.eventEmit name _) | .effect (.eventEmitIndexed name _ _) => name == eventName
  | .ifElse _ thenBody elseBody =>
      thenBody.any (statementEmits eventName) || elseBody.any (statementEmits eventName)
  | .boundedFor _ _ _ body | .whileLoop _ body => body.any (statementEmits eventName)
  | _ => false

def moduleEmits (module : Module) (eventName : String) : Bool :=
  module.entrypoints.any fun entrypoint => entrypoint.body.any (statementEmits eventName)

def main : IO Unit := do
  let erc165 := ProofForge.Contract.Stdlib.ERC165.module
  require (!(erc165.entrypoints.any (·.name == "registerInterface")))
    "ERC-165 interface claims must not be publicly mutable"
  requireSignature erc165 "supportsInterface" "supportsInterface(bytes4)"

  let ownable := ProofForge.Contract.Stdlib.Ownable.module
  requireSignature ownable "owner" "owner()"
  requireSignature ownable "transferOwnership" "transferOwnership(address)"
  let some ownerEntry := ownable.entrypoints.find? (·.name == "owner")
    | throw <| IO.userError "missing owner entrypoint"
  require (ownerEntry.returns == .u64) "portable owner() carrier must remain u64"
  require (ownerEntry.returnAbiWord? == some "address") "ERC-173 owner() must return address"
  require (moduleEmits ownable "OwnershipTransferred")
    "ERC-173 OwnershipTransferred event missing"

  let access := ProofForge.Contract.Stdlib.AccessControl.module
  requireSignature access "hasRole" "hasRole(bytes32,address)"
  requireSignature access "getRoleAdmin" "getRoleAdmin(bytes32)"
  requireSignature access "grantRole" "grantRole(bytes32,address)"
  requireSignature access "revokeRole" "revokeRole(bytes32,address)"
  requireSignature access "renounceRole" "renounceRole(bytes32,address)"
  for eventName in #["RoleAdminChanged", "RoleGranted", "RoleRevoked"] do
    require (moduleEmits access eventName) s!"missing {eventName} event"

  IO.println "evm-standard-identity: ok"
