import ProofForge.Compiler.Wasm.AST
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Compiler.Wasm Printer

/-! Unit tests for the Wasm AST → WAT printer: string escaping, edge cases,
    and structural correctness. Run with `lake env lean --run`. -/

/-- Assert `actual` contains `expected`, printing a diagnostic otherwise. -/
def check (name : String) (actual : String) (expectedSubstr : String)
    (failures : IO.Ref Nat) : IO Unit := do
  if actual.contains expectedSubstr then
    IO.println s!"wasm-printer: ok: {name}"
  else
    IO.eprintln s!"wasm-printer: FAILED: {name}"
    IO.eprintln s!"  expected substring: {expectedSubstr}"
    IO.eprintln s!"  actual:\n{actual}"
    failures.modify (· + 1)

/-- Assert `actual` does NOT contain `bad`. -/
def checkAbsent (name : String) (actual : String) (bad : String)
    (failures : IO.Ref Nat) : IO Unit := do
  if actual.contains bad then
    IO.eprintln s!"wasm-printer: FAILED: {name} (found forbidden `{bad}`)"
    IO.eprintln s!"  actual:\n{actual}"
    failures.modify (· + 1)
  else
    IO.println s!"wasm-printer: ok: {name}"

def main : IO UInt32 := do
  let failures ← IO.mkRef 0

  -- 1. String escaping: a data segment with a quote, backslash, and newline.
  let m1 : Module := { dataSegments := #[{ offset := 0, bytes := "a\"b\\c\nd" }] }
  let w1 := render m1
  check "quote escaped" w1 "a\\\"b" failures
  check "backslash escaped" w1 "b\\\\c" failures
  check "newline hex-escaped" w1 "\\0a" failures
  checkAbsent "raw newline absent" w1 "\n\"" failures

  -- 2. Import field names are escaped.
  let m2 : Module := { imports := #[
    { module_ := "env", name := "sto\"rage", funcName := "f",
      type := { params := #[.i64], results := #[.i64] } } ] }
  let w2 := render m2
  check "import name escaped" w2 "sto\\\"rage" failures

  -- 3. Func with empty body renders on one line, no dangling indent.
  let m3 : Module := { funcs := #[{ name := "noop", body := { insns := #[] } }] }
  let w3 := render m3
  check "empty-body func one-line" w3 "(func $noop)" failures

  -- 4. Nested if emits matching if/else/end.
  let m4 : Module := { funcs := #[{ name := "f", body :=
    { insns := #[ .plain "i64.eqz",
                  .if_ { insns := #[.drop] } { insns := #[.unreachable] } ] } }] }
  let w4 := render m4
  check "if keyword" w4 "    if" failures
  check "else keyword" w4 "    else" failures
  check "end closes if" w4 "    end" failures

  -- 5. load/store offset immediate.
  let m5 : Module := { funcs := #[{ name := "f", body :=
    { insns := #[ .i32Const 0, .load "i64.load" 32 ] } }] }
  let w5 := render m5
  check "load offset immediate" w5 "i64.load offset=32" failures

  -- 6. memory export.
  let w6 := render ({ } : Module)
  check "default memory export" w6 "(memory (export \"memory\") 1)" failures

  let n ← failures.get
  if n == 0 then
    IO.println "wasm-printer: all cases passed"
    pure 0
  else
    IO.eprintln s!"wasm-printer: {n} case(s) failed"
    pure 1
