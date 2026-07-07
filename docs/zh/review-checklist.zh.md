# 多链设计评审检查清单

在评审 ProofForge 设计文档和即将进行的实现时，请使用此检查清单。重点关注路径是否可以增量交付，而不是愿景是否宏大。

已确定的决策：[decisions.md](decisions.md)。

## 待确认的问题

### 1. 目标分类清晰

确认：

- EVM 是直接编译器目标。
- NEAR/CosmWasm 是 Wasm 宿主目标。
- Solana 是二进制工具链目标。
- Sui/Aptos 是 Move 源代码生成目标。
- Psy/DPN 是 ZK 电路源代码生成目标。

如果设计将所有这些视为同一种后端类型，请将其退回。

### 2. 能力是显式的

合约使用的每个面向链的操作都应通过 [capability-registry.md](capability-registry.md) 中的能力 id 列出：

- storage
- caller/signer
- value/native token
- events/logs
- cross-contract call / CPI / submessage
- account/object/resource
- crypto / precompile / syscall

编译器必须拒绝不支持的目标，而不是默默地改变语义。

### 3. Solana 不是 EVM 形态的

Solana 评审重点：

- 账户必须是显式的。
- 指令数据必须是显式的。
- PDA 必须是显式的。
- CPI 必须是显式的。
- 不要将 Solana 状态隐藏为通用的合约存储。

良好的方向：

```text
entrypoint manifest + accounts schema + generated validator + Lean handler
```

风险方向：

```text
auto-map EVM slot storage to Solana accounts
```

### 4. Wasm 家族区分宿主 ABI

NEAR 和 CosmWasm 都是 Wasm，但绝不能共享同一个目标 id。

确认：

- NEAR 有自己的方法导出、宿主 KV、promises。
- CosmWasm 有 instantiate/execute/query、region ABI、submessages。
- Wasm 运行时可以共享；宿主桥接必须分开。

权威 CosmWasm 草案：[targets/wasm-family.md](targets/wasm-family.md)。

### 5. Move 使用源代码生成

第一阶段 Move 生成 Move 源代码/包，而不是在 MoveVM 上运行完整的 Lean 运行时。

确认：

- Lean 证明在代码生成之前完成。
- Move 仅携带可执行逻辑。
- IR 显式表达 resource/object/ability。
- Sui 和 Aptos 分开处理。

### 6. ZK 目标不伪装成 Yul 目标

Psy/DPN 评审重点：

- 首先生成 `.psy` 源代码。
- 将 DPN 电路 JSON 视为制品，而不是 ProofForge 自己的 IR。
- 保持 ZK/电路能力显式化。
- 在公共编译器 API 足够稳定之前，不要直接发射 Psy 内部结构。

权威 Psy 草案：[targets/psy-dpn.md](targets/psy-dpn.md)。

### 7. 从第一天起就包含制品元数据

每个目标构建都应发射：

- 目标 id
- 制品路径和哈希
- 源模块
- 使用的能力
- 工具链版本
- 证明/检查状态
- 警告

这将提供给 CI、云平台和审计追踪。

## 推荐评审顺序

1. [RFC 0001](rfcs/0001-multichain-platform.md) —— 愿景与边界。
2. [RFC 0002](rfcs/0002-target-implementation-design.md) —— 目标与流水线。
3. [可移植 IR](portable-ir.md) 和 [能力注册表](capability-registry.md)。
4. [实现待办列表](implementation-backlog.md) —— 任务切片。
5. 目标说明：
   - [EVM](targets/evm.md)
   - [Wasm 家族](targets/wasm-family.md)
   - [Solana sBPF](targets/solana-sbf.md)
   - [Move 家族](targets/move-family.md)
   - [Psy DPN ZK 目标](targets/psy-dpn.md)
6. [共享场景：Counter](shared-scenario.md)。

## 已记录的决策

参见 [decisions.md](decisions.md) 了解：

- 在非 EVM spike 之前的第 1 阶段
- 并行 CosmWasm + Solana spike
- `solana-sbpf-linker` 作为主要 Solana 路径
- Aptos 优先的 Move POC
- `psy-dpn` 作为 Experimental 阶段的 ZK 电路源代码生成目标

## 暂不执行

- 在两个 Experimental 目标存在之前，不进行云平台 UI 开发。
- 自动 Solana 账户推断。
- 不将直接 Move 字节码生成作为第一个 Move 路径。
- 不为所有 Wasm 链使用同一个 Wasm 目标 id。
- 在生成的 `.psy` 源代码工作之前，不直接进行 Psy DPN 内部发射。
- 不承诺“任何 Lean 代码都能在每条链上运行”。

## 好的信号 vs 坏的信号

好的信号：

- EVM 基准保持稳定。
- 每个新目标都有冒烟测试。
- 不支持的能力会产生清晰的错误。
- 制品元数据在各目标间趋于统一。
- 共享场景在至少两个截然不同的目标上工作。

坏的信号：

- 后端堆积特殊情况的 `if target == ...` 分支。
- 能力 id 在文档间不一致。
- Solana 账户逻辑隐藏在运行时中。
- Move 代码生成是缺乏 IR 约束的字符串模板。
- ZK 目标向能力检查器隐藏证明/电路限制。
- 文档与 CLI 产生脱节。

### 8. 文档↔代码同步（2026-07）

当评审触及 registry、CLI、`justfile` gates、Stdlib 或 shared examples 的 PR 时：

- [ ] 最近的英文真值来源文档已更新（见 [development-standards.md](development-standards.md) 的文档同步清单）。
- [ ] 如果 target ids、gates 或 capability matrix 改变，已在本地运行 `just doc-sync-audit`（advisory P0 mechanical drift）。
- [ ] 未实现路径标记为 **Planned** / **Research**，而不是当前行为。
