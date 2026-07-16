/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Z1.3: round-trip Counter DPN AST printer against checked-in golden JSON.
-/

import ProofForge.Backend.Psy.Dpn

open ProofForge.Backend.Psy.Dpn
open ProofForge.Backend.Psy.Dpn.Printer

def main (args : List String) : IO UInt32 := do
  let goldenPath :=
    match args with
    | p :: _ => System.FilePath.mk p
    | [] => System.FilePath.mk "Examples/Backend/Psy/dpn/Counter.golden.dpn.json"
  let golden ← IO.FS.readFile goldenPath
  let rendered := renderDocument CounterGolden.document
  if rendered == golden then
    IO.println s!"psy-dpn-printer: ok (Counter golden match, {rendered.length} bytes)"
    pure 0
  else
    -- Write rendered for debugging
    let out := System.FilePath.mk "build/psy/dpn-goldens/Counter.lean-printed.json"
    try
      IO.FS.createDirAll (System.FilePath.mk "build/psy/dpn-goldens")
    catch _ => pure ()
    IO.FS.writeFile out rendered
    IO.eprintln "psy-dpn-printer: FAIL Counter golden mismatch"
    IO.eprintln s!"wrote rendered copy to {out}"
    -- Show a short prefix diff hint
    let gLines := golden.splitOn "\n"
    let rLines := rendered.splitOn "\n"
    let mut shown := 0
    for i in [:min gLines.length rLines.length] do
      if gLines[i]! != rLines[i]! && shown < 12 then
        IO.eprintln s!"line {i+1}:"
        IO.eprintln s!"  golden: {gLines[i]!}"
        IO.eprintln s!"  print:  {rLines[i]!}"
        shown := shown + 1
    if gLines.length != rLines.length then
      IO.eprintln s!"line count golden={gLines.length} printed={rLines.length}"
    pure 1
