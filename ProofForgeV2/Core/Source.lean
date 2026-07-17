import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Source

inductive ValueType where
  | u64
  | bool
  | field
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
  deriving BEq, Inhabited, Repr

structure ConstDecl where
  name : String
  type : ValueType
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | assign (stateName : String) (value : Expr)
  | returnValue (value : Expr)
  | synchronousCall (callee : String)
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
  { qualifiedName, name, state, structs, enums, consts, events, errors, initializer, entries,
    functions }

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

private def appendConstDecl (bytes : ByteArray) (decl : ConstDecl) : ByteArray :=
  appendExpr (appendValueType (appendString bytes decl.name) decl.type) decl.value

private def appendStatement (bytes : ByteArray) : Statement → ByteArray
  | .assign name value => appendExpr (appendString (appendTag bytes 0) name) value
  | .returnValue value => appendExpr (appendTag bytes 1) value
  | .synchronousCall callee => appendString (appendTag bytes 2) callee

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
  appendArray appendFnDecl bytes program.functions

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
