import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Allocator
import ProofForge.Target.Capability
import ProofForge.Target.HostBridge

namespace ProofForge.Target

inductive TargetFamily where
  | evm
  | wasmHost
  | solana
  | move
  | zkCircuitSourcegen
  deriving BEq, DecidableEq, Repr

def TargetFamily.id : TargetFamily → String
  | .evm => "evm"
  | .wasmHost => "wasm-host"
  | .solana => "solana"
  | .move => "move"
  | .zkCircuitSourcegen => "zk-circuit-sourcegen"

inductive ArtifactKind where
  | evmBytecode
  | yul
  | wasm
  | solanaElf
  | movePackage
  | psyCircuitJson
  deriving BEq, DecidableEq, Repr

def ArtifactKind.id : ArtifactKind → String
  | .evmBytecode => "evm-bytecode"
  | .yul => "yul"
  | .wasm => "wasm"
  | .solanaElf => "solana-elf"
  | .movePackage => "move-package"
  | .psyCircuitJson => "psy-circuit-json"

structure TargetProfile where
  id : String
  family : TargetFamily
  artifactKind : ArtifactKind
  capabilities : CapabilitySet
  deploymentAllocator? : Option ProofForge.IR.AllocatorConfig := none
  offlineAllocators : Array ProofForge.IR.AllocatorConfig := #[]
  requiredTools : Array String := #[]
  /-- Host bridge for Wasm-family targets. Ignored for non-Wasm families. -/
  hostBridge? : Option HostBridge := none
  deriving Repr

structure EvmChainProfile where
  id : String
  targetId : String
  networkName : String
  chainId : Nat
  nativeCurrencySymbol : String
  rollupFamily : Option String := none
  dataAvailability : Option String := none
  rpcUrls : Array String := #[]
  websocketUrls : Array String := #[]
  sequencerUrls : Array String := #[]
  blockExplorerUrl : Option String := none
  verifier : Option String := none
  verifierUrl : Option String := none
  notes : Array String := #[]
  deriving Repr

def evm : TargetProfile := {
  id := "evm"
  family := .evm
  artifactKind := .evmBytecode
  deploymentAllocator? := some (ProofForge.IR.AllocatorConfig.evm)
  capabilities := #[
    .storageScalar,
    .storageMap,
    .storageArray,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataDynamicArray,
    .dataDynamicBytes,
    .dataStruct,
    .cryptoHash,
    .assertions,
    .accountExplicit
  ]
  requiredTools := #["solc", "foundry"]
}

def wasmNear : TargetProfile := {
  id := "wasm-near"
  family := .wasmHost
  artifactKind := .wasm
  deploymentAllocator? := some (ProofForge.IR.AllocatorConfig.nearWeeModel)
  offlineAllocators := #[ProofForge.IR.AllocatorConfig.hostBump]
  capabilities := #[
    .storageScalar,
    .storageMap,
    .storageArray,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .envBlock,
    .cryptoHash,
    .accountExplicit,
    .assertions,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataStruct
  ]
  hostBridge? := some .near
  requiredTools := #["rustup", "cargo", "near-cli"]
}

def wasmCosmWasm : TargetProfile := {
  id := "wasm-cosmwasm"
  family := .wasmHost
  artifactKind := .wasm
  deploymentAllocator? := some (ProofForge.IR.AllocatorConfig.cosmWasmRegion)
  offlineAllocators := #[ProofForge.IR.AllocatorConfig.hostBump]
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash
  ]
  hostBridge? := some .cosmWasm
  -- M1 spike uses a direct WAT emitter; the Zig route is deferred to Workstream 4.
  requiredTools := #["wat2wasm", "cosmwasm-check"]
}

def wasmCloudflareWorkers : TargetProfile := {
  id := "wasm-cloudflare-workers"
  family := .wasmHost
  artifactKind := .wasm
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataStruct,
    .assertions
  ]
  requiredTools := #["zig", "wrangler"]
}

def solanaSbpfLinker : TargetProfile := {
  -- Superseded by solanaSbpfAsm (D-026). Kept as historical reference.
  id := "solana-sbpf-linker"
  family := .solana
  artifactKind := .solanaElf
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .accountExplicit,
    .runtimeAllocator,
    .runtimeMemory,
    .runtimeReturnData,
    .runtimeComputeUnits,
    .storagePda,
    .crosscallCpi
  ]
  requiredTools := #["zig", "sbpf-linker"]
}

def solanaSbpfAsm : TargetProfile := {
  -- Canonical Solana route (D-026). Direct sBPF assembly codegen via the
  -- blueshift-gg/sbpf toolchain. CPI and PDA effects stay Solana-specific
  -- (D-027): crosscall.cpi and storage.pda, not crosscall.invoke.
  id := "solana-sbpf-asm"
  family := .solana
  artifactKind := .solanaElf
  capabilities := #[
    .storageScalar,
    .storageMap,
    .storageArray,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .envBlock,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataDynamicArray,
    .dataStruct,
    .cryptoHash,
    .assertions,
    .accountExplicit,
    .runtimeAllocator,
    .runtimeMemory,
    .runtimeReturnData,
    .runtimeComputeUnits,
    .storagePda,
    .crosscallCpi
  ]
  requiredTools := #["sbpf"]
}

def solanaZigFork : TargetProfile := {
  id := "solana-zig-fork"
  family := .solana
  artifactKind := .solanaElf
  capabilities := solanaSbpfLinker.capabilities
  requiredTools := #["solana-zig"]
}

def moveAptos : TargetProfile := {
  id := "move-aptos"
  family := .move
  artifactKind := .movePackage
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .accountExplicit
  ]
  requiredTools := #["aptos"]
}

def moveSui : TargetProfile := {
  id := "move-sui"
  family := .move
  artifactKind := .movePackage
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .accountExplicit
  ]
  requiredTools := #["sui"]
}

def psyDpn : TargetProfile := {
  id := "psy-dpn"
  family := .zkCircuitSourcegen
  artifactKind := .psyCircuitJson
  capabilities := #[
    .storageScalar,
    .storageMap,
    .storageArray,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataStruct,
    .cryptoHash,
    .assertions,
    .accountExplicit,
    .zkCircuit,
    .zkProof
  ]
  requiredTools := #["dargo"]
}

def all : Array TargetProfile := #[
  evm,
  wasmNear,
  wasmCosmWasm,
  solanaSbpfAsm,
  wasmCloudflareWorkers,
  solanaSbpfLinker,
  solanaZigFork,
  moveAptos,
  moveSui,
  psyDpn
]

def find? (id : String) : Option TargetProfile :=
  all.find? (fun profile => profile.id == id)

def knownIds : Array String :=
  all.map (fun profile => profile.id)

def hasCapability (profile : TargetProfile) (capability : Capability) : Bool :=
  profile.capabilities.contains capability

def robinhoodChainTestnet : EvmChainProfile := {
  id := "robinhood-chain-testnet"
  targetId := evm.id
  networkName := "Robinhood Chain Testnet"
  chainId := 46630
  nativeCurrencySymbol := "ETH"
  rollupFamily := some "arbitrum-orbit"
  dataAvailability := some "ethereum-blobs"
  rpcUrls := #[
    "https://rpc.testnet.chain.robinhood.com",
    "https://robinhood-testnet.g.alchemy.com/v2/<API_KEY>"
  ]
  websocketUrls := #[
    "wss://feed.testnet.chain.robinhood.com",
    "wss://robinhood-testnet.g.alchemy.com/v2/<API_KEY>"
  ]
  sequencerUrls := #[
    "https://sequencer.testnet.chain.robinhood.com"
  ]
  blockExplorerUrl := some "https://explorer.testnet.chain.robinhood.com"
  verifier := some "blockscout"
  verifierUrl := some "https://explorer.testnet.chain.robinhood.com/api/"
  notes := #[
    "Ethereum-compatible Arbitrum Orbit L2; compile contracts with the evm target.",
    "This profile owns deployment metadata, not a separate compiler backend."
  ]
}

def anvilLocal : EvmChainProfile := {
  id := "anvil-local"
  targetId := evm.id
  networkName := "Anvil Local"
  chainId := 31337
  nativeCurrencySymbol := "ETH"
  rpcUrls := #["http://127.0.0.1:8545"]
  notes := #[
    "Local Foundry Anvil chain used by ProofForge EVM deploy smokes.",
    "This profile is for reproducible local validation, not public RPC deployment."
  ]
}

def evmChainProfiles : Array EvmChainProfile := #[
  robinhoodChainTestnet,
  anvilLocal
]

def findEvmChainProfile? (id : String) : Option EvmChainProfile :=
  evmChainProfiles.find? (fun profile => profile.id == id)

def findEvmChainProfileByChainId? (chainId : Nat) : Option EvmChainProfile :=
  evmChainProfiles.find? (fun profile => profile.chainId == chainId)

def knownEvmChainProfileIds : Array String :=
  evmChainProfiles.map (fun profile => profile.id)

end ProofForge.Target
