# Wasm 家族目标

Wasm 家族包括 NEAR、CosmWasm、Stellar/Soroban、Internet Computer canisters，以及后续 Polkadot/ink 风格合约。它们共享一种可执行格式，但合约 ABI 并不相同。ProofForge 只应共享真正通用的部分。

## Spike 诚实性 (U7)

- **NEAR (`wasm-near`)** 是主要 Wasm 产品 host（Experimental）。
- **CosmWasm：**portable remote 使用 WasmMsg 形状的 `execute_msg` **stub**；
  Gate G1a（M3/M4）**未开始**。
- **Soroban：**Counter MVP host adapter（`PF-P3-02` six-gate）；在真实 Env auth
  落地前，interpreter auth 始终授权。
- **Cloudflare Workers：**仅用于 research / off-chain。

## 通用形态

规范的 Wasm-family backend 是 **`EmitWat`**，它参考的是仓库内 portable-IR → Yul renderer `ProofForge/Backend/Evm/IR.lean`（所有 `--emit-*-ir-yul` CLI mode 使用的路径），而不是单独的 LCNF-based `Compiler/LCNF/EmitYul.lean`。`Backend/Evm/IR.lean` 将 portable IR（`Module`/`Entrypoint`/`Statement`/`Expr`）lower 到 `Yul.AST`，再由 `Printer` 渲染为 Yul 文本，最后交给 `solc` 编译。`EmitWat` 做同样的事情，只是目标变为 WAT：portable IR → `Wasm.AST` → WAT text → `wat2wasm`。

因为 portable IR 已经抽象掉 Lean 对象（只有 `u32`/`u64`/`bool`/`hash` 标量、storage maps 和 effects，没有 closures、没有 arbitrary recursion、没有 Lean runtime objects），`EmitWat` **不需要 Lean runtime port、不需要 object-model boxing、不需要 GC**。这是它相对 Rust sourcegen（耦合 `near-sdk` macros）和早期 `EmitZig` 计划（需要把完整 Lean runtime 移植到 Wasm）的关键优势（[D-031](../decisions.zh.md)）。

```text
Portable IR (Module)
  -> EmitWat              (shared: portable IR -> Wasm AST, mirroring Backend/Evm/IR.lean)
  -> Wasm AST             (shared: Compiler/Wasm/AST.lean, like Compiler/Yul/AST.lean)
  -> WAT text             (shared: Compiler/Wasm/Printer.lean, like Yul/Printer.lean)
  -> wat2wasm / wabt      (shared toolchain)
  -> Wasm artifact        (imports the per-chain host functions)
  -> target-specific validation
```

**共享层（整个家族只写一次）：**

- `Compiler/Wasm/AST.lean` + `Compiler/Wasm/Printer.lean`：Wasm/WAT AST 和 printer，对应 `Compiler/Yul/AST.lean` + `Yul/Printer.lean`。
- portable-IR → Wasm-AST lowering 骨架（capabilities、type inference、statement/expression lowering），复用 `Backend/WasmHost/IR.lean`（Rust v0）和 `Backend/Evm/IR.lean` 已验证过的 validation logic。
- WAT module scaffolding：memory、type/import/export sections、`wat2wasm` invocation 和 artifact metadata。

**按链区分的层（NEAR / CosmWasm / Soroban / ICP 之间真正不同的部分）：**

- Host-import table：IR storage/crypto/context effects lower 到哪些 Wasm imports（NEAR `env.storage_*`、CosmWasm `db.read`/`db.write`、Soroban host functions 等）。
- **ABI serialization**：参数和返回值的序列化（NEAR JSON/Borsh、CosmWasm JSON 等），这是最麻烦的按链问题，也是主要 spike risk。
- Exported entrypoint names 和 deployment packaging。

共享/按链拆分是整个设计的核心：Wasm AST、lowering 和 `wat2wasm` 在家族内一致；只有 host imports 和 ABI 不同。

## 旧路径

- **`EmitZig`**（早期 canonical plan）：`Lean → EmitZig → Zig → host bridge → Wasm`。它需要把完整 Lean runtime 移植到 Wasm（libuv/threads/GC），这是已记录的 blocker，因此被 `EmitWat` 取代。
- **Rust / CDK sourcegen**（例如 NEAR `near-sdk-rs`）：`Portable IR → Rust package → cargo wasm32`。只保留为**冻结的 v0 stopgap**，用于验证链语义；不再扩展。参见 [Wasm-NEAR 目标](wasm-near.zh.md)。它的 IR-lowering/validation logic 可被 `EmitWat` 复用；丢弃的只是 emission target（Rust strings）。

## NEAR

完整实现设计见 [Wasm-NEAR 目标](wasm-near.zh.md)。

- **Canonical path：** `Portable IR → EmitWat → Wasm AST → WAT → wat2wasm → Wasm`，NEAR host bridge 将 portable IR effects lower 到 `env.storage_*` / `env.sha256` / `env.predecessor_account_id` / `env.block_height` / `env.log` imports。
- **冻结的 v0 stopgap（仓库内，可编译）：** Rust `near-sdk-rs` sourcegen，经由 `ProofForge/Backend/WasmHost/IR.lean`。它现在验证 NEAR 语义，但不再扩展。canonical path 的关键风险是 NEAR 参数（反）序列化（JSON/Borsh），这是 EVM backend 不会遇到的（EVM 使用 calldata）。

移植前的设计清理：

- 不要在 generic EmitZig extern lists 中保留 `lean_near_*` declarations。
- 不要为每个 Wasm target 强制链接 NEAR host code。
- 将 method metadata 移入统一的 target manifest。

## CosmWasm

CosmWasm 也是 Wasm，但 ABI 是 message-oriented。

预期 exports：

- `interface_version_8`
- `allocate`
- `deallocate`
- `instantiate`
- `execute`
- `query`
- 后续：`migrate`, `reply`, `sudo`, `ibc_channel_open`,
  `ibc_channel_connect`, `ibc_channel_close`, `ibc_packet_receive`,
  `ibc_packet_ack`, `ibc_packet_timeout`

预期 imports 包括 storage、address、crypto、debug 和 chain query host functions。实现开始时应从支持的 CosmWasm VM 版本取得精确 imports。

第一版 adapter 行为：

- 将 messages 保持为 JSON strings。
- 返回 JSON responses。
- 将 events 表示为 attributes。
- 先使用 string-keyed storage。
- 后续再增加 typed schema generation。

## Stellar/Soroban

Stellar smart contracts 也是 Wasm artifacts，但 Soroban 有自己的 SDK、host environment、storage lifecycle、authorization model、deployment flow 和 CLI tooling。

候选 target id：`wasm-stellar-soroban`。

当前 native path：

```text
Rust + soroban-sdk
  -> stellar contract build
  -> wasm32v1-none Wasm
  -> stellar contract deploy / invoke
```

目标特有问题：

- build flow 使用 Rust 和 Stellar CLI，而不是 `cosmwasm-check`；
- storage 区分 instance、persistent 和 temporary entries，并带 TTL 与 archival behavior；
- authorization 是显式的、address-based 的 `require_auth` 风格调用，不只是 sender read；
- contract accounts 可以实现 custom authorization；
- contract interface/spec metadata 是 developer workflow 的一部分；
- deployment 将 Wasm upload/install 与 contract instantiation 分开。

第一版 ProofForge spike 可以先生成或包装 native Soroban package，再尝试 direct Lean-to-Wasm host bridge。参见 [Stellar Soroban 目标](stellar-soroban.zh.md)。

## Internet Computer Canisters

Internet Computer canisters 是 Wasm modules 加 persistent canister state 和 Candid interfaces。它们有自己的 message model、lifecycle、cycles accounting、stable memory 和 management canister APIs。

候选 target id：`wasm-icp-canister`。

当前 native paths：

```text
Motoko or Rust CDK
  -> Wasm canister module
  -> Candid .did interface
  -> local replica / PocketIC / ICP CLI validation
```

目标特有问题：

- update、query 和 composite query methods 的语义不同；
- Candid service metadata 是 public contract interface 的一部分；
- caller 和 canister identities 是 principals；
- persistent state 可能依赖 canister memory、stable memory 或 CDK-managed stable structures；
- inter-canister calls 是 asynchronous message flows；
- cycles 是 resource-accounting unit，不是普通 native value；
- deployment 和 upgrades 通过 canister lifecycle 与 management canister APIs。

第一版 ProofForge spike 可以先生成或包装 native Motoko/Rust CDK canister，再尝试 direct Lean-to-Wasm canister bridge。参见 [Internet Computer 目标](internet-computer.zh.md)。

## Runtime Profile

因为 `EmitWat` lower 的是 **portable IR**（不是 Lean LCNF），这里根本没有 Lean runtime 要移植。IR 只有 `u32`/`u64`/`bool`/`hash` 标量和 storage effects，可直接映射到 Wasm `i32`/`i64` values 和 host-import calls。剩余目标问题真实存在，但按 target 选择：

- threads：无（single-threaded，每次调用原子执行）
- POSIX filesystem / process environment / libuv：无
- native GMP：无（hash 是固定 4×u64 limb tuple，直接 lower）
- chain-agnostic host bridge force-linking：无

| Option | NEAR | CosmWasm | Stellar/Soroban | ICP canister |
|---|---|---|---|---|
| Scalar lowering | shared `EmitWat` (IR u32/u64/bool/hash → Wasm i32/i64) | shared | shared | shared |
| Hash lowering | shared `EmitWat` (4×u64 tuple in linear memory) | shared | shared | shared |
| Host bridge | `near` (`env.*`) | `cosmwasm` (`db.*`) | `stellar-soroban` | `icp-canister` |
| Args ABI | JSON / Borsh | JSON | Soroban XDR / native | Candid |
| Validation | NEAR VM/MVP checks | `cosmwasm-check` | Stellar CLI or sandbox | Local replica, PocketIC, or ICP CLI |

## CosmWasm Counter Spike

最小 Lean surface：

```lean
namespace CosmWasm

opaque inputJson : IO String
opaque storageRead : String -> IO (Option String)
opaque storageWrite : String -> String -> IO Unit
opaque storageRemove : String -> IO Unit
opaque returnJson : String -> IO Unit
opaque logAttribute : String -> String -> IO Unit
opaque queryChain : String -> IO String

end CosmWasm
```

预期用户合约形态：

```lean
def instantiate : CosmWasm.Entrypoint := do
  CosmWasm.storageWrite "count" "0"
  CosmWasm.returnJson "{\"ok\":true}"

def execute : CosmWasm.Entrypoint := do
  let msg <- CosmWasm.inputJson
  if msg == "{\"increment\":{}}" then
    ...

def query : CosmWasm.Entrypoint := do
  ...
```

验收标准：

- Wasm exports all required functions。
- `cosmwasm-check` accepts the artifact。
- Counter can instantiate, increment, and query。
- Artifact metadata records `target: wasm-cosmwasm`。

## 待解决问题

- **[NEAR spike gate]** NEAR 参数（反）序列化（JSON/Borsh）能否在 `EmitWat` 下干净 lowering？这是最高风险未知项，必须在扩大 lowering 覆盖前先 de-risk。
- `EmitWat` 应发射 WAT text（→ `wat2wasm`）还是直接发射 Wasm binary？默认是 WAT text（对齐 `Backend/Evm/IR.lean` → Yul text → `solc`）；binary 是后续用于移除 `wabt` 依赖的优化。
- `Backend/WasmHost/IR.lean`（Rust v0）和 `Backend/Evm/IR.lean` 中有多少 IR-lowering / validation logic 可以共享？
- CosmWasm 应通过 `wasm32-freestanding` 编译，还是走带 import stripping 的 WASI 路径？
- Schema generation（CosmWasm JSON schema、Soroban spec、ICP `.did`）应来自 Lean types 还是 separate manifest？
- Soroban / ICP 是否应先走 native Rust/Motoko package sourcegen，再做 direct `EmitWat` host bridge？
