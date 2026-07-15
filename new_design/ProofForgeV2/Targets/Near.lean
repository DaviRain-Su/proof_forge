import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Near

open ProofForgeV2 Source

def descriptor : TargetDescriptor := {
  targetId := .near
  artifactEncoding := .wasmText
  executionHost := .nearRuntime
  commitModel := .receiptLocal
  stateBinding := .hostKeyValue
  callModel := .asynchronousReceipt
  proofModel := .none
  settlementModel := .near
  codegenProfile := "near-wasm-raw-u64-v1"
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback
  ]
}

structure Plan where
  source : SemanticProgram
  storageKey : String
  inputAbi : String
  deriving Inhabited, Repr

structure IR where
  name : String
  wat : String
  abi : String
  deriving Inhabited, Repr

def makePlan (resolved : ResolvedProgram .near) : CompileResult Plan := do
  unless Targets.isExactCounter resolved.source do
    throw <| .planInvariant .near "v2alpha1 only lowers the exact checked Counter semantics"
  return { source := resolved.source, storageKey := "count", inputAbi := "raw-little-endian-u64" }

private def renderWat (plan : Plan) : String :=
  "(module\n" ++
  "  (import \"env\" \"input\" (func $input (param i64)))\n" ++
  "  (import \"env\" \"register_len\" (func $register_len (param i64) (result i64)))\n" ++
  "  (import \"env\" \"read_register\" (func $read_register (param i64 i64)))\n" ++
  "  (import \"env\" \"storage_read\" (func $storage_read (param i64 i64 i64) (result i64)))\n" ++
  "  (import \"env\" \"storage_write\" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))\n" ++
  "  (import \"env\" \"value_return\" (func $value_return (param i64 i64)))\n" ++
  "  (memory (export \"memory\") 1)\n" ++
  s!"  (data (i32.const 0) \"{plan.storageKey}\")\n" ++
  "  (func (export \"init\")\n" ++
  "    (call $input (i64.const 0))\n" ++
  "    (if (i64.ne (call $register_len (i64.const 0)) (i64.const 8)) (then unreachable))\n" ++
  "    (call $read_register (i64.const 0) (i64.const 32))\n" ++
  "    (if (i64.ne (call $storage_write (i64.const 5) (i64.const 0) (i64.const 8) (i64.const 32) (i64.const 1)) (i64.const 0)) (then unreachable)))\n" ++
  "  (func (export \"increment\") (local $old i64) (local $delta i64) (local $next i64)\n" ++
  "    (call $input (i64.const 0))\n" ++
  "    (if (i64.ne (call $register_len (i64.const 0)) (i64.const 8)) (then unreachable))\n" ++
  "    (call $read_register (i64.const 0) (i64.const 32))\n" ++
  "    (local.set $delta (i64.load (i32.const 32)))\n" ++
  "    (if (i64.eqz (call $storage_read (i64.const 5) (i64.const 0) (i64.const 1))) (then unreachable))\n" ++
  "    (call $read_register (i64.const 1) (i64.const 40))\n" ++
  "    (local.set $old (i64.load (i32.const 40)))\n" ++
  "    (local.set $next (i64.add (local.get $old) (local.get $delta)))\n" ++
  "    (if (i64.lt_u (local.get $next) (local.get $old)) (then unreachable))\n" ++
  "    (i64.store (i32.const 40) (local.get $next))\n" ++
  "    (drop (call $storage_write (i64.const 5) (i64.const 0) (i64.const 8) (i64.const 40) (i64.const 2)))\n" ++
  "    (call $value_return (i64.const 8) (i64.const 40)))\n" ++
  "  (func (export \"get\")\n" ++
  "    (if (i64.eqz (call $storage_read (i64.const 5) (i64.const 0) (i64.const 1))) (then unreachable))\n" ++
  "    (call $read_register (i64.const 1) (i64.const 40))\n" ++
  "    (call $value_return (i64.const 8) (i64.const 40)))\n" ++
  ")\n"

def lower (plan : Plan) : CompileResult IR :=
  let abi := "{\"schema\":\"proof-forge-near-abi/v1alpha1\",\"program\":\"" ++
    plan.source.name ++ "\",\"encoding\":\"" ++ plan.inputAbi ++
    "\",\"exports\":[\"init\",\"increment\",\"get\"]}\n"
  .ok { name := plan.source.name, wat := renderWat plan, abi }

def emit (ir : IR) : CompileResult (Array OutputFile) := .ok #[
  { path := s!"{ir.name}.wat", mediaType := "application/wasm-text", contents := ir.wat },
  { path := s!"{ir.name}.near-abi.json", mediaType := "application/json", contents := ir.abi }
]

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR
  makePlan := makePlan
  lower := lower
  emit := emit

def materialize (program : SemanticProgram) : CompileResult OutputSet := do
  let resolved ← Targets.resolve descriptor program
  let plan ← makePlan resolved
  let ir ← lower plan
  let files ← emit ir
  return Targets.makeOutput descriptor program false files

end ProofForgeV2.Targets.Near
