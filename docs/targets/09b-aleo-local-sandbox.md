---
id: TARGET-ALEO-LOCAL-SANDBOX
title: Aleo local sandbox (generic build → package → offline run)
status: draft
owner: engineering
updated: 2026-08-09
normative: false
---

# Aleo 本地 sandbox（通用：任意 ProgramV1 → package → offline run）

状态：`draft`（2026-08-09）  
父文档：[`09-aleo-instructions-lowering.md`](09-aleo-instructions-lowering.md)（Instructions 权威；IR-7 package-only 仍 MISSING）  
入口：`just aleo-sandbox -- …` → `scripts/aleo_local_sandbox.sh`；  
产品包装：`proof-forge-next local --target aleo --mode sandbox -- --source … --module …`

**不是 Counter 专用。** 任意满足 Aleo materializer 的 ProgramV1 源均可；入口点由调用方用
`--run` 显式给出。可选 `--golden` 才做字节金样钉（回归用）。

## 1. 目标

当作者选定 **`--target aleo`** 时，提供一条 **可复现、诚实边界** 的本机 sandbox 执行路径
（与 Solana Mollusk / NEAR sandbox 同级：**host-heavy 本地门**，非 ordinary ci）：

```text
任意 ProgramV1 源
  → proof-forge-next build <source> --module <M> --target aleo
  → primary {id}.aleo  (Aleo Instructions)
  → debug {id}.leo     (PROOF_FORGE_ALEO_EMIT_LEO=1；非产品 sole 权威)
  → 临时 Leo 4.0.2 package（program.json program={id}.aleo）
  → locked leo build --offline
  → 可选 locked leo run --offline  <caller-supplied entrypoints>
  → 打印观测 + 明确成熟度边界
```

成功标准：

| 条件 | 结果 |
|---|---|
| locked Leo 4.0.2 在 `PROOF_FORGE_TOOL_ROOT`（或默认 cache）| 可进入 build |
| `--source` + `--module` 缺失 | **exit 2** usage（无默认 program） |
| Leo 缺失 | **exit 2**：`PF-TOOLCHAIN-MISSING`（不假绿） |
| 产品 build 失败 / 产物不完整 | **exit 1** |
| 可选 `--golden` 与 product `{id}.aleo` 不一致 | **exit 1** |
| `leo build/main.aleo` ≢ product Instructions | **exit 1** |
| 调用方 `--run` 失败 | **exit 1** |
| 无 `--run` 或 `--skip-run` | **exit 0**：仅 build pins（`LOCAL-SANDBOX-OK`） |

## 2. 非目标（禁止升级话术）

- 主网 / testnet **链上 deploy** 或 `leo execute` 广播
- snarkVM **package-only** 执行产品 Instructions（仍见 `just aleo-runtime` / IR-7）
- 产品 `deployable=true`、formal proof、hermetic Stage-0
- ordinary `just ci` 并入（host-heavy；与 `aleo-runtime` 同级）
- 把 `leo run` 说成「已上链部署」或「AVM 生产执行」
- 脚本内 hardcode 某一示例 program 的 entrypoint / golden（回归 golden 仅经 `--golden`）

## 3. 成熟度标签（必须原样出现在脚本日志）

| 标签 | 含义 |
|---|---|
| `aleo-local-sandbox-v1` | 本机 sandbox 工程 profile 名 |
| `INSTRUCTIONS-PRIMARY` | 产品权威 = Plan→Instructions `{id}.aleo` |
| `LEO-DEBUG-PACKAGE` | 调用路径消费 **debug Leo 源** 入 package |
| `LEO-OFFLINE-RUN` | `leo run --offline` = **本地解释**，非 prove / 非 chain deploy |
| `NOT-PACKAGE-ONLY-SNARKVM` | 与 IR-7 区分；无 snarkVM pin 则不装成已有 |
| `deployable=false` | 产品声明不变 |

## 4. 工具契约

- **仅** locked path：`$PROOF_FORGE_TOOL_ROOT/leo` 或  
  `$HOME/.cache/proof-forge-v2/tool-root/{linux-x86_64,darwin-arm64}/leo`
- **禁止** PATH / cargo / brew fallback
- 版本门：`--version` 须含 `4.0.2`
- 隔离：Leo 步骤 `HOME` = 临时目录 + `mkdir $HOME/.aleo`；清理 ambient 钱包/网络变量
- 产品 CLI：仓库内 `.lake/build/bin/proof-forge-next`

## 5. CLI 契约（实现权威）

`scripts/aleo_local_sandbox.sh`：

```bash
# 通用：任意源，仅 build + Instructions↔leo pin
./scripts/aleo_local_sandbox.sh \
  --source path/to/Prog.lean \
  --module My.Module

# 带 offline run（入口由调用方决定）
./scripts/aleo_local_sandbox.sh \
  --source path/to/Prog.lean \
  --module My.Module \
  --run 'initialize 1u64' \
  --run 'increment 2u64'

# 中性 runtime 回归；历史 Counter 字节金样由 Instructions suite 独立固定
./scripts/aleo_local_sandbox.sh \
  --source Examples/StateCell.lean \
  --module Examples.StateCell \
  --run 'initialize 1u64' \
  --run 'increment 2u64'

# 产品包装
proof-forge-next local --target aleo --mode sandbox -- \
  --source Examples/StateCell.lean --module Examples.StateCell --skip-run
```

| flag | 含义 |
|---|---|
| `--source` / `--module` | **必填** |
| `--root DIR` | 外部工程根（产品 build `--root`；`--source` 须在其下） |
| `--program` / `--profile` | 透传产品 build |
| `--golden PATH` | 可选：product `{id}.aleo` exact-byte pin |
| `--run 'name args…'` | 可重复；无则只做 build pins |
| `--skip-run` | 跳过全部 run |
| `--output-dir DIR` | 保留 product OutputSet（不得已存在） |
| `--keep` | 保留工作目录 |

外部工程示例（模板 [`templates/external-aleo-hello/`](../../templates/external-aleo-hello/)）：

```bash
./scripts/aleo_local_sandbox.sh \
  --root /path/to/external-aleo-hello \
  --source src/Hello.lean \
  --module Hello \
  --run 'initialize 1u64' \
  --run 'increment 2u64'
```

步骤：

1. 解析 locked `leo`；缺失 → exit 2。
2. `PROOF_FORGE_ALEO_EMIT_LEO=1 proof-forge-next build <source> --module … --target aleo -o <out>`。
3. 在 OutputSet 中发现 **恰好一个** 主 `{id}.aleo`（排除 query-contract），并要求 `{id}.leo` + query-contract。
4. 若给了 `--golden`：`cmp` product ≡ golden。
5. 暂存 package：`program.json`（`program={id}.aleo`）+ `src/main.leo` ← product `{id}.leo`。
6. `leo build --offline`；`cmp` `build/main.aleo` ≡ product Instructions。
7. 对每个 `--run` 执行 `leo run --offline`（local-dev key 仅隔离 HOME；不写用户密钥）。

## 6. 与其它入口关系

| 入口 | 角色 |
|---|---|
| `aleo_local_sandbox.sh` | **通用** 本机 sandbox：build → pins → optional offline run |
| `just aleo-sandbox -- <args…>` | 同上；**须**传 `--source`/`--module` |
| `proof-forge-next local --target aleo` | 产品薄包装（默认 mode=sandbox） |
| `just aleo-runtime` | IR-7 honesty：无 snarkVM → `PF-TOOLCHAIN-MISSING` |
| `just aleo-network` / network wrapper | 链上 deploy/execute + 独立 receipt（另一维） |

## 7. 注册与 CI

- `just aleo-sandbox` 注册；**不**加入 ordinary `ci` / `dev-check`。
- ordinary smoke 仅验证：usage fail-closed、缺工具 `PF-TOOLCHAIN-MISSING`、CLI wrapper 拒 signer 参数。
- 真实 locked-Leo offline run 仍 host-heavy、独立执行。

## 8. SDK / MCP

- SDK：`ProofForgeClient.local(target="aleo", mode="sandbox", script_args=[...])` 透传本脚本参数。
- MCP：`pf_local` 工具映射 `local --target …`；**拒** network/broadcast/private-key；Aleo sandbox 须 `source`+`module`。
- 均 **不** 改 `deployable`；成功 **不** 等于 formal / 主网。
