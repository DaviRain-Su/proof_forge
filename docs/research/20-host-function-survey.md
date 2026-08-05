---
id: RPT-020
title: 多链系统能力（host function / runtime API）全景调研
status: draft
owner: research
updated: 2026-08-05
normative: false
---

# 多链系统能力（host function / runtime API）全景调研

> 调研日期：2026-08-05
> 目的：回答"是否应把各链暴露给合约的系统能力（时间戳、高度、余额、调用者等）
> 统一抽象为公共 API"——先摸清各链到底有哪些能力，再谈抽象。
> 方法：官方/权威资料 web 调研（EIP、execution-specs、Solana syscall-reference、
> near-sdk/nomicon、cosmwasm-std、docs.ton.org、aleo.org、aztec docs、ic interface spec、
> developers.stellar.org、openvm.dev）。详细平台报告见：
> - [`system-capabilities-evm-solana.md`](system-capabilities-evm-solana.md)（EVM + Solana）
> - 本文各平台小节为浓缩权威清单

## 1. 平台分类（核心洞察）

各平台按"系统能力如何进入程序"分三类，**这决定了抽象边界**：

| 类别 | 平台 | 系统能力如何进入 | 时间戳/高度/调用者 |
|---|---|---|---|
| **状态类**（合约直接调用 host） | EVM、Solana、NEAR、CosmWasm、TON、Soroban、ICP | 直接 host function / opcode / system API | 直接返回**真实链上值** |
| **电路类**（ZK 证明） | Noir、OpenVM、Psy（推断） | 只能经 input / witness / oracle / hint stream 注入，且必须被电路约束 | **无法直接获得**；公开输入由 prover 选择、无锚定 |
| **混合** | Aleo | proof context = 电路（无链上访问）；finalize context = 链上确定性执行（可读链上值） | proof ❌ / finalize ✅（`std::ctx::block_height()` 等仅 finalize） |
| **模型层** | Quint | 无宿主能力（纯数学状态机） | 无 |

**关键结论**：电路类平台的"系统能力"本质上不是 host function，而是**可信输入问题**。
Noir/Aztec 的解法是 oracle 注入 + 电路内约束（如 `get_anchor_block_header` 经 Archive Tree
Merkle 证明约束历史区块头），或经 sequencer 公开执行闭环（PublicChecks，包含时用真实链时间
断言）。裸电路没有此能力——**项目对 Noir/Psy 的 unixTime 保持 fail-closed 的技术依据成立**。

## 2. 各平台系统能力全景（浓缩清单）

### 2.1 EVM（约 50 项；详见 platform 报告 §1）

| 维度 | 能力 |
|---|---|
| 时间/高度 | TIMESTAMP(0x42)、NUMBER(0x43)、BLOCKHASH(0x40，最近 256 块) |
| 身份 | ADDRESS、CALLER(0x33)、ORIGIN(0x32，tx.origin)、COINBASE、CHAINID(0x46)、EXTCODESIZE/COPY/HASH |
| 余额/价值 | BALANCE、SELFBALANCE(0x47)、CALLVALUE(0x34) |
| 资源/费用 | GASLIMIT、GASPRICE(0x3A)、BASEFEE(0x48)、BLOBBASEFEE(0x4A)、BLOBHASH(0x49) |
| 随机 | PREVRANDAO(0x44)——**有偏可预测，非安全随机**（OWASP SCWE-153） |
| 日志 | LOG0–LOG4（有副作用，view 禁） |
| 密码学 | 预编译 0x01–0x11：ecrecover / sha256 / ripemd160 / identity / modexp / BN254(G1 add·msm·pairing) / blake2f / KZG point-eval / BLS12-381 全套(0x0b–0x11) |

### 2.2 Solana（约 40 项；详见 platform 报告 §2）

| 维度 | 能力 |
|---|---|
| 时间/高度 | Clock sysvar：`slot`、`epoch`、`unix_timestamp`（i64，质押加权中位数）；SlotHashes(~512)、LastRestartSlot、EpochSchedule |
| 身份 | 无 ORIGIN 概念；调用者经 AccountInfo.is_signer；**无 sol_get_account_info**（账户数据入口点直传） |
| 余额 | AccountInfo.lamports；System Program transfer |
| 随机 | 无原生安全随机 |
| 日志 | sol_log_ / sol_log_64_ / sol_log_pubkey / sol_log_data / sol_log_compute_units_ |
| 密码学 | sol_sha256 / sol_keccak256 / sol_blake3 / sol_poseidon / sol_secp256k1_recover / curve25519 系列 / sol_alt_bn128_* / sol_big_mod_exp；precompiles：Ed25519 / Secp256k1 / Secp256r1（不可 CPI） |
| 调用/消息 | sol_invoke_signed_c/rust（CPI）、sol_get_processed_sibling_instruction、sol_get_stack_height、sol_set/get_return_data |
| PDA | sol_create_program_address、sol_try_find_program_address（**独有概念**） |
| 资源 | sol_remaining_compute_units、Rent sysvar、Compute Budget Program、sol_get_epoch_stake |

### 2.3 NEAR（host functions，nomicon 权威）

| 维度 | 能力 |
|---|---|
| 时间/高度 | `block_timestamp`（**纳秒**）、`block_index`/`block_height`、`epoch_height` |
| 身份 | `current_account_id`、`signer_account_id`/`pk`（view 禁）、`predecessor_account_id`（view 禁）、`chain_id` |
| 余额 | `account_balance`（view 可读）、`account_locked_balance`、`attached_deposit`（view 禁）、`validator_stake`/`validator_total_stake` |
| 存储 | `storage_read/write/remove/has_key/iter_*`（KV） |
| 调用/消息 | **promise 家族**（多区块异步）：`promise_create/then/and/batch_*`、`promise_result(s)`、`promise_return`、`promise_yield_*`；batch action：create_account/deploy_contract/function_call/transfer/stake/add_key/delete_key/delete_account |
| 密码学 | sha256 / keccak256 / keccak512 / ripemd160 / ecrecover / ed25519_verify / p256_verify / alt_bn128(3) / BLS12-381(8) |
| 随机 | `random_seed`（**区块级确定性**，不可直接作不可预测随机源） |
| 日志/返回 | log_utf8 / log_utf16 / value_return / panic_utf8 |
| 资源 | prepaid_gas / used_gas（view 禁）、storage_usage |

### 2.4 CosmWasm（Env/Querier/Message 三层）

| 维度 | 能力 |
|---|---|
| 时间/高度 | `Env.block.height`、`Env.block.time`（秒+纳秒）、`Env.block.chain_id` |
| 身份 | `Env.contract.address`、`MessageInfo.sender`（无独立 signer）、`MessageInfo.funds` |
| 余额 | `BankQuery::Balance/Supply`（querier，只读） |
| 存储 | Storage trait（KV，instance）；**RawQuery/RawRange 可读其他合约底层 KV** |
| 调用/消息 | `WasmMsg::Execute/Instantiate/Instantiate2/Migrate/...`；**SubMsg + reply_on(Always/Success/Error/Never) 同交易回调**；BankMsg::Send/Burn |
| 质押/治理 | StakingQuery/StakingMsg 全家桶（Delegate/Undelegate/Redelegate/WithdrawDelegatorReward...）、GovMsg::Vote（cosmwasm_2_0+） |
| 跨链 | IbcQuery（PortId/Channel）+ IbcMsg（Transfer/SendPacket/WriteAcknowledgement/CloseChannel） |
| 其他 | GrpcQuery（任意 gRPC，需链 allowlist）、CustomQuery/CustomMsg（trait 扩展）、事件 Response.attributes/events |

### 2.5 TON（TVM stdlib + send_raw_message）

| 维度 | 能力 |
|---|---|
| 时间/高度 | `now()`（秒）、`cur_lt()`/`block_lt()`（**逻辑时间**）；**无 block_height 直接 host function**（经 config_param/block info 间接） |
| 身份 | `my_address()`；**无内建 sender()**——需手动解析 in_msg_full |
| 余额 | `get_balance()`（计算阶段起始余额，返回 (nanoton, extra-currency dict)；send_raw_message 不更新）、`raw_reserve()` |
| 存储 | `get_data`/`set_data`（c4 cell）、cell DAG |
| 调用/消息 | `send_raw_message(cell, mode)`（**fire-and-forget，无内建回调**）+ SEND_MODE 位掩码（64=携带入站剩余/128=携带全部余额/+32=销毁/+16=bounce-on-action-fail）、`accept_message()`、`commit()`（**计算中途提交，防 bounce 回滚**） |
| 密码学 | `check_signature`/`check_data_signature`（Ed25519）、sha256/cell_hash/slice_hash；**无 keccak/ripemd/BLS** |
| 随机 | `random()`/`rand()`/`randomize_lt()`（**可预测，非密码学安全**） |
| 资源 | `compute_data_size`、`get_simple_compute_fee`/`get_storage_fee`/`get_forward_fee`、`config_param`（**直接读链全局配置**） |

### 2.6 Aleo（混合：proof context vs finalize context）

| 维度 | proof context（电路） | finalize context（链上） |
|---|---|---|
| 时间/高度 | ❌ | ✅ `std::ctx::block_height()` / `block_timestamp()` |
| 调用者 | ✅ `std::ctx::caller()` / `signer()` | ✅ 同左 |
| 状态 | ❌（无 mapping 访问） | ✅ mapping get/set/remove/contains/get_or_use |
| 密码学 | ✅ Poseidon2/4/8、BHP、Pedersen、Keccak、SHA3、Schnorr、ECDSA(secp256k1)、Snark::verify | 同左 + `rand.chacha` |
| 系统程序 | `credits.aleo` 跨程序调用：transfer_public/private/private_to_public/public_to_private、bond_public、unbond_public、claim_unbond_public、split、join、fee_private/public | — |

> 注：Aleo **不原生支持 SHA-256（SHA-2）**，用 SHA3/Keccak/Poseidon 替代。

### 2.7 电路类与模型层（Noir / OpenVM / Psy / Quint）

| 平台 | 系统能力 | 进入机制 |
|---|---|---|
| **Noir** | **无 host function**；纯约束系统 | Aztec oracle/foreign call（get_notes、storage_read、get_block_header_at、auth/membership witness、capsules）→ 返回值**必须在 constrained 代码中约束**；stdlib 密码学：sha256_compression、blake2s/3、pedersen、keccakf1600、ecdsa_secp256k1/r1、embedded_curve_ops、aes128 |
| **OpenVM** | **无 ecall**；guest 纯 zkVM | input_stream / hint_stream（宿主注入，guest 自行约束）/ reveal（公开输出）；密码学走 RISC-V 自定义指令扩展（Keccak/SHA2/BigInt/ECC/pairing） |
| **Psy** | **资料不足**（公开无 API 文档）；推断为 CFC 电路模型 | 推断：witness/input + Merkle delta proof（与 Noir 同型）；Goldilocks field、Plonky2/3 |
| **Quint** | **无**（纯模型检查规约） | 状态建模为 maps/sets/records；无时间/调用者/密码学 |

### 2.8 design-only：Soroban / ICP（状态类，直接可读）

| 平台 | 时间/高度 | 调用者 | 其他 |
|---|---|---|---|
| **Soroban** | `env.ledger().timestamp()` / `.sequence()` | `Address::require_auth()`（宿主管理授权+验签+重放保护） | storage(Temporary/Persistent/Instance)+TTL、events、crypto 全家桶（sha256/Ed25519/secp256k1/r1/BLS12-381/BN254/Poseidon）、deployer、network id |
| **ICP** | `ic0.time()`（纳秒）；**无直接块高度 API** | `ic0.msg_caller_*` | canister_cycle_balance、msg_cycles、stable memory、management canister：create/install/start/stop/delete、raw_rand、http_request、链密钥 ECDSA/Schnorr/VetKeys、global_timer |

## 3. 跨链能力维度对照（统一抽象候选判定）

| 能力维度 | EVM | Solana | NEAR | CW | TON | Soroban | ICP | Aleo(finalize) | 电路类(Noir/Psy/OpenVM) |
|---|---|---|---|---|---|---|---|---|---|
| **时间戳** | TIMESTAMP | Clock.unix_timestamp | block_timestamp(ns) | block.time | now() | ledger.timestamp | ic0.time | block_timestamp | ❌ 无法锚定 |
| **区块高度** | NUMBER | Clock.slot | block_index | block.height | 无直接函数 | ledger.sequence | 无直接 API | block_height | ❌ |
| **调用者** | CALLER | AccountInfo.is_signer | predecessor_account_id | MessageInfo.sender | 手动解析消息 | require_auth | msg_caller | caller() | oracle/witness 注入 |
| **签名者(origin)** | ORIGIN | 无此概念 | signer_account_id | 无独立 signer | 无（验签在合约外） | 部分(auth 内部) | 无 | signer() | oracle/witness |
| **自身余额** | SELFBALANCE | lamports | account_balance | BankQuery(querier) | get_balance | (balance 经 storage/query) | canister_cycle_balance | (credits 经系统程序) | ❌ |
| **附加价值(deposit)** | CALLVALUE | (无直接) | attached_deposit | MessageInfo.funds | msg_value | (无直接) | msg_cycles | fee 参数 | ❌ |
| **链 ID** | CHAINID | 无 | chain_id | block.chain_id | (config 间接) | network id | (无直接) | network_id | ❌ |
| **随机数** | PREVRANDAO⚠️ | 无原生 | random_seed⚠️ | 无内建 | rand⚠️ | (无内建) | raw_rand(management) | ChaCha(finalize) | hintrandom⚠️ |
| **SHA-256** | precompile 0x02 | sol_sha256 | sha256 | 无内建 | string_hash | env.crypto.sha256 | (无直接) | ❌(SHA3) | black-box sha256_compression |
| **Keccak-256** | 指令 | sol_keccak256 | keccak256 | 无内建 | ❌ | (部分) | (无直接) | Keccak | keccakf1600 |
| **Ed25519 验签** | ❌ | precompile | ed25519_verify | 无内建 | check_signature | env.crypto | 链密钥 | ❌(Schnorr) | 外部库 |
| **日志/事件** | LOG0-4 | sol_log_* | log_utf8 | Response.attributes | 无内建(消息) | events | (无直接) | (无) | (无) |
| **KV 存储** | storage slots | account data | KV host | KV trait | c4 cell | storage+TTL | stable memory | mapping | Merkle witness |
| **跨合约调用** | CALL | CPI | promise(多区块) | SubMsg(同交易) | send_raw_message(fire-forget) | invoke | inter-canister | 系统程序调用 | oracle/外置 |
| **治理/质押** | ❌ | Stake program | validator_stake | Staking/Gov 全家桶 | ❌ | ❌ | management | bond/unbond | ❌ |
| **IBC/跨链** | ❌ | ❌ | ❌ | IBC 一等公民 | ❌ | ❌ | ❌ | ❌ | ❌ |

> ⚠️ = 存在但**不可靠/不可预测**（各链官方文档均不建议直接用于高价值随机）。

## 4. 统一抽象建议（对项目架构的含义）

### 4.0 系统能力分两层，应统一进同一 catalog（2026-08-05 补充）

调研初版只覆盖 **L1 内建运行时能力**（host function / syscall / opcode / stdlib）。经产品
owner 指出，系统能力还有 **L2 官方链上程序**层：各链由协议官方部署/内建的链上程序
（builtin program / system contract / precompile / management canister / 链级模块），对
调用方而言与 L1 一样是"可调用的系统能力"。Solana 的 System/Token/ATA/Stake/ComputeBudget
program、EVM 的 precompile 与 EIP-4788 等系统合约、TON 的 Elector/Config、ICP 的
`aaaaa-aa`、Aleo 的 `credits.aleo`、Cosmos 的 x/bank/x/staking 链模块、Soroban 的 SAC
均属此层。**关键洞察：同一能力在不同链以不同形态出现**（sha256 = EVM precompile /
Solana syscall / NEAR host / TON stdlib；原生转账 = System Program / BankMsg / promise
action / send_raw_message / credits.aleo）——统一抽象的本质是把"能力"与"形态"解耦。
L2 详细清单与"能力 vs 形态"对照表见
[`21-system-programs-survey.md`](21-system-programs-survey.md)。

对抽象设计的含义：
- L1 与 L2 统一进同一个 wire catalog + requirement 行机制；per-target 物化 + 无对应物 FC。
- 官方 program 的**强制等级**须记入 catalog：协议内建（Solana System、EVM precompile、
  Aleo credits.aleo、ICP aaaaaa-aa）vs 官方部署（Solana Token/ATA、NNS canisters）vs
  生态参考（NEAR staking pool、soroban-examples/token）——后者不得冒充系统能力。
- 密码学是 L2 最大的统一候选：`pf.crypto`（EXT-CRYPTO）逐能力 catalog（EVM 最全、TON
  仅 Ed25519+SHA、Aleo 无 SHA-2），缺能力的 target 按行 FC。
- 项目先例已验证 L2 路径：ADR-0030 E1 绑 Solana System/Token/ATA、NEAR NEP-141、CW
  CW20——已是"官方链上程序作为能力"的工程化，待系统化为 catalog 层（SYS-CAP-UNIFY）。

### 4.1 延续现有模式是正确方向

项目现有抽象（`ContextRead` / `EnvRead` + wire catalog + requirement 行 + per-target
物化 + fail closed）与调研结论一致：**统一在语义层，物化在 target 层**。上表显示"时间戳、
高度、调用者、自身余额、附加价值、链 ID"六维在**状态类平台全部有直接对应物**，语义高度
同构，适合继续往 catalog 里加键。**电路类平台统一 fail-closed**，除非引入 Aztec
PublicChecks 式"sequencer 公开执行闭环"——那是独立设计波，不是 ContextRead 能解决的。

### 4.2 建议优先候选（按语义同构度排序）

| 候选 | 语义 | 状态类平台覆盖 | 建议 |
|---|---|---|---|
| `context.blockHeight` | 当前区块高度（UInt64） | 6/7（TON 需间接、ICP 无） | **高优先**：与 unixTimeSeconds 完全同构，`UInt64` result，view 可读 |
| `context.chainId` | 链 ID | EVM/NEAR/CW/Soroban/Aleo 有；Solana/TON/ICP 无或间接 | 中优先：语义（重放保护/域分隔）在链间差异大，建议 `Bytes` 或 `UInt64` 并允许 per-target 语义差异，找不到的 FC |
| `context.attachedValue` | 本次调用携带的资产量 | CALLVALUE / attached_deposit / funds / msg_value | 中优先：注意 Solana 无直接对应（SOL 转账经指令），价值单位不统一（wei/yoctoNEAR/denom），需仔细设计 |
| `context.signer` | 交易签名者（tx.origin 类） | 仅 EVM ORIGIN / NEAR signer（view 禁）/ Aleo signer | **低优先且谨慎**：view 禁止 + Solana/CW/TON 无此概念，语义分歧大 |
| `envRead.*` 扩展 | 其他账户余额等 | 各链形态差异大（BALANCE vs AccountInfo vs BankQuery） | 按 E2 模式逐个加键 |

### 4.3 不建议抽象（应保持平台独有或走 extension catalog）

- **随机数**：各链要么没有、要么有偏/可预测/区块级确定性，语义分歧极大，统一抽象会教出
  错误安全模型。**不建议进 ContextRead**。
- **质押/治理/IBC**：CW 一家独有（Cosmos SDK 模块），NEAR 只有只读 stake 查询、Aleo 只有
  bond/unbond。属**业务能力**而非通用系统能力，应走 `pf.assets` 式 extension catalog
  （per-target 独立绑定），不进 ContextRead。
- **PDA/CPI stack height/RawQuery/commit()/config_param/SEND_MODE** 等：平台独有原语，
  各自留在 target Plan 层，不试图统一。
- **密码学预编译全家桶**：各链覆盖不同（EVM 最全、TON 只有 Ed25519+SHA、Aleo 无 SHA-2），
  适合独立 `pf.crypto` extension（ADDR-0030 后 EXT-CRYPTO 候选），按能力逐个 catalog。

### 4.4 对现有抽象的三点修正建议

1. **高度与时间的语义差异要记入 catalog**：EVM NUMBER 是逻辑块号、Solana Clock.slot 约
   400ms 物理槽、NEAR block_index 是链高度、TON 无直接高度（逻辑时间 cur_lt 是其事件序
   来源）。抽象为 `context.blockHeight` 时 per-target 物化须各自选诚实对应物，找不到的
   （TON/ICP）fail closed。
2. **NEAR signer/predecessor 的 view 限制**：`context.caller` 在 NEAR 应映射
   `predecessor_account_id`（view 禁），与 EVM CALLER（view 可读）不一致——view 可读性
   应作为 catalog 行的一个轴记录，而不是假装各链都 view-safe。
3. **电路类平台的时间/高度**：若要支持，必须走 Aztec PublicChecks 式 sequencer 闭环
   （公开执行时用真实链值断言），这是独立设计波，且 Aztec 语境才成立；裸 Noir/Psy 保持 FC。

## 5. 权威来源

- EVM：execution-specs、evm.codes、EIP-4399/4844/7516/2537、go-ethereum precompiles、OWASP SCWE-153
- Solana：solana.com/docs/core/programs/syscall-reference、anza-xyz/agave、docs.anza.xyz/runtime/sysvars
- NEAR：docs.rs/near-sdk、nomicon.io RuntimeSpec BindingsSpec
- CosmWasm：docs.rs/cosmwasm-std（Env/QueryRequest/CosmosMsg/SubMsg）、book.cosmwasm.com
- TON：docs.ton.org/languages/func/stdlib、stdlib.fc 源码、docs.ton.org/foundations/messages
- Aleo：docs.aleo.org（credits-and-transfers、finalization、standard library）
- Noir/Aztec：noir-lang.org、docs.aztec.network（oracles、call_types）、OpenZeppelin Safe Noir Circuits
- Soroban：developers.stellar.org/docs/learn/fundamentals/contract-development
- ICP：docs.internetcomputer.org/references/ic-interface-spec、management-canister
- OpenVM：docs.openvm.dev/specs
- Psy：psy.xyz/docs、QEDProtocol GitHub（**资料不足**，推断已标注）
- Quint：quint.sh

详细 EVM/Solana 逐项清单（opcode/syscall/sysvar 级别）见
[`system-capabilities-evm-solana.md`](system-capabilities-evm-solana.md)。
