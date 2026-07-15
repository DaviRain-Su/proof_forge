/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-S3: pure Lean Keccak-256 vectors (no cast / no mathlib)
-/
import ProofForge.Util.Keccak256

namespace ProofForge.Tests.Util.Keccak256

open ProofForge.Util.Keccak256

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO UInt32 := do
  -- Ethereum empty-string digest
  require (hashHex "".toUTF8 ==
      "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    "keccak256(\"\") mismatch"
  -- "abc"
  require (hashHex "abc".toUTF8 ==
      "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
    "keccak256(\"abc\") mismatch"
  -- Solidity selector seeds
  require (selectorHex "transfer(address,uint256)" == "a9059cbb")
    "selector transfer(address,uint256)"
  require (selectorHex "owner()" == "8da5cb5b")
    "selector owner()"
  require (selectorHex "initialize()" == "8129fc1c")
    "selector initialize() — Counter fixture pin"
  IO.println "keccak256: ok (ethereum vectors + ABI selectors)"
  pure 0

end ProofForge.Tests.Util.Keccak256

def main : IO UInt32 :=
  ProofForge.Tests.Util.Keccak256.main
