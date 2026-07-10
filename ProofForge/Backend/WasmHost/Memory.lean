/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Backend.WasmHost.Memory

/-! ## NEAR Wasm linear-memory scratch layout

These constants carve fixed, non-overlapping regions out of the Wasm linear
memory for EmitWat codegen. The layout is a frozen contract between the
emitter and the runtime host imports (`read_register`/`storage_read`/...).

Region map (base -> base+size, all bytes are exclusive scratch space):

| Region          | Base   | Size   | End    | Purpose |
|-----------------|--------|--------|--------|---------|
| `KEY_BUF`       | 4096   | 4096   | 8192   | input register read buffer |
| `RET_BUF`       | 8192   | 3808   | 12000  | `value_return` payload (U64/U32/Bool) |
| `TRUE_PTR`      | 12000  | 6      | 12006  | canonical `true` byte (1) |
| `FALSE_PTR`     | 12006  | 5      | 12011  | canonical `false` bytes |
| `HEX_LUT_PTR`   | 12012  | 16     | 12028  | lowercase hex digit lookup table |
| `MAPKEY_BUF`    | 12500  | ~17500 | 30000  | scratch for map storage keys (prefix ++ key) |
| `HASH_HEAP`     | 30000  | ~10000 | 40000  | bump-alloc base for 32-byte hash temporaries |
| `HASH_CONCAT_BUF`| 40000 | 64     | 40064  | `hash_two_to_one` 64-byte input |
| `CTX_BUF`       | 41000  | 128    | 41128  | account-id -> sha256 -> u64 |
| `EVENT_BUF`     | 42000  | 256    | 42256  | event JSON scratch |
| `PACK_KEY_PTR`  | 42600  | 6      | 42606  | fixed `"__pf_s"` key for packed scalars |
| `EVT_PUNCT`     | 42800  | 16     | 42816  | static JSON punctuation for event logs |
| `STRING_BASE`   | 43000  | ~1000  | 44000  | event/field name string pool |
| `INPUT_BUF`     | 44000  | ~2000  | 46000  | Borsh input args (1 KB headroom) |
| `PARAM_HASH_BUF`| 46000  | ~1000  | 47000  | 32-byte slots for decoded hash params |
| `CROSSCALL_BUF` | 47000  | ~1100  | 48100  | NEAR crosscall JSON argument scratch |
| `CROSSCALL_ARGS_EMPTY_PTR` | 48100 | 2 | 48102 | fixed "[]" payload |
| `CROSSCALL_STRING_BASE` | 49000 | ~1000 | 50000 | NEAR account/method string pool |
| `ZERO_HASH_BUF` | 50000  | 32     | 50032  | 32 zero bytes for missing hash map entries |
| `OLD_HASH_BUF`  | 50500  | 32     | 50532  | previous value for hash map set/insert |
| `PROMISE_RESULT_BUF` | 51000 | 8   | 51008  | Borsh U64 promise callback payload |
| `STRUCT_BUF`    | 52000  | ...    | ...    | struct-valued scalar state read/write |
| `ARR_HEAP`      | 60000  | ...    | ...    | bump-alloc base for array-value temporaries |

The bump heaps (`HASH_HEAP`, `ARR_HEAP`) grow upward and are reset per
entrypoint by the prologue. Their high-water marks must stay below the next
fixed region: `HASH_HEAP` must stay below `HASH_CONCAT_BUF` (40000), and
`ARR_HEAP` must stay below the Wasm memory limit configured by the host.
The fixed scratch regions above 40000 are never touched by the bump heaps.

Note: this is a codegen-only layout, separate from the `AllocatorConfig`
bound to the `wasm-near` target profile (`nearWeeModel`, used for IR-level
storage slot assignment). The two do not overlap because `AllocatorConfig`
addresses storage keys, not linear memory. -/

-- Memory layout
def KEY_BUF   : Nat := 4096
def RET_BUF   : Nat := 8192
def TRUE_PTR  : Nat := 12000
def FALSE_PTR : Nat := 12006
def HEX_LUT_PTR : Nat := 12012
def MAPKEY_BUF : Nat := 12500    -- scratch for building map storage keys (prefix ++ key bytes)
def HASH_HEAP : Nat := 30000       -- bump-allocator base for hash (32-byte) temporaries
def ARR_HEAP : Nat := 60000       -- bump-allocator base for array-value temporaries
def HASH_CONCAT_BUF : Nat := 40000 -- 64-byte scratch for hash_two_to_one
def CTX_BUF : Nat := 41000          -- 128-byte scratch for account-id -> sha256 -> u64
def EVENT_BUF : Nat := 42000       -- 256-byte scratch for building event JSON
/-- Storage key for packed multi-scalar state (`"__pf_s"`). -/
def PACK_KEY_PTR : Nat := 42600
def PACK_KEY_LEN : Nat := 6
/-- Packed scalar scratch reuses `STRUCT_BUF` (52000) as the in-memory blob. -/
def PACK_BUF : Nat := 52000
/-- Static punctuation pack used by optimized event JSON assembly (replaces
per-character `putc` sequences). Layout within the 16-byte region:
  +0  (10) `{"event":"`
  +10 (1)  `"`
  +11 (2)  `,"`
  +13 (2)  `":`
  +15 (1)  `}`
-/
def EVT_PUNCT_BASE : Nat := 42800
def EVT_PUNCT_SIZE : Nat := 16
def EVT_HDR_OPEN_PTR : Nat := EVT_PUNCT_BASE
def EVT_HDR_OPEN_LEN : Nat := 10
def EVT_QUOTE_PTR : Nat := EVT_PUNCT_BASE + 10
def EVT_FIELD_SEP_PTR : Nat := EVT_PUNCT_BASE + 11
def EVT_COLON_PTR : Nat := EVT_PUNCT_BASE + 13
def EVT_CLOSE_PTR : Nat := EVT_PUNCT_BASE + 15
/-- Back-compat alias: start of the event punctuation pack (was "event" key). -/
def EVT_KEY_PTR : Nat := EVT_PUNCT_BASE
def STRING_BASE : Nat := 43000     -- event/field name string pool base
def INPUT_BUF : Nat := 44000       -- 1 KB scratch for Borsh input args
def CROSSCALL_BUF : Nat := 47000          -- scratch for building crosscall JSON arg arrays
def CROSSCALL_ARGS_EMPTY_PTR : Nat := 48100 -- fixed "[]" payload for zero-arg NEAR crosscalls
def CROSSCALL_ARGS_EMPTY_LEN : Nat := 2
def CROSSCALL_STRING_BASE : Nat := 49000
def crosscallDefaultGas : Nat := 50_000_000_000_000
def PARAM_HASH_BUF : Nat := 46000  -- 32-byte slots for decoded hash params (one per hash param)
def ZERO_HASH_BUF : Nat := 50000  -- 32 zero bytes returned for missing hash-valued map entries
def OLD_HASH_BUF   : Nat := 50500  -- 32-byte slot holding the previous value for hash-valued map set/insert
def STRUCT_BUF      : Nat := 52000  -- buffer for reading/writing struct-valued scalar state
def PROMISE_RESULT_BUF : Nat := 51000  -- scratch for Borsh U64 promise callback payloads
def crosscallPoolPtrName : String := "__pf_crosscall_pool_ptr"
def crosscallPoolLenName : String := "__pf_crosscall_pool_len"

/-- Assert two half-open intervals `[a0, a0+aSz)` and `[b0, b0+bSz)` do not
overlap. Used by `memoryLayoutNonoverlap` below to make the frozen layout
machine-checked at build time. -/
def disjointRegions (a0 aSz b0 bSz : Nat) : Bool :=
  a0 + aSz <= b0 || b0 + bSz <= a0

/-- Build-time check that the fixed scratch regions are pairwise disjoint.
Evaluated by `memoryLayoutNonoverlap_valid` below; a failure means someone
added or moved a constant without leaving a gap, which would silently
corrupt runtime scratch state. -/
def memoryLayoutNonoverlap : Bool :=
  let regions := #[
    (KEY_BUF, 4096), (RET_BUF, 3808), (TRUE_PTR, 6), (FALSE_PTR, 5),
    (HEX_LUT_PTR, 16), (MAPKEY_BUF, 17500), (HASH_HEAP, 10000),
    (HASH_CONCAT_BUF, 64), (CTX_BUF, 128),
    (EVENT_BUF, 256), (PACK_KEY_PTR, PACK_KEY_LEN), (EVT_PUNCT_BASE, EVT_PUNCT_SIZE),
    (STRING_BASE, 1000),
    (INPUT_BUF, 2000), (PARAM_HASH_BUF, 1000), (CROSSCALL_BUF, 1100),
    (CROSSCALL_ARGS_EMPTY_PTR, CROSSCALL_ARGS_EMPTY_LEN),
    (CROSSCALL_STRING_BASE, 1000), (ZERO_HASH_BUF, 32),
    (OLD_HASH_BUF, 32), (PROMISE_RESULT_BUF, 8), (STRUCT_BUF, 4000)
  ]
  regions.all (fun (a0, aSz) =>
    regions.all (fun (b0, bSz) =>
      a0 == b0 || disjointRegions a0 aSz b0 bSz))

/-- Decidable proof that the fixed EmitWat scratch regions are pairwise
disjoint. If this theorem fails to elaborate, the memory layout constants
above have been edited into an overlapping state and codegen would silently
corrupt runtime scratch buffers. `native_decide` is used because the
check folds `Array.all` over a literal array, which the kernel's `decide`
reduction does not fully evaluate, while native evaluation handles it
trivially. -/
theorem memoryLayoutNonoverlap_valid : memoryLayoutNonoverlap = true := by
  native_decide

end ProofForge.Backend.WasmHost.Memory
