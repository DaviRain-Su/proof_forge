import ProofForge.Backend.Stylus.AbiLayout
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.RustSdk.Render
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def word (value : Nat) : Array UInt8 :=
  (List.range 32).toArray.map fun index => UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

def main : IO Unit := do
  let empty := word 32 ++ word 0
  let emptySlice <- match decodeDynamicArgument empty 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (emptySlice.dataOffset == 64 && emptySlice.length == 0 && emptySlice.paddedEnd == 64)
    "empty dynamic ABI slice changed"

  let hello := word 32 ++ word 5 ++ "hello".toUTF8.data ++ Array.replicate 27 0
  let helloSlice <- match decodeDynamicArgument hello 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (helloSlice.dataOffset == 64 && helloSlice.length == 5 && helloSlice.paddedEnd == 96)
    "string tail layout changed"

  for (name, calldata, maximum) in #[
      ("unaligned", word 33 ++ word 0, 64),
      ("inside-head", word 0 ++ word 0, 64),
      ("missing-length", word 64, 64),
      ("truncated-tail", word 32 ++ word 33 ++ Array.replicate 32 0, 64),
      ("over-limit", word 32 ++ word 65 ++ Array.replicate 96 0, 64)] do
    match decodeDynamicArgument calldata 1 0 maximum with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"{name} dynamic ABI vector was accepted"

  let support : RendererSupportPlan := { rustSdk := .implemented, directWasm := .implemented }
  let bytesMethod : StylusAbiMethodPlan := {
    name := "echoBytes", canonicalSignature := "echoBytes(bytes)", selector := #[0xde, 0xad, 0xbe, 0x01]
    params := #[{ name := "value", type := .bytes }], returns := #[.bytes], mutability := .view
  }
  let stringMethod : StylusAbiMethodPlan := {
    name := "echoString", canonicalSignature := "echoString(string)", selector := #[0xde, 0xad, 0xbe, 0x02]
    params := #[{ name := "value", type := .string }], returns := #[.string], mutability := .view
  }
  let plan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "AggregateEcho"
    abi := { methods := #[bytesMethod, stringMethod], errors := #[] }, storage := { words := #[] }
    functions := #[
      { id := "echoBytes", abiMethod := "echoBytes", params := #[{
          valueId := 1, name := "value", type := .bytes, dynamicMaxLength? := some 64 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[1] }], support },
      { id := "echoString", abiMethod := "echoString", params := #[{
          valueId := 2, name := "value", type := .string, dynamicMaxLength? := some 64 }]
        entryBlock := 0, blocks := #[{ id := 0, operations := #[], terminator := .return #[2] }], support }
    ]
    events := #[], calls := #[]
    hostOps := #[
      { id := "bytes.value", functionId := "echoBytes", operation := .msgValue, support },
      { id := "bytes.result", functionId := "echoBytes", operation := .writeResult, support },
      { id := "string.value", functionId := "echoString", operation := .msgValue, support },
      { id := "string.result", functionId := "echoString", operation := .writeResult, support }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let direct <- match ProofForge.Backend.Stylus.DirectWasm.lowerFromPlan plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  let crate <- match ProofForge.Backend.Stylus.RustSdk.renderCrate plan with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  IO.FS.createDirAll "build/stylus/aggregate-differential"
  IO.FS.writeFile "build/stylus/aggregate-differential/echo.wat"
    (ProofForge.Compiler.Wasm.Printer.render direct)
  let cratePath := System.FilePath.mk "build/stylus/aggregate-differential/rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← ProofForge.Backend.Stylus.writeCrateAtomic crate cratePath with
  | .ok () => pure () | .error error => throw <| IO.userError error.message
  IO.println "stylus-aggregate-differential: ok"
