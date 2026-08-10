---
id: PRODUCT-CHAIN-CLIENT-CATALOG
title: Chain client / frontend catalog (metadata for agents)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# 多链客户端 / 前端 catalog（元数据）

状态：`draft`（2026-08-09）  
机器可读权威：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  
schema：`proof-forge.chain-client-catalog.v1`  
MCP：`pf_chain_catalog` · SDK：`ProofForgeClient.chain_catalog`

## 1. 目的

给 Code Agent / 作者回答：

- 某条链 **后端** 走 ProofForge 哪些入口（build / local / network）？
- **前端 / 客户端** 生态常见包是什么（**不由 PF 发货或 pin**）？
- 本机如何测、哪些诚实边界？

**不是** 第二编译器、不是钱包实现、不是 RPC 代理。

## 2. 字段（每 target）

| 字段 | 含义 |
|---|---|
| `id` | `TargetId` |
| `implemented` | registry implemented vs design-only |
| `maturityLabel` | 工程成熟度文案（非 formal） |
| `role` | `backend-contracts` / circuits / model / design-only |
| `pfSurface` | build/localModes/network/mcpTools/template |
| `frontendClients[]` | 生态客户端名；`shippedByProofForge=false` |
| `localDev` | offline interpret / chain-like engineering gates |
| `honesty[]` | 禁止升级话术 |

## 3. 后端 vs 前端

```text
                    ┌─────────────────────────────┐
  Agent / Author    │  ProofForge CLI / SDK / MCP │  后端合约编译与本机测
                    └─────────────┬───────────────┘
                                  │ artifacts (e.g. .aleo)
                                  ▼
                    ┌─────────────────────────────┐
  dApp UI (later)   │  Ecosystem chain client SDK │  前端 / 钱包 / RPC
                    └─────────────────────────────┘
```

Hello 后端剧本：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。

## 4. 查询

```bash
# MCP tool pf_chain_catalog  { "target": "aleo" } 或 { "includeDesignOnly": true }
# SDK:
python3 -I tools/sdk/proof_forge_sdk.py chain-catalog --target aleo
```

过滤：`target` 单 id；省略则返回全表 implemented（或 `includeDesignOnly`）。

## 5. 更新纪律

- 与 `TargetRegistryV1` **implemented 集合** 对齐；design-only 仅 catalog 展示
- 不把 resolver support 写成完整平台语义
- 不因 catalog 存在而改 `deployable`
- 生态 SDK 名称可演进；变更只改 JSON + 本页日期

## 6. 非目标

- 不安装前端 npm 包
- 不提供 mainnet endpoint 白名单（network 脚本另有 policy）
- 不 formal / Stage-0

## 7. Aleo frontend deep-dive

Aleo dApp 前端（Wallet Adapter · Provable SDK · 与 `pf` 产物对接）见：

[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)

Catalog JSON 的 `aleo.frontendClients` 列出具体 `@provablehq/aleo-wallet-adaptor-*` 与 `@provablehq/sdk` 包名；**仍不**由 PF 安装或 pin。

最小可运行 UI 模板：[`templates/aleo-dapp-ui/`](../../templates/aleo-dapp-ui/)。

## 8. EVM frontend deep-dive

EVM dApp 前端（viem / MetaMask / 本地 Anvil）见：

[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md) · 模板 [`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/)

