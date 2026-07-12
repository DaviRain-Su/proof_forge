import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Capability
import ProofForge.Target.HostRuntime
import ProofForge.IR.Allocator

namespace ProofForge.IR

/--! ### ValueType portability vocabulary (D-050 Slice 2)

`ValueType` constructors are chain-neutral. In particular `.address` is a
**portable account/identity handle**, not an EVM 20-byte address: each target
adapter renames it to its native identity encoding (EVM `address`, Solana
`Pubkey`, NEAR `AccountId`, Move `signer`/`address`) via the target ABI
metadata bag (`paramAbiWords`). `ValueType.byteWidth` is the EVM storage width
and only consulted by the EVM adapter; it is not part of the portable
contract.
-/

inductive ValueType where
  | unit
  | bool
  | u8
  | u32
  | u64
  | u128
  | address
  | bytes
  | string
  | hash
  | fixedArray (element : ValueType) (length : Nat)
  | structType (name : String)
  | array (element : ValueType)
  deriving BEq, DecidableEq, Repr

def ValueType.name : ValueType → String
  | .unit => "Unit"
  | .bool => "Bool"
  | .u8 => "U8"
  | .u32 => "U32"
  | .u64 => "U64"
  | .u128 => "U128"
  | .address => "Address"
  | .bytes => "Bytes"
  | .string => "String"
  | .hash => "Hash"
  | .fixedArray element length => s!"Array<{element.name},{length}>"
  | .structType name => name
  | .array element => s!"Array<{element.name}>"

def ValueType.capabilities : ValueType → Array ProofForge.Target.Capability
  | .unit => #[]
  | .bool => #[]
  | .u8 => #[]
  | .u32 => #[]
  | .u128 => #[]
  | .u64 => #[]
  | .address => #[]
  | .bytes => #[.dataDynamicBytes]
  | .string => #[.dataDynamicBytes]
  | .hash => #[]
  | .fixedArray element _ => #[.dataFixedArray] ++ element.capabilities
  | .structType _ => #[.dataStruct]
  | .array element => #[.dataDynamicArray] ++ element.capabilities

/--! Byte width of a scalar `ValueType` in EVM storage. Returns 0 for non-scalar types. -/
def ValueType.byteWidth : ValueType → Nat
  | .bool => 1
  | .u8 => 1
  | .u32 => 4
  | .u64 => 8
  | .u128 => 16
  | .address => 20
  | .hash => 32
  | .unit | .bytes | .string | .fixedArray _ _ | .structType _ | .array _ => 0

/--! Whether a `ValueType` is a packed storage scalar (byteWidth > 0 and < 32). -/
def ValueType.isPackedScalar : ValueType → Bool
  | .bool | .u8 | .u32 | .u64 | .u128 | .address => true
  | .unit | .hash | .bytes | .string | .fixedArray _ _ | .structType _ | .array _ => false

/-- Portable identity `ValueType` constructors — every primary target has a
native account/identity encoding for these, so a module may use them without a
family-only finding. `.address` is the chain-neutral account/identity handle;
target adapters rename it to native form (EVM `address`, Solana `Pubkey`, NEAR
`AccountId`, Move `signer`/`address`) via `paramAbiWords` metadata. -/
def ValueType.isPortableIdentity : ValueType → Bool
  | .address => true
  | _ => false

structure StructField where
  id : String
  type : ValueType
  isPublic : Bool := true
  isRef : Bool := false
  deriving Repr

structure StructDecl where
  name : String
  fields : Array StructField
  deriveStorage : Bool := false
  isPublic : Bool := true
  /-- Linear/consumable record semantics. Aleo materializes this as a private
  UTXO-like `record`; adapters without equivalent ownership semantics must
  explicitly reject it rather than treating it as a copyable struct. -/
  isRecord : Bool := false
  deriving Repr

inductive StructSemantics where
  | value
  | linearRecord
  deriving BEq, DecidableEq, Repr

def StructSemantics.id : StructSemantics → String
  | .value => "value"
  | .linearRecord => "linear_record"

def StructDecl.semantics (decl : StructDecl) : StructSemantics :=
  if decl.isRecord then .linearRecord else .value

inductive StateKind where
  | scalar
  | map (keyType : ValueType) (capacity : Nat)
  | array (length : Nat)
  | dynamicArray
  deriving BEq, DecidableEq, Repr

/-- Portable persistent state declaration.

Shape only (`kind` + `type`). Chain-native binding (EVM slots, Solana account
bytes, NEAR host KV, Aptos `has key` resources, Sui objects with UID) is **not**
chosen here — the selected `--target` adapter resolves binding during lowering
(D-050 / D-028). Authors write `state count: scalar U64`; Sui emits an object,
Aptos a resource, EVM a storage slot. -/
structure StateDecl where
  id : String
  kind : StateKind
  type : ValueType
  deriving Repr

inductive Literal where
  | u8 (value : Nat)
  | u128 (value : Nat)
  | u32 (value : Nat)
  | u64 (value : Nat)
  | bool (value : Bool)
  | hash4 (a b c d : Nat)
  | address (value : Nat)
  | bytes (value : ByteArray)
  | string (value : String)
  deriving BEq

instance : Repr Literal where
  reprPrec n _ := match n with
  | .u8 v => s!"Literal.u8 {v}"
  | .u128 v => s!"Literal.u128 {v}"
  | .u32 v => s!"Literal.u32 {v}"
  | .u64 v => s!"Literal.u64 {v}"
  | .bool v => s!"Literal.bool {v}"
  | .hash4 a b c d => s!"Literal.hash4 {a} {b} {c} {d}"
  | .address v => s!"Literal.address {v}"
  | .bytes ba => s!"Literal.bytes ({ba.size} bytes)"
  | .string s => s!"Literal.string {repr s}"

inductive AssignOp where
  | add
  | sub
  | mul
  | div
  | mod
  | bitAnd
  | bitOr
  | bitXor
  | shiftLeft
  | shiftRight
  deriving BEq, DecidableEq, Repr

mutual
  inductive ContextField where
    | userId
    | userIdHash
    | contractId
    | checkpointId
    | timestamp
    | epochHeight
    | chainId
    | gasPrice
    | gasLeft
    | prepaidGas
    | usedGas
    | baseFee
    | prevRandao
    | randomSeed
    | origin
    | coinbase
    | blockHash (blockNumber : Expr)
    deriving Repr, BEq

  inductive Expr where
    | literal (value : Literal)
    | local (name : String)
    | arrayLit (elementType : ValueType) (values : Array Expr)
    | arrayGet (array index : Expr)
    | memoryArrayNew (elementType : ValueType) (length : Expr)
    | memoryArrayLength (array : Expr)
    | memoryArrayGet (array index : Expr)
    | structLit (typeName : String) (fields : Array (String × Expr))
    | field (base : Expr) (fieldName : String)
    | add (lhs rhs : Expr) (overflowChecked : Bool := true)
    | sub (lhs rhs : Expr) (overflowChecked : Bool := true)
    | mul (lhs rhs : Expr) (overflowChecked : Bool := true)
    | div (lhs rhs : Expr)
    | mod (lhs rhs : Expr)
    | pow (lhs rhs : Expr)
    | bitAnd (lhs rhs : Expr)
    | bitOr (lhs rhs : Expr)
    | bitXor (lhs rhs : Expr)
    | shiftLeft (lhs rhs : Expr)
    | shiftRight (lhs rhs : Expr)
    | cast (value : Expr) (targetType : ValueType)
    | eq (lhs rhs : Expr)
    | ne (lhs rhs : Expr)
    | lt (lhs rhs : Expr)
    | le (lhs rhs : Expr)
    | gt (lhs rhs : Expr)
    | ge (lhs rhs : Expr)
    | boolAnd (lhs rhs : Expr)
    | boolOr (lhs rhs : Expr)
    | boolNot (value : Expr)
    | hashValue (a b c d : Expr)
    | hash (preimage : Expr)
    | hashTwoToOne (lhs rhs : Expr)
    /-- EVM secp256k1 `ecrecover(digest, v, r, s)` → address word.
    Requires `crypto.ecrecover` (EVM-only). -/
    | ecrecover (digest v r s : Expr)
    /-- EVM helper: EIP-712 permit struct digest
    `keccak256("\x19\x01" ‖ domainSeparator ‖
      keccak256(PERMIT_TYPEHASH ‖ owner ‖ spender ‖ value ‖ nonce ‖ deadline))`.
    Requires `crypto.ecrecover` (same EVM-only gate as ecrecover). -/
    | eip712PermitDigest (owner spender value nonce deadline domainSep : Expr)
    | nativeValue
    /-- ABI-packed CALL (EVM). `stores` are `(offset, word)` in the **args
    region** after the 4-byte selector (from `Evm.AbiEncode.Plan`).
    - `dynLenOffset?`/`dynLen?`: overwrite Call[] length word at runtime.
    - `dynTargetOffsets`/`dynTargets`: overwrite each Call.address word with a
      **runtime** target (static calldata stays in `stores`).
    Requires `crosscall.invoke`. Other hosts reject. -/
    | crosscallAbiPacked
        (target : Expr)
        (selector : Nat)
        (stores : Array (Nat × Nat))
        (argsSize : Nat)
        (outSize : Nat)
        (dynLenOffset? : Option Nat)
        (dynLen? : Option Expr)
        (dynTargetOffsets : Array Nat)
        (dynTargets : Array Expr)
    | crosscallInvoke (targetContractId : Expr) (methodId : Expr) (args : Array Expr)
    | crosscallInvokeTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeValueTyped (targetContractId : Expr) (methodId callValue : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeStaticTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeDelegateTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallCreate (callValue : Expr) (initCodeHex : String)
    | crosscallCreate2 (callValue salt : Expr) (initCodeHex : String)
    /-- Named-callee cross-program call for app-chain targets (RFC 0015 D4):
    `crosscallNamed(programId, method, args, returnType)` addresses the callee
    by compile-time program/method identifiers (Aleo `_dynamic_call`), unlike the
    runtime-address `crosscallInvoke`. Account-chain targets reject it. -/
    | crosscallNamed (programId method : String) (args : Array Expr) (returnType : ValueType)
    /-- NEAR host-extension only (not portable product path): `promise_create`
        with runtime index into `module.nearCrosscallStrings`. Prefer portable
        `crosscallInvoke` for authoring; this is a lower-level host form. -/
    | nearCrosscallInvokePool (accountIndex : Expr) (methodId : Expr) (args : Array Expr) (deposit : Expr)
    /-- NEAR host-extension only: attach a callback method on the current contract
        (`promise_then`). D-050 Slice 3 — not portable-core. -/
    | nearPromiseThen (parentPromise : Expr) (callbackMethod : Expr) (args : Array Expr) (deposit : Expr)
    /-- NEAR host-extension only: number of completed promise results in a callback. -/
    | nearPromiseResultsCount
    /-- NEAR host-extension only: status of promise result at `index` (1 = success, 2 = failed). -/
    | nearPromiseResultStatus (index : Expr)
    /-- NEAR host-extension only: Borsh-decoded U64 payload from promise result at `index`. -/
    | nearPromiseResultU64 (index : Expr)
    | effect (effect : Effect)
    deriving Repr, BEq

  inductive Effect where
    | storageScalarRead (stateId : String)
    | storageScalarWrite (stateId : String) (value : Expr)
    | storageScalarAssignOp (stateId : String) (op : AssignOp) (value : Expr)
    | storageMapContains (stateId : String) (key : Expr)
    | storageMapGet (stateId : String) (key : Expr)
    | storageMapInsert (stateId : String) (key value : Expr)
    | storageMapSet (stateId : String) (key value : Expr)
    | storageMapDelete (stateId : String) (key : Expr)
    | storageArrayRead (stateId : String) (index : Expr)
    | storageArrayWrite (stateId : String) (index value : Expr)
    | storageArrayStructFieldRead (stateId : String) (index : Expr) (fieldName : String)
    | storageArrayStructFieldWrite (stateId : String) (index : Expr) (fieldName : String) (value : Expr)
    | storageDynamicArrayPush (stateId : String) (value : Expr)
    | storageDynamicArrayPop (stateId : String)
    | memoryArraySet (array index value : Expr)
    | storageStructFieldRead (stateId fieldName : String)
    | storageStructFieldWrite (stateId fieldName : String) (value : Expr)
    | storagePathRead (stateId : String) (path : Array StoragePathSegment)
    | storagePathWrite (stateId : String) (path : Array StoragePathSegment) (value : Expr)
    | storagePathAssignOp (stateId : String) (path : Array StoragePathSegment) (op : AssignOp) (value : Expr)
    | contextRead (field : ContextField)
    | eventEmit (name : String) (fields : Array (String × Expr))
    | eventEmitIndexed (name : String) (indexedFields dataFields : Array (String × Expr))
    /-- EVM ERC-721 receiver check (PF-P2-02): if `to` has code, CALL
    `onERC721Received(operator,from,tokenId,"")` and require magic return.
    Non-EVM targets must reject this effect honestly. -/
    | checkErc721Received (operator fromAddr toAddr tokenId : Expr)
    /-- EVM ERC-1155 single-transfer receiver check (PF-P2-02): if `to` has
    code, CALL `onERC1155Received(operator,from,id,value,"")` and require
    magic return. Non-EVM targets must reject honestly. -/
    | checkErc1155Received (operator fromAddr toAddr id amount : Expr)
    /-- EVM ERC-1155 dynamic batch receiver check (E1.2): if `to` has code, CALL
    `onERC1155BatchReceived(operator,from,ids,amounts,"")` and require magic return.
    `ids` and `amounts` are `Expr.arrayLit .u256 ...` expressions.
    Non-EVM targets must reject honestly. -/
    | checkErc1155BatchReceived
        (operator fromAddr toAddr ids amounts : Expr)
    deriving Repr, BEq

  inductive StoragePathSegment where
    | field (fieldName : String)
    | index (index : Expr)
    | mapKey (key : Expr)
    deriving Repr, BEq
end

def ContextField.name : ContextField → String
  | .userId => "userId"
  | .userIdHash => "userIdHash"
  | .contractId => "contractId"
  | .checkpointId => "checkpointId"
  | .timestamp => "timestamp"
  | .epochHeight => "epochHeight"
  | .chainId => "chainId"
  | .gasPrice => "gasPrice"
  | .gasLeft => "gasLeft"
  | .prepaidGas => "prepaidGas"
  | .usedGas => "usedGas"
  | .baseFee => "baseFee"
  | .prevRandao => "prevRandao"
  | .randomSeed => "randomSeed"
  | .origin => "origin"
  | .coinbase => "coinbase"
  | .blockHash _ => "blockHash"

def ContextField.capability : ContextField → ProofForge.Target.Capability
  | .userId | .userIdHash | .origin => .callerSender
  | .contractId => .accountExplicit
  | .checkpointId | .timestamp | .epochHeight | .chainId | .gasPrice | .gasLeft | .prepaidGas | .usedGas | .baseFee | .prevRandao | .randomSeed | .coinbase | .blockHash _ => .envBlock

/-! ### Context field portability + HostEnv mapping (D-050 / gap-analysis step 1)

IR keeps `ContextField` constructors for source compatibility. The
**chain-agnostic vocabulary** is `HostRuntime.HostEnv` (three buckets:
general / approximate / chainOnly). Use `toHostEnv` + `materializeEnv`
for materialize-or-reject; `isPortableEnv` remains the coarse family-shared
gate used by IR portability checks (general core + shipped `epochHeight`).
-/

/-- Map an IR context field onto the portable HostEnv vocabulary. -/
def ContextField.toHostEnv : ContextField → ProofForge.Target.HostRuntime.HostEnv
  | .userId | .userIdHash => .caller
  | .contractId => .selfAddress
  | .checkpointId => .blockHeight
  | .timestamp => .blockTime
  | .epochHeight => .epoch
  | .chainId => .chainId
  | .gasPrice => .gasPrice
  | .gasLeft => .gasOrComputeBudgetLeft
  | .prepaidGas => .nearPrepaidGas
  | .usedGas => .nearUsedGas
  | .baseFee => .baseFee
  | .prevRandao | .randomSeed => .randomness
  | .origin => .txOrigin
  | .coinbase => .coinbase
  | .blockHash _ => .blockHash

/-- Product portable-core env whitelist: true only when **every** primary triad
target (`evm` · `solana-sbpf-asm` · `wasm-near`) materializes the field via
`HostRuntime.materializeEnv` without reject.

Derived from HostRuntime so the list cannot drift from honesty. After U1.1–U1.2
that includes `caller` (userId / userIdHash), `blockHeight` (checkpointId),
`blockTime` (timestamp via Solana `Clock.unix_timestamp`), and `selfAddress`
(contractId via Solana program_id sha256 limb0). Fields such as `chainId` and
`epochHeight` are not triad-safe — authors get honest reject on unsupported
targets rather than a false "portable" label.
Fine-grained per-target honesty still uses `HostEnv.bucket` + `materializeEnv`. -/
def ContextField.isPortableEnv (field : ContextField) : Bool :=
  ProofForge.Target.HostRuntime.primaryTargetIds.all fun targetId =>
    ProofForge.Target.HostRuntime.supportsHostEnv targetId field.toHostEnv

structure ErrorRef where
  assertionId : UInt32
  userCode? : Option String := none
  /-- Optional Solidity custom-error selector (8 hex digits, no `0x`).
  When set, EVM lowers to `abi.encodeWithSelector(selector[, args…])`
  (PF-P2-02 / E1.1) instead of the ProofForge `(assertionId, string)` envelope. -/
  soliditySelector? : Option String := none
  /-- Transitional EVM-only compile-time ABI static words after the 4-byte
  selector (E1.1). EVM validation checks arity, supported type, and range. -/
  solidityArgWords : Array Nat := #[]
  /-- Solidity ABI type names parallel to `solidityArgWords` / `solidityArgExprs`.
  Contract metadata exposes this schema, but deliberately omits the concrete
  compile-time words or runtime expressions. -/
  solidityArgTypes : Array String := #[]
  /-- Runtime expression arguments after the 4-byte selector. When non-empty,
  EVM lowers each expression to a Yul value and `mstore`s it at the
  corresponding ABI word offset, replacing the compile-time `solidityArgWords`.
  The `solidityArgTypes` array must have the same length. EVM validation
  rejects dynamic types (bytes/string/array) in this slot. -/
  solidityArgExprs : Array Expr := #[]
  deriving Repr

/-- Manual `BEq` for `ErrorRef`, including the runtime argument expressions. -/
instance : BEq ErrorRef where
  beq a b :=
    a.assertionId == b.assertionId &&
    a.userCode? == b.userCode? &&
    a.soliditySelector? == b.soliditySelector? &&
    a.solidityArgWords == b.solidityArgWords &&
    a.solidityArgTypes == b.solidityArgTypes &&
    a.solidityArgExprs == b.solidityArgExprs

inductive Statement where
  | letBind (name : String) (type : ValueType) (value : Expr)
  | letMutBind (name : String) (type : ValueType) (value : Expr)
  | assign (target value : Expr)
  | assignOp (target : Expr) (op : AssignOp) (value : Expr)
  | effect (effect : Effect)
  | assert (condition : Expr) (message : String) (errorRef? : Option ErrorRef := none)
  | assertEq (lhs rhs : Expr) (message : String) (errorRef? : Option ErrorRef := none)
  /-- Unconditional revert with an optional error reason string. -/
  | revert (message : String := "")
  /-- Unconditional revert carrying a structured ErrorRef (same encoding as assert). -/
  | revertWithError (errorRef : ErrorRef)
  /-- Release an owned heap-backed local. This is intentionally name-based
      rather than pointer-based so later IR checkers can prove no use-after-free
      and no double-release properties over local ownership. -/
  | release (name : String)
  | ifElse (condition : Expr) (thenBody elseBody : Array Statement)
  | boundedFor (indexName : String) (start stopExclusive : Nat) (body : Array Statement)
  /-- A general while loop with a Bool condition. Psy accepts unbounded
      `while cond { ... }` loops; EVM v0 rejects this because EVM gas bounds
      require statically bounded iteration. -/
  | whileLoop (condition : Expr) (body : Array Statement)
  | return (value : Expr)
  deriving Repr

inductive EntrypointKind where
  /-- Normal function entrypoint with a 4-byte selector. -/
  | function
  /-- Fallback: called on unknown selector or non-empty calldata that doesn't match. -/
  | fallback
  /-- Receive: called on empty calldata with ETH. -/
  | receive
  deriving Repr, BEq

/-- Host-visible invocation semantics. A return value does not imply `view`:
mutating calls may return a value on-chain, so the conservative default is
`call` and read-only methods must opt in explicitly. -/
inductive EntrypointMutability where
  | call
  | view
  deriving Repr, BEq, DecidableEq, Inhabited

def EntrypointMutability.id : EntrypointMutability → String
  | .call => "call"
  | .view => "view"

structure Entrypoint where
  name : String
  kind : EntrypointKind := .function
  mutability : EntrypointMutability := .call
  /-- Optional target dispatch tag. On EVM this is the 4-byte selector hex;
  other targets may use it as an instruction discriminator or ignore it. -/
  selector? : Option String := none
  params : Array (String × ValueType) := #[]
  /-- Parallel ABI surface overrides for selector/signature metadata
  (`some "address"`, etc.). Historically EVM-only (`paramEvmAbiWords`); kept
  chain-neutral so other ABI-bearing targets can reuse the same field (D-050). -/
  paramAbiWords : Array (Option String) := #[]
  returns : ValueType := .unit
  /-- Optional host ABI override for the return carrier. -/
  returnAbiWord? : Option String := none
  body : Array Statement
  deriving Repr

/-- Compatibility alias for the pre-D-050 EVM-specific field name. -/
abbrev Entrypoint.paramEvmAbiWords (ep : Entrypoint) : Array (Option String) :=
  ep.paramAbiWords

/-- Host ABI scalar type for one named event field. Event expressions retain
their portable IR carrier; target adapters use this declaration for canonical
event signatures and artifact metadata. -/
structure EventAbiWord where
  eventName : String
  fieldName : String
  abiWord : String
  deriving Repr, BEq

structure Module where
  name : String
  structs : Array StructDecl := #[]
  state : Array StateDecl
  entrypoints : Array Entrypoint
  /-- Named event-field ABI overrides, parallel to `Entrypoint.paramAbiWords`.
  Names keep the declaration stable when indexed and data fields are split. -/
  eventAbiWords : Array EventAbiWord := #[]
  allocator : AllocatorConfig := defaultAllocator
  /-- When set to `uups`, the EVM adapter adds a delegatecall fallback for
  proxy shells. Stored on the module as target-resolved metadata rather than a
  portable effect (D-050); non-EVM backends must ignore or reject it. -/
  proxyPattern? : Option String := none
  /-- NEAR EmitWat host strings indexed by `.literal (.address i)` (remote account/method
      names and local promise callback method names). Target-family metadata, not a
      portable IR constructor (see `IR.Portability`). -/
  nearCrosscallStrings : Array String := #[]
  /-- Integer-overflow mode for this module's `Expr.add/.sub/.mul` nodes.

      `false` (default): portable wrapping arithmetic — matches Solana (sBPF
      `add64`/`mul64`) and NEAR (Wasm `i64.add`) native behavior. This is the
      safe cross-target default.
      `true`: checked arithmetic that reverts on overflow — matches EVM
      Solidity-0.8 semantics. A module that sets this declares the
      `arith.checked` capability and can only resolve to a target profile that
      also declares it (currently EVM-only). See `docs/capability-registry.md`
      "Semantic Divergence Notes — `arith.checked`" and FV-5 in
      `docs/formal-verification.md`. -/
  overflowChecked : Bool := false
  deriving Repr

/-- Compatibility alias for the pre-D-050 EVM-specific field name. -/
abbrev Module.evmProxyPattern? (module : Module) : Option String :=
  module.proxyPattern?

def Effect.capability : Effect → ProofForge.Target.Capability
  | .storageScalarRead _ => .storageScalar
  | .storageScalarWrite _ _ => .storageScalar
  | .storageScalarAssignOp _ _ _ => .storageScalar
  | .storageMapContains _ _ => .storageMap
  | .storageMapGet _ _ => .storageMap
  | .storageMapInsert _ _ _ => .storageMap
  | .storageMapSet _ _ _ => .storageMap
  | .storageMapDelete _ _ => .storageMap
  | .storageArrayRead _ _ => .storageArray
  | .storageArrayWrite _ _ _ => .storageArray
  | .storageArrayStructFieldRead _ _ _ => .storageArray
  | .storageArrayStructFieldWrite _ _ _ _ => .storageArray
  | .storageDynamicArrayPush _ _ => .storageArray
  | .storageDynamicArrayPop _ => .storageArray
  | .memoryArraySet _ _ _ => .dataDynamicArray
  | .storageStructFieldRead _ _ => .storageScalar
  | .storageStructFieldWrite _ _ _ => .storageScalar
  | .storagePathRead _ path =>
      if path.any (fun segment => match segment with | .mapKey _ => true | _ => false) then
        .storageMap
      else
        .storageScalar
  | .storagePathWrite _ path _ =>
      if path.any (fun segment => match segment with | .mapKey _ => true | _ => false) then
        .storageMap
      else
        .storageScalar
  | .storagePathAssignOp _ path _ _ =>
      if path.any (fun segment => match segment with | .mapKey _ => true | _ => false) then
        .storageMap
      else
        .storageScalar
  | .contextRead field => field.capability
  | .eventEmit _ _ => .eventsEmit
  | .eventEmitIndexed _ _ _ => .eventsEmit
  | .checkErc721Received _ _ _ _ => .crosscallInvoke
  | .checkErc1155Received _ _ _ _ _ => .crosscallInvoke
  | .checkErc1155BatchReceived _ _ _ _ _ => .crosscallInvoke

mutual
  partial def Expr.capabilities : Expr → Array ProofForge.Target.Capability
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit elementType values =>
        elementType.capabilities ++ values.foldl (fun acc value => acc ++ value.capabilities) #[.dataFixedArray]
    | .arrayGet array index =>
        #[.dataFixedArray] ++ array.capabilities ++ index.capabilities
    | .memoryArrayNew elementType length =>
        elementType.capabilities ++ length.capabilities ++ #[.dataDynamicArray]
    | .memoryArrayLength array =>
        #[.dataDynamicArray] ++ array.capabilities
    | .memoryArrayGet array index =>
        #[.dataDynamicArray] ++ array.capabilities ++ index.capabilities
    | .structLit _ fields =>
        fields.foldl (fun acc field => acc ++ field.snd.capabilities) #[.dataStruct]
    | .field base _ =>
        #[.dataStruct] ++ base.capabilities
    | .add lhs rhs _ => lhs.capabilities ++ rhs.capabilities
    | .sub lhs rhs _ => lhs.capabilities ++ rhs.capabilities
    | .mul lhs rhs _ => lhs.capabilities ++ rhs.capabilities
    | .div lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .mod lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .pow lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .bitAnd lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .bitOr lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .bitXor lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .shiftLeft lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .shiftRight lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .cast value targetType => value.capabilities ++ targetType.capabilities
    | .eq lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .ne lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .lt lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .le lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .gt lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .ge lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .boolAnd lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .boolOr lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .boolNot value => value.capabilities
    | .hashValue a b c d => a.capabilities ++ b.capabilities ++ c.capabilities ++ d.capabilities
    | .hash preimage => #[.cryptoHash] ++ preimage.capabilities
    | .hashTwoToOne lhs rhs => #[.cryptoHash] ++ lhs.capabilities ++ rhs.capabilities
    | .ecrecover digest v r s =>
        #[.cryptoEcrecover] ++ digest.capabilities ++ v.capabilities ++ r.capabilities ++ s.capabilities
    | .eip712PermitDigest owner spender value nonce deadline domainSep =>
        #[.cryptoEcrecover, .cryptoHash] ++ owner.capabilities ++ spender.capabilities ++
          value.capabilities ++ nonce.capabilities ++ deadline.capabilities ++ domainSep.capabilities
    | .nativeValue => #[.valueNative]
    | .crosscallNamed _ _ args returnType =>
        #[.crosscallNamed] ++ returnType.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallAbiPacked target _selector _stores _argsSize _outSize _dynOff dynLen?
        _dynTgtOffs dynTargets =>
        let caps := #[.crosscallInvoke] ++ target.capabilities
        let caps :=
          match dynLen? with
          | none => caps
          | some len => caps ++ len.capabilities
        dynTargets.foldl (init := caps) fun acc t => acc ++ t.capabilities
    | .crosscallInvoke target methodId args =>
        #[.crosscallInvoke] ++ target.capabilities ++ methodId.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallInvokeTyped target methodId args returnType =>
        #[.crosscallInvoke] ++ target.capabilities ++ methodId.capabilities ++ returnType.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallInvokeValueTyped target methodId callValue args returnType =>
        #[.crosscallInvoke] ++ target.capabilities ++ methodId.capabilities ++ callValue.capabilities ++
          returnType.capabilities ++ args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallInvokeStaticTyped target methodId args returnType =>
        #[.crosscallInvoke] ++ target.capabilities ++ methodId.capabilities ++ returnType.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallInvokeDelegateTyped target methodId args returnType =>
        #[.crosscallInvoke] ++ target.capabilities ++ methodId.capabilities ++ returnType.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .crosscallCreate callValue _ =>
        #[.crosscallInvoke] ++ callValue.capabilities
    | .crosscallCreate2 callValue salt _ =>
        #[.crosscallInvoke] ++ callValue.capabilities ++ salt.capabilities
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        #[.nearPromise] ++ accountIndex.capabilities ++ methodId.capabilities ++ deposit.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        #[.nearPromise] ++ parentPromise.capabilities ++ callbackMethod.capabilities ++ deposit.capabilities ++
          args.foldl (fun acc arg => acc ++ arg.capabilities) #[]
    | .nearPromiseResultsCount => #[.nearPromise]
    | .nearPromiseResultStatus index => #[.nearPromise] ++ index.capabilities
    | .nearPromiseResultU64 index => #[.nearPromise] ++ index.capabilities
    | .effect effect => #[effect.capability] ++ effect.capabilities

  partial def Effect.capabilities : Effect → Array ProofForge.Target.Capability
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value => value.capabilities
    | .storageScalarAssignOp _ _ value => value.capabilities
    | .storageMapContains _ key => key.capabilities
    | .storageMapGet _ key => key.capabilities
    | .storageMapInsert _ key value => key.capabilities ++ value.capabilities
    | .storageMapSet _ key value => key.capabilities ++ value.capabilities
    | .storageMapDelete _ key => key.capabilities
    | .storageArrayRead _ index => index.capabilities
    | .storageArrayWrite _ index value => index.capabilities ++ value.capabilities
    | .storageArrayStructFieldRead _ index _ => #[.dataStruct] ++ index.capabilities
    | .storageArrayStructFieldWrite _ index _ value => #[.dataStruct] ++ index.capabilities ++ value.capabilities
    | .storageDynamicArrayPush _ value => value.capabilities
    | .storageDynamicArrayPop _ => #[]
    | .memoryArraySet array index value =>
        array.capabilities ++ index.capabilities ++ value.capabilities
    | .storageStructFieldRead _ _ => #[.dataStruct]
    | .storageStructFieldWrite _ _ value => #[.dataStruct] ++ value.capabilities
    | .storagePathRead _ path => path.foldl (fun acc segment => acc ++ segment.capabilities) #[]
    | .storagePathWrite _ path value => path.foldl (fun acc segment => acc ++ segment.capabilities) value.capabilities
    | .storagePathAssignOp _ path _ value => path.foldl (fun acc segment => acc ++ segment.capabilities) value.capabilities
    | .contextRead _ => #[]
    | .eventEmit _ fields => fields.foldl (fun acc field => acc ++ field.snd.capabilities) #[]
    | .eventEmitIndexed _ indexedFields dataFields =>
        indexedFields.foldl (fun acc field => acc ++ field.snd.capabilities)
          (dataFields.foldl (fun acc field => acc ++ field.snd.capabilities) #[])
    | .checkErc721Received operator fromAddr toAddr tokenId =>
        operator.capabilities ++ fromAddr.capabilities ++ toAddr.capabilities ++ tokenId.capabilities
    | .checkErc1155Received operator fromAddr toAddr id amount =>
        operator.capabilities ++ fromAddr.capabilities ++ toAddr.capabilities ++
          id.capabilities ++ amount.capabilities
    | .checkErc1155BatchReceived operator fromAddr toAddr ids amounts =>
        operator.capabilities ++ fromAddr.capabilities ++ toAddr.capabilities ++
          ids.capabilities ++ amounts.capabilities

  partial def StoragePathSegment.capabilities : StoragePathSegment → Array ProofForge.Target.Capability
    | .field _ => #[.dataStruct]
    | .index index => #[.dataFixedArray] ++ index.capabilities
    | .mapKey key => #[.storageMap] ++ key.capabilities
end

def StructField.capabilities (field : StructField) : Array ProofForge.Target.Capability :=
  field.type.capabilities

def StructDecl.capabilities (decl : StructDecl) : Array ProofForge.Target.Capability :=
  #[.dataStruct] ++
    (if decl.semantics == .linearRecord then #[.dataLinearRecord] else #[]) ++
    decl.fields.foldl (fun acc field => acc ++ field.capabilities) #[]

def StateDecl.capabilities (state : StateDecl) : Array ProofForge.Target.Capability :=
  match state.kind with
  | .scalar => state.type.capabilities
  | .map keyType _ => #[.storageMap] ++ keyType.capabilities ++ state.type.capabilities
  | .array _ => #[.storageArray, .dataFixedArray] ++ state.type.capabilities
  | .dynamicArray => #[.storageArray, .dataDynamicArray] ++ state.type.capabilities

def Statement.capabilities : Statement → Array ProofForge.Target.Capability
  | .letBind _ type value => type.capabilities ++ value.capabilities
  | .letMutBind _ type value => type.capabilities ++ value.capabilities
  | .assign target value => target.capabilities ++ value.capabilities
  | .assignOp target _ value => target.capabilities ++ value.capabilities
  | Statement.effect eff => #[eff.capability] ++ eff.capabilities
  | .assert condition _ _ => #[.assertions] ++ condition.capabilities
  | .assertEq lhs rhs _ _ => #[.assertions] ++ lhs.capabilities ++ rhs.capabilities
  | .revert _ => #[.assertions]
  | .revertWithError _ => #[.assertions]
  | .release _ => #[]
  | .ifElse condition thenBody elseBody =>
      #[.controlConditional] ++ condition.capabilities ++
        thenBody.foldl (fun acc stmt => acc ++ stmt.capabilities) #[] ++
        elseBody.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]
  | .boundedFor _ _ _ body =>
      #[.controlBoundedLoop] ++ body.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]
  | .whileLoop condition body =>
      #[.controlUnboundedLoop] ++ condition.capabilities ++
        body.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]
  | .return value => value.capabilities

def Entrypoint.capabilities (entrypoint : Entrypoint) : Array ProofForge.Target.Capability :=
  let paramCaps := entrypoint.params.foldl (fun acc param => acc ++ param.snd.capabilities) #[]
  paramCaps ++ entrypoint.returns.capabilities ++
    entrypoint.body.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]

def Module.capabilities (module : Module) : Array ProofForge.Target.Capability :=
  module.structs.foldl (fun acc decl => acc ++ decl.capabilities) #[] ++
    module.state.foldl (fun acc state => acc ++ state.capabilities) #[] ++
    module.entrypoints.foldl (fun acc entrypoint => acc ++ entrypoint.capabilities) #[] ++
    (if module.overflowChecked then #[.checkedArithmetic] else #[])

end ProofForge.IR
