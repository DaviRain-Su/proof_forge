---
id: PRODUCT-ALEO-DAPP-FRONTEND-WALLET
title: Aleo dApp frontend — Wallet Adapter + Provable SDK (FCCP companion)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Aleo dApp 前端：Wallet Adapter · Provable SDK · 与 ProofForge 的分工

状态：`draft`（2026-08-10）  
前置：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) · [`04-chain-client-catalog.md`](04-chain-client-catalog.md) · [`02-external-program-v1.md`](02-external-program-v1.md)  
参考（生态，**非** PF 发货）：

| 源 | 用途 |
|---|---|
| [Aleo Wallet Adapter (docs.aleo.org)](https://docs.aleo.org/build/wallets/wallet-adapter/getting-started) | 官方 Wallet Adapter 入门 |
| [ProvableHQ/aleo-dev-toolkit](https://github.com/ProvableHQ/aleo-dev-toolkit) | Wallet adaptor monorepo + React 示例 |
| [ProvableHQ/sdk](https://github.com/ProvableHQ/sdk) / [`@provablehq/sdk`](https://www.npmjs.com/package/@provablehq/sdk) | 链上对象、prove/deploy/execute、RPC |
| [create-leo-app](https://github.com/ProvableHQ/sdk/tree/mainnet/create-leo-app) | 框架脚手架示例 |
| [aleodocs.vercel.app](https://aleodocs.vercel.app)（Aleo-101 / OpenBuild） | 中文学习路径：账户、Program、Transaction、Credits |
| [Leo Wallet docs](https://docs.leo.app/) | 历史 demox-labs adapter 文档（见 §8 版本说明） |

## 1. 问题：FCCP 缺了什么

现有 FCCP（Front/Chain Client Product）把 Aleo **后端**钉死了：

```text
ProgramV1 (Lean) → pf build → .aleo Instructions + query descriptor
```

但 **完整 dApp** 还需要前端：

```text
Browser UI
  ├─ Wallet connect / address / network
  ├─ Sign / decrypt / request records
  ├─ requestTransaction / executeDeployment (keys stay in wallet)
  └─ optional: @provablehq/sdk for offline prove, program parse, RPC query
         ▲
         │ program id + function ABI from PF artifact
         │
ProofForge backend (this monorepo)
```

此前 `chain-client-catalog` 只写了一行模糊的 “Aleo SDK / Provable SDK”，**没有**：

- 具体 npm 包名与职责分层  
- Wallet Adapter 安装/Provider/`useWallet` 面  
- 与 `pf build` 产物如何对接  
- 密钥边界（浏览器 vs `pf deploy --broadcast`）  
- Agent 可执行的前端剧本  

本文补齐 **metadata + 剧本 + 最小代码样例**。ProofForge **不** vendor/pin 这些 npm 包，**不**在 MCP 默认面持有私钥或广播。

## 2. 后端 vs 前端权威边界

| 层 | 谁负责 | 典型命令 / 包 | 密钥 |
|---|---|---|---|
| **Backend contracts** | ProofForge `pf` / `proof-forge-next` | `pf new` · `pf build` · `pf run` · `pf deploy`（CLI） | CLI 侧 env key **仅**开发者本机；MCP **禁止** |
| **Frontend wallet UX** | 生态 Wallet Adapter | `@provablehq/aleo-wallet-adaptor-*` | **钱包扩展**保管；dApp 不持 private key |
| **Frontend chain logic** | 生态 Provable SDK | `@provablehq/sdk` · `@provablehq/wasm` | 可选本地 prove；生产优先 wallet 内 prove |
| **Indexer / explorer** | 公共 API | `https://api.explorer.provable.com/v1` | 无 |

**诚实句（必须保留）：**

- PF 产品 OutputSet 对 Aleo 仍可是 `deployable=false` 的 direct Instructions 面；CLI `pf` 的 deploy/execute 是 **工程 lane**，不是 formal/mainnet。  
- 前端 wallet 广播 **不等于** PF 已提供产品级 network 工具。  
- 不要把浏览器里的 `executeTransaction` 写进 MCP 默认工具。

## 3. 推荐包分层（2026-08 生态）

### 3.1 Wallet Adapter（React dApp 首选）

来自 **ProvableHQ/aleo-dev-toolkit**（当前 npm 作用域 `@provablehq/*`）：

| 包 | 角色 |
|---|---|
| `@provablehq/aleo-wallet-adaptor-react` | `AleoWalletProvider` · `useWallet` |
| `@provablehq/aleo-wallet-adaptor-react-ui` | `WalletModalProvider` · `WalletMultiButton` · CSS |
| `@provablehq/aleo-wallet-adaptor-core` | 错误类型 · `DecryptPermission` · base types |
| `@provablehq/aleo-wallet-standard` | Wallet Standard 接口 |
| `@provablehq/aleo-types` | `Network` 等公共类型 |
| `@provablehq/aleo-wallet-adaptor-leo` | **Leo Wallet** |
| `@provablehq/aleo-wallet-adaptor-puzzle` | Puzzle |
| `@provablehq/aleo-wallet-adaptor-shield` | Shield（含 privacy props） |
| `@provablehq/aleo-wallet-adaptor-fox` | Fox |
| `@provablehq/aleo-wallet-adaptor-soter` | Soter |
| `@provablehq/aleo-hooks` | 链数据 hooks（可选） |

安装（核心 + 常用钱包）：

```bash
npm install --save \
  @provablehq/aleo-wallet-adaptor-react \
  @provablehq/aleo-wallet-adaptor-react-ui \
  @provablehq/aleo-wallet-adaptor-core \
  @provablehq/aleo-wallet-standard \
  @provablehq/aleo-types \
  @provablehq/aleo-wallet-adaptor-leo \
  @provablehq/aleo-wallet-adaptor-puzzle \
  @provablehq/aleo-wallet-adaptor-shield \
  react react-dom
```

### 3.2 Provable SDK（程序对象 / prove / RPC）

| 包 | 角色 |
|---|---|
| `@provablehq/sdk` | Account、Program、Transaction、deploy/execute、RPC client |
| `@provablehq/wasm` | Wasm 绑定（sdk 依赖；浏览器 prove 重量级） |
| `create-leo-app` | 官方 web 示例脚手架 |

### 3.3 历史包名（兼容说明）

旧文档/教程可能写 `@demox-labs/aleo-wallet-adapter-*`（Leo Wallet 早期 adapter）。  
**新 dApp 优先 `@provablehq/aleo-wallet-adaptor-*`**。若维护旧代码，对照 [docs.leo.app](https://docs.leo.app/) 迁移，不要在同一应用混用两套 Provider。

## 4. 端到端 dApp 拓扑

```text
┌──────────────────────────── ProofForge monorepo ────────────────────────────┐
│  src/*.lean (ProgramV1)                                                     │
│       │ pf build --target aleo                                              │
│       ▼                                                                     │
│  build/aleo/*.aleo  +  *-query-contract.json  +  manifest.json              │
│       │                                                                     │
│  optional eng: pf deploy/execute --network testnet [--broadcast]            │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │ copy program id / .aleo text / query ABI
                                ▼
┌──────────────────────────── Frontend app (Vite/Next) ───────────────────────┐
│  AleoWalletProvider + WalletModalProvider                                   │
│       │ connect (Leo / Puzzle / Shield / …)                                 │
│       │ executeTransaction(programId, function, inputs, fee)                │
│       │ requestRecords / decrypt (private state)                            │
│       ▼                                                                     │
│  Explorer RPC  https://api.explorer.provable.com/v1/{network}/…             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**PF 产物如何喂给前端：**

| Artifact | 前端用法 |
|---|---|
| `*.aleo` | 部署源；或已上链后只保留 **program id**（如 `helloworld.aleo` / `pfdemo….aleo`） |
| `*-query-contract.json` | 映射/view 查询形状（public state） |
| `manifest.json` | 校验 output schema / 文件清单；**不要**当 runtime ABI 权威 |

StateCell 形程序的链上调用与 CLI 一致：`initialize` / `increment`（public `u64` 输入）；public mapping 可用 explorer API 读。

## 5. 最小 React 接线（Wallet）

### 5.1 Provider 根

```tsx
import React, { useMemo, type FC, type ReactNode } from "react";
import { AleoWalletProvider } from "@provablehq/aleo-wallet-adaptor-react";
import {
  WalletModalProvider,
  WalletMultiButton,
} from "@provablehq/aleo-wallet-adaptor-react-ui";
import { LeoWalletAdapter } from "@provablehq/aleo-wallet-adaptor-leo";
import { PuzzleWalletAdapter } from "@provablehq/aleo-wallet-adaptor-puzzle";
import { ShieldWalletAdapter } from "@provablehq/aleo-wallet-adaptor-shield";
import { Network } from "@provablehq/aleo-types";
import { DecryptPermission } from "@provablehq/aleo-wallet-adaptor-core";
import "@provablehq/aleo-wallet-adaptor-react-ui/dist/styles.css";

/** Programs this dApp intends to call (empty = any). Prefer pinning. */
const PROGRAMS = ["credits.aleo", "YOUR_PROGRAM.aleo"];

export const AleoAppShell: FC<{ children: ReactNode }> = ({ children }) => {
  const wallets = useMemo(
    () => [
      new LeoWalletAdapter(),
      new PuzzleWalletAdapter(),
      new ShieldWalletAdapter(),
    ],
    [],
  );

  return (
    <AleoWalletProvider
      wallets={wallets}
      network={Network.TESTNET}
      decryptPermission={DecryptPermission.UponRequest}
      autoConnect={false}
      programs={PROGRAMS}
      onError={(e) => console.error("[aleo-wallet]", e)}
    >
      <WalletModalProvider>
        <header style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <strong>ProofForge × Aleo</strong>
          <WalletMultiButton />
        </header>
        {children}
      </WalletModalProvider>
    </AleoWalletProvider>
  );
};
```

### 5.2 `useWallet` 能力面（agent 应知道的方法名）

| 方法 / 状态 | 用途 |
|---|---|
| `connected` · `address` · `network` | 连接状态 |
| `connect` · `disconnect` · `selectWallet` · `switchNetwork` | 会话 |
| `signMessage` | 登录/绑定 |
| `decrypt` · `requestRecords` | 私有 record |
| `executeTransaction` · `transactionStatus` | **调用已部署 program** |
| `executeDeployment` | 从浏览器部署 program（fee 高；测试网慎用） |
| `transitionViewKeys` · `requestTransactionHistory` | 需更高 decrypt 权限 |

### 5.3 调用已部署 program（示意）

> 具体 `Transaction` / input 编码以当前 `@provablehq/aleo-wallet-adaptor-*` 与钱包实现为准；升级包后对照官方 example app：  
> https://aleo-dev-toolkit-react-app.vercel.app/

```tsx
import { useCallback } from "react";
import { useWallet } from "@provablehq/aleo-wallet-adaptor-react";
import { WalletNotConnectedError } from "@provablehq/aleo-wallet-adaptor-core";

const PROGRAM_ID = "YOUR_PROGRAM.aleo"; // from pf deploy / explorer

export function IncrementButton() {
  const { connected, address, executeTransaction, transactionStatus } =
    useWallet();

  const onIncrement = useCallback(async () => {
    if (!connected || !address) throw new WalletNotConnectedError();
    // Wallet builds+proves+broadcasts; dApp never sees private key.
    const txId = await executeTransaction({
      program: PROGRAM_ID,
      functionName: "increment",
      inputs: ["3u64"],
      // fee / priority fields: follow current adapter types
    } as never);
    // Poll status (finality is not instant)
    const status = await transactionStatus(txId);
    console.log({ txId, status });
  }, [connected, address, executeTransaction, transactionStatus]);

  return (
    <button disabled={!connected} onClick={() => void onIncrement()}>
      increment(+3)
    </button>
  );
}
```

### 5.4 读 public mapping（无需钱包）

与 CLI demo 相同的 explorer REST：

```bash
# example from live PF demo
curl -sS \
  "https://api.explorer.provable.com/v1/testnet/program/pfdemo336641.aleo/mapping/pf_state_0/0u8"
```

前端：

```ts
const ENDPOINT = "https://api.explorer.provable.com/v1";
const network = "testnet"; // or mainnet — product default stays testnet
async function readU64(program: string, mapping: string, key: string) {
  const url = `${ENDPOINT}/${network}/program/${program}/mapping/${mapping}/${key}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  return res.text(); // e.g. "\"8u64\""
}
```

## 6. 与 `pf` 后端的对接清单

| 步 | 后端（PF） | 前端 |
|---|---|---|
| 1 | `pf setup --target aleo` · `pf new` · `pf build` | — |
| 2 | `pf run -- initialize 5u64`（本机 VM） | — |
| 3 | `pf deploy --network testnet`（save-only）或 `--broadcast` | 记录 **program id** |
| 4 | （可选）`pf execute … --broadcast` 冒烟 | 或改用 wallet `executeTransaction` |
| 5 | 把 program id + 函数名写进前端 env | `VITE_ALEO_PROGRAM_ID=….aleo` |
| 6 | — | Wallet connect → execute → explorer 校验 mapping |

**不要：**

- 把 `APrivateKey1…` 放进前端 bundle / Vercel env 给浏览器  
- 在 MCP remote 工具里代用户签名  
- 混用 demox-labs 与 `@provablehq` 两套 adapter  

**可以：**

- 开发者本机用 `PF_ALEO_TESTNET_KEY` + `pf deploy --broadcast` 做 CI/demo  
- 终端用户只通过扩展钱包交互  

## 7. Agent 剧本（前端切片）

接在 [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) **后端完成后**：

| 步 | 动作 | 成功判据 |
|---|---|---|
| F0 | `pf_chain_catalog` `target=aleo` | `frontendClients` 含 wallet-adaptor + sdk 条目 |
| F1 | 读本文 §3–§5 | 选 `@provablehq/aleo-wallet-adaptor-*` |
| F2 | 脚手架 Vite/Next React app | `AleoWalletProvider` 可编译 |
| F3 | 安装 Leo（或 Puzzle/Shield）扩展 · Testnet | `WalletMultiButton` 显示 address |
| F4 | 配置 `PROGRAM_ID`（来自 PF deploy 或 explorer） | env 无私钥 |
| F5 | `executeTransaction` initialize/increment | explorer tx + mapping 更新 |
| F6 | （可选）`@provablehq/sdk` 做只读 Program 解析 | 不替代 wallet 签名 |

Remote MCP 可增加的 **guidance-only** 提示（已有 `pf_cli_cheatsheet` / `pf_aleo_live_demo`）：指向本文 id `PRODUCT-ALEO-DAPP-FRONTEND-WALLET`。

## 8. 网络与费用

| 网络 | 用途 | PF 默认 |
|---|---|---|
| `Network.TESTNET` | dApp 联调 · faucet | **默认** |
| `Network.CANARY` | 预发 | 可选 |
| `Network.MAINNET` | 生产 | PF CLI **拒绝** mainnet；前端若接 mainnet 是 **应用自己的产品决策**，与 PF formal 无关 |

- Deploy fee ≈ 数 credits（namespace + synthesis）；短 program 名更贵。  
- Execute fee 远小于 deploy。  
- Faucet：https://faucet.aleo.org/（人机验证，不进 CI）。  

## 9. 安全清单

1. **私钥只在钱包或开发者本机 CLI env** — 永不进 git / 前端。  
2. `decryptPermission` 默认偏紧（`NoDecrypt` / `UponRequest`）；不要一上来 `OnChainHistory`。  
3. `programs` 白名单限制 dApp 可请求的 program id。  
4. Shield 的 `readAddress` / `recordAccess` 用于隐私 dApp；默认读官方 privacy guide。  
5. XSS = 丢会话；CSP + 勿 `eval` 用户 program 文本。  
6. 依赖锁定用应用自己的 package-lock；PF catalog **不 pin** 版本号（只给名字）。  

## 10. 与 aleodocs.vercel.app 学习路径的映射

[aleodocs.vercel.app](https://aleodocs.vercel.app)（Aleo-101）适合补概念；实现时落到官方包：

| 文档概念 | 前端落点 |
|---|---|
| Accounts & Keys | Wallet connect · 不导出 private key |
| Programs | PF `.aleo` + on-chain program id |
| Transactions / Transitions | `executeTransaction` · `transactionStatus` |
| Credits & Transfers | `credits.aleo` + wallet records |
| Record scanning | `requestRecords` · `decrypt` |
| Public vs private state | mapping REST vs record decrypt |

## 11. 成熟度 / 非目标

| 项 | 状态 |
|---|---|
| 本文 + catalog 字段 | **engineering draft** |
| PF 发货 React 模板 / pin npm | **未做**（可选后续 `templates/aleo-dapp-ui`） |
| MCP 代签 / 远程 broadcast | **明确不做** |
| Formal / mainnet / hermetic | **不声称** |

## 12. 相关

- 后端 Hello：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)  
- Catalog JSON：[`chain-client-catalog.v1.json`](chain-client-catalog.v1.json)  
- Testnet CLI demo：[`../demos/aleo-testnet-walkthrough.md`](../demos/aleo-testnet-walkthrough.md)  
- 远程 MCP：`https://proof-forge-mcp.davirain-yin.workers.dev/mcp` · tool `pf_aleo_live_demo`  
