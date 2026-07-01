import ProofForge.Target.Registry

namespace ProofForge.Tests.TargetRegistry

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireSome {α : Type} (value : Option α) (message : String) : IO α :=
  match value with
  | some x => pure x
  | none => throw <| IO.userError message

def main : IO UInt32 := do
  let evmProfile ← requireSome (find? "evm") "missing evm target profile"
  require (evmProfile.id == "evm") "evm target id mismatch"
  require (evmProfile.chainSemantics.nativeAmount? == some NativeAmountSemantics.evmWeiU256)
    "evm native amount semantics mismatch"
  require (evmProfile.chainSemantics.indexedEvents == IndexedEventSemantics.evmTopics 3)
    "evm indexed event semantics mismatch"
  require (evmProfile.chainSemantics.crosscall == CrosscallSemantics.evmCall)
    "evm crosscall semantics mismatch"
  require (find? "robinhood-chain-testnet" |>.isNone)
    "robinhood-chain-testnet must not be registered as a compiler target"

  let nearProfile ← requireSome (find? "wasm-near") "missing wasm-near target profile"
  require (nearProfile.chainSemantics.nativeAmount? == some NativeAmountSemantics.nearYoctoNearU128)
    "wasm-near native amount semantics mismatch"
  require nearProfile.chainSemantics.requiresNativeAmountProjection
    "wasm-near native amount must require a wide amount projection"
  require (nearProfile.chainSemantics.indexedEvents == IndexedEventSemantics.nearJsonLogNoTopics)
    "wasm-near indexed event semantics mismatch"
  require (nearProfile.chainSemantics.crosscall == CrosscallSemantics.nearPromise)
    "wasm-near crosscall semantics mismatch"
  require (nearProfile.deploymentAllocator? == some ProofForge.IR.ChainAllocator.nearWeeModel)
    "wasm-near deployment allocator must stay on the NEAR wasm-internal profile"
  require (nearProfile.offlineAllocators == #[ProofForge.IR.ExperimentAllocator.hostBump])
    "wasm-near offline allocator surface must stay host-bump only"
  require (!nearProfile.offlineAllocators.contains ProofForge.IR.ExperimentAllocator.hostJemallocShape)
    "wasm-near must not advertise jemalloc-shaped host allocation"

  let robinhood ← requireSome (findEvmChainProfile? "robinhood-chain-testnet")
    "missing Robinhood Chain testnet profile"
  require (robinhood.targetId == evm.id)
    "Robinhood Chain profile must reuse the evm compiler target"
  require (robinhood.chainId == 46630)
    "Robinhood Chain testnet chain id mismatch"
  require (robinhood.nativeCurrencySymbol == "ETH")
    "Robinhood Chain testnet gas token mismatch"
  require (robinhood.rollupFamily == some "arbitrum-orbit")
    "Robinhood Chain rollup family mismatch"
  require (findEvmChainProfileByChainId? 46630 |>.isSome)
    "Robinhood Chain testnet chain id lookup failed"
  require (knownEvmChainProfileIds.contains "robinhood-chain-testnet")
    "Robinhood Chain profile id missing from known ids"

  IO.println "target-registry: ok"
  return 0

end ProofForge.Tests.TargetRegistry

def main : IO UInt32 :=
  ProofForge.Tests.TargetRegistry.main
