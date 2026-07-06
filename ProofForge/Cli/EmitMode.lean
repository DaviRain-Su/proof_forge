/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

The `EmitMode` enumeration lists every legacy `--mode` / fixture flag the CLI
accepts. It is a large flat inductive (~140 constructors) covering EVM, Solana
sBPF, NEAR Wasm, Move/Sui, Aleo Leo, CosmWasm, Aptos, Quint, and Psy targets
plus per-fixture IR smokes.

The type itself is dependency-free, so it lives in its own module separate from
the helper functions in `Cli.lean` (`EmitMode.emitsEvmDeployManifest`,
`EmitMode.hasBuiltInFixture`, `EmitMode.isLegacyAlias`, `EmitMode.deprecationNote`,
`EmitMode.acceptsTarget`) which reference `CliOptions` / `Target` and therefore
cannot move out yet. `Cli.lean` imports this module and `export`s `EmitMode` so
existing `ProofForge.Cli.EmitMode` references keep resolving.
-/

namespace ProofForge.Cli.EmitMode

inductive EmitMode where
  | yul
  | evmBytecode
  | counterIrYul
  | counterIrBytecode
  | valueVaultIrYul
  | valueVaultIrBytecode
  | errorRefIrYul
  | errorRefIrBytecode
  | errorRefIrSbpf
  | errorRefEmitWat
  | learnYul
  | learnBytecode
  | learnSbpf
  | contractSourceSbpf
  | contractSourceEmitWat
  | learnTarget
  | learnTokenTarget
  | counterIrTs
  | abiScalarIrYul
  | abiScalarIrBytecode
  | assertIrYul
  | assertIrBytecode
  | assignmentIrYul
  | assignmentIrBytecode
  | evmAssignOpIrYul
  | evmAssignOpIrBytecode
  | conditionalIrYul
  | conditionalIrBytecode
  | contextIrYul
  | contextIrBytecode
  | evmEventIrYul
  | evmEventIrBytecode
  | evmCrosscallIrYul
  | evmCrosscallIrBytecode
  | evmExpressionIrYul
  | evmExpressionIrBytecode
  | evmHashIrYul
  | evmHashIrBytecode
  | evmLoopIrYul
  | evmLoopIrBytecode
  | evmMapIrYul
  | evmMapIrBytecode
  | evmStorageArrayIrYul
  | evmStorageArrayIrBytecode
  | evmStorageStructIrYul
  | evmStorageStructIrBytecode
  | evmTypedMapIrYul
  | evmTypedMapIrBytecode
  | evmTypedStorageIrYul
  | evmTypedStorageIrBytecode
  | evmArrayValueIrYul
  | evmArrayValueIrBytecode
  | evmStructArrayValueIrYul
  | evmStructArrayValueIrBytecode
  | evmStructValueIrYul
  | evmStructValueIrBytecode
  | evmAbiAggregateIrYul
  | evmAbiAggregateIrBytecode
  | evmArrayAbiIrYul
  | evmArrayAbiIrBytecode
  | evmDynamicAbiIrYul
  | evmDynamicAbiIrBytecode
  | evmDynamicArrayIrYul
  | evmDynamicArrayIrBytecode
  | evmMemoryArrayIrYul
  | evmMemoryArrayIrBytecode
  | evmPackedStorageIrYul
  | evmPackedStorageIrBytecode
  | evmErrorsIrYul
  | evmErrorsIrBytecode
  | evmFallbackIrYul
  | evmFallbackIrBytecode
  | counterIrPsy
  | eventIrPsy
  | crosscallIrPsy
  | expressionPredicateIrPsy
  | genericEntrypointIrPsy
  | arithmeticIrPsy
  | bitwiseIrPsy
  | boolStorageArrayIrPsy
  | boolStorageScalarIrPsy
  | conditionalIrPsy
  | elseIfIrPsy
  | contextIrPsy
  | hashIrPsy
  | hashStorageIrPsy
  | mapIrPsy
  | assertIrPsy
  | loopIrPsy
  | arrayIrPsy
  | structIrPsy
  | structArrayIrPsy
  | abiAggregateIrPsy
  | nestedAggregateIrPsy
  | storageNestedAggregateIrPsy
  | u32ArithmeticIrPsy
  | u32HashPackingIrPsy
  | u32StorageScalarIrPsy
  | u32StorageArrayIrPsy
  | counterIrSbpf
  | valueVaultIrSbpf
  | controlIrSbpf
  | solanaSdkSbpf
  | solanaSystemCpiSbpf
  | solanaSystemCreateAccountCpiSbpf
  | solanaSplTokenTransferCpiSbpf
  | solanaSplTokenOpsCpiSbpf
  | solanaSplTokenCloseAccountCpiSbpf
  | solanaSplTokenAuthorityCpiSbpf
  | solanaSplToken2022CpiSbpf
  | solanaElf
  | valueVaultSolanaElf
  | solanaSystemCpiElf
  | solanaSystemCreateAccountCpiElf
  | solanaSplTokenTransferCpiElf
  | solanaSplTokenOpsCpiElf
  | solanaSplTokenCloseAccountCpiElf
  | solanaSplTokenAuthorityCpiElf
  | solanaSplToken2022CpiElf
  | solanaLogEventElf
  | solanaClockSysvarElf
  | solanaRentSysvarElf
  | solanaEpochScheduleSysvarElf
  | solanaEpochRewardsSysvarElf
  | solanaLastRestartSlotSysvarElf
  | solanaMemoryElf
  | solanaCryptoHashElf
  | solanaReturnDataComputeElf
  | sbpfAsm
  | counterIrWasmNear
  | contextIrWasmNear
  | hashIrWasmNear
  | mapIrWasmNear
  | counterEmitWat
  | contextEmitWat
  | hashEmitWat
  | mapEmitWat
  | counterIrLeo
  | pureMathIrLeo
  | counterIrCosmWasm
  | counterIrAptos
  | counterIrSui
  | counterIrQuint
  | valueVaultIrQuint
  deriving BEq, Inhabited

def EmitMode.emitsEvmDeployManifest : EmitMode → Bool
  | .evmBytecode
  | .counterIrBytecode
  | .valueVaultIrBytecode
  | .errorRefIrBytecode
  | .learnBytecode
  | .abiScalarIrBytecode
  | .assertIrBytecode
  | .assignmentIrBytecode
  | .evmAssignOpIrBytecode
  | .conditionalIrBytecode
  | .contextIrBytecode
  | .evmEventIrBytecode
  | .evmCrosscallIrBytecode
  | .evmExpressionIrBytecode
  | .evmHashIrBytecode
  | .evmLoopIrBytecode
  | .evmMapIrBytecode
  | .evmStorageArrayIrBytecode
  | .evmStorageStructIrBytecode
  | .evmTypedMapIrBytecode
  | .evmTypedStorageIrBytecode
  | .evmArrayValueIrBytecode
  | .evmStructArrayValueIrBytecode
  | .evmStructValueIrBytecode
  | .evmAbiAggregateIrBytecode => true
  | .evmArrayAbiIrBytecode => true
  | .evmDynamicAbiIrBytecode => true
  | .evmDynamicArrayIrBytecode => true
  | .evmMemoryArrayIrBytecode => true
  | .evmPackedStorageIrBytecode => true
  | .evmErrorsIrBytecode => true
  | .evmFallbackIrBytecode => true
  | _ => false

def EmitMode.hasBuiltInFixture : EmitMode → Bool
  | .counterIrYul
  | .counterIrBytecode
  | .valueVaultIrYul
  | .valueVaultIrBytecode
  | .errorRefIrYul
  | .errorRefIrBytecode
  | .errorRefIrSbpf
  | .errorRefEmitWat
  | .abiScalarIrYul
  | .abiScalarIrBytecode
  | .assertIrYul
  | .assertIrBytecode
  | .assignmentIrYul
  | .assignmentIrBytecode
  | .evmAssignOpIrYul
  | .evmAssignOpIrBytecode
  | .conditionalIrYul
  | .conditionalIrBytecode
  | .contextIrYul
  | .contextIrBytecode
  | .evmEventIrYul
  | .evmEventIrBytecode
  | .evmCrosscallIrYul
  | .evmCrosscallIrBytecode
  | .evmExpressionIrYul
  | .evmExpressionIrBytecode
  | .evmHashIrYul
  | .evmHashIrBytecode
  | .evmLoopIrYul
  | .evmLoopIrBytecode
  | .evmMapIrYul
  | .evmMapIrBytecode
  | .evmStorageArrayIrYul
  | .evmStorageArrayIrBytecode
  | .evmStorageStructIrYul
  | .evmStorageStructIrBytecode
  | .evmTypedMapIrYul
  | .evmTypedMapIrBytecode
  | .evmTypedStorageIrYul
  | .evmTypedStorageIrBytecode
  | .evmArrayValueIrYul
  | .evmArrayValueIrBytecode
  | .evmStructArrayValueIrYul
  | .evmStructArrayValueIrBytecode
  | .evmStructValueIrYul
  | .evmStructValueIrBytecode
  | .evmAbiAggregateIrYul
  | .evmAbiAggregateIrBytecode
  | .evmArrayAbiIrYul
  | .evmArrayAbiIrBytecode
  | .evmDynamicAbiIrYul
  | .evmDynamicAbiIrBytecode
  | .evmDynamicArrayIrYul
  | .evmDynamicArrayIrBytecode
  | .evmMemoryArrayIrYul
  | .evmMemoryArrayIrBytecode
  | .evmPackedStorageIrYul
  | .evmPackedStorageIrBytecode
  | .evmErrorsIrYul
  | .evmErrorsIrBytecode
  | .evmFallbackIrYul
  | .evmFallbackIrBytecode
  | .counterIrPsy
  | .eventIrPsy
  | .crosscallIrPsy
  | .expressionPredicateIrPsy
  | .genericEntrypointIrPsy
  | .arithmeticIrPsy
  | .bitwiseIrPsy
  | .boolStorageArrayIrPsy
  | .boolStorageScalarIrPsy
  | .conditionalIrPsy
  | .elseIfIrPsy
  | .contextIrPsy
  | .hashIrPsy
  | .hashStorageIrPsy
  | .mapIrPsy
  | .assertIrPsy
  | .loopIrPsy
  | .arrayIrPsy
  | .structIrPsy
  | .structArrayIrPsy
  | .abiAggregateIrPsy
  | .nestedAggregateIrPsy
  | .storageNestedAggregateIrPsy
  | .u32ArithmeticIrPsy
  | .u32HashPackingIrPsy
  | .u32StorageScalarIrPsy
  | .u32StorageArrayIrPsy
  | .counterIrSbpf
  | .valueVaultIrSbpf
  | .controlIrSbpf
  | .solanaSdkSbpf
  | .solanaSystemCpiSbpf
  | .solanaSystemCreateAccountCpiSbpf
  | .solanaSplTokenTransferCpiSbpf
  | .solanaSplTokenOpsCpiSbpf
  | .solanaSplTokenCloseAccountCpiSbpf
  | .solanaSplTokenAuthorityCpiSbpf
  | .solanaSplToken2022CpiSbpf
  | .solanaElf
  | .valueVaultSolanaElf
  | .solanaSystemCpiElf
  | .solanaSystemCreateAccountCpiElf
  | .solanaSplTokenTransferCpiElf
  | .solanaSplTokenOpsCpiElf
  | .solanaSplTokenCloseAccountCpiElf
  | .solanaSplTokenAuthorityCpiElf
  | .solanaSplToken2022CpiElf
  | .solanaLogEventElf
  | .solanaClockSysvarElf
  | .solanaRentSysvarElf
  | .solanaEpochScheduleSysvarElf
  | .solanaEpochRewardsSysvarElf
  | .solanaLastRestartSlotSysvarElf
  | .solanaMemoryElf
  | .solanaCryptoHashElf
  | .solanaReturnDataComputeElf
  | .sbpfAsm
  | .counterIrWasmNear
  | .contextIrWasmNear
  | .hashIrWasmNear
  | .mapIrWasmNear
  | .counterEmitWat
  | .contextEmitWat
  | .hashEmitWat
  | .mapEmitWat
  | .counterIrLeo
  | .pureMathIrLeo
  | .counterIrTs
  | .counterIrCosmWasm
  | .counterIrAptos
  | .counterIrSui
  | .counterIrQuint => true
  | .valueVaultIrQuint => true
  | _ => false

def EmitMode.isLegacyAlias : EmitMode → Bool
  | .yul => false
  | _ => true

def EmitMode.deprecationNote : EmitMode → Option String
  | mode =>
      if mode.isLegacyAlias then
        some "Deprecation warning: this legacy flag is deprecated and will be removed in a future release. Use the target-first CLI surface (`proof-forge build|emit|check --target <id> ...`). See RFC 0009."
      else
        none

def EmitMode.acceptsTarget : EmitMode → Bool
  | .learnTarget
  | .learnTokenTarget
  | .counterEmitWat
  | .contextEmitWat
  | .hashEmitWat
  | .mapEmitWat
  | .contractSourceEmitWat => true
  | _ => false

end ProofForge.Cli.EmitMode