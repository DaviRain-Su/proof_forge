import ProofForge.Compiler.Yul.AST
import ProofForge.Util.StringUtil

namespace ProofForge.Backend.Evm.YulSemantics

open Lean.Compiler.Yul
open ProofForge.Util.StringUtil

/-! A narrow executable Yul model for EVM refinement obligations.

This is intentionally small: it covers the Yul subset generated for the shared
Counter and ValueVault scenarios and fails explicitly for unsupported
constructs. It is not a general EVM interpreter; its job is to make FV-4
obligations stronger than surface-shape checks while keeping the trusted model
reviewable.
-/

abbrev Word := Nat
abbrev NamedBindings := List (String × Word)
abbrev WordBindings := List (Nat × Word)

def twoPow (n : Nat) : Nat :=
  2 ^ n

def lookupName (name : String) : NamedBindings → Option Word
  | [] => none
  | (key, value) :: rest =>
      if key == name then
        some value
      else
        lookupName name rest

def insertName (name : String) (value : Word) : NamedBindings → NamedBindings
  | [] => [(name, value)]
  | (key, oldValue) :: rest =>
      if key == name then
        (key, value) :: rest
      else
        (key, oldValue) :: insertName name value rest

def lookupWord (key : Nat) : WordBindings → Word
  | [] => 0
  | (slot, value) :: rest =>
      if slot == key then
        value
      else
        lookupWord key rest

def insertWord (key : Nat) (value : Word) : WordBindings → WordBindings
  | [] => [(key, value)]
  | (slot, oldValue) :: rest =>
      if slot == key then
        (slot, value) :: rest
      else
        (slot, oldValue) :: insertWord key value rest

structure Log where
  topics : Array Word := #[]
  data : Array Word := #[]
  deriving Repr, BEq, DecidableEq

structure Runtime where
  storage : WordBindings := []
  memory : WordBindings := []
  locals : NamedBindings := []
  calldata : WordBindings := []
  calldataSize : Nat := 4
  blockNumber : Word := 0
  timestamp : Word := 0
  chainId : Word := 0
  gasPrice : Word := 0
  gasLeft : Word := 0
  baseFee : Word := 0
  prevRandao : Word := 0
  origin : Word := 0
  coinbase : Word := 0
  logs : Array Log := #[]
  deriving Repr, BEq, DecidableEq

structure FunctionDef where
  name : String
  params : Array TypedName
  returns : Array TypedName
  body : Block

structure Context where
  functions : Array FunctionDef

inductive Control where
  | running
  | leave
  | returned (words : Array Word)
  deriving Repr, BEq, DecidableEq

def Runtime.readLocal (rt : Runtime) (name : String) : Except String Word :=
  match lookupName name rt.locals with
  | some value => .ok value
  | none => .error s!"unknown Yul local `{name}`"

def Runtime.writeLocal (rt : Runtime) (name : String) (value : Word) : Runtime :=
  { rt with locals := insertName name value rt.locals }

def Runtime.readStorage (rt : Runtime) (slot : Nat) : Word :=
  lookupWord slot rt.storage

def Runtime.writeStorage (rt : Runtime) (slot : Nat) (value : Word) : Runtime :=
  { rt with storage := insertWord slot value rt.storage }

def Runtime.readMemory (rt : Runtime) (offset : Nat) : Word :=
  lookupWord offset rt.memory

def Runtime.writeMemory (rt : Runtime) (offset : Nat) (value : Word) : Runtime :=
  { rt with memory := insertWord offset value rt.memory }

def Runtime.readCalldata (rt : Runtime) (offset : Nat) : Word :=
  lookupWord offset rt.calldata

def Runtime.pushLog (rt : Runtime) (topics data : Array Word) : Runtime :=
  { rt with logs := rt.logs.push { topics, data } }

def decimalDigit? (c : Char) : Option Nat :=
  if '0' <= c && c <= '9' then
    some (c.toNat - '0'.toNat)
  else
    none

def hexDigit? (c : Char) : Option Nat :=
  if '0' <= c && c <= '9' then
    some (c.toNat - '0'.toNat)
  else if 'a' <= c && c <= 'f' then
    some (10 + c.toNat - 'a'.toNat)
  else if 'A' <= c && c <= 'F' then
    some (10 + c.toNat - 'A'.toNat)
  else
    none

def parseDigits (base : Nat) (digit? : Char → Option Nat) (chars : List Char) :
    Except String Nat :=
  chars.foldlM
    (fun acc c =>
      match digit? c with
      | some digit =>
          if digit < base then
            .ok (acc * base + digit)
          else
            .error s!"digit `{c}` is out of range for base {base}"
      | none => .error s!"invalid digit `{c}`")
    0

def parseDecimalNat (value : String) : Except String Nat :=
  parseDigits 10 decimalDigit? value.toList

def parseHexNat (value : String) : Except String Nat :=
  parseDigits 16 hexDigit? (stripHexPrefix value).toList

def parseLiteralWord : Literal → Except String Word
  | { kind := .number, value } => parseDecimalNat value
  | { kind := .hexNumber, value } => parseHexNat value
  | { kind := .bool, value } =>
      if value == "true" then .ok 1
      else if value == "false" then .ok 0
      else .error s!"invalid Yul bool literal `{value}`"
  | { kind := .string, value := _ } =>
      .error "string literals are not supported by the FV-4 Yul subset"
  | { kind := .hexString, value := _ } =>
      .error "hex string literals are not supported by the FV-4 Yul subset"

def collectFunctions (object : Object) : Array FunctionDef :=
  object.code.statements.foldl
    (fun acc stmt =>
      match stmt with
      | .funcDef name params returns body =>
          acc.push { name, params, returns, body }
      | _ => acc)
    #[]

def Context.ofObject (object : Object) : Context := {
  functions := collectFunctions object
}

def Context.findFunction? (ctx : Context) (name : String) : Option FunctionDef :=
  ctx.functions.find? fun fn => fn.name == name

def bindParams (params : Array TypedName) (args : Array Word) : Except String NamedBindings := do
  if params.size != args.size then
    .error s!"function expected {params.size} argument(s), got {args.size}"
  let mut bindings : NamedBindings := []
  for h : idx in [0:params.size] do
    let some arg := args[idx]?
      | .error s!"missing function argument {idx}"
    bindings := insertName params[idx].name arg bindings
  .ok bindings

def initReturnBindings (returns : Array TypedName) (bindings : NamedBindings) : NamedBindings :=
  returns.foldl (fun acc ret => insertName ret.name 0 acc) bindings

def collectReturnValues (returns : Array TypedName) (locals : NamedBindings) :
    Except String (Array Word) := do
  let mut values := #[]
  for ret in returns do
    match lookupName ret.name locals with
    | some value => values := values.push value
    | none => .error s!"function return local `{ret.name}` was not assigned"
  .ok values

def memoryWords (rt : Runtime) (offset size : Nat) : Array Word :=
  Id.run do
    let count := (size + 31) / 32
    let mut words := #[]
    for _h : idx in [0:count] do
      words := words.push (rt.readMemory (offset + idx * 32))
    words

def pseudoKeccakStep (acc word : Word) : Word :=
  (acc * 1315423911 + word + 2654435761) % twoPow 256

/-- Deterministic, memory-sensitive surrogate for `keccak256`.

The FV-4 interpreter is not a cryptographic EVM model. For storage-layout
obligations it only needs generated map/hash helper calls to be deterministic
and to distinguish the memory words they hash, so this deliberately small
surrogate keeps the executable model reviewable while avoiding the old
all-zero hash collision.
-/
def pseudoKeccak (rt : Runtime) (offset size : Nat) : Word :=
  let words := memoryWords rt offset size
  words.foldl pseudoKeccakStep
    ((offset + 1) * 16777619 + (size + 1) * 1099511628211)

def pseudoKeccakWords (words : Array Word) : Word :=
  let size := words.size * 32
  words.foldl pseudoKeccakStep
    ((0 + 1) * 16777619 + (size + 1) * 1099511628211)

def selectorCalldataWord (selector : Nat) : Word :=
  selector * twoPow 224

def calldataArgBindings (args : Array Word) : WordBindings := Id.run do
  let mut bindings : WordBindings := []
  for h : idx in [0:args.size] do
    bindings := insertWord (4 + idx * 32) args[idx] bindings
  bindings

def callRuntimeWithArgs (selector : Nat) (storage : WordBindings) (args : Array Word) :
    Runtime := {
  storage
  memory := []
  locals := []
  calldata := insertWord 0 (selectorCalldataWord selector) (calldataArgBindings args)
  calldataSize := 4 + args.size * 32
  blockNumber := 0
  timestamp := 0
  chainId := 0
  gasPrice := 0
  gasLeft := 0
  baseFee := 0
  prevRandao := 0
  origin := 0
  coinbase := 0
  logs := #[]
}

def callRuntime (selector : Nat) (storage : WordBindings) : Runtime :=
  callRuntimeWithArgs selector storage #[]

mutual
  partial def evalExpr (ctx : Context) (rt : Runtime) : Expr →
      Except String (Runtime × Array Word)
    | .lit literal => do
        let value ← parseLiteralWord literal
        .ok (rt, #[value])
    | .ident name => do
        let value ← rt.readLocal name
        .ok (rt, #[value])
    | .builtin name args => evalBuiltin ctx rt name args
    | .call name args => evalCall ctx rt name args

  partial def evalWord (ctx : Context) (rt : Runtime) (expr : Expr) :
      Except String (Runtime × Word) := do
    let (rt, values) ← evalExpr ctx rt expr
    match values.toList with
    | [value] => .ok (rt, value)
    | [] => .error "expected one Yul word, got no values"
    | _ => .error s!"expected one Yul word, got {values.size} values"

  partial def evalArgs (ctx : Context) (rt : Runtime) (args : Array Expr) :
      Except String (Runtime × Array Word) := do
    let mut current := rt
    let mut values := #[]
    for arg in args do
      let (next, value) ← evalWord ctx current arg
      current := next
      values := values.push value
    .ok (current, values)

  partial def evalBuiltin (ctx : Context) (rt : Runtime) (name : String) (args : Array Expr) :
      Except String (Runtime × Array Word) := do
    match name, args.toList with
    | "add", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[lhs + rhs])
    | "sub", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[lhs - rhs])
    | "mul", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[lhs * rhs])
    | "div", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[if rhs == 0 then 0 else lhs / rhs])
    | "mod", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[if rhs == 0 then 0 else lhs % rhs])
    | "exp", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[lhs ^ rhs])
    | "eq", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[if lhs == rhs then 1 else 0])
    | "lt", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[if lhs < rhs then 1 else 0])
    | "gt", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[if lhs > rhs then 1 else 0])
    | "iszero", [value] => do
        let (rt, value) ← evalWord ctx rt value
        .ok (rt, #[if value == 0 then 1 else 0])
    | "and", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[Nat.land lhs rhs])
    | "or", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[Nat.lor lhs rhs])
    | "xor", [lhs, rhs] => do
        let (rt, lhs) ← evalWord ctx rt lhs
        let (rt, rhs) ← evalWord ctx rt rhs
        .ok (rt, #[Nat.xor lhs rhs])
    | "not", [value] => do
        let (rt, value) ← evalWord ctx rt value
        let modulus := twoPow 256
        .ok (rt, #[(modulus - 1) - (value % modulus)])
    | "shl", [shift, value] => do
        let (rt, shift) ← evalWord ctx rt shift
        let (rt, value) ← evalWord ctx rt value
        .ok (rt, #[value * twoPow shift])
    | "shr", [shift, value] => do
        let (rt, shift) ← evalWord ctx rt shift
        let (rt, value) ← evalWord ctx rt value
        .ok (rt, #[value / twoPow shift])
    | "calldataload", [offset] => do
        let (rt, offset) ← evalWord ctx rt offset
        .ok (rt, #[rt.readCalldata offset])
    | "sload", [slotExpr] => do
        let (rt, slot) ← evalWord ctx rt slotExpr
        .ok (rt, #[rt.readStorage slot])
    | "sstore", [slotExpr, valueExpr] => do
        let (rt, slot) ← evalWord ctx rt slotExpr
        let (rt, value) ← evalWord ctx rt valueExpr
        .ok (rt.writeStorage slot value, #[])
    | "mstore", [offsetExpr, valueExpr] => do
        let (rt, offset) ← evalWord ctx rt offsetExpr
        let (rt, value) ← evalWord ctx rt valueExpr
        .ok (rt.writeMemory offset value, #[])
    | "calldatasize", [] =>
        .ok (rt, #[rt.calldataSize])
    | "number", [] =>
        .ok (rt, #[rt.blockNumber])
    | "timestamp", [] =>
        .ok (rt, #[rt.timestamp])
    | "chainid", [] =>
        .ok (rt, #[rt.chainId])
    | "gasprice", [] =>
        .ok (rt, #[rt.gasPrice])
    | "gas", [] =>
        .ok (rt, #[rt.gasLeft])
    | "basefee", [] =>
        .ok (rt, #[rt.baseFee])
    | "prevrandao", [] =>
        .ok (rt, #[rt.prevRandao])
    | "origin", [] =>
        .ok (rt, #[rt.origin])
    | "coinbase", [] =>
        .ok (rt, #[rt.coinbase])
    | "blockhash", [blockNumber] => do
        let (rt, _blockNumber) ← evalWord ctx rt blockNumber
        .ok (rt, #[0])
    | "keccak256", [offset, size] => do
        let (rt, offset) ← evalWord ctx rt offset
        let (rt, size) ← evalWord ctx rt size
        .ok (rt, #[pseudoKeccak rt offset size])
    | "log0", [offset, size] =>
        evalLog ctx rt #[offset, size] 0
    | "log1", [offset, size, topic0] =>
        evalLog ctx rt #[offset, size, topic0] 1
    | "log2", [offset, size, topic0, topic1] =>
        evalLog ctx rt #[offset, size, topic0, topic1] 2
    | "log3", [offset, size, topic0, topic1, topic2] =>
        evalLog ctx rt #[offset, size, topic0, topic1, topic2] 3
    | "log4", [offset, size, topic0, topic1, topic2, topic3] =>
        evalLog ctx rt #[offset, size, topic0, topic1, topic2, topic3] 4
    | _, _ =>
        .error s!"unsupported Yul builtin `{name}` with {args.size} argument(s)"

  partial def evalLog (ctx : Context) (rt : Runtime) (args : Array Expr) (topicCount : Nat) :
      Except String (Runtime × Array Word) := do
    let (rt, values) ← evalArgs ctx rt args
    if values.size != topicCount + 2 then
      .error s!"Yul log expected {topicCount + 2} evaluated argument(s), got {values.size}"
    let some offset := values[0]?
      | .error "Yul log missing memory offset"
    let some size := values[1]?
      | .error "Yul log missing memory size"
    let topics := values.toList.drop 2 |>.toArray
    .ok (rt.pushLog topics (memoryWords rt offset size), #[])

  partial def evalCall (ctx : Context) (rt : Runtime) (name : String) (args : Array Expr) :
      Except String (Runtime × Array Word) := do
    let some fn := ctx.findFunction? name
      | .error s!"unknown Yul function `{name}`"
    let (rtAfterArgs, argValues) ← evalArgs ctx rt args
    let paramBindings ← bindParams fn.params argValues
    let functionLocals := initReturnBindings fn.returns paramBindings
    let functionRuntime := { rtAfterArgs with locals := functionLocals }
    let (functionRuntime, control) ← execBlock ctx functionRuntime fn.body
    match control with
    | .running | .leave => pure ()
    | .returned _ =>
        .error s!"Yul function `{name}` performed an EVM return"
    let returnValues ← collectReturnValues fn.returns functionRuntime.locals
    .ok ({ rtAfterArgs with
      storage := functionRuntime.storage
      memory := functionRuntime.memory
      logs := functionRuntime.logs
    }, returnValues)

  partial def execExprStmt (ctx : Context) (rt : Runtime) : Expr →
      Except String (Runtime × Control)
    | .builtin "return" args =>
        match args.toList with
        | [offsetExpr, sizeExpr] => do
            let (rt, offset) ← evalWord ctx rt offsetExpr
            let (rt, size) ← evalWord ctx rt sizeExpr
            .ok (rt, .returned (memoryWords rt offset size))
        | _ => .error s!"Yul return expected 2 arguments, got {args.size}"
    | .builtin "revert" _ =>
        .error "Yul execution reverted"
    | expr => do
        let (rt, _) ← evalExpr ctx rt expr
        .ok (rt, .running)

  partial def assignValues (rt : Runtime) (names : Array String) (values : Array Word) :
      Except String Runtime := do
    if names.size != values.size then
      .error s!"assignment expected {names.size} value(s), got {values.size}"
    let mut current := rt
    for h : idx in [0:names.size] do
      let some value := values[idx]?
        | .error s!"missing assignment value {idx}"
      current := current.writeLocal names[idx] value
    .ok current

  partial def declareValues (rt : Runtime) (vars : Array TypedName) (values : Array Word) :
      Except String Runtime :=
    assignValues rt (vars.map (·.name)) values

  partial def execStatement (ctx : Context) (rt : Runtime) : Statement →
      Except String (Runtime × Control)
    | .block block => execBlock ctx rt block
    | .varDecl vars none =>
        declareValues rt vars (vars.map fun _ => 0) |>.map fun rt => (rt, .running)
    | .varDecl vars (some value) => do
        let (rt, values) ← evalExpr ctx rt value
        let rt ← declareValues rt vars values
        .ok (rt, .running)
    | .assignment names value => do
        let (rt, values) ← evalExpr ctx rt value
        let rt ← assignValues rt names values
        .ok (rt, .running)
    | .exprStmt expr =>
        execExprStmt ctx rt expr
    | .ifStmt condition body => do
        let (rt, value) ← evalWord ctx rt condition
        if value == 0 then
          .ok (rt, .running)
        else
          execBlock ctx rt body
    | .switchStmt selector cases => do
        let (rt, value) ← evalWord ctx rt selector
        execSwitch ctx rt value cases
    | .funcDef _ _ _ _ =>
        .ok (rt, .running)
    | .forLoop pre cond post body =>
        execForLoop ctx rt pre cond post body
    | .break =>
        .error "break is not supported by the FV-4 Yul subset"
    | .continue =>
        .error "continue is not supported by the FV-4 Yul subset"
    | .leave =>
        .ok (rt, .leave)

  partial def execStatements (ctx : Context) (rt : Runtime) : List Statement →
      Except String (Runtime × Control)
    | [] => .ok (rt, .running)
    | stmt :: rest => do
        let (rt, control) ← execStatement ctx rt stmt
        match control with
        | .running => execStatements ctx rt rest
        | .leave | .returned _ => .ok (rt, control)

  partial def execBlock (ctx : Context) (rt : Runtime) (block : Block) :
      Except String (Runtime × Control) :=
    execStatements ctx rt block.statements.toList

  partial def execSwitch (ctx : Context) (rt : Runtime) (value : Word) (cases : Array Case) :
      Except String (Runtime × Control) := do
    let rec findMatching : List Case → Option Case
      | [] => none
      | case :: rest =>
          match case.value with
          | some literal =>
              match parseLiteralWord literal with
              | .ok caseValue =>
                  if caseValue == value then some case else findMatching rest
              | .error _ => findMatching rest
          | none => findMatching rest
    let rec findDefault : List Case → Option Case
      | [] => none
      | case :: rest =>
          match case.value with
          | none => some case
          | some _ => findDefault rest
    match findMatching cases.toList <|> findDefault cases.toList with
    | some selected => execBlock ctx rt selected.body
    | none => .ok (rt, .running)

  partial def execForLoop
      (ctx : Context)
      (rt : Runtime)
      (pre : Block)
      (cond : Expr)
      (post body : Block) : Except String (Runtime × Control) := do
    let (rt, control) ← execBlock ctx rt pre
    match control with
    | .running => execForLoopBody ctx rt cond post body
    | .leave | .returned _ => .ok (rt, control)

  partial def execForLoopBody
      (ctx : Context)
      (rt : Runtime)
      (cond : Expr)
      (post body : Block) : Except String (Runtime × Control) := do
    let (rt, condition) ← evalWord ctx rt cond
    if condition == 0 then
      .ok (rt, .running)
    else
      let (rt, control) ← execBlock ctx rt body
      match control with
      | .running =>
          let (rt, postControl) ← execBlock ctx rt post
          match postControl with
          | .running => execForLoopBody ctx rt cond post body
          | .leave | .returned _ => .ok (rt, postControl)
      | .leave | .returned _ => .ok (rt, control)
end

def runSelectorWithArgsWithLogs (object : Object) (storage : WordBindings) (selector : Nat)
    (args : Array Word) :
    Except String (WordBindings × Array Word × Array Log) := do
  let ctx := Context.ofObject object
  let (rt, control) ← execBlock ctx (callRuntimeWithArgs selector storage args) object.code
  match control with
  | .returned words => .ok (rt.storage, words, rt.logs)
  | .running => .error "Yul dispatcher finished without returning"
  | .leave => .error "Yul dispatcher left without returning"

def runSelectorWithArgs (object : Object) (storage : WordBindings) (selector : Nat)
    (args : Array Word) :
    Except String (WordBindings × Array Word) := do
  let (storage, words, _) ← runSelectorWithArgsWithLogs object storage selector args
  .ok (storage, words)

def runSelector (object : Object) (storage : WordBindings) (selector : Nat) :
    Except String (WordBindings × Array Word) :=
  runSelectorWithArgs object storage selector #[]

end ProofForge.Backend.Evm.YulSemantics
