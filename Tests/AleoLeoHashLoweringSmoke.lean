import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo `crypto.hash` lowering (RFC 0015).

Aleo resolves the portable `Hash` digest to `field` and lowers hash ops to the
native ZK hash `Poseidon2::hash_to_field` (verified against ProvableHQ/leo
operators/crypto). Hashing is capability-portable, not value-portable
(keccak ≠ Poseidon), per the RFC.

- `.hash preimage` → `Poseidon2::hash_to_field(preimage)` (single input).
- `.hashTwoToOne l r` → ordered, pair-domain-separated field encoding.
- `hash4` literals are rejected (EVM 4×u64 digest shape; Aleo hashes values). -/

namespace ProofForge.Tests.AleoLeoHashLoweringSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- `fn hash_u64(x: u64) -> field { return Poseidon2::hash_to_field(x); }` -/
def hashU64 : Entrypoint :=
  { name := "hash_u64"
    params := #[("x", .u64)]
    returns := .hash
    body := #[ .return (.hash (.local "x")) ] }

/-- `fn hash_pair(a: u64, b: u64) -> field` uses an ordered field encoding. -/
def hashPair : Entrypoint :=
  { name := "hash_pair"
    params := #[("a", .u64), ("b", .u64)]
    returns := .hash
    body := #[ .return (.hashTwoToOne (.local "a") (.local "b")) ] }

def hashModule : Module :=
  { name := "Zh", state := #[], entrypoints := #[hashU64, hashPair] }

def hashLowersOk : Bool :=
  match renderModule hashModule with
  | .ok _ => true
  | .error _ => false

theorem hash_lowers_ok : hashLowersOk = true := by native_decide

/-- The lowered Leo uses Poseidon2 and returns `field` (Hash ≡ field). -/
def hashLeoHasMarkers : Bool :=
  match renderModule hashModule with
  | .ok s =>
      s.contains "program zh.aleo" &&
      s.contains "fn hash_u64(x: u64) -> field" &&
      s.contains "return Poseidon2::hash_to_field(x);" &&
      s.contains "fn hash_pair(a: u64, b: u64) -> field" &&
      s.contains "Poseidon2::hash_to_field(a) * 1315423911field" &&
      s.contains "Poseidon2::hash_to_field(b)" &&
      s.contains "2field"
  | .error _ => false

theorem hash_leo_has_markers : hashLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @hash_lowers_ok
  have _ := @hash_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoHashLoweringSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-hash-lowering-smoke: crypto.hash -> Poseidon2 (Hash = field) checked"
  return 0
