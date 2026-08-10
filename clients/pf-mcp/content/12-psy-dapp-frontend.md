---
id: PRODUCT-PSY-DAPP-FRONTEND
title: Psy dApp frontend — wallet + SDK (FCCP companion)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Psy dApp 前端：Wallet · SDK · 与 ProofForge 的分工

状态：`draft`（2026-08-10）  
剧本：[`11-psy-agent-playbook.md`](11-psy-agent-playbook.md)  
Walkthrough：[`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)  
Target dossier：[`../targets/10-psy.md`](../targets/10-psy.md)

## 1. 核心原则

**合约语义用 ProofForge 写并物化为 DPN；链上交互用 Psy 官方钱包/SDK。**

```text
ProgramV1 --pf build -t psy-->  *.dpn.json (+ manifest)
                                      │
                    hand-off to official Psy stack
                                      │
 Browser / WebIDE / psy-wallet  <----- contract_id + ABI + SDK
```

ProofForge **不** vendor `@psy-protocol/*` npm 包，**不**在 MCP 默认面持私钥或广播。

## 2. PF 产物（StateCell 形）

```bash
pf build Examples/StateCell.lean --module Examples.StateCell --target psy -o <dir>
```

| 文件 | 前端/官方工具是否需要 |
|---|---|
| `StateCell.dpn.json` | **是** — canonical DPN package（method_id / definitions / state_commands） |
| `manifest.json` | 审计 / Agent inspect |
| `evidence.json` | 可选 |

`deployable=false`。没有 PF 生成的 `.psy` / Dargo 工程作为产品权威输出。

### DPN 形状（摘要）

每个 callable → `DPNFunctionCircuitDefinition`：

```text
name, method_id, circuit_inputs, circuit_outputs,
state_commands, state_command_resolution_indices,
assertions, definitions, events
```

Authority pin：`PsyProtocol/psy-node@79e0b824…`（schema only — 见 supply-chain annotation）。

## 3. 官方前端 / 钱包面

| 面 | URL |
|---|---|
| App | https://app.psy-protocol.xyz |
| Wallet | https://app.psy-protocol.xyz/#/wallet |
| Explorer | https://explorer.psy-protocol.xyz |
| WebIDE | https://ide.psy-protocol.xyz |
| Config JSON | https://config.psy-protocol.xyz/config.json |

### 3.1 浏览器扩展 / `window.psy`（官方模板）

```ts
// conceptual — follow current psy-template types
const accounts = await window.psy.requestAccounts()
const txId = await window.psy.sendTransaction(accounts[0], {
  contract_id: 7n,
  method_name: "increment",
  inputs: [5n],
})
```

- 密钥留在钱包；dApp 不持 private key。  
- 读路径可能需要公共 RPC / SDK `PsyUserWallet`（以官方模板 README 为准）。

### 3.2 npm 包

```bash
pnpm add @psy-protocol/psy-sdk @psy-protocol/contract-sdk
```

| 包 | 用途 |
|---|---|
| `@psy-protocol/psy-sdk` | coordinator/realm RPC · wallet · local web prover/compiler |
| `@psy-protocol/contract-sdk` | ABI → typed contract helpers |
| `@psy-protocol/utils` | 共享 |

子路径（以当前 package exports 为准）：`@psy-protocol/psy-sdk/local-web-compiler`、`…/local-web-prover`。

### 3.3 公共配置

```bash
curl -sS https://config.psy-protocol.xyz/config.json | jq '.services,.frontends,.l1'
```

L1 侧当前公开面为 **Sepolia** bridge 相关合约；Psy L2/realm 走 coordinator + realm RPCs。地址会变 — **禁止**把旧地址写死进 PF 仓库当权威。

## 4. 与 DPN / method_id 的衔接

1. `pf build -t psy` → 读 `*.dpn.json` 的 `name` + `method_id`。  
2. 官方部署成功后得到 `contract_id` / `contract_uuid`（`contract/.psy-deploy` 一类元数据 — 官方工具写出）。  
3. 前端调用用 **官方 ABI/SDK 形状**（`method_name` + `inputs: bigint[]`），不是 Solana discriminator，也不是 EVM calldata。  
4. PF **不**保证 DPN 可被某一版 `dargo` 直接“当源码导入”；hand-off 是 **schema-compatible package**，部署流水线以官方文档为准。若官方要求 `.psy` 源，则：
   - 用 WebIDE / `psyup new` 写官方合约，或  
   - 将 DPN 作为审计/对照物，而不是假装 PF 已生成可 `psyup deploy` 的完整 Dargo 工程。

## 5. Agent 剧本（前端）

| 步 | 动作 |
|---|---|
| P0 | MCP `pf_psy_scaffold` / `pf_chain_catalog target=psy` |
| P1 | PF 语言写合约 → `pf build -t psy` → 保留 `*.dpn.json` |
| P2 | 打开官方 docs / config；安装 `psyup`（开发者机） |
| P3 | WebIDE 或 `psyup new` 做官方交互原型 |
| P4 | wallet connect · 小额 test 调用 · explorer 核对 |
| P5 | **禁止**把私钥放进 MCP/git；**禁止**声称 PF 已 mainnet |

## 6. 安全

- 无私钥进前端仓库 / MCP 参数  
- PF v0 **无** Psy network broadcast 产品命令  
- UPS / local prove 在用户设备或官方 prover 路径 — 非 PF  
- engineering demo ≠ formal evidence  

## Related

- `docs/product/11-psy-agent-playbook.md`  
- `docs/demos/psy-dpn-walkthrough.md`  
- `docs/targets/10-psy-dpn-lowering.md`  
- https://github.com/PsyProtocol/psy-sdk  
- https://github.com/PsyProtocol/psy-template  
