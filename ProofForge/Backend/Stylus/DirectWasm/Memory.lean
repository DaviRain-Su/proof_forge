import ProofForge.Backend.Stylus.DirectWasm.Imports

namespace ProofForge.Backend.Stylus.DirectWasm

structure ScratchLayout where
  keyPtr : Nat := 0
  valuePtr : Nat := 32
  wordBytes : Nat := 32
  deriving Repr, BEq

def ScratchLayout.endOffset (layout : ScratchLayout) : Nat :=
  layout.valuePtr + layout.wordBytes

def wasmPageBytes : Nat := 65536

def validateScratch (pages : Nat) (layout : ScratchLayout := {}) : Except DirectError Unit := do
  if pages == 0 then throw { message := "Stylus direct Wasm requires at least one memory page" }
  if layout.keyPtr + layout.wordBytes > layout.valuePtr then
    throw { message := "Stylus key and value scratch regions overlap" }
  if layout.endOffset > pages * wasmPageBytes then
    throw { message := "Stylus scratch region exceeds declared memory pages" }

def scratchMemory (pages : Nat) : Except DirectError ProofForge.Compiler.Wasm.Memory := do
  validateScratch pages
  pure { min := pages, max := some pages, exportName := some "memory" }

end ProofForge.Backend.Stylus.DirectWasm
