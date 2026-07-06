/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared JSON string builders for CLI output (artifact manifests, check reports,
metadata). These produce compact JSON text consumed by `json.loads` validators
and humans; whitespace is not semantically significant.

Previously `Cli.lean` and `Cli/Check.lean` each defined their own `jsonString`/
`jsonObject`/`jsonArray` with subtly different separators (`,` vs `, `). This
module is the single source of truth. Consumers should `open ProofForge.Cli.JsonUtil`
or call qualified names instead of redefining these helpers.
-/

namespace ProofForge.Cli.JsonUtil

/-- Escape a single character for JSON string content. -/
def escapeJsonChar : Char → String
  | '"' => "\\\""
  | '\\' => "\\\\"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | ch => ch.toString

/-- Render a string as a JSON string literal (with surrounding quotes and escaping). -/
def jsonString (value : String) : String :=
  "\"" ++ String.intercalate "" (value.toList.map escapeJsonChar) ++ "\""

/-- Render a Bool as a JSON literal. -/
def jsonBool (value : Bool) : String :=
  if value then "true" else "false"

/-- Render an Array of already-rendered JSON values as a JSON array. -/
def jsonArray (values : Array String) : String :=
  "[" ++ String.intercalate ", " values.toList ++ "]"

/-- Render an Array of strings as a JSON array of string literals. -/
def jsonStringArray (values : Array String) : String :=
  jsonArray (values.map jsonString)

/-- Render `some value` as a JSON string literal and `none` as `null`. -/
def jsonStringOption : Option String → String
  | some value => jsonString value
  | none => "null"

/-- Render `some value` as a JSON number and `none` as `null`. -/
def jsonNatOption : Option Nat → String
  | some value => toString value
  | none => "null"

/-- Render an Array of (key, already-rendered value) pairs as a JSON object.
The `": "` separator is human-readable and `json.loads`-compatible. -/
def jsonObject (fields : Array (String × String)) : String :=
  "{" ++ String.intercalate ", " (fields.toList.map fun field =>
    jsonString field.fst ++ ": " ++ field.snd) ++ "}"

end ProofForge.Cli.JsonUtil