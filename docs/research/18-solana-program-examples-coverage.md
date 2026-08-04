---
id: RPT-018
title: QuickNode Solana Program Examples × ProofForge 覆盖评估
status: draft
owner: research
updated: 2026-08-04
normative: false
---

# QuickNode Solana Program Examples × ProofForge 覆盖评估

> 上游：[`quicknode/solana-program-examples`](https://github.com/quicknode/solana-program-examples)
> 固定提交：[`59000a4a324bc1b7902a45cba70dfee042da2483`](https://github.com/quicknode/solana-program-examples/tree/59000a4a324bc1b7902a45cba70dfee042da2483)
> 研究日期：2026-08-03
> 探索：4 轮并行 explorer + 每轮独立 verifier

> **非执行权威**：本文是研究快照，不是第四份 live gap queue，不改变 accepted PRD/SPEC、
> formal `TASK-D5-*`/`TST-SOL-*` 状态或 target maturity。可执行缺口必须回写
> [`engineering-backlog.md`](../engineering-backlog.md) 与
> [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md)。
>
> **范围说明**：本文的 57 项分母只属于 QuickNode 教学应用 corpus，不代表全部 Solana program。
> Anza 维护的 `solana-program` 组织仓库另见 companion
> [`RPT-019`](19-solana-program-org-coverage.md)；其 38 个仓库混合 program、interface、client、tooling、
> example 与 archived 项，不能与本文分母相加或平均。

## 1. 结论先行

### 1.1 是否应把 57 个示例逐个对等实现？

**不应把“57 个目录全部移植”作为产品目标。** 正确目标是：

1. 把 57 个示例冻结为外部兼容 corpus；
2. 将每个示例拆成业务规则、Solana 账户力学、协议 pack 和 SDK/运维部分；
3. 对共享能力实现少量独立 probe；
4. 对资金、权限、签名、CPI 与回滚保留应用级 E2E golden；
5. 未实现的能力精确 fail closed，而不是用日志、Map 余额或近似地址冒充。

逐目录移植会重复大量 Anchor/Quasar/Pinocchio/Native/ASM 变体，也会把 Token-2022、
Metaplex、Bubblegum、PDA、CPI metas 等 Solana 专属契约错误塞入 target-neutral Semantic。
这与 `OOS-001`、`INV-001/002`、`FR-005/006/013` 冲突。

### 1.2 当前覆盖到底是多少？

需要分开两个完全不同的问题：

- **ProofForge Solana backend 是否有真实能力？** 有。当前已有 retained Semantic →
  target-owned Plan/IR → SBPF assembly → ELF → Mollusk 的工程纵切，覆盖单 state account、
  多宽算术、控制流、pure fn、emit/revert、Array/Map/Bytes/named aggregate、WideMul 和
  Principal wire identity 子集。
- **它是否与 QuickNode corpus 中某个完整示例的 Solana 外部行为严格等价？** 在本文定义的
  whole-example strict equivalence 口径下，当前为 **0/56 runtime-bearing examples**；另有一个
  `repository-layout` 是非 runtime 教学项。这个数字**不表示 backend capability 为零**，只表示
  当前没有一个完整示例同时闭合它所声明的账户、PDA、System/SPL CPI、失败和回滚行为。

### 1.3 最大的当前正确性问题

**2026-08-03 implementation update（#111）**：两个 legacy Solana profiles 已删除
`effect.synchronous-call` 与 `effect.asynchronous-workflow` support claim；Plan/IR/SBPF 对旧节点纵深
fail closed，static `QualifiedName` 不再经 SHA-256 冒充 program id，原 `sol_log_data` call/schedule
观测桩不可达。以下段落保留研究时发现的问题，真实 CPI/account metas 仍由 epic #110 实现：

- [`RequirementResolverV1.lean`](../../ProofForgeV2/Targets/RequirementResolverV1.lean)
- [`EmitSbpfAsmV1.lean`](../../ProofForgeV2/Targets/Solana/EmitSbpfAsmV1.lean)
- backlog：[`B-CALL-SEM`](../engineering-backlog.md)

因此 P0 必须先使 capability claim 与真实物化一致；在此之前不得把 static-QN stub 写成 CPI 支持。

**2026-08-03 #115/#116 engineering update**：harness-only caller/companion 已在 pinned Mollusk 上真实执行
multi-account ABIv1、canonical PDA/bump、`invoke`/`invoke_signed` success/failure、return-data 与 rollback；
随后 exact extension requirement/provenance 与 `solana-sbpf-cpi-elf-v1` membership 已接线。该 profile仍不含
sync/async support，并在 legacy Plan生成前 fail closed、零制品；System/Token/ATA 也未 admission，
所以 whole-example strict equivalence 仍为 **0/56**。

**2026-08-03 #117/#118 engineering update**：target-owned CPI Plan/IR/IDL 已由 inspection DTO 扩为
exact capability + retained Semantic sole-derived authority，并新增 handler-local 16-role ABIv1 preflight
emitter。`AccountRoles` 的 generated assembly经 locked `sbpf` 与 committed manifest绑定后在 Mollusk通过
init/route/view、0/16/17 role boundary和 22 个 one-mutation account checks；但该 ELF明确是
production-code-generated **test-preactivation** evidence，不是产品 artifact，且不含任何 invoke/PDA。
因此下表中 ACCT 只能标为“preflight engineering subset”，`CPI`/`PDA`与 strict equivalence仍不变。

**2026-08-04 #119 engineering update**：独立 `CpiUnsignedIRV1`/`EmitCpiUnsignedSbpfV1` 在仍为
`activationDenied`/test-preactivation 的 `solana-sbpf-cpi-elf-v1` lane 上，对 pinned companion-v1
发射真实 unsigned `sol_invoke_signed_c`（零 signer groups）与成功路径 `sol_set_return_data(0,0)`；
#118 no-invoke 链保持独立。`CompanionCpi` 证明 state write → CPI → post-call write 的 source order，
以及 fail 路径完整 snapshot rollback + `fail:v1!` 保留；committed unsigned manifest 绑定
source/profile/extension 与 #115 companion ELF pin。准确称谓仍是 **production-code-generated
test-preactivation unsigned-CPI ELF**，不是 `OutputFile`/产品 artifact/activated sync；ordinary
resolver 仍拒 sync。#120 PDA/bump/`invoke_signed` 与 #121+ 仍 pending，whole-example strict
equivalence 仍为 **0/56**；`CPI`/`PDA` 产品面与 formal D5 不因 #119 改写。

**2026-08-04 post-#125 TransferSol engineering update**：active
`solana-sbpf-cpi-elf-v1` 已可从 tracked `Examples/TransferSol.lean` 经 ordinary resolver 生成
manifest-bound 产品 ELF；Mollusk 固定真实 native System CPI、成功余额/return data 与失败回滚。
独立 Rust client 消费 manifest/Plan/IR/IDL/bindings，并预留显式 Devnet 调用与 Loader V3/receipt
核对；部署和具体公开 Program ID 仍由 operator 提供，未执行 live Devnet 前不写成链上闭环。
本切片只覆盖 QuickNode 的 CPI transfer 路径；上游同例还包含 program-owned lamport 直接变更/
close 语义（`CLOSE`），因此本报告的 whole-example strict-equivalence 仍为 **0/56**，表中
`transfer-sol` 继续 `NO`，不得仅因这条 analogue 改为 `SE`。

## 2. 方法与分母

### 2.1 分母规则

固定上游 commit 后，以“逻辑示例”计数：

- 同一逻辑例的 Anchor / Quasar / Pinocchio / Native Rust / ASM 变体只计一次；
- companion mock program、Kani harness、客户端和资源文件不另计；
- nested packaging（如 `nft-meta-data-pointer/anchor-example/anchor`）仍计一个逻辑例；
- `tools/shank-and-codama`、`tokens/quasar-metadata`、`.assets` 不属于 program corpus。

机械目录结果：

| 组 | 数量 |
|---|---:|
| Basics | 16 |
| Finance | 9 |
| Classic tokens | 7 |
| Token-2022 non-hook | 14 |
| Transfer hooks | 8 |
| Compression | 3 |
| **合计** | **57** |

根 README 只列出 7 个 transfer-hook 例；tree 中另有 Pinocchio-only
`tokens/token-extensions/transfer-hook/block-list`，因此 README 视角的 56 不是固定 tree 的完整分母。

### 2.2 Strict equivalence 定义

对 runtime-bearing example，只有下列量词全部成立才标为 `STRICT-EQ`：

> 在同一声明的链上入口表面和账户前置条件下，成功、失败、回滚，以及示例测试观察的外部状态与
> effects（account data、lamports、token balances、logs/events）均与 ProofForge 物化的 Solana
> artifact 等价。

不要求 Anchor/Quasar 源码、SBPF bytes、IDL 或账户布局逐字相同；允许 target-owned 编码不同，
但归一后的业务观察不可不同。

## 3. 三轴分类

单一“支持/不支持”会混淆等价程度、阻塞原因与产品归属，因此本文使用三轴。

### 3.1 等价程度 `EQ`

| 值 | 含义 |
|---|---|
| `SE` | Whole-example strict equivalence 当前成立 |
| `PP` | 已有相近真实 runtime surface，但账户/CPI/ABI 等仍不同 |
| `BA` | 业务规则可做 ProofForge analogue；不得声称 Solana platform parity |
| `NO` | 当前没有诚实的 whole-example partial/analogue 声明 |
| `NA` | 非 runtime 产品目标 |

### 3.2 阻塞能力 `BLOCKERS`

| 代码 | 能力 |
|---|---|
| `ACCT` | 显式 account model：role/order/owner/signer/writable/init |
| `SYS` | System Program CPI |
| `PDA` | seeds/bump/program-id domain 与 `invoke_signed` |
| `CLOSE` | account close / lamport reclaim / direct lamport move |
| `REALLOC` | account data realloc |
| `SPL` | Classic SPL Token CPI |
| `ATA` | Associated Token Program |
| `T22` | Token-2022 与 extensions |
| `THOOK` | Transfer-hook execute + ExtraAccountMeta |
| `META` | Metaplex Token Metadata |
| `COMPR` | Bubblegum/account-compression/Merkle proof accounts |
| `REMAIN` | 动态 `remaining_accounts` |
| `ORACLE` | 外部价格账户、可信度与 freshness |
| `SECP` | keccak + secp256k1 recover/verify |
| `CPI` | 任意 program-to-program CPI |
| `SYSVAR` | Clock/Rent/Instructions 等 material sysvar |
| `SESSION` | session-key delegated auth 子特性 |

### 3.3 产品处置 `DISP`

| 值 | 含义 |
|---|---|
| `CUR` | 当前可用作 ProofForge probe，但不是 strict-equivalence 声明 |
| `CORE` | 依赖核心 Solana 平台 primitive |
| `PACK` | 必须成为 versioned、closed protocol/extension pack |
| `OOS` | 整个示例不是 runtime 产品目标 |

`SESSION` 可以是某个 `PACK` 内的 OOS 子特性；不能因此把整个 metadata-pointer 示例删掉。
`DISP` 只表示该 row 的主导处置，不会覆盖 `BLOCKERS`：例如标为 `CORE` 的 classic-token row
若同时含 `META`，strict equivalence 仍必须关闭对应 versioned metadata pack，不能只完成 SPL primitive。

## 4. 57 项逐例矩阵

### 4.1 Basics（16）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 1 | account-data | `basics/account-data` | PP | `ACCT, SYS` | CUR |
| 2 | checking-accounts | `basics/checking-accounts` | NO | `ACCT` | CORE |
| 3 | close-account | `basics/close-account` | NO | `PDA, CLOSE` | CORE |
| 4 | counter | `basics/counter` | PP | `ACCT, SYS` | CUR |
| 5 | create-account | `basics/create-account` | NO | `SYS, SYSVAR` | CORE |
| 6 | cross-program-invocation | `basics/cross-program-invocation` | NO | `CPI, ACCT` | CORE |
| 7 | favorites | `basics/favorites` | BA | `PDA, ACCT, SYS` | CORE |
| 8 | hello-solana | `basics/hello-solana` | PP | `ACCT` | CUR |
| 9 | pda-rent-payer | `basics/pda-rent-payer` | NO | `PDA, SYS, SYSVAR` | CORE |
| 10 | processing-instructions | `basics/processing-instructions` | BA | `ACCT` | CUR |
| 11 | program-derived-addresses | `basics/program-derived-addresses` | BA | `PDA, ACCT, SYS` | CORE |
| 12 | pyth | `basics/pyth` | NO | `ORACLE, SYSVAR, ACCT` | PACK |
| 13 | realloc | `basics/realloc` | NO | `REALLOC, SYS, ACCT` | CORE |
| 14 | rent | `basics/rent` | NO | `SYS, SYSVAR` | CORE |
| 15 | repository-layout | `basics/repository-layout` | NA | — | OOS |
| 16 | transfer-sol | `basics/transfer-sol` | NO | `SYS, CLOSE` | CORE |

### 4.2 Finance（9）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 17 | betting-market | `finance/betting-market` | BA | `SPL, PDA, CLOSE` | CORE |
| 18 | escrow | `finance/escrow` | BA | `SPL, PDA, ATA, CLOSE` | CORE |
| 19 | lending | `finance/lending` | BA | `SPL, PDA, ORACLE, SYSVAR` | CORE |
| 20 | order-book | `finance/order-book` | BA | `SPL, PDA, REMAIN, SYSVAR` | CORE |
| 21 | perpetual-futures | `finance/perpetual-futures` | BA | `SPL, PDA, ORACLE, SYSVAR` | CORE |
| 22 | prop-amm | `finance/prop-amm` | BA | `SPL, PDA, ORACLE, SYSVAR` | CORE |
| 23 | token-fundraiser | `finance/token-fundraiser` | BA | `SPL, PDA, ATA, SYSVAR, CLOSE` | CORE |
| 24 | token-swap | `finance/token-swap` | BA | `SPL, PDA, ATA` | CORE |
| 25 | vault-strategy | `finance/vault-strategy` | BA | `SPL, PDA, ATA, ORACLE, CPI, SYSVAR` | CORE |

这些示例的 AMM 曲线、LTV、fee、matching、NAV、escrow 状态机可以形成业务 analogue；
但 token custody、oracle authenticity、PDA authority 与 remaining accounts 是正确性的一部分，
不能只实现数学后声称平台等价。

### 4.3 Classic tokens（7）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 26 | create-token | `tokens/create-token` | NO | `SPL, META, SYSVAR` | PACK |
| 27 | external-delegate-token-master | `tokens/external-delegate-token-master` | NO | `SECP, SPL, PDA` | CORE |
| 28 | nft-minter | `tokens/nft-minter` | NO | `SPL, META, ATA, SYSVAR` | PACK |
| 29 | nft-operations | `tokens/nft-operations` | NO | `SPL, META, PDA` | PACK |
| 30 | pda-mint-authority | `tokens/pda-mint-authority` | NO | `PDA, SPL` | CORE |
| 31 | token-minter | `tokens/token-minter` | NO | `SPL, META` | CORE |
| 32 | transfer-tokens | `tokens/transfer-tokens` | NO | `SPL, META` | CORE |

### 4.4 Token-2022 non-hook（14）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 33 | basics | `tokens/token-extensions/basics` | NO | `T22, SYS` | PACK |
| 34 | cpi-guard | `tokens/token-extensions/cpi-guard` | NO | `T22, PDA` | PACK |
| 35 | default-account-state | `tokens/token-extensions/default-account-state` | NO | `T22` | PACK |
| 36 | group | `tokens/token-extensions/group` | NO | `T22` | PACK |
| 37 | immutable-owner | `tokens/token-extensions/immutable-owner` | NO | `T22, SYS, SYSVAR` | PACK |
| 38 | interest-bearing | `tokens/token-extensions/interest-bearing` | NO | `T22` | PACK |
| 39 | memo-transfer | `tokens/token-extensions/memo-transfer` | NO | `T22` | PACK |
| 40 | metadata | `tokens/token-extensions/metadata` | NO | `T22` | PACK |
| 41 | mint-close-authority | `tokens/token-extensions/mint-close-authority` | NO | `T22, CLOSE` | PACK |
| 42 | multiple-extensions | `tokens/token-extensions/multiple-extensions` | NO | `T22, SYS` | PACK |
| 43 | nft-meta-data-pointer | `tokens/token-extensions/nft-meta-data-pointer` | NO | `T22, SESSION` | PACK |
| 44 | non-transferable | `tokens/token-extensions/non-transferable` | NO | `T22, SYS, SYSVAR` | PACK |
| 45 | permanent-delegate | `tokens/token-extensions/permanent-delegate` | NO | `T22` | PACK |
| 46 | transfer-fee | `tokens/token-extensions/transfer-fee` | NO | `T22, REMAIN` | PACK |

MetadataPointer 只表示 Token-2022 指向 metadata 的 extension，不等于 metadata schema/create/update/verify
已支持；示例中的 session-key 游戏子面单独 OOS。不同 Token-2022 extensions 也不能机械任意组合，
必须按 account size、初始化顺序、authorities、required accounts 与 transfer path 冻结兼容矩阵。

### 4.5 Transfer hooks（8）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 47 | account-data-as-seed | `tokens/token-extensions/transfer-hook/account-data-as-seed` | NO | `T22, THOOK, PDA` | PACK |
| 48 | allow-block-list-token | `tokens/token-extensions/transfer-hook/allow-block-list-token` | NO | `T22, THOOK, PDA` | PACK |
| 49 | block-list | `tokens/token-extensions/transfer-hook/block-list` | NO | `T22, THOOK, PDA, CLOSE` | PACK |
| 50 | counter | `tokens/token-extensions/transfer-hook/counter` | NO | `T22, THOOK, PDA` | PACK |
| 51 | hello-world | `tokens/token-extensions/transfer-hook/hello-world` | NO | `T22, THOOK` | PACK |
| 52 | transfer-cost | `tokens/token-extensions/transfer-hook/transfer-cost` | NO | `T22, THOOK, SPL` | PACK |
| 53 | transfer-switch | `tokens/token-extensions/transfer-hook/transfer-switch` | NO | `T22, THOOK, PDA` | PACK |
| 54 | whitelist | `tokens/token-extensions/transfer-hook/whitelist` | NO | `T22, THOOK, PDA` | PACK |

### 4.6 Compression（3）

| # | 示例 | 上游路径 | EQ | BLOCKERS | DISP |
|---:|---|---|---|---|---|
| 55 | cnft-burn | `compression/cnft-burn` | NO | `COMPR, REMAIN, CPI` | PACK |
| 56 | cnft-vault | `compression/cnft-vault` | NO | `COMPR, REMAIN, PDA, CPI` | PACK |
| 57 | cutils | `compression/cutils` | NO | `COMPR, REMAIN` | PACK |

### 4.7 汇总

| EQ | 数量 |
|---|---:|
| Strict equivalent | 0 |
| Platform partial | 3 |
| Business analogue | 12 |
| None | 41 |
| N/A/OOS | 1 |
| **合计** | **57** |

| DISP | 数量 |
|---|---:|
| Current probe | 4 |
| Core primitive | 23 |
| Versioned pack | 29 |
| OOS | 1 |
| **合计** | **57** |

## 5. 当前 ProofForge Solana 事实

### 5.1 已有纵切

| 能力 | Source/Semantic | Plan/IR/SBPF | Mollusk |
|---|---|---|---|
| Typed discriminator/params/return | 有 | 有 | 有 |
| 单 state account CRUD | 有 | 有 | 有 |
| UInt/Int 算术、shift/bit、Bool/assert | 有 | 有 | 多个正负例 |
| if/match/bounded for/pureFn | 有 | 有 | 有 |
| emit/revert | 有 | `sol_log_data`/custom error | 有 |
| Array/Map/Bytes/named aggregate | 非均匀子集 | flatten/pilot | ArraySlots/MapMini 等 |
| UInt128/256 mul | 有 | schoolbook | WideMul |
| Principal | opaque identity | 9×UInt64 leaves | PrincipalStore；**非 pubkey** |

当前 Plan 是**单 state-account**模型：state account 固定 index 0；handler 对该账户执行 instruction
length、current-program owner、exact data length、初始化 header，以及按 mode 推导的 signer/writable
检查。SBPF 对非零 account index fail closed。代码入口：

- [`LowerSemanticV1.lean`](../../ProofForgeV2/Targets/Solana/LowerSemanticV1.lean)
- [`EmitIRV1.lean`](../../ProofForgeV2/Targets/Solana/EmitIRV1.lean)
- [`EmitSbpfAsmV1.lean`](../../ProofForgeV2/Targets/Solana/EmitSbpfAsmV1.lean)

### 5.2 明确缺失或 fail closed

| 能力 | 当前事实 |
|---|---|
| Multi-account / order / alias | #118 已有 retained-Semantic-derived target Plan/IR + 16-role preactivation parser/constraints；#119 在同一 lane 接 unsigned companion CPI，仍无产品 artifact |
| PDA / seeds / bump / signer | 产品缺失；#115 仅 pinned-runtime golden/feasibility，#120 pending |
| System create/transfer/close/realloc | 缺失；#118 只 preflight `transfer` roles，不执行 System CPI |
| Lamports 语义 | assembly 可做 exact preflight read，无业务读写/转账 |
| True CPI | 产品缺失且三个 profile 均 fail closed；#115 harness-only feasibility；**#119** 为 production-code-generated test-preactivation unsigned companion CPI（真实 `sol_invoke_signed_c` 零 signer groups + rollback 矩阵），**不是** OutputFile/产品 sync/activated support；#120+ pending |
| Classic SPL / ATA | 缺失 |
| Token-2022 / Metaplex | 缺失 |
| Clock/Rent/Instructions sysvar | shared ContextRead 部分存在，Solana Plan fail closed |
| Remaining accounts | 缺失 |
| Pyth/Switchboard oracle | 缺失 |
| Runtime crypto / compression | 缺失 |
| Multi-instruction transaction model | 当前 Mollusk harness 不提供产品语义门 |
| Reference↔Mollusk adapter | 不存在 |

## 6. 当前测试基线

本研究从源码机械重算：

- `runtime-tests/solana/tests/counter.rs`：8 个 `#[test]`；
- `runtime-tests/solana/tests/programs.rs`：52 个 `#[test]`；
- 合计 **60**；13 个 fixture + Counter = **14 programs**。

按本研究的人工分类：

| 类别 | 数量 | 说明 |
|---|---:|---|
| Positive runtime | 43 | 含单条 reference-shaped Counter chain |
| Negative runtime | 15 | 算术、shift、assert、bound、revert、unknown discriminator、wrong owner |
| Artifact/static only | 2 | artifact presence 与 discriminator property |

当前 checkpoint 文档报告 60 个均 active/pass；本研究未重跑会删除并重建 runtime output 的
`just solana-runtime`。上述 43/15/2 是审计分类，不是测试源码中的机器标签。

### 6.1 最大测试缺口

owner/signer/writable/header checks 已经发射，但账户安全负例目前只有
`counter_wrong_owner_check_fails`。缺少至少：

- initializer missing signer；
- mutate read-only；
- double init；
- mutate/view uninitialized；
- wrong account data length；
- malformed header；
- trailing/short instruction data 的合同；
- multi-account substitution、alias 和 privilege escalation（未来能力）。

`counter_reference_trace_chain` 只是多次单 instruction 的顺序 harness，不是通用
Reference adapter，也不是一笔 multi-instruction transaction。

Formal 状态保持不变：[`TASK-D5-01..05`](../04-task-breakdown.md) 全部 `pending`。

## 7. 测试架构

### 7.1 七层 gate

| 层 | Gate | 通过标准 |
|---|---|---|
| L1 | Source/Typed | 语法、类型、effect、bound、disclosure 正负例 |
| L2 | Semantic/requirements | canonical carrier、exact requirements、unsupported 不丢失 |
| L3 | Solana Plan | account roles/layout/CPI sites/resource assumptions 完整且 canonical |
| L4 | SBPF/ELF | syscall/static structure、frame limit、locked assembler、ELF validation |
| L5 | Mollusk single-instruction | success/error、account state、return data、logs、单 ix rollback |
| L6 | Multi-step harness | 顺序故事；必须标注 **非 multi-instruction tx 原子性** |
| L7 | Reference differential | 未来 adapter；当前 `N/A`，不得由 L6 冒充 |

### 7.2 Oracle provenance

| Oracle | 来源 | 能证明 | 不能证明 |
|---|---|---|---|
| `O-MATH` | target-neutral 纯函数/手算/独立实现 | 业务数学和 state transition | ABI、账户、CPI |
| `O-ABI` | PF ABI 规格 + 第二实现/golden | PF discriminator/layout/return encoding 自洽 | Anchor/Solana 生态兼容 |
| `O-RT` | Mollusk/SVM 实际执行 | 该 ELF 在该 runtime 上的行为 | PF 语义本身正确或主网等价 |
| `O-QN` | 固定上游示例的外部合同 | 与选定示例行为兼容 | 未声明路径、生产安全 |
| `O-REF` | `ReferenceV1` | target-neutral Outcome 行为 | account meta、PDA、SPL/CPI 物理语义 |

Rust `common` helper 与 Lean lowering 镜像相同 domain/formula，属于双实现一致性，不是完全独立 oracle。
关键 ABI 应另有固定 golden/mutation；Plan 只能做 cross-check，不能反过来生成期望值。

### 7.3 风险交互矩阵

| 交互 | 代表 probe | 最低正例 | 最低攻击/不变量 | 当前 |
|---|---|---|---|---|
| owner×signer×writable×header | auth-state | init/mutate/view 合法三角 | wrong owner、missing signer/writable、double/uninit；失败 state hold | Partial |
| PDA×program-id×bump | PDA vault | canonical derivation 可写 | wrong seed/bump/program-id；无 partial write | Blocked |
| CPI metas×privilege×rollback | hand→lever | callee state 精确变化 | missing writable/false signer/alias；callee fail 全回滚 | Blocked |
| System create×rent×owner×len | create-account | owner/len/lamports exact | underfund/existing/wrong program；无残留 | Blocked |
| SPL authority×mint×decimals×conservation | SPL transfer | src−n,dst+n | wrong authority/mint/ATA；失败双侧 hold | Blocked |
| sysvar identity×freshness | time/oracle | fixed Clock fixture | fake sysvar、stale/future boundary | Plan FC |
| compression root×proof×replay | cNFT | valid proof once | wrong root/leaf/index/replay；state hold | Blocked |

普通 set-cover 不能替代这些交互。资金、权限、签名和原子性至少要覆盖关键 pairwise，必要时覆盖三元组。

### 7.4 应用级 golden

| Golden | 合同 | 当前 |
|---|---|---|
| Counter | init→increment→get；overflow state hold | Pass（工程） |
| Calc guard | arithmetic/assert/shift/bound 成功与失败 | Pass（工程） |
| Event flow | emit 成功；revert 后 state/effect 不提交 | Pass（工程子集） |
| Auth state | owner/signer/writable/header 攻击矩阵 | Partial；测试不足 |
| Classic SPL transfer | raw amount 守恒、authority、wrong mint/ATA、失败 hold | Blocked；P1 forcing golden |
| PDA+CPI escrow | deposit/release/refund、wrong caller/seeds、CPI fail rollback | Blocked；P1 exit gate |
| Oracle feed | trusted account/freshness/price branch；当前 stub 不算 | Blocked/Plan FC |

### 7.5 禁止单一“100%”

只能分别报告：

- capability contracts；
- critical interactions；
- application goldens；
- attack negatives；
- runtime differential points；
- unsupported closure；
- Reference adapter；
- multi-instruction transaction semantics。

`N/A` 不能写成 0%，unsupported 也不能算“已支持”。

## 8. 推荐代表集

不移植 57 个目录；使用约 18–20 个 probe 覆盖主能力，同时保留不可替代交互：

| 层 | 代表例 |
|---|---|
| Current core | counter、hello-solana、processing-instructions |
| Account/System | checking-accounts、create-account、transfer-sol、close-account、realloc |
| PDA/CPI | favorites、cross-program-invocation、pda-rent-payer |
| Classic token/DeFi | transfer-tokens、pda-mint-authority、escrow、token-swap |
| Dynamic/oracle/crypto | order-book、pyth、external-delegate-token-master |
| Protocol packs | nft-minter、te-basics、multiple-extensions、th-hello-world、transfer-fee、cnft-burn |

不可被普通 set-cover 吸收的项包括：PDA-as-rent-payer、System vs direct lamports、account substitution、
arbitrary CPI、remaining-account matching、oracle staleness/confidence、secp nonce、Metaplex collection、
transfer-hook seed modes、transfer-fee harvest 和 cNFT custody/replay。

## 9. P0–P2 路线

这只是研究建议。执行时只更新现有 backlog/matrix，不建立新的 roadmap authority。

### P0：诚实与当前基线，**不增加平台能力**

1. **裁决 `B-CALL-SEM`**：当前 Solana sync/async support 要么降为 fail closed，要么使用一个明确不占用
   `effect.synchronous-call` 最终语义的 observe-only 身份；推荐在真实 CPI 前先降级。
2. **schedule 与 sync 分离**：Solana `schedule` 默认 fail closed；若未来支持，必须是独立 versioned contract。
3. 冻结工程观察映射：runtime status/error → Outcome 三态；account business leaves → logical state；
   return data → value；account precondition 失败不等于业务 `false`。
4. 补当前单账户安全矩阵并重标现有 60 tests；不写成 Reference differential。
5. ContextRead 保持当前 Plan fail closed，除非 `B-CTX-OPEN` 另做产品决定。
6. 继续明确 engineering ELF/Mollusk ≠ formal D5。

**P0 退出门**：claim 与 runtime 一致；call/schedule 无假 CPI；当前安全矩阵有明确负例；零新 platform capability。

关联现有权威：`B-CALL-SEM`、`C-5`、`B-ctx`、`B-CTX-OPEN`。

### P1：垂直 explicit-account + real CPI + classic SPL

P1 不做 primitive waterfall，而做三条垂直切片：

1. **P1a explicit-account roles/security**：新 Plan policy/version；多账户 role/order/owner/signer/writable；
   substitution 与 privilege 负例；旧单账户 ABI 不静默改变。
2. **P1b PDA + System + true sync CPI**：seeds/bump/program-id、必要 System 最小闭包、真实
   `invoke`/`invoke_signed` 与 callee failure rollback。未来真实 CPI 必须使用新 contract/version/digest
   或显式 major cutover，不能让同一 support identity 从日志桩静默变真。
3. **P1c classic SPL/ATA transfer**：固定 classic token program/version 与最小 transfer 闭包；
   明确 `NS-1` Map token 不是 SPL Token。

**P1 硬退出门**：一个 PDA + true CPI + classic SPL transfer 的 escrow forcing golden，必须同时覆盖：

- token amount conservation；
- PDA custody；
- wrong seeds/owner/signer/account substitution；
- inner CPI failure 后调用方、vault 与用户余额无半写。

Schedule 全阶段保持 fail closed 或独立版本，不复用 sync CPI 路径。P1 完成仍不代表 formal D5。

关联现有权威：`B-CALL-SEM`、`C-5`、`T-1`、FR-013 extension 区、`NS-1`（仅作逻辑 token 对照）。

### P2：可选、versioned protocol packs

仅在 P1 exit 后按独立产品决定开放：

- `EXT-CRYPTO` / oracle；
- remaining accounts / order-book；
- Token-2022（不可任意组合）；
- Metaplex；
- Bubblegum/account compression；
- 更复杂 DeFi application probes。

每个 pack 必须有 exact semver/digest、依赖与兼容矩阵、正例、攻击负例和 pack 外 fail-closed 测试。
未选择的 pack 保持精确拒绝，不做 best effort。

## 10. 验证记录

| Claim | 方法 | 结果 |
|---|---|---|
| 上游分母 | 固定 commit tree，按逻辑叶去重 | 57；README 漏一个 transfer-hook block-list |
| 本地 runtime tests | `rg '#[test]'` | 60（8+52） |
| 本地 fixture 数 | `runtime-tests/solana/fixtures/*.lean` | 13 + Counter = 14 programs |
| Call/schedule 实现 | 直接审 `EmitSbpfAsmV1` | 两者调用 `sol_log_data`；注释明确 full CPI follow-on |
| Plan account 模型 | 直接审 Lower/IR/ASM | 单 state account index 0；非零 index FC |
| Formal D5 | `docs/04-task-breakdown.md` | TASK-D5-01..05 全 pending |
| 当前 maturity | dossier/AGENTS/code/tests 交叉 | 工程 ELF+Mollusk 子集；非 formal/Stage-0/hermetic |

## 11. 盲点与限制

- 本研究没有在本次会话中重跑完整 `just solana-runtime`；当前“60 active/pass”来自项目 checkpoint，
  本研究只机械重算源码数量并审查测试内容。
- 上游 57 例是教学 corpus，不是生产审计或 Solana 全能力目录；它未覆盖的能力不能据此判定不需要。
- 代表性金融测试对 oracle、MEV、并发、坏账和全局会计不变量的强度不一致。
- LiteSVM/Mollusk 与 mainnet feature set、program versions、compute behavior 仍需各 pack 冻结。
- `OutcomeV1` 只定义 target-neutral 核；lamports、account owners、CPI account graph、CU 与 multi-ix tx
  需要分层观察，不能硬塞入同一跨 target值。
- 本文不批准新的 extension、support claim、Plan schema 或 accepted scope；实现前仍需产品决定。

## 12. 最终答案

**不要对等实现 57 份源码；要对等实现一组版本化能力合同，并用少量高价值应用 golden 验证组合。**

最先要做的不是 Token-2022 或更多 DeFi 例，而是：

1. 关闭 `B-CALL-SEM` 的假支持风险；
2. 补当前单账户安全负例；
3. 用新版本 contract 建 multi-account/PDA/System/真实 CPI；
4. 以 classic SPL transfer + PDA/CPI escrow 作为 P1 架构退出门；
5. 之后才按 versioned pack 选择 oracle、Token-2022、Metaplex、compression 等长尾能力。

只要每个 corpus row 最终都有“strict equivalent / business analogue / exact unsupported / OOS”之一，
并且 capability、interaction、golden、attack、runtime 与 unsupported closure 分别可审计，就完成了
**诚实的覆盖评估**；这比“57/57 能编译”更有价值，也更符合 ProofForge 的 target-neutral 使命。
