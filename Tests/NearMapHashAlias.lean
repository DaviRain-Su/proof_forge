import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.WasmInterpreter

namespace ProofForge.Tests.NearMapHashAlias

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.WasmHost.WasmInterpreter

def aliasProbe : Entrypoint := {
  name := "alias_probe"
  mutability := .view
  params := #[("first_value", .hash), ("second_value", .hash)]
  returns := .bool
  body := #[
    .effect (.storageMapSet "roots" (.literal (.u64 1)) (.local "first_value")),
    .effect (.storageMapSet "roots" (.literal (.u64 2)) (.local "second_value")),
    .letBind "first" .hash (.effect (.storageMapGet "roots" (.literal (.u64 1)))),
    .letBind "second" .hash (.effect (.storageMapGet "roots" (.literal (.u64 2)))),
    .letBind "noise" .u64 (.effect (.storageMapGet "noise" (.literal (.u64 9)))),
    .return (.boolAnd
      (.eq (.local "first") (.local "first_value"))
      (.eq (.local "second") (.local "second_value")))
  ]
}

def aliasModule : Module := {
  name := "NearMapHashAlias"
  state := #[
    { id := "roots", kind := .map .u64 8, type := .hash },
    { id := "noise", kind := .map .u64 8, type := .u64 }
  ]
  entrypoints := #[aliasProbe]
}

def main (args : List String) : IO Unit := do
  let wasm <- match ProofForge.Backend.WasmHost.EmitWat.lowerModule aliasModule with
    | .ok wasm => pure wasm
    | .error error => throw <| IO.userError error.message
  let first := ProofForge.IR.Semantics.Value.hash 1 2 3 4
  let second := ProofForge.IR.Semantics.Value.hash 5 6 7 8
  let input <- match borshArgsBytes #[first, second] with
    | .ok input => pure input
    | .error message => throw <| IO.userError message
  let some func := findExportedFunc? wasm "alias_probe"
    | throw <| IO.userError "missing alias_probe export"
  if !func.body.insns.any (fun insn => match insn with
      | .globalSet "hash_ptr" => true
      | _ => false) then
    throw <| IO.userError "hash-valued map entrypoint does not reset the hash allocator"
  let initial := initialState wasm
  let initial := { initial with host := initial.host.beginCall input }
  let (_, finalState) <- match evalFunc wasm func #[] 1000000 initial with
    | .ok result => pure result
    | .error message => throw <| IO.userError message
  if leBytesToNat finalState.host.returnValue != 1 then
    throw <| IO.userError "Map<U64, Hash> retained reads aliased scratch memory"
  if let some path := args[0]? then
    let wat <- match ProofForge.Backend.WasmHost.EmitWat.renderModule aliasModule with
      | .ok wat => pure wat
      | .error error => throw <| IO.userError error.message
    IO.FS.writeFile path (wat ++ "\n")
  IO.println "near-map-hash-alias: ok"

end ProofForge.Tests.NearMapHashAlias

def main (args : List String) : IO Unit := ProofForge.Tests.NearMapHashAlias.main args
