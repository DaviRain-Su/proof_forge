---
id: PLAN-COMPLETENESS-ROADMAP
title: ProofForge V2 完善度审查与分阶段执行队列
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# ProofForge V2 完善度审查与分阶段执行队列

> 本文件是 **2026-08-19 完善度审查** 的活执行指针。  
> **不是** formal `TASK-*` / `TST-*` / EV。  
> **不是** 第四份平行 gap 清单：格子仍以
> [`../research/12-target-coverage-matrix.md`](../research/12-target-coverage-matrix.md)
> 为准；勾选只回写 [`../engineering-backlog.md`](../engineering-backlog.md) §12。  
> **不是** formal / accepted-PRD / SPEC 代签。2026-08-19 owner 继续指令后，
> **COMP-1-CALL-SEM-LAND 第一刀**（inspect family + residual 标签）与
> **COMP-1-NORMALIZE-RESIDUAL FC 针**（Field/Principal 源字面量 + Bytes 嵌套穿透）
> 已部分落地；部署地址绑定与 Field/Principal 字面量开放仍 pending。ADR 仍 `proposed`。

范围边界：[`../adr/0036-engineering-scope-and-evm-formal-lighthouse.md`](../adr/0036-engineering-scope-and-evm-formal-lighthouse.md)
（工程 **13+0**，仍 `proposed`）。SPEC 分裂收口：
[`../adr/0051-spec-honesty-external-call-return.md`](../adr/0051-spec-honesty-external-call-return.md)
（仍 `proposed`；accepted 前不得改 `semantic-core.md`）。

---

## 0. 三条完成轴（互不代签）

产品链已通：

```text
单次 read → Loader/ProgramV1 → CheckV1 → NormalizeV1
  → CompiledSemanticV1 → certifyInlineProofV1
  → TargetRegistryV1 + RequirementResolverV1
  → 13 × target-owned Plan/IR → Finalize → proof-forge.output.v1
```

registry = **13 implemented + 0 design-only**；resolver = **17 rows**。
Goal-auto / LH-1…28 / Track F **已空**。不要再开 lighthouse pin。

| 轴 | 当前 | 真正完成长什么样 |
|---|---|---|
| **A. 工程纵切** | 13 个 materializer 吃 retained `SemanticProgramV1`，按 capability fail closed | 语言面剩余缺口闭合或显式 FC；每 target 诚实天花板钉死；resolver 声称 = 平台语义 |
| **B. accepted PRD Phase-1** | 仍是四目标：EVM / Solana / NEAR / Noir | 一份 Counter 四目标 + overflow 状态不变；EVM/Solana/NEAR 本地 runtime；**Noir witness/prove/verify**；PrivateSum4 隐私；OutputSet 可重现 + clean-room |
| **C. Formal + release** | D1–D4 = **0/27**；`TASK-D1-01` 卡资格主机；无 `just release-check` | formal SupportClaim / `OutputSetV1` / Reference↔Anvil（C-3）/ Stage-0 / SBOM ceremony |

工程 13 叶 **不等于** accepted 产品范围，更不等于 formal。
Cairo / RISC0 / SP1 / Move / 比特币 **不进本队列**。

---

## 1. 分层缺口（审查事实）

### 1.1 语言 / D1

已强：13 种声明、递归 `pfType`、语句/表达式/place/pattern 大子集、v2 export、
span/origin join、B8b 诊断、进程内 Loader。

工程仍差：Field/Principal **源字面量**与 Bytes 嵌套穿透仍 TypeCheck FC（已有
产品针；开则须十三叶同时 Lower 或命名 FC）。Map 嵌套穿透 `m[k].x := v` 已开
（N-NEST-IDX）。Enum/Option 嵌套构造器子模式已开；产品 parser 仍拒单分量
struct pattern。Field 排序/`mod` 仍 FC。TypeKey unused rejection 仍 deferred。

formal：TASK-D1-01…07 pending；D1-08 产品层已删，不恢复监督层。

### 1.2 Typed / CheckV1

已强：七相位产品门。工程仍差：context/extension 与 authority/custody 是子集，
不是 formal TST-VIS-002 / 完整 extension catalog。formal TASK-D2-01…04 pending。

### 1.3 Semantic / Normalize / Reference

Wire structure gate 已能容纳完整 op 集。缺口在 Normalize 子集、Reference 执行子集、
以及 SPEC 分裂（`semantic-core` 仍写 void-call；产品 N-CALL-RET 已有 typed return；
ADR-0051 已起草）。CodecInvert 九字段是 transport invert，**不**关 TST-SEM-001。
LH pin **不**关 TST-SEM-002/003。C-3 / Anvil lossless 仍 fail closed。

### 1.4 Registry / capability

已强：`TargetRegistryV1`、engineering resolver、S6 capability-only Plan、S7a–c disk closure。

仍差：**B-CALL-SEM**（resolver 支持键 ≠ 平台语义）；SYS-CAP S5/L2 官方 program catalog；
**B-COMMIT-ZK**；D3-E8 evidence grade 只解析不进 resolver；RES-1B 真计量另批。
formal：无 `registryDigest` / SupportClaim / BuildIdentity mint / formal `OutputSetV1`。

### 1.5 十三 target 距该族工程完成

| Target | 下一刀（仅 owner 拍板后） | 未拍板时只做 |
|---|---|---|
| EVM | 部署地址绑定；Bool/Int/Bytes returndata 按决策开或钉 FC | hashed QN stub 保持 PARTIAL；C-3 保持 FC |
| Solana | product CPI callee / 外层账户 ABI；Token/ATA binding 诚实化 | async 保持 FC；Mollusk 不进 ordinary `just ci` |
| NEAR | sandbox overflow rollback | view caller/attachedValue 保持 FC |
| Noir | 仅在推翻 C-4 后做 prove/verify | compile-only；不得把 nargo compile 写成 prove |
| CosmWasm | B-CALL-SEM 地址；可选 wasmd rung-2 | query ContextRead / sha256 保持 FC |
| TON | schedule callback | **不**解冻 pf.assets |
| ICP | inter-canister await Plan | PocketIC 继续 host-optional |
| Quint | QUINT-2 ITF/MBT/verify | Q0 `.qnt` 零工具 |
| Soroban | SOR-1 locked Wasm + auth/TTL | S0 `.rs` non-deployable |
| OpenVM | 独立 prove/execute profile（新 ADR） | O0/O1 不声称 verifiable-workload |
| Aleo / Psy | 重开 VM/proof 必须新 ADR | Instructions / DPN 发射 |
| XRPL | TIME/CALLER 叶；AlphaNet 另批 | Q0 source + Q1 ambient wasm extra |

Capability 横切（2026-08-19）：`sha256Bytes` 五叶已开；`merkleVerifyKeccak256` 仅 EVM；
十二 target 对 Merkle **命名 FC** 是正确边界。不要发明 CAP-7/8/9。

---

## 2. 阶段 0 — 推荐冻结（proposed；等人拍）

本阶段 **不**把 ADR 标 `accepted`，**不**改 accepted PRD，**不**改 `semantic-core.md`。
下列四句是审查冻结的**推荐口径**，owner 未盖章前只约束「不得发明相反声称」。

| ID | 问题 | 推荐冻结 | 状态 |
|---|---|---|---|
| **COMP-0-CALL-SEM** | call/schedule「完成」是部署地址、hashed stub + 文档诚实、还是按族拆？ | **按族拆**。已是 AGENTS caveat：EVM 真实 CALL + hashed stub PARTIAL；schedule = 同笔 tx fire-and-forget；Solana product sync CPI、async FC；NEAR promise / CW SubMsg / TON message；Noir relation slot；Aleo 双拒。**禁止** resolver 支持键冒充跨平台 call 完成。部署地址绑定另 ADR，见 [`evm-call-addr-gap.md`](evm-call-addr-gap.md) | owner-directed 2026-08-19（按族拆诚实已开刀；ADR 仍 proposed） |
| **COMP-0-NOIR-PROVE** | 是否推翻 C-4「不升格 prove」？ | **不推翻**。nargo compile-only 保持。Phase-1 DoD 字面（Noir witness/prove/verify）**仍未满足**；若长期保持 compile-only，须另开 PRD 修订，不得假装已满足 | proposed / 等人拍 |
| **COMP-0-ADR-0036** | ADR-0036 `proposed` → `accepted`，并改 12+0 为 13+0？ | **工程事实改为 13+0**（本审查已改 ADR 正文计数；含 XRPL ADR-0049/0050）。**status 仍 `proposed`**。accepted PRD 仍四目标 | 计数已对齐；acceptance 等人拍 |
| **COMP-0-SPEC-HONESTY** | semantic-core void-call 旧句 vs 产品 N-CALL-RET：改 SPEC 还是改叙事？ | **改 SPEC**，采纳已起草的 ADR-0051（typed return 一等；schedule 维持 void）。**accepted 前不得改 semantic-core** | ADR-0051 proposed；acceptance 等人拍 |

附带可并行拍板（不阻塞阶段 1 文档，但阻塞对应叶编码）：

- CAP-D-XRPL-TIME / CALLER：yes 才开叶；SHA 已 keep-FC
- SOR-1 / QUINT-2 / DOC-JUST-CONTROL / RES-1B 真计量：做或不做
- 十三叶是否永远保持「accepted 仍四目标」——推荐冻结：**是**

---

## 3. 阶段 1 — 共享核收口（串行；解锁所有 target）

一次一个 shared-core cutover。leaf 才可并行。

| ID | 项 | 依赖 | 状态 |
|---|---|---|---|
| **COMP-1-SPEC-ALIGN** | ADR-0051 accepted 后修订 `semantic-core.md` + corpus 对齐；无新 Sem00x pin | COMP-0-SPEC-HONESTY owner 接受 | pending |
| **COMP-1-NORMALIZE-RESIDUAL** | 嵌套穿透赋值；仍拒绝的构造器嵌套；Field/Principal 源字面量（开则十三叶同时 Lower 或命名 FC） | 无（可先做 FC 针） | **partial** — Field/Principal 源字面量 + Bytes 嵌套穿透产品 FC 针；Map 穿透已是 N-NEST-IDX；开字面量/Bytes 穿透另批 |
| **COMP-1-TYPEKEY-REST** | TypeKey 剩余 usage-closure → StructureV1 | 不关 TASK-D2-06 | **partial** — Stage D 已接线；剩余 SPEC 匿名 rank 字节序（人拍）+ formal |
| **COMP-1-CALL-SEM-LAND** | 先改 resolver/文档/针，再按 COMP-0 做 EVM 部署地址、Solana 外层账户、CW `contract_addr` | COMP-0-CALL-SEM 人拍 | **partial** — 十三 kind inspect 表面针（human+JSON）+ evm/solana/cosmwasm `callScheduleResidual` 地址缺口标签 + ExtFlow/LaterFlow xrpl 针；地址绑定仍 pending |
| **COMP-1-SYS-CAP-L2** | 官方 program catalog：有 host 就 exact 一行一叶，无 host 就命名 FC | SYS-CAP S1–S4 已闭 | **partial** — attachedValue inspect + `cryptoHonesty` 十三 kind 闭表 + cw/xrpl/psy residual；新官方叶仍 pending |
| **COMP-1-COMMIT-ZK** | Psy/Noir Commit 设计钉；未冻 binding 前继续 FC | ADR-0041 已 proposed | pending |
| **COMP-1-D3-E8** | evidence grade 语义冻结后再进 resolver | 先语义，再门禁 | pending |

验证：聚焦 Lean suite + `Tests/Materialization/Targets.lean` 针 + `just docs-check`。
改 `ProofForgeV2/**` 后 `just sbom-package-files-refresh`。合并前 `just ci`。

---

## 4. 阶段 2 — accepted 四目标工程 DoD

在阶段 0 的 Noir/call 决策之后。这是 **产品 Phase-1 工程解读**，**不是** formal D4–D7。

| ID | 项 | 状态 |
|---|---|---|
| **COMP-2-EVM-ADDR** | static-QN → 真实 deployment-address binding；Bool/Int/Bytes returndata 按决策；C-3 保持 FC | pending |
| **COMP-2-SOL-CPI** | product CPI callee / 外层账户；Token/ATA `artifactBinding` 诚实化；WideDiv runtime 差分；async 保持 FC | pending |
| **COMP-2-NEAR-OVERFLOW** | sandbox Counter overflow rollback；view ContextRead 保持 FC 并写死 dossier | pending |
| **COMP-2-NOIR-PRD** | 若 COMP-0 不推翻 C-4：另开 PRD 修订 FR-008 / Phase-1 DoD。若推翻：独立 `NoirProveAcceptance` | pending |

四目标共同：Counter overflow 状态不变的 **工程** runtime 证据。不写 EV，不关 TST。

---

## 5. 阶段 3 — 其余九叶诚实天花板

默认不主动扩面。每叶最多一条「下一 profile」，且必须先有 ADR。

| ID | 叶 | 下一刀 | 状态 |
|---|---|---|---|
| **COMP-3-CW** | CosmWasm | B-CALL-SEM 地址；可选 wasmd rung-2 | pending |
| **COMP-3-TON** | TON | schedule callback；不解冻 pf.assets | pending |
| **COMP-3-ICP** | ICP | inter-canister await；Candid 富类型另批 | pending |
| **COMP-3-QUINT** | Quint | QUINT-2 Tool Lock + ITF/MBT/verify | pending |
| **COMP-3-SOR** | Soroban | SOR-1 locked Wasm + auth/TTL | pending |
| **COMP-3-OVM** | OpenVM | 独立 prove/execute（新 ADR） | pending |
| **COMP-3-NATIVE** | Aleo / Psy | 重开 VM/proof 必须新 ADR | pending |
| **COMP-3-XRPL** | XRPL | TIME/CALLER 叶；AlphaNet 另批 | pending |

---

## 6. 阶段 4 — Formal lighthouse（资格轴；不进日常编码）

```text
合格主机 + TASK-D1-01
  → TASK-D2-06 / TST-SEM-001
    → TASK-D2-07 / TST-SEM-002/003
      → D3 SupportClaim / OutputSetV1
        → D4 + C-3 Reference↔Anvil lossless
```

| ID | 项 | 状态 |
|---|---|---|
| **COMP-4-FORMAL** | 上列顺序；禁止工程 pin / 他 target positives 代签；禁止发明 EV | pending / blocked-on host |

前置：COMP-0-SPEC-HONESTY accepted。单维护者默认做不了资格仪式。

---

## 7. 阶段 5 — Release qualification（独立轴）

| ID | 项 | 状态 |
|---|---|---|
| **COMP-5-JUST-CONTROL** | 显式设计 `governance-check` / `release-check`，或永久写「不可执行」 | pending（产品决策） |
| **COMP-5-STAGE0** | 直接 `scripts/verify_host_stage0.sh --require-eligible`；无 just 包装冒充 | pending |
| **COMP-5-REVIEW** | clean-room / SBOM ceremony / [`../07-review-report.md`](../07-review-report.md)（现 `not_started`） | pending |

不得用 `just ci` 绿代签 release。

---

## 8. 不要做的事

- 不要再开 `prompt-next-wave` / 再钉 Sem00x / 把 TST-SEM-002/003 标 done
- 不要把 ordinary `just ci` 写成 hermetic / formal / release
- 不要静默把 accepted PRD 从四目标改成十三
- 不要新增 Cairo/RISC0/SP1/Move/BTC target
- 不要恢复已删的 frontend 监督层
- 共享核一次一把

---

## 9. 下一刀

日常编码下一刀仍是 **B-CALL-SEM 残差绑定**（EVM 部署地址 / Solana 外层账户 / CW
`contract_addr`），或有真实 host 的官方 program 一叶，**不是**
把 B-CALL-SEM 标 closed。COMP-1 inspect 标签（call / attachedValue / crypto）
与 NORMALIZE FC 针已部分落地；字面量/Bytes 穿透开放、TypeKey SPEC rank 与
ADR 仍 proposed。
