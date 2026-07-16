---
id: TRACE-INDEX
title: 追踪与证据索引
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# 追踪与证据索引

规范链固定为：

```text
GOAL → FR/NFR → CLM/ADR/INV → SPEC/CAP → TASK → TST → EV → RELEASE
```

- [ID 规则](id-schema.md)
- [需求追踪矩阵](requirements-matrix.md)
- [证据 schema](evidence-schema.md)
- [alpha evidence ledger](evidence-ledger.md)

`specified` 链表示规格已定义但尚无执行证据；只有 EV 经 gate 校验并由 release report 引用后
才是 closed。为避免 proposed 阶段的 checker 退化为 vacuous pass，所有 active normative
（`draft|proposed|in_review|accepted`）GOAL/FR/NFR 都必须在 matrix 中拥有完整
GOAL → FR/NFR → ADR/INV → SPEC/MOD → TASK → TST forward chain。OOS 是显式非目标，不进入
implementation/evidence chain。

CI 的 docs-check 必须验证 ID 唯一、结构化引用存在、无孤立 normative requirement、done task
有 TST + 语法精确的 `passed` EV、任务依赖闭合、matrix 每个 TST 由同一行至少一个 TASK
拥有、最多一个 `in_progress`，并拒绝无法绑定正式 evidence set 的 accepted release。
`TASK-D0-03` binder 落地前，任何 accepted `REL-*` 都必须拒绝；same-candidate、artifact hash、
revocation 与外部网络 30 天新鲜度由
`TASK-D0-03` 的 formal finalizer 校验；docs-check 不以本机时钟或文件 mtime 重新解释历史 A0
ledger。
