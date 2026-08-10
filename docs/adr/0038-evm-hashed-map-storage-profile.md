# ADR-0038: Opt-in EVM hashed-Map storage profile

## Status

Accepted. **Product default** for EVM as of the follow-up default flip
(`evm-yul-solc-0.8.34-hashmap-v1`). Dense layout remains an explicit profile.

## Context

Dense EVM Map layout stores fixed pilot tables:

* `Map UInt64 UInt64` → 24 contiguous UInt64 leaves (cap-8 × occ/key/val)
* `Map Principal UInt64` → 44 contiguous UInt64 leaves (cap-4 × occ/9-key/val)

This fixed layout is portable, enumerable, and good for cross-target proof
surfaces, but MiniAmm / Token bytecode and runtime gas are dominated by the
scan loops and leaf stores. Solidity `mapping` uses keccak slot derivation
instead.

## Decision

Product default codegen profile:

```text
evm-yul-solc-0.8.34-hashmap-v1   # keccak Map storage (default)
```

Dense layout remains available as an explicit selection:

```text
evm-yul-solc-0.8.34-v1   # dense 24/44-leaf Map layout (explicit)
```

There is **no** automatic migration between dense and hashed deployments.
Existing dense deployments must keep `--profile evm-yul-solc-0.8.34-v1`.

### Storage wire (canonical)

**UInt64 Map** (one declared base slot `{state}_base`):

```text
mstore(0, key)
mstore(32, base)
h := keccak256(0, 64)
slot h     = occupancy 0/1
slot h + 1 = UInt64 payload
```

**Principal Map** (same base slot; key is full 9-leaf Principal wire):

```text
// keyMem[0..8] = Principal leaves (len + 8×UInt64 body)
mstore(keyMem + 288, base)
h := keccak256(keyMem, 320)
slot h     = occupancy 0/1
slot h + 1 = UInt64 payload
```

* Occupancy/payload loads go through `pf_sload_u64` (UInt64 fail-closed gate).
* Collisions follow the standard EVM mapping cryptographic assumption.
* This is **not** claimed Solidity ABI/storage-compatible unless an exact
  Solidity slot preimage is later pinned with tests.

### Map.empty / reset

* Constructor `Map.empty()` is admitted (fresh storage is zero; base slot zero
  write is elided like other fresh-zero stores).
* Runtime `m := Map.empty()` is **fail closed** on the hashed profile: a single
  base-slot zero cannot clear historical keccak entries. Epoch/generation reset
  is a future option, not part of this MVP.

### Plan / digest

`Plan.hashedMapStorage : Bool` is part of the engineering Plan schema encode
(appended bool). Dense and hashed plans must not share the same plan digest for
otherwise identical programs.

### Finalize

Same locked solc 0.8.34 argv as dense default:

```text
--strict-assembly --optimize --bin
```

Evidence note fragment: ` map-storage=hashed`.

## Consequences

* Smaller Map-heavy bytecode / gas expected (Token, MiniAmm) vs dense tables.
* Loses fixed enumerable layout and dense cross-target layout parity.
* Product docs must say hashed is opt-in and migration-incompatible.
* Dense remains available for portability / historical goldens via explicit profile.
* New EVM builds default to hashed Map storage.
