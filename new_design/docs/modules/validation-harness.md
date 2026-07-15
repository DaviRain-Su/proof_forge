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
HOME/cache 与网络并跑通四目标/Anvil，但尚未锁定完整 tool/runtime closure，也尚未输出
schema-complete `GateResult`/`EV-ISO-*`；不得视为本模块规格已实现。

`TASK-A0-07` 已把 solc、WABT+libcrypto 与 Anvil/Cast 切到 content-addressed external
bundle，并同时验证静态 Mach-O 图、实际 dyld load 与 tamper negative；剩余 Lean/host/
deny-default/evidence closure 继续阻止正式 gate。
