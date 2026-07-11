# 开发标准

本页面是面向开发者的标准索引。它链接了现有的真值来源文档，并说明了必须更新这些文档的时机。

## 真值来源

| 主题 | 权威文档 |
|---|---|
| 文档地图 | `docs/INDEX.md` |
| 已确定的架构和路线图决策 | `docs/decisions.md` |
| 已接受的产品 / 目标方向 | `docs/rfcs/0001-multichain-platform.md`, `docs/rfcs/0002-target-implementation-design.md` |
| 可移植 IR 与运行时/能力降级 | `docs/portable-ir.md`, `docs/rfcs/0003-portable-ir-and-runtime.md` |
| 规范的能力 id 与支持矩阵 | `docs/capability-registry.md` |
| 目标生命周期与各目标注释 | `docs/targets/README.md`, 以及具体的 `docs/targets/*.md` 注释 |
| EVM 基准详情 | `docs/targets/evm.md`, `Examples/Backend/Evm/README.md` |
| 共享的跨目标 Counter 场景 | `docs/shared-scenario.md` |
| 当前全项目差距与修复优先级 | `docs/multi-chain-gap-audit-2026-07-10.md` |
| 执行积压工作与验收标准 | `docs/implementation-backlog.md` |
| 验证命令与工具先决条件 | `docs/validation-gates.md` |
| 中文叙述 / 策略文档 | `docs/zh/*.md`；它们必须与英文工程文档保持一致，且不得引入独立的工程策略 |

## RFC 与决策策略

- RFC 以 `Draft` 开始。
- 只有当决策记录在 `docs/decisions.md` 中且链接文档已对齐（符合 `docs/rfcs/README.md` 第 7-8 行）时，RFC 才会变为 `Accepted`。
- 被取代的立场记录在 `docs/decisions.md` 的 `Superseded Positions` 下。
- 除非相应的决策已存在于 `docs/decisions.md` 中，否则不要在此任务中更改 RFC 状态。

## 更改代码之前

1. 阅读 `docs/INDEX.md`。
2. 阅读 `docs/decisions.md` 以及相关的 RFC/目标注释。
3. 如果更改涉及公共 CLI 标志、目标 id、能力 id、制品字段、验证命令、目标生命周期阶段或示例合约行为，请在同一次更改中更新最近的真值来源文档。
4. 运行 `docs/validation-gates.md` 中与所触及边界匹配的窄门。

## 命令运行器规范

- 根目录 `justfile` 是面向开发者的命令目录，用于常见本地工作流，例如
  `just build`、`just check`、`just evm-smoke abi-scalar` 和
  `just evm-all`。
- 将较长的目标 harness、生成的测试工程、validator 和特定目标的 shell
  逻辑保留在 `scripts/` 中；`justfile` recipe 应组合这些脚本，而不是内联
  它们的实现。
- CI 应调用与本地常见门禁相同的 `just` recipe，同时在有助于定位失败时保留独立
  的 GitHub Actions 步骤。
- 添加面向用户或 CI 覆盖的 smoke 脚本时，应在同一次更改中添加或更新匹配的
  `just` recipe/list 入口。
- 文档可以用 `just` 命令展示常见工作流，但当某个脚本是验证门禁的权威实现时，
  目标文档仍应命名底层脚本。

## 分支与目标策略

- 目标、链或后端 spike 应由目录和 target id 表示，而不是由长期 feature
  branch 表示。
- 触及下列真值来源文件的更改，必须以独立、可 review 的 PR 落到 `main`，
  不应批量夹带在某条链分支里：
  - `ProofForge/IR/*`
  - `ProofForge/Target/*`
  - `ProofForge/Contract/{Spec,Intent,Source}*`
  - `docs/capability-registry.md`
  - `docs/decisions.md`
  - `docs/portable-ir.md`
- 链分支合并后，应 retire 对应 remote branch；从那一刻起 trunk 拥有该 target。

## i18n 规则

- Feature branch 和 chain branch 不应修改 `docs/zh/*.zh.md` 或
  `scripts/i18n/manifest.json`。
- Translation sync（`scripts/translate-docs.py`）只在 `main` 上运行，并且应在英文
  真值来源文档稳定后再运行。

## Lean 包规范

- Lean 工具链是来自 `lean-toolchain` 的 `leanprover/lean4:v4.31.0`。
- 基础构建门禁是 `lake build`。
- 当前库根为 `ProofForge`、`ProofForge.Psy`、`ProofForge.Target`、
  `ProofForge.IR`、`ProofForge.Backend`、
  `ProofForge.Backend.Solana.SbpfAsm`、`ProofForge.Compiler.Yul.AST`、
  `ProofForge.Compiler.Yul.Printer`、`ProofForge.Compiler.Wasm.AST`、
  `ProofForge.Compiler.Wasm.Printer`、`ProofForge.Compiler.TS.AST`、
  `ProofForge.Compiler.TS.Printer` 和 `ProofForge.Compiler.TS.Emit`，
  均来自 `lakefile.lean`。
- 可执行文件为 `proof-forge`，根位于 `ProofForge.Cli`，并在 `lakefile.lean`
  中设置 `supportInterpreter := true`。
- 新编译的 Lean 模块必须由现有根导入或添加到 Lake 根中，文档才能声称它们是包的一部分。

## 作者侧接口规范

- 新的链无关合约使用 `ProofForge.Contract.Source`，并降低到 `ContractSpec` /
  portable IR。不要仅为了选择输出链，就在 starter 模板中加入
  `ProofForge.Backend.Evm`、Solana、NEAR 或其他 target/backend 导入；目标选择属于
  CLI（`--target <id>`）或包元数据。
- `ProofForge.Backend.Evm` 是编译器实现代码，不是产品级 authoring SDK。
  `Examples/` 下的新示例应使用 `contract_source`，或组合可 import 的
  `contract_source` 模块；backend-only probe 应放在 `Tests/` 或
  `ProofForge/IR/Examples/` 下。
- 旧的 `ProofForge.Evm` / `Lean.Evm` / LCNF `EmitYul` authoring 路线已从产品
  surface 中移除。历史 RFC 或研究笔记如果引用这条路线，必须标记为
  legacy/research，不能写成当前 authoring 指引。
- EVM 文档中的能力名称必须重用 `docs/capability-registry.md` id：`events.emit`、`crosscall.invoke`、`account.explicit`、`storage.pda`、`crosscall.cpi`。不要引入替代 id，例如 `events.log`、`cross_call.contract` 或 `account.container`。

## 计划行为标签

未实现的行为必须标记为 **Planned** 或 **Research**，不能描述成当前产品行为。

## 文档同步清单

当更改触及下列任一行时，请在**同一个 PR** 中更新列出的文档，并运行
`just doc-sync-audit`（advisory；写入 `build/doc-sync-audit.md`）。

| 代码 / 配置更改 | 需要更新的文档 |
|----------------------|-------------------|
| `ProofForge/Target/Registry.lean`（id、stage、capabilities） | README Backend Status、`docs/targets/<target>.md`、`docs/capability-registry.md`、`docs/targets/README.md` |
| `ProofForge/Cli/Fixture.lean`（支持的 targets/fixtures） | README emit examples、`docs/validation-gates.md`、AGENTS.md registry vs CLI table |
| 根 `justfile` 中 CI 跟踪的 recipe | `docs/validation-gates.md`；如果进入 `just check`，还要更新 AGENTS.md |
| `ProofForge/Contract/Stdlib/*` | `docs/sdk-ecosystem-gaps-2026-07.md`；若用户可见，还要更新 README stdlib bullet |
| `Examples/Product/*` 或 portable scenario smokes | `docs/shared-scenario.md`、`docs/validation-gates.md` |
| Gate closure（G0/P0/G1） | `docs/gate-status.md`、`docs/implementation-backlog.md` |
| Accepted RFC / decision | RFC status line、`docs/decisions.md`、最近的 target note |

完整审计登记：[doc-code-sync-audit-2026-07.md](../doc-code-sync-audit-2026-07.md)。
机械 diff：`scripts/docs/audit-doc-code-sync.sh`。

任何未在此仓库中实现的任务命令、目标、制品字段或验证路径必须标记为 `Planned` 或 `Research`，不得写为当前行为。
