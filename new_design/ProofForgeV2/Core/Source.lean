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

/-- Inclusive-exclusive byte range plus 1-based line/column of the start. -/
structure Span where
  byteStart : Nat
  byteEnd : Nat
  line : Nat
  column : Nat
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace Span

def synthetic : Span := { byteStart := 0, byteEnd := 0, line := 0, column := 0 }

def isWellFormed (span : Span) : Bool :=
  span.byteStart ≤ span.byteEnd

end Span

/-- First 128 bits of SHA-256(module, program, syntactic path) as 32 lower-case hex chars. -/
structure NodeId where
  hex128 : String
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace NodeId

def isWellFormed (id : NodeId) : Bool :=
  id.hex128.length == 32 && id.hex128.toList.all fun char =>
    "0123456789abcdef".toList.contains char

private def firstChars (value : String) (count : Nat) : String :=
  String.ofList (value.toList.take count)

def ofPath (moduleName programName path : String) : NodeId :=
  let material := (moduleName ++ "\u0000" ++ programName ++ "\u0000" ++ path).toUTF8
  let digest := ProofForgeV2.Crypto.sha256Hex material
  { hex128 := firstChars digest 32 }

end NodeId

inductive TokenKind where
  | keyword (name : String)
  | ident (name : String)
  | number (text : String)
  | stringLit (text : String)
  | symbol (text : String)
  | eof
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

structure Token where
  kind : TokenKind
  span : Span
  deriving BEq, Inhabited, Repr

structure Limits where
  maxNodes : Nat := 100000
  maxNesting : Nat := 256
  maxSourceBytes : Nat := 16 * 1024 * 1024
  maxLoopBound : Nat := 4096
  deriving BEq, Inhabited, Repr

def defaultLimits : Limits := {}

structure NodeRecord where
  path : String
  nodeId : NodeId
  span : Span
  kind : String
  deriving BEq, Inhabited, Repr

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
  /-- Explicitly bounded loop; `bound` must be in 1..Limits.maxLoopBound. -/
  | loopBounded (bound : Nat) (body : Array Statement)
  /-- Unbounded/recursive control form; bound checker must fail closed with PF-BOUND-001. -/
  | unboundedLoop (body : Array Statement)
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

private partial def appendStatement (bytes : ByteArray) : Statement → ByteArray
  | .assign name value => appendExpr (appendString (appendTag bytes 0) name) value
  | .returnValue value => appendExpr (appendTag bytes 1) value
  | .synchronousCall callee => appendString (appendTag bytes 2) callee
  | .loopBounded bound body =>
      appendArray appendStatement (appendNat (appendTag bytes 3) bound) body
  | .unboundedLoop body =>
      appendArray appendStatement (appendTag bytes 4) body

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

namespace Inventory

private def moduleOf (qualifiedName : String) : String := Id.run do
  let chars := qualifiedName.toList
  let mut lastDot : Option Nat := none
  let mut index : Nat := 0
  for c in chars do
    if c == '.' then
      lastDot := some index
    index := index + 1
  match lastDot with
  | none => ""
  | some idx => String.ofList (chars.take idx)

private def pushNode (moduleName programName : String) (path kind : String)
    (span : Span) (acc : Array NodeRecord) : Array NodeRecord :=
  acc.push {
    path
    nodeId := NodeId.ofPath moduleName programName path
    span
    kind
  }

private partial def exprNesting : Expr → Nat
  | .literal _ | .variable _ | .state _ => 1
  | .checkedAdd lhs rhs => 1 + max (exprNesting lhs) (exprNesting rhs)

private partial def collectExpr (moduleName programName path : String)
    (span : Span) (expr : Expr) (acc : Array NodeRecord) : Array NodeRecord :=
  let acc := pushNode moduleName programName path "expr" span acc
  match expr with
  | .literal _ | .variable _ | .state _ => acc
  | .checkedAdd lhs rhs =>
      let acc := collectExpr moduleName programName (path ++ "/lhs") span lhs acc
      collectExpr moduleName programName (path ++ "/rhs") span rhs acc

private partial def stmtNesting : Statement → Nat
  | .assign _ value => 1 + exprNesting value
  | .returnValue value => 1 + exprNesting value
  | .synchronousCall _ => 1
  | .loopBounded _ body =>
      1 + body.foldl (fun acc stmt => max acc (stmtNesting stmt)) 0
  | .unboundedLoop body =>
      1 + body.foldl (fun acc stmt => max acc (stmtNesting stmt)) 0

mutual
  private partial def collectStatement (moduleName programName path : String)
      (span : Span) (stmt : Statement) (acc : Array NodeRecord) : Array NodeRecord :=
    let acc := pushNode moduleName programName path "stmt" span acc
    match stmt with
    | .assign _ value =>
        collectExpr moduleName programName (path ++ "/value") span value acc
    | .returnValue value =>
        collectExpr moduleName programName (path ++ "/value") span value acc
    | .synchronousCall _ => acc
    | .loopBounded _ body =>
        collectStatements moduleName programName (path ++ "/body") span body acc
    | .unboundedLoop body =>
        collectStatements moduleName programName (path ++ "/body") span body acc

  private partial def collectStatements (moduleName programName basePath : String)
      (span : Span) (body : Array Statement) (acc : Array NodeRecord) : Array NodeRecord := Id.run do
    let mut acc := acc
    let mut idx : Nat := 0
    for child in body do
      acc := collectStatement moduleName programName (basePath ++ s!"/{idx}") span child acc
      idx := idx + 1
    return acc
end

end Inventory

/-- Deterministic NodeId inventory for a program. Spans are synthetic until the
Lean syntax decoder attaches real byte ranges; NodeIds still depend only on
module/program/path. -/
def Program.enumerateNodes (program : Program) (span : Span := Span.synthetic) :
    Array NodeRecord := Id.run do
  let moduleName := Inventory.moduleOf program.qualifiedName
  let programName := program.name
  let mut acc : Array NodeRecord := #[]
  acc := Inventory.pushNode moduleName programName "program" "program" span acc
  for state in program.state do
    let path := s!"state/{state.name}"
    acc := Inventory.pushNode moduleName programName path "state" span acc
  match program.initializer with
  | none => pure ()
  | some initializer =>
      acc := Inventory.pushNode moduleName programName "init" "initializer" span acc
      for param in initializer.params do
        acc := Inventory.pushNode moduleName programName s!"init/param/{param.name}" "param" span acc
      acc := Inventory.collectStatements moduleName programName "init/body" span initializer.body acc
  for entry in program.entries do
    let entryPath := s!"entry/{entry.name}"
    acc := Inventory.pushNode moduleName programName entryPath "entry" span acc
    for param in entry.params do
      acc := Inventory.pushNode moduleName programName s!"{entryPath}/param/{param.name}" "param" span acc
    acc := Inventory.collectStatements moduleName programName s!"{entryPath}/body" span entry.body acc
  return acc

def Program.nodeCount (program : Program) : Nat :=
  program.enumerateNodes.size

def Program.maxNesting (program : Program) : Nat := Id.run do
  let mut depth : Nat := 1
  match program.initializer with
  | none => pure ()
  | some initializer =>
      for stmt in initializer.body do
        depth := max depth (1 + Inventory.stmtNesting stmt)
  for entry in program.entries do
    for stmt in entry.body do
      depth := max depth (1 + Inventory.stmtNesting stmt)
  return depth

private partial def checkStatementBounds (limits : Limits) : Statement → CompileResult Unit
  | .unboundedLoop _ =>
      throw <| .resourceBound "unbounded loop is not permitted (PF-BOUND-001)"
  | .loopBounded bound body => do
      if bound == 0 || bound > limits.maxLoopBound then
        throw <| .resourceBound
          s!"loop bound {bound} is outside 1..{limits.maxLoopBound}"
      for child in body do
        checkStatementBounds limits child
  | .assign _ _ | .returnValue _ | .synchronousCall _ => .ok ()

private def checkControlBounds (program : Program) (limits : Limits) : CompileResult Unit := do
  match program.initializer with
  | none => pure ()
  | some initializer =>
      for stmt in initializer.body do
        checkStatementBounds limits stmt
  for entry in program.entries do
    for stmt in entry.body do
      checkStatementBounds limits stmt

/-- Structural resource / termination precheck used by D1 identity and D2 bound gates. -/
def Program.validateLimits (program : Program) (limits : Limits := defaultLimits) :
    CompileResult Unit := do
  let nodes := program.enumerateNodes
  if nodes.size > limits.maxNodes then
    throw <| .resourceBound
      s!"AST node count {nodes.size} exceeds limit {limits.maxNodes}"
  let nesting := program.maxNesting
  if nesting > limits.maxNesting then
    throw <| .resourceBound
      s!"AST nesting depth {nesting} exceeds limit {limits.maxNesting}"
  let mut seen : Array String := #[]
  for record in nodes do
    unless record.nodeId.isWellFormed do
      throw <| .invalidProgram s!"malformed NodeId at path {record.path}"
    unless record.span.isWellFormed do
      throw <| .invalidProgram s!"malformed span at path {record.path}"
    if seen.contains record.nodeId.hex128 then
      throw <| .invalidProgram s!"duplicate NodeId at path {record.path}"
    seen := seen.push record.nodeId.hex128
  checkControlBounds program limits

private def isIdentStart (c : Char) : Bool :=
  c.isAlpha || c == '_'

private def isIdentContinue (c : Char) : Bool :=
  c.isAlphanum || c == '_'

private def reservedKeywords : Array String :=
  #["program", "where", "state", "init", "entry", "view", "return", "call",
    "public", "private", "do", "for", "bounded", "UInt64"]

private def classifyWord (word : String) : TokenKind :=
  if reservedKeywords.contains word then .keyword word else .ident word

private def lineColumnAt (source : String) (byteOffset : Nat) : Nat × Nat := Id.run do
  let mut line : Nat := 1
  let mut column : Nat := 1
  let mut index : Nat := 0
  for c in source.toList do
    if index >= byteOffset then
      return (line, column)
    if c == '\n' then
      line := line + 1
      column := 1
    else
      column := column + 1
    index := index + 1
  return (line, column)

private def sliceString (chars : Array Char) (start stop : Nat) : String :=
  String.ofList (chars.extract start stop).toList

/-- Portable DSL tokenizer for identity/span tests. Comments and whitespace are skipped
and do not receive tokens (and therefore do not enter source identity). -/
def tokenize (source : String) : CompileResult (Array Token) := Id.run do
  if source.toUTF8.size > defaultLimits.maxSourceBytes then
    return .error <| .resourceBound
      s!"source size {source.toUTF8.size} exceeds limit {defaultLimits.maxSourceBytes}"
  let chars := source.toList.toArray
  let mut tokens : Array Token := #[]
  let mut i : Nat := 0
  while i < chars.size do
    let c := chars[i]!
    if c.isWhitespace then
      i := i + 1
    else if c == '/' && i + 1 < chars.size && chars[i + 1]! == '/' then
      i := i + 2
      while i < chars.size && chars[i]! != '\n' do
        i := i + 1
    else if isIdentStart c then
      let start := i
      i := i + 1
      while i < chars.size && isIdentContinue chars[i]! do
        i := i + 1
      let word := sliceString chars start i
      let (line, column) := lineColumnAt source start
      tokens := tokens.push {
        kind := classifyWord word
        span := { byteStart := start, byteEnd := i, line, column }
      }
    else if c.isDigit then
      let start := i
      i := i + 1
      while i < chars.size && chars[i]!.isDigit do
        i := i + 1
      let text := sliceString chars start i
      let (line, column) := lineColumnAt source start
      tokens := tokens.push {
        kind := .number text
        span := { byteStart := start, byteEnd := i, line, column }
      }
    else if c == '"' then
      let start := i
      i := i + 1
      while i < chars.size && chars[i]! != '"' do
        i := i + 1
      if i >= chars.size then
        return .error <| .invalidProgram "unterminated string literal"
      i := i + 1
      let text := sliceString chars (start + 1) (i - 1)
      let (line, column) := lineColumnAt source start
      tokens := tokens.push {
        kind := .stringLit text
        span := { byteStart := start, byteEnd := i, line, column }
      }
    else
      let start := i
      i := i + 1
      let text := String.ofList [c]
      let (line, column) := lineColumnAt source start
      tokens := tokens.push {
        kind := .symbol text
        span := { byteStart := start, byteEnd := i, line, column }
      }
  let (line, column) := lineColumnAt source chars.size
  tokens := tokens.push {
    kind := .eof
    span := { byteStart := chars.size, byteEnd := chars.size, line, column }
  }
  let mut prevEnd : Nat := 0
  for token in tokens do
    unless token.span.isWellFormed do
      return .error <| .invalidProgram "token span is malformed"
    if token.span.byteStart < prevEnd then
      return .error <| .invalidProgram "token spans overlap or go backwards"
    prevEnd := token.span.byteEnd
  return .ok tokens

end ProofForgeV2.Source

namespace ProofForgeV2

abbrev ProgramRequirements := Array ProgramRequirement

end ProofForgeV2
