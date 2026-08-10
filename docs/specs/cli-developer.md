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
| wrap 官方链工具（Aleo: Leo；Solana: solana-client verify） | 默认广播交易 |
| Aleo local run / deploy-save / execute-save | mainnet 第一期 |
| Solana offline `pf verify`（OutputSet self-consistency） | Solana/EVM network deploy（v0） |
| EVM local `pf test`（Anvil via `scripts/pf_evm_test.sh`） | 全量 differential corpus / forge 框架替代 |
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
| `PROOF_FORGE_SOLANA_CLIENT` | 可选 `proof-forge-solana-client` 覆盖（`pf verify -t solana`） |

缺 `PROOF_FORGE_CLI` 时解析顺序：`env` → 与 `pf` 同目录 `proof-forge-next` →
`$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next` → error。

## 3. 命令面（v0 / Aleo-first，cargo-like）

项目文件：`pf.toml`（`pf new` 生成）。默认 target=`aleo`，默认输出=`build/<target>/`。

### 3.0 依赖模型（与 Cargo/Lake 的差异）

外部合约工程 **不是** Lake package，**不** `require proof-forge-next` 作为 Lean 库。

| 依赖 | 声明位置 | 运行时含义 |
|---|---|---|
| 编译器产品 | `[dependencies] compiler = "proof-forge-next"` | `pf` spawn 该二进制 |
| 语言/DSL 门 | `[dependencies] language = "ProofForgeV2"` | 源文件必须含 exact `import ProofForgeV2`（**文本 gate**，非 Lake 解析） |
| 二进制路径 | `PROOF_FORGE_CLI` 或 `[toolchain].compiler-path` | 找到 `proof-forge-next` |
| 可选 monorepo root | `PROOF_FORGE_ROOT` / `[toolchain].root` | doctor/install 包根 |
| 可选 host SDK | Python `proof-forge-sdk` | **不**写进合约 `pf.toml`；给 Agent/脚本用 |

`import ProofForgeV2` / `open ProofForgeV2.Language` 看起来像 Lean import，在外部
`pf build` 路径上只是 **source gate + DSL 语法标记**；真正的编译语义在
`proof-forge-next` 进程内 Loader，不在用户 Lake 依赖图里。

```text
pf new <name> [--target aleo]
pf build [-t <target>] [-o <out>]          # 读 pf.toml；可省略 source/module
pf check
pf run -- <fn> [inputs...]                 # = local run；默认 build/<target>/
pf inspect
pf verify [-t solana] [--artifact DIR] [--adapter transfer-sol-v1]
pf test   [-t evm|solana|aleo|evm,solana] [--artifact DIR]
pf deploy [-n testnet|devnet] [--broadcast] [--private-key-env NAME]   # Aleo only
pf execute [-n …] [--broadcast] -- <fn> [inputs...]
pf doctor | pf setup [--target …] [--yes] | pf version | pf list-targets
```

仍支持显式 monorepo 路径（无 pf.toml 时）：

```text
pf build <source.lean> --module <Lean.Name> -t aleo -o build/aleo
```

### 3.1 语义摘要

| 命令 | 行为 |
|---|---|
| `setup` | `doctor`；若缺工具则 `proof-forge-next install --targets … --yes`（Aleo zero-tool 可仅检查 leo host 可选） |
| `build` | spawn compiler build；校验 OutputSet 存在 `*.aleo`（aleo） |
| `local run` | Aleo Wave-B：imports 钉扎 PF bytecode → `leo run --offline` |
| `verify` | **Solana only（D7a）**：spawn `proof-forge-solana-client verify-artifacts`；offline，无 RPC/wallet/deploy |
| `test` | 单/多 target（`-t evm,solana`）；EVM Anvil / Solana Mollusk / Aleo leo smoke；统一 report；skip ≠ pass |
| `setup` | doctor checklist + 可选 `proof-forge-next install --yes`；打印短路径 next steps |
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

## 4.5 Solana offline verify（D7a）

1. 仅 `target=solana`；`aleo` → 指引 `pf inspect`；`evm` → not implemented（D7c）。
2. 默认 artifact：`build/solana/`（或 `--artifact`）。
3. 解析 client：`PROOF_FORGE_SOLANA_CLIENT` → 与 `pf` 同目录 →  
   `$PROOF_FORGE_ROOT/clients/solana-client/target/{release,debug}/proof-forge-solana-client` →  
   cwd monorepo 同路径 → `PATH`。
4. spawn：`verify-artifacts --artifact-dir <dir> [--program-adapter <id>]`。
5. client 非 0 或 JSON `ok=false` → fail closed（exit 1）；**禁止**静默降级为成功。
6. 非声称：不是 formal、不是 hermetic、不是 network-write、不是 Mollusk 执行（D7b）。
7. 金样 fixture：`Examples/TransferSol`；部分 generic CPI 产物可能在 evidence.note irDigest join 上失败——保持 FC。

## 4.6 EVM local Anvil test（D7c）

1. `target=evm`；默认 artifact：`build/evm/`（或 `--artifact`）。
2. 解析脚本：`PROOF_FORGE_EVM_TEST_SCRIPT` → `$PROOF_FORGE_ROOT/scripts/pf_evm_test.sh` → cwd/parents。
3. 工具：`PROOF_FORGE_TOOL_ROOT` / `FOUNDRY_BIN` 下 locked `anvil`+`cast`（禁止把 PATH 乱装进 lock）。
4. 矩阵（StateCell 形）：constructor(7) → get=7 → eth_call increment(5)=12 且不提交 → send increment → get=12 → overflow hold。
5. 缺工具：exit 0 + `skipped:`（host-optional，**不是 pass 声称**）；工具在场断言失败 → exit 1。
6. 非声称：不是 formal、不是 mainnet、不是全量 differential corpus。

## 4.7 Solana Mollusk test（D7b）

### 开发者短路径（规范）

```text
pf new hello --target solana
cd hello
pf build          # → build/solana/  （读 pf.toml，无 --module/-o）
pf test           # 默认 StateCell-shaped Mollusk
```

### 实现

1. `target=solana`；默认 artifact：`build/solana/`（或 `--artifact`）。
2. 脚本：`scripts/pf_solana_test.sh`（`PROOF_FORGE_SOLANA_TEST_SCRIPT` 可覆盖）。
3. **默认 lane — StateCell-shaped（通用）**  
   - 任意 `artifactProgramName`（`Hello` / `Counter` / `StateCell` …）  
   - IDL：`init|initialize` + `increment` + `get`，`exactDataLen=16`  
   - spawn：`cargo test --test state_cell_shaped_product`  
   - env：`PROOF_FORGE_SOLANA_TEST_OUT=<artifact>`
4. **专项 lane — TransferSol CPI gold（自动探测）**  
   - 当 artifact 为 TransferSol 时改走 `transfer_sol_product`  
   - env：`PROOF_FORGE_TRANSFER_SOL_OUT`  
   - **不是** 默认开发者路径；文档 monorepo 长命令仅 CI/维护用。
5. 其它形状：fail closed（指引改模板或 `pf verify`）。
6. 缺 cargo / runtime-tests：skip-clean；在场失败 → exit 1。
7. 非声称：不是 formal / mainnet / 全量 19-program corpus / RPC。

### `pf verify` 与 `pf test` 分工

| 命令 | 通用性 | 说明 |
|---|---|---|
| `pf test -t solana` | StateCell-shaped **通用** | 本地 Mollusk 执行差分 |
| `pf verify -t solana` | offline joins | 部分 generic CPI 可能 irDigest note 失败（FC）；TransferSol 为 client 金样 |

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

`pf verify` 成功对象额外：

```json
{
  "schema": "proof-forge.pf.result.v1",
  "command": "verify",
  "ok": true,
  "target": "solana",
  "artifactDir": "...",
  "extra": {
    "client": ".../proof-forge-solana-client",
    "programAdapter": "transfer-sol-v1",
    "result": { "ok": true, "programName": "TransferSol", "...": "..." }
  },
  "notes": [
    "offline OutputSet self-consistency only",
    "not formal/hermetic/network-write",
    "deployable not rewritten"
  ]
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

## 4.8 Multi-target `pf test` report（D8）

成功 JSON（单或多 target）`extra`：

```json
{
  "targets": ["evm", "solana"],
  "summary": { "total": 2, "ok": 1, "skipped": 1, "failed": 0, "notImplemented": 0 },
  "results": [
    { "target": "evm", "status": "ok", "lane": "anvil-statecell", "artifactDir": "…", "message": "…" },
    { "target": "solana", "status": "skipped", "lane": "state-cell-shaped", "message": "…" }
  ]
}
```

规则：`status=failed|not_implemented` → 进程非零；全 `skipped` → 零但 human 标明非 pass。

## 4.9 Setup / 分发（D9）

- `pf setup`：见 `clients/pf-cli/INSTALL.md`
- `just pf-cli-dist` → `build/dist/pf-<os>-<arch>/` 并排 `pf` + `proof-forge-next`

## 4.10 Twin registry（D10）

- 登记 id 列表：`statecell-v1`（唯一 materializer）
- 未知形状 → deploy fail closed；禁止 silent 近似

## 6. 非目标（v0）

- EVM/Solana **network** deploy（**D11 deferred**；`pf deploy` Aleo-only）。
- MCP 暴露 broadcast。
- 交互式钱包 UI。
- 把 acceptance scripts 删除（CI 仍用 scripts 或 `pf` 的 `--gate` 模式）。
- GitHub Release 自动上传（dist 脚本已有；CI 接线可选）。

## 7. 测试

| 层 | 内容 |
|---|---|
| unit | safety gates、artifact parse、program id rewrite、solana client resolve |
| integration | `pf build` against built `proof-forge-next`（host） |
| host-optional | `pf local run` / `pf deploy` save-only（需 leo + network） |
| host-optional | `pf verify -t solana` on TransferSol（需 solana-client binary） |
| host-optional | `pf test -t evm` on StateCell（需 locked anvil/cast） |
| host-optional | `pf test -t solana` on TransferSol（需 cargo + mollusk deps） |
| CI ordinary | 不强制 leo/network/solana-client/anvil/mollusk；unit + clap smoke |

## 8. 版本

- CLI semver 随 `clients/pf-cli` package version。
- `pf version` 打印 pf version + 解析到的 `proof-forge-next --help` 首行（若可得）。