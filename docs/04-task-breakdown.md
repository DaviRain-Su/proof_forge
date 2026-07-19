---
id: PHASE-4
title: 实施任务拆解
status: accepted
owner: engineering
updated: 2026-07-19
normative: true
approvers: architecture-owner, davirain, quality-owner
approvedAt: 2026-07-19
reviewCommit: cda99d931ab02f063302cfa82861871bddee93e8
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/cda99d931ab02f063302cfa82861871bddee93e8
openFindings: none
---

# Phase 4：实施任务拆解

每项预计不超过四小时；先完成对应 `TST-*` 骨架，再实现。状态仅用 `pending`、
`in_progress`、`blocked`、`done`，同一时刻只能有一项 `in_progress`。
表中依赖是任务完成依赖；前置任务未完成时可以收集明确标注的 pre-acceptance evidence，
但不能据此把正式任务标为 `done`。

> **2026-07-17：** `TASK-D0-01` 经 `FX-2026-07-17-D0-01` 关闭为 `done`（pure consumer +
> docs-check；protected production positive 移交 D0-04）。`TASK-D0-02` 曾因缺受保护的 bootstrap
> TaskApproval/receipt 而 `blocked`；现经 `FX-2026-07-17-D0-02` 以 development package-boundary
> 切片记为 `done`，signed approval/receipt 仍移交 D0-04，且等待 genesis 追认生效。

## 全局任务冻结（所有 TASK，强制）

全部任务遵守 [`governance/task-freeze.md`](governance/task-freeze.md)
（`GOV-TASK-FREEZE-001`）：

1. **`pending` → `in_progress` 前**必须具备冻结完成包（output / tests / inScope /
   outOfScope / doneWhen）。  
2. **`in_progress` 与 `done` 禁止完成面变胖**（不得改 Output/Tests/Dependencies/
   Prerequisites 语义，不得在 AGENTS/checkpoint 追加“还必须…”）。  
3. **新缺口**只能：修实现、标 `blocked`、开新 task、或书面 Freeze Exception——禁止回填当前任务。  
4. **A0** 已冻结到 `TASK-A0-20`；**D0** 执行基线为 `TASK-D0-01`…`TASK-D0-08`；milestone
   增行须 Architecture + Quality 批准。  
5. 超时（默认 3 日或 20 个 task-owned commits）必须 24h 内 triage：Close / Split / Block /
   Exception。

任务选择以本文件为准，`AGENTS.md` 只镜像当前指针。新增 pre-acceptance task 必须先在本文件
说明为什么既有 Milestone 任务不能承载该工作；不得由 checkpoint 的 `Next task` 自动递增
`TASK-A0-*`。`Dependencies` 只列精确 `TASK-*` 完成依赖，禁止里程碑简称和范围简写；
非任务条件单独进入 `Prerequisites`。

## Pre-acceptance alpha checkpoint

以下任务验证设计可行性，不等同于关闭后续完整任务；`TST-A0-*` 只标识对应 alpha
验收切片，不冒充 formal milestone 的 `TST-*`；证据和限制见实现日志。A0 已冻结且不再参与
调度，历史执行先后不伪装成技术完成依赖，因此其 `Dependencies` 统一记为 `—`。

| ID | 输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-A0-01 | 文档控制面与 docs-check | — | — | TST-A0-001 | EV-20260715-0001 | done |
| TASK-A0-02 | 独立 Lake、统一 DSL/Core/需求推导最小切片 | — | — | TST-A0-002 | EV-20260715-0002 | done |
| TASK-A0-03 | 四目标 alpha artifacts 与 EVM runtime | — | — | TST-A0-003 | EV-20260715-0003, EV-20260715-0004 | done |
| TASK-A0-04 | archive isolation smoke（非完整 clean-room） | — | — | TST-A0-004 | EV-20260715-0005 | done |
| TASK-A0-05 | Lean parser 前端与独立 Typed/Semantic IR 集成 | — | — | TST-A0-005 | EV-20260715-0006, EV-20260715-0007 | done |
| TASK-A0-06 | network-denied clean-room alpha（非正式 hermetic） | — | — | TST-A0-006 | EV-20260715-0008 | done |
| TASK-A0-07 | content-addressed external tool/Mach-O closure slice | — | — | TST-A0-007 | EV-20260715-0009 | done |
| TASK-A0-08 | Host Stage-0 development attestation 与 formal-ineligible negative | — | — | TST-A0-008 | EV-20260715-0011, EV-20260715-0012 | done |
| TASK-A0-09 | strict development evidence schema/bundle/publication core | — | — | TST-A0-009 | EV-20260715-0014 | done |
| TASK-A0-10 | deny-default materialize/core/exact-local-port runtime continuation | — | — | TST-A0-010 | EV-20260715-0015 | done |
| TASK-A0-11 | evidence v1 exact-local-port 条件端口、current-reader legacy-v1 compatibility 与攻击 self-tests | — | — | TST-A0-011 | EV-20260715-0016 | done |
| TASK-A0-12 | H1e-a opt-in run/invocation contexts、canonical metadata receipt 与 single-writer receipt-last publication | — | — | TST-A0-012 | EV-20260716-0017 | done |
| TASK-A0-13 | 通用 UInt64 EvmPlan/Yul/ABI、动态 Keccak selector 与 Accumulator Anvil runtime | — | — | TST-A0-013 | EV-20260716-0018 | done |
| TASK-A0-14 | 通用 UInt64 SolanaPlan/typed audit IR/plan text/IDL 与 Accumulator artifact | — | — | TST-A0-014 | EV-20260716-0019 | done |
| TASK-A0-15 | 通用 UInt64 NearPlan/Wasm recipe/WAT 与 Accumulator artifact | — | — | TST-A0-015 | EV-20260716-0020 | done |
| TASK-A0-16 | 通用 UInt64 NoirPlan/typed relation IR/source 与 Accumulator external-state relation artifact | — | — | TST-A0-016 | EV-20260716-0021 | done |
| TASK-A0-17 | 递归 decode/type-check 前的共享 Syntax node/nesting preflight 与稳定 boundary diagnostics | — | — | TST-A0-017 | EV-20260716-0022 | done |
| TASK-A0-18 | accepted-width `Source.Program` 的线性 duplicate/name index 与 typecheck complexity regression | — | — | TST-A0-018 | EV-20260716-0023 | done |
| TASK-A0-19 | reusable Loader `ParserSession` 与 hosted `source-core` 重资源向量进程隔离 | — | — | TST-A0-019 | EV-20260716-0024 | done |
| TASK-A0-20 | Lean command/CLI Loader 共用唯一 validated decoded `Source.Program`，移除第二套 raw-Syntax AST construction | — | — | TST-A0-020 | EV-20260716-0025 | done |

本 checkpoint 截止 `TASK-A0-20` 冻结。2026-07-16 对账确认：A0 的 `done` 只表示 alpha
切片；它们不自动关闭 D0/D1。2026-07-17：`TASK-D0-01`/`TASK-D0-02`/`TASK-D0-03`/`TASK-D0-05`
经 Freeze Exception 关闭，统一由 [`governance/genesis-authority.md`](governance/genesis-authority.md)
追认；`TASK-D0-06` 的错误关闭经 reopen 纠正，在途补全后按 genesis 关闭重新关闭。

## Milestone D0：文档与独立工程

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D0-01 | 建立文档 status/ID/link/trace/task→TST→EV/checkpoint checker 与 external TaskApproval/task-receipt pure consumer（FX-2026-07-17-D0-01：candidate-external protected production positive 移交 D0-04，缺失时 fail closed 不阻塞本任务 done） | — | PHASE-1@accepted, PHASE-2@accepted, PHASE-3@accepted | TST-DOC-001 | EV-20260717-0028 | done |
| TASK-D0-02 | 建立独立 Lake package/namespace/exe（FX-2026-07-17-D0-02：package-boundary 以 isolation development gates 关闭；signed TaskApproval/authenticated receipt 移交 D0-04） | TASK-D0-01 | — | TST-ISO-001 | EV-20260717-0030 | done |
| TASK-D0-03 | 锁定 Lean/external closure、Host Profile/Stage-0、candidate/evidence core、deny-default continuation 与 exact-port schema；只交付 development evidence schema/bundle/catalog finalizer 及 formal zero-output rejection，当前 alpha 输入为 `TASK-A0-02`（FX-2026-07-17-D0-03：development triad 关闭；full policy/receipt evaluator 与 signed receipt 移交后续） | TASK-D0-01, TASK-D0-02 | — | TST-EVIDENCE-001, TST-HOST-001, TST-TOOL-001 | EV-20260717-0031 | done |
| TASK-D0-04 | 实现 bootstrap foundation：eligible Stage-0 handoff、跨 process-session containment、signed RequiredTestSet/formal-catalog authority、per-task verifier receipt/protected service，以及 six-item BootstrapApprovalSet/activation producer-consumer；owned TST 只在 pre-activation 运行，task done 另须随后取得 set+activation receipt，且二者不得回填 TST/TaskApproval/task receipt | TASK-D0-02, TASK-D0-03, TASK-D0-05, TASK-D0-06 | — | TST-BOOTSTRAP-001 | — | blocked |
| TASK-D0-05 | direct/transitive license inventory + CycloneDX 1.6 SBOM 生成、schema/closure/release binding（FX-2026-07-17-D0-05：inventory+CycloneDX development gate） | TASK-D0-03 | — | TST-SBOM-001 | EV-20260717-0033 | done |
| TASK-D0-06 | common scalar parsers、canonical encoders/domain hashes 与 ResourceProfileV1 types | TASK-D0-01, TASK-D0-02 | — | TST-COMMON-001 | EV-20260717-0035 | done |
| TASK-D0-07 | 在 current、non-revoked BootstrapApprovalSet activation 后执行正式 hermetic archive clean-room gate，并实现 formal evidence-set finalizer、freshness/private scan/revocation 与 acceptance/support-binding producer/store | TASK-D0-04 | — | TST-EVIDENCE-002, TST-ISO-002 | — | pending |
| TASK-D0-08 | SBOM↔toolchains.lock closure 重算、release binding、per-executable/per-dylib 粒度与 TST-SBOM-001 全量语义收尾 | TASK-D0-05 | — | TST-SBOM-002 | EV-20260718-0053 | done |
| TASK-D0-09 | Linux host profile schema v2/生成器/验证器、locked linux tool root（Tool Lock v3 per-platform 文件/elfPolicy/linux 资产）与 Stage-0 linux 分支；darwin 行为不变 | TASK-D0-03 | — | TST-HOST-002 | EV-20260718-0052 | done |

`TASK-D0-02` 曾因缺少候选外部 authority 才能产生的 exact signed TaskApproval 与
authenticated task receipt 而 blocked；2026-07-17 经 `FX-2026-07-17-D0-02` 以 package-boundary
关闭，signed 对象移交 `TASK-D0-04`。genesis 任务的定义、追认与补票义务见
[`governance/genesis-authority.md`](governance/genesis-authority.md)。

`TASK-D0-09` 经 [`adr/0016-cross-platform-host-profile-and-linux-eligibility.md`](adr/0016-cross-platform-host-profile-and-linux-eligibility.md)
立项（GOV-TASK-FREEZE-001 §4 R3 / §7 milestone 变更）：linux host profile 与 locked linux
tool root 是 GOV-CI-001 明示的 hermetic 前置，但 `TASK-D0-03` 已 `done` 完成面禁止变胖、
`TASK-D0-04` outOfScope 禁止扩面且 host/工具属外部前置、`TASK-D0-07` 依赖 activation 之后，
现有任务均不能承载。ADR-0016 已于 2026-07-18 经 Architecture + Quality 批准转 `accepted`，
本任务同日进入 `in_progress`（冻结包
[`task-freeze-packages/TASK-D0-09.json`](governance/task-freeze-packages/TASK-D0-09.json)，
freezeCommit `6dc1d8365c02cd51a8b3365c5199597deda99b61`）。2026-07-18：TST-HOST-002 已
RED→GREEN，linux tool-root lane 本地复跑与合并树 `just ci` 全绿（`EV-20260718-0041`、
`EV-20260718-0042`）；lane 首次真实 GitHub 运行前修复 job-env `runner` context 缺陷
（`63df5494`），随后 CI run `29642879415` 三 lane（docs/source-core/linux-tool-root）
全 success，ubuntu CI 生成器产出 ineligible development profile 并被验证器接受。
doneWhen 剩余两项一度为外部前置而 `blocked`；2026-07-18 经
[`governance/pre-cutover-closure-ruling.md`](governance/pre-cutover-closure-ruling.md)
（`GOV-PRECUTOVER-001`，Architecture + Quality 批准）关闭为 `done`：darwin 回归以
ADR-0016 字节保持设计 + 静态保持性验证（darwin lock 逐字节、profile 四字段组相等、
Stage-0 darwin 语义行全保留、数据级 v2 校验通过）认定满足，darwin live 重观察递延为
P2 债务（owner=quality，截止 `TASK-D0-07` 关闭前）；pre-cutover 关闭路径由该裁决提供，
attest `docs/governance/bootstrap-closure/TASK-D0-09.attest.json`，bootstrap EV
`EV-20260718-0052`。development 级关闭，不产生 formal/hermetic 证据。

`TASK-D0-08` 于 2026-07-18 进入 `in_progress`（counts 盘点固化后的完整冻结包
[`task-freeze-packages/TASK-D0-08.json`](governance/task-freeze-packages/TASK-D0-08.json)），
同日完成 TST-SBOM-002 RED（`904f8eb6`）与全 31 例 GREEN（`EV-20260718-0043`）：
SB2-001..031 + LEGACY-NOT-GREEN 共 32 例与 SB2-028 逐点 fault injection 全绿，
locked-jv 对 pinned CycloneDX schema 实测 schema/instance ok。doneWhen 第 1–3 条与第 5
条满足后，同日经 `GOV-PRECUTOVER-001` 确认关闭路径（第 4 条）关闭为 `done`：
attest `docs/governance/bootstrap-closure/TASK-D0-08.attest.json`，bootstrap EV
`EV-20260718-0053`。development 级关闭；formal release binding、freshness/revocation
与发布签名仍分别属 `TASK-D0-07`、`TASK-D3-05`、`TASK-D8-05`。

## Milestone D1：语言前端

### D1 pre-acceptance 执行指针（不改变正式 TASK 状态）

由于 `TASK-D0-04`/`TASK-D0-07` 的 formal authority 与 hermetic 前置尚未闭合，下面只记录
用户明确授权继续推进的 development slices，防止代码、checkpoint 与任务文档脱节。它们不是
新增 `TASK-*`，不改变冻结依赖、Tests 集合、Done 语义或下表状态，也不能单独关闭正式 D1。

| Slice | Formal task | Scope | Commits | Verification | Pointer |
|---|---|---|---|---|---|
| D1-PA-01 | TASK-D1-01 | canonical NodeId v1 preimage、63 条 parent/field 路径与拓扑/深度拒绝 | `51cce575`, `75b7a62c`, `cdeff9d3` | focused tests + `just ci` at `6dc5acaa` | complete (development) |
| D1-PA-02 | TASK-D1-01 | Lean original-parser byte span、整树 snapshot/token/boundary 防伪 | `6e559103`, `0e2013f6`, `6dc5acaa` | focused tests + independent P0/P1=0 + `just ci` | complete (development) |
| D1-PA-03 | TASK-D1-03 | `Bool` 与 `commitment` parameter 的双前端 parity、独立 support requirements 与 pre-Plan rejection | `bc8324fe`, `d174e130`, `89a611b5`, `4d4f7c79`, `b1e37b8a` | focused aggregate + dual-entry negatives + clean `just ci` green；re-review P0/P1=0 | complete (development) |
| D1-PA-04 | TASK-D1-03 | exact `Field bn254_fr` declaration grammar、独立 support requirement；其他 field identifier fail closed | `1a81418e`, `d99d67a2`, `4c4b0eb2` | focused aggregate + dual-entry negatives + clean `just ci` at `4c4b0eb2`；independent review P0/P1=0 | complete (development) |
| D1-PA-05 | TASK-D1-03 | state visibility carrier、canonical source binding 与 disclosure support envelope | `e1a61872`, `f2b3f02e`, `cf0805d3`, `be71e864` | focused aggregate + forged-resolution negative + clean `just ci` at `be71e864`；re-review P0/P1=0 | complete (development) |
| D1-PA-06 | TASK-D1-03 | event/error declaration carriers、canonical source binding 与 declaration-order duplicate rejection | `4a85ffed`, `0a348f7e`, `7ac2d531`, `481b59fb`, `795e1b45`, `3da5e09b` | focused aggregate + dual-entry negatives + clean `just ci` at `3da5e09b`；re-review P0/P1=0 | complete (development) |
| D1-PA-07 | TASK-D1-03 | struct/enum declaration carriers、canonical child binding 与 field/variant duplicate rejection | `876770e5`, `0b5767d5`, `71d10745`, `9ce2227a`, `199e54f7` | focused aggregate + dual-entry negatives + clean `just ci` at `199e54f7`；re-review P0/P1=0 | complete (development) |
| D1-PA-08 | TASK-D1-03 | const declaration carrier、canonical value binding 与 duplicate/type boundary | `1c792f72`, `cd29bf21`, `05aa1efa`, `8cc05c57` | focused aggregate + dual-entry negatives + clean `just ci` at `8cc05c57`；re-review P0/P1=0 | complete (development) |
| D1-PA-09 | TASK-D1-03 | pure fn declaration carrier、canonical signature/body binding 与 duplicate/fail-closed boundary | `0e8b82ca`, `337eedff`, `7df85988`, `ecb517da`, `c62937d1`, `419c1564`, `1c94e414`, `6c88b376` | focused aggregate + dual-entry/layout coverage + clean `just ci` at `6c88b376`；re-review P0/P1=0 | complete (development) |
| D1-PA-10 | TASK-D1-03 | invariant declaration carrier、canonical expression binding 与 duplicate/fail-closed boundary | `c635815b`, `469c4d7a`, `5b01b4bf` | focused aggregate + dual-entry negatives + clean `just ci` at `5b01b4bf`；final review P0/P1=0 | complete (development) |
| D1-PA-11 | TASK-D1-03 | extension requirement carrier、exact version/digest binding 与 duplicate/fail-closed boundary | `5d73bf65`, `5dca8069` | focused aggregate + dual-entry negatives + clean `just ci` at `5dca8069`；adversarial review P0/P1=0 | complete (development) |
| D1-PA-12 | TASK-D1-03 | proof reference carrier、exact invariant/qualified theorem binding 与 duplicate/fail-closed boundary | `105a76e2`, `fc89664e`, `751844f8`, `2a5d1b1f`, `b0c679ef` | focused aggregate + dual-entry negatives + clean `just ci` at `b0c679ef`；final review P0/P1/P2=0 | complete (development) |
| D1-PA-13 | TASK-D1-03 | entry/view/fn cross-kind callable namespace uniqueness 与 deterministic validation priority | `e8acaffa`, `9eec99dd`, `70965df3` | focused aggregate + six dual-entry exact-diagnostic vectors + clean `just ci` at `70965df3`；review P0=0，P1/P2 全关闭 | complete (development) |
| D1-PA-14 | TASK-D1-03 | 对照 frozen TST-SRC-004 做 Phase 1 declaration residual gap audit，并冻结下一个 bounded RED slice | — | 13 种 declaration kind inventory + code/test cross-check；P0=0，剩余 gap 全为 type grammar | complete (development audit) |
| D1-PA-15 | TASK-D1-03 | closed integer-width declaration types：`UInt8/16/32/128/256` 与 `Int8/16/32/64/128/256` | `d26eb71f`, `bdbdfbf8`, `db25328b` | focused aggregate + four dual-entry negatives + clean `just ci` at `db25328b`；final review P0/P1/P2=0 | complete (development) |
| D1-PA-16 | TASK-D1-03 | `Unit` declaration type carrier 与 omitted return type materialization | `dbaf9a20`, `25274210`, `a6dc9223` | focused aggregate + four dual-entry negatives + Loader bare-colon rejection + clean `just ci` at `a6dc9223`；final review P0/P1/P2=0 | complete (development) |
| D1-PA-17 | TASK-D1-03 | exact `Principal` declaration type carrier；declaration-only zero-requirement boundary | `a69cc49c`, `c7aa6746` | focused aggregate + four dual-entry negatives + clean `just ci` at `c7aa6746`；independent RED/GREEN/canonical reviews P0/P1/P2=0 | complete (development) |
| D1-PA-18 | TASK-D1-03 | bounded `Option` declaration carrier；alpha payload canonical encoding 与 transitive requirement propagation | `f6b2b2bf`, `06c56f78`, `9858ede0` | focused aggregate + dual-entry/parser-boundary negatives + clean `just ci` at `9858ede0`；final review P0/P1=0 | complete (development) |
| D1-PA-19 | TASK-D1-03 | bounded `Bytes N` declaration carrier；exact decimal `0..4096` 与 encoder-local alpha canonical payload | `4849ae5b`, `119307ea`, `7a93fb07` | focused aggregate + dual-entry/parser-boundary negatives + clean `just ci` at `7a93fb07`；final reviews P0/P1=0 | complete (development) |
| D1-PA-20 | TASK-D1-04 | bounded `let name [ : Type ] := Expr` Source statement carrier；Typed fail-closed boundary | `d815d400`, `bb3f9e27`, `bc0447f2` | focused aggregate + dual-entry/parser-boundary negatives + clean committed `just ci` at `bc0447f2`；final reviews P0/P1=0 | complete (development) |
| D1-PA-21 | TASK-D1-04 | exact `true`/`false` Source-only literal carrier；append-only Expr tag `4` 与 Typed fail-closed boundary | `175545d6`, `10159066`, `76ebc809` | focused aggregate + dual-entry/parser-boundary controls + clean committed `just ci` at `76ebc809`；final reviews P0/P1=0 | complete (development) |
| D1-PA-22 | TASK-D1-04 | binary checked subtraction Source-only carrier；`+`/`-` 同层左结合、Expr tag `5` 与 Typed fail-closed boundary | `756afdc2`, `0d97da50`, `e8c3773f` | focused 128-job aggregate + left-associative AST/sourceHash pins + parser-boundary negatives；final reviews P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-23 | TASK-D1-04 | binary checked multiplication Source-only carrier；高于 `+`/`-` 的 precedence、Expr tag `6` 与 Typed fail-closed boundary | `21a4157b`, `6b30cce4`, `2749d1c6` | focused 130-job aggregate + precedence/associativity AST/sourceHash pins + parser-boundary negatives；final reviews P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-24 | TASK-D1-04 | parenthesized expression grouping parser sugar；无新 Expr ctor/tag，等价 grouping canonical/sourceHash 不变 | `77c6b23b`, `ddaadfb6`, `d321db74` | focused 132-job aggregate + same-identity AST/canonical/hash equality + parser-boundary negatives；final reviews P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-25 | TASK-D1-04 | unary checked negation Source-only carrier；prefix precedence `75`、Expr tag `7`、既有 unary-negative pin migration 与 Typed fail-closed boundary | `009159e0`, `946b8c67`, `01739d5c`, `08a1ac29` | focused 14-job build + 134-job aggregate + exact AST/canonical/hash/comment-boundary controls；checkpoint `just ci` deferred | complete (development) |
| D1-PA-26 | TASK-D1-04 | bare `assert Expr` Source-only statement carrier；Statement tag `4` 与 Typed fail-closed boundary，optional `else Ident` 显式 deferred | `0477e089`, `a6f052d3`, `ff7a6fee`, `de45d253` | focused 14-job build + 136-job aggregate + exact AST/canonical/keyword/parser-boundary controls；checkpoint `just ci` deferred | complete (development) |
| D1-PA-27 | TASK-D1-04 | unary bitwise-not `~` Source-only carrier；prefix precedence `75`、Expr tag `8`、mixed-unary shapes 与 Typed fail-closed boundary | `6f0322d5`, `6724f120`, `0f4455ad` | focused 14-job build + 138-job aggregate + exact AST/canonical/mixed-unary/parser-boundary controls；checkpoint `just ci` deferred | complete (development) |
| D1-PA-28 | TASK-D1-04 | unary logical-not `!` Source-only carrier；prefix precedence `75`、Expr tag `9`、mixed-unary/`!=` boundary 与 Typed fail-closed | `d5395e1e`, `facae339`, `92f57f30` | focused 14-job build + 140-job aggregate + exact AST/canonical/mixed-unary/parser-boundary controls；final reviews P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-29 | TASK-D1-04 | binary checked division `/` Source-only carrier；与 `*` 同层 precedence `70` 左结合、Expr tag `10`、两条既有 negative 迁移与 Typed fail-closed | `a1415163`, `84f0f72c`, `8a00bd21`, `300b8a9c` | focused 14-job build + 142-job aggregate + exact precedence/grouping/zero/parser-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-30 | TASK-D1-04 | binary checked modulo `%` Source-only carrier；与 `*`/`/` 同层 precedence `70` 左结合、Expr tag `11`、3 suites/4 negatives 迁移与 Typed fail-closed | `84408784`, `197e412e`, `49012f57` | focused 14-job build + 144-job aggregate + exact cross-operator/grouping/zero/parser-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-31 | TASK-D1-04 | shift-left `<<` Source-only carrier；低于 AddExpr 的 precedence `60` 左结合、Expr tag `12`、zero/over-width Source boundary 与 Typed fail-closed | `97be1f2d`, `5f8766b6`, `b38e033e` | focused 14-job build + 146-job aggregate + exact additive/multiplicative/grouping/count/parser-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-32 | TASK-D1-04 | shift-right `>>` Source-only carrier；与 `<<` 同层 precedence `60` 左结合、Expr tag `13`、single retention migration 与 Typed fail-closed | `dc8b57ad`, `56f0e70c`, `29513a00` | focused 14-job build + 148-job aggregate + exact cross-shift/count/parser-boundary controls；clean committed `just ci` at `29513a00`；final review P0/P1=0 | complete (development) |
| D1-PA-33 | TASK-D1-04 | equality `==` Source-only carrier；低于 ShiftExpr 的 precedence `50` non-associative、Expr tag `14`、zero migration 与 Typed fail-closed | `5363ba0c`, `6d246cd5`, `055658b9` | focused 14-job build + 150-job aggregate + exact non-associativity/precedence/sibling-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-34 | TASK-D1-04 | not-equal `!=` Source-only carrier；与 `==` 同层 precedence `50` non-associative、Expr tag `15`、single retention migration 与 Typed fail-closed | `b683bea9`, `25222bdb`, `cff64eea` | focused 14-job build + 152-job aggregate + exact token-integrity/same+mixed-chain/canonical controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-35 | TASK-D1-04 | less-than `<` Source-only carrier；与 equality pair 同层 precedence `50` non-associative、Expr tag `16`、single ordering migration 与 Typed fail-closed | `c743f4b0`, `38afba9b`, `8d9ebe01`, `6d93896b` | focused 14-job build + 154-job aggregate + exact shift-token/same+mixed-chain/canonical controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-36 | TASK-D1-04 | less-or-equal `<=` Source-only carrier；与既有 comparisons 同层 precedence `50` non-associative、Expr tag `17`、single ordering migration 与 Typed fail-closed | `9ab8b6b8`, `c6c5fb80`, `9d4fbd37` | focused 14-job build + 156-job aggregate + exact token-integrity/same+mixed-chain/canonical controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-37 | TASK-D1-04 | greater-than `>` Source-only carrier；与既有 comparisons 同层 precedence `50` non-associative、Expr tag `18`、single ordering migration 与 Typed fail-closed | `d8b8120a`, `880f2b95`, `996fa0fe` | focused 14-job build + 158-job aggregate + exact shift-token/same+mixed-chain/canonical controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-38 | TASK-D1-04 | greater-or-equal `>=` Source-only carrier；CompareExpr 最后一个 Source residual、Expr tag `19`、final ordering migration 与 Typed fail-closed | `99b5ac11`, `568c1e2e`, `af40d164`, `8957c636` | focused 14-job + 160-job aggregate + exact token/ten-chain/canonical controls；clean committed CompareExpr batch `just ci` at `8957c636`；final review P0/P1=0 | complete (development) |
| D1-PA-39 | TASK-D1-04 | binary bitwise-and `&` Source-only carrier；低于 CompareExpr 的 precedence `45` 左结合、Expr tag `20`、zero migration 与 Typed fail-closed | `10186ad5`, `c7ea38f2`, `dc075680` | focused 14-job build + 162-job aggregate + exact left/right nesting、comparison-mix、canonical/token-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-40 | TASK-D1-04 | binary bitwise-xor `^` Source-only carrier；低于 BitAndExpr 的 precedence `40` 左结合、Expr tag `21`、zero migration 与 Typed fail-closed | `f98ec300`, `d6f61464`, `a3a48028` | focused 14-job build + 164-job aggregate + exact and/compare mixes、left/right nesting、canonical/token-boundary controls；final review P0/P1=0；checkpoint `just ci` deferred | complete (development) |
| D1-PA-41 | TASK-D1-04 | binary bitwise-or Source-only carrier；低于 BitXorExpr 的 precedence `35` 左结合、Expr tag `22`、single retention migration 与 Typed fail-closed | `2cd00ef6`, `80f319a9`, `5ecd8378`, `08ce0b6b` | focused 14-job build + 166-job aggregate + enum coexistence、six mixed shapes、left/right nesting 与 token-boundary controls；clean committed bitwise-tier `just ci` at `08ce0b6b`；final review P0/P1=0 | complete (development) |
| D1-PA-42 | TASK-D1-04 | binary logical-and Source-only carrier；低于 BitOrExpr 的 precedence `30` 左结合、Expr tag `23`、single retention migration 与 Typed fail-closed | `72c8bcd2`, `f7adbf8f`, `3c16300f` | focused 14-job build + 168-job aggregate/test binary + exact bitwise/comparison mixes、left/right nesting、canonical/digraph controls；final review P0/P1=0；logical-tier `just ci` deferred | complete (development) |
| D1-PA-43 | TASK-D1-04 | binary logical-or Source-only carrier；低于 LogicAndExpr 的 precedence `25` 左结合、Expr tag `24`、single retention migration 与 Typed fail-closed | `9ef75d70`, `ed9ae637`, `3ff4b76b` | focused 14-job build + 170-job aggregate + exact logical/bitwise/comparison mixes、left/right nesting、canonical/token-boundary controls；clean committed logical-tier `just ci` at `3ff4b76b`；final review P0/P1=0 | complete (development) |
| D1-PA-44 | TASK-D1-04 | StringLiteral Source-only carrier；Lean decoded string value、Expr tag `25`、zero migration 与 Typed fail-closed | `989503eb`, `7b0b1c5a`, `a0a460b2`, `fa4d00c9` | focused 14-job build + 172-job aggregate/test binary + empty/escape/Unicode/decoded-equality/tag-nonalias/parser-boundary controls；final review P0/P1=0；primary-expression batch `just ci` deferred | complete (development) |
| D1-PA-45 | TASK-D1-04 | complete LocalFnCall/ExprList Source-only carrier；unqualified callee、Expr tag `26`、single grouping migration 与 Typed fail-closed | `b94d694e`, `02ab14b3`, `fe41856b`, `75cc3dae`, `024ae637`, `af0a7889` | focused 15-job build + 176-job aggregate/test binary + zero/one/multi/nested/canonical/qualified-name/parser-boundary controls；shared ParserSession harness correction；final review P0/P1=0；call-like batch `just ci` deferred | complete (development) |
| D1-PA-46 | TASK-D1-04 | ConstructorExpr Source-only carrier；qualified component-array identity、Expr tag `27`、two qualified-call migrations 与 Typed fail-closed | `4d61820e`, `717da5a0`, `fbed21c6`, `66f56bf9`, `2bc6eb9d`, `ab610e57`, `a624b484`, `48c00733`, `f8ca5fe4` | focused 15-job + 178-job aggregate/test binary；component/argument value-count-order-nesting、escaped/dotted/reserved/invalid boundaries；final reviews P0/P1=0；clean committed call-like batch `just ci` 186-job archive 全绿 | complete (development) |
| D1-PA-47 | TASK-D1-04 | bare-base rvalue `indexAccess` Source-only carrier；single `Ident "[" Expr "]"` suffix、Expr tag `28`、zero migration 与 Typed fail-closed | `88aa2af7`, `049ef0c8`, `dcfb6e19`, `5515acb2`, `cc1e1ef2` | focused 15-job + 180-job aggregate/test binary；bare-base/full-index-expression/canonical/tag/parser-boundary controls；final reviews P0/P1=0；按冻结未运行 `just ci` | complete (development) |
| D1-PA-48 | TASK-D1-04 | complete `revertStmt(errorName,args)` Source-only carrier；bare/empty/full ExprList、Statement tag `5`、zero migration 与 Typed fail-closed | `6e37c8a5`, `f8fa9e5f`, `0791cb10`, `856b68e6`, `27b3a17e`, `d4761ff6`, `64a081cf` | focused 15-job + 182-job aggregate/test binary；longest-match/name/ExprList/canonical/tag/parser-boundary controls；final reviews P0/P1=0；按冻结未运行 `just ci` | complete (development) |
| D1-PA-49 | TASK-D1-04 | value-less `returnUnit` Source-only carrier；既有 `returnValue` 不变、Statement tag `6`、zero migration 与 Typed fail-closed | `63371613`, `df5ea962`, `57239979`, `5c04c4f0`, `591129f9`, `5d16caab`, `1ea48621`, `7d944c0e`, `4a95e5ef` | deterministic offside return layout/canonical/tag/parser-boundary controls；focused 15-job + 184-job aggregate/test binary；clean committed `just ci` 192-job archive 全绿；final reviews P0/P1=0 | complete (development) |
| D1-PA-50 | TASK-D1-04 | complete `emitStmt(eventName,args)` Source-only carrier；mandatory parentheses/full ExprList、Statement tag `7`、zero migration 与 Typed fail-closed | `c91260df`, `d7d79f5e`, `7eaf464e`, `de40194f` | focused 15-job + 186-job aggregate/test binary；name/ExprList/canonical/tag/parser-boundary controls；coordinator/Kimi final reviews P0/P1=0；按冻结未运行 `just ci` | complete (development) |
| D1-PA-51 | TASK-D1-04 | complete `assert Expr else Ident` Source-only carrier；append-only `assertErrorStmt`、Statement tag `8`、single deferred-negative migration 与 Typed fail-closed | `2c7f84cc`, `3c844b80`, `e97a889d`, `c2a1e4fa` | focused 15-job + 186-job aggregate/test binary；name-before-condition/canonical/tag/longest-match/parser-boundary controls；coordinator/Kimi final reviews P0/P1=0；按冻结未运行 `just ci` | complete (development) |
| D1-PA-52 | TASK-D1-04 | complete `if Expr then Block (else Block)?` Source-only carrier；recursive statement blocks、Statement tag `9`、zero migration 与 Typed fail-closed | `8f6d506f`, `ad2c183b`, `8db0def3`, `2efb9ad9`, `3d8f48f8` | focused 15-job + 188-job aggregate/test binary；linebreak/owning-column/nonempty/nesting/canonical/tag/Typed controls；coordinator/Kimi final reviews P0/P1=0；package file-set re-pin；按冻结未运行 `just ci` | complete (development) |
| D1-PA-53 | TASK-D1-04 | complete `for Ident in Expr ..< Expr bounded Nat do Block` Source-only carrier；`Fin 4097` exact bound、Statement tag `10`、zero migration 与 Typed fail-closed | `25f7572d`, `8f6acd5d`, `bf80a1cf`, `4985163d`, `affd21c4`, `e41fd10e`, `2a18c827` | focused 15-job + 190-job aggregate/test binary；strict header/block、range/bound/canonical/tag/Typed controls；Nat canonical-alias RED-driven correction；final reviews P0/P1=0；clean committed PA50–PA53 batch `just ci` 198-job archive 全绿 | complete (development) |
| D1-PA-54 | TASK-D1-03 | bounded `Array PrimitiveAtom N` declaration carrier；`Fin 4097` exact length、Type tag `18`、transitive requirements 与 zero migration | `1bda5b17`, `0f51d950`, `88051192`, `a9fdd05f`, `efb6206e` | focused 23-job + 192-job aggregate/test binary；15 PrimitiveAtom、parser/decoder/canonical/requirement/support-vs-Plan controls；Kimi final review P0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-55 | TASK-D1-03 | exact `Option Field bn254_fr` spelling for existing `option(.field)` carrier；tag `16→2`、transitive `fieldBn254` requirement 与 single deferred-negative migration | `1371f5be`, `efa68394`, `1e922851`, `1b15dc4f` | focused 23-job + 192-job aggregate/test binary；exact parser/raw-id/canonical/requirement/all-target support controls；Kimi final review P0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-56 | TASK-D1-03 | exact one-level `Option Option PrimitiveAtom` spelling for existing recursive `option(option(element))` carrier；tag `16→16→element`、transitive requirements 与 single deferred-negative migration | `b598114d`, `1a6d9ee8`, `008b2da0`, `8b4d4c2c` | focused 23-job + 192-job aggregate/test binary；exact named parser、15-atom decoder closure、canonical/requirement/all-target support-vs-Plan controls；Kimi final review P0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-57 | TASK-D1-03 | exact `Option Array PrimitiveAtom N` spelling for existing recursive `option(array(element,length))` carrier；tag `16→18→element→length`、transitive requirements 与 single deferred-negative migration | `5fece0df`, `a068a76e`, `dbbe9f07`, `25a5c3cd` | focused 23-job + 192-job aggregate/test binary；exact named parsers、15-atom/`0..4096` Array decoder reuse、canonical/requirement/all-target support-vs-Plan controls；independent RED/final reviews P0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-58 | TASK-D1-03 | exact `Option Bytes N` spelling for existing recursive `option(bytes(length))` carrier；tag `16→17→length`、transitive zero requirements 与 two existing negative migrations | `0f8f31d0`, `6afd44a8`, `8d9c6c2e`, `ff36cac7` | focused 24-job + 192-job aggregate/test binary；exact named parser、Bytes length decoder reuse、canonical/requirement/support-vs-Plan controls；Grok/Kimi residual audits P0=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-59 | TASK-D1-03 | exact `Array Option PrimitiveAtom N` spelling for existing recursive `array(option(element),length)` carrier；tag `18→16→element→length`、transitive requirements 与 two existing negative migrations | `2aad1b3c`, `6ff1ad73`, `911d253e`, `1b07b22a` | focused 24-job + 192-job aggregate/test binary；exact named parser、Array length/PrimitiveAtom decoder reuse、canonical/requirement/support-vs-Plan controls；Grok post-PA58 + Kimi freeze/final reviews P0=0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-60 | TASK-D1-03 | exact `Array Field bn254_fr N` spelling for existing recursive `array(field,length)` carrier；tag `18→2→length`、transitive `fieldBn254` requirement 与 two existing negative migrations | `5e504456`, `7ef54270`, `be990868`, `8345ef53` | focused 24-job + 192-job aggregate/test binary；exact named parser、raw `bn254_fr` guard、Array length decoder reuse、canonical/requirement/support controls；Grok post-PA59 residual + Kimi freeze/final reviews P0=0/P1=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-61 | TASK-D1-03 | exact `Array Bytes N M` spelling for existing recursive `array(bytes(innerLength),outerLength)` carrier；tag `18→17→innerLength→outerLength`、transitive zero requirements 与 single existing negative migration | `fce7406f`, `f2809e00`, `07e6e7d4`, `3555c142` | focused 23-job + 192-job aggregate/test binary；exact named parser、dual Bytes/Array length decoder reuse、canonical/requirement/support-vs-Plan controls；Kimi freeze/final reviews P0=0/P1=0/P2=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-62 | TASK-D1-03 | exact `Option Option Field bn254_fr` spelling for existing recursive `option(option(field))` carrier；tag `16→16→2`、transitive `fieldBn254` requirement 与 single existing negative migration | `9df534f6`, `01f20129`, `d5b31886`, `4f2fcf06` | focused 23-job + 192-job aggregate/test binary；exact named parser、raw `bn254_fr` guard、canonical/requirement/support controls；Kimi freeze/final reviews P0=0/P1=0/P2=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-63 | TASK-D1-03 | exact `Option Option Bytes N` spelling for existing recursive `option(option(bytes(length)))` carrier；tag `16→16→17→length`、transitive zero requirements 与 single existing negative migration | `fd8af0a9`, `c9e72cf4`, `7c616a3d`, `e6e0297d`, `c1747722` | focused 23-job + 192-job aggregate/test binary；exact named parser、dual Option/Bytes decoder reuse、canonical/requirement/support-vs-Plan controls；Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-64 | TASK-D1-03 | exact `Option Option Array PrimitiveAtom N` spelling for existing recursive `option(option(array(element,length)))` carrier；tag `16→16→18→element→length`、transitive requirements 与 single existing negative migration | `de508b9e`, `75e68778`, `bee37a16`, `f232cce1` | focused 23-job + 192-job aggregate/test binary；exact named parser、Array/PrimitiveAtom/length decoder reuse、canonical/requirement/support-vs-Plan controls；Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-65 | TASK-D1-03 | exact `Option Array Field bn254_fr N` spelling for existing recursive `option(array(field,length))` carrier；tag `16→18→2→length`、transitive `fieldBn254` requirement 与 single existing negative migration | `6169dbaf`, `ca1cb2e0`, `0f6bf15d`, `a7fc520e` | focused 23-job + 192-job aggregate/test binary；exact named parser、Array Field/length decoder reuse、canonical/requirement/support-vs-Plan controls；Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；按冻结未重复 `just ci` | complete (development) |
| D1-PA-66 | TASK-D1-03 | exact `Array Array PrimitiveAtom N M` spelling for existing recursive `array(array(element,innerLength),outerLength)` carrier；tag `18→18→element→innerLength→outerLength`、transitive requirements 与 single existing negative migration | `8ba6e131`, `57e6f68b`, `b868a4c0`, `a4c291b2` | focused 23-job + 192-job aggregate/test binary；15-atom/dual-length decoder reuse、canonical/requirement/support-vs-Plan controls；Grok residual/Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；`just sbom` green；按冻结未重复 `just ci` | complete (development) |
| D1-PA-67 | TASK-D1-03 | exact `Option Array Option PrimitiveAtom N` spelling for existing recursive `option(array(option(element),length))` carrier；tag `16→18→16→element→length`、transitive requirements 与 single existing negative migration | `72a7a0d1`, `418e33d7`, `0e81a80a` | focused 23-job + 192-job aggregate/test binary；15-atom/Option/Array/length decoder reuse、canonical non-alias/requirement/support-vs-Plan controls；Grok residual/Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；`just sbom` green；按冻结未重复 `just ci` | complete (development) |
| D1-PA-68 | TASK-D1-03 | exact `Option Array Bytes N M` spelling for existing recursive `option(array(bytes(innerLength),outerLength))` carrier；tag `16→18→17→innerLength→outerLength`、zero requirements 与 single existing negative migration | `1c30b470`, `5f6bd5dd`, `367bb9f0` | focused 23-job + 192-job aggregate/test binary；dual-length Array Bytes decoder reuse、canonical non-alias/zero-requirement/support-vs-Plan controls；Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；`just sbom` green；按冻结未重复 `just ci` | complete (development) |
| D1-PA-69 | TASK-D1-03 | exact `Option Array Array PrimitiveAtom N M` spelling for existing recursive `option(array(array(element,innerLength),outerLength))` carrier；tag `16→18→18→element→innerLength→outerLength`、transitive requirements 与 single existing negative migration | `7f62835a`, `8ff18a9d`, `31750d95` | focused 23-job + 192-job aggregate/test binary；closed Array Array decoder reuse、canonical non-alias/requirement/support-vs-Plan controls；parser-channel correction 与 non-Primitive compound controls；Kimi final review P0=0/P1=0/P2=0；package file-set re-pin；`just sbom` green；按冻结未重复 `just ci` | complete (development) |
| D1-PA-70 | TASK-D1-03 | exact three-layer `Option Option Option PrimitiveAtom` spelling for existing recursive `option(option(option(element)))` carrier；tag `16→16→16→element`、transitive requirements 与 single existing negative migration | `8a1e1474`, `4d3030b3`, `134ac9e6` | focused 23-job + 192-job aggregate/test binary；closed nested Option decoder reuse、15-atom/depth/non-alias/requirement/support-vs-Plan controls；empirical parser/decoder channel corrections；Kimi + coordinator final reviews P0=0/P1=0/P2=0；package file-set re-pin；`just sbom` green；按冻结未重复 `just ci` | complete (development) |
| D1-PA-71 | TASK-D1-03 | exact `Array Option Option PrimitiveAtom N` spelling for existing recursive `array(option(option(element)),length)` carrier；tag `18→16→16→element→length`、transitive requirements 与 single existing negative migration | `3614e4c5`, `be967ecc`, `b56b2d04` | focused 23-job + 192-job aggregate/test binary；15-atom/length/canonical/requirement/support-vs-Plan/no-artifact controls；Syntax +27/-0；Kimi + coordinator final reviews P0=0/P1=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-72 | TASK-D1-03 | exact `Array Option Bytes N M` spelling for existing recursive `array(option(bytes(innerLength)),outerLength)` carrier；tag `18→16→17→innerLength→outerLength`、zero requirements 与 single existing negative migration | `d80e2aeb`, `5a1b21d3`, `f5bfd28b` | focused 23-job + 192-job aggregate/test binary；dual-length/canonical/zero-requirement/support-vs-Plan/no-artifact controls；Syntax +27/-0；Kimi + coordinator final reviews P0=0/P1=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-73 | TASK-D1-03 | post-PA-72 bounded arbitration 选择 exact `Option Option Option Field bn254_fr` spelling for existing recursive `option(option(option(field)))` carrier；tag `16→16→16→2`、single `fieldBn254` requirement 与 single existing negative migration | `b936076d`, `98220833`, `6a6ced82`, `545c4b7e` | focused 23-job + 192-job aggregate/test binary；wrapper-depth/Field-leaf canonical non-alias、requirement/support-rejection/no-artifact controls；empirical third-Option error-channel correction；Syntax +26/-0；independent final reviews P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-74 | TASK-D1-03 | post-PA-73 bounded arbitration 选择 exact `Option Option Option Bytes N` spelling for existing recursive `option(option(option(bytes(length))))` carrier；tag `16→16→16→17→length`、zero requirements 与 single existing negative migration | `e5810700`, `cf018c96`, `836169a8` | focused 23-job + 192-job aggregate/test binary；single-length/wrapper-depth/Bytes-leaf canonical non-alias、zero-requirement/support-vs-Plan/no-artifact controls；Syntax +26/-0；两路独立 final review P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-75 | TASK-D1-03 | post-PA-74 residual challenge 选择 exact `Option Option Array Field bn254_fr N` spelling for existing recursive `option(option(array(field,length)))` carrier；tag `16→16→18→2→length`、single `fieldBn254` requirement 与 single existing negative migration | `b1873f6a`, `f87109b1`, `557cace2` | focused 23-job + 192-job aggregate/test binary；single Field/single-length canonical non-alias、requirement/support-rejection/no-artifact controls；Syntax +27/-0；Grok implementation audit + Kimi independent final review P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-76 | TASK-D1-03 | post-PA-75 bounded arbitration 选择 exact `Array Option Option Field bn254_fr N` spelling for existing recursive `array(option(option(field)),length)` carrier；tag `18→16→16→2→length`、single `fieldBn254` requirement 与 single existing negative migration | `e1b26295`, `e8d9477a`, `0ebf6555`, `d1b76abe` | focused 23-job + 192-job aggregate/test binary；single Field/single-length canonical non-alias、requirement/support-rejection/no-artifact controls；Syntax +29/-0；双路 canonical probe + independent final review P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-77 | TASK-D1-03 | post-PA-76 bounded arbitration 选择 exact `Array Array Field bn254_fr N M` spelling for existing recursive `array(array(field,innerLength),outerLength)` carrier；tag `18→18→2→innerLength→outerLength`、single `fieldBn254` requirement 与 single existing negative migration | `a032d4a2`, `fac3e2f7`, `0afddb53` | focused 23-job + 192-job aggregate/test binary；fixed Field/dual-length canonical non-alias、requirement/support-rejection/no-artifact controls；Syntax +34/-0；三路 RED/GREEN independent review P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-78 | TASK-D1-03 | post-PA-77 bounded challenge 选择 exact `Option Array Array Field bn254_fr N M` spelling for existing recursive `option(array(array(field,innerLength),outerLength))` carrier；tag `16→18→18→2→innerLength→outerLength`、single `fieldBn254` requirement 与 single existing negative migration | `4b2da645`, `26690dc9`, `175e8a1b` | focused 23-job + 192-job aggregate/test binary；fixed Field/dual-length/wrapper canonical non-alias、requirement/support-rejection/no-artifact controls；Syntax +31/-0；两路 independent final review P0/P1/P2=0；package file-set re-pin；`just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-79 | TASK-D1-03 | post-PA-78 residual 选择 exact `Option Option Array Bytes N M` spelling for existing recursive `option(option(array(bytes(innerLength),outerLength)))` carrier；tag `16→16→18→17→innerLength→outerLength`、zero requirements 与 single existing negative migration | `36673098`, `2f115c74`, `529d2699`, `a4752ae0`, `bbab5013`, `37102754` | focused 23-job + 192-job aggregate/test binary；dual-length/wrapper/leaf canonical non-alias、zero-requirement/support-pass + state/result/parameter Plan-invariant/no-artifact controls；empirical error-channel corrections；Syntax +27/-0；independent final review P0/P1/P2=0；package file-set re-pin；clean detached `just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-80 | TASK-D1-03 | post-PA-79 bounded arbitration 选择 exact `Array Option Option Bytes N M` spelling for existing recursive `array(option(option(bytes(innerLength))),outerLength)` carrier；tag `18→16→16→17→innerLength→outerLength`、zero requirements、single existing negative migration 与 fixed-leaf family closure | `d9bdb762`, `363fb7c0`, `ebd3eed2` | focused 23-job + 192-job aggregate/test binary；dual-length/wrapper/leaf canonical non-alias、zero-requirement/support-pass + state/result/parameter Plan-invariant/no-artifact controls；Syntax +30/-0；independent final review P0/P1/P2=0；package file-set re-pin；clean detached `just sbom` green；按冻结不重复 `just ci` | complete (development) |
| D1-PA-81 | TASK-D1-05 | 把 no-op `proof_forge_program` 替换为 schema-bound persistent environment export registry；跨 module/import-order stable UTF-8 FQN listing 与 duplicate/schema fail-closed | `6b482876`, `e67c4c30`, `7326e1bc` | focused 17-job + 208-job aggregate/test binary；schema/FQN-only persistent entry、diamond/import-order/manual-alias、reverse/schema/duplicate fail-closed；ProgramExport 84 lines、Syntax +1/-6、31-file package re-pin；`SB2-031` live fixture limit 修复 `6fe9bea0` 后 `just sbom` 全绿；independent review P0/P1/P2=0；不含 payload eval、identity-level duplicate、CLI/Loader、target 或正式 `TST-SRC-006/007` closure | complete (development) |
| D1-PA-82 | TASK-D1-05 | 从 PA81 registry FQN 以 closed Lean `Expr` structural decoder 重建 exported `Source.Program`；禁止 `evalConst`/`evalExpr`、reduction 与任意 attributed code execution | `0470c41a`, `c6aa1b8e`, `951efdd6` | focused 21-job + 230-job aggregate/test binary；358/360-line RED 覆盖 rich BEq、direct quoted state、six negative classes、all-or-nothing 与 100000/100001 + 256/257 bounds；429-line closed structural decoder、declaration safety gates、32-file package re-pin；`just sbom` 全绿；independent final review P0/P1/P2=0；不含不可观察的 source modifier provenance、identity duplicate、CLI/Loader、target、contained worker 或正式 `TST-SRC-006/007` closure | complete (development) |
| D1-PA-83 | TASK-D1-05 | PA82 全量 reconstruction 后按 exact payload `qualifiedName` 拒绝 cross-row duplicate/split-brain Source identity；`sourceHash` 只分类同名同/异内容 | `d740b724`, `7d016287`, `e266f3ed` | focused 12-job + 242-job aggregate/test binary；195/220-line RED 覆盖 distinct-qname、exact duplicate、split-brain 与 decode-before-identity priority；ProgramPayload +20/449 lines、qualifiedName→sourceHash private scan、32-file package re-pin；`just sbom` 全绿；Grok/Kimi final reviews P0/P1=0；不含 declaration/payload single-row binding、independent hash-collision oracle、CLI/Loader、target、contained worker 或正式 `TST-SRC-006/007` closure | complete (development) |
| D1-PA-84 | TASK-D1-05 | exact bind `ProgramExportV1.declaration.toString` 与 reconstructed `Source.Program.qualifiedName`；single API decode 后绑定，table 保留 PA83 collision-before-binding priority | `de9ab20c`, `f60390bf`, `ed669820` | focused PA84+PA83 23-job + 254-job aggregate/test binary；208/220-line RED 覆盖 nested/escaped DSL、hand-aligned、single/table mismatch、`PF-EXPORT-004` 与 PA83 priority；ProgramPayload +9/458 lines、32-file package re-pin；`just sbom` 全绿；Grok/Kimi P0/P1=0；不含 short-name/wire component binding、`PF-EXPORT-002/003`、CLI/Loader、target、worker 或正式 `TST-SRC-006/007` closure | complete (development) |
| D1-PA-85 | TASK-D1-05 | exact bind reconstructed `Source.Program.name` 与 export declaration 最后一个 `Name.str` component 的 isolated `Name.toString` rendering；保留 PA82→PA83→PA84 priority | `bce351f4`, `bc180f56`, `2f7f916b`, `3f435a67`, `91d31880` | focused PA85+PA84+PA83 28-job + 264-job aggregate/test binary；178/180-line RED 覆盖 simple/escaped-hyphen/escaped-dot、isolated dual-API mismatch 与 `PF-EXPORT-004` priority；test macro collision correction 后 aggregate green；ProgramPayload +10/468 lines、32-file package re-pin；`just sbom` 全绿；Grok/Kimi P0/P1=0；代码侧 pre-acceptance 饱和；不含 wire component identity、NodeId/origin、D1-06 或正式 `TST-SRC-006/007` closure | complete (development) |
| D1-PA-86 | TASK-D1-05 | tests-only labeled acceptance entrypoint for frozen `TST-SRC-006/007`：exact schema/diagnostic/empty registry goldens、AB/BA diamond order、cross-row duplicate/conflict 与 decode→identity→binding priority；零 production change | `af6de6c9`, `b43bf1e8`, `00d77c8c`, `685243d1` | pending-prep freeze package 先锁定 exact row/scope/formal-grade doneWhen；124/150-line `ProgramExportAcceptance` + isolated empty snapshot；真实 distinct-Name/same-render conflict、exact diagnostics、AB/BA/identity/priority 全覆盖；focused 29-job、268-job aggregate/test binary、docs/diff 全绿；independent review P0/P1/P2=0；未运行完整 `just ci`/SBOM，不关闭 formal task，不进入 D1-06 | complete (development) |
| D1-PA-87 | TASK-D1-03 | tests-only labeled `DeclarationAcceptance` executable harness for frozen `TST-SRC-004`：exact 16-suite single-run wrapper，保留既有 assertion、suite 相对顺序与 `FrontendParity` 独立执行；零 production change | `0d4b5d31`, `0eafc92d`, `926df351` | pending-prep freeze package 锁定 exact row/scope/formal-grade doneWhen；39-line wrapper、42/50 additions、Tests runner +2/-16；focused 41-job、270-job aggregate/test binary、docs/diff 全绿；Grok/Kimi freeze review 与 Kimi final review P0/P1=0；未运行完整 `just ci`/SBOM，不关闭 formal task | complete (development) |
| D1-PA-88 | TASK-D1-02 | tests-only labeled `ProgramCommandAcceptance` executable harness for frozen `TST-SRC-003`：direct command/ParserSession exact parity、无顶层 kind 与非白名单 command 的 exact fail-closed/non-execution；不调用 `selectProgram` | `a55f26ac`, `efa7a935`, `867cba14` | pending-prep freeze package 锁定 exact row/scope/formal-grade doneWhen；71-line direct-fixture suite、74/80 additions；focused acceptance、272-job aggregate/test binary、docs/diff 全绿；Grok freeze review 与 Kimi final review P0/P1=0；未运行完整 `just ci`/SBOM，不关闭 formal task | complete (development) |
| D1-PA-89 | TASK-D1-01 | tests-only labeled `SourceWireAcceptance` executable harness for the existing `TST-SRC-001` NodeId/span development surface：exact `SourceIdentity`→`SourceSpan` single-run wrapper；零 production change | `ee1cbc8d`, `2df076fe`, `510f1fad` | pending-prep package 锁定 TASK-D1-01 的两项 formal tests；11-line wrapper、14/30 additions、aggregate -2 calls；focused acceptance + 274-job aggregate/test binary、docs/diff 全绿；Grok implementation 与 independent final review P0/P1/P2=0；不吸收完整 wire golden 或 SRC-002，未运行完整 `just ci`/SBOM，不关闭 formal task | complete (development) |
| D1-PA-90 | TASK-D1-01 | tests-only direct `SourceBoundsAcceptance` unit harness for frozen `TST-SRC-002`：exact Syntax 256/257、100000/100001、six-decoder walker 与 qualified/identifier identity boundary；heavy integration 复用 `just dsl-negative` | `605b139a`, `8422bcc1`, `7f53c324` | 81-line direct suite、84/110 additions；四条 full diagnostics、六 decoder、qualified/identifier off-by-one 全覆盖；276-job focused+aggregate/test binary、existing `just dsl-negative`、docs/diff 全绿；Grok implementation、Kimi 与 independent final review P0/P1/P2=0；未复制 resident heavy paths，未运行完整 `just ci`/SBOM，不关闭 formal task | complete (development) |
| D1-PA-91 | TASK-D1-01 | production `WireCodecV1` primitive/tagged encoder foundation for proposed `SPEC-SOURCE-WIRE-001`：little-endian scalars、u256、Bool/Option/Array、NFC Ident/String、QualifiedName/QualifiedId、generic tagged fields；independent Python reference/goldens | `cec96db2`, `b59dadfd`, `aa54102f` | 109-line codec、92-line Lean suite、100-line independent Python reference，authored additions 305/380；20 fixed positive hex vectors、11 negatives、child-error propagation 与 transient u256/order/boundary probes；focused + 280-job aggregate/test binary、package re-pin、final `just sbom`、docs/diff 全绿；Grok/Kimi final P0/P1=0；无 ProgramV1/model/hash/decoder/NodeId，未运行完整 `just ci`，不关闭 formal task | complete (development) |
| D1-PA-92 | TASK-D1-01 | cursor-based production `WireDecodeV1` primitive decoder：u8/u16/u32/u256 little-endian、Bool、higher-order Option/Array（caller count cap）、strict UTF-8 pinned-NFC String、remaining/finish；independent Python decode oracle | `9d935dc9`, `52011dbb`, `a4cbedfa` | 113-line production decoder、108-line Lean suite、87-line Python oracle，authored additions 312/370；34-file package re-pin；exact `array count exceeds caller limit` before child；checked-in LE/NFC positives、PA91 allowlist encode→decode round-trips、full negative class set；focused + 284-job aggregate/test binary、final `just sbom`、docs/diff 全绿；Grok implementation 与 Kimi final P0/P1/P2=0；无 Ident/QN/QID/tag/model/hash/NodeId/global budgets；未运行完整 `just ci`，不关闭 formal task | complete (development) |
| D1-PA-93 | TASK-D1-01 | production `SourceNameComponentV1` raw Lean `Name.str` carrier + typed wire encode/decode；PA91 `encodeIdent` validation migrates to raw carrier；independent Python raw oracle | `139036b7`, `cbecfacc`, `93c63390`, `e982fdee`, `08e7e7de` | 41-line carrier、118-line Lean suite、49 existing/registration additions，总 authored 208/255；raw/render/Common 三身份分离，private constructor、1..240 pinned-NFC/Cc/closing-guillemet fail-closed，`_`/opening-guillemet/digit/hyphen/dot/space/keyword body positives；typed raw encode/decode、PA91 `1bad` exact positive与独立 Python oracle；35-file package re-pin；focused + 288-job aggregate/test binary、final single `just sbom`、docs/diff 全绿；Kimi RED/final review P0/P1/P2=0；无 ProgramV1/SourceQualifiedName root/model/hash/NodeId，未运行完整 `just ci`，不关闭 formal task | complete (development) |

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D1-01 | source token、span、NodeId | TASK-D0-01, TASK-D0-02, TASK-D0-03, TASK-D0-04, TASK-D0-07 | — | TST-SRC-001, TST-SRC-002 | EV-20260717-0036, EV-20260719-0087, EV-20260719-0088, EV-20260719-0089, EV-20260719-0090, EV-20260719-0091 | pending |
| TASK-D1-02 | `program ... where` command parser | TASK-D1-01 | — | TST-SRC-003 | EV-20260719-0086 | pending |
| TASK-D1-03 | declaration grammar/elaboration | TASK-D1-02 | — | TST-SRC-004 | EV-20260717-0037, EV-20260717-0038, EV-20260717-0039, EV-20260717-0040, EV-20260717-0041, EV-20260717-0042, EV-20260717-0043, EV-20260717-0044, EV-20260717-0045, EV-20260717-0046, EV-20260717-0047, EV-20260718-0001, EV-20260718-0002, EV-20260718-0003, EV-20260718-0004, EV-20260718-0005, EV-20260718-0046, EV-20260718-0047, EV-20260718-0048, EV-20260718-0049, EV-20260718-0050, EV-20260718-0051, EV-20260718-0055, EV-20260718-0057, EV-20260718-0058, EV-20260719-0059, EV-20260719-0060, EV-20260719-0061, EV-20260719-0062, EV-20260719-0063, EV-20260719-0064, EV-20260719-0065, EV-20260719-0066, EV-20260719-0067, EV-20260719-0068, EV-20260719-0070, EV-20260719-0072, EV-20260719-0073, EV-20260719-0074, EV-20260719-0075, EV-20260719-0076, EV-20260719-0077, EV-20260719-0078, EV-20260719-0085 | pending |
| TASK-D1-04 | statement/expression grammar | TASK-D1-03 | — | TST-SRC-005 | EV-20260718-0006, EV-20260718-0007, EV-20260718-0008, EV-20260718-0009, EV-20260718-0010, EV-20260718-0011, EV-20260718-0012, EV-20260718-0013, EV-20260718-0014, EV-20260718-0015, EV-20260718-0016, EV-20260718-0017, EV-20260718-0018, EV-20260718-0019, EV-20260718-0020, EV-20260718-0021, EV-20260718-0022, EV-20260718-0023, EV-20260718-0024, EV-20260718-0025, EV-20260718-0026, EV-20260718-0027, EV-20260718-0028, EV-20260718-0029, EV-20260718-0030, EV-20260718-0031, EV-20260718-0032, EV-20260718-0033, EV-20260718-0034, EV-20260718-0035, EV-20260718-0036, EV-20260718-0037, EV-20260718-0044, EV-20260718-0045 | pending |
| TASK-D1-05 | `Source.Program` stable attribute export/schema | TASK-D1-03 | — | TST-SRC-006, TST-SRC-007 | EV-20260719-0079, EV-20260719-0080, EV-20260719-0081, EV-20260719-0082, EV-20260719-0083, EV-20260719-0084 | pending |
| TASK-D1-06 | multi-program loader/selection | TASK-D1-05 | — | TST-SRC-008 | — | pending |
| TASK-D1-07 | stable source diagnostics | TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06 | — | TST-DIAG-001 | — | pending |
| TASK-D1-08 | contained frontend worker、safe source open 与 ResourceProfileV1 supervisor | TASK-D0-04, TASK-D0-06, TASK-D0-07, TASK-D1-01, TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06, TASK-D1-07 | — | TST-RESOURCE-001 | — | pending |

## Milestone D2：检查与语义

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D2-01 | name/type checker + pure-fn call graph + invariant/proof-reference source binding（不装载 proof environment） | TASK-D1-01, TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06, TASK-D1-07, TASK-D1-08 | — | TST-TYPE-001, TST-TYPE-002, TST-TYPE-003 | — | pending |
| TASK-D2-02 | effect/call/view checker | TASK-D2-01 | — | TST-EFFECT-001 | — | pending |
| TASK-D2-03 | bound/termination checker | TASK-D2-01 | — | TST-BOUND-001 | — | pending |
| TASK-D2-04 | disclosure/authority/custody checker | TASK-D2-01 | — | TST-VIS-001, TST-VIS-002 | — | pending |
| TASK-D2-05 | canonical ProgramRequirements inference、predicate merge + origin | TASK-D2-01, TASK-D2-02, TASK-D2-03, TASK-D2-04 | — | TST-REQ-001, TST-REQ-002 | — | pending |
| TASK-D2-06 | closed SemanticProgram construction/canonical serializer + post-canonical proof-bundle/theorem signature validation | TASK-D2-05 | — | TST-SEM-001, TST-PROOF-001 | — | pending |
| TASK-D2-07 | reference step interpreter | TASK-D2-06 | — | TST-SEM-002, TST-SEM-003 | — | pending |

## Milestone D3：目标解析与制品框架

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D3-01 | Target/Profile ID parsers | TASK-D2-01, TASK-D2-02, TASK-D2-03, TASK-D2-04, TASK-D2-05, TASK-D2-06, TASK-D2-07 | — | TST-REG-001 | — | pending |
| TASK-D3-02 | static registry duplicate/exact lookup | TASK-D3-01 | — | TST-REG-002 | — | pending |
| TASK-D3-03 | ProgramRequirements requested predicates → exact static SupportClaim/claimDigest + selected BuildIdentity ProfileSupportIndex resolver；candidate/profile/ref/freshness/revocation exact fail closed 与 aggregate rejection | TASK-D3-02, TASK-D2-05 | — | TST-REQ-003 | — | pending |
| TASK-D3-04 | materializer associated-type protocol | TASK-D3-03 | — | TST-MAT-001, TST-BOUNDARY-001 | — | pending |
| TASK-D3-05 | OutputSet staging/manifest/schema + support-decisions exact schema/digest/binding | TASK-D3-04 | — | TST-OUT-001, TST-OUT-002 | — | pending |
| TASK-D3-06 | CLI check/build/inspect/list-targets + stage/field-specific lower-only resource override parser | TASK-D3-05 | — | TST-CLI-001, TST-CLI-002, TST-CLI-003, TST-CLI-004 | — | pending |
| TASK-D3-07 | contained compiler-core/tool/output supervisor、effective resource profile digest/receipt 与 whole-containment cleanup | TASK-D3-06 | — | TST-RESOURCE-002 | — | pending |

## Milestone D4：EVM

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D4-01 | EvmPlan schema/invariants | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-EVM-001 | — | pending |
| TASK-D4-02 | SemanticProgram → EvmPlan | TASK-D4-01 | — | TST-EVM-002 | — | pending |
| TASK-D4-03 | EvmPlan → Yul + ABI | TASK-D4-02 | — | TST-EVM-003 | — | pending |
| TASK-D4-04 | solc bytecode packaging | TASK-D4-03 | — | TST-EVM-004 | — | pending |
| TASK-D4-05 | Anvil Counter differential | TASK-D4-04 | — | TST-EVM-005 | — | pending |

## Milestone D5：Solana

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D5-01 | SolanaPlan account/layout schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-SOL-001 | — | pending |
| TASK-D5-02 | semantic → SolanaPlan | TASK-D5-01 | — | TST-SOL-002 | — | pending |
| TASK-D5-03 | Plan → sBPF AST/text + IDL | TASK-D5-02 | — | TST-SOL-003 | — | pending |
| TASK-D5-04 | 新建 `solana-sbpf-elf-v1` executable CodegenProfile，lock toolchain/ELF validation；formal gate 后以 registry 新版本切换 default，不得原地升级 plan profile | TASK-D5-03 | — | TST-SOL-004 | — | pending |
| TASK-D5-05 | local runtime Counter differential | TASK-D5-04 | — | TST-SOL-005 | — | pending |

## Milestone D6：NEAR

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D6-01 | NearPlan KV/ABI/import schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-NEAR-001 | — | pending |
| TASK-D6-02 | semantic → NearPlan | TASK-D6-01 | — | TST-NEAR-002 | — | pending |
| TASK-D6-03 | Plan → WasmModuleRecipe | TASK-D6-02 | — | TST-NEAR-003 | — | pending |
| TASK-D6-04 | deterministic Wasm emit/validate | TASK-D6-03 | — | TST-NEAR-004 | — | pending |
| TASK-D6-05 | sandbox Counter differential | TASK-D6-04 | — | TST-NEAR-005 | — | pending |

## Milestone D7：Noir

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D7-01 | NoirPlan disclosure/state relation schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-NOIR-001 | — | pending |
| TASK-D7-02 | semantic → NoirPlan | TASK-D7-01 | — | TST-NOIR-002 | — | pending |
| TASK-D7-03 | Plan → `.nr`/ABI | TASK-D7-02 | — | TST-NOIR-003 | — | pending |
| TASK-D7-04 | 新建 `noir-acir-proof-v1` CodegenProfile，lock ACIR/witness/prove/verify toolchain，并发布 exact ZK security profile + candidate/build formal approval；formal gate 后以 registry 新版本切换 default，不得原地升级 source profile | TASK-D7-03 | — | TST-NOIR-004, TST-ZKSEC-001 | — | pending |
| TASK-D7-05 | Counter + PrivateSum4 proof tests | TASK-D7-04 | — | TST-NOIR-005, TST-NOIR-006 | — | pending |

## Milestone D8：集成与评审

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D8-01 | Counter + Accumulator four-target aggregate and target-neutral structural boundary | TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-XTARGET-001, TST-XTARGET-003 | — | pending |
| TASK-D8-02 | unsupported/version/tool failure matrix | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-XTARGET-002 | — | pending |
| TASK-D8-03 | reproducibility/concurrency/path/resource/performance attacks | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07, TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-SEC-001, TST-PERF-001, TST-RESOURCE-001, TST-RESOURCE-002 | — | pending |
| TASK-D8-04 | clean-room full gate | TASK-D8-01, TASK-D8-02, TASK-D8-03 | — | TST-ISO-003 | — | pending |
| TASK-D8-05 | review report + release/rollback drill | TASK-D8-04 | — | TST-REL-001, TST-VER-001 | — | pending |

任务完成记录必须包含 commit、精确命令、结果、制品/evidence 路径及已知限制。
