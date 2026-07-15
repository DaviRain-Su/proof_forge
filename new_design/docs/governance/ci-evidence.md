---
id: GOV-CI-001
title: CI 与证据策略
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# CI 与证据策略

## Required Lanes

1. `docs`：frontmatter/status/ID/link/claim/ADR/trace/accepted TODO 检查。
2. `source-core`：Lake build、frontend、type/effect/semantic/property/fuzz smoke。
3. `resolver-artifact`：registry、support、Plan protocol、manifest、安全负例。
4. `evm`、`solana`、`near`、`noir`：target artifact + required runtime/proof。
5. `four-target`：Counter normalized differential、PrivateSum4 matrix。
6. `reproducibility`：不同 root/jobs 的 hash 比较。
7. `clean-room`：archive、empty cache/env、全量 required gate。

顺序 docs→source-core→resolver-artifact→targets→aggregate→repro→clean-room；fail-fast 只停止
昂贵下游，不掩盖本 lane 已产生的失败 EV。required lane 不允许 continue-on-error 或 missing
tool skip。

## Evidence

每个 lane 输出 `TRACE-EV-001` JSON、hashed logs 和 OutputSet；CI 汇总 evidence set root。
artifact retention：candidate/release 证据至少 2 年，普通 main 90 天，PR 30 天；private witness
永不上传。外部 network evidence 需 chain identity、tx/proof/artifact hash，最多 30 天。

重试只允许基础设施分类错误，最多一次，并保留两次记录；test assertion 不自动重试。
branch protection 要求所有 required lanes 来自同 candidate commit，禁止用旧成功覆盖新提交。
