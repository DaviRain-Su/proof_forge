/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Backend.Stylus

abbrev StylusValueId := Nat
abbrev StylusBlockId := Nat
abbrev StylusBytes := Array UInt8

inductive StylusAbiType where
  | bool
  | uint (bits : Nat)
  | address
  | fixedBytes (bytes : Nat)
  | bytes
  | string
  | fixedArray (elem : StylusAbiType) (size : Nat)
  | dynamicArray (elem : StylusAbiType)
  | tuple (fields : Array StylusAbiType)
  deriving Repr, BEq

def StylusAbiType.validUintBits : Array Nat := #[8, 16, 32, 64, 128, 160, 256]

def StylusAbiType.uint? (bits : Nat) : Option StylusAbiType :=
  if validUintBits.contains bits then some (.uint bits) else none

def StylusAbiType.fixedBytes? (bytes : Nat) : Option StylusAbiType :=
  if bytes >= 1 && bytes <= 32 then some (.fixedBytes bytes) else none

inductive StylusSlotExpr where
  | literal (slot : StylusBytes)
  | add (base : StylusSlotExpr) (offset : Nat)
  | mapping (base : StylusSlotExpr) (keyType : StylusAbiType)
  | dynamicBase (base : StylusSlotExpr)
  deriving Repr, BEq

inductive StylusHostOp where
  | storageLoad | storageCache | storageFlush
  | calldataSize | calldataCopy | writeResult | writeRevert
  | msgSender | msgValue | txOrigin | contractAddress
  | chainId | blockNumber | blockTimestamp | gasLeft | inkLeft
  | keccak256 | emitLog
  | callContract | staticCallContract | delegateCallContract | readReturnData
  deriving Repr, BEq, DecidableEq

inductive StylusCallMode where
  | call | staticCall | delegateCall
  deriving Repr, BEq, DecidableEq

inductive StylusOverflowMode where
  | wrapping
  | checked
  deriving Repr, BEq, DecidableEq

inductive StylusCompareOp where
  | eq | ne | lt | le | gt | ge
  deriving Repr, BEq, DecidableEq

inductive StylusLiteralPlan where
  | bool (value : Bool)
  | uint (value : Nat)
  | address (value : String)
  | fixedBytes (value : StylusBytes)
  deriving Repr, BEq

inductive StylusOpPlan where
  | literal (result : StylusValueId) (type : StylusAbiType) (value : StylusLiteralPlan)
  | add (result : StylusValueId) (type : StylusAbiType) (mode : StylusOverflowMode)
      (lhs rhs : StylusValueId)
  | sub (result : StylusValueId) (type : StylusAbiType) (mode : StylusOverflowMode)
      (lhs rhs : StylusValueId)
  | mul (result : StylusValueId) (type : StylusAbiType) (mode : StylusOverflowMode)
      (lhs rhs : StylusValueId)
  | div (result : StylusValueId) (type : StylusAbiType) (mode : StylusOverflowMode)
      (lhs rhs : StylusValueId)
  | storageLoad (result : StylusValueId) (wordId : String)
  | storageCache (wordId : String) (value : StylusValueId)
  | storagePathLoad (result : StylusValueId) (wordId : String) (keys : Array StylusValueId)
  | storagePathCache (wordId : String) (keys : Array StylusValueId) (value : StylusValueId)
  | contextRead (result : StylusValueId) (type : StylusAbiType) (operation : StylusHostOp)
  | compare (result : StylusValueId) (type : StylusAbiType) (op : StylusCompareOp)
      (lhs rhs : StylusValueId)
  | assert_ (condition : StylusValueId) (message : String)
  | emitEvent (eventId : String) (values : Array StylusValueId)
  deriving Repr, BEq

inductive StylusTerminatorPlan where
  | jump (target : StylusBlockId)
  | branch (condition : StylusValueId) (onTrue onFalse : StylusBlockId)
  | return (values : Array StylusValueId)
  | revert (errorId : String)
  deriving Repr, BEq

structure StylusBlockPlan where
  id : StylusBlockId
  operations : Array StylusOpPlan
  terminator : StylusTerminatorPlan
  deriving Repr, BEq

inductive RendererSupport where
  | planned
  | implemented
  | unsupported (reason : String)
  deriving Repr, BEq, DecidableEq

structure RendererSupportPlan where
  rustSdk : RendererSupport := .planned
  directWasm : RendererSupport := .planned
  deriving Repr, BEq, DecidableEq

structure StylusAbiParamPlan where
  name : String
  type : StylusAbiType
  deriving Repr, BEq

inductive StylusMutability where
  | call
  | view
  deriving Repr, BEq, DecidableEq

structure StylusAbiMethodPlan where
  name : String
  canonicalSignature : String
  selector : StylusBytes
  params : Array StylusAbiParamPlan := #[]
  returns : Array StylusAbiType := #[]
  payable : Bool := false
  mutability : StylusMutability := .call
  deriving Repr, BEq

structure StylusAbiErrorPlan where
  name : String
  canonicalSignature : String
  selector : StylusBytes
  params : Array StylusAbiParamPlan := #[]
  deriving Repr, BEq

structure StylusAbiPlan where
  methods : Array StylusAbiMethodPlan
  errors : Array StylusAbiErrorPlan
  deriving Repr, BEq

structure StylusStorageWordPlan where
  id : String
  slot : StylusSlotExpr
  byteOffset : Nat := 0
  byteWidth : Nat := 32
  type : StylusAbiType
  keyTypes : Array StylusAbiType := #[]
  deriving Repr, BEq

structure StylusStoragePlan where
  words : Array StylusStorageWordPlan
  deriving Repr, BEq

structure StylusFunctionParamPlan where
  valueId : StylusValueId
  name : String
  type : StylusAbiType
  deriving Repr, BEq

structure StylusFunctionPlan where
  id : String
  abiMethod : String
  params : Array StylusFunctionParamPlan := #[]
  entryBlock : StylusBlockId
  blocks : Array StylusBlockPlan
  support : RendererSupportPlan := {}
  deriving Repr, BEq

structure StylusEventFieldPlan where
  name : String
  type : StylusAbiType
  indexed : Bool := false
  deriving Repr, BEq

structure StylusEventPlan where
  id : String
  canonicalSignature : String
  topic0 : StylusBytes
  fields : Array StylusEventFieldPlan := #[]
  support : RendererSupportPlan := {}
  deriving Repr, BEq

structure StylusCallPlan where
  id : String
  mode : StylusCallMode
  target : StylusValueId
  calldata : StylusValueId
  value? : Option StylusValueId := none
  gas? : Option StylusValueId := none
  support : RendererSupportPlan := {}
  deriving Repr, BEq

structure StylusHostOpPlan where
  id : String
  functionId : String
  operation : StylusHostOp
  support : RendererSupportPlan := {}
  deriving Repr, BEq

structure StylusResourcePlan where
  maxMemoryPages : Nat
  requiresStorageFlush : Bool
  deriving Repr, BEq

structure StylusArtifactPlan where
  solidityAbi : Bool
  typescriptClient : Bool
  deriving Repr, BEq

structure StylusPlan where
  targetId : String
  moduleName : String
  abi : StylusAbiPlan
  storage : StylusStoragePlan
  functions : Array StylusFunctionPlan
  events : Array StylusEventPlan
  calls : Array StylusCallPlan
  hostOps : Array StylusHostOpPlan
  resources : StylusResourcePlan
  artifacts : StylusArtifactPlan
  deriving Repr, BEq

end ProofForge.Backend.Stylus
