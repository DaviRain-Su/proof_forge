# ProofForge

Lean 优先的多链智能合约平台。

ProofForge 的目标是：一份经过验证的 Lean 合约代码库，可以在多个区块链目标家族
中编译、测试和部署。合约面向链中立的 Contract Intent API 编写；编译器将其降级
为可移植 IR，按目标做 capability 路由，并产出链原生制品。目标不支持的能力会在
编译期被拒绝，而不是静默改变语义。

入口文档：

- [docs/INDEX.md](../INDEX.md) — 完整文档地图。
- [RFC 0001](../rfcs/0001-multichain-platform.md) — 多链架构与路线图；
  [RFC 0002](../rfcs/0002-target-implementation-design.md) — 目标实现设计。
- [Design decisions](../decisions.md) — 已定决策（D-001…D-045）。
- [形式化验证路线图](../formal-verification.md) — 现有证明锚点与分阶段定理目标。
- [演示录屏](https://asciinema.org/a/fn6o6kSxB5RpMXJl) — 终端演示：编写 → 编译 → 部署 → 测试。

中文文档：

- [中文文档索引](README.md)
- [架构评审（2026-07）：统一 SDK 输入与分支收敛](architecture-review-2026-07.md)
- [多链愿景可行性分析](feasibility-analysis.md)

## 后端状态

所有后端都在 `main` 上（"链"是目录和 target id，不是分支）。生命周期阶段见
[docs/targets/README.md](../targets/README.md)。
主三链完成规约 (D-045) 已关闭：`solana-sbpf-asm`、`evm` 和 `wasm-near`
已经具备生产级本地/CI 门禁。下一条硬化主线是 CLI M3/M4，把 legacy flags
迁移到 `proof-forge build|emit|check --target ...`，然后再推进 Tier-1 M3/M4 工作。

| Target id | 管线 | 阶段 | 本地验证 |
|---|---|---|---|
| `evm` | Lean / portable IR → Yul → `solc` → bytecode | 基线（成熟） | golden Yul、诊断、Foundry 运行时冒烟、Anvil 部署 |
| `solana-sbpf-asm` | portable IR → sBPF assembly → `sbpf` → ELF | Experimental | Mollusk 测试、Surfpool/Web3.js live 冒烟、Pinocchio 等价性门禁 |
| `wasm-near` | portable IR → `EmitWat`（Wasm AST → WAT）→ `wat2wasm` | Experimental | 诊断、IR 覆盖清单、形式化 trace obligation、target-first 冒烟、离线宿主冒烟、artifact/deploy metadata |
| `psy-dpn` | portable IR → `.psy` → Dargo → DPN circuit JSON | Experimental（受限子集） | golden source、诊断、`dargo` execute 冒烟 |
| `aleo-leo` | portable IR → Leo package → `leo build`/`leo test` | Research spike | Counter/PureMath golden fixture 与冒烟 |
| `wasm-cloudflare-workers` | portable IR → TypeScript Worker | Research（链下宿主，D-033） | `tsc` 类型检查、`wrangler` dry-run |

多链 Token SDK（`TokenSpec`，[RFC 0006](../rfcs/0006-multichain-token-sdk.md)）
把同一份 token 意图在 EVM 上路由为 ERC-20 bytecode，在 Solana 上路由为
SPL Token / Token-2022 部署计划。

## 快速开始

从 [casey/just](https://github.com/casey/just) 安装 `just`；根目录 `justfile`
是面向开发者的命令目录和 CI 入口。

```sh
just --list        # 所有 recipe
just build         # lake build
just check         # 快速静态门禁（Lean + EVM + Psy）
just evm-all       # 完整 EVM 门禁：示例编译、Foundry 冒烟、Anvil 部署
just ci            # 本地跑完整 CI 序列
```

直接用 Lake 构建：

```sh
lake build
```

把 EVM Counter 示例编译为运行时 bytecode：

```sh
lake env proof-forge build --target evm --root . --module contract \
  -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean
```

从内置的 portable IR fixture 产出其他目标的制品：

```sh
lake env proof-forge emit --target wasm-near --fixture counter --format wat -o build/wasm-near
lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format elf -o build/solana/counter.so
lake env proof-forge emit --target psy-dpn --fixture counter --format psy -o build/psy/Counter.psy
lake env proof-forge emit --target aleo-leo --fixture counter --format leo -o build/aleo
lake env proof-forge emit --target wasm-cloudflare-workers --fixture counter --format ts -o build/ts/Counter.ts
```

各目标完整的可运行验证命令及工具前置条件（Foundry、`solc`、`sbpf`、
`wat2wasm`、`dargo`、`leo`、`wrangler` 等）见
[docs/validation-gates.md](../validation-gates.md)。云端/agent 环境说明见
[AGENTS.md](../../AGENTS.md)。

## 架构

```mermaid
flowchart TB
  subgraph authoring ["作者层（用户面，链中立）"]
    SDK["Lean SDK<br/>contract_source / Contract Intent API"]
    TOK["Token SDK<br/>TokenSpec"]
    LEARN[".learn 解析器<br/>（冻结的兼容层）"]
  end

  subgraph core ["编译器私有核心"]
    SPEC["ContractSpec"]
    IR["可移植 IR<br/>+ AllocatorConfig + 所有权规则"]
    SEM["IR 语义 + 形式化锚点<br/>（FV 路线图）"]
  end

  subgraph routing ["目标路由（--target）"]
    REG["Target registry<br/>profile + allocator 绑定"]
    CAP["Capability 检查<br/>拒绝不支持的 intent"]
    EXT["Target Extension SDK<br/>Solana 账户/PDA/CPI 等"]
  end

  subgraph backends ["后端"]
    EVM["EVM<br/>Plan → Yul → solc"]
    SOL["Solana<br/>sBPF asm → ELF"]
    NEAR["NEAR<br/>EmitWat → WAT → wasm"]
    PSY["Psy/DPN<br/>.psy → Dargo"]
    ALEO["Aleo<br/>Leo package"]
    CFW["CF Workers<br/>TypeScript"]
  end

  subgraph artifacts ["制品与验证"]
    ART["bytecode/ELF/wasm/circuit + ABI/IDL<br/>artifact + deploy manifest + TS client"]
    GATES["门禁：Lean 测试 · testkit（规划中，RFC 0007）<br/>Foundry · Mollusk/Surfpool · 离线宿主 · dargo/leo"]
  end

  SDK --> SPEC
  TOK --> SPEC
  LEARN --> SPEC
  SPEC --> IR
  IR --- SEM
  IR --> CAP
  REG --> CAP
  EXT --> CAP
  CAP --> EVM & SOL & NEAR & PSY & ALEO & CFW
  EVM & SOL & NEAR & PSY & ALEO & CFW --> ART
  ART --> GATES
```

- **Contract Intent API** — 默认 SDK 表面：state、entrypoint、event、
  caller/value 访问、checked 算术、断言和证明，不需要 import 目标链模块。
- **Target Extension SDK** — 合约确实需要链原生语义时显式引入（Solana
  账户/PDA/CPI、allocator 选择等）。扩展通过 capability id 和 target
  metadata 降级，绝不给可移植 IR 增加仅单链使用的 constructor（D-027）。
- **Target adapter** — 每个链家族的 ABI、打包、测试运行器和部署逻辑；
  `--target` 选择 adapter，不支持的 intent 在产出制品前被拒绝（D-028）。

作者层边界见 [docs/authoring-model.md](../authoring-model.md)（遗留 `.learn`
解析器是冻结的兼容层，不是第二门产品语言）；IR 规范见
[docs/portable-ir.md](../portable-ir.md)。

## 开发文档

- [Development standards](../development-standards.md)
- [Validation gates](../validation-gates.md)
- [Implementation backlog](../implementation-backlog.md) — 当前优先级是
  Workstream 24（合并收敛跟进）和 Workstream 25（形式化验证）。
- [Capability registry](../capability-registry.md)
- [Shared scenario: Counter](../shared-scenario.md) — 跨目标验收测试；
  当前阶段目标是在 `evm` + `solana-sbpf-asm` + `wasm-near` 上跑通。
- Target 说明：[docs/targets/](../targets/README.md)

## 作者侧模块命名

- **可移植作者模块：** `ProofForge.Contract.Source`（新的链无关合约和模板默认使用）。
- **目标选择：** `proof-forge --target <id>` 在构建/发射阶段选择 EVM、Solana、NEAR
  或其他后端；可移植合约源码不应该为了选择输出链而导入目标链模块。
- **EVM-native 模块：** `ProofForge.Evm` 及命名空间 `Lean.Evm` 仍保留给旧版
  EVM 示例和明确只面向 EVM 的 adapter 工作。

`Lean.Evm` 命名空间来自 Lean fork 迁移。统一重命名到 `ProofForge.*`
命名空间已列入 backlog（Workstream 24），因为 `Lean.Evm` 会遮蔽 Lean
编译器自身的 `Lean` 命名空间。

## 路线图

```text
Phase 0: EVM 基线                          （完成）
Phase 1: target registry + portable IR     （完成）
Phase 2+: 并行后端 spike                   （Solana、NEAR、Psy 已在 main；
                                            Aleo、CF Workers 为 research）
当前:     shared scenario 在 evm + solana-sbpf-asm + wasm-near 跑通，
          合并收敛跟进（Workstream 24），
          形式化验证路线图（Workstream 25）
之后:     Move 家族（Aptos 优先）、云平台（两个以上目标达到
          Experimental 且 shared-scenario 对齐后；D-010）
```

规范 target id 与完整决策日志：[docs/decisions.md](../decisions.md)。
`docs/targets/solana-sbf.md` 是 Solana 目标说明的历史别名；规范路线是
`solana-sbpf-asm`（D-026）。
