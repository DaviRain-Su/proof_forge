/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Pretty JSON printer for DPN circuits (2-space indent, golden-compatible).
-/

import ProofForge.Backend.Psy.Dpn.Ast

namespace ProofForge.Backend.Psy.Dpn.Printer

open ProofForge.Backend.Psy.Dpn

private def indent (n : Nat) : String :=
  String.ofList (List.replicate n ' ')

private def quoteString (s : String) : String :=
  "\"" ++ (s.toList.map (fun c =>
    match c with
    | '\\' => "\\\\"
    | '"' => "\\\""
    | '\n' => "\\n"
    | c => c.toString)).foldl (· ++ ·) "" ++ "\""

private def renderNatArray (xs : Array Nat) (ind : Nat) : String :=
  if xs.isEmpty then "[]"
  else
    let body := xs.toList.map (fun n => s!"{indent (ind + 2)}{n}")
    "[\n" ++ ",\n".intercalate body ++ "\n" ++ indent ind ++ "]"

private def renderDef (d : IndexedVarDef) (ind : Nat) : String :=
  let i := indent ind
  let i2 := indent (ind + 2)
  let inputs :=
    if d.inputs.isEmpty then "[]"
    else
      let body := d.inputs.toList.map (fun n => s!"{indent (ind + 4)}{n}")
      "[\n" ++ ",\n".intercalate body ++ "\n" ++ i2 ++ "]"
  "{\n" ++
    i2 ++ "\"data_type\": " ++ toString d.dataType ++ ",\n" ++
    i2 ++ "\"index\": " ++ toString d.index ++ ",\n" ++
    i2 ++ "\"op_type\": " ++ toString d.opType ++ ",\n" ++
    i2 ++ "\"inputs\": " ++ inputs ++ "\n" ++
    i ++ "}"

private def renderStateCommand (c : StateCommand) (ind : Nat) : String :=
  let i := indent ind
  let i2 := indent (ind + 2)
  match c with
  | .getSelfUserCurrentContractStateSlotSingle sub =>
      "{\n" ++
        i2 ++ "\"type\": \"GetSelfUserCurrentContractStateSlotSingle\",\n" ++
        i2 ++ "\"sub_slot_index\": " ++ toString sub ++ "\n" ++
        i ++ "}"
  | .setContractStateSlotSingle cond sub val =>
      "{\n" ++
        i2 ++ "\"type\": \"SetContractStateSlotSingle\",\n" ++
        i2 ++ "\"condition\": " ++ toString cond ++ ",\n" ++
        i2 ++ "\"sub_slot_index\": " ++ toString sub ++ ",\n" ++
        i2 ++ "\"value\": " ++ toString val ++ "\n" ++
        i ++ "}"
  | .other typeName fields =>
      let fieldLines :=
        fields.toList.map (fun (k, v) => i2 ++ quoteString k ++ ": " ++ toString v)
      "{\n" ++
        i2 ++ "\"type\": " ++ quoteString typeName ++
        (if fields.isEmpty then "\n" else ",\n" ++ ",\n".intercalate fieldLines ++ "\n") ++
        i ++ "}"

private def renderObjectArray (items : Array String) (ind : Nat) : String :=
  if items.isEmpty then "[]"
  else
    let body := items.toList.map (fun s => indent (ind + 2) ++ s)
    "[\n" ++ ",\n".intercalate body ++ "\n" ++ indent ind ++ "]"

def renderMethod (m : FunctionCircuit) (ind : Nat := 2) : String :=
  let i := indent ind
  let i2 := indent (ind + 2)
  let stateCmds := renderObjectArray (m.stateCommands.map (renderStateCommand · (ind + 4))) (ind + 2)
  let defs := renderObjectArray (m.definitions.map (renderDef · (ind + 4))) (ind + 2)
  "{\n" ++
    i2 ++ "\"name\": " ++ quoteString m.name ++ ",\n" ++
    i2 ++ "\"method_id\": " ++ toString m.methodId ++ ",\n" ++
    i2 ++ "\"circuit_inputs\": " ++ renderNatArray m.circuitInputs (ind + 2) ++ ",\n" ++
    i2 ++ "\"circuit_outputs\": " ++ renderNatArray m.circuitOutputs (ind + 2) ++ ",\n" ++
    i2 ++ "\"state_commands\": " ++ stateCmds ++ ",\n" ++
    i2 ++ "\"state_command_resolution_indices\": " ++
      renderNatArray m.stateCommandResolutionIndices (ind + 2) ++ ",\n" ++
    i2 ++ "\"assertions\": " ++ renderObjectArray #[] (ind + 2) ++ ",\n" ++
    i2 ++ "\"definitions\": " ++ defs ++ ",\n" ++
    i2 ++ "\"events\": " ++ renderObjectArray #[] (ind + 2) ++ "\n" ++
    i ++ "}"

def renderDocument (doc : CircuitDocument) : String :=
  if doc.isEmpty then "[]\n"
  else
    let methods := doc.toList.map (fun m => "  " ++ renderMethod m 2)
    "[\n" ++ ",\n".intercalate methods ++ "\n]\n"

end ProofForge.Backend.Psy.Dpn.Printer
