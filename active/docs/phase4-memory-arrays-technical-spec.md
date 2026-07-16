# Phase 4 Memory Dynamic Arrays — Technical Spec

## Scope

This spec covers the remaining Phase 4 work for ProofForge's EVM backend:
- In-memory dynamic arrays (`ValueType.array elementType`) for word-sized elements.
- ABI head-tail encode/decode for dynamic array parameters and return values.
- Calldata decoding of dynamic array arguments.

Out of scope (follow-up):
- Memory arrays of structs or nested arrays.
- `push`/`pop` on memory arrays (Solidity does not support these; only storage arrays have push/pop).
- Crosscall dynamic-array arguments/returns.

## 1. Memory Layout

A memory dynamic array is represented by a single 256-bit pointer local. At `ptr`:

```
memory[ptr]       = length (32 bytes)
memory[ptr+32]    = element 0 (32 bytes)
memory[ptr+64]    = element 1 (32 bytes)
...
memory[ptr+32+n*32] = element n
```

Only 32-byte word element types are supported in this first slice:
`u8`, `u32`, `u64`, `u128`, `bool`, `hash`, `address`.

## 2. IR Surface Additions

### `ProofForge/IR/Contract.lean`

Add `Expr` constructors:

```lean
| memoryArrayNew (elementType : ValueType) (length : Expr)
| memoryArrayLength (array : Expr)
| memoryArrayGet (array index : Expr)
```

Add `Effect` constructor:

```lean
| memoryArraySet (array index value : Expr)
```

`memoryArrayNew` returns a value of type `ValueType.array elementType`.
`memoryArrayLength` returns `ValueType.u64` (length fits in 64 bits for practical arrays).
`memoryArrayGet` returns `elementType`.
`memoryArraySet` requires `array` of type `ValueType.array elementType`, `index` of type `u64`, and `value` of type `elementType`.

### Capability updates

- `Expr.capabilities`: `.memoryArrayNew` → `[.dataDynamicArray]`; `.memoryArrayLength`/`.memoryArrayGet` → `[.dataDynamicArray]`.
- `Effect.capabilities`: `.memoryArraySet` → `[.dataDynamicArray]`.

## 3. Validation

### `ProofForge/Backend/Evm/Validate.lean`

- `memoryArrayNew elementType length`: `elementType` must be a storage-word type (`isStorageWordType`). `length` must infer to `u64`.
- `memoryArrayLength array`: `array` must infer to `ValueType.array _`.
- `memoryArrayGet array index`: `array` must infer to `ValueType.array elementType`; `index` must infer to `u64`.
- `memoryArraySet array index value`: same as get plus `value` type matches element type.

## 4. Plan Layer

### `ProofForge/Backend/Evm/Plan.lean`

Add `ExprPlan` constructors:

```lean
| memoryArrayNew (elementType : ValueType) (length : ValuePlan)
| memoryArrayLength (array : ValuePlan)
| memoryArrayGet (array index : ValuePlan)
```

Add `EffectPlan` constructor:

```lean
| memoryArraySet (array index value : ValuePlan)
```

Add helper requirements:

```lean
| memoryArraySlot -- not needed; computed inline
```

No new helper functions are required; all address arithmetic is emitted inline.

## 5. Lowering

### `ProofForge/Backend/Evm/Lower.lean`

In `buildExprPlan`:
- `Expr.memoryArrayNew elementType length` → `.memoryArrayNew elementType (← buildExprPlan length)`
- `Expr.memoryArrayLength array` → `.memoryArrayLength (← buildExprPlan array)`
- `Expr.memoryArrayGet array index` → `.memoryArrayGet (← buildExprPlan array) (← buildExprPlan index)`

In effect planning:
- `Effect.memoryArraySet array index value` → `.memoryArraySet ...`

### `ProofForge/Backend/Evm/IR.lean`

- `inferExprType` handles new Expr plans.
- `validateEffectStmtTypes` handles new effects.
- `nestedLocalArrayGetShapesStatements` handles new effects.
- `exprUsesCheckedArithmetic` / `stmtUsesCheckedArithmetic` handle new forms.

## 6. Yul Generation

### `ProofForge/Backend/Evm/ToYul.lean`

The runtime uses two helper functions emitted whenever the module carries the `.dataDynamicArray` capability:

```yul
function __proof_forge_memory_array_new(length) -> ptr {
  ptr := mload(64)
  mstore(ptr, length)
  mstore(64, add(ptr, mul(add(length, 1), 32)))
}
function __proof_forge_memory_array_get(array, index) -> value {
  if iszero(lt(index, mload(array))) {
    revert(0, 0)
  }
  value := mload(add(add(array, 32), mul(index, 32)))
}
```

`memoryArraySet` is lowered inline as:

```yul
if iszero(lt(index, mload(array))) { revert(0, 0) }
mstore(add(add(array, 32), mul(index, 32)), value)
```

`memoryArrayLength` is `mload(array)`.

The free-memory pointer at slot `0x40` is assumed initialized by the existing dynamic-ABI decode preamble; the helper reads `mload(64)` and bumps it.

## 7. ABI Encoding / Decoding (future work)

### Dynamic array as function parameter

A parameter of type `uint256[]` (or `u64[]`, etc.) uses head-tail ABI encoding:

- Head word at calldata offset `4 + paramIndex*32` contains the byte offset (relative to first parameter head) to the tail.
- Tail: `[length, elem0, elem1, ...]`.

The decode logic mirrors existing bytes/string decode but reads `length` words instead of bytes:

```yul
let offsetHead := calldataload(4 + paramIndex * 32)
let dataOffset := add(4 + paramIndex * 32, offsetHead)
let len := calldataload(dataOffset)
let dataStart := add(dataOffset, 32)
let ptr := mload(64)
mstore(ptr, len)
let bytes := mul(add(len, 1), 32)
calldatacopy(add(ptr, 32), dataStart, mul(len, 32))
mstore(64, add(ptr, bytes))
```

Validate tail is within calldata bounds.

### Dynamic array as return value

Return encoding for `ValueType.array elementType`:

```yul
let len := mload(array)
let bytes := mul(add(len, 1), 32)
mstore(0, 32)            // head: offset to tail
mstore(32, len)
mstore(64, 0x40)         // tail data starts at offset 64 in return buffer
// Actually copy array data to memory[64 .. 64+bytes-32]
```

Because the return buffer is a fresh memory region, we can lay it out as:
- `memory[0..32]` = head offset = 32
- `memory[32..64]` = length
- `memory[64..64+len*32]` = elements

Return `(0, 64 + len*32)`.

This commit does **not** implement ABI-facing dynamic arrays; the probe keeps memory arrays internal and only passes scalar parameters.

## 8. Example Probe

Create `ProofForge/IR/Examples/Backend/EvmMemoryArrayProbe.lean` with entrypoints:

- `memory_lifecycle` — allocates a 3-element `Array<U64>`, fills it, and returns the sum.
- `memory_length` — allocates a 5-element array and returns its length.
- `get_and_sum(uint256,uint256,uint256)` — copies three u64 parameters into a fresh array and returns their sum.

This probe is registered as the `evm-memory-array` CLI fixture.

## 9. Tests

### Lean/Yul generation
- `just evm-ir-smokes` must still pass for existing fixtures.
- Regenerate `EvmDynamicArrayProbe.golden.yul` because the new helpers are also emitted for any module with `.dataDynamicArray`.

### Foundry tests
`scripts/evm/memory-array-ir-smoke.sh` verifies:
- `memory_lifecycle` returns `31`.
- `memory_length` returns `5`.
- `get_and_sum(7, 11, 13)` returns `31`.
- Unknown selector reverts.

Bounds checking is exercised by the Yul helper revert path when index >= length.

## 10. Coverage / i18n

- `Tests/Backend/Evm/EvmCoverage.tsv`: updated entries for `ValueType.array`, `Effect.memoryArraySet`, `Statement.letBind`, and `Statement.letMutBind`.
- `Tests/Backend/Wasm/WasmNearCoverage.tsv`, `Tests/PsyCoverage.tsv`, `Tests/Backend/Wasm/EmitWatCoverage.tsv`: `ValueType.array` already unsupported; added explicit `memoryArray*` unsupported rows.
- `scripts/i18n/manifest.json`: no update required because `docs/targets/evm.md` did not change.

## Acceptance Criteria

- [x] `just check` passes.
- [x] `just evm-ir-smokes` passes with updated golden Yul.
- [x] New Foundry tests for memory arrays pass.
- [x] `scripts/i18n/check-sync.sh` passes.
- [x] `Tests/Backend/Evm/EvmCoverage.tsv` updated.
