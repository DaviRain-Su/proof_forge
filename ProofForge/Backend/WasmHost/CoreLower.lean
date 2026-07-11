import ProofForge.Backend.WasmHost.CorePlan
import ProofForge.Compiler.Wasm.AST

namespace ProofForge.Backend.WasmHost.CoreLower

open ProofForge.Backend.WasmHost.CorePlan
open ProofForge.Compiler.Wasm

/-- Map the portable Core IR type vocabulary to a Wasm value type.
This is a Task-9 skeleton mapping: complex/unsupported types default to `i32`
so the module can still be assembled; future tasks will refine the mapping. -/
def coreTypeToWasmValType : ProofForge.IR.Core.CoreType → ValType
  | .unit => .i32
  | .bool => .i32
  | .u8 => .i32
  | .u32 => .i32
  | .u64 => .i64
  | .u128 => .i64
  | .address => .i64
  | .bytes => .i32
  | .string => .i32
  | .hash => .i32
  | .fixedArray _ _ => .i32
  | .array _ => .i32
  | .structType _ => .i32

/-- Lower a `WasmCorePlan` (Task 8) into a `Wasm.Module` that can be printed
by `ProofForge.Compiler.Wasm.Printer` or executed by the Wasm interpreter. -/
def lowerWasmCorePlan (p : WasmCorePlan) : Module :=
  { funcs := p.functions.toArray.map fun f =>
      { name := f.name
      , params := f.params.toArray.map fun p => { name := p.1, type := coreTypeToWasmValType p.2 }
      , results := if f.retTy == .unit then #[] else #[coreTypeToWasmValType f.retTy]
      , locals := #[]
      , body := { insns := f.body.toArray }
      , exportName := some f.name
      }
  , imports := p.imports.toArray
  , memory := some { min := 1 }
  }

end ProofForge.Backend.WasmHost.CoreLower
