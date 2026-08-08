---
id: PRODUCT-TOOLCHAIN-INSTALL-SURFACE
title: Product surface ladder — install / doctor / CLI / MCP
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP

状态：`draft`（2026-08-08）
执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）
Tool Lock 规范：[`specs/toolchains.md`](../specs/toolchains.md)（`proof-forge.toolchains.v4`）

## 0. 实现状态（诚实）

| 相位 | 状态 |
|---|---|
| **DOC**（本文 + index 指针） | **done**（本文件） |
| **I0 doctor** | **done**（`scripts/proof_forge_doctor.py` + `proof-forge-next doctor`；schema `proof-forge.doctor.v1`；缺 Tool Root → `PF-TOOLCHAIN-MISSING`） |
| **I1 install** | **done**（`scripts/proof_forge_install.py` + `proof-forge-next install`；schema `proof-forge.install.v1`；`--targets`/`--all-core` + `--yes`；delegate `toolchain_assets` provision/materialize；digest 幂等 skip；无 PATH fallback；`--dry-run` 计划-only） |
| I1b CLI wire residual | **done with I1**（CLI 薄包装 + parse 覆盖 + `scripts/install_smoke.sh`；若后续扩 usage 文案仍可叠） |
| I2 local/network 统一包装 | **not started**（现有 `scripts/aleo_*.sh` 等为工程脚本，非产品 CLI） |
| I3 Aleo snarkos runtime 诚实路径 | **not started**（snarkos **不在** Tool Lock；见 §10） |
| MCP-V0 / SDK-V0 | **not started** |
| Close | 待后续相位 |

本文是 **产品契约与实现顺序** 的权威草稿，不是已交付的 CLI/MCP 行为声明。

## 1. 产品目标

用户安装 / 使用 ProofForge 时：

1. **知道** 当前支持哪些 target（`TargetRegistryV1` 事实，非营销名单）。
2. **选择** 要开发的链，安装对应 **Tool Lock** 锁定工具到 `PROOF_FORGE_TOOL_ROOT`。
3. **诊断** 缺工具 / digest 不匹配（`doctor`），再 **build / local / network**。
4. 后续 **SDK / MCP** 只封装同一 CLI 契约，供 Code Agent 做 Web Coding。

## 2. 非目标

- 不把 install 变成「静默 PATH 扫全盘随便装」。
- 不默认 `deployable=true` 或主网广播（无产品 N3 决策不得改写 maturity）。
- 不在 ordinary `just ci` 里起 snarkOS / Anvil / Mollusk。
- 不先做大而全多语言 SDK；先 CLI + 薄封装。
- design-only target（`soroban` / `icp` / `openvm`）只展示为 `unsupported`，不提供假安装。
- 不发明 Tool Lock 外的第二工具权威或 “best effort” fallback 进 Tool Root。

## 3. 阶梯切片（workflow 相位）

| 相位 | ID | 交付 | 完成标准 |
|---|---|---|---|
| DOC | `DOC` | 本文 + `docs/index.md` 指针 | `just docs-check` 过 |
| I0 | `I0-DOCTOR` | `proof-forge-next doctor` | **done**：每 implemented target 报告 ok/missing/mismatch/partial；`--json`=`proof-forge.doctor.v1`；无 Tool Root → `PF-TOOLCHAIN-MISSING`；引擎 `scripts/proof_forge_doctor.py`；CLI 薄包装 |
| I1 | `I1-INSTALL` | 非交互 `install --targets a,b --yes` | **done**：`scripts/proof_forge_install.py`；复用 `toolchain_assets` provision/materialize；只装 lock 内 asset；digest 校验；幂等 skip；`--dry-run`/`--json`；`scripts/install_smoke.sh` |
| I1b | `I1b-CLI-WIRE` | CLI 子命令接到 Exe；`--json`；usage | **done with I1**：`proof-forge-next install` 薄包装 + parse 覆盖 |
| I2 | `I2-LOCAL-CMDS` | 统一本机/网络入口包装 | `local --target …` / `network …` 调现有 sandbox/devnet/network 脚本；broadcast 显式 |
| I3 | `I3-ALEO-RUNTIME` | Aleo runtime 安装诚实路径 | snarkos `features=test_network`：document 或 semi-auto cargo install 到约定路径；`doctor --target aleo` 识别；**不得**把缺 test_network 的 prebuilt 标 ok |
| MCP | `MCP-V0` | 最小 MCP server | tools 仅调 CLI/JSON；不重实现编译器 |
| SDK | `SDK-V0` | 可选薄 SDK（TS 或 Python 选一） | spawn CLI + parse manifest；非第二编译器 |
| Close | `Close` | AGENTS/backlog 指针 | 成熟度诚实；不声称 formal / hermetic / mainnet |

## 4. 架构约束

```text
User / Agent
    │
    ▼
proof-forge-next  (sole product CLI)
    │  doctor | install | build | check | local | network | inspect | list-targets
    ▼
scripts/toolchain_assets.py  +  Tool Lock v4
    │
    ▼
PROOF_FORGE_TOOL_ROOT/   # default: ~/.cache/proof-forge-v2/tool-root/<platform>/
    solc, sbpf, leo, nargo, dargo, wat2wasm, anvil, …  (lock-defined only)
```

### 4.1 Tool Lock 权威菜单

| File | `platform` | 备注 |
|---|---|---|
| `toolchains.lock.json` | `darwin-arm64` | Mach-O policy |
| `toolchains-linux-x86_64.lock.json` | `linux-x86_64` | ELF policy |

- Schema：`proof-forge.toolchains.v4`（见 SPEC-TOOL-001）。
- **当前无** `linux-aarch64` 等其它平台 lock；未锁平台上 install 必须 fail closed。
- 引擎：`scripts/toolchain_assets.py`（provision / materialize / verify）；产品 install 是其薄 CLI 包装，不复制第二份下载逻辑。
- **禁止** PATH fallback 把非 lock 二进制写入 `PROOF_FORGE_TOOL_ROOT`。

### 4.2 Target 菜单

- **Implemented（可 install 编译档）**：`evm`、`solana`、`near`、`noir`、`aleo`、`psy`、`quint`、`cosmwasm`、`ton`（与 `TargetRegistryV1` 九 materializer 一致）。
- **Design-only（`unsupported`，不可 install）**：`soroban`、`icp`、`openvm`。
- Accepted PRD Phase 1 文案仍为四目标；engineering 九 target 扩面不自动改写 accepted 范围（`DOC-ADR-SCOPE`）。

### 4.3 编译档 vs runtime 档

| 档 | 默认 `install` | 例 |
|---|---|---|
| **core / compile** | 是（`--targets` / `--all-core`） | `solc`、`sbpf`、`leo`、`nargo`、`dargo`、`wat2wasm`、`tolk`、`cosmwasm-check`、`jv` |
| **runtime** | 否；需 `--with-runtime` 或 `--profile runtime` | `anvil`/`cast`、`near-sandbox`；Aleo **snarkos** 见 §10（非 lock asset） |

host-heavy 门（`just solana-runtime` / `just psy-runtime` / Anvil / snarkOS）**不**并入 ordinary `just ci`。

### 4.4 Implemented target → lock tools（doctor 规划表）

| Target | core tools（Tool Lock ids） | runtime / 额外 |
|---|---|---|
| `evm` | `solc` | `anvil`、`cast`（runtime 档） |
| `solana` | `sbpf` | Mollusk 等工程 harness（非本 lock 的 install 默认面；runtime 文档另述） |
| `near` | `wat2wasm` | `near-sandbox`（runtime） |
| `noir` | `nargo` | prove/VK / barretenberg：**unresolved / FC**（见 lock `unresolved.barretenberg`） |
| `aleo` | `leo` | snarkos：**不在 lock**；I3 诚实路径（`test_network`） |
| `psy` | `dargo` | local-VM / base-proof 为 host-heavy `just psy-runtime`，非 ordinary install 默认 |
| `quint` | `jv`（模型侧辅助；Quint 产品 finalize 仍 zero-tool source） | 无 snarkOS 类 runtime |
| `cosmwasm` | `wat2wasm`、`cosmwasm-check` | wasmd Docker rung 等工程门，非 CLI 默认 install |
| `ton` | `tolk` | sandbox 工程门独立 |

表中 “core” 是 doctor/install 的 **规划映射**；某 profile 的 exact `requiredByProfiles` 仍以 lock 字段为准，不得在 doctor 里发明额外工具。

## 5. doctor 输出契约（I0）

人类：

```text
platform=linux-x86_64
tool_root=...
target=aleo status=partial
  leo: ok sha=… version=4.0.2
  snarkos: missing (need features=test_network; see docs/product/01-toolchain-install-surface.md §10)
```

JSON（MCP/Agent）：

```json
{
  "schema": "proof-forge.doctor.v1",
  "platform": "linux-x86_64",
  "toolRoot": "...",
  "targets": [
    {
      "id": "aleo",
      "status": "partial",
      "tools": [
        {"name": "leo", "status": "ok"},
        {"name": "snarkos", "status": "missing", "hint": "features=test_network; not in Tool Lock"}
      ]
    }
  ]
}
```

状态枚举：`ok` | `partial` | `missing` | `mismatch` | `unsupported`。

- 无 `PROOF_FORGE_TOOL_ROOT` 且默认 cache 不存在 → fail closed：stderr `PF-TOOLCHAIN-MISSING: tool root does not exist: …`，exit 3。
- `PROOF_FORGE_TOOL_ROOT` 非绝对路径 → `PF-TOOLCHAIN-MISMATCH`，exit 3。
- design-only id → `unsupported`，不假装可装。
- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_doctor.py`；产品 CLI：`proof-forge-next doctor`（CWD=repo root 以发现脚本）。
- 聚焦 smoke：`scripts/doctor_smoke.sh`。

## 6. install 契约（I1）

```bash
proof-forge-next install --targets aleo,solana --yes
proof-forge-next install --targets aleo --with-runtime --yes
proof-forge-next install --all-core --yes   # 所有 implemented 的 compile/core 档
```

- 无 `--yes` 且非 `--dry-run` → usage / fail closed（非交互；不提供 TTY 确认）。
- 禁止 PATH fallback 安装进 Tool Root。
- 已存在且 digest 匹配 → skip（幂等）。
- 只物化 **当前平台 lock** 中的 asset；跨平台/缺锁 fail closed。
- `--with-runtime` 仅装 lock 内 runtime 工具（`anvil`/`cast`、`near-sandbox`）；Aleo `snarkos` 仅 documented（I3）。
- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_install.py`；产品 CLI：`proof-forge-next install`（CWD=repo root）。
- 聚焦 smoke：`scripts/install_smoke.sh`（含 temp root 上 `quint`/`jv` 物化 + 幂等 skip）。
- 成功后同一进程或紧随 `doctor` 可验证 present。

## 7. 本机 / 网络包装（I2）

规划 CLI（实现后）：

```bash
proof-forge-next local --target aleo …     # → scripts/aleo_local_sandbox.sh / aleo_devnet.sh 等
proof-forge-next network --target aleo …  # → scripts/aleo_network.sh；默认不 broadcast
```

- network 工具 / 子命令必须显式 `broadcast=true`（或等价 flag）才广播。
- 不把 host-heavy 结果写成 ordinary ci 通过或 formal 证据。

## 8. MCP-V0 工具列表

| Tool | 映射 |
|---|---|
| `pf_list_targets` | `list-targets` / registry |
| `pf_doctor` | `doctor --json` |
| `pf_install` | `install --targets … --yes` |
| `pf_build` | `build` source `--module` `--target` `-o` |
| `pf_local` | `local` sandbox/runtime by target |
| `pf_artifacts` | `inspect` output-dir / list files |

全部 **不** 默认 network broadcast；若暴露 network 工具必须显式 `broadcast=true`。
MCP **只** spawn 产品 CLI 并解析 JSON/manifest，不内嵌 solc/leo/nargo。

## 9. SDK-V0

- 可选一门语言（TS 或 Python）。
- 职责：spawn `proof-forge-next`、解析 `proof-forge.output.v1` / doctor JSON。
- **非**第二编译器、非第二 Tool Root 写入器。

## 10. Aleo snarkos 诚实性（I3）

- Tool Lock **当前不含** `snarkos` / `snarkvm` asset。
- 本地 DevNet / network 路径需要 snarkos 时，须 **`features=test_network`**（crate 特性）；GitHub 常见 prebuilt zip **通常缺少**该 feature，不得标为 `ok`。
- I3 交付二选一或组合：
  1. 文档化 `cargo install snarkos --features test_network …` 到约定目录（例如 Tool Root 旁或 documented cache）；
  2. 半自动 install 脚本写入同一约定路径并由 `doctor --target aleo` 探测。
- 在 N3 产品决策前，**不得**因 snarkos 存在而把 Aleo `deployable` 改为 `true`。

## 11. 与现有脚本 / CLI 关系

| 现有 | 角色 |
|---|---|
| `scripts/toolchain_assets.py` | install 引擎（I1 复用） |
| `toolchains*.lock.json` | 唯一可装 tool 菜单 |
| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档主推 CLI |
| `proof-forge-next` 现有 | `build` / `check` / `inspect` / `list-targets` / **`doctor`** / **`install`**；**尚无** local/network |
| `scripts/aleo_local_sandbox.sh` / `aleo_devnet.sh` / `aleo_network.sh` | I2 包装对象 |
| `just solana-runtime` / `just psy-runtime` / Anvil smokes | 同左，逐步 `local --target`；保持 host-heavy |

## 12. 验证

- 每切片：聚焦测或脚本 smoke + `just docs-check`。
- 改 Lean 产品面时按 AGENTS 跑相关测 + 必要时 `just sbom-package-files-refresh`。
- 不声称 ordinary ci 已含 host-heavy runtime。
- 不声称 formal Stage-0 / hermetic / mainnet / release。

## 13. 相关文档

- Tool Lock：[`specs/toolchains.md`](../specs/toolchains.md)
- CLI 规格：[`specs/cli.md`](../specs/cli.md)
- Aleo 本地 / 网络：[`targets/09b-aleo-local-sandbox.md`](../targets/09b-aleo-local-sandbox.md)、[`targets/09c-aleo-network.md`](../targets/09c-aleo-network.md)
- 导航：[`index.md`](../index.md)
- 工作流：`.grok/workflows/product-surface-ladder.rhai`
