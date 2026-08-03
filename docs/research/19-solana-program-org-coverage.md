---
id: RPT-019
title: solana-program 组织仓库 × ProofForge 覆盖评估
status: draft
owner: research
updated: 2026-08-03
normative: false
---

# solana-program 组织仓库 × ProofForge 覆盖评估

> 上游：[`github.com/solana-program`](https://github.com/solana-program)
> 组织说明固定点：[`solana-program/.github@e76aac1/profile/README.md`](https://github.com/solana-program/.github/blob/e76aac191daaa8dfe2f3a0f93f565d145f0d8472/profile/README.md)
> 仓库清单观察日期：2026-08-03；GitHub repository search 返回 38 项且 `incomplete_results=false`
> 关系：本文是 [`RPT-018`](18-solana-program-examples-coverage.md) 的 companion corpus，不合并两者分母

> **非执行权威**：本文是研究快照，不是第四份 live gap queue，不改变 accepted PRD/SPEC、
> formal `TASK-D5-*`/`TST-SOL-*` 状态或 target maturity。可执行缺口仍只能回写
> [`engineering-backlog.md`](../engineering-backlog.md) 与
> [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md)。

## 1. 范围纠正与结论

### 1.1 此前是否已经调研这个组织？

**没有。** RPT-018 只冻结了 QuickNode 的 57 个逻辑教学示例。本报告补充
`solana-program` 的组织级清单、角色分类和能力增量。

### 1.2 这个组织是不是“全部 Solana program”？

不是。组织 profile 的精确表述是：

> “This organization contains all of the on-chain program tooling maintained by Anza.”

它覆盖 **Anza 维护的** SPL/Core-BPF program、接口、客户端和相关工具；不声称覆盖：

- Solana runtime、SBF VM 与全部 syscalls；
- 仍在 Agave 中的 native processor；
- Metaplex、Pyth、DEX、借贷、桥、钱包等第三方生态程序；
- 历史 SPL monorepo 的每一个项目；
- 用户程序能表达的全部控制流、账户交互或交易行为。

因此应使用三个相互独立的分母：

| 分母 | 单位 | 用途 |
|---|---|---|
| QuickNode corpus | 57 个逻辑示例，56 个 runtime-bearing | 应用故事与 whole-example 外部行为 |
| `solana-program` snapshot | 38 个 GitHub 仓库 | 官方 program、接口、客户端和工具的来源清单 |
| ProofForge capability contracts | account、PDA、CPI、sysvar、pack、tx/deploy 等合同 | 产品真实覆盖与 fail-closed 闭包 |

**不得把 38 个仓库当成 38 个能力，也不得发布 `N/38` 的“Solana 特性覆盖率”。**

### 1.3 对 ProofForge 的直接结论

组织清单不会提高 RPT-018 的 QuickNode strict-equivalence 分数；当前仍是
**0/56 whole-example strict equivalence**。更重要的是，它为真实 CPI 提供了更权威的
callee 合同：System、classic Token 和 ATA 应成为 P1 forcing oracles。

当前 ProofForge Solana backend 仍是单 state-account 模型。2026-08-03 的 #111 honesty cut 已让
两个 legacy profile 对 `call`/`schedule` 双键 fail closed，并删除可达的 `sol_log_data` 观测桩；
但仍没有 account metas、`invoke`/`invoke_signed` 或 inner rollback。因此当前不能声称能够调用、
替代或对等实现本组织中的任何真实 platform program。

## 2. 快照方法与角色分类

### 2.1 清单规则

- 通过 GitHub `org:solana-program` repository search 取公开仓库；观察到 38 项；
- program 与同仓的 IDL/client 只计一个 repository row；
- interface、client-only、example、tooling 和 archived 均保留，但角色不能混算；
- 本次没有为 38 个 default branch 全部冻结 commit SHA，也没有逐 cluster 重验部署地址和
  feature activation；相应事实只作为 2026-08-03 repository snapshot；
- `alpenglow-vote` 是唯一观察到的 archived repo；`account-compression` 默认分支为
  `ac-mainnet-tag`，需单独看待其快照性质。

### 2.2 角色代码

| 代码 | 数量 | 含义 |
|---|---:|---|
| `PROG` | 19 | repo 内包含或承载 on-chain program 实现；部署状态仍需另验 |
| `IFACE` | 3 | 规范接口 + client/example；不是一个统一全局产品 program |
| `ABI` | 6 | native/runtime-special 或 loader 的 IDL/client surface，processor 不在该 repo |
| `EXAMPLE` | 2 | SDK/框架示例 |
| `TOOL` | 6 | library、scaffold、CI、docs 或 migration tooling |
| `ARCH` | 1 | 已归档，权威已迁移 |
| `INC` | 1 | under-construction，尚无稳定合同可审计 |
| **合计** | **38** | repository 数，不是 capability 数 |

## 3. 38 项完整仓库矩阵

“研究处置”只说明如何进入覆盖模型，不是产品批准或 backlog 排期。

| # | Repository | 角色 | 主要 surface | 研究处置 |
|---:|---|---|---|---|
| 1 | [`token`](https://github.com/solana-program/token) | `PROG` | classic SPL Token program + clients | P1 pinned callee |
| 2 | [`token-2022`](https://github.com/solana-program/token-2022) | `PROG` | Token Extensions program + clients | versioned pack |
| 3 | [`create-solana-program`](https://github.com/solana-program/create-solana-program) | `TOOL` | project scaffolding | tooling/OOS |
| 4 | [`system`](https://github.com/solana-program/system) | `ABI` | native System Program IDL + clients | P1 pinned callee |
| 5 | [`stake`](https://github.com/solana-program/stake) | `PROG` | Core-BPF stake lifecycle | staking pack |
| 6 | [`program-metadata`](https://github.com/solana-program/program-metadata) | `PROG` | program metadata PDA + clients/CLI | deploy/metadata pack |
| 7 | [`config`](https://github.com/solana-program/config) | `PROG` | Core-BPF config account | optional platform pack |
| 8 | [`stake-pool`](https://github.com/solana-program/stake-pool) | `PROG` | multi-validator liquid staking | staking pack |
| 9 | [`address-lookup-table`](https://github.com/solana-program/address-lookup-table) | `PROG` | LUT administration; v0 address loading | tx boundary + optional CPI |
| 10 | [`associated-token-account`](https://github.com/solana-program/associated-token-account) | `PROG` | ATA PDA/create program | P1 pinned callee |
| 11 | [`zk-elgamal-proof`](https://github.com/solana-program/zk-elgamal-proof) | `ABI` | native ZK ElGamal proof surface | crypto/proof pack |
| 12 | [`memo`](https://github.com/solana-program/memo) | `PROG` | UTF-8 memo/log program | optional callee pack |
| 13 | [`token-metadata`](https://github.com/solana-program/token-metadata) | `IFACE` | SPL Token Metadata interface | Token-2022 interface pack |
| 14 | [`token-wrap`](https://github.com/solana-program/token-wrap) | `PROG` | Token ↔ Token-2022 wrapping | versioned pack |
| 15 | [`libraries`](https://github.com/solana-program/libraries) | `TOOL` | on-chain helper libraries | reference/tooling |
| 16 | [`feature-gate`](https://github.com/solana-program/feature-gate) | `PROG` | network feature activation/revoke | platform/OOS by default |
| 17 | [`single-pool`](https://github.com/solana-program/single-pool) | `PROG` | single-validator liquid staking | staking pack |
| 18 | [`compute-budget`](https://github.com/solana-program/compute-budget) | `ABI` | runtime-special CU/heap/fee instructions | transaction profile |
| 19 | [`slashing`](https://github.com/solana-program/slashing) | `PROG` | duplicate-block violation reporting | consensus-adjacent/OOS by default |
| 20 | [`actions`](https://github.com/solana-program/actions) | `TOOL` | GitHub Actions | tooling/OOS |
| 21 | [`transfer-hook`](https://github.com/solana-program/transfer-hook) | `IFACE` | transfer-hook interface + example | Token-2022 interface pack |
| 22 | [`counter-shank`](https://github.com/solana-program/counter-shank) | `EXAMPLE` | Shank Counter | example only |
| 23 | [`feature-proposal`](https://github.com/solana-program/feature-proposal) | `PROG` | token-voted feature proposal | network-governance/OOS by default |
| 24 | [`solana-program.github.io`](https://github.com/solana-program/solana-program.github.io) | `TOOL` | documentation + org issues | docs/OOS |
| 25 | [`instruction-padding`](https://github.com/solana-program/instruction-padding) | `PROG` | no-op/wrapped instruction benchmark | test utility, not app coverage |
| 26 | [`record`](https://github.com/solana-program/record) | `PROG` | record/immutable-data program | optional utility pack |
| 27 | [`loader-v3`](https://github.com/solana-program/loader-v3) | `ABI` | upgradeable loader IDL + clients | deploy/upgrade profile |
| 28 | [`token-group`](https://github.com/solana-program/token-group) | `IFACE` | SPL Token Group interface | Token-2022 interface pack |
| 29 | [`loader-v4`](https://github.com/solana-program/loader-v4) | `ABI` | loader-v4 IDL + clients | deploy/upgrade profile |
| 30 | [`.github`](https://github.com/solana-program/.github) | `TOOL` | organization profile/community files | org metadata/OOS |
| 31 | [`counter-anchor`](https://github.com/solana-program/counter-anchor) | `EXAMPLE` | Anchor Counter | example only |
| 32 | [`alpenglow-vote`](https://github.com/solana-program/alpenglow-vote) | `ARCH` | archived; moved to `anza-xyz/alpenglow` | historical/OOS |
| 33 | [`vote`](https://github.com/solana-program/vote) | `ABI` | native Vote Program pointer/client surface | validator consensus/OOS |
| 34 | [`account-compression`](https://github.com/solana-program/account-compression) | `PROG` | concurrent Merkle tree/account compression | versioned pack; snapshot caveat |
| 35 | [`core-bpf-migration-test-cli`](https://github.com/solana-program/core-bpf-migration-test-cli) | `TOOL` | builtin→Core-BPF migration testing | tooling/OOS |
| 36 | [`secp256k1`](https://github.com/solana-program/secp256k1) | `PROG` | secp256k1 verification program/library | crypto pack |
| 37 | [`ed25519`](https://github.com/solana-program/ed25519) | `PROG` | ed25519 verification program/library | crypto pack; activation caveat |
| 38 | [`ed25519-programmatic-signer`](https://github.com/solana-program/ed25519-programmatic-signer) | `INC` | README 标注 under construction | no stable claim |

### 3.1 必须保持的三个名称边界

1. `solana-program/token-metadata` 是 **SPL Token Metadata interface**，不是
   `metaplex-foundation/mpl-token-metadata` 产品程序；不能把两者的 PDA、layout 或 program ID 合并。
2. `account-compression` 提供压缩树程序；Bubblegum/cNFT 产品协议仍是更上一层，不因这个 repo 存在而
   自动获得 Metaplex parity。
3. `NS-1` dense Map token 是 ProofForge 逻辑 token demo，不是 classic SPL Token，也不能作为
   `token` callee 支持的替代证据。

## 4. 相对 QuickNode corpus 的能力增量

| 能力族 | QuickNode RPT-018 | 组织清单带来的增量 | ProofForge 当前 |
|---|---|---|---|
| System account lifecycle | `SYS`, `CLOSE`, `REALLOC` 已出现 | official System IDL/client authority | 缺失真实 CPI |
| Classic Token + ATA | `SPL`, `ATA` 已出现 | pinned callee implementations/contracts | 缺失 |
| Token-2022 | 22 个 extension/hook 教学例 | 更完整 extension/interface/composition surface | 缺失 |
| Metadata | 多处 Metaplex/Token-2022 路径 | SPL metadata interface 与 Metaplex 必须拆分 | 两者均缺失 |
| Staking | 教学 finance 无官方 stake parity | Stake、Stake Pool、Single Pool、Vote dependency | 缺失；应为专用 pack |
| Token wrap | 未单列 | Token ↔ Token-2022 custody/conservation | 缺失 |
| Crypto/proofs | `SECP`、oracle 侧面出现 | secp256k1、ed25519、ZK ElGamal | 缺失；runtime feature-sensitive |
| Compression | `COMPR` 已出现 | official compression program source/snapshot | 缺失 |
| Transaction semantics | 未系统列出 | compute budget、ALT use | ProgramV1 body 外；无产品合同 |
| Deploy/upgrade | 只验证 ELF artifact | loader-v3/v4、program metadata | 有 ELF；无 deploy/upgrade 管理 parity |
| Network governance | 基本未出现 | feature gate/proposal、vote、slashing | 默认 OOS |
| Utility programs | 少量 hello/log | Memo、Record、Instruction Padding、Config | 无真实 CPI；低优先 |

组织清单扩大的是 **callee/pack/transaction/deployment** 边界，而不是 target-neutral 业务语义。

## 5. 当前 ProofForge 对照

| 合同 | 当前事实 | 对组织仓库的影响 |
|---|---|---|
| Explicit multi-account roles/order | Plan 只有 state account index 0 | 不能构造 System/Token/ATA CPI metas |
| Solana pubkey identity | Principal 是 wire identity，非 32-byte pubkey | 不能把 Principal 当 program/account address |
| PDA/seeds/bump | 缺失 | ATA、stake pool、metadata、compression 等均阻塞 |
| True synchronous CPI | `call` 只 `sol_log_data` | 不能声称调用任何 official program |
| `invoke_signed` | 缺失 | PDA authority/custody 阻塞 |
| System lifecycle/lamports | 缺失 | create/allocate/assign/transfer/close 阻塞 |
| Classic Token/ATA | 缺失 | P1 forcing callees 尚不可用 |
| Token-2022/interfaces | 缺失 | 必须保持 versioned pack fail closed |
| Context/sysvars | Solana Plan 对 ContextRead fail closed | Clock/Rent/Instructions/epoch 路径阻塞 |
| Crypto/proof programs | 无 versioned Solana crypto extension | secp/ed25519/ZK 路径阻塞 |
| Transaction builder | ProgramV1 不定义 compute budget/ALT | 应在 profile/publisher 层另建合同 |
| Loader lifecycle | 可生成 ELF，无 deploy/upgrade 流程 parity | 不能声称 loader-v3/v4 支持 |

当前真实能力仍然有价值：retained Semantic → Solana Plan/IR → SBPF/ELF → Mollusk 的单账户工程纵切
已覆盖算术、控制流、state、return、emit/revert、aggregate 与部分多宽运算；但它不等价于上述
platform program interoperability。

## 6. 正确测试分母与 oracle

### 6.1 分开报告五类分数

| Scorecard | 单位 | 例子 |
|---|---|---|
| Plan capability | versioned account/PDA/CPI/sysvar contract | multi-account roles、true CPI |
| Callee readiness | pinned official program version | System、Token、ATA |
| Pack conformance | ABI/feature compatibility matrix | Token-2022、staking、compression |
| Tx/deploy profile | transaction/publisher behavior | compute budget、ALT、loader |
| Application golden | normalized external behavior | QuickNode escrow、token transfer |

不能把 tooling/OOS 算作已支持，也不能把 unsupported 当作支持；`N/A` 必须单独报告。

### 6.2 新增 oracle：`O-SP`

| Oracle | 来源 | 能证明 | 不能证明 |
|---|---|---|---|
| `O-SP` | pinned `solana-program` implementation/IDL + runtime artifact | PF artifact 对真实 official callee 的 account、IX、CPI 行为 | PF portable program 等价于该 official program |

`O-SP` 与 RPT-018 的 `O-QN` 不同：前者验证 callee/pack，后者验证应用故事。两者都不能替代
`O-RT` runtime 观察或 `O-REF` target-neutral reference。

### 6.3 P1 forcing tests

P1 应以三个 official callees 固定架构，而不是移植 38 个 repo：

1. **System**：create/allocate/assign/transfer；wrong signer、owner、rent、address、duplicate create；
2. **classic Token**：mint/account/transfer/burn/close；authority、mint、freeze、amount conservation；
3. **ATA**：wallet + token-program-id + mint 的 PDA；classic 与 Token-2022 地址不得混淆；
4. **组合 escrow**：PDA custody + true CPI + inner failure rollback；调用方、vault 与用户账户均无半写。

最低 runtime oracle 必须读取所有相关 account 的 owner、lamports、data 和 token amount，并检查 inner
instruction 失败后的原子回滚。只检查 `sol_log_data` 或 Plan 文本不算 callee readiness。

### 6.4 P2 pack tests

| Pack | 关键测试 |
|---|---|
| Token-2022/interface | extension init/order/size/combination matrix；hook account resolution；authority attacks |
| Staking | epoch/activation/deactivation、fee/exchange-rate、stake/vote dependency、multi-account conservation |
| Crypto/proof | 官方 vectors、mutation rejects、feature-off fail closed、CU/resource limits |
| Compression | root/proof/index/canopy、concurrent changelog、replay、off-chain indexer differential |
| Token wrap | 1:1 escrow backing、PDA uniqueness、stuck escrow、metadata sync |
| Utility | Memo ordering/UTF-8、Record immutability、Config signer ACL |

### 6.5 Tx/deploy 必须是独立 gate

- compute budget：CU limit、heap、priority fee 与 duplicate/conflict rules；
- ALT：create/extend/freeze/deactivate/close，以及 v0 message 的 address resolution；
- loader-v3/v4：buffer/write/deploy/upgrade/authority/immutability；
- program metadata：canonical PDA、authority、immutable、fetch/decompress。

这些不能塞进 target-neutral Semantic，也不能由单 instruction Mollusk application test 冒充。

## 7. 对 P0–P2 路线的影响

### P0 不变，而且更重要

- 裁决 `B-CALL-SEM`：真实 CPI 前 Solana sync/async claim 必须降级或使用明确 observe-only 身份；
- schedule 保持独立且默认 fail closed；
- 补单账户 owner/signer/writable/header 安全负例；
- 不把工程 ELF/Mollusk 写成 formal D5、CPI 或 transaction parity。

官方 System/Token ABI 的存在会让读者更容易误解 “call supported”，所以 claim honesty 必须先于扩面。

### P1 不变，但 oracle 更权威

P1 顺序仍应是：

1. explicit accounts；
2. PDA + System + true `invoke`/`invoke_signed`；
3. classic Token + ATA；
4. PDA/CPI/SPL escrow forcing golden。

QuickNode 提供应用故事，`solana-program/system|token|associated-token-account` 提供 pinned callee 合同。
这两类证据不能互相替代。

### P2 改为类别化 pack

- Token-2022 + transfer-hook + token-group + SPL metadata interface + token-wrap；
- Stake + Stake Pool + Single Pool；
- secp256k1 + ed25519 + ZK ElGamal；
- account compression；
- 可选 utility packs；
- compute budget、ALT、loader 独立放在 tx/deploy profile，不算 application pack；
- feature gate/proposal、vote、slashing、Alpenglow 默认 OOS，除非另有产品决定。

每个 pack 仍需 exact program id/version/digest、依赖/feature-set 兼容矩阵、攻击负例及 pack 外
fail-closed 测试。本文不批准其中任何 pack。

## 8. 是否要把这些程序逐个对等实现？

**不要。** 对 System、Token、Stake、Vote、loader 等官方 program，ProofForge 的通常目标应该是：

- 生成的用户程序能在版本化 account/CPI 合同下正确调用它们；
- 交易/部署 profile 能正确装配需要的 platform instructions；
- 未选择的 pack 精确 fail closed；
- 对少数高风险组合保留端到端 golden。

把 System、Token 或 loader 用 ProofForge 重新写一遍既不构成 VM 特性覆盖，也会引入错误的替代实现。
只有当某个 repo 的业务状态机本身被选作语言表达力 probe 时，才应写 analogue；也不能因此声称替代
官方部署程序。

## 9. 验证记录与限制

| Claim | 验证 | 结果 |
|---|---|---|
| 组织使命 | 固定 profile README commit | “all … tooling maintained by Anza”，非全生态 |
| 仓库数 | GitHub repository search | 38，搜索返回 complete |
| 清单闭包 | 38 行逐项 + 角色计数 | `19+3+6+2+6+1+1=38` |
| archived | GitHub metadata | `alpenglow-vote` |
| Metadata 边界 | repo title/README | SPL interface，非 Metaplex product |
| 当前 CPI | 本地 `EmitSbpfAsmV1` | call/schedule 均为 `sol_log_data` stub |
| 当前 account model | 本地 Lower/Validate/ASM | 单 state account index 0 |
| formal 状态 | `docs/04-task-breakdown.md` | `TASK-D5-01..05` 全 pending |

限制：

- 38 个 repo 的 default-branch HEAD 没有逐项冻结；组织成员和实现会变化；
- 未逐 cluster 验证 program id、deployed ELF hash、feature activation 或 client/program semver join；
- `ed25519`、`secp256k1`、`slashing`、`account-compression` 等 maturity 需在选择 pack 时重新固定；
- native System/Vote/compute-budget/ZK processor 的完整事实还需以 pinned Agave/runtime 为共同 authority；
- 本组织仍不覆盖 Metaplex、Pyth、全部历史 SPL 与第三方 DeFi，因此不能作为生态 completeness proof；
- 本研究未运行新的 Solana runtime suite，也未修改产品代码。

## 10. 最终答案

`solana-program` 必须纳入 Solana 覆盖研究，但要作为 **official callee / interface / pack / tx-tooling
catalog**，而不是第二份应用示例清单。

正确的完整性目标不是 “57 个 QuickNode 示例 + 38 个 repo 全部重写”，而是：

1. 每个外部应用 row 有 strict/analogue/unsupported/OOS 裁决；
2. 每个官方 callee 有 pinned ABI/runtime oracle 或 exact fail closed；
3. 每个可选 pack 有版本、依赖、组合与攻击矩阵；
4. tx/deploy 能力单独报告；
5. 工具、示例、归档和 network-governance 项不充当 coverage numerator。

按这个口径，ProofForge 当前有真实的单账户 SBPF/Mollusk 工程纵切，但离 Solana platform completeness
仍缺 multi-account、PDA、真实 CPI、System、classic Token/ATA、sysvars 与独立 tx/deploy 合同；
Token-2022、staking、crypto/ZK、compression 等应在这些基础能力之后以版本化 pack 处理。
