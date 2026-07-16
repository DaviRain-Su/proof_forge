/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Pretty printer for Counter-subset Aleo Instructions (golden-compatible).
-/

import ProofForge.Backend.Aleo.Instructions.Ast

namespace ProofForge.Backend.Aleo.Instructions.Printer

open ProofForge.Backend.Aleo.Instructions

private def renderLit : Lit → String
  | .u64 n => s!"{n}u64"
  | .u16 n => s!"{n}u16"

private def renderOperand : Operand → String
  | .reg n => s!"r{n}"
  | .lit l => renderLit l

private def renderFinalInst : FinalInst → String
  | .set value mapping key =>
      s!"    set {renderOperand value} into {mapping}[{renderOperand key}];"
  | .getOrUse mapping key default_ dest =>
      s!"    get.or_use {mapping}[{renderOperand key}] {renderOperand default_} into r{dest};"
  | .add a b dest =>
      s!"    add {renderOperand a} {renderOperand b} into r{dest};"

private def renderMapping (m : MappingDecl) : String :=
  s!"mapping {m.name}:\n    key as {m.keyType};\n    value as {m.valueType};"

private def renderFunction (progName : String) (f : AsyncFunction) : String :=
  s!"function {f.name}:\n    async {f.name} into r{f.futureReg};\n    output r{f.futureReg} as {progName}/{f.name}.future;"

private def renderFinalize (b : FinalizeBlock) : String :=
  let body := "\n".intercalate (b.body.toList.map renderFinalInst)
  s!"finalize {b.name}:\n{body}"

def renderProgram (p : Program) : String :=
  let maps := "\n\n".intercalate (p.mappings.toList.map renderMapping)
  let pairs := p.functions.toList.zip p.finalizes.toList
  let fnBlocks := pairs.map (fun (f, fin) =>
    renderFunction p.name f ++ "\n\n" ++ renderFinalize fin)
  let body := "\n\n".intercalate (maps :: fnBlocks)
  s!"program {p.name};\n\n{body}\n\nconstructor:\n    assert.eq edition {p.constructorEdition}u16;\n"

end ProofForge.Backend.Aleo.Instructions.Printer
