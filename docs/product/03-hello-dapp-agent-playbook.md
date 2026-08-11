---
id: PRODUCT-HELLO-DAPP-AGENT-PLAYBOOK
title: Hello dApp agent playbook (MCP / SDK / external template)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Hello dApp：Code Agent 剧本（后端合约 + direct artifact）

状态：`draft`（2026-08-10；**默认路径 = engineering bundle**，ADR-0040）  
前置：[`14-external-author-mvp.md`](14-external-author-mvp.md)、[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)、[`02-external-program-v1.md`](02-external-program-v1.md)  
Catalog：[`04-chain-client-catalog.md`](04-chain-client-catalog.md) / `pf_chain_catalog`  
网络：[`networks.v1.json`](networks.v1.json) · `pf network list`

## 1. 范围

本剧本让 **Code Agent**（经 MCP）或脚本（经 SDK/CLI）完成 **hello 级闭环**：

```text
bootstrap bundle → doctor/setup → write ProgramV1 → build → test? → artifacts / UI json
```

**后端** = ProofForge `program … where`。  
**前端** = 生态客户端 / `templates/*-dapp-ui`；本剧本钉后端可测 + 产物契约。

## 2. 非目标

- MCP **不**暴露 `network --broadcast` / private-key
- 不设 `deployable=true`、不主网、不 formal
- **禁止**默认教 Agent `lake build` monorepo（贡献者路径另开）
- 不发明 Aleo compiler/local runtime/network fallback
- 不要求外部工程 Lake `require` PF

## 3. 环境（外部作者默认）

| 变量 | 含义 |
|---|---|
| `PROOF_FORGE_ROOT` | **bundle 根**（含 `scripts/`、`bin/`、`lib/lean/`）— 不是 monorepo |
| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径（常为 `$PROOF_FORGE_ROOT/bin/proof-forge-next`） |
| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根；Aleo/Psy zero-tool 可不设 |
| `PROOF_FORGE_HOST_MODE` | 默认 `dev`（不 pin 他机 host:stat） |

```bash
# 一次安装（Release bundle）
bash scripts/install.sh --from proof-forge-bundle-*.tar.gz
# 或: pf bootstrap --from proof-forge-bundle-*.tar.gz

export PATH="$HOME/.local/proof-forge/current/bin:$PATH"
export PROOF_FORGE_CLI="$HOME/.local/proof-forge/current/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$HOME/.local/proof-forge/current"
```

贡献者 monorepo：仍可用 monorepo 的 `PROOF_FORGE_ROOT` + `.lake/build/bin/proof-forge-next`，但 **不是** Agent 默认剧本。

MCP 接线见 [`tools/mcp/README.md`](../../tools/mcp/README.md)（stdio 本机 spawn CLI；远程 edge 只 docs/catalog）。

## 4. 推荐：`pf` 短路径（EVM hello）

| 步 | 命令 | 成功判据 |
|---|---|---|
| 0 | `pf version` | 见 compiler path + hostMode=dev |
| 1 | `pf -y setup --target evm` | doctor/setup ready；Tool Root 有 solc（+ anvil/cast） |
| 2 | `pf network list --family evm` | 看到 `evm.local.anvil` 等 |
| 3 | `pf new hello --target evm && cd hello` | `src/*.lean` + `pf.toml` |
| 4 | `pf build` | `build/evm/manifest.json` + `*.bin` + `*.abi.json` |
| 5 | `pf test` | Anvil smoke ok **或** skip-clean（缺 anvil） |
| 6 | `pf deploy` | save-only `build/evm/tx/*deployment.package.json` |
| 7 | `pf scaffold-ui --template evm-dapp` | `ui/evm-dapp/` + 同步 abi/bin + `public/deployment.json` |
| 8 | `pf write-ui-json`（可选） | 单独刷新 UI JSON，不重拷模板 |

```bash
pf -y setup --target evm
pf new hello --target evm && cd hello
pf build && pf test
pf deploy
pf scaffold-ui --template evm-dapp
cd ui/evm-dapp && npm install && npm run dev
# optional after local broadcast (fills contractAddress):
# pf deploy --broadcast --network local
# pf scaffold-ui --template evm-dapp --force --address 0x…
```

### 4b. Aleo hello（zero-tool）

| 步 | 命令 |
|---|---|
| 1 | `pf -y setup --target aleo` |
| 2 | `pf new hello --target aleo && cd hello` |
| 3 | `pf build` |
| 4 | `pf inspect` / artifacts |

构建结果是 canonical Aleo Instructions + query descriptor。

## 5. MCP 工具顺序（本机 stdio；需已装 bundle）

| 步 | Tool | 参数（示意） | 成功判据 |
|---|---|---|---|
| 0 | `pf_chain_catalog` | `target=evm` 或 `aleo` | honesty + artifact shape |
| 1 | `pf_doctor` | `targets=["evm"]` | `proof-forge.doctor.v1` |
| 2 | 写源 | 文件系统 | `import ProofForgeV2` + `program Hello where` |
| 3 | `pf_build` | source/module/target/root/output | exit 0 |
| 4 | `pf_artifacts` | `outputDir=…` | exact closure inspect |

远程 edge MCP：**不**提供 compile；Agent 应提示用户本机 bundle + stdio MCP。

### 5.1 build 参数例（EVM）

```json
{
  "source": "src/Hello.lean",
  "module": "Hello",
  "target": "evm",
  "root": "/abs/path/to/project",
  "output": "/abs/path/to/project/build/evm"
}
```

## 6. SDK 等价

```python
from proof_forge_sdk import ProofForgeClient
c = ProofForgeClient()  # spawns PROOF_FORGE_CLI
c.doctor(targets=["evm"])
result = c.build(
    source="src/Hello.lean",
    module="Hello",
    target="evm",
    root="/abs/path/to/project",
    output="/abs/path/to/project/build/evm",
)
print(result.parsed)
```

## 7. CLI 等价（compiler 直调）

```bash
proof-forge-next build src/Hello.lean --module Hello --target evm \
  --root "$PROJ" -o "$PROJ/build/evm"
proof-forge-next inspect --output-dir "$PROJ/build/evm" --json
```

外部作者优先用 **`pf build`**（同契约，少记 flag）。

## 8. 前端下一步

| Target | 文档 / 模板 |
|---|---|
| EVM | [`08-evm-dapp-frontend.md`](08-evm-dapp-frontend.md) · `templates/evm-dapp-ui` · `pf write-ui-json` |
| Aleo | [`07-aleo-dapp-frontend-wallet.md`](07-aleo-dapp-frontend-wallet.md) |
| Solana | [`09-solana-agent-playbook.md`](09-solana-agent-playbook.md) · [`10-solana-dapp-frontend.md`](10-solana-dapp-frontend.md) |
| Psy | [`11-psy-agent-playbook.md`](11-psy-agent-playbook.md) |

EVM 最短：

```bash
pf write-ui-json -o templates/evm-dapp-ui/public/deployment.json
# or: cp build/evm/ui-deployment.json templates/evm-dapp-ui/public/deployment.json
cd templates/evm-dapp-ui && npm install && npm run dev
```

## 9. 禁止清单（Agent）

- 不要 `git clone` + `lake build proof_forge_next` 作为默认装机
- 不要手改 `host-profiles.lock.json`
- 不要在远程 MCP 上声称可以 `pf_build`
- 不要默认 `--broadcast` 到 public testnet（v0：EVM/Solana 仅 local）

## 10. 相关

- ADR-0040 host mode + bundle  
- [`14-external-author-mvp.md`](14-external-author-mvp.md)  
- `pf network list` / `pf network use evm.xlayer.testnet`（元数据 only）
