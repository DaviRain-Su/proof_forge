---
id: SPEC-CLI-DEV-001
title: Developer CLI `pf` contract
status: proposed
owner: cli
updated: 2026-08-10
normative: true
---

# Developer CLI `pf` 契约

Authority: [ADR-0037](../adr/0037-developer-cli-pf.md).  
Compiler CLI 契约仍见 [SPEC-CLI-001](cli.md)（`proof-forge-next` only）。

## 1. 角色

`pf` 是 **Developer CLI**：面向人类开发者的本地/网络工作流编排器。

| 做 | 不做 |
|---|---|
| spawn `proof-forge-next` 做 build/check/inspect/doctor/install | 解析/类型检查 ProgramV1 |
| 读 `proof-forge.output.v1` | 改写 `deployable` / maturity |
| wrap 官方链工具（Aleo: Leo） | 默认广播交易 |
| Aleo local run / deploy-save / execute-save | mainnet 第一期 |
| 稳定 JSON + 人类输出 | 托管私钥钱包文件格式（第一期） |

可执行文件名固定 **`pf`**。package 名 `proof-forge-pf`。

## 2. 全局选项与环境

| 项 | 含义 |
|---|---|
| `--json` | 成功/失败结构化对象到 stdout；日志 stderr |
| `--yes` / `-y` | 非交互确认（仍不能绕过 mainnet 拒绝与缺 key） |
| `PROOF_FORGE_CLI` | `proof-forge-next` 绝对路径 |
| `PROOF_FORGE_ROOT` | monorepo/package root（含 scripts/ 时用于 doctor/install） |
| `PROOF_FORGE_TOOL_ROOT` | Tool Lock 根（无 PATH fallback 写入） |
| `PROOF_FORGE_ALEO_LEO` | 可选 Leo 覆盖 |

缺 `PROOF_FORGE_CLI` 时解析顺序：`env` → 与 `pf` 同目录 `proof-forge-next` →
`$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next` → error。

## 3. 命令面（v0 / Aleo-first）

```text
pf setup --target <id> [--yes]
pf doctor [--target <id>]... [--json]
pf build --target <id> --module <Lean.Name> <source>
        [--root <dir>] [-o <out>] [--profile <id>] [--json]
pf check --module <Lean.Name> <source> [--root <dir>] [--json]
pf inspect --artifact <out-dir> [--json]
pf local run --target aleo --artifact <out-dir> -- <fn> [inputs...]
pf deploy --target aleo --artifact <out-dir>
          --network testnet|devnet [--endpoint <url>]
          [--broadcast] [--private-key-env <NAME>] [--save <dir>] [--json]
pf execute --target aleo --artifact <out-dir>
           --network testnet|devnet [--endpoint <url>]
           [--broadcast] [--private-key-env <NAME>] [--save <dir>] [--json]
           -- <fn> [inputs...]
pf version
pf list-targets [--json]
```

### 3.1 语义摘要

| 命令 | 行为 |
|---|---|
| `setup` | `doctor`；若缺工具则 `proof-forge-next install --targets … --yes`（Aleo zero-tool 可仅检查 leo host 可选） |
| `build` | spawn compiler build；校验 OutputSet 存在 `*.aleo`（aleo） |
| `local run` | Aleo Wave-B：imports 钉扎 PF bytecode → `leo run --offline` |
| `deploy` | 默认 save-only；twin exact-match 后 `leo deploy --save` |
| `execute` | 默认 save-only；`leo execute --save`（可 `--skip-execute-proof`） |

### 3.2 网络安全门禁

1. `--network mainnet` → exit 2（第一期硬拒绝）。
2. 无 `--broadcast` → 不得向网络提交；输出须标明 `broadcast=false`。
3. `--broadcast` 需要 `--private-key-env`（或文档化的等效显式源）；禁止从 CWD 默读 keypair 文件。
4. well-known Leo local-dev private key + `--broadcast` → exit 2。
5. 不得把 private key 写入 JSON 成功对象、artifact manifest 或 acceptance 副本。

### 3.3 Exit codes

| Code | 含义 |
|---|---|
| 0 | 成功；或 host-optional 工具/endpoint 缺失且命令定义为 skip-clean（须 stdout/stderr 标明 skipped） |
| 1 | 工具在场但业务/验证失败 |
| 2 | usage / 配置 / 安全门禁（mainnet、缺 key、broadcast 策略） |

与 compiler CLI 对齐：usage=2。

## 4. Aleo adapter 不变量

### 4.1 Artifact

- 输入：`proof-forge.output.v1` 目录。
- 必须存在恰好一个 primary `*.aleo`（非 `*.aleo-query-contract.json`）。
- profile 期望 `aleo-instructions-v1`；其它 fail closed。
- `deployable` 字段若存在且为 true，**不** 被 `pf` 当作可主网广播许可；仍受 §3.2 约束。

### 4.2 Local run

1. 解析 artifact 中 program id（`program foo.aleo;`）。
2. 创建 ephemeral Leo runner + `leo add --local` metadata dep。
3. `cp` PF `.aleo` → `runner/build/imports/{id}.aleo`。
4. `leo run --offline --network testnet --endpoint http://127.0.0.1:9 --network-retries 0 \
   {id}.aleo::{fn} {inputs…}`。
5. post-check：imports 文件 sha256 == PF artifact sha256。

### 4.3 Deploy / execute packaging

因 `leo deploy` 重编译 package src：

1. 仅当 PF 程序与 **登记的 structural twin 模板** exact-match（program id 改写后）才允许 packaging。
2. v0 登记 twin：`Examples/StateCell` 形状（`assert(!initGuard)` + increment dropped re-read）。
3. 其它 PF 程序：`pf deploy` fail closed，提示扩展 twin 目录或使用 save 研究路径——**禁止** silent 近似。
4. deploy 交易 JSON 必须内嵌与 twin/PF 一致的 `not`/mapping 形态（验收可 grep）。

StateCell twin 源形态（规范钉）：

```text
initialize: get.or_use initialized; assert(!r1); set state; set guard
increment:  get state; add; set; get.or_use again (dropped)
```

### 4.4 官方工具

- 解析 Leo：`PROOF_FORGE_ALEO_LEO` → `PROOF_FORGE_TOOL_ROOT/leo` → cache tool-root →
  `~/.cargo/bin/leo`（host-optional；**不** 写入 Tool Root）。
- 不实现第二套 Aleo VM。

## 5. JSON 成功对象（最小）

```json
{
  "schema": "proof-forge.pf.result.v1",
  "command": "deploy",
  "ok": true,
  "target": "aleo",
  "network": "testnet",
  "broadcast": false,
  "artifactDir": "...",
  "saved": [".../x.deployment.json"],
  "notes": ["deployable not rewritten", "not formal"]
}
```

失败：

```json
{
  "schema": "proof-forge.pf.result.v1",
  "command": "deploy",
  "ok": false,
  "error": { "code": "PF-DEV-MAINNET-REFUSED", "message": "..." }
}
```

## 6. 非目标（v0）

- EVM/Solana deploy（adapter stub 可存在，命令 fail closed with “not implemented”）。
- MCP 暴露 broadcast。
- 交互式钱包 UI。
- 把 acceptance scripts 删除（CI 仍用 scripts 或 `pf` 的 `--gate` 模式）。

## 7. 测试

| 层 | 内容 |
|---|---|
| unit | safety gates、artifact parse、program id rewrite |
| integration | `pf build` against built `proof-forge-next`（host） |
| host-optional | `pf local run` / `pf deploy` save-only（需 leo + network） |
| CI ordinary | 不强制 leo/network；unit + clap smoke |

## 8. 版本

- CLI semver 随 `clients/pf-cli` package version。
- `pf version` 打印 pf version + 解析到的 `proof-forge-next --help` 首行（若可得）。