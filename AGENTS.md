# AGENTS.md

这是 ProofForge V2 独立工程的 agent 控制面。它只负责导航、当前产品检查点和工作协议，
不替代 PRD、架构或技术规格。当前恢复模式的详细边界见 [`RECOVERY.md`](RECOVERY.md)。

## Project Mission

构建 Lean 4 编译器 `proof-forge-next`：统一的 `program ... where` 源码经类型化、
目标中立语义和需求求解，进入 target-owned Plan/IR，最终生成平台制品。作者不写
顶层 `kind`；目标决定物化形态，但不得改变业务语义。

## Current Checkpoint

| Field | Current value |
|---|---|
| Program | V2 产品恢复桥：`ProgramV1` 子集已接通既有 alpha EVM backend |
| Product milestone | 当前工程纵切面为 `ValidatedSourceV1` → alpha Typed/Semantic → alpha EVM Plan/IR → locked `solc` bytecode |
| Product status | D1–D4 formal 仍为 0/27 done；当前 bytecode 结果不代表 `SemanticProgramV1`、正式 resolver 或 `OutputSetV1` 已完成 |
| Active task | 无（恢复工作不再创建治理型 `TASK-*` 行） |
| Next task | **TASK-D1-01**（历史 release-qualification 序列的下一行；恢复期间暂停，不是产品开发前置） |
| Known blocker | **TASK-D1-01** 的 formal TaskQualification/eligible-host 前置仍未满足；该阻塞只影响 release qualification，不阻塞产品开发 |
| Recovery authority | [`RECOVERY.md`](RECOVERY.md) |
| Task authority | [`docs/04-task-breakdown.md`](docs/04-task-breakdown.md) |
| Document authority | [`docs/document-status.md`](docs/document-status.md) |
| Phase 1 targets | `evm`, `solana`, `near`, `noir` |
| Design-only targets | `cosmwasm`, `soroban`, `icp`, `openvm`, `aleo`, `psy` |

`docs/04-task-breakdown.md` 与既有 evidence ledger 继续保存 D0/D1 release-qualification
历史，但不再生成日常产品工作的完成条件。恢复期间禁止新增 `D1-PA-*`、资格协议、
custody 服务或 formal-evidence ceremony。

成熟度声明仍必须准确：EVM 已有 `solc` bytecode 与 Anvil Counter/overflow 验证；NEAR
只有 raw-u64 Counter/Accumulator 的 `wat2wasm` 结构验证；Solana 只有不可执行的
`.sbpf-plan`+IDL；Noir 只有 target-owned Plan/typed relation IR 与 source packages。
不得把静态制品写成部署、运行或证明完成。

## Mandatory Reading Order

1. 完整阅读本文件并运行 `git status --short`，确认不会覆盖其他人的工作。
2. 阅读 [`RECOVERY.md`](RECOVERY.md)、[`docs/document-status.md`](docs/document-status.md)
   与 [`docs/index.md`](docs/index.md)。
3. 阅读 [`docs/01-prd.md`](docs/01-prd.md)、[`docs/02-architecture.md`](docs/02-architecture.md)
   与 [`docs/03-technical-spec.md`](docs/03-technical-spec.md)。
4. 只阅读当前产品切片直接相关的模块规格、ADR、目标档案与测试规格；不要因为历史
   qualification 引用而扩张工作面。
5. 修改前核对真实代码和工具链；声称完成前运行聚焦测试与普通产品 CI。

## Non-Negotiable Product Boundaries

- 用户源码只有统一 `program Name where` 入口，不得加入用户可写顶层类别标记。
- frontend 和 `SemanticProgram` 不依据 `TargetId` 改写语义。
- `TargetId`、`CodegenProfileId`、`NetworkProfileId` 是三个独立身份。
- Wasm 只可共享 AST/编码/结构验证；NEAR、CosmWasm、Soroban、ICP 各自拥有 Plan。
- Noir、OpenVM、Aleo、Psy 分别属于电路、zkVM、ZK 应用链边界，不共用伪通用 Plan。
- 每项 capability/extension 必须精确版本并 fail closed；禁止 best effort 或隐式 fallback。
- 每个 materializer 保留关联 `Plan` 和 `TargetIR` 类型；不得擦除成 `Unit`、字符串或 JSON。
- V2 禁止依赖 `active/` 归档、`ProofForge.*` import、旧制品、旧二进制、symlink 或运行时回退。
- `ProgramV1` 产品路径必须直接从 Syntax 构造并在 Typed 边界消费；禁止新增
  legacy→ProgramV1 adapter、产品 dual reader、第二套 ProgramV1 decoder 或 fallback。

## Recovery Execution Protocol

1. 一次只推进一个可运行的产品纵切面；当前唯一切面是 Counter → EVM artifact。
2. 先写聚焦失败测试，再实现满足现有规格的最小代码；不为恢复工作新增 `TASK-*`、
   `TST-*`、`EV-*`、freeze package 或 qualification object。
3. 日常反馈使用 `just dev-check`；普通合并检查使用 `just ci`。
4. `just governance-check` 只审计历史 task/freeze/evidence 数据；
   `just release-check` 才允许进入 eligible-host、SBOM、clean-room 与 formal qualification。
5. development completion 与 release qualification 分开记录。普通 CI 成功不得写成
   hermetic/formal evidence；release 主机不合格也不得反向否定已通过的产品测试。
6. 检查 unsupported 声明、`active/`/v1 泄漏、非确定制品、无关变更和生成垃圾。
7. 修改 `ProofForgeV2/**` 时运行相关 Lean 测试；SBOM package-file pin 在本次迁移中核对一次，
   后续归入 `release-check`，不再作为每次源码编辑的日常完成仪式。
8. 当前恢复工作由单一 agent 执行，不启动 subagent，也不伪造独立复审者。
9. 交接时给出精确文件、命令、结果和限制；不提交、不推送，除非用户另行要求。

正式 Stage-0 若用于真正的 release 判断，仍只能由调用者直接执行：

`/usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --require-eligible`

通过 `just release-check` 运行的同类命令只是 release preflight，不自动生成正式证据。

## Documentation Protocol

- 状态只使用 `draft`、`proposed`、`in_review`、`accepted`、`superseded`、
  `archived`、`not_started`。
- 产品行为变化同步更新相关规格或架构说明；不要批量重写历史 ledger/log/review。
- `06-implementation-log.md` 只保留已执行事实；`07-review-report.md` 不得预填通过。
- 文档变更运行 `just docs-check` 与 `git diff --check`。
- 不新增治理层来管理恢复工作；`RECOVERY.md` 是短期单一执行指针。

## Definition of Done

开发切片完成意味着：真实产品路径可运行、聚焦测试与 `just ci` 通过、文档与成熟度声明
准确、没有 fallback 或无关扩张。发布资格是独立的更高门槛，只能由显式
`just release-check` 与符合资格的外部流程判断；它不是日常产品开发的完成条件。
