---
id: PRODUCT-EXTERNAL-PROGRAM-V1
title: External ProgramV1 project guide (build / sandbox / SDK / MCP)
status: draft
owner: product+engineering
updated: 2026-08-09
normative: false
---

# 外部 ProgramV1 工程：写合约 → build → 本机 sandbox

状态：`draft`（2026-08-09；external ProgramV1 engineering closeout）  
前置：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)、[`../targets/09b-aleo-local-sandbox.md`](../targets/09b-aleo-local-sandbox.md)  
模板：[`templates/external-aleo-hello/`](../../templates/external-aleo-hello/)  
Workflow：`external-program-v1`（`.grok/workflows/external-program-v1.rhai`）

## 1. 权威范围与目标

本文是外部 ProgramV1 工程的产品说明权威：外部目录如何满足 source gate、如何用 `--root` + 相对 `--source` 调用 build/local sandbox，以及 SDK/MCP 对同一契约的字段映射。它不扩大 target maturity，也不替代 CLI、Aleo sandbox 或 OutputSet 规格。

作者在 **ProofForge monorepo 之外**（或拷贝模板）维护一个最小工程目录，用产品 CLI：

1. `build --target aleo` 得到 Instructions + query-contract；
2. `local --mode sandbox` / `aleo_local_sandbox.sh` 做 offline `leo run`；
3. 经 SDK / MCP 复用同一契约（给 Code Agent）。

**不要求** 外部工程 `require` Lake 包 `proof-forge-next`。产品 `build` 路径是进程内
`IO.FS.readFile` → Loader，不是 `lake build` 用户包。

Closeout honesty（本切片）：**engineering done** for external source tree + `--root` build, generic Aleo offline sandbox wiring, SDK/MCP field mapping, and template smoke. Product build remains **`deployable=false`**; sandbox is **offline Leo only**; MCP has **no network/broadcast tool**; formal/release evidence remains out of scope.

## 2. 源文件契约

| 规则 | 说明 |
|---|---|
| 文件扩展名 | `.lean` |
| 必填首行门 | 源文本须 **exact** 含 `import ProofForgeV2`（产品 gate；非 Lake 解析） |
| 程序形状 | 统一 `program Name where …`（用户不写顶层 kind） |
| `--source` | 相对 `--root` 的规范相对路径（如 `src/Hello.lean`） |
| `--module` | 必填 pure Lean module 标识（可与 program 名不同；模板用 `Hello`） |
| `--root` | 外部工程根；省略时默认 CLI CWD / 包根（见 CLI 规格） |

最小 Hello 见模板 `src/Hello.lean`（UInt64 counter：`init` / `entry increment` / `view get`）。

## 3. 推荐目录

```text
my-dapp-contracts/           # --root
  README.md
  src/
    Hello.lean              # import ProofForgeV2 + program Hello where …
  out-aleo/                 # build -o（gitignore）
```

从 monorepo 拷贝：

```bash
cp -a templates/external-aleo-hello /path/to/my-dapp-contracts
```

## 4. 命令阶梯（Aleo）

```bash
export PF=/path/to/proof_forge
export PROOF_FORGE_CLI=$PF/.lake/build/bin/proof-forge-next
export PROJ=/path/to/my-dapp-contracts

# 0) doctor / install (from package root)
(cd "$PF" && "$PROOF_FORGE_CLI" doctor --target aleo --json)
(cd "$PF" && "$PROOF_FORGE_CLI" install --targets aleo --yes)

# 1) build
"$PROOF_FORGE_CLI" build src/Hello.lean \
  --module Hello --target aleo --root "$PROJ" -o "$PROJ/out-aleo"

# 2) inspect
"$PROOF_FORGE_CLI" inspect --output-dir "$PROJ/out-aleo" --json

# 3) local sandbox (generic, offline Leo only)
"$PROOF_FORGE_CLI" local --target aleo --mode sandbox -- \
  --root "$PROJ" --source src/Hello.lean --module Hello \
  --run 'initialize 1u64' --run 'increment 2u64'
```

Aleo Final 表面入口名在 materialize 后为 `initialize` / `increment`（与 DSL `init`/`entry`
对应；以生成的 `.aleo` / Leo debug 为准）。

## 5. SDK / MCP

| 面 | 用法 |
|---|---|
| SDK | `ProofForgeClient.local(target="aleo", root=…, source=…, module=…, runs=[…])` |
| MCP | `pf_local` 同名字段；**拒** broadcast / private-key |
| 构建 | `pf_build` / `client.build` 亦须 `root` 当源不在 monorepo 时 |

Agent 剧本（hello）：

1. `pf_doctor`（target=aleo）  
2. `pf_install`（targets=[aleo], yes）  
3. 写/改 `src/Hello.lean`  
4. `pf_build` 或 `pf_local`（sandbox + runs）  
5. `pf_artifacts` 看 OutputSet  

**不要**经 MCP 广播 network；MCP-V0 intentionally exposes no network demo or deployment action.

## 6. 非目标

- 不要求外部工程作为 Lake SDK package 依赖 `proof-forge-next`；CLI source gate 已足够
- 不提供完整 Lean IDE 插件 / 语法高亮包（可后续）
- 不把 monorepo `Examples` 设为 sole 外部入口
- 不设 `deployable=true`、不 formal、不主网
- 不在 ordinary `just ci` 跑 host-heavy sandbox（smoke 用拷贝模板 + skip-run / 缺工具路径）
- 不经 MCP 做 network deploy/execute；network demo 必须使用显式 CLI network wrapper + owner-provided endpoint/key outside this slice

## 7. 聚焦门

| 命令 | 作用 |
|---|---|
| `scripts/external_hello_smoke.sh` | 拷贝模板到临时目录 → build aleo → optional sandbox skip-run / run |
| `just external-hello-smoke` | 同上 |

## 8. 成熟度

| 层 | 状态 |
|---|---|
| 外部源 + `--root` build | **engineering done**（本切片） |
| 通用 sandbox + `--root` | **engineering done** |
| 模板 Hello offline run | **host-heavy verified** on locked Leo 4.0.2 |
| MCP / SDK external root fields | **engineering done**（no network broadcast） |
| Multi-chain frontend catalog | **remaining**（future product UX/catalog work） |
| Network demo | **remaining**（explicit CLI network receipt path only; no MCP network） |
| Lake syntax package | **optional remaining**（not required for product build/local） |
| Formal / release | **remaining last** |
