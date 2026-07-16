/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

WebAssembly / WAT Abstract Syntax Tree.

The Wasm-family counterpart of `ProofForge.Compiler.Yul.AST`: a small AST that
a lowering backend (e.g. `Backend.WasmHost.EmitWat`) builds, and
`ProofForge.Compiler.Wasm.Printer` renders to WAT text. The emitted WAT is
valid input for `wat2wasm` (wabt) and targets the NEAR VM host ABI.

Design: flat-form instructions (stack machine). Structured control flow
(`block`/`loop`/`if`) is nested in the AST so the printer can emit matching
`end` delimiters. Locals are referenced by name (`local.get $name`).
-/
module

prelude
public import Init.Prelude
public import Init.Data.Repr
import Init.Data.Array.Basic
import Init.Data.String.Basic

public section

namespace ProofForge.Compiler.Wasm

/-- A Wasm value type. NEAR MVP contracts use `i32`/`i64` only. -/
inductive ValType where
  | i32 | i64 | f32 | f64
  deriving BEq, DecidableEq, Repr

/-- Textual form used in WAT (`i32`, `i64`, …). -/
def ValType.wat : ValType → String
  | .i32 => "i32"
  | .i64 => "i64"
  | .f32 => "f32"
  | .f64 => "f64"

/-- A function signature: parameter types and result types. -/
structure FuncType where
  params  : Array ValType := #[]
  results : Array ValType := #[]

/-- A named local or parameter: `$name : type`. -/
structure Local where
  name : String
  type : ValType

/-- An imported host function: `(import "env" "storage_read" (func $storage_read (param …) (result …)))`. -/
structure Import where
  module_  : String     -- import module name, e.g. "env"
  name     : String     -- imported field name, e.g. "storage_read"
  funcName : String     -- wasm `$name` to bind, e.g. "storage_read"
  type     : FuncType

/-- Linear memory declaration. -/
structure Memory where
  min        : Nat
  max        : Option Nat := none
  exportName : Option String := some "memory"

/-- A `(data (i32.const offset) "bytes")` segment. `bytes` is rendered verbatim
    inside quotes; the caller is responsible for escaping. -/
structure DataSegment where
  offset : Nat
  bytes  : String

/-- A global variable: `(global $name (mut i32) (i32.const init))`. -/
structure Global where
  name      : String
  type      : ValType
  init      : String
  isMutable : Bool := true

/-! A Wasm instruction. Stack inputs/outputs are implicit (stack machine);
    only immediate operands are stored. -/
mutual
  inductive Insn where
    | nop
    | unreachable
    | drop
    | select
    | return_
    | br (label : Nat)
    | brIf (label : Nat)
    | const (t : ValType) (value : String)
    | localGet (name : String)
    | localSet (name : String)
    | localTee (name : String)
    | globalGet (name : String)
    | globalSet (name : String)
    | plain (name : String)                 -- e.g. "i32.add", "i64.eqz", "i64.lt_u"
    | load (name : String) (offset : Nat)   -- e.g. "i32.load8_u", "i64.load"
    | store (name : String) (offset : Nat)  -- e.g. "i32.store8", "i64.store"
    | call (name : String)
    | block_ (body : Block)
    | loop_ (body : Block)
    | if_ (thenBody : Block) (elseBody : Block)

  /-- A sequence of instructions. -/
  structure Block where
    insns : Array Insn
end

instance : Inhabited Block := ⟨{ insns := #[] }⟩

/-- A function: optional export name, named params/results/locals, and a body. -/
structure Func where
  name       : String
  params     : Array Local := #[]
  results    : Array ValType := #[]
  locals     : Array Local := #[]
  body       : Block
  exportName : Option String := none

/-- A Wasm module. -/
structure Module where
  imports      : Array Import := #[]
  globals      : Array Global := #[]
  funcs        : Array Func := #[]
  memory       : Option Memory := some { min := 1 }
  dataSegments : Array DataSegment := #[]

-- Convenience constructors -------------------------------------------------

/-- `i32.const <n>`. -/
def Insn.i32Const (n : Nat) : Insn := .const .i32 (toString n)
/-- `i64.const <n>`. -/
def Insn.i64Const (n : Nat) : Insn := .const .i64 (toString n)

/-- Empty block. -/
def Block.empty : Block := { insns := #[] }

/-- Build a block from an instruction array (convenience). -/
def block (insns : Array Insn) : Block := { insns := insns }

end ProofForge.Compiler.Wasm
