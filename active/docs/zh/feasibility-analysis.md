# ProofForge 多链愿景可行性分析

日期：2026-06-30

## 结论

这个愿景可行，但不能理解为“同一份合约代码完全无差别地跑在所有链上”。更现实、也更强的路线是：

```text
Lean 业务核心 + 形式化证明
  -> 可移植合约 IR
  -> 显式 capability 边界
  -> 各链 target adapter
  -> 本地测试 + 云端部署平台
```

核心判断：

- 技术上可行：EVM baseline 已经跑通，行业里也已经存在 Reach、Solang、Wasm 合约、Move VM 等相关先例。
- 产品上有机会：开发者确实需要更统一的多链构建、测试、部署、验证体验，类似 Vercel/Cloudflare 的平台形态有想象力。
- 难点不在“能不能编译”，而在“如何定义跨链共同语义”。EVM、Solana、Wasm 链、Move 链的账户、存储、调用和资产模型差异很大。
- 第一阶段不能追求所有链全覆盖。应该先证明“一套 Lean 业务逻辑 + 多 target 构建 + 多 target smoke test”可以成立。

一句话版本：ProofForge 不是“把 EVM 合约搬到所有链”，而是“用 Lean 写可证明的业务核心，再按目标链显式选择能力和部署适配器”。

## 我们已经做了哪些分析

已经做过初步可行性分析，结论写进了英文 RFC 与决策记录：

- [RFC 0001: Lean-first multi-chain contract platform](../rfcs/0001-multichain-platform.md)
- [RFC 0002: Target implementation design](../rfcs/0002-target-implementation-design.md)
- [Design decisions](../decisions.md)
- [Portable IR](../portable-ir.md) / [Shared scenario](../shared-scenario.md)

本中文文档是在 RFC 基础上的战略版分析，重点回答：

- 市面上有没有类似东西？
- 为什么 ProofForge 仍然有差异化？
- 哪些链最值得先做？
- 哪些部分最难？
- 如何用最小成本验证愿景？

## 外部生态判断

| 方向 | 已有项目/生态 | 说明 | 对 ProofForge 的启发 |
|---|---|---|---|
| 一次编写，多链部署 | Reach, https://www.reach.sh/ | 已经证明“多链合约开发抽象”有真实需求。 | 多链平台不是空想，但需要强产品体验和清晰语义边界。 |
| Solidity 编到非 EVM | Solang, https://solang.readthedocs.io/ | Solidity 可以编译到 Solana、Polkadot/Soroban 等目标。 | 多 target 编译可行；ProofForge 的差异化应来自 Lean、证明和平台化。 |
| EVM 工具链 | Foundry, solc | 本地测试、调试、bytecode pipeline 成熟。 | EVM 应继续作为 baseline 和回归测试主线。 |
| Solana | https://solana.com/docs/core/programs | 程序、账户、instruction、CPI 模型和 EVM 差异极大。 | Solana 是验证抽象能力的关键目标，不能只做 EVM-like 链。 |
| Wasm 链 | NEAR、CosmWasm、Polkadot ink! | 都用 Wasm，但 host ABI、存储、消息模型不同。 | 可以做 Wasm family，但必须保留链级 adapter。 |
| Move 链 | Sui、Aptos | 资源、对象、模块模型强，和 EVM/Solana 都不同。 | Move family 是高价值研究线，适合体现类型和证明优势。 |
| Bitcoin 生态 | Stacks Clarity、BitVM | 更偏专用语言、L2、验证或脚本扩展，不是通用合约 VM。 | 先做研究，不作为早期直接编译目标。 |

结论：市场上有相邻产品，但没有看到一个主流项目同时满足：

- 入口语言是 Lean；
- 业务逻辑和证明天然绑定；
- 目标是多链编译、测试、部署平台；
- 以 capability 方式显式暴露链差异；
- 最终产品形态类似 Vercel/Cloudflare。

这就是 ProofForge 的机会点。

## 为什么不能直接“一份代码到所有链”

这个愿景最大的坑是语义差异。

EVM 的世界：

- 合约有自己的地址。
- 存储是 slot。
- `msg.sender`、`msg.value`、logs、call 是核心模型。
- ABI selector 很自然。

Solana 的世界：

- 程序本身通常不持有同样意义上的内部状态。
- 状态在 accounts 里，调用方显式传账户。
- instruction data、account metadata、PDA、CPI 是核心模型。

Wasm 链的世界：

- Wasm 只是执行格式，不同链的 host ABI 不一样。
- NEAR、CosmWasm、ink! 的存储、消息、事件、部署包都不同。

Move 的世界：

- 资源、对象、模块和权限模型是核心。
- Sui 和 Aptos 都是 Move 系，但对象模型和生态工具也不完全一样。

所以正确抽象不是：

```text
同一份代码 -> 神奇自动适配所有链
```

而是：

```text
同一份业务核心 -> 显式声明用到哪些 capability -> 支持该 capability 的 target 才能编译
```

这会让平台更可信。编译器应该拒绝不支持的目标，而不是偷偷改变语义。

## 可行架构

建议把系统拆成四层：

```text
1. Lean source
   业务逻辑、状态机、类型、证明

2. Portable Contract IR
   入口函数、数据类型、状态转移、capability 调用、证明元数据

3. Target Backend
   EVM/Yul, Solana/sBPF, Wasm family, Move family

4. Tooling and Cloud Platform
   build matrix, smoke tests, artifact registry, deploy, verification report
```

关键是第二层。只要没有 portable contract IR，后端会越写越像一堆特殊脚本；一旦有了 IR，后端扩展、测试矩阵、云平台都能统一起来。

## 目标链优先级

这部分不再只是研究偏好，而是当前产品实现的前置规约。权威记录见
[D-045 主三链完成规约](../decisions.md) 和
[Gate P0](../gate-status.md)：在继续推进更多链之前，ProofForge 必须先按
`solana-sbpf-asm` -> `evm` -> `wasm-near` 的顺序，把 Solana、Ethereum 和
NEAR/Wasm 做到生产级完善。

“完成”不是只生成一点代码，而是每条链都要具备 target-first 构建/发射、本地执行
或部署冒烟、制品/部署元数据、能力诊断、资源预算、CI 覆盖和同步维护的文档。

### 第一优先级：Solana/sBPF

原因：

- 和 EVM 差异大，能真正验证抽象能力。
- 如果 Solana 这种显式账户模型能被统一入口表达出来，后续多链抽象才可信。
- Solana 生态足够大，平台化价值明显。

最大难点：

- account model 需要在方法签名、adapter 或 capability 层显式表达。

### 第二优先级：Ethereum/EVM

原因：

- 工具成熟，Foundry 和 Anvil 可以做本地 smoke/deploy test。
- 市场最大，最容易展示 demo 和验证 artifact/deploy metadata。
- EVM 是重要的对照组，但不能让它反向绑死上层 SDK 设计。

目标：

- 把现有 EVM backend 从实验状态整理成稳定生产级 backend。
- 让 Ethereum 路径覆盖 target-first 构建、Yul/bytecode、ABI、部署清单和本地链验证。

### 第三优先级：NEAR/Wasm

原因：

- NEAR 代表 Wasm-host 架构，能验证共享 Wasm lowering 加链级 host adapter 的路线。
- Wasm 是长期收益很高的编译目标，但不能把 Wasm 当成单独一条链。

注意：

- NEAR 是当前主三链之一；CosmWasm、Polkadot/ink!、Soroban、ICP 等 Wasm-host
  目标要等 Gate P0 之后再从文档研究或冻结 spike 继续推进。

### 后续优先级：Move family

原因：

- Sui/Aptos 的 Move 资源模型和 Lean 的类型/证明优势可能有很强结合。
- 这是差异化明显的研究线。

第一版建议：

- 先研究生成 Move source，而不是直接生成 Move bytecode。
- 先选 Sui 或 Aptos 中一个做 prototype，不要同时做。

### Bitcoin 生态：研究，不做早期 target

原因：

- Bitcoin L1 不是通用合约 VM。
- Stacks/Clarity、BitVM、RGB、Taproot Assets 等方向各自差异大。
- 早期投入会拉散主线。

建议：

- 放在 research track。
- 产品叙事可以说 ProofForge 关注 Bitcoin ecosystem，但不要承诺近期直接支持 Bitcoin L1。

## 产品可行性

把 ProofForge 做成 Vercel/Cloudflare 式平台是合理的，但它应该排在 compiler baseline 之后。

理想产品体验：

```text
连接 GitHub
  -> 选择 Lean contract project
  -> 选择 target matrix: EVM, Solana, Wasm, Move
  -> 云端 build
  -> 每个 target 跑本地链或测试网 smoke
  -> 生成 artifact / ABI / proof report
  -> 用户确认签名
  -> 部署到 testnet/mainnet
  -> dashboard 追踪版本、地址、日志、验证状态
```

平台价值：

- 降低多链部署的工具链成本。
- 每次部署都带 proof/build/test report。
- 统一管理 artifact、版本、链上地址、测试结果。
- 对团队来说，比本地脚本更容易审计和复现。

但前置条件是：

- 本地 CLI 必须稳定。
- 至少两个差异很大的 target 跑通。
- 每个 target 都有 smoke test。

## 最大风险

| 风险 | 严重度 | 说明 | 缓解方式 |
|---|---|---|---|
| 跨链语义被过度承诺 | 高 | “一份代码所有链完全一致”不现实。 | 使用 portable core + capabilities，并让 compiler 拒绝不支持目标。 |
| Solana account model 抽象失败 | 高 | 如果账户模型表达不好，Solana backend 会很别扭。 | 先做最小账户显式模型，不追求自动推断。 |
| Wasm family 被误认为一个 target | 中高 | NEAR/CosmWasm/ink! host ABI 差异大。 | 做 shared Wasm lowering + chain adapter。 |
| Move backend 路线不清 | 中高 | 生成 Move source、Move bytecode、还是 adapter，都需要研究。 | 先做 research spike，选 Sui 或 Aptos 单点突破。 |
| 云平台过早 | 中高 | 后端不稳定时做云平台会变成 UI 壳。 | 先本地 CLI 和 target matrix，再云化。 |
| Lean 生态学习成本 | 中 | Web3 开发者未必熟 Lean。 | 用模板、示例、可视化 proof report 降低门槛。 |

## 最小可行验证路线

建议用 Gate P0 验证愿景，而不是一开始追求完整平台或继续增加链数量。

### Milestone 1：Solana 生产级完成

验收标准：

- `proof-forge build --target solana-sbpf-asm` 形态稳定。
- Solana direct sBPF assembly、IDL/client、manifest、artifact metadata 和本地
  执行/部署 smoke 稳定。
- Pinocchio/reference equivalence、compute-unit budget 和 CI 覆盖达到 Gate P0 要求。

### Milestone 2：Ethereum/EVM 生产级完成

验收标准：

- `proof-forge build --target evm` 形态稳定。
- EVM examples、Foundry smoke、Anvil deploy smoke、ABI、bytecode、initcode、
  deploy manifest 和 artifact metadata 全稳定。
- EVM gas budget 和 semantic-plan 迁移达到 Gate P0 要求。

### Milestone 3：NEAR/Wasm 生产级完成

验收标准：

- `proof-forge build --target wasm-near` 形态稳定。
- EmitWat/Wasm AST、NEAR host adapter、本地执行或 sandbox/deploy metadata、
  capability diagnostics 和 artifact metadata 全稳定。
- NEAR gas budget 和 CI 覆盖达到 Gate P0 要求。

Gate P0 关闭之后，才恢复 CosmWasm、Move、ZK、UTXO 等后续链的实现推进。详见
[decisions.md](../decisions.md)、[gate-status.md](../gate-status.md) 和
[shared-scenario.md](../shared-scenario.md)。

三条主链都通过 Gate P0，才算当前阶段的最小可行验证路线完成。

### Milestone 4：Move（Aptos 优先）

验收标准：

- Aptos counter package 从 portable IR 生成并通过 `aptos move test`。
- Sui object POC 作为后续 slice，不在 Milestone 4 阻塞项内。

如果 Milestone 3 成功，这个愿景就从“概念”进入“高可信原型”。

## 投资判断

值得继续投入，但投入顺序要保守：

1. 先按 D-045 完成主三链：Solana、Ethereum/EVM、NEAR/Wasm。
2. 继续收紧 portable IR 和 capability system（见 [portable-ir.md](../portable-ir.md)）。
3. Gate P0 关闭后，再恢复 CosmWasm、Move、ZK、UTXO 等后续链的实现推进。
4. 云平台等主三链具备稳定本地构建、执行/部署和验证报告后再启动。

ProofForge 的强叙事不是“我们支持很多链”，而是：

> 用 Lean 写可证明的合约业务核心，用一个平台生成多链 artifact、测试报告和部署记录。

这比普通多链编译器更强，也比单链智能合约 IDE 更有长期平台价值。
