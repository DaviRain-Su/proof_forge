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

当前 `scripts/verify_isolation.sh`（`just v2-clean-room-h1`）在 deny-default sandbox 中
隔离父仓库、HOME/cache 与网络，跑通四目标/Anvil，并写入 candidate/archive binding 与
schema-complete `proof-forge.evidence.v1` JSON。H0 Stage-0 在 harness 入口先完成
development attestation；formal `--require-eligible` 在本 host 稳定
`PF-HOST-INELIGIBLE`。因此 H1 repo-side 前提已闭合，但 formal hermetic
（`TASK-D0-04`/`TST-ISO-002`）仍被 ineligible host 阻断，不得混称。
