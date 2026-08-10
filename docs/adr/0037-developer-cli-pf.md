---
id: ADR-0037
title: Developer CLI `pf` separate from compiler CLI `proof-forge-next`
status: proposed
owner: product+engineering
updated: 2026-08-10
normative: true
---

# ADR-0037：Developer CLI `pf` 与 Compiler CLI 分离

## Status

`proposed`

## Context

ProofForge 已有 Lean 产品 CLI `proof-forge-next`（build/check/inspect/doctor/install）与
Python SDK/MCP 薄封装。Aleo Wave A/B/C 用 bash 验收脚本证明了：

- 官方 `leo abi` 可加载 PF Instructions；
- local VM 可通过 imports 字节钉扎解释 PF `.aleo`；
- testnet 可在 **exact twin** 前提下 `deploy/execute --save`（默认不广播）。

开发者需要 Anchor/Solana 式“一句话”本地跑与部署体验。若把 deploy/run 写进
`proof-forge-next`，会：

1. 把网络/签名/官方工具编排混入编译权威；
2. 与 ADR-0035（Aleo zero-tool finalize、`deployable=false`）和产品“默认不广播”冲突；
3. 强迫 Lean CLI 承担 spawn 生态工具、密钥策略与多链 DX 的职责。

Solana 侧已有先例：`clients/solana-client` 是 **独立 Rust 二进制**，只消费
`proof-forge.output.v1`，不重做编译器。

## Decision

1. **两层 CLI，永不合并权威**

   | 层 | 二进制 | 权威 |
   |---|---|---|
   | Compiler | `proof-forge-next` | ProgramV1 → target 物化；`proof-forge.output.v1` |
   | Developer | `pf` | 编排：setup/build/local/network UX；wrap 官方工具 |

2. **`pf` 用 Rust 实现**，放在 `clients/pf-cli/`（与 `solana-client` 同 clients 树）。
   **不** 做 Python 过渡实现；Python SDK/MCP 继续只服务 Agent/脚本，不是 Developer CLI。

3. **`pf` 永不重新解释 ProgramV1 语义**。`pf build` 只 spawn `proof-forge-next`；
   链侧操作只消费 OutputSet + 官方工具。

4. **TargetAdapter 接口**：Aleo 第一实现；EVM/Solana 后接同一命令面，不得复制第二套 CLI。

5. **安全默认**

   - `deploy` / `execute` 默认 **save-only**（不 `--broadcast`）；
   - `mainnet` 拒绝或要求显式破坏性确认（第一期直接拒绝）；
   - 私钥只来自 flag/env，永不写入 manifest / 日志明文；
   - 成功不改写 compiler 的 `deployable=false`。

6. **Aleo 路径绑定已验证不变量**（Wave A/B/C）

   - local：PF `.aleo` → runner `build/imports` 字节钉扎 → `leo run`；
   - network packaging：Leo twin 与 PF Instructions **exact match**（program id 改写后）→
     `leo deploy/execute`；
   - acceptance scripts 仍是 CI 真源；`pf` 提供 UX，行为不得弱于 scripts。

7. **Compiler CLI 保持现状**：`proof-forge-next local/network` 对 Aleo 继续 fail closed；
   开发者网络面只在 `pf`。

## Consequences

- 新增 crate `proof-forge-pf`（bin `pf`）与 SPEC `docs/specs/cli-developer.md`。
- 分发：`pf` 与 `proof-forge-next` 可并排；`PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT` 继承现契约。
- bash `scripts/aleo_instructions_*.sh` 保留为 gate；逐步改为调用 `pf` 或共享 Rust 库逻辑。
- 不恢复 Aleo Leo source 为产品 materializer（ADR-0035 仍有效）。

## Non-claims

- `pf` 成功 ≠ formal / hermetic / mainnet / Stage-0。
- `pf deploy` save-only ≠ 链上 inclusion。
- EVM/Solana **公共网** deploy 仍非目标；local save/broadcast 已由 D11 接入。
- crates.io 仅发布 orchestrator crate `proof-forge-pf`（bin `pf`）；`proof-forge-next` 不走 crates.io。

## Alternatives rejected

| 方案 | 拒绝理由 |
|---|---|
| 把 deploy 做进 `proof-forge-next` | 污染编译权威；与 zero-tool finalize 冲突 |
| Python 主 CLI | 分发与和 solana-client 栈分裂；用户明确要求 Rust |
| 每链一个无关 CLI | 命令面分裂；违反“一份 program 多 target”产品叙事 |
| 重写 Leo/snark 客户端 | 供应链与正确性成本过高；wrap 官方工具即可 |