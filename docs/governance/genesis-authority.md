---
id: GOV-GENESIS-001
title: 自举信任根与 genesis 关闭协议
status: proposed
owner: quality
updated: 2026-07-17
normative: true
---

# 自举信任根与 genesis 关闭协议

本文件是 C2 级治理修订（影响全部任务的完成判定），需 Architecture + Quality 书面批准，
批准记录补齐后方可转为 `accepted` 并生效。与 [`task-freeze.md`](task-freeze.md)、
[`authority.md`](authority.md)、[`change-control.md`](change-control.md) 并用；
冲突时本文件只管辖"自举期任务如何合法关闭"，技术语义仍以 accepted ADR/spec 为准。
本文件不得单独生效：`GOV-MAINTAINERS-001`、`GOV-AUTH-001`、`GOV-CHANGE-001` 与
`GOV-TASK-FREEZE-001` 必须在同一批准行为中转为 `accepted`，五份文档均须记录
`architecture-owner, davirain, quality-owner` 的批准，且五份 frontmatter 的 `approvers`、
`approvedAt`、`reviewCommit`、`reviewLink`、`openFindings` 必须逐字节相同。

## 1. 问题

1. 稳态规格（[`../traceability/evidence-schema.md`](../traceability/evidence-schema.md)）
   假设签发 `TaskApprovalV1` / authenticated receipt 的 authority 已存在；该 authority 是
   `TASK-D0-04` 的交付物。于是 D0-04 的全部上游任务在"需要批准才能关闭、批准者尚不存在"
   的循环里无法合法关闭。
2. 2026-07-17 已发生五次 Freeze Exception（`FX-2026-07-17-D0-01`、`FX-2026-07-17-D0-02`、
   `FX-2026-07-17-D0-03`、`FX-2026-07-17-D0-05`、`FX-2026-07-17-D0-06`），其"批准"栏均
   指向仓库自身记录，无实名人类批准；其中 D0-03 缺 §8 强制字段、D0-06 在 task-freeze.md
   中无 exception 记录，且 `FX-2026-07-17-D0-02` 直接违反了任务表"agent 不得自行选择
   后者"的注记。`TASK-D0-06` 的错误关闭随后被 reopen 纠正。
3. 逐任务"一次性 exception，不得推广"不收敛：每个任务撞同一堵墙，防推广条款逐次收窄，
   被约束者在关单 commit 中同步改写门禁放行自己（TFP-004 循环论证）。
4. 本文件用**一次人类批准的 genesis 行为**替代逐任务自我 exception，并把信任升级义务
   显式绑定到 `TASK-D0-07`。

## 2. 定义

| 术语 | 含义 |
|---|---|
| Genesis 任务集合 | 精确集合 `TASK-D0-01`、`TASK-D0-02`、`TASK-D0-03`、`TASK-D0-05`、`TASK-D0-06`（即 `TASK-D0-04` 的全部完成依赖闭包；`TASK-D0-04` 本身不是 genesis 任务，它是 authority 的建造者）。集合见 [`genesis-set.lock.json`](genesis-set.lock.json)，静默新增需 Architecture + Quality 批准并同变更更新 lock |
| Genesis 关闭 | genesis 任务允许以 development 级证据 + attest + **本文件的人类批准**关闭；关闭时不要求存在 signed `TaskApprovalV1` / authenticated receipt |
| Cutover | `TASK-D0-04` 的 six-item `BootstrapApprovalSetV1` activation 生效点为 cutover；其后一切任务关闭必须持规范签名对象，genesis 路径永久失效 |
| 信任升级义务 | genesis 关闭是临时低级别关闭，不是永久豁免（见 §5） |

## 3. 对既有关闭的追认（Ratification）

本文件及上述四份治理依赖经 Architecture + Quality 批准（approval 五字段齐全）后生效，
生效时：

1. **追认** `FX-2026-07-17-D0-01`、`FX-2026-07-17-D0-02`、`FX-2026-07-17-D0-03`、
   `FX-2026-07-17-D0-05` 的关闭为 genesis 关闭；task-freeze.md §11 各 exception 记录的
   批准来源统一改为指向本文件。追认依据是五个任务的独立技术复审结论（P0=0；D0-01/02
   交付真实且可复现；D0-03/05 收窄切片真实、deferral 披露诚实）。
2. **不追认** `FX-2026-07-17-D0-06`：该关闭已被 reopen 纠正（程序上 reopen 不符合
   task-freeze.md §2，但实质是撤销错误关闭，予以认可）；`TASK-D0-06` 须在补全其冻结
   inScope（含 JCS encoder / domain-separated hash / ID 与 path parser / 完整
   ResourceProfileV1 profile）并经独立技术复审后，按 genesis 关闭重新关闭。
3. **追认 Phase 1–3（PHASE-1/2/3）的 `accepted`**：批准来源改为本文件；三份文档的
   `reviewCommit`/`reviewLink` 在本文件落地时更新为真实记录。原 `reviewCommit` 指向
   纯日志 commit 的记录方式作废，不得再用。
4. 追认以**同一变更集修复下列已登记 P1 缺陷**为附条件（不修复不生效）：

   | # | 缺陷 | 位置 |
   |---|---|---|
   | F1 | EVF record `finalizedUtc` 伪造分支：日期不符应拒绝而非改写 record | `scripts/gate_evidence.py` `_publish_development_finalization` 日期分支 |
   | F2 | `EV-20260717-0031` 命令栏失真（缺 host 命令、attest 路径空）；docs_check 不校验命令栏 | `docs/traceability/evidence-ledger.md`、`scripts/docs_check.py` |
   | F3 | D0-03 attest 的 `deferred-incomplete` 已被 `9e3e6ffa` 还清却被 checker 钉死 | `docs/governance/bootstrap-closure/TASK-D0-03.attest.json`、`scripts/docs_check.py` |
   | F4 | 任务表 D0-02 blocked 注记与表格行自相矛盾 | `docs/04-task-breakdown.md` D0 节后段落 |
   | F5 | docs_check 的 D0-02/03/05/06 attest 放行分支零 mutation 覆盖 | `scripts/docs_check_self_test.py` |
   | F6 | solc SPDX 跨文件矛盾（`GPL-3.0-only` vs `GPL-3.0-or-later`）+ SBOM 生成不自 lock 闭合 | `toolchains.lock.json`（仓库根）、`docs/supply-chain/license-inventory.v1.json`、`scripts/sbom_generate.py` |
   | F7 | SBOM root 组件 digest 悬空、不可复现 | `docs/supply-chain/license-inventory.v1.json` |
   | F8 | `just sbom` 未接入 `just ci` / `just check`，"development gate" 名不副实 | `justfile` |
   | F9 | `licenses/Apache-2.0.txt`、`licenses/MIT.txt` 为占位文本，非许可证正文 | `licenses/` |

5. **登记延期项（deferred，未立项不得视为已交付）**：

   | 项 | 去向 |
   |---|---|
   | D0-05 的 release binding、SBOM↔lock closure 重算、per-executable/per-dylib 粒度、`05-test-spec.md:140` 全量语义 | 新任务 `TASK-D0-08`（见 §6） |
   | D0-03 的 `TST-TOOL-001` timeout 腿、`TST-HOST-001` 环境/lock mutation negatives | P2 债务，owner=quality，截止 D0-07 关闭前 |
   | D0-01 的 attest `consumerCommit` 语义、`Rejected` truthy 返回形态 | P2 债务，并入 D0-04 authority 对象设计 |
   | signed `TaskApprovalV1` / authenticated receipt（D0-01/02/03/05 关闭时豁免项） | `TASK-D0-04` 交付 + `TASK-D0-07` 补票（§5） |

## 4. Genesis root key（离线根）

1. 由实名 maintainer（[`maintainers.md`](maintainers.md)）执行离线仪式生成 Ed25519
   root key；私钥不入库、不进 CI；只把公钥写入
   `docs/governance/genesis-root-policy.json`。没有该文件或文件未通过下述 exact validator，
   本文件即使 frontmatter 标为 `accepted` 也不得生效。
2. pre-cutover 根使用独立 `GenesisRootPolicyV1`，**不得**伪装成
   `BootstrapAuthorityPolicyV1`。后者要求多 principal quorum、private-scan policy、authority
   store 与 verifier digest，均属 D0-04 稳态交付；在 genesis 文件中填 placeholder 会重新引入
   自举循环并必须 fail closed。
3. `GenesisRootPolicyV1` 是无 trailing newline 的 canonical PF-JCS closed object，字段精确为：

   | 字段 | 精确约束 |
   |---|---|
   | `schema` | `proof-forge.genesis-root-policy.v1` |
   | `id` / `version` | `proof-forge-genesis-root` / `1.0.0` |
   | `authorityDocument` / `maintainersDocument` | `GOV-GENESIS-001` / `GOV-MAINTAINERS-001` |
   | `principalId` | `davirain` |
   | `keyId` | safe-id，由离线仪式显式输入，不得自动随机生成 |
   | `algorithm` / `publicKey` | `ed25519` / 32-byte lowercase hex canonical prime-subgroup public key |
   | `allowedSchemas` | 精确单元素数组 `proof-forge.bootstrap-authority-policy.v1` |
   | `cutoverTask` | `TASK-D0-04` |
   | `postCutoverDisposition` | `revoke-and-historical-only` |

   object key 必须按 UTF-16 code unit canonical order；duplicate/unknown/missing field、非 canonical
   bytes、无效/小阶/非 prime-subgroup key 全部拒绝。policy ContentRef digest 为
   `SHA-256(UTF8("pf.genesis-root-policy.v1") || 0x00 || canonicalBytes)`。
4. generator 只接受调用者提供的**公钥**并做 validate/generate；不得提供生成、读取或持久化私钥
   的代码路径。离线 maintainer 负责生成和保管 private seed，再把 public key 作为普通输入带回。
   仓库侧仅执行 [`scripts/genesis_root_policy.py`](../../scripts/genesis_root_policy.py)：
   `generate --key-id <safe-id> --public-key <64-lowercase-hex> --output
   docs/governance/genesis-root-policy.json`，随后以 `validate --input
   docs/governance/genesis-root-policy.json` 复核；两条命令均须由 `/usr/bin/python3 -I -S` 启动。
5. genesis root 只允许签发首个 `BootstrapAuthorityPolicyV1`。D0-04 authority activation 后，
   genesis root 经 revocation/rotation 退役；其后所有对象由稳态多-principal policy 管辖，root
   历史记录进入 implementation log 与 evidence ledger。

## 5. 信任升级义务（防永久低级别）

`TASK-D0-07` 的 `doneWhen` 必须包含（落地时写入其冻结完成包）：

1. 在 **eligible host** 上重放全部 genesis 任务的冻结 `TST-*` 集合；
2. 由已激活的 authority 按 `D0-01..06` exact 顺序补发六项 approval + task receipt，
   组成 `BootstrapApprovalSetV1` 并完成 activation；
3. 任一 genesis TST 重放失败或补票失败 → `TASK-D0-07` 不得关闭，对应 genesis 任务的
   关闭记录标注 superseded-by-finding 并开 P1 finding。

## 6. 里程碑集合变更：`TASK-D0-08`

经本文件批准，Milestone D0 新增一行 `TASK-D0-08`（SBOM closure / release binding /
executable-dylib 粒度 + `TST-SBOM-001` 全量语义收尾），同变更更新
[`task-set.lock.json`](task-set.lock.json) 与任务表；其 Dependencies 为
`TASK-D0-05`，Tests 为 `TST-SBOM-002`（落地时在 `05-test-spec.md` 定义）。

## 7. 禁令与机器强制

1. 自本文件生效起，**禁止任何新的自我批准 exception**：task-freeze.md §8 的批准字段
   必须解析到本文件或后续同级 `accepted` 人类批准文档；指向本仓库自身
   closeout/log commit 的批准记录一律无效。§11 的 founding-ratification `批准` 整格只允许
   精确值 `Quality + Architecture（经 GOV-GENESIS-001 追认）`（文档中的 ID 使用 code span）；
   历史说明必须放在独立 `历史` 行，不得作为任意后缀混入批准值。
2. docs_check 落地机器规则：exception 批准字段自指 → 拒绝（`PF-DOC-FX-APPROVAL`）；
   EV 命令栏空/attest 路径不存在 → 拒绝；attest 放行分支纳入 mutation 覆盖。
3. 本条自本文件生效后的后续变更起适用：协议文本（task-freeze.md）、门禁
   （docs_check.py）与关单不得出现在同一变更集；门禁变更必须先落地并全绿，关单变更
   单独成集。本文件的首次批准变更是唯一 founding-ratification carve-out：可按 §3.4 在同一
   变更集修复 F1–F9 及其门禁，但**不得**在该变更集中关闭 `TASK-D0-06`；D0-06 仍须在批准
   生效和门禁全绿后以独立变更集关闭。
4. pre-acceptance 工作必须显式标注目标任务，且该任务依赖未闭合时不得关闭；
   唯一 `in_progress` 纪律不变。

## 8. 修订

本文件变更属 C2：Architecture + Quality 批准；生效后 task-freeze.md §11 的 exception
记录只保留历史价值，其批准来源以本文件为准。
