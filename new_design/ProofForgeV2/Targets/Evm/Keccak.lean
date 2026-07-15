import Std

namespace ProofForgeV2.Targets.Evm.Keccak

private def rateBytes : Nat := 136

private def rateLanes : Nat := rateBytes / 8

private def roundConstants : Array UInt64 := #[
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
  0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
  0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
  0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
  0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
  0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
  0x8000000000008080, 0x0000000080000001, 0x8000000080008008
]

/-- Keccak-f[1600] rotation offsets, indexed as `x + 5 * y`. -/
private def rotationOffsets : Array Nat := #[
   0,  1, 62, 28, 27,
  36, 44,  6, 55, 20,
   3, 10, 43, 25, 39,
  41, 45, 15, 21,  8,
  18,  2, 61, 56, 14
]

private def rotateLeft (value : UInt64) (amount : Nat) : UInt64 :=
  if amount == 0 then
    value
  else
    UInt64.shiftLeft value (UInt64.ofNat amount) |||
      UInt64.shiftRight value (UInt64.ofNat (64 - amount))

private def keccakF1600 (input : Array UInt64) : Array UInt64 := Id.run do
  let mut state := input
  for round in [0:24] do
    -- Theta
    let mut columns : Array UInt64 := Array.replicate 5 0
    for x in [0:5] do
      let mut parity : UInt64 := 0
      for y in [0:5] do
        parity := parity ^^^ state[x + 5 * y]!
      columns := columns.set! x parity
    for x in [0:5] do
      let delta := columns[(x + 4) % 5]! ^^^ rotateLeft columns[(x + 1) % 5]! 1
      for y in [0:5] do
        let index := x + 5 * y
        state := state.set! index (state[index]! ^^^ delta)

    -- Rho and Pi. The destination is B[y, (2*x + 3*y) mod 5].
    let mut mixed : Array UInt64 := Array.replicate 25 0
    for y in [0:5] do
      for x in [0:5] do
        let sourceIndex := x + 5 * y
        let targetX := y
        let targetY := (2 * x + 3 * y) % 5
        let targetIndex := targetX + 5 * targetY
        mixed := mixed.set! targetIndex
          (rotateLeft state[sourceIndex]! rotationOffsets[sourceIndex]!)

    -- Chi
    for y in [0:5] do
      for x in [0:5] do
        let index := x + 5 * y
        let next := mixed[(x + 1) % 5 + 5 * y]!
        let following := mixed[(x + 2) % 5 + 5 * y]!
        state := state.set! index (mixed[index]! ^^^ ((~~~next) &&& following))

    -- Iota
    state := state.set! 0 (state[0]! ^^^ roundConstants[round]!)
  return state

private def padEthereumKeccak (input : ByteArray) : ByteArray := Id.run do
  let mut padded := input.push 0x01
  while padded.size % rateBytes != 0 do
    padded := padded.push 0
  let last := padded.size - 1
  padded := padded.set! last (padded[last]! ||| 0x80)
  return padded

private def readLaneLE (bytes : ByteArray) (offset : Nat) : UInt64 := Id.run do
  let mut lane : UInt64 := 0
  for index in [0:8] do
    lane := lane ||| UInt64.shiftLeft bytes[offset + index]!.toUInt64
      (UInt64.ofNat (8 * index))
  return lane

private def absorbBlock (input : Array UInt64) (block : ByteArray)
    (offset : Nat) : Array UInt64 := Id.run do
  let mut state := input
  for laneIndex in [0:rateLanes] do
    let lane := readLaneLE block (offset + 8 * laneIndex)
    state := state.set! laneIndex (state[laneIndex]! ^^^ lane)
  return keccakF1600 state

private def appendLaneLE (output : ByteArray) (lane : UInt64) : ByteArray := Id.run do
  let mut bytes := output
  for index in [0:8] do
    bytes := bytes.push <| UInt64.shiftRight lane (UInt64.ofNat (8 * index)) |>.toUInt8
  return bytes

/-- Ethereum-compatible Keccak-256. This uses the legacy Keccak domain suffix
`0x01` (with the terminal `0x80` bit), not the SHA3-256 suffix `0x06`. -/
def keccak256 (input : ByteArray) : ByteArray := Id.run do
  let padded := padEthereumKeccak input
  let mut state : Array UInt64 := Array.replicate 25 0
  for blockIndex in [0:padded.size / rateBytes] do
    state := absorbBlock state padded (blockIndex * rateBytes)
  let mut output := ByteArray.empty
  for laneIndex in [0:4] do
    output := appendLaneLE output state[laneIndex]!
  return output

private def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat (48 + value) else Char.ofNat (87 + value)

private def toHex (bytes : ByteArray) : String :=
  bytes.foldl (fun output byte =>
    output.push (hexDigit (byte.toNat / 16)) |>.push (hexDigit (byte.toNat % 16))) ""

/-- Lower-case hexadecimal Ethereum Keccak-256 digest. -/
def keccak256Hex (input : ByteArray) : String :=
  toHex (keccak256 input)

/-- Canonical Solidity ABI function signature. -/
def signature (name : String) (paramTypes : Array String) : String :=
  s!"{name}({String.intercalate "," paramTypes.toList})"

/-- The lower-case, eight-hex-character Solidity ABI function selector. -/
def selector (name : String) (paramTypes : Array String) : String :=
  toHex ((keccak256 (signature name paramTypes).toUTF8).extract 0 4)

end ProofForgeV2.Targets.Evm.Keccak
