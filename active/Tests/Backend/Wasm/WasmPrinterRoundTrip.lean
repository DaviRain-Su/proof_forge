import ProofForge.Compiler.Wasm.AST
import ProofForge.Compiler.Wasm.Printer
open ProofForge.Compiler.Wasm

/-! Round-trip proof: rebuild the hand-written NEAR counter purely via the
Wasm AST + Printer, then render to WAT. The emitted WAT is fed to `wat2wasm`
and deployed to `near-sandbox` to confirm the AST/Printer produce deployable
wasm equivalent to `examples/near/spike/handwritten-counter.wat`. -/

def envImport (name : String) (type : FuncType) : Import :=
  { module_ := "env", name := name, funcName := name, type := type }

def imports : Array Import :=
  #[ envImport "storage_read"  { params := #[.i64, .i64, .i64], results := #[.i64] },
     envImport "storage_write" { params := #[.i64, .i64, .i64, .i64, .i64], results := #[.i64] },
     envImport "read_register" { params := #[.i64, .i64], results := #[] },
     envImport "value_return"  { params := #[.i64, .i64], results := #[] },
     envImport "log_utf8"      { params := #[.i64, .i64], results := #[] } ]

/-- Read the value byte at mem[32], defaulting to '0' (48) if absent. -/
def loadDigitBody : Block :=
  block #[
    .i64Const 5, .i64Const 0, .i64Const 0, .call "storage_read", .localSet "found",
    .localGet "found", .plain "i64.eqz",
    .if_ (block #[ .i32Const 32, .i32Const 48, .store "i32.store8" 0 ])
         (block #[ .i64Const 0, .i64Const 32, .call "read_register" ]),
    .i32Const 32, .load "i32.load8_u" 0 ]

def loadDigit : Func :=
  { name := "load_digit", results := #[.i32], locals := #[{ name := "found", type := .i64 }],
    body := loadDigitBody }

def initFunc : Func :=
  { name := "init", exportName := "init", body := block #[
      .i32Const 32, .i32Const 48, .store "i32.store8" 0,
      .i64Const 5, .i64Const 0, .i64Const 1, .i64Const 32, .i64Const 0,
      .call "storage_write", .drop ] }

def getFunc : Func :=
  { name := "get", exportName := "get", locals := #[{ name := "found", type := .i64 }],
    body := block #[
      .i64Const 5, .i64Const 0, .i64Const 0, .call "storage_read", .localSet "found",
      .localGet "found", .plain "i64.eqz",
      .if_ (block #[ .i32Const 32, .i32Const 48, .store "i32.store8" 0 ])
           (block #[ .i64Const 0, .i64Const 32, .call "read_register" ]),
      .i64Const 1, .i64Const 32, .call "value_return" ] }

def incrementFunc : Func :=
  { name := "increment", exportName := "increment", body := block #[
      .i32Const 32,
      .call "load_digit", .i32Const 1, .plain "i32.add",
      .store "i32.store8" 0,
      .i64Const 5, .i64Const 0, .i64Const 1, .i64Const 32, .i64Const 0,
      .call "storage_write", .drop ] }

def counterModule : Module :=
  { imports := imports,
    funcs := #[loadDigit, initFunc, getFunc, incrementFunc],
    memory := some { min := 1 },
    dataSegments := #[{ offset := 0, bytes := "count" }] }

def main : IO UInt32 := do
  let wat := Printer.render counterModule
  let outPath := "build/wasm-near/ast-counter.wat"
  IO.FS.writeFile outPath wat
  IO.println s!"wrote {outPath} ({wat.length} bytes)"
  pure 0
