import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Allocator
import ProofForge.Target.Capability
import ProofForge.Target.ChainSemantics

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
  chainSemantics : ChainSemantics := {}
  deploymentAllocator? : Option ProofForge.IR.ChainAllocator := none
  offlineAllocators : Array ProofForge.IR.ExperimentAllocator := #[]
  requiredTools : Array String := #[]
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
    .accountExplicit
  ]
  chainSemantics := {
    nativeAmount? := some .evmWeiU256
    indexedEvents := .evmTopics 3
    crosscall := .evmCall
  }
  requiredTools := #["solc", "foundry"]
}

def wasmNear : TargetProfile := {
  id := "wasm-near"
  family := .wasmHost
  artifactKind := .wasm
  deploymentAllocator? := some .nearWeeModel
  offlineAllocators := #[.hostBump]
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .valueNative,
    .eventsEmit,
    .envBlock,
    .cryptoHash,
    .accountExplicit,
    .assertions
  ]
  chainSemantics := {
    nativeAmount? := some .nearYoctoNearU128
    indexedEvents := .nearJsonLogNoTopics
    crosscall := .nearPromise
    notes := #[
      "NEAR deployment uses wasm-internal allocation; offline experiments use host-managed linear-memory allocation.",
      "NEAR native value is attached_deposit, which needs an explicit U128 IR projection before EmitWat can lower it.",
      "NEAR cross-contract execution is Promise-based and asynchronous."
    ]
  }
  requiredTools := #["rustup", "cargo", "near-cli"]
}

def wasmCosmWasm : TargetProfile := {
  id := "wasm-cosmwasm"
  family := .wasmHost
  artifactKind := .wasm
  deploymentAllocator? := some .cosmWasmRegion
  offlineAllocators := #[.hostBump]
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
  chainSemantics := {
    nativeAmount? := some .cosmWasmFunds
    indexedEvents := .cosmWasmAttributes
    crosscall := .cosmWasmSubmessage
  }
  requiredTools := #["zig", "cosmwasm-check"]
}

def solanaSbpfLinker : TargetProfile := {
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
    .storagePda,
    .crosscallCpi
  ]
  chainSemantics := {
    nativeAmount? := some .solanaLamportsU64
    indexedEvents := .unsupported
    crosscall := .solanaCpi
  }
  requiredTools := #["zig", "sbpf-linker"]
}

def solanaZigFork : TargetProfile := {
  id := "solana-zig-fork"
  family := .solana
  artifactKind := .solanaElf
  capabilities := solanaSbpfLinker.capabilities
  chainSemantics := solanaSbpfLinker.chainSemantics
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
  chainSemantics := {
    nativeAmount? := some .moveCoinResources
    indexedEvents := .moveEvents
    crosscall := .moveEntryFunction
  }
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
  chainSemantics := {
    nativeAmount? := some .moveCoinResources
    indexedEvents := .moveEvents
    crosscall := .moveEntryFunction
  }
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
  chainSemantics := {
    nativeAmount? := none
    indexedEvents := .unsupported
    crosscall := .unsupported
    notes := #["Psy DPN is a circuit sourcegen target; chain-native value and cross-contract execution are not modeled here."]
  }
  requiredTools := #["dargo"]
}

def all : Array TargetProfile := #[
  evm,
  wasmNear,
  wasmCosmWasm,
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

def evmChainProfiles : Array EvmChainProfile := #[
  robinhoodChainTestnet
]

def findEvmChainProfile? (id : String) : Option EvmChainProfile :=
  evmChainProfiles.find? (fun profile => profile.id == id)

def findEvmChainProfileByChainId? (chainId : Nat) : Option EvmChainProfile :=
  evmChainProfiles.find? (fun profile => profile.chainId == chainId)

def knownEvmChainProfileIds : Array String :=
  evmChainProfiles.map (fun profile => profile.id)

end ProofForge.Target
