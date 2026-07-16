# Psy/DPN ZK Target 初步分析

这份文档记录 `https://github.com/PsyProtocol/psy-compiler` 对 ProofForge
多链路线的意义，以及后续是否可以把它做成一个新的 target。

结论：**可以做，但它不是普通 L1 backend，也不是 Yul-like backend。**

它更适合被放进一个新的 target family：

```text
ZK circuit sourcegen
```

也就是：

```text
Lean 合约
  -> ProofForge portable IR
  -> 生成 .psy 源码
  -> 调用 dargo compile
  -> 产出 DPNFunctionCircuitDefinition JSON
  -> 再进入 Psy 的部署/证明/执行工具链
```

## 它和 EVM/Yul 的差别

EVM 路线里，Yul 可以作为相对稳定的中间语言：

```text
Lean -> LCNF -> Yul -> solc -> EVM bytecode
```

Psy 目前公开仓库里没有看到类似 Yul 的稳定文本 IR。它的主要层次是：

- `.psy`：合约源码语言，最适合我们第一阶段生成。
- `psy-ast` / `psy-sema`：内部 AST 和类型检查结果。
- `QExecContext` / DPN ops：解释执行和电路 lowering 的内部层。
- `DPNFunctionCircuitDefinition`：最终电路函数定义 JSON，更像 artifact，
  不像适合我们直接维护的 IR。
- ABI / contract code JSON：部署和调用需要的元数据。

所以 ProofForge 不应该直接把自己的 IR 降到 DPN 内部结构。第一版应该生成
`.psy` 源码，然后复用 Psy 自己成熟的 `dargo` 编译链。

## 为什么它值得做

Psy 和 ProofForge 的愿景很匹配：

- ProofForge 强调 Lean 里的规范、证明和可验证业务逻辑。
- Psy 的执行模型本身就是 ZK/circuit/proof oriented。
- 如果能把 Lean 合约编译到 Psy，就可以展示 ProofForge 不只是
  "EVM + 几个普通链"，而是可以覆盖 ZK 原生执行环境。

这对平台叙事有价值：

```text
一套 Lean 业务逻辑
  -> EVM
  -> Solana
  -> Wasm chains
  -> Move chains
  -> ZK circuit chains / ZK VM
```

但要注意，这不是“任意 Lean 代码都能变成 ZK 合约”。ZK target 必须有更严格
的 IR subset 和 capability check。

## 建议的 target id

```text
psy-dpn
```

含义：

- `psy`：Psy ecosystem。
- `dpn`：当前编译产物围绕 DPN circuit/function definition。

不建议叫 `psy-zk` 作为第一版 id，因为 `zk` 太泛，后续可能还会有 Cairo、
Noir、Risc0、SP1、zkWasm 等 target。

## 第一阶段怎么做

第一阶段只做 source generation，不做深度编译器融合。

产物目录建议：

```text
build/psy-dpn/counter/
  Dargo.toml
  src/main.psy
  target/counter.json
  target/Counter.abi.json
  proof-forge-artifact.json
```

最小流程：

1. 从 ProofForge portable IR 生成 Counter `.psy`。
2. 生成 `Dargo.toml`。
3. 调用 `dargo compile`。
4. 确认 `target/counter.json` 非空并且是合法 JSON。
5. 调用 `dargo generate-abi`。
6. 记录 artifact metadata。

暂时不要直接接 Psy node/prover 部署。先让本地 compile + in-memory smoke 跑通。

## IR subset

第一版允许：

- `Felt`
- `Bool`
- `U32`
- 固定长度数组
- 具体 struct
- 一阶函数
- 简单 `if`
- Psy 能接受的有界循环
- `assert`
- hash capability
- scalar storage
- 固定容量 map/storage pattern
- 显式 contract method

第一版拒绝：

- 完整 Lean runtime
- closure / 高阶 runtime value
- 任意递归
- 动态 heap-heavy 数据结构
- 未建模的目标链 syscall
- 直接生成 DPN 内部结构
- 自动迁移任意 EVM storage layout

## Capability 设计

已有通用 capability 可以复用：

- `storage.scalar`
- `storage.map`
- `caller.sender`
- `env.block`
- `crypto.hash`
- `crosscall.invoke`

Psy/ZK 特有能力需要补充：

- `zk.circuit`：合约方法会 lowering 成电路函数定义。
- `zk.proof`：证明/验证/部署相关能力，先作为 research capability。

这些能力不应该污染普通业务逻辑。普通 Counter 不应该关心 ZK 细节；只有在用户
显式写 proof-oriented 合约时，才需要暴露更多 ZK capability。

## 主要风险

### 1. Toolchain 可复现性

`psy-compiler` 依赖 `psy-node` 里的 VM/prover crate，而且当前是 SSH git
依赖。CI 里直接构建可能会卡在权限和可复现性上。

短期解法：把 `dargo` 当外部工具，目标 CI 可以 optional。

### 2. 状态模型不同

Psy 的状态模型不是 EVM slot storage。很多 token 逻辑会变成 user-local
state、claim、deferred invoke 这类模式。不能把 EVM mapping 直接搬过去。

### 3. 类型和控制流更受限制

ZK/circuit target 对类型、循环、动态数据结构更敏感。ProofForge 的 portable
IR 必须能表达“这个 target 不支持”的清晰错误。

### 4. 暂时没有 Yul-like IR

这意味着我们不能像 EVM 那样维护一个可读的低层 IR snapshot。可读产物应该是
生成的 `.psy` 源码，低层 artifact 是 JSON。

## 和 ProofForge 大愿景的关系

Psy target 可以让 ProofForge 的多链愿景变得更大：

- EVM：主流合约生态。
- Solana：高性能账户模型。
- Wasm family：NEAR/CosmWasm 等 host ABI。
- Move family：resource/object 模型。
- Psy/DPN：ZK 原生执行和证明模型。

这说明 ProofForge 不是在做“一个 Solidity 替代品”，而是在做：

```text
verified contract logic portability layer
```

也就是用 Lean 写可验证业务逻辑，然后根据目标链的执行模型生成对应 artifact。

## 下一步

1. 把 `psy-dpn` 加入 target registry。
2. 在 capability registry 里加入 ZK capability。
3. 增加 `docs/targets/psy-dpn.md` 作为英文工程说明。
4. 等 portable IR 有最小 Counter fixture 后，实现 `.psy` source generator。
5. 用 `dargo compile` 做第一个 smoke。

