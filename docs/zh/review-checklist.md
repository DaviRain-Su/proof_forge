# 多链方案 Review 清单

这份清单用于 review 当前文档和后续设计。重点不是判断“愿景是否宏大”，而是判断实现路径是否能一步步落地。

## 需要重点确认的问题

### 1. Target 划分是否清楚

需要确认：

- EVM 是直接编译目标。
- NEAR/CosmWasm 是 Wasm host 目标。
- Solana 是二进制工具链目标。
- Sui/Aptos 是 Move source generation 目标。
- Psy/DPN 是 ZK circuit source generation 目标。

如果某个设计把这些目标都当成同一种 backend，就应该退回重写。

### 2. Capability 是否足够显式

需要确认每个合约用到的链能力都能被列出来：

- storage
- caller/signer
- value/native token
- events/logs
- cross-contract call/CPI/submessage
- account/object/resource
- crypto/precompile/syscall

重点看编译器是否会在不支持时拒绝目标，而不是静默改语义。

### 3. Solana 是否避免 EVM 化

Solana review 重点：

- 账户必须显式。
- instruction data 必须显式。
- PDA 必须显式。
- CPI 必须显式。
- 不要把 Solana state 伪装成普通 contract storage。

好的方向：

```text
entrypoint manifest + accounts schema + generated validator + Lean handler
```

风险方向：

```text
自动把 EVM slot storage 映射成 Solana account
```

### 4. Wasm family 是否区分 host ABI

NEAR 和 CosmWasm 都是 Wasm，但不能混成一个 target。

需要确认：

- NEAR 有自己的 method export、host KV、promise。
- CosmWasm 有 `instantiate/execute/query`、region ABI、submessage。
- Wasm runtime 可以共享，但 host bridge 必须拆开。

### 5. Move 是否走源码生成

Sui/Aptos 第一阶段应该生成 Move source/package，不应该尝试把完整 Lean runtime 搬到 MoveVM。

需要确认：

- Lean proofs 在编译前完成。
- Move 只承载 executable logic。
- IR 显式表达 resource/object/ability。
- Sui 和 Aptos 分别处理，不假装 Move family 完全一致。

### 6. ZK target 是否避免伪装成 Yul target

Psy/DPN review 重点：

- 第一阶段生成 `.psy` 源码。
- 把 DPN circuit JSON 当成 artifact，而不是 ProofForge 自己的 IR。
- ZK/circuit capability 要显式。
- 在 `.psy` sourcegen 跑通前，不要直接生成 Psy 内部 DPN 结构。

### 7. Artifact metadata 是否从第一天就有

每个 target build 都应该输出：

- target id
- artifact 路径
- hash
- source module
- capabilities
- toolchain versions
- proof/check 状态
- warnings

这会直接影响后续 CI、云平台和审计。

## 推荐 review 顺序

1. 先看 [RFC 0001](../rfcs/0001-multichain-platform.md)：确认愿景和边界。
2. 再看 [RFC 0002](../rfcs/0002-target-implementation-design.md)：确认 target 和实现路线。
3. 再看 [RFC 0003](../rfcs/0003-portable-ir-and-runtime.md)：确认 portable IR、capability 机制、runtime profile 是否成立——这是其余 backlog 的地基。
4. 再看 [Implementation Backlog](../implementation-backlog.md)：确认任务拆分是否合理。
4. 再看 target 专页：
   - [Wasm family](../targets/wasm-family.md)
   - [Solana sBPF](../targets/solana-sbf.md)
   - Move family (removed from `main`, D-057; archive `archive/move-cloudflare-2026-07-15`)
   - [Psy DPN ZK target](../targets/psy-dpn.md)

## 当前最需要拍板的决策

已记录在 [decisions.md](../decisions.md)，包括：

- Phase 1 先于非 EVM spike
- CosmWasm 与 Solana 并行 spike
- Solana 主路线 `solana-sbpf-linker`
- Move Aptos 优先 POC
- `psy-dpn` 作为 Experimental 阶段 ZK circuit sourcegen target

Review 时对照 decisions 与 backlog，无需在此重复争论已关闭项。

## 暂时不要做的事

- 不要先做云平台 UI。
- 不要先做自动 Solana account 推断。
- 不要直接生成 Move bytecode。
- 不要把所有 Wasm 链合并成一个 target。
- 不要在 `.psy` sourcegen 跑通前直接生成 Psy DPN 内部结构。
- 不要承诺“一份任意 Lean 代码跑所有链”。

## 判断项目是否走对了的信号

好信号：

- EVM baseline 一直稳定。
- 每个新 target 都有 smoke test。
- target 不支持时能给清晰错误。
- artifact metadata 越来越统一。
- shared scenario 能跨至少两个差异大的 target。

坏信号：

- backend 里开始堆大量特殊 if。
- capability 没有统一命名。
- Solana account 逻辑藏在 runtime 里。
- Move codegen 只是字符串模板，没有 IR 约束。
- ZK target 把 proof/circuit 限制藏起来，不通过 capability checker 暴露。
- 文档和实际 CLI 越来越不一致。
