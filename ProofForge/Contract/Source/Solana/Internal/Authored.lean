import ProofForge.Frontend.Authored.Builder
import ProofForge.Target.HostOps.Solana

/-! # Direct Solana Authored Adapter

Compiler-internal bridge used by the Solana `contract_source` extension during
the single-authoring cutover. It emits versioned typed operation payloads and
has no dependency on `Contract.Builder`, `IR.Module`, or `Source.Solana.Legacy`.
-/

namespace ProofForge.Contract.Source.Solana.Internal.Authored

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Builder
open ProofForge.Target
open ProofForge.Target.HostOps.Solana.Payload

private def operationIntent (id : HostOpId) (capability : Capability)
    (payload : OperationPayload) : AuthoredIntent := {
  kind := .capability
  operation := .hostOp id
  capability? := some capability
  payload
}

def declareAccount (spec : AccountSpec) : ModuleM Unit :=
  intent (operationIntent ProofForge.Target.HostOps.Solana.accountDeclareId
    .accountExplicit spec.encode)

def declarePda (spec : PdaSpec) : ModuleM Unit :=
  intent (operationIntent ProofForge.Target.HostOps.Solana.pdaDeriveId
    .storagePda spec.encode)

def derivePda (spec : PdaSpec) : EntryM Unit :=
  entryIntent (operationIntent ProofForge.Target.HostOps.Solana.pdaDeriveId
    .storagePda spec.encode)

def declareCpi (spec : CpiSpec) : ModuleM Unit :=
  intent (operationIntent ProofForge.Target.HostOps.Solana.cpiInvokeId
    .crosscallCpi spec.encode)

def invokeCpi (spec : CpiSpec) : EntryM Unit :=
  entryIntent (operationIntent ProofForge.Target.HostOps.Solana.cpiInvokeId
    .crosscallCpi spec.encode)

def configureAllocator (spec : AllocatorSpec) : ModuleM Unit :=
  intent (operationIntent ProofForge.Target.HostOps.Solana.allocatorConfigureId
    .runtimeAllocator spec.encode)

def reallocAccount (spec : AccountReallocSpec) : EntryM Unit :=
  entryIntent (operationIntent ProofForge.Target.HostOps.Solana.accountReallocId
    .accountExplicit spec.encode)

def initializeTransferHookExtraAccountMeta
    (spec : TransferHookExtraAccountMetaSpec) : EntryM Unit :=
  entryIntent (operationIntent ProofForge.Target.HostOps.Solana.transferHookExtraAccountMetaId
    .accountExplicit spec.encode)

end ProofForge.Contract.Source.Solana.Internal.Authored
