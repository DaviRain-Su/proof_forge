---
id: PRODUCT-HELLO-DAPP-AGENT-PLAYBOOK
title: Hello dApp agent playbook (MCP / SDK / external template)
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# Hello dApp：Code Agent 剧本（后端合约 + 本机 sandbox）

状态：`draft`（2026-08-09）  
前置：[`02-external-program-v1.md`](02-external-program-v1.md)、[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  
模板：[`templates/external-aleo-hello/`](../../templates/external-aleo-hello/)  
Catalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md) / `pf_chain_catalog`

## 1. 范围

本剧本让 **Code Agent**（经 MCP）或脚本（经 SDK/CLI）完成 **hello 级** 闭环：

```text
doctor → install(aleo) → 写/确认 ProgramV1 → build → local sandbox offline run → inspect artifacts
```

**后端** = ProofForge `program … where` 合约。  
**前端** = 生态客户端（见 chain catalog）；本剧本 **不** 生成完整 Web UI，只钉后端可测。

## 2. 非目标

- MCP **不**暴露 `network --broadcast` / private-key
- 不设 `deployable=true`、不主网、不 formal
- 不把 `leo run` 说成上链
- 不要求外部工程 Lake `require` PF

## 3. 环境

| 变量 | 含义 |
|---|---|
| `PROOF_FORGE_ROOT` | monorepo 根（含 `scripts/`、`tools/mcp/`） |
| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径 |
| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根（含 locked `leo`） |

MCP 接线见 [`tools/mcp/README.md`](../../tools/mcp/README.md)。

## 4. MCP 工具顺序（Aleo Hello）

| 步 | Tool | 参数（示意） | 成功判据 |
|---|---|---|---|
| 0 | `pf_chain_catalog` | `target=aleo` | 看到 sandbox/local + honesty |
| 1 | `pf_doctor` | `targets=["aleo"]` | JSON `proof-forge.doctor.v1`；缺工具可读 |
| 2 | `pf_install` | `targets=["aleo"]` | 装 core tools；`--yes` 已内置 |
| 3 | 写源 | 文件系统 | `import ProofForgeV2` + `program Hello where`（模板） |
| 4 | `pf_build` **或** `pf_local` | 见下 | build exit 0 / LOCAL-SANDBOX-OK |
| 5 | `pf_artifacts` | `outputDir=…` | exact closure inspect |

### 4.1 仅 build

```json
{
  "source": "src/Hello.lean",
  "module": "Hello",
  "target": "aleo",
  "root": "/abs/path/to/project",
  "output": "/abs/path/to/project/out-aleo"
}
```

### 4.2 build + offline run（推荐 hello）

```json
{
  "target": "aleo",
  "mode": "sandbox",
  "root": "/abs/path/to/project",
  "source": "src/Hello.lean",
  "module": "Hello",
  "runs": ["initialize 1u64", "increment 2u64"]
}
```

`pf_local` 会 spawn 产品 `local` → 通用 `aleo_local_sandbox.sh`（host-heavy）。

缺 Leo：`PF-TOOLCHAIN-MISSING` — 回到 `pf_install` / doctor，**不** PATH fallback。

## 5. SDK 等价

```python
from proof_forge_sdk import ProofForgeClient
c = ProofForgeClient()
c.doctor(targets=["aleo"])
c.install(targets=["aleo"], yes=True)
print(c.chain_catalog(target="aleo").parsed)
c.local(
    target="aleo",
    mode="sandbox",
    root="/abs/path/to/project",
    source="src/Hello.lean",
    module="Hello",
    runs=["initialize 1u64", "increment 2u64"],
)
```

## 6. CLI 等价

```bash
just external-hello-smoke
# or
proof-forge-next local --target aleo --mode sandbox -- \
  --root "$PROJ" --source src/Hello.lean --module Hello \
  --run 'initialize 1u64' --run 'increment 2u64'
```

## 7. 前端下一步（剧本外）

Agent 完成后端后：

1. `pf_chain_catalog` 读 `frontendClients`（ecosystem，**非** PF 发货）
2. 用生态 SDK 做极薄页面/脚本（查询 mapping / 调合约）— **人工或后续切片**
3. 链上 deploy 仅显式 CLI `network --broadcast`（DevNet/Testnet 工程路径）

## 8. 失败剧本

| 现象 | 处理 |
|---|---|
| 缺 `--source`/`--module` | usage exit；补参数 |
| `import ProofForgeV2` 缺失 | `PF-SRC-INVALID`；补 gate 行 |
| 缺 leo | install + doctor；勿 PATH 扫 |
| Agent 请求 broadcast | **拒绝**；指引产品 CLI 显式 network |
| design-only target | catalog `implemented=false`；不 install/build |

## 9. 成熟度标签（日志中应保持）

- `deployable=false`
- `LEO-OFFLINE-RUN` = local interpret
- `NOT-PACKAGE-ONLY-SNARKVM`
- 非 formal / 非 mainnet
