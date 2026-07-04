import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.Capability
import ProofForge.IR.Allocator

namespace ProofForge.IR

inductive ValueType where
  | unit
  | bool
  | u32
  | u64
  | address
  | bytes
  | string
  | hash
  | fixedArray (element : ValueType) (length : Nat)
  | structType (name : String)
  deriving BEq, DecidableEq, Repr

def ValueType.name : ValueType → String
  | .unit => "Unit"
  | .bool => "Bool"
  | .u32 => "U32"
  | .u64 => "U64"
  | .address => "Address"
  | .bytes => "Bytes"
  | .string => "String"
  | .hash => "Hash"
  | .fixedArray element length => s!"Array<{element.name},{length}>"
  | .structType name => name

def ValueType.capabilities : ValueType → Array ProofForge.Target.Capability
  | .unit => #[]
  | .bool => #[]
  | .u32 => #[]
  | .u64 => #[]
  | .address => #[]
  | .bytes => #[.dataDynamicBytes]
  | .string => #[.dataDynamicBytes]
  | .hash => #[]
  | .fixedArray element _ => #[.dataFixedArray] ++ element.capabilities
  | .structType _ => #[.dataStruct]

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
  deriving Repr

inductive StateKind where
  | scalar
  | map (keyType : ValueType) (capacity : Nat)
  | array (length : Nat)
  deriving BEq, DecidableEq, Repr

structure StateDecl where
  id : String
  kind : StateKind
  type : ValueType
  deriving Repr

inductive Literal where
  | u32 (value : Nat)
  | u64 (value : Nat)
  | bool (value : Bool)
  | hash4 (a b c d : Nat)
  | address (value : Nat)
  deriving BEq, Repr

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
    | contractId
    | checkpointId
    | timestamp
    | chainId
    | gasPrice
    | gasLeft
    | baseFee
    | prevRandao
    | origin
    | coinbase
    | blockHash (blockNumber : Expr)
    deriving Repr

  inductive Expr where
    | literal (value : Literal)
    | local (name : String)
    | arrayLit (elementType : ValueType) (values : Array Expr)
    | arrayGet (array index : Expr)
    | structLit (typeName : String) (fields : Array (String × Expr))
    | field (base : Expr) (fieldName : String)
    | add (lhs rhs : Expr)
    | sub (lhs rhs : Expr)
    | mul (lhs rhs : Expr)
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
    | nativeValue
    | crosscallInvoke (targetContractId : Expr) (methodId : Expr) (args : Array Expr)
    | crosscallInvokeTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeValueTyped (targetContractId : Expr) (methodId callValue : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeStaticTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallInvokeDelegateTyped (targetContractId : Expr) (methodId : Expr) (args : Array Expr) (returnType : ValueType)
    | crosscallCreate (callValue : Expr) (initCodeHex : String)
    | crosscallCreate2 (callValue salt : Expr) (initCodeHex : String)
    | effect (effect : Effect)
    deriving Repr

  inductive Effect where
    | storageScalarRead (stateId : String)
    | storageScalarWrite (stateId : String) (value : Expr)
    | storageScalarAssignOp (stateId : String) (op : AssignOp) (value : Expr)
    | storageMapContains (stateId : String) (key : Expr)
    | storageMapGet (stateId : String) (key : Expr)
    | storageMapInsert (stateId : String) (key value : Expr)
    | storageMapSet (stateId : String) (key value : Expr)
    | storageArrayRead (stateId : String) (index : Expr)
    | storageArrayWrite (stateId : String) (index value : Expr)
    | storageArrayStructFieldRead (stateId : String) (index : Expr) (fieldName : String)
    | storageArrayStructFieldWrite (stateId : String) (index : Expr) (fieldName : String) (value : Expr)
    | storageStructFieldRead (stateId fieldName : String)
    | storageStructFieldWrite (stateId fieldName : String) (value : Expr)
    | storagePathRead (stateId : String) (path : Array StoragePathSegment)
    | storagePathWrite (stateId : String) (path : Array StoragePathSegment) (value : Expr)
    | storagePathAssignOp (stateId : String) (path : Array StoragePathSegment) (op : AssignOp) (value : Expr)
    | contextRead (field : ContextField)
    | eventEmit (name : String) (fields : Array (String × Expr))
    | eventEmitIndexed (name : String) (indexedFields dataFields : Array (String × Expr))
    deriving Repr

  inductive StoragePathSegment where
    | field (fieldName : String)
    | index (index : Expr)
    | mapKey (key : Expr)
    deriving Repr
end

def ContextField.name : ContextField → String
  | .userId => "userId"
  | .contractId => "contractId"
  | .checkpointId => "checkpointId"
  | .timestamp => "timestamp"
  | .chainId => "chainId"
  | .gasPrice => "gasPrice"
  | .gasLeft => "gasLeft"
  | .baseFee => "baseFee"
  | .prevRandao => "prevRandao"
  | .origin => "origin"
  | .coinbase => "coinbase"
  | .blockHash _ => "blockHash"

def ContextField.capability : ContextField → ProofForge.Target.Capability
  | .userId | .origin => .callerSender
  | .contractId => .accountExplicit
  | .checkpointId | .timestamp | .chainId | .gasPrice | .gasLeft | .baseFee | .prevRandao | .coinbase | .blockHash _ => .envBlock

structure ErrorRef where
  assertionId : UInt32
  userCode? : Option String := none
  deriving Repr, BEq

inductive Statement where
  | letBind (name : String) (type : ValueType) (value : Expr)
  | letMutBind (name : String) (type : ValueType) (value : Expr)
  | assign (target value : Expr)
  | assignOp (target : Expr) (op : AssignOp) (value : Expr)
  | effect (effect : Effect)
  | assert (condition : Expr) (message : String) (errorRef? : Option ErrorRef := none)
  | assertEq (lhs rhs : Expr) (message : String) (errorRef? : Option ErrorRef := none)
  /-- Release an owned heap-backed local. This is intentionally name-based
      rather than pointer-based so later IR checkers can prove no use-after-free
      and no double-release properties over local ownership. -/
  | release (name : String)
  | ifElse (condition : Expr) (thenBody elseBody : Array Statement)
  | boundedFor (indexName : String) (start stopExclusive : Nat) (body : Array Statement)
  | return (value : Expr)
  deriving Repr

structure Entrypoint where
  name : String
  selector? : Option String := none
  params : Array (String × ValueType) := #[]
  /-- Parallel ABI word overrides for EVM selector/signature metadata (`some "address"`, etc.). -/
  paramEvmAbiWords : Array (Option String) := #[]
  returns : ValueType := .unit
  body : Array Statement
  deriving Repr

structure Module where
  name : String
  structs : Array StructDecl := #[]
  state : Array StateDecl
  entrypoints : Array Entrypoint
  allocator : AllocatorConfig := defaultAllocator
  /-- When set to `uups`, EVM lowering adds a delegatecall fallback for proxy shells. -/
  evmProxyPattern? : Option String := none
  deriving Repr

def Effect.capability : Effect → ProofForge.Target.Capability
  | .storageScalarRead _ => .storageScalar
  | .storageScalarWrite _ _ => .storageScalar
  | .storageScalarAssignOp _ _ _ => .storageScalar
  | .storageMapContains _ _ => .storageMap
  | .storageMapGet _ _ => .storageMap
  | .storageMapInsert _ _ _ => .storageMap
  | .storageMapSet _ _ _ => .storageMap
  | .storageArrayRead _ _ => .storageArray
  | .storageArrayWrite _ _ _ => .storageArray
  | .storageArrayStructFieldRead _ _ _ => .storageArray
  | .storageArrayStructFieldWrite _ _ _ _ => .storageArray
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

mutual
  partial def Expr.capabilities : Expr → Array ProofForge.Target.Capability
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit elementType values =>
        elementType.capabilities ++ values.foldl (fun acc value => acc ++ value.capabilities) #[.dataFixedArray]
    | .arrayGet array index =>
        #[.dataFixedArray] ++ array.capabilities ++ index.capabilities
    | .structLit _ fields =>
        fields.foldl (fun acc field => acc ++ field.snd.capabilities) #[.dataStruct]
    | .field base _ =>
        #[.dataStruct] ++ base.capabilities
    | .add lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .sub lhs rhs => lhs.capabilities ++ rhs.capabilities
    | .mul lhs rhs => lhs.capabilities ++ rhs.capabilities
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
    | .nativeValue => #[.valueNative]
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
    | .effect effect => #[effect.capability] ++ effect.capabilities

  partial def Effect.capabilities : Effect → Array ProofForge.Target.Capability
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value => value.capabilities
    | .storageScalarAssignOp _ _ value => value.capabilities
    | .storageMapContains _ key => key.capabilities
    | .storageMapGet _ key => key.capabilities
    | .storageMapInsert _ key value => key.capabilities ++ value.capabilities
    | .storageMapSet _ key value => key.capabilities ++ value.capabilities
    | .storageArrayRead _ index => index.capabilities
    | .storageArrayWrite _ index value => index.capabilities ++ value.capabilities
    | .storageArrayStructFieldRead _ index _ => #[.dataStruct] ++ index.capabilities
    | .storageArrayStructFieldWrite _ index _ value => #[.dataStruct] ++ index.capabilities ++ value.capabilities
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

  partial def StoragePathSegment.capabilities : StoragePathSegment → Array ProofForge.Target.Capability
    | .field _ => #[.dataStruct]
    | .index index => #[.dataFixedArray] ++ index.capabilities
    | .mapKey key => #[.storageMap] ++ key.capabilities
end

def StructField.capabilities (field : StructField) : Array ProofForge.Target.Capability :=
  field.type.capabilities

def StructDecl.capabilities (decl : StructDecl) : Array ProofForge.Target.Capability :=
  #[.dataStruct] ++ decl.fields.foldl (fun acc field => acc ++ field.capabilities) #[]

def StateDecl.capabilities (state : StateDecl) : Array ProofForge.Target.Capability :=
  match state.kind with
  | .scalar => state.type.capabilities
  | .map keyType _ => #[.storageMap] ++ keyType.capabilities ++ state.type.capabilities
  | .array _ => #[.storageArray, .dataFixedArray] ++ state.type.capabilities

def Statement.capabilities : Statement → Array ProofForge.Target.Capability
  | .letBind _ type value => type.capabilities ++ value.capabilities
  | .letMutBind _ type value => type.capabilities ++ value.capabilities
  | .assign target value => target.capabilities ++ value.capabilities
  | .assignOp target _ value => target.capabilities ++ value.capabilities
  | Statement.effect eff => #[eff.capability] ++ eff.capabilities
  | .assert condition _ _ => #[.assertions] ++ condition.capabilities
  | .assertEq lhs rhs _ _ => #[.assertions] ++ lhs.capabilities ++ rhs.capabilities
  | .release _ => #[]
  | .ifElse condition thenBody elseBody =>
      #[.controlConditional] ++ condition.capabilities ++
        thenBody.foldl (fun acc stmt => acc ++ stmt.capabilities) #[] ++
        elseBody.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]
  | .boundedFor _ _ _ body =>
      #[.controlBoundedLoop] ++ body.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]
  | .return value => value.capabilities

def Entrypoint.capabilities (entrypoint : Entrypoint) : Array ProofForge.Target.Capability :=
  let paramCaps := entrypoint.params.foldl (fun acc param => acc ++ param.snd.capabilities) #[]
  paramCaps ++ entrypoint.returns.capabilities ++
    entrypoint.body.foldl (fun acc stmt => acc ++ stmt.capabilities) #[]

def Module.capabilities (module : Module) : Array ProofForge.Target.Capability :=
  module.structs.foldl (fun acc decl => acc ++ decl.capabilities) #[] ++
    module.state.foldl (fun acc state => acc ++ state.capabilities) #[] ++
    module.entrypoints.foldl (fun acc entrypoint => acc ++ entrypoint.capabilities) #[]

end ProofForge.IR
