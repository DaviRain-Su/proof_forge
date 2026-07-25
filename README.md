# ProofForge V2 (`proof-forge-next`)

[![CI](https://github.com/DaviRain-Su/proof_forge/actions/workflows/ci.yml/badge.svg)](https://github.com/DaviRain-Su/proof_forge/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/DaviRain-Su/proof_forge)](LICENSE)
[![Lean](https://img.shields.io/badge/Lean-4.31-purple)](lean-toolchain)

**One portable program source → controlled materialization for many execution platforms.**  
**一份 portable 业务程序源码 → 多个执行平台的受控物化。**

ProofForge V2 is a **Lean 4** multi-target compiler (`proof-forge-next`): authors write a
single `program … where` program; the compiler infers semantic **requirements**, then
`--target` selects materialization for **EVM, Solana, NEAR, Noir** (and later platforms).

ProofForge V2 是用 **Lean 4** 实现的多目标编译器：作者只写统一的
`program … where` 源码；编译器从源码推导语义需求（requirements），再由
`--target` 选择 **EVM / Solana / NEAR / Noir**（及后续平台）的物化方式。

- **改 target 只能改制品与物化**，不能改整数语义、状态迁移、回滚、调用顺序、
  授权或信息披露语义。
- **无法保持语义时必须拒绝**（稳定诊断），禁止 best-effort 降级或回退到旧路径。
- 编译器是 **代码生成 + 语义检查工具**，不是链上 VM、密钥托管或默认网络执行器。

仓库根目录即 V2 产品工程。旧版 ProofForge（v1）归档在 [`active/`](active/ARCHIVE.md)，
仅作研究参考，**不是**运行时依赖。

---

## 30 秒上手

```lean
import ProofForgeV2
open ProofForgeV2.Language

program Counter where
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

# 仅在明确做历史治理审计或发布预检时运行：
# just governance-check
# just release-check

# 真实 ProgramV1 CLI 路径（--module 是 canonical identity 的显式输入）：
lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean \
  --module Examples.Counter --target solana -o build/counter-solana

# 可选：显式联网 provision 一次，再离线物化锁定工具并生成 EVM bytecode。
just toolchains-provision-external
just toolchains-materialize-external "$PWD/build/dev-tool-root"
PROOF_FORGE_TOOL_ROOT="$PWD/build/dev-tool-root" \
  lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean \
    --module Examples.Counter --target evm -o build/counter-evm
```

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

### 一源四目标（Phase 1）

同一 `Counter` 语义；`--target` 只改变物化与制品编码。成熟度必须诚实标注
（runtime / plan-only / wasm / source-only）。

![One program, four targets](docs/diagrams/03-one-program-four-targets.png)

### 更多图

| 预览 | 源文件 | 说明 |
|---|---|---|
| [PNG](docs/diagrams/04-requirements-support.png) · [Excalidraw](docs/diagrams/04-requirements-support.excalidraw) | Requirements + SupportClaim 求解（fail closed） |
| [PNG](docs/diagrams/05-target-landscape.png) · [Excalidraw](docs/diagrams/05-target-landscape.excalidraw) | Phase 1 vs design-only + 成熟度阶梯 |
| [PNG](docs/diagrams/06-repo-layout.png) · [Excalidraw](docs/diagrams/06-repo-layout.excalidraw) | 根 = V2；`active/` = v1 归档 |
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

| Target | 角色 | 本阶段 | 证据状态（不得夸大） |
|---|---|---|---|
| `evm` | contract VM | Phase 1 | Counter bytecode + Anvil 初始化/increment/overflow；**非**完整 EVM 后端 |
| `solana` | explicit-account SVM | Phase 1 | typed `.sbpf-plan` + IDL；**无** sBPF object / ELF / runtime |
| `near` | Wasm host | Phase 1 | raw-u64 Counter/Accumulator WAT/Wasm + `wat2wasm`；**无** sandbox receipt |
| `noir` | circuit | Phase 1 | target-owned Plan / relation IR → `.nr` packages；**无** Nargo/ACIR/proof/VK |
| CosmWasm / Soroban / ICP / OpenVM / Aleo / Psy | — | design / research | 仅档案与路线图，**无** 产品后端宣称 |

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
├── active/                # 归档的 v1 全树（研究 only）
└── AGENTS.md              # 给 agent / 贡献者的控制面
```

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
just governance-check   # 显式审计历史 task/freeze/evidence
just release-check      # 发布预检；需要 eligible host 与锁定工具链
```

| 表面 | 命令 / 配置 | 宣称 |
|---|---|---|
| Hosted CI | `.github/workflows/ci.yml`、`.woodpecker.yml` → `just ci` | Linux portable 产品检查：docs + build/test + 负例 |
| Linux tool-root CI | `.github/workflows/ci.yml` 的 `linux-tool-root` lane | linux 资产 provision/materialize/verify 与 host profile 观察；development 级 |
| 密钥扫描 | `secret-scan` workflow | only-verified TruffleHog |
| 历史治理审计 | `just governance-check` | task/freeze/evidence 数据自洽；不证明 release |
| 发布预检 | `just release-check` | eligible-host、SBOM、clean-room 与锁定工具；只有外部正式流程才能生成 release EV |

### macOS / Linux 双开发机

ADR-0016 后工具链与 host 观察按平台拆分，两台机器都可以直接开发：

- 工具锁定按平台分文件：`toolchains.lock.json`（darwin-arm64，字节冻结）与
  `toolchains-linux-x86_64.lock.json`（linux）；`justfile` 按 `uname` 选择
  tool root、锁定 git/python 与 Stage-0 分支，consumer 对跨平台文件互相拒绝。
- `just dev-check` 与 `just ci` 在两个平台都应可运行，且不会进入 Stage-0、custody 或
  formal qualification。显式 EVM/NEAR build 可使用锁定的 per-tool development closure；
  完整 tool-root exact-set、clean-room 与 host qualification 仍只属于 `release-check`。
- 多台开发机协作时先 `git fetch && git status --short`；不要覆盖他人的未提交文件，
  也不要为维护历史 evidence 哈希而阻塞普通产品迭代。
- SBOM package-file pin 与供应链闭包归入 `release-check`。本次 ProgramV1 迁移会核对一次
  既有 pin；后续普通源码编辑不再由 SBOM ceremony 决定 development completion。
- 当前已登记开发机均不是 eligible host；因此 `release-check` 应明确拒绝，而
  `dev-check`/`ci` 仍应正常给出产品结论。不得把两者混写成同一失败。

首次物化锁定工具（本地 hermetic，非普通 `just ci`）：

```bash
just toolchains-provision-lean
just toolchains-provision-external
```

---

## 当前状态（product recovery）

CLI 的 `build` 与 `build-counter` 已直接使用
`Syntax → ValidatedSourceV1 → Typed.checkV1 → alpha Semantic → alpha target Plan/IR`；Counter 的
EVM Yul/ABI materialization 由快速产品测试固定，真实 Counter/Accumulator source 也已通过锁定
`solc` 生成 EVM bytecode。产品只要求所选工具的 exact closure；无关 `jv` 不再阻塞 EVM。
这是恢复纵切面，不表示正式 `SemanticProgramV1`、D3 resolver/`OutputSetV1` 或 D1–D4 task 已完成。
详情见 [`RECOVERY.md`](RECOVERY.md)。

- Lean command quote、`proof-forge.program-export.v1` 与旧 Loader API 仍作为历史
  `Source.Program` characterization 保留，不在 CLI 产品路径中；它们是下一轮隔离/删除对象。
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
