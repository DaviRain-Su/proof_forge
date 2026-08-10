---
id: PRODUCT-XLAYER-ONCHAINOS
title: X Layer networks + OKX OnchainOS integration (catalog / MCP / roadmap)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# X Layer · OnchainOS · ProofForge

状态：`draft`（2026-08-10）  
机器可读网络表：[`networks.v1.json`](networks.v1.json)（schema `proof-forge.network-catalog.v1`）  
链客户端 catalog：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  
EVM 前端：[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md) · [`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/)  
官方 X Layer： [about](https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer) · [network info](https://web3.okx.com/zh-hans/onchainos/dev-docs/xlayer/developer/build-on-xlayer/network-information)  
OnchainOS 总览： [what-is-onchainos](https://web3.okx.com/zh-hans/onchainos/dev-docs/home/what-is-onchainos)  
Build X 黑客松： [build-x-series](https://web3.okx.com/zh-hans/xlayer/build-x-series)

## 1. 目的

给作者 / Code Agent 固定：

1. **X Layer** 主网 / 测试网参数（chainId、RPC、explorer、OKB gas）
2. **OnchainOS** 能力地图（钱包 · 交易 · 行情 · 支付）与 **官方 MCP**
3. 与 ProofForge 的 **分工** 与 **P0–P2 路线**（产品决策未定时仍可开发）

**不是** 第二编译器、不是钱包实现、不是默认 public broadcast。

## 2. 网络速查

| id | env | chainId | gas | policy |
|---|---|---|---|---|
| `evm.local.anvil` | local | 31337 | ETH | `local-only`（默认 demo） |
| `evm.xlayer.testnet` | testnet | **1952** | **OKB** | `testnet-opt-in` |
| `evm.xlayer.mainnet` | mainnet | **196** | **OKB** | `mainnet-gated` |
| `evm.ethereum.sepolia` | testnet | 11155111 | ETH | `metadata-only`（占位） |

权威字段与 RPC 列表见 [`networks.v1.json`](networks.v1.json)。

### X Layer 要点

- **全 EVM 等效** → ProofForge `--target evm` 产物（Yul / solc bytecode / ABI）可部署，无需改 materializer 语义。
- 架构：OP Stack 乐观 Rollup + AggLayer（见官方 about 页）。
- Gas：**OKB**（不是 ETH）。
- 黑客松：期间 **testnet**；之后 **mainnet**。

## 3. 架构边界

```text
Author / Agent
    │
    ├─ ProofForge (pf / proof-forge-next / PF MCP)
    │     program → build --target evm → abi + bytecode + manifest
    │     catalog: networks · chain-client · docs
    │     local: Anvil differential / templates/evm-dapp-ui
    │     NO default public broadcast · NO keys on remote MCP
    │
    └─ OKX OnchainOS (official MCP + Open API + Skills)
          DEX quote / liquidity / swap calldata
          Market data (API; MCP probe)
          Agentic Wallet (TEE; agent execution)
          Payments (APP protocol; later)
                    │
                    ▼
              X Layer (1952 / 196)
```

| 层 | 谁 | 密钥 |
|---|---|---|
| 合约语义 + codegen | ProofForge | 无 |
| 本机 Anvil demo | PF scripts + Anvil #0 | 仅 local |
| X Layer 读链 / 前端 attach | dApp + public RPC | 无 |
| X Layer 写链 | 用户钱包或开发者本机 env key | **永不**进 PF remote MCP |
| DEX 报价 / swap 构造 | OnchainOS MCP（`OK-ACCESS-KEY`） | API key 在应用本地 |

## 4. 官方 OnchainOS MCP（P0：直接用）

| | |
|---|---|
| URL | `https://web3.okx.com/api/v1/onchainos-mcp` |
| Auth | Header `OK-ACCESS-KEY`（[Dev Portal](https://web3.okx.com/zh-hans/onchainos/dev-portal/project)） |
| 文档 | [DEX MCP Server](https://web3.okx.com/onchainos/dev-docs/trade/dex-ai-tools-mcp-server) |

已文档化的工具（Trade/DEX 面）：

- `dex-okx-dex-aggregator-supported-chains`
- `dex-okx-dex-liquidity`（示例含 **X-layer**）
- `dex-okx-dex-quote`
- `dex-okx-dex-approve-transaction`
- `dex-okx-dex-swap`
- `dex-okx-dex-solana-swap-instruction`

### Agent 双挂示例

```bash
# ProofForge remote (docs/catalog/guidance)
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp

# OnchainOS official (DEX) — key from portal, app-local only
claude mcp add onchainos-mcp https://web3.okx.com/api/v1/onchainos-mcp -t http \
  -H "OK-ACCESS-KEY: <your-key>"
```

**禁止**：把 `OK-ACCESS-KEY` 写进 monorepo、Workers 公共 env、或 PF 远程工具参数。

## 5. 能力 × 优先级（P0–P2）

| Pri | 能力 | 动作 | 状态（本切片） |
|---|---|---|---|
| **P0** | X Layer 网络元数据 | `networks.v1.json` + MCP `pf_network_info` | **done (catalog)** |
| **P0** | OnchainOS 地图 + 双 MCP 说明 | 本文 + `pf_onchainos_guide` | **done (docs/MCP guidance)** |
| **P0** | DEX | **官方** onchainos-mcp，不自研 | **use official** |
| **P0** | EVM UI 链预设 | `templates/evm-dapp-ui` X Layer chain ids | **done (template presets)** |
| **P1** | 行情 Market API | 探官方 MCP；否则只读 REST 薄包装 | **planned** |
| **P1** | Agentic Wallet | 文档 + Skills/dApp 接线；PF 不实现 TEE | **planned** |
| **P1** | testnet 部署脚本 | `scripts/pf_evm_xlayer_deploy.sh` 工程 lane | **stub / planned** |
| **P2** | Payments APP | 文档占位 → 后置 | **planned** |
| **P2** | 更多 EVM 行 | 同表加 `evm.<chain>.<env>` | **placeholder row exists** |
| **P2** | Lean `NetworkRegistry` | 规格已有；产品 deploy identity join | **spec only** |

## 6. PF 查询面

| 面 | 入口 |
|---|---|
| JSON | `docs/product/networks.v1.json` |
| 远程 MCP | `pf_network_info` · `pf_onchainos_guide` · `pf_get_doc` id=`13-xlayer-onchainos.md` |
| 本地 stdio MCP | 同名工具（读 monorepo JSON） |
| SDK | `ProofForgeClient.network_catalog` / `networks` |
| chain catalog | `pf_chain_catalog` `target=evm` → `networksRef` + `ecosystem.okxOnchainOs` |

### `pf_network_info` 参数（示意）

```json
{ "id": "evm.xlayer.testnet" }
```

```json
{ "targetFamily": "evm", "env": "testnet" }
```

省略 filter → 返回全表 + notes。

## 7. 前端（X Layer）

默认 demo 仍是 **Anvil**。连 X Layer testnet 时：

```bash
cd templates/evm-dapp-ui
# example — attach already-deployed contract; wallet signs
export VITE_CHAIN_ID=1952
export VITE_RPC_URL=https://testrpc.xlayer.tech/terigon
export VITE_CONTRACT_ADDRESS=0x…
npm run dev
```

或使用模板内 `XLAYER_TESTNET` / `XLAYER_MAINNET` 预设（见 `src/chains.ts`）。

**不要**把主网热钱包私钥放进 `.env` 或前端 bundle。

## 8. 工程部署（诚实）

| 路径 | 现状 |
|---|---|
| `pf build -t evm` | 产品支持（产物） |
| Anvil local deploy | 产品 demo 脚本 |
| X Layer testnet write | **工程 lane**：开发者本机 cast/viem + funded OKB；非 MCP 默认面 |
| X Layer mainnet write | **gated**；pf v0 默认拒绝 public broadcast |
| Lean NetworkRegistry digest join | 规格见 `docs/specs/target-registry.md`；未产品接线 |

Deploy 脚本占位：`scripts/pf_evm_xlayer_deploy.sh`（fail-closed 除非显式 env）。

## 9. 黑客松产品方向（未定案 · 仅参考）

竖切候选（决策前不绑定实现）：

- **ForgeAgent**：NL → 受控 PF 模板 → EVM 部署 X Layer → OnchainOS quote/swap 编排
- 合约侧：限额金库 / Intent Guard / 分账（ProgramV1）
- 不冲 Launch Grant 刷量；主打完成度 + AI + X Layer 真实部署

## 10. 非目标

- 不在 `proof-forge-next build` 上加 `--network`
- 不把 OnchainOS REST 重写成 Lean
- 不在远程 PF MCP 代签或代持 OKX key
- 不声称 formal / hermetic / mainnet-ready
- 不因 catalog 存在而改 `deployable=true`

## 11. 相关

- Network catalog：[`networks.v1.json`](networks.v1.json)
- Chain client catalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md)
- EVM frontend：[`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md)
- CLI network 规格：[`../specs/target-registry.md`](../specs/target-registry.md) · [`../specs/cli.md`](../specs/cli.md)
- 远程 MCP：[`../../clients/pf-mcp/`](../../clients/pf-mcp/)
