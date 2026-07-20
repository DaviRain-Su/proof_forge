---
id: ADR-0020
title: 任务作用域 formal qualification 与 release aggregate 分离
status: accepted
owner: architecture
updated: 2026-07-20
normative: true
approvers: architecture-owner, davirain, quality-owner, security-owner
approvedAt: 2026-07-20
reviewCommit: db4cf6b883196548e46e0e9c7d630ae6b397ee4e
reviewLink: https://ampcode.com/threads/T-019f7dea-e600-77ea-8884-9f35f81f747d
openFindings: none
---

# ADR-0020：任务作用域 formal qualification 与 release aggregate 分离

## 背景

`ADR-0018` 已 accepted。它描述的真实 activation 下 77-ID RequiredTestSet 全量 formal partition
与 `TASK-D8-04`/`TST-ISO-003` release aggregate 方向仍被保留；其中“D8 前任何非 D0 task
均不可能 formal 关闭”的结论会使 `TASK-D1-01` 与依赖 D1 的 D8-04 构成任务图循环。

## 决定

1. 新增与 evidence qualification、`RequiredTestSetV1` 和 full formal finalization 不同的
   control-plane 对象 `TaskQualificationV1`（`SPEC-TASKQUAL-001`）。它只证明一个已冻结任务
   在精确 candidate 上满足自身 tests 与关闭控制，不声称全局测试分母完成。
2. pending task 可把 `TaskQualificationV1` 设为关闭前置；运行时 task row 必须为
   `in_progress`，qualification 先完成，关单在受约束的后续 commit 完成。
3. `TASK-D8-04`/`TST-ISO-003` 继续独占真实 activation 的完整 77-ID partition、real catalog、
   full formal finalization 与 release aggregate。两种协议不可互换，也不能由 task subset
   推导 RequiredTestSet 分母覆盖率。
4. 本 ADR 仅窄幅修订 accepted ADR-0018 的上述 pre-D8 closeout 结论；所有 task-qualification
   wire/consumer contract 均直接位于 accepted SPEC-TASKQUAL-001。ADR-0018 与 accepted
   `GOV-D0CLOSE-001` 的 D0-07 历史 bootstrap closure boundary 保持原样，不重解释、不升级为
   formal；D8 全量责任保持不变。ADR-0019 不受影响。

## 安全与治理后果

Task qualification 必须绑定 eligible Stage-0、session containment、verifier identity、命令策略、
freshness/private scan/revocation、已认证依赖、独立 review 和 Architecture+Quality+Security 签名。
角色签名不证明 reviewer 独立性；在 `GOV-MAINTAINERS-001` 单点映射下，bootstrap closeout 前
仍必须取得并记录独立复审。

R2 澄清采用既有 D0-07 pure-consumer/protected-consumer 边界：四个 public verifier 只消费 closed
content bundle与subject bytes并产生非provenance的immutable projection；policy-pinned protected adapter
独立取得current policy、trusted time、FD/session/store/Git provenance，调用同一pure verifier后再证明
provenance。fixture namespace静态不相交且永不authoritative。该澄清不增加第二套evidence framework，
也不改变D8 aggregate、task冻结轴或关闭语义。

本 accepted 决定的批准来源是当前 Amp thread；`reviewCommit` 使用批准时仓库 HEAD，表示
maintainer 授权本 authority amendment，并非虚构未来 merge commit。
