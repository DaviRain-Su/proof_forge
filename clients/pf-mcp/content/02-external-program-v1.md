---
id: PRODUCT-EXTERNAL-PROGRAM-V1
title: External ProgramV1 project guide (build / SDK / MCP)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# 外部 ProgramV1 工程：写合约 → build → inspect

状态：`draft`（2026-08-10；external ProgramV1 build surface）
前置：[`01-toolchain-install-surface.md`](01-toolchain-install-surface.md)

## 1. 权威范围与目标

本文说明外部目录如何满足 source gate、如何用 `--root` + 相对 `--source` 调用 build，
以及 SDK/MCP 对同一 build/inspect 契约的字段映射。它不扩大 target maturity，也不替代
CLI、Aleo target 或 OutputSet 规格。

作者在 **ProofForge monorepo 之外**维护一个最小工程目录，用产品 CLI
`build --target aleo` 得到 canonical Instructions + query-contract，再经 `inspect`、SDK 或 MCP
复用同一 OutputSet 契约。Aleo 没有 Leo sandbox/runtime/network 产品 lane。

**不要求** 外部工程 `require` Lake 包 `proof-forge-next`。产品 `build` 路径是进程内
`IO.FS.readFile` → Loader，不是 `lake build` 用户包。

Closeout honesty：external source tree + `--root` build 与 SDK/MCP build 字段映射已接线。Aleo profile 是 zero-tool `aleo-instructions-v1`，保持 **`deployable=false`**；无本地执行、网络广播或 formal/release 声明。

## 2. 源文件契约

| 规则 | 说明 |
|---|---|
| 文件扩展名 | `.lean` |
| 必填首行门 | 源文本须 **exact** 含 `import ProofForgeV2`（产品 gate；非 Lake 解析） |
| 程序形状 | 统一 `program Name where …`（用户不写顶层 kind） |
| `--source` | 相对 `--root` 的规范相对路径（如 `src/Hello.lean`） |
| `--module` | 必填 pure Lean module 标识（可与 program 名不同；模板用 `Hello`） |
| `--root` | 外部工程根；省略时默认 CLI CWD / 包根（见 CLI 规格） |

最小 Hello 是一个 UInt64 counter：`init` / `entry increment` / `view get`。

## 3. 推荐目录

```text
my-dapp-contracts/           # --root
  README.md
  src/
    Hello.lean              # import ProofForgeV2 + program Hello where …
  out-aleo/                 # build -o（gitignore）
```


## 4. 命令阶梯（Aleo direct Instructions）

```bash
export PF=/path/to/proof_forge
export PROOF_FORGE_CLI=$PF/.lake/build/bin/proof-forge-next
export PROJ=/path/to/my-dapp-contracts

# 0) doctor（Aleo 为 zero-tool target）
(cd "$PF" && "$PROOF_FORGE_CLI" doctor --target aleo --json)

# 1) build
"$PROOF_FORGE_CLI" build src/Hello.lean \
  --module Hello --target aleo --root "$PROJ" -o "$PROJ/out-aleo"

# 2) inspect
"$PROOF_FORGE_CLI" inspect --output-dir "$PROJ/out-aleo" --json
```

生成的 `.aleo` 是 canonical Aleo Instructions 制品；query descriptor 只描述 network-state 查询契约。
产品不调用 Leo、snarkOS 或其它本地/网络 runtime。

## 5. SDK / MCP

| 面 | 用法 |
|---|---|
| SDK | `client.build(..., target="aleo", root=…)` 后读取 OutputSet manifest |
| MCP | `pf_build` 后用 `pf_artifacts` 检查 exact disk closure |

Agent 剧本：

1. `pf_doctor`（target=aleo；预期 zero-tool `ok`）
2. 写/改 `src/Hello.lean`
3. `pf_build`
4. `pf_artifacts` 看 OutputSet

MCP-V0 不暴露 Aleo local/network action。

## 6. 非目标

- 不要求外部工程作为 Lake SDK package 依赖 `proof-forge-next`；CLI source gate 已足够
- 不提供完整 Lean IDE 插件 / 语法高亮包（可后续）
- 不把 monorepo `Examples` 设为 sole 外部入口
- 不设 `deployable=true`、不 formal、不主网
- 不提供 Aleo compiler、local runtime、network deploy/execute 或其 fallback

## 7. 聚焦门

外部模板复用 ordinary product build/inspect smoke；不再有 Aleo-specific external sandbox recipe。

## 8. 成熟度

| 层 | 状态 |
|---|---|
| 外部源 + `--root` build | **engineering done** |
| Direct Instructions + query descriptor | **engineering done** |
| MCP / SDK external root fields | **engineering done** |
| Local/compiler/network runtime | **removed / unsupported** |
| Lake syntax package | **optional remaining**（not required for product build） |
| Formal / release | **remaining** |
