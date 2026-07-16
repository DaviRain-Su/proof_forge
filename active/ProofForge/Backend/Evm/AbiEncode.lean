/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# EVM ABI encode builder (calldata layout)

Compile-time **ABI encoding planner** for EVM-shaped targets.
Parallel to:

| Host | Pack layer |
|------|------------|
| NEAR / Wasm | `WasmHost.JsonEncode` |
| EVM | **`Evm.AbiEncode`** (this module) |
| Solana | CPI `dataLayout` packing (`Extension.Cpi`) |

Protocols describe a schema; one plan step materializes offsets + words.
This module is **pure layout**. Yul emit lives in `ToYul.AbiEncode`
(Wave δ: Plan → `mstore` + CALL). Tests and Protocol clients consume `Plan`.

## Supported shapes (honest subset)

| Shape | Use |
|-------|-----|
| Static words | address / uint256 as one word |
| `bytes` (static content) | Inner call data |
| `Call` = `(address,bytes)` | Multicall `aggregate` element |
| `Call3` = `(address,bool,bytes)` | Multicall3 `aggregate3` element |
| Dynamic array of Call / Call3 | `aggregate` / `aggregate3` args |
| Selector ‖ static arg words | Inner `callDataFromSelectorArgs` |
| Plan → Yul | `ToYul.AbiEncode.emitCall` / `renderAggregateCallYul` |

Not yet: nested dynamic arrays beyond Call[], free-form runtime calldata
blobs, string-as-UTF8 (treat as bytes). Call[] IR auto-lower: static
(`irAggregate`), runtime length, runtime targets, runtime **selector‖uint256\***
args (`irAggregateDynCalls`).
-/
import Init.Data.Array.Basic
import Init.Data.Nat.Basic

namespace ProofForge.Backend.Evm.AbiEncode

/-- 32-byte ABI word value. -/
inductive WordVal where
  | num (n : Nat)
  deriving BEq, Repr

/-- One word store relative to the encoding region base. -/
structure Store where
  offset : Nat
  value : WordVal
  deriving BEq, Repr

/-- Complete encoding plan. -/
structure Plan where
  stores : Array Store
  size : Nat
  deriving Repr

def catalogId : String := "evm.abi_encode"

def pad32 (n : Nat) : Nat :=
  ((n + 31) / 32) * 32

def store (offset n : Nat) : Store :=
  { offset := offset, value := .num n }

/-- Pack raw bytes into big-endian 32-byte words (ABI bytes payload). -/
def packBytesToWords (data : Array Nat) : Array Nat :=
  let wordCount := pad32 data.size / 32
  Id.run do
    let mut words : Array Nat := #[]
    for w in [0:wordCount] do
      let mut v : Nat := 0
      for b in [0:32] do
        let i := w * 32 + b
        let byte := if i < data.size then data[i]! % 256 else 0
        v := v * 256 + byte
      words := words.push v
    words

/-- Encode `bytes` at absolute `base`: length word + padded data. -/
def encodeBytesAt (base : Nat) (data : Array Nat) : Array Store × Nat :=
  let lenStore := store base data.size
  let words := packBytesToWords data
  let dataBase := base + 32
  let dataStores := Id.run do
    let mut acc : Array Store := #[]
    for i in [0:words.size] do
      acc := acc.push (store (dataBase + i * 32) words[i]!)
    acc
  (#[lenStore] ++ dataStores, dataBase + pad32 data.size)

/-- Inner call data bytes: 4-byte selector ‖ each arg word as 32 big-endian bytes. -/
def callDataFromSelectorArgs (selector : Nat) (argWords : Array Nat) : Array Nat :=
  let s0 := (selector / (256 ^ 3)) % 256
  let s1 := (selector / (256 ^ 2)) % 256
  let s2 := (selector / 256) % 256
  let s3 := selector % 256
  let head : Array Nat := #[s0, s1, s2, s3]
  let argBytes := argWords.foldl
    (fun acc w =>
      let out : Array Nat := Id.run do
        let mut y := w
        let mut bytes : Array Nat := Array.replicate 32 0
        for i in [0:32] do
          let idx := 31 - i
          bytes := bytes.set! idx (y % 256)
          y := y / 256
        bytes
      acc ++ out)
    (#[] : Array Nat)
  head ++ argBytes

/-- Multicall `Call` = `(address target, bytes callData)`. -/
structure Call where
  target : Nat
  data : Array Nat
  deriving Repr, Inhabited

/-- Multicall3 `Call3` = `(address, bool allowFailure, bytes)`. -/
structure Call3 where
  target : Nat
  allowFailure : Bool
  data : Array Nat
  deriving Repr, Inhabited

/-- Encode one `Call` at `base`: [address][rel_offset=0x40][bytes…]. -/
def encodeCallAt (base : Nat) (c : Call) : Array Store × Nat :=
  let head0 := store base c.target
  let head1 := store (base + 32) 0x40
  let (byteStores, endOff) := encodeBytesAt (base + 0x40) c.data
  (#[head0, head1] ++ byteStores, endOff)

/-- Encode one `Call3` at `base`: [address][bool][rel_offset=0x60][bytes…]. -/
def encodeCall3At (base : Nat) (c : Call3) : Array Store × Nat :=
  let head0 := store base c.target
  let head1 := store (base + 32) (if c.allowFailure then 1 else 0)
  let head2 := store (base + 64) 0x60
  let (byteStores, endOff) := encodeBytesAt (base + 0x60) c.data
  (#[head0, head1, head2] ++ byteStores, endOff)

/-- Encode `Call[]` at `arrayBase`: length, per-element offsets (rel. to arrayBase), tuples. -/
def encodeCallArrayAt (arrayBase : Nat) (calls : Array Call) : Array Store × Nat :=
  Id.run do
    let n := calls.size
    let mut stores : Array Store := #[store arrayBase n]
    let offsetsBase := arrayBase + 32
    let mut cursor := offsetsBase + n * 32
    for i in [0:n] do
      stores := stores.push (store (offsetsBase + i * 32) (cursor - arrayBase))
      let (ts, endOff) := encodeCallAt cursor calls[i]!
      stores := stores ++ ts
      cursor := endOff
    (stores, cursor)

/-- Encode `Call3[]` at `arrayBase`. -/
def encodeCall3ArrayAt (arrayBase : Nat) (calls : Array Call3) : Array Store × Nat :=
  Id.run do
    let n := calls.size
    let mut stores : Array Store := #[store arrayBase n]
    let offsetsBase := arrayBase + 32
    let mut cursor := offsetsBase + n * 32
    for i in [0:n] do
      stores := stores.push (store (offsetsBase + i * 32) (cursor - arrayBase))
      let (ts, endOff) := encodeCall3At cursor calls[i]!
      stores := stores ++ ts
      cursor := endOff
    (stores, cursor)

/-- `aggregate` **args** region (no 4-byte selector): head `0x20` + Call[]. -/
def encodeAggregateArgs (calls : Array Call) : Plan :=
  let head := store 0 0x20
  let (arrStores, endOff) := encodeCallArrayAt 0x20 calls
  { stores := #[head] ++ arrStores, size := endOff }

/-- `aggregate3` **args** region: head `0x20` + Call3[]. -/
def encodeAggregate3Args (calls : Array Call3) : Plan :=
  let head := store 0 0x20
  let (arrStores, endOff) := encodeCall3ArrayAt 0x20 calls
  { stores := #[head] ++ arrStores, size := endOff }

/-- Word at exact offset, if present. -/
def planWordAt? (p : Plan) (offset : Nat) : Option Nat :=
  p.stores.find? (fun s => s.offset == offset) |>.map fun s =>
    match s.value with
    | .num n => n

def planWordCount (p : Plan) : Nat :=
  pad32 p.size / 32

end ProofForge.Backend.Evm.AbiEncode
