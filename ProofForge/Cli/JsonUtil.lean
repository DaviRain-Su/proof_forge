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

import ProofForge.Util.Json

namespace ProofForge.Cli.JsonUtil

open ProofForge.Util.Json

/-- Escape a single character for JSON string content. -/
def escapeJsonChar : Char → String
  | '"' => "\\\""
  | '\\' => "\\\\"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | ch => ch.toString

/-- Re-export `Util.Json.jsonString` so CLI code that `open JsonUtil` keeps
seeing it. The implementation lives in `ProofForge.Util.Json` and is shared
with the Contract and Backend layers. -/
def jsonString (value : String) : String := ProofForge.Util.Json.jsonString value

/-- Re-export `Util.Json.jsonBool`. -/
def jsonBool (value : Bool) : String := ProofForge.Util.Json.jsonBool value

/-- Re-export `Util.Json.jsonArray`. -/
def jsonArray (values : Array String) : String := ProofForge.Util.Json.jsonArray values

/-- Re-export `Util.Json.jsonStringArray`. -/
def jsonStringArray (values : Array String) : String := ProofForge.Util.Json.jsonStringArray values

/-- Re-export `Util.Json.jsonStringOption`. -/
def jsonStringOption : Option String → String := ProofForge.Util.Json.jsonStringOption

/-- Render `some value` as a JSON number and `none` as `null`. -/
def jsonNatOption : Option Nat → String
  | some value => toString value
  | none => "null"

/-- Re-export `Util.Json.jsonObject`. The `": "` separator is human-readable
and `json.loads`-compatible. -/
def jsonObject (fields : Array (String × String)) : String := ProofForge.Util.Json.jsonObject fields

end ProofForge.Cli.JsonUtil