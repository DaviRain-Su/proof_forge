---
id: PRODUCT-HELLO-DAPP-AGENT-PLAYBOOK
title: Hello dApp agent playbook (MCP / SDK / external template)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Hello dApp：Code Agent 剧本（后端合约 + direct artifact）

状态：`draft`（2026-08-10）
前置：[`02-external-program-v1.md`](02-external-program-v1.md)、[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)  
Catalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md) / `pf_chain_catalog`

## 1. 范围

本剧本让 **Code Agent**（经 MCP）或脚本（经 SDK/CLI）完成 **hello 级 artifact 闭环**：

```text
doctor → 写/确认 ProgramV1 → build → inspect artifacts
```

**后端** = ProofForge `program … where` 合约。  
**前端** = 生态客户端（见 chain catalog）；本剧本 **不** 生成完整 Web UI，只钉后端可测。

## 2. 非目标

- MCP **不**暴露 `network --broadcast` / private-key
- 不设 `deployable=true`、不主网、不 formal
- 不发明 Aleo compiler/local runtime/network fallback
- 不要求外部工程 Lake `require` PF

## 3. 环境

| 变量 | 含义 |
|---|---|
| `PROOF_FORGE_ROOT` | monorepo 根（含 `scripts/`、`tools/mcp/`） |
| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径 |
| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根；Aleo direct target 不需要工具 |

MCP 接线见 [`tools/mcp/README.md`](../../tools/mcp/README.md)。

## 4. MCP 工具顺序（Aleo Hello）

| 步 | Tool | 参数（示意） | 成功判据 |
|---|---|---|---|
| 0 | `pf_chain_catalog` | `target=aleo` | 看到 direct artifact + honesty |
| 1 | `pf_doctor` | `targets=["aleo"]` | JSON `proof-forge.doctor.v1`；zero-tool `ok` |
| 2 | 写源 | 文件系统 | `import ProofForgeV2` + `program Hello where` |
| 3 | `pf_build` | 见下 | exit 0 |
| 4 | `pf_artifacts` | `outputDir=…` | exact closure inspect |

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

构建结果是 canonical Aleo Instructions + query descriptor。`pf_local` 对 Aleo fail closed；
不存在 Leo/Dargo/snarkOS fallback。

## 5. SDK 等价

```python
from proof_forge_sdk import ProofForgeClient
c = ProofForgeClient()
c.doctor(targets=["aleo"])
result = c.build(
    source="src/Hello.lean",
    module="Hello",
    target="aleo",
    root="/abs/path/to/project",
    output="/abs/path/to/project/out-aleo",
)
print(result.parsed)
```

## 6. CLI 等价

```bash
proof-forge-next build src/Hello.lean --module Hello --target aleo \
  --root "$PROJ" -o "$PROJ/out-aleo"
proof-forge-next inspect --output-dir "$PROJ/out-aleo" --json
```

## 7. 前端下一步（Aleo dApp）

Agent 完成后端后，**前端不是可选闲笔**——完整 Aleo APP 需要 Wallet 交互。权威剧本：

[`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md)

最短路径：

1. `pf_chain_catalog` `target=aleo` → 读 `frontendClients`（`@provablehq/aleo-wallet-adaptor-*` · `@provablehq/sdk`）
2. 脚手架：复制/打开 [`templates/aleo-dapp-ui`](../../templates/aleo-dapp-ui/)（Vite + `AleoWalletProvider` / `WalletMultiButton`）
3. 从 PF `pf deploy`（或 explorer）取得 **program id**，写入前端 env（**无私钥**）
4. 用户钱包 `executeTransaction` 调 `initialize` / `increment`；public mapping 用 explorer REST 读
5. 开发者本机仍可用 `pf deploy|execute --broadcast` 做冒烟；**终端用户只走钱包**

边界：

- MCP **不**代签、不持 key、不默认 broadcast
- 不得从 Instructions artifact  alone 推断「已部署」
- 浏览器禁止嵌入 `APrivateKey1…`

## 8. 失败剧本

| 现象 | 处理 |
|---|---|
| 缺 `--source`/`--module` | usage exit；补参数 |
| `import ProofForgeV2` 缺失 | `PF-SRC-INVALID`；补 gate 行 |
| Aleo local/network 请求 | **拒绝**；只支持 direct build/inspect |
| design-only target | catalog `implemented=false`；不 install/build |

## 9. 成熟度标签（日志中应保持）

- `deployable=false`
- `ALEO-INSTRUCTIONS-DIRECT`
- `NO-LOCAL-OR-NETWORK-RUNTIME`
- 非 formal / 非 mainnet
