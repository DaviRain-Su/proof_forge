/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Pure Lean Keccak-256 (Ethereum / original Keccak padding)

Mathlib-free implementation for CLI/product paths (D-058 / LR-S3): ABI selectors
and similar digests without Foundry `cast`. Algorithm mirrors the well-known
Keccak-f[1600] sponge used by Ethereum (padding delimiter `0x01`, not SHA-3
`0x06`).

Not a formal model; validated against standard Ethereum test vectors in
`Tests/Util/Keccak256.lean`.
-/

namespace ProofForge.Util.Keccak256

/-- Keccak-f[1600] round constants (24 values). -/
def RC : Array UInt64 := #[
  0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
  0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
  0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
  0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
  0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
  0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

/-- ρ rotation offsets (bits), lane index `x + 5·y`. -/
def rotOff : Array Nat := #[
   0,  1, 62, 28, 27,
  36, 44,  6, 55, 20,
   3, 10, 43, 25, 39,
  41, 45, 15, 21,  8,
  18,  2, 61, 56, 14]

def rotl64 (x : UInt64) (n : Nat) : UInt64 :=
  if n = 0 then x
  else (x <<< UInt64.ofNat n) ||| (x >>> UInt64.ofNat (64 - n))

def round (A : Array UInt64) (rc : UInt64) : Array UInt64 := Id.run do
  let mut C : Array UInt64 := Array.replicate 5 0
  for x in [0:5] do
    C := C.set! x (A[x]! ^^^ A[x+5]! ^^^ A[x+10]! ^^^ A[x+15]! ^^^ A[x+20]!)
  let mut D : Array UInt64 := Array.replicate 5 0
  for x in [0:5] do
    D := D.set! x (C[(x + 4) % 5]! ^^^ rotl64 C[(x + 1) % 5]! 1)
  let mut B : Array UInt64 := A
  for x in [0:5] do
    for y in [0:5] do
      B := B.set! (x + 5*y) (B[x + 5*y]! ^^^ D[x]!)
  let mut B' : Array UInt64 := Array.replicate 25 0
  for x in [0:5] do
    for y in [0:5] do
      let src := x + 5*y
      let dst := y + 5 * ((2 * x + 3 * y) % 5)
      B' := B'.set! dst (rotl64 B[src]! rotOff[src]!)
  let mut A' : Array UInt64 := Array.replicate 25 0
  for y in [0:5] do
    for x in [0:5] do
      A' := A'.set! (x + 5*y)
              (B'[x + 5*y]! ^^^
                ((B'[((x + 1) % 5) + 5*y]! ^^^ 0xffffffffffffffff) &&&
                 B'[((x + 2) % 5) + 5*y]!))
  return A'.set! 0 (A'[0]! ^^^ rc)

def permute (A : Array UInt64) : Array UInt64 := Id.run do
  let mut A := A
  for i in [0:24] do
    A := round A RC[i]!
  return A

def readLE64 (bs : ByteArray) (off : Nat) : UInt64 := Id.run do
  let mut w : UInt64 := 0
  for i in [0:8] do
    let b : UInt64 := if h : off + i < bs.size then bs[off + i].toUInt64 else 0
    w := w ||| (b <<< UInt64.ofNat (8 * i))
  return w

def writeLE64 (acc : ByteArray) (w : UInt64) : ByteArray := Id.run do
  let mut acc := acc
  for i in [0:8] do
    acc := acc.push (((w >>> UInt64.ofNat (8 * i)) &&& 0xff).toUInt8)
  return acc

/-- Ethereum Keccak-256 digest (32 bytes). -/
def hash (bs : ByteArray) : ByteArray := Id.run do
  let rate := 136
  let mut state : Array UInt64 := Array.replicate 25 0
  let nFull := bs.size / rate
  for blk in [0:nFull] do
    let base := blk * rate
    for j in [0:rate / 8] do
      let lane := readLE64 bs (base + j * 8)
      state := state.set! j (state[j]! ^^^ lane)
    state := permute state
  let remBase := nFull * rate
  let rem := bs.size - remBase
  let mut block : ByteArray := ByteArray.mk (Array.replicate rate (0 : UInt8))
  for i in [0:rem] do
    block := block.set! i bs[remBase + i]!
  block := block.set! rem (block[rem]! ^^^ 0x01)
  block := block.set! (rate - 1) (block[rate - 1]! ^^^ 0x80)
  for j in [0:rate / 8] do
    let lane := readLE64 block (j * 8)
    state := state.set! j (state[j]! ^^^ lane)
  state := permute state
  let mut out : ByteArray := ByteArray.empty
  for j in [0:4] do
    out := writeLE64 out state[j]!
  return out

def hashUtf8 (s : String) : ByteArray :=
  hash s.toUTF8

private def hexDigit (n : UInt8) : Char :=
  let v := n.toNat
  if v < 10 then Char.ofNat ('0'.toNat + v)
  else Char.ofNat ('a'.toNat + (v - 10))

/-- Lowercase hex of a byte array (no `0x` prefix). -/
def bytesToHex (bs : ByteArray) : String := Id.run do
  let mut acc : String := ""
  for i in [0:bs.size] do
    let b := bs[i]!
    acc := acc.push (hexDigit (b >>> 4))
    acc := acc.push (hexDigit (b &&& 0x0f))
  return acc

/-- Full 32-byte digest as lowercase hex. -/
def hashHex (bs : ByteArray) : String :=
  bytesToHex (hash bs)

/-- EVM 4-byte function selector (first 4 bytes of keccak256 of the ABI signature). -/
def selectorHex (abiSignature : String) : String :=
  let dig := hashUtf8 abiSignature
  bytesToHex (dig.extract 0 4)

end ProofForge.Util.Keccak256
