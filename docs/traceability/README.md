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

`planned` 链表示规格已定义但尚无执行证据；只有 EV 经 gate 校验并由 release report 引用后
才是 closed。任何 accepted FR/NFR 必须至少关联一个 SPEC、TASK、TST；任何 implemented
行为必须有 EV。覆盖率按唯一 ID 计算，不以文档行数计算。

CI 的 docs-check 必须验证 ID 唯一、引用存在、无孤立 normative requirement、done task 有
TST+EV、release 只引用通过且未过期 EV。默认证据新鲜度：同一 release commit；外部网络
证据最多 30 天且 artifact hash 必须与 candidate 相同。
