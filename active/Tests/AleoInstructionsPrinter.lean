/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Z2.2: Aleo Instructions printer round-trip against Counter.golden.aleo.
-/

import ProofForge.Backend.Aleo.Instructions

open ProofForge.Backend.Aleo.Instructions
open ProofForge.Backend.Aleo.Instructions.Printer

def main (args : List String) : IO UInt32 := do
  let goldenPath :=
    match args with
    | p :: _ => System.FilePath.mk p
    | [] => System.FilePath.mk "Examples/Backend/Aleo/Counter.golden.aleo"
  let golden ← IO.FS.readFile goldenPath
  let rendered := renderProgram CounterGolden.program
  if rendered == golden then
    IO.println s!"aleo-instructions-printer: ok (Counter golden match, {rendered.length} bytes)"
    pure 0
  else
    try IO.FS.createDirAll (System.FilePath.mk "build/aleo/z2") catch _ => pure ()
    let out := System.FilePath.mk "build/aleo/z2/Counter.lean-printed.aleo"
    IO.FS.writeFile out rendered
    IO.eprintln "aleo-instructions-printer: FAIL golden mismatch"
    IO.eprintln s!"wrote {out}"
    let gLines := golden.splitOn "\n"
    let rLines := rendered.splitOn "\n"
    let mut shown := 0
    for i in [:min gLines.length rLines.length] do
      if gLines[i]! != rLines[i]! && shown < 15 then
        IO.eprintln s!"line {i+1}:"
        IO.eprintln s!"  golden: {gLines[i]!}"
        IO.eprintln s!"  print:  {rLines[i]!}"
        shown := shown + 1
    if gLines.length != rLines.length then
      IO.eprintln s!"line count golden={gLines.length} printed={rLines.length}"
    pure 1
