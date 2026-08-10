---
id: PRODUCT-SOLANA-DAPP-FRONTEND
title: Solana dApp frontend — wallet-adapter + PF IDL (not Anchor)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Solana dApp 前端：wallet-adapter · PF IDL · 与 ProofForge 的分工

状态：`draft`（2026-08-10）  
模板：[`templates/solana-dapp-ui/`](../../templates/solana-dapp-ui/)  
剧本：[`09-solana-agent-playbook.md`](09-solana-agent-playbook.md)  
Walkthrough：[`../demos/solana-local-walkthrough.md`](../demos/solana-local-walkthrough.md)

## 1. 核心原则

**合约用 ProofForge 写，不用 Solana 官方 Rust/Anchor 脚手架当主路径。**

```text
ProgramV1 (Lean)  --pf build -t solana-->  *.idl.json + *.so + manifest
                                              |
                         pf deploy --network local (CLI only)
                                              |
Browser UI (wallet-adapter + web3.js)  <------ deployment.json + IDL
```

| 层 | 谁 | 密钥 |
|---|---|---|
| 写合约 | ProofForge 语言 + `pf` / `proof-forge-next` | 无 |
| 编译 | `pf build --target solana` | 无 |
| 本地测 | `pf verify` / `pf test`（Mollusk） | 无 / 本机 |
| 本地部署 | `pf deploy --network local` | 本机 keypair |
| dApp UX | `templates/solana-dapp-ui` + 钱包 | **钱包** |
| 公网写 | **pf v0 拒绝** | — |

官方 Solana Developer MCP（Rust/Anchor autofixer）**不是**本产品的合约写作路径；PF MCP 只摘要 PF 需要的 ix 编码 / 产物 / CLI 知识。

## 2. PF 产物（StateCell 形）

`pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o <dir>`：

| 文件 | 前端是否需要 |
|---|---|
| `StateCell.idl.json` | **是** — handlerId / accounts / name |
| `StateCell.so` | 否（CLI deploy） |
| `StateCell.s` | 否 |
| `manifest.json` / `evidence.json` | 可选审计 |
| `*.cpi-*.json` | 否（工程中间态） |

## 3. Instruction data（必须钉死）

PF sBPF **不是** Anchor sighash：

```text
ix data = u64le(handlerId) || u64le(param0) || u64le(param1) || …
```

- `handlerId` 来自 IDL `instructions[].handlerId`（dense 0..n-1）
- 非 Principal 标量参数按 **u64 LE** 追加（窄整数零扩展）
- 模板：`templates/solana-dapp-ui/src/ix.ts` → `encodePfIxData`

错误示范：对 PF ELF 使用 Anchor `sha256("global:increment")[..8`。

## 4. 最小模板

```bash
pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o /tmp/sc-sol
cp /tmp/sc-sol/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/

# local validator + pf deploy --network local …
# write public/deployment.json from deployment.example.json

cd templates/solana-dapp-ui && npm install && npm run dev
```

## 5. Agent 剧本（前端）

| 步 | 动作 |
|---|---|
| F0 | MCP `pf_solana_scaffold` / `pf_chain_catalog target=solana` |
| F1 | **用 PF 语言**写/改合约（不要新建 Anchor 工程） |
| F2 | `pf build -t solana` → 复制 `*.idl.json` |
| F3 | `pf verify` / `pf test` |
| F4 | `pf deploy --network local` → 填 `deployment.json` |
| F5 | 起 `templates/solana-dapp-ui` · 钱包连本地 RPC |
| F6 | 禁止默认连 mainnet/devnet 热路径 |

## 6. 安全

- 无私钥进前端仓库 / MCP 参数  
- pf v0 **拒绝** public Solana RPC broadcast  
- Principal wire ≠ Solana pubkey 全局等价  
- 工程 demo ≠ formal/mainnet evidence  

## Related

- `templates/solana-dapp-ui/`  
- `docs/product/09-solana-agent-playbook.md`  
- `docs/targets/02-solana.md`  
