# Wasm-NEAR 目标

**Target id:** `wasm-near`
**Family:** Wasm host

两条后端路径并存：

- **Canonical（目标状态）：** `EmitWat` — Portable IR → Wasm AST → WAT → `wat2wasm`，对齐仓库内 portable-IR → Yul 的 EVM 后端。参见 [D-031](../decisions.zh.md) 和 [Wasm family common shape](wasm-family.zh.md)。
- **冻结的 v0 stopgap（仓库内，可编译）：** Rust `near-sdk-rs` sourcegen — `Portable IR → near-sdk-rs package → cargo wasm32`。它现在验证 NEAR 语义，但**不再扩展**。细节见下方 [Frozen v0 reference](#frozen-v0-reference-rust-sourcegen)。

## Canonical architecture (`EmitWat`)

```text
Portable IR (Module)
  -> EmitWat                       (portable IR -> Wasm AST; mirrors Backend/Evm/IR.lean)
  -> Wasm AST -> WAT text          (Compiler/Wasm/AST.lean + Printer.lean)
  -> wat2wasm                      (shared toolchain)
  -> NEAR-compatible Wasm          (imports env.* host functions)
```

`EmitWat` 对齐 `ProofForge/Backend/Evm/IR.lean`（portable IR → Yul AST），但目标是 WAT 而不是 Yul。因为 portable IR 已经抽象掉 Lean 对象（只有 `u32`/`u64`/`bool`/`hash` 标量 + storage effects），这里**没有 Lean runtime 要移植，也没有 object-model boxing/GC**。标量直接映射到 Wasm `i32`/`i64`，storage/crypto/context effects lower 到 NEAR host imports。IR-lowering 和 validation logic 可复用冻结 Rust v0（`Backend/WasmNear/IR.lean`）以及 `Backend/Evm/IR.lean`；只有 emission target 变化（Rust/Yul strings → Wasm AST → WAT）。

Storage/crypto/context effects lower 到这些 NEAR host imports：

| IR effect | NEAR host import |
|---|---|
| `storageScalarRead` / `storageMapGet` | `env.storage_read` |
| `storageScalarWrite` / `storageMapSet` | `env.storage_write` |
| `storageMapContains` | `env.storage_has_key` |
| `hash` / `hashTwoToOne` | `env.sha256` |
| `contextRead userId` | `env.predecessor_account_id` |
| `contextRead contractId` | `env.current_account_id` |
| `contextRead checkpointId` | `env.block_height` |
| `eventEmit` | `env.log` |

### 为什么不用 `EmitZig`

早期计划（`Lean → EmitZig → Zig → host bridge → Wasm`）已被取代，因为它要求把完整 Lean runtime 移植到 Wasm（libuv / threads / GC），这是已记录的 blocker。`EmitWat` 直接 lower portable IR，完全避开这个 runtime port；它也避免了对 `near-sdk` macros 的耦合（Rust v0 中 E0119 / missing-`&self` bug 的来源）。

### Spike gate（最高风险）— 已解决（EmitWat 端到端）

NEAR 通过序列化的 Borsh 传入 entrypoint arguments，并期望序列化后的 returns；contract methods 导出为 `() -> ()` dispatchers，通过 `env.input()`/`env.read_register` 读取参数，并通过 `env.value_return` 返回（不是 wasm function returns）。

这个风险已经完全 de-risk，不只是通过手写 reference counter（`examples/near/spike/handwritten-counter.wat`，约 40 行），也通过完整的 `EmitWat` backend 对真实 IR modules 端到端 lowering。ABI 是**对称 Borsh**：params 从 `env.input` decode（`u32`/`u64`/`bool`/`hash`，按累计 Borsh offset 打包为 little-endian），returns 通过 `value_return` encode 为 little-endian bytes（`u32`/`u64`/`bool`）或直接返回 32-byte hash，匹配 `near-sdk-rs` 的 Borsh convention，不使用 JSON。

7 个 IR example probes 已部署到 `near-sandbox` 并通过 `viewRaw` + Borsh decode 场景测试（Counter / Features / Map / Hash / Context / Params / Event），另有 `Map<Hash,Hash>` smoke（hash-keyed map）和 u32 arithmetic smoke（覆盖 `.pow`，断言 17^2=289）。四个 CLI emit modes（`--emit-{counter,context,hash,map}-emitwat -o <dir>`）会 lower 内置 IR examples，并写出 `<name>.wat` + `<name>.wasm`（经由 `wat2wasm`），这是无需 `cargo` 步骤的 deploy-ready package。

基础风险已解决：register-based host ABI 和 Borsh (de)serialization 在 WAT 层面对真实 IR 是可行的，不只是手写 counter 可行。

## Frozen v0 reference (Rust sourcegen)

本文档剩余部分描述冻结的 Rust `near-sdk-rs` sourcegen backend（`ProofForge/Backend/WasmNear/IR.lean`）。它作为可工作的 reference 保留，用于验证 NEAR 语义和 capability coverage；它不是 canonical path，也不再扩展。

**Backend pattern:** Portable IR → Rust `near-sdk-rs` package → `cargo build --target wasm32-unknown-unknown` → NEAR-compatible Wasm。

### Capability Profile

定义在 `ProofForge/Target/Registry.lean`（`def wasmNear`）：

| Capability | Supported | Notes |
|---|---|---|
| `storage.scalar` | Yes | u32、u64、bool、hash → Rust struct fields |
| `storage.map` | Yes | Map<U64, …> 和 Map<Hash, …> → raw `env::storage_read`/`env::storage_write` |
| `caller.sender` | Yes | `env::predecessor_account_id()` |
| `value.native` | Partial | Rust sourcegen 和 EmitWat 将 `nativeValue` 降级为 `env::attached_deposit()` / `attached_deposit` host import，作为 U64 投影 |
| `events.emit` | Yes | 使用 deterministic JSON lower 到 `near_sdk::log!` |
| `env.block` | Yes | `env::block_height()` |
| `crypto.hash` | Yes | 基于 `env::sha256` 的 hash helpers |
| `assertions.check` | Yes | Lower 到 Rust `assert!`/`assert_eq!` |
| `account.explicit` | Yes | `env::current_account_id()` |
| `crosscall.invoke` | No | sourcegen v0 不支持 |
| `storage.array` | Partial | target profile 为 EmitWat 路径声明该能力；Rust sourcegen v0 拒绝 array state |
| `control.conditional` | Partial | target profile 为 EmitWat 声明该能力；Rust sourcegen v0 拒绝 `if/else` |
| `control.bounded_loop` | Partial | target profile 为 EmitWat 声明该能力；Rust sourcegen v0 拒绝 bounded loop |
| `data.fixed_array` | Partial | target profile 为 EmitWat 声明该能力；Rust sourcegen v0 拒绝 fixed-array ABI 和 expression lowering |
| `data.struct` | Partial | target profile 为 EmitWat 声明该能力；Rust sourcegen v0 拒绝 struct ABI 和 expression lowering |

## Deviations from Original Plan

实现与原计划在几个地方不同，均记录在 [D-030](../decisions.zh.md)：

1. **Map keys widened to Hash.** 原计划只指定 `Map<U64, …>`，但 `MapProbe` 使用 `Map<Hash, Hash, 128>`。实现同时支持 U64 和 Hash keys，并提供独立的 `__pf_map_key_u64` / `__pf_map_key_hash` helpers。

2. **添加 `.assertions` 和 `.accountExplicit`。** 原计划能力列表遗漏了这些能力，但 `MapProbe` 使用 `assertEq`，`ContextProbe` 使用 `contractId`。两者现在都在 profile 中并已 lower。

3. **移除 `.crosscallInvoke`。** 与计划一致，v0 sourcegen 不支持它。

4. **Lower `assert`/`assertEq`。** 既然 `.assertions` 在 profile 中，这些语句 lower 到 Rust `assert!`/`assert_eq!` macros，而不是被拒绝。

5. **拒绝 `ifElse`/`boundedFor`。** 它们不在 capability profile 中。

6. **拒绝 `nativeValue` expression。** 虽然 `.valueNative` 在 profile 中（用于 capability declaration），但 v0 不支持检查 attached deposit 的 expression。

## Generated Package Structure

`renderPackage` 生成包含这些文件的 `NearPackage`：

- `Cargo.toml`：package name 从 module name sanitize 而来；依赖 `near-sdk = "5"`、`borsh = "1"`、`serde = "1"`、`serde_json = "1"`
- `src/lib.rs`：`#[near(contract_state)]` struct、`Default` impl、带 entrypoints 的 `#[near] impl` block，以及按需 helper functions

### Scalar State

Scalar state fields 变为带 `BorshDeserialize`/`BorshSerialize` 的 Rust struct fields：

| IR type | Rust type | Default |
|---|---|---|
| `u32` | `u32` | `0u32` |
| `u64` | `u64` | `0u64` |
| `bool` | `bool` | `false` |
| `hash` | `[u64; 4]` | `[0u64, 0u64, 0u64, 0u64]` |

### Map State

Map state 通过 `env::storage_read`、`env::storage_write` 和 `env::storage_has_key` 使用 raw NEAR KV storage。每种已使用 key type 会发射对应 helper：

- `__pf_map_key_u64(prefix, key)`：用于 `Map<U64, …>`
- `__pf_map_key_hash(prefix, key)`：用于 `Map<Hash, …>`

Codec helpers 只为模块实际使用的 value types 发射：`__pf_encode_u64`/`__pf_decode_u64`、`__pf_encode_bool`/`__pf_decode_bool`、`__pf_encode_hash`/`__pf_decode_hash`。

Map set helpers（`__pf_map_set_u64`、`__pf_map_set_bool`、`__pf_map_set_hash`）返回 previous value，对齐现有 Psy/EVM map semantics。

### Context Fields

| IR context field | Rust lowering |
|---|---|
| `userId` | `__pf_account_id_hash_u64(&env::predecessor_account_id())` |
| `contractId` | `__pf_account_id_hash_u64(&env::current_account_id())` |
| `checkpointId` | `env::block_height()` |

当使用 `.userId` 或 `.contractId` 时会发射 `__pf_account_id_hash_u64` helper。

### Hash Helpers

使用 `.cryptoHash` 时发射：

- `__pf_hash(value: [u64; 4]) -> [u64; 4]`：single-value SHA-256
- `__pf_hash_two_to_one(left: [u64; 4], right: [u64; 4]) -> [u64; 4]`：two-to-one SHA-256

### Events

`eventEmit` lower 到带 deterministic JSON 的 `near_sdk::log!`。v0 支持 `U32`、`U64`、`Bool` 和 `Hash` event fields。

## CLI Modes

```sh
proof-forge emit --target wasm-near --fixture counter --format wat -o build/wasm-near/Counter
proof-forge emit --target wasm-near --fixture context --format wat -o build/wasm-near/ContextProbe
proof-forge emit --target wasm-near --fixture hash --format wat -o build/wasm-near/HashProbe
proof-forge emit --target wasm-near --fixture map --format wat -o build/wasm-near/MapProbe
```

`-o` 对 Wasm-NEAR target-first package emission 是必需的，并被解释为 package output directory（不是单个文件）。Legacy
`--emit-*-ir-wasm-near` aliases 会在 RFC 0009 过渡期内作为兼容 shim 保留。

## Implementation Files

**Canonical (EmitWat):**

| File | Purpose |
|---|---|
| `ProofForge/Backend/WasmNear/EmitWat.lean` | Core EmitWat lowering：IR → Wasm AST（scalars、maps 含 `Map<Hash,T>`、hash、context、events、params、returns、`.pow`） |
| `ProofForge/Backend/WasmNear/IR.lean` | Wasm AST → WAT text + printer wiring |
| `ProofForge/Compiler/Wasm/AST.lean` / `Printer.lean` | Wasm AST + WAT printer |
| `Tests/EmitWat{Smoke,Features,Map,Hash,Context,Params,Event,Hashmap,Arith}.lean` | Per-probe renderers |
| `Examples/near/spike/emitwat-{regression,hashmap-smoke,arith-smoke}.cjs` | Deploy + Borsh-decode smoke tests |
| `ProofForge/Cli.lean` | `emit --target wasm-near --fixture ... --format wat` routing、`writeWatPackage`、`compileEmitWat` |

**Frozen v0 reference (Rust sourcegen):**

| File | Purpose |
|---|---|
| `ProofForge/Backend/WasmNear.lean` | Umbrella module |
| `ProofForge/Backend/WasmNear/IR.lean` | Core lowering：validation、type inference、Rust source generation（约 57KB） |
| `ProofForge/Target/Registry.lean` | 带 tools 和 capabilities 的 `wasmNear` profile |
| `ProofForge/Cli.lean` | `EmitMode` constructors、parse cases、`writeNearPackage`、compile functions |

## Required Tools

- `rustup` + `cargo` + `wasm32-unknown-unknown` target
- `near-cli`（用于 deployment validation；source generation 或 cargo build 不需要）

## Verification

```sh
# Build the compiler
lake build

# Generate a Counter package
lake env proof-forge emit --target wasm-near --fixture counter --format wat -o build/wasm-near/Counter

# Build the Wasm artifact
cd build/wasm-near/Counter && cargo build --target wasm32-unknown-unknown --release

# Run diagnostics
lake env lean --run Tests/WasmNearDiagnostics.lean
```

## Open Questions

这些问题只针对**冻结 v0**（Rust sourcegen）。Canonical path 的开放问题见 [Wasm family common shape](wasm-family.zh.md#待解决问题)。

- v0 已冻结；Rust route **不再扩展** capability coverage。新 capabilities 进入 canonical `EmitWat` path。
- 是否应将 `nativeValue` expression inspection（attached deposit）作为 dedicated IR context field 加入 canonical path？
- v0 reference 中的 map storage 应使用 `near_sdk::collections::LookupMap`，还是保持 raw `env::storage_read`/`env::storage_write`，作为 `EmitWat` 必须复现的文档化语义？
