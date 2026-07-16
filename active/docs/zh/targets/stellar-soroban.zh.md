# Stellar Soroban 目标

状态：**Counter MVP（PF-P3-02 六门，2026-07-10）** — 注册 id `wasm-stellar-soroban`
已上线；产品 Counter 经 `EmitWat` + `HostBridge.soroban` 降级，`wat2wasm` 校验，
offline-host 生命周期（`just soroban-promotion`）。

**仍保留的 spike 诚实点：** `require_auth_for_args` always-auth；`invoke_contract`
桩；Stellar CLI / TTL 尚未进 promotion 门。主产品三元组仍是 EVM · Solana · NEAR。

候选 target id：**`wasm-stellar-soroban`**

英文权威文档：[../../targets/stellar-soroban.md](../../targets/stellar-soroban.md)

## 结论

Stellar/Soroban 应归入 Wasm-host 家族，但必须是独立目标，不能和 NEAR 或 CosmWasm 合并。

```text
Stellar smart contract 目标
  -> 当前主流是 Rust/Soroban SDK
  -> 编译为 wasm32v1-none Wasm
  -> 使用 Stellar host environment 和 Env API
  -> 通过 Stellar CLI build / deploy / invoke
```

这不是“通用 Wasm”。Wasm 只是制品格式；contract ABI、host function、storage、authorization、deployment、resource limits 和 tooling 都是 Stellar/Soroban 特有的。

## 对 ProofForge 的含义

`wasm-stellar-soroban` 已在 `ProofForge.Target.Registry` 中；Counter 六门证据见 `just soroban-promotion`。

目标特有问题包括：

- 当前原生路径是 Rust + `soroban-sdk` + Stellar CLI；
- `stellar contract build` 是最先要镜像的 build 命令；
- deploy 是上传/install Wasm 与实例化 contract id 的两步模型；
- storage 有 instance、persistent、temporary 形式，并带 TTL / archival 语义；
- authorization 通过 `require_auth` / `require_auth_for_args` 等显式地址授权表达；
- contract account 可以实现 `__check_auth()`；
- contract spec / interface metadata 是工具链和 bindings 的一部分。

## 候选能力

现有 Wasm-host 能力可覆盖一部分基础语义，例如 `storage.scalar`、`storage.map`、`events.emit`、`crosscall.invoke`、`env.block` 和 `crypto.hash`。

但以下能力应先作为候选项保留在文档中：

| 候选能力 | 含义 |
|---|---|
| `auth.require` | 合约要求地址级 authorization payload。 |
| `auth.account_contract` | contract account 通过目标原生账户逻辑验证授权。 |
| `storage.ttl` | 状态条目有 TTL extension、archival 和 restoration 语义。 |
| `artifact.contract_spec` | 构建输出包含 contract interface/spec metadata。 |
| `asset.stellar` | 使用 Stellar Asset Contract 或 token interface。 |

## 两条接入路线

1. **Native Soroban package sourcegen**：先生成或包装 Rust/Soroban SDK package，通过 Stellar CLI 构建。这个路线最保守，适合先验证目标语义。
2. **Direct Wasm host bridge**：Lean 直接降级到 Wasm + Stellar host bridge。这个路线更接近 NEAR/CosmWasm，但应等 Wasm runtime split 足够清楚后再做。

## 第一阶段非目标

- 不把 `wasm-stellar-soroban` 加入代码 registry。
- 不把 Soroban 和 `wasm-near` / `wasm-cosmwasm` 合并。
- 不把 Rust/Soroban SDK 细节当成 ProofForge 的长期 IR。
- 不忽略 storage TTL / archival 语义。
- 不把 authorization 简化成普通 `msg.sender`。
