---
id: RPT-021
title: 各链官方链上程序（系统合约 / builtin program）全景调研
status: draft
owner: research
updated: 2026-08-05
normative: false
---

# 各链官方链上程序（系统合约 / builtin program）全景调研

> 调研日期：2026-08-05
> 目的：RPT-020（[`20-host-function-survey.md`](20-host-function-survey.md)）只覆盖
> host function / syscall / opcode 级系统能力。本报告补充**第二层**：各链由协议官方部署到
> 链上、合约可调用的程序（builtin program / system contract / precompile / management
> canister / 链级模块）。核心视角：**同一系统能力在不同链以不同形态出现**，对调用方而言
> "内建 host function"与"官方链上程序"都是可调用的系统能力，应统一抽象。
> 方法：官方资料 web 调研（EIP、solana docs、nomicon、docs.ton.org、cosmwasm-std、
> aleo docs、ic interface spec、developers.stellar.org）。地址/ID 均经权威来源核对。

## 1. 系统能力的两种形态（统一抽象的依据）

| 层 | 定义 | 典型例子 | 项目现状 |
|---|---|---|---|
| **L1 内建运行时能力** | 宿主运行时直接暴露，非链上合约：opcode / syscall / host function / stdlib | EVM opcode、Solana syscall、NEAR host function、TON stdlib | 已有 `ContextRead` / `EnvRead` 抽象（时间/调用者/余额） |
| **L2 官方链上程序** | 协议官方部署/内建的链上程序：builtin program / system contract / precompile / management canister / 链级模块 | Solana System/Token/ATA、EVM precompile 与系统合约、TON Elector/Config、ICP `aaaaa-aa`、Aleo `credits.aleo`、Cosmos x/bank | 已有先例：ADR-0030 E1 绑 Solana System/Token/ATA program、NEAR NEP-141 合约、CW CW20 合约 |

**统一抽象的含义**：把"能力"从"形态"中解耦——同一能力（如 sha256）在 EVM 是 precompile
合约、在 Solana 是 syscall、在 NEAR 是 host function、在 TON 是 stdlib；同一能力（如转账）
在 Solana 是 System/Token program、在 NEAR 是 host action、在 CW 是 x/bank 链模块、在
Aleo 是 credits.aleo 系统程序。catalog 一行 + per-target 物化 + 无对应物 fail closed。

## 2. 各链官方链上程序清单

### 2.1 EVM

**Precompiles**（协议内建、固定地址、经 CALL/STATICCALL、无持久状态）：
`0x01` ecrecover / `0x02` sha256 / `0x03` ripemd160 / `0x04` identity / `0x05` modexp /
`0x06`-`0x08` BN254(add/mul/pairing) / `0x09` blake2f / `0x0a` KZG point-eval /
`0x0b`-`0x11` BLS12-381 全套（Pectra）。

**系统合约**（有持久状态的真实合约，协议在区块边界经 `SYSTEM_ADDRESS` 系统调用）：

| 合约 | 地址 | 职责 |
|---|---|---|
| Beacon Block Roots（EIP-4788） | `0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02` | 环形缓冲存近期 beacon block roots |
| Withdrawal Request（EIP-7002） | `0x00000961Ef480Eb55e80D19ad83579A64c007002` | 0x01 提款凭证触发验证者退出 |
| Consolidation Request（EIP-7251） | `0x0000BBdDc7CE488642fb579F8B00f3a590007251` | 验证者合并 |
| History Storage（EIP-2935） | `0x0000F90827F1C53a10cb7A02335B175320002935` | 历史 block hash（突破 256 块限制） |
| Beacon Deposit Contract | `0x00000000219ab540356cBB839Cbe05303d7705Fa` | 信标质押存款（单向） |

**明确排除**：ERC-20/721/1155 **不是**链上系统程序——是部署惯例/标准接口，无固定地址、
无协议内建地位。

### 2.2 Solana

**Builtin/Native programs**（运行时内建，Native Loader 拥有）：

| 程序 | Program ID | 职责 |
|---|---|---|
| System | `11111111111111111111111111111111` | 建账户、转 SOL、分配空间/owner |
| Vote | `Vote111...` | 验证者投票账户 |
| Stake | `Stake111...` | 质押委托 |
| Config | `Config111...` | 链上配置存储 |
| Compute Budget | `ComputeBudget111...` | CU 上限与优先费 |
| Address Lookup Table | `AddressLookupTab1e111...` | 地址查找表 |
| ZK ElGamal Proof | `ZkE1Gama1Proof111...` | ElGamal/Pedersen ZK proof 验证（Token-2022 保密转账） |

**Precompiles**（原生验签，**不可 CPI**，经 instruction introspection）：Ed25519 /
Secp256k1（ecrecover 风格）/ Secp256r1。

**Loaders**：Native Loader、BPF Loader v1（已禁用管理）、v2（旧版）、Upgradeable v3（默认）。

**官方部署的 SPL 程序**（官方部署的 BPF 程序，非运行时内建）：Token
（`TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`）、Token-2022
（`TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`）、ATA
（`ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL`）。

### 2.3 NEAR

**确认：协议层无官方系统合约**——存储/转账/质押/promise/哈希/验签全部是 host function
（WASM import），不存在"调用系统合约地址"概念。
官方部署的**生态/参考合约**（官方维护、非协议强制）：Staking Pool + Factory
（`poolv1.near`/`pool.near`）、Whitelist、Lockup/Vesting + 工厂、Multisig v1/v2 + 工厂、
w-NEAR。质押委托是智能合约实现而非协议原生。

### 2.4 TON（masterchain 系统合约，workchain -1）

| 合约 | 地址（raw `-1:`） | 职责 | config param |
|---|---|---|---|
| Config | `5555...55` | 链配置参数存储/治理 | 0 |
| Elector | `3333...33` | 验证者选举/质押/奖励 | 1 |
| Minter/System | `0000...00` | 铸造 TON 奖励给验证者 | 2 |
| Fee Collector | （param 3） | 手续费收集 | 3 |
| Root DNS | `e56754f8...` | `.ton` 域名根 | 4 |
| Blackhole | `ffff...ff` | 销毁资金 | 5 |

另有 Fundamental SMCs（config param 31）：BSC 桥、Oracle、Oracle multisig 等。
**交互机制**：`config_param(x)`（TVM c7 读配置）、`send_raw_message`（写：质押申请/治理
投票/奖励回收）、get methods（只读，链下）。Elector/Config 有 tick/tock 特殊事务。
**说明**：TON Storage 无固定全局系统合约（provider 部署）；标准 multisig 是用户部署合约。

### 2.5 CosmWasm / Cosmos SDK（链级模块，非合约但系统能力）

| 模块 | 消息 | 职责 |
|---|---|---|
| x/bank | BankMsg::Send/Burn | 原生代币转账/销毁 |
| x/staking | StakingMsg::Delegate/Undelegate/Redelegate | 委托 |
| x/distribution | DistributionMsg::WithdrawDelegatorReward 等 | 奖励 |
| x/gov | GovMsg::Vote/VoteWeighted | 治理投票 |
| x/ibc | IbcMsg::Transfer/SendPacket 等 | 跨链 |
| x/wasm | WasmMsg::Execute/Instantiate/Instantiate2/Migrate | 跨合约调用 |
| x/feegrant、x/group | CosmosMsg::Any（无专用变体） | 代付手续费、链上多签 |

合约经 `CosmosMsg` 变体调用，运行时自动填 sender=合约地址。**非"合约"**——是 Cosmos SDK
Go 模块，但对合约而言是系统能力。

### 2.6 Aleo

**唯一协议内建系统程序**：`credits.aleo`——私有/公开余额、5 种隐私级别转账、split/join、
质押（bond_public/unbond_public/claim_unbond_public，解绑冷却 360 块）、fee_private/public。
官方部署/参考：`token_registry.aleo`（多代币注册表）、`wrapped_credits.aleo`（ARC-20 参考）。
社区标准：ARC-20（主代币）、ARC-22（合规代币）、ARC-0721（NFT）、ARC-101（验证者）。
程序以 `name.aleo` 标识、部署后不可变。

### 2.7 ICP

**Management Canister `aaaaa-aa`**（虚拟 canister，协议实现，非真实 Wasm）：生命周期
（create/install/start/stop/delete/upgrade）、`raw_rand`、`http_request`、链密钥 ECDSA /
Schnorr / VetKeys（阈值密码学）、Bitcoin API（已弃用转专用 canister）。
**官方部署系统 canisters**：NNS Governance/Registry/Root、ICP Ledger、Cycles Minting、
Internet Identity、Cycles Ledger、Bitcoin（`ghsi2-tqaaa-aaaan-aaaca-cai`）、ckBTC/ckETH
Ledger+Minter、EVM RPC。

### 2.8 Soroban

**唯一协议级预编译合约**：**Stellar Asset Contract (SAC)**——执行类型
`CONTRACT_EXECUTABLE_STELLAR_ASSET`（非 WASM hash），宿主原生执行：transfer/approve/burn/
mint/clawback/set_authorized/set_admin，直接访问经典 trustline/账户余额；每个资产有确定性
保留地址；实现 CAP-46-6 与 SEP-41。官方参考合约（非协议强制）：soroban-examples/token。

## 3. 能力 vs 形态对照（统一抽象的核心表）

| 能力 | EVM | Solana | NEAR | TON | CosmWasm | Aleo | ICP | Soroban |
|---|---|---|---|---|---|---|---|---|
| **SHA-256** | precompile `0x02` | syscall `sol_sha256` | host `sha256` | stdlib（sha256u） | —（无原生） | snarkVM 内建 | —（间接） | host function |
| **Keccak-256** | opcode 级 | precompile（内含） | host `keccak256` | — | — | Keccak | — | — |
| **Ed25519 验签** | — | precompile（不可 CPI） | host `ed25519_verify` | stdlib `check_signature` | — | — | 链密钥 Schnorr | — |
| **secp256k1 恢复** | precompile `0x01` | precompile | host `ecrecover` | — | — | ECDSA（keccak 变体） | 链密钥 ECDSA | — |
| **原生资产转账** | CALL+value（ETH） | System Program（lamports）/ Token 程序 | host `promise_batch_action_transfer` | `send_raw_message` 带 value | 链模块 `BankMsg::Send` | `credits.aleo` transfer | ICP Ledger canister | SAC（含原生 XLM） |
| **跨合约调用** | CALL/STATICCALL/DELEGATECALL | CPI + System Program | promise（异步） | `send_raw_message` | 链模块 `WasmMsg::Execute` | Leo `call` | canister 间 call | 合约间 invoke |

**形态分类**：host function（宿主 import，非链上合约）/ syscall（VM 原生调用）/ precompile
（固定地址原生执行，Solana 不可 CPI）/ 官方 program（官方部署的 BPF/WASM，固定 ID 非内建）/
链模块（Cosmos SDK Go 模块）/ 系统合约（协议级链上合约，区块边界交互）。

## 4. 对统一抽象设计的含义

1. **L1 与 L2 统一进同一个能力 catalog**：`ContextRead`/`EnvRead`（L1 内建）+ 官方 program
   能力（L2）都登记为 wire catalog 行 + requirement 行，per-target 物化 + 无对应物 FC。
2. **能力与形态解耦**是 catalog 设计的核心：一行 `pf.crypto.sha256` 物化为 EVM precompile /
   Solana syscall / NEAR host / TON stdlib；一行 `pf.assets.native.transfer` 物化为 System
   Program / BankMsg / promise action / send_raw_message / credits.aleo。
3. **官方 program 的"强制等级"要记入 catalog**：协议内建（Solana System、EVM precompile、
   Aleo credits.aleo、ICP aaaaa-aa）vs 官方部署（Solana Token/ATA、NNS canisters）vs
   生态参考（NEAR staking pool、soroban-examples/token、ARC-20）——后者不得冒充系统能力。
4. **密码学是 L2 最大的统一候选**：`pf.crypto`（EXT-CRYPTO）可把 sha256/keccak/ed25519/
   secp256k1 逐能力 catalog，各链形态天然不同（EVM 最全、TON 只有 Ed25519+SHA、Aleo 无
   SHA-2）——找不到对应物的能力按 target FC。
5. **项目先例已验证 L2 路径**：ADR-0030 E1 绑 Solana System/Token/ATA program、NEAR
   NEP-141、CW CW20——都是"官方链上程序作为能力"的工程化，只是尚未系统化为 catalog 层。

## 5. 权威来源

- EVM：evm.codes/precompiled、EIP-2537/4788/7002/7251/2935、ethereum.org staking deposit
- Solana：solana.com/docs/core/programs/{builtin-programs,precompiles}、anza-xyz runtime
  zk-elgamal-proof、SIMD-0153
- NEAR：nomicon.io BindingsSpec、near-nodes.io staking、github.com/near/core-contracts
- TON：docs.ton.org/foundations/{system,config}、stdlib、tonviewer.com/config
- CosmWasm：docs.rs/cosmwasm-std（CosmosMsg/WasmMsg）、book.cosmwasm.com、wasmd
- Aleo：docs.aleo.org（credits-and-transfers、staking、arc-20-tokens）
- ICP：docs.internetcomputer.org/references/{management-canister,system-canisters,
  chain-key-canister-ids,protocol-canisters}
- Soroban：developers.stellar.org/docs/tokens/{stellar-asset-contract,token-interface}、
  rs-soroban-env builtin_contracts

配套：[`20-host-function-survey.md`](20-host-function-survey.md)（L1 内建能力全景 +
 跨链对照 + 统一抽象候选）。
