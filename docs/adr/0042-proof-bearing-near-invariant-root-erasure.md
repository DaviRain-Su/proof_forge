---
id: ADR-0042
title: Proof-bearing NEAR invariant-root erasure
status: proposed
owner: architecture
updated: 2026-08-11
normative: true
---

# ADR-0042：Proof-bearing NEAR invariant-root erasure

## Status

**proposed**（2026-08-11）。本 ADR 是 [ADR-0027](0027-inline-same-file-theorem-certification.md)
同文件认证与 [ADR-0034](0034-preservation-abi.md) L1 preservation 的 target amendment；
不 supersede 二者，也不改变 `SemanticProgramV1 + ReferenceMachineV1` 的唯一语义权威。

## Context

ProofForge invariant 在 retained `SemanticProgramV1` 中既有 `InvariantDecl`，也有
`.invariant` callable root。该 root 是 `evalInvariantV1` 和
`PreservationTheoremV1` 的 compile-time proof subject；它不是作者声明的 initializer、entry
或 view，也不应成为公开 NEAR ABI method。

历史 NEAR materializer 对任何 nonempty invariant table 都 fail closed。这保证 target 不会静默
丢掉 proof subject，但也使已经由 Lean kernel/audit 认证的 `Examples/VerifiedVaultPF.lean`
无法产出 NEAR artifact。直接在 lowering 中忽略 `.invariant`、接受 caller 提供的 proof digest，
或根据名字删除“proof closure”都会破坏 authority 与 callable identity。

## Decision

### D1 — invariant root 是 compile-time proof subject

1. NEAR runtime 只导出 initializer、entry 与 view；`.invariant` callable root 不进入 ABI/Wasm
   exports。
2. 擦除不修改 retained `SemanticProgramV1`、source/semantic digest、callable id、state layout、
   business invocation、effect order 或 Reference theorem subject。
3. 只允许擦除 `.invariant` roots。所有 `.pureFn`（包括 business 与 invariant closure 共享的
   pureFn）继续进入 target function environment；本策略不做 proof-closure dead-code deletion。

### D2 — 私有 proof certificate 是唯一授权

NEAR erasure authorization 只能由 product 内部从 private-constructor
`CertifiedInlineProofV1` mint。certificate 的 sole public mint 把 held raw source 的 in-process
elaboration与 Environment audit 放在同一模块；不存在可把 independently supplied Environment
与另一组 raw bytes 配对的公开 low-level mint。authorization transition 必须重新验证：

1. certificate source digest 与 exact `CompiledSemanticV1.sourceDigestOf` 相等；
2. certificate semantic digest 与 exact `CompiledSemanticV1.semanticDigestOf` 相等；
3. validated semantic invariant table nonempty；
4. 每个 dense `InvariantDecl` 恰有一个经过 Environment/kernel audit 的 `preserving` obligation，
   且 obligation ordinal/name 指向 exact invariant callable root；
5. selected target kind 是 NEAR。

`holds`-only、partial preserving coverage、foreign/cross-subject certificate、普通 engineering
capability、空 invariant table 和非 NEAR target 均不能获得该 authorization。certificate
constructor、authorization constructor 与 capability constructor都不向 caller 开放。

### D3 — versioned Plan attestation

首个策略版本固定为：

```text
proof-forge.near.invariant-root-erasure.v1
```

NEAR `Plan.invariantErasure?` 的 `some` 分支必须绑定：

- exact source digest、semantic digest、proof certification digest；
- semantic callable count；
- retained initializer callable id；
- retained entry/view callable ids；
- retained pureFn callable ids；
- erased invariant callable ids。

所有 id 只能从 structure-validated semantic callable/InvariantDecl table 推导，调用方不能提供。
四组 id 必须互斥、范围内、各数组严格递增，并精确组成 `0 .. callableCount - 1` 的 dense
partition；erased root set 必须 nonempty 且 exact 等于 `InvariantDecl.callableId` 表。

### D4 — canonical identity 与 fail-closed

1. `some` attestation 以固定 extension tag
   `pf.near-plan.extension.invariant-erasure.v1` 追加到 canonical NEAR Plan bytes；historical
   `none` Plan bytes 不变。
2. version、三个 digest、callable count 或 partition 的任何变化必须改变 Plan digest。
3. capability lowering还为完整 erasure-bearing Plan mint private tamper binding；decision 被删除、
   semantic IDs 被重新分组、handler/body 或其他 Plan 字段被修改、或 decision 被 replay 到另一
   Plan 时，`validatePlan` fail closed。该 internal binding 不替代 canonical Plan digest，也不进入
   historical `none` bytes。
4. ordinary capability + nonempty invariants 继续 fail closed。
5. constants 与其他既有 unsupported shapes 不因本 ADR 开放。
6. proof gate、capability mint、Plan validation、emit/finalize 任一失败均不得发布 partial
   destination 或 staging residue。

### D5 — Unit entry 与业务 ABI

NEAR 已支持 effect-only `entry ... : Unit`：它只能是 mutate method，Plan 使用
`resultKind=unit`、`ExpectedReturnV1.none_` 与 `returnNone`；view/pureFn Unit result 仍 fail closed。
该规则用于 VerifiedVault guarded withdraw，不由 invariant erasure 特判。

## Assurance boundary

2026-08-11，完整 runtime corpus 已使用原始 locked near-sandbox 2.13.0
（SHA-256 `634bc8c5e14a53c2a622c787975201b1505ec07712b8159f38e97ede3607e114`）
执行通过。Debian 12 / GLIBC 2.36 host 通过 Ubuntu Noble `libc6 2.39-0ubuntu8.8`
userspace loader 启动该原始 executable；未用 wrapper 替换或冒充 Tool Lock artifact。因此本
ADR 允许的最强声明升级为：

```text
Reference-verified + NEAR engineering runtime observed
≠ formally target-refined
```

Lean kernel/audit 证明的是 exact `SemanticProgramV1` 在唯一 Reference semantics 上的
preservation。locked `wat2wasm` 与 Plan/ABI mutation tests 是 engineering evidence；required
near-sandbox run 已实际观察 exact storage/rollback corpus。兼容 libc/loader 是 runner evidence，
尚未纳入 ProofForge Tool Lock，故该次运行也不是 hermetic release evidence。上述证据都不构成
Reference→Wasm/NEAR simulation theorem、formal
`TASK-D2-07`/`TST-SEM-002/003`、hermetic release 或 network evidence。

## Consequences

- `VerifiedVaultPF` 可在同一次 product build 中保留真实 certificate，mint NEAR-only
  authorization，并物化 init/deposit/withdraw/status；`solvent` 不成为 runtime export。
- output manifest 的 `planDigest` 间接绑定 proof certification digest 与 exact callable
  partition；CLI `check` 的 proof status 仍与 target-refinement 状态分开。
- 其他 target 不自动继承该策略；每个 target 必须单独定义/审核自己的 Plan attestation 与
  runtime/refinement 边界。
- Phase 7 的正式 target refinement 仍是独立长期工作，不能由本 ADR 或 runtime positive 代签。

## Rejected alternatives

1. **所有 nonempty invariants 永久 fail closed**：安全但阻断已经认证的真实业务纵切。
2. **lowering 无条件跳过 invariant**：没有 proof authority，拒绝。
3. **caller 传 proof digest / boolean**：可伪造且不绑定 exact subject，拒绝。
4. **删除整个 invariant closure**：可能删除 business-shared pureFn 并改变 callable identity，拒绝。
5. **为 VerifiedVault 写 target/contract 特例**：不可泛化并会恢复 contract registry/pin，拒绝。

## Verification contract

- certificate：exact source/semantic binding、complete preserving coverage、holds-only/foreign reuse
  negatives；
- Plan：ordinary fail-closed、exact business partition、canonical digest binding、version/digest/
  ordering/range/overlap/completeness mutation negatives；
- product：real `build --target near` 在 locked tool available 时产出 Wasm/ABI，tool missing 时零
  destination；
- runtime：locked near-sandbox 直接观察两 KV slots 的 equality、Unit withdraw、overflow/assert
  rollback，并要求 erased invariant call 以 exact `MethodNotFound` 失败；qualification invocation
  设置 `PF_NEAR_RUNTIME_REQUIRED=1`，禁止 missing/incompatible sandbox 被 optional skip 冒充通过。
  2026-08-11 compatible-loader required run 已完成，十个 suite 全部 PASS。
