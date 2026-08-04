/-
  EVM TargetIR structural validation (M4 engineering slice).

  The EVM TargetIR is a Yul+ABI text carrier (`objectName`, `yul`, `abi`).
  This module performs **bounded structural** checks only — it is not a Yul
  parser, solc frontend, or formal TargetIR validation (TASK-D4 pending).

  What IS validated (fail closed):
  * non-empty objectName that appears as `object "<name>"` in Yul
  * Yul size bounds (1 .. maxEvmYulBytesV1)
  * balanced braces `{`/`}` outside of double-quoted strings
  * no unterminated double-quoted strings
  * no bare newline inside double-quoted strings
  * required fragment markers produced by `renderYul`
  * ABI JSON array shape + bracket balance + size bounds

  What is NOT validated: full Yul grammar, ABI schema completeness,
  semantic equivalence, solc acceptance (FinalizeV1 / Anvil).

  Wired into `lower` so every capability IR/file path fails closed on
  structural IR violations before emit/finalize.
-/
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler

def maxEvmYulBytesV1 : Nat := 4 * 1024 * 1024
def maxEvmAbiBytesV1 : Nat := 1024 * 1024

private def containsSubstr (haystack needle : String) : Bool :=
  if needle.isEmpty then
    true
  else
    let rec loop (cs : List Char) : Bool :=
      match cs with
      | [] => false
      | _ :: rest =>
          if needle.toList.isPrefixOf cs then true else loop rest
    loop haystack.toList

private def scanBalanced
    (label : String)
    (text : String)
    (openCh closeCh : Char) : CompileResult Unit := do
  let mut depth : Nat := 0
  let mut inString : Bool := false
  let mut escape : Bool := false
  let mut sawOpen : Bool := false
  for c in text.toList do
    if inString then
      if escape then
        escape := false
      else if c == '\\' then
        escape := true
      else if c == '"' then
        inString := false
      else if c == '\n' || c == '\r' then
        throw <| .planInvariant .evm
          s!"{label}: unterminated string (newline inside quotes)"
    else if c == '"' then
      inString := true
      escape := false
    else if c == openCh then
      depth := depth + 1
      sawOpen := true
    else if c == closeCh then
      if depth == 0 then
        throw <| .planInvariant .evm s!"{label}: unmatched closing delimiter"
      depth := depth - 1
  if inString then
    throw <| .planInvariant .evm s!"{label}: unterminated string"
  if depth != 0 then
    throw <| .planInvariant .evm s!"{label}: unbalanced delimiters (depth {depth})"
  unless sawOpen do
    throw <| .planInvariant .evm s!"{label}: missing opening delimiter"
  pure ()

private def requiresFragment (yul : String) (needle : String) (label : String) :
    CompileResult Unit := do
  unless containsSubstr yul needle do
    throw <| .planInvariant .evm s!"evm ir yul missing required fragment: {label}"

def validateEvmTargetIRV1
    (objectName : String) (yul : String) (abi : String) : CompileResult Unit := do
  if objectName.isEmpty then
    throw <| .planInvariant .evm "evm ir objectName must be non-empty"
  let yulBytes := yul.toUTF8.size
  if yulBytes == 0 then
    throw <| .planInvariant .evm "evm ir yul must be non-empty"
  if yulBytes > maxEvmYulBytesV1 then
    throw <| .planInvariant .evm
      s!"evm ir yul exceeds size limit {maxEvmYulBytesV1} bytes"
  let abiBytes := abi.toUTF8.size
  if abiBytes == 0 then
    throw <| .planInvariant .evm "evm ir abi must be non-empty"
  if abiBytes > maxEvmAbiBytesV1 then
    throw <| .planInvariant .evm
      s!"evm ir abi exceeds size limit {maxEvmAbiBytesV1} bytes"
  let objectMarker := "object \"" ++ objectName ++ "\" {"
  requiresFragment yul objectMarker "outer object name"
  requiresFragment yul "code {" "top-level code block"
  requiresFragment yul "object \"" "nested runtime object"
  requiresFragment yul "switch shr(224, calldataload(0))" "selector switch"
  -- Non-payable programs keep the global/entry `if callvalue() { revert(0, 0) }`
  -- fragment. Payable pf.assets programs always reference `callvalue()` via
  -- deposit exact-eq and/or non-payable entry guards; accept either form.
  unless containsSubstr yul "if callvalue() { revert(0, 0) }" ||
      containsSubstr yul "callvalue()" do
    throw <| .planInvariant .evm "evm ir yul missing required fragment: callvalue guard"
  requiresFragment yul "default { revert(0, 0) }" "dispatcher default arm"
  -- Nested .fieldDiv is unreachable for validated plans (nested slots are
  -- Bool/UInt-typed); the nested emitter stamps this marker instead of a
  -- wrong op, and any occurrence is rejected here (fail closed at compile
  -- time rather than silently emitting a multiply).
  if containsSubstr yul "pf_unsupported_nested_field_div" then
    throw <| .planInvariant .evm
      "evm ir contains unsupported nested fieldDiv marker (fieldDiv must lower via statement form)"
  scanBalanced "evm ir yul" yul '{' '}'
  let abiTrim := abi.trimAscii.copy
  unless abiTrim.startsWith "[" do
    throw <| .planInvariant .evm "evm ir abi must start with '['"
  unless abiTrim.endsWith "]" do
    throw <| .planInvariant .evm "evm ir abi must end with ']'"
  scanBalanced "evm ir abi" abiTrim '[' ']'
  pure ()

end ProofForgeV2.Targets.Evm
