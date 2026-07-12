import ProofForge.Backend.Stylus.DirectWasm.Memory

namespace ProofForge.Backend.Stylus.DirectWasm

abbrev Bytes := Array UInt8

def zeroWord : Bytes := Array.replicate 32 0

def normalizeWord (bytes : Bytes) : Except DirectError Bytes :=
  if bytes.size == 32 then .ok bytes else .error { message := "Stylus storage word must be 32 bytes" }

def natToWord (value : Nat) : Bytes :=
  (List.range 32).toArray.map fun index => UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

def wordToNat (word : Bytes) : Nat :=
  word.foldl (fun value byte => value * 256 + byte.toNat) 0

def maskedUpdate (word : Bytes) (byteOffset byteWidth : Nat) (field : Bytes) :
    Except DirectError Bytes := do
  let word <- normalizeWord word
  if byteWidth == 0 || byteOffset + byteWidth > 32 then
    throw { message := "Stylus packed storage field exceeds its 32-byte word" }
  if field.size != byteWidth then
    throw { message := "Stylus packed storage field width does not match its value" }
  pure <| word.mapIdx fun index byte =>
    if byteOffset <= index && index < byteOffset + byteWidth then field[index - byteOffset]! else byte

def mappingPreimage (paddedKey baseSlot : Bytes) : Except DirectError Bytes := do
  let key <- normalizeWord paddedKey
  let slot <- normalizeWord baseSlot
  pure (key ++ slot)

def mappingSlotWith (keccak : Bytes -> Bytes) (paddedKey baseSlot : Bytes) :
    Except DirectError Bytes := do
  let digest := keccak (← mappingPreimage paddedKey baseSlot)
  normalizeWord digest

def storageHelperModule (imports : Array ProofForge.Compiler.Wasm.Import) (pages : Nat) :
    Except DirectError ProofForge.Compiler.Wasm.Module := do
  pure { imports, memory := some (← scratchMemory pages) }

end ProofForge.Backend.Stylus.DirectWasm
