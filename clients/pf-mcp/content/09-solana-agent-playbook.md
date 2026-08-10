---
id: PRODUCT-SOLANA-AGENT-PLAYBOOK
title: Solana agent playbook — ProofForge CLI/SDK first
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Solana agent playbook（ProofForge 主路径）

**Audience:** coding agents + developers  
**Claims:** engineering guidance only — **not** formal / hermetic / mainnet

## 一句话

用 **ProofForge 语言 + `pf` CLI（+ host SDK）** 写/编/测/部署 Solana 程序；  
前端用 **`templates/solana-dapp-ui`** 消费 `*.idl.json`。  
**不要**把「Solana 官方 Rust/Anchor MCP」当成写 PF 合约的入口。

## 唯一推荐 MCP

| Server | Endpoint | 用途 |
|---|---|---|
| **ProofForge remote MCP** | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` | catalog、CLI ladder、ix 编码摘要、前端模板指引 |

```bash
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp
```

PF MCP 工具（Solana）：

| Tool | 作用 |
|---|---|
| `pf_solana_scaffold` | setup → new → build → verify → test → deploy → UI |
| `pf_solana_ix_codec` | **摘要** PF ix-data 布局（handlerId u64 LE + params） |
| `pf_solana_artifacts` | build 产物清单 / 哪些给前端 |
| `pf_target_info` / `pf_cli_cheatsheet` | target=solana |
| `pf_get_doc` | `09-…` / `10-…` / demo walkthrough |

> 说明：官方 `https://mcp.solana.com/mcp` 面向 **Rust/Anchor/Pinocchio** 文档与 autofixer。  
> 与 PF Lean→sBPF 路径不同；本产品 **不在 agent 默认路径里推荐** 双 MCP。  
> 若维护者手写生态 Rust 适配层，可自行查阅 Solana 文档，但 **合约本体仍走 PF**。

## 本地 `pf` ladder

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"

pf setup --target solana
pf doctor --target solana

pf new hello --target solana && cd hello
# 编辑 src/*.lean（ProgramV1）— 不是 Cargo/Anchor 工程
pf build
pf verify
pf test
pf deploy --network local
# optional loopback only:
# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899
```

Monorepo example:

```bash
pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol
pf verify --target solana -o build/v2/sc-sol
cp build/v2/sc-sol/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/
```

## 前端

见 [`10-solana-dapp-frontend.md`](10-solana-dapp-frontend.md) · 模板 [`templates/solana-dapp-ui/`](../../templates/solana-dapp-ui/)。

## Install companions

| Binary | Purpose |
|---|---|
| `pf` (`proof-forge-pf`) | Developer CLI |
| `proof-forge-next` | Compiler |
| `proof-forge-solana-client` | `pf verify -t solana` |

## Honesty

- CPI/ELF engineering maturity — not mainnet-ready claim  
- Principal ≠ Solana pubkey globally  
- Public RPC broadcast refused in pf v0  
- Never paste private keys into chat / MCP / git  

## Related

- `docs/demos/solana-local-walkthrough.md`  
- `docs/targets/02-solana.md`  
- `docs/product/10-solana-dapp-frontend.md`  
