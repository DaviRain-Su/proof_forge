/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# N1.2 EmitWat aggregate Borsh ABI smoke

Positive: flat struct param + struct/fixedArray return lower to WAT with
`value_return` and expected payload sizes. The shell gate validates the emitted
WAT and executes exact Borsh return bytes in the offline host.

Negative: dynamic `bytes` params still fail closed with a stable diagnostic.
-/
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR
open ProofForge.Backend.WasmHost.EmitWat

def pairStruct : StructDecl := {
  name := "Pair"
  fields := #[{ id := "a", type := .u64 }, { id := "b", type := .u64 }]
}

def structParamModule : Module := {
  name := "StructParamProbe"
  structs := #[pairStruct]
  state := #[{ id := "sum", kind := .scalar, type := .u64 }]
  entrypoints := #[{
    name := "setPair"
    params := #[("p", .structType "Pair")]
    returns := .unit
    body := #[
      .effect (.storageScalarWrite "sum"
        (.add (.field (.local "p") "a") (.field (.local "p") "b")))
    ]
  }]
}

def structReturnModule : Module := {
  name := "StructReturnProbe"
  structs := #[pairStruct]
  state := #[]
  entrypoints := #[{
    name := "make"
    params := #[("a", .u64), ("b", .u64)]
    returns := .structType "Pair"
    body := #[.return (.structLit "Pair" #[("a", .local "a"), ("b", .local "b")])]
  }]
}

def fixedArrayReturnModule : Module := {
  name := "ArrReturnProbe"
  state := #[]
  entrypoints := #[{
    name := "zeros"
    params := #[]
    returns := .fixedArray .u64 2
    body := #[.return (.arrayLit .u64 #[.literal (.u64 0), .literal (.u64 1)])]
  }]
}

def hashArrayReturnModule : Module := {
  name := "HashArrReturnProbe"
  state := #[]
  entrypoints := #[{
    name := "roots"
    params := #[]
    returns := .fixedArray .hash 2
    body := #[.return (.arrayLit .hash #[
      .literal (.hash4 1 2 3 4),
      .literal (.hash4 5 6 7 8)
    ])]
  }]
}

def bytesParamModule : Module := {
  name := "BytesParamProbe"
  state := #[]
  entrypoints := #[{
    name := "set"
    params := #[("data", .bytes)]
    returns := .unit
    body := #[]
  }]
}

def requireContains (wat needle label : String) : IO Unit := do
  if !wat.contains needle then
    throw <| IO.userError s!"{label}: missing `{needle}`"

def writeAggregateWat (name wat : String) : IO Unit := do
  IO.FS.createDirAll "build/emitwat-aggregate-abi"
  IO.FS.writeFile s!"build/emitwat-aggregate-abi/{name}.wat" wat

def main : IO UInt32 := do
  -- Positive: struct param
  match renderModule structParamModule with
  | .error e =>
    IO.eprintln s!"struct param failed: {e.message}"
    return 1
  | .ok wat =>
    requireContains wat "setPair" "struct param export"
    requireContains wat "read_register" "struct param Borsh input"
    IO.println s!"struct-param: ok ({wat.length} bytes)"

  -- Positive: struct return (16-byte Pair)
  match renderModule structReturnModule with
  | .error e =>
    IO.eprintln s!"struct return failed: {e.message}"
    return 1
  | .ok wat =>
    requireContains wat "value_return" "struct return host"
    requireContains wat "(import \"env\" \"value_return\"" "struct return import"
    requireContains wat "i64.const 16" "struct return size"
    writeAggregateWat "struct-return" wat
    IO.println s!"struct-return: ok ({wat.length} bytes)"

  -- Positive: fixedArray return (2 × u64 = 16)
  match renderModule fixedArrayReturnModule with
  | .error e =>
    IO.eprintln s!"fixedArray return failed: {e.message}"
    return 1
  | .ok wat =>
    requireContains wat "value_return" "array return host"
    requireContains wat "(import \"env\" \"value_return\"" "array return import"
    requireContains wat "i64.const 16" "array return size"
    writeAggregateWat "fixed-array-return" wat
    IO.println s!"fixedArray-return: ok ({wat.length} bytes)"

  -- Positive: fixedArray<Hash> copies each 32-byte value, never its i32 pointer.
  match renderModule hashArrayReturnModule with
  | .error e =>
    IO.eprintln s!"hash fixedArray return failed: {e.message}"
    return 1
  | .ok wat =>
    requireContains wat "(import \"env\" \"value_return\"" "hash array return import"
    requireContains wat "call $__pf_memcpy" "hash array element copy"
    requireContains wat "i64.const 64" "hash array return size"
    writeAggregateWat "hash-array-return" wat
    IO.println s!"hash-fixedArray-return: ok ({wat.length} bytes)"

  -- Negative: dynamic bytes param fail-closed
  match renderModule bytesParamModule with
  | .ok _ =>
    IO.eprintln "bytes param must fail closed"
    return 1
  | .error e =>
    if !(e.message.contains "dynamic_bytes" || e.message.contains "Bytes" ||
         e.message.contains "unsupported") then
      IO.eprintln s!"unexpected bytes diagnostic: {e.message}"
      return 1
    IO.println s!"bytes-param: fail-closed ok ({e.message})"

  IO.println "emitwat-aggregate-abi: ok"
  pure 0
