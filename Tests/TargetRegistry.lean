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
  require (evmProfile.deploymentAllocator? == some (ProofForge.IR.AllocatorConfig.evm))
    "evm target must declare an explicit bump-over-scratch allocator binding"
  require (find? "robinhood-chain-testnet" |>.isNone)
    "robinhood-chain-testnet must not be registered as a compiler target"

  let nearProfile ← requireSome (find? "wasm-near") "missing wasm-near target profile"
  require (nearProfile.deploymentAllocator? == some (ProofForge.IR.AllocatorConfig.nearWeeModel))
    "wasm-near deployment allocator must stay on the NEAR wasm-internal profile"
  require (nearProfile.offlineAllocators == #[ProofForge.IR.AllocatorConfig.hostBump])
    "wasm-near offline allocator surface must stay host-bump only"
  require (!nearProfile.offlineAllocators.contains (ProofForge.IR.AllocatorConfig.hostJemallocShape))
    "wasm-near must not advertise jemalloc-shaped host allocation"
  require (nearProfile.hostBridge? == some HostBridge.near)
    "wasm-near must declare the NEAR host bridge"

  let cosmwasmProfile ← requireSome (find? "wasm-cosmwasm") "missing wasm-cosmwasm target profile"
  require (cosmwasmProfile.hostBridge? == some HostBridge.cosmWasm)
    "wasm-cosmwasm must declare the CosmWasm host bridge"

  let suiProfile ← requireSome (find? "move-sui") "missing move-sui target profile"
  require (suiProfile.capabilities.contains .storageScalar)
    "move-sui Counter MVP must support scalar storage"
  require (suiProfile.capabilities.contains .assertions)
    "move-sui Counter MVP must support assertions"
  require (suiProfile.capabilities.contains .accountExplicit)
    "move-sui Counter MVP must support explicit object/account semantics"
  for unsupported in #[
    .storageMap,
    .storageArray,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .dataFixedArray,
    .dataDynamicArray,
    .dataStruct
  ] do
    require (!suiProfile.capabilities.contains unsupported)
      s!"move-sui Counter MVP must not advertise unsupported capability {unsupported.id}"

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

  let anvil ← requireSome (findEvmChainProfile? "anvil-local")
    "missing Anvil local profile"
  require (anvil.targetId == evm.id)
    "Anvil local profile must reuse the evm compiler target"
  require (anvil.chainId == 31337)
    "Anvil local chain id mismatch"
  require (findEvmChainProfileByChainId? 31337 |>.isSome)
    "Anvil local chain id lookup failed"
  require (knownEvmChainProfileIds.contains "anvil-local")
    "Anvil local profile id missing from known ids"

  -- D-026: superseded Solana profiles stay importable as constants but must
  -- not appear on the active target surface.
  require (find? "solana-sbpf-linker" |>.isNone)
    "solana-sbpf-linker is deprecated (D-026) and must be hidden from find?"
  require (find? "solana-zig-fork" |>.isNone)
    "solana-zig-fork is deprecated (D-005) and must be hidden from find?"
  require (!knownIds.contains "solana-sbpf-linker")
    "solana-sbpf-linker must not appear in knownIds"
  require (!knownIds.contains "solana-zig-fork")
    "solana-zig-fork must not appear in knownIds"
  require (allIncludingDeprecated.contains solanaSbpfLinker)
    "solanaSbpfLinker constant must remain in allIncludingDeprecated"
  require (allIncludingDeprecated.contains solanaZigFork)
    "solanaZigFork constant must remain in allIncludingDeprecated"

  IO.println "target-registry: ok"
  return 0

end ProofForge.Tests.TargetRegistry

def main : IO UInt32 :=
  ProofForge.Tests.TargetRegistry.main
