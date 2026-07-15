---
id: MOD-TEST-001
title: ValidationHarness 模块规格
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# ValidationHarness

测试模块消费产品 public API/CLI/OutputSet，不能被 production library import。它拥有
Counter/PrivateSum4 vectors、normalized observation schema、external tool runners、EV JSON、
repeatability 和 clean-room orchestration。

Runner 输入 exact tool/profile/vector/timeout，输出 `GateResult`：command、versions、exit、
observations、artifacts/log hashes。缺 required tool 是 failed，不是 skipped；只有 target
dossier 明确 optional 的 gate 可 skipped，且不能提升 maturity。

normalized observation 固定 `{step,status,return,logicalState,effects,errorClass}`；target-specific
logs/resources 作为附加维度，不能掩盖核心 mismatch。覆盖 runner timeout/signal/huge output、
flaky retries、malformed observation、stale artifact、dirty tree、missing tool、different roots/
jobs、proof invalid/private leak、network wrong identity。关联 `PHASE-5`、`TASK-D8-*`、所有
`TST-*`；证据 schema 必须可独立复核。

当前 `scripts/verify_isolation.sh` 是 network-denied clean-room alpha：它已隔离父仓库、
HOME/cache 与网络并跑通四目标/Anvil。Lean/Lake 与 external bundle 的 development closure
已经锁定；`TASK-D0-03/H0` 会在任何未验证的 Git/Python 前完成 Stage-0 bootstrap，随后只
允许已锁定的 direct Python 完成 live profile，并区分 development observation 与 formal
eligibility。当前 host 精确匹配 development profile，
但正式模式按策略拒绝。eligible host、deny-default sandbox 与 schema-complete
`GateResult`/`EV-ISO-*` 仍阻止正式 gate，不得视为本模块规格已实现。
