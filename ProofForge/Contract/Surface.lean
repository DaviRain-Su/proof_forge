import Lean
import ProofForge.Contract.Builder

namespace ProofForge.Contract.Surface

open ProofForge.IR

abbrev ModuleM := ProofForge.Contract.Builder.ModuleM
abbrev EntryM := ProofForge.Contract.Builder.EntryM

structure ScalarRef where
  id : String
  type : ValueType
  deriving BEq, Repr

structure BindingRef where
  id : String
  type : ValueType
  /-- Optional host ABI word override (EVM materialization today). Prefer
  portable `ValueType` defaults; set only when the host encoding must differ. -/
  abiWord? : Option String := none
  deriving BEq, Repr

/-- Historical field name — prefer `abiWord?`. -/
def BindingRef.evmAbiWord? (b : BindingRef) : Option String :=
  b.abiWord?

structure MethodRef where
  name : String
  /-- Optional 4-byte method id for EVM dispatch; portable sources leave `none`
  and let CLI/`cast` hydrate. -/
  selector? : Option String := none
  params : Array BindingRef := #[]
  returns : ValueType := .unit
  deriving BEq, Repr

structure EventRef where
  name : String
  deriving BEq, Repr

structure EventField where
  name : String
  value : ProofForge.IR.Expr
  deriving Repr

def contract (name : String) (body : ModuleM Unit) : ContractSpec :=
  ProofForge.Contract.Builder.build name body

def declareConstructorParam (name : String) (abiType : String) : ModuleM Unit :=
  ProofForge.Contract.Builder.constructorParam name abiType

def declareEventAbi (eventName : String) (fields : Array (String × String)) : ModuleM Unit :=
  ProofForge.Contract.Builder.eventAbi eventName fields

def declareConstructorInitBinding
    (stateId paramName : String) (kind : ProofForge.Contract.ConstructorInitKind) : ModuleM Unit :=
  ProofForge.Contract.Builder.constructorInitBinding stateId paramName kind

def setUpgradePolicy (policy : ProofForge.Contract.UpgradePolicy) : ModuleM Unit :=
  ProofForge.Contract.Builder.upgradePolicy policy

def setProxyPattern (pattern : ProofForge.Contract.ProxyPattern) : ModuleM Unit :=
  ProofForge.Contract.Builder.proxyPattern pattern

def declareQuintInvariant (name expr : String) : ModuleM Unit :=
  ProofForge.Contract.Builder.quintInvariant name expr

def declareQuintLiveness (name expr : String) : ModuleM Unit :=
  ProofForge.Contract.Builder.quintLiveness name expr

/-- Declare a named Lean invariant, linking it to a `State → Bool` predicate
function by qualified name. FV-8 / Track 1.7 authoring surface. -/
def declareLeanInvariant (name predicateFnName : String) : ModuleM Unit :=
  ProofForge.Contract.Builder.leanInvariant name predicateFnName

def slot (id : String) (type : ValueType) : ScalarRef :=
  { id, type }

/-- ERC-1967 implementation slot (`bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`). -/
def eip1967ImplementationId : String := "$eip1967.implementation"

def eip1967Implementation : ScalarRef :=
  slot eip1967ImplementationId .u64

def binding (id : String) (type : ValueType) : BindingRef :=
  { id, type }

/-- Binding with explicit host ABI word override (EVM materialization). -/
def bindingWithAbiWord (id : String) (type : ValueType) (abiWord : String) : BindingRef :=
  { id, type, abiWord? := some abiWord }

/-- Historical name — prefer `bindingWithAbiWord`. -/
def bindingWithAbi (id : String) (type : ValueType) (evmAbiWord : String) : BindingRef :=
  bindingWithAbiWord id type evmAbiWord

def event (name : String) : EventRef :=
  { name }

/-- Pin an EVM 4-byte selector for ABI fixtures only.

Prefer `method` on the portable product path; Shared examples and tutorials
must not require hand-written selectors (T4.1 / `docs/authoring-model.md`). -/
def methodWithSelector (name selector : String) (params : Array BindingRef := #[])
    (returns : ValueType := .unit) : MethodRef :=
  { name, selector? := some selector, params, returns }

/-- Default: name-only method (no EVM selector). Portable tutorials use this. -/
def method (name : String) (params : Array BindingRef := #[])
    (returns : ValueType := .unit) : MethodRef :=
  { name, selector? := none, params, returns }

private def identNameLit (name : Lean.TSyntax `ident) : Lean.TSyntax `term :=
  ⟨Lean.Syntax.mkStrLit name.getId.toString⟩

macro "state_ref " name:ident " : " type:term : command => do
  let nameLit := identNameLit name
  `(def $name : ScalarRef := slot $nameLit $type)

macro "state_decl " name:ident " : " type:term : command => do
  let nameLit := identNameLit name
  `(def $name : ScalarRef := slot $nameLit $type)

macro "binding_ref " name:ident " : " type:term : command => do
  let nameLit := identNameLit name
  `(def $name : BindingRef := binding $nameLit $type)

macro "binding_decl " name:ident " : " type:term : command => do
  let nameLit := identNameLit name
  `(def $name : BindingRef := binding $nameLit $type)

macro "event_ref " name:ident : command => do
  let nameLit := identNameLit name
  `(def $name : EventRef := event $nameLit)

macro "event_decl " name:ident : command => do
  let nameLit := identNameLit name
  `(def $name : EventRef := event $nameLit)

macro "method_ref " name:ident " : " params:term : command => do
  let nameLit := identNameLit name
  `(def $name : MethodRef := method $nameLit $params)

macro "method_ref " name:ident " returns " "(" returns:term ")" " : " params:term : command => do
  let nameLit := identNameLit name
  `(def $name : MethodRef := method $nameLit $params $returns)

macro "method_decl " name:ident " : " params:term : command => do
  let nameLit := identNameLit name
  `(def $name : MethodRef := method $nameLit $params)

macro "method_return_decl " name:ident " : " retTy:term " := " params:term : command => do
  let nameLit := identNameLit name
  `(def $name : MethodRef := method $nameLit $params $retTy)

macro "contract_decl " name:ident body:term : term => do
  let nameLit := identNameLit name
  `(contract $nameLit $body)

def scalar (ref : ScalarRef) : ModuleM Unit :=
  ProofForge.Contract.Builder.scalarState ref.id ref.type

def entryWithMutability (mutability : ProofForge.IR.EntrypointMutability)
    (methodRef : MethodRef) (body : EntryM Unit) : ModuleM Unit :=
  ProofForge.Contract.Builder.entryFull
    methodRef.name
    methodRef.selector?
    methodRef.returns
    (methodRef.params.map fun param => (param.id, param.type))
    (methodRef.params.map fun param => param.abiWord?)
    body
    mutability

def entry (methodRef : MethodRef) (body : EntryM Unit) : ModuleM Unit :=
  entryWithMutability .call methodRef body

def view (methodRef : MethodRef) (body : EntryM Unit) : ModuleM Unit :=
  entryWithMutability .view methodRef body

def bind (bindingRef : BindingRef) (value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.letBind bindingRef.id bindingRef.type value

def ref (bindingRef : BindingRef) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.localVar bindingRef.id

def read (slot : ScalarRef) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.storageScalarRead slot.id

def write (slot : ScalarRef) (value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (ProofForge.Contract.Builder.storageScalarWrite slot.id value)

def field (name : String) (value : ProofForge.IR.Expr) : EventField :=
  { name, value }

def fieldOf (bindingRef : BindingRef) : EventField :=
  field bindingRef.id (ref bindingRef)

def fieldAs (slot : ScalarRef) (value : ProofForge.IR.Expr) : EventField :=
  field slot.id value

def emitNamed (name : String) (fields : Array EventField) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (ProofForge.Contract.Builder.eventEmit name (fields.map fun field => (field.name, field.value)))

def emit (eventRef : EventRef) (fields : Array EventField) : EntryM Unit :=
  emitNamed eventRef.name fields

def emitIndexed (eventRef : EventRef) (indexedFields dataFields : Array EventField) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.eventEmitIndexed eventRef.name
      (indexedFields.map fun field => (field.name, field.value))
      (dataFields.map fun field => (field.name, field.value)))

def ret (value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.ret value

def checkpointId : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .checkpointId

def timestamp : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .timestamp

def epochHeight : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .epochHeight

def randomSeed : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .randomSeed

def u64 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.u64 value

def u32 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.u32 value

def boolOr (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.boolOr lhs rhs

def add (lhs rhs : ProofForge.IR.Expr) (overflowChecked : Bool := true) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.add lhs rhs overflowChecked

def sub (lhs rhs : ProofForge.IR.Expr) (overflowChecked : Bool := true) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.sub lhs rhs overflowChecked

def mul (lhs rhs : ProofForge.IR.Expr) (overflowChecked : Bool := true) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.mul lhs rhs overflowChecked

def div (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.div lhs rhs

def eq (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.eq lhs rhs

def ne (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.ne lhs rhs

def le (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.le lhs rhs

def ge (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.ge lhs rhs

def caller : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .userId

/-- This contract's address (`address(this)` / contract id). -/
def contractId : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .contractId

/-- NEAR predecessor account id as a full 32-byte hash (sha256 of account id bytes). -/
def callerHash : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .userIdHash

/-- The transaction signer (EVM `tx.origin` / NEAR `signer_account_id`).
    Distinct from `caller` (the immediate caller / predecessor). -/
def signer : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.contextRead .origin

def nativeValue : ProofForge.IR.Expr :=
  .nativeValue

def assertCondition (condition : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  ProofForge.Contract.Builder.assert condition message

def requireEq (lhs rhs : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  ProofForge.Contract.Builder.assertEq lhs rhs message

def requireNe (lhs rhs : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  assertCondition (ne lhs rhs) message

def requireGe (lhs rhs : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  assertCondition (ge lhs rhs) message

def requireNonZero (value : ProofForge.IR.Expr) (message : String) : EntryM Unit :=
  assertCondition (ne value (u64 0)) message

def requireZero (slot : ScalarRef) (message : String) : EntryM Unit :=
  requireEq (read slot) (u64 0) message

def requireOwner (ownerSlot : ScalarRef) (message : String := "not owner") : EntryM Unit :=
  requireEq caller (read ownerSlot) message

/-- Hash-width owner check: compare `callerHash` to a `.hash` owner slot.
- NEAR: full predecessor account id → sha256 Hash
- Solana: sha256(account[0] pubkey) limb0 handle (Phase-1 Hash)
- EVM: `keccak256` of 32-byte zero-padded `caller` (`hashWord(caller)`)
Use `requireOwner` (u64 triad) when address-width handles are preferred. -/
def requireOwnerHash (ownerSlot : ScalarRef) (message : String := "not owner") : EntryM Unit :=
  requireEq callerHash (read ownerSlot) message

def requireNotPaused (pausedSlot : ScalarRef) (message : String := "paused") : EntryM Unit :=
  requireEq (read pausedSlot) (u64 0) message

def requirePaused (pausedSlot : ScalarRef) (message : String := "not paused") : EntryM Unit :=
  requireNe (read pausedSlot) (u64 0) message

def requireUnlocked (lockSlot : ScalarRef) (message : String := "reentrant") : EntryM Unit :=
  requireEq (read lockSlot) (u64 0) message

structure MapRef where
  id : String
  keyType : ValueType
  valueType : ValueType
  capacity : Nat := 256
  deriving BEq, Repr

def mapState (ref : MapRef) : ModuleM Unit :=
  ProofForge.Contract.Builder.mapState ref.id ref.keyType ref.valueType ref.capacity

def mapGet (ref : MapRef) (key : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.storageMapGet ref.id key

def mapSet (ref : MapRef) (key value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (ProofForge.Contract.Builder.storageMapSet ref.id key value)

def mapKey (key : ProofForge.IR.Expr) : StoragePathSegment :=
  .mapKey key

def pathRead (stateId : String) (path : Array StoragePathSegment) : ProofForge.IR.Expr :=
  .effect (.storagePathRead stateId path)

def pathWrite (stateId : String) (path : Array StoragePathSegment) (value : ProofForge.IR.Expr) :
    EntryM Unit :=
  ProofForge.Contract.Builder.effect (.storagePathWrite stateId path value)

def allowancePath (ownerKey spenderKey : ProofForge.IR.Expr) : Array StoragePathSegment :=
  #[mapKey ownerKey, mapKey spenderKey]

def requireRole (members : MapRef) (roleKey accountKey : ProofForge.IR.Expr)
    (message : String := "missing role") : EntryM Unit :=
  requireNe (pathRead members.id (allowancePath roleKey accountKey)) (u64 0) message

def acquireLock (lockSlot : ScalarRef) : EntryM Unit := do
  requireUnlocked lockSlot
  write lockSlot (u64 1)

def releaseLock (lockSlot : ScalarRef) : EntryM Unit :=
  write lockSlot (u64 0)

/-- Mark the current entry as value-bearing (`msg.value` / `callvalue`). -/
def markPayable : EntryM Unit :=
  ProofForge.Contract.Builder.entryCapability .valueNative "contract_source.payable"

/-- Plain native transfer to an EOA or contract (EVM empty-calldata call with value). -/
def nativeTransfer (recipient amount : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.letBind "_sent" .u64
    (.crosscallInvokeValueTyped recipient (u64 0) amount #[] .u64)

/-- EVM ERC-721 safe-transfer receiver check (PF-P2-02).

If `to` has code (`extcodesize`), CALL
`onERC721Received(operator, from, tokenId, "")` and require the magic
`bytes4` return. EOAs skip the callback. Non-EVM targets reject this
effect. -/
def checkErc721Received (operator fromAddr toAddr tokenId : ProofForge.IR.Expr) :
    EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.checkErc721Received operator fromAddr toAddr tokenId)

/-- EVM ERC-1155 safe-transfer receiver check (PF-P2-02).

If `to` has code, CALL `onERC1155Received(operator, from, id, value, "")`
and require the magic `bytes4` return. EOAs skip the callback. -/
def checkErc1155Received
    (operator fromAddr toAddr id amount : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.checkErc1155Received operator fromAddr toAddr id amount)

/-- EVM ERC-1155 dynamic batch receiver check (E1.2).
If `to` has code, CALL
`onERC1155BatchReceived(operator, from, ids, amounts, "")`
and require the magic `bytes4` return. EOAs skip.
`ids` and `amounts` are array expressions (e.g. `arrayLit .u256 #[...]`). -/
def checkErc1155BatchReceived
    (operator fromAddr toAddr ids amounts : ProofForge.IR.Expr) :
    EntryM Unit :=
  ProofForge.Contract.Builder.effect
    (.checkErc1155BatchReceived operator fromAddr toAddr ids amounts)

/-- Portable cross-contract intent (family-shared). Backends materialize as
EVM CALL / Solana CPI / NEAR `promise_create` / Soroban `invoke_contract` —
authors never write CPI metas or Promise chains here. Prefer `declareRemote`
+ this call so Shared sources never mention host string pools. -/
def remoteCall (target method : ProofForge.IR.Expr) (args : Array ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  .crosscallInvoke target method args

/-- Opaque peer/method handle used by `remoteCall` (materializes as address
literal index into the host string pool on Wasm hosts; numeric handle on
EVM/Solana). Authors obtain handles only via `declareRemote` — not by
hand-indexing NEAR pools. -/
def peerHandle (idx : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.nearAddressLit idx

structure RemoteRef where
  target : ProofForge.IR.Expr
  method : ProofForge.IR.Expr
  deriving Repr

/-- Declare a portable remote peer + method once at module scope.
Auto-fills host string pool for Wasm-NEAR/Soroban; EVM/Solana ignore the
strings and use the handle indices. **This is the product path** — do not
call `registerNearCrosscallString` from Shared examples.

`peerId` is a **deployment identity string** (e.g. NEAR account id, or a
logical peer name resolved at deploy time) — not a chain-specific API call. -/
def declareRemote (peerId methodId : String) : ModuleM RemoteRef := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  let mIdx ← ProofForge.Contract.Builder.ensureCrosscallString methodId
  pure { target := peerHandle tIdx, method := peerHandle mIdx }

/-- Module-scope form for `contract_source` (`do declareRemoteUnit …;`).
Registers peer then method (deduped). First remote is handles 0 and 1. -/
def declareRemoteUnit (peerId methodId : String) : ModuleM Unit := do
  let _ ← declareRemote peerId methodId
  pure ()

/-- Sugar: `remoteCall` through a `RemoteRef` from `declareRemote`.

## Portable scalar ABI (T3.1)

`args` are portable IR expressions. Primary product types for multi-target
remote:

| IR type | EVM (Yul) | Solana CPI ix data | NEAR promise | Soroban invoke |
|---------|-----------|--------------------|--------------|----------------|
| `.u64` literal / expr | CALL arg word | LE u64 in ix data | serialized in args | args buffer |
| `.bool` | 0/1 word | LE u64 0/1 | same | same |
| `.hash` | 32-byte word | limb packing / host | host hash ptr | host hash |

Authors pass `#[u64 42, u64 7]` etc. Host encoding is materialization; do not
hand-write selectors or CPI account metas in Shared. See
`Examples/Product/RemoteCall.lean` (`call_with_args`). -/
def remoteCallRef (remote : RemoteRef) (args : Array ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  remoteCall remote.target remote.method args

def hash4 (a b c d : Nat) : ProofForge.IR.Expr :=
  .literal (.hash4 a b c d)

/-- EVM family-only CREATE2 deploy (init-code hex). **Not portable** — banned in
`Examples/Product` (`just portable-default`). Prefer portable `remoteCallRef` for
cross-contract intent; keep CREATE2 in EVM fixtures only (T4.3). -/
def create2Deploy (callValue salt : ProofForge.IR.Expr) (initCodeHex : String) : ProofForge.IR.Expr :=
  .crosscallCreate2 callValue salt initCodeHex

/-- Low-level host string-pool registration (Wasm-NEAR/Soroban materialize).
Prefer `declareRemote` on the portable product path. -/
def registerNearCrosscallString (value : String) : ModuleM Unit := do
  let _ ← ProofForge.Contract.Builder.ensureCrosscallString value
  pure ()

/-- Low-level handle; prefer `peerHandle` / `declareRemote` on portable path. -/
def nearAddressLit (idx : Nat) : ProofForge.IR.Expr :=
  peerHandle idx

/-- NEAR host-extension: low-level pool invoke. Prefer `remoteCall` + string pool. -/
def nearCrosscallPool (accountIndex methodId : ProofForge.IR.Expr) (args : Array ProofForge.IR.Expr)
    (deposit : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.nearCrosscallInvokePool accountIndex methodId args deposit

/-- NEAR host-extension only (`Source.Near`): `promise_then` chaining. -/
def nearPromiseThen (parentPromise callbackMethod : ProofForge.IR.Expr) (args : Array ProofForge.IR.Expr)
    (deposit : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.nearPromiseThen parentPromise callbackMethod args deposit

/-- NEAR host-extension only (`Source.Near`): decode callback result as u64. -/
def nearPromiseResultU64 (index : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.nearPromiseResultU64 index

def cast (value : ProofForge.IR.Expr) (target : ValueType) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.cast value target

def whenPositive (value : ProofForge.IR.Expr) (body : EntryM Unit) : EntryM Unit := do
  let (_, entryBuilder) := body.run {}
  ProofForge.Contract.Builder.ifElse (ProofForge.Contract.Builder.gt value (u64 0)) entryBuilder.body #[]

/-- Run `body` when `value == 0`. -/
def whenZero (value : ProofForge.IR.Expr) (body : EntryM Unit) : EntryM Unit := do
  let (_, entryBuilder) := body.run {}
  ProofForge.Contract.Builder.ifElse (ProofForge.Contract.Builder.eq value (u64 0)) entryBuilder.body #[]

/-- EVM `ecrecover(digest, v, r, s)` → address word. Requires `crypto.ecrecover`. -/
def ecrecover (digest v r s : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .ecrecover digest v r s

/-- EIP-712 permit digest for ERC-2612 (EVM helper). -/
def eip712PermitDigest (owner spender value nonce deadline domainSep : ProofForge.IR.Expr) :
    ProofForge.IR.Expr :=
  .eip712PermitDigest owner spender value nonce deadline domainSep

end ProofForge.Contract.Surface
