---
id: RPT-005
title: 后端、制品与工具链研究
status: draft
owner: research
updated: 2026-07-15
normative: false
---

# 后端、制品与工具链研究

状态：`draft`
研究日期：2026-07-15

## 问题

统一编译平台怎样既提供一致 CLI，又诚实呈现每个目标不同的制品、部署/证明流程和版本依赖？

## 后端协议结论

每个 materializer 必须保留关联类型，不能把 Plan 擦除成 `Unit`、JSON 或字符串：

```lean
class Materializer (target : TargetId) where
  Plan     : Type
  TargetIR : Type
  resolve  : SemanticProgram → CompileResult (ResolvedProgram target)
  plan     : ResolvedProgram target → CompileResult Plan
  lower    : Plan → CompileResult TargetIR
  emit     : TargetIR → IO (CompileResult OutputSet)
```

`resolve` 只证明目标支持 requirements；`plan` 固化目标 ABI/state/call/proof 决策；`lower` 负责机器表示；`emit` 负责确定性序列化和 manifest。任何阶段都不能重新解释业务语义。

## 制品契约

每次构建都输出 manifest，至少包含：

- schema、compiler build、source/semantic/plan/IR/artifact hash；
- `TargetId`、`CodegenProfile`、`NetworkProfile`；
- toolchain binary digest、dependency lock digest；
- outputs 的路径、媒体类型、用途和 deployability；
- requirements/support claim resolution；
- diagnostics、proof/verification status、reproducibility status。

circuit workload、zkVM workload 与 deployable contract 是制品角色，不是源码类别。wire
deployability 只使用 `ArtifactDeployability`；若没有 exact settlement adapter，Noir/OpenVM 的
proof/VK 至多为 `verifiable-workload`，CLI 不得包装成“已部署合约”。

## Phase 1 输出

| Target | Target-owned Plan | 主要输出 | 外部验证 |
|---|---|---|---|
| EVM | `EvmPlan` | ABI、Yul、init/runtime bytecode、manifest | EVM interpreter + Anvil |
| Solana | `SolanaPlan` | sBPF assembly/ELF、account schema、IDL、manifest | loader/static verifier + local runtime |
| NEAR | `NearPlan` | WAT/Wasm、JSON ABI/metadata、manifest | Wasm validation + NEAR sandbox |
| Noir | `NoirPlan` | `.nr`、ACIR/ABI、witness/proof/VK metadata | `nargo` + pinned backend prove/verify |

## Profile 分离

- `TargetId`：语义宿主，如 `near`。
- `CodegenProfile`：编译器、ABI、VM feature、proof backend 的精确版本组合。
- `NetworkProfile`：chain/genesis identity、endpoint、fee/deploy 限制和 RPC policy；
  protocol/fork 与会改变执行结果的资源计量属于 target semantics。

源码与 `TargetId` 相同不代表不同 profile 可互换。未锁版本、hash 不匹配或运行时 feature 缺失必须返回 `PF-TOOLCHAIN-MISMATCH`。

## 研究目标准入

- CosmWasm：固定 `wasmd/cosmwasm-vm`、entrypoint ABI、capabilities 和 transaction semantics。
- Soroban：固定 protocol、Wasm subset、XDR contract spec、resource/TTL rules。
- ICP：固定 interface spec、System API、Candid toolchain、cycles/resource model。
- OpenVM：从混合文档版本中选定一个完整 profile，并完成 guest build/keygen/prove/verify。
- Aleo：以 Leo 4.0 术语和精确版本实现，不接受旧 async/Future adapter。
- Psy：完成 compiler/deploy/prover/network 流程复现前不建 registry production entry。

## 安全与可重现性

- toolchain 只从 lockfile 和 allowlist 解析，禁止 PATH 中偶遇的旧二进制静默胜出。
- 外部进程使用参数数组、隔离工作目录、资源限制和输出大小限制。
- 输出排序、metadata timestamp、绝对路径和随机 seed 必须规范化。
- proof verification 必须绑定 semantic hash、program I/O schema、VM/config hash 和 verification key。

## 限制

本报告未冻结具体工具版本；该工作由 toolchain spec 和各 target dossier 的 implementation entry gate 完成。
