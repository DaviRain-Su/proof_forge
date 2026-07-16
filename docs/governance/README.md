---
id: GOV-INDEX
title: 工程治理索引
status: proposed
owner: maintainers
updated: 2026-07-17
normative: true
---

# 工程治理索引

- [权威与角色](authority.md)
- [变更控制](change-control.md)
- [**全局任务冻结协议**](task-freeze.md)（全部 `TASK-*` 完成面守恒；禁止执行中扩 scope）
- [版本与兼容治理](version-compatibility.md)
- [依赖与供应链](dependency-policy.md)
- [CI 与证据](ci-evidence.md)
- [发布与回滚](release-rollback.md)
- [维护与 EOL](maintenance-eol.md)
- [安全响应](security-response.md)

治理文档与技术规格冲突时，技术行为由 accepted ADR/spec 决定，审批、发布和响应流程
由本目录决定。任务调度与“何时算做完”以
[`task-freeze.md`](task-freeze.md) 为规范。紧急安全流程可以临时禁用 profile/target，
但不能静默改变语义，也不得借安全流程改胖无关 `in_progress` 任务的完成面。
