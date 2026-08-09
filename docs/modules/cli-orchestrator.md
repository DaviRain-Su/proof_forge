---
id: MOD-CLI-001
title: CliOrchestrator 模块规格
status: proposed
owner: cli
updated: 2026-08-07
normative: true
---

# CliOrchestrator

> **当前工程覆盖（2026-08-07）**：B11/B12 supervisor 产品层已删除。`check` / `build`
> 在进程内 **单次** `IO.FS.readFile` 后调用
> `Loader.selectProgramV1ProductWithTheoremInventory` → compile → **sole**
> `certifyInlineProofV1`（早于 target resolve/materialize）。`--proof-bundle` /
> `--proof-bundle-digest` 已删除（unknown option）；`ProofBundleV1` 仅 library。check 成功
> 输出 `proofStatus` / theorem count / certification digest；build 只门禁、不输出 proof 字段。
> proof inventory/certifier 已按 `(invariant,kind)` 接线：bare proof=holds，explicit preserving
> 选择 `PreservationTheoremV1`，kind 进入 certification identity、不进入 semantic identity。
> holds simple-closure 与 EvenCounter preserving product certified positive 均已闭合
>（2026-08-08）；第二非 AMM 实例仍 pending。JSON 不含 public
> `receipts`，也不声明 contained assurance。simple-closure/ordinal-0
> kernel cert 与 literal-true/public-Bool-view same-file ordinary theorem 的 product `check`
> certified 正例均已完成 engineering 验证；formal/reachability/target refinement 不随之关闭。
> 下文 supervised receipt 条款是尚未实现的 proposed 契约。

模块把 argv 转成 typed command，调用 frontend/semantics/resolver/materializer/artifact public
API，并渲染 human/JSON result。它不 import target Plan/IR 模块，不读取 registry 之外的 target
常量，不用 shell 拼接命令。

命令状态：`parse → validate options → invoke one service → render → exit`；每个 invocation 只
执行一个 command。stdout JSON 原子写单 object；日志 stderr；broken pipe 作为 I/O error，
不重跑副作用命令。

## Parser selection（ADR-0022 D1 / SPEC-CLI-001）

`check`/`build` 的 `--language-version` 只解析 static registry 内 exact SemVer。当前 major `1`
的 sole default 为 **`1.0.0`**（omit ≡ `1.0.0`）。orchestrator 不得实现 ranges、`latest` 或
negotiation；selection 失败映射既有 `PF-LANGUAGE-*` 诊断。`languageVersion` 不传入
ProgramV1 identity/hash/NodeId 构造。

## 规划中的 supervised public `receipts`（ADR-0022 D3）

该接口尚未由当前产品实现。若后续重新引入 supervised `check`/`build`，其 JSON object 在
**success 与 failure** 均应带顶层 **`receipts`**：bounded public-safe supervisor
projection/digest。orchestrator **不得**：

- 把 raw/full receipt、stream tails、host paths 或 secrets 写入 stdout JSON；
- 把 receipt 当作 `diagnostics[]` 元素或 diagnostic 字段；
- 把 receipt 当作 OutputSet artifact 或 artifact path；
- 以 human stderr 文本充当稳定 receipt API。

development in-process 路径若发出 observation 投影，assurance class 必须可区分
（`darwin-development-observed` 永不等于 `contained` / formal evidence；Linux `contained` 仅在
controller-bound + controller-event attribution 下成立，禁止 silent fallback）。

**当前 B8b + ADR-0027 engineering：** `check` / `build` 解析 canonical root-relative source path；
`CLI.Main.loadSourceProduct` 以 **一次** `IO.FS.readFile` 读入并调用
`Loader.selectProgramV1ProductWithTheoremInventory`，进入 located Normalize /
`compileProgramProductV1`，再 **`certifyInlineProofV1`**（held raw；失败 `PF-SRC-INVALID`/
exit 3 且零 staging；`noProof` → `not-required`）。随后才 TargetRegistry resolve 与
materialize。Loader/typed 失败保留 full `DiagnosticBundleV1` 并统一 `selectExitCode`；usage 仍
exit 2。产品 JSON 不含 `receipts`；check 可观测 proof 字段，build 成功输出不带 proof 字段。
16 MiB gate 由 Loader 在读入后执行。formal executable identity、supervised `receipts`、
controller containment、formal `TST-PROOF-001`、reachability 与 target refinement 仍
out of scope；narrow product same-file ordinary-theorem check positive 已由 CLI suite 覆盖。

覆盖全部命令/flags（含 **已删除** `--proof-bundle*` 为 unknown）、multi-program、unknown
target/profile/network、exit priority、JSON/human、TTY、signals、private file/FD、build network
prohibition、inline proof fail-closed、output force、parser default `1.0.0`、supervised
`receipts` 形状。关联 `SPEC-CLI-001`、`SPEC-DIAG-001`、`ADR-0022`、`ADR-0027`、`TASK-D3-06`、
`TST-CLI-*`、`TST-PROOF-INLINE-E1`。
