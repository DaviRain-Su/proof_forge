# ProofForge V2 (`proof-forge-next`)

[![CI](https://github.com/DaviRain-Su/proof_forge/actions/workflows/ci.yml/badge.svg)](https://github.com/DaviRain-Su/proof_forge/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/DaviRain-Su/proof_forge)](LICENSE)
[![Lean](https://img.shields.io/badge/Lean-4.31-purple)](lean-toolchain)

**One portable program source → controlled materialization for many execution platforms.**  
**一份 portable 业务程序源码 → 多个执行平台的受控物化。**

ProofForge V2 is a **Lean 4** multi-target compiler (`proof-forge-next`): authors write a
single `program … where` program; the compiler infers semantic **requirements**, then
`--target` selects materialization. Engineering registry is **12 = 9 implemented + 3
design-only**; nine targets own Plan/IR/materializer leaves today (EVM, Solana, NEAR,
Noir, Aleo, Psy, Quint, CosmWasm, TON). Quint is a non-deployable, source-only
executable-model target; product finalization does not run Quint or Apalache.

ProofForge V2 是用 **Lean 4** 实现的多目标编译器：作者只写统一的
`program … where` 源码；编译器从源码推导语义需求（requirements），再由
`--target` 选择物化方式。工程 registry **12 = 9 implemented + 3 design-only**；当前
九个 target 各有 target-owned Plan/IR/materializer（EVM / Solana / NEAR / Noir / Aleo /
Psy / Quint / CosmWasm / TON）。Quint 是不可部署的 source-only 可执行模型 target；产品
finalization 不运行 Quint 或 Apalache。

- **改 target 只能改制品与物化**，不能改整数语义、状态迁移、回滚、调用顺序、
  授权或信息披露语义。
- **无法保持语义时必须拒绝**（稳定诊断），禁止 best-effort 降级或回退到旧路径。
- 编译器是 **代码生成 + 语义检查工具**，不是链上 VM、密钥托管或默认网络执行器。

仓库根目录即 V2 产品工程。仅包含 V2 源码、测试与门禁；不存在任何 v1 归档、
fallback、镜像或运行时回退依赖。

---

## 30 秒上手

```lean
import ProofForgeV2
open ProofForgeV2.Language

program StateCell where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count
```

```bash
# 安装 Lean（见 lean-toolchain）后：
just dev-check   # 快速文档检查、构建与核心产品测试
just ci          # 普通开发机 / GitHub CI 的完整产品门禁

# 历史控制面名称（当前 justfile 未注册，不能执行或声称通过）：
# just governance-check
# just release-check

# 真实 ProgramV1 CLI 路径（--module 是 canonical identity 的显式输入）：
lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean \
  --module Examples.StateCell --target solana -o build/state-cell-solana

# Quint Q0 是 zero-tool、不可部署的 executable-model source target：
lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean \
  --module Examples.StateCell --target quint -o build/state-cell-quint
lake env .lake/build/bin/proof-forge-next inspect build/state-cell-quint --json

# 可选：显式联网 provision 一次，再离线物化锁定工具并生成 EVM bytecode。
just toolchains-provision-external
just toolchains-materialize-external "$PWD/build/dev-tool-root"
PROOF_FORGE_TOOL_ROOT="$PWD/build/dev-tool-root" \
  lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean \
    --module Examples.StateCell --target evm -o build/state-cell-evm
```

### 通用 Solana client 与 TransferSol 本地真实调用

[`clients/solana-client`](clients/solana-client) 提供通用的离线
`proof-forge-solana-client`：它先验证 `proof-forge.output.v1` 闭包，再按已知 Solana profile
fail-closed 分派；默认路径不硬编码程序名、source hash 或 Transfer ABI。程序级约束由显式
`--program-adapter` 加载，因此后续 Solana program 可以增加自己的 adapter，而不需要复制 CLI。

[`Examples/TransferSol.lean`](Examples/TransferSol.lean) 是首个 adapter/runtime fixture：它使用显式
Solana CPI extension 调用原生 System Program，Mollusk 在本地加载 manifest-bound ELF 并执行
真实 native System CPI。

```bash
# 运行通用 client 的离线测试与严格 Clippy。
just solana-client-test

# 只构建 TransferSol 产品树。
just solana-transfer-sol-build

# 构建并运行通用 profile 校验 + 显式 TransferSol ABI adapter。
just solana-transfer-sol-offline

# 构建、校验并运行 8 个聚焦测试（其中 6 个加载执行产品 ELF）。
just solana-transfer-sol-local
```

这些入口不访问 RPC，不请求测试币，不读取钱包/keypair，也不部署到 Devnet。部署若有需要由
operator 在自己的本地 validator 与工具链中完成；ProofForge 此处只物化、校验并本地执行产品
ELF。该结果是 engineering self-consistency/runtime observation，不是 signed provenance、mainnet、
formal 或 hermetic 证据。完整边界见
[`clients/solana-client/README.md`](clients/solana-client/README.md)。

源码 **不** 声明 “合约 / 电路 / zkVM workload” 类别；类别由 `--target` 的物化决定，
且不得偷偷改业务语义。

---

## 架构一览

权威文字规格：[`docs/02-architecture.md`](docs/02-architecture.md)。  
图源（Excalidraw + PNG）在 [`docs/diagrams/`](docs/diagrams/README.md)。

### 系统总览

一份 portable `program` 源码，经 target-neutral 语义与 exact support 求解后，进入
**目标自有** Plan/IR 与制品；外部 packager / runtime / 网络在编译器边界之外。

![Architecture overview](docs/diagrams/01-architecture-overview.png)

### 编译管线

`Syntax` 只是入口树，不是领域语义：Parse → Preflight → Decode → Typed → Semantic →
Resolve → Materialize。失败 **fail closed**，禁止降级或 legacy fallback。

![Compilation pipeline](docs/diagrams/02-compilation-pipeline.png)

### 一源多目标（accepted Phase 1 vs engineering registry）

同一 `StateCell` 语义；`--target` 只改变物化与制品编码。

- **Accepted PRD Phase 1 范围（四目标）**：EVM / Solana / NEAR / Noir。工程 registry
  扩大到 Aleo / Psy / Quint / CosmWasm / TON 的 reconciliation 仍由 **`DOC-ADR-SCOPE`** 跟踪，
  **不得**把后五者静默读成 accepted Phase 1 范围扩张。
- **Engineering registry（代码事实）**：**12 = 9 implemented + 3 design-only**。九个
  materializer：EVM、Solana、NEAR、Noir、Aleo、Psy、Quint、CosmWasm、TON；design-only：
  Soroban、ICP、OpenVM。Quint 只产 `.qnt` 且 zero-tool finalize；CosmWasm 工程面为 WAT +
  locked `wat2wasm` + `cosmwasm-check` + cosmwasm-vm mock；TON 工程面为 Tolk + real BoC +
  `@ton/sandbox`。

下图是早期四目标架构示意；当前事实以本页诚实表与
[`docs/targets/README.md`](docs/targets/README.md) 为准。

![Original four-target architecture illustration](docs/diagrams/03-one-program-four-targets.png)

### 更多图

| 预览 | 源文件 | 说明 |
|---|---|---|
| [PNG](docs/diagrams/04-requirements-support.png) · [Excalidraw](docs/diagrams/04-requirements-support.excalidraw) | Requirements + SupportClaim 求解（fail closed） |
| [PNG](docs/diagrams/05-target-landscape.png) · [Excalidraw](docs/diagrams/05-target-landscape.excalidraw) | Phase 1 vs design-only + 成熟度阶梯 |
| [PNG](docs/diagrams/06-repo-layout.png) · [Excalidraw](docs/diagrams/06-repo-layout.excalidraw) | 历史布局图；当前根 = V2，v1 `active/` 仅存于 Git 历史 |
| [PNG](docs/diagrams/07-module-boundaries.png) · [Excalidraw](docs/diagrams/07-module-boundaries.excalidraw) | 模块边界与禁止依赖 |

编辑白板：打开 [excalidraw.com](https://excalidraw.com) → Open 对应 `.excalidraw` →
导出 PNG 覆盖同名 `0N-*.png`。重新生成 JSON（会覆盖未备份手改）：

```bash
python3 scripts/generate-excalidraw-diagrams.py
```

### 编译数据流（文字）

```text
Author / CI
    │  Lean source + explicit --target / profiles
    ▼
proof-forge-next
    ├─ Lean Parser + portable decoder (+ Syntax preflight)
    │     → Source.ProgramV1 → ValidatedSourceV1
    ├─ name / type / effect check
    │     → Typed.Program
    ├─ target-neutral normalization
    │     → Semantic.Program + ProgramRequirements
    ├─ Support resolver (exact SupportClaim, fail closed)
    │     → ResolvedProgram target
    ├─ target Materializer
    │     → target Plan → TargetIR
    └─ emitter
          → OutputSet + provenance (atomic write)
                │
                ├─ official packager / validator / local runtime
                └─ deploy / prove / verify   ← 仅显式命令，不隐式联网
```

前端直接使用 Lean 4 的 `Syntax`，但 **不把 Lean AST 当作领域语义**。CLI 只解析允许的
portable command，不 elaboration / 执行用户文件中的任意 Lean command。

关键不变量（摘要）：

| ID | 含义 |
|---|---|
| INV-001 | Source / Typed / Semantic 层不按 `TargetId` 分支 |
| INV-002 | target 只能做等价物化；否则拒绝 |
| INV-005 | 任一失败不得变成“成功”或 legacy fallback |
| INV-008 | build 无网络与密钥副作用；deploy/prove/verify 显式 |
| INV-010 | clean-room 不依赖 `active/` 或旧 v1 路径 |

---

## 目标与成熟度（诚实表）

> **双轨**：表中「本阶段」区分 **accepted PRD Phase 1 四目标**（EVM/Solana/NEAR/Noir）与
> **engineering implemented leaves**（Aleo/Psy/Quint/CosmWasm/TON；scope ADR 仍 open，见
> `DOC-ADR-SCOPE`）。后五行 **不是** accepted Phase 1 范围扩张。

| Target | 角色 | 本阶段 | 证据状态（不得夸大） |
|---|---|---|---|
| `evm` | contract VM | accepted Phase 1 | retained-Semantic Plan/IR → Yul + locked `solc` bytecode；G4 Anvil 工程差分；**非** formal Reference↔Anvil / D4 完成 |
| `solana` | explicit-account SVM | accepted Phase 1 | target-owned Plan/IR → SBPF asm + locked assembler ELF `.so`；Mollusk 工程差分；**非** formal Stage-0/hermetic |
| `near` | Wasm host | accepted Phase 1 | WAT/Wasm + locked `wat2wasm` / host-optional runtime load；near-sandbox StateCell overflow/state-hold、aggregate return 与 Option state 工程 corpus；**非** formal Reference↔sandbox / D6 完成 |
| `noir` | circuit | accepted Phase 1 | target-owned Plan/relation IR → `.nr` packages + locked nargo compile-only；**无** ACIR/witness/proof/VK/verify |
| `aleo` | ZK application chain | engineering implemented (scope ADR open) | sole `aleo-instructions-v1`：target-owned Plan → canonical Aleo Instructions `.aleo` + query descriptor；zero-tool、non-deployable；**无** VM/prove/deploy/network query |
| `psy` | ZK application chain | engineering implemented (scope ADR open) | sole `psy-dpn-v1`：target-owned Plan → canonical DPN `.dpn.json`；zero-tool、non-deployable；**无** DPN execution/local VM/proof/UPS/network/deploy |
| `quint` | executable specification / model | engineering implemented (scope ADR open) | target-owned Q0 Plan/structured IR → `.qnt`；zero-tool finalize、`deployable=false`；host Quint 0.32 仅 optional observation，**非** Tool Lock / ITF / MBT / verify / formal |
| `cosmwasm` | Wasm host | engineering implemented (scope ADR open) | Plan/IR→WAT；UInt8/16/32、named state、bounded aggregate/Array/Option return；Binary SubMsg PARTIAL；locked check + mock 28 tests + wasmd Docker rung-1；label=`wasm-validated-alpha`；**非** 主网/formal |
| `ton` | TVM stack-account | engineering implemented (scope ADR open) | Plan/IR→Tolk + real BoC；UInt8/16/32、named/container state、bounded view returns；schedule `createMessage` PARTIAL；sandbox 10/10；label=`source-only`；**非** 主网/formal |
| Soroban / ICP / OpenVM | — | design only | 仅档案与路线图，**无** 产品 backend（design-only 3） |

详情：[`docs/targets/README.md`](docs/targets/README.md)。

---

## 仓库结构

```text
.
├── ProofForgeV2/          # 编译器（Core · Language · Targets · CLI）
├── Examples/              # 可编译示例程序
├── Tests/                 # 单元 / 物化测试
├── docs/                  # PRD · 架构 · 规格 · ADR · diagrams
├── scripts/               # CI · clean-room · toolchain · 文档检查
├── justfile               # 本地与 CI 门禁入口
└── AGENTS.md              # 给 agent / 贡献者的控制面
```

历史 v1 `active/` 已从工作树删除；如本次 Quint 恢复一样，只能从 Git 对象做研究，
不得作为 V2 import、adapter 或 runtime fallback。

---

## 文档从哪读

| 想了解 | 打开 |
|---|---|
| 生命周期与权威索引 | [`docs/document-status.md`](docs/document-status.md) |
| 文档导航 | [`docs/index.md`](docs/index.md) |
| 产品需求 | [`docs/01-prd.md`](docs/01-prd.md) |
| 系统架构 | [`docs/02-architecture.md`](docs/02-architecture.md) |
| 当前产品恢复 | [`RECOVERY.md`](RECOVERY.md) |
| 历史 release 任务与验收 | [`docs/04-task-breakdown.md`](docs/04-task-breakdown.md) |
| 实现事实日志 | [`docs/06-implementation-log.md`](docs/06-implementation-log.md) |
| Agent 工作协议 | [`AGENTS.md`](AGENTS.md) |

**权威顺序：** 已接受 ADR/PRD/架构/规格 → 当前代码、制品与可复现产品测试 →
显式 release qualification。调研材料是证据输入，不会自动变成规范。

---

## 开发与 CI

```bash
just docs-check         # 快速文档与链接/状态检查
just test-fast          # 核心产品 smoke tests
just dev-check          # 日常：docs-check + build + test-fast
just test               # 全量 proof-forge-next-tests
just ci                 # 普通主机的完整产品门禁
# governance-check / release-check 当前未注册；恢复前不得声称运行或通过
```

| 表面 | 命令 / 配置 | 宣称 |
|---|---|---|
| Hosted CI | `.github/workflows/ci.yml`、`.woodpecker.yml` → `just ci` | Linux portable core/build/test/selection 检查，并断言 Darwin-only product frontend 在 Linux fail closed；不声称 Linux 产品 build 成功 |
| Linux tool-root CI | `.github/workflows/ci.yml` 的 `linux-tool-root` lane | linux 资产 provision/materialize/verify 与 host profile 观察；development 级 |
| 密钥扫描 | `secret-scan` workflow | only-verified TruffleHog |
| 历史治理审计 | 当前无 `governance-check` recipe | 仅保留历史数据；恢复命令前不可声称已审计 |
| 发布预检 | 当前无 `release-check` recipe | 正式判断只能由直接 eligible-host Stage-0 与外部流程完成；恢复 wrapper 前不可声称已预检 |

### macOS / Linux 双开发机

ADR-0016 后工具链与 host 观察按平台拆分，两台机器都可以直接开发：

- 工具锁定按平台分文件：`toolchains.lock.json`（darwin-arm64，字节冻结）与
  `toolchains-linux-x86_64.lock.json`（linux）；`justfile` 按 `uname` 选择
  tool root、锁定 git/python 与 Stage-0 分支，consumer 对跨平台文件互相拒绝。
- `just dev-check` 与 `just ci` 在两个平台都应可运行，且不会进入 Stage-0、custody 或
  formal qualification。2026-08-01 起 B11/B12 frontend supervisor 已删除；macOS/Linux 产品
  source 路径均为进程内单次 `IO.FS.readFile` → `Loader.selectProgramV1ProductWithTheoremInventory` → compile → `certifyInlineProofV1`。这不提供 safe-open、
  receipt 或 contained assurance。
- 显式 EVM/NEAR build 可使用锁定的 per-tool development closure；完整 tool-root exact-set、
  clean-room 与 host qualification 只属于独立 release 流程。当前无 `release-check` recipe。
- 多台开发机协作时先 `git fetch && git status --short`；不要覆盖他人的未提交文件，
  也不要为维护历史 evidence 哈希而阻塞普通产品迭代。
- SBOM package-file pin 与供应链闭包属于独立 release 轴。本次 ProgramV1 迁移会核对一次
  既有 pin；后续普通源码编辑不再由 SBOM ceremony 决定 development completion。
- 当前已登记开发机均不是 eligible host；直接 Stage-0 应明确拒绝，而 `dev-check`/`ci`
  仍应正常给出产品结论。不得把两者混写成同一失败。

首次物化锁定工具（本地 hermetic，非普通 `just ci`）：

```bash
just toolchains-provision-lean
just toolchains-provision-external
```

---

## 当前状态（product recovery）

macOS 与 Linux 的产品 CLI 都经进程内单次 `IO.FS.readFile` →
`Loader.selectProgramV1ProductWithTheoremInventory` → located `NormalizeV1` structure gate →
`CompiledSemanticV1` → inline proof certification → requirement capability → target-owned
Plan/IR/materialization。产品路径没有 embedded example fallback，也不持有 alpha residual。
`StateCell` 与 `Accumulator` 的 EVM Yul/ABI 物化由产品测试固定，并可通过锁定 `solc`
生成 bytecode。这是工程恢复纵切面，不表示 formal D1–D4、完整 SupportClaim 或 release
qualification 已完成。迁移顺序、27 项要求与删除门槛见
[`MIGRATION_MATRIX.md`](MIGRATION_MATRIX.md)；执行边界见 [`RECOVERY.md`](RECOVERY.md)。

- Lean command/export 已切到 `proof-forge.program-export.v2` + canonical ProgramV1；legacy
  `Source.Program` decoder、v1 payload 与旧 Loader source-reading API 已删除。库内仍保留
  `parseProgramsV1`/`selectProgramV1` 非产品测试面；产品 CLI 只消费同一次 Loader snapshot 产出的 validated source、origin 与 theorem inventory。
- TaskQualification/custody/formal-evidence 扩张已暂停，不再作为开发完成条件。
- Clean-room 与 eligible-host 只属于显式 release qualification。
- 写 maturity 时以真实代码、制品与对应产品测试为准，不能用治理对象数量代替产品进度。

---

## 社区与发现（GitHub）

| 项 | 位置 |
|---|---|
| 问题 / 讨论 | GitHub Issues |
| 贡献指南 | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| 安全报告 | [`SECURITY.md`](SECURITY.md) |
| 架构图 | [`docs/diagrams/`](docs/diagrams/) |
| Agent 协议 | [`AGENTS.md`](AGENTS.md) |

仓库 **About** 描述、Topics、Website 由 maintainer 在 GitHub 设置；Social preview
建议使用 `docs/diagrams/01-architecture-overview.png`（Settings → General → Social preview）。

## 许可

Apache-2.0 — 见根目录 [`LICENSE`](LICENSE)。
