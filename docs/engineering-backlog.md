---
id: ENG-BACKLOG
title: 工程业务 Backlog（文档↔实现差异 + 构建加速）
status: draft
owner: engineering
updated: 2026-08-06
normative: false
---

# 工程业务 Backlog

> **本文件是什么**：日常**工程执行队列**（可勾选、可并行、可关闭），把“规范意图 / 研究缺口 /
> 代码事实”压成下一刀切什么。  
> **本文件不是什么**：
> - **不是** “读完仓库每一页文档后的最终真理表”
> - **不是** formal `TASK-*` / `TST-*` / EV / release-qualification 权威（那是
>   `04-task-breakdown` / `05-test-spec` / `MIGRATION_MATRIX`；`release-check` 当前无 recipe）
> - **不是** 第二套 PRD/SPEC（冲突时：accepted ADR → PRD → architecture → SPEC → 代码事实）

状态只允许：`pending` / `in_progress` / `done` / `blocked` / `wontfix`。

## 诚实范围声明（2026-08-01 二次汇总）

### 已作为主输入深度使用（工程队列真源）

| 材料 | 用法 |
|---|---|
| `AGENTS.md` / `Agents.md`（同内容） | 当前 checkpoint、产品路径、T8 状态 |
| `RECOVERY.md` | Wave DAG、工程完成口径与当前进程内产品路径 |
| `MIGRATION_MATRIX.md` | D1–D4 行级工程 vs formal（**未逐字精读全部 400+ 行增量证明段**） |
| `docs/roadmap-t8.md` | T8/T9 切片状态 |
| `docs/research/11-feature-coverage-audit.md` | L1–L8 特性缺口清单 |
| `docs/research/12-target-coverage-matrix.md` | Op×target GAP/LOWERED |
| `docs/research/10-ibc-as-proofforge-programs.md` | 北极星用例与语言前置（**非近期任务**） |
| `docs/01-prd.md` FR/NFR/Phase-1 DoD | 产品验收分母（工程解读） |
| `justfile` / `lakefile.lean` / CI workflow | 构建与反馈循环 |
| `NormalizeV1` docstring + fail-closed 面抽样 | 代码事实抽检 |

### 扫过目录 / 抽样，但**未**做 line-by-line 规格对账

| 材料 | 规模感 | 备注 |
|---|---|---|
| `docs/specs/*`（19 份） | 含 language 2k+、wire 1k+、gate-catalog 2k+、task-qual 1k+ 行 | 应用 **accepted 规范**，不能假装已逐条映射到 backlog 行 |
| `docs/02-architecture.md` / `03-technical-spec.md` | 短入口 | 细节在 specs/modules |
| `docs/05-test-spec.md` | **~4.8k 行** | formal TST 权威；工程队列不展开每条 TST |
| `docs/06-implementation-log.md` | **~12.6k 行** | 已执行事实账本；只抽样检索，非全文回放 |
| `docs/04-task-breakdown.md` | formal 任务树 | 恢复期不新增 TASK；不驱动日常切片 |
| `docs/targets/*.md` + family | 多数 `proposed`/`draft` | 工程状态段**常落后于代码**（如 Solana 仍写 plan-only） |
| `docs/modules/*` | 除 source-frontend 外多为短 stub | 边界意图在，细节未当 checklist |
| `docs/adr/*` | 24 ADR | 决策约束已知；未逐 ADR 生成任务 |
| `docs/research/01–09` + claim/source register | 早期设计研究 | 已被 ADR/SPEC 吸收；**不单独开任务** |
| `docs/traceability/*` | formal 证据图式 | 属 release 轴 |
| `QUALIFICATION_INVENTORY.md` | 隔离 qualification 子系统 | 不进产品队列 |
| `build/**/*.md` | 历史 probe/review 草稿 | **非权威**；勿回填任务 |

### 明确未读透、若要对账需专项

- SPEC-LANG-001 / SPEC-SEM-001 / SPEC-TYPE-001 **全文 EBNF 与 §op 表** vs `NormalizeV1` 的机械 diff
- SPEC-CLI / output-contract / diagnostics **字段矩阵** vs CLI 实际 surface
- 每个 target dossier 与 `LowerSemanticV1` 的逐 op 复核（应用矩阵 12 的更新协议）
- `06-implementation-log` 全文与当前 HEAD 的“幽灵切片”清理
- formal `05-test-spec` 分母闭合（属 Wave 5 / release，非日常）

**结论**：本 backlog 是 **“工程轨道最可用的汇总队列”**，不是 **“全文档全集闭包证明”**。  
若要把“全集闭包”做实，需要专项 **SPEC×code 机械对账**（DOC-SPEC-AUDIT），那是独立切片，不是写一份 markdown 能完成的。

### 文档宇宙怎么读（避免再散）

```text
规范意图（accepted）     执行指针（recovery）      工程队列（本文件）
  ADR / PRD / Arch  ──►  RECOVERY + AGENTS   ──►  engineering-backlog
  specs / modules        MIGRATION_MATRIX          roadmap-t8（宽度切片）
                         research/11+12            research/10（北极星，非近期）
代码与制品事实 ─────────────────────────────────────► 关闭 backlog 项的唯一证据
formal / release ──────────────────► 04/05/traceability / release-check（独立轴）
```

**建议只维护这三份“活队列”**，其余 research 做引用不复制：

1. 本文件 — 总执行 backlog  
2. [`roadmap-t8.md`](roadmap-t8.md) — 宽度/ABI 专项协议（T8/T9）  
3. [`research/12-target-coverage-matrix.md`](research/12-target-coverage-matrix.md) — op×target 格子  

`research/11` 的分层审查、`research/10` 的 IBC 北极星，关闭后**回写本文件状态**，不必再开第三份平行清单。

**索引状态**：`research/README.md` 已登记 11/12/13 与后续 toolchain research；DOC-2 已关闭。

**产品现状一句话**：CLI 进程内 `Loader → Normalize → CompiledSemanticV1 → capability Plan/IR →
Materialized/Finalized + disk closure` 已通；sole Normalize 与**九个 materializer**（EVM/Solana/NEAR/Noir/
Aleo/Psy/Quint/CosmWasm/TON）已覆盖非均匀的多宽算术、控制流、fn、let/for、shift/bitwise、call/schedule、
聚合与 Field 子集；EVM/Solana/NEAR/CosmWasm/TON 有工程 runtime 门，Noir/Aleo 有 compile-only 门，Psy
与 Quint 仍 source-only（Quint 为 zero-tool `.qnt` executable-model target）。registry = **12 targets / 9 implemented + 3 design-only / 11 resolver rows**；CW：sync 拒、
async SubMsg 子集（msg 已升 Binary/base64）；TON：resolver admit async、schedule 已降 `createMessage`
async internal out-message（NoBounce/value=0/dest hash stub；sync 仍 FC）；**完整语言面、平台语义与 formal 资格仍未闭合**，
D1–D4 = 0/27 done。

---

## PRD Phase-1 工程解读（非 formal 勾选）

对照 [`01-prd.md`](01-prd.md)。“部分”= 有工程路径但未达 Phase-1 DoD 字面。

| FR | 工程判断 | backlog 落点 |
|---|---|---|
| FR-001 唯一 `program` | 基本 done | — |
| FR-002 全 declaration + proof ref | parser/typed 强；**INV-1 superseded by ADR-0027 inline gate**；simple-closure/ordinal-0 kernel cert 与 literal-true/public-Bool-view same-file ordinary theorem product `check` positive 已 engineering closed；formal TST/reachability/target refinement仍开 | N-*、ADR-0027 |
| FR-003 type/effect/bound/disclosure | CheckV1 七相位产品门禁；**T-1 工程 authority/custody 子集已接线**（entry 写 private 需 `context.caller`；**非** formal TST-VIS-002） | T-1 **done** |
| FR-004 SemanticProgram + requirements | structure-gated + S2 freeze 工程子集 | N-*、D3-E* |
| FR-005 target 不改语义 | 架构遵守；跨 target reference trace 矩阵未做满 | R-1、C-* |
| FR-006 exact capability | engineering resolver 有；formal SupportClaim 未 | D3-E2、B-3 |
| FR-007 typed Plan/IR | 九个 materializer 有 target-owned 类型（含 Quint/CosmWasm/TON）；formal schema/hash 不齐 | D4-E*、T9d、B-CALL-SEM |
| FR-008 accepted 四-target + runtime/proof | accepted PRD 仍四目标；工程 registry 已 9 implemented + 3 design-only（含 Quint/CosmWasm/TON materializer；scope 债见 DOC-ADR-SCOPE）；EVM/Solana runtime 较强、NEAR/CosmWasm/TON 有工程 runtime 门、Quint source-only、Noir 无 prove | C-1/C-4/C-6、DOC-ADR-SCOPE、PRD-DoD、B-CALL-SEM |
| FR-009 manifest 全 hash 链 | engineering output 部分；plan/IR/tool 不齐 | D3-E3/E4、T9d |
| FR-010 multi-program `--program` | Loader 有 | 回归保持 |
| FR-011 CLI JSON | 主命令有；flag 面未满 | D3-E5 |
| FR-012 private/authority/custody | disclosure 有；**T-1 工程 authority/custody 子集有**（非 formal TST-VIS-002 / 完整 owner-key custody） | T-1 **done**、N-3 |
| FR-013 extension exact-match | 矩阵雏形；非完整 | EXT-* |
| FR-014 无隐式 deploy | 遵守 | — |

| Phase-1 DoD 要点 | 工程判断 |
|---|---|
| accepted PRD Counter 四目标 + overflow 状态不变 | 部分：EVM/Solana 工程 runtime 较强；NEAR 只有 sandbox happy path，未覆盖 overflow rollback；Noir 无 proof |
| EVM/Solana/NEAR local runtime；Noir prove/verify | **未满足字面**：G4/Mollusk 为工程差分，NEAR C-6 非 Reference negatives，Noir C-7 仅 compile-only |
| PrivateSum4 隐私边界 | **APP-1** 产品持续向量（PF-VIS-001 + 无制品泄漏） | APP-1 |
| OutputSet 可重现 + clean-room | engineering 有；formal/clean-room 属 release |
| 全 FR/NFR×SPEC/TASK/TST/EV 闭合 | formal 轴；不进日常 |

| NFR 工程债（常被 research 漏） | backlog |
|---|---|
| NFR-007 check 性能 profile 测量 | **PERF-1** |
| NFR-008 显式 resource limit flags | D3-E5 / **RES-1 / RES-1B** |
| NFR-009 release SBOM ceremony | Q-*（release） |

---

## 北极星用例（研究，非近期切片）

来自 [`research/10-ibc…`](research/10-ibc-as-proofforge-programs.md)；**不改变 PRD 范围**。

| ID | 项 | 说明 | 状态 |
|---|---|---|---|
| **NS-1** | Fungible Token 四 target | 验证“写一次跨链物化”；共享 N-1/N-2/B-3 前置 | **done**（2026-08-02：dense Map pilot **EVM+Solana+NEAR+Noir** cap-8 UInt64 键值；EVM locked-solc finalization 已通，但 258460 B creation bytecode 超 EIP-3860、无链上部署声明；NEAR deployable；Solana 默认仍为 plan profile，但 opt-in ELF+Mollusk 已通，24 叶 snapshot upsert 已修且 MapMini 4/4 runtime 通过；Noir multi-leaf public inputs + relation model；**非** formal/IBC） |
| **NS-2** | packet mailbox 最小件 | IBC-flavored 子集 | pending |
| **NS-3** | 真 IBC 模块栈 | 长期；依赖 crypto | wontfix-until-NS-1 |
| **EXT-ASSETS** | `extension.pf-assets`（L1 portable assets；ADR-0029） | Phase A：payload 冻结 + Typed/Normalize + Quint vault + 产品 demo；Phase B：EVM（payable exact callvalue + full-gas value CALL + `interface-standard` 骨架 + Anvil 门）与 Solana（vault PDA + 幂等 ensure + System CPI 入金 + program-direct 出金 + Mollusk 12/12）；Phase C：CosmWasm（funds exact + BankMsg::Send reply_on=never sync + cw-vm mock）与 NEAR（attached_deposit + transferAsync Promise + near-sandbox 余额观测）已绑定；resolver multi-permit 六行（Quint + EVM×2 + Solana CPI + NEAR + CW）。**ADR-0030（2026-08-05）**：`pf.assets.token.transfer`/`transferAsync`（payload 不变）**E1 四链全绑**——EVM（E1a 受控动态 callee ERC-20 transfer + 返回值三分支 predicate + Anvil 门）、Solana（E1b vault ATA→dst ATA transferCheckedPda + ATA ensure×2 + ROLE_DATA_LEN 刷新纪律 + Mollusk `tipjar_token` 14/14、门 16/338）、CosmWasm（E1-CW CW20 Transfer WasmMsg::Execute SubMsg reply_on=never + bech32 charset `[a-z0-9]` 注入安全门 + cw-vm mock `tokenjar.rs` 6/6）、NEAR（E1-NEAR NEP-141 `ft_transfer` fire-and-forget Promise + 恰好 1 yoctoNEAR + mock token sandbox 真实跨合约 receipt + schedule function-call ABI 7 参修正）；E2 balanceOfSelf env-read **全波 done**（payload v1.1.0 已 cutover 为唯一承认 triple、Reference self-vault 解释器闭合 ADR-0029 opaque caveat、六 target 物化：EVM SELFBALANCE+STATICCALL `balanceOf`、Solana vault lamports/ATA coherence 读（无 CPI）、CW `query_chain` bank/CW20（msg=Binary base64）、NEAR `account_balance` native-only（u128→UInt64 range guard，真实余额≫2^64 trap 已真实触发）、Quint vaultNative native-only；NEAR/Quint token env-read 永久 FC；gates：Anvil envread leg、Mollusk、cw-vm `envreadjar.rs`、near-sandbox 9 suites，含 CallerCheck），E3 caller 已由 ADR-0031 S1 四 target 工程闭合；E4 MiniAMM **in_progress**：Solana multiword div/mod + Mollusk WideDiv、EVM cap-4 Principal Map + MiniAmm demo + Anvil engineering override、Solana cap-4 Principal Map Plan/IR 已交付；Solana MiniAMM 产品 demo、真实 asset flow/remove-liquidity 与双链 formal runtime 仍是诚实 residual；token.transferAsync 除 NEAR 外仍全 target FC。**TON 决策（2026-08-05，产品 owner）：TON 冻结现状（async createMessage 子集已开即止），pf.assets 与后续功能不开发；Noir 永久 FC** | **A（08-04）/B/C/D done（2026-08-05）**；ADR-0030 **E1 done（2026-08-05，四链全绑）/ E2 done（2026-08-06，六 target env-read 物化）/ E3 done（2026-08-06，四 target caller）**，E4 in_progress |
| **EXT-CRYPTO** | `extension.crypto`（SHA-256 / Merkle / 签名） | IBC 与大量链上逻辑命脉；capability 矩阵 | pending（设计后单独立项） |
| **N-BYTES** | Bytes state/param 路径复核（+ 产品 String 若仍需） | state/index assign 随 N-A3 产品路径已钉；String 另议 | **done**（2026-08-02：随 MapBytesAssign；Bytes state+IndexGet/Set 测例） |

---

## 0. 构建与反馈循环加速（可并行于产品切片）

目标：缩短 `just dev-check` / `just ci` / 聚焦 rebuild 墙钟，不改变产品语义。

| ID | 项 | 现状 | 建议 | 状态 |
|---|---|---|---|---|
| **BUILD-1** | 测试 shard **串行**执行 | `justfile` `test` 在一次 `lake build` 后顺序跑 9 个 shard | 本地用有界并行（如 `xargs -P4` / job 组），CI runner 内存不足时保持串行或 `P=2`；失败时打印 shard 名 | **done**（2026-08-02：`PROOF_FORGE_TEST_JOBS` 默认 4，`xargs -P`；`FAIL shard: <name>`） |
| **BUILD-2** | 默认 `build` 仍链 frontend worker | `lake build … proof_forge_frontend_worker_v1`；产品 CLI 已走进程内 `selectProgramV1ProductWithTheoremInventory` + `certifyInlineProofV1` | 将 worker 移出默认 `build`/`dev-check`，仅 `ci` 或显式 target 构建；核对 `Tests/Frontend/WorkerV1` 是否仍进 ordinary CI | **done**（2026-08-02：`build`/`test-fast`/`dev-check` 无 worker；`build-frontend-worker` + `test-frontend-worker` 显式；Fast 去掉 WorkerV1） |
| **BUILD-3** | 巨型 interpreter 测试 exe | 各 shard ~170–188 MB；`supportInterpreter := true` | 评估：减少跨 shard 重复 link、合并极轻 shard（core）、或仅对需要 elaborator 的 suite 开 interpreter | **done**（2026-08-02：test suite `supportInterpreter := false`；core ~7 MB，其余 shard ~100–120 MB；产品 CLI 仍 true） |
| **BUILD-4** | CI 单 job 串行 `just ci` + Solana runtime | `source-core` 一锅端 | 拆 job：docs（已独立）/ lean-product / target-smoke / solana-runtime，共享 Lake cache artifact；缩短失败反馈 | **done**（2026-08-02：CI jobs `docs` + `lean-product` + `target-smoke` + `solana-runtime`；`just ci-lean-product` / `ci-target-smoke`） |
| **BUILD-5** | 删除门与 `rg` 门禁串在 dev-check | 8+ deletion gates 顺序跑 | 多数为秒级；可 `bash` 并行跑无写盘门禁；保持失败汇总 | **done**（2026-08-02：`run-deletion-gates` **serial** — all gates touch `.lake`；`PROOF_FORGE_GATE_JOBS>1` forced to 1） |
| **BUILD-6** | 聚焦路径未默认暴露 | 改 target 时常全量 shard | 文档化 / 加 `just test-shard NAME`、`just test-targets`（已有部分 gate 内 build）；开发默认 `test-fast` + 一 shard | **done**（2026-08-02：`test-shard` / `test-targets` + CONTRIBUTING） |
| **BUILD-7** | Lake 并行度 | 本机 12 核；warm `ProofForgeV2` ~0.4s | 冷构建/CI 确认 `lake` 默认 job 数；必要时 `lake -j$(nproc) build` 写进 justfile | **done**（2026-08-02：Lake 5 无 `-j`；模块构建已多 job；justfile 注释 + 测试并行仍用 PROOF_FORGE_TEST_JOBS） |
| **BUILD-8** | 死代码与过时 RECOVERY 叙述 | RECOVERY 仍大量写 B12 supervisor 为当前路径；AGENTS 已写移除 | 文档对齐（见 DOC-1）；删除已 supersede 的 worker-only 路径若产品不再需要 | **done**（2026-08-02：audit 无 SafeOpen/Supervisor 产品模块；仅 Protocol/Worker；CLI=Loader；见 goal slice-BUILD-8-checks.log） |
| **BUILD-9** | `build/` 与 `runtime-tests/**/target` 垃圾 | 工作区含大量历史产物 | `.gitignore` 收紧 + 定期清理；避免误扫进 SBOM/索引 | **done**（2026-08-02：gitignore runtime-tests/**/target + build probe logs） |
| **BUILD-10** | ordinary CI suite reachability | Authority/Custody、Context/Extension、ProofSubject、InvariantTheorem、ResourceFlags、PsyAcceptance 六个关键 suite 未进入九 shard | 注册到 Typed/Targets shard；InvariantTheorem import-only；工具验收缺席需 skip-clean | **done**（2026-08-02：两 shard 实际执行通过；非 formal/release evidence） |

**预期收益（粗估）**：BUILD-1 在本地满核可把 test 执行墙钟接近压到最慢 shard；BUILD-2/3 降冷构建与磁盘；BUILD-4 降 CI 排队与失败定位时间。

---

## 1. 文档 / 控制面同步（主代理串行）

| ID | 项 | 说明 | 状态 |
|---|---|---|---|
| **DOC-1** | RECOVERY / AGENTS / MIGRATION_MATRIX 与代码对齐 | 前端监督层移除、产品 CLI 进程内 Loader；AGENTS 已正确并链 backlog | **done**（2026-08-01 主代理文档同步；Matrix 行内历史 B12 叙述保留在 D1-08 superseded 段） |
| **DOC-2** | `12-target-coverage-matrix` 按代码复扫 + 登记 research README | README 已列 11/12；**NEAR 格子逐 op 复扫仍待** | **done**（2026-08-02：NEAR NearAggregate 列 GAP→LOWERED/FAIL-CLOSED；README 已登记） |
| **DOC-3** | `11-feature-coverage-audit` L4/L6 刷新 | Solana 多宽句已修；Reference admitted 全表仍待 | **done**（2026-08-02：L6 Solana/T9e + N-A1/A2 注记；L4 admitted 全表仍可深化） |
| **DOC-4** | 四 target dossier「工程迁移状态」刷新 | EVM/Solana/NEAR/Noir + targets/README | **done**（2026-08-01） |
| **DOC-5** | `docs/index.md` / document-status 恢复桥叙述 | 工程路径 + backlog 链接 | **done**（2026-08-01） |
| **DOC-T9-0** | `MIGRATION_MATRIX` 长表过时 present-tense 扫（UInt64-only / single-block / supervisor 等） | **非** 仅 roadmap 状态；commit **必须**改矩阵 | **done**（2026-08-02：矩阵 commit 含 `MIGRATION_MATRIX.md`；D2/边界/D1-06/D1-08 Engineering/Solana 标签对齐 multi-width + 进程内 Loader） |
| **SKEPTIC-1** | Goal 内闭合 skeptic 三缺口：DOC-T9-0 真扫 + DONE_IDS 全量（含 B-1d/B-1e/T9e）+ BUILD-5 exit-0 日志 | 入口 `prompt-skeptic-recovery.md` | **done**（2026-08-02：DOC-T9-0 `1657989ca` 含矩阵；`just run-deletion-gates` EXIT=0 无 traceback；DONE_IDS 含 B-1d/B-1e/T9e） |
| **DOC-SPEC-AUDIT** | SPEC-LANG/SEM/TYPE × Normalize **机械对账** | `docs/research/13-spec-normalize-diff.md`；回流 backlog 校准 | **done**（2026-08-02：RPT-013 表 + N-2/N-3/N-BYTES 校准注；非 formal 全集 EBNF） |
| **DOC-DEDUP** | 禁止再开第四份平行 gap 清单 | 新研究只追加 11/12 或本文件；关掉旧 `build/*-audit.md` 心智依赖 | **done**（2026-08-02：research README + goals README + index 已指向 sole live queues） |

---

## 2. Wave 2 当前主轴：sole Normalize / Reference 扩面（串行共享核）

共享文件：`NormalizeV1` / `ReferenceV1` / `EnvelopeV1` / Wire 相关——**禁止并行改同一文件**。

### 2.1 覆盖审计第一梯队（语言表达力）

| ID | 项 | 解锁 | 状态 |
|---|---|---|---|
| **N-1** | Map：非空构造 + Map state/param + index | 余额表、IBC 表 | **done**（2026-08-02：product nonempty = empty/`Map.empty` + IndexSet；Wire multi-arg Construct 仍 FC；state/index 已 N-A3） |
| **N-2** | ContextRead **扩面** + `callerContext`（CheckV1 + Normalize + Reference） | **done**（2026-08-02 shared：`context.caller` → Principal ContextRead + wire `context.caller`；unixTime 保留；Reference Principal identity admission + resource bounds；**target Plan 见 B-CTX-OPEN**：EVM caller+unixTime 已开 2026-08-06） |
| **N-3** | Commit **disclosure 契约** + Check | Normalize label-only `commit(x)`（N5）+ Disclosure 契约钉测 | **done**（2026-08-02：sole private→commitment declass；commitment↛public；pureFn Commit FC；非 crypto commitment） |
| **N-4** | aggregate entry/view/fn **返回值** + target ABI struct 返回 | 查询型 API | **done**（2026-08-02：Normalize 允许 named Struct/Enum 作 entry/view/fn result；后续 B-RET-ABI 与 CW-7/TON-6 已在八个非 Quint materializer 开放 target-specific bounded entry/view ABI。匿名 Array/Map/Option/Bytes shared admission 与 target Array/Option 子集见 N-ANON-RESULT；Map/Bytes、target pureFn aggregate 与 Quint 容器仍 FC） |
| **N-5** | call **返回值** / typed external call（可能要升 semantic schema） | oracle/跨链 ack；大切片 | **done**（2026-08-02 RPT-014 完成 schema 研究；其 shared product follow-on 已由 N-CALL-RET 闭合，target residual 见 B-CALL-SEM） |
| **N-6** | true mutable locals（非仅 field/index rebind） | 循环携带聚合 | **done**（2026-08-02：let/for-binder bare `x:=e` env rebind；param 仍 immutable；SSA 新 ValueId） |
| **N-7** | match 构造器**嵌套子模式** | 完整 pattern | **done**（2026-08-02：递归 ctor/lit/bind 子模式 + N-A2 同外层；深度-2 VariantPayload 钉测） |
| **N-8** | Int event/error 字段；非 UInt64 call/schedule args 与 for 端点 | 宽度完整性 | **done**（2026-08-02：event/error 与 call/schedule args 开 legal UInt/Int；for 的 Int 余量后由 N-FOR-INT 闭合） |

### 2.2 矩阵 A 组（已编号，与上表重叠处合并执行）

| ID | 项 | 状态 |
|---|---|---|
| **N-A1** | EVM String `match` switch（N4 类型面已开） | **done**（2026-08-02：`a25365213` EvmStringMatch；matrix LOWERED） |
| **N-A2** | 多臂同外构造器 match 细化 | **done**（2026-08-02：`2a6c2bc9c` MultiArmCtor；shared Normalize + matrix 原六 target（EVM/Solana/NEAR/Noir/Aleo/Psy）LOWERED） |
| **N-A3** | Map/Bytes 穿透元素赋值 | **done**（2026-08-02：TypeCheck assign-target Map→value / Bytes→UInt8；Normalize 单步 IndexSet；嵌套 FC；target coverage 非均匀——EVM/Solana/NEAR/Noir/Aleo Map 已开并完成 snapshot 修复，Bytes 见 coverage matrix） |
| **N-A4** | Option state | **done（shared）**（2026-08-02：Normalize/Reference admit Option state/param + default none；当时九 materializer FC。后续 **B-OPT-STATE 已开八 materializer** `Option UInt64` state：EVM/Solana/NEAR/Noir/Aleo/Psy/CosmWasm/TON；**仅 Quint FC**；Option params/非 UInt64/nested 全 target 继续 FC） |

### 2.3 Reference / invariant 工程子集

| ID | 项 | 状态 |
|---|---|---|
| **R-1** | Reference 扩到 PureCall / aggregates / index / Int / Field / Principal / ContextRead / Commit | **done**（2026-08-02：Map empty-default admit + product IndexSet step；Option state product step；external UInt/Int 全宽；Map Reference budget 4096） |
| **R-2** | `evalInvariantV1` + `InvariantTheoremV1` 工程入口（非 formal theorem 完成） | **done**（2026-08-02：ABI 已接线；空 invariants OOR trap 钉测；theorem 形 Iff.rfl；非 formal corpus） |
| **R-3** | ProofBundleV1 safe loading（library only） | **done library**（2026-08-02：`openProofBundleV1`…；**2026-08-04**：产品 CLI 已删除 `--proof-bundle*`，本路径 **不是** check/build surface；formal TST-PROOF-001 仍 pending） |

---

## 2.4 剩余缺口登记（2026-08-02 文档↔代码复核新增）

下列缺口来自「done 切片的显式余量」与三方复核（SPEC×Normalize、op×target 矩阵、backlog done 声明）。
状态均为 `pending`，按序消费；共享核串行、target leaf 可并行。

| ID | 项 | 类型 | 说明 | 状态 |
|---|---|---|---|---|
| **N-ASSERT-ELSE** | assert-else（带 error 的 assert）Normalize+TypeCheck 接线 | 共享核（小） | EBNF `assert Expr (else Ident)?`；零参 error → `Op.Assert cond (some eid) #[]`；带参 error 源无法供参仍 FC；target Plan 对 errorId=some 保持 FC | **done**（pre-Wave-1 L1 lane；integration commit b059778fa） |
| **N-CONST** | `const` 声明 lowering → constants 表 | 共享核（小） | `evalConstDeclValueV1` 编译期求值字面量（UInt/Int±/Bool/String）→ canonical valueBytes（与 Op.Literal 字节一致）；声明值中的 place/binary/ctor/call/match 仍 FC；Reference admission 已消费 constants；body read 由 N-CONST-REF 闭合 | **done**（2026-08-02；integration commit 9a73a3287；Tests.Semantic.NormalizeConst 注册 Typed shard） |
| **N-CALL-RET** | typed call 返回值（sync call） | 共享核（大） | **done（2026-08-04，用户决策启动）**：source `call` 进值位置（`CallExpr ::= "call" ExternalCallExpr`，let 标注/return/operand；schedule 保持 statement-only）；TypeCheck 由外围 expected type 唯一钉 result（无 expected → typed error）；Normalize 降 result-bearing `Op.ExternalCall`（EffectId 序列共享，result 限 Bool/合法 UInt/Int 宽度/Bytes 标量，非标量 FC）；Wire step-j 条件 result（serializable scalar 否则 `.badCfg`；Schedule 保持 void）；Reference `ExternalResponseV1.returnValue?`（bind 精确 TypeId、callee revert → externalCallReverted、missing/mismatched → invalidExternalResponse）；Source 三处 closed table（childCardinality/isExpressionTag/permitsChildTag）补齐 `Expr.ExternalCall`；Provenance/SpanJoin/OriginJoin/NodeAssignment/RequirementsInfer/EffectCheck/Disclosure/Bound/CallGraph/AuthorityCustody/ContextExtension 全接线；**target follow-up 非均匀**：EVM 已开 UInt64 CALL returndata 校验，Solana 已开真实 CPI + UInt64 return-data 读取；两者 callee identity/外层账户 ABI仍属 B-CALL-SEM residual，其他 target 保持 FC/PARTIAL边界；SPEC language/semantic-wire 已同步 | **done**（shared-only，非 target returndata/formal D2/D4） |
| **N-ANON-RESULT** | 匿名容器（Array/Map/Option/Bytes）entry/view/fn 返回值 | 共享核 | Normalize/typed Semantic 已接纳四类 anonymous result TypeId；Reference 固定 Array/Bytes/Option/Map canonical valueBytes 与 Array-typed PureCall。**Target ABI 已开全部八 target**（2026-08-03：`Array UInt64 N`(1..8) 按 named struct 同序 flatten、`Option UInt64` tag+payload 双叶，复用 named 多叶路径零新 tag；EVM solc、Solana Mollusk 16B LE、NEAR sandbox 16B LE、Noir nargo 10 包、Psy psyup、TON locked-tolk .fif/.boc、Aleo leo build、CosmWasm cosmwasm-vm 精确 JSON 证据；诚实边界：TON entry FC（async actor 无返回通道）、Aleo view-over-state 经 computed-view 门 FC、Option UInt64 state 已开八 materializer（Quint FC）；Map/Bytes state 按 target 非均匀；Map/Bytes 返回、非 UInt64 元素/Int64 容器/嵌套/>8/pureFn 聚合均 FC） | **done**（2026-08-03；`ea74d132a` shared + 八 target lanes；非 formal D2/D4） |
| **N-NEST-IDX** | Map/Bytes 嵌套穿透赋值（`m[k].x:=v`、`b[i].…`） | 共享核 | Map 穿透已开：TypeCheck 递归 assign-target（Map index 任一步得 value 类型、field 经 named struct 解析）；Normalize 降 IndexGet→VariantPayload(1,0)→嵌套更新→IndexSet 回写；Reference 钉 present-key 写穿、absent-key `.invalidCore` trap 保 pre-state；`Map UInt64 Map …` 深穿透亦通。Bytes 穿透仍 FC | **done**（2026-08-03；`93ac5151b`；shared-only，非 target/formal） |
| **N-INVARIANT-IR** | invariant 进 Semantic callables/invariants | 共享核 | Normalize 将每个 `invariant name : BoolExpr` 降为零参 public-Bool `.invariant` callable + source-order dense `InvariantDecl`；复用 Wire sole closure membership 与 exact `invariantSteps` 公式，支持 pureFn closure 与 expression-match 多块 CFG；Provenance 覆盖全部 lowered block/instruction/value/terminator；`.proof` 仍仅为 certification metadata，同一 program 有/无 proof 的 semantic bytes/hash 相同；Quint 对 Q0 read-only Bool invariant 已 lowering；其余八个 materializer 对 nonempty invariants 继续 fail closed | **done**（2026-08-02；engineering，非 formal TASK-D2-06/07） |
| **N-STR-EVENT** | String 作 event/error 字段 | 共享核（小） | Normalize 现允许 public anonymous UInt/Int/String event/error 字段；String 字面量按 canonical `u32le(len) || NFC UTF-8` 降为 payload，located product compile 与 Reference Emit/Revert（ordered effect / declared rollback）已钉。九个 materializer 不发明 ABI：EVM/Solana/NEAR/Noir/Psy/Quint/CosmWasm/TON 在 target Plan 精确 FC，Aleo 在 `effect.event` resolver FC | **done**（2026-08-03；`c768d68c7`；shared-only，非 target ABI/formal D2/D4） |
| **N-FOR-INT** | for 端点 Int | 共享核（小） | Normalize 接受同宽 legal UInt/Int，按 endpoint TypeId 发 typed `<` 与同宽 `+1`，复用 exact back-edge `loopBounds`；Reference 固定 `[-2,2)`、`start≥end` 零趟、Int8 `126→127` 与 boundExceeded 全 state rollback。九个 materializer 不猜 signed range ABI：EVM/Solana/NEAR/Noir/Aleo/Psy/Quint/CosmWasm/TON 均在 target Plan 精确 fail closed | **done**（2026-08-03；`9ad021700`；shared-only，非 target Int loop/formal D2/D4） |
| **N-CONST-REF** | body 中 const place 引用 | 共享核（小） | constants lookup 在 fn signatures 后、任何 callable body 前完成，支持 forward ref；bare place 按 env→state→const 降为独立 value-producing `Op.Constant`，精确绑定 ConstantId/TypeId/ValueId；entry/view/pureFn/invariant、窄 UInt 合成与 authoritative Provenance（`.constant`/`.typeRef`/body place/Bool requirement）已钉。const 声明表达式仍仅 literal/negative Int；EVM/Solana/NEAR/Noir 对任意 nonempty constants 表 FC，Aleo/Psy 对实际 Op.Constant FC；post-declared novel const shape 有明确 engineering semantic-identity cutover，非 hash-stability/formal 声明 | **done**（2026-08-02；engineering，非 formal D2/D4） |
| **N-MAP-CONSTRUCT** | 非空 Map 构造 / wire multi-arg Construct | 共享核 | `Map.of(k0, v0, ...)` 变长构造器（NameResolution/TypeCheck/Normalize 已接线；expected Map 类型必需、偶数 kv 参数、positional K/V 精确）→ 单个 `Op.Construct`（flattened kv 对，source order）；Wire step-j 开偶数对（奇数/位置错/result 错/ctor≠0 → `.badCfg`）；Reference 为空 Map + 顺序 upsert（duplicate key last-wins 与 IndexSet 一致、canonical 值保持排序、允许运行期 key）；EVM/Noir 既有显式 FC，Solana/NEAR/Aleo/CosmWasm/TON 已补显式 nonempty-Map-construct FC（消除 Array 路径 arity 碰撞隐患），Psy 经 container 门 FC | **done**（2026-08-03；shared-only，target materialization 仍 FC，非 formal D2/D4） |
| **B-RET-ABI** | 原六 target aggregate ABI 返回（named struct/enum） | target leaf | N-4 done 的剩余；EVM+Noir LOWERED（≤8 UInt64/Int64 叶 preorder flatten；EVM tuple ABI + Noir per-leaf verifier inputs）；**Solana/NEAR 亦 LOWERED**（2026-08-03：Solana `ResultKind.aggregate`/`setReturnDataMulti` 单条 `sol_set_return_data` N×8 LE + IDL 叶数组；NEAR `MethodResultKind.aggregate`/`setReturnDataLeaves` 单次 `value_return` N×8 LE + near-abi 叶数组 + HostModel e2e）；**Aleo 非 Final entry LOWERED**（2026-08-03：Leo 原生 tuple 返回；Final 函数评叶后 drop 同 scalar 模型；multi-leaf view-over-state 经 computed-view 门保持 FC）；**Psy entry/view LOWERED**（2026-08-03：`[Felt; N]` 固定长 Felt 数组为诚实多叶源形式，psyup 真实验收 PairRet；叶继承既有 Goldilocks 文档模型）；anonymous Array/Option entry/view 已由 N-ANON-RESULT target lanes 开放；Map/Bytes返回、aggregate 参数与 target pureFn aggregate仍 FC | **done**（EVM/Noir：pre-Wave-1 L3 lane `b059778fa`；Solana：`5aeee9c17`；NEAR：`a82ec3fce`；Aleo：`e42d2e2e1`；Psy：`cc99484b3`） |
| **B-SOL-MAP-ELF** | Solana Map ELF 帧预算友好化 + MapMini Mollusk 升级 | target leaf | IR temp recycling + aggregate-store structural CSE；MapMini/Token 均 deployable ELF，Map put 峰值 177 temp≈1424B≤4096；MapMini 4/4 Mollusk active；**未提预算上限** | **done**（L2 + B-SOL-MAP-UPSERT；`put_into_empty` 已解除 ignore） |
| **B-CTX-OPEN** | ContextRead 各 target Plan 开放（unixTime/caller/blockHeight） | target leaf | **unixTimeSeconds**：EVM `timestamp()`（tag 59）+ NEAR `block_timestamp` ns÷10^9（tag 41）+ CW Env JSON time + TON `blockchain.now()` 已开；**Solana/Noir/Psy/Aleo/Quint 保持 FC**（电路域决策 2026-08-04）。**caller / ADR-0031 S1 已闭合（2026-08-06）**：EVM ADR-0025 `u32le(20)\|\|CALLER` + CallerCheck/Ownable Anvil；Solana 仅 exact CPI profile 的 `pf_caller` signer→32B Principal，ordinary Principal ix canonical gate + Mollusk 8/8，legacy profiles FC；NEAR `predecessor_account_id` init/entry + sandbox，view FC；CW `MessageInfo.sender` instantiate/execute + branch-local loader/charset gate + cw-vm，query/view FC。**blockHeight / ADR-0031 S2**：EVM `number()`（tag 62）、NEAR view-safe `block_index()`、CW Env JSON bare-u64 `height`（tag 55）、Solana ordinary-elf `Clock.slot` via `sol_get_clock_sysvar`（Plan tag 51；CPI product FC）Plan/IR/emitter leaves 均已开；EVM 已有 host-optional Anvil `BlockHeightCheck` 门；NEAR/CW/Solana 专门 runtime 门仍 residual | **in_progress**（caller S1 done；blockHeight 四 leaf + EVM Anvil 工程门 done，他链 runtime residual） |
| **B-OPT-STATE** | 九 materializer Option state Plan | target leaf | N-A4 只开 Normalize admit。**NEAR 已开**（2026-08-04 `95289615e`：`Option UInt64` state 复用 Enum 双叶布局（tag+payload 8B KV），none 默认零初始化、none 赋值清零 payload（HostModel+sandbox 双钉），match 走既有 VariantTag/VariantPayload 路径；Option params/非 UInt64 payload 仍 FC）；**EVM 已开**（2026-08-04 `0a46e54d8`：同构 2-slot 布局 + storeAtomic 沿用 B-EVM-MAP-STACK memory-spill 惯例，none 双叶清零，solc strict-assembly 验收 + Token 栈预算不变；Option params 不扩展）；**Solana 已开**（2026-08-04 `42c863d0c`：同构 `slot_tag`/`slot_p0` u64-le 布局 + 多叶原子 store，stale-payload clear 钉死，6 项 Mollusk 测试）；**Aleo 已开**（2026-08-04 `68d7c0a7f`：同构 tag+payload mapping 双叶（flatten-to-mapping），none 默认 get_or_use(0) 零初始化、payload 清零钉死，entry-surface match（multi-leaf view-over-state 仍 FC），OptionState 过真实 leo build）；**CosmWasm 已开**（2026-08-04 `da2f9ffe7`：同构 8B KV 双叶 + storeAtomic，none 清零 runtime 钉死，3 项 cosmwasm-vm 测试）；**Psy 已开**（2026-08-04 `a2755c6c9`：同构 Felt 双叶；顺带两修——VariantTag 窄 32 化使 Enum/Option match 可解、return-only 臂改 dargo expression-if；psyup 验收 10 fixture 全绿）；**Noir 已开**（2026-08-04 `27fa56c83`：同构双叶 + EmitIR brace-escape 共修（`}} else {` 非法输出），nargo 验收）；**TON 已开**（2026-08-04 `ac13b9b09`：同构 tag/payload c4 双叶 + storeAtomic，match 走 VariantTag/VariantPayload，Tolk 1.4 合法性共修（switchRegion 去 do-while/break、view 每臂早退 return），locked tolk→.fif 验收；Option params 仍 FC）；Quint 仍 FC（无 admit 路径） | done（8/9 materializer；Quint FC） |
| **B-COMMIT-ZK** | Commit × Noir/Psy | target leaf | EVM/Solana/NEAR/Aleo 身份透传已开；Noir/Psy FC | pending |
| **B-CALL-SEM** | call/schedule capability 与真实平台语义对齐 | 产品决策 + target leaf | **#111 Solana legacy honesty 已接线**：两 legacy profile 删除 sync/async support claim，Plan/IR/SBPF 纵深 fail closed（过渡空 AccountMeta CPI / log stub 不可达）。EVM 仍保留真实 `CALL`/returndata（BL-28）与 same-tx fire-and-forget schedule；NEAR/TON/CW/Noir/Psy/Aleo/Quint 纪律保持 main 现状。真实 Solana CPI 见 epic #110 versioned profile。不得把 resolver 支持键写成跨平台 call 完成 | **open**（Solana legacy 已诚实；产品 CPI 与他链缺口仍 open） |
| **CW-ABI-FREEZE** | CosmWasm A1 runtime/ABI design-exit | 产品/target semantics 决策 | 已由 **CW-5** 闭合：versioned std/vm/check 3.0.9 + wasmvm 3.0.7 + wasmd v0.70.3 dispatcher 语义冻结；structural-WAT 工程先导批准；`wasm-validated-alpha` 限定 mock 子集。历史 A0/no-dispatch 叙述作废 | **done**（见 CW-5；非 formal） |
| **DOC-ADR-SCOPE** | accepted 范围与工程控制面 reconciliation | 文档/产品决策 | accepted PRD 仍以 EVM/Solana/NEAR/Noir 为 Phase 1，工程 registry 已 9 implemented（Aleo/Psy/Quint/CosmWasm/TON 含 materializer）+ 3 design-only；accepted ADR-0022/架构仍要求 contained frontend，而 B11/B12 已删除。不得直接重写 accepted 文档；需新增 accepted ADR 或正式修订，明确 accepted 4 → engineering 9 implemented (including Quint/TON) 与 frontend assurance 取舍 | pending（**产品决策**） |
| **DOC-JUST-CONTROL** | 文档引用不存在的 governance/release recipes | 文档/发布决策 | `AGENTS`/`RECOVERY`/README/CONTRIBUTING/qualification inventory 曾把 `just governance-check` / `just release-check` 写成当前命令，但本分支及已知 `origin/main` 的 `justfile` 均无 recipe。现已纠正当前文档为“不可执行”；若要恢复，必须显式设计 recipe、测试与资格边界，禁止临时拼装命令冒充 gate | pending（**产品/发布决策**） |
| **B-FIELD-CATALOG** | Field 真 catalog 接通 Aleo(BLS12-377)/Psy(Goldilocks) | 共享核+leaf | DOC-CODE-1 已决策：**真做 T14**；Wire FieldSpec catalog sole bn254 → 三 spec（bn254/BLS12-377/Goldilocks，exact id+modulusBE membership，无任意 modulus）+ TypeKey allowlist + Source/TypeCheck Field id + Normalize catalog 镜像 + Aleo bls12_377_fr→Leo field + Psy goldilocks→Felt + Reference fieldModulus 参数化 | **done**（2026-08-02；T14 lane 0f4d9e294 + field-id 测试修复；typed/targets/source shard 绿） |
| **B-SOL-MUL** | Solana UInt128/256 真多字 mul/div/mod | target leaf | SBPF `narrowCheckedMul` 128/256 使用 schoolbook 多字乘（32-bit digit split、lane-ordered carry、高肢 overflow trap）；follow-up `910835aa4` 将 div/mod 从 low64 gate 切为 exact restoring binary long division（2/4×u64 limbs，divisor-zero trap、lhs/rhs alias-safe scratch、quotient/remainder exact）。WideMul Mollusk 覆盖 mul 成功/溢出；WideDiv/WideDiv256 以独立 Rust oracle 覆盖 8 个成功/零除全账户回滚；WideDivDispatch 以近距 branch stub + BPF-to-BPF call 组合四宽 handler，并由 locked `sbpf` + Mollusk 执行最远 handler。 | **done（production arithmetic + host-optional runtime leaf）**（mul `9bb6fe1ad` + runtime `de72b46fa`；div/mod `910835aa4` + wave3 runtime；非 formal/hermetic） |
| **RES-1B** | memory/output 运行时 limit | NFR | **output-only 子切片已交付**：build `artifact-output.published-bytes` lower-only effective cap，按 pre-scan base+extra 与 exact evidence/manifest UTF-8 总量在 sidecar write/rename 前强制；over → `PF-RESOURCE-OUTPUT`/exit 6、清 staging、零 destination。memory/process/protocol/stderr 与 receipts/containment 仍无 producer | pending（output-only done；其余 pending） |
| **B-SOL-MAP-UPSERT** | 聚合 StateStore 顺序 store-then-read hazard（Map empty upsert） | target leaf（正确性） | 已实证 EVM/Solana/NEAR/Noir cap-8 与 Aleo cap-2 同构：leaf Expr live-read 已部分写 state。五 target 均改为 target-owned atomic aggregate store：同一 Semantic StateStore 全叶先基于 pre-store snapshot 求值、再统一写；不同 StateStore 保持顺序可见。Solana structural CSE 保持 1424B frame，`map_mini_put_into_empty` 真实 Mollusk 转绿；EVM Yul 顺序、NEAR HostModel、Noir relation model、Aleo Leo get-before-set 均钉测 | **done**（2026-08-02；非 formal） |
| **B-MAP-STRUCT-PIN** | Map atomic-store 结构与跨 batch 可见性补钉 | target tests（P2） | Solana MapMini production Plan/IR 固定单个 24-leaf `storeAggregate`/`storeStateMulti` 且无 scalar store；Token 固定多个独立 24-leaf batch，并要求 batch 间重新 load。EVM Token 同样固定多个 `storeAtomic(24)`，每批内部无 `sload`、批间重新 `sload`；Solana SBPF 继续守 4096B frame gate | **done**（2026-08-02；commit `ff61d3e13`，非 formal） |
| **B-EVM-MAP-STACK** | EVM dense Map `storeAtomic` solc stack 峰值 | Evm emitter + target tests | 每个 leaf 在 nested Yul block 中求值并 spill 到 `0x10000+32*i`，全部 leaf 完成后再连续 `mload`→`sstore`；保留 pre-store snapshot 与跨 batch 顺序。`EvmSmoke` 固定 24-leaf 结构，`EvmSolcAcceptance`/`TokenV1` 要求 shipped Token 通过 solc/finalization；runtime 不再把 build/StackTooDeep 回归当 skip。Token creation bytecode 258460 B 超 EIP-3860，deployment/runtime/OZ 仍未闭合 | **done**（2026-08-03；engineering compiler/finalizer only，非 formal D4） |
| **NFR-REPEAT** | NFR-001 决定性 repeat gate（连续构建 hash 相同） | NFR | `scripts/nfr_repeat_gate.py` 同机同 binary 连续构建 Counter：Solana 默认 `solana-sbpf-plan-v1` ×2 + Noir 默认 profile ×2；每树独立重验 exact closure/descriptors/evidence，再要求 `manifest.json`/`evidence.json` exact bytes；no-tool mutation self-test；`just nfr-repeat` 进入 ordinary `ci-target-smoke` | **done**（2026-08-03；仅 engineering subset，非 hermetic/clean-room/multi-host/full-target/formal NFR-001/TST） |
| **DOC-CODE-1** | **T14 Field catalog v2 文档↔代码矛盾** | 文档/代码决策 | commit 30df771f2 声称「Wire ModelV1 扩 bls12377/goldilocks FieldSpec + Aleo/Psy Field 接线」，实际 diff 只有 NEAR/Solana 文件+docs；**代码 catalog 仍 sole bn254**（EnvelopeV1/WireV1）。AGENTS.md 已先行修正为 fail-closed 叙述。需要产品决策：(a) 按 commit message 真做 T14（共享核 Wire 变更）；(b) 把 30df771f2 的 commit message 记录为错误声明并关闭 | **done**（2026-08-02：选 (a) 真做 T14，已由 B-FIELD-CATALOG 闭合；见 T14 lane 0f4d9e294） |
| **SYS-CAP-SURVEY** | 多链系统能力全景调研（host function / runtime API / 官方链上 program） | 调研 | RPT-020（2026-08-05）：平台分**状态类**（EVM/Solana/NEAR/CW/TON/Soroban/ICP 直接读链）vs **电路类**（Noir/OpenVM/Psy 只能 input/witness/oracle 注入 + 电路约束；混合 Aleo finalize 可读链）；时间戳/区块高度/调用者/自身余额/附加价值/链 ID 六维在状态类平台高度同构；随机数有偏不可靠、质押/治理/IBC 属业务能力，均不宜进 ContextRead；**系统能力分两层**——L1 内建运行时（host/syscall/opcode/stdlib）+ L2 官方链上 program（builtin/system contract/precompile/management canister/链模块），同一能力在不同链形态不同（sha256：EVM precompile vs Solana sol_sha256 vs NEAR host vs TON string_hash），统一抽象=能力与形态解耦 | **done**（2026-08-05 调研落盘：RPT-020 `docs/research/20-host-function-survey.md` + `system-capabilities-evm-solana.md`；RPT-021 `21-system-programs-survey.md` 官方 program 层；research README 已登记） |
| **SYS-CAP-UNIFY** | 系统能力统一抽象（L1 ContextRead/EnvRead catalog 扩键 + L2 官方 program 能力 catalog） | 共享核 + leaf | ADR-0031 已冻结两层 catalog、view-safety 与 L2 强制等级。L1 依 E2 纪律逐行推进：S1 `context.caller` **engineering done**（EVM CALLER、Solana exact-CPI signer role、NEAR predecessor、CW MessageInfo；各自 runtime 门与诚实 FC 边界已闭合）；S2 `context.blockHeight` shared + EVM `NUMBER` / NEAR `block_index` / CW `Env.block.height` / Solana ordinary `Clock.slot` leaves 已完成（CPI product 仍 FC Clock）；S2 target runtime 门待接；S3 chainId、S4 attachedValue、S5 `pf.crypto.sha256` 后续。L2 将 Solana official programs、EVM precompile/系统合约、TON/ICP/Aleo/CW 官方能力逐行 exact catalog + per-target 物化；无对应物与电路锚定值继续 FC | **in_progress**（S0 design + S1 done；S2 leaf 4/4 ordinary、runtime residual；不声称 formal/跨链完整） |

### 复核结论存档（2026-08-02）

- **backlog done 声明可信度**：对「本切片自承范围」大体可信（诚实注释在）；但「子集 done + 显式 residual」大量未挂 ID，可执行完整性偏低——上表已补齐。
- **research/13** §2/§5 已过时，本次已刷新对齐 HEAD。
- **research/12** 矩阵约 9 格已修正（Aleo Map/Bytes/aggregate/Array LOWERED、Noir Array LOWERED、B-1b/B-1c 行重写）。
- **Aleo/Psy dossier** T14 污染已修正为 fail-closed 叙述。

---

## 3. T9 宽度 / identity 切片（见 roadmap-t8）

| ID | 项 | 状态 |
|---|---|---|
| **T9a–T9c-2** | 窄结果 / EVM UInt128·256 / 窄 Int 四 target | **done**（roadmap merged） |
| **T9d** | NEAR/Solana/Noir `planDigest` 绑 BuildIdentity/OutputSet（镜像 M4） | **done**（`c3626725f` / roadmap 2026-08-01） |
| **T9e** | Solana/NEAR UInt128/256 多字算术（先设计后实现，可拆） | **done**（2026-08-02：T9e-Solana `52f527140` + T9e-NEAR claimed on main） |
| **T9-0** | 控制面/roadmap 状态对齐 | **done**（2026-08-02：roadmap merged `93b80db45` / control-plane status；矩阵长表状态已对齐） |

---

## 4. Target Plan/IR/emitter 覆盖（可按文件隔离并行）

| ID | 项 | 文件边界 | 状态 |
|---|---|---|---|
| **B-1a** | NEAR named 聚合 + Array/容器 lower 或显式 FAIL-CLOSED+测 | `Targets/Near/**` | **done**（`4c79e0a59` NearAggregate） |
| **B-1a2** | NEAR named Struct/Enum（B-1a 余量） | `Targets/Near/**` | **done**（2026-08-03：L1 lane `integrate/w1-all`；preorder 扁平 UInt64/Int64 KV leaves + construct/fieldGet/fieldSet/variantTag/variantPayload + atomic storeAtomic；HostModel PointBox/EnumBox 端到端；该 lane 当时聚合返回/Option state FC，后续已分别由 B-RET-ABI 与 BL-30 开放 bounded aggregate return / `Option UInt64` state；ContextRead 仍 FC） |
| **B-1b** | Noir named 聚合 | Noir/** | **done**（`61b7dff09`） |
| **B-1b2** | Noir Bytes state（B-1b 余量） | Noir/** | **done**（2026-08-03：L3 lane `integrate/w1-all`；Bytes N→N×UInt8 leaves + literal IndexGet/Set + atomic storeAggregate；Bytes construct/param/动态索引仍 FC） |
| **B-PSY-BITNOT** | Psy UInt64 `~`（矩阵 unary 粒度偏差） | Psy/** | **done**（2026-08-03：L4 lane `integrate/w1-all`；`checkedBitNot` = assert `x ≥ 2^32−1` + Felt sub `(2^32−2)−x`，可表示半区精确语义、其余运行时 trap；Int64 `~` 仍 FC） |
| **B-1c** | Aleo 覆盖核对 + 显式边界 | Aleo/** | **done**（`04fe6e815`） |
| **B-1d** | Solana Map/Bytes/Option state：open 或钉死 FAIL-CLOSED | Solana/** | **done**（2026-08-02：Array + **Map UInt64 dense pilot** cap-8；默认仍 plan profile，opt-in ELF+Mollusk 已通；aggregate CSE/storeStateMulti 修复 empty upsert，MapMini 4/4 active；Option 中间值自 Map IndexGet；**Bytes 已随 B-1d2 开放，`Option UInt64` state 后由 BL-29 开放**） |
| **B-1d2** | Solana named Struct/Enum + Bytes state | Solana/** | **done**（2026-08-03：L2 lane `integrate/w1-all`；named 聚合 flatten + Bytes N×UInt8 state/params + atomic storeAggregate/storeStateMulti；4096B frame 硬门保持、plan/ELF 绿；该 lane 当时聚合返回/Option state FC，后续已由 B-RET-ABI/N-ANON-RESULT 与 BL-29 开放 bounded return / `Option UInt64` state；Bytes construct/ContextRead 仍 FC） |
| **B-1e** | EVM Map/Bytes/Option state：同上 | Evm/** | **done**（2026-08-02：Array EvmIndex + Bytes D4-E2；**Map UInt64 dense pilot** cap-8 + Token locked-solc finalization；creation bytecode 超 EIP-3860，chain deployment 未闭合；Option-from-Map 当时仅中间值，后续 BL-31 已开 `Option UInt64` state；EVM/Solana/NEAR/Noir/Aleo Map 横向已开并闭合 aggregate snapshot hazard） |
| **B-1f** | Noir Map multi-leaf public inputs | Noir/** | **done**（2026-08-02：Map UInt64 cap-8 occ/key/val public-input leaves + IndexGet→Option + IndexSet upsert + Token relations；Array 已开放，Bytes 随 B-1b2 开放 fixed state + literal IndexGet/Set；Option/String state 与 Bytes construct/param/动态索引仍 FC） |
| **CW-A1** | CosmWasm target-owned Plan/IR/materializer after registry A0 | `Targets/CosmWasm*` + Registry/umbrella/tests/SBOM | **done**（见 §10 **CW-1**：`Registry.materializeResult` 已有 `.cosmwasm` dispatch；Counter 纵切 Plan/IR/WAT+Wasm；sync 拒、async SubMsg 子集见 CW-4；ABI freeze 见 CW-5；非 formal） |
| **B-3** | Principal/address-bearing 与 EVM/Solana call/schedule | Envelope + EVM/Solana | **done**（2026-08-02：PrincipalAddr 固定 wire Principal ≠ EVM 20B / Solana 32B pubkey，不做 approximate 映射；AddressBearing 仍以 static QualifiedName callee 独立开放，非 dynamic address）。**ADR-0025 realization（2026-08-06）**：EVM `context.caller` 已按唯一 valueBytes `u32le(20)\|\|CALLER` 接入 Plan/IR/Yul 与 Anvil；shared TypeShape/codec 不变，T10 storage 仍为 wire-identity leaf；**不**把 Principal ValueId 变为 CALL 目标，PF Ownable primitive pass 也**不**提升 OZ F01 family/ABI credit | **#111：Solana legacy call 观测桩已 supersede 为 fail closed** |

| **B-ctx** | ContextRead 各 target Plan：closed baseline + per-key 原子开放 | 九 materializer | **done / superseded by SYS-CAP-UNIFY**（2026-08-02 的九 materializer FC matrix 是历史基线；随后 unixTime 已按 target 开放，2026-08-06 ADR-0031 S1 首先完成 EVM caller。其余 target/key 只能经版本化 requirement + target-owned Plan/IR/runtime 门逐行开放；未知 key、未交付 lane 与电路锚定值继续 FC） |

### 验收门（工程，非 formal）

| ID | 项 | 状态 |
|---|---|---|
| **C-1** | NEAR Wasm 工具链 load + sandbox 工程子集 | **done**（2026-08-02：`672e6115d` NearWasmAcceptance = locked `wat2wasm` + host-optional `wasm-interp`/`wasmtime`/`wasmer` load，工具缺席 skip；2026-08-03 C-6 另加 locked near-sandbox Counter happy path；均非 formal Reference differential） |
| **C-2** | Aleo/Psy compiler/VM 可用性研究与是否升格验收 | **done**（2026-08-02：RPT-015 保持 source-only；2026-08-03 G123/C-2-pin 后 Aleo 已有 locked leo 4.0.2 compile-only 门，但仍无 VM/prove/deploy；Psy 仍无 Tool Lock/VM） |
| **C-3** | EVM Reference↔Anvil **formal** 差分 | blocked（formal 轨道；G4 产品 CLI→Anvil 工程差分已覆盖四程序，但未绑定正式 Reference corpus/identity） |
| **C-4** | Noir 真实电路证明/prove 路径（若工具链锁定可行） | **done（研究决定仍有效）**：2026-08-03 G123 已锁定 nargo 1.0.0-beta.26 并接 `NoirCompileAcceptance` compile-only 门（C-7），supersede 原“无 nargo pin”观察；Barretenberg/backend、CRS/security profile、witness/prove/verify 与 proof binding 仍无，因此不升格 prove/verify、保持 source-only；见 `16-noir-prove-path.md` |
| **C-5** | Solana 已有 Mollusk；扩 fixture 跟 Normalize 新面 | **ongoing**（Counter + 18 fixtures = 19 programs；#111 移除 CpiCaller；**#113** V1 单账户安全负例矩阵；OptionState 与聚合返回保留；manifest-bound artifact 读取已接线） |
| **C-6** | NEAR near-sandbox receipt 工程门（G123） | **done**（2026-08-03：near-sandbox 2.13.0 入 `tools[]`（darwin+linux，Darwin 捆绑 xz/liblzma）；`scripts/near_sandbox_acceptance.sh` deploy/init/mutate/view 真实通过；`NearSandboxAcceptance` 注册 shard-targets；非 formal Reference↔sandbox / Stage-0） |
| **C-8** | NEAR sandbox 全差分 harness（Counter + 聚合返回 + overflow） | **done**（2026-08-03；`971e27a76` + `be8842962`：`runtime-tests/near` 薄 Python JSON-RPC/borsh-Ed25519 客户端（pin cryptography 47.0.0 + base58 2.1.1）+ `scripts/near_runtime_test.sh`；Counter init/increment/get + overflow state-hold + recovery；PairRet named 聚合返回与 ArrayRet/OptionRet 匿名容器返回 e2e 精确 16B LE 断言；独立 sandbox homes、skip-clean；engineering differential，非 testnet/mainnet/formal） |
| **C-7** | Noir nargo compile-only 工程门（G123；RPT-017 最小路径） | **done**（2026-08-03：nargo 1.0.0-beta.26 入 `tools[]`；`scripts/noir_compile_acceptance.sh` 产品 Counter 三 relation 包真实 compile 通过；`NoirCompileAcceptance` 注册 shard-targets；barretenberg 仍 null，**不**升格 prove/verify；`validate_artifacts.py` 仍拒 proof-stage 叶） |
| **C-8** | EVM Anvil 工程差分加固（G4） | **done**（2026-08-03：Counter/Accumulator/ArithOps/EventFlow 产品 CLI 制品 + overflow revert 状态不变（view+storage 双读）+ EventFlow emit 日志断言真实通过；B-EVM-MAP-STACK 已修复 Token 的 solc StackTooDeep，但 258460 B creation bytecode 超 EIP-3860，Token companion 仍仅可按部署上限 explicit skip；非 formal C-3） |
| **EVMOZ-001** | 显式 Cancun EVM profile（shared） | **done**（2026-08-03：`evm-yul-solc-0.8.34-cancun-v1` 进入 registry/descriptor/resolver/Tool Lock；Finalize 仅 Cancun 加 `--evm-version cancun`；runtime `PF_EVM_PROFILE` → `anvil --hardfork cancun`；默认 legacy v1 不改写；同一 solc 0.8.34/Anvil 0.3.0；**非** OZ claim / formal D4 / 工具升级） |
| **EVMOZ-002** | closed EVM corpus case/observation schema | **done**（2026-08-03：`proof-forge.evm-corpus-case.v1` / `evm-observation.v1` + `scripts/evm_corpus_v1.py` PF-JCS validator + schema-tests；**非** formal evidence / OZ claim） |
| **EVMOZ-003** | ADR-0025 EVM `context.caller` encoding freeze | **done**（2026-08-03：sole spelling `u32le(20)\|\|CALLER`；不解锁 Plan/ABI/Ownable F01；见 B-CTX-OPEN / B-3） |
| **EVMOZ-004** | primitive + Token adapter business cases + Reference/Anvil harness | **done**（2026-08-06 更新：5 primitive + 1 adapter cases；Reference 28 obs；新增 `pf.primitive.ownablelike.caller-admit.v1` 的 owner/stranger/rollback PF-Anvil closure；Token 仅因 EIP-3860 部署上限允许 explicit skip；**非** formal C-3 / OZ） |
| **EVMOZ-005** | Ownable-like caller boundary | **done / blocked case retired**（2026-08-06：`OwnableLike.lean` 从 ContextRead planInvariant blocker 升为 EVM caller primitive；历史 `oz.f01…blocked.v1` 删除，`EvmCorpusBlockedV1` 保留文件名但改为 Loader/Normalize/Reference + Plan/Yul admit pin。F01 OZ family 仍 Blocked：无 OZ behavior leg/标准 address+event+error ABI） |
| **EVMOZ-006** | corpus manifest + CI registration + real Ownable pins | **done**（2026-08-06：manifest exact inventory 50 entries / 13 runners；6 business cases / 6 runnable；Ownable source/semantic pins保留；`just evm-corpus-{schema,reference,static,runtime}`；static 进 `dev-check`/`ci-lean-product`，runtime 不进 ordinary CI；**Exact 0 / Partial 0 / Blocked 20 不变**；无 OZ leg） |
| **C-2-pin** | leo 4.0.2 Tool Lock pin（G123） | **done**（2026-08-03：leo 4.0.2 入 `tools[]`（darwin+linux）；`aleo_acceptance.sh` 优先 Tool Lock 解析；仍 source-only + optional compile，非 prove/deploy） |

---

## 5. Wave 3：D3 identity / output 工程→规格对齐

工程 S4–S7c 已接线；下列是**与 accepted 规格仍差的产品形态**（非立刻 formal done）：

| ID | 项 | 状态 |
|---|---|---|
| **D3-E1** | 产品可达 formal-layout `registryDigest` / root codec（或明确永久工程-only） | **done**（2026-08-02：**永久工程-only** 决策 — 产品不暴露 formal `registryDigest`；`TargetRegistryV1` 无 root digest 字段；见 `RECOVERY.md` D3-E1 段） |
| **D3-E2** | SupportClaim/decision 全字段与 resolver 决策面 | **done**（2026-08-02：**工程** `EngineeringSupportClaimV1` + `mintEngineeringSupportClaimsV1` + resolver/describe-target `claimDigest` + `Tests/Materialization/IdentityChainV1`；domain `pf.support-claim.engineering.v1`；**非** formal SupportClaim/predicate/evidence grade） |
| **D3-E3** | 可达 BuildIdentity mint + Plan/IR digest 全 target（T9d 子集） | **done**（2026-08-02：工程 `mintEngineeringBuildIdentityV1` + EVM/Solana/NEAR/Noir planDigest；Aleo/Psy engineering-absent slot；`IdentityChainV1` 钉四 target 匹配 + absent；**非** formal BuildIdentity） |
| **D3-E4** | formal `OutputSetV1` 字段齐套；退役 transitional v2alpha1 残留 | **done**（2026-08-02：**工程** on-disk 已是 `proof-forge.output.v1` + `mintEngineeringOutputSetV1`；legacy `proof-forge-output/v2alpha1` renderer 已删并由 OutputSetV1 suite 钉零；`sourceHash`/`semanticHash` 键名仅为兼容；**非** formal OutputSetV1 字段齐套） |
| **D3-E5** | CLI 剩余 flag：evidence/resource override 等 SPEC-CLI 面 | **done**（2026-08-02：`--resource-limit`…；`--minimum-evidence` build-only；**2026-08-04**：structural `--proof-bundle*` 产品 flag 已删，sole proof gate = inline certifier；check/build JSON 可观测 `resourceLimits`；非 formal SPEC-CLI） |
| **D3-E6** | stage supervisor / receipt（compiler-core/tool/output）——与 D1 监督层移除决策协调 | **done**（2026-08-02：**永久进程内** — 不恢复 SafeOpen/supervisor 产品路径；sole Loader 进程内；RES-1 wall 与 RES-1B published-bytes 均进程内，其余 resource producer 仍 pending；见 `RECOVERY.md` D3-E6） |
| **D3-E7** | artifact 内容绑定与 post-publish inspect closure | **done**（2026-08-03：`ArtifactContentV1` sole walker/stable-read/hash → private canonical inventory；engineering manifest `files` 原子迁为 `role/path/size/contentSha256` descriptor，并绑定 exact evidence UTF-8 `evidenceSha256`；pure OutputSet mint；publisher sidecar 前后 inventory compare + manifest-last closure；`inspect <output-dir>` 重开 artifacts并重走 no-follow/single-link exact disk closure；legacy path-only fail closed；Python validator同构；**仅 stable observation，非 race-free/hermetic/formal OutputSetV1**） |
| **D3-E8** | `--minimum-evidence` 进入 resolver/claim | pending：当前只解析、白名单和 JSON 回显，不参与 support decision、claim 或 manifest identity；需先冻结 evidence grade 语义，禁止把回显写成门禁 |
| **D3-E9** | Protocol descriptor axes ↔ TargetRegistry axes 一致性门 | **done**（2026-08-03：`TargetDescriptor` 直接复用 registry-owned `*V1` 六轴；`semanticsAxesOfKindV1` 为 frozen product seed，八个 registry-implemented descriptors（含 CosmWasm/TON Plan/materializer leaf）补 profile/artifact-encoding metadata；`validateDescriptorAxesJoinV1` 在 capability resolve、artifact mint、CLI target inspect 前 exact join；Protocol 重复 axis inductive 物理删除并由 `TargetRegistryV1` suite/deletion gate 固定；**非** formal TargetSemantics payload/digest） |

---

## 6. Wave 4：Target completion（D3 冻结后，EVM-first）

| ID | 项 | 状态 |
|---|---|---|
| **D4-E1** | EVM Plan schema/canonical hash/BuildIdentity 绑定完整 | **done**（2026-08-02：工程 `engineeringEvmPlanDigestV1` + PlanSchemaV1 + BuildIdentity planDigest 绑定；`Tests.Materialization.EvmPlanSchemaV1` + IdentityChainV1；**非** formal TASK-D4-01） |
| **D4-E2** | EVM 完整 Semantic→Plan 表面（非仅当前 pilot 集） | **done**（2026-08-02：Bytes N leaves + **Map UInt64→UInt64 dense pilot**（8×occ/key/val、动态键 upsert、Option match、effect-boundary free-set promote）；Token/MapMini 可走 EVM Plan/Yul/locked-solc finalization，但 Token creation bytecode 超 EIP-3860、无链上部署闭环；非 formal 全 Semantic 面） |
| **D4-E3** | TargetIR schema/validator/hash/trace | **done**（2026-08-02：工程 `validateEvmTargetIRV1` 结构门 + `lower`/`emitFromIR` 接线；Yul/ABI size/brace/marker；**非** formal TargetIR grammar/solc 等价） |
| **D4-E4** | locked solc + OutputSet 角色齐套 | **done**（2026-08-02：locked solc FinalizeV1 + engineering OutputSet `proof-forge.output.v1` + EvmSolcAcceptance；**非** formal OutputSetV1 角色齐套） |
| **D5+** | Solana / NEAR / Noir 里程碑拆分（ELF/runtime/prove 按 dossier） | **done（meta 拆分）**：Solana ELF+Mollusk 已有；NEAR=C-1+C-6（sandbox happy path，非 formal differential）；Noir=C-7 compile-only + C-4 prove 不升格；fixture 增长=C-5 ongoing；**非** formal D5–D7 完成 |

---

## 7. Typed / requirements 边角（Check 已七相位，仍缺轴）

| ID | 项 | 状态 |
|---|---|---|
| **T-1** | authority / custody 轴（`TST-VIS-002` 工程子集） | **done**（2026-08-02：`AuthorityCustodyCheckV1` — entry 写 private state 需 `context.caller` 权威证据；`reqPrecondition` 非 PF-VIS-001；CheckV1 phase 6；**非** formal TST-VIS-002） |
| **T-2** | context / extension requirements 接入 CheckV1 | **done**（2026-08-02：`ContextExtensionCheckV1` — 仅 admit context.caller/unixTimeSeconds；extension 声明工程 Check `ext001` fail-closed；CheckV1 phase 7；**非** formal extension catalog） |
| **T-3** | RequirementsInfer：callerContext / commit 等贡献键（随 N-2/N-3） | **done**（2026-08-02：context.unixTimeSeconds/caller + commit 贡献 wire id；S2 freeze skip；Normalize 仍 sole wire-row mint） |
| **INV-1** | 受约束 `proof` reference 产品路径（FR-002） | **superseded → ADR-0027 inline；narrow engineering closed**（2026-08-04：产品 sole path = `selectProgramV1ProductWithTheoremInventory` → `certifyInlineProofV1`；`--proof-bundle*` unknown；check 输出 proofStatus/count/digest，build 只门禁；`ProofReferenceJoinV1`/bundle 退回 library；structure+encode+decode+`ProofedProof.safe`、legal-only simple-closure encode/decode、exact ordinal-0 `InvariantTheoremV1` 与 literal-true/public-Bool-view same-file ordinary theorem 的真实 product `check` certified 正例均闭合；false theorem/inventory/audit fail closed，proof-first 且零 staging；body 不改 source/semantic hash但改变 cert digest；package-owned session 排除 ambient `LEAN_PATH`/用户 `.olean`；in-process elab ≠ sandbox；axioms 仅 Classical.choice/Quot.sound/propext；**非** formal TST-PROOF-001 / reachability / target refinement / hermetic/release；Quint Q0 对 read-only Bool invariant 已开放，其余八个 materializer 对 nonempty invariants 仍 FC） |
| **APP-1** | PrivateSum4 持续作为隐私边界验收向量（Phase-1 DoD） | **done**（2026-08-02：`Examples/PrivateSum4` + `Tests.Product.PrivateSum4PrivacyV1` — product compile/CLI check·build 对 private→public `PF-VIS-001` fail closed、无 manifest 泄漏；**非** Noir prove/formal TST-NOIR-006） |

---

## 8. 性能 / 资源（NFR，常被特性审计忽略）

| ID | 项 | 状态 |
|---|---|---|
| **PERF-1** | NFR-007：`PerformanceProfileV1` 上 1000-node check 测量 harness（不宣称增量编译） | **done**（2026-08-02：`scripts/perf_check_harness.py` + `Tests.Product.PerfCheckHarnessV1`；工程 cold-sample p50/p95 报告、**不**声称 NFR-007 预算 / formal TST-PERF-001 / 增量编译） |
| **RES-1** | NFR-008：check/build 显式 time/memory/output limit flags（与 D1 监督层移除后的进程内路径协调） | **done**（2026-08-02：进程内 wall-ms 强制 `enforceWallMsLimitV1` 于 check/build 成功路径；`PF-RESOURCE-TIME` exit 6；ResourceFlagsV1 pure+CLI pin。2026-08-03 published-bytes 由 RES-1B output-only 子切片补入；memory/process/protocol/stderr 与 formal NFR-008 仍未闭合） |

---

## 9. Formal / release（独立轴，不阻塞产品切片）

| ID | 项 | 状态 |
|---|---|---|
| **F-*** | D1–D4 formal 0/27；`TASK-D1-01` blocked | 不进日常队列 |
| **Q-*** | SBOM ceremony / eligible-host / clean-room / custody | 独立 formal/release 轴；`release-check` 当前无 recipe，见 DOC-JUST-CONTROL |

---

## 推荐击杀顺序（产品开发）

```text
0. ~~既有 DOC/T8–T14/Normalize 主轴~~（已完成；formal 状态不变）
1. ~~2026-08-02 P0 审计修复批~~：
   - BUILD-10：六个 ordinary-CI 漏注册 suite 接入 Typed/Targets shard
   - proposed current-path 文档：删除 B12 现状误述，保留 accepted ADR 决策债
   - B-SOL-MAP-UPSERT：EVM/Solana/NEAR/Noir/Aleo 五个 target-local snapshot 修复；Solana 真实 Mollusk 转绿
2. **必须先决策**：B-CALL-SEM（降 support 或实现真实 call/schedule）+ DOC-ADR-SCOPE（accepted 4 target → engineering 9 implemented (including Quint/TON) / frontend assurance）；~~CW-ABI-FREEZE / CW-A1~~ 已闭合（见 CW-1/CW-5）
3. ~~N-INVARIANT-IR（消除 invariant 静默丢弃）~~已完成；~~D3-E7（artifact 内容 hash/inspect closure）~~与~~D3-E9（descriptor axes exact join）~~已完成；identity residual 仅余 D3-E8，且需先冻结 evidence-grade 语义
4. ~~N-CONST-REF~~、~~N-STR-EVENT~~、~~N-FOR-INT~~、~~N-ANON-RESULT~~、~~N-NEST-IDX~~、~~N-MAP-CONSTRUCT~~与~~N-CALL-RET~~已完成；**剩余串行语言面**：无（语言面切完；真实 returndata/CPI lowering 属 B-CALL-SEM target 工程）
5. **可并行 target leaf（接口冻结后）**：B-COMMIT-ZK / B-CTX-OPEN residual（S1 caller 已于 2026-08-06 在 EVM/Solana-exact-CPI/NEAR/CW 闭合；S2 `blockHeight` 四 leaf 已开；residual 为 S2 runtime gates、Solana CPI-profile Clock、S3/S4 keys；TON 仅 unixTime，电路类/Quint 继续 FC）。E4 前置中的 Solana Principal-key Map 与 UInt128/256 div/mod Mollusk 已闭合；residual 为 Solana MiniAMM 产品镜像/Mollusk 应用门、真实 asset movement/remove-liquidity，以及 EVM 无 code-size override 的正常部署闭环
6. **NFR / identity residual**：D3-E8 → RES-1B memory/process/protocol/stderr residual（published-bytes output-only 已完成）；~~D3-E9~~与~~NFR-REPEAT~~已完成（后者为同机双 target 工程子集）
7. 语言面够用后：NS-2 / EXT-CRYPTO（仍 language-gated）
```

**切片纪律**（继承 roadmap-t8 / AGENTS）：

1. 一次一个 shared-core cutover；leaf 可 worktree 并行且文件 allowlist 零重叠。  
2. 先失败测试再最小实现；不新增 formal `TASK-*`。  
3. 改 `ProofForgeV2/**` 后 `just sbom-package-files-refresh`。  
4. 日常 `just dev-check`；合并前 `just ci`。  
5. 完成一项后：改本文件状态 + 必要时更新 matrix/AGENTS 一行事实。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-08-01 | 初版：汇总 RECOVERY/Matrix/RPT-011/012/roadmap-t8 + 构建观测 |
| 2026-08-01 | 二次汇总：诚实范围声明、文档宇宙分层、PRD FR/DoD 工程解读、IBC/Token 北极星、NFR 性能/资源、DOC-SPEC-AUDIT、dossier/index 债；明确“工程最可用队列 ≠ 全文档闭包” |
| 2026-08-01 | DOC-1/4/5 落地：RECOVERY 当前路径改进程内 Loader；index/document-status/targets dossiers+README；Matrix D1-02/06 CLI 句；research 11/12 链 backlog |
| 2026-08-02 | 与 main 对齐：T9d / NearAggregate / NoirAggregate / AleoCoverage 标 done；推荐序改为 BUILD → Normalize 串行 |
| 2026-08-02 | Goal+workflow 操作：`.grok/goals/README.md` + `prompt-build-1-2.md` + `prompt-n-a2.md`；配合 `proof-forge-engineering-slice` / `proof-forge-one-slice` |
| 2026-08-02 | **全队列 Goal**：`.grok/goals/prompt-master-queue.md` + `QUEUE.md` + `slices/`（60 个工程切片 prompt）；排除 formal/release |
| 2026-08-02 | **Goal 默认 drain**：master 禁止「做满 3 项即结束」；仅预算硬尽/阻塞/队列空可停；续跑用 starting at NEXT |
| 2026-08-02 | **文档↔代码三方复核**（SPEC×Normalize / op×target 矩阵 / backlog done 声明）：§2.4 剩余缺口登记（15 新 ID + DOC-CODE-1）；research/12 约 9 格修正（Aleo Map/Bytes/aggregate/Array、Noir Array）；research/13 §1-§6 刷新对齐 HEAD；NEAR/Solana/Aleo/Psy dossier 工程状态段修正；**AGENTS.md T14 假声明修正**（Field catalog 仍 sole bn254；30df771f2 commit message 与 diff 不符，挂 DOC-CODE-1 待产品决策）；推荐序重排为当前批 4 lane + 下一串行主轴 |
| 2026-08-03 | **D3-E7 工程闭合**：content descriptors + evidence digest 进入 engineering OutputSet identity；publisher pre/post inventory 与 inspect exact closure 接线；明确 stable-observation-only、formal D3-05 仍 pending |
| 2026-08-03 | **NFR-REPEAT 工程门**：Counter × Solana default plan/Noir default 各连续两次产品构建，sidecars exact-byte + descriptor content closure 相等；进入 ordinary CI；非 formal NFR-001/clean-room |
| 2026-08-03 | **控制面事实同步**：live present-tense 对齐 11 targets / 8 implemented + 3 design-only / 8 materializers / 9 resolver rows；修正 A0/no-dispatch 假事实；CW/TON capability 已接线；D2-07 evalInvariant 工程存在 formal pending |
| 2026-08-03 | **Quint Q0 工程 target**：控制面扩为 12 targets / 9 implemented + 3 design-only / 9 materializers / 11 resolver rows（EVM×2 Cancun+legacy + Solana×2 + Quint 四键）；`.qnt` source-only、zero-tool finalize、显式失败 outcome+state stutter；ITF/MBT/verify 留后续 profile，formal 状态不变 |
| 2026-08-03 | **D3-E9 工程闭合**：Protocol 重复六轴删除；registry V1 六轴成为 descriptor sole seed；resolve/mint/inspect 三处 exact join；非 formal TargetSemantics payload/digest |
| 2026-08-05 | **SYS-CAP-SURVEY 登记**：RPT-020 多链系统能力全景调研（状态类 vs 电路类；六维同构候选；系统能力两层：L1 内建 host + L2 官方链上 program，能力与形态解耦）；登记 SYS-CAP-UNIFY 设计项（ContextRead/EnvRead catalog 扩键 + 官方 program 能力 catalog） |
| 2026-08-06 | **SYS-CAP-UNIFY S1 闭合 / S2 四 leaf / E4 推进**：S1 caller 四 target 工程闭合；S2 blockHeight 四 leaf（EVM NUMBER / NEAR block_index / CW height / Solana ordinary Clock.slot）Plan/IR/emitter 完成，runtime 门 residual；E4：Solana/NEAR/CW multiword div/mod、EVM/Solana cap-4 Principal Map、EVM MiniAmm demo + host-optional Anvil（EIP-3860 override）已交付；Solana 另有 WideDiv 数值/回滚 Mollusk、四宽 handler 长距 dispatch runtime pin 与 Array 24/44/Map 类型分派防回归。Solana MiniAMM 应用门、真实 asset movement/remove-liquidity 仍 pending |
| 2026-08-06 | **ADR-0032 U1 Solana 统一 materializer**：sole rail = `solana-sbpf-cpi-elf-v1`；P2–P3-e multi-role system.transfer 已绿；**P4 默认 profile 已切到 cpi-elf**（body-only 准入 + zero-site full-body；Counter/Map/Token/MiniAmm/TipJar bare `--target solana` deployable；plan/elf 仍显式 shim） |

---

## 10. 新 target 波次（2026-08-03 起）

| ID | 项 | 状态 |
|---|---|---|
| **CW-0** | CosmWasm registry 晋升 implemented（A0） | **done**（`dd607de72`：profile `cosmwasm-wasm-u64-v1`、resolver 第八行五键、descriptor wasmText、全部钉测同步） |
| **CW-1** | CosmWasm MVP leaf（A1） | **done**（`integrate/cosmwasm-a1`：Counter 纵切 Plan/IR/WAT、locked wat2wasm deployable、产品 `.wasm` 过 `cosmwasm-check 3.0.9` 真实验收；**sync call FC**（async schedule 见 **CW-4** SubMsg 子集）；iterator/IBC/migrate/聚合/ContextRead/多宽 ABI FC） |
| **CW-2** | cosmwasm-check Tool Lock 验收门（A2） | **done**（cargo-git 3.0.9 入 `tools[]`；fixture 矩阵 + 产品条件式验收脚本 + suite 注册） |
| **CW-3** | CosmWasm runtime 差分（cosmwasm-vm mock / cw-multi-test / wasmd） | **done**（2026-08-03：`runtime-tests/cosmwasm` cosmwasm-vm 3.0.9 mock harness + `scripts/cosmwasm_runtime_test.sh`；Counter/Accumulator/EventFlow 9 tests：init/increment/query、overflow trap+state hold、emit attributes、revert Err；trap≠ContractResult::Err 已钉；mock≠wasmd 不声称 runtime/formal） |
| **CW-4** | CosmWasm SubMsg/reply 语义评估与 schedule 候选 | **done**（2026-08-03：schedule→`SubMsg{reply_on:never,id:0,WasmMsg::Execute}`；resolver async 键开放、sync 仍拒；诚实边界钉死：同事务分发、子失败打爆整 tx、contract_addr QN stub、msg JSON 待 Binary 升级；**不是**跨 tx async） |
| **TON-0** | TON 研究期 dossier + family（ADR-0017 遗留，B0） | **done**（`integrate/cosmwasm-a2-b0`：`docs/targets/11-ton.md` + `family-tvm-stack-account.md` + README 索引；research ceiling） |
| **TON-1** | TON 实现 ADR + TargetId/registry/descriptor/capability（B1） | **done**（2026-08-03：ADR-0024；8 implemented+3 design-only；resolver 九行 sync 拒/async+event 开；tolk 1.4.2 入 `tools[]`；全部钉测同步） |
| **TON-2** | TON Tolk emitter Counter 纵切（B2） | **done**（2026-08-03：`Targets/Ton/**` + Registry dispatch + `TonPlanV1` 注册；c4 struct cell + op 分发 + int257 显式守卫；locked tolk→`.fif`+abi、companion fift→真实 BoC；Counter e2e `deployable=true` + inspect closure；schedule Plan 发射仍 FC） |
| **TON-3** | TON `@ton/sandbox` 验收门（B3） | **done**（2026-08-03：`runtime-tests/ton`（sandbox 0.44.0 + core 0.63.1 lockfile）+ `scripts/ton_runtime_test.sh`；Counter/EventFlowTon **7/7**：overflow exit 100 + state 不变（bounce 开关两态）、emit external out op/载荷、Cap exit 200、五相位分离；工具缺席 skip-clean；engineering differential，非主网/formal） |
| **TON-4** | TON schedule→async internal out-message Plan 发射 | **done**（2026-08-03；`a1d9217bb`：`Op.Schedule` 降 `Statement.promiseAccount`（mutate/init only；QN≥2 + lowercase receiver stub + UInt64 args）；IR 带 `destHashHex`+`methodOp`；Tolk 发 `createMessage`（bounce=NoBounce、value=0、SEND_MODE_PAY_FEES_SEPARATELY、`dest=(0,SHA-256(UTF-8 target path))` identity stub，**非** 真实地址）；sync ExternalCall 仍 FC；消息 value 经济为后续切片） |
| **TON-5** | TON schedule sandbox 差分（ScheduleFlow） | **done**（2026-08-03；`678f78a9e`：`runtime-tests/ton` ScheduleFlow fixture + `schedule.test.js`；`later()` 产出恰好一条 internal out-message（bounce=false、value=0、dest stub、op=0x6f31304c、query_id=0、pre-increment arg），父状态仍 +1；Counter 无 createMessage 回归；全套 **10/10**（locked tolk + companion fift）；engineering differential，非主网/formal） |
| **TON-6** | TON named Struct/Enum view 聚合返回（B-RET-ABI） | **done**（2026-08-03；`e49fcaf4e`：named 聚合 view 返回降为多栈值 get method（Tolk tuple return 需括号形式，locked tolk 实测）；`MethodResultKind.aggregate`（schema tag 12）+ `returnAggregate`（tag 11）；ton-abi `returns` 叶数组（scalar 现亦显式发射 spelling/null）；PairRet/MaybeRet 经产品 finalize 出真实 .fif/.boc；entry 聚合返回因 TON async actor 无返回通道保持 FC，匿名容器/>8 叶/pureFn/非 UInt64-Int64 叶均 FC） |
| **TON-7** | TON 多宽 UInt8/16/32（T8 on TON） | **done**（2026-08-03；`082ca925d`：复用 NEAR ABI pilot policy；state/param 精确宽度序列化（c4 cell + message body 8/16/32/64-bit storeUint/loadUint）；body 窄算术在 int257 上按宽度参数化 range/mask 守卫，复用 100-105 错误码族；entry/view uint8/16/32 result kind + ABI `paramBitsExact`；Counter UInt64 不变；locked tolk 真实 .fif 钉 8 PLDU/LDU/STU；UInt128/256、Int8/16/32、Field/Principal、聚合叶多宽、pureFn 多宽均 FC） |
| **QUINT-1** | Quint source-only executable-model target Q0 | **done**（2026-08-03：独立 TargetId/profile/axes + capability-only target-owned Plan/IR/`.qnt` emitter + zero-tool finalize；完整 UInt64 输入域；失败调用显式 outcome 且业务状态 stutter；resolver 仅 rollback/state/Bool/checked-arithmetic 四键；非 deploy/proof/formal D3/D4） |
| **QUINT-2** | Quint locked typecheck + ITF/MBT/verify profile | **pending**（需独立 Tool Lock、trace projection、resource limits 与 evidence contract；不得让 product finalization 隐式调用 Quint/Apalache/TLC/Java，也不得用小整数域冒充 UInt64） |
| **CW-5** | CW-ABI-FREEZE 完整 design-exit（合并前置） | **done**（2026-08-03：§6 版本冻结——cosmwasm-std/vm/check 3.0.9 + wasmvm 3.0.7 + wasmd v0.70.3 dispatcher 语义；Rust-independent ABI 与 allowed capabilities（MVP 无 requires_*）；SubMsg/savepoint 语义按 pinned 源固定（ReplyNever 失败=整 tx 失败）；`SRC-CW-002` provisional→verified（dispatcher 快照）、`SRC-CW-003/004` 登记、`CLM-CW-001..004` 登记；§10 批准 structural-WAT 工程先导（bounded ABI subset）为首个 accepted profile，`wasm-validated-alpha` 声明限定为 WAT+wat2wasm+cosmwasm-check+cosmwasm-vm mock，不含 wasmd/formal） |
| **CW-6** | CW schedule SubMsg `msg` 升级 Binary（base64） | **done**（2026-08-03；`6228e0f36`：`WasmMsg::Execute.msg` 从嵌套 JSON 对象升级为 cosmwasm-std `Binary`（RFC 4648 base64 of UTF-8 inner method JSON）；WAT 表驱动 base64 编码器 + inner-JSON scratch 构建器，容量守卫 512/1536 trap；cosmwasm-vm 3.0.9 mock `ScheduleFlow` 断言 id=0/reply_on=Never/gas_limit=None/funds 空 + Binary 精确解码 + 父状态 +1；sync call/reply 处理仍 FC、contract_addr 仍 QN stub） |
| **CW-7** | CW named Struct/Enum entry/view 聚合返回（B-RET-ABI） | **done**（2026-08-03；`13779643d`：named 聚合 ≤8 叶（UInt64/Int64 preorder）沿用 CW scalar JSON 惯用法推广：execute `result` 属性为十进制 JSON 数组、query 返回 `{"ok":"[d0,d1,...]"}`，不发明第二返回路径；`MethodResultKind.aggregate`（schema tag 12）+ `returnAggregate`（tag 11）；WAT ret_kind=4 + 8 叶容量守卫；named Struct/Enum state 由此承认（替换 type-closure 全 named 一刀切 FC，与 Solana/NEAR 同模型）；cosmwasm-vm pair_ret 精确断言 + 全旧 fixture 绿；匿名容器/参数/pureFn/>8 叶/非 64 位叶仍 FC） |
| **CW-8** | CW 多宽 UInt8/16/32（T8 on CW） | **done**（2026-08-03；`767862be0`：param 先按 unsigned decimal 解析、写前 `shr_u bitWidth ≠ 0 → unreachable`（JSON 输入无静默截断）；state 保持 8B Region 高位零构造，load 复查高位 corrupt trap；body `narrowChecked*`/`narrowBit*`/`narrowShl|Shr` 高位守卫；entry/view uint8/16/32 result + 宽度感知 ABI；NarrowCounter 6 项 cosmwasm-vm 测试（overflow state-hold、u8 max、param 256 trap、delta 300 trap）+ 全旧 fixture 绿；UInt128/256、Int8/16/32、Field/Principal 窄组合仍 FC） |
| **CW-9** | wasmd tx 级 runtime 差分 rung-1（docker） | **done**（2026-08-04；`1f8317cc1`：`scripts/cosmwasm_wasmd_test.sh` + in-container 断言；digest-pinned 官方镜像 `cosmwasm/wasmd:v0.70.3` 本地链；Counter init/increment/query 与 overflow `deliver_code=29` state-hold；**SRC-CW-002 真链验证**：ScheduleFlow `later{}` 的 SubMsg dest 为 QN stub（非 bech32），dispatcher validation 失败，`reply_on=never` 下**整 tx abort、父状态回滚**（deliver_code=1）；产品 query 返回 UTF-8 非 Binary 已记录（harness 走 raw state query）；skip-clean 无 docker；engineering differential，非主网/formal Stage-0） |
| **ALEO-2** | Aleo 多宽 UInt8/16/32（T8 on Aleo） | **done**（2026-08-03；`5be4b02fc`：Leo 4.0.2 spike 实证原生 uN 算术 const/runtime 均 trap overflow（add/sub/mul/shl + cast 越界表），匹配 DSL checked 语义 → 原生 Leo u8/u16/u32 发射，无 widen 脚手架；Plan ABI `uintWidth`（state/param/result）；body width-tracked `narrowChecked*`/`narrowBit*`/`narrowShl|Shr` + shift count<width 断言；switch case literal 按 scrutinee 宽度；shift result 随 lhs 宽；验收 U8Ctr/MultiW 过真实 leo build（13 fixture 全绿）；UInt128/256、Int8/16/32、Field 变体、聚合窄叶仍 FC） |
| **PSY-2** | Psy 多宽 UInt8/16/32（T8 on Psy，系列收尾） | **done**（2026-08-03；`4f92e66cb`：Psy Felt=Goldilocks wrap mod p 且原生 uN 不忠实 Reference（overflow 内部 trap、shift wrap）→ 拒绝原生 uN，采用 Felt 承载 + 显式宽度守卫（add/mul/shl 结果<2^w、sub l>=r、div/mod r≠0、bitNot xor mask、param 入场 range check）；w∈{8,16,32} 时 (2^32−1)²<p 故窄运算不可能 wrap mod p，UInt64 保持 field-wrap 惯用法；Plan `uintWidth` 覆盖 state/param/result；验收 U8Ctr 过真实 psyup（6 fixture 全绿）；UInt128/256、Int8/16/32、bn254 Field、Map/Bytes/Option/Principal 窄组合与窄 loop 归纳仍 FC；`psyTypeClosureWording` 文案已同步多宽集合） |


> **Solana CPI epic #111–#125 engineering closed** (#110 engineering epic complete): legacy profiles fail closed on call/schedule; exact `solana-sbpf-cpi-elf-v1` advertises sync+extension (async still FC); CpiEscrowIRV1 composite escrow remains test-preactivation history; product activation is ordinary-resolver product capability (not formal TASK-D5).
