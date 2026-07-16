# ProofForge 多链技术实现方案

日期：2026-06-30

## 总结

ProofForge 不应把所有链都当成同一种 backend。工程划分见
[RFC 0002](../rfcs/0002-target-implementation-design.md)（**工程细节以该 RFC 为准**）。

```text
Lean 业务代码 + 证明
  -> 可移植合约 IR（见 portable-ir.md）
  -> target profile / capability 检查（见 capability-registry.md）
  -> 不同目标族的 backend
  -> 链原生工具构建和 smoke test
```

目标族四类：

| 族 | 代表 target | 模式 |
|---|---|---|
| 直接编译 | `evm` | Lean → LCNF → Yul → solc |
| Wasm host | `wasm-near`, `wasm-cosmwasm` | Lean → EmitZig → Wasm + host bridge |
| 二进制工具链 | `solana-sbpf-linker` | Lean → EmitZig → bitcode → sbpf-linker |
| 源码生成 | `move-aptos`, `move-sui` | Portable IR → Move package |

已拍板决策：[decisions.md](../decisions.md)

## 工程文档索引

| 主题 | 文档 |
|---|---|
| 架构愿景 | [RFC 0001](../rfcs/0001-multichain-platform.md) |
| Target / pipeline / artifact | [RFC 0002](../rfcs/0002-target-implementation-design.md) |
| Portable IR | [portable-ir.md](../portable-ir.md)、[RFC 0003](../rfcs/0003-portable-ir-and-runtime.md) |
| Capability id | [capability-registry.md](../capability-registry.md) |
| Counter 跨链场景 | [shared-scenario.md](../shared-scenario.md) |
| 任务拆分 | [implementation-backlog.md](../implementation-backlog.md) |
| Target 研究笔记 | [targets/](../targets/README.md) |

## Target id（canonical）

与 RFC 0002 一致：

- `evm`
- `wasm-near`, `wasm-cosmwasm`
- `solana-sbpf-linker`（主路线）, `solana-zig-fork`（fallback）
- `move-aptos`（Move POC 优先）, `move-sui`（后续）
- `wasm-polkadot` / ink! — 仅 research，未进 registry

## 近期里程碑

与 [implementation-backlog.md](../implementation-backlog.md) 对齐：

### M1：目标注册 + IR + metadata（Phase 1）

- `TargetProfile` 概念落地
- [portable-ir.md](../portable-ir.md) Counter 可走通
- EVM build 生成 `proof-forge-artifact.json`
- [capability-registry.md](../capability-registry.md) 与文档一致

### M2：并行 spike — CosmWasm + Solana（Phase 2）

Phase 1 完成后并行，不固定先后：

- CosmWasm Counter：`cosmwasm-check` + instantiate/execute/query
- Solana Counter：stock Zig + sbpf-linker + Mollusk/validator

详见 [shared-scenario.md](../shared-scenario.md)。

### M3：Move Aptos POC（Phase 3）

- 从 IR 生成 Aptos counter package
- `aptos move compile/test` 通过
- Sui object POC 作为独立 follow-up

### M4：跨 target 场景硬化 + CI matrix

- 多 target shared scenario 测试
- 可选 CI job 不阻塞 base build

## 当前判断

优先顺序见 [decisions.md](../decisions.md)：

1. EVM metadata 和 target profile
2. Portable IR + Counter shared scenario
3. CosmWasm 与 Solana **并行** spike
4. Aptos Move sourcegen
5. 云平台等至少两个 target 达到 Experimental

## 风险（摘要）

完整列表见 [可行性分析](feasibility-analysis.md) 和 RFC 0002 Open Engineering Risks：

- sBPF 上 Lean runtime 体积与 loader 约束
- CosmWasm 需要更紧的 no-WASI runtime
- Move 需要真实 resource/object 模型，不能只做字符串模板
- Portable IR 不能太 EVM 化，也不能过度抽象失去可用性

## 参考

- 英文文档入口：[INDEX.md](../INDEX.md)
- Review 清单：[review-checklist.md](../review-checklist.md)
