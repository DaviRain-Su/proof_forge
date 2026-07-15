---
id: TRACE-EV-001
title: Gate Evidence Schema
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# Gate Evidence Schema

`build/evidence/<gate>/<EV-ID>.json`（不提交大型日志）使用 JCS：

```text
schema: "proof-forge.evidence.v1"
id: "EV-YYYYMMDD-NNNN"
gateId, testIds[], taskId
repository: {commit, dirty, diffDigest?}
environment: {os, arch, envDigest, cleanRoom, cacheMode}
toolchains: [{id, version, executableSha256}]
command: {argv[], cwdRelative, startedUtc, durationMs, exitCode}
inputs: [{path, sha256}]
outputs: [{path, sha256, size}]
observations: [{step, status, return, logicalState, effects, errorClass}]
result: "passed" | "failed" | "skipped"
logs: [{path, sha256, truncated}]
```

时间只用于证据新鲜度，不进入 artifact reproducibility hash。passed 要求 exit 0、所有 assertion
通过、required tools 齐全；skipped 必须有 dossier-authorized reason，不能用于关闭 FR 或提升
maturity。dirty evidence 只用于开发，不用于 release。

证据不可变；重跑分配新 EV ID。修正错误证据时标记 revoked 并链接 replacement，不能原地
编辑。CI 校验 schema、hash、commit、tool lock、test/task references、日志存在性和 private
data scan。release report 固定引用 EV IDs 与 evidence set Merkle root。

边界：失败、timeout、signal、重试、truncated log、missing output、hash mismatch、dirty tree、
stale network evidence、wrong candidate artifact、clock skew、duplicate ID、revoked evidence、
private witness/log、malformed observation、partial upload。验收 `TST-EVIDENCE-001`。
