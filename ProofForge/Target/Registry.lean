import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Allocator
import ProofForge.Target.Capability
import ProofForge.Target.HostBridge
import ProofForge.Target.Support

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
  | leoSource
  | typescriptSource
  deriving BEq, DecidableEq, Repr

def ArtifactKind.id : ArtifactKind → String
  | .evmBytecode => "evm-bytecode"
  | .yul => "yul"
  | .wasm => "wasm"
  | .solanaElf => "solana-elf"
  | .movePackage => "move-package"
  | .psyCircuitJson => "psy-circuit-json"
  | .leoSource => "leo-source"
  | .typescriptSource => "typescript-source"

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
  /-- True for profiles kept only as historical reference (D-026). Deprecated
  profiles are excluded from `all`, `find?`, `knownIds`, and `--list-targets`,
  but the underlying constants (`solanaSbpfLinker`, `solanaZigFork`) remain
  importable for tests that exercise legacy routing. -/
  deprecated : Bool := false
  /-- Machine-readable command/input/stage support (PF-P1-02). Authoritative
  over README prose; plain `--list-targets` still means registry membership. -/
  support : TargetSupport := {}
  deriving Repr, BEq

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
    .cryptoEcrecover,
    .assertions,
    .checkedArithmetic,
    .accountExplicit
  ]
  requiredTools := #["solc", "foundry"]
  support := TargetSupport.primaryTriad
    "portable IR Counter/ValueVault + TokenSpec; Yul intermediate, solc bytecode final"
    #[
      { tool := "solc", stage := "final-deployable" },
      { tool := "foundry", stage := "runtime-smoke" }
    ]
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
    .crosscallInvoke,
    .nearPromise,
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
  support := TargetSupport.primaryTriad
    "portable IR → EmitWat WAT intermediate → wat2wasm Wasm final; NEP-141 stdlib"
    #[
      { tool := "wat2wasm", stage := "final-deployable" },
      { tool := "near-cli", stage := "deploy" }
    ]
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
  requiredTools := #["wat2wasm"]
  support := {
    maturity := .counterMvp
    inputModes := #[.contractSource, .fixture]
    commands := #[.build, .emit, .check]
    outputStages := #[.intermediate, .finalDeployable]
    validationLevel := .capability
    supportedFragment :=
      "Counter MVP (PF-P3-02 six-gate): contract_source via EmitWat + HostBridge.cosmWasm; " ++
      "offline-host lifecycle; execute_msg remains stub; cosmwasm-check golden via fixture emit"
    toolStages := #[{ tool := "wat2wasm", stage := "final-deployable" }]
  }
}

def wasmCloudflareWorkers : TargetProfile := {
  id := "wasm-cloudflare-workers"
  family := .wasmHost
  artifactKind := .typescriptSource
  capabilities := #[.storageScalar]
  requiredTools := #["wrangler"]
  support := {
    maturity := .research
    inputModes := #[.fixture]
    commands := #[.emit]
    outputStages := #[.sourcegen]
    validationLevel := .none
    supportedFragment :=
      "Off-chain research sourcegen: fixture Counter storage.scalar subset → TypeScript Worker; " ++
      "product contract_source fails closed; strict Wrangler validation is an optional promotion gate"
    toolStages := #[{ tool := "wrangler", stage := "sourcegen" }]
  }
}

/-- Stellar Soroban host-family adapter (Phase 4). In `Registry.all` /
`--list-targets` as a **host-bridge product target** on the shared EmitWat
core (`HostBridge.soroban`: `_get`/`_put`, `invoke_contract`,
`require_auth_for_args`). Full Stellar CLI / contract-spec / TTL storage
remain follow-on work; portable authors still only write business logic. -/
def wasmStellarSoroban : TargetProfile := {
  id := "wasm-stellar-soroban"
  family := .wasmHost
  artifactKind := .wasm
  deploymentAllocator? := some (ProofForge.IR.AllocatorConfig.hostBump)
  offlineAllocators := #[ProofForge.IR.AllocatorConfig.hostBump]
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
  hostBridge? := some .soroban
  requiredTools := #["wat2wasm"]
  support := {
    maturity := .counterMvp
    inputModes := #[.contractSource]
    commands := #[.build, .check]
    outputStages := #[.intermediate, .finalDeployable]
    validationLevel := .capability
    supportedFragment :=
      "Counter MVP (PF-P3-02 six-gate): contract_source via EmitWat + HostBridge.soroban; " ++
      "offline-host lifecycle; TokenSpec unsupported; auth/TTL/Stellar CLI follow-on"
    toolStages := #[{ tool := "wat2wasm", stage := "final-deployable" }]
  }
}

def solanaSbpfLinker : TargetProfile := {
  -- Superseded by solanaSbpfAsm (D-026). Kept as historical reference.
  -- Excluded from `all`/`find?`/`knownIds` via deprecated := true.
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
  deprecated := true
}

def solanaSbpfAsm : TargetProfile := {
  -- Canonical Solana route (D-026). Direct sBPF assembly codegen via the
  -- blueshift-gg/sbpf toolchain. Explicit Source.Solana CPI/PDA remain
  -- extension-only (D-027). Portable `crosscall.invoke` is accepted and
  -- **materialized** as CPI-shaped execution (Phase B.3): method/args → ix
  -- data, program account by index (`callee_program`).
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
    .controlUnboundedLoop,
    .dataFixedArray,
    .dataDynamicArray,
    .dataDynamicBytes,
    .dataStruct,
    .cryptoHash,
    .assertions,
    .accountExplicit,
    .runtimeAllocator,
    .runtimeMemory,
    .runtimeReturnData,
    .runtimeComputeUnits,
    .storagePda,
    .crosscallCpi,
    .crosscallInvoke
  ]
  requiredTools := #["sbpf"]
  support := TargetSupport.primaryTriad
    "portable IR → sBPF assembly intermediate → sbpf ELF final; CPI/PDA extensions"
    #[{ tool := "sbpf", stage := "final-deployable" }]
}

def solanaZigFork : TargetProfile := {
  -- Fallback/reference track (D-005), not the primary product path.
  -- Excluded from `all`/`find?`/`knownIds` via deprecated := true.
  id := "solana-zig-fork"
  family := .solana
  artifactKind := .solanaElf
  capabilities := solanaSbpfLinker.capabilities
  requiredTools := #["solana-zig"]
  deprecated := true
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
  support := {
    maturity := .spike
    inputModes := #[.fixture]
    commands := #[.build, .emit, .check]
    outputStages := #[.sourcegen]
    validationLevel := .capability
    supportedFragment :=
      "Counter sourcegen spike: fixture counter → Move source package; " ++
      "product contract_source fails closed; final package requires mandatory aptos compile/test"
    toolStages := #[{ tool := "aptos", stage := "sourcegen" }]
  }
}

def moveSui : TargetProfile := {
  id := "move-sui"
  family := .move
  artifactKind := .movePackage
  capabilities := #[
    .storageScalar,
    .assertions,
    .accountExplicit
  ]
  requiredTools := #["sui"]
  support := {
    maturity := .counterMvp
    inputModes := #[.fixture]
    commands := #[.build, .emit, .check]
    outputStages := #[.sourcegen]
    validationLevel := .capability
    supportedFragment := "Counter MVP Move package; scalar storage + assertions only"
    toolStages := #[{ tool := "sui", stage := "sourcegen" }]
  }
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
  support := TargetSupport.fixtureSpike
    "PF-P3-02: fixture Counter .psy + diagnostics; dargo final execute when installed; product source fail-closed"
    #[{ tool := "dargo", stage := "final-deployable" }]
}

/-- Aleo/Leo target (Phase 4 ZK lane, Road 1 sourcegen).

First ZK-app-sourcegen registry entry alongside `psy-dpn`. The Road 1 spike
lowers the portable IR `Counter` fixture to a Leo 4.0 program with a public
`mapping`, `@noupgrade constructor`, and `fn ... -> Final` entrypoints. The
ZK-specific value proposition (private records, transitions, proof
generation) is future Road 2 work; this profile owns the codegen boundary and
the `leo build` / `leo test` validation gate.

`storageScalar` is declared because the Aleo backend rewrites portable scalar
state into a single-slot Leo `mapping` (Leo has no scalar storage), so scalar
storage is faithfully supported from the author's perspective. See
`docs/targets/aleo-leo.md` for the full capability proposal and research-exit
plan. -/
def aleoLeo : TargetProfile := {
  id := "aleo-leo"
  family := .zkCircuitSourcegen
  artifactKind := .leoSource
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .envBlock,
    .controlConditional,
    .controlBoundedLoop,
    .dataStruct,
    .dataLinearRecord,
    .cryptoHash,
    .assertions,
    .accountExplicit,
    .checkedArithmetic,
    .crosscallNamed,
    .zkCircuit,
    .zkProof
  ]
  requiredTools := #["leo"]
  support := {
    maturity := .research
    inputModes := #[.fixture]
    commands := #[.emit, .check]
    outputStages := #[.sourcegen]
    validationLevel := .capability
    supportedFragment :=
      "Research Leo sourcegen for validated pure, Unit-final, and state-independent (T, Final) functions; " ++
      "state-derived non-Unit returns and product contract_source fail closed"
    toolStages := #[{ tool := "leo", stage := "sourcegen" }]
  }
}

/-- All defined profiles, including deprecated ones. Tests that exercise
legacy routing (e.g. `Tests/ValueVaultExample`) import the individual
constants and may use this. -/
def allIncludingDeprecated : Array TargetProfile := #[
  evm,
  wasmNear,
  wasmCosmWasm,
  solanaSbpfAsm,
  wasmCloudflareWorkers,
  wasmStellarSoroban,
  solanaSbpfLinker,
  solanaZigFork,
  moveAptos,
  moveSui,
  psyDpn,
  aleoLeo
]

/-- Active (non-deprecated) profiles. This is the public target surface:
`--list-targets`, `find?`, and `knownIds` only expose these. Deprecated
profiles (D-026) stay importable as constants but are hidden from routing. -/
def all : Array TargetProfile :=
  allIncludingDeprecated.filter (fun profile => !profile.deprecated)

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
