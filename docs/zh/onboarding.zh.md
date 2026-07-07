# 贡献者入职指南

本页给出从干净 checkout 到可用本地开发循环的最短路径。重点是实用：先安装共享工具，
跑最小门禁；只有在处理某个具体 target 时，再安装该 target 的专用工具。

## 当前产品重点

Gate P0 已经关闭，主三链完成规约（D-045）的三个优先 target 已经按以下顺序达到
production-grade 的本地/CI 门禁：

1. `solana-sbpf-asm`
2. `evm`
3. `wasm-near`

下一条硬化主线是 CLI M3/M4：从 legacy flags 迁移到
`proof-forge build|emit|check --target ...`。Tier-1 target 已经具备排期资格，
但除非遇到安全或 CI 维护问题，否则应排在这次 CLI cleanup 之后。

## 必需工具

日常开发需要安装：

- `elan`，使用仓库里的 `lean-toolchain` 锁定版本。
- `just`，本地开发和 CI 共用的命令目录。
- `python3`，用于文档和验证脚本。
- Rust/Cargo，用于统一 testkit 和若干 target harness。

推荐编辑器设置：

- VS Code 或 Cursor，并安装官方 `leanprover.lean4` 扩展。
- 仓库已经包含 `.vscode/extensions.json` 和 `.vscode/settings.json`，会自动推荐
  Lean 扩展、TOML 语法支持，并排除 `.lake`、`build`、`target` 等噪声目录的搜索/监听。
- scaffold 出来的 portable 项目也会复制同一套 `.vscode` 推荐和
  `proof-forge check` task 配方。
- 打开仓库根目录，而不是子目录，这样 Lake、import 和 `lean-toolchain` 才会稳定解析。
- 让扩展通过 `elan` 使用仓库工具链；不要在 workspace 里手动覆盖 Lean 版本。

## Starter 模板

最小的编写循环可以从仓库内 portable 模板开始：

```sh
lake env lean templates/portable-counter/Counter.lean
```

模板位于 [templates/portable-counter](../../templates/portable-counter/README.md)。它使用
`ProofForge.Contract.Source`，不导入 EVM、Solana 或 NEAR SDK。目标选择属于 CLI 配置：
`--target evm`、`--target solana-sbpf-asm`、`--target wasm-near` 等。独立
package scaffold 以及任意 `contract_source` 文件通过所有 target-first `build` 路径的路由
仍是开放的 DX/source-routing 项；在公开 SDK/package 边界稳定前，模板先保持为仓库内模板。

## 第一次本地检查

```sh
elan show
lake build
just --list
just check
scripts/i18n/check-sync.sh
git diff --check
```

`just check` 是常用的快速门禁。它运行 CI 期望的通用 build、诊断、覆盖率和 smoke
切片，但不要求安装每一个 live-chain 工具。

使用 `proof-forge check --target <id> [--fixture <id>|input.lean]` 可以在构建制品前验证
capability 支持和 lowering。传入 `--report-format json` 可以得到机器可读诊断，
适合编辑器集成和 smoke validator 使用。

## Target 专用工具

只在处理对应 target 或门禁时安装：

| Target 范围 | 工具 |
|---|---|
| EVM | Foundry（`cast`, `forge`）、`solc` |
| Solana | `sbpf`、Solana CLI、`solana-keygen`、用于 Rust live harness 的 Cargo、用于 live local tests 的 Surfpool；Node/npm 仅用于生成的 JS client 检查 |
| Wasm/NEAR | `wat2wasm`；只有 live deployment 工作需要 NEAR sandbox |
| Psy/DPN | `psyup`、`dargo` |
| Aleo | `leo` |
| Cloudflare Workers | Node/npm、`wrangler` |

权威命令列表和前置条件见 [validation-gates.md](validation-gates.md)。如果缺少某个工具，
许多脚本会跳过对应的可选分支，但仍会验证生成源码、元数据或诊断。

## 工作规则

- 改代码前，先读 [development-standards.md](development-standards.md) 以及被触及边界最近的真值来源文档。
- 英文工程文档是权威来源。中文 `.zh.md` 翻译在 `main` 上从英文文档同步。
- 如果更改公共 CLI flag、target id、capability id、artifact 字段、验证命令、target 生命周期阶段或示例行为，必须在同一次更改里更新对应文档。
- 先跑窄门禁，再跑 `just check`；只有当变更触及某个 target 时，再跑更宽的 target gates。
