import ProofForge.IR.Contract
import ProofForge.Contract.Spec

namespace ProofForge.IR.Legacy

/--! Disposition of a legacy IR node in the canonical-core migration.

A `LegacyDisposition` records what the migration plan intends to do with a
legacy constructor or `ContractSpec` field. It is part of the Wave 0 "freeze
and classify" contract: before the adapter can accept a legacy node, that node
must have an explicit decision and an owner. -/
inductive LegacyDisposition
  | preserve
  | normalize
  | materialization
  | evidence
  | reject
  deriving BEq, Repr

def LegacyDisposition.toString : LegacyDisposition → String
  | .preserve => "preserve"
  | .normalize => "normalize"
  | .materialization => "materialization"
  | .evidence => "evidence"
  | .reject => "reject"

/--! Decision for one legacy IR constructor.

`nodeTag` is a stable constructor identifier (e.g. `"Expr.literal"`).  The
`owner` is the team/task responsible for making the disposition true.  The
`reason` is a short, human-readable justification. -/
structure LegacyDecision where
  nodeTag : String
  disposition : LegacyDisposition
  owner : String
  reason : String
  deriving BEq, Repr

/--! Decision for one `ContractSpec` field. -/
structure LegacySpecFieldDecision where
  field : String
  disposition : LegacyDisposition
  owner : String
  reason : String
  deriving BEq, Repr

private def payloadDecision (nodeTag : String) (disposition : LegacyDisposition)
    (owner reason : String) : LegacyDecision :=
  { nodeTag, disposition, owner, reason }

/- Payload classifiers are deliberately constructor-exhaustive. Outer-node
classifiers must not hide schema growth in nested legacy inductives.

`ValueType` now lives in the portable `IR.ValueType` module rather than the v1
contract schema. This classifier remains only to decide how value shapes found
inside compatibility `Contract` nodes normalize into Canonical Core. -/

def classifyValueType : ValueType → LegacyDecision
  | .unit => payloadDecision "ValueType.unit" .normalize "canonical-core" "unit type maps to CoreType.unit"
  | .bool => payloadDecision "ValueType.bool" .normalize "canonical-core" "boolean type maps to CoreType.bool"
  | .u8 => payloadDecision "ValueType.u8" .normalize "canonical-core" "u8 type maps to CoreType.u8"
  | .u32 => payloadDecision "ValueType.u32" .normalize "canonical-core" "u32 type maps to CoreType.u32"
  | .u64 => payloadDecision "ValueType.u64" .normalize "canonical-core" "u64 type maps to CoreType.u64"
  | .u128 => payloadDecision "ValueType.u128" .normalize "canonical-core" "u128 type maps to CoreType.u128"
  | .address => payloadDecision "ValueType.address" .normalize "canonical-core" "portable identity maps to CoreType.address"
  | .bytes => payloadDecision "ValueType.bytes" .normalize "canonical-core" "bytes type maps to CoreType.bytes"
  | .string => payloadDecision "ValueType.string" .normalize "canonical-core" "string type maps to CoreType.string"
  | .hash => payloadDecision "ValueType.hash" .normalize "canonical-core" "hash type maps to CoreType.hash"
  | .fixedArray _ _ => payloadDecision "ValueType.fixedArray" .normalize "canonical-core-arrays" "fixed array shape maps recursively to canonical Core"
  | .structType _ => payloadDecision "ValueType.structType" .reject "canonical-core-structs" "named struct references are outside the initial adapter fragment"
  | .array _ => payloadDecision "ValueType.array" .normalize "canonical-core-arrays" "dynamic array shape maps recursively to canonical Core"

def classifyLiteral : Literal → LegacyDecision
  | .u8 _ => payloadDecision "Literal.u8" .normalize "canonical-core" "u8 literal is range checked during normalization"
  | .u128 _ => payloadDecision "Literal.u128" .normalize "canonical-core" "u128 literal is range checked during normalization"
  | .u32 _ => payloadDecision "Literal.u32" .normalize "canonical-core" "u32 literal is range checked during normalization"
  | .u64 _ => payloadDecision "Literal.u64" .normalize "canonical-core" "u64 literal is range checked during normalization"
  | .bool _ => payloadDecision "Literal.bool" .normalize "canonical-core" "boolean literal maps to canonical Core"
  | .hash4 _ _ _ _ => payloadDecision "Literal.hash4" .normalize "canonical-core" "hash4 limbs are range checked and packed into a canonical numeric hash literal"
  | .address _ => payloadDecision "Literal.address" .normalize "canonical-core" "numeric address handle maps to CoreType.address"
  | .bytes _ => payloadDecision "Literal.bytes" .normalize "canonical-core" "byte literal maps to canonical Core bytes"
  | .string _ => payloadDecision "Literal.string" .normalize "canonical-core" "string literal maps to canonical Core string"

def classifyAssignOp : AssignOp → LegacyDecision
  | .add => payloadDecision "AssignOp.add" .normalize "canonical-core" "addition assignment maps to canonical arithmetic"
  | .sub => payloadDecision "AssignOp.sub" .normalize "canonical-core" "subtraction assignment maps to canonical arithmetic"
  | .mul => payloadDecision "AssignOp.mul" .normalize "canonical-core" "multiplication assignment maps to canonical arithmetic"
  | .div => payloadDecision "AssignOp.div" .normalize "canonical-core" "division assignment maps to canonical arithmetic"
  | .mod => payloadDecision "AssignOp.mod" .normalize "canonical-core" "modulo assignment maps to canonical arithmetic"
  | .bitAnd => payloadDecision "AssignOp.bitAnd" .normalize "canonical-core" "bitwise-and assignment maps to canonical arithmetic"
  | .bitOr => payloadDecision "AssignOp.bitOr" .normalize "canonical-core" "bitwise-or assignment maps to canonical arithmetic"
  | .bitXor => payloadDecision "AssignOp.bitXor" .normalize "canonical-core" "bitwise-xor assignment maps to canonical arithmetic"
  | .shiftLeft => payloadDecision "AssignOp.shiftLeft" .normalize "canonical-core" "left-shift assignment maps to canonical arithmetic"
  | .shiftRight => payloadDecision "AssignOp.shiftRight" .normalize "canonical-core" "right-shift assignment maps to canonical arithmetic"

def classifyStoragePathSegment : StoragePathSegment → LegacyDecision
  | .field _ => payloadDecision "StoragePathSegment.field" .reject "canonical-core-storage-paths" "record-field paths are outside the initial adapter fragment"
  | .index _ => payloadDecision "StoragePathSegment.index" .reject "canonical-core-storage-paths" "array-index paths are outside the initial adapter fragment"
  | .mapKey _ => payloadDecision "StoragePathSegment.mapKey" .reject "canonical-core-storage-paths" "map-key paths are outside the initial adapter fragment"

def classifyContextField : ContextField → LegacyDecision
  | .userId => payloadDecision "ContextField.userId" .normalize "canonical-core" "caller identity maps to canonical sender context"
  | .userIdHash => payloadDecision "ContextField.userIdHash" .normalize "canonical-core-context" "hashed caller identity expands to sender followed by the canonical hash primitive"
  | .accountId => payloadDecision "ContextField.accountId" .normalize "near-context-hostop" "raw predecessor AccountId maps to near.context.predecessor_account_id"
  | .contractId => payloadDecision "ContextField.contractId" .normalize "canonical-core" "contract identity maps to canonical contract address context"
  | .checkpointId => payloadDecision "ContextField.checkpointId" .normalize "canonical-core" "checkpoint maps to canonical block number context"
  | .timestamp => payloadDecision "ContextField.timestamp" .normalize "canonical-core" "timestamp maps to canonical block timestamp context"
  | .epochHeight => payloadDecision "ContextField.epochHeight" .normalize "near-context-hostop" "epoch height maps to near.context.epoch_height"
  | .chainId => payloadDecision "ContextField.chainId" .reject "canonical-core-context" "chain id is outside the initial adapter fragment"
  | .gasPrice => payloadDecision "ContextField.gasPrice" .normalize "evm-context-hostop" "EVM gas price maps to evm.context.gas_price"
  | .gasLeft => payloadDecision "ContextField.gasLeft" .normalize "canonical-core" "portable remaining gas maps to canonical gas context"
  | .prepaidGas => payloadDecision "ContextField.prepaidGas" .normalize "near-context-hostop" "prepaid gas maps to near.context.prepaid_gas"
  | .usedGas => payloadDecision "ContextField.usedGas" .normalize "near-context-hostop" "used gas maps to near.context.used_gas"
  | .baseFee => payloadDecision "ContextField.baseFee" .normalize "evm-context-hostop" "EVM base fee maps to evm.context.base_fee"
  | .prevRandao => payloadDecision "ContextField.prevRandao" .normalize "evm-context-hostop" "EVM randomness maps to evm.context.prevrandao"
  | .randomSeed => payloadDecision "ContextField.randomSeed" .normalize "near-context-hostop" "NEAR randomness maps to near.context.random_seed"
  | .origin => payloadDecision "ContextField.origin" .normalize "evm-context-hostop" "transaction origin maps to evm.context.origin"
  | .coinbase => payloadDecision "ContextField.coinbase" .normalize "evm-context-hostop" "EVM block producer maps to evm.context.coinbase"
  | .blockHash _ => payloadDecision "ContextField.blockHash" .reject "canonical-core-context" "historical block hash is outside the initial adapter fragment"

def classifyEntrypointKind : EntrypointKind → LegacyDecision
  | .function => payloadDecision "EntrypointKind.function" .preserve "canonical-interface" "normal function dispatch kind is preserved"
  | .fallback => payloadDecision "EntrypointKind.fallback" .preserve "canonical-interface" "fallback dispatch kind is preserved"
  | .receive => payloadDecision "EntrypointKind.receive" .preserve "canonical-interface" "receive dispatch kind is preserved"

def classifyEntrypointMutability : EntrypointMutability → LegacyDecision
  | .call => payloadDecision "EntrypointMutability.call" .preserve "canonical-interface" "state-mutating invocation metadata is preserved"
  | .view => payloadDecision "EntrypointMutability.view" .preserve "canonical-interface" "read-only invocation metadata is preserved"

def classifyStateKind : StateKind → LegacyDecision
  | .scalar => payloadDecision "StateKind.scalar" .normalize "canonical-core" "scalar state maps to canonical scalar storage"
  | .map _ _ => payloadDecision "StateKind.map" .normalize "canonical-core-maps" "map key type and capacity are classified before canonical storage lowering"
  | .array _ => payloadDecision "StateKind.array" .normalize "canonical-core-arrays" "fixed array length is classified before canonical storage lowering"
  | .dynamicArray => payloadDecision "StateKind.dynamicArray" .normalize "canonical-core-arrays" "dynamic array shape is classified before canonical storage lowering"

def classifyStateKindPayload : StateKind → Array LegacyDecision
  | .scalar => #[]
  | .map _ _ => #[
      payloadDecision "StateKind.map.keyType" .normalize "canonical-core-maps" "map key type maps recursively to canonical Core",
      payloadDecision "StateKind.map.capacity" .materialization "target-plan-storage" "bounded map capacity is resolved by the target storage plan"
    ]
  | .array _ => #[
      payloadDecision "StateKind.array.length" .normalize "canonical-core-arrays" "fixed array length is preserved in canonical storage shape"
    ]
  | .dynamicArray => #[]

def classifyStructSemantics : StructSemantics → LegacyDecision
  | .value => payloadDecision "StructSemantics.value" .normalize "canonical-core-structs" "copyable struct semantics map to canonical record types"
  | .linearRecord => payloadDecision "StructSemantics.linearRecord" .reject "canonical-core-ownership" "linear record ownership is rejected until canonical ownership semantics cover records"

def classifyAllocatorStrategy : AllocatorStrategy → LegacyDecision
  | .bump => payloadDecision "AllocatorStrategy.bump" .materialization "target-plan-allocator" "bump allocation is materialized by the selected target plan"
  | .bumpReset => payloadDecision "AllocatorStrategy.bumpReset" .materialization "target-plan-allocator" "resetting bump allocation is materialized by the selected target plan"
  | .freeList => payloadDecision "AllocatorStrategy.freeList" .materialization "target-plan-allocator" "free-list allocation is materialized by the selected target plan"
  | .hostImport => payloadDecision "AllocatorStrategy.hostImport" .materialization "target-plan-allocator" "host allocation imports are materialized by the selected target plan"

def classifyAllocatorRelease : AllocatorRelease → LegacyDecision
  | .none => payloadDecision "AllocatorRelease.none" .materialization "target-plan-allocator" "unsupported release is enforced by the selected target plan"
  | .noop => payloadDecision "AllocatorRelease.noop" .materialization "target-plan-allocator" "no-op release is materialized by the selected target plan"
  | .reuse => payloadDecision "AllocatorRelease.reuse" .materialization "target-plan-allocator" "storage reuse is materialized by the selected target plan"

def classifyConstructorInitKind : ProofForge.Contract.ConstructorInitKind → LegacyDecision
  | .scalarU64 => payloadDecision "ConstructorInitKind.scalarU64" .materialization "target-plan-constructor" "scalar constructor initialization is target materialization"
  | .addressWord => payloadDecision "ConstructorInitKind.addressWord" .materialization "target-plan-constructor" "address-word constructor initialization is target materialization"
  | .addressKeccak => payloadDecision "ConstructorInitKind.addressKeccak" .materialization "target-plan-constructor" "address hashing during construction is target materialization"
  | .stringLength => payloadDecision "ConstructorInitKind.stringLength" .materialization "target-plan-constructor" "string length initialization is target materialization"
  | .stringKeccak => payloadDecision "ConstructorInitKind.stringKeccak" .materialization "target-plan-constructor" "string hashing during construction is target materialization"
  | .bytesLength => payloadDecision "ConstructorInitKind.bytesLength" .materialization "target-plan-constructor" "byte length initialization is target materialization"
  | .bytesKeccak => payloadDecision "ConstructorInitKind.bytesKeccak" .materialization "target-plan-constructor" "byte hashing during construction is target materialization"
  | .arrayLength => payloadDecision "ConstructorInitKind.arrayLength" .materialization "target-plan-constructor" "array length initialization is target materialization"
  | .arraySumU64 => payloadDecision "ConstructorInitKind.arraySumU64" .materialization "target-plan-constructor" "array reduction during construction is target materialization"

def classifyIntentKind : ProofForge.Contract.IntentKind → LegacyDecision
  | .module => payloadDecision "IntentKind.module" .materialization "target-plan-intent" "module intent is retained for materialization"
  | .state => payloadDecision "IntentKind.state" .materialization "target-plan-intent" "state intent is retained for materialization"
  | .entrypoint => payloadDecision "IntentKind.entrypoint" .materialization "target-plan-intent" "entrypoint intent is retained for materialization"
  | .capability => payloadDecision "IntentKind.capability" .materialization "target-plan-intent" "capability intent is retained for materialization"

def classifyUpgradePolicy : ProofForge.Contract.UpgradePolicy → LegacyDecision
  | .immutable => payloadDecision "UpgradePolicy.immutable" .materialization "target-plan-upgrade" "immutable deployment policy is target materialization"
  | .authority _ => payloadDecision "UpgradePolicy.authority" .materialization "target-plan-upgrade" "authority-controlled upgrades are target materialization"
  | .governance _ => payloadDecision "UpgradePolicy.governance" .materialization "target-plan-upgrade" "governance-controlled upgrades are target materialization"

def classifyUpgradePolicyPayload : ProofForge.Contract.UpgradePolicy → Array LegacyDecision
  | .immutable => #[]
  | .authority _ => #[
      payloadDecision "UpgradePolicy.authority.keyRef" .materialization "target-plan-upgrade" "upgrade authority key reference is preserved for target materialization"
    ]
  | .governance _ => #[
      payloadDecision "UpgradePolicy.governance.ref" .materialization "target-plan-upgrade" "governance reference is preserved for target materialization"
    ]

def classifyProxyPattern : ProofForge.Contract.ProxyPattern → LegacyDecision
  | .uups => payloadDecision "ProxyPattern.uups" .materialization "target-plan-upgrade" "UUPS proxy layout is target materialization"
  | .transparent => payloadDecision "ProxyPattern.transparent" .materialization "target-plan-upgrade" "transparent proxy layout is target materialization"

/- Structure classifiers use positional patterns deliberately. Adding a field,
even one with a default value, must make this file fail to compile until that
field has an explicit migration decision. -/

def classifyStructFieldFields : StructField → Array LegacyDecision
  | ⟨_, _, _, _⟩ => #[
      payloadDecision "StructField.id" .preserve "canonical-core-structs" "field identity is preserved in canonical type declarations",
      payloadDecision "StructField.type" .normalize "canonical-core-structs" "field value type maps recursively to canonical Core",
      payloadDecision "StructField.isPublic" .materialization "target-plan-interface" "field visibility controls the emitted target interface",
      payloadDecision "StructField.isRef" .normalize "canonical-core-ownership" "reference ownership is checked during canonical normalization"
    ]

def classifyStructDeclFields : StructDecl → Array LegacyDecision
  | ⟨_, _, _, _, _⟩ => #[
      payloadDecision "StructDecl.name" .preserve "canonical-core-structs" "struct identity is preserved in canonical type declarations",
      payloadDecision "StructDecl.fields" .normalize "canonical-core-structs" "struct fields are classified individually before canonical normalization",
      payloadDecision "StructDecl.deriveStorage" .materialization "target-plan-storage" "derived storage representation is selected by the target plan",
      payloadDecision "StructDecl.isPublic" .materialization "target-plan-interface" "struct visibility controls the emitted target interface",
      payloadDecision "StructDecl.isRecord" .normalize "canonical-core-ownership" "record ownership semantics are classified explicitly"
    ]

def classifyStateDeclFields : StateDecl → Array LegacyDecision
  | ⟨_, _, _, _⟩ => #[
      payloadDecision "StateDecl.id" .preserve "canonical-core-storage" "state identity is preserved in canonical storage declarations",
      payloadDecision "StateDecl.kind" .normalize "canonical-core-storage" "state shape is classified by StateKind",
      payloadDecision "StateDecl.type" .normalize "canonical-core-storage" "stored value type maps recursively to canonical Core",
      payloadDecision "StateDecl.keyPathTypes" .normalize "canonical-core-maps" "ordered composite map key types normalize to canonical mapN storage"
    ]

def classifyErrorRefFields : ErrorRef → Array LegacyDecision
  | ⟨_, _, _, _, _, _⟩ => #[
      payloadDecision "ErrorRef.assertionId" .normalize "canonical-core-errors" "portable assertion identity is preserved by canonical control flow",
      payloadDecision "ErrorRef.userCode?" .normalize "canonical-core-errors" "user error code is normalized as observable structured-error identity",
      payloadDecision "ErrorRef.soliditySelector?" .materialization "evm-adapter" "Solidity selector is EVM materialization metadata",
      payloadDecision "ErrorRef.solidityArgWords" .materialization "evm-adapter" "Solidity static error arguments are EVM materialization metadata",
      payloadDecision "ErrorRef.solidityArgTypes" .materialization "evm-adapter" "Solidity error ABI types are EVM materialization metadata",
      payloadDecision "ErrorRef.solidityArgExprs" .materialization "evm-adapter" "runtime Solidity error arguments are retained for EVM materialization"
    ]

def classifyEntrypointFields : Entrypoint → Array LegacyDecision
  | ⟨_, _, _, _, _, _, _, _, _⟩ => #[
      payloadDecision "Entrypoint.name" .preserve "canonical-interface" "entrypoint identity is preserved in the canonical interface",
      payloadDecision "Entrypoint.kind" .preserve "canonical-interface" "dispatch kind is preserved in the canonical interface",
      payloadDecision "Entrypoint.mutability" .preserve "canonical-interface" "host-visible mutability is preserved in the canonical interface",
      payloadDecision "Entrypoint.selector?" .materialization "target-plan-dispatch" "optional dispatch selector is resolved by the target plan",
      payloadDecision "Entrypoint.params" .normalize "canonical-interface" "entrypoint parameters map to typed canonical parameters",
      payloadDecision "Entrypoint.paramAbiWords" .materialization "target-plan-abi" "ABI word overrides are resolved by the target plan",
      payloadDecision "Entrypoint.returns" .normalize "canonical-interface" "return type maps to the canonical interface",
      payloadDecision "Entrypoint.returnAbiWord?" .materialization "target-plan-abi" "return ABI override is preserved in the canonical interface",
      payloadDecision "Entrypoint.body" .normalize "canonical-core" "entrypoint statements normalize to canonical control flow"
    ]

def classifyEventAbiWordFields : EventAbiWord → Array LegacyDecision
  | ⟨_, _, _⟩ => #[
      payloadDecision "EventAbiWord.eventName" .materialization "target-plan-events" "event identity is preserved for target event materialization",
      payloadDecision "EventAbiWord.fieldName" .materialization "target-plan-events" "event field identity is preserved for target event materialization",
      payloadDecision "EventAbiWord.abiWord" .materialization "target-plan-events" "event ABI override is target materialization metadata"
    ]

def classifyModuleFields : Module → Array LegacyDecision
  | ⟨_, _, _, _, _, _, _, _, _⟩ => #[
      payloadDecision "Module.name" .preserve "canonical-core" "module identity is preserved by canonical Core",
      payloadDecision "Module.structs" .normalize "canonical-core-structs" "struct declarations are classified field-by-field",
      payloadDecision "Module.state" .normalize "canonical-core-storage" "state declarations are classified field-by-field",
      payloadDecision "Module.entrypoints" .normalize "canonical-core" "entrypoints are classified field-by-field",
      payloadDecision "Module.eventAbiWords" .materialization "target-plan-events" "event ABI overrides are target materialization metadata",
      payloadDecision "Module.allocator" .materialization "target-plan-allocator" "allocator model is classified field-by-field for target materialization",
      payloadDecision "Module.proxyPattern?" .materialization "target-plan-upgrade" "module proxy layout is target materialization metadata",
      payloadDecision "Module.crosscallStrings" .materialization "near-adapter" "NEAR host string pool is target materialization metadata",
      payloadDecision "Module.overflowChecked" .normalize "canonical-core-arithmetic" "overflow mode selects canonical arithmetic semantics"
    ]

def classifyAllocatorRegionFields : AllocatorRegion → Array LegacyDecision
  | ⟨_, _, _⟩ => #[
      payloadDecision "AllocatorRegion.base" .materialization "target-plan-allocator" "allocator base address is target materialization metadata",
      payloadDecision "AllocatorRegion.size?" .materialization "target-plan-allocator" "allocator region bound is target materialization metadata",
      payloadDecision "AllocatorRegion.growable" .materialization "target-plan-allocator" "allocator growth policy is target materialization metadata"
    ]

def classifyAllocatorModelFields : AllocatorModel → Array LegacyDecision
  | ⟨_, _, _, _⟩ => #[
      payloadDecision "AllocatorModel.strategy" .materialization "target-plan-allocator" "allocator strategy is classified explicitly",
      payloadDecision "AllocatorModel.region" .materialization "target-plan-allocator" "allocator region is classified field-by-field",
      payloadDecision "AllocatorModel.release" .materialization "target-plan-allocator" "allocator release semantics are classified explicitly",
      payloadDecision "AllocatorModel.hostProvided" .materialization "target-plan-allocator" "host allocation requirement is target materialization metadata"
    ]

def classifyAllocatorConfigFields : AllocatorConfig → Array LegacyDecision
  | ⟨_⟩ => #[
      payloadDecision "AllocatorConfig.model" .materialization "target-plan-allocator" "allocator model is classified field-by-field"
    ]

def classifyConstructorParamFields : ProofForge.Contract.ConstructorParam → Array LegacyDecision
  | ⟨_, _⟩ => #[
      payloadDecision "ConstructorParam.name" .materialization "target-plan-constructor" "constructor parameter identity is preserved for deploy materialization",
      payloadDecision "ConstructorParam.abiType" .materialization "target-plan-constructor" "constructor ABI type is target materialization metadata"
    ]

def classifyConstructorInitBindingFields : ProofForge.Contract.ConstructorInitBinding → Array LegacyDecision
  | ⟨_, _, _⟩ => #[
      payloadDecision "ConstructorInitBinding.stateId" .materialization "target-plan-constructor" "constructor storage destination is target materialization metadata",
      payloadDecision "ConstructorInitBinding.paramName" .materialization "target-plan-constructor" "constructor parameter reference is target materialization metadata",
      payloadDecision "ConstructorInitBinding.kind" .materialization "target-plan-constructor" "constructor initialization operation is classified explicitly"
    ]

def classifyIntentFields : ProofForge.Contract.Intent → Array LegacyDecision
  | ⟨_, _, _, _, _⟩ => #[
      payloadDecision "Intent.kind" .materialization "target-plan-intent" "intent kind is classified explicitly",
      payloadDecision "Intent.label" .materialization "target-plan-intent" "intent identity is retained for target planning",
      payloadDecision "Intent.capability?" .materialization "target-plan-intent" "intent capability is retained for target planning",
      payloadDecision "Intent.source?" .evidence "canonical-evidence" "intent source location is retained as evidence",
      payloadDecision "Intent.metadata" .materialization "target-plan-intent" "intent metadata is retained for target planning"
    ]

/--! Classify a legacy `Effect` constructor.

No wildcard arms: adding a new `Effect` constructor makes this function fail to
compile until it receives an explicit decision. -/
def classifyEffect : Effect → LegacyDecision
  | .hostCall id _ _ =>
      { nodeTag := s!"Effect.hostCall({id.render})"
        disposition := .materialization
        owner := "target-extension"
        reason := "typed effect extension normalizes to a catalog-validated Canonical HostOp" }
  | .storageScalarRead _ =>
      { nodeTag := "Effect.storageScalarRead"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage read is in the initial accepted runtime fragment" }
  | .storageScalarWrite _ _ =>
      { nodeTag := "Effect.storageScalarWrite"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage write is in the initial accepted runtime fragment" }
  | .storageScalarAssignOp _ _ _ =>
      { nodeTag := "Effect.storageScalarAssignOp"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar storage assign-op is in the initial accepted runtime fragment" }
  | .storageMapContains _ _ =>
      { nodeTag := "Effect.storageMapContains"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage rejected until core validator and semantics tasks land" }
  | .storageMapGet _ _ =>
      { nodeTag := "Effect.storageMapGet"
        disposition := .normalize
        owner := "canonical-core-maps"
        reason := "map storage reads normalize to a typed Core storageLoad mapKey path" }
  | .storageMapInsert _ _ _ =>
      { nodeTag := "Effect.storageMapInsert"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage insert rejected until core validator and semantics tasks land" }
  | .storageMapSet _ _ _ =>
      { nodeTag := "Effect.storageMapSet"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map storage set rejected until core validator and semantics tasks land" }
  | .storageMapDelete _ _ =>
      { nodeTag := "Effect.storageMapDelete"
        disposition := .reject
        owner := "canonical-core-maps"
        reason := "map deletion has no canonical Core operation yet" }
  | .storageArrayRead _ _ =>
      { nodeTag := "Effect.storageArrayRead"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array read rejected until core validator and semantics tasks land" }
  | .storageArrayWrite _ _ _ =>
      { nodeTag := "Effect.storageArrayWrite"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array write rejected until core validator and semantics tasks land" }
  | .storageArrayStructFieldRead _ _ _ =>
      { nodeTag := "Effect.storageArrayStructFieldRead"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array struct-field read rejected until core validator and semantics tasks land" }
  | .storageArrayStructFieldWrite _ _ _ _ =>
      { nodeTag := "Effect.storageArrayStructFieldWrite"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "storage array struct-field write rejected until core validator and semantics tasks land" }
  | .storageDynamicArrayPush _ _ =>
      { nodeTag := "Effect.storageDynamicArrayPush"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "dynamic array push rejected until core validator and semantics tasks land" }
  | .storageDynamicArrayPop _ =>
      { nodeTag := "Effect.storageDynamicArrayPop"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "dynamic array pop rejected until core validator and semantics tasks land" }
  | .memoryArraySet _ _ _ =>
      { nodeTag := "Effect.memoryArraySet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array set rejected until core validator and semantics tasks land" }
  | .storageStructFieldRead _ _ =>
      { nodeTag := "Effect.storageStructFieldRead"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "storage struct field read rejected until core validator and semantics tasks land" }
  | .storageStructFieldWrite _ _ _ =>
      { nodeTag := "Effect.storageStructFieldWrite"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "storage struct field write rejected until core validator and semantics tasks land" }
  | .storagePathRead _ _ =>
      { nodeTag := "Effect.storagePathRead"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path read rejected until core validator and semantics tasks land" }
  | .storagePathWrite _ _ _ =>
      { nodeTag := "Effect.storagePathWrite"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path write rejected until core validator and semantics tasks land" }
  | .storagePathAssignOp _ _ _ _ =>
      { nodeTag := "Effect.storagePathAssignOp"
        disposition := .reject
        owner := "canonical-core-storage-paths"
        reason := "storage path assign-op rejected until core validator and semantics tasks land" }
  | .contextRead _ =>
      { nodeTag := "Effect.contextRead"
        disposition := .normalize
        owner := "canonical-core"
        reason := "context read is in the initial accepted runtime fragment" }
  | .eventEmit _ _ =>
      { nodeTag := "Effect.eventEmit"
        disposition := .normalize
        owner := "canonical-core"
        reason := "event emit is in the initial accepted runtime fragment" }
  | .eventEmitIndexed _ _ _ =>
      { nodeTag := "Effect.eventEmitIndexed"
        disposition := .materialization
        owner := "target-plan-events"
        reason := "indexed/data event field split materialized to target plan" }

/--! Classify a legacy `Statement` constructor.

No wildcard arms: adding a new `Statement` constructor makes this function fail
to compile until it receives an explicit decision. -/
def classifyStatement : Statement → LegacyDecision
  | .letBind _ _ _ =>
      { nodeTag := "Statement.letBind"
        disposition := .normalize
        owner := "canonical-core"
        reason := "immutable let binding is in the initial accepted runtime fragment" }
  | .letMutBind _ _ _ =>
      { nodeTag := "Statement.letMutBind"
        disposition := .normalize
        owner := "canonical-core"
        reason := "mutable let binding is in the initial accepted runtime fragment" }
  | .assign _ _ =>
      { nodeTag := "Statement.assign"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assignment is in the initial accepted runtime fragment" }
  | .assignOp _ _ _ =>
      { nodeTag := "Statement.assignOp"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assign-op is in the initial accepted runtime fragment" }
  | .effect _ =>
      { nodeTag := "Statement.effect"
        disposition := .normalize
        owner := "canonical-core"
        reason := "effect statement is in the initial accepted runtime fragment" }
  | .assert _ _ _ =>
      { nodeTag := "Statement.assert"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assert is in the initial accepted runtime fragment" }
  | .assertEq _ _ _ _ =>
      { nodeTag := "Statement.assertEq"
        disposition := .normalize
        owner := "canonical-core"
        reason := "assert-eq is in the initial accepted runtime fragment" }
  | .revert _ =>
      { nodeTag := "Statement.revert"
        disposition := .normalize
        owner := "canonical-core"
        reason := "revert is in the initial accepted runtime fragment" }
  | .revertWithError _ =>
      { nodeTag := "Statement.revertWithError"
        disposition := .normalize
        owner := "canonical-core"
        reason := "revert with structured error is in the initial accepted runtime fragment" }
  | .release _ =>
      { nodeTag := "Statement.release"
        disposition := .normalize
        owner := "canonical-core"
        reason := "local release is in the initial accepted runtime fragment" }
  | .ifElse _ _ _ =>
      { nodeTag := "Statement.ifElse"
        disposition := .normalize
        owner := "canonical-core"
        reason := "conditional is in the initial accepted runtime fragment" }
  | .boundedFor _ _ _ _ =>
      { nodeTag := "Statement.boundedFor"
        disposition := .normalize
        owner := "canonical-core"
        reason := "bounded for loop is in the initial accepted runtime fragment" }
  | .whileLoop _ _ =>
      { nodeTag := "Statement.whileLoop"
        disposition := .reject
        owner := "canonical-core-loops"
        reason := "unbounded while loop rejected until core validator and semantics tasks land" }
  | .return _ =>
      { nodeTag := "Statement.return"
        disposition := .normalize
        owner := "canonical-core"
        reason := "return is in the initial accepted runtime fragment" }

/--! Classify a legacy `Expr` constructor.

No wildcard arms: adding a new `Expr` constructor makes this function fail to
compile until it receives an explicit decision. -/
def classifyExpr : Expr → LegacyDecision
  | .hostCall id _ _ _ =>
      { nodeTag := s!"Expr.hostCall({id.render})"
        disposition := .normalize
        owner := "target-extension-registry"
        reason := "typed extension calls normalize to catalog-validated Canonical HostOps" }
  | .literal _ =>
      { nodeTag := "Expr.literal"
        disposition := .preserve
        owner := "canonical-core"
        reason := "fixed-width literal is in the initial accepted runtime fragment" }
  | .local _ =>
      { nodeTag := "Expr.local"
        disposition := .preserve
        owner := "canonical-core"
        reason := "local variable reference is in the initial accepted runtime fragment" }
  | .arrayLit _ _ =>
      { nodeTag := "Expr.arrayLit"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "fixed array literal rejected until core validator and semantics tasks land" }
  | .arrayGet _ _ =>
      { nodeTag := "Expr.arrayGet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "fixed array get rejected until core validator and semantics tasks land" }
  | .memoryArrayNew _ _ =>
      { nodeTag := "Expr.memoryArrayNew"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array allocation rejected until core validator and semantics tasks land" }
  | .memoryArrayLength _ =>
      { nodeTag := "Expr.memoryArrayLength"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array length rejected until core validator and semantics tasks land" }
  | .memoryArrayGet _ _ =>
      { nodeTag := "Expr.memoryArrayGet"
        disposition := .reject
        owner := "canonical-core-arrays"
        reason := "memory array get rejected until core validator and semantics tasks land" }
  | .structLit _ _ =>
      { nodeTag := "Expr.structLit"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "struct literal rejected until core validator and semantics tasks land" }
  | .field _ _ =>
      { nodeTag := "Expr.field"
        disposition := .reject
        owner := "canonical-core-structs"
        reason := "struct field projection rejected until core validator and semantics tasks land" }
  | .add _ _ _ =>
      { nodeTag := "Expr.add"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar addition is in the initial accepted runtime fragment" }
  | .sub _ _ _ =>
      { nodeTag := "Expr.sub"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar subtraction is in the initial accepted runtime fragment" }
  | .mul _ _ _ =>
      { nodeTag := "Expr.mul"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar multiplication is in the initial accepted runtime fragment" }
  | .div _ _ =>
      { nodeTag := "Expr.div"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar division is in the initial accepted runtime fragment" }
  | .mod _ _ =>
      { nodeTag := "Expr.mod"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar modulo is in the initial accepted runtime fragment" }
  | .pow _ _ =>
      { nodeTag := "Expr.pow"
        disposition := .reject
        owner := "canonical-core"
        reason := "scalar power rejected: Core has no exact exponentiation primitive" }
  | .bitAnd _ _ =>
      { nodeTag := "Expr.bitAnd"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise and is in the initial accepted runtime fragment" }
  | .bitOr _ _ =>
      { nodeTag := "Expr.bitOr"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise or is in the initial accepted runtime fragment" }
  | .bitXor _ _ =>
      { nodeTag := "Expr.bitXor"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar bitwise xor is in the initial accepted runtime fragment" }
  | .shiftLeft _ _ =>
      { nodeTag := "Expr.shiftLeft"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar left shift is in the initial accepted runtime fragment" }
  | .shiftRight _ _ =>
      { nodeTag := "Expr.shiftRight"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar right shift is in the initial accepted runtime fragment" }
  | .cast _ _ =>
      { nodeTag := "Expr.cast"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar cast is in the initial accepted runtime fragment" }
  | .eq _ _ =>
      { nodeTag := "Expr.eq"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar equality is in the initial accepted runtime fragment" }
  | .ne _ _ =>
      { nodeTag := "Expr.ne"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar inequality is in the initial accepted runtime fragment" }
  | .lt _ _ =>
      { nodeTag := "Expr.lt"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar less-than is in the initial accepted runtime fragment" }
  | .le _ _ =>
      { nodeTag := "Expr.le"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar less-or-equal is in the initial accepted runtime fragment" }
  | .gt _ _ =>
      { nodeTag := "Expr.gt"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar greater-than is in the initial accepted runtime fragment" }
  | .ge _ _ =>
      { nodeTag := "Expr.ge"
        disposition := .normalize
        owner := "canonical-core"
        reason := "scalar greater-or-equal is in the initial accepted runtime fragment" }
  | .boolAnd _ _ =>
      { nodeTag := "Expr.boolAnd"
        disposition := .reject
        owner := "canonical-core"
        reason := "boolean and rejected: Core lacks a logical boolean operator (use bitAnd for 1-bit values)" }
  | .boolOr _ _ =>
      { nodeTag := "Expr.boolOr"
        disposition := .reject
        owner := "canonical-core"
        reason := "boolean or rejected: Core lacks a logical boolean operator (use bitOr for 1-bit values)" }
  | .boolNot _ =>
      { nodeTag := "Expr.boolNot"
        disposition := .normalize
        owner := "canonical-core"
        reason := "boolean not is in the initial accepted runtime fragment" }
  | .hashValue _ _ _ _ =>
      { nodeTag := "Expr.hashValue"
        disposition := .materialization
        owner := "target-plan-abi"
        reason := "four-word hash packing materialized to target plan" }
  | .hash _ =>
      { nodeTag := "Expr.hash"
        disposition := .materialization
        owner := "target-plan-abi"
        reason := " cryptographic hash materialized to target plan" }
  | .hashTwoToOne _ _ =>
      { nodeTag := "Expr.hashTwoToOne"
        disposition := .reject
        owner := "target-plan-abi"
        reason := "two-to-one hash combiner rejected: Core has no two-input hash primitive" }
  | .ecrecover _ _ _ _ =>
      { nodeTag := "Expr.ecrecover"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "EVM secp256k1 ecrecover precompile materialized by EVM adapter" }
  | .eip712PermitDigest _ _ _ _ _ _ =>
      { nodeTag := "Expr.eip712PermitDigest"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "EIP-712 permit digest materialized by EVM adapter" }
  | .nativeValue =>
      { nodeTag := "Expr.nativeValue"
        disposition := .preserve
        owner := "canonical-core"
        reason := "native value reference is in the initial accepted runtime fragment" }
  | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallAbiPacked"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "ABI-packed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvoke _ _ _ =>
      { nodeTag := "Expr.crosscallInvoke"
        disposition := .preserve
        owner := "canonical-core"
        reason := "portable invoke maps to typed CoreCrosscallSpec with u64 return" }
  | .crosscallInvokeTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "typed dynamic crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeValueTyped _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeValueTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "value-bearing typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeStaticTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeStaticTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "static typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeDelegateTyped _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeDelegateTyped"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "delegate typed crosscall rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallCreate _ _ =>
      { nodeTag := "Expr.crosscallCreate"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "contract creation rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallCreate2 _ _ _ =>
      { nodeTag := "Expr.crosscallCreate2"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "CREATE2 deployment rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallNamed _ _ _ _ =>
      { nodeTag := "Expr.crosscallNamed"
        disposition := .reject
        owner := "target-plan-crosscall"
        reason := "named-callee cross-program call rejected until a typed portable primitive or HostOp handler exists" }
  | .crosscallInvokeNamedValue _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallInvokeNamedValue"
        disposition := .normalize
        owner := "canonical-crosscall-adapter"
        reason := "named value invocation normalizes to a typed Core crosscall mode" }
  | .crosscallContinue _ _ _ _ _ =>
      { nodeTag := "Expr.crosscallContinue"
        disposition := .normalize
        owner := "canonical-crosscall-adapter"
        reason := "asynchronous continuation normalizes to a typed Core crosscall mode" }
  | .callValueU128 =>
      { nodeTag := "Expr.callValueU128"
        disposition := .normalize
        owner := "canonical-context-adapter"
        reason := "full-width call value normalizes to the U128 value context" }
  | .effect _ =>
      { nodeTag := "Expr.effect"
        disposition := .normalize
        owner := "canonical-core"
        reason := "effect expression wrapper is in the initial accepted runtime fragment" }

/- Representative payload values exercise every payload classifier. Exhaustive
matching in each classifier, rather than these sample arrays, is the schema
growth guard. -/

def valueTypeInventory : Array ValueType := #[
  .unit, .bool, .u8, .u32, .u64, .u128, .address, .bytes, .string, .hash,
  .fixedArray .u8 1, .structType "S", .array .u8
]

def literalInventory : Array Literal := #[
  .u8 0, .u128 0, .u32 0, .u64 0, .bool false, .hash4 0 0 0 0, .address 0,
  .bytes ByteArray.empty, .string ""
]

def assignOpInventory : Array AssignOp := #[
  .add, .sub, .mul, .div, .mod, .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight
]

def storagePathSegmentInventory : Array StoragePathSegment := #[
  .field "field", .index (.literal (.u32 0)), .mapKey (.literal (.u32 0))
]

def contextFieldInventory : Array ContextField := #[
  .userId, .userIdHash, .contractId, .checkpointId, .timestamp, .epochHeight,
  .chainId, .gasPrice, .gasLeft, .prepaidGas, .usedGas, .baseFee, .prevRandao, .randomSeed, .origin,
  .coinbase, .blockHash (.literal (.u64 0))
]

def entrypointKindInventory : Array EntrypointKind := #[
  .function, .fallback, .receive
]

def entrypointMutabilityInventory : Array EntrypointMutability := #[
  .call, .view
]

def stateKindInventory : Array StateKind := #[
  .scalar, .map .u64 1, .array 1, .dynamicArray
]

def structSemanticsInventory : Array StructSemantics := #[
  .value, .linearRecord
]

def allocatorStrategyInventory : Array AllocatorStrategy := #[
  .bump, .bumpReset, .freeList, .hostImport
]

def allocatorReleaseInventory : Array AllocatorRelease := #[
  .none, .noop, .reuse
]

def constructorInitKindInventory : Array ProofForge.Contract.ConstructorInitKind := #[
  .scalarU64, .addressWord, .addressKeccak, .stringLength, .stringKeccak,
  .bytesLength, .bytesKeccak, .arrayLength, .arraySumU64
]

def intentKindInventory : Array ProofForge.Contract.IntentKind := #[
  .module, .state, .entrypoint, .capability
]

def upgradePolicyInventory : Array ProofForge.Contract.UpgradePolicy := #[
  .immutable, .authority "key", .governance "governance"
]

def proxyPatternInventory : Array ProofForge.Contract.ProxyPattern := #[
  .uups, .transparent
]

def allPayloadDecisions : Array LegacyDecision :=
  valueTypeInventory.map classifyValueType ++
  literalInventory.map classifyLiteral ++
  assignOpInventory.map classifyAssignOp ++
  storagePathSegmentInventory.map classifyStoragePathSegment ++
  contextFieldInventory.map classifyContextField ++
  entrypointKindInventory.map classifyEntrypointKind ++
  entrypointMutabilityInventory.map classifyEntrypointMutability ++
  stateKindInventory.map classifyStateKind ++
  stateKindInventory.flatMap classifyStateKindPayload ++
  structSemanticsInventory.map classifyStructSemantics ++
  allocatorStrategyInventory.map classifyAllocatorStrategy ++
  allocatorReleaseInventory.map classifyAllocatorRelease ++
  constructorInitKindInventory.map classifyConstructorInitKind ++
  intentKindInventory.map classifyIntentKind ++
  upgradePolicyInventory.map classifyUpgradePolicy ++
  upgradePolicyInventory.flatMap classifyUpgradePolicyPayload ++
  proxyPatternInventory.map classifyProxyPattern

/--! Representative expression for every `Expr` constructor.

Used to build `allDecisions`; the actual sub-expressions/types do not affect the
classification because `classifyExpr` dispatches only on the constructor. -/
def exprInventory : Array Expr := #[
  .literal (Literal.bool false),
  .local "x",
  .arrayLit .u8 #[],
  .arrayGet (.local "a") (.literal (Literal.u32 0)),
  .memoryArrayNew .u8 (.literal (Literal.u32 0)),
  .memoryArrayLength (.local "a"),
  .memoryArrayGet (.local "a") (.literal (Literal.u32 0)),
  .structLit "S" #[],
  .field (.local "s") "f",
  .add (.local "x") (.local "y"),
  .sub (.local "x") (.local "y"),
  .mul (.local "x") (.local "y"),
  .div (.local "x") (.local "y"),
  .mod (.local "x") (.local "y"),
  .pow (.local "x") (.local "y"),
  .bitAnd (.local "x") (.local "y"),
  .bitOr (.local "x") (.local "y"),
  .bitXor (.local "x") (.local "y"),
  .shiftLeft (.local "x") (.local "y"),
  .shiftRight (.local "x") (.local "y"),
  .cast (.local "x") .u64,
  .eq (.local "x") (.local "y"),
  .ne (.local "x") (.local "y"),
  .lt (.local "x") (.local "y"),
  .le (.local "x") (.local "y"),
  .gt (.local "x") (.local "y"),
  .ge (.local "x") (.local "y"),
  .boolAnd (.local "x") (.local "y"),
  .boolOr (.local "x") (.local "y"),
  .boolNot (.local "x"),
  .hashValue (.local "a") (.local "b") (.local "c") (.local "d"),
  .hash (.local "x"),
  .hashTwoToOne (.local "x") (.local "y"),
  .ecrecover (.local "d") (.local "v") (.local "r") (.local "s"),
  .eip712PermitDigest (.local "o") (.local "s") (.local "v") (.local "n") (.local "d") (.local "ds"),
  .nativeValue,
  .crosscallAbiPacked (.local "t") 0 #[] 0 0 none none #[] #[],
  .crosscallInvoke (.local "t") (.local "m") #[],
  .crosscallInvokeTyped (.local "t") (.local "m") #[] .unit,
  .crosscallInvokeValueTyped (.local "t") (.local "m") (.local "v") #[] .unit,
  .crosscallInvokeStaticTyped (.local "t") (.local "m") #[] .unit,
  .crosscallInvokeDelegateTyped (.local "t") (.local "m") #[] .unit,
  .crosscallCreate (.local "v") "",
  .crosscallCreate2 (.local "v") (.local "s") "",
  .crosscallNamed "p" "m" #[] .unit,
  .crosscallInvokeNamedValue (.local "i") (.local "m") #[] (.local "d") #[],
  .crosscallContinue (.local "p") (.local "c") #[] (.local "d") #[],
  .callValueU128,
  .effect (Effect.contextRead .userId)
]

/--! Representative effect for every `Effect` constructor. -/
def effectInventory : Array Effect := #[
  .storageScalarRead "s",
  .storageScalarWrite "s" (.local "v"),
  .storageScalarAssignOp "s" .add (.local "v"),
  .storageMapContains "m" (.local "k"),
  .storageMapGet "m" (.local "k"),
  .storageMapInsert "m" (.local "k") (.local "v"),
  .storageMapSet "m" (.local "k") (.local "v"),
  .storageMapDelete "m" (.local "k"),
  .storageArrayRead "a" (.local "i"),
  .storageArrayWrite "a" (.local "i") (.local "v"),
  .storageArrayStructFieldRead "a" (.local "i") "f",
  .storageArrayStructFieldWrite "a" (.local "i") "f" (.local "v"),
  .storageDynamicArrayPush "a" (.local "v"),
  .storageDynamicArrayPop "a",
  .memoryArraySet (.local "a") (.local "i") (.local "v"),
  .storageStructFieldRead "s" "f",
  .storageStructFieldWrite "s" "f" (.local "v"),
  .storagePathRead "s" #[],
  .storagePathWrite "s" #[] (.local "v"),
  .storagePathAssignOp "s" #[] .add (.local "v"),
  .contextRead .userId,
  .eventEmit "E" #[],
  .eventEmitIndexed "E" #[] #[],
]

/--! Representative statement for every `Statement` constructor. -/
def statementInventory : Array Statement := #[
  .letBind "x" .u64 (.local "v"),
  .letMutBind "x" .u64 (.local "v"),
  .assign (.local "x") (.local "v"),
  .assignOp (.local "x") .add (.local "v"),
  .effect (Effect.contextRead .userId),
  .assert (.local "c") "msg",
  .assertEq (.local "x") (.local "y") "msg",
  .revert,
  .revertWithError { assertionId := 0 },
  .release "x",
  .ifElse (.local "c") #[] #[],
  .boundedFor "i" 0 1 #[],
  .whileLoop (.local "c") #[],
  .return (.local "x")
]

def allStructureFieldDecisions : Array LegacyDecision :=
  classifyStructFieldFields {
    id := "field", type := .u64, isPublic := true, isRef := false
  } ++
  classifyStructDeclFields {
    name := "S", fields := #[], deriveStorage := false,
    isPublic := true, isRecord := false
  } ++
  classifyStateDeclFields { id := "state", kind := .scalar, type := .u64 } ++
  classifyErrorRefFields { assertionId := 0 } ++
  classifyEntrypointFields { name := "run", body := #[] } ++
  classifyEventAbiWordFields {
    eventName := "E", fieldName := "value", abiWord := "uint64"
  } ++
  classifyModuleFields {
    name := "LegacyInventory", state := #[], entrypoints := #[]
  } ++
  classifyAllocatorRegionFields {} ++
  classifyAllocatorModelFields defaultAllocator.model ++
  classifyAllocatorConfigFields defaultAllocator ++
  classifyConstructorParamFields { name := "owner", abiType := "address" } ++
  classifyConstructorInitBindingFields {
    stateId := "owner", paramName := "owner", kind := .addressWord
  } ++
  classifyIntentFields { kind := .module, label := "LegacyInventory" }

/--! All constructor decisions.

Every current payload, `Expr`, `Effect`, and `Statement` constructor has a
representative decision. Exhaustive classifier matches enforce schema growth. -/
def allDecisions : Array LegacyDecision :=
  allPayloadDecisions ++
  exprInventory.map classifyExpr ++
  effectInventory.map classifyEffect ++
  statementInventory.map classifyStatement ++
  allStructureFieldDecisions

/--! All node tags extracted from `allDecisions`. -/
def allNodeTags : Array String :=
  allDecisions.map (·.nodeTag)

/--! Classify the fields of a `ContractSpec`.

The full positional structure pattern is intentional: adding even a defaulted
field to `ContractSpec` makes this definition fail to compile until the field
receives an explicit decision here. This is the single source of the field
inventory; tests inspect its output rather than maintaining another name list. -/
def classifySpecFields : ProofForge.Contract.ContractSpec → Array LegacySpecFieldDecision
  | ⟨_, _, _, _, _, _, _, _, _, _⟩ => #[
      { field := "name"
        disposition := .preserve
        owner := "canonical-core"
        reason := "contract name metadata preserved by canonical core" },
      { field := "module"
        disposition := .normalize
        owner := "canonical-core"
        reason := "IR module is classified field-by-field; target materialization fields are not blanket-preserved" },
      { field := "intents"
        disposition := .materialization
        owner := "target-plan"
        reason := "intents materialized to target plan" },
      { field := "upgradePolicy?"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "upgrade policy materialized by EVM adapter" },
      { field := "proxyPattern?"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "proxy pattern materialized by EVM adapter" },
      { field := "constructorParams"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "constructor parameters materialized by EVM adapter" },
      { field := "constructorInitBindings"
        disposition := .materialization
        owner := "evm-adapter"
        reason := "constructor init bindings materialized by EVM adapter" },
      { field := "quintInvariants"
        disposition := .evidence
        owner := "fv-quint"
        reason := "Quint invariants are verification evidence" },
      { field := "quintLiveness"
        disposition := .evidence
        owner := "fv-quint"
        reason := "Quint liveness properties are verification evidence" },
      { field := "leanInvariants"
        disposition := .evidence
        owner := "fv-lean"
        reason := "Lean invariants are verification evidence" }
    ]

/-- A decision is inside the scalar fragment iff it is marked `preserve` or
`normalize`. -/
def isScalarAcceptable (d : LegacyDecision) : Bool :=
  d.disposition == .preserve || d.disposition == .normalize

end ProofForge.IR.Legacy
