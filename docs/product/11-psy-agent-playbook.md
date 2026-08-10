---
id: PRODUCT-PSY-AGENT-PLAYBOOK
title: Psy agent playbook — ProofForge DPN + official Psy toolchain
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Psy agent playbook（ProofForge DPN 主路径）

**Audience:** coding agents + developers  
**Claims:** engineering guidance only — **not** formal / hermetic / mainnet deploy from PF

## 一句话

用 **ProofForge 语言 + `pf` CLI** 把 `ProgramV1` **编译成 canonical DPN package**（`*.dpn.json`）。  
链上部署、prove、钱包、前端 **走 Psy 官方工具**（`psyup` / `dargo` / `psy_user_cli` / `@psy-protocol/psy-sdk` / wallet / WebIDE）。  
**不要**把 Dargo/Psy-lang 手写脚手架当成 PF 合约主路径；也 **不要**假装 PF 已内置 Psy network broadcast。

## 官方入口（生态，非 PF 发货）

| 面 | URL | 用途 |
|---|---|---|
| Docs | https://docs.psy-protocol.xyz · https://psy.xyz/docs | 协议 / 语言 / SDK / VM / RPC |
| App / Bridge | https://app.psy-protocol.xyz | 支付 / bridge / UX |
| Wallet | https://app.psy-protocol.xyz/#/wallet · https://app.psy-protocol.xyz/wallet | 用户密钥 / 签名 / claim |
| Explorer | https://explorer.psy-protocol.xyz | 区块 / 交易 / 合约观察 |
| WebIDE | https://ide.psy-protocol.xyz | 浏览器写 Psy-lang · compile · 交互 |
| Config | https://config.psy-protocol.xyz · `…/config.json` | 公共 RPC / L1 Sepolia / 合约地址 |
| GitHub | https://github.com/PsyProtocol · psy-sdk / psy-compiler / psy-node / psy-template | 源码与模板 |
| Toolchain installer | https://github.com/QEDProtocol/psyup | `psyup` 安装 dargo / psy_user_cli 等 |

Release config snapshot（2026-07-20 公开面，**会变** — 以 `config.json` 为准）：

| Key | Value |
|---|---|
| L1 | Ethereum Sepolia (`chain_id=11155111`) |
| coordinator_rpc | `https://coordinator.psy-protocol.xyz` |
| realm_rpcs | `https://realm0.psy-protocol.xyz`, `https://realm1.psy-protocol.xyz` |
| prove_proxy | `https://prove.psy-protocol.xyz` |
| indexer | `https://indexer.psy-protocol.xyz/v1/graphql` |

## 唯一推荐 MCP

| Server | Endpoint |
|---|---|
| **ProofForge remote MCP** | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` |

Psy tools：

| Tool | 作用 |
|---|---|
| `pf_psy_scaffold` | PF ladder + 官方 toolchain 边界 |
| `pf_psy_artifacts` | `*.dpn.json` 产物说明 |
| `pf_psy_ecosystem` | 官方站点 / SDK / wallet / config 摘要 |
| `pf_target_info` / `pf_cli_cheatsheet` | `target=psy` |
| `pf_get_doc` | `11-…` / `12-…` / demo walkthrough |

## 分工（必须钉死）

```text
ProgramV1 (Lean)
    │  pf build --target psy
    ▼
{name}.dpn.json   ← ProofForge sole product artifact (deployable=false)
    │
    │  hand-off (human / agent on developer machine)
    ▼
Official Psy toolchain
    dargo / psyup build   (Psy-lang source projects)
    psyup deploy / psy_user_cli
    @psy-protocol/psy-sdk + psy-wallet / WebIDE
    explorer / coordinator / realm RPC
```

| 层 | 谁 | PF 是否发货 |
|---|---|---|
| 写 PF 合约 · 出 DPN | `pf` / `proof-forge-next` | **是** |
| Psy-lang 源工程 · ABI | `dargo` / `psyup` / WebIDE | 否（官方） |
| 部署 / 调用 CLI | `psyup deploy` · `psy_user_cli` | 否 |
| 浏览器钱包 | psy-wallet · `window.psy` | 否 |
| TS SDK | `@psy-protocol/psy-sdk` · `contract-sdk` | 否 |
| 本地全节点集群 | `psy-node` | 否 |

**诚实边界：**

- PF profile **仅** `psy-dpn-v1`；`deployable=false`；zero-tool finalize。  
- 旧 Dargo/source/VM/proof product lane **已删除**（ADR-0035 / C-2）。  
- DPN 可被官方 VM schema 消费的权威 pin 见 `supply-chain/psy-node-dpn-authority.v1.json` — **不是** Tool Lock 可执行物。  
- **没有** PF→testnet 一键 deploy；不要在 MCP 默认面持有 Psy 私钥或 broadcast。

## 本地 `pf` ladder（DPN only）

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"

pf setup --target psy      # zero-tool: doctor ok with empty tool set
pf doctor --target psy

pf new hello --target psy && cd hello
# edit Lean ProgramV1 — not Dargo.toml / .psy as PF source of truth
pf build
# monorepo:
# pf build Examples/StateCell.lean --module Examples.StateCell --target psy -o build/v2/sc-psy

ls *.dpn.json manifest.json evidence.json
pf inspect --output-dir .
python3 scripts/psy_dpn_to_abi.py --dpn *.dpn.json -o StateCell.abi.json


> **Session continuity:** `psy_user_cli simulate` is **one call per process** (fresh memory).
> For `init(7) → increment(5) → get = 12`, use `scripts/psy_dpn_session.py` / `pf test -t psy`
> (shared-state harness). Do not expect three separate simulates to accumulate.

# Local DPN VM (official psy_user_cli simulate — host tool)
export PATH="$HOME/.psy/bin:$PATH"
pf test -t psy
pf run -t psy -- initialize 7
# multi-call session is NOT preserved across simulates (fresh memory each call)
```

StateCell 示例 method_id（DPN，算法钉死；重建可能变若 schema pin 变）：

| method | method_id (u32) |
|---|---|
| get | 1459926901 |
| increment | 1990357658 |
| initialize | 202172507 |

## 官方 toolchain（部署 / dApp — 开发者本机）

```bash
# Installer (public docs; network name follows psyup release — often sepolia config)
curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh \
  | PSYUP_DEFAULT_NETWORK=sepolia sh
psyup install   # dargo, psy_user_cli, …

# Optional official scaffold (Psy-lang, not PF Lean)
psyup new my-app
cd my-app/contract && psyup build

# Deploy is official CLI — NOT pf deploy
# psyup init && export KEYSTORE_PATH=$HOME/.psy/keystore/default
# psyup deploy
```

浏览器路径：

1. https://ide.psy-protocol.xyz — 写/编译 Psy-lang  
2. https://app.psy-protocol.xyz/#/wallet — 钱包  
3. https://explorer.psy-protocol.xyz — 观察  

## Frontend 包（生态）

| Package | 角色 |
|---|---|
| `@psy-protocol/psy-sdk` | RPC · wallet provider · local web prover/compiler |
| `@psy-protocol/contract-sdk` | ABI codegen / typed contract runtime |
| `@psy-protocol/utils` | 共享工具 |

模板注入：`window.psy.requestAccounts` / `sendTransaction`（见官方 `psy-template`）。


## Deploy (official CLI wrapped by `pf`)

```bash
pf build -t psy -o build/v2/sc-psy
# save-only: materialize deploy_cmd.json via psy_user_cli deploy-contract (no --is-deploy)
pf deploy -t psy --artifact build/v2/sc-psy --network local

# broadcast (needs funded key + live coordinator)
# local cluster:
pf deploy -t psy --artifact build/v2/sc-psy --network local --broadcast --private-key-env PF_PSY_KEY
# public staging/testnet (sepolia config in ~/.psy/config.json):
pf deploy -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY
# after deploy: tx/deployment.json has contractId
pf execute -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY -- initialize 7
pf execute -t psy --artifact build/v2/sc-psy --network testnet --broadcast --private-key-env PF_PSY_KEY -- increment 5
```

`pf` only shells to `psy_user_cli deploy-contract`. Mainnet refused.
Probe chain: `bash scripts/psy_local_chain_status.sh`


### Funding note (call vs deploy)

- `pf deploy --broadcast` may succeed with **zero L2 balance**.
- `pf execute` / `psy_user_cli call` burns **GUTA + DA fees** (~1e9 native units observed on staging).
- If you see `insufficient balance (left: 0, right: 1)`: fund via
  [Psy app / faucet / bridge](https://app.psy-protocol.xyz) for the registered user, then retry.
- Check leaf: `psy_user_cli get-user-leaf --user-id <id> --rpc-config <sepolia-config>`.

## Honesty

- engineering DPN emission ≠ execution / UPS / proof / network settlement  
- Principal / identity model ≠ EVM address 全局等价  
- Never paste private keys into chat / MCP / git  
- Config endpoints drift — always refresh `config.psy-protocol.xyz/config.json`

## Frontend template

[`templates/psy-dapp-ui`](../../templates/psy-dapp-ui/) — copy `deployment.json` + `*.abi.json`, `npm run dev`, connect official wallet.

## Related

- [`12-psy-dapp-frontend.md`](12-psy-dapp-frontend.md)  
- [`../demos/psy-dpn-walkthrough.md`](../demos/psy-dpn-walkthrough.md)  
- [`../targets/10-psy.md`](../targets/10-psy.md)  
- [`../targets/10-psy-dpn-lowering.md`](../targets/10-psy-dpn-lowering.md)  
