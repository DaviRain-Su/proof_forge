---
id: PRODUCT-EVM-DAPP-FRONTEND
title: EVM dApp frontend — viem/MetaMask + PF bytecode (FCCP companion)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# EVM dApp 前端：viem · MetaMask · 与 ProofForge 的分工

状态：`draft`（2026-08-10）  
前置：[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md) · [`04-chain-client-catalog.md`](04-chain-client-catalog.md) · [`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  
模板：[`templates/evm-dapp-ui/`](../../templates/evm-dapp-ui/)  
Walkthrough：[`../demos/evm-local-walkthrough.md`](../demos/evm-local-walkthrough.md)  
对称文档（Aleo）：[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)

## 1. 问题

FCCP 对 EVM 后端已经很强（Yul/solc/Anvil），但前端只有 catalog 一行 `ethers/viem/wagmi`。  
完整 dApp 需要：

```text
Browser UI (viem + injected wallet)
  ├─ connect / switch chain
  ├─ deploy (optional) or attach address
  ├─ eth_call get()
  └─ send increment(uint64)
         ▲
         │ ABI + bytecode / address from PF
         │
ProofForge: pf build -t evm → *.abi.json + *.bin
            pf test -t evm / pf deploy --network local
```

## 2. 后端 vs 前端边界

| 层 | 谁 | 密钥 |
|---|---|---|
| Compile | `pf build -t evm` | 无 |
| Local test | `pf test -t evm` / Anvil scripts | Anvil 默认 key（本机） |
| Local deploy | `pf deploy --broadcast --network local` 或 demo script | 本机 / Anvil #0 |
| dApp UX | `templates/evm-dapp-ui` + MetaMask | **钱包**；禁止主网私钥进前端 |
| Public chain write | **pf v0 拒绝** | — |

## 3. PF 产物（StateCell 形）

`pf build Examples/StateCell.lean --module Examples.StateCell -t evm -o <dir>`：

| 文件 | 用途 |
|---|---|
| `StateCell.abi.json` | Solidity JSON ABI（constructor / increment / get） |
| `StateCell.bin` | creation bytecode（hex，可无 `0x` 前缀） |
| `StateCell.yul` | 中间表示（前端通常不需要） |
| `manifest.json` | OutputSet 清单 |

典型 ABI：

```json
constructor(uint64 initial)
function increment(uint64 delta) returns (uint64)
function get() view returns (uint64)
```

## 4. 推荐包

| 包 | 角色 |
|---|---|
| `viem` | 类型化 RPC / encode / wallet client（模板默认） |
| `wagmi` + `viem` | React hooks 全家桶（可选，未打进最小模板） |
| `ethers` v6 | 生态替代 |
| MetaMask / Rabby | injected `window.ethereum` |

模板故意 **只依赖 viem**，降低安装面；catalog 仍列出 wagmi/ethers 作为生态选项。

## 5. 最小模板

```bash
# monorepo — builds, Anvil, deploy, writes deployment.json
bash scripts/pf_evm_local_demo.sh

# other terminal
cd templates/evm-dapp-ui && npm install && npm run dev
```

`public/deployment.json` schema：`proof-forge.pf.evm-local-deployment.v1`  
字段：`rpcUrl` · `chainId` · `contractAddress` · `abi` · `bytecode?` · `constructorInitial`。

## 6. Agent 剧本（前端）

| 步 | 动作 |
|---|---|
| F0 | `pf_chain_catalog` `target=evm` |
| F1 | `pf build -t evm` 得到 abi/bin |
| F2 | `bash scripts/pf_evm_local_demo.sh` 或 `pf test -t evm` |
| F3 | 起 `templates/evm-dapp-ui` · MetaMask 加本地链 |
| F4 | connect → get → increment |
| F5 | **不要**配置 public RPC + 热钱包到模板默认路径 |

## 7. 安全

1. Anvil #0 私钥仅本地演示；永不用于 public 链。  
2. pf v0 **拒绝** EVM public broadcast（testnet/mainnet 写）。  
3. 前端不要内嵌部署私钥；用户签名走扩展。  
4. `deployment.json` 可进 gitignore（含本机地址）；模板默认 ignore。  
5. 成功 ≠ formal / hermetic / mainnet。

## 8. 与路线 B 的边界

本文 + 模板是 **路线 A（产品闭环）**。  
路线 B（code-size、真实 CALL 地址、corpus 扩面、OZ）见 engineering backlog / `docs/targets/01-evm.md` residuals——**不在本切片声明完成**。

## 9. 相关

- 模板 README：`templates/evm-dapp-ui/README.md`  
- Demo 脚本：`scripts/pf_evm_local_demo.sh`  
- 既有 Anvil 测：`scripts/pf_evm_test.sh` · `scripts/evm_anvil_differential.sh`  
- Target dossier：`docs/targets/01-evm.md`  
