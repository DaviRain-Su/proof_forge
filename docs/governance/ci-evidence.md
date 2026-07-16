---
id: GOV-CI-001
title: CI 与证据策略
status: proposed
owner: quality
updated: 2026-07-16
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

### Current hosted subset (2026-07-16)

Hosted GitHub/Woodpecker only enforce the portable Linux subset of lanes 1–2 via
`just ci` (docs-check, lake build/test, DSL and target negative gates). Lanes 3–7
and hermetic host/toolchain/clean-room evidence remain local macOS development
gates until a linux host profile and locked external tool root exist. Do not
treat hosted green as formal EV or hermetic qualification.

## Evidence

目标状态是每个 lane 输出符合 [`TRACE-EV-001`](../traceability/evidence-schema.md) 的 JSON、
hashed logs 和 OutputSet，再由正式 gate-catalog finalizer 汇总 evidence set root。当前只实现
schema validation、bundle point-in-time integrity 与 development-only atomic publication；不得
把它们标成 lane attestation。formal evidence publication、required gate catalog、freshness、
revocation lookup 和 evidence set root 尚未实现。

CI 消息必须保留工具给出的边界：`schema-validated ... claims-not-verified` 仅表示结构有效；
`bundle-integrity-verified ... gate-catalog-not-verified` 仅表示声明文件在读取时匹配。只有未来
finalizer 才可产生 formal pass。当前 formal publish 必须以
`PF-EVIDENCE-FORMAL-UNVERIFIED` fail closed，required branch protection 不得接受 development
EV 代替。

development record 的固定发布布局为 `<trusted-root>/<gate.id>/<id>.json`；同一 ID 不覆盖，
重跑分配新 ID。修正记录通过未来独立 append-only revocation ledger 引用原 EV digest 和可选
replacement，不修改原 EV；revocation schema 当前仅 specified，CI 尚不能据此作 release 判断。

artifact retention 目标：candidate/release 证据至少 2 年，普通 main 90 天，PR 30 天；private
witness 永不上传。外部 network evidence 需 chain identity、tx/proof/artifact hash，最多 30 天。

重试只允许基础设施分类错误，最多一次，并保留两次记录；test assertion 不自动重试。
branch protection 要求所有 required lanes 来自同 candidate commit，禁止用旧成功覆盖新提交。
v1 formal passed 只允许一次 command attempt；development 可记录一次重试，但该记录不能升级成
formal。上述 retention、branch protection 和 retry policy 都仍需 gate catalog/finalizer 实现
后才能成为机器可执行证据规则。

Development catalog finalization 将使用 [`SPEC-EVFINAL-001`](../specs/gate-catalog-finalization.md)
定义的独立 catalog lock、typed EV bindings 和 immutable finalization record。它只会证明 catalog
exact-set 与 point-in-time bundle bindings，不构成 lane attestation 或 evidence-set root；正式
CI 仍必须汇总同一 candidate/host/catalog 的全部 required gates，并验证 freshness、revocation
与 private scan。
