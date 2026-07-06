import Lean.Util.Path
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.HexUtil
import ProofForge.Cli.Options
import ProofForge.Cli.Usage

open System
open ProofForge.Cli.ConstructorAbi
open ProofForge.Cli.HexUtil

namespace ProofForge.Cli

partial def parseArgs : List String → CliOptions → Except String CliOptions
  | [], opts =>
      let hasRunnableInput := opts.input?.isSome || opts.mode.hasBuiltInFixture
      if opts.targetId?.isSome && !opts.mode.acceptsTarget then
        .error "--target only applies to --learn, --learn-token, and emitwat modes"
      else if opts.mode == .learnTarget && opts.targetId?.isNone then
        .error "--learn requires --target <target-id>"
      else if opts.mode == .learnTokenTarget && opts.targetId?.isNone then
        .error "--learn-token requires --target <target-id>"
      else if opts.evmChainProfile?.isSome && !opts.emitsEvmDeployManifest then
        .error "--evm-chain-profile only applies to EVM bytecode modes that emit proof-forge-deploy.json"
      else if !opts.evmConstructorArgsHex.isEmpty && !opts.emitsEvmDeployManifest then
        .error "--evm-constructor-args-hex only applies to EVM bytecode modes that emit proof-forge-deploy.json"
      else if !opts.evmConstructorParams.isEmpty && !opts.emitsEvmDeployManifest then
        .error "--evm-constructor-param only applies to EVM bytecode modes that emit proof-forge-deploy.json"
      else if !opts.evmConstructorValues.isEmpty && !opts.emitsEvmDeployManifest then
        .error "--evm-constructor-arg only applies to EVM bytecode modes that emit proof-forge-deploy.json"
      else
        match finalizeConstructorOptions opts with
        | .ok opts => if hasRunnableInput then .ok opts else .error usage
        | .error msg => .error msg
  | "-o" :: out :: rest, opts =>
      parseArgs rest { opts with output? := some (FilePath.mk out) }
  | "--output" :: out :: rest, opts =>
      parseArgs rest { opts with output? := some (FilePath.mk out) }
  | "--root" :: root :: rest, opts =>
      parseArgs rest { opts with root? := some (FilePath.mk root) }
  | "--module" :: modName :: rest, opts =>
      parseArgs rest { opts with moduleName? := some (parseModuleName modName) }
  | "--yul-output" :: path :: rest, opts =>
      parseArgs rest { opts with yulOutput? := some (FilePath.mk path) }
  | "--artifact-output" :: path :: rest, opts =>
      parseArgs rest { opts with artifactOutput? := some (FilePath.mk path) }
  | "--target" :: targetId :: rest, opts =>
      parseArgs rest { opts with targetId? := some targetId }
  | "--target" :: [], _ =>
      .error "missing value for --target"
  | "--scenario" :: path :: rest, opts =>
      parseArgs rest { opts with scenario? := some (FilePath.mk path) }
  | "--scenario" :: [], _ =>
      .error "missing value for --scenario"
  | "--fixture" :: fixture :: rest, opts =>
      parseArgs rest { opts with fixture? := some fixture }
  | "--fixture" :: [], _ =>
      .error "missing value for --fixture"
  | "--evm-chain-profile" :: profile :: rest, opts =>
      parseArgs rest { opts with evmChainProfile? := some profile }
  | "--evm-constructor-args-hex" :: hex :: rest, opts => do
      let normalized ← normalizeConstructorArgsHex hex
      parseArgs rest { opts with evmConstructorArgsHex := normalized }
  | "--evm-constructor-param" :: param :: rest, opts => do
      let spec ← parseConstructorParamSpec param
      parseArgs rest { opts with evmConstructorParams := opts.evmConstructorParams.push spec }
  | "--evm-constructor-arg" :: value :: rest, opts => do
      let spec ← parseConstructorValueSpec value
      parseArgs rest { opts with evmConstructorValues := opts.evmConstructorValues.push spec }
  | "--solana-sbpf-arch" :: arch :: rest, opts =>
      if arch == "v0" || arch == "v3" then
        parseArgs rest { opts with solanaSbpfArch := arch }
      else
        .error s!"invalid --solana-sbpf-arch '{arch}', expected v0 or v3"
  | "--solana-sbpf-arch" :: [], _ =>
      .error "missing value for --solana-sbpf-arch, expected v0 or v3"
  | "--solc" :: path :: rest, opts =>
      parseArgs rest { opts with solc := path }
  | "--cast" :: path :: rest, opts =>
      parseArgs rest { opts with cast := path }
  | "--evm-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmBytecode }
  | "--bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmBytecode }
  | "--learn" :: rest, opts =>
      parseArgs rest { opts with mode := .learnTarget }
  | "--learn-token" :: rest, opts =>
      parseArgs rest { opts with mode := .learnTokenTarget }
  | "--learn-target" :: targetId :: rest, opts =>
      parseArgs rest { opts with mode := .learnTarget, targetId? := some targetId }
  | "--learn-target" :: [], _ =>
      .error "missing value for --learn-target"
  | "--emit-counter-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrYul }
  | "--emit-counter-ir-ts" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrTs }
  | "--emit-counter-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrBytecode }
  | "--emit-value-vault-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultIrYul }
  | "--emit-value-vault-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultIrBytecode }
  | "--emit-error-ref-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .errorRefIrYul }
  | "--emit-error-ref-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .errorRefIrBytecode }
  | "--learn-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .learnYul }
  | "--learn-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .learnBytecode }
  | "--learn-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .learnSbpf }
  | "--contract-source-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .contractSourceSbpf }
  | "--contract-source-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .contractSourceEmitWat }
  | "--emit-abi-scalar-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .abiScalarIrYul }
  | "--emit-abi-scalar-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .abiScalarIrBytecode }
  | "--emit-assert-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .assertIrYul }
  | "--emit-assert-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .assertIrBytecode }
  | "--emit-assignment-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .assignmentIrYul }
  | "--emit-assignment-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .assignmentIrBytecode }
  | "--emit-evm-assign-op-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmAssignOpIrYul }
  | "--emit-evm-assign-op-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmAssignOpIrBytecode }
  | "--emit-conditional-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .conditionalIrYul }
  | "--emit-conditional-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .conditionalIrBytecode }
  | "--emit-context-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .contextIrYul }
  | "--emit-context-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .contextIrBytecode }
  | "--emit-evm-event-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmEventIrYul }
  | "--emit-evm-event-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmEventIrBytecode }
  | "--emit-evm-crosscall-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmCrosscallIrYul }
  | "--emit-evm-crosscall-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmCrosscallIrBytecode }
  | "--emit-evm-expression-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmExpressionIrYul }
  | "--emit-evm-expression-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmExpressionIrBytecode }
  | "--emit-evm-hash-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmHashIrYul }
  | "--emit-evm-hash-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmHashIrBytecode }
  | "--emit-evm-loop-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmLoopIrYul }
  | "--emit-evm-loop-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmLoopIrBytecode }
  | "--emit-evm-map-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmMapIrYul }
  | "--emit-evm-map-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmMapIrBytecode }
  | "--emit-evm-storage-array-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStorageArrayIrYul }
  | "--emit-evm-storage-array-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStorageArrayIrBytecode }
  | "--emit-evm-storage-struct-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStorageStructIrYul }
  | "--emit-evm-storage-struct-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStorageStructIrBytecode }
  | "--emit-evm-typed-map-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmTypedMapIrYul }
  | "--emit-evm-typed-map-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmTypedMapIrBytecode }
  | "--emit-evm-typed-storage-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmTypedStorageIrYul }
  | "--emit-evm-typed-storage-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmTypedStorageIrBytecode }
  | "--emit-evm-array-value-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmArrayValueIrYul }
  | "--emit-evm-array-value-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmArrayValueIrBytecode }
  | "--emit-evm-struct-array-value-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStructArrayValueIrYul }
  | "--emit-evm-struct-array-value-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStructArrayValueIrBytecode }
  | "--emit-evm-struct-value-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStructValueIrYul }
  | "--emit-evm-struct-value-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmStructValueIrBytecode }
  | "--emit-evm-abi-aggregate-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmAbiAggregateIrYul }
  | "--emit-evm-abi-aggregate-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmAbiAggregateIrBytecode }
  | "--emit-evm-array-abi-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmArrayAbiIrYul }
  | "--emit-evm-array-abi-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmArrayAbiIrBytecode }
  | "--emit-evm-dynamic-abi-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmDynamicAbiIrYul }
  | "--emit-evm-dynamic-abi-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmDynamicAbiIrBytecode }
  | "--emit-evm-dynamic-array-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmDynamicArrayIrYul }
  | "--emit-evm-dynamic-array-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmDynamicArrayIrBytecode }
  | "--emit-evm-memory-array-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmMemoryArrayIrYul }
  | "--emit-evm-memory-array-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmMemoryArrayIrBytecode }
  | "--emit-evm-packed-storage-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmPackedStorageIrYul }
  | "--emit-evm-packed-storage-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmPackedStorageIrBytecode }
  | "--emit-evm-errors-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmErrorsIrYul }
  | "--emit-evm-errors-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmErrorsIrBytecode }
  | "--emit-evm-fallback-ir-yul" :: rest, opts =>
      parseArgs rest { opts with mode := .evmFallbackIrYul }
  | "--emit-evm-fallback-ir-bytecode" :: rest, opts =>
      parseArgs rest { opts with mode := .evmFallbackIrBytecode }
  | "--emit-counter-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrPsy }
  | "--emit-event-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .eventIrPsy }
  | "--emit-crosscall-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .crosscallIrPsy }
  | "--emit-expression-predicate-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .expressionPredicateIrPsy }
  | "--emit-generic-entrypoint-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .genericEntrypointIrPsy }
  | "--emit-arithmetic-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .arithmeticIrPsy }
  | "--emit-bitwise-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .bitwiseIrPsy }
  | "--emit-bool-storage-array-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .boolStorageArrayIrPsy }
  | "--emit-bool-storage-scalar-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .boolStorageScalarIrPsy }
  | "--emit-conditional-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .conditionalIrPsy }
  | "--emit-else-if-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .elseIfIrPsy }
  | "--emit-context-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .contextIrPsy }
  | "--emit-hash-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .hashIrPsy }
  | "--emit-hash-storage-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .hashStorageIrPsy }
  | "--emit-map-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .mapIrPsy }
  | "--emit-assert-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .assertIrPsy }
  | "--emit-loop-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .loopIrPsy }
  | "--emit-array-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .arrayIrPsy }
  | "--emit-struct-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .structIrPsy }
  | "--emit-struct-array-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .structArrayIrPsy }
  | "--emit-abi-aggregate-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .abiAggregateIrPsy }
  | "--emit-nested-aggregate-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .nestedAggregateIrPsy }
  | "--emit-storage-nested-aggregate-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .storageNestedAggregateIrPsy }
  | "--emit-u32-arithmetic-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .u32ArithmeticIrPsy }
  | "--emit-u32-hash-packing-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .u32HashPackingIrPsy }
  | "--emit-u32-storage-scalar-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .u32StorageScalarIrPsy }
  | "--emit-u32-storage-array-ir-psy" :: rest, opts =>
      parseArgs rest { opts with mode := .u32StorageArrayIrPsy }
  | "--emit-counter-ir-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrSbpf }
  | "--emit-value-vault-ir-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultIrSbpf }
  | "--emit-error-ref-ir-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .errorRefIrSbpf }
  | "--emit-control-ir-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .controlIrSbpf }
  | "--emit-solana-sdk-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSdkSbpf }
  | "--emit-solana-system-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSystemCpiSbpf }
  | "--emit-solana-system-create-account-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSystemCreateAccountCpiSbpf }
  | "--emit-solana-spl-token-transfer-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenTransferCpiSbpf }
  | "--emit-solana-spl-token-ops-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenOpsCpiSbpf }
  | "--emit-solana-spl-token-close-account-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenCloseAccountCpiSbpf }
  | "--emit-solana-spl-token-authority-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenAuthorityCpiSbpf }
  | "--emit-solana-associated-token-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaAssociatedTokenCpiSbpf }
  | "--emit-solana-spl-token-2022-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022CpiSbpf }
  | "--emit-solana-spl-token-2022-pausable-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022PausableCpiSbpf }
  | "--emit-solana-spl-token-2022-transfer-hook-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022TransferHookSbpf }
  | "--solana-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaElf }
  | "--value-vault-solana-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultSolanaElf }
  | "--solana-value-vault-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultSolanaElf }
  | "--solana-system-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSystemCpiElf }
  | "--solana-system-create-account-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSystemCreateAccountCpiElf }
  | "--solana-spl-token-transfer-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenTransferCpiElf }
  | "--solana-spl-token-ops-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenOpsCpiElf }
  | "--solana-spl-token-close-account-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenCloseAccountCpiElf }
  | "--solana-spl-token-authority-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplTokenAuthorityCpiElf }
  | "--solana-associated-token-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaAssociatedTokenCpiElf }
  | "--solana-spl-token-2022-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022CpiElf }
  | "--solana-spl-token-2022-pausable-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022PausableCpiElf }
  | "--solana-spl-token-2022-transfer-hook-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022TransferHookElf }
  | "--solana-log-event-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaLogEventElf }
  | "--solana-clock-sysvar-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaClockSysvarElf }
  | "--solana-rent-sysvar-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaRentSysvarElf }
  | "--solana-epoch-schedule-sysvar-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaEpochScheduleSysvarElf }
  | "--solana-epoch-rewards-sysvar-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaEpochRewardsSysvarElf }
  | "--solana-last-restart-slot-sysvar-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaLastRestartSlotSysvarElf }
  | "--solana-memory-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaMemoryElf }
  | "--solana-crypto-hash-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaCryptoHashElf }
  | "--solana-return-data-compute-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaReturnDataComputeElf }
  | "--emit-sbpf-asm" :: rest, opts =>
      parseArgs rest { opts with mode := .sbpfAsm }
  | "--emit-counter-ir-wasm-near" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrWasmNear }
  | "--emit-context-ir-wasm-near" :: rest, opts =>
      parseArgs rest { opts with mode := .contextIrWasmNear }
  | "--emit-hash-ir-wasm-near" :: rest, opts =>
      parseArgs rest { opts with mode := .hashIrWasmNear }
  | "--emit-map-ir-wasm-near" :: rest, opts =>
      parseArgs rest { opts with mode := .mapIrWasmNear }
  | "--emit-counter-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .counterEmitWat }
  | "--emit-error-ref-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .errorRefEmitWat }
  | "--emit-context-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .contextEmitWat }
  | "--emit-hash-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .hashEmitWat }
  | "--emit-map-emitwat" :: rest, opts =>
      parseArgs rest { opts with mode := .mapEmitWat }
  | "--emit-counter-ir-leo" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrLeo }
  | "--emit-pure-math-ir-leo" :: rest, opts =>
      parseArgs rest { opts with mode := .pureMathIrLeo }
  | "--emit-counter-ir-cosmwasm" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrCosmWasm }
  | "--emit-counter-ir-aptos" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrAptos }
  | "--emit-counter-ir-sui" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrSui }
  | "--emit-counter-ir-quint" :: rest, opts =>
      parseArgs rest { opts with mode := .counterIrQuint }
  | "--emit-value-vault-ir-quint" :: rest, opts =>
      parseArgs rest { opts with mode := .valueVaultIrQuint }
  | "--emit-ir-quint" :: rest, opts =>
      parseArgs rest { opts with mode := .irQuint }
  | "--emit-ir-quint-scenario" :: rest, opts =>
      parseArgs rest { opts with mode := .irQuintScenario }
  | "-h" :: _, _ =>
      .error usage
  | "--help" :: _, _ =>
      .error usage
  | arg :: rest, opts =>
      if arg.startsWith "-" then
        .error s!"unknown option: {arg}\n{usage}"
      else if opts.input?.isSome then
        .error s!"multiple input files provided\n{usage}"
      else
        parseArgs rest { opts with input? := some (FilePath.mk arg) }


end ProofForge.Cli
