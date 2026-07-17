import ProofForgeV2.Core.Typed

namespace ProofForgeV2.Semantic

open ProofForgeV2

def schemaVersion : Nat := 1

structure ParamId where
  value : Nat
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

structure StateId where
  value : Nat
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

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
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

inductive Visibility where
  | verifierVisible
  | proverWitness
  | commitmentOnly
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

structure Param where
  id : ParamId
  name : String
  type : ValueType
  visibility : Visibility
  deriving BEq, Inhabited, Repr

structure StateDecl where
  id : StateId
  name : String
  type : ValueType
  visibility : Visibility := .verifierVisible
  deriving BEq, Inhabited, Repr

/-- Canonical value expression. References use stable IDs; checked arithmetic
is represented explicitly rather than inferred again by a target. -/
inductive Expr where
  | literal (value : UInt64)
  | param (id : ParamId)
  | state (id : StateId)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (state : StateId) (value : Expr)
  | returnValue (value : Expr)
  | synchronousCall (callee : String)
  deriving BEq, Inhabited, Repr

structure Initializer where
  params : Array Param
  body : Array Statement
  deriving BEq, Inhabited, Repr

inductive EntryMode where
  | mutate
  | view
  deriving BEq, Inhabited, Repr

structure Entry where
  name : String
  params : Array Param
  result : ValueType
  mode : EntryMode
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Target-neutral canonical program for the current Phase-1 subset. This is a
separate type from both `Source.Program` and `Typed.Program`. -/
structure Program where
  schemaVersion : Nat
  qualifiedName : String
  name : String
  /-- Digest of the decoded Source AST. It is provenance, not an input to the
  semantic digest, so semantically equivalent future surface forms may share a
  semantic hash while retaining distinct source hashes. -/
  sourceHash : String
  state : Array StateDecl
  initializer : Option Initializer
  entries : Array Entry
  requirements : Array ProgramRequirement
  deriving BEq, Inhabited, Repr

private def adaptType : Source.ValueType → ValueType
  | .u64 => .u64
  | .bool => .bool
  | .field => .field
  | .u8 => .u8
  | .u16 => .u16
  | .u32 => .u32
  | .u128 => .u128
  | .u256 => .u256
  | .i8 => .i8
  | .i16 => .i16
  | .i32 => .i32
  | .i64 => .i64
  | .i128 => .i128
  | .i256 => .i256
  | .unit => .unit
  | .principal => .principal
  | .option element => .option (adaptType element)
  | .bytes length => .bytes length

private def adaptVisibility : Source.Visibility → Visibility
  | .verifierVisible => .verifierVisible
  | .proverWitness => .proverWitness
  | .commitmentOnly => .commitmentOnly

private def adaptParam (param : Typed.Param) : Param := {
  id := ⟨param.id.value⟩
  name := param.name
  type := adaptType param.type
  visibility := adaptVisibility param.visibility
}

private def adaptState (state : Typed.StateDecl) : StateDecl := {
  id := ⟨state.id.value⟩
  name := state.name
  type := adaptType state.type
  visibility := adaptVisibility state.visibility
}

private partial def adaptExpr : Typed.Expr → Expr
  | .literal value => .literal value
  | .ref (.param id _) => .param ⟨id.value⟩
  | .ref (.state id _) => .state ⟨id.value⟩
  | .checkedAdd lhs rhs => .checkedAdd (adaptExpr lhs) (adaptExpr rhs)

private def adaptStatement : Typed.Statement → Statement
  | .assign state value => .store ⟨state.value⟩ (adaptExpr value)
  | .returnValue value => .returnValue (adaptExpr value)
  | .synchronousCall callee => .synchronousCall callee

private def adaptInitializer (initializer : Typed.Initializer) : Initializer := {
  params := initializer.params.map adaptParam
  body := initializer.body.map adaptStatement
}

private def adaptMode : Typed.EntryMode → EntryMode
  | .mutate => .mutate
  | .view => .view

private def adaptEntry (entry : Typed.Entry) : Entry := {
  name := entry.name
  params := entry.params.map adaptParam
  result := adaptType entry.result
  mode := adaptMode entry.mode
  body := entry.body.map adaptStatement
}

private partial def Expr.requirements : Expr → Array ProgramRequirement
  | .literal .. | .param .. | .state .. => #[]
  | .checkedAdd lhs rhs =>
      lhs.requirements ++ rhs.requirements ++
        #[.checkedArithmetic, .transactionalRollback]

private def Statement.requirements : Statement → Array ProgramRequirement
  | .store _ value | .returnValue value => value.requirements
  | .synchronousCall .. => #[.synchronousCall, .transactionalRollback]

private def ValueType.requirements : ValueType → Array ProgramRequirement
  | .u64 => #[]
  | .bool => #[.boolValues]
  | .field => #[.fieldBn254]
  | .u8 | .u16 | .u32 | .u128 | .u256
  | .i8 | .i16 | .i32 | .i64 | .i128 | .i256
  | .unit => #[]
  -- Principal is a declaration type carrier only: zero requirements, and not
  -- conflated with context.caller (callerContext).
  | .principal => #[]
  -- Option adds no capability of its own; requirements are exactly the element's.
  | .option element => element.requirements
  -- Bytes declaration carrier only: zero requirements, no runtime bytes capability.
  | .bytes _ => #[]

private def Visibility.requirements : Visibility → Array ProgramRequirement
  | .verifierVisible => #[]
  | .proverWitness => #[.privateWitness]
  | .commitmentOnly => #[.commitmentDisclosure]

private def Param.requirements (param : Param) : Array ProgramRequirement :=
  param.type.requirements ++ param.visibility.requirements

private def StateDecl.requirements (state : StateDecl) : Array ProgramRequirement :=
  let visibilityRequirements := match state.visibility with
    | .verifierVisible => #[]
    | .proverWitness => #[.privateState]
    | .commitmentOnly => #[.commitmentState]
  state.type.requirements ++ visibilityRequirements

private def stableUnique [BEq α] (values : Array α) : Array α :=
  values.foldl (fun found value =>
    if found.contains value then found else found.push value) #[]

def deriveRequirements (program : Program) : Array ProgramRequirement :=
  let stateRequirements :=
    (if program.state.isEmpty then #[] else #[.persistentState]) ++
      program.state.flatMap StateDecl.requirements
  let initializerRequirements := program.initializer.map (fun initializer =>
    initializer.params.flatMap Param.requirements ++
      initializer.body.flatMap Statement.requirements) |>.getD #[]
  let entryRequirements := program.entries.flatMap fun entry =>
    entry.params.flatMap Param.requirements ++ entry.result.requirements ++
      entry.body.flatMap Statement.requirements
  stableUnique (stateRequirements ++ initializerRequirements ++ entryRequirements)

/-- Total normalization from a checked Typed program. Requirements are derived
only from the resulting semantic operations. -/
def fromTyped (sourceHash : String) (typed : Typed.Program) : Program :=
  let program : Program := {
    schemaVersion
    qualifiedName := typed.qualifiedName
    name := typed.name
    sourceHash
    state := typed.state.map adaptState
    initializer := typed.initializer.map adaptInitializer
    entries := typed.entries.map adaptEntry
    requirements := #[]
  }
  { program with requirements := deriveRequirements program }

namespace Canonical

private def appendTag (bytes : ByteArray) (tag : UInt8) : ByteArray :=
  bytes.push tag

private def appendUInt64LE (bytes : ByteArray) (value : UInt64) : ByteArray :=
  bytes
    |>.push value.toUInt8
    |>.push (UInt64.shiftRight value 8).toUInt8
    |>.push (UInt64.shiftRight value 16).toUInt8
    |>.push (UInt64.shiftRight value 24).toUInt8
    |>.push (UInt64.shiftRight value 32).toUInt8
    |>.push (UInt64.shiftRight value 40).toUInt8
    |>.push (UInt64.shiftRight value 48).toUInt8
    |>.push (UInt64.shiftRight value 56).toUInt8

private def appendNat (bytes : ByteArray) (value : Nat) : ByteArray :=
  appendUInt64LE bytes (UInt64.ofNat value)

private def appendString (bytes : ByteArray) (value : String) : ByteArray :=
  let encoded := value.toUTF8
  (appendNat bytes encoded.size).append encoded

private def appendArray (appendValue : ByteArray → α → ByteArray)
    (bytes : ByteArray) (values : Array α) : ByteArray :=
  values.foldl appendValue (appendNat bytes values.size)

private def appendParamId (bytes : ByteArray) (id : ParamId) : ByteArray :=
  appendNat bytes id.value

private def appendStateId (bytes : ByteArray) (id : StateId) : ByteArray :=
  appendNat bytes id.value

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

private def appendVisibility (bytes : ByteArray) : Visibility → ByteArray
  | .verifierVisible => appendTag bytes 0
  | .proverWitness => appendTag bytes 1
  | .commitmentOnly => appendTag bytes 2

private def appendParam (bytes : ByteArray) (param : Param) : ByteArray :=
  let bytes := appendParamId bytes param.id
  let bytes := appendString bytes param.name
  let bytes := appendValueType bytes param.type
  appendVisibility bytes param.visibility

private def appendState (bytes : ByteArray) (state : StateDecl) : ByteArray :=
  appendVisibility
    (appendValueType (appendString (appendStateId bytes state.id) state.name) state.type)
    state.visibility

private partial def appendExpr (bytes : ByteArray) : Expr → ByteArray
  | .literal value => appendUInt64LE (appendTag bytes 0) value
  | .param id => appendParamId (appendTag bytes 1) id
  | .state id => appendStateId (appendTag bytes 2) id
  | .checkedAdd lhs rhs => appendExpr (appendExpr (appendTag bytes 3) lhs) rhs

private def appendStatement (bytes : ByteArray) : Statement → ByteArray
  | .store state value => appendExpr (appendStateId (appendTag bytes 0) state) value
  | .returnValue value => appendExpr (appendTag bytes 1) value
  | .synchronousCall callee => appendString (appendTag bytes 2) callee

private def appendInitializer (bytes : ByteArray) (initializer : Initializer) : ByteArray :=
  appendArray appendStatement (appendArray appendParam bytes initializer.params) initializer.body

private def appendMode (bytes : ByteArray) : EntryMode → ByteArray
  | .mutate => appendTag bytes 0
  | .view => appendTag bytes 1

private def appendEntry (bytes : ByteArray) (entry : Entry) : ByteArray :=
  let bytes := appendString bytes entry.name
  let bytes := appendArray appendParam bytes entry.params
  let bytes := appendValueType bytes entry.result
  let bytes := appendMode bytes entry.mode
  appendArray appendStatement bytes entry.body

private def appendRequirement (bytes : ByteArray) : ProgramRequirement → ByteArray
  | .persistentState => appendTag bytes 0
  | .checkedArithmetic => appendTag bytes 1
  | .transactionalRollback => appendTag bytes 2
  | .synchronousCall => appendTag bytes 3
  | .asynchronousWorkflow => appendTag bytes 4
  | .privateWitness => appendTag bytes 5
  | .eventEmission => appendTag bytes 6
  | .callerContext => appendTag bytes 7
  | .boolValues => appendTag bytes 8
  | .commitmentDisclosure => appendTag bytes 9
  | .fieldBn254 => appendTag bytes 10
  | .privateState => appendTag bytes 11
  | .commitmentState => appendTag bytes 12

def appendProgram (bytes : ByteArray) (program : Program) : ByteArray :=
  let bytes := appendNat bytes program.schemaVersion
  let bytes := appendString bytes program.qualifiedName
  let bytes := appendString bytes program.name
  let bytes := appendArray appendState bytes program.state
  let bytes := match program.initializer with
    | none => appendTag bytes 0
    | some initializer => appendInitializer (appendTag bytes 1) initializer
  let bytes := appendArray appendEntry bytes program.entries
  appendArray appendRequirement bytes program.requirements

end Canonical

def Program.canonicalBytes (program : Program) : ByteArray :=
  Canonical.appendProgram ("pf.semantic.v1".toUTF8 |>.push 0) program

def Program.semanticHash (program : Program) : String :=
  Crypto.sha256Hex program.canonicalBytes

end ProofForgeV2.Semantic

namespace ProofForgeV2

/-- The canonical, target-neutral business semantics accepted by all target
materializers. This alias deliberately points at `Semantic.Program`, never at
the parser-owned Source AST. -/
abbrev SemanticProgram := Semantic.Program

end ProofForgeV2
