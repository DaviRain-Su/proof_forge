import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.Psy.IR
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Client
import ProofForge.Contract.Client
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Learn
import ProofForge.Contract.Spec.Json
import ProofForge.Contract.Token.Evm
import ProofForge.Contract.Token.EvmSpec
import ProofForge.Contract.Token.EvmWrap
import ProofForge.Contract.Token.Learn
import ProofForge.Backend.WasmNear
import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.CosmWasm.EmitWat
import ProofForge.Backend.Move.Aptos
import ProofForge.Cli.ContractLoader
import ProofForge.Cli.Fixture
import ProofForge.Cli.Scaffold
import ProofForge.Compiler.TS.AST
import ProofForge.Compiler.TS.Printer
import ProofForge.Compiler.TS.Emit
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.AbiScalarProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.AssignmentProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.BoolStorageArrayProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.ControlFlowAssertProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.ErrorRefProbe
import ProofForge.IR.Examples.PureMath
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.EvmAbiAggregateProbe
import ProofForge.IR.Examples.EvmArrayValueProbe
import ProofForge.IR.Examples.EvmAssignOpProbe
import ProofForge.IR.Examples.EvmCrosscallProbe
import ProofForge.IR.Examples.EvmContextProbe
import ProofForge.IR.Examples.EvmExpressionProbe
import ProofForge.IR.Examples.EvmHashProbe
import ProofForge.IR.Examples.EvmLoopProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmStorageArrayProbe
import ProofForge.IR.Examples.EvmStorageStructProbe
import ProofForge.IR.Examples.EvmStructArrayValueProbe
import ProofForge.IR.Examples.EvmStructValueProbe
import ProofForge.IR.Examples.EvmTypedMapProbe
import ProofForge.IR.Examples.EvmTypedStorageProbe
import ProofForge.IR.Examples.ExpressionPredicateProbe
import ProofForge.IR.Examples.GenericEntrypointProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.NestedAggregateProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.StructArrayProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32HashPackingProbe
import ProofForge.IR.Examples.U32StorageArrayProbe
import ProofForge.IR.Examples.U32StorageScalarProbe
import ProofForge.Target
import ProofForge.Target.Check
import ProofForge.Solana.Examples.Vault
import ProofForge.Solana.Examples.SystemCpi
import ProofForge.Solana.Examples.SystemCreateAccountCpi
import ProofForge.Solana.Examples.SplTokenTransferCheckedCpi
import ProofForge.Solana.Examples.SplTokenOpsCpi
import ProofForge.Solana.Examples.SplTokenCloseAccountCpi
import ProofForge.Solana.Examples.SplTokenAuthorityCpi
import ProofForge.Solana.Examples.SplToken2022Cpi
import ProofForge.Solana.Examples.LogEvent
import ProofForge.Solana.Examples.Clock
import ProofForge.Solana.Examples.Rent
import ProofForge.Solana.Examples.EpochSchedule
import ProofForge.Solana.Examples.EpochRewards
import ProofForge.Solana.Examples.LastRestartSlot
import ProofForge.Solana.Examples.Memory
import ProofForge.Solana.Examples.Crypto
import ProofForge.Solana.Examples.ReturnDataCompute

open Lean
open System

namespace ProofForge.Cli

structure ConstructorParamSpec where
  name : String
  abiType : String
  deriving Repr, BEq

structure ConstructorValueSpec where
  name : String
  value : String
  deriving Repr

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
  | .counterIrAptos => true
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

inductive Command where
  | build
  | emit
  | check
  | init
  | listTargets
  | listFixtures
  deriving BEq, Inhabited, Repr

structure CliOptions where
  cmd : Command := .build
  input? : Option FilePath := none
  output? : Option FilePath := none
  root? : Option FilePath := none
  moduleName? : Option Name := none
  yulOutput? : Option FilePath := none
  artifactOutput? : Option FilePath := none
  solc : String := "solc"
  cast : String := "cast"
  evmChainProfile? : Option String := none
  evmConstructorArgsHex : String := ""
  evmConstructorArgsSource : String := "--evm-constructor-args-hex"
  evmConstructorParams : Array ConstructorParamSpec := #[]
  evmConstructorValues : Array ConstructorValueSpec := #[]
  solanaSbpfArch : String := "v3"
  targetId? : Option String := none
  fixture? : Option String := none
  format? : Option String := none
  mode : EmitMode := .yul
  fromNewSurface : Bool := false
  deriving Inhabited

def CliOptions.emitsEvmDeployManifest (opts : CliOptions) : Bool :=
  opts.mode.emitsEvmDeployManifest ||
    (opts.mode == .learnTarget && opts.targetId? == some ProofForge.Target.evm.id)

def EmitMode.acceptsTarget : EmitMode → Bool
  | .learnTarget
  | .learnTokenTarget
  | .counterEmitWat
  | .contextEmitWat
  | .hashEmitWat
  | .mapEmitWat
  | .contractSourceEmitWat => true
  | _ => false

def usage : String :=
  String.intercalate "\n" [
    "Usage:",
    "  proof-forge [--root DIR] [--module Mod.Name] [-o output.yul] input.lean",
    "  proof-forge --evm-bytecode [--root DIR] [--module Mod.Name] [--yul-output file] [--artifact-output file] [--evm-chain-profile id] [--evm-constructor-param name:type] [--evm-constructor-arg name=value] [--evm-constructor-args-hex hex] [-o output.bin] input.lean",
    "  proof-forge --emit-counter-ir-yul [-o output.yul]",
    "  proof-forge --emit-counter-ir-ts [-o output.ts]",
    "  proof-forge --emit-counter-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-value-vault-ir-yul [-o output.yul]",
    "  proof-forge --emit-value-vault-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --learn --target evm [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin] input.learn",
    "  proof-forge --learn --target solana-sbpf-asm [-o output.s] [--artifact-output file] input.learn",
    "  proof-forge --learn-target <target-id> [target options] input.learn",
    "  proof-forge --learn-token --target evm [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin] input.learn",
    "  proof-forge --learn-token --target solana-sbpf-asm [-o token-plan.json] input.learn",
    "  proof-forge --learn-yul [-o output.yul] input.learn",
    "  proof-forge --learn-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin] input.learn",
    "  proof-forge --learn-sbpf [-o output.s] [--artifact-output file] input.learn",
    "  proof-forge --emit-abi-scalar-ir-yul [-o output.yul]",
    "  proof-forge --emit-abi-scalar-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-assert-ir-yul [-o output.yul]",
    "  proof-forge --emit-assert-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-assignment-ir-yul [-o output.yul]",
    "  proof-forge --emit-assignment-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-assign-op-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-assign-op-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-conditional-ir-yul [-o output.yul]",
    "  proof-forge --emit-conditional-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-context-ir-yul [-o output.yul]",
    "  proof-forge --emit-context-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-event-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-event-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-crosscall-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-crosscall-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-expression-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-expression-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-hash-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-hash-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-loop-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-loop-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-map-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-map-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-storage-array-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-storage-array-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-storage-struct-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-storage-struct-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-typed-map-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-typed-map-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-typed-storage-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-typed-storage-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-array-value-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-array-value-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-struct-array-value-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-struct-array-value-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-struct-value-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-struct-value-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-evm-abi-aggregate-ir-yul [-o output.yul]",
    "  proof-forge --emit-evm-abi-aggregate-ir-bytecode [--solc solc] [--yul-output output.yul] [--artifact-output file] [-o output.bin]",
    "  proof-forge --emit-counter-ir-psy [-o output.psy]",
    "  proof-forge --emit-event-ir-psy [-o output.psy]",
    "  proof-forge --emit-crosscall-ir-psy [-o output.psy]",
    "  proof-forge --emit-expression-predicate-ir-psy [-o output.psy]",
    "  proof-forge --emit-generic-entrypoint-ir-psy [-o output.psy]",
    "  proof-forge --emit-arithmetic-ir-psy [-o output.psy]",
    "  proof-forge --emit-bitwise-ir-psy [-o output.psy]",
    "  proof-forge --emit-bool-storage-array-ir-psy [-o output.psy]",
    "  proof-forge --emit-bool-storage-scalar-ir-psy [-o output.psy]",
    "  proof-forge --emit-conditional-ir-psy [-o output.psy]",
    "  proof-forge --emit-context-ir-psy [-o output.psy]",
    "  proof-forge --emit-hash-ir-psy [-o output.psy]",
    "  proof-forge --emit-hash-storage-ir-psy [-o output.psy]",
    "  proof-forge --emit-map-ir-psy [-o output.psy]",
    "  proof-forge --emit-assert-ir-psy [-o output.psy]",
    "  proof-forge --emit-loop-ir-psy [-o output.psy]",
    "  proof-forge --emit-array-ir-psy [-o output.psy]",
    "  proof-forge --emit-struct-ir-psy [-o output.psy]",
    "  proof-forge --emit-struct-array-ir-psy [-o output.psy]",
    "  proof-forge --emit-abi-aggregate-ir-psy [-o output.psy]",
    "  proof-forge --emit-nested-aggregate-ir-psy [-o output.psy]",
    "  proof-forge --emit-storage-nested-aggregate-ir-psy [-o output.psy]",
    "  proof-forge --emit-u32-arithmetic-ir-psy [-o output.psy]",
    "  proof-forge --emit-u32-hash-packing-ir-psy [-o output.psy]",
    "  proof-forge --emit-u32-storage-scalar-ir-psy [-o output.psy]",
    "  proof-forge --emit-u32-storage-array-ir-psy [-o output.psy]",
    "  proof-forge --emit-counter-ir-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-value-vault-ir-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-control-ir-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-sdk-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-system-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-system-create-account-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-spl-token-transfer-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-spl-token-ops-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-spl-token-close-account-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-spl-token-authority-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-solana-spl-token-2022-cpi-sbpf [-o output.s] [--artifact-output file]",
    "  proof-forge --solana-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --value-vault-solana-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-system-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-system-create-account-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-spl-token-transfer-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-spl-token-ops-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-spl-token-close-account-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-spl-token-authority-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-spl-token-2022-cpi-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-log-event-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-clock-sysvar-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-rent-sysvar-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-epoch-schedule-sysvar-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-epoch-rewards-sysvar-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-last-restart-slot-sysvar-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-memory-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-crypto-hash-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --solana-return-data-compute-elf [-o output.so] [--artifact-output file] [--solana-sbpf-arch v0|v3]",
    "  proof-forge --emit-sbpf-asm [-o output.s] [--artifact-output file]",
    "  proof-forge --emit-counter-ir-wasm-near -o output-dir",
    "  proof-forge --emit-counter-emitwat [-o output-dir] [--target wasm-near|wasm-cosmwasm]",
    "  proof-forge --emit-context-emitwat [-o output-dir] [--target wasm-near|wasm-cosmwasm]",
    "  proof-forge --emit-hash-emitwat [-o output-dir] [--target wasm-near|wasm-cosmwasm]",
    "  proof-forge --emit-map-emitwat [-o output-dir] [--target wasm-near|wasm-cosmwasm]",
    "  proof-forge --emit-context-ir-wasm-near -o output-dir",
    "  proof-forge --emit-hash-ir-wasm-near -o output-dir",
    "  proof-forge --emit-map-ir-wasm-near -o output-dir",
    "  proof-forge --emit-counter-ir-leo [-o output.leo]",
    "  proof-forge --emit-counter-ir-cosmwasm [-o output.wat]   (CosmWasm Counter spike)",
    "  proof-forge --emit-counter-ir-aptos [-o output-dir]       (Aptos Move Counter spike)",
    "  proof-forge init [DIR] [--template portable-counter]",
    "",
    "EVM bytecode mode loads `spec : ContractSpec` from the Lean module and uses Foundry `cast sig` plus `solc --strict-assembly`.",
    "`--evm-chain-profile <id>` records deployment profile metadata in the EVM deploy manifest without broadcasting transactions.",
    "`--evm-constructor-param name:type` records static-word constructor ABI schema metadata for an ABI-encoded constructor args blob.",
    "`--evm-constructor-arg name=value` ABI-encodes one typed constructor value using the declared constructor schema.",
    "`--evm-constructor-args-hex <hex>` appends ABI-encoded constructor arguments to generated EVM initcode.",
    "IR fixture modes render hand-written portable IR fixtures to target source or bytecode."
  ]

def parseModuleName (s : String) : Name :=
  s.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if part.isEmpty then acc else acc.str part

def trimAsciiString (s : String) : String :=
  s.trimAscii.toString

def dropEndString (s : String) (n : Nat) : String :=
  (s.dropEnd n).toString

def stripHexPrefix (s : String) : String :=
  if s.startsWith "0x" || s.startsWith "0X" then (s.drop 2).toString else s

def lowerHexString (s : String) : String :=
  String.intercalate "" <| s.toList.map fun ch =>
    match ch with
    | 'A' => "a"
    | 'B' => "b"
    | 'C' => "c"
    | 'D' => "d"
    | 'E' => "e"
    | 'F' => "f"
    | _ => ch.toString

def leanBaseName (input : FilePath) : String :=
  let fileName := input.fileName.getD input.toString
  if fileName.endsWith ".lean" then
    dropEndString fileName ".lean".length
  else
    fileName

def siblingPath (input : FilePath) (fileName : String) : FilePath :=
  let child := FilePath.mk fileName
  match input.parent with
  | some parent => parent / child
  | none => child

def defaultYulOutput (input : FilePath) : FilePath :=
  siblingPath input s!".{leanBaseName input}.yul"

def isHexChar (c : Char) : Bool :=
  c.isDigit || "abcdefABCDEF".contains c

def isHexString (s : String) : Bool :=
  !s.isEmpty && s.all isHexChar

def repeatString : Nat → String → String
  | 0, _ => ""
  | n+1, s => s ++ repeatString n s

def hexDigit (value : Nat) : String :=
  match value with
  | 0 => "0"
  | 1 => "1"
  | 2 => "2"
  | 3 => "3"
  | 4 => "4"
  | 5 => "5"
  | 6 => "6"
  | 7 => "7"
  | 8 => "8"
  | 9 => "9"
  | 10 => "a"
  | 11 => "b"
  | 12 => "c"
  | 13 => "d"
  | 14 => "e"
  | _ => "f"

partial def natToHex (value : Nat) : String :=
  if value < 16 then
    hexDigit value
  else
    natToHex (value / 16) ++ hexDigit (value % 16)

def byteLimit : Nat → Nat
  | 0 => 1
  | n+1 => 256 * byteLimit n

def fixedHexBytes (byteCount value : Nat) : String :=
  let raw := natToHex value
  repeatString (byteCount * 2 - raw.length) "0" ++ raw

def normalizeConstructorArgsHex (value : String) : Except String String :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.isEmpty then
    .ok ""
  else if hex.length % 2 != 0 then
    .error "--evm-constructor-args-hex must have an even number of hex digits"
  else if !hex.all isHexChar then
    .error "--evm-constructor-args-hex must contain only hex digits"
  else
    .ok (lowerHexString hex)

def supportedConstructorAbiTypes : Array String :=
  #["uint256", "uint64", "uint32", "bool", "bytes32", "address", "string", "bytes", "uint256[]"]

def constructorParamIsDynamic (abiType : String) : Bool :=
  abiType == "string" || abiType == "bytes" || abiType == "uint256[]"

def constructorParamEncoding (abiType : String) : String :=
  match abiType with
  | "string" | "bytes" => "abi-dynamic-bytes"
  | "uint256[]" => "abi-dynamic-array"
  | _ => "abi-static-word"

def constructorAbiTypeSupported (abiType : String) : Bool :=
  supportedConstructorAbiTypes.contains abiType

def supportedConstructorAbiTypesMessage : String :=
  String.intercalate ", " supportedConstructorAbiTypes.toList

def parseConstructorParamSpec (s : String) : Except String ConstructorParamSpec := do
  match s.splitOn ":" with
  | [name, abiType] =>
      let name := trimAsciiString name
      let abiType := trimAsciiString abiType
      if name.isEmpty then
        .error s!"invalid constructor parameter spec '{s}': name is empty"
      else if abiType.isEmpty then
        .error s!"invalid constructor parameter spec '{s}': type is empty"
      else if !constructorAbiTypeSupported abiType then
        .error s!"unsupported constructor ABI type '{abiType}'; supported types: {supportedConstructorAbiTypesMessage}"
      else
        .ok { name := name, abiType := abiType }
  | _ =>
      .error s!"invalid constructor parameter spec '{s}', expected name:type"

def parseConstructorValueSpec (s : String) : Except String ConstructorValueSpec := do
  match s.splitOn "=" with
  | [name, value] =>
      let name := trimAsciiString name
      let value := trimAsciiString value
      if name.isEmpty then
        .error s!"invalid constructor argument spec '{s}': name is empty"
      else if value.isEmpty then
        .error s!"invalid constructor argument spec '{s}': value is empty"
      else
        .ok { name := name, value := value }
  | _ =>
      .error s!"invalid constructor argument spec '{s}', expected name=value"

def hexCharValue! : Char → Nat
  | '0' => 0
  | '1' => 1
  | '2' => 2
  | '3' => 3
  | '4' => 4
  | '5' => 5
  | '6' => 6
  | '7' => 7
  | '8' => 8
  | '9' => 9
  | 'a' | 'A' => 10
  | 'b' | 'B' => 11
  | 'c' | 'C' => 12
  | 'd' | 'D' => 13
  | 'e' | 'E' => 14
  | _ => 15

def parseHexNat (value name : String) : Except String Nat :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.isEmpty then
    .error s!"{name} must not be empty"
  else if !hex.all isHexChar then
    .error s!"{name} must contain only hex digits"
  else
    .ok (hex.toList.foldl (fun acc ch => acc * 16 + hexCharValue! ch) 0)

def parseUnsignedNat (value name : String) : Except String Nat :=
  let value := trimAsciiString value
  if value.startsWith "0x" || value.startsWith "0X" then
    parseHexNat value name
  else
    match value.toNat? with
    | some n => .ok n
    | none => .error s!"{name} must be an unsigned decimal integer or 0x-prefixed hex integer"

def normalizeExactHexBytes (value name : String) (bytes : Nat) : Except String String :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.length != bytes * 2 then
    .error s!"{name} must be exactly {bytes} byte(s)"
  else if !hex.all isHexChar then
    .error s!"{name} must contain only hex digits"
  else
    .ok (lowerHexString hex)

def encodeUintConstructorArg (name value : String) (bytes : Nat) : Except String String := do
  let n ← parseUnsignedNat value s!"constructor argument `{name}`"
  if n < byteLimit bytes then
    .ok (fixedHexBytes 32 n)
  else
    .error s!"constructor argument `{name}` does not fit in uint{bytes * 8}"

def encodeBoolConstructorArg (name value : String) : Except String String :=
  match trimAsciiString value with
  | "true" | "True" | "TRUE" | "1" => .ok (fixedHexBytes 32 1)
  | "false" | "False" | "FALSE" | "0" => .ok (fixedHexBytes 32 0)
  | _ => .error s!"constructor argument `{name}` must be true, false, 1, or 0"

def byteToHex (byte : UInt8) : String :=
  let value := byte.toNat
  hexDigit (value / 16) ++ hexDigit (value % 16)

def byteArrayToHex (bytes : ByteArray) : String := Id.run do
  let mut hex := ""
  for idx in [0:bytes.size] do
    hex := hex ++ byteToHex (bytes[idx]!)
  return hex

def padHexTo32ByteBoundary (hex : String) : String :=
  let byteCount := hex.length / 2
  let rem := byteCount % 32
  if rem == 0 then
    hex
  else
    hex ++ repeatString ((32 - rem) * 2) "0"

def encodeDynamicBytesTail (dataHex : String) (byteLen : Nat) : String :=
  fixedHexBytes 32 byteLen ++ padHexTo32ByteBoundary dataHex

def parseCommaSeparatedNatList (value name : String) : Except String (Array Nat) := do
  let trimmed := trimAsciiString value
  if trimmed.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  let mut nums : Array Nat := #[]
  for part in trimmed.splitOn "," do
    let part := trimAsciiString part
    if part.isEmpty then
      .error s!"constructor argument `{name}` must not contain empty elements"
    else
      let n ← parseUnsignedNat part s!"constructor argument `{name}` element"
      nums := nums.push n
  .ok nums

def encodeStringConstructorTail (name value : String) : Except String String := do
  let trimmed := trimAsciiString value
  if trimmed.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  let bytes := trimmed.toUTF8
  let dataHex := byteArrayToHex bytes
  .ok (encodeDynamicBytesTail dataHex bytes.size)

def encodeBytesConstructorTail (name value : String) : Except String String := do
  let hex ← normalizeConstructorArgsHex value
  if hex.isEmpty then
    .error s!"constructor argument `{name}` must not be empty"
  .ok (encodeDynamicBytesTail hex (hex.length / 2))

def encodeUint256ArrayConstructorTail (name value : String) : Except String String := do
  let nums ← parseCommaSeparatedNatList value name
  if !nums.all (fun n => n < byteLimit 32) then
    .error s!"constructor argument `{name}` element does not fit in uint256"
  else
    let countWord := fixedHexBytes 32 nums.size
    let elemWords := String.intercalate "" (nums.toList.map (fixedHexBytes 32))
    .ok (countWord ++ elemWords)

def encodeDynamicConstructorTail (param : ConstructorParamSpec) (value : String) : Except String String :=
  match param.abiType with
  | "string" => encodeStringConstructorTail param.name value
  | "bytes" => encodeBytesConstructorTail param.name value
  | "uint256[]" => encodeUint256ArrayConstructorTail param.name value
  | abiType => .error s!"unsupported dynamic constructor ABI type '{abiType}'"

def encodeStaticConstructorValue (param : ConstructorParamSpec) (value : String) : Except String String := do
  match param.abiType with
  | "uint256" => encodeUintConstructorArg param.name value 32
  | "uint64" => encodeUintConstructorArg param.name value 8
  | "uint32" => encodeUintConstructorArg param.name value 4
  | "bool" => encodeBoolConstructorArg param.name value
  | "bytes32" => normalizeExactHexBytes value s!"constructor argument `{param.name}`" 32
  | "address" =>
      let address ← normalizeExactHexBytes value s!"constructor argument `{param.name}`" 20
      .ok (repeatString 24 "0" ++ address)
  | abiType => .error s!"unsupported static constructor ABI type '{abiType}'"

def constructorParamExists (params : Array ConstructorParamSpec) (name : String) : Bool :=
  params.any (fun param => param.name == name)

def constructorValueCount (values : Array ConstructorValueSpec) (name : String) : Nat :=
  values.foldl (fun count value => if value.name == name then count + 1 else count) 0

def findConstructorValue? (values : Array ConstructorValueSpec) (name : String) : Option String :=
  values.foldl
    (fun found value =>
      match found with
      | some _ => found
      | none => if value.name == name then some value.value else none)
    none

def validateConstructorValues (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String Unit := do
  for value in values do
    if constructorValueCount values value.name > 1 then
      .error s!"duplicate --evm-constructor-arg for `{value.name}`"
    else
      pure ()

def validateConstructorValuesAgainstParams
    (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String Unit := do
  validateConstructorValues params values
  for value in values do
    if !constructorParamExists params value.name then
      .error s!"--evm-constructor-arg `{value.name}` has no matching --evm-constructor-param"
    else
      pure ()

def encodeConstructorValues (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Except String String := do
  if params.isEmpty then
    .error "--evm-constructor-arg requires at least one --evm-constructor-param"
  validateConstructorValuesAgainstParams params values
  let headWordCount := params.size
  let mut headWords : Array String := #[]
  let mut tailHex := ""
  let mut tailOffset := headWordCount * 32
  for param in params do
    match findConstructorValue? values param.name with
    | some value =>
        if constructorParamIsDynamic param.abiType then
          let tail ← encodeDynamicConstructorTail param value
          headWords := headWords.push (fixedHexBytes 32 tailOffset)
          tailHex := tailHex ++ tail
          tailOffset := tailOffset + tail.length / 2
        else
          let word ← encodeStaticConstructorValue param value
          headWords := headWords.push word
    | none =>
        .error s!"missing --evm-constructor-arg for constructor parameter `{param.name}`"
  .ok (String.intercalate "" headWords.toList ++ tailHex)

def constructorSchemaHasDynamic (params : Array ConstructorParamSpec) : Bool :=
  params.any (fun param => constructorParamIsDynamic param.abiType)

def validateConstructorSchemaAndArgs (params : Array ConstructorParamSpec) (constructorArgsHex : String) : Except String Unit := do
  let argsHex ← normalizeConstructorArgsHex constructorArgsHex
  if params.isEmpty then
    .ok ()
  else if argsHex.isEmpty then
    .ok ()
  else
    let actualBytes := argsHex.length / 2
    if constructorSchemaHasDynamic params then
      let minBytes := params.size * 32
      if actualBytes >= minBytes then
        .ok ()
      else
        .error s!"constructor ABI schema expects at least {minBytes} bytes ({params.size} ABI head word(s)), but constructor args have {actualBytes} byte(s)"
    else
      let expectedBytes := params.size * 32
      if actualBytes == expectedBytes then
        .ok ()
      else
        .error s!"constructor ABI schema expects {expectedBytes} bytes ({params.size} static-word parameter(s)), but constructor args have {actualBytes} byte(s)"

def mergeSpecConstructorParams
    (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) : CliOptions :=
  if spec.evmConstructorParams.isEmpty then
    opts
  else
    let specParams := spec.evmConstructorParams.map fun param =>
      { name := param.name, abiType := param.abiType }
    let extraParams := opts.evmConstructorParams.filter fun param =>
      !specParams.any (fun existing => existing.name == param.name)
    { opts with evmConstructorParams := specParams ++ extraParams }

def constructorValuesDeferSpecMerge
    (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Bool :=
  values.any (fun value => !constructorParamExists params value.name)

def constructorValuesReady (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Bool :=
  !values.isEmpty &&
    !constructorValuesDeferSpecMerge params values &&
    params.all (fun param => findConstructorValue? values param.name |>.isSome)

def finalizeConstructorOptions (opts : CliOptions) : Except String CliOptions := do
  let argsHex ← normalizeConstructorArgsHex opts.evmConstructorArgsHex
  if !opts.evmConstructorValues.isEmpty then
    if !argsHex.isEmpty then
      .error "--evm-constructor-arg cannot be combined with --evm-constructor-args-hex"
    else if constructorValuesDeferSpecMerge opts.evmConstructorParams opts.evmConstructorValues then
      validateConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      .ok opts
    else if constructorValuesReady opts.evmConstructorParams opts.evmConstructorValues then
      let encoded ← encodeConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      validateConstructorSchemaAndArgs opts.evmConstructorParams encoded
      .ok { opts with
        evmConstructorArgsHex := encoded,
        evmConstructorArgsSource := "--evm-constructor-arg"
      }
    else
      validateConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      .ok opts
  else
    validateConstructorSchemaAndArgs opts.evmConstructorParams argsHex
    .ok { opts with
      evmConstructorArgsHex := argsHex,
      evmConstructorArgsSource := "--evm-constructor-args-hex"
    }

def finalizeConstructorOptionsForSpec
    (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) : Except String CliOptions := do
  let merged := { (mergeSpecConstructorParams opts spec) with evmConstructorArgsHex := "" }
  if !merged.evmConstructorValues.isEmpty && constructorValuesDeferSpecMerge merged.evmConstructorParams merged.evmConstructorValues then
    validateConstructorValuesAgainstParams merged.evmConstructorParams merged.evmConstructorValues
  finalizeConstructorOptions merged

def runProcess (cmd : String) (args : Array String) (cwd? : Option FilePath := none) : IO String := do
  let output ← IO.Process.output { cmd := cmd, args := args, cwd := cwd? }
  if output.exitCode != 0 then
    let stderr := trimAsciiString output.stderr
    let detail := if stderr.isEmpty then trimAsciiString output.stdout else stderr
    throw <| IO.userError s!"{cmd} failed with exit code {output.exitCode}: {detail}"
  return output.stdout

def selectorFor (cast : String) (sig : String) : IO String := do
  let stdout ← runProcess cast #["sig", sig]
  let selector := stripHexPrefix (trimAsciiString stdout)
  if selector.length != 8 || !isHexString selector then
    throw <| IO.userError s!"cast returned invalid selector for {sig}: {trimAsciiString stdout}"
  return selector

def solcBytecode (solc : String) (yulFile : FilePath) : IO String := do
  let stdout ← runProcess solc #["--strict-assembly", yulFile.toString, "--bin"]
  for line in stdout.splitOn "\n" do
    let line := trimAsciiString line
    if isHexString line then
      return line
  throw <| IO.userError s!"solc did not emit bytecode for {yulFile}"

def solcVersion? (solc : String) : IO (Option String) := do
  try
    return some (trimAsciiString (← runProcess solc #["--version"]))
  catch _ =>
    return none

def fileDigestAndBytes (path : FilePath) : IO (String × Nat) := do
  let script := "import hashlib, pathlib, sys; data = pathlib.Path(sys.argv[1]).read_bytes(); print(hashlib.sha256(data).hexdigest(), len(data))"
  let stdout ← runProcess "python3" #["-c", script, path.toString]
  match (trimAsciiString stdout).splitOn " " with
  | [digest, byteCount] =>
      let some bytes := byteCount.toNat?
        | throw <| IO.userError s!"python3 returned invalid byte count for {path}: {byteCount}"
      return (digest, bytes)
  | _ =>
      throw <| IO.userError s!"python3 returned invalid digest output for {path}: {trimAsciiString stdout}"

def sha256HexBytes (hex : String) : IO String := do
  let script := "import hashlib, sys; print(hashlib.sha256(bytes.fromhex(sys.argv[1])).hexdigest())"
  let digest := trimAsciiString (← runProcess "python3" #["-c", script, hex])
  if digest.length == 64 && digest.all isHexChar then
    return digest
  else
    throw <| IO.userError s!"python3 returned invalid SHA-256 digest for constructor args: {digest}"

def jsonString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def jsonBool (value : Bool) : String :=
  if value then "true" else "false"

def jsonObject (fields : Array (String × String)) : String :=
  "{" ++ String.intercalate "," (fields.toList.map fun field => jsonString field.fst ++ ":" ++ field.snd) ++ "}"

def jsonArray (values : Array String) : String :=
  "[" ++ String.intercalate "," values.toList ++ "]"

def jsonStringArray (values : Array String) : String :=
  jsonArray (values.map jsonString)

def jsonStringOption : Option String → String
  | some value => jsonString value
  | none => "null"

def jsonNatOption : Option Nat → String
  | some value => toString value
  | none => "null"

def defaultArtifactOutput (bytecodeOutput : FilePath) : FilePath :=
  let fileName := FilePath.mk "proof-forge-artifact.json"
  match bytecodeOutput.parent with
  | some parent => parent / fileName
  | none => fileName

def defaultDeployManifestOutput (metadataOutput : FilePath) : FilePath :=
  let fileName := metadataOutput.fileName.getD metadataOutput.toString
  let deployName :=
    if fileName == "proof-forge-artifact.json" then
      "proof-forge-deploy.json"
    else if fileName.endsWith ".proof-forge-artifact.json" then
      s!"{dropEndString fileName ".proof-forge-artifact.json".length}.proof-forge-deploy.json"
    else
      s!"{fileName}.proof-forge-deploy.json"
  let deployFile := FilePath.mk deployName
  match metadataOutput.parent with
  | some parent => parent / deployFile
  | none => deployFile

def defaultInitCodeOutput (bytecodeOutput : FilePath) : FilePath :=
  bytecodeOutput.withExtension "init.bin"

def artifactEntryJson (path : FilePath) : IO String := do
  let (digest, bytes) ← fileDigestAndBytes path
  return jsonObject #[
    ("path", jsonString path.toString),
    ("sha256", jsonString digest),
    ("bytes", toString bytes)
  ]

def optionalArtifactEntryJson : Option FilePath → IO (Option String)
  | some path => do
      let artifact ← artifactEntryJson path
      return some artifact
  | none => return none

def dedupStrings (values : Array String) : Array String :=
  values.foldl (init := #[]) fun acc value =>
    if acc.contains value then acc else acc.push value

partial def pushByteWidthFrom (value width : Nat) : Option Nat :=
  if width > 32 then
    none
  else if value < byteLimit width then
    some width
  else
    pushByteWidthFrom value (width + 1)

def pushByteWidth (value : Nat) : Option Nat :=
  pushByteWidthFrom value 1

def pushDataHex (value : Nat) : Except String String := do
  let some width := pushByteWidth value
    | .error s!"EVM initcode value {value} is too large for PUSH32"
  .ok (fixedHexBytes 1 (0x5f + width) ++ fixedHexBytes width value)

partial def initCodeOffsetWidth (sizePushWidth offsetWidth : Nat) : Except String Nat := do
  let headerBytes := 9 + 2 * sizePushWidth + offsetWidth
  let some requiredWidth := pushByteWidth headerBytes
    | .error s!"EVM initcode header offset {headerBytes} is too large for PUSH32"
  if requiredWidth == offsetWidth then
    .ok offsetWidth
  else
    initCodeOffsetWidth sizePushWidth requiredWidth

def deploymentInitCodeHex (runtimeBytecode constructorArgsHex : String) : Except String String := do
  let runtime := stripHexPrefix (trimAsciiString runtimeBytecode)
  let constructorArgs ← normalizeConstructorArgsHex constructorArgsHex
  if runtime.isEmpty then
    .error "EVM runtime bytecode must be non-empty before initcode generation"
  else if runtime.length % 2 != 0 then
    .error "EVM runtime bytecode hex must have an even number of digits before initcode generation"
  else if !runtime.all isHexChar then
    .error "EVM runtime bytecode must contain only hex digits before initcode generation"
  else
    let runtimeBytes := runtime.length / 2
    let some sizePushWidth := pushByteWidth runtimeBytes
      | .error s!"EVM runtime bytecode length {runtimeBytes} is too large for PUSH32 initcode"
    let offsetWidth ← initCodeOffsetWidth sizePushWidth 1
    let headerBytes := 9 + 2 * sizePushWidth + offsetWidth
    let sizePush ← pushDataHex runtimeBytes
    let offsetPush ← pushDataHex headerBytes
    .ok (sizePush ++ offsetPush ++ "600039" ++ sizePush ++ "6000f3" ++ runtime ++ constructorArgs)

def writeEvmInitCode (bytecodeOutput : FilePath) (constructorArgsHex : String) : IO FilePath := do
  let runtimeBytecode ← IO.FS.readFile bytecodeOutput
  let initCode ←
    match deploymentInitCodeHex runtimeBytecode constructorArgsHex with
    | .ok initCode => pure initCode
    | .error msg => throw <| IO.userError msg
  let initCodeOutput := defaultInitCodeOutput bytecodeOutput
  if let some parent := initCodeOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile initCodeOutput (initCode ++ "\n")
  IO.println s!"wrote {initCodeOutput} ({initCode.length} hex chars)"
  return initCodeOutput

def moduleCapabilityIds (module : ProofForge.IR.Module) : Array String :=
  dedupStrings (module.capabilities.map fun capability => capability.id)

def valueTypeJson (type : ProofForge.IR.ValueType) : String :=
  jsonString type.name

def entrypointAbiScalarTypeName
    (context : String)
    (type : ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String String :=
  match evmAbiWord? with
  | some word => .ok word
  | none =>
      match type with
      | .u32 => .ok "uint32"
      | .u64 => .ok "uint256"
      | .bool => .ok "bool"
      | .hash => .ok "bytes32"
      | .unit | .fixedArray _ _ | .structType _ =>
          .error s!"{context} has unsupported EVM ABI word type `{type.name}`; entrypoint ABI words support U32, U64, Bool, or Hash"

partial def entrypointAbiType
    (module : ProofForge.IR.Module)
    (context : String)
    (type : ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String String := do
  match type with
  | .u32 | .u64 | .bool | .hash =>
      entrypointAbiScalarTypeName context type evmAbiWord?
  | .unit =>
      .error s!"{context} uses Unit; EVM entrypoint parameters and non-Unit returns must use U32, U64, Bool, Hash, fixed arrays, or flat structs"
  | .fixedArray elementType length => do
      if length == 0 then
        .error s!"{context} uses Array<{elementType.name},0>; EVM entrypoint ABI fixed arrays must have non-zero length"
      let elementAbiType ← entrypointAbiType module s!"{context} fixed-array element" elementType
      .ok s!"{elementAbiType}[{length}]"
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error s!"{context} uses unknown struct `{typeName}`"
      if decl.fields.isEmpty then
        .error s!"{context} uses empty struct `{typeName}`; EVM entrypoint ABI structs must have at least one field"
      let mut parts := #[]
      for field in decl.fields do
        parts := parts.push (← entrypointAbiScalarTypeName s!"{context} struct `{typeName}` field `{field.id}`" field.type)
      .ok ("(" ++ String.intercalate "," parts.toList ++ ")")

partial def entrypointAbiWordTypes
    (module : ProofForge.IR.Module)
    (context : String)
    (type : ProofForge.IR.ValueType) : Except String (Array String) := do
  match type with
  | .u32 | .u64 | .bool | .hash =>
      .ok #[← entrypointAbiScalarTypeName context type]
  | .unit =>
      .error s!"{context} uses Unit; EVM entrypoint ABI values must use U32, U64, Bool, Hash, fixed arrays, or flat structs"
  | .fixedArray elementType length => do
      if length == 0 then
        .error s!"{context} uses Array<{elementType.name},0>; EVM entrypoint ABI fixed arrays must have non-zero length"
      let elementWords ← entrypointAbiWordTypes module s!"{context} fixed-array element" elementType
      let mut words : Array String := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error s!"{context} uses unknown struct `{typeName}`"
      if decl.fields.isEmpty then
        .error s!"{context} uses empty struct `{typeName}`; EVM entrypoint ABI structs must have at least one field"
      let mut words : Array String := #[]
      for field in decl.fields do
        words := words.push (← entrypointAbiScalarTypeName s!"{context} struct `{typeName}` field `{field.id}`" field.type)
      .ok words

def entrypointAbiValueJson
    (name? : Option String)
    (type : ProofForge.IR.ValueType)
    (abiType : String)
    (wordTypes : Array String) : String :=
  let encoding :=
    if type == .unit then "none" else "abi-static-words"
  let nameFields :=
    match name? with
    | some name => #[("name", jsonString name)]
    | none => #[]
  jsonObject (nameFields ++ #[
    ("type", valueTypeJson type),
    ("irType", valueTypeJson type),
    ("abiType", jsonString abiType),
    ("encoding", jsonString encoding),
    ("wordTypes", jsonStringArray wordTypes),
    ("wordCount", toString wordTypes.size)
  ])

def entrypointParamJson
    (module : ProofForge.IR.Module)
    (entrypointName : String)
    (param : String × ProofForge.IR.ValueType)
    (evmAbiWord? : Option String := none) : Except String (String × Nat × String) := do
  let abiType ← entrypointAbiType module s!"entrypoint `{entrypointName}` parameter `{param.fst}`" param.snd evmAbiWord?
  let wordTypes ← entrypointAbiWordTypes module s!"entrypoint `{entrypointName}` parameter `{param.fst}`" param.snd
  .ok (abiType, wordTypes.size, entrypointAbiValueJson (some param.fst) param.snd abiType wordTypes)

def entrypointParamEvmAbiWord (entrypoint : ProofForge.IR.Entrypoint) (index : Nat) : Option String :=
  if h : index < entrypoint.paramEvmAbiWords.size then
    entrypoint.paramEvmAbiWords[index]
  else
    none

def entrypointReturnJson
    (module : ProofForge.IR.Module)
    (entrypointName : String)
    (type : ProofForge.IR.ValueType) : Except String (Nat × String) := do
  match type with
  | .unit =>
      .ok (0, entrypointAbiValueJson none type "void" #[])
  | _ => do
      let abiType ← entrypointAbiType module s!"entrypoint `{entrypointName}` return" type
      let wordTypes ← entrypointAbiWordTypes module s!"entrypoint `{entrypointName}` return" type
      .ok (wordTypes.size, entrypointAbiValueJson none type abiType wordTypes)

def entrypointSoliditySignature
    (module : ProofForge.IR.Module)
    (entrypoint : ProofForge.IR.Entrypoint) : Except String String := do
  let mut paramAbiTypes := #[]
  for h : idx in [0:entrypoint.params.size] do
    let param := entrypoint.params[idx]
    let abiType ← entrypointAbiType module s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" param.snd
      (entrypointParamEvmAbiWord entrypoint idx)
    paramAbiTypes := paramAbiTypes.push abiType
  .ok s!"{entrypoint.name}({String.intercalate "," paramAbiTypes.toList})"

def hydrateEvmSelectors (cast : String) (module : ProofForge.IR.Module) :
    IO ProofForge.IR.Module := do
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    let signature ←
      match entrypointSoliditySignature module entrypoint with
      | .ok signature => pure signature
      | .error msg => throw <| IO.userError msg
    let derived ← selectorFor cast signature
    match entrypoint.selector? with
    | some selector =>
        if selector.toLower != derived.toLower then
          throw <| IO.userError
            s!"entrypoint `{entrypoint.name}` selector `{selector}` does not match ABI signature `{signature}` selector `{derived}`"
        entrypoints := entrypoints.push entrypoint
    | none =>
        entrypoints := entrypoints.push { entrypoint with selector? := some derived }
  return { module with entrypoints := entrypoints }

def entrypointJson (module : ProofForge.IR.Module) (entrypoint : ProofForge.IR.Entrypoint) : Except String String := do
  let mut params := #[]
  let mut paramAbiTypes := #[]
  let mut calldataWords := 0
  for h : idx in [0:entrypoint.params.size] do
    let param := entrypoint.params[idx]
    let (abiType, wordCount, paramJson) ← entrypointParamJson module entrypoint.name param
      (entrypointParamEvmAbiWord entrypoint idx)
    params := params.push paramJson
    paramAbiTypes := paramAbiTypes.push abiType
    calldataWords := calldataWords + wordCount
  let (returnWords, returnValue) ← entrypointReturnJson module entrypoint.name entrypoint.returns
  let signature := s!"{entrypoint.name}({String.intercalate "," paramAbiTypes.toList})"
  let selectorValue :=
    match entrypoint.selector? with
    | some selector => jsonString selector
    | none => "null"
  .ok <| jsonObject #[
    ("name", jsonString entrypoint.name),
    ("selector", selectorValue),
    ("signature", jsonString signature),
    ("params", jsonArray params),
    ("returns", valueTypeJson entrypoint.returns),
    ("returnValue", returnValue),
    ("calldataWords", toString calldataWords),
    ("returnWords", toString returnWords)
  ]

structure EventAbiField where
  name : String
  irType : ProofForge.IR.ValueType
  abiType : String
  indexed : Bool
  wordTypes : Array String
  deriving BEq, Repr

structure EventAbi where
  name : String
  signature : String
  topic0 : String
  indexedFields : Array EventAbiField
  dataFields : Array EventAbiField
  deriving BEq, Repr

def lowerExceptString (result : Except ProofForge.Backend.Evm.IR.LowerError α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error err => .error err.render

def liftExceptString (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error msg => throw <| IO.userError msg

def eventAbiWordTypeName : ProofForge.IR.ValueType → Except String String
  | .u32 => .ok "uint32"
  | .u64 => .ok "uint64"
  | .bool => .ok "bool"
  | .hash => .ok "bytes32"
  | type => .error s!"event ABI word type must be scalar, got `{type.name}`"

def eventAbiField
    (module : ProofForge.IR.Module)
    (env : ProofForge.Backend.Evm.IR.TypeEnv)
    (eventName : String)
    (indexed : Bool)
    (field : String × ProofForge.IR.Expr) : Except String EventAbiField := do
  let irType ← lowerExceptString <|
    ProofForge.Backend.Evm.IR.inferExprType module env field.snd
  let abiType ← lowerExceptString <|
    ProofForge.Backend.Evm.IR.eventSignatureFieldType module eventName field.fst irType
  let wordTypes ← lowerExceptString <|
    ProofForge.Backend.Evm.IR.abiValueWordTypes module s!"event `{eventName}` field `{field.fst}`" irType
  let mut wordTypeNames : Array String := #[]
  for wordType in wordTypes do
    wordTypeNames := wordTypeNames.push (← eventAbiWordTypeName wordType)
  .ok {
    name := field.fst,
    irType := irType,
    abiType := abiType,
    indexed := indexed,
    wordTypes := wordTypeNames
  }

def eventAbiFieldJson (field : EventAbiField) : String :=
  let encoding :=
    if field.indexed then
      if field.wordTypes.size == 1 then
        "indexed-word"
      else
        "indexed-keccak256"
    else
      "abi-static-words"
  jsonObject #[
    ("name", jsonString field.name),
    ("type", jsonString field.abiType),
    ("irType", valueTypeJson field.irType),
    ("indexed", jsonBool field.indexed),
    ("encoding", jsonString encoding),
    ("wordTypes", jsonStringArray field.wordTypes),
    ("wordCount", toString field.wordTypes.size)
  ]

def eventFieldsWordCount (fields : Array EventAbiField) : Nat :=
  fields.foldl (fun count field => count + field.wordTypes.size) 0

def eventTopic0For (cast signature : String) : IO String := do
  let stdout ← runProcess cast #["keccak", signature]
  let topic := stripHexPrefix (trimAsciiString stdout)
  if topic.length == 64 && isHexString topic then
    return "0x" ++ lowerHexString topic
  else
    throw <| IO.userError s!"cast returned invalid event topic for {signature}: {trimAsciiString stdout}"

def eventAbi
    (cast : String)
    (module : ProofForge.IR.Module)
    (env : ProofForge.Backend.Evm.IR.TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : IO EventAbi := do
  let signature ← liftExceptString <| lowerExceptString <|
    ProofForge.Backend.Evm.IR.eventSignature module env name (indexedFields ++ dataFields)
  let topic0 ← eventTopic0For cast signature
  let indexed ← liftExceptString <| indexedFields.foldlM (init := #[]) fun acc field => do
    .ok (acc.push (← eventAbiField module env name true field))
  let data ← liftExceptString <| dataFields.foldlM (init := #[]) fun acc field => do
    .ok (acc.push (← eventAbiField module env name false field))
  return {
    name := name,
    signature := signature,
    topic0 := topic0,
    indexedFields := indexed,
    dataFields := data
  }

def eventAbiJson (event : EventAbi) : String :=
  jsonObject #[
    ("name", jsonString event.name),
    ("signature", jsonString event.signature),
    ("topic0", jsonString event.topic0),
    ("anonymous", "false"),
    ("indexedFields", jsonArray (event.indexedFields.map eventAbiFieldJson)),
    ("dataFields", jsonArray (event.dataFields.map eventAbiFieldJson)),
    ("topics", toString (event.indexedFields.size + 1)),
    ("dataWords", toString (eventFieldsWordCount event.dataFields))
  ]

def mergeEventAbis (left right : Array EventAbi) : Except String (Array EventAbi) :=
  right.foldlM (init := left) fun acc event => do
    match acc.find? (fun existing => existing.signature == event.signature) with
    | none => .ok (acc.push event)
    | some existing =>
        if existing == event then
          .ok acc
        else
          .error s!"conflicting EVM event ABI metadata for signature `{event.signature}`"

mutual
  partial def eventAbisInStatements
      (cast : String)
      (module : ProofForge.IR.Module)
      (env : ProofForge.Backend.Evm.IR.TypeEnv)
      (statements : Array ProofForge.IR.Statement) :
      IO (Array EventAbi × ProofForge.Backend.Evm.IR.TypeEnv) := do
    let mut events : Array EventAbi := #[]
    let mut currentEnv := env
    for statement in statements do
      let (statementEvents, nextEnv) ← eventAbisInStatement cast module currentEnv statement
      events ← liftExceptString <| mergeEventAbis events statementEvents
      currentEnv := nextEnv
    return (events, currentEnv)

  partial def eventAbisInStatement
      (cast : String)
      (module : ProofForge.IR.Module)
      (env : ProofForge.Backend.Evm.IR.TypeEnv) :
      ProofForge.IR.Statement → IO (Array EventAbi × ProofForge.Backend.Evm.IR.TypeEnv)
    | .letBind name type _ => do
        let nextEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env name type false
        return (#[], nextEnv)
    | .letMutBind name type _ => do
        let nextEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env name type true
        return (#[], nextEnv)
    | .assign _ _ | .assignOp _ _ _ | .assert _ _ _ | .assertEq _ _ _ _ | .return _
    | .release _ =>
        return (#[], env)
    | .effect (.eventEmit name fields) => do
        let event ← eventAbi cast module env name #[] fields
        return (#[event], env)
    | .effect (.eventEmitIndexed name indexedFields dataFields) => do
        let event ← eventAbi cast module env name indexedFields dataFields
        return (#[event], env)
    | .effect _ =>
        return (#[], env)
    | .ifElse _ thenBody elseBody => do
        let (thenEvents, _) ← eventAbisInStatements cast module env thenBody
        let (elseEvents, _) ← eventAbisInStatements cast module env elseBody
        let events ← liftExceptString <| mergeEventAbis thenEvents elseEvents
        return (events, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← liftExceptString <| lowerExceptString <|
          ProofForge.Backend.Evm.IR.addLocal env indexName .u32 false
        let (events, _) ← eventAbisInStatements cast module loopEnv body
        return (events, env)
end

def eventAbisForModule (cast : String) (module : ProofForge.IR.Module) : IO (Array EventAbi) := do
  let mut events : Array EventAbi := #[]
  for entrypoint in module.entrypoints do
    let (entrypointEvents, _) ←
      eventAbisInStatements cast module (ProofForge.Backend.Evm.IR.entrypointTypeEnv entrypoint) entrypoint.body
    events ← liftExceptString <| mergeEventAbis events entrypointEvents
  return events

def constructorParamJson (param : ConstructorParamSpec) : String :=
  let fields : Array (String × String) := #[
    ("name", jsonString param.name),
    ("type", jsonString param.abiType),
    ("encoding", jsonString (constructorParamEncoding param.abiType)),
    ("slotBytes", "32")
  ]
  let fields :=
    if param.abiType == "uint256[]" then
      fields.push ("elementType", jsonString "uint256")
    else
      fields
  jsonObject fields

def constructorAbiJson (params : Array ConstructorParamSpec) : String :=
  jsonObject #[
    ("params", jsonArray (params.map constructorParamJson)),
    ("encoding", jsonString "abi")
  ]

def targetMetadataJson (metadata : ProofForge.Target.TargetMetadata) : String :=
  jsonObject #[
    ("key", jsonString metadata.key),
    ("value", jsonString metadata.value)
  ]

def capabilityCallJson (call : ProofForge.Target.CapabilityCall) : String :=
  let sourceValue :=
    match call.source? with
    | some source => jsonString source
    | none => "null"
  jsonObject #[
    ("capability", jsonString call.capability.id),
    ("operation", jsonString call.operation),
    ("source", sourceValue),
    ("metadata", jsonArray (call.metadata.map targetMetadataJson))
  ]

def capabilityPlanJson (plan : ProofForge.Target.CapabilityPlan) : String :=
  jsonObject #[
    ("targetId", jsonString plan.targetId),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("calls", jsonArray (plan.calls.map capabilityCallJson)),
    ("metadata", jsonArray (plan.metadata.map targetMetadataJson))
  ]

def solanaExtensionAccountJson (account : ProofForge.Backend.Solana.Extension.AccountMeta) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer)
  ]

def solanaDeclaredAccountJson
    (account : ProofForge.Backend.Solana.Extension.DeclaredAccount) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("access", jsonString account.access),
    ("signer", jsonString account.signer),
    ("owner", jsonString account.owner)
  ]

def solanaPdaSeedJson (seed : ProofForge.Backend.Solana.Extension.PdaSeed) : String :=
  jsonObject #[
    ("kind", jsonString seed.kind.id),
    ("value", jsonString seed.value)
  ]

def solanaPdaJson (pda : ProofForge.Backend.Solana.Extension.PdaDerive) : String :=
  jsonObject #[
    ("name", jsonString pda.name),
    ("seeds", jsonStringArray pda.seedValues),
    ("typedSeeds", jsonArray (pda.effectiveSeeds.map solanaPdaSeedJson)),
    ("bump", match pda.bump? with | some bump => jsonString bump | none => "null"),
    ("account", match pda.account? with | some account => jsonString account | none => "null"),
    ("signer", jsonBool pda.signer)
  ]

def solanaCpiJson (cpi : ProofForge.Backend.Solana.Extension.CpiInvoke) : String :=
  jsonObject #[
    ("name", jsonString cpi.name),
    ("program", jsonString cpi.program),
    ("instruction", jsonString cpi.instruction),
    ("accounts", jsonArray (cpi.accounts.map solanaExtensionAccountJson)),
    ("signerSeeds", jsonStringArray cpi.signerSeeds),
    ("protocol", match cpi.protocol? with | some protocol => jsonString protocol | none => "null"),
    ("dataLayout", match cpi.dataLayout? with | some layout => jsonString layout | none => "null"),
    ("lamportsSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.lamports_source" with
      | some value => jsonString value
      | none => "null"),
    ("spaceSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.space_source" with
      | some value => jsonString value
      | none => "null"),
    ("ownerSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.owner" with
      | some value => jsonString value
      | none => "null"),
    ("amountSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.amount_source" with
      | some value => jsonString value
      | none => "null"),
    ("feeSource",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.fee_source" with
      | some value => jsonString value
      | none => "null"),
    ("decimals",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.decimals" with
      | some value => jsonString value
      | none => "null"),
    ("authorityType",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.authority_type" with
      | some value => jsonString value
      | none => "null"),
    ("newAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.new_authority" with
      | some value => jsonString value
      | none => "null"),
    ("transferFeeConfigAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.transfer_fee_config_authority" with
      | some value => jsonString value
      | none => "null"),
    ("withdrawWithheldAuthority",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.withdraw_withheld_authority" with
      | some value => jsonString value
      | none => "null"),
    ("transferFeeBasisPoints",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.transfer_fee_basis_points" with
      | some value => jsonString value
      | none => "null"),
    ("maximumFee",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.maximum_fee" with
      | some value => jsonString value
      | none => "null"),
    ("numTokenAccounts",
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.num_token_accounts" with
      | some value => jsonString value
      | none => "null"),
    ("signed", jsonBool cpi.signed)
  ]

def solanaAllocatorJson (allocator : ProofForge.Backend.Solana.Extension.RuntimeAllocator) : String :=
  let region := allocator.config.model.region
  jsonObject #[
    ("name", jsonString allocator.name),
    ("kind", jsonString allocator.kind),
    ("model", jsonString allocator.model),
    ("heapStart", jsonString allocator.heapStart),
    ("heapBytes", jsonString allocator.heapBytes),
    ("strategy", jsonString allocator.config.model.strategy.id),
    ("release", jsonString allocator.config.model.release.id),
    ("region", jsonObject #[
      ("base", jsonString (toString region.base)),
      ("size", jsonString allocator.heapBytes),
      ("growable", jsonString (toString region.growable))
    ])
  ]

def solanaPdaActionJson (action : ProofForge.Backend.Solana.Extension.PdaAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("pda", jsonString action.name)
  ]

def solanaCpiActionJson (action : ProofForge.Backend.Solana.Extension.CpiAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("cpi", jsonString action.name)
  ]

def solanaMemoryActionJson (action : ProofForge.Backend.Solana.Extension.MemoryAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("memory", jsonString action.name),
    ("op", jsonString action.op.id),
    ("bytes", toString action.bytes),
    ("dstState", match action.dstState? with | some state => jsonString state | none => "null"),
    ("srcState", match action.srcState? with | some state => jsonString state | none => "null"),
    ("lhsState", match action.lhsState? with | some state => jsonString state | none => "null"),
    ("rhsState", match action.rhsState? with | some state => jsonString state | none => "null"),
    ("resultState", match action.resultState? with | some state => jsonString state | none => "null"),
    ("value", match action.value? with | some value => toString value | none => "null")
  ]

def solanaCryptoHashActionJson
    (action : ProofForge.Backend.Solana.Extension.CryptoHashAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("crypto", jsonString action.name),
    ("op", jsonString action.op.id),
    ("inputState", jsonString action.inputState),
    ("bytes", toString action.bytes),
    ("outputStates", jsonArray (action.outputStates.map jsonString)),
    ("featureGated", jsonBool action.featureGated)
  ]

def solanaSysvarActionJson
    (action : ProofForge.Backend.Solana.Extension.SysvarReadAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("sysvar", jsonString action.name),
    ("kind", jsonString action.kind.id),
    ("field", jsonString action.field.id),
    ("outputState", jsonString action.outputState),
    ("featureGated", jsonBool (ProofForge.Backend.Solana.Extension.SysvarKind.featureGated action.kind))
  ]

def solanaReturnDataActionJson
    (action : ProofForge.Backend.Solana.Extension.ReturnDataAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("returnData", jsonString action.name),
    ("op", jsonString "set"),
    ("sourceState", jsonString action.sourceState),
    ("bytes", toString action.bytes)
  ]

def solanaReturnDataReadActionJson
    (action : ProofForge.Backend.Solana.Extension.ReturnDataReadAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("returnData", jsonString action.name),
    ("op", jsonString "get"),
    ("destinationState", jsonString action.destinationState),
    ("maxBytes", toString action.maxBytes),
    ("lengthState", match action.lengthState? with | some state => jsonString state | none => "null"),
    ("programIdStates", jsonArray (action.programIdStates.map jsonString))
  ]

def solanaComputeUnitsActionJson
    (action : ProofForge.Backend.Solana.Extension.ComputeUnitsAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("computeUnits", jsonString action.name),
    ("op", jsonString "remaining"),
    ("outputState", jsonString action.outputState),
    ("featureGated", jsonBool action.featureGated)
  ]

def solanaComputeUnitsLogActionJson
    (action : ProofForge.Backend.Solana.Extension.ComputeUnitsLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("computeUnits", jsonString action.name),
    ("op", jsonString "log_remaining")
  ]

def solanaPubkeyLogActionJson
    (action : ProofForge.Backend.Solana.Extension.PubkeyLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("log", jsonString action.name),
    ("op", jsonString "pubkey"),
    ("account", jsonString action.account)
  ]

def solanaDataLogActionJson
    (action : ProofForge.Backend.Solana.Extension.DataLogAction) : String :=
  jsonObject #[
    ("entrypoint", jsonString action.entrypoint),
    ("log", jsonString action.name),
    ("op", jsonString "data"),
    ("sourceState", jsonString action.sourceState),
    ("bytes", toString action.bytes)
  ]

def solanaInstructionAccountJson (account : ProofForge.Backend.Solana.Manifest.AccountEntry) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("index", toString account.index),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("owner", jsonString account.owner)
  ]

def solanaInstructionParamJson
    (param : ProofForge.Backend.Solana.Manifest.InstructionParamEntry) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.typeName),
    ("offset", toString param.offset),
    ("byteSize", toString param.byteSize),
    ("encoding", jsonString param.encoding)
  ]

def solanaInstructionJson (instruction : ProofForge.Backend.Solana.Manifest.InstructionEntry) : String :=
  jsonObject #[
    ("name", jsonString instruction.name),
    ("tag", toString instruction.tag),
    ("handler", jsonString instruction.handler),
    ("minDataLen", toString instruction.minDataLen),
    ("accounts", jsonArray (instruction.accounts.map solanaInstructionAccountJson)),
    ("params", jsonArray (instruction.params.map solanaInstructionParamJson))
  ]

def solanaInstructionsJson (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : String :=
  jsonArray ((ProofForge.Backend.Solana.Manifest.buildInstructionsWithPlan module plan).map solanaInstructionJson)

def solanaExtensionsJson (plan : ProofForge.Target.CapabilityPlan) : String :=
  let extensions := ProofForge.Backend.Solana.Extension.ProgramExtensions.fromPlan plan
  jsonObject #[
    ("accounts", jsonArray (extensions.accounts.map solanaDeclaredAccountJson)),
    ("allocators", jsonArray (extensions.allocators.map solanaAllocatorJson)),
    ("pdas", jsonArray (extensions.pdas.map solanaPdaJson)),
    ("cpis", jsonArray (extensions.cpis.map solanaCpiJson)),
    ("pdaActions", jsonArray (extensions.pdaActions.map solanaPdaActionJson)),
    ("cpiActions", jsonArray (extensions.cpiActions.map solanaCpiActionJson)),
    ("memoryActions", jsonArray (extensions.memoryActions.map solanaMemoryActionJson)),
    ("cryptoHashActions", jsonArray (extensions.cryptoHashActions.map solanaCryptoHashActionJson)),
    ("sysvarActions", jsonArray (extensions.sysvarActions.map solanaSysvarActionJson)),
    ("returnDataActions", jsonArray (extensions.returnDataActions.map solanaReturnDataActionJson)),
    ("returnDataReadActions", jsonArray (extensions.returnDataReadActions.map solanaReturnDataReadActionJson)),
    ("computeUnitsActions", jsonArray (extensions.computeUnitsActions.map solanaComputeUnitsActionJson)),
    ("computeUnitsLogActions", jsonArray (extensions.computeUnitsLogActions.map solanaComputeUnitsLogActionJson)),
    ("pubkeyLogActions", jsonArray (extensions.pubkeyLogActions.map solanaPubkeyLogActionJson)),
    ("dataLogActions", jsonArray (extensions.dataLogActions.map solanaDataLogActionJson))
  ]

def contractNameForFixture (fixture : String) : String :=
  if fixture.endsWith ".lean" then
    dropEndString fixture ".lean".length
  else if fixture.endsWith ".learn" then
    dropEndString fixture ".learn".length
  else
    fixture

def resolveEvmChainProfile? (profileId? : Option String) : IO (Option ProofForge.Target.EvmChainProfile) := do
  match profileId? with
  | none => return none
  | some profileId =>
      match ProofForge.Target.findEvmChainProfile? profileId with
      | some profile => return some profile
      | none =>
          let known := String.intercalate ", " ProofForge.Target.knownEvmChainProfileIds.toList
          throw <| IO.userError s!"unknown EVM chain profile `{profileId}`; known profiles: {known}"

def evmChainProfileJson (profile : ProofForge.Target.EvmChainProfile) : String :=
  jsonObject #[
    ("id", jsonString profile.id),
    ("targetId", jsonString profile.targetId),
    ("networkName", jsonString profile.networkName),
    ("chainId", toString profile.chainId),
    ("nativeCurrencySymbol", jsonString profile.nativeCurrencySymbol),
    ("rollupFamily", jsonStringOption profile.rollupFamily),
    ("dataAvailability", jsonStringOption profile.dataAvailability),
    ("rpcUrls", jsonStringArray profile.rpcUrls),
    ("websocketUrls", jsonStringArray profile.websocketUrls),
    ("sequencerUrls", jsonStringArray profile.sequencerUrls),
    ("blockExplorerUrl", jsonStringOption profile.blockExplorerUrl),
    ("verifier", jsonStringOption profile.verifier),
    ("verifierUrl", jsonStringOption profile.verifierUrl),
    ("notes", jsonStringArray profile.notes)
  ]

def evmChainProfileFieldJson (profile? : Option ProofForge.Target.EvmChainProfile) : String :=
  match profile? with
  | some profile => evmChainProfileJson profile
  | none => "null"

def constructorArgsJson (constructorArgsHex source : String) : IO String := do
  let normalized ←
    match normalizeConstructorArgsHex constructorArgsHex with
    | .ok hex => pure hex
    | .error msg => throw <| IO.userError msg
  if normalized.isEmpty then
    return jsonArray #[]
  else
    let digest ← sha256HexBytes normalized
    return jsonArray #[
      jsonObject #[
        ("encoding", jsonString "abi-encoded"),
        ("hex", jsonString s!"0x{normalized}"),
        ("bytes", toString (normalized.length / 2)),
        ("sha256", jsonString digest),
        ("source", jsonString source)
      ]
    ]

def evmDeploymentJson (profile? : Option ProofForge.Target.EvmChainProfile) : String :=
  let (profileId, chainId, networkName, rpcUrls, blockExplorerUrl, verifier, verifierUrl, reason) :=
    match profile? with
    | some profile =>
        (jsonString profile.id,
          toString profile.chainId,
          jsonString profile.networkName,
          jsonStringArray profile.rpcUrls,
          jsonStringOption profile.blockExplorerUrl,
          jsonStringOption profile.verifier,
          jsonStringOption profile.verifierUrl,
          jsonString "ProofForge emitted a chain-profile-aware deployment plan, but transaction signing and broadcast artifacts are not generated yet.")
    | none =>
        ("null",
          "null",
          "null",
          jsonArray #[],
          "null",
          "null",
          "null",
          jsonString "ProofForge EVM bytecode modes emit deployable initcode and runtime bytecode artifacts, but no EVM chain profile was selected and transaction broadcasting is not generated yet.")
  jsonObject #[
    ("profileId", profileId),
    ("chainId", chainId),
    ("networkName", networkName),
    ("rpcUrls", rpcUrls),
    ("blockExplorerUrl", blockExplorerUrl),
    ("verifier", verifier),
    ("verifierUrl", verifierUrl),
    ("address", "null"),
    ("broadcast", jsonString "not-generated"),
    ("broadcastArtifact", "null"),
    ("reason", reason),
    ("reference", jsonString "scripts/evm/foundry-smoke.sh")
  ]

def writeEvmDeployManifest
    (deployOutput : FilePath)
    (fixture sourceKind sourceModule : String)
    (capabilities : Array String)
    (entrypoints : Array String)
    (events : Array String)
    (methods : Array String)
    (chainProfile? : Option ProofForge.Target.EvmChainProfile)
    (constructorParams : Array ConstructorParamSpec)
    (sourceArtifact? : Option String)
    (yulArtifact bytecodeArtifact initCodeArtifact constructorArgs : String) : IO Unit := do
  let mut inputFields : Array (String × String) := #[
    ("yul", yulArtifact),
    ("bytecode", bytecodeArtifact),
    ("initCode", initCodeArtifact)
  ]
  if let some sourceArtifact := sourceArtifact? then
    inputFields := inputFields.push ("source", sourceArtifact)
  let manifest := jsonObject #[
    ("schemaVersion", "1"),
    ("kind", jsonString "proof-forge-evm-deploy-manifest"),
    ("target", jsonString "evm"),
    ("targetFamily", jsonString "evm"),
    ("artifactKind", jsonString "evm-initcode-deploy"),
    ("fixture", jsonString fixture),
    ("contractName", jsonString (contractNameForFixture fixture)),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString sourceModule),
    ("chainProfile", evmChainProfileFieldJson chainProfile?),
    ("capabilities", jsonStringArray (dedupStrings capabilities)),
    ("abi", jsonObject #[
      ("constructor", constructorAbiJson constructorParams),
      ("entrypoints", jsonArray entrypoints),
      ("events", jsonArray events),
      ("methods", jsonArray methods)
    ]),
    ("creation", jsonObject #[
      ("mode", jsonString "init-code"),
      ("constructorArgs", constructorArgs),
      ("initCode", initCodeArtifact),
      ("runtimeBytecode", bytecodeArtifact)
    ]),
    ("inputs", jsonObject inputFields),
    ("deployment", evmDeploymentJson chainProfile?)
  ]
  if let some parent := deployOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile deployOutput (manifest ++ "\n")

def writeEvmArtifactMetadata
    (opts : CliOptions)
    (fixture sourceKind sourceModule : String)
    (capabilities : Array String)
    (entrypoints : Array String)
    (events : Array String)
    (methods : Array String)
    (source? : Option FilePath)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[]) : IO Unit := do
  let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput bytecodeOutput)
  let deployOutput := defaultDeployManifestOutput metadataOutput
  let chainProfile? ← resolveEvmChainProfile? opts.evmChainProfile?
  let constructorArgs ← constructorArgsJson opts.evmConstructorArgsHex opts.evmConstructorArgsSource
  let initCodeOutput ← writeEvmInitCode bytecodeOutput opts.evmConstructorArgsHex
  let yulArtifact ← artifactEntryJson yulOutput
  let bytecodeArtifact ← artifactEntryJson bytecodeOutput
  let initCodeArtifact ← artifactEntryJson initCodeOutput
  let sourceArtifact? ← optionalArtifactEntryJson source?
  writeEvmDeployManifest
    deployOutput
    fixture
    sourceKind
    sourceModule
    capabilities
    entrypoints
    events
    methods
    chainProfile?
    opts.evmConstructorParams
    sourceArtifact?
    yulArtifact
    bytecodeArtifact
    initCodeArtifact
    constructorArgs
  let mut artifactFields : Array (String × String) := #[
    ("yul", yulArtifact),
    ("bytecode", bytecodeArtifact),
    ("initCode", initCodeArtifact),
    ("deployManifest", ← artifactEntryJson deployOutput)
  ]
  if let some sourceArtifact := sourceArtifact? then
    artifactFields := artifactFields.push ("source", sourceArtifact)
  for (name, artifact) in extraArtifacts do
    artifactFields := artifactFields.push (name, artifact)
  let solcVersionValue :=
    match (← solcVersion? opts.solc) with
    | some version => jsonString version
    | none => "null"
  let metadata := jsonObject #[
    ("schemaVersion", "1"),
    ("target", jsonString "evm"),
    ("targetFamily", jsonString "evm"),
    ("artifactKind", jsonString "evm-bytecode"),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString sourceModule),
    ("capabilities", jsonStringArray (dedupStrings capabilities)),
    ("toolchain", jsonObject #[
      ("solc", jsonObject #[
        ("path", jsonString opts.solc),
        ("version", solcVersionValue)
      ])
    ]),
    ("abi", jsonObject #[
      ("constructor", constructorAbiJson opts.evmConstructorParams),
      ("entrypoints", jsonArray entrypoints),
      ("events", jsonArray events),
      ("methods", jsonArray methods)
    ]),
    ("artifacts", jsonObject artifactFields),
    ("validation", jsonObject #[
      ("solcStrictAssembly", jsonString "passed"),
      ("bytecodeGeneration", jsonString "passed"),
      ("initCodeGeneration", jsonString "passed"),
      ("deployManifest", jsonString "passed")
    ])
  ]
  if let some parent := metadataOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile metadataOutput (metadata ++ "\n")
  IO.println s!"wrote {metadataOutput}"

def writeEvmModuleArtifactMetadata
    (opts : CliOptions)
    (fixture sourceKind sourceModule : String)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[]) : IO Unit := do
  let events ← eventAbisForModule opts.cast module
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    entrypoints := entrypoints.push (← liftExceptString (entrypointJson module entrypoint))
  writeEvmArtifactMetadata
    opts
    fixture
    sourceKind
    sourceModule
    (moduleCapabilityIds module)
    entrypoints
    (events.map eventAbiJson)
    #[]
    none
    yulOutput
    bytecodeOutput
    extraArtifacts

def writeEvmContractSdkClientArtifacts
    (spec : ProofForge.Contract.ContractSpec)
    (bytecodeOutput : FilePath)
    (artifactBaseName : String) : IO (FilePath × FilePath × String × String) := do
  let specOutput := siblingPath bytecodeOutput s!"{artifactBaseName}.contract-spec.json"
  let clientOutput := siblingPath bytecodeOutput ProofForge.Contract.Client.evmAbiWrapperPath
  if let some parent := specOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
  IO.println s!"wrote {specOutput}"
  if let some parent := clientOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile clientOutput (ProofForge.Contract.Client.renderEvmAbiWrapper spec artifactBaseName ++ "\n")
  IO.println s!"wrote {clientOutput}"
  let specArtifact ← artifactEntryJson specOutput
  let clientArtifact ← artifactEntryJson clientOutput
  return (specOutput, clientOutput, specArtifact, clientArtifact)

def writeEvmContractSdkArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (spec : ProofForge.Contract.ContractSpec)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath) : IO Unit := do
  let (_, _, specArtifact, clientArtifact) ←
    writeEvmContractSdkClientArtifacts spec bytecodeOutput fixture
  writeEvmModuleArtifactMetadata opts fixture "contract-sdk" sourceModule module yulOutput bytecodeOutput #[
    ("contractSpec", specArtifact),
    ("client", clientArtifact)
  ]

def writeEvmIrArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath)
    (extraArtifacts : Array (String × String) := #[]) : IO Unit :=
  writeEvmModuleArtifactMetadata opts fixture "portable-ir" sourceModule module yulOutput bytecodeOutput extraArtifacts

def writeEvmLearnArtifactMetadata
    (opts : CliOptions)
    (fixture sourceModule : String)
    (input : FilePath)
    (module : ProofForge.IR.Module)
    (yulOutput bytecodeOutput : FilePath) : IO Unit := do
  let events ← eventAbisForModule opts.cast module
  let mut entrypoints := #[]
  for entrypoint in module.entrypoints do
    entrypoints := entrypoints.push (← liftExceptString (entrypointJson module entrypoint))
  writeEvmArtifactMetadata
    opts
    fixture
    "learn-source"
    sourceModule
    (moduleCapabilityIds module)
    entrypoints
    (events.map eventAbiJson)
    #[]
    (some input)
    yulOutput
    bytecodeOutput

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
  | "--emit-solana-spl-token-2022-cpi-sbpf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022CpiSbpf }
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
  | "--solana-spl-token-2022-cpi-elf" :: rest, opts =>
      parseArgs rest { opts with mode := .solanaSplToken2022CpiElf }
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

structure NewCommandParseState where
  target? : Option String := none
  fixture? : Option String := none
  format? : Option String := none
  out? : Option String := none
  yulOut? : Option String := none
  artifactOut? : Option String := none
  root? : Option String := none
  module? : Option String := none
  solc : String := "solc"
  cast : String := "cast"
  evmChainProfile? : Option String := none
  evmConstructorParams : Array ConstructorParamSpec := #[]
  evmConstructorValues : Array ConstructorValueSpec := #[]
  evmConstructorArgsHex : String := ""
  solanaSbpfArch? : Option String := none
  token : Bool := false
  input? : Option String := none
  legacyPrefix : List String := []
  deriving Inhabited

def takeOption (args : List String) (name : String) : Except String (String × List String) :=
  match args with
  | value :: rest => .ok (value, rest)
  | [] => .error s!"{name} requires a value"

partial def parseNewOptions : List String → NewCommandParseState → Except String NewCommandParseState
  | [], state => .ok state
  | "--target" :: rest, state => do
      let (target, rest) ← takeOption rest "--target"
      parseNewOptions rest { state with target? := some target }
  | "--fixture" :: rest, state => do
      let (fixture, rest) ← takeOption rest "--fixture"
      parseNewOptions rest { state with fixture? := some fixture }
  | "--format" :: rest, state => do
      let (format, rest) ← takeOption rest "--format"
      parseNewOptions rest { state with format? := some format }
  | "-o" :: rest, state => do
      let (out, rest) ← takeOption rest "-o"
      parseNewOptions rest { state with out? := some out }
  | "--output" :: rest, state => do
      let (out, rest) ← takeOption rest "--output"
      parseNewOptions rest { state with out? := some out }
  | "--root" :: rest, state => do
      let (root, rest) ← takeOption rest "--root"
      parseNewOptions rest { state with root? := some root }
  | "--module" :: rest, state => do
      let (module, rest) ← takeOption rest "--module"
      parseNewOptions rest { state with module? := some module }
  | "--yul-output" :: rest, state => do
      let (path, rest) ← takeOption rest "--yul-output"
      parseNewOptions rest { state with yulOut? := some path }
  | "--artifact-output" :: rest, state => do
      let (path, rest) ← takeOption rest "--artifact-output"
      parseNewOptions rest { state with artifactOut? := some path }
  | "--solc" :: rest, state => do
      let (path, rest) ← takeOption rest "--solc"
      parseNewOptions rest { state with solc := path }
  | "--cast" :: rest, state => do
      let (path, rest) ← takeOption rest "--cast"
      parseNewOptions rest { state with cast := path }
  | "--evm-chain-profile" :: rest, state => do
      let (profile, rest) ← takeOption rest "--evm-chain-profile"
      parseNewOptions rest { state with evmChainProfile? := some profile }
  | "--evm-constructor-param" :: rest, state => do
      let (spec, rest) ← takeOption rest "--evm-constructor-param"
      match spec.splitOn ":" with
      | [name, abiType] =>
          parseNewOptions rest { state with evmConstructorParams := state.evmConstructorParams.push { name := name, abiType := abiType } }
      | _ => .error s!"invalid --evm-constructor-param '{spec}', expected name:type"
  | "--evm-constructor-arg" :: rest, state => do
      let (spec, rest) ← takeOption rest "--evm-constructor-arg"
      match spec.splitOn "=" with
      | [name, value] =>
          parseNewOptions rest { state with evmConstructorValues := state.evmConstructorValues.push { name := name, value := value } }
      | _ => .error s!"invalid --evm-constructor-arg '{spec}', expected name=value"
  | "--evm-constructor-args-hex" :: rest, state => do
      let (hex, rest) ← takeOption rest "--evm-constructor-args-hex"
      parseNewOptions rest { state with evmConstructorArgsHex := hex }
  | "--solana-sbpf-arch" :: rest, state => do
      let (arch, rest) ← takeOption rest "--solana-sbpf-arch"
      if arch == "v0" || arch == "v3" then
        parseNewOptions rest { state with solanaSbpfArch? := some arch }
      else
        .error s!"invalid --solana-sbpf-arch '{arch}', expected v0 or v3"
  | "--token" :: rest, state =>
      parseNewOptions rest { state with token := true }
  | arg :: rest, state =>
      if arg.startsWith "-" then
        .error s!"unknown option: {arg}\n{usage}"
      else if state.input?.isSome then
        .error s!"multiple input files provided\n{usage}"
      else
        parseNewOptions rest { state with input? := some arg }

def isLeanSourceFile (input? : Option String) : Bool :=
  match input? with
  | some path => path.endsWith ".lean"
  | none => false

def buildLegacyFlag (target : String) (input? : Option String) (fixture? : Option String := none) (format? : Option String := none) (token : Bool := false) : Except String String :=
  let isLearn := match input? with | some input => input.endsWith ".learn" | none => false
  let isLeanSource := isLeanSourceFile input?
  match target, isLearn, fixture?, format?, token with
  | "evm", true, _, some "yul", false => Except.ok "--learn-yul"
  | "evm", true, _, some "yul", true => Except.error "proof-forge build --target evm --token --format yul is not yet implemented"
  | "evm", true, _, some "bytecode", true => Except.ok "--learn-token"
  | "evm", true, _, some "bytecode", false => Except.ok "--learn"
  | "evm", true, _, none, true => Except.ok "--learn-token"
  | "evm", true, _, none, false => Except.ok "--learn"
  | "evm", false, _, _, _ => Except.ok "--evm-bytecode"
  | "wasm-near", true, _, _, _ =>
      Except.error "proof-forge build --target wasm-near from .learn source is not yet implemented"
  | "wasm-near", false, fixture?, format?, _ =>
      if isLeanSource then
        if format?.isSome && format? != some "wat" then
          Except.error s!"proof-forge build --target wasm-near does not support format '{format?.getD ""}'; use --format wat"
        else
          Except.ok "--contract-source-emitwat"
      else if input?.isSome then
        Except.error "proof-forge build --target wasm-near from Lean source is not yet implemented; use a .lean contract_source module"
      else
        if format?.isSome && format? != some "wat" then
          Except.error s!"proof-forge build --target wasm-near does not support format '{format?.getD ""}'; use --format wat"
        else
          let fixture := fixture?.getD "counter"
          if fixture == "counter" || fixture == "error-ref" || fixture == "context" || fixture == "hash" || fixture == "map" then
            Except.ok s!"--emit-{fixture}-emitwat"
          else
            Except.error s!"proof-forge build --target wasm-near --fixture {fixture} is not yet implemented"
  | "wasm-cosmwasm", true, _, _, _ =>
      Except.error "proof-forge build --target wasm-cosmwasm from .learn source is not yet implemented"
  | "wasm-cosmwasm", false, _, _, _ => Except.ok "--emit-counter-ir-cosmwasm"
  | "solana-sbpf-asm", true, _, _, true => Except.ok "--learn-token"
  | "solana-sbpf-asm", true, _, _, false => Except.ok "--learn"
  | "solana-sbpf-asm", false, _, _, _ =>
      if isLeanSource then
        Except.ok "--contract-source-sbpf"
      else if format? == some "s" || format?.isNone then
        Except.ok "--emit-counter-ir-sbpf"
      else
        Except.error s!"proof-forge build --target solana-sbpf-asm does not support format '{format?.getD ""}' without a Lean contract source input"
  | "psy-dpn", true, _, _, _ =>
      Except.error "proof-forge build --target psy-dpn from .learn source is not yet implemented"
  | "psy-dpn", false, _, _, _ => Except.ok "--emit-counter-ir-psy"
  | "aleo-leo", true, _, _, _ =>
      Except.error "proof-forge build --target aleo-leo from .learn source is not yet implemented"
  | "aleo-leo", false, _, _, _ => Except.ok "--emit-counter-ir-leo"
  | "move-aptos", true, _, _, _ =>
      Except.error "proof-forge build --target move-aptos from .learn source is not yet implemented"
  | "move-aptos", false, _, _, _ => Except.ok "--emit-counter-ir-aptos"
  | other, _, _, _, _ => Except.error s!"unknown target '{other}'"

def emitLegacyFlag (target fixture : String) (format? : Option String) : Except String String :=
  let format := format?.getD ""
  match target, fixture, format with
  | "evm", f, "yul" => Except.ok s!"--emit-{f}-ir-yul"
  | "evm", f, "bytecode" => Except.ok s!"--emit-{f}-ir-bytecode"
  | "solana-sbpf-asm", "counter", fmt =>
      if fmt == "elf" || fmt == "so" then
        Except.ok "--solana-elf"
      else
        Except.ok "--emit-counter-ir-sbpf"
  | "solana-sbpf-asm", "value-vault", fmt =>
      if fmt == "elf" || fmt == "so" then
        Except.ok "--value-vault-solana-elf"
      else
        Except.ok "--emit-value-vault-ir-sbpf"
  | "solana-sbpf-asm", "error-ref", _ => Except.ok "--emit-error-ref-ir-sbpf"
  | "solana-sbpf-asm", "control", _ => Except.ok "--emit-control-ir-sbpf"
  | "solana-sbpf-asm", "solana-sdk", _ => Except.ok "--emit-solana-sdk-sbpf"
  | "solana-sbpf-asm", "canned-entrypoint", _ => Except.ok "--emit-sbpf-asm"
  | "solana-sbpf-asm", f, fmt =>
      if f.startsWith "solana-" then
        if fmt == "s" then
          Except.error s!"emit --target solana-sbpf-asm --fixture {f} --format s is not yet mapped to a legacy flag; use --format elf"
        else
          Except.ok s!"--solana-{f.drop 7}-elf"
      else if f.startsWith "spl-token-" then
        if fmt == "s" || fmt == "" then
          Except.ok s!"--emit-solana-spl-token-{f.drop 10}-sbpf"
        else
          Except.ok s!"--solana-spl-token-{f.drop 10}-elf"
      else if f.startsWith "system-" then
        if fmt == "s" || fmt == "" then
          Except.ok s!"--emit-solana-system-{f.drop 7}-sbpf"
        else
          Except.ok s!"--solana-system-{f.drop 7}-elf"
      else if f == "log-event" then
        if fmt == "s" then
          Except.error s!"emit --target solana-sbpf-asm --fixture {f} --format s is not yet mapped to a legacy flag; use --format elf"
        else
          Except.ok "--solana-log-event-elf"
      else
        Except.error s!"emit --target solana-sbpf-asm --fixture {f} is not yet mapped to a legacy flag"
  | "wasm-near", f, "wat" =>
      if f == "counter" || f == "error-ref" || f == "context" || f == "hash" || f == "map" then
        Except.ok s!"--emit-{f}-emitwat"
      else
        Except.error s!"emit --target wasm-near --fixture {f} --format wat is not yet mapped to a legacy flag"
  | "wasm-near", f, _ =>
      if f == "counter" || f == "error-ref" || f == "context" || f == "hash" || f == "map" then
        Except.ok s!"--emit-{f}-ir-wasm-near"
      else
        Except.error s!"emit --target wasm-near --fixture {f} is not yet mapped"
  | "wasm-cosmwasm", "counter", _ => Except.ok "--emit-counter-ir-cosmwasm"
  | "wasm-cloudflare-workers", "counter", _ => Except.ok "--emit-counter-ir-ts"
  | "psy-dpn", f, _ =>
      if ProofForge.Cli.Fixture.supportsFormat "psy-dpn" f .psy then
        Except.ok s!"--emit-{f}-ir-psy"
      else
        Except.error s!"emit --target psy-dpn --fixture {f} is not yet mapped to a legacy flag"
  | "aleo-leo", "counter", _ => Except.ok "--emit-counter-ir-leo"
  | "aleo-leo", "pure-math", _ => Except.ok "--emit-pure-math-ir-leo"
  | "move-aptos", "counter", _ => Except.ok "--emit-counter-ir-aptos"
  | t, f, fmt =>
      Except.error s!"emit --target {t} --fixture {f} --format {fmt} is not yet mapped to a legacy flag"

def newCommandArgsToLegacy (args : List String) : Except String (List String) := do
  match args with
  | "build" :: rest => do
      let state ← parseNewOptions rest {}
      let target ← match state.target? with | some t => Except.ok t | none => Except.error "build requires --target <id>"
      let flag ← buildLegacyFlag target state.input? state.fixture? state.format? state.token
      let mut legacy := [flag]
      if let some out := state.out? then legacy := legacy ++ ["-o", out]
      if let some root := state.root? then legacy := legacy ++ ["--root", root]
      if let some modName := state.module? then legacy := legacy ++ ["--module", modName]
      if let some yul := state.yulOut? then legacy := legacy ++ ["--yul-output", yul]
      if let some artifact := state.artifactOut? then legacy := legacy ++ ["--artifact-output", artifact]
      if let some profile := state.evmChainProfile? then legacy := legacy ++ ["--evm-chain-profile", profile]
      for param in state.evmConstructorParams do
        legacy := legacy ++ ["--evm-constructor-param", s!"{param.name}:{param.abiType}"]
      for value in state.evmConstructorValues do
        legacy := legacy ++ ["--evm-constructor-arg", s!"{value.name}={value.value}"]
      if state.evmConstructorArgsHex != "" then
        legacy := legacy ++ ["--evm-constructor-args-hex", state.evmConstructorArgsHex]
      if flag == "--evm-bytecode" then
        legacy := legacy ++ ["--solc", state.solc, "--cast", state.cast]
      if flag == "--learn" || flag == "--learn-token" then
        legacy := legacy ++ ["--target", target]
      if target == "solana-sbpf-asm" then
        if let some arch := state.solanaSbpfArch? then
          legacy := legacy ++ ["--solana-sbpf-arch", arch]
      if let some input := state.input? then legacy := legacy ++ [input]
      Except.ok legacy
  | "emit" :: rest => do
      let state ← parseNewOptions rest {}
      let target ← match state.target? with | some t => Except.ok t | none => Except.error "emit requires --target <id>"
      let fixture ← match state.fixture? with | some f => Except.ok f | none => Except.error "emit requires --fixture <id>"
      let flag ← emitLegacyFlag target fixture state.format?
      let mut legacy := [flag]
      if let some out := state.out? then legacy := legacy ++ ["-o", out]
      if let some yul := state.yulOut? then legacy := legacy ++ ["--yul-output", yul]
      if let some artifact := state.artifactOut? then legacy := legacy ++ ["--artifact-output", artifact]
      if let some profile := state.evmChainProfile? then legacy := legacy ++ ["--evm-chain-profile", profile]
      if flag.endsWith "-bytecode" then
        legacy := legacy ++ ["--solc", state.solc, "--cast", state.cast]
      if target == "solana-sbpf-asm" then
        if let some arch := state.solanaSbpfArch? then
          legacy := legacy ++ ["--solana-sbpf-arch", arch]
      Except.ok legacy
  | "check" :: _ => Except.error "proof-forge check is not yet implemented"
  | _ => Except.error "expected build, emit, or check"

def emitWatFixtureModule? (fixtureId : String) : Option ProofForge.IR.Module :=
  match fixtureId with
  | "counter" => some ProofForge.IR.Examples.Counter.module
  | "error-ref" => some ProofForge.IR.Examples.ErrorRefProbe.module
  | "context" => some ProofForge.IR.Examples.ContextProbe.module
  | "hash" => some ProofForge.IR.Examples.HashProbe.module
  | "map" => some ProofForge.IR.Examples.MapProbe.emitWatModule
  | _ => none

def toolOnPath (tool : String) : IO Bool := do
  try
    let r ← IO.Process.output { cmd := "which", args := #[tool] }
    return r.exitCode == 0
  catch _ =>
    return false

unsafe def checkCommand (opts : CliOptions) : IO UInt32 := do
  let targetId ← match opts.targetId? with
    | some id => pure id
    | none => throw <| IO.userError "check requires --target <id>"
  let profile ← match ProofForge.Target.find? targetId with
    | some p => pure p
    | none => throw <| IO.userError s!"unknown target '{targetId}'\nknown targets: {String.intercalate ", " ProofForge.Target.knownIds.toList}"
  if let some fixtureId := opts.fixture? then
    if !ProofForge.Cli.Fixture.isValidId fixtureId then
      throw <| IO.userError s!"unknown fixture '{fixtureId}'\nknown fixtures: {ProofForge.Cli.Fixture.listIds}"
    let format ← match opts.format? with
      | some fmt =>
          match ProofForge.Cli.Fixture.parseFormat? fmt with
          | some f => pure f
          | none => throw <| IO.userError s!"unknown format '{fmt}'"
      | none =>
          match ProofForge.Cli.Fixture.defaultFormatFor targetId fixtureId with
          | some f => pure f
          | none => throw <| IO.userError s!"no default format for --target {targetId} --fixture {fixtureId}"
    if !ProofForge.Cli.Fixture.supportsFormat targetId fixtureId format then
      throw <| IO.userError s!"fixture '{fixtureId}' does not support format '{format.id}' for target '{targetId}'"
    if targetId == ProofForge.Target.wasmNear.id && format == .wat then
      let module ← match emitWatFixtureModule? fixtureId with
        | some module => pure module
        | none => throw <| IO.userError s!"fixture '{fixtureId}' is not mapped to the wasm-near EmitWat backend"
      match ProofForge.Backend.WasmNear.EmitWat.renderModule module with
      | .ok _ => pure ()
      | .error err => throw <| IO.userError err.message
    else
      let caps := ProofForge.Cli.Fixture.capabilitiesFor fixtureId
      match ProofForge.Target.requireCapabilities profile caps with
      | .ok _ => pure ()
      | .error err => throw <| IO.userError err.render
  for tool in profile.requiredTools do
    if !(← toolOnPath tool) then
      IO.eprintln s!"warning: required tool '{tool}' not found on PATH for target '{targetId}'"
  IO.println "check: ok"
  return 0

def writeTextFile (path : FilePath) (contents : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

def writeNearPackage (outputDir : FilePath) (pkg : ProofForge.Backend.WasmNear.IR.NearPackage) : IO Unit := do
  for file in pkg.files do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path file.content

/-! ### EmitWat output (canonical IR → WAT → wasm) -/

def emitWatEntrypointJson (entrypoint : ProofForge.IR.Entrypoint) : String :=
  jsonObject #[
    ("name", jsonString entrypoint.name),
    ("params", jsonArray (entrypoint.params.map fun param =>
      jsonObject #[
        ("name", jsonString param.fst),
        ("type", valueTypeJson param.snd)
      ])),
    ("returns", valueTypeJson entrypoint.returns)
  ]

def defaultEmitWatArtifactOutput (outputDir : FilePath) : FilePath :=
  outputDir / "proof-forge-artifact.json"

def emitWatTargetId (opts : CliOptions) : String :=
  opts.targetId?.getD ProofForge.Target.wasmNear.id

def emitWatDeployManifestKind (targetId : String) : String :=
  if targetId == ProofForge.Target.wasmNear.id then
    "proof-forge-wasm-near-deploy-manifest"
  else
    "proof-forge-wasm-host-deploy-manifest"

def optionalExistingArtifactEntryJson (path? : Option FilePath) : IO (Option String) := do
  match path? with
  | none => return none
  | some path =>
      if ← path.pathExists then
        return some (← artifactEntryJson path)
      else
        return none

def writeEmitWatDeployManifest
    (deployOutput : FilePath)
    (targetId fixture sourceKind : String)
    (module : ProofForge.IR.Module)
    (watArtifact : String)
    (wasmArtifact? : Option String) : IO Unit := do
  let mut artifactFields : Array (String × String) := #[("wat", watArtifact)]
  if let some wasmArtifact := wasmArtifact? then
    artifactFields := artifactFields.push ("wasm", wasmArtifact)
  let manifest := jsonObject #[
    ("schemaVersion", "1"),
    ("kind", jsonString (emitWatDeployManifestKind targetId)),
    ("target", jsonString targetId),
    ("targetFamily", jsonString "wasmHost"),
    ("artifactKind", jsonString "wasm-deploy"),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString module.name),
    ("capabilities", jsonStringArray (moduleCapabilityIds module)),
    ("abi", jsonObject #[
      ("entrypoints", jsonArray (module.entrypoints.map emitWatEntrypointJson))
    ]),
    ("artifacts", jsonObject artifactFields),
    ("deployment", jsonObject #[
      ("mode", jsonString "local-offline-host"),
      ("status", jsonString "not-broadcast"),
      ("localExecutor", jsonString "runtime/offline-host"),
      ("nearAccountId", "null"),
      ("nearSandbox", jsonString "not-generated"),
      ("note", jsonString "EmitWat target-first output is locally executable through runtime/offline-host; NEAR account deployment is not generated by this manifest.")
    ])
  ]
  if let some parent := deployOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile deployOutput (manifest ++ "\n")

def writeEmitWatArtifactMetadata
    (opts : CliOptions)
    (targetId fixture sourceKind : String)
    (module : ProofForge.IR.Module)
    (outputDir watPath : FilePath)
    (wasmPath? : Option FilePath) : IO Unit := do
  let metadataOutput := opts.artifactOutput?.getD (defaultEmitWatArtifactOutput outputDir)
  let deployOutput := defaultDeployManifestOutput metadataOutput
  let watArtifact ← artifactEntryJson watPath
  let wasmArtifact? ← optionalExistingArtifactEntryJson wasmPath?
  writeEmitWatDeployManifest deployOutput targetId fixture sourceKind module watArtifact wasmArtifact?
  let deployArtifact ← artifactEntryJson deployOutput
  let mut artifactFields : Array (String × String) := #[
    ("wat", watArtifact),
    ("deployManifest", deployArtifact)
  ]
  if let some wasmArtifact := wasmArtifact? then
    artifactFields := artifactFields.push ("wasm", wasmArtifact)
  let wat2wasmStatus := if wasmArtifact?.isSome then "passed" else "skipped"
  let metadata := jsonObject #[
    ("schemaVersion", "1"),
    ("target", jsonString targetId),
    ("targetFamily", jsonString "wasmHost"),
    ("artifactKind", jsonString "wasm"),
    ("fixture", jsonString fixture),
    ("sourceKind", jsonString sourceKind),
    ("irVersion", if sourceKind == "portable-ir" then jsonString "portable-ir-v0" else "null"),
    ("sourceModule", jsonString module.name),
    ("capabilities", jsonStringArray (moduleCapabilityIds module)),
    ("toolchain", jsonObject #[
      ("wat2wasm", jsonObject #[
        ("path", jsonString "wat2wasm"),
        ("version", "null")
      ])
    ]),
    ("abi", jsonObject #[
      ("entrypoints", jsonArray (module.entrypoints.map emitWatEntrypointJson))
    ]),
    ("artifacts", jsonObject artifactFields),
    ("validation", jsonObject #[
      ("emitWat", jsonString "passed"),
      ("watGeneration", jsonString "passed"),
      ("wat2wasm", jsonString wat2wasmStatus),
      ("deployManifest", jsonString "passed"),
      ("offlineHost", jsonString "pending")
    ])
  ]
  if let some parent := metadataOutput.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile metadataOutput (metadata ++ "\n")
  IO.println s!"wrote {metadataOutput}"

def writeWatPackage (outputDir : FilePath) (name : String) (wat : String) : IO (FilePath × Option FilePath) := do
  IO.FS.createDirAll outputDir
  let watPath := outputDir / s!"{name}.wat"
  IO.FS.writeFile watPath wat
  let wasmPath := outputDir / s!"{name}.wasm"
  try
    let r ← IO.Process.output { cmd := "wat2wasm", args := #[watPath.toString, "-o", wasmPath.toString] }
    if r.exitCode == 0 then
      IO.println s!"wrote EmitWat {name}.wat + {name}.wasm to {outputDir}"
      return (watPath, some wasmPath)
    else
      IO.eprintln s!"wat2wasm exit {r.exitCode}: {r.stderr.trimAscii} (WAT at {watPath})"
      return (watPath, none)
  catch _ =>
    IO.println s!"wrote EmitWat {name}.wat to {watPath} (wat2wasm unavailable; install wabt to build wasm)"
    return (watPath, none)

def compileEmitWat (opts : CliOptions) (name : String) (mod : ProofForge.IR.Module) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "emitwat mode requires -o output directory"
  let isCosmWasm := opts.targetId? == some ProofForge.Target.wasmCosmWasm.id
  let renderResult : Except String String :=
    if isCosmWasm then
      match ProofForge.Backend.CosmWasm.EmitWat.renderModule mod with
      | .ok wat => .ok wat
      | .error e => .error e.message
    else
      match ProofForge.Backend.WasmNear.EmitWat.renderModule mod with
      | .ok wat => .ok wat
      | .error e => .error e.message
  match renderResult with
  | .ok wat =>
      let (watPath, wasmPath?) ← writeWatPackage output name wat
      writeEmitWatArtifactMetadata opts (emitWatTargetId opts) name "portable-ir" mod output watPath wasmPath?
      return 0
  | .error msg =>
      throw <| IO.userError msg

def compileEmitWatWithPlan
    (opts : CliOptions)
    (name : String)
    (mod : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "emitwat mode requires -o output directory"
  match ProofForge.Backend.WasmNear.EmitWat.renderModuleWithPlan mod plan with
  | .ok wat =>
      let (watPath, wasmPath?) ← writeWatPackage output name wat
      writeEmitWatArtifactMetadata opts (emitWatTargetId opts) name "contract-sdk" mod output watPath wasmPath?
      return 0
  | .error err =>
      throw <| IO.userError err.message

def compileCounterEmitWat (opts : CliOptions) : IO UInt32 := compileEmitWat opts "counter" ProofForge.IR.Examples.Counter.module
def compileErrorRefEmitWat (opts : CliOptions) : IO UInt32 := compileEmitWat opts "error-ref" ProofForge.IR.Examples.ErrorRefProbe.module
def compileContextEmitWat  (opts : CliOptions) : IO UInt32 := compileEmitWat opts "context" ProofForge.IR.Examples.ContextProbe.module
def compileHashEmitWat     (opts : CliOptions) : IO UInt32 := compileEmitWat opts "hash" ProofForge.IR.Examples.HashProbe.module
def compileMapEmitWat      (opts : CliOptions) : IO UInt32 := compileEmitWat opts "map" ProofForge.IR.Examples.MapProbe.emitWatModule

def compileCounterIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileErrorRefIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderCounterIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileCounterIrTs (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ts/Counter.ts")
  match ProofForge.Compiler.TS.Emit.emitModule ProofForge.IR.Examples.Counter.module with
  | .ok tsModule =>
    let source := ProofForge.Compiler.TS.Printer.render tsModule
    writeTextFile output source
    IO.println s!"wrote {output}"
    return 0
  | .error msg =>
    IO.eprintln s!"compileCounterIrTs: {msg}"
    return 1

def compileCounterIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/Counter.yul")
  let yul ← renderCounterIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/Counter.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "Counter" "ProofForge.IR.Examples.Counter" ProofForge.IR.Examples.Counter.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def renderErrorRefIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileErrorRefIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ErrorRefProbe.yul")
  let yul ← renderErrorRefIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ErrorRefProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
  let (_, _, specArtifact, clientArtifact) ←
    writeEvmContractSdkClientArtifacts spec output "ErrorRefProbe"
  writeEvmIrArtifactMetadata opts "ErrorRefProbe" "ProofForge.IR.Examples.ErrorRefProbe"
    ProofForge.IR.Examples.ErrorRefProbe.module yulOutput output #[
    ("contractSpec", specArtifact),
    ("client", clientArtifact)
  ]
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileValueVaultIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Backend.Evm.IR.renderModule module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderValueVaultIrYul (opts : CliOptions) : IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast ProofForge.Contract.Examples.ValueVault.module
  match ProofForge.Backend.Evm.IR.renderModule module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def compileValueVaultIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ValueVault.yul")
  let (yul, module) ← renderValueVaultIrYul opts
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ValueVault.bin")
  writeTextFile output (bytecode ++ "\n")
  let spec := ProofForge.Contract.ContractSpec.fromIR module
  writeEvmContractSdkArtifactMetadata opts "ValueVault" "ProofForge.Contract.Examples.ValueVault"
    spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def learnInput (opts : CliOptions) (modeName : String) : IO FilePath := do
  match opts.input? with
  | some input => pure input
  | none => throw <| IO.userError s!"{modeName} requires an input .learn file"

def parseLearnInput (opts : CliOptions) (modeName : String) :
    IO (FilePath × ProofForge.Contract.ContractSpec) := do
  let input ← learnInput opts modeName
  match (← ProofForge.Contract.Learn.parseAndLowerFile input) with
  | .ok spec => pure (input, spec)
  | .error err => throw <| IO.userError s!"{input}: {err}"

def parseLearnTokenInput (opts : CliOptions) (modeName : String) :
    IO (FilePath × ProofForge.Contract.Token.Learn.TokenDecl) := do
  let input ← learnInput opts modeName
  match (← ProofForge.Contract.Token.Learn.parseFile input) with
  | .ok decl => pure (input, decl)
  | .error err => throw <| IO.userError s!"{input}: {err}"

def learnFixtureName (input : FilePath) : String :=
  input.fileName.getD input.toString

def learnSourceModuleName (input : FilePath) (spec : ProofForge.Contract.ContractSpec) : String :=
  s!"{spec.name} ({input})"

def defaultLearnOutput (subdir extension : String) (spec : ProofForge.Contract.ContractSpec) :
    FilePath :=
  FilePath.mk s!"build/{subdir}/{spec.name}.{extension}"

def defaultLearnTokenPlanOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile) : FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.{profile.id}.token-plan.json"

def defaultLearnTokenEvmYulOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl) :
    FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.erc20.yul"

def defaultLearnTokenEvmBytecodeOutput (decl : ProofForge.Contract.Token.Learn.TokenDecl) :
    FilePath :=
  FilePath.mk s!"build/learn/token/{decl.id}.erc20.bin"

def defaultLearnTokenArtifactOutput (bytecodeOutput : FilePath) : FilePath :=
  let fileName := FilePath.mk "proof-forge-token-artifact.json"
  match bytecodeOutput.parent with
  | some parent => parent / fileName
  | none => fileName

def targetProfileForMode (opts : CliOptions) (modeName : String) :
    IO ProofForge.Target.TargetProfile := do
  let some targetId := opts.targetId?
    | throw <| IO.userError s!"{modeName} requires --target <target-id>"
  match ProofForge.Target.find? targetId with
  | some profile => pure profile
  | none =>
      let known := String.intercalate ", " ProofForge.Target.knownIds.toList
      throw <| IO.userError s!"unknown {modeName} target `{targetId}`; known targets: {known}"

def learnTargetProfile (opts : CliOptions) : IO ProofForge.Target.TargetProfile :=
  targetProfileForMode opts "--learn"

def learnTokenTargetProfile (opts : CliOptions) : IO ProofForge.Target.TargetProfile :=
  targetProfileForMode opts "--learn-token"

def tokenFeatureIdsJson (spec : ProofForge.Contract.Token.TokenSpec) : String :=
  jsonStringArray (spec.features.map fun feature => feature.id)

def tokenSpecJson (decl : ProofForge.Contract.Token.Learn.TokenDecl) : String :=
  jsonObject #[
    ("id", jsonString decl.id),
    ("name", jsonString decl.spec.name),
    ("symbol", jsonString decl.spec.symbol),
    ("decimals", toString decl.spec.decimals),
    ("initialSupply", jsonNatOption decl.spec.initialSupply?),
    ("features", tokenFeatureIdsJson decl.spec)
  ]

def tokenSolanaAccountJson
    (account : ProofForge.Contract.Token.SolanaTokenAccountPlan) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("role", jsonString account.role),
    ("ownerProgram", jsonStringOption account.ownerProgram?),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("derivation", jsonStringOption account.derivation?)
  ]

def tokenSolanaInstructionParamJson
    (param : ProofForge.Contract.Token.SolanaTokenInstructionParam) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.type),
    ("source", jsonString param.source)
  ]

def tokenSolanaInstructionJson
    (instruction : ProofForge.Contract.Token.SolanaTokenInstructionPlan) : String :=
  jsonObject #[
    ("order", toString instruction.order),
    ("name", jsonString instruction.name),
    ("operation", jsonString instruction.operation),
    ("programId", jsonString instruction.programId),
    ("accounts", jsonStringArray instruction.accounts),
    ("params", jsonArray (instruction.params.map tokenSolanaInstructionParamJson)),
    ("feature", jsonStringOption instruction.feature?),
    ("token2022Only", jsonBool instruction.token2022Only)
  ]

def tokenSolanaExtensionJson
    (extension : ProofForge.Contract.Token.SolanaTokenExtensionPlan) : String :=
  jsonObject #[
    ("feature", jsonString extension.feature),
    ("extension", jsonString extension.extension),
    ("scope", jsonString extension.scope),
    ("initInstruction", jsonString extension.initInstruction),
    ("requiresConfig", jsonBool extension.requiresConfig),
    ("notes", jsonStringArray extension.notes)
  ]

def tokenSolanaAuthorityChangeJson
    (change : ProofForge.Contract.Token.SolanaTokenAuthorityChangePlan) : String :=
  jsonObject #[
    ("name", jsonString change.name),
    ("authorityType", jsonString change.authorityType),
    ("currentAuthority", jsonString change.currentAuthority),
    ("newAuthority", jsonString change.newAuthority),
    ("operation", jsonString change.operation),
    ("reason", jsonString change.reason)
  ]

def tokenSolanaReferenceJson
    (reference : ProofForge.Contract.Token.SolanaTokenReference) : String :=
  jsonObject #[
    ("label", jsonString reference.label),
    ("url", jsonString reference.url)
  ]

def tokenSolanaDeploymentPlanJson
    (deployment : ProofForge.Contract.Token.SolanaTokenDeploymentPlan) : String :=
  jsonObject #[
    ("standard", jsonString deployment.standard.id),
    ("programs", jsonObject #[
      ("token", jsonString deployment.tokenProgramId),
      ("associatedToken", jsonString deployment.associatedTokenProgramId),
      ("system", jsonString deployment.systemProgramId),
      ("rentSysvar", jsonString deployment.rentSysvarId)
    ]),
    ("accounts", jsonArray (deployment.accounts.map tokenSolanaAccountJson)),
    ("instructions", jsonArray (deployment.instructions.map tokenSolanaInstructionJson)),
    ("extensions", jsonArray (deployment.extensions.map tokenSolanaExtensionJson)),
    ("authorityChanges", jsonArray (deployment.authorityChanges.map tokenSolanaAuthorityChangeJson)),
    ("references", jsonArray (deployment.references.map tokenSolanaReferenceJson))
  ]

def tokenPlanJson (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact : String)
    (solanaDeployment? : Option ProofForge.Contract.Token.SolanaTokenDeploymentPlan := none) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-plan-v0"),
    ("sourceKind", jsonString "learn-token-source"),
    ("token", tokenSpecJson decl),
    ("target", jsonString profile.id),
    ("targetFamily", jsonString profile.family.id),
    ("standard", jsonString plan.standard.id),
    ("artifactKind", jsonString plan.artifactKind.id),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("operations", jsonStringArray plan.operations),
    ("notes", jsonStringArray plan.notes),
    ("solana", match solanaDeployment? with
      | some deployment => tokenSolanaDeploymentPlanJson deployment
      | none => "null"),
    ("artifacts", jsonObject #[
      ("source", sourceArtifact)
    ]),
    ("validation", jsonObject #[
      ("learnTokenParsing", jsonString "passed"),
      ("targetRouting", jsonString "passed"),
      ("planGeneration", jsonString "passed")
    ])
  ]

def tokenEntrypointReturnsAbi
    (module : ProofForge.IR.Module)
    (entrypoint : ProofForge.IR.Entrypoint) : Except String String :=
  match entrypoint.returns with
  | .unit => .ok "void"
  | _ =>
      entrypointAbiType module s!"entrypoint `{entrypoint.name}` return" entrypoint.returns

def tokenEvmEntrypointsJson (module : ProofForge.IR.Module) : Except String String := do
  let mut entries := #[]
  for entrypoint in module.entrypoints do
    let signature ← entrypointSoliditySignature module entrypoint
    let selector :=
      match entrypoint.selector? with
      | some value => value
      | none => ""
    let returnsAbi ← tokenEntrypointReturnsAbi module entrypoint
    entries := entries.push <| jsonObject #[
      ("name", jsonString entrypoint.name),
      ("selector", jsonString selector),
      ("signature", jsonString signature),
      ("returns", jsonString returnsAbi)
    ]
  pure (jsonArray entries)

def tokenEvmEventsJson (events : Array EventAbi) : String :=
  jsonArray (events.map fun event => jsonObject #[
    ("name", jsonString event.name),
    ("topic0", jsonString event.topic0),
    ("signature", jsonString event.signature)
  ])

def tokenEvmArtifactJson (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (profile : ProofForge.Target.TargetProfile)
    (plan : ProofForge.Contract.Token.TokenPlan)
    (sourceArtifact yulArtifact bytecodeArtifact entrypointsJson eventsJson : String) : String :=
  jsonObject #[
    ("format", jsonString "proof-forge-token-artifact-v0"),
    ("sourceKind", jsonString "learn-token-source"),
    ("token", tokenSpecJson decl),
    ("target", jsonString profile.id),
    ("targetFamily", jsonString profile.family.id),
    ("standard", jsonString plan.standard.id),
    ("artifactKind", jsonString plan.artifactKind.id),
    ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
    ("operations", jsonStringArray plan.operations),
    ("notes", jsonStringArray plan.notes),
    ("abi", jsonObject #[
      ("entrypoints", entrypointsJson),
      ("events", eventsJson)
    ]),
    ("artifacts", jsonObject #[
      ("source", sourceArtifact),
      ("yul", yulArtifact),
      ("bytecode", bytecodeArtifact)
    ]),
    ("validation", jsonObject #[
      ("learnTokenParsing", jsonString "passed"),
      ("targetRouting", jsonString "passed"),
      ("erc20IrLowering", jsonString "passed"),
      ("solcStrictAssembly", jsonString "passed")
    ])
  ]

def renderLearnEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) := do
  let module ← hydrateEvmSelectors opts.cast spec.module
  match ProofForge.Backend.Evm.IR.renderModule module with
  | .ok yul => return (yul, module)
  | .error err => throw <| IO.userError err.render

def renderContractSourceEvmYul (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) :
    IO (String × ProofForge.IR.Module) :=
  renderLearnEvmYul opts spec

unsafe def compileContractSourceEvmBytecode (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let opts ← match finalizeConstructorOptionsForSpec opts spec with
    | .ok opts => pure opts
    | .error msg => throw <| IO.userError msg
  let yulOutput := opts.yulOutput?.getD (defaultYulOutput input)
  let (yul, module) ← renderContractSourceEvmYul opts spec
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (input.withExtension "bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmContractSdkArtifactMetadata opts (leanBaseName input) spec.name spec module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

unsafe def compileContractSourceYul (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let output := opts.output?.getD (defaultYulOutput input)
  let (yul, _module) ← renderContractSourceEvmYul opts spec
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

def compileLearnYul (opts : CliOptions) : IO UInt32 := do
  let (_input, spec) ← parseLearnInput opts "--learn-yul"
  let output := opts.output?.getD (defaultLearnOutput "learn/evm" "yul" spec)
  let (yul, _module) ← renderLearnEvmYul opts spec
  writeTextFile output yul
  IO.println s!"wrote {output}"
  return 0

def compileLearnBytecode (opts : CliOptions) : IO UInt32 := do
  let (input, spec) ← parseLearnInput opts "--learn-bytecode"
  let yulOutput := opts.yulOutput?.getD (defaultLearnOutput "learn/evm" "yul" spec)
  let (yul, module) ← renderLearnEvmYul opts spec
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (defaultLearnOutput "learn/evm" "bin" spec)
  writeTextFile output (bytecode ++ "\n")
  writeEvmLearnArtifactMetadata opts (learnFixtureName input)
    (learnSourceModuleName input spec) input module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAbiScalarIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAbiScalarIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AbiScalarProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAbiScalarIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AbiScalarProbe.yul")
  let yul ← renderAbiScalarIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AbiScalarProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AbiScalarProbe" "ProofForge.IR.Examples.AbiScalarProbe" ProofForge.IR.Examples.AbiScalarProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssertIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssertIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AssertProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssertIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssertProbe.yul")
  let yul ← renderAssertIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssertProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssertProbe" "ProofForge.IR.Examples.AssertProbe" ProofForge.IR.Examples.AssertProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileAssignmentIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderAssignmentIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.AssignmentProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileAssignmentIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/AssignmentProbe.yul")
  let yul ← renderAssignmentIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/AssignmentProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "AssignmentProbe" "ProofForge.IR.Examples.AssignmentProbe" ProofForge.IR.Examples.AssignmentProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAssignOpIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAssignOpIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmAssignOpProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAssignOpIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.yul")
  let yul ← renderEvmAssignOpIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAssignOpProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAssignOpProbe" "ProofForge.IR.Examples.EvmAssignOpProbe" ProofForge.IR.Examples.EvmAssignOpProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileConditionalIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderConditionalIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileConditionalIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ConditionalProbe.yul")
  let yul ← renderConditionalIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ConditionalProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ConditionalProbe" "ProofForge.IR.Examples.ConditionalProbe" ProofForge.IR.Examples.ConditionalProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileContextIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderContextIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmContextProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileContextIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/ContextProbe.yul")
  let yul ← renderContextIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/ContextProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "ContextProbe" "ProofForge.IR.Examples.EvmContextProbe" ProofForge.IR.Examples.EvmContextProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmEventIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmEventIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EventProbe.evmModule with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmEventIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EventProbe.yul")
  let yul ← renderEvmEventIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EventProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EventProbe" "ProofForge.IR.Examples.EventProbe.evmModule" ProofForge.IR.Examples.EventProbe.evmModule yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmCrosscallIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmCrosscallIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmCrosscallProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmCrosscallIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.yul")
  let yul ← renderEvmCrosscallIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmCrosscallProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmCrosscallProbe" "ProofForge.IR.Examples.EvmCrosscallProbe" ProofForge.IR.Examples.EvmCrosscallProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmExpressionIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmExpressionIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmExpressionProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmExpressionIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmExpressionProbe.yul")
  let yul ← renderEvmExpressionIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmExpressionProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmExpressionProbe" "ProofForge.IR.Examples.EvmExpressionProbe" ProofForge.IR.Examples.EvmExpressionProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmHashIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmHashIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmHashProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmHashIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmHashProbe.yul")
  let yul ← renderEvmHashIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmHashProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmHashProbe" "ProofForge.IR.Examples.EvmHashProbe" ProofForge.IR.Examples.EvmHashProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmLoopIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmLoopIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmLoopProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmLoopIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmLoopProbe.yul")
  let yul ← renderEvmLoopIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmLoopProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmLoopProbe" "ProofForge.IR.Examples.EvmLoopProbe" ProofForge.IR.Examples.EvmLoopProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmMapIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmMapProbe.yul")
  let yul ← renderEvmMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmMapProbe" "ProofForge.IR.Examples.EvmMapProbe" ProofForge.IR.Examples.EvmMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageArrayIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageArrayIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStorageArrayProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageArrayIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.yul")
  let yul ← renderEvmStorageArrayIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageArrayProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageArrayProbe" "ProofForge.IR.Examples.EvmStorageArrayProbe" ProofForge.IR.Examples.EvmStorageArrayProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStorageStructIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStorageStructIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStorageStructProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStorageStructIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.yul")
  let yul ← renderEvmStorageStructIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStorageStructProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStorageStructProbe" "ProofForge.IR.Examples.EvmStorageStructProbe" ProofForge.IR.Examples.EvmStorageStructProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedMapIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedMapIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmTypedMapProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedMapIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.yul")
  let yul ← renderEvmTypedMapIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedMapProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedMapProbe" "ProofForge.IR.Examples.EvmTypedMapProbe" ProofForge.IR.Examples.EvmTypedMapProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmTypedStorageIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmTypedStorageIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmTypedStorageProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmTypedStorageIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.yul")
  let yul ← renderEvmTypedStorageIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmTypedStorageProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmTypedStorageProbe" "ProofForge.IR.Examples.EvmTypedStorageProbe" ProofForge.IR.Examples.EvmTypedStorageProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmArrayValueIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.yul")
  let yul ← renderEvmArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmArrayValueProbe" "ProofForge.IR.Examples.EvmArrayValueProbe" ProofForge.IR.Examples.EvmArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructArrayValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructArrayValueIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStructArrayValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructArrayValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.yul")
  let yul ← renderEvmStructArrayValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructArrayValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructArrayValueProbe" "ProofForge.IR.Examples.EvmStructArrayValueProbe" ProofForge.IR.Examples.EvmStructArrayValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmStructValueIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmStructValueIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmStructValueProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmStructValueIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmStructValueProbe.yul")
  let yul ← renderEvmStructValueIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmStructValueProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmStructValueProbe" "ProofForge.IR.Examples.EvmStructValueProbe" ProofForge.IR.Examples.EvmStructValueProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileEvmAbiAggregateIrYul (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul =>
      writeTextFile output yul
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def renderEvmAbiAggregateIrYul : IO String := do
  match ProofForge.Backend.Evm.IR.renderModule ProofForge.IR.Examples.EvmAbiAggregateProbe.module with
  | .ok yul => return yul
  | .error err => throw <| IO.userError err.render

def compileEvmAbiAggregateIrBytecode (opts : CliOptions) : IO UInt32 := do
  let yulOutput := opts.yulOutput?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.yul")
  let yul ← renderEvmAbiAggregateIrYul
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (FilePath.mk "build/ir/EvmAbiAggregateProbe.bin")
  writeTextFile output (bytecode ++ "\n")
  writeEvmIrArtifactMetadata opts "EvmAbiAggregateProbe" "ProofForge.IR.Examples.EvmAbiAggregateProbe" ProofForge.IR.Examples.EvmAbiAggregateProbe.module yulOutput output
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  return 0

def compileCounterIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/Counter.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileEventIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/EventProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.EventProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCrosscallIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/CrosscallProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.CrosscallProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileExpressionPredicateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ExpressionPredicateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ExpressionPredicateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileGenericEntrypointIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/GenericEntrypointProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.GenericEntrypointProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBitwiseIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BitwiseProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BitwiseProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileBoolStorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/BoolStorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.BoolStorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileConditionalIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ConditionalProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ConditionalProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ContextProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ContextProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashStorageIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/HashStorageProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.HashStorageProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/MapProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.MapProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAssertIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AssertProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AssertProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileLoopIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/LoopProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.LoopProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/ArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.ArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStructArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StructArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StructArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileAbiAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/AbiAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.AbiAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/NestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.NestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileStorageNestedAggregateIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/StorageNestedAggregateProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.StorageNestedAggregateProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32ArithmeticIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32ArithmeticProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32ArithmeticProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32HashPackingIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32HashPackingProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32HashPackingProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageScalarIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageScalarProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageScalarProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileU32StorageArrayIrPsy (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/psy/U32StorageArrayProbe.psy")
  match ProofForge.Backend.Psy.IR.renderModule ProofForge.IR.Examples.U32StorageArrayProbe.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
def compileCounterIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near Counter package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileContextIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.ContextProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near ContextProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileHashIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.HashProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near HashProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileMapIrWasmNear (opts : CliOptions) : IO UInt32 := do
  let some output := opts.output?
    | throw <| IO.userError "wasm-near package emit mode requires -o output directory"
  match ProofForge.Backend.WasmNear.IR.renderPackage ProofForge.IR.Examples.MapProbe.module with
  | .ok pkg =>
      writeNearPackage output pkg
      IO.println s!"wrote wasm-near MapProbe package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

/-- Write the Solana instruction manifest.toml alongside the emitted .s file.
Returns the path that was written. -/
def writeSbpfManifest (output : FilePath) (module : ProofForge.IR.Module) : IO FilePath := do
  let manifestOutput := match output.parent with
    | some parent => parent / "manifest.toml"
    | none => FilePath.mk "manifest.toml"
  let manifest := ProofForge.Backend.Solana.Manifest.renderManifest module
  IO.FS.writeFile manifestOutput (manifest ++ "\n")
  return manifestOutput

def writeSbpfManifestWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let manifestOutput := match output.parent with
    | some parent => parent / "manifest.toml"
    | none => FilePath.mk "manifest.toml"
  let manifest := ProofForge.Backend.Solana.Manifest.renderManifestWithPlan module plan
  IO.FS.writeFile manifestOutput (manifest ++ "\n")
  return manifestOutput

def writeSbpfIdlWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let idlOutput := match output.parent with
    | some parent => parent / ProofForge.Backend.Solana.Idl.idlPath
    | none => FilePath.mk ProofForge.Backend.Solana.Idl.idlPath
  let idl := ProofForge.Backend.Solana.Idl.renderWithPlan module plan
  IO.FS.writeFile idlOutput (idl ++ "\n")
  return idlOutput

def writeSbpfClientWithPlan (output : FilePath) (module : ProofForge.IR.Module)
    (plan : ProofForge.Target.CapabilityPlan) : IO FilePath := do
  let clientOutput := match output.parent with
    | some parent => parent / ProofForge.Backend.Solana.Client.clientPath
    | none => FilePath.mk ProofForge.Backend.Solana.Client.clientPath
  let client := ProofForge.Backend.Solana.Client.renderWithPlan module plan
  IO.FS.writeFile clientOutput (client ++ "\n")
  return clientOutput

def packagePath (root : FilePath) (rel : String) : FilePath :=
  rel.splitOn "/" |>.foldl (init := root) fun acc part =>
    if part.isEmpty then acc else acc / part

def compileCounterIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/Counter.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.Counter.module
      IO.println s!"wrote {manifestOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "counter-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileErrorRefIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ErrorRefProbe.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.ErrorRefProbe.module
      IO.println s!"wrote {manifestOutput}"
      let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
      let specOutput := match output.parent with
        | some parent => parent / "ErrorRefProbe.contract-spec.json"
        | none => FilePath.mk "ErrorRefProbe.contract-spec.json"
      writeTextFile specOutput (ProofForge.Contract.Spec.Json.render spec ++ "\n")
      IO.println s!"wrote {specOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "error-ref-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "ErrorRefProbe"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "assertions.check"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileControlIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ControlFlowAssertProbe.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderModule ProofForge.IR.Examples.ControlFlowAssertProbe.module with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifest output ProofForge.IR.Examples.ControlFlowAssertProbe.module
      IO.println s!"wrote {manifestOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "control-ir-sbpf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "ControlFlowAssertProbe"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional", "assertions.check"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed"),
          ("molluskRuntime", jsonObject #[
            ("lifecycle", jsonString "pending"),
            ("guardedIncrementSuccess", jsonString "pending"),
            ("guardedIncrementRevert", jsonString "pending"),
            ("equalityGuardSuccess", jsonString "pending"),
            ("equalityGuardRevert", jsonString "pending")
          ])
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSdkSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/SolanaVault.s")
  let spec := ProofForge.Solana.Examples.Vault.spec
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "solana-sdk-vault-sbpf"),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending"),
          ("cpiLowering", jsonString "helper-emitted"),
          ("pdaLowering", jsonString "helper-emitted")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileValueVaultIrSbpf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/ValueVault.s")
  let spec := ProofForge.Contract.Examples.ValueVault.spec
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "value-vault-ir-sbpf"),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileLearnSbpf (opts : CliOptions) : IO UInt32 := do
  let (input, spec) ← parseLearnInput opts "--learn-sbpf"
  let output := opts.output?.getD (defaultLearnOutput "learn/solana" "s" spec)
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let asmArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let learnArtifact ← artifactEntryJson input
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString (learnFixtureName input)),
        ("sourceKind", jsonString "learn-source"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString (learnSourceModuleName input spec)),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("source", learnArtifact),
          ("sbpfAsm", asmArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("learnLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

unsafe def compileContractSourceSbpf (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let output := opts.output?.getD (siblingPath input s!".{leanBaseName input}.s")
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let sourceArtifactEntry ← artifactEntryJson input
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString (leanBaseName input)),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("source", sourceArtifactEntry),
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("contractSourceLowering", jsonString "passed"),
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

unsafe def compileContractSourceEmitWat (opts : CliOptions) : IO UInt32 := do
  let some input := opts.input?
    | IO.eprintln usage
      return 1
  let spec ← ProofForge.Cli.ContractLoader.loadSpec input opts.root? opts.moduleName?
  let fixtureSlug := spec.name.toLower
  let outputDir ← match opts.output? with
    | some out =>
        if out.extension == "wat" then
          pure <| match out.parent with | some parent => parent | none => FilePath.mk "."
        else
          pure out
    | none =>
        throw <| IO.userError "contract source EmitWat build requires -o output directory (or .wat path)"
  let opts' := { opts with
    output? := some outputDir
    targetId? := opts.targetId? <|> some ProofForge.Target.wasmNear.id
  }
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.wasmNear spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  compileEmitWatWithPlan opts' fixtureSlug spec.module plan

def compileLearnTarget (opts : CliOptions) : IO UInt32 := do
  let profile ← learnTargetProfile opts
  if profile.id == ProofForge.Target.evm.id then
    compileLearnBytecode opts
  else if profile.id == ProofForge.Target.solanaSbpfAsm.id then
    compileLearnSbpf opts
  else
    throw <| IO.userError
      s!"Learn target emission for `{profile.id}` is not implemented yet; currently implemented targets: evm, solana-sbpf-asm"

def compileLearnTokenEvm (opts : CliOptions)
    (profile : ProofForge.Target.TargetProfile)
    (input : FilePath)
    (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (plan : ProofForge.Contract.Token.TokenPlan) : IO UInt32 := do
  let spec := ProofForge.Contract.Token.EvmSpec.specFor decl.spec
  let module ← hydrateEvmSelectors opts.cast spec.module
  let runtimeObject ←
    match ProofForge.Backend.Evm.IR.lowerModule module with
    | .ok obj => pure obj
    | .error err => throw <| IO.userError err.render
  let runtimeName := decl.id ++ "Runtime"
  let yul := ProofForge.Contract.Token.EvmWrap.wrapRuntimeObject decl.id runtimeName runtimeObject decl.spec
  let yulOutput := opts.yulOutput?.getD (defaultLearnTokenEvmYulOutput decl)
  writeTextFile yulOutput yul
  let bytecode ← solcBytecode opts.solc yulOutput
  let output := opts.output?.getD (defaultLearnTokenEvmBytecodeOutput decl)
  writeTextFile output (bytecode ++ "\n")
  let metadataOutput := opts.artifactOutput?.getD (defaultLearnTokenArtifactOutput output)
  let sourceArtifact ← artifactEntryJson input
  let yulArtifact ← artifactEntryJson yulOutput
  let bytecodeArtifact ← artifactEntryJson output
  let events ← eventAbisForModule opts.cast module
  let entrypointsJson ← liftExceptString (tokenEvmEntrypointsJson module)
  let eventsJson := tokenEvmEventsJson events
  writeTextFile metadataOutput
    (tokenEvmArtifactJson decl profile plan sourceArtifact yulArtifact bytecodeArtifact entrypointsJson
      eventsJson ++ "\n")
  IO.println s!"wrote {yulOutput}"
  IO.println s!"wrote {output} ({bytecode.length} hex chars)"
  IO.println s!"wrote {metadataOutput}"
  return 0

def compileLearnTokenPlan (opts : CliOptions)
    (profile : ProofForge.Target.TargetProfile)
    (input : FilePath)
    (decl : ProofForge.Contract.Token.Learn.TokenDecl)
    (plan : ProofForge.Contract.Token.TokenPlan) : IO UInt32 := do
  let output := opts.output?.getD (defaultLearnTokenPlanOutput decl profile)
  let sourceArtifact ← artifactEntryJson input
  let solanaDeployment? ←
    if profile.family == ProofForge.Target.TargetFamily.solana then
      match ProofForge.Contract.Token.solanaTokenDeploymentPlan decl.spec with
      | .ok deployment => pure (some deployment)
      | .error err => throw <| IO.userError err
    else
      pure none
  writeTextFile output (tokenPlanJson decl profile plan sourceArtifact solanaDeployment? ++ "\n")
  IO.println s!"wrote {output}"
  return 0

def compileLearnTokenTarget (opts : CliOptions) : IO UInt32 := do
  let profile ← learnTokenTargetProfile opts
  let (input, decl) ← parseLearnTokenInput opts "--learn-token"
  let plan ←
    match ProofForge.Contract.Token.planForTarget profile decl.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  if profile.id == ProofForge.Target.evm.id then
    compileLearnTokenEvm opts profile input decl plan
  else
    compileLearnTokenPlan opts profile input decl plan

def compileSolanaElf (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/Counter.so")
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD "counter"
    | none => "counter"
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"

  match ProofForge.Backend.Solana.Package.renderPackage projectName ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath

      -- Invoke the sbpf toolchain to assemble and link the ELF.
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let elfArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "counter-elf"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString "Counter"),
        ("capabilities", jsonStringArray #["storage.scalar", "account.explicit", "control.conditional"]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "passed"),
          ("sbpfDisassembleRoundtrip", jsonString "pending"),
          ("manifestGeneration", jsonString "passed")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSpecElf (opts : CliOptions) (defaultOutput : FilePath)
    (fallbackProjectName fixture : String) (spec : ProofForge.Contract.ContractSpec) :
    IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let projectName := match output.fileName with
    | some n => (n.splitOn ".").headD fallbackProjectName
    | none => fallbackProjectName
  let projectDir := match output.parent with
    | some parent => parent / s!"{projectName}-sbpf-project"
    | none => FilePath.mk s!"{projectName}-sbpf-project"
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render

  match ProofForge.Backend.Solana.Package.renderPackageForSpec projectName spec with
  | .ok pkg =>
      for file in pkg.files do
        let path := packagePath projectDir file.path
        writeTextFile path file.contents
        IO.println s!"wrote {path}"

      let asmSrc := packagePath projectDir pkg.asmPath
      let manifestOutput := packagePath projectDir pkg.manifestPath
      let idlOutput := packagePath projectDir pkg.idlPath
      let clientOutput := packagePath projectDir pkg.clientPath
      let _ ← runProcess "sbpf" #["build", "--arch", opts.solanaSbpfArch] (cwd? := some projectDir)

      let builtElf := projectDir / "deploy" / s!"{projectName}.so"
      if ! (← builtElf.pathExists) then
        throw <| IO.userError s!"sbpf build did not produce {builtElf}"

      let elfBytes ← IO.FS.readBinFile builtElf
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      IO.FS.writeBinFile output elfBytes
      IO.println s!"wrote {output}"

      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson asmSrc
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let elfArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null"),
            ("arch", jsonString opts.solanaSbpfArch)
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact),
          ("solanaElf", elfArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "passed"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSpecSbpf (opts : CliOptions) (defaultOutput : FilePath)
    (fixture : String) (spec : ProofForge.Contract.ContractSpec) : IO UInt32 := do
  let output := opts.output?.getD defaultOutput
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.render
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan spec.module plan with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let manifestOutput ← writeSbpfManifestWithPlan output spec.module plan
      IO.println s!"wrote {manifestOutput}"
      let idlOutput ← writeSbpfIdlWithPlan output spec.module plan
      IO.println s!"wrote {idlOutput}"
      let clientOutput ← writeSbpfClientWithPlan output spec.module plan
      IO.println s!"wrote {clientOutput}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let manifestArtifact ← artifactEntryJson manifestOutput
      let idlArtifact ← artifactEntryJson idlOutput
      let clientArtifact ← artifactEntryJson clientOutput
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString fixture),
        ("sourceKind", jsonString "contract-sdk"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("sourceModule", jsonString spec.name),
        ("capabilities", jsonStringArray (dedupStrings (plan.capabilities.map fun capability => capability.id))),
        ("capabilityPlan", capabilityPlanJson plan),
        ("solanaInstructions", solanaInstructionsJson spec.module plan),
        ("solanaExtensions", solanaExtensionsJson plan),
        ("solanaIdl", ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact),
          ("manifestToml", manifestArtifact),
          ("solanaIdl", idlArtifact),
          ("solanaClientTs", clientArtifact)
        ]),
        ("validation", jsonObject #[
          ("targetRouting", jsonString "passed"),
          ("manifestGeneration", jsonString "passed"),
          ("sbpfBuild", jsonString "pending"),
          ("liveCpi", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileSolanaSystemCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCpi.s")
    "solana-system-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.s")
    "solana-system-create-account-cpi-sbpf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.s")
    "solana-spl-token-transfer-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.s")
    "solana-spl-token-ops-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.s")
    "solana-spl-token-close-account-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.s")
    "solana-spl-token-authority-cpi-sbpf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaSplToken2022CpiSbpf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecSbpf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.s")
    "solana-spl-token-2022-cpi-sbpf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileValueVaultSolanaElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ValueVault.so")
    "value-vault"
    "value-vault-solana-elf"
    ProofForge.Contract.Examples.ValueVault.spec

def compileSolanaSystemCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCpi.so")
    "system-cpi"
    "solana-system-cpi-elf"
    ProofForge.Solana.Examples.SystemCpi.spec

def compileSolanaSystemCreateAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SystemCreateAccountCpi.so")
    "system-create-account-cpi"
    "solana-system-create-account-cpi-elf"
    ProofForge.Solana.Examples.SystemCreateAccountCpi.spec

def compileSolanaSplTokenTransferCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenTransferCheckedCpi.so")
    "spl-token-transfer-cpi"
    "solana-spl-token-transfer-cpi-elf"
    ProofForge.Solana.Examples.SplTokenTransferCheckedCpi.spec

def compileSolanaSplTokenOpsCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenOpsCpi.so")
    "spl-token-ops-cpi"
    "solana-spl-token-ops-cpi-elf"
    ProofForge.Solana.Examples.SplTokenOpsCpi.spec

def compileSolanaSplTokenCloseAccountCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenCloseAccountCpi.so")
    "spl-token-close-account-cpi"
    "solana-spl-token-close-account-cpi-elf"
    ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec

def compileSolanaSplTokenAuthorityCpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplTokenAuthorityCpi.so")
    "spl-token-authority-cpi"
    "solana-spl-token-authority-cpi-elf"
    ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec

def compileSolanaSplToken2022CpiElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/SplToken2022Cpi.so")
    "spl-token-2022-cpi"
    "solana-spl-token-2022-cpi-elf"
    ProofForge.Solana.Examples.SplToken2022Cpi.spec

def compileSolanaLogEventElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LogEvent.so")
    "log-event"
    "solana-log-event-elf"
    ProofForge.Solana.Examples.LogEvent.spec

def compileSolanaClockSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Clock.so")
    "clock-sysvar"
    "solana-clock-sysvar-elf"
    ProofForge.Solana.Examples.Clock.spec

def compileSolanaRentSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Rent.so")
    "rent-sysvar"
    "solana-rent-sysvar-elf"
    ProofForge.Solana.Examples.Rent.spec

def compileSolanaEpochScheduleSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochSchedule.so")
    "epoch-schedule-sysvar"
    "solana-epoch-schedule-sysvar-elf"
    ProofForge.Solana.Examples.EpochSchedule.spec

def compileSolanaEpochRewardsSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/EpochRewards.so")
    "epoch-rewards-sysvar"
    "solana-epoch-rewards-sysvar-elf"
    ProofForge.Solana.Examples.EpochRewards.spec

def compileSolanaLastRestartSlotSysvarElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/LastRestartSlot.so")
    "last-restart-slot-sysvar"
    "solana-last-restart-slot-sysvar-elf"
    ProofForge.Solana.Examples.LastRestartSlot.spec

def compileSolanaMemoryElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/Memory.so")
    "memory"
    "solana-memory-elf"
    ProofForge.Solana.Examples.Memory.spec

def compileSolanaCryptoHashElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/CryptoHash.so")
    "crypto-hash"
    "solana-crypto-hash-elf"
    ProofForge.Solana.Examples.Crypto.spec

def compileSolanaReturnDataComputeElf (opts : CliOptions) : IO UInt32 :=
  compileSolanaSpecElf opts
    (FilePath.mk "build/solana/ReturnDataCompute.so")
    "return-data-compute"
    "solana-return-data-compute-elf"
    ProofForge.Solana.Examples.ReturnDataCompute.spec

def compileSbpfAsm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/solana/entrypoint.s")
  match ProofForge.Backend.Solana.SbpfAsm.renderCannedEntrypoint with
  | .ok source =>
      if let some parent := output.parent then
        IO.FS.createDirAll parent
      writeTextFile output source
      IO.println s!"wrote {output}"
      let metadataOutput := opts.artifactOutput?.getD (defaultArtifactOutput output)
      if let some parent := metadataOutput.parent then
        IO.FS.createDirAll parent
      let sourceArtifact ← artifactEntryJson output
      let metadata := jsonObject #[
        ("schemaVersion", "1"),
        ("target", jsonString ProofForge.Backend.Solana.SbpfAsm.targetId),
        ("targetFamily", jsonString "solana"),
        ("artifactKind", jsonString ProofForge.Backend.Solana.SbpfAsm.artifactKind),
        ("fixture", jsonString "sbpf-asm-phase0-canned-entrypoint"),
        ("sourceKind", jsonString "portable-ir"),
        ("irVersion", jsonString ProofForge.Backend.Solana.SbpfAsm.irVersion),
        ("capabilities", jsonStringArray #[]),
        ("toolchain", jsonObject #[
          ("sbpf", jsonObject #[
            ("path", jsonString "sbpf"),
            ("version", "null")
          ])
        ]),
        ("artifacts", jsonObject #[
          ("sbpfAsm", sourceArtifact)
        ]),
        ("validation", jsonObject #[
          ("sbpfBuild", jsonString "pending"),
          ("sbpfDisassembleRoundtrip", jsonString "pending")
        ])
      ]
      IO.FS.writeFile metadataOutput (metadata ++ "\n")
      IO.println s!"wrote {metadataOutput}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCounterIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/Counter.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compilePureMathIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/PureMath.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.PureMath.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render

def compileCounterIrCosmWasm (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/cosmwasm/Counter.wat")
  match ProofForge.Backend.CosmWasm.EmitWat.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

def writePackageFiles (outputDir : FilePath) (pkg : Array ProofForge.Backend.Move.Aptos.PackageFile) : IO Unit := do
  for file in pkg do
    let path := outputDir / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    writeTextFile path file.content

def compileCounterIrAptos (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aptos/counter")
  match ProofForge.Backend.Move.Aptos.renderPackage ProofForge.IR.Examples.Counter.module with
  | .ok pkg =>
      writePackageFiles output pkg
      IO.println s!"wrote Aptos package to {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.message

unsafe def compileEvmBytecode (opts : CliOptions) : IO UInt32 :=
  compileContractSourceEvmBytecode opts

unsafe def compileFile (opts : CliOptions) : IO UInt32 := do
  match opts.mode with
  | .yul => compileContractSourceYul opts
  | .evmBytecode => compileEvmBytecode opts
  | .counterIrYul => compileCounterIrYul opts
  | .counterIrTs => compileCounterIrTs opts
  | .counterIrBytecode => compileCounterIrBytecode opts
  | .valueVaultIrYul => compileValueVaultIrYul opts
  | .valueVaultIrBytecode => compileValueVaultIrBytecode opts
  | .errorRefIrYul => compileErrorRefIrYul opts
  | .errorRefIrBytecode => compileErrorRefIrBytecode opts
  | .errorRefIrSbpf => compileErrorRefIrSbpf opts
  | .errorRefEmitWat => compileErrorRefEmitWat opts
  | .learnYul => compileLearnYul opts
  | .learnBytecode => compileLearnBytecode opts
  | .learnSbpf => compileLearnSbpf opts
  | .contractSourceSbpf => compileContractSourceSbpf opts
  | .contractSourceEmitWat => compileContractSourceEmitWat opts
  | .learnTarget => compileLearnTarget opts
  | .learnTokenTarget => compileLearnTokenTarget opts
  | .abiScalarIrYul => compileAbiScalarIrYul opts
  | .abiScalarIrBytecode => compileAbiScalarIrBytecode opts
  | .assertIrYul => compileAssertIrYul opts
  | .assertIrBytecode => compileAssertIrBytecode opts
  | .assignmentIrYul => compileAssignmentIrYul opts
  | .assignmentIrBytecode => compileAssignmentIrBytecode opts
  | .evmAssignOpIrYul => compileEvmAssignOpIrYul opts
  | .evmAssignOpIrBytecode => compileEvmAssignOpIrBytecode opts
  | .conditionalIrYul => compileConditionalIrYul opts
  | .conditionalIrBytecode => compileConditionalIrBytecode opts
  | .contextIrYul => compileContextIrYul opts
  | .contextIrBytecode => compileContextIrBytecode opts
  | .evmEventIrYul => compileEvmEventIrYul opts
  | .evmEventIrBytecode => compileEvmEventIrBytecode opts
  | .evmCrosscallIrYul => compileEvmCrosscallIrYul opts
  | .evmCrosscallIrBytecode => compileEvmCrosscallIrBytecode opts
  | .evmExpressionIrYul => compileEvmExpressionIrYul opts
  | .evmExpressionIrBytecode => compileEvmExpressionIrBytecode opts
  | .evmHashIrYul => compileEvmHashIrYul opts
  | .evmHashIrBytecode => compileEvmHashIrBytecode opts
  | .evmLoopIrYul => compileEvmLoopIrYul opts
  | .evmLoopIrBytecode => compileEvmLoopIrBytecode opts
  | .evmMapIrYul => compileEvmMapIrYul opts
  | .evmMapIrBytecode => compileEvmMapIrBytecode opts
  | .evmStorageArrayIrYul => compileEvmStorageArrayIrYul opts
  | .evmStorageArrayIrBytecode => compileEvmStorageArrayIrBytecode opts
  | .evmStorageStructIrYul => compileEvmStorageStructIrYul opts
  | .evmStorageStructIrBytecode => compileEvmStorageStructIrBytecode opts
  | .evmTypedMapIrYul => compileEvmTypedMapIrYul opts
  | .evmTypedMapIrBytecode => compileEvmTypedMapIrBytecode opts
  | .evmTypedStorageIrYul => compileEvmTypedStorageIrYul opts
  | .evmTypedStorageIrBytecode => compileEvmTypedStorageIrBytecode opts
  | .evmArrayValueIrYul => compileEvmArrayValueIrYul opts
  | .evmArrayValueIrBytecode => compileEvmArrayValueIrBytecode opts
  | .evmStructArrayValueIrYul => compileEvmStructArrayValueIrYul opts
  | .evmStructArrayValueIrBytecode => compileEvmStructArrayValueIrBytecode opts
  | .evmStructValueIrYul => compileEvmStructValueIrYul opts
  | .evmStructValueIrBytecode => compileEvmStructValueIrBytecode opts
  | .evmAbiAggregateIrYul => compileEvmAbiAggregateIrYul opts
  | .evmAbiAggregateIrBytecode => compileEvmAbiAggregateIrBytecode opts
  | .counterIrPsy => compileCounterIrPsy opts
  | .eventIrPsy => compileEventIrPsy opts
  | .crosscallIrPsy => compileCrosscallIrPsy opts
  | .expressionPredicateIrPsy => compileExpressionPredicateIrPsy opts
  | .genericEntrypointIrPsy => compileGenericEntrypointIrPsy opts
  | .arithmeticIrPsy => compileArithmeticIrPsy opts
  | .bitwiseIrPsy => compileBitwiseIrPsy opts
  | .boolStorageArrayIrPsy => compileBoolStorageArrayIrPsy opts
  | .boolStorageScalarIrPsy => compileBoolStorageScalarIrPsy opts
  | .conditionalIrPsy => compileConditionalIrPsy opts
  | .contextIrPsy => compileContextIrPsy opts
  | .hashIrPsy => compileHashIrPsy opts
  | .hashStorageIrPsy => compileHashStorageIrPsy opts
  | .mapIrPsy => compileMapIrPsy opts
  | .assertIrPsy => compileAssertIrPsy opts
  | .loopIrPsy => compileLoopIrPsy opts
  | .arrayIrPsy => compileArrayIrPsy opts
  | .structIrPsy => compileStructIrPsy opts
  | .structArrayIrPsy => compileStructArrayIrPsy opts
  | .abiAggregateIrPsy => compileAbiAggregateIrPsy opts
  | .nestedAggregateIrPsy => compileNestedAggregateIrPsy opts
  | .storageNestedAggregateIrPsy => compileStorageNestedAggregateIrPsy opts
  | .u32ArithmeticIrPsy => compileU32ArithmeticIrPsy opts
  | .u32HashPackingIrPsy => compileU32HashPackingIrPsy opts
  | .u32StorageScalarIrPsy => compileU32StorageScalarIrPsy opts
  | .u32StorageArrayIrPsy => compileU32StorageArrayIrPsy opts
  | .counterIrSbpf => compileCounterIrSbpf opts
  | .valueVaultIrSbpf => compileValueVaultIrSbpf opts
  | .controlIrSbpf => compileControlIrSbpf opts
  | .solanaSdkSbpf => compileSolanaSdkSbpf opts
  | .solanaSystemCpiSbpf => compileSolanaSystemCpiSbpf opts
  | .solanaSystemCreateAccountCpiSbpf => compileSolanaSystemCreateAccountCpiSbpf opts
  | .solanaSplTokenTransferCpiSbpf => compileSolanaSplTokenTransferCpiSbpf opts
  | .solanaSplTokenOpsCpiSbpf => compileSolanaSplTokenOpsCpiSbpf opts
  | .solanaSplTokenCloseAccountCpiSbpf => compileSolanaSplTokenCloseAccountCpiSbpf opts
  | .solanaSplTokenAuthorityCpiSbpf => compileSolanaSplTokenAuthorityCpiSbpf opts
  | .solanaSplToken2022CpiSbpf => compileSolanaSplToken2022CpiSbpf opts
  | .solanaElf => compileSolanaElf opts
  | .valueVaultSolanaElf => compileValueVaultSolanaElf opts
  | .solanaSystemCpiElf => compileSolanaSystemCpiElf opts
  | .solanaSystemCreateAccountCpiElf => compileSolanaSystemCreateAccountCpiElf opts
  | .solanaSplTokenTransferCpiElf => compileSolanaSplTokenTransferCpiElf opts
  | .solanaSplTokenOpsCpiElf => compileSolanaSplTokenOpsCpiElf opts
  | .solanaSplTokenCloseAccountCpiElf => compileSolanaSplTokenCloseAccountCpiElf opts
  | .solanaSplTokenAuthorityCpiElf => compileSolanaSplTokenAuthorityCpiElf opts
  | .solanaSplToken2022CpiElf => compileSolanaSplToken2022CpiElf opts
  | .solanaLogEventElf => compileSolanaLogEventElf opts
  | .solanaClockSysvarElf => compileSolanaClockSysvarElf opts
  | .solanaRentSysvarElf => compileSolanaRentSysvarElf opts
  | .solanaEpochScheduleSysvarElf => compileSolanaEpochScheduleSysvarElf opts
  | .solanaEpochRewardsSysvarElf => compileSolanaEpochRewardsSysvarElf opts
  | .solanaLastRestartSlotSysvarElf => compileSolanaLastRestartSlotSysvarElf opts
  | .solanaMemoryElf => compileSolanaMemoryElf opts
  | .solanaCryptoHashElf => compileSolanaCryptoHashElf opts
  | .solanaReturnDataComputeElf => compileSolanaReturnDataComputeElf opts
  | .sbpfAsm => compileSbpfAsm opts
  | .counterIrWasmNear => compileCounterIrWasmNear opts
  | .contextIrWasmNear => compileContextIrWasmNear opts
  | .hashIrWasmNear => compileHashIrWasmNear opts
  | .mapIrWasmNear => compileMapIrWasmNear opts
  | .counterEmitWat => compileCounterEmitWat opts
  | .contextEmitWat => compileContextEmitWat opts
  | .hashEmitWat => compileHashEmitWat opts
  | .mapEmitWat => compileMapEmitWat opts
  | .counterIrLeo => compileCounterIrLeo opts
  | .pureMathIrLeo => compilePureMathIrLeo opts
  | .counterIrCosmWasm => compileCounterIrCosmWasm opts
  | .counterIrAptos => compileCounterIrAptos opts

end ProofForge.Cli

unsafe def main (args : List String) : IO UInt32 := do
  match args with
  | "init" :: rest =>
    match ProofForge.Cli.Scaffold.parseInitOptions rest with
    | Except.ok opts => ProofForge.Cli.Scaffold.initCommand opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
  | _ =>
    let parseResult : Except String ProofForge.Cli.CliOptions :=
      match args with
      | "--list-targets" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listTargets }
      | "--list-fixtures" :: _ => Except.ok { cmd := ProofForge.Cli.Command.listFixtures }
      | "build" :: _ | "emit" :: _ =>
        match ProofForge.Cli.newCommandArgsToLegacy args with
        | Except.ok legacyArgs =>
          match ProofForge.Cli.parseArgs legacyArgs {} with
          | Except.ok opts => Except.ok { opts with
              cmd :=
                match args with
                | "build" :: _ => ProofForge.Cli.Command.build
                | _ => ProofForge.Cli.Command.emit,
              fromNewSurface := true }
          | Except.error msg => Except.error msg
        | Except.error msg => Except.error msg
      | "check" :: rest =>
        match ProofForge.Cli.parseNewOptions rest {} with
        | Except.ok state =>
          Except.ok {
            cmd := ProofForge.Cli.Command.check,
            targetId? := state.target?,
            fixture? := state.fixture?,
            format? := state.format?,
            input? := state.input?.map FilePath.mk,
            root? := state.root?.map FilePath.mk,
            fromNewSurface := true
            : ProofForge.Cli.CliOptions }
        | Except.error msg => Except.error msg
      | _ => ProofForge.Cli.parseArgs args {}
    match parseResult with
    | Except.ok opts => do
        match opts.cmd with
        | ProofForge.Cli.Command.listTargets =>
          IO.println (String.intercalate "\n" ProofForge.Target.knownIds.toList)
          return 0
        | ProofForge.Cli.Command.listFixtures =>
          IO.println (String.intercalate "\n" ProofForge.Cli.Fixture.ids.toList)
          return 0
        | ProofForge.Cli.Command.check =>
          ProofForge.Cli.checkCommand opts
        | _ =>
          if !opts.fromNewSurface then
            if let some note := ProofForge.Cli.EmitMode.deprecationNote opts.mode then
              IO.eprintln note
          if opts.evmChainProfile?.isSome then
            discard <| ProofForge.Cli.resolveEvmChainProfile? opts.evmChainProfile?
          ProofForge.Cli.compileFile opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
