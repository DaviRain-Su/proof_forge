---
id: GOV-TASKQUAL-BOOTSTRAP-001
title: TASK-D0-10 task qualification bootstrap 裁决
status: accepted
owner: quality
updated: 2026-07-20
normative: true
approvers: architecture-owner, davirain, quality-owner, security-owner
approvedAt: 2026-07-20
reviewCommit: db4cf6b883196548e46e0e9c7d630ae6b397ee4e
reviewLink: https://ampcode.com/threads/T-019f7dea-e600-77ea-8884-9f35f81f747d
openFindings: none
---

# GOV-TASKQUAL-BOOTSTRAP-001

## 裁决

Architecture + Quality 批准 D0 exact task set 从 D0-01…09 扩为 D0-01…10；Security 批准
新 qualification 信任边界。新增项只能是 pending `TASK-D0-10`，不得借本裁决激活任务、
创建冻结包、签发 evidence 或标 done。

`TASK-D0-10` 可且仅可使用一次 bootstrap closeout，以交付 `SPEC-TASKQUAL-001` verifier、
protected docs consumer 与后续任务可认证引用的 completion bridge。永久 bootstrap task set
不得扩大；本裁决不把 D0-10 加入 six-item activation，也不改变或重解释 D0-07 历史关闭。

## Gate-before-close

1. verifier/protected-consumer implementation 与其门禁必须先在一个变更集完成并全绿；
2. D0-10 closeout 必须是后续独立 commit，二者不得共享 commit；closeout 只能消费已钉住的
   verifier 并执行 one-time bridge，不得修改 verifier 或协议；
3. 因 `GOV-MAINTAINERS-001` 的角色均映射到同一维护者，Architecture+Quality+Security
   signatures 不构成人员独立性；bootstrap closeout 前必须有 mandatory independent read-only
   review，记录 reviewer/report/findings。当前 Oracle 建议与 Amp thread 方向批准不替代该实现复审。

违反 separation、出现 P0/P1、资格输入撤销/过期或 protected consumer 无法重算时必须 fail closed。

R2 specification repair将content verification与production provenance分层：fixture只能验证pure contract；
production docs acceptance只能来自本裁决/policy钉住的protected adapter及
`production-candidate-bound` projection。D0-10 fixture只测一次性approval/receipt并消费fixture D0-07
GovernanceBootstrapCompletion；它不能签发本裁决的真实bridge或关闭任务。冻结包及blocked状态不变，
amendment经独立复审前不得恢复RED。

## 一次性对象与 checker authority

本裁决采用 `SPEC-TASKQUAL-001` §7 的 exact `GovernanceBootstrapCompletionV1`、
`D0_10BootstrapApprovalV1` 与 `D0_10BootstrapReceiptV1`，并采用该规格 §6/§7 的 C→approval→D→
external receipt→optional P acyclic protocol。D0-10 checker authority 只对本 ruling、exact task、
exact purpose 生效；不得复用于其他 task，不得修改 external activated BootstrapAuthorityPolicyV1
及其 six-item taskRules，不得进入 six-item activation。

raw EV 永远是 development；仅 D0-10 最终一次性 receipt 的 Ledger projection 可为 bootstrap。
approval 必须绑定 exact in_progress row/freeze、pre-close candidate/tree/archive、verifier+consumer
closure、`TST-DOC-001/task-qualification-v1`、development raw EV、authenticated D0-07 bridge、P0/P1=0
independent reviews、Architecture+Quality+Security signatures 与 allowed closeout patch。当前 baseline
仍 pending且无 freeze/package/object，不能预填这些事实。

本 authority baseline 的独立审查曾报告 schema/bridge/closeout 等 P1，逐项修复后最终 bounded
复审结论为 `COMMIT BASELINE`、P0/P1=0。该结论不替代 D0-10 verifier 实现后的 mandatory
independent read-only review，亦不授权当前 pending task 自动激活或关闭。
