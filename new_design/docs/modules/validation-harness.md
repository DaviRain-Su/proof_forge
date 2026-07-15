---
id: MOD-TEST-001
title: ValidationHarness 模块规格
status: proposed
owner: quality
updated: 2026-07-16
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

当前 `scripts/verify_isolation.sh` 仍是 development clean-room alpha，但 materialize/core/
runtime payload 已接入 deny-default policies 和 closed-FD launcher。materialize/core 全断网；
runtime 为 exact-local-port，并由 Anvil `127.0.0.1` bind 与 LAN refusal negative 补充。
stdout/stderr 以 bounded current-user `0400` single-link receipts 发布，原 process group 会在
leader reap 前清理。

当前 host 不 eligible，formal Stage-0 handoff、`setsid()` session-escape containment、
gate catalog、`networkPort` 与 rendered policy bytes/digest、retained launcher logs/receipts 及
required probes 的绑定、freshness/revocation/private scan、remote attestation 和正式 finalizer
仍未闭合。evidence v1 candidate 已能条件表达
`exact-local-port` + `networkPort`，但 schema field 本身不证明实际 policy bytes 或 required
probes。失败时回显的 ASCII-escaped 32 KiB tail 只属于 development diagnostics，不能作为已
脱敏或 retained formal evidence。`TST-EVIDENCE-001`、`TST-ISO-002`、`TASK-D0-03` 均保持
未完成。

H1e 的完整契约见 [`SPEC-EVFINAL-001`](../specs/gate-catalog-finalization.md)。Catalog 必须是
独立 lock；launcher 先为每个 invocation 产生绑定 policy/port/terminal/raw streams 的 canonical
metadata receipt；finalizer 再以一次 safe-open snapshot 做 exact-set evaluation，并发布独立
development finalization record。Schema-only `publish` 不得复用该 namespace 或声称 catalog
已验证。
