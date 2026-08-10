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
                 scripts/pf_solana_local_demo.sh (Surfpool)
                                               |
 Browser UI (wallet-adapter + web3.js)  <------ deployment.json + IDL
```

| 层 | 谁 | 密钥 |
|---|---|---|
| 写合约 | ProofForge 语言 + `pf` / `proof-forge-next` | 无 |
| 编译 | `pf build --target solana` | 无 |
| 本地测 | `pf verify` / `pf test`（Mollusk） | 无 / 本机 |
| 本地部署 + invoke | `scripts/pf_solana_local_demo.sh`（Surfpool） | 本机 keypair |
| dApp UX | `templates/solana-dapp-ui` + 钱包 | **钱包**（entry/view） |
| 公网写 | **pf v0 拒绝** | — |

官方 Solana Developer MCP（Rust/Anchor autofixer）**不是**本产品的合约写作路径；PF MCP 只摘要 PF 需要的 ix 编码 / 产物 / CLI 知识。

## 2. PF 产物（StateCell 形）

`pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o <dir>`：

| 文件 | 前端是否需要 |
|---|---|
| `StateCell.idl.json` | **是** — name / mode / accounts / handlerId（CPI 分支才用 handlerId） |
| `StateCell.so` | 否（CLI deploy） |
| `StateCell.s` | 否 |
| `manifest.json` / `evidence.json` | 可选审计 |
| `*.cpi-*.json` | 否（工程中间态） |

## 3. Instruction data（必须钉死 · 分 profile）

PF sBPF **不是** Anchor sighash。编码按 **build profile** 分支：

### 3.1 body-only S1b（StateCell / `pf new` 默认）

```text
ix data = sha256("proof-forge-solana-v1:" ++ discName ++ "(" ++ types ++ ")")[0:8]
          || u64le(param0) || u64le(param1) || …

types = "u64" * n joined by ","
discName(init) = "initialize"   # IDL name may still be "init"
```

Known StateCell discriminators (hex LE bytes):

| ix | disc name | first 8 hex |
|---|---|---|
| init | `initialize(u64)` | `5e494767a7582864` |
| increment | `increment(u64)` | `9dc79703d1db3e22` |
| get | `get()` | `a4a276b0d690dd37` |

Account metas (StateCell):

| ix | state.is_signer | state.is_writable |
|---|---|---|
| init | **true** | true |
| increment | false | true |
| get | false | false |

Browser wallets usually **cannot** sign an arbitrary state keypair → run init via
`scripts/pf_solana_local_demo.sh` / `pf_solana_statecell_invoke.py`, then use the UI for entry/view.

### 3.2 CPI-product（TransferSol 等）

```text
ix data = u64le(handlerId) || u64le(param0) || …
```

- `handlerId` 来自 IDL `instructions[].handlerId`
- 模板默认 UI 走 body-only；CPI 路径按 manifest/profile 分支，见 MCP `pf_solana_ix_codec`

### 3.3 错误示范

- 对 body-only ELF 使用 `handlerId`
- 对 PF ELF 使用 Anchor `sha256("global:increment")[..8]`
- 把两种 layout 混成一个全局规则

模板：`templates/solana-dapp-ui/src/ix.ts` → `encodePfIxData`（body-only）

## 4. State account layout（StateCell ordinary）

16 bytes：

```text
offset 0: layout marker u64 LE  (non-zero when initialized)
offset 8: count u64 LE
```

UI：`readStateCellCount` 读 offset 8（**不是** offset 0）。

## 5. 一键本地 demo（推荐）

```bash
# needs: surfpool 1.x on PATH (~/.local/bin), solana CLI, solders venv optional
just pf-solana-local-demo
# or:
bash scripts/pf_solana_local_demo.sh

# leaves Surfpool up by default; tear down:
just solana-surfpool-down
```

Writes:

- `templates/solana-dapp-ui/public/deployment.json`
- `templates/solana-dapp-ui/public/artifacts/StateCell.idl.json`

Then:

```bash
cd templates/solana-dapp-ui && npm install && npm run dev
```

## 6. Agent 剧本（前端）

| 步 | 动作 |
|---|---|
| F0 | MCP `pf_solana_scaffold` / `pf_chain_catalog target=solana` |
| F1 | **用 PF 语言**写/改合约（不要新建 Anchor 工程） |
| F2 | `pf build -t solana` → 复制 `*.idl.json` |
| F3 | `pf verify` / `pf test` |
| F4 | `just pf-solana-local-demo`（Surfpool deploy + init）→ `deployment.json` |
| F5 | 起 `templates/solana-dapp-ui` · 钱包连本地 Surfpool RPC |
| F6 | 禁止默认连 mainnet/devnet 热路径 |

## 7. 安全

- 无私钥进前端仓库 / MCP 参数  
- pf v0 **拒绝** public Solana RPC broadcast  
- Principal wire ≠ Solana pubkey 全局等价  
- 工程 demo ≠ formal/mainnet evidence  

## Related

- `templates/solana-dapp-ui/`  
- `scripts/pf_solana_local_demo.sh`  
- `docs/product/09-solana-agent-playbook.md`  
- `docs/targets/02-solana.md`  
