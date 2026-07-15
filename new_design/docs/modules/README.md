---
id: MOD-INDEX
title: 模块边界索引
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# 模块边界索引

每个模块独立拥有 Phase 3 规格；共同引用项目 PRD/Architecture，但不能用它们替代模块
输入、输出、错误和测试契约。

```text
CliOrchestrator
 ├─ SourceFrontend → SemanticEngine
 ├─ SupportResolver → Target Materializer → ArtifactPipeline
 └─ ValidationHarness（仅测试依赖产品模块）

Near/CosmWasm/Soroban/ICP Materializer → WasmEncoder
```

| Module | 规格 | 禁止依赖 |
|---|---|---|
| SourceFrontend | [source-frontend.md](source-frontend.md) | target、profiles、artifact emitters |
| SemanticEngine | [semantic-engine.md](semantic-engine.md) | target registry、target Plan |
| SupportResolver | [support-resolver.md](support-resolver.md) | source parser、target emitter |
| MaterializerRuntime | [materializer-runtime.md](materializer-runtime.md) | 其他 target 的 Plan/IR |
| WasmEncoder | [wasm-encoder.md](wasm-encoder.md) | host ABI/storage/auth/call semantics |
| ArtifactPipeline | [artifact-pipeline.md](artifact-pipeline.md) | source AST、network/deploy logic |
| CliOrchestrator | [cli-orchestrator.md](cli-orchestrator.md) | target internals（只用 registry/protocol） |
| ValidationHarness | [validation-harness.md](validation-harness.md) | production code 对 Tests 的反向依赖 |

Boundary gate 对 Lean import graph、文件 I/O 权限和 public symbol ownership 同时检查。
