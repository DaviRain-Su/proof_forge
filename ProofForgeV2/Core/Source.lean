import ProofForgeV2.Core.Diagnostic

namespace ProofForgeV2.Crypto

private def rotateRight (value : UInt32) (amount : Nat) : UInt32 :=
  UInt32.shiftRight value (UInt32.ofNat amount) |||
    UInt32.shiftLeft value (UInt32.ofNat (32 - amount))

private def choose (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ ((~~~x) &&& z)

private def majority (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

private def bigSigma0 (value : UInt32) : UInt32 :=
  rotateRight value 2 ^^^ rotateRight value 13 ^^^ rotateRight value 22

private def bigSigma1 (value : UInt32) : UInt32 :=
  rotateRight value 6 ^^^ rotateRight value 11 ^^^ rotateRight value 25

private def smallSigma0 (value : UInt32) : UInt32 :=
  rotateRight value 7 ^^^ rotateRight value 18 ^^^ UInt32.shiftRight value 3

private def smallSigma1 (value : UInt32) : UInt32 :=
  rotateRight value 17 ^^^ rotateRight value 19 ^^^ UInt32.shiftRight value 10

private def roundConstants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

private def initialState : Array UInt32 := #[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
]

private def appendUInt64BE (bytes : ByteArray) (value : UInt64) : ByteArray :=
  bytes
    |>.push (UInt64.shiftRight value 56).toUInt8
    |>.push (UInt64.shiftRight value 48).toUInt8
    |>.push (UInt64.shiftRight value 40).toUInt8
    |>.push (UInt64.shiftRight value 32).toUInt8
    |>.push (UInt64.shiftRight value 24).toUInt8
    |>.push (UInt64.shiftRight value 16).toUInt8
    |>.push (UInt64.shiftRight value 8).toUInt8
    |>.push value.toUInt8

private def pad (input : ByteArray) : ByteArray := Id.run do
  let bitLength := UInt64.ofNat input.size * 8
  let mut padded := input.push 0x80
  while padded.size % 64 != 56 do
    padded := padded.push 0
  return appendUInt64BE padded bitLength

private def wordAt (bytes : ByteArray) (offset : Nat) : UInt32 :=
  UInt32.shiftLeft bytes[offset]!.toUInt32 24 |||
    UInt32.shiftLeft bytes[offset + 1]!.toUInt32 16 |||
    UInt32.shiftLeft bytes[offset + 2]!.toUInt32 8 |||
    bytes[offset + 3]!.toUInt32

private def scheduleFor (bytes : ByteArray) (offset : Nat) : Array UInt32 := Id.run do
  let mut schedule := Array.replicate 64 0
  for index in [0:16] do
    schedule := schedule.set! index (wordAt bytes (offset + index * 4))
  for index in [16:64] do
    let value := smallSigma1 schedule[index - 2]! + schedule[index - 7]! +
      smallSigma0 schedule[index - 15]! + schedule[index - 16]!
    schedule := schedule.set! index value
  return schedule

private def compress (state : Array UInt32) (schedule : Array UInt32) : Array UInt32 := Id.run do
  let mut a := state[0]!
  let mut b := state[1]!
  let mut c := state[2]!
  let mut d := state[3]!
  let mut e := state[4]!
  let mut f := state[5]!
  let mut g := state[6]!
  let mut h := state[7]!
  for index in [0:64] do
    let temp1 := h + bigSigma1 e + choose e f g + roundConstants[index]! + schedule[index]!
    let temp2 := bigSigma0 a + majority a b c
    h := g
    g := f
    f := e
    e := d + temp1
    d := c
    c := b
    b := a
    a := temp1 + temp2
  return #[
    state[0]! + a, state[1]! + b, state[2]! + c, state[3]! + d,
    state[4]! + e, state[5]! + f, state[6]! + g, state[7]! + h
  ]

private def appendUInt32BE (bytes : ByteArray) (value : UInt32) : ByteArray :=
  bytes
    |>.push (UInt32.shiftRight value 24).toUInt8
    |>.push (UInt32.shiftRight value 16).toUInt8
    |>.push (UInt32.shiftRight value 8).toUInt8
    |>.push value.toUInt8

/-- Pure SHA-256 over bytes. This implementation performs no IO and has no toolchain dependency. -/
def sha256 (input : ByteArray) : ByteArray := Id.run do
  let padded := pad input
  let mut state := initialState
  for chunk in [0:padded.size / 64] do
    state := compress state (scheduleFor padded (chunk * 64))
  return state.foldl appendUInt32BE ByteArray.empty

private def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat (48 + value) else Char.ofNat (87 + value)

/-- Lower-case hexadecimal SHA-256 digest over bytes. -/
def sha256Hex (input : ByteArray) : String :=
  (sha256 input).foldl (fun output byte =>
    output.push (hexDigit (byte.toNat / 16)) |>.push (hexDigit (byte.toNat % 16))) ""

end ProofForgeV2.Crypto

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
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | variable (name : String)
  | state (name : String)
  | checkedAdd (lhs rhs : Expr)
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

inductive Item where
  | stateDecl (decl : StateDecl)
  | initializer (decl : Initializer)
  | entry (decl : Entry)
  deriving BEq, Inhabited, Repr

structure Program where
  qualifiedName : String
  name : String
  state : Array StateDecl
  initializer : Option Initializer
  entries : Array Entry
  deriving BEq, Inhabited, Repr

def Program.buildQualified (qualifiedName name : String) (items : Array Item) : Program :=
  let state := items.foldl (fun acc item => match item with | .stateDecl decl => acc.push decl | _ => acc) #[]
  let initializer := items.foldl (fun acc item => match item with | .initializer decl => some decl | _ => acc) none
  let entries := items.foldl (fun acc item => match item with | .entry decl => acc.push decl | _ => acc) #[]
  { qualifiedName, name, state, initializer, entries }

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
  appendValueType (appendString bytes decl.name) decl.type

private partial def appendExpr (bytes : ByteArray) : Expr → ByteArray
  | .literal value => appendUInt64 (appendTag bytes 0) value
  | .variable name => appendString (appendTag bytes 1) name
  | .state name => appendString (appendTag bytes 2) name
  | .checkedAdd lhs rhs => appendExpr (appendExpr (appendTag bytes 3) lhs) rhs

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

def appendProgram (bytes : ByteArray) (program : Program) : ByteArray :=
  let bytes := appendString bytes program.qualifiedName
  let bytes := appendString bytes program.name
  let bytes := appendArray appendStateDecl bytes program.state
  let bytes := match program.initializer with
    | none => appendTag bytes 0
    | some initializer => appendInitializer (appendTag bytes 1) initializer
  appendArray appendEntry bytes program.entries

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
