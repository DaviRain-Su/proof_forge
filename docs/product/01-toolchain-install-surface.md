---
id: PRODUCT-TOOLCHAIN-INSTALL-SURFACE
title: Product surface ladder — install / doctor / CLI / MCP
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP

状态：`draft`（2026-08-09；I0–I3 + MCP-V0 + SDK-V0 done；Close residual backlog）
执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）
Tool Lock 规范：[`specs/toolchains.md`](../specs/toolchains.md)（`proof-forge.toolchains.v4`）

## 0. 实现状态（诚实）

| 相位 | 状态 |
|---|---|
| **DOC**（本文 + index 指针） | **done**（本文件） |
| **I0 doctor** | **done**（`scripts/proof_forge_doctor.py` + `proof-forge-next doctor`；schema `proof-forge.doctor.v1`；缺 Tool Root → `PF-TOOLCHAIN-MISSING`） |
| **I1 install** | **done**（`scripts/proof_forge_install.py` + `proof-forge-next install`；schema `proof-forge.install.v1`；`--targets`/`--all-core` + `--yes`；delegate `toolchain_assets` provision/materialize；digest 幂等 skip；无 PATH fallback；`--dry-run` 计划-only） |
| I1b CLI wire residual | **done with I1**（CLI 薄包装 + parse 覆盖 + `scripts/install_smoke.sh`；若后续扩 usage 文案仍可叠） |
| I2 local/network 统一包装 | **done**（`proof-forge-next local` / `network` 薄包装；固定 `/bin/bash -p`；signer argv/env pre-spawn rejection + human/JSON defense-in-depth redaction；Aleo network 只消费 private-inspected OutputSet/tool snapshots并发布独立 receipt；`scripts/local_network_smoke.sh`） |
| **I3 Aleo snarkos runtime 诚实路径** | **done**（`scripts/proof_forge_aleo_snarkos.py`；doctor 经 `PROOF_FORGE_ALEO_SNARKOS` / 约定 cargo-install 路径探测 `features=test_network`；`install --targets aleo --with-runtime` **只**打印 exact cargo 配方、不 cargo-build、不进 Tool Root；prebuilt GitHub zip 无 feature → `mismatch` 永不 `ok`；见 §10） |
| **MCP-V0** | **done**（`tools/mcp/proof_forge_mcp_server.py` stdio MCP；tools: `pf_list_targets`/`pf_doctor`/`pf_install`/`pf_build`/`pf_artifacts`；仅 spawn 产品 CLI/引擎 JSON；无 network broadcast 工具；`tools/mcp/README.md` Agent 接线；`scripts/mcp_smoke.sh`） |
| **SDK-V0** | **done**（Python `tools/sdk/proof_forge_sdk.py`：`ProofForgeClient` spawn `proof-forge-next` + parse doctor/install/list-targets JSON + `load_output_manifest` for engineering `proof-forge.output.v1`；非第二编译器；`tools/sdk/README.md`；`scripts/sdk_smoke.sh`） |
| **Close** | **done**（本文 + index 成熟度诚实；剩余 backlog：交互式 install UI、全链 runtime pack、N3 前 `deployable=true` 禁改） |
| **External ProgramV1** | **done engineering**（[`02-external-program-v1.md`](02-external-program-v1.md) + `templates/external-aleo-hello/` + sandbox/SDK/MCP `--root` + `just external-hello-smoke`；非 Lake SDK / formal） |
| **Hello agent playbook** | **done engineering**（[`03-hello-dapp-agent-playbook.md`](03-hello-dapp-agent-playbook.md)；MCP 顺序 doctor→install→build/local→artifacts） |
| **Chain client catalog** | **done engineering**（[`04-chain-client-catalog.md`](04-chain-client-catalog.md) + `chain-client-catalog.v1.json` + `pf_chain_catalog` / SDK `chain_catalog`；元数据 only） |
| **Distribution / packages** | **REL-CLI-0/1 engineering done**（[`05-distribution-and-packages.md`](05-distribution-and-packages.md)：`version` + `just package-cli` tarball；Author SDK / Host pip / formal Stage-0 仍 pending） |

本文是 **产品契约与实现顺序** 的权威草稿；I0–I3、MCP-V0、SDK-V0 已接线。不声称 formal / hermetic / mainnet / Stage-0。

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
| I2 | `I2-LOCAL-CMDS` | 统一本机/网络入口包装 | **done**：`local --target …` / `network --target … --broadcast` 调现有 package 脚本；`--json`=`proof-forge.local.v1`/`proof-forge.network.v1`；`scripts/local_network_smoke.sh` |
| I3 | `I3-ALEO-RUNTIME` | Aleo runtime 安装诚实路径 | **done**：snarkos `features=test_network` 文档 + doctor 探测 + install 打印 exact cargo 配方（不 cargo-build）；约定路径 `~/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos` / `PROOF_FORGE_ALEO_SNARKOS`；缺 feature 的 prebuilt → `mismatch` 永不 `ok` |
| MCP | `MCP-V0` | 最小 MCP server | **done**：`tools/mcp/proof_forge_mcp_server.py`；tools 含 `pf_local`（通用 sandbox）+ build/doctor；拒 network broadcast；见 §8 |
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
| **runtime** | 否；需 `--with-runtime` 或 `--profile runtime` | lock：`anvil`/`cast`、`near-sandbox`；Aleo **snarkos** 见 §10（**非** lock asset：install 只打印 cargo 配方） |

host-heavy 门（`just solana-runtime` / `just psy-runtime` / Anvil / snarkOS）**不**并入 ordinary `just ci`。

### 4.4 Implemented target → lock tools（doctor 规划表）

| Target | core tools（Tool Lock ids） | runtime / 额外 |
|---|---|---|
| `evm` | `solc` | `anvil`、`cast`（runtime 档） |
| `solana` | `sbpf` | Mollusk 等工程 harness（非本 lock 的 install 默认面；runtime 文档另述） |
| `near` | `wat2wasm` | `near-sandbox`（runtime） |
| `noir` | `nargo` | prove/VK / barretenberg：**unresolved / FC**（见 lock `unresolved.barretenberg`） |
| `aleo` | `leo` | snarkos：**不在 lock**；I3 已接线（`PROOF_FORGE_ALEO_SNARKOS` / cargo-install 路径 + `test_network` probe） |
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
  snarkos: missing installCommand=cargo install snarkos --version 4.9.0 --features test_network --locked --root ~/.cache/proof-forge-v2/aleo-devnet/cargo-install (…; set PROOF_FORGE_ALEO_SNARKOS …)
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
        {
          "name": "snarkos",
          "status": "missing",
          "tier": "runtime",
          "envVar": "PROOF_FORGE_ALEO_SNARKOS",
          "defaultPath": "~/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos",
          "installCommand": "cargo install snarkos --version 4.9.0 --features test_network --locked --root ~/.cache/proof-forge-v2/aleo-devnet/cargo-install",
          "hint": "features=test_network required; not in Tool Lock; prebuilt GitHub snarkos usually lacks test_network"
        }
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
- `--with-runtime` 装 lock 内 runtime 工具（`anvil`/`cast`、`near-sandbox`）；Aleo `snarkos` **不在 lock**：install **不** cargo-build，只在 report 中给出 exact `installCommand` + `PROOF_FORGE_ALEO_SNARKOS` 约定（I3；host-heavy，非 ordinary ci）。
- 引擎：`/usr/bin/python3 -I -S scripts/proof_forge_install.py`；产品 CLI：`proof-forge-next install`（CWD=repo root）。
- 聚焦 smoke：`scripts/install_smoke.sh`（含 temp root 上 `quint`/`jv` 物化 + 幂等 skip + aleo `--with-runtime` snarkos documented）。
- 成功后同一进程或紧随 `doctor` 可验证 present。

## 7. 本机 / 网络包装（I2）

**已实现**。实际 runtime/network 广播仍 host-heavy、**不**并入 ordinary `just ci`、**不** formal；
ordinary CI 只运行 no-network parser/security self-test 与 CLI smoke：

```bash
proof-forge-next local --target aleo [--mode sandbox|devnet] [--json] [--] [script-args...]
proof-forge-next local --target solana [--mode runtime] [--json] [--] [script-args...]
proof-forge-next local --target evm [--mode runtime] [--json] [--] [script-args...]
proof-forge-next network --target aleo --broadcast [--json] [--] [script-args...]
```

| Target | `local` 模式（默认） | 包装脚本 | 等价工程入口 |
|---|---|---|---|
| `aleo` | `sandbox`（默认） | `scripts/aleo_local_sandbox.sh` | `just aleo-sandbox` |
| `aleo` | `devnet` | `scripts/aleo_devnet.sh` | `just aleo-devnet` |
| `solana` | `runtime`（默认） | `scripts/solana_runtime_test.sh` | `just solana-runtime` |
| `evm` | `runtime`（默认） | `scripts/evm_anvil_differential.sh` | Anvil engineering smokes |
| 其它 implemented | — | fail closed（无产品 script path） | 见 target dossier |
| design-only | — | fail closed `unsupported` | 不可 install/local |

| Target | `network` | 包装脚本 | 备注 |
|---|---|---|---|
| `aleo` | CLI：no-secret DevNet；explicit engine：DevNet/Testnet | `scripts/aleo_network_receipt.py`（`aleo_network.sh` 仅 privileged-Bash adapter） | 显式 `--broadcast`；OutputSet/tool private snapshot；独立 retained-FD receipt；CLI CWD wrapper spawn 前拒 signer args/env/FD capability；Testnet key-file identity→inherited FD + snarkOS SHA pin；mainnet/canary 拒绝 |
| 其它 | fail closed | — | 无产品 network 脚本 |

- local/network CWD wrapper 固定执行 `/bin/bash -p`；Testnet 推荐 `just aleo-network` 直接执行
  `/usr/bin/python3 -I -S`，显式 shell adapter 也固定 privileged Bash + absolute Python；禁止 PATH/BASH_ENV fallback。
- `network` 无 `--broadcast` → usage / exit 2（产品 parse 层，永不隐式广播）。
- Aleo network 缺参数 → `PF-NETWORK-MISSING`；缺/错 snarkOS → `PF-TOOLCHAIN-MISSING`；CLI JSON 映射稳定 status。
- schema：`proof-forge.local.v1` / `proof-forge.network.v1`（含 `script`/public-safe `args`/`exitCode`/`status`/redacted `scriptStdout`/`scriptStderr`）。raw key、key-file path 与 fee record 不得出现在 JSON。
- Aleo network 不重跑 build/Leo：先 stable-read 完整 compile-profile OutputSet 到 owner-private snapshot，
  产品 `inspect --output-dir` 重验该 snapshot 的 exact closure，再从同一 snapshot staged package；snarkOS
  也按 validated FD/hash 复制为 private executable snapshot。deployment receipt 父目录须预先存在、
  owner-safe 且与 OutputSet 不重叠，并由 retained parent/staging FD 发布；build Finalize 不访问 network/signer。
- 聚焦门：`scripts/local_network_smoke.sh` + `aleo_network_receipt_self_test.py` + `aleo_devnet_self_test.py` 进入 ordinary target CLI smoke；它们不广播。实际 `just aleo-devnet-integration` 仍独立 host-heavy。
- 不把 host-heavy 结果写成 ordinary ci 通过或 formal 证据。
- build 的 **flag** `--network` 仍为 usage error（无 network registry）；与 top-level `network` **子命令**不同。

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

## 10. Aleo snarkos 诚实性（I3）— **done**

- Tool Lock **当前不含** `snarkos` / `snarkvm` asset；**禁止**把 snarkos 物化进 `PROOF_FORGE_TOOL_ROOT`。
- 本地 DevNet（`proof-forge-next local --target aleo --mode devnet` / `scripts/aleo_devnet.sh` / `leo devnet`）需要 snarkos 时，须 **`features=test_network`**（crate 特性）。
- **GitHub 常见 prebuilt snarkos zip 通常缺少 `test_network`**，**不得**标为 doctor `ok`，也**不得**声称可用于 leo devnet。

### 10.1 约定路径与环境变量

| 项 | 值 |
|---|---|
| Env | `PROOF_FORGE_ALEO_SNARKOS`（优先；绝对路径推荐） |
| 默认 binary | `~/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos` |
| 默认 cargo `--root` | `~/.cache/proof-forge-v2/aleo-devnet/cargo-install` |
| 共享 helper | `scripts/proof_forge_aleo_snarkos.py` |

### 10.2 安装配方（product install 只打印、不执行）

host-heavy（需 Rust/clang 等；**不**并入 ordinary `just ci`；产品 `install` **不**自动 cargo-build）：

```bash
cargo install snarkos --version 4.9.0 --features test_network --locked \
  --root ~/.cache/proof-forge-v2/aleo-devnet/cargo-install
# optional: export PROOF_FORGE_ALEO_SNARKOS=~/.cache/proof-forge-v2/aleo-devnet/cargo-install/bin/snarkos
```

```bash
proof-forge-next install --targets aleo --with-runtime --dry-run --json
# → tools[] 含 snarkos status=documented|present + installCommand + envVar
```

若本机已有经 `--version` 验证含 `test_network` 的 binary，install 报告 `status=present`（观察-only，仍非 Tool Lock member）。

### 10.3 doctor 探测

- `doctor --target aleo` **始终**报告 snarkos（runtime 诚实面；路径 **不是** `$TOOL_ROOT/snarkos`）。
- 探测：对解析路径执行 `snarkos --version`，解析 `features=[…,test_network,…]`。
- 状态：
  - `missing` — 路径不存在；hint + `installCommand`
  - `mismatch` — 文件在但 version **无** `test_network`（典型 prebuilt）
  - `partial` — 文件在但 version probe 失败（不可 attest）
  - `ok` — version 列表含 `test_network`
- 聚焦 smoke：`scripts/doctor_smoke.sh`（fake missing / prebuilt mismatch / good ok）。

### 10.4 DevNet/Testnet 使用与成熟度边界

- DevNet 使用 `features=test_network` 的 local validator + funded `--dev-key`，不向 snarkOS 暴露用户 private-key file；lifecycle fresh-ledger/loopback/exact PID ownership 见 09c。
- public Testnet 因 snarkOS 尚不在 Tool Lock，network engine 额外要求 operator-provided exact SHA-256 pin、single-link/非 group-write binary；validated source FD 被流式复制到 private executable snapshot 后才执行。signer key-file 只作为 identity-pinned pre-open adapter并通过 inherited FD 交给工具。
- Testnet deploy 需要 Faucet test credits；无余额不能部署。Mainnet/canary 在 wrapper preflight 明确拒绝。
- 在 N3 产品决策前，**不得**因 snarkos 存在或 engineering receipt 成功而把 Aleo `deployable` 改为 `true`。
- doctor/install/DevNet 成功 **不是** formal / hermetic / mainnet / package-only snarkVM execute 证据。

## 11. 与现有脚本 / CLI 关系

| 现有 | 角色 |
|---|---|
| `scripts/toolchain_assets.py` | install 引擎（I1 复用） |
| `toolchains*.lock.json` | 唯一可装 tool 菜单 |
| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档主推 CLI |
| `proof-forge-next` 现有 | `build` / `check` / `inspect` / `list-targets` / **`doctor`** / **`install`** / **`local`** / **`network`** |
| `tools/mcp/proof_forge_mcp_server.py` | MCP-V0 stdio 薄封装（仅 spawn 上列 CLI JSON） |
| `tools/sdk/proof_forge_sdk.py` | SDK-V0 Python 薄客户端（spawn CLI + parse JSON/manifest） |
| `scripts/aleo_local_sandbox.sh` / `aleo_devnet.sh` / `aleo_network.sh` | I2 已包装；DevNet lifecycle 与 explicit post-build deploy wrapper |
| `scripts/aleo_devnet.py` | fresh-ledger、loopback REST、exact owned PID lifecycle |
| `scripts/aleo_network_receipt.py` | OutputSet/snarkOS private snapshot gate、identity-pinned signer FD bridge、bounded/reaped process groups、retained-FD独立 receipt authority（engineering） |
| `scripts/proof_forge_aleo_snarkos.py` | I3 snarkos 路径/env/`test_network` probe + cargo 配方 sole doctor/install helper |
| `scripts/solana_runtime_test.sh` / `scripts/evm_anvil_differential.sh` | I2 `local --target solana|evm`；`just solana-runtime` / Anvil 工程 lane 仍可用 |
| `just psy-runtime` 等 | 尚未统一进 `local`；保持 host-heavy 工程入口 |

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
