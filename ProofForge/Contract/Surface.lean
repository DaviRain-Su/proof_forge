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
  evmAbiWord? : Option String := none
  deriving BEq, Repr

structure MethodRef where
  name : String
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

def setUpgradePolicy (policy : ProofForge.Contract.UpgradePolicy) : ModuleM Unit :=
  ProofForge.Contract.Builder.upgradePolicy policy

def setProxyPattern (pattern : ProofForge.Contract.ProxyPattern) : ModuleM Unit :=
  ProofForge.Contract.Builder.proxyPattern pattern

def slot (id : String) (type : ValueType) : ScalarRef :=
  { id, type }

/-- ERC-1967 implementation slot (`bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`). -/
def eip1967ImplementationId : String := "$eip1967.implementation"

def eip1967Implementation : ScalarRef :=
  slot eip1967ImplementationId .u64

def binding (id : String) (type : ValueType) : BindingRef :=
  { id, type }

def bindingWithAbi (id : String) (type : ValueType) (evmAbiWord : String) : BindingRef :=
  { id, type, evmAbiWord? := some evmAbiWord }

def event (name : String) : EventRef :=
  { name }

def methodWithSelector (name selector : String) (params : Array BindingRef := #[])
    (returns : ValueType := .unit) : MethodRef :=
  { name, selector? := some selector, params, returns }

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

def entry (methodRef : MethodRef) (body : EntryM Unit) : ModuleM Unit :=
  ProofForge.Contract.Builder.entryFull
    methodRef.name
    methodRef.selector?
    methodRef.returns
    (methodRef.params.map fun param => (param.id, param.type))
    (methodRef.params.map fun param => param.evmAbiWord?)
    body

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

def u64 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.u64 value

def u32 (value : Nat) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.u32 value

def boolOr (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.boolOr lhs rhs

def add (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.add lhs rhs

def sub (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.sub lhs rhs

def mul (lhs rhs : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Builder.mul lhs rhs

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

def hash4 (a b c d : Nat) : ProofForge.IR.Expr :=
  .literal (.hash4 a b c d)

/-- Deterministic CREATE2 deployment of fixed init-code hex; returns the deployed address word. -/
def create2Deploy (callValue salt : ProofForge.IR.Expr) (initCodeHex : String) : ProofForge.IR.Expr :=
  .crosscallCreate2 callValue salt initCodeHex

end ProofForge.Contract.Surface
