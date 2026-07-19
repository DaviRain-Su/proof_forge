---
id: PHASE-3
title: 技术规格总索引
status: accepted
owner: engineering
updated: 2026-07-17
normative: true
approvers: architecture-owner, language-semantics-owner, quality-owner, target-owner
approvedAt: 2026-07-17
reviewCommit: 1e97798b5e59c3a7c15db47f2865575dfd3e3dd3
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/1e97798b5e59c3a7c15db47f2865575dfd3e3dd3
openFindings: none
---

# Phase 3：技术规格总索引

本页定义跨模块集成契约；细节必须以对应子规格为准。所有子模块必须拥有自己的
Phase 3 模块规格，不能只引用系统架构。

## 公共数据流

```text
SourceFile
→ Lean Parser → per-program bounded Syntax preflight → ProofForge decode → Source.Program
→ resolve/type/effect/bound/disclosure → Typed.Program
→ normalize → SemanticProgramV1 + SemanticProvenanceV1（ProgramRequirements 嵌入前者）
→ optional proof-reference validation against digest-pinned ProofBundleV1
→ resolve(TargetId, minimumEvidence) → ResolvedProgram target
→ Materializer.plan(CodegenProfile) → target Plan
→ lower → target TargetIR
→ emit → staged OutputSetV1
→ validate hashes/schema/tool outputs → atomic publish
```

各阶段只能消费前一阶段的成功类型；禁止以 optional/error string 绕过阶段。失败统一
返回 `DiagnosticBundle`，排序键为 `(file, startByte, code, stableContext)`。
当前 alpha 的 CLI 不 elaboration 或执行用户 Lean module；Lean command elaborator 与
non-elaborating loader 共用同一个 syntax decoder，以 AST 等价测试防止双入口漂移。

## 公共类型

```lean
structure SourceNameComponentV1 where
  private mk ::
  raw : String

structure SourceQualifiedNameV1 where
  components : NonEmptyArray SourceNameComponentV1

structure SourceProgramIdentity where
  qualifiedName : SourceQualifiedNameV1
  sourceHash    : Digest

structure SemanticProgramBinding where
  source                   : SourceProgramIdentity
  semanticHash             : Digest
  semanticProvenanceDigest : Digest

structure BuildSelection where
  program        : Name
  target         : TargetId
  codegenProfile : CodegenProfileId
  outputDir      : System.FilePath

class Materializer (target : TargetId) where
  Plan             : Type
  TargetIR         : Type
  planSchema       : SchemaId
  targetIrSchema   : SchemaId
  plan             : ResolvedProgram target → CodegenProfile target → CompileResult Plan
  validatePlan     : Plan → CompileResult Unit
  lower            : Plan → CompileResult TargetIR
  validateTargetIR : TargetIR → CompileResult Unit
  emit             : TargetIR → EmitContext → IO (CompileResult OutputSet)
```

`SourceQualifiedNameV1` 是 ProgramV1 规范类型；其实现由后续独立 slice 落地。当前 alpha
`Source.Program` 的 rendered `String` 与使用 common `QualifiedName` 的 development helper 都是过渡面，
不得替代该 raw carrier。

`RequirementRef`、`RequirementKey` 与 `SupportPredicate` 的唯一 type/wire authority 是
[`SPEC-CAP-001`](specs/capabilities-extensions.md)；本集成页直接使用该类型，不重新声明字段。

`NetworkProfileId` 不属于 `BuildSelection`；只允许出现在显式 deploy/verify 命令。
`TargetId + targetSemanticsVersion + targetSemanticsDigest` 固定全部可观察执行宿主语义；
`CodegenProfileId + codegenProfileDigest` 固定 emitter/ABI/toolchain/lowering，并 exact 引用而不
覆盖 target semantics。`NetworkProfileId` 只记录 chain/genesis identity、endpoint、fee 与 deploy
policy；deploy/verify 必须对三者做 exact compatibility join，不匹配只能拒绝，
不得改写 SemanticProgram、Plan 或 artifact。

## 子规格

| 领域 | 规格 | 主要 FR/NFR |
|---|---|---|
| Common types/resources | [`specs/common-types.md`](specs/common-types.md) | NFR-002/006/008 |
| DSL | [`specs/language.md`](specs/language.md) | FR-001/002/010 |
| Source.ProgramV1 wire | [`specs/source-program-wire.md`](specs/source-program-wire.md)（Ident = raw `SourceNameComponentV1`；source identity 数组 source-specific；不削弱 SPEC-COMMON） | FR-001/002/010 |
| Type/effect | [`specs/type-effect-system.md`](specs/type-effect-system.md) | FR-003/012 |
| Semantics | [`specs/semantic-core.md`](specs/semantic-core.md) | FR-004/005 |
| SemanticProgram wire/provenance | [`specs/semantic-program-wire.md`](specs/semantic-program-wire.md) | FR-004/005 |
| Requirements | [`specs/capabilities-extensions.md`](specs/capabilities-extensions.md) | FR-006/013 |
| Registry | [`specs/target-registry.md`](specs/target-registry.md) | FR-005/008 |
| Materializer | [`specs/materializer-protocol.md`](specs/materializer-protocol.md) | FR-007 |
| Output | [`specs/output-contract.md`](specs/output-contract.md) | FR-009 |
| Diagnostics | [`specs/diagnostics.md`](specs/diagnostics.md) | FR-003/011, NFR-002 |
| CLI | [`specs/cli.md`](specs/cli.md) | FR-008/010/011/014 |
| Security | [`specs/security.md`](specs/security.md) | NFR-003/008/009 |
| Toolchains | [`specs/toolchains.md`](specs/toolchains.md) | NFR-001/009 |
| Versioning | [`specs/versioning.md`](specs/versioning.md) | NFR-006 |
| Reproducibility | [`specs/reproducibility.md`](specs/reproducibility.md) | NFR-001/004 |
| Gate finalization | [`specs/gate-catalog-finalization.md`](specs/gate-catalog-finalization.md) | NFR-003/004/005/009 |

## 全局前置与后置条件

前置：UTF-8 source、锁文件存在、target/profile exact lookup、输出路径在允许 root 内、
无未声明 extension。后置：成功时无 error diagnostics、所有 artifacts 在 manifest 中且
hash/size 匹配、输出目录原子发布；失败时旧输出不变、临时目录清理、无网络/部署/
密钥副作用。

## 全局边界条件

至少覆盖：空文件、零/多 program、重复 qualified name、非法 UTF-8、极深 AST、最大
整数、overflow/underflow、零长度/最大长度 bytes、未界定循环、递归、动态分配、
private 到 public 泄漏、未知 target/profile、版本/digest 不符、重复 registry key、
不支持 extension、外部工具缺失/超时/错误输出、路径穿越、symlink、部分写盘、并发
同目录构建、非确定环境、父项目 cache/path 泄漏。

## 状态与错误

编译状态机：`received → parsed → typed → normalized → resolved → planned → lowered →
emitted → validated → published`。任一步失败进入 `failed`，只能通过新 invocation 重试；
不能从失败状态继续。错误码和退出码见 diagnostics/CLI 规格。

## 接受条件

本阶段只有在每个子规格完成字段、接口、算法、错误、版本、安全、至少 10 个边界、
trace ID 和可执行 acceptance，且评审无开放阻断项时才可改为 accepted。
