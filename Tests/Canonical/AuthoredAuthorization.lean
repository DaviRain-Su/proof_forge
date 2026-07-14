import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Contract.Source
import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Target.Registry

namespace ProofForge.Tests.Canonical.AuthoredAuthorization

open ProofForge.Contract.Source
open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core
open ProofForge.Target

contract_source AuthorizationProbe do
  state owner : .address

  event OwnershipTransferred #[
    indexedField previousOwner .address,
    indexedField newOwner .address
  ]

  entry init do
    let sender : .address := caller;
    owner := sender;
    emit OwnershipTransferred #[
      indexedFieldAs previousOwner addressZero,
      indexedFieldAs newOwner sender
    ];

  entry transferOwnership (newOwner : .address) do
    do requireEq caller owner "not owner";
    do requireNe newOwner addressZero "zero address";
    let previousOwner : .address := owner;
    owner := newOwner;
    emit OwnershipTransferred #[
      indexedField previousOwner,
      indexedField newOwner
    ];

  query owner returns(.address) do
    return owner;

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def capabilityPlan (targetId : String)
    (bundle : ProofForge.IR.Canonical.CanonicalBundle) : CapabilityPlan := {
  targetId
  calls := bundle.contract.contract.requirements
}

def operations (bundle : ProofForge.IR.Canonical.CanonicalBundle) : Array InstructionOp :=
  bundle.contract.contract.module.functions.flatMap fun function =>
    function.blocks.flatMap fun block => block.instructions.map (·.op)

def withEvmSelectors
    (checked : ProofForge.IR.Canonical.CheckedCanonicalContract) :
    IO ProofForge.IR.Canonical.CheckedCanonicalContract := do
  let entrypoints := checked.contract.interface.entrypoints.map fun entrypoint =>
    let selector? := match entrypoint.name with
      | "init" => some "e1c7392a"
      | "transferOwnership" => some "f2fde38b"
      | "owner" => some "8da5cb5b"
      | _ => entrypoint.selector?
    { entrypoint with selector? }
  let canonical := { checked.contract with
    interface := { checked.contract.interface with entrypoints } }
  match ProofForge.IR.Canonical.validateCanonical canonical with
  | .ok hydrated => pure hydrated
  | .error error => throw <| IO.userError s!"EVM selector hydration failed: {repr error}"

def main : IO Unit := do
  let bundle <- match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"authorization normalization failed: {repr error}"
  let ops := operations bundle
  require (ops.any fun operation => match operation with
      | .contextRead .sender => true
      | _ => false)
    "caller did not normalize to portable Core sender context"
  require (ops.any fun operation => match operation with
      | .pure (.compare .eq _ _) => true
      | _ => false)
    "assert_eq did not normalize to a portable Core equality"
  require (ops.any fun operation => match operation with
      | .pure (.compare .ne _ _) => true
      | _ => false)
    "assert_ne did not normalize to a portable Core inequality"
  require (ops.any fun operation => match operation with
      | .pure (.literal (.addressLit "0")) => true
      | _ => false)
    "addressZero did not remain a target-neutral address literal"

  let evmChecked <- withEvmSelectors bundle.contract
  match ProofForge.Backend.Evm.Plan.Core.buildFromCore evmChecked
      (capabilityPlan evm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"EVM authorization plan failed: {error.message}"
  match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract
      (capabilityPlan solanaSbpfAsm.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"Solana authorization plan failed: {error.message}"
  match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract
      (capabilityPlan wasmNear.id bundle) with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"NEAR authorization plan failed: {error.message}"
  IO.println "authored-authorization: ok"

end ProofForge.Tests.Canonical.AuthoredAuthorization

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredAuthorization.main
