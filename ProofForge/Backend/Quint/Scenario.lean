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
  nTraces : Nat := 10
  deriving Repr, Inhabited

def Config.quintPureDefs (cfg : Config) : Array PureDef := #[
  { name := "MAX_UINT", ret := .int, body := .literalInt (Int.ofNat cfg.maxUint) },
  { name := "USERS", ret := .set .str, body := .setLit (cfg.users.map .literalStr) }
]

def Config.userSetExpr (cfg : Config) : Expr :=
  .setLit (cfg.users.map .literalStr)

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

private def charsToQuotedString (chars : List Char) : Except String String :=
  let trimmed := trimChars chars
  match trimmed with
  | '"' :: rest =>
      let rev := rest.reverse
      match rev with
      | '"' :: bodyRev => .ok (String.ofList bodyRev.reverse)
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

/-- Very small TOML-like parser for scenario files.
    Supports only the keys needed by `Config`:
      max_uint = 3
      users = ["alice", "bob"]
      max_steps = 10
      n_traces = 10
    Lines starting with '#' are ignored. -/
def parse (input : String) : Except String Config := do
  let mut cfg : Config := {}
  let lines := splitLines input.toList
  for line in lines do
    let line := trimChars line
    if line.isEmpty || (line.head? == some '#') then
      continue
    match splitOnEq line with
    | none => .error s!"invalid scenario line: {String.ofList line}"
    | some (keyChars, valueChars) =>
        let key := String.ofList (trimChars keyChars)
        let value := String.ofList (trimChars valueChars)
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
          | "n_traces" =>
              match charsToNat value.toList with
              | some n => pure { cfg with nTraces := n }
              | none => .error s!"expected natural number, got: {value}"
          | _ => .error s!"unknown scenario key: {key}"
        cfg := cfg'
  pure cfg

end ProofForge.Backend.Quint.Scenario
