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
- [**自举信任根与 genesis 关闭协议**](genesis-authority.md)（`GOV-GENESIS-001`；C2，待 Architecture+Quality 批准）
- [**D0-08/D0-09 pre-cutover 关闭裁决**](pre-cutover-closure-ruling.md)（`GOV-PRECUTOVER-001`；C2，genesis 同级批准来源）
- [**TASK-D0-07 bootstrap 级关闭裁决**](d0-07-closure-ruling.md)（`GOV-D0CLOSE-001`；C2，genesis 同级批准来源，formal 边界不稀释）
- [**TASK-D0-10 task qualification bootstrap 裁决**](task-qualification-bootstrap-ruling.md)（`GOV-TASKQUAL-BOOTSTRAP-001`；一次性 bridge，gate-before-close）
- [角色与人员映射](maintainers.md)（`GOV-MAINTAINERS-001`；authority.md 的角色绑定）
- [genesis 任务集合 lock](genesis-set.lock.json)（`GOV-GENESIS-001` 的 exact genesis 集合）
- [任务集合 lock](task-set.lock.json)（A0/D0–D8 exact `TASK-*` 集合；M1 机器强制）
- [任务冻结包目录](task-freeze-packages/)（每个 `in_progress` 的完成面 JSON；M2 机器强制）
- [D0-01 pure-consumer 关闭证明](bootstrap-closure/TASK-D0-01.attest.json)（`FX-2026-07-17-D0-01`）
- [D0-02 package-boundary 关闭证明](bootstrap-closure/TASK-D0-02.attest.json)（`FX-2026-07-17-D0-02`）
- [D0-03 development triad 关闭证明](bootstrap-closure/TASK-D0-03.attest.json)（`FX-2026-07-17-D0-03`）
- [D0-05 SBOM inventory 关闭证明](bootstrap-closure/TASK-D0-05.attest.json)（`FX-2026-07-17-D0-05`）
- [D0-08 SBOM closure 关闭证明](bootstrap-closure/TASK-D0-08.attest.json)（`GOV-PRECUTOVER-001`）
- [D0-09 linux host profile 关闭证明](bootstrap-closure/TASK-D0-09.attest.json)（`GOV-PRECUTOVER-001`）
- 供应链：[`../supply-chain/`](../supply-chain/)（license policy/inventory）
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
