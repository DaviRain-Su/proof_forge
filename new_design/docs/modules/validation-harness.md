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
observations、artifacts/log hashes。可持久化表示必须使用
[`proof-forge.evidence.v1`](../traceability/evidence-schema.md)，不能另造宽松 `GateResult`
JSON。缺 required tool 是 failed，不是 skipped；只有 target dossier 明确 optional 的 gate
可 skipped，且不能提升 maturity。

normalized observation 固定 `{step,status,return,logicalState,effects,errorClass}`；target-specific
logs/resources 作为附加维度，不能掩盖核心 mismatch。覆盖 runner timeout/signal/huge output、
flaky retries、malformed observation、stale artifact、dirty tree、missing tool、different roots/
jobs、proof invalid/private leak、network wrong identity。关联 `PHASE-5`、`TASK-D8-*`、所有
`TST-*`；证据 schema 必须可独立复核。

证据验证必须明确分层：

1. `gate_evidence.py validate` 只验证 restricted PF JCS、schema、derived digest 与跨字段不变量；
2. `verify-bundle` 只对 inputs、retained artifacts、logs 做逐组件 safe-open 的时点 size/hash
   复核；
3. 未来 gate-catalog finalizer 才能证明 required test/tool/probe 完整、命令与 candidate/host
   绑定并发布 formal evidence。

前两层的输出必须分别写明 `claims-not-verified` 与 `gate-catalog-not-verified`，不能被 CI
summary 改写为 formal pass。当前 publisher 仅接受 development qualification，formal 输入
稳定返回 `PF-EVIDENCE-FORMAL-UNVERIFIED`。修正/撤销旧 EV 必须使用未来独立 append-only
revocation ledger，不能改写原 EV；该 ledger 尚未实现。

当前 `scripts/verify_isolation.sh` 仍是 development clean-room alpha。Lean/Lake、external
bundle、Stage-0 development host observation 与 candidate commit/tree/git-tar binding 已有
可执行切片，但当前 host 不 eligible，deny-default continuation、gate catalog、remote
attestation、revocation lookup 和正式 finalizer 尚未闭合。`TST-EVIDENCE-001`、
`TST-ISO-002`、`TASK-D0-03` 均保持未完成。
