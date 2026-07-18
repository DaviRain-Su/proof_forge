---
id: GOV-PRECUTOVER-001
title: TASK-D0-08 与 TASK-D0-09 pre-cutover 关闭裁决
status: accepted
owner: quality
updated: 2026-07-18
normative: true
approvers: architecture-owner, davirain, quality-owner
approvedAt: 2026-07-18
reviewCommit: 2bbd19bd3e979addbe9dc85ae68c49c8da3eb7e8
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/2bbd19bd3e979addbe9dc85ae68c49c8da3eb7e8
openFindings: none
---

# GOV-PRECUTOVER-001：TASK-D0-08 与 TASK-D0-09 pre-cutover 关闭裁决

本文件是 C2 级治理裁决，经 Architecture + Quality 批准生效。与
[`genesis-authority.md`](genesis-authority.md)（`GOV-GENESIS-001`）同级，是其 §7.1
"后续同级 accepted 人类批准文档"条款下的第二个批准来源；冲突时技术语义仍以
accepted ADR/spec 为准。

## 1. 问题

`TASK-D0-08`（SBOM closure）与 `TASK-D0-09`（linux host profile/tool root/Stage-0
分支）的实现与验收已全部转绿，但二者均不在 genesis 任务集合
（[`genesis-set.lock.json`](genesis-set.lock.json)），docs-check 在 `TASK-D0-07`
之前拒绝 formal 级 EV（`PF-DOC-EVIDENCE-FORMAL-UNVERIFIED`），bootstrap grade 又被
限定在 exact D0-01..06 集合——两任务没有合法关闭路径。其冻结包已预见：
D0-08 doneWhen 第 4 条要求"关闭路径按 cutover 前程序确认……无合法路径时保持
实现+TST 全绿待关闭并升级治理裁决"；D0-09 的 blocker 注记同样指向本裁决。

## 2. 裁决

### 2.1 `TASK-D0-09` → done

doneWhen 逐项确认：

1. TST-HOST-002 先 RED（`06274f19`）后 GREEN（`1ab751ce`），覆盖冻结 inScope
   全部断言——满足。
2. linux CI lane 绿：修复 job-env `runner` context 缺陷（`63df5494`）后，GitHub
   run `29642879415` 的 `linux-tool-root` lane success（provision/materialize/verify
   与 validate linux 分支全过）——满足。
3. darwin 回归：按 ADR-0016 的字节保持设计以**静态保持性验证**认定满足——
   `toolchains.lock.json`（darwin v2）与 D0-09 立项基线 `6dc1d836` 逐字节相等；
   `host-profiles.lock.json` 中 darwin profile 的
   platform/developerTools/systemTools/systemRuntime 逐字段相等（仅 schema id
   v1→v2 与受影响 digest pin 按 ADR 更新）；`verify_host_stage0.sh` 全部 darwin
   语义行保留（仅新增平台分派与空初始化行）；已提交 darwin profile 作为数据经
   v2 验证器校验通过并正确报告 ineligible；TST-HOST-002 自测覆盖 darwin 谓词与
   linux↔darwin 互斥。**递延项**：对真实 darwin 机的 live 重观察
   （`just host-stage0-development` 实机执行）记为 P2 债务，owner=quality，
   截止 `TASK-D0-07` 关闭前，与 `GOV-GENESIS-001` §3.5 的 D0-03 递延同型。
4. ubuntu CI 上生成器产出 ineligible development profile 并被验证器接受——
   满足（lane 内 observe→validate 闭环）。
5. docs-check 与冻结包对齐无完成面漂移——满足。

### 2.2 `TASK-D0-08` → done

doneWhen 逐项确认：

1. TST-SBOM-002 先 RED（`904f8eb6`）后 GREEN，oracle 将冻结 exact counts 固化为
   常量（37 leaf refs、41 components、37 content identities、146 typed
   relationships、10 compiler-runtime、30 file-set、4 standards、3 sidecars），
   不从 production output 动态推导——满足。
2. 三文件 sidecar 在两个 absolute root、不同 HOME/locale/umask 下 byte-identical
   （SB2-001/029），synthetic metadata root hash 等于 candidate archive raw
   SHA-256（SB2-019）——满足。
3. legacy negative、substitution/extra/missing/race 全部零输出拒绝，
   `--verify-existing` 独立全量重算通过（SB2-005/021/023/024/027/028 含逐点
   fault injection；locked-jv 对 pinned CycloneDX schema 实测 ok）——满足。
4. 关闭路径——由本文件确认（见 §3）。
5. docs-check 与冻结包对齐无完成面漂移——满足。

## 3. 机器强制

1. docs_check 对 `TASK-D0-08`/`TASK-D0-09` 增加与 genesis 任务同型的 attestation
   分支：仅当 `docs/governance/bootstrap-closure/TASK-D0-08.attest.json` /
   `TASK-D0-09.attest.json` 通过各自 exact 校验时，对应任务的 bootstrap 级 EV 才
   允许关闭任务；attest 必须逐字记录 `ruling: GOV-PRECUTOVER-001`。
2. bootstrap grade 的 exact 任务集合由 D0-01..06 扩展为 D0-01..06 ∪
   {TASK-D0-08, TASK-D0-09}；其余任务的 grade 规则不变。
3. docs_check_self_test 必须为两个新分支提供 mutation 覆盖（缺字段/错值一律
   `PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED`）。

## 4. 信任升级与边界

1. 两个关闭均为 development 级关闭（同 genesis 关闭的性质），不产生 formal/
   hermetic/release 证据。`TASK-D0-07` 的冻结完成包落地时，其 doneWhen 必须包含
   在 eligible host 上重放 `TST-HOST-002` 与 `TST-SBOM-002`（以及 §2.1 的 darwin
   live 重观察递延项）；本文件不改变 `TASK-D0-07` 当前 pending 行。
2. 本裁决不解除 `TASK-D0-04`/`TASK-D0-07` 的任何前置（eligible host、producer/
   service 基建、activation），不扩展 genesis 集合，不适用于任何其他任务或未来
   切片；不得援引本文件为新的自我批准 exception 开路（批准字段规则不变）。
3. 若任一 attest 被撤销或发现伪造，docs-check 立即重新拒绝对应 bootstrap EV，
   任务须 reopen 并记 P1 finding。

## 5. 修订

本文件变更属 C2：Architecture + Quality 批准；批准记录五字段随变更更新。
