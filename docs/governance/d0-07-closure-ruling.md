---
id: GOV-D0CLOSE-001
title: TASK-D0-07 bootstrap 级关闭裁决与 formal 边界
status: proposed
owner: quality
updated: 2026-07-19
normative: true
---

# GOV-D0CLOSE-001：TASK-D0-07 bootstrap 级关闭裁决与 formal 边界

本文件是 C2 级治理裁决，经 Architecture + Quality 批准生效。与
[`genesis-authority.md`](genesis-authority.md)（`GOV-GENESIS-001`）、
[`pre-cutover-closure-ruling.md`](pre-cutover-closure-ruling.md)（`GOV-PRECUTOVER-001`）
同级，是 `GOV-GENESIS-001` §7.1 "后续同级 accepted 人类批准文档"条款下的第三个批准
来源；冲突时技术语义仍以 accepted ADR/spec 为准。

## 1. 问题

`TASK-D0-07` 的实现与验收已按其冻结包转绿（fixture 验收域，ADR-0018），但
docs-check 的完成 grade 规则（`validate_tasks`）要求非 bootstrap 集合任务的 done EV
必须为 **formal** 级，而 formal EV 在"D0-07 formal finalizer 与 candidate-bound
evidence-set binder 存在前"一律被 `PF-DOC-EVIDENCE-FORMAL-UNVERIFIED` 拒绝。按
ADR-0018 §1，fixture 产出永不构成 formal evidence；对真实 activation 的 77-ID
formal partition 与 real catalog 归 `TASK-D8-04`/`TST-ISO-003`。于是 D0-07 与当年
D0-08/09 一样没有合法关闭路径——这是本裁决要解决的问题，不是新的自我批准
exception。

## 2. 裁决

### 2.1 `TASK-D0-07` → done（bootstrap 级关闭）

doneWhen 逐项确认（冻结包
[`task-freeze-packages/TASK-D0-07.json`](task-freeze-packages/TASK-D0-07.json)）：

1. `TASK-D0-04` done 且 current non-revoked `BootstrapApprovalSetV1` activation 存在
   ——满足（`EV-20260719-0075`，candidate `ecd5b5a9…`）。
2. `TST-EVIDENCE-002` 先 RED 后绿——满足：fixture 验收链（`revocation_ledger.py`、
   `private_scan.py`、`formal_input_producers.py`、`formal_evidence_finalizer.py`
   单快照 orchestrator、`formal_evidence_acceptance.py` rehearsal）全部先 RED 后绿
   （`EV-20260719-0076`…`EV-20260719-0080`），负例矩阵按 test-spec 2045-2068 条目。
3. `TST-ISO-002` 先 RED 后绿——满足：bwrap stage 引擎（ADR-0018 §2，
   `EV-20260719-0081`）与 `formal_clean_room.py` harness + `v2-clean-room` recipe
   （`EV-20260719-0082`）：权威 Stage-0 `--require-eligible`、product-tree anchor
   前后不变、空环境/cache、materialize/core deny-all-network、evm-runtime loopback
   内 Anvil differential + LAN/adjacent-port refusal、containment receipt、fixture
   formal EV。
4. formal evidence-set finalization 产生并经全 consumer 复验；freshness/private
   scan/revocation/session containment 各由对应 policy rule 签发且全链验证——满足
   （fixture namespace，`EV-20260719-0079`、`EV-20260719-0080`）。
5. genesis §5 信任升级重放全绿：eligible host 上全部 genesis TST 与
   `TST-HOST-002`/`TST-SBOM-002` 重放通过——满足（`just genesis-replay` post-commit
   报告，见关闭 attest 引用的报告 digest；darwin-only legs 由 §3.2 的 P2 债务机制
   覆盖，非静默 skip）。
6. darwin live 重观察与 D0-03 递延两项 P2 清偿——**关闭前置**，见 §3.2；清偿证据
   记入关闭 attest。
7. docs-check 与冻结包对齐无完成面漂移——满足（见关闭 attest 的 docsCheckCommand）。

### 2.2 formal 边界（不稀释）

1. 本关闭为 **bootstrap 级**：fixture namespace 验收不产生 formal/hermetic 证据；
   formal-EV 解锁（"D0-07 formal finalizer 与 candidate-bound evidence-set binder"）
   专指对**真实 activation** 的 formal evidence set，归 `TASK-D8-04`/`TST-ISO-003`，
   届时另行落地 docs_check 的 formal-EV 验证分支。
2. `TASK-D0-07` 关闭后，后续任务的 done EV grade 规则不变：bootstrap 集合不扩大
   （仅按 §3.1 加入 `TASK-D0-07` 自身），其余任务仍需 formal 级——该 formal 路径在
   D8 之前保持 fail closed。
3. 本裁决不解除任何其他任务的前置，不适用于未来切片；若 attest 被撤销或发现
   伪造，docs-check 立即重新拒绝 `TASK-D0-07` 的 bootstrap EV，任务须 reopen 并记
   P1 finding。

## 3. 机器强制与关闭前置

1. docs_check 对 `TASK-D0-07` 增加与 genesis/GOV-PRECUTOVER-001 同型的 attestation
   分支：`bootstrap_tasks` 集合加入 `TASK-D0-07`；仅当
   `docs/governance/bootstrap-closure/TASK-D0-07.attest.json` 通过 exact 校验时，
   `TASK-D0-07` 的 bootstrap 级 EV 才允许关闭任务；attest 必须逐字记录
   `ruling: GOV-D0CLOSE-001`；docs_check_self_test 为新分支提供 mutation 覆盖
   （缺字段/错值一律 `PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED`）。
2. 关闭 attest 必须同时记录：(a) genesis 重放报告的路径与 digest（post-commit
   全绿）；(b) darwin live 重观察证据（Mac 实机 `just host-stage0-development` 的
   执行记录，GOV-PRECUTOVER-001 §2.1 递延清偿）；(c) D0-03 递延两项
   （`TST-TOOL-001` timeout 腿、`TST-HOST-001` 环境/lock mutation negatives）的清偿
   说明；三者缺一，attest 不得通过校验。
3. 门禁变更（docs_check 分支）与关单变更（attest + EV + 任务行）按
   GOV-GENESIS-001 §7.3 分属两个变更集，门禁先行并全绿。

## 4. 边界

1. `TASK-D0-07` 的关闭不声称 hermetic clean-room gate 的 formal 语义；fixture
   namespace 的 catalog、EV、containment、handoff 均为 development maturity。
2. `05-test-spec.md` 的 fixture 文字同步仍为 P2 债务（ADR-0018 §1.4，随下次
   required-set 重签发落地）；PHASE-4 任务表 graph parser 修复（DEFECT-1）按 R3
   归新任务。
3. darwin SBPL 路径与其证据不变；linux bwrap 引擎为 ADR-0018 §2 新增。
4. 本文件变更属 C2：Architecture + Quality 批准；批准记录五字段随变更更新。
