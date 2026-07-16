/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Wasm AST printer — renders a `Wasm.Module` to WAT source text.

The output is valid input for `wat2wasm` (wabt). Pure functional style: each
printer takes an indent level and returns the rendered text. Mirrors
`ProofForge.Compiler.Yul.Printer`.
-/
module

prelude
public import Init.Prelude
import Init.Data.Array.Basic
import Init.Data.String.Basic
public import ProofForge.Compiler.Wasm.AST

public section

namespace ProofForge.Compiler.Wasm.Printer

open ProofForge.Compiler.Wasm

/-- Indent prefix: two spaces per level. -/
def pad : Nat → String
  | 0 => ""
  | n+1 => "  " ++ pad n

/-- A single indented line, terminated by a newline. -/
def line (indent : Nat) (s : String) : String :=
  pad indent ++ s ++ "\n"

/-- One lowercase hex digit. -/
def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n) else Char.ofNat ('a'.toNat + (n - 10))

/-- A byte value as two lowercase hex digits (e.g. 5 -> "05", 255 -> "ff"). -/
def toHexByte (n : Nat) : String :=
  String.ofList [hexDigit (n / 16 % 16), hexDigit (n % 16)]

/-! Escape the body of a WAT string literal. Printable ASCII passes through
    (except `"` and `\`), control bytes become `\HH` hex escapes, and
    multibyte UTF-8 passes through verbatim (valid in WAT). -/
def escapeWatChar (c : Char) : String :=
  let n := c.toNat
  if c == '"' then "\\\""
  else if c == '\\' then "\\\\"
  else if n <= 0x1f || n == 0x7f then "\\" ++ toHexByte n
  else toString c

def escapeWatString (s : String) : String :=
  s.toList.foldl (fun acc c => acc ++ escapeWatChar c) ""

/-- Render a param/result type list as `(param i64 i32)` or `(result i64)`. -/
def printTypeList (keyword : String) (types : Array ValType) : String :=
  if types.isEmpty then ""
  else "(" ++ keyword ++ " " ++ String.intercalate " " (types.toList.map ValType.wat) ++ ")"

/-- Render `(param $name i64)` clauses joined by spaces. -/
def printParams (ps : Array Local) : String :=
  ps.foldl (fun acc p => acc ++ " (param $" ++ p.name ++ " " ++ p.type.wat ++ ")") ""

/-- Render `(local $name i64)` clauses joined by spaces. -/
def printLocals (ls : Array Local) : String :=
  ls.foldl (fun acc l => acc ++ " (local $" ++ l.name ++ " " ++ l.type.wat ++ ")") ""

/-- Render `(result i64)` or empty. -/
def printResults (rs : Array ValType) : String :=
  if rs.isEmpty then "" else " " ++ printTypeList "result" rs

/-- Render an import's function signature inline:
    `(func $name (param i64 i64 i64) (result i64))`. -/
def printImportSig (funcName : String) (type : FuncType) : String :=
  let params := printTypeList "param" type.params
  let results := printTypeList "result" type.results
  let head := "func $" ++ funcName
  let rest := (if params.isEmpty then [] else [params]) ++ (if results.isEmpty then [] else [results])
  "(" ++ String.intercalate " " (head :: rest) ++ ")"

/-- Render an import. -/
def printImport (indent : Nat) (i : Import) : String :=
  line indent ("(import \"" ++ escapeWatString i.module_ ++ "\" \"" ++ escapeWatString i.name ++ "\" " ++ printImportSig i.funcName i.type ++ ")")

/-- Render the memory declaration. -/
def printMemory (indent : Nat) (m : Memory) : String :=
  let exportPart := match m.exportName with
    | some n => "(export \"" ++ escapeWatString n ++ "\") "
    | none => ""
  let limits := match m.max with
    | some max => toString m.min ++ " " ++ toString max
    | none => toString m.min
  line indent ("(memory " ++ exportPart ++ limits ++ ")")

/-- Render a data segment. -/
def printData (indent : Nat) (d : DataSegment) : String :=
  line indent ("(data (i32.const " ++ toString d.offset ++ ") \"" ++ escapeWatString d.bytes ++ "\")")

/-- Render a global declaration. -/
def printGlobal (indent : Nat) (g : Global) : String :=
  let mutKind := if g.isMutable then "(mut " ++ g.type.wat ++ ")" else g.type.wat
  line indent ("(global $" ++ g.name ++ " " ++ mutKind ++ " (" ++ g.type.wat ++ ".const " ++ g.init ++ "))")

mutual
  /-- Render an instruction (possibly multiple lines). -/
  partial def printInsn (indent : Nat) : Insn → String
    | .nop => line indent "nop"
    | .unreachable => line indent "unreachable"
    | .drop => line indent "drop"
    | .select => line indent "select"
    | .return_ => line indent "return"
    | .br l => line indent ("br " ++ toString l)
    | .brIf l => line indent ("br_if " ++ toString l)
    | .const t v => line indent (t.wat ++ ".const " ++ v)
    | .localGet n => line indent ("local.get $" ++ n)
    | .localSet n => line indent ("local.set $" ++ n)
    | .localTee n => line indent ("local.tee $" ++ n)
    | .globalGet n => line indent ("global.get $" ++ n)
    | .globalSet n => line indent ("global.set $" ++ n)
    | .plain name => line indent name
    | .load name offset =>
      line indent (if offset == 0 then name else name ++ " offset=" ++ toString offset)
    | .store name offset =>
      line indent (if offset == 0 then name else name ++ " offset=" ++ toString offset)
    | .call name => line indent ("call $" ++ name)
    | .block_ body =>
      line indent "block" ++ printInsns (indent + 1) body.insns ++ line indent "end"
    | .loop_ body =>
      line indent "loop" ++ printInsns (indent + 1) body.insns ++ line indent "end"
    | .if_ thenBody elseBody =>
      line indent "if"
        ++ printInsns (indent + 1) thenBody.insns
        ++ line indent "else"
        ++ printInsns (indent + 1) elseBody.insns
        ++ line indent "end"

  /-- Render a sequence of instructions. -/
  partial def printInsns (indent : Nat) (insns : Array Insn) : String :=
    insns.foldl (fun acc i => acc ++ printInsn indent i) ""
end

/-- Render a function. -/
def printFunc (indent : Nat) (f : Func) : String :=
  let exportPart := match f.exportName with
    | some n => " (export \"" ++ escapeWatString n ++ "\")"
    | none => ""
  let header :=
    pad indent ++ "(func $" ++ f.name ++ exportPart
      ++ printParams f.params ++ printResults f.results ++ printLocals f.locals
  let body := printInsns (indent + 1) f.body.insns
  if body.isEmpty then
    header ++ ")\n"
  else
    header ++ "\n" ++ body ++ pad indent ++ ")\n"

/-- Render a module to WAT source text. -/
def render (m : Module) : String :=
  let imports := m.imports.foldl (fun acc i => acc ++ printImport 1 i) ""
  let globals := m.globals.foldl (fun acc g => acc ++ printGlobal 1 g) ""
  let funcs := m.funcs.foldl (fun acc f => acc ++ printFunc 1 f) ""
  let mem := match m.memory with
    | some mm => printMemory 1 mm
    | none => ""
  let datas := m.dataSegments.foldl (fun acc d => acc ++ printData 1 d) ""
  "(module\n" ++ imports ++ globals ++ funcs ++ mem ++ datas ++ ")\n"

end ProofForge.Compiler.Wasm.Printer
