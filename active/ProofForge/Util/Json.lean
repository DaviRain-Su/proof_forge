/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal human-readable JSON serialization helpers shared across the CLI,
Contract, and Backend layers. These emit compact-but-readable JSON with a
space after each comma (arrays) and after each colon (object fields).

Previously `jsonString`/`jsonBool`/`jsonArray`/`jsonObject`/`jsonStringOption`/
`jsonStringArray` were duplicated in `Cli/JsonUtil.lean`, `Contract/Spec/Json.lean`,
and `Backend/Solana/Idl.lean`. This module is the single source of truth; the
per-layer modules now re-export thin aliases so existing callers that `open`
them are unchanged.
-/

namespace ProofForge.Util.Json

def jsonString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def jsonBool (value : Bool) : String :=
  if value then "true" else "false"

def jsonArray (items : Array String) : String :=
  "[" ++ String.intercalate ", " items.toList ++ "]"

def jsonObject (fields : Array (String × String)) : String :=
  "{" ++
    String.intercalate ", " (fields.toList.map fun field =>
      jsonString field.fst ++ ": " ++ field.snd) ++
  "}"

def jsonStringOption : Option String → String
  | some value => jsonString value
  | none => "null"

def jsonStringArray (values : Array String) : String :=
  jsonArray (values.map jsonString)

end ProofForge.Util.Json