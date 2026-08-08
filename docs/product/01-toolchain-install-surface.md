---
id: PRODUCT-TOOLCHAIN-INSTALL-SURFACE
title: Product surface ladder — install / doctor / CLI / MCP
status: draft
owner: product+engineering
updated: 2026-08-08
normative: false
---

# 产品面阶梯：安装选链 → 本机验证 → SDK / MCP

状态：`draft`（2026-08-08）  
执行入口：workflow `product-surface-ladder`（`.grok/workflows/product-surface-ladder.rhai`）

## 1. 产品目标

用户安装 / 使用 ProofForge 时：

1. **知道** 当前支持哪些 target（registry 事实，非营销名单）。
2. **选择** 要开发的链，安装对应 **Tool Lock** 锁定工具到 `PROOF_FORGE_TOOL_ROOT`。
3. **诊断** 缺工具 / digest 不匹配（`doctor`），再 **build / local / network**。
4. 后续 **SDK / MCP** 只封装同一 CLI 契约，供 Code Agent 做 Web Coding。

## 2. 非目标

- 不把 install 变成「静默 PATH 扫全盘随便装」。
- 不默认 `deployable=true` 或主网广播。
- 不在 ordinary `just ci` 里起 snarkOS / Anvil / Mollusk。
- 不先做大而全多语言 SDK；先 CLI + 薄封装。
- design-only target（soroban/icp/openvm）只展示为未实现，不提供假安装。

## 3. 阶梯切片（workflow 相位）

| 相位 | ID | 交付 | 完成标准 |
|---|---|---|---|
| DOC | `DOC` | 本文 + `docs/index.md` 指针 | docs-check 过 |
| I0 | `I0-DOCTOR` | `proof-forge doctor`（或 `proof-forge-next doctor`） | 每 implemented target 报告 present/missing/mismatch；JSON 输出；无 Tool Root 时 fail closed 有码 |
| I1 | `I1-INSTALL` | 非交互 `install --targets a,b --yes` | 复用 `scripts/toolchain_assets.py` provision/materialize；只装 lock 内 asset；digest 校验 |
| I1b | `I1b-CLI-WIRE` | CLI 子命令接到 Exe；`--json`；usage | `just docs-check` + 聚焦 CLI 测或 smoke |
| I2 | `I2-LOCAL-CMDS` | 统一本机/网络入口包装 | `local --target aleo` / `network …` 调现有 sandbox/devnet/network 脚本；显式 broadcast |
| I3 | `I3-ALEO-RUNTIME` | Aleo runtime 安装诚实路径 | snarkos `test_network`：document 或 semi-auto cargo install 到约定路径；`doctor --target aleo` 识别 |
| MCP | `MCP-V0` | 最小 MCP server | tools: doctor, install, build, list_artifacts；只调 CLI/JSON |
| SDK | `SDK-V0` | 可选薄 SDK（TS 或 Python 选一） | spawn CLI + parse manifest；非第二编译器 |
| Close | `Close` | AGENTS/backlog 指针 | 成熟度诚实；不声称 formal |

## 4. 架构约束

```text
User / Agent
    │
    ▼
proof-forge-next  (sole product CLI)
    │  doctor | install | build | local | network | inspect
    ▼
scripts/toolchain_assets.py  +  Tool Lock v4
    │
    ▼
PROOF_FORGE_TOOL_ROOT/<platform>/{solc,sbpf,leo,nargo,...}
```

- **权威菜单** = `toolchains.lock.json` / `toolchains-linux-x86_64.lock.json`（及 aarch64）。
- **Target 菜单** = `TargetRegistryV1` implemented ids（evm/solana/near/noir/aleo/psy/quint/cosmwasm/ton）。
- **Runtime 重依赖**（Anvil、Mollusk、snarkOS DevNet）标 `runtime` 档，默认不装；`--with-runtime` 或 `install --profile runtime --targets aleo`。

## 5. doctor 输出契约（I0）

人类：

```text
platform=linux-x86_64
tool_root=...
target=aleo status=partial
  leo: ok sha=… version=4.0.2
  snarkos: missing (need features=test_network; see docs/product/01…)
```

JSON（MCP/Agent）：

```json
{
  "schema": "proof-forge.doctor.v1",
  "platform": "linux-x86_64",
  "toolRoot": "...",
  "targets": [
    {"id": "aleo", "status": "partial", "tools": [{"name":"leo","status":"ok"},{"name":"snarkos","status":"missing","hint":"..."}]}
  ]
}
```

状态枚举：`ok` | `partial` | `missing` | `mismatch` | `unsupported`。

## 6. install 契约（I1）

```bash
proof-forge-next install --targets aleo,solana --yes
proof-forge-next install --targets aleo --with-runtime --yes
proof-forge-next install --all-core --yes   # 所有 implemented 的 compile 档
```

- 无 `--yes` 且非 TTY → usage / fail closed。
- 禁止 PATH fallback 安装进 Tool Root。
- 已存在且 digest 匹配 → skip（幂等）。

## 7. MCP-V0 工具列表

| Tool | 映射 |
|---|---|
| `pf_list_targets` | registry list |
| `pf_doctor` | doctor --json |
| `pf_install` | install --targets … --yes |
| `pf_build` | build source --module --target -o |
| `pf_local` | local sandbox/runtime by target |
| `pf_artifacts` | inspect output-dir / list files |

全部 **不** 默认 network broadcast；network 工具必须显式 `broadcast=true`。

## 8. 与现有脚本关系

| 现有 | 角色 |
|---|---|
| `toolchain_assets.py` | install 引擎 |
| `just toolchains-*` | 工程/CI 旁路；产品 CLI 成后文档指向 CLI |
| `aleo_local_sandbox.sh` / `aleo_devnet.sh` / `aleo_network.sh` | I2 包装对象 |
| `just solana-runtime` 等 | 同左，逐步 `local --target` |

## 9. 验证

每切片：聚焦测或脚本 smoke + `just docs-check`；改 Lean 产品面时按 AGENTS 跑相关测 + 必要时 SBOM。  
不声称 ordinary ci 已含 host-heavy runtime。
