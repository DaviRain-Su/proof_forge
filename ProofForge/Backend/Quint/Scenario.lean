import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.Scenario

open ProofForge.Backend.Quint

/-- Scenario configuration that controls abstractions used when lowering
    a portable IR module to a Quint model. -/
structure Config where
  maxUint : Nat := 3
  users : Array String := #["alice", "bob", "charlie"]
  maxSteps : Nat := 10
  maxLoopUnroll : Nat := 10
  nTraces : Nat := 10
  /-- When true, nondet integer params sample `0..MAX_UINT` instead of `1..MAX_UINT`. -/
  indexFromZero : Bool := false
  /-- When true (default), literals and computed integer state use Quint unbounded `int`
      semantics. Only nondet entrypoint parameters stay bounded by `maxUint` (`MAX_UINT`).
      Set `unbounded_integers = false` in scenario TOML to document strict bounded models. -/
  unboundedIntegers : Bool := true
  /-- Scenario TOML `[invariants]` entries. -/
  invariants : Array (String × String) := #[]
  /-- `contract_source` `quint_invariant` annotations merged at emit time. -/
  contractInvariants : Array (String × String) := #[]
  /-- Scenario TOML `[liveness]` entries. -/
  liveness : Array (String × String) := #[]
  /-- `contract_source` `quint_liveness` annotations merged at emit time. -/
  contractLiveness : Array (String × String) := #[]
  deriving Repr, Inhabited

def Config.quintPureDefs (cfg : Config) : Array PureDef := #[
  { name := "MAX_UINT", ret := .int, body := .literalInt (Int.ofNat cfg.maxUint) },
  { name := "USERS", ret := .set .str, body := .setLit (cfg.users.map .literalStr) }
]

def Config.userSetExpr (cfg : Config) : Expr :=
  .setLit (cfg.users.map .literalStr)

/-- Default scenario bounds tuned per Quint fixture (MBT gates and model-check budgets). -/
def defaultForFixture (fixtureId : String) : Config :=
  match fixtureId with
  | "counter" =>
      { maxUint := 3, users := #["alice", "bob"], maxSteps := 5, nTraces := 10 }
  | "value-vault" =>
      { maxUint := 100, users := #["alice", "bob"], maxSteps := 5, nTraces := 10 }
  | "struct-dynamic-path" =>
      { maxUint := 1, users := #["alice"], indexFromZero := true }
  | "assert" | "assignment" | "crosscall" =>
      { maxUint := 20, users := #["alice"], indexFromZero := true }
  | "unbounded-int" =>
      { maxUint := 3, users := #["alice"], indexFromZero := true, unboundedIntegers := true }
  | _ => {}

private def escapeTomlString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\t' => "\\t"
    | '\r' => "\\r"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

private def renderUsers (users : Array String) : String :=
  "[" ++ String.intercalate ", " (users.map escapeTomlString).toList ++ "]"

private def renderExprEntries (sectionName : String) (entries : Array (String × String)) : Array String :=
  if entries.isEmpty then #[] else
    #[s!"[{sectionName}]"] ++
      entries.map (fun (name, expr) => s!"{name} = {escapeTomlString expr}")

/-- Render a scenario config as editable TOML (bounds, optional scenario invariants/liveness). -/
def renderToml (fixtureId : String) (cfg : Config) : String :=
  let header := s!"# Auto-generated Quint scenario for `{fixtureId}`."
  let note :=
    "# Safety invariants and liveness from contract_source are merged at emit time."
  let lines0 := #[header, note, s!"max_uint = {cfg.maxUint}", s!"users = {renderUsers cfg.users}",
    s!"max_steps = {cfg.maxSteps}", s!"max_loop_unroll = {cfg.maxLoopUnroll}",
    s!"n_traces = {cfg.nTraces}"]
  let lines1 := if cfg.indexFromZero then lines0.push "index_from_zero = true" else lines0
  let lines2 := if !cfg.unboundedIntegers then lines1.push "unbounded_integers = false" else lines1
  let lines3 := lines2 ++ renderExprEntries "invariants" cfg.invariants
  let lines4 := lines3 ++ renderExprEntries "liveness" cfg.liveness
  String.intercalate "\n" lines4.toList

private def isWhitespace (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\r' || c == '\n'

private def trimChars (chars : List Char) : List Char :=
  let rec dropWhile (p : Char → Bool) : List Char → List Char
    | [] => []
    | c :: cs => if p c then dropWhile p cs else c :: cs
  dropWhile isWhitespace (dropWhile isWhitespace chars).reverse |>.reverse

private def charsToNat (chars : List Char) : Option Nat :=
  let s := String.ofList chars
  s.toNat?

private def splitOnComma (chars : List Char) : Array (List Char) :=
  let rec loop (acc : Array (List Char)) (cur : List Char) (cs : List Char) : Array (List Char) :=
    match cs with
    | [] => acc.push cur.reverse
    | ',' :: rest => loop (acc.push cur.reverse) [] rest
    | c :: rest => loop acc (c :: cur) rest
  loop #[] [] chars

private partial def unescapeString (acc : List Char) (cs : List Char) : Except String (List Char) :=
  match cs with
  | [] => .ok acc.reverse
  | '\\' :: c :: rest =>
      let decoded :=
        match c with
        | '"' => '"'
        | '\\' => '\\'
        | 'n' => '\n'
        | 't' => '\t'
        | 'r' => '\r'
        | _ => c
      unescapeString (decoded :: acc) rest
  | c :: rest => unescapeString (c :: acc) rest

private def charsToQuotedString (chars : List Char) : Except String String :=
  let trimmed := trimChars chars
  match trimmed with
  | '"' :: rest =>
      let rev := rest.reverse
      match rev with
      | '"' :: bodyRev =>
          let body := bodyRev.reverse
          match unescapeString [] body with
          | .ok s => .ok (String.ofList s)
          | .error e => .error e
      | _ => .error s!"expected quoted string, got: {String.ofList chars}"
  | _ => .error s!"expected quoted string, got: {String.ofList chars}"

private partial def charsToStringArray (chars : List Char) : Except String (Array String) := do
  let trimmed := trimChars chars
  match trimmed with
  | '[' :: rest =>
      let lastRev := rest.reverse
      match lastRev with
      | ']' :: bodyRev =>
          let body := trimChars bodyRev.reverse
          if body.isEmpty then
            pure #[]
          else
            let tokens := splitOnComma body
            let strs ← tokens.toList.mapM charsToQuotedString
            pure strs.toArray
      | _ => .error s!"expected array, got: {String.ofList chars}"
  | _ => .error s!"expected array, got: {String.ofList chars}"


private def splitLines (chars : List Char) : Array (List Char) :=
  let rec loop (acc : Array (List Char)) (cur : List Char) (cs : List Char) : Array (List Char) :=
    match cs with
    | [] => acc.push cur.reverse
    | '\n' :: rest => loop (acc.push cur.reverse) [] rest
    | c :: rest => loop acc (c :: cur) rest
  loop #[] [] chars

private def splitOnEq (chars : List Char) : Option (List Char × List Char) :=
  let rec find (before : List Char) (cs : List Char) : Option (List Char × List Char) :=
    match cs with
    | [] => none
    | '=' :: rest => some (before.reverse, rest)
    | c :: rest => find (c :: before) rest
  find [] chars

private def parseSectionHeader (chars : List Char) : Option String :=
  let trimmed := trimChars chars
  match trimmed with
  | '[' :: rest =>
      let rev := rest.reverse
      match rev with
      | ']' :: bodyRev => some (String.ofList (trimChars bodyRev.reverse))
      | _ => none
  | _ => none

/-- Very small TOML-like parser for scenario files.
    Supports only the keys needed by `Config`:
      max_uint = 3
      users = ["alice", "bob"]
      max_steps = 10
      max_loop_unroll = 10
      n_traces = 10
      unbounded_integers = true
    Lines starting with '#' are ignored. -/
def parse (input : String) : Except String Config := do
  let mut cfg : Config := {}
  let mut currentSection := ""
  let lines := splitLines input.toList
  for line in lines do
    let line := trimChars line
    if line.isEmpty || (line.head? == some '#') then
      continue
    if let some sec := parseSectionHeader line then
      currentSection := sec
      continue
    match splitOnEq line with
    | none => .error s!"invalid scenario line: {String.ofList line}"
    | some (keyChars, valueChars) =>
        let key := String.ofList (trimChars keyChars)
        let value := String.ofList (trimChars valueChars)
        if currentSection == "invariants" then
          let expr ← charsToQuotedString value.toList
          cfg := { cfg with invariants := cfg.invariants.push (key, expr) }
        else if currentSection == "liveness" then
          let expr ← charsToQuotedString value.toList
          cfg := { cfg with liveness := cfg.liveness.push (key, expr) }
        else
          let cfg' ← match key with
            | "max_uint" =>
                match charsToNat value.toList with
                | some n => pure { cfg with maxUint := n }
                | none => .error s!"expected natural number, got: {value}"
            | "users" =>
                let us ← charsToStringArray value.toList
                pure { cfg with users := us }
            | "max_steps" =>
                match charsToNat value.toList with
                | some n => pure { cfg with maxSteps := n }
                | none => .error s!"expected natural number, got: {value}"
            | "max_loop_unroll" =>
                match charsToNat value.toList with
                | some n => pure { cfg with maxLoopUnroll := n }
                | none => .error s!"expected natural number, got: {value}"
            | "n_traces" =>
                match charsToNat value.toList with
                | some n => pure { cfg with nTraces := n }
                | none => .error s!"expected natural number, got: {value}"
            | "unbounded_integers" =>
                match value with
                | "true" => pure { cfg with unboundedIntegers := true }
                | "false" => pure { cfg with unboundedIntegers := false }
                | _ => .error s!"expected boolean, got: {value}"
            | "index_from_zero" =>
                match value with
                | "true" => pure { cfg with indexFromZero := true }
                | "false" => pure { cfg with indexFromZero := false }
                | _ => .error s!"expected boolean, got: {value}"
            | _ => .error s!"unknown scenario key: {key}"
          cfg := cfg'
  pure cfg

end ProofForge.Backend.Quint.Scenario
