# 跨目标原生差分验证设计

状态：**已接受（2026-07-14）**

## 目的

ProofForge 的承诺是：开发者只编写一份与目标链无关的业务合约，系统将其检查为可移植 IR，再根据所选 target 进行物化。仅有编译器内部测试还不能证明生成合约与该链原生 SDK 编写的实现具有相同行为，因此需要统一的独立原生参考差分层。

这是验证架构，不是新的编译路线。它不能向共享 authoring IR 或 Canonical Core 添加链专有构造。

## 被验证的编译边界

```text
单一可移植源码
  -> Authored contract
  -> 已检查的目标无关 Canonical Core
  -> target capability/extension 匹配
  -> target 自有 materializer 和 plan
  -> target artifact

独立原生参考源码
  -> 原生工具链
  -> 原生 artifact

共享场景
  -> ProofForge runner ----\
                           +-> 归一化观测 -> fail-closed 比较
  -> 原生 runner ----------/
```

Solana 的 Account、PDA、CPI 和指令数据属于 Solana extension 与 `ModulePlan`；NEAR 的 Promise、JSON ABI、receipt 和 host storage 属于 NEAR target；EVM 的 ABI、log、call、revert data 和 storage layout 属于 EVM target。比较层只观测结果，绝不把这些语义移入可移植 IR。

## 现有基础

- `testkit/scenarios` 已能运行主三链共享场景并记录资源指标。
- `testkit/compare/near` 已有 Rust `near-sdk` 参考合约和 Sandbox 双部署 runner，并采用 fail-closed observation coverage。
- `references/solana/pinocchio` 已有独立 Pinocchio 程序、reference manifest、静态等效门禁和 Surfpool live 比较。
- Stylus 已有 ProofForge direct Wasm 与固定版本 `stylus-sdk` Rust 实现的差分门禁。
- EVM 已有 Yul、bytecode、Anvil、Foundry 和 `revm` 门禁，但 Solidity 原生参考还没有与其他目标统一。

实现应整合这些资产，而不是重新创建一套平行框架。

## 原生参考规则

| Target | 主要原生参考 |
|---|---|
| EVM | 固定版本 `solc` 编译的 Solidity；Rust 只能作为附加语义模型，不能冒充原生 oracle |
| Solana | 使用 Pinocchio、原生 program crate，或按场景需要使用 Anchor 的 Rust 程序 |
| NEAR | 使用固定版本 `near-sdk` 或 `near-contract-standards` 的 Rust 合约 |
| Arbitrum Stylus | 使用固定版本 `stylus-sdk` 的 Rust 合约 |

参考实现可以是对上游合约的最小独立重写，也可以是固定版本的上游示例。每个 manifest 必须记录上游 URL 或本地来源、commit/tag 或依赖版本、license、工具链、覆盖场景和允许差异。原生参考不能导入 ProofForge planner 或 lowering 代码。

## 场景分类

### 可移植场景

Counter、ValueVault、所有权、暂停、map、event 和可移植 remote-call intent 等由一份 `Examples/Product` 源码编译到所有公开 target。各 runner 只负责把同一逻辑 actor 和输入翻译成原生调用。

### Target-extension 场景

- Solana：账户约束、PDA seed/bump、CPI 账户顺序、signer/writable、指令数据、return data 和 CU。
- NEAR：JSON 参数/返回值、storage key、attached deposit、promise action/result、receipt、log 和 gas。
- EVM：selector、calldata/returndata、revert、topic/log、call/create、storage layout 和 gas。
- Stylus：Solidity ABI、HostIO storage/call/log、Wasm 有效性、ink/gas 和 Rust SDK 互操作。

这些场景由 target 测试目录拥有。Source facade 可以暴露链原生语法，但必须在 checked Canonical Core 前降为 typed target extension。

## 归一化观测契约

语义等效不要求 byte-for-byte artifact 一致。场景结果必须能够表达：

1. 调用状态和归一化错误类别。
2. typed 返回值或 canonical 返回字节。
3. 每步调用前后的命名状态快照和余额。
4. 有序 event/log 及其 typed 字段。
5. target 自有的外部 action：EVM call/create、Solana CPI、NEAR promise/receipt。
6. 场景要求的 ABI、account 或 interface metadata。
7. EVM gas、Solana CU、NEAR gas、Wasm fuel 和 artifact size 等资源观测。

比较器必须区分：

- `observedMatch`：已收集且可比较的值全部相同。
- `observationCoverage`：已覆盖和缺失的必需维度。
- `semanticMatch`：仅当 observed match 且必需 coverage 完整时为 true。

缺失数据、未知 schema、runner skip 和未分类错误必须让语义晋级 fail closed。资源只使用 target 本地预算，不能把不同链的 gas/CU 合成一个跨链分数。

## 验证层级

| 层级 | 目的 | 典型门禁 |
|---|---|---|
| L0 migration parity | Legacy 删除期间临时比较新旧编译路线 | canonical/plan/artifact focused equivalence |
| L1 structural conformance | ABI、account layout、manifest、target plan 和 artifact 不变量 | 确定性静态门禁 |
| L2 VM behavior | 在本地确定性 VM 中执行两份独立 artifact | `revm`、Mollusk、`near-vm-runner`、Stylus VM runner |
| L3 local-chain behavior | 在同一本地节点或 sandbox 双部署 | Anvil、Surfpool、NEAR Sandbox、本地 Nitro harness |
| L4 resource regression | 语义匹配后固定 target 本地资源区间 | 带容差的预算门禁 |

L0 只用于保护迁移切片，并随旧路线删除；独立原生参考是长期 oracle。

## 对当前排期的影响

该计划不阻塞 A-CUT1e-c2。该任务继续使用现有 typed Solana plan 和 Pinocchio 证据，并补充证明公共 Solana macro 不经过 `Source.Solana.Legacy` 也能得到相同 target-owned plan。

| 架构任务 | 必需差分证据 |
|---|---|
| A-CUT2 | 直接 Authored/Canonical 路线上的主三链 Counter |
| A-CUT3 | Stateful ValueVault 及代表性产品族，全部来自唯一 Product source |
| IR-B5 | Solana Account/PDA/CPI 与独立 Rust reference 的 target-extension 场景 |
| NEAR-R4 | 现有 NEAR 原生比较从 canonical-only 公共 artifact 重放 |
| IR-B8 / A-CUT5 | 生产 Legacy 清零，比较矩阵及 coverage validator fail closed 通过 |

这样不会让测试框架重写拖延当前 authoring cutover，同时保证后续删除旧路线不能只依赖静态编译器断言。

## 非目标

- 不要求不同链的 bytecode、storage encoding 或 instruction layout 一致。
- 不把 Rust 当作所有 target 的统一原生语言。
- 不生成跨不同资源模型的单一性能排名。
- 不永久使用旧编译路线作为 oracle。
- 不为测试方便向可移植 IR 添加链原生概念。
- 不根据最小场景宣称完整协议兼容。

## 验收

当版本化的 reference/scenario schema、归一化观测契约和 coverage validator 至少驱动主三链 Counter 与 ValueVault，Solana/NEAR/EVM 的 target-extension 套件覆盖原生行为，每份 reference 都有来源记录，并且 CI 将快速确定性门禁与 heavyweight local-chain 执行分离时，本设计完成落地。
