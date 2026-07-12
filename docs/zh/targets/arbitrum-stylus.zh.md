# Arbitrum Stylus 目标

## 状态

`wasm-arbitrum-stylus` 当前是 **research** `contract_source` 目标。它已加入目标
注册表、`--list-targets` 和 CLI build 路由，但不属于主三目标。公开路由生成固定
版本的 Rust SDK source bundle 和 intermediate Wasm metadata，不声明可部署产物。

## 分类

Stylus 合约是以 Ethereum 合约语义执行的 Wasm 程序。由于部署产物是 Wasm，
ProofForge 将其归入 `wasmHost` family；但它不得复用 NEAR/Soroban ABI 或字符串
键存储计划。

目标拥有独立 `StylusPlan`，包含 Solidity ABI、EVM 兼容 256 位 slot 与 32 字节
storage word、EVM event/call、Stylus HostIO、cache flush、gas/ink 和 artifact metadata。

## 最终流水线

```text
Canonical Contract
  -> Stylus capability validation
  -> StylusPlan
       |-> Rust SDK renderer -> cargo stylus -> Wasm
       `-> Direct Wasm renderer -> Stylus HostIO Wasm
```

**Direct Wasm** 是最终 canonical renderer。**Rust SDK** renderer 是 bootstrap、
兼容路径和差分 oracle。两者只消费同一个不可变 plan，不得从源码或 legacy IR
重新推导合约语义。

## 工具链固定版本

- `stylus-sdk = "=0.10.8"`
- `cargo-stylus = "=0.10.8"`
- Rust `1.91.0`
- target `wasm32-unknown-unknown`

禁止版本范围、`latest` 和无界 git 依赖。升级版本必须重新生成 Rust/direct 差分证据。

## 与现有 Wasm Host 的语义差异

| 关注点 | Stylus | NEAR/Soroban 路径 |
|---|---|---|
| 公共 ABI | Solidity ABI 与四字节 selector | Borsh/JSON 或 Soroban spike ABI |
| 持久状态 | EVM State Trie、256 位 slot、32 字节 word | Host key-value binding |
| 写入生命周期 | cache word 后 flush | 目标特定的直接 host write |
| 事件 | 最多四个 EVM topic 加 data | 目标原生 log/event ABI |
| 调用 | EVM call mode 与返回数据缓冲区 | promise/invoke host model |
| 资源 | EVM gas 加 Stylus ink | 目标原生单位 |

可复用边界是 canonical IR、中立 Solidity ABI/storage planning、Wasm AST/printer、
artifact 和通用 refinement。Stylus backend 不得经过 `NearModulePlan`。

## 已实现与计划支持片段

1. Counter（research 实现）：`u64` scalar storage、ABI dispatch、checked arithmetic、
   cache flush、Direct WAT 编译和 abstract/direct 归一化 trace parity。
2. ValueVault：address、sender、value、block、授权和 payable。
3. Token：mapping、indexed event、allowance 和 EVM ABI 互操作。
4. RemoteCall：call mode、value/gas、return data、revert、reentrancy。
5. Aggregates：struct、array、bytes、string、动态 ABI 和 storage layout。

“任意合约”表示完整落在已实现 Stylus capability fragment 内的 canonical 合约。
不支持的操作必须在 artifact emission 前返回 target/function/operation 命名诊断。

## 晋级门槛

晋级到 research 以上仍要求 `cargo stylus check`、目标原生 direct `vm_hooks` 执行、
精确 ABI/storage 向量、完整可部署 artifact、Rust/direct runtime trace parity、资源
证据和静态 CI。Direct WAT 编译与 abstract trace parity 只是中间 gate。
Live RPC/deployment 保持可选。

仅通过 `cargo stylus check` 不等于 runtime 或 deployment 证据。

## 权威来源

- <https://github.com/OffchainLabs/stylus-sdk-rs>
- <https://github.com/OffchainLabs/cargo-stylus>
- <https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/stylus-sdk/src/hostio.rs>
- <https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/rust-toolchain.toml>

## 相关设计

- [混合 backend 设计](../../superpowers/specs/2026-07-12-arbitrum-stylus-hybrid-backend-design.md)
- [实施计划](../../superpowers/plans/2026-07-12-arbitrum-stylus-hybrid-backend.md)
- [Wasm family](wasm-family.zh.md)
- [EVM 目标](evm.zh.md)
