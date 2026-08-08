---
id: TARGET-ALEO-LOCAL-SANDBOX
title: Aleo local sandbox (build → package → offline run)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Aleo 本地 sandbox（产品路径：build → package → offline run）

状态：`draft`（2026-08-08）  
父文档：[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)（Instructions 权威；IR-7 package-only 仍 MISSING）  
入口：`just aleo-sandbox` → `scripts/aleo_local_sandbox.sh`

## 1. 目标

当作者选定 **`--target aleo`** 时，产品链除 Plan→Instructions materialize 外，还提供一条 **可复现、诚实边界** 的本机 sandbox 执行路径（与 Solana Mollusk / NEAR sandbox 同级：**host-heavy 本地门**，非 ordinary ci）：

```text
ProgramV1 Counter
  → proof-forge-next build --target aleo
  → primary counter.aleo  (Aleo Instructions；≡ golden)
  → debug counter.leo    (PROOF_FORGE_ALEO_EMIT_LEO=1；非产品 sole 权威)
  → 临时 Leo 4.0.2 package
  → locked leo build --offline
  → locked leo run --offline  initialize / increment
  → 打印观测 + 明确成熟度边界
```

成功标准：

| 条件 | 结果 |
|---|---|
| locked Leo 4.0.2 在 `PROOF_FORGE_TOOL_ROOT`（或默认 cache）| **exit 0**：build pin + offline run 调用成功 |
| Leo 缺失 | **exit 2**：`PF-TOOLCHAIN-MISSING`（不假绿） |
| 产品 build / golden / leo-build Instructions 不一致 | **exit 1** |
| 调用失败 | **exit 1** |

## 2. 非目标（禁止升级话术）

- 主网 / testnet **链上 deploy** 或 `leo execute` 广播
- snarkVM **package-only** 执行产品 Instructions（仍见 `just aleo-runtime` / IR-7）
- 产品 `deployable=true`、formal proof、hermetic Stage-0
- ordinary `just ci` 并入（host-heavy；与 `aleo-runtime` 同级）
- 把 `leo run` 说成「已上链部署」或「AVM 生产执行」

## 3. 成熟度标签（必须原样出现在脚本日志）

| 标签 | 含义 |
|---|---|
| `aleo-local-sandbox-v1` | 本机 sandbox 工程 profile 名 |
| `INSTRUCTIONS-PRIMARY` | 产品权威 = Plan→Instructions `{id}.aleo` |
| `LEO-DEBUG-PACKAGE` | 调用路径消费 **debug Leo 源** 入 package（与 spike/acceptance 同构） |
| `LEO-OFFLINE-RUN` | `leo run --offline` = **本地解释**，非 prove / 非 chain deploy |
| `NOT-PACKAGE-ONLY-SNARKVM` | 与 IR-7 区分；无 snarkVM pin 则不装成已有 |
| `deployable=false` | 产品声明不变 |

## 4. 工具契约

- **仅** locked path：`$PROOF_FORGE_TOOL_ROOT/leo` 或  
  `$HOME/.cache/proof-forge-v2/tool-root/{linux-x86_64,darwin-arm64}/leo`
- **禁止** PATH / cargo / brew fallback（与 `aleo_acceptance.sh` / `aleo_runtime_test.sh` 一致）
- 版本门：`--version` 须含 `4.0.2`
- 隔离：Leo 步骤 `HOME` = 临时目录 + `mkdir $HOME/.aleo`；清理 `PRIVATE_KEY` / `NETWORK` / `ENDPOINT` 等 ambient 钱包/网络变量（产品 `build` 仍用真实 HOME，避免 elan 重装）
- 产品 CLI：仓库内 `.lake/build/bin/proof-forge-next`（缺失则先提示 `lake build proof_forge_next`）

## 5. 脚本步骤（实现权威）

`scripts/aleo_local_sandbox.sh`：

1. 解析 locked `leo`；缺失 → exit 2。
2. `lake env` 下  
   `PROOF_FORGE_ALEO_EMIT_LEO=1 proof-forge-next build Examples/Counter.lean --module Examples.Counter --target aleo -o <work>/product-out`
3. 要求产物：`counter.aleo`、`counter.leo`、`counter.aleo-query-contract.json`、`manifest.json`。
4. `cmp` 产品 `counter.aleo` ≡ `testdata/golden/aleo-instructions-v1/counter.compiled.aleo`。
5. 暂存 package：`program.json` + `src/main.leo` ← 产品 `counter.leo`。
6. `leo build --offline --disable-update-check --path <pkg>`。
7. `cmp` `build/main.aleo` ≡ 产品 `counter.aleo`（Leo 编译结果与 Plan→Instructions 同字节）。
8. `leo run --offline … initialize 1u64` 然后 `increment 2u64`（local-dev key 仅本机；不写用户密钥）。
9. 打印 query-contract 摘要 + 成熟度标签；exit 0 → `LOCAL-SANDBOX-OK`。

可选 flag：

- `--keep`：保留 workdir 路径（默认 trap 清理）
- `--skip-run`：只做到 build pin（对照 spike）

## 6. 与既有脚本分工

| 脚本 | 角色 |
|---|---|
| `aleo_local_sandbox.sh` | **产品本机 sandbox**：build → Instructions pin → Leo package → offline run |
| `aleo_runtime_test.sh` | IR-7 honesty：package-only snarkVM **MISSING** |
| `aleo_local_toolchain_spike.sh` | 研究 spike：手写 Leo 包 dual-build |
| `aleo_acceptance.sh` | 对已有 `.aleo`/目录做 locked leo **compile-only** |

## 7. 文档 / CI

- `just aleo-sandbox` 注册；**不**加入 ordinary `ci` / `dev-check`。
- `docs/index.md` 链到本文件。
- `09-aleo-instructions-lowering.md` 指针本路径（不改 IR-7 状态）。

## 8. 后续

- Tool Lock pin snarkVM 后扩展「Instructions 直喂」路径（仍 fail closed 直至 pin）。
- 可选 local snarkOS + `leo deploy`（网络；单独决策）。
- CLI 子命令 / SDK / MCP 消费本脚本 exit code 与 artifact 目录。
