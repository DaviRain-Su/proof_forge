---
id: PRODUCT-TOOLCHAIN-INSTALL-SURFACE
title: Product surface ladder — install / doctor / CLI / MCP
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP

状态：`draft`（2026-08-10；I0–I2 + MCP-V0 + SDK-V0 + distribution REL-CLI/Author/CI engineering done；Aleo/Psy tool/runtime lanes removed）
执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）
Tool Lock 规范：[`specs/toolchains.md`](../specs/toolchains.md)（`proof-forge.toolchains.v4`）

## 0. 实现状态（诚实）

| 相位 | 状态 |
|---|---|
| **DOC**（本文 + index 指针） | **done**（本文件） |
| **I0 doctor** | **done**（`scripts/proof_forge_doctor.py` + `proof-forge-next doctor`；schema `proof-forge.doctor.v1`；缺 Tool Root → `PF-TOOLCHAIN-MISSING`） |
| **I1 install** | **done**（`scripts/proof_forge_install.py` + `proof-forge-next install`；schema `proof-forge.install.v1`；`--targets`/`--all-core` + `--yes`；delegate `toolchain_assets` provision/materialize；digest 幂等 skip；无 PATH fallback；`--dry-run` 计划-only） |
| I1b CLI wire residual | **done with I1**（CLI 薄包装 + parse 覆盖 + `scripts/install_smoke.sh`；若后续扩 usage 文案仍可叠） |
| I2 local/network 统一包装 | **done / narrowed**（`local` 仅保留 EVM/Solana runtime wrappers；`network` 对全部 target fail closed；`scripts/local_network_smoke.sh`） |
| **MCP-V0** | **done** (stdio) + **remote edge** `clients/pf-mcp` → https://proof-forge-mcp.davirain-yin.workers.dev/mcp（`tools/mcp/proof_forge_mcp_server.py` stdio MCP；tools: `pf_list_targets`/`pf_doctor`/`pf_install`/`pf_build`/`pf_artifacts`；仅 spawn 产品 CLI/引擎 JSON；无 network broadcast 工具；`tools/mcp/README.md` Agent 接线；`scripts/mcp_smoke.sh`） |
| **SDK-V0** | **done**（Python `tools/sdk/proof_forge_sdk.py`：`ProofForgeClient` spawn `proof-forge-next` + parse doctor/install/list-targets JSON + `load_output_manifest` for engineering `proof-forge.output.v1`；非第二编译器；`tools/sdk/README.md`；`scripts/sdk_smoke.sh`） |
| **Close** | **done**（本文 + index 成熟度诚实；剩余 backlog：交互式 install UI、全链 runtime pack、N3 前 `deployable=true` 禁改） |
| **External ProgramV1** | **done engineering**（[`02-external-program-v1.md`](02-external-program-v1.md) + `templates/external-aleo-hello/` + sandbox/SDK/MCP `--root` + `just external-hello-smoke`；非 Lake SDK / formal） |
| **Hello agent playbook** | **done engineering**（[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)；MCP 顺序 doctor→install→build/local→artifacts） |
| **Chain client catalog** | **done engineering**（[`04-chain-client-catalog.md`](04-chain-client-catalog.md) + `chain-client-catalog.v1.json` + `pf_chain_catalog` / SDK `chain_catalog`；元数据 only） |
| **Distribution / packages** | **engineering-dist + PyPI wiring done**（[`05-distribution-and-packages.md`](05-distribution-and-packages.md) / [`06-pypi-host-sdk.md`](06-pypi-host-sdk.md)：CLI multi-arch、Author SDK、Host wheel+OIDC PyPI job；Trusted Publisher 需一次人工配置；formal Stage-0 仍 pending） |

本文是 **产品契约与实现顺序** 的权威草稿；I0–I2、MCP-V0、SDK-V0 与 distribution engineering dist 已接线。Aleo/Psy 仅保留 zero-tool direct materializer；不再提供 Leo/Dargo/snarkOS/local VM/network 产品或工程 lane。不声称 formal / hermetic / mainnet / Stage-0。

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
| I2 | `I2-LOCAL-CMDS` | 统一本机入口包装 | **done / narrowed**：`local --target evm|solana` 调现有 runtime 脚本；`network` 全 target fail closed；`scripts/local_network_smoke.sh` |
| MCP | `MCP-V0` | 最小 MCP server | **done**：`tools/mcp/proof_forge_mcp_server.py`；tools 含 `pf_local`（仅 EVM/Solana）+ build/doctor；拒 network broadcast；见 §8 |
| SDK | `SDK-V0` | 可选薄 SDK（TS 或 Python 选一） | **done**（Python）：`tools/sdk/proof_forge_sdk.py`；spawn CLI + `local` 通用 API + parse manifest；非第二编译器；见 §9 |
| Close | `Close` | AGENTS/backlog 指针 | **done**：成熟度诚实；不声称 formal / hermetic / mainnet；剩余见 §0 Close 行 |

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
    solc, sbpf, nargo, wat2wasm, anvil, …  (lock-defined only)
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
- Accepted PRD Phase 1 文案仍为四目标；engineering 九 target 扩面不自动改写 accepted 范围（ADR-0036）。

### 4.3 编译档 vs runtime 档

| 档 | 默认 `install` | 例 |
|---|---|---|
| **core / compile** | 是（`--targets` / `--all-core`） | `solc`、`sbpf`、`nargo`、`wat2wasm`、`tolk`、`cosmwasm-check`、`jv` |
| **runtime** | 否；需 `--with-runtime` 或 `--profile runtime` | lock：`anvil`/`cast`、`near-sandbox` |

host-heavy 门（`just solana-runtime` / Anvil）**不**并入 ordinary `just ci`。

### 4.4 Implemented target → lock tools（doctor 规划表）

| Target | core tools（Tool Lock ids） | runtime / 额外 |
|---|---|---|
| `evm` | `solc` | `anvil`、`cast`（runtime 档） |
| `solana` | `sbpf` | Mollusk 等工程 harness（非本 lock 的 install 默认面；runtime 文档另述） |
| `near` | `wat2wasm` | `near-sandbox`（runtime） |
| `noir` | `nargo` | prove/VK / barretenberg：**unresolved / FC**（见 lock `unresolved.barretenberg`） |
| `aleo` | —（sole `aleo-instructions-v1` zero-tool） | 无 compiler/runtime/network lane |
| `psy` | —（sole `psy-dpn-v1` zero-tool） | 无 compiler/runtime/network lane |
| `quint` | `jv`（模型侧辅助；Quint 产品 finalize 仍 zero-tool source） | 无 snarkOS 类 runtime |
| `cosmwasm` | `wat2wasm`、`cosmwasm-check` | wasmd Docker rung 等工程门，非 CLI 默认 install |
| `ton` | `tolk` | sandbox 工程门独立 |

表中 “core” 是 doctor/install 的 **规划映射**；某 profile 的 exact `requiredByProfiles` 仍以 lock 字段为准，不得在 doctor 里发明额外工具。

## 5. doctor 输出契约（I0）

对 zero-tool direct target，doctor 必须明确报告空工具集合，而不是要求已删除的编译器：

```text
platform=linux-x86_64
tool_root=...
target=aleo status=ok
```

```json
{
  "schema": "proof-forge.doctor.v1",
  "platform": "linux-x86_64",
  "toolRoot": "...",
  "targets": [
    {"id": "aleo", "status": "ok", "tools": []},
    {"id": "psy", "status": "ok", "tools": []}
  ]
}
```

状态枚举：`ok` | `partial` | `missing` | `mismatch` | `unsupported`。

- 无 `PROOF_FORGE_TOOL_ROOT` 且默认 cache 不存在 → fail closed：stderr `PF-TOOLCHAIN-MISSING: tool root does not exist: …`，exit 3。
- `PROOF_FORGE_TOOL_ROOT` 非绝对路径 → `PF-TOOLCHAIN-MISMATCH`，exit 3。
- 对所有非 zero-tool target，Tool Root 采用 **current-lock exact-set closure**：允许只物化所选 target 的 lock 子集，但任何不属于当前全局 Tool Lock 的文件、目录、symlink 或 special node 都使 target 为 `mismatch`，并给出 `install --all-core --yes` 修复提示。这样已退役工具不会再出现 doctor 绿、构建门禁红。
- design-only id → `unsupported`，不假装可装。
- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_doctor.py`；产品 CLI：`proof-forge-next doctor` 通过 `PackageRootV1` 解析 package root（`PROOF_FORGE_ROOT` 绝对路径 → `IO.appDir` 父目录含 `scripts/` → CWD），并以 `cwd=packageRoot` spawn。
- 聚焦 smoke：`scripts/doctor_smoke.sh`。

## 6. install 契约（I1）

```bash
proof-forge-next install --targets solana --yes
proof-forge-next install --all-core --yes   # 所有 implemented target 的非空 compile/core 档
```

- 无 `--yes` 且非 `--dry-run` → usage / fail closed（非交互；不提供 TTY 确认）。
- 禁止 PATH fallback 安装进 Tool Root。
- 已存在且 digest 匹配 → skip（幂等）。
- 只物化 **当前平台 lock** 中的 asset；跨平台/缺锁 fail closed。
- 每次 install（包括 zero-tool target）都会扫描 Tool Root：保留当前 lock 中尚未选装的合法成员，清除不再属于当前 lock 的退役节点；`--dry-run` 只在 `notes` 报告 `would remove`，不落盘。
- `--with-runtime` 仅物化 lock 内 runtime 工具（`anvil`/`cast`、`near-sandbox`）；Aleo/Psy 没有 runtime 配方或外部工具 fallback。
- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_install.py`；产品 CLI：`proof-forge-next install` 同样经 `PackageRootV1` 定位 package root并以 `cwd=packageRoot` spawn。
- 聚焦 smoke：`scripts/install_smoke.sh`（含 temp root 上 `quint`/`jv` 物化 + 幂等 skip + Aleo/Psy zero-tool + 退役 `leo` dry-run/清理断言）。
- 成功后同一进程或紧随 `doctor` 可验证 present。

## 7. 本机包装（I2）

**已实现并收窄**。`local` 只保留 EVM/Solana 已有 runtime wrapper；Aleo/Psy 及其它 target
fail closed。已删除无实现 target 的 `network` 子命令：

```bash
proof-forge-next local --target solana [--mode runtime] [--json] [--] [script-args...]
proof-forge-next local --target evm [--mode runtime] [--json] [--] [script-args...]
```

| Target | `local` 模式（默认） | 包装脚本 | 等价工程入口 |
|---|---|---|---|
| `solana` | `runtime`（默认） | `scripts/solana_runtime_test.sh` | `just solana-runtime` |
| `evm` | `runtime`（默认） | `scripts/evm_anvil_differential.sh` | Anvil engineering smokes |
| 其它 implemented | — | fail closed（无产品 script path） | 见 target dossier |
| design-only | — | fail closed `unsupported` | 不可 install/local |

- local wrapper 经 `PackageRootV1` 定位 package root，以 `cwd=packageRoot` 固定执行 `/bin/bash -p`，
  并设置 `PROOF_FORGE_ROOT=packageRoot`；禁止 PATH/BASH_ENV fallback。
- 顶层 `network` 子命令已删除，作为未知命令以 usage / exit 2 拒绝；build 的 `--network`
  flag 同样为 usage error，因为尚无 network registry。
- schema 仅为 `proof-forge.local.v1`；不得在 JSON 中暴露秘密。
- 聚焦门：`scripts/local_network_smoke.sh`。实际 runtime 仍 host-heavy，不并入 ordinary CI 或 formal evidence。

## 8. MCP-V0 工具列表 — **done**

实现：`tools/mcp/proof_forge_mcp_server.py`（stdlib-only stdio JSON-RPC MCP；newline 分隔；stderr 日志）。
接线说明：`tools/mcp/README.md`。聚焦 smoke：`scripts/mcp_smoke.sh`。

| Tool | 映射 |
|---|---|
| `pf_list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |
| `pf_doctor` | `doctor --json` → `proof-forge.doctor.v1` |
| `pf_install` | `install --targets … --yes`（或 `--dry-run`）`--json` → `proof-forge.install.v1` |
| `pf_build` | `build` source `--module` `--target` `-o` `--json`（**拒** broadcast/network 参数） |
| `pf_artifacts` | `inspect --output-dir <dir> --json` 或 `inspect <target> --json` |
| `pf_local` | `local --target … [--mode sandbox]` + 透传 script args；Aleo sandbox **通用** 须 `source`+`module`（可选 `root`/`runs`/`golden`/`skipRun`；有 `root` 时传为 product `--root`）；**拒** broadcast / private-key |
| `pf_chain_catalog` | 静态 `docs/product/chain-client-catalog.v1.json`（前后端分工元数据；不装前端包、不 broadcast） |

V0+ 已暴露 `pf_local` 与 `pf_chain_catalog`；**仍不**暴露 network broadcast 工具（network 必须显式 `network --broadcast`，不经 MCP 默认面）。Hello 剧本见 [`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)。
返回包装 schema：`proof-forge.mcp.tool-result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`）。
Env：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（继承 doctor/install/build 契约）。
MCP **只** spawn 产品 CLI 并解析 JSON/manifest，不内嵌 solc/leo/nargo；不 PATH fallback 写 Tool Root；不改 `deployable`。

## 9. SDK-V0 — **done**（Python）

实现：`tools/sdk/proof_forge_sdk.py`（stdlib-only；可选 `PYTHONPATH=tools/sdk`）。
接线说明：`tools/sdk/README.md`。聚焦 smoke：`scripts/sdk_smoke.sh`。

| API | 映射 |
|---|---|
| `ProofForgeClient.list_targets` | `list-targets [--all] --json` → `proof-forge.cli.list-targets.v1` |
| `ProofForgeClient.doctor` | `doctor --json` → `proof-forge.doctor.v1`（exit 3 + body 仍 `ok` 给 Agent） |
| `ProofForgeClient.install` | `install --yes`/`--dry-run --json` → `proof-forge.install.v1` |
| `ProofForgeClient.build` / `check` | 产品 `build`/`check --json`；**拒** design-only target；**无** network/broadcast |
| `ProofForgeClient.inspect_artifacts` / `inspect_target` | `inspect --output-dir` / `inspect <target> --json` |
| `ProofForgeClient.local` | `local --target …`；Aleo sandbox 透传 `--source`/`--module`/`--root`/`--run`（通用；有 `root=` 时传为 product `--root`；拒 broadcast/signer） |
| `ProofForgeClient.chain_catalog` | 静态 chain client catalog（`proof-forge.chain-client-catalog.v1`） |
| `load_output_manifest` / `client.load_output_manifest` | 读 on-disk `manifest.json` 的 engineering `schemaVersion=proof-forge.output.v1`（**不**重走 exact disk closure；closure 用 `inspect_artifacts`） |

- 返回载体 schema：`proof-forge.sdk.result.v1`（`ok`/`exitCode`/`command`/`stdout`/`stderr`/`parsed`/`error`/`productOk`）。
- Env：`PROOF_FORGE_ROOT` / `PROOF_FORGE_CLI` / `PROOF_FORGE_TOOL_ROOT`（与 MCP/CLI 相同契约）。
- **非**第二编译器、**非**第二 Tool Root 写入器、**无** PATH fallback 物化 lock tools、**不**改 `deployable`。
- 未做：TS SDK、交互式 install UI、全链 runtime pack 一键装、pip 发布。

## 11. 与现有脚本 / CLI 关系

| 现有 | 角色 |
|---|---|
| `scripts/toolchain_assets.py` | install 引擎（I1 复用） |
| `toolchains*.lock.json` | 唯一可装 tool 菜单 |
| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档主推 CLI |
| `proof-forge-next` 现有 | `build` / `check` / `inspect` / `list-targets` / **`doctor`** / **`install`** / **`local`** / **`network`** |
| `tools/mcp/proof_forge_mcp_server.py` | MCP-V0 stdio 薄封装（仅 spawn 上列 CLI JSON） |
| `tools/sdk/proof_forge_sdk.py` | SDK-V0 Python 薄客户端（spawn CLI + parse JSON/manifest） |
| `scripts/solana_runtime_test.sh` / `scripts/evm_anvil_differential.sh` | I2 `local --target solana|evm`；`just solana-runtime` / Anvil 工程 lane 仍可用 |

## 12. 验证

- 每切片：聚焦测或脚本 smoke + `just docs-check`。
- 改 Lean 产品面时按 AGENTS 跑相关测 + 必要时 `just sbom-package-files-refresh`。
- 不声称 ordinary ci 已含 host-heavy runtime。
- 不声称 formal Stage-0 / hermetic / mainnet / release。

## 13. 相关文档

- Tool Lock：[`specs/toolchains.md`](../specs/toolchains.md)
- CLI 规格：[`specs/cli.md`](../specs/cli.md)
- 导航：[`index.md`](../index.md)
- 工作流：`.grok/workflows/product-surface-ladder.rhai`
