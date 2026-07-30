import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2

/-- Legacy alpha requirement enum. Product ProgramV1 requirements use only
    `Semantic.WireV1.ProgramRequirementsV1`; product import roots forbid this
    `Core.Source` compatibility module. -/
inductive ProgramRequirement where
  | persistentState
  | checkedArithmetic
  | transactionalRollback
  | synchronousCall
  | asynchronousWorkflow
  | privateWitness
  | eventEmission
  | callerContext
  | boolValues
  | commitmentDisclosure
  | fieldBn254
  | privateState
  | commitmentState
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace ProgramRequirement

def id : ProgramRequirement → String
  | .persistentState => "state.persistent"
  | .checkedArithmetic => "value.checked-arithmetic"
  | .transactionalRollback => "failure.atomic-rollback"
  | .synchronousCall => "effect.synchronous-call"
  | .asynchronousWorkflow => "effect.asynchronous-workflow"
  | .privateWitness => "disclosure.private-witness"
  | .eventEmission => "effect.event"
  | .callerContext => "context.caller"
  | .boolValues => "value.bool"
  | .commitmentDisclosure => "disclosure.commitment"
  | .fieldBn254 => "value.field.bn254-fr"
  | .privateState => "disclosure.private-state"
  | .commitmentState => "disclosure.commitment-state"

instance : ToString ProgramRequirement := ⟨id⟩

end ProgramRequirement
end ProofForgeV2

namespace ProofForgeV2.Source

abbrev ArrayLength := Fin 4097

inductive ValueType where
  | u64
  | bool
  | field
  | u8
  | u16
  | u32
  | u128
  | u256
  | i8
  | i16
  | i32
  | i64
  | i128
  | i256
  | unit
  | principal
  | option (element : ValueType)
  | bytes (length : UInt32)
  | array (element : ValueType) (length : ArrayLength)
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

inductive Visibility where
  | verifierVisible
  | proverWitness
  | commitmentOnly
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

structure Param where
  name : String
  type : ValueType
  visibility : Visibility := .verifierVisible
  deriving BEq, Inhabited, Repr

structure StateDecl where
  name : String
  type : ValueType
  visibility : Visibility := .verifierVisible
  deriving BEq, Inhabited, Repr

structure FieldDecl where
  name : String
  type : ValueType
  deriving BEq, Inhabited, Repr

structure StructDecl where
  name : String
  fields : Array FieldDecl
  deriving BEq, Inhabited, Repr

structure EnumVariant where
  name : String
  payloadTypes : Array ValueType
  deriving BEq, Inhabited, Repr

structure EnumDecl where
  name : String
  variants : Array EnumVariant
  deriving BEq, Inhabited, Repr

structure EventDecl where
  name : String
  params : Array Param
  deriving BEq, Inhabited, Repr

structure ErrorDecl where
  name : String
  params : Array Param
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | variable (name : String)
  | state (name : String)
  | checkedAdd (lhs rhs : Expr)
  | boolLiteral (value : Bool)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedNeg (operand : Expr)
  | bitwiseNot (operand : Expr)
  | logicalNot (operand : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | shiftLeft (lhs rhs : Expr)
  | shiftRight (lhs rhs : Expr)
  | equal (lhs rhs : Expr)
  | notEqual (lhs rhs : Expr)
  | lessThan (lhs rhs : Expr)
  | lessEqual (lhs rhs : Expr)
  | greaterThan (lhs rhs : Expr)
  | greaterEqual (lhs rhs : Expr)
  | bitwiseAnd (lhs rhs : Expr)
  | bitwiseXor (lhs rhs : Expr)
  | bitwiseOr (lhs rhs : Expr)
  | logicalAnd (lhs rhs : Expr)
  | logicalOr (lhs rhs : Expr)
  | stringLiteral (value : String)
  | localFnCall (callee : String) (args : Array Expr)
  | constructorExpr (path : Array String) (args : Array Expr)
  | indexAccess (base : String) (index : Expr)
  deriving BEq, Inhabited, Repr

structure ConstDecl where
  name : String
  type : ValueType
  value : Expr
  deriving BEq, Inhabited, Repr

abbrev IterationBound := Fin 4097

inductive Statement where
  | assign (stateName : String) (value : Expr)
  | returnValue (value : Expr)
  | returnUnit
  | synchronousCall (callee : String)
  | letDecl (name : String) (typeAnn : Option ValueType) (value : Expr)
  | assertStmt (condition : Expr)
  | assertErrorStmt (condition : Expr) (errorName : String)
  | revertStmt (errorName : String) (args : Array Expr)
  | emitStmt (eventName : String) (args : Array Expr)
  | ifStmt (condition : Expr) (thenBody : Array Statement) (elseBody : Option (Array Statement))
  | forStmt (iterator : String) (start stopExclusive : Expr) (maxIterations : IterationBound) (body : Array Statement)
  deriving BEq, Inhabited, Repr

inductive EntryMode where
  | mutate
  | view
  deriving BEq, Inhabited, Repr

structure Initializer where
  params : Array Param
  body : Array Statement
  deriving BEq, Inhabited, Repr

structure Entry where
  name : String
  params : Array Param
  result : ValueType
  mode : EntryMode
  body : Array Statement
  deriving BEq, Inhabited, Repr

structure FnDecl where
  name : String
  params : Array Param
  result : ValueType
  body : Array Statement
  deriving BEq, Inhabited, Repr

structure InvariantDecl where
  name : String
  predicate : Expr
  deriving BEq, Inhabited, Repr

structure ExtensionReq where
  id : String
  version : String
  digest : String
  deriving BEq, Inhabited, Repr

structure ProofDecl where
  invariant : String
  «theorem» : Array String
  deriving BEq, Inhabited, Repr

inductive Item where
  | stateDecl (decl : StateDecl)
  | structDecl (decl : StructDecl)
  | enumDecl (decl : EnumDecl)
  | constDecl (decl : ConstDecl)
  | eventDecl (decl : EventDecl)
  | errorDecl (decl : ErrorDecl)
  | initializer (decl : Initializer)
  | entry (decl : Entry)
  | fnDecl (decl : FnDecl)
  | invariantDecl (decl : InvariantDecl)
  | extensionReq (decl : ExtensionReq)
  | proofDecl (decl : ProofDecl)
  deriving BEq, Inhabited, Repr

structure Program where
  qualifiedName : String
  name : String
  state : Array StateDecl
  structs : Array StructDecl := #[]
  enums : Array EnumDecl := #[]
  consts : Array ConstDecl := #[]
  events : Array EventDecl := #[]
  errors : Array ErrorDecl := #[]
  initializer : Option Initializer
  entries : Array Entry
  functions : Array FnDecl := #[]
  invariants : Array InvariantDecl := #[]
  extensionRequirements : Array ExtensionReq := #[]
  proofReferences : Array ProofDecl := #[]
  deriving BEq, Inhabited, Repr

def Program.buildQualified (qualifiedName name : String) (items : Array Item) : Program :=
  let state := items.foldl (fun acc item => match item with | .stateDecl decl => acc.push decl | _ => acc) #[]
  let structs := items.foldl (fun acc item => match item with | .structDecl decl => acc.push decl | _ => acc) #[]
  let enums := items.foldl (fun acc item => match item with | .enumDecl decl => acc.push decl | _ => acc) #[]
  let consts := items.foldl (fun acc item => match item with | .constDecl decl => acc.push decl | _ => acc) #[]
  let events := items.foldl (fun acc item => match item with | .eventDecl decl => acc.push decl | _ => acc) #[]
  let errors := items.foldl (fun acc item => match item with | .errorDecl decl => acc.push decl | _ => acc) #[]
  let initializer := items.foldl (fun acc item => match item with | .initializer decl => some decl | _ => acc) none
  let entries := items.foldl (fun acc item => match item with | .entry decl => acc.push decl | _ => acc) #[]
  let functions := items.foldl (fun acc item => match item with | .fnDecl decl => acc.push decl | _ => acc) #[]
  let invariants := items.foldl (fun acc item => match item with | .invariantDecl decl => acc.push decl | _ => acc) #[]
  let extensionRequirements := items.foldl (fun acc item => match item with | .extensionReq decl => acc.push decl | _ => acc) #[]
  let proofReferences := items.foldl (fun acc item => match item with | .proofDecl decl => acc.push decl | _ => acc) #[]
  { qualifiedName, name, state, structs, enums, consts, events, errors, initializer, entries,
    functions, invariants, extensionRequirements, proofReferences }

def Program.build (name : String) (items : Array Item) : Program :=
  Program.buildQualified name name items

namespace Canonical

private def appendTag (bytes : ByteArray) (tag : UInt8) : ByteArray :=
  bytes.push tag

private def appendUInt64 (bytes : ByteArray) (value : UInt64) : ByteArray :=
  bytes
    |>.push (UInt64.shiftRight value 56).toUInt8
    |>.push (UInt64.shiftRight value 48).toUInt8
    |>.push (UInt64.shiftRight value 40).toUInt8
    |>.push (UInt64.shiftRight value 32).toUInt8
    |>.push (UInt64.shiftRight value 24).toUInt8
    |>.push (UInt64.shiftRight value 16).toUInt8
    |>.push (UInt64.shiftRight value 8).toUInt8
    |>.push value.toUInt8

private def appendNat (bytes : ByteArray) (value : Nat) : ByteArray :=
  appendUInt64 bytes (UInt64.ofNat value)

private def appendString (bytes : ByteArray) (value : String) : ByteArray :=
  let encoded := value.toUTF8
  (appendNat bytes encoded.size).append encoded

private def appendArray (appendValue : ByteArray → α → ByteArray)
    (bytes : ByteArray) (values : Array α) : ByteArray :=
  values.foldl appendValue (appendNat bytes values.size)

private def appendValueType (bytes : ByteArray) : ValueType → ByteArray
  | .u64 => appendTag bytes 0
  | .bool => appendTag bytes 1
  | .field => appendTag bytes 2
  | .u8 => appendTag bytes 3
  | .u16 => appendTag bytes 4
  | .u32 => appendTag bytes 5
  | .u128 => appendTag bytes 6
  | .u256 => appendTag bytes 7
  | .i8 => appendTag bytes 8
  | .i16 => appendTag bytes 9
  | .i32 => appendTag bytes 10
  | .i64 => appendTag bytes 11
  | .i128 => appendTag bytes 12
  | .i256 => appendTag bytes 13
  | .unit => appendTag bytes 14
  | .principal => appendTag bytes 15
  | .option element => appendValueType (appendTag bytes 16) element
  | .bytes length => appendNat (appendTag bytes 17) length.toNat
  | .array element length =>
      appendNat (appendValueType (appendTag bytes 18) element) length.val

private def appendVisibility (bytes : ByteArray) : Visibility → ByteArray
  | .verifierVisible => appendTag bytes 0
  | .proverWitness => appendTag bytes 1
  | .commitmentOnly => appendTag bytes 2

private def appendParam (bytes : ByteArray) (param : Param) : ByteArray :=
  appendVisibility (appendValueType (appendString bytes param.name) param.type) param.visibility

private def appendStateDecl (bytes : ByteArray) (decl : StateDecl) : ByteArray :=
  appendValueType (appendString (appendVisibility bytes decl.visibility) decl.name) decl.type

private def appendFieldDecl (bytes : ByteArray) (decl : FieldDecl) : ByteArray :=
  appendValueType (appendString bytes decl.name) decl.type

private def appendStructDecl (bytes : ByteArray) (decl : StructDecl) : ByteArray :=
  appendArray appendFieldDecl (appendString bytes decl.name) decl.fields

private def appendEnumVariant (bytes : ByteArray) (variant : EnumVariant) : ByteArray :=
  appendArray appendValueType (appendString bytes variant.name) variant.payloadTypes

private def appendEnumDecl (bytes : ByteArray) (decl : EnumDecl) : ByteArray :=
  appendArray appendEnumVariant (appendString bytes decl.name) decl.variants

private def appendEventDecl (bytes : ByteArray) (decl : EventDecl) : ByteArray :=
  appendArray appendParam (appendString bytes decl.name) decl.params

private def appendErrorDecl (bytes : ByteArray) (decl : ErrorDecl) : ByteArray :=
  appendArray appendParam (appendString bytes decl.name) decl.params

private partial def appendExpr (bytes : ByteArray) : Expr → ByteArray
  | .literal value => appendUInt64 (appendTag bytes 0) value
  | .variable name => appendString (appendTag bytes 1) name
  | .state name => appendString (appendTag bytes 2) name
  | .checkedAdd lhs rhs => appendExpr (appendExpr (appendTag bytes 3) lhs) rhs
  | .boolLiteral value =>
      appendTag (appendTag bytes 4) (if value then 1 else 0)
  | .checkedSub lhs rhs => appendExpr (appendExpr (appendTag bytes 5) lhs) rhs
  | .checkedMul lhs rhs => appendExpr (appendExpr (appendTag bytes 6) lhs) rhs
  | .checkedNeg operand => appendExpr (appendTag bytes 7) operand
  | .bitwiseNot operand => appendExpr (appendTag bytes 8) operand
  | .logicalNot operand => appendExpr (appendTag bytes 9) operand
  | .checkedDiv lhs rhs => appendExpr (appendExpr (appendTag bytes 10) lhs) rhs
  | .checkedMod lhs rhs => appendExpr (appendExpr (appendTag bytes 11) lhs) rhs
  | .shiftLeft lhs rhs => appendExpr (appendExpr (appendTag bytes 12) lhs) rhs
  | .shiftRight lhs rhs => appendExpr (appendExpr (appendTag bytes 13) lhs) rhs
  | .equal lhs rhs => appendExpr (appendExpr (appendTag bytes 14) lhs) rhs
  | .notEqual lhs rhs => appendExpr (appendExpr (appendTag bytes 15) lhs) rhs
  | .lessThan lhs rhs => appendExpr (appendExpr (appendTag bytes 16) lhs) rhs
  | .lessEqual lhs rhs => appendExpr (appendExpr (appendTag bytes 17) lhs) rhs
  | .greaterThan lhs rhs => appendExpr (appendExpr (appendTag bytes 18) lhs) rhs
  | .greaterEqual lhs rhs => appendExpr (appendExpr (appendTag bytes 19) lhs) rhs
  | .bitwiseAnd lhs rhs => appendExpr (appendExpr (appendTag bytes 20) lhs) rhs
  | .bitwiseXor lhs rhs => appendExpr (appendExpr (appendTag bytes 21) lhs) rhs
  | .bitwiseOr lhs rhs => appendExpr (appendExpr (appendTag bytes 22) lhs) rhs
  | .logicalAnd lhs rhs => appendExpr (appendExpr (appendTag bytes 23) lhs) rhs
  | .logicalOr lhs rhs => appendExpr (appendExpr (appendTag bytes 24) lhs) rhs
  | .stringLiteral value => appendString (appendTag bytes 25) value
  | .localFnCall callee args => appendArray appendExpr (appendString (appendTag bytes 26) callee) args
  | .constructorExpr path args => appendArray appendExpr (appendArray appendString (appendTag bytes 27) path) args
  | .indexAccess base index => appendExpr (appendString (appendTag bytes 28) base) index

private def appendConstDecl (bytes : ByteArray) (decl : ConstDecl) : ByteArray :=
  appendExpr (appendValueType (appendString bytes decl.name) decl.type) decl.value

private partial def appendStatement (bytes : ByteArray) : Statement → ByteArray
  | .assign name value => appendExpr (appendString (appendTag bytes 0) name) value
  | .returnValue value => appendExpr (appendTag bytes 1) value
  | .returnUnit => appendTag bytes 6
  | .synchronousCall callee => appendString (appendTag bytes 2) callee
  | .letDecl name typeAnn value =>
      let bytes := appendString (appendTag bytes 3) name
      let bytes := match typeAnn with
        | none => appendTag bytes 0
        | some type => appendValueType (appendTag bytes 1) type
      appendExpr bytes value
  | .assertStmt condition => appendExpr (appendTag bytes 4) condition
  | .assertErrorStmt condition errorName => appendString (appendExpr (appendTag bytes 8) condition) errorName
  | .revertStmt errorName args => appendArray appendExpr (appendString (appendTag bytes 5) errorName) args
  | .emitStmt eventName args => appendArray appendExpr (appendString (appendTag bytes 7) eventName) args
  | .ifStmt condition thenBody elseBody =>
      let bytes := appendArray appendStatement (appendExpr (appendTag bytes 9) condition) thenBody
      match elseBody with
      | none => appendTag bytes 0
      | some body => appendArray appendStatement (appendTag bytes 1) body
  | .forStmt iterator start stopExclusive maxIterations body =>
      let bytes := appendExpr (appendExpr (appendString (appendTag bytes 10) iterator) start) stopExclusive
      appendArray appendStatement (appendNat bytes maxIterations.val) body

private def appendEntryMode (bytes : ByteArray) : EntryMode → ByteArray
  | .mutate => appendTag bytes 0
  | .view => appendTag bytes 1

private def appendInitializer (bytes : ByteArray) (initializer : Initializer) : ByteArray :=
  appendArray appendStatement (appendArray appendParam bytes initializer.params) initializer.body

private def appendEntry (bytes : ByteArray) (entry : Entry) : ByteArray :=
  let bytes := appendString bytes entry.name
  let bytes := appendArray appendParam bytes entry.params
  let bytes := appendValueType bytes entry.result
  let bytes := appendEntryMode bytes entry.mode
  appendArray appendStatement bytes entry.body

private def appendFnDecl (bytes : ByteArray) (decl : FnDecl) : ByteArray :=
  let bytes := appendString bytes decl.name
  let bytes := appendArray appendParam bytes decl.params
  let bytes := appendValueType bytes decl.result
  appendArray appendStatement bytes decl.body

private def appendInvariantDecl (bytes : ByteArray) (decl : InvariantDecl) : ByteArray :=
  appendExpr (appendString bytes decl.name) decl.predicate

private def appendExtensionReq (bytes : ByteArray) (decl : ExtensionReq) : ByteArray :=
  let bytes := appendString bytes decl.id
  let bytes := appendString bytes decl.version
  appendString bytes decl.digest

private def appendProofDecl (bytes : ByteArray) (decl : ProofDecl) : ByteArray :=
  appendArray appendString (appendString bytes decl.invariant) decl.«theorem»

def appendProgram (bytes : ByteArray) (program : Program) : ByteArray :=
  let bytes := appendString bytes program.qualifiedName
  let bytes := appendString bytes program.name
  let bytes := appendArray appendStateDecl bytes program.state
  let bytes := appendArray appendStructDecl bytes program.structs
  let bytes := appendArray appendEnumDecl bytes program.enums
  let bytes := appendArray appendConstDecl bytes program.consts
  let bytes := appendArray appendEventDecl bytes program.events
  let bytes := appendArray appendErrorDecl bytes program.errors
  let bytes := match program.initializer with
    | none => appendTag bytes 0
    | some initializer => appendInitializer (appendTag bytes 1) initializer
  let bytes := appendArray appendEntry bytes program.entries
  let bytes := appendArray appendFnDecl bytes program.functions
  let bytes := appendArray appendInvariantDecl bytes program.invariants
  let bytes := appendArray appendExtensionReq bytes program.extensionRequirements
  appendArray appendProofDecl bytes program.proofReferences

end Canonical

def Program.canonicalBytes (program : Program) : ByteArray :=
  let domain := "pf.source.v1".toUTF8 |>.push 0
  Canonical.appendProgram domain program

def Program.sourceHash (program : Program) : String :=
  ProofForgeV2.Crypto.sha256Hex program.canonicalBytes

end ProofForgeV2.Source

namespace ProofForgeV2

abbrev ProgramRequirements := Array ProgramRequirement

end ProofForgeV2
