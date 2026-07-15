# AGENTS.md

这是 ProofForge V2 独立工程的 agent 控制面。它只负责导航、当前检查点和工作
协议，不替代 PRD、架构、技术规格或测试规格。

## Project Mission

构建 Lean 4 编译器 `proof-forge-next`：统一的 `program ... where` 源码经类型化、
目标中立语义和需求求解，进入 target-owned Plan/IR，最终生成平台制品。作者不写
顶层 `kind`；目标决定物化形态，但不得改变业务语义。

## Current Checkpoint

| Field | Current value |
|---|---|
| Program | V2 独立编译管线 alpha：Lean syntax 到 target-owned Plan/IR |
| Active task | **TASK-D4-01..03**：以非 Counter 的 `Accumulator` 打通真实 `SemanticProgram → EvmPlan → Yul/ABI`；移除 EVM exact-fixture matcher |
| Next task | 用 CLI/solc/Anvil 验证 Accumulator 初始化、checked add、查询和 overflow rollback 后提交产品里程碑；H1e-b/H1e-c 暂停 |
| Phase 1 targets | `evm`, `solana`, `near`, `noir` |
| Design-only targets | `cosmwasm`, `soroban`, `icp`, `openvm`, `aleo`, `psy` |
| Known blocker | `TASK-D0-04` 尚缺 eligible host、digest-bound Stage-0 handoff、跨 `setsid()` 的 process-session containment、gate catalog/freshness/revocation/private scan 与正式 EV finalizer；当前 host 因 `Sealed: Broken` 且 Xcode pathname 可由当前 admin 用户替换而不合格；Phase 0 商业证据也未闭合 |
| Source of status | [`docs/document-status.md`](docs/document-status.md) |

检查点不是完成证据；完成必须有 `TST-*` 与 `EV-*`，并记录在实现日志中。
当前 EVM 已有 `solc` bytecode 与 Anvil Counter/overflow 验证，NEAR 有 `wat2wasm` 结构验证
但没有 sandbox receipt；Solana 只有 `.s`+IDL，Noir
只有 source+Prover input，且 manifest 为 non-deployable。不得写成 ELF/runtime 或 proof 完成。

## Mandatory Reading Order

1. 完整阅读本文件。
2. 运行 `git status --short` 并确认不会覆盖其他人的工作。
3. 阅读 [`docs/document-status.md`](docs/document-status.md) 和
   [`docs/index.md`](docs/index.md)。
4. 阅读 [`docs/01-prd.md`](docs/01-prd.md)、
   [`docs/02-architecture.md`](docs/02-architecture.md) 与
   [`docs/03-technical-spec.md`](docs/03-technical-spec.md)。
5. 阅读当前模块规格、相关 ADR、目标档案和
   [`docs/05-test-spec.md`](docs/05-test-spec.md)。
6. 实施前检查 [`docs/04-task-breakdown.md`](docs/04-task-breakdown.md)；一次只把
   一个任务置为 `in_progress`。
7. 声称完成前检查 traceability、验证证据和 review report。

## Non-Negotiable Boundaries

- 用户源码只有统一 `program Name where` 入口，不得加入用户可写顶层类别标记。
- frontend 和 `SemanticProgram` 不依据 `TargetId` 改写语义。
- `TargetId`、`CodegenProfileId`、`NetworkProfileId` 是三个独立身份。
- Wasm 只可共享 AST/编码/结构验证；NEAR、CosmWasm、Soroban、ICP 各自拥有 Plan。
- Noir、OpenVM、Aleo、Psy 分别属于电路、zkVM、ZK 应用链边界，不共用伪通用 Plan。
- 每项 capability/extension 必须精确版本并 fail closed；禁止 best effort 或隐式 fallback。
- 每个 materializer 保留关联 `Plan` 和 `TargetIR` 类型；不得擦除成 `Unit`、字符串或 JSON。
- V2 禁止依赖父项目目录、`ProofForge.*` import、父制品、旧二进制、symlink 或运行时回退。

## Execution Protocol

1. 对照代码、规格和实际工具链复核任务输入。
2. 在任务表中只标记一个 `in_progress`。
3. 先提交失败的验收测试或可执行验证脚本。
4. 实现满足规格的最小切片，遇到规格缺口先改规格并重新评审。
5. 运行聚焦测试；合并前运行完整 V2 gate。当前 `isolated-check`/
   `v2-clean-room-alpha` 会隔离 HOME/cache、限制网络并拒绝父仓库访问，Lean/external tool
   都从锁定 cache 离线物化，non-system dylib closure 已锁定；H0 会先做本地、时点性的
   development host attestation，并已接入 deny-default materialize/core/exact-local-port
   runtime stages；但 eligible host、formal Stage-0 handoff、process-session containment 与
   gate-catalog-bound formal evidence 尚未闭合，所以仍不是正式
   hermetic clean-room gate，不得混称。
6. 检查不支持的声明、父项目泄漏、非确定制品、无关变更和生成垃圾。
7. 同一变更中更新 task、traceability、evidence、implementation log 和 checkpoint。
8. 交接时给出精确文件、命令、结果、限制和下一任务。

正式 Stage-0 证据只能由调用者直接执行
`/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --require-eligible`。
`just host-stage0-*` 先经过继承环境的 recipe shell，只是开发便利入口，不能作为该信任边界。

## Documentation Protocol

- 状态只使用 `draft`、`proposed`、`in_review`、`accepted`、`superseded`、
  `archived`、`not_started`。
- 规范变更先更新 ADR/PRD/spec/test/traceability，再修改代码。
- 调研事实必须引用 `SRC-*`；设计结论必须引用 `CLM-*` 或 `ADR-*`。
- `06-implementation-log.md` 只追加已执行事实；`07-review-report.md` 不得预填通过。
- 文档变更运行 `just docs-check`（脚本落地前运行等价静态检查）和
  `git diff --check`。

## Definition of Done

任务只有在规格、测试、实现、可复现制品、目标运行/证明证据、追踪链和评审全部
闭合时才可标为 done。缺少外部工具或网络证据时必须保留较低 maturity，不得把
静态生成写成部署、执行或证明成功。
