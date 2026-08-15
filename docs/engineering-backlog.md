---
id: ENG-BACKLOG
title: 工程业务 Backlog（文档↔实现差异 + 构建加速）
status: draft
owner: engineering
updated: 2026-08-15
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

**剩余 target 波次**（Soroban/ICP/OpenVM + Move/比特币边界）：见 §10.1 与
[`research/25-remaining-target-landscape.md`](research/25-remaining-target-landscape.md)。

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
| `docs/targets/*.md` + family | 多数 `proposed`/`draft` | 工程状态段**常落后于代码**（历史示例：Solana 曾滞后写 plan-only，registry label 已于 2026-08-12 修正为 runtime-validated-alpha） |
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
Materialized/Finalized + disk closure` 已通；sole Normalize 与**十二个 materializer**（EVM/Solana/NEAR/Noir/
Aleo/Psy/Quint/CosmWasm/TON/Soroban/OpenVM/ICP）已覆盖非均匀的多宽算术、控制流、fn、let/for、shift/bitwise、call/schedule、
聚合与 Field 子集；EVM/Solana/NEAR/CosmWasm/TON 有工程 runtime 门，ICP 有 host-optional PocketIC，Noir 有 compile-only 门；Aleo 为 sole `aleo-instructions-v1` zero-tool materializer，Psy 为 sole `psy-dpn-v1` zero-tool materializer；Quint 为 zero-tool `.qnt` executable-model target；Soroban 为 source-only S0（ADR-0044）；OpenVM 默认 `openvm-guest-source-v1` 为 zero-tool guest-source（ADR-0045 O0），opt-in `openvm-guest-elf-v1` 锁定 `cargo-openvm` 2.0.1 build/transpile ELF/VmExe（ADR-0046 O1）。registry = **12 targets / 12 implemented + 0 design-only / 15 resolver rows**（EVM×2、Noir×2、OpenVM×2、其余各一）；CW：sync 拒、
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
| FR-007 typed Plan/IR | 十二个 materializer 有 target-owned 类型（含 Quint/CosmWasm/TON/Soroban/OpenVM/ICP）；formal schema/hash 不齐 | D4-E*、T9d、B-CALL-SEM |
| FR-008 accepted 四-target + runtime/proof | accepted PRD 仍四目标；工程 registry 已 12 implemented + 0 design-only（含 Quint/CosmWasm/TON/Soroban/OpenVM/ICP materializer；ADR-0036/0044/0045/0046/0047 固定非静默扩面并选择 EVM-first formal lighthouse）；EVM/Solana runtime 较强、NEAR/CosmWasm/TON 有工程 runtime 门、ICP host-optional PocketIC、Quint/Soroban/OpenVM source-only、Noir 无 prove | C-1/C-4/C-6、ADR-0036、ADR-0044、ADR-0045、ADR-0046、ADR-0047、PRD-DoD、B-CALL-SEM |
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
| **EXT-ASSETS** | `extension.pf-assets`（L1 portable assets；ADR-0029） | Phase A：payload 冻结 + Typed/Normalize + Quint vault + 产品 demo；Phase B：EVM（payable exact callvalue + full-gas value CALL + `interface-standard` 骨架 + Anvil 门）与 Solana（vault PDA + 幂等 ensure + System CPI 入金 + program-direct 出金 + Mollusk 12/12）；Phase C：CosmWasm（funds exact + BankMsg::Send reply_on=never sync + cw-vm mock）与 NEAR（attached_deposit + transferAsync Promise + near-sandbox 余额观测）已绑定；resolver multi-permit 六行（Quint + EVM×2 + Solana CPI + NEAR + CW）。**ADR-0030（2026-08-05）**：`pf.assets.token.transfer`/`transferAsync`（payload 不变）**E1 四链全绑**——EVM（E1a 受控动态 callee ERC-20 transfer + 返回值三分支 predicate + Anvil 门）、Solana（E1b vault ATA→dst ATA transferCheckedPda + ATA ensure×2 + ROLE_DATA_LEN 刷新纪律 + Mollusk `tipjar_token` 14/14、门 16/338）、CosmWasm（E1-CW CW20 Transfer WasmMsg::Execute SubMsg reply_on=never + bech32 charset `[a-z0-9]` 注入安全门 + cw-vm mock `tokenjar.rs` 6/6）、NEAR（E1-NEAR NEP-141 `ft_transfer` fire-and-forget Promise + 恰好 1 yoctoNEAR + mock token sandbox 真实跨合约 receipt + schedule function-call ABI 7 参修正）；E2 balanceOfSelf env-read **全波 done**（payload v1.1.0 已 cutover 为唯一承认 triple、Reference self-vault 解释器闭合 ADR-0029 opaque caveat、六 target 物化：EVM SELFBALANCE+STATICCALL `balanceOf`、Solana vault lamports/ATA coherence 读（无 CPI）、CW `query_chain` bank/CW20（msg=Binary base64）、NEAR `account_balance` native-only（u128→UInt64 range guard，真实余额≫2^64 trap 已真实触发）、Quint vaultNative native-only；NEAR/Quint token env-read 永久 FC；gates：Anvil envread leg、Mollusk、cw-vm `envreadjar.rs`、near-sandbox 9 suites，含 CallerCheck），E3 caller 已由 ADR-0031 S1 四 target 工程闭合；E4 MiniAMM **engineering dual-chain closed（2026-08-07）**：同一 `Examples/MiniAmmAssets.lean` 经 Solana Mollusk `miniamm_assets` 10/10（multi-role dual-mint Token CPI）+ EVM Anvil M5 dual ERC-20（strict EIP-3860）runtime 门；M0 vault-internal MiniAmm + M4c multi-role 产品 pin 保留；formal TASK-D5 / hermetic / mainnet 仍 residual；token.transferAsync 除 NEAR 外仍全 target FC。**TON 决策（2026-08-05，产品 owner）：TON 冻结现状（async createMessage 子集已开即止），pf.assets 与后续功能不开发；Noir 永久 FC** | **A（08-04）/B/C/D done（2026-08-05）**；ADR-0030 **E1 done（2026-08-05，四链全绑）/ E2 done（2026-08-06，六 target env-read 物化）/ E3 done（2026-08-06，四 target caller）**，E4 in_progress |
| **EXT-CRYPTO** | `extension.crypto`（SHA-256 / Merkle / 签名） | IBC 与大量链上逻辑命脉；capability 矩阵 | **设计钉 done**（RPT-027）；S5 sha256 = EVM/Solana/NEAR；**CRYPTO-D2 EVM ecrecover** engineering done；Merkle/其它签名/其它 target 仍 pending |
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
| **PF-CLI** | Rust Developer CLI `pf`（ADR-0037） | D0–D11：多链 build/test/verify + deploy wrap | **done**（2026-08-10）；公共网写仍拒绝；见 [`plan/pf-cli-aleo.md`](plan/pf-cli-aleo.md) |

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
| **N-ANON-RESULT** | 匿名容器（Array/Map/Option/Bytes）entry/view/fn 返回值 | 共享核 | Normalize/typed Semantic 已接纳四类 anonymous result TypeId；Reference 固定 Array/Bytes/Option/Map canonical valueBytes 与 Array-typed PureCall。**Target ABI 已开全部八 target**（2026-08-03：`Array UInt64 N`(1..8) 按 named struct 同序 flatten、`Option UInt64` tag+payload 双叶，复用 named 多叶路径零新 tag；EVM solc、Solana Mollusk 16B LE、NEAR sandbox 16B LE、Noir nargo 10 包、Psy psyup、TON locked-tolk .fif/.boc、Aleo leo build、CosmWasm cosmwasm-vm 精确 JSON 证据；诚实边界：TON entry FC（async actor 无返回通道）、Aleo view-over-state 经 computed-view 门 FC、Option UInt64 state 已开八 materializer（Quint FC）；Map/Bytes state 按 target 非均匀；Map 返回、非 UInt64 元素/Int64 容器/嵌套/>8/pureFn 聚合均 FC；**Psy PSY-SCALAR-ABI 另开 Bytes 1..8 return**） | **done**（2026-08-03；`ea74d132a` shared + 八 target lanes；非 formal D2/D4） |
| **N-NEST-IDX** | Map/Bytes 嵌套穿透赋值（`m[k].x:=v`、`b[i].…`） | 共享核 | Map 穿透已开：TypeCheck 递归 assign-target（Map index 任一步得 value 类型、field 经 named struct 解析）；Normalize 降 IndexGet→VariantPayload(1,0)→嵌套更新→IndexSet 回写；Reference 钉 present-key 写穿、absent-key `.invalidCore` trap 保 pre-state；`Map UInt64 Map …` 深穿透亦通。Bytes 穿透仍 FC | **done**（2026-08-03；`93ac5151b`；shared-only，非 target/formal） |
| **N-INVARIANT-IR** | invariant 进 Semantic callables/invariants | 共享核 | Normalize 将每个 `invariant name : BoolExpr` 降为零参 public-Bool `.invariant` callable + source-order dense `InvariantDecl`；复用 Wire sole closure membership 与 exact `invariantSteps` 公式，支持 pureFn closure 与 expression-match 多块 CFG；Provenance 覆盖全部 lowered block/instruction/value/terminator；`.proof` 仍仅为 certification metadata，同一 program 有/无 proof 的 semantic bytes/hash 相同；Quint 对 Q0 read-only Bool invariant 已 lowering；其余八个 materializer 对 nonempty invariants 继续 fail closed | **done**（2026-08-02；engineering，非 formal TASK-D2-06/07） |
| **N-STR-EVENT** | String 作 event/error 字段 | 共享核（小） | Normalize 现允许 public anonymous UInt/Int/String event/error 字段；String 字面量按 canonical `u32le(len) || NFC UTF-8` 降为 payload，located product compile 与 Reference Emit/Revert（ordered effect / declared rollback）已钉。九个 materializer 不发明 ABI：EVM/Solana/NEAR/Noir/Psy/Quint/CosmWasm/TON 在 target Plan 精确 FC，Aleo 在 `effect.event` resolver FC | **done**（2026-08-03；`c768d68c7`；shared-only，非 target ABI/formal D2/D4） |
| **N-FOR-INT** | for 端点 Int | 共享核（小） | Normalize 接受同宽 legal UInt/Int，按 endpoint TypeId 发 typed `<` 与同宽 `+1`，复用 exact back-edge `loopBounds`；Reference 固定 `[-2,2)`、`start≥end` 零趟、Int8 `126→127` 与 boundExceeded 全 state rollback。九个 materializer 不猜 signed range ABI：EVM/Solana/NEAR/Noir/Aleo/Psy/Quint/CosmWasm/TON 均在 target Plan 精确 fail closed | **done**（2026-08-03；`9ad021700`；shared-only，非 target Int loop/formal D2/D4） |
| **N-CONST-REF** | body 中 const place 引用 | 共享核（小） | constants lookup 在 fn signatures 后、任何 callable body 前完成，支持 forward ref；bare place 按 env→state→const 降为独立 value-producing `Op.Constant`，精确绑定 ConstantId/TypeId/ValueId；entry/view/pureFn/invariant、窄 UInt 合成与 authoritative Provenance（`.constant`/`.typeRef`/body place/Bool requirement）已钉。const 声明表达式仍仅 literal/negative Int；EVM/Solana/NEAR/Noir 对任意 nonempty constants 表 FC；**Aleo 已于 2026-08-08 开放 literal-backed `Op.Constant` 内联**（ALEO-CONST；同 `lowerLiteral` envelope）；**Psy 已于 2026-08-07 开放精确可表示标量子域**（UInt8/16/32、Bool、`UInt64 < Goldilocks p`、非负 Int64；target-internal canonical Goldilocks ConstantV1 亦复用同一 decoder，但 source 无 Field literal），负 Int64 与 `UInt64 ≥ p` 精确 FC，不新增 ABI/const declaration/emitter primitive，String/aggregate/CheckedCast 仍 FC；post-declared novel const shape 有明确 engineering semantic-identity cutover，非 hash-stability/formal 声明 | **done**（2026-08-02；engineering，非 formal D2/D4） |
| **N-MAP-CONSTRUCT** | 非空 Map 构造 / wire multi-arg Construct | 共享核 | `Map.of(k0, v0, ...)` 变长构造器（NameResolution/TypeCheck/Normalize 已接线；expected Map 类型必需、偶数 kv 参数、positional K/V 精确）→ 单个 `Op.Construct`（flattened kv 对，source order）；Wire step-j 开偶数对（奇数/位置错/result 错/ctor≠0 → `.badCfg`）；Reference 为空 Map + 顺序 upsert（duplicate key last-wins 与 IndexSet 一致、canonical 值保持排序、允许运行期 key）；EVM/Noir 既有显式 FC，Solana/NEAR/Aleo/CosmWasm/TON 已补显式 nonempty-Map-construct FC（消除 Array 路径 arity 碰撞隐患），Psy 经 container 门 FC | **done**（2026-08-03；shared-only，target materialization 仍 FC，非 formal D2/D4） |
| **B-RET-ABI** | 原六 target aggregate ABI 返回（named struct/enum） | target leaf | N-4 done 的剩余；EVM+Noir LOWERED（≤8 UInt64/Int64 叶 preorder flatten；EVM tuple ABI + Noir per-leaf verifier inputs）；**Solana/NEAR 亦 LOWERED**（2026-08-03：Solana `ResultKind.aggregate`/`setReturnDataMulti` 单条 `sol_set_return_data` N×8 LE + IDL 叶数组；NEAR `MethodResultKind.aggregate`/`setReturnDataLeaves` 单次 `value_return` N×8 LE + near-abi 叶数组 + HostModel e2e）；**Aleo 非 Final entry LOWERED**（2026-08-03：Leo 原生 tuple 返回；Final 函数评叶后 drop 同 scalar 模型；multi-leaf view-over-state 经 computed-view 门保持 FC）；**Psy entry/view LOWERED**（2026-08-03：`[Felt; N]` 固定长 Felt 数组为诚实多叶源形式，psyup 真实验收 PairRet；叶继承既有 Goldilocks 文档模型）；anonymous Array/Option entry/view 已由 N-ANON-RESULT target lanes 开放；Map/Bytes返回、aggregate 参数与 target pureFn aggregate仍 FC | **done**（EVM/Noir：pre-Wave-1 L3 lane `b059778fa`；Solana：`5aeee9c17`；NEAR：`a82ec3fce`；Aleo：`e42d2e2e1`；Psy：`cc99484b3`） |
| **B-SOL-MAP-ELF** | Solana Map ELF 帧预算友好化 + MapMini Mollusk 升级 | target leaf | IR temp recycling + aggregate-store structural CSE；MapMini/Token 均 deployable ELF，Map put 峰值 177 temp≈1424B≤4096；MapMini 4/4 Mollusk active；**未提预算上限** | **done**（L2 + B-SOL-MAP-UPSERT；`put_into_empty` 已解除 ignore） |
| **B-CTX-OPEN** | ContextRead 各 target Plan 开放（unixTime/caller/blockHeight） | target leaf | **unixTimeSeconds**：EVM `timestamp()`（tag 59）+ NEAR `block_timestamp` ns÷10^9（tag 41）+ CW Env JSON time + TON `blockchain.now()` 已开；**Solana/Noir/Psy/Aleo/Quint 保持 FC**（电路域决策 2026-08-04）。**caller / ADR-0031 S1 已闭合（2026-08-06）**：EVM ADR-0025 `u32le(20)\|\|CALLER` + CallerCheck/Ownable Anvil；Solana 仅 exact CPI profile 的 `pf_caller` signer→32B Principal，ordinary Principal ix canonical gate + Mollusk 8/8，legacy profiles FC；NEAR `predecessor_account_id` init/entry + sandbox，view FC；CW `MessageInfo.sender` instantiate/execute + branch-local loader/charset gate + cw-vm，query/view FC。**blockHeight / ADR-0031 S2**：EVM `number()`（tag 62）、NEAR view-safe `block_index()`、CW Env JSON bare-u64 `height`（tag 55）、Solana `Clock.slot` via `sol_get_clock_sysvar`（Plan tag 51）Plan/IR/emitter leaves 均已开；**Solana sole product profile `solana-sbpf-cpi-elf-v1` 已于 2026-08-12 admit blockHeight**（syscall 读、零 role/site/`pf_caller` 需求；`unixTimeSeconds` 保持 FC）并接 Mollusk runtime 门（`block_height.rs`：双 warp slot 证非常量 + view/entry/state-hold）；EVM 已有 host-optional Anvil `BlockHeightCheck` 门（非 Anvil lossless / formal）；NEAR sandbox 已跑 `Examples/BlockHeightCheck.lean`（`scripts/near_runtime_test.sh` `run_suite blockheightcheck`）；CW 已有 `runtime-tests/cosmwasm/tests/block_height.rs`（`scripts/cosmwasm_runtime_test.sh` 列 `Examples/BlockHeightCheck.lean`）。**Solana `unixTimeSeconds` 仍 FC**（Noir/Psy/Aleo/Quint unixTime 亦 FC） | **done**（2026-08-14 honesty close：NEAR/CW `blockHeight` runtime gates already in tree；unixTimeSeconds Solana/Noir/Psy/Aleo/Quint 仍 FC；非 formal / 非 Anvil lossless） |
| **B-OPT-STATE** | 九 materializer Option state Plan | target leaf | N-A4 只开 Normalize admit。**NEAR 已开**（2026-08-04 `95289615e`：`Option UInt64` state 复用 Enum 双叶布局（tag+payload 8B KV），none 默认零初始化、none 赋值清零 payload（HostModel+sandbox 双钉），match 走既有 VariantTag/VariantPayload 路径；Option params/非 UInt64 payload 仍 FC）；**EVM 已开**（2026-08-04 `0a46e54d8`：同构 2-slot 布局 + storeAtomic 沿用 B-EVM-MAP-STACK memory-spill 惯例，none 双叶清零，solc strict-assembly 验收 + Token 栈预算不变；Option params 不扩展）；**Solana 已开**（2026-08-04 `42c863d0c`：同构 `slot_tag`/`slot_p0` u64-le 布局 + 多叶原子 store，stale-payload clear 钉死，6 项 Mollusk 测试）；**Aleo 已开**（2026-08-04 `68d7c0a7f`：同构 tag+payload mapping 双叶（flatten-to-mapping），none 默认 get_or_use(0) 零初始化、payload 清零钉死，entry-surface match（multi-leaf view-over-state 仍 FC），OptionState 过真实 leo build）；**CosmWasm 已开**（2026-08-04 `da2f9ffe7`：同构 8B KV 双叶 + storeAtomic，none 清零 runtime 钉死，3 项 cosmwasm-vm 测试）；**Psy 已开**（2026-08-04 `a2755c6c9`：同构 Felt 双叶；顺带两修——VariantTag 窄 32 化使 Enum/Option match 可解、return-only 臂改 dargo expression-if；psyup 验收 10 fixture 全绿）；**Noir 已开**（2026-08-04 `27fa56c83`：同构双叶 + EmitIR brace-escape 共修（`}} else {` 非法输出），nargo 验收）；**TON 已开**（2026-08-04 `ac13b9b09`：同构 tag/payload c4 双叶 + storeAtomic，match 走 VariantTag/VariantPayload，Tolk 1.4 合法性共修（switchRegion 去 do-while/break、view 每臂早退 return），locked tolk→.fif 验收；Option params 仍 FC）；Quint 仍 FC（无 admit 路径） | done（8/9 materializer；Quint FC） |
| **B-COMMIT-ZK** | Commit × Noir/Psy | target leaf | EVM/Solana/NEAR/Aleo 身份透传已开；Noir/Psy FC。Psy 在开放 identity 前必须先冻结 proof/public-input/commitment binding；仅把 operand 作为普通 Felt 透传会过度声明密码学承诺能力 | pending |
| **B-CALL-SEM** | call/schedule capability 与真实平台语义对齐 | 产品决策 + target leaf | **#111 Solana legacy honesty 已接线**：两 legacy profile 删除 sync/async support claim，Plan/IR/SBPF 纵深 fail closed（过渡空 AccountMeta CPI / log stub 不可达）。EVM 仍保留真实 `CALL`/returndata（BL-28）与 same-tx fire-and-forget schedule；NEAR/TON/CW/Noir/Psy/Aleo/Quint 纪律保持 main 现状。真实 Solana CPI 见 epic #110 versioned profile。不得把 resolver 支持键写成跨平台 call 完成 | **open**（Solana legacy 已诚实；产品 CPI 与他链缺口仍 open） |
| **CW-ABI-FREEZE** | CosmWasm A1 runtime/ABI design-exit | 产品/target semantics 决策 | 已由 **CW-5** 闭合：versioned std/vm/check 3.0.9 + wasmvm 3.0.7 + wasmd v0.70.3 dispatcher 语义冻结；structural-WAT 工程先导批准；`wasm-validated-alpha` 限定 mock 子集。历史 A0/no-dispatch 叙述作废 | **done**（见 CW-5；非 formal） |
| **ADR-0036** | accepted 范围与工程控制面 reconciliation | 文档/产品决策 | accepted PRD 仍以 EVM/Solana/NEAR/Noir 为 Phase 1；engineering 现 12 implemented + 0 design-only（Soroban ADR-0044 + OpenVM ADR-0045/0046 + ICP ADR-0047）不静默扩 accepted scope；B11/B12 contained frontend 保持退役；formal lighthouse=EVM-first | **done（2026-08-10 owner direction；ADR-0036 proposed，accepted PRD 未静默改写；2026-08-14 计数随 ICP implemented 更新为 12+0）** |
| **ADR-0045** | OpenVM guest-source O0 engineering leaf | 文档/工程 | sole default `openvm-guest-source-v1`；受控 Rust guest + catalog；zero-tool finalize；4-key capability；无 prove | **done（2026-08-14；proposed）** |
| **ADR-0046** | OpenVM guest-elf O1 dual-profile engineering leaf | 文档/工程 | 共享 Plan/IR 的 opt-in `openvm-guest-elf-v1`：锁定 `cargo-openvm` 2.0.1 build/transpile guest → RV32IM ELF + `.vmexe` extras；默认 `openvm-guest-source-v1` 仍 zero-tool；resolver 现 15 rows（EVM×2、Noir×2、OpenVM×2、其余各一，含 ICP）；无 keygen/execute/prove/verify | **done（2026-08-14；proposed）** |
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
| **SYS-CAP-UNIFY** | 系统能力统一抽象（L1 ContextRead/EnvRead catalog 扩键 + L2 官方 program 能力 catalog） | 共享核 + leaf | ADR-0031 已冻结两层 catalog、view-safety 与 L2 强制等级。L1 依 E2 纪律逐行推进：S1 `context.caller` **engineering done**（EVM CALLER、Solana exact-CPI signer role、NEAR predecessor、CW MessageInfo；各自 runtime 门与诚实 FC 边界已闭合）；S2 `context.blockHeight` shared + EVM `NUMBER` / NEAR `block_index` / CW `Env.block.height` / Solana `Clock.slot` leaves 已完成（**2026-08-12 Solana sole product profile 已 admit + Mollusk 门**；`unixTimeSeconds` 在 Solana 仍 FC）；S2 runtime residual 已按工程 host-optional 门闭合（NEAR sandbox `BlockHeightCheck` + CW `block_height.rs`；非 formal）；S3 chainId 已于 2026-08-12 开 EVM/NEAR/CW（见实现日志），**S4 attachedValue EVM+NEAR+CW leaves 已开**（EVM `CALLVALUE`；NEAR `attached_deposit` init/entry、view FC；CW `MessageInfo.funds` execute/init、query FC）。剩余 SYS-CAP 工作是 S5/L2，不是 S2 missing harnesses。L2 将 Solana official programs、EVM precompile/系统合约、TON/ICP/Aleo/CW 官方能力逐行 exact catalog + per-target 物化；无对应物与电路锚定值继续 FC | **in_progress**（S0 design + S1 done；S2 leaf+host-optional runtime gates closed as engineering；remaining = S5/L2；不声称 formal/跨链完整） |

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
| **ALEO-DIRECT** | ProgramV1 → Aleo Instructions sole materializer | Aleo Plan/Instructions/Registry | **done（2026-08-10）**：sole profile `aleo-instructions-v1`；Plan→target-owned Instructions AST→canonical `{id}.aleo` + query descriptor；zero-tool Finalize；source-language emitter、compiler profiles、tool/runtime/network wrappers、compiler-output extras与兼容环境变量均物理删除；未知旧 profile fail closed。覆盖与边界见 [`targets/09-aleo-instructions-lowering.md`](targets/09-aleo-instructions-lowering.md)；无 VM/proof/deploy/network/formal 声称 |
| **ALEO-G5-HARD** | Instructions residual hard-require | Aleo Instructions | **done**：Int64、BLS12-377 Field、pureFn、const 等 admitted surface 直降；`isAleoInstructionsG5HardResidualAllowlistV1` 恒 false；Plan admitted 但 Instructions lower 失败稳定 `ALEO-IR-G5-HARD` |
| **ALEO-ARTIFACTS** | canonical Instructions + query descriptor | Aleo Emit/Finalize | **done**：仅两个 materialized-base；无 finalized-extra；query descriptor 是静态 network-state contract，不执行 query |
| **NOIR-IR** | ProgramV1 → ACIR 权威物化（去 sole .nr） | **IR-0..IR-7 done（2026-08-08）**：规划见 [`targets/07-noir-acir-lowering.md`](targets/07-noir-acir-lowering.md)。nargo 1.0.0-beta.26 nargo-assisted ACIR；opt-in dual-write；IR-4 multi-fixture inventory；IR-7 prove honesty **PARTIAL/MISSING**（`barretenberg=null`；`just noir-runtime` → `PF-TOOLCHAIN-MISSING`）。Lane **idle**。**诚实 residual（deferred only）**：真实 backend pin 后 Counter prove 扩展；`deployable=false`。**非** product prove/formal |
| **EVM-BC-RESEARCH** | EVM bytecode sole 权威 cutover | **research-only pause（2026-08-08）**：笔记 [`targets/08-evm-bytecode-lowering.md`](targets/08-evm-bytecode-lowering.md)；**不**实现；用户未授权 Active |
| **NOIR-IR-0** | 规划 + pin 策略 | **done（2026-08-08）**：`07-noir-acir-lowering.md`；Active 切 Noir ACIR |
| **NOIR-IR-1** | nargo Counter ACIR 金样 + inventory pin | **done（2026-08-08）**：`testdata/golden/noir-acir-v1/`（product packages + path-normalized ProgramArtifact JSON）；`InventoryV1` multi-file SHA-256 + envelope keys；`NoirAcirV1` suite（live recheck tool-optional）；**未**解码 ACIR opcode / 无产品 ACIR OutputFile；`deployable=false` |
| **NOIR-IR-2** | Plan→ACIR MVP | **done（2026-08-08）**：路径决策 = **nargo-assisted**（非 pure-Lean ACIR encoder）；`Acir/CaptureV1` + `NoirAcirV1` product Plan Counter source-join ≡ golden product + live capture circuit core ≡ golden（nargo 缺席 skip）；`.nr` 过渡；Finalize 仍 source-only；`deployable=false` |
| **NOIR-IR-3** | G3 控制流/聚合 admit-surface capture pins | **done（2026-08-08）**：`CaptureV1.admitSurfaceFixturesV1` circuit-hash pins（BranchCounter if、LoopSum for、OptionState、ArrayRet 全捕获；MapMini init pin + put/get nargo type residual honesty）；package-stem 恒跑；nargo 缺席 live capture honest skip；Counter 金样回归；multi-file fixture inventory 见 IR-4；`deployable=false` |
| **NOIR-IR-4** | multi-fixture path-normalized inventory | **done（2026-08-08）**：`fixtures/{BranchCounter,LoopSum,OptionState,ArrayRet,MapMini}/nargo-compile/*` 14 nargo-ok leaves + `inventory-admit.json` + Lean `admitInventoryEntriesV1`；MapMini put/get residual 无 leaf；非 product-source 全量矩阵；inventory 恒跑、live recheck honest skip；`deployable=false`；**非** prove |
| **NOIR-IR-5** | G5 轻量诚实矩阵 | **done（2026-08-08）**：§3.2 状态列 Y/P/F + 证据；`CaptureV1.honestyMatrixRowsV1`；call/schedule **P**（witness-binding only，禁止 ACIR Y）；String/Option non-UInt64 **F**（product plan-FC）；prove/VK **F**（Finalize `deployable=false`）；`NoirAcirV1` IR-5 段恒跑；无假 Y；Counter 金样回归；**无** ACIR OutputFile（IR-6）/prove |
| **NOIR-IR-6** | G4 产品 ACIR dual-write | **done（2026-08-08）**：default `noir-source-u64-relations-v1` zero-tool；显式 `noir-nargo-1.0.0-beta.26-acir-v1` Finalize dual-write path-normalized ProgramArtifact `finalized-extra`（`nargo-compile/{stem}/*.json`；缺 nargo `PF-TOOLCHAIN-MISSING`）；Counter ≡ 金样；`.nr` transitional；`deployable=false`；**非** prove |
| **NOIR-IR-7** | G6 prove honesty | **done PARTIAL/MISSING（2026-08-08）**：探路 Tool Lock `barretenberg=null`；`scripts/noir_runtime_test.sh` + `just noir-runtime` 缺工具 `PF-TOOLCHAIN-MISSING`（exit 2；非 ordinary ci）；suite `testIr7ProveHonestyNotes`；nargo compile ≠ prove；不发明 bb/CRS CLI；prove/VK 仍 F；`deployable=false`；**非** product prove/formal |
| **ALEO-DIRECT-CLEANUP** | 删除 obsolete source/compiler/network lanes | Aleo/CLI/ToolLock/scripts/tests/docs | **done（2026-08-10）**：见 ADR-0035；删除全部旧代码、recipes、fixtures、tests、profile aliases、tool entries 与 network receipts；不提高 maturity |
| **ALEO-LOAD-A** | 官方工具加载 PF `.aleo`（Wave A） | Aleo Instructions + Leo abi | **done（2026-08-10）**：`reservedInstructionIdentifierV1` fail-closed（含 entry `add`）；`just aleo-instructions-load` 对 StateCell/LoopSum + golden counter/optionstate 跑 `leo abi` 全绿；Accumulator 产品 FC + reserved golden 被 leo 拒绝；Lean `AleoInstructionsV1` 同步；计划 [`plan/aleo-official-load-dev-testnet.md`](plan/aleo-official-load-dev-testnet.md)。**非** VM/proof/Devnet/Testnet/Mainnet |
| **ALEO-LOAD-B** | 本地 interpret（Wave B） | host-optional | **done（2026-08-10）**：`just aleo-instructions-interpret`；Leo runner shell + PF `{id}.aleo` → `build/imports` 字节钉扎；StateCell initialize/increment offline VM；imports sha 与 PF emission 一致；非 proof/network/durable ledger；产品 `local aleo` 仍 FC |
| **ALEO-LOAD-C** | Devnet/Testnet tx materialization（Wave C） | host-optional network | **done（2026-08-10）**：`just aleo-instructions-network-tx`；PF StateCell ↔ Leo twin **exact Instructions match**；默认 testnet `leo deploy/execute --save` 无 broadcast；`PROOF_FORGE_ALEO_BROADCAST=1`+funded key 才广播；mainnet 拒绝；`deployable=false`；endpoint 不可达 skip-clean |
| **B-1d** | Solana Map/Bytes/Option state：open 或钉死 FAIL-CLOSED | Solana/** | **done**（2026-08-02：Array + **Map UInt64 dense pilot** cap-8；默认仍 plan profile，opt-in ELF+Mollusk 已通；aggregate CSE/storeStateMulti 修复 empty upsert，MapMini 4/4 active；Option 中间值自 Map IndexGet；**Bytes 已随 B-1d2 开放，`Option UInt64` state 后由 BL-29 开放**） |
| **B-1d2** | Solana named Struct/Enum + Bytes state | Solana/** | **done**（2026-08-03：L2 lane `integrate/w1-all`；named 聚合 flatten + Bytes N×UInt8 state/params + atomic storeAggregate/storeStateMulti；4096B frame 硬门保持、plan/ELF 绿；该 lane 当时聚合返回/Option state FC，后续已由 B-RET-ABI/N-ANON-RESULT 与 BL-29 开放 bounded return / `Option UInt64` state；Bytes construct/ContextRead 仍 FC） |
| **B-1e** | EVM Map/Bytes/Option state：同上 | Evm/** | **done**（2026-08-02：Array EvmIndex + Bytes D4-E2；**Map UInt64 dense pilot** cap-8 + Token locked-solc finalization；creation bytecode 超 EIP-3860，chain deployment 未闭合；Option-from-Map 当时仅中间值，后续 BL-31 已开 `Option UInt64` state；EVM/Solana/NEAR/Noir/Aleo Map 横向已开并闭合 aggregate snapshot hazard） |
| **B-1f** | Noir Map multi-leaf public inputs | Noir/** | **done**（2026-08-02：Map UInt64 cap-8 occ/key/val public-input leaves + IndexGet→Option + IndexSet upsert + Token relations；Array 已开放，Bytes 随 B-1b2 开放 fixed state + literal IndexGet/Set；Option/String state 与 Bytes construct/param/动态索引仍 FC） |
| **CW-A1** | CosmWasm target-owned Plan/IR/materializer after registry A0 | `Targets/CosmWasm*` + Registry/umbrella/tests/SBOM | **done**（见 §10 **CW-1**：`Registry.materializeResult` 已有 `.cosmwasm` dispatch；Counter 纵切 Plan/IR/WAT+Wasm；sync 拒、async SubMsg 子集见 CW-4；ABI freeze 见 CW-5；非 formal） |
| **SOR-0** | Soroban source-only S0（ADR-0044） | `Targets/Soroban*` + registry/resolver/CLI | **done**（2026-08-13：`soroban-source-u64-v1` → `.rs`；zero-tool；4-key；auth/TTL/Wasm/call FC；engineering 12+0；**非** accepted Phase 1 / formal） |
| **SOR-1** | Soroban locked Wasm Finalize + auth/TTL Plan fields | Tool Lock + Plan schema | **open**（不得在 S0 声称） |
| **B-3** | Principal/address-bearing 与 EVM/Solana call/schedule | Envelope + EVM/Solana | **done**（2026-08-02：PrincipalAddr 固定 wire Principal ≠ EVM 20B / Solana 32B pubkey，不做 approximate 映射；AddressBearing 仍以 static QualifiedName callee 独立开放，非 dynamic address）。**ADR-0025 realization（2026-08-06）**：EVM `context.caller` 已按唯一 valueBytes `u32le(20)\|\|CALLER` 接入 Plan/IR/Yul 与 Anvil；shared TypeShape/codec 不变，T10 storage 仍为 wire-identity leaf；**不**把 Principal ValueId 变为 CALL 目标，PF Ownable primitive pass 也**不**提升 OZ F01 family/ABI credit | **#111：Solana legacy call 观测桩已 supersede 为 fail closed** |

| **B-ctx** | ContextRead 各 target Plan：closed baseline + per-key 原子开放 | 九 materializer | **done / superseded by SYS-CAP-UNIFY**（2026-08-02 的九 materializer FC matrix 是历史基线；随后 unixTime 已按 target 开放，2026-08-06 ADR-0031 S1 首先完成 EVM caller。其余 target/key 只能经版本化 requirement + target-owned Plan/IR/runtime 门逐行开放；未知 key、未交付 lane 与电路锚定值继续 FC） |

### 验收门（工程，非 formal）

| ID | 项 | 状态 |
|---|---|---|
| **C-1** | NEAR Wasm 工具链 load + sandbox 工程子集 | **done**（2026-08-02：`672e6115d` NearWasmAcceptance = locked `wat2wasm` + host-optional `wasm-interp`/`wasmtime`/`wasmer` load，工具缺席 skip；2026-08-03 C-6 另加 locked near-sandbox Counter happy path；均非 formal Reference differential） |
| **C-2** | Aleo/Psy native artifact boundary | **done（2026-08-10）**：Aleo 仅生成 Aleo Instructions，Psy 仅生成 DPN；二者 zero-tool、non-deployable。旧 source compiler/local runtime/network lanes 删除，不再属于产品或验收面；无 VM/proof/UPS/network/formal 结论 |
| **C-3** | EVM Reference↔Anvil **formal** 差分 | blocked（formal 轨道；G4 工程差分四程序；**2026-08-12** identity binding + Outcome wire + step façade + Outcome projection/digests + **切片-3** ArithOps mint/`sidecars=18` + digest-case 投影硬门——仍非 formal C-3/TST / Anvil↛OutcomeWire 仍 FC） |
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
| **PSY-DPN** | ProgramV1 → DPN sole materializer | **done（2026-08-10）**：sole profile `psy-dpn-v1`；target-owned DPN schema/codec/lowering直接生成 canonical `.dpn.json`；source emitter、compiler/VM profiles、runtime/acceptance scripts、tool assets、compatibility environment variables与相关 tests 全部物理删除；未知旧 profile fail closed。详见 [`targets/10-psy-dpn-lowering.md`](targets/10-psy-dpn-lowering.md) 与 ADR-0035 |
| **PSY-DPN-COVERAGE** | DPN admitted surface | **done（engineering）**：UInt/Int/Goldilocks Field、checked arithmetic/bit/shift、bounded control flow、pureFn inline、bounded aggregates/dense Map、event/void sync-call 部分结构；schedule/assets/ContextRead/Commit/nonempty invariant/payload error 保持精确 FC；allowlist empty |
| **PSY-DPN-ARTIFACTS** | canonical DPN package + zero-tool finalize | **done**：仅 `{name}.dpn.json` materialized-base；无 source、compiler or runtime extras；无 DPN execution/local VM/proof/UPS/network/deploy/formal 声称 |

---

## 5. Wave 3：D3 identity / output 工程→规格对齐

工程 S4–S7c 已接线；下列是**与 accepted 规格仍差的产品形态**（非立刻 formal done）：

| ID | 项 | 状态 |
|---|---|---|
| **D3-E1** | 产品可达 formal-layout `registryDigest` / root codec（或明确永久工程-only） | **done**（2026-08-02：**永久工程-only** 决策 — 产品不暴露 formal `registryDigest`；`TargetRegistryV1` 无 root digest 字段；见 `RECOVERY.md` D3-E1 段） |
| **D3-E2** | SupportClaim/decision 全字段与 resolver 决策面 | **done**（2026-08-02：**工程** `EngineeringSupportClaimV1` + `mintEngineeringSupportClaimsV1` + resolver/describe-target `claimDigest` + `Tests/Materialization/IdentityChainV1`；domain `pf.support-claim.engineering.v1`；**非** formal SupportClaim/predicate/evidence grade） |
| **D3-E3** | 可达 BuildIdentity mint + Plan/IR digest 全 target（T9d 子集） | **done**（2026-08-07 更新：工程 `mintEngineeringBuildIdentityV1` 已绑定 EVM/Solana/NEAR/Noir 与 **Aleo content planDigest**；Aleo domain=`pf.aleo-plan.engineering.v1`，`IdentityChainV1` 钉 product recompute；Psy 仍为 engineering-absent slot；**非** formal BuildIdentity） |
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
| **INV-2** | ADR-0034 通用 L1 Preservation 产品实例 | **engineering done（wave-3′ generic-first，2026-08-09）**：通用 Preservation API（`CodecInvertV1` / `PreservationShapeV1` / `SubjectDataBridgeV1` / `PreservationPackagingV1`）+ ordinary same-file `Counter` / `MiniAmmL1` product positives 已闭合；`ProofInstances/`、`ClosedSubjectPinV1`、ParityCounter/ZeroCounter 专属模块与重复 examples/tests **已物理删除**（合约专属 pin 路径退役）。ADR-0027 supersession **仍独立 pending**；**不** supersede ADR-0027；**不**关闭 formal TASK/TST / target refinement / hermetic/release |
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

## 11. External Author MVP（工程化 / 外部可用性，2026-08-10）

权威草稿：[`product/14-external-author-mvp.md`](product/14-external-author-mvp.md)。  
问题本质：**分发 + host 策略 + 命令闭环**，不是 Lean Hello 语义慢，也不是「再写几个 shell」能代替。

| ID | 项 | 状态 | 说明 |
|---|---|---|---|
| **EA-D1..D5** | 产品决策拍板（外部永不 lake / host dev 默认 / testnet broadcast / 同 VERSION / Agent 双轨） | **done** | ADR-0040 proposed；用户 2026-08-10 确认建议默认 |
| **EA-P0-1** | Release bundle：`pf` + `proof-forge-next` 同包 + install.sh / `pf bootstrap` | **done engineering** | `scripts/package_bundle_dist.sh` + release upload；crates.io 仍仅 orchestrator |
| **EA-P0-2** | `HostMode=dev`：engineering build 不 pin 他机 `host:stat`；只严校 Tool Root | **done engineering** | `LockedToolchainV1.resolveHostMode` 默认 dev |
| **EA-P0-3** | `pf setup -t <target> -y` 真装齐（`proof-forge-next install`） | **done engineering** | 有 compiler 即 spawn install；缺 compiler → bootstrap 提示 |
| **EA-P0-4** | Agent 双轨诚实：stdio MCP spawn 本机 CLI；edge 不装 compile | **done engineering** | README + `03-hello-dapp-agent-playbook` 默认 bundle；edge 仍不 compile |
| **EA-P0-5** | 外部路径永不 lake；预编译 next 为 sole 冷启动 | **done engineering** | INSTALL/setup/README 主路径 = bundle |
| **EA-P0-6** | 错误 → 可执行修复（fix: 行） | **done engineering** | Diagnostic.render + pf compiler wrapper + mismatch fixup |
| **EA-CI-1** | `install-dist-smoke` / external-author-dist-smoke | **done engineering** | release job + `external-author-smoke.yml` |
| **EA-CI-2** | `host-dev-mode-smoke`：非 lock 原生 distro | **done engineering** | ubuntu-22.04/24.04 + debian:bookworm pf-cli unit；source pin `HostMode=dev` |
| **EA-CI-3** | `agent-path-smoke`：仅 env + pf；禁 lake | **done engineering** | EA smoke 断言 + cheatsheet 禁止 lake |
| **EA-P1-1** | `pf test -t evm` 不依赖 monorepo 路径 | **done engineering** | bundle `pf_evm_test.sh` + setup `--with-runtime` |
| **EA-P1-2** | EVM UI 产物契约 | **done engineering** | write-ui-json / deploy UI JSON |
| **EA-P1-4** | `pf network list/show/use` | **done engineering** | embedded catalog |
| **EA-P1-7** | `pf scaffold-ui` | **done engineering** | 模板 + artifacts sync |
| **EA-P1-solana-test** | Solana test 脚本 bundle 解析 + 诚实 skip | **done engineering** | Mollusk 仍需 monorepo harness；`pf verify` 为外部路径 |
| **EA-P2-cheatsheet** | Agent 单页 cheatsheet | **done engineering** | `docs/product/16-external-author-cheatsheet.md` |
| **EA-MVP-SLICE** | External Author MVP 工程收口 | **done engineering** | 公开 Release tag 仍可选（产品发版动作，非代码缺口） |
| **EA-P1-5** | monorepo 增量编译 | **pending** | 贡献者路径；非外部主路径 |

**最小 DoD（EVM-first）**：

```text
干净 Ubuntu（无 monorepo lake 产物）:
  install.sh | sh
  pf new hello --target evm && cd hello
  pf setup --target evm -y && pf doctor --target evm
  pf build   # exit 0，proof-forge.output.v1
# 全程无 lake build、无手改 host-profiles.lock.json
```

推荐击杀：`EA-D*` 确认 → `EA-P0-1` ∥ `EA-P0-2` → `EA-P0-3` → `EA-CI-*` 挂 release gate → 文档两轨（P2）→ P1 日用。

---

## 推荐击杀顺序（产品开发；2026-08-12 全面审查后刷新）

优先序遵循产品判断：**EVM（最完善，formal lighthouse）→ Solana → NEAR → CosmWasm/Wasm**；
Noir/Aleo/Psy/Quint/TON 维持现有边界，不主动扩面。

**Goal/workflow 入口（2026-08-15）**：next-wave Goal/workflow **已退役**（queue 零 pending）。**不要**再 `/goal @.grok/goals/prompt-next-wave.md` 或 `/workflow next-wave-runner`。日常工程下一刀 = [`plan/capability-layer-tasks.md`](plan/capability-layer-tasks.md)（默认 CAP-1a）。对账 [`research/28-project-wide-honesty-audit.md`](research/28-project-wide-honesty-audit.md)。Formal / 产品决策项仍不进 drain。

```text
1. EVM formal lighthouse（ADR-0036，仍 proposed；LH-1…28 + Track F **engineering-done**；**不要**把 TASK/TST 标 done）：
   - shared D2/D3 formal 前置仍 pending：TASK-D2-07 / TST-SEM-002/003 —— **资格/formal 轴，不是 Goal drain**
     · **LH-1…LH-7 packaging done**（engineering only；**不**关闭 formal TASK/TST）：
       · LH-1：OutcomeWireV1 / `pf.reference-outcome.v1`
       · LH-2：public `step` façade + EVM Outcome adapter；Anvil lossless 仍 FC
       · LH-3：ArithOps OutcomeWire + digest-case 投影硬门（`sidecars=18`）
       · LH-4：EventFlow OutcomeWire mint + `OUTCOME_DIGEST_CASE_STEPS` 5 步（`sidecars=23`）
       · LH-5：OwnableLike OutcomeWire mint（caller + assertionFailed；`sidecars=28`）
       · LH-6：`Tests.Semantic.Sem002ShapeV1` Counter reference-trace *shape* pin
       · LH-7：`Tests.Semantic.Sem003ShapeV1` overflow/revert/assert rollback *shape* pin
     · **LH-8 engineering done**（`ee14a0788`）：Sem003 fault + response-precedence OutcomeWire pin
       （`Tests/Semantic/Sem003ShapeV1.lean`）；**不**关闭 TST-SEM-003
     · **LH-9 engineering done**（`3dedfea2a`）：Sem002 external-response returned/reverted +
       context extra/dup pin（`Tests/Semantic/Sem002ShapeV1.lean`）；**不**关闭 TST-SEM-002
     · **LH-10 engineering done**（`ee14a0788`）：Sem003 剩余 standard revert codes
       （invalidShift / castOutOfRange / indexOutOfBounds / uninitialized / alreadyInitialized）
       OutcomeWire pin（`Tests/Semantic/Sem003ShapeV1.lean`）；**不**关闭 TST-SEM-003
     · **LH-11 engineering done**（`7cdca0e85`）：Sem002 wrong kind / wrong arg type /
       response duplicate+reordered / noncanonical arg bytes pin
       （`Tests/Semantic/Sem002ShapeV1.lean`）；**不**关闭 TST-SEM-002
     · **LH-12 engineering done**（`f48a90f79`）：`AGENTS.md` 控制面诚实化（Current/Next 与
       lighthouse / `.grok/next-wave-queue.md` 指针对齐；不代签 formal）；**不**关闭 formal TASK/TST
     · **LH-13 engineering done**（`218ddc447`）：Sem003 trap + unconsumed response →
       unique invalidExternalResponse pin（`Tests/Semantic/Sem003ShapeV1.lean`）；**不**关闭 TST-SEM-003
     · **LH-16 engineering done**（`dfbb4532a`）：`EvmOutcomeAdapterV1` 28-step shared-status pin
       （in-process Outcome constructor ↔ committed case `expectedSharedStatus`）；**不**关闭 C-3 /
       TST-SEM-002/003；Anvil lossless 仍 FC
     · **LH-17/18/19 engineering done**：矩阵头 `2026-08-13`（`f093262eb`）；master Goal 入口退役
       （`ea0f19078`）；RECOVERY 指针 LH-13 + document-status 日期（`ed0ab1cd4`）
     · **LH-20 engineering done**（`88da32e57`）：Quint `context.attachedValue` Plan/materialize
       outside-Q0 FC pin（`Tests/Materialization/QuintSourceV1.lean`）；**不**关闭 formal
     · **LH-21 engineering done**（`25520ecea`）：backlog INV-2 wave-3′ honesty + LH-16 记录
     · **LH-22 engineering done**（`fdfb24dbe`）：`AGENTS.md` Solana 23/414 标为 Mollusk-only
       inventory（非 ordinary CI）；docs-check checkpoint 措辞保留
     · **LH-23 engineering done**（`885d2c048`）：`StepFacadeV1` façade==machine pin
       （declared revert + invalidExternalResponse + invalidInvocation）；**不**关闭 formal TST
     · **LH-24 engineering done**（`9650c5358`）：`OutcomeWireV1` decode negatives
       （truncated envelope + OOR outcome/revert tags）；**不**关闭 formal
     · **LH-25 engineering done**（`10c280f07`）：`Examples/AttachedValueCheck.lean` comment
       honesty after S4 leaves
     · **LH-26…28 engineering done**：`blockHeight`/`chainId`/`self` 跨 target 矩阵；
       invariant `attachedValue` Normalize FC；ContextRead 六键 catalog 诚实化
     ——仍非 formal；LH-1…13 + 16…28 engineering-done；Anvil ↛ OutcomeWire lossless 保持 fail-closed；**C-3 仍 blocked**
     · **2026-08-14 formal closeout 工程半步**：D2-07/D2-06 gap plans + Sem002 missing/extra/wrong-TypeId + Sem001 path-vs-hash pin；**不**关闭 formal TASK/TST
     · **2026-08-14 F-CTX-CORE-TYPEID**：Sem002 同 key 不同 Core result TypeId → structure `.badCfg`（`step` 不可达）；Normalize `fn` 纯度改为 body-local，不再被先前 entry ContextRead 污染；**不**关闭 TST-SEM-002
     · **2026-08-14 F-SEM001-SPAN**：同 AST leading-comment span 位移保持 `.pfsem`/`semanticHash`/`sourceHash`，仅 `.pfprov` 变；**不**关闭 TST-SEM-001
     · ~~**EVM CALL returndata wide admit**~~（2026-08-13 **done**：UInt8–256 CALL/schedule/returndata；Bool/Int/Bytes 仍 FC）
   - identity-bound Reference↔Anvil formal differential（**C-3 仍 blocked**；
     engineering identity/projection 已落地，formal 轨道仍 pending；Anvil lossless FC）——**不是**下一刀编码
   - 不得用其他 target 或业务合约 engineering positives 代签
2. B-CALL-SEM 产品决策 + EVM 残差（并行于 1 的 leaf；**决策，非 Goal drain**）：
   - EVM static-QN callee 仍是 hashed-address stub → 真实 deployment-address binding
   - ~~result-bearing 宽于 UInt64 的 returndata~~（2026-08-13 **done**；Bool/Int/Bytes 仍 FC）
3. Solana 残差：
   - B-CALL-SEM Solana 侧：product CPI callee identity / 外层账户 ABI
   - ~~S2 blockHeight runtime 门~~（2026-08-12 done：product profile admit + Mollusk `block_height.rs`）
   - C-5 fixture 随 Normalize 新面持续扩（ongoing）
4. NEAR 残差（roadmap Phase 4 之外需先决策）：
   - GLIBC loader digests → Tool Lock hermetic pin（产品决策）
   - Map return >8 叶 encoding story；view-caller 保持 FC（诚实边界）
   - Phase 7 formal spine 继续按既有节奏（provenance closure，不冒充 target refinement）
5. CosmWasm/Wasm 残差：
   - SubMsg contract_addr QN stub → 真实地址 binding（挂 B-CALL-SEM）
   - wasmd rung-2（若产品需要；rung-1 已闭）
6. 横切 residual：D3-E8（evidence grade 语义冻结）→ RES-1B memory/process/protocol/stderr
   → B-COMMIT-ZK（Psy 须先冻结 commitment binding）→ QUINT-2 → DOC-JUST-CONTROL（产品决策）
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
| 2026-08-06 | **ADR-0032 U1 Solana 统一 materializer**：sole rail = `solana-sbpf-cpi-elf-v1`；P2–P3-e multi-role 已绿；**P4 默认 + shim 物理删除**：registry/resolver 仅 cpi-elf；plan/elf 不可选；runtime bind 切 cpi 产物；WideDiv/Map fixtures 默认可 build |
| 2026-08-07 | **Aleo ALEO-I1–I4 工程闭合**：Plan content digest 进入 identity chain；query-contract sidecar 进入 exact artifact closure；locked Leo acceptance 去除 PATH/cargo/brew fallback；新增 opt-in compile profile product Finalize、三 content-bound extras、repeat/inspect 与坏工具零发布。RPT-024 的 VM/proof/deploy/query blocker 不变 |
| 2026-08-09 | **INV-2 wave-2 ZeroCounter 通用性门闭合（bf2-docs）**：EvenCounter + ZeroCounter（P=`count==0`）双 preserving product GREEN；packaging/non-pin 已交付；ADR-0034/research-023/Agents/document-status 第二实例状态同步；**不** supersede ADR-0027；MiniAmm P1 仍后置；非 formal |
| 2026-08-10 | **ALEO-LOAD-A**：官方 Leo `abi` 加载门 + reserved-name FC；三波计划（A load / B interpret / C Dev·Testnet；Mainnet 不做产品路径）登记 `docs/plan/aleo-official-load-dev-testnet.md` |
| 2026-08-10 | **ALEO-LOAD-B**：PF Instructions 本地 VM interpret（Leo runner + imports 字节钉扎）；`just aleo-instructions-interpret`；非 proof/Devnet |
| 2026-08-10 | **ALEO-LOAD-C**：testnet deploy/execute **tx save**（默认无 broadcast）；PF↔Leo twin exact bytecode；mainnet 拒绝；broadcast 显式 opt-in |
| 2026-08-10 | **External Author MVP**：登记 §11 + [`product/14-external-author-mvp.md`](product/14-external-author-mvp.md)（bundle 分发 / host dev / setup 真装齐 / CI 三绿线）；诊断：慢在工具链交付与宿主门禁，非 program Hello 语义 |
| 2026-08-12 | **全面审查后刷新**：`pf run` one-shot 五链（EVM/Solana/NEAR/CW/TON）、Solana registry label `runtime-validated-alpha`、NEAR parity Phase 0–4（lite）闭合（Map return cap-8 / UInt128 balance env-read / multiword shift / negative corpus）、CW Map loop cap-8 + Map return + wide shift、context chainId/self（S3）三链 runtime、NEAR/EVM/TON 负例语料、ProofShip 迁出独立仓库；推荐击杀顺序按 EVM→Solana→NEAR→CW 优先序重排 |
| 2026-08-12 | **晚批双 lane**：Solana `context.blockHeight` 开到 sole product profile（CpiDerive admit + Mollusk `block_height.rs` 双 warp-slot 门；`unixTimeSeconds` 仍 FC；23 binaries / 414 active）；EVM corpus observation 硬性 identity binding（`identity{sourceHash,semanticHash}` 全 leg 全 verdict；Reference 取 Loader→Normalize、Anvil 取 deployed manifest、close-case 对 case pin exact join；顺修 StateCell staging 目录回归）。engineering only，非 formal C-3/TST/Stage-0 |
| 2026-08-12 | **EVM formal lighthouse 切片-1**：engineering retained Outcome wire（`OutcomeWireV1` / `pf.reference-outcome.v1`；re-encode identity + digest；Counter Reference corpus 钉测）。关闭 packaging 缺口的工程半步；**不**关闭 TASK-D2-07 / TST-SEM-002/003；下一切片 = target→Outcome adapter 或 formal `step` façade |
| 2026-08-12 | **EVM formal lighthouse 切片-2**：public engineering `step` façade（admit→machine；invalidCore on admit fail）+ EVM Outcome adapter（Reference OutcomeWire digests + shared observation projection；Anvil lossless 仍 FC）。仍非 formal TASK/TST/C-3 |
| 2026-08-12 | **EVM formal lighthouse 切片-3**：ArithOps OutcomeWire mint；digest 案 `sidecars=18`；`close-case` digest 硬门（双 leg required + 投影键相等 + sidecar 校验）；Anvil emit 诚实守卫。仍非 formal C-3/Anvil→OutcomeWire |
| 2026-08-12 | **Next-wave Goal+workflow**：登记 `.grok/next-wave-queue.md` + `prompt-next-wave.md` + `next-wave-runner`（LH-4…7 然后 SYS-S4）；旧 master/business-formalization 队列标历史；不代签 formal/产品决策 |
| 2026-08-12 | **EVM formal lighthouse LH-4**：EventFlow Reference OutcomeWire mint（emit + declared Cap）+ digest list 5 步；`just evm-corpus-reference` `sidecars=23`；observation mint 仍 FC；OwnableLike 仍 observation-only。仍非 formal C-3/TST |
| 2026-08-12 | **EVM formal lighthouse LH-5**：OwnableLike admit/step already yields Outcome；mint 5 OutcomeWire sidecars + assertionFailed constructor pin；`sidecars=28`。仍非 formal C-3/TST |
| 2026-08-12 | **EVM formal lighthouse LH-6**：`Tests.Semantic.Sem002ShapeV1` pins no-init/init default, unixTime context key/type, emit occurrence 0, and exact UInt64 result via public `step` + OutcomeWire. Does **not** close TASK-D2-07 / TST-SEM-002 |
| 2026-08-12 | **EVM formal lighthouse LH-7**：`Tests.Semantic.Sem003ShapeV1` pins overflow / declared Cap / assert rollback (exact reason, unchanged pre-state, zero committed effects) via `step` + OutcomeWire. Does **not** close TST-SEM-003 |
| 2026-08-12 | **SYS-S4-SHARED**：`context.attachedValue` source → UInt64 ContextRead + `context.attached-value` wire requirement + Reference step; nine target Plans remain fail closed |
| 2026-08-13 | **SYS-S4-EVM**：`context.attachedValue` → EVM `CALLVALUE` / Yul `callvalue()` (tag 75, UInt64 range guard); entry that reads the key is payable; view stays view (STATICCALL ⇒ 0); constructor FC; Anvil companion `evm_attachedvalue_anvil_smoke.sh`. NEAR/CW/other Plans remain FC. Not formal C-3 |
| 2026-08-13 | **SYS-S4-NEAR**：`context.attachedValue` → host `attached_deposit` u128 with hi==0 UInt64 guard; init/entry `allowAttached`; **view/pureFn FC**; HostModel + near-sandbox suite (`collect` 42/0/2^64). CW/other Plans remain FC. Not formal |
| 2026-08-13 | **SYS-S4-CW**：`context.attachedValue` → MessageInfo.funds single-denom `stake` (empty=0; multi-coin/wrong denom trap); execute/init `allowFunds`; **query/view FC**; cw-vm mock 3/3. Other Plans remain FC. Not wasmd/formal |
| 2026-08-13 | **EVM formal lighthouse 登记 LH-8/LH-9**：推荐击杀序标 LH-1…7 packaging done；新增 LH-8 pending（Sem003 fault + response-precedence OutcomeWire pin，`Tests/Semantic/Sem003ShapeV1.lean`）与 LH-9 pending（Sem002 external-response returned/reverted + context extra/dup pin，`Tests/Semantic/Sem002ShapeV1.lean`）；明确 engineering-only，**不**关闭 TST-SEM-002/003；C-3 / Anvil lossless 仍 blocked/FC。**不**声称实现已完成 |
| 2026-08-13 | **EVM formal lighthouse LH-8/LH-9 engineering done + 登记 LH-10…12**：LH-8（Sem003 fault + response-precedence）与 LH-9（Sem002 external-response returned/reverted + context extra/dup）标 **engineering done**（reviewer P1 已修：Sem003 top-level main 删除；`lake build proof_forge_next_fast_tests` exit 0）；**不**关闭 TST-SEM-002/003。新增 **LH-10 pending**（Sem003 剩余 standard revert codes：invalidShift/castOutOfRange/indexOutOfBounds/uninitialized/alreadyInitialized）、**LH-11 pending**（Sem002 wrong kind / wrong arg type / response duplicate+reordered / noncanonical arg bytes）、**LH-12 pending**（`AGENTS.md` 控制面诚实化）。C-3 / Anvil lossless 仍 blocked/FC。**不**声称 formal 完成 |
| 2026-08-13 | **EVM formal lighthouse LH-10 engineering done**：Sem003 剩余 standard revert codes（invalidShift/castOutOfRange/indexOutOfBounds/uninitialized/alreadyInitialized）OutcomeWire pin（`ee14a0788`；focused Sem003 run 通过）；**不**关闭 TST-SEM-003。C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM formal lighthouse LH-11 engineering done**：Sem002 wrong kind / wrong arg type / response duplicate+reordered / noncanonical arg bytes OutcomeWire pin（`7cdca0e85`；focused Sem002 run 通过）；**不**关闭 TST-SEM-002。C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM formal lighthouse LH-12 engineering done（LH-14 backlog 对齐）**：`AGENTS.md` 控制面诚实化与 `.grok/next-wave-queue.md` / commit `f48a90f79` 对齐；同节复核 LH-8=`ee14a0788`、LH-9=`3dedfea2a`、LH-10=`ee14a0788`、LH-11=`7cdca0e85`。LH-1…12 engineering-done；**不**关闭 TST-SEM-002/003 或 formal TASK；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM formal lighthouse LH-13 engineering done**：Sem003 trap + unconsumed response → unique invalidExternalResponse OutcomeWire pin（`218ddc447`；`Tests/Semantic/Sem003ShapeV1.lean`）；**不**关闭 TST-SEM-003。C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **LH-17/18/19 engineering done**：`MIGRATION_MATRIX.md` 事实日期 `2026-08-13`（`f093262eb`）；`docs/index.md` live Goal 改 next-wave（`ea0f19078`）；`RECOVERY.md` 指针 LH-13 + `document-status` 日期（`ed0ab1cd4`）。**不**关闭 formal TASK/TST；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM formal lighthouse LH-16 engineering done**：`EvmOutcomeAdapterV1` 28-step shared-status pin（`dfbb4532a`；`Tests/Materialization/EvmOutcomeAdapterV1.lean`）；**不**关闭 C-3 / TST-SEM-002/003；Anvil lossless 仍 FC。顺带刷新 INV-2：wave-3′ generic-first 已闭，合约专属 pin 已删 |
| 2026-08-13 | **EVM formal lighthouse LH-20…25 engineering done**：LH-20 Quint attachedValue outside-Q0 FC（`88da32e57`）；LH-21 INV-2/LH-16 backlog（`25520ecea`）；LH-22 AGENTS Solana 23/414 Mollusk-only（`fdfb24dbe`）；LH-23 StepFacade revert/trap pin（`885d2c048`）；LH-24 OutcomeWire decode negatives（`9650c5358`）；LH-25 AttachedValueCheck comment（`10c280f07`）。**不**关闭 formal TASK/TST；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM formal lighthouse LH-26…28 engineering done**：`Tests/Materialization/Targets.lean` blockHeight/chainId/self admit-decline 矩阵；`AttachedValueContextV1` invariant Normalize FC；`semantic-program-wire.md` 六键 ContextRead catalog + wire≠target 支持。**不**关闭 formal TASK/TST；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-13 | **EVM result-bearing CALL UInt128/256 returndata**：Plan/Yul 按宽度守卫（64/128/256）；参数仍 UInt64；Bool 仍 FC；hashed callee 不变。**不**关闭 B-CALL-SEM / C-3 / Anvil lossless |
| 2026-08-13 | **EVM CALL args UInt128/256**：每参独立宽度；selector 按 `uint64`/`uint128`/`uint256`；全 UInt64 保持旧 tag；UInt8 等仍 FC。**不**关闭 B-CALL-SEM / C-3 / Anvil lossless |
| 2026-08-13 | **EVM schedule args UInt128/256**：与 CALL 同纪律；旧 tag 10 保留；宽参新 tag 20；fire-and-forget 不变。**不**关闭 B-CALL-SEM / C-3 / Anvil lossless |
| 2026-08-13 | **EVM CALL/schedule/returndata UInt8/16/32**：无符号 ABI family 工程接线闭合为 UInt8/16/32/64/128/256；Bool/Int/Bytes 仍 fail closed。**不**关闭 B-CALL-SEM / C-3 / Anvil lossless |
| 2026-08-13 | **SYS-S5-EVM first leaf**：`pf.crypto.sha256` UInt256→UInt256 绑定 EVM SHA-256 precompile `0x02` `STATICCALL`；其它 `pf.crypto.*` 在 EVM fail closed，Bytes ABI、其它 target 与 extension catalog 留待后续。**不**关闭 EXT-CRYPTO / B-CALL-SEM / formal / Anvil lossless |
| 2026-08-13 | **SYS-S5-EVM Anvil known-vector companion**：真实产品 `Sha256Check.yul/.bin` 部署到 Anvil，以 32-byte word `0`/`1` 钉 `pf.crypto.sha256` precompile `0x02` known vectors 与状态回读；host-optional，不进入 ordinary `just ci`。**不**关闭 formal C-3 / EXT-CRYPTO / Anvil lossless |
| 2026-08-13 | **SYS-S5-SOLANA first leaf**：sole `solana-sbpf-cpi-elf-v1` 将 `pf.crypto.sha256` UInt256→UInt256 绑定 `sol_sha256`（dedicated Plan/IR/SBPF，非 generic result-bearing CPI）。其它 `pf.crypto.*` / Bytes / 非 product profile 仍 fail closed。EVM+Solana leaves 仅 engineering **in_progress**；产品路由见下一行；**不**关闭 S5 / EXT-CRYPTO / formal，Mollusk 非 ordinary CI |
| 2026-08-13 | **SYS-S5-SOLANA product route**：`CpiDeriveV1` 将 exact `pf.crypto.sha256` 识别为 host syscall 并跳过 CPI `RawSite` / approved-API 门禁，`ProductSynthesizeV1` 仍强制走 full-body Plan/IR/SBPF；与真实 CPI 共存时 site list 仅保留真实 CPI。其它 `pf.crypto.*` 继续 fail closed；**不**关闭 EXT-CRYPTO / formal，未声称 Mollusk runtime |
| 2026-08-13 | **SYS-S5-NEAR first leaf**：exact `pf.crypto.sha256` UInt256→UInt256 绑定 NEAR host `sha256`（dedicated Plan/IR/WAT、按使用条件导入，非 Promise / generic result-bearing call），并以 exact 32-byte register 门禁回读 UInt256 LE limbs；其它 `pf.crypto.*` / Bytes / 其它 target 继续 fail closed。EVM+Solana+NEAR leaves 仅 engineering **in_progress**；**不**关闭 S5 / EXT-CRYPTO / formal，未声称 runtime gate |
| 2026-08-13 | **SYS-S5 triad tighten**：NEAR host result 允许 store-then-return；Solana Mollusk `sha256_check` 4 测 + NEAR sandbox `Sha256Check` known-vector 门；CosmWasm 无 sha256 host，Plan 对 `pf.crypto.*` 精确 fail closed。EVM Anvil 门保持。Solana runtime inventory **24/418**。**不**关闭 EXT-CRYPTO / formal / Anvil lossless |
| 2026-08-13 | **SYS-S5-TON honesty**：TON 无 sha256 host；Plan 对 `pf.crypto.*` 精确 fail closed（无 `string_hash` 伪装）。SBOM lean-package-files 刷新为 284。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5-NOIR honesty**：Noir 无 sha256 host；Plan 对 `pf.crypto.*` 精确 fail closed（不把 circuit `sha256_compression` / generic ExtFlow oracle 伪装成 host）。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5-ALEO/QUINT honesty**：Aleo/Quint 无 sha256 host；Plan 对 `pf.crypto.*` 精确 fail closed（不把 BHP/Pedersen/Poseidon 或 pf.assets catch-all 伪装成 host）。Aleo 产品路径仍先拒 sync-call。SBOM lean-package-files 刷新为 285。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5-EVM keccak256 + PSY sha256 honesty**：EVM `pf.crypto.keccak256` UInt256→UInt256 绑定 native `keccak256` opcode（非 SHA-256 precompile、非 hashed CALL）。Psy 无 SHA-2 host，`pf.crypto.sha256` 精确 fail closed。**不**关闭 EXT-CRYPTO / Bytes ABI / formal |
| 2026-08-13 | **SYS-S5-SOLANA keccak256**：sole `solana-sbpf-cpi-elf-v1` 将 `pf.crypto.keccak256` UInt256→UInt256 绑定 `sol_keccak256`（dedicated Plan/IR/SBPF，非 hashed/`externalCallResult`）。CpiDerive 将 exact sha256/keccak256 一并跳过 CPI RawSite。其它 `pf.crypto.*` / Bytes / 非 product profile 仍 fail closed。CPI product capability 对 host-only syscall 的 body-only 准入仍是预存失败，本刀不扩 capability。**不**关闭 S5 / EXT-CRYPTO / formal，未声称 Mollusk runtime |
| 2026-08-13 | **SYS-S5-NEAR keccak256**：exact `pf.crypto.keccak256` UInt256→UInt256 绑定 NEAR host `keccak256`（dedicated Plan/IR/WAT、按使用条件导入，非 Promise / generic result-bearing call），并以 exact 32-byte register 门禁回读 UInt256 LE limbs。其它 `pf.crypto.*` / Bytes 仍 fail closed。**不**关闭 S5 / EXT-CRYPTO / formal，未声称 sandbox runtime |
| 2026-08-13 | **SYS-S5-CW keccak256 honesty**：CosmWasm 无 sha256/keccak256 host；Plan 对 exact `pf.crypto.keccak256` 与 sibling QN 精确 fail closed（诊断点名 sha256/keccak256，无 hashed / stdlib 伪装）。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5 TON/Noir/Aleo/Quint keccak256 honesty**：四 target 无 keccak256 host；Plan 对 exact `pf.crypto.keccak256` 精确 fail closed（诊断点名 sha256/keccak256；不把 `string_hash` / `keccakf1600` / BHP-Pedersen-Poseidon / pf.assets catch-all 伪装成 host）。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5 Psy keccak gadget + EVM Anvil keccak + Solana product hole pin**：Psy `keccak256` 钉为 ADR-0039 电路 gadget（UInt64 first-limb 仍开；UInt256 host 形状 FC）。EVM 增 `Keccak256Check` fixture + host-optional Anvil companion（本机实际 pass `hashWord(0|1)`，非 lossless）。Solana host-only sha256/keccak256 产品 capability 预存 FC 改为诚实钉测，不扩 admission。**不**关闭 EXT-CRYPTO / formal / Anvil lossless |
| 2026-08-13 | **SYS-S5 NEAR keccak companion + Psy remaining gadgets**：NEAR sandbox 增 `Keccak256Check` LE known-vector companion（本机实际 pass `hashWord(0|1)`，非 lossless）。Psy `hashPad`/`hashTwoToOne` UInt256 host 与 keccak/hashPad Array4 HashOut 精确 FC；first-limb gadget 仍开。Solana host-only keccak 仍产品 FC，不扩 capability / 不声称 Mollusk pass。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-13 | **SYS-S5 sibling QN + Bytes ABI pin**：shared compile 钉 Bytes 不能当 `pf.crypto` 参数。EVM/Solana/NEAR 钉 `hashPad`/`hashTwoToOne` 与 Bytes-result FC。Noir 另钉 `sha256_compression`/`keccakf1600` 不是 host。**不**关闭 EXT-CRYPTO / formal / Bytes ABI |
| 2026-08-13 | **剩余 target 版图 RPT-025**：登记 §10.1（TGT-SOROBAN/ICP/OPENVM-MVP、Move dossier、第二 zkVM、比特币脚本族钉死默认不实现）；不扩 accepted PRD；不新开平行 gap 清单 |
| 2026-08-13 | **zkVM 三机 Plan 设计 RPT-026**：Cairo/RISC Zero/SP1 独立 Plan + 共享 Q0 fail-closed；TGT-ZKVM-TRIO-DESIGN done；dossier/MVP 仍 pending |
| 2026-08-13 | **TGT-ZKVM-DOSSIERS**：`13-cairo`/`14-risc0`/`15-sp1` research dossier 落地；不进 registry；避开 soroban/icp/openvm 实现车道 |
| 2026-08-13 | **Move wontfix + EXT-CRYPTO-DESIGN**：产品决定不做 Aptos/Sui；RPT-027 钉 crypto 扩展（S5 现状/Merkle/签名/避让三车道） |
| 2026-08-13 | **CRYPTO-D2 EVM ecrecover leaf**：`pf.crypto.ecdsaRecoverSecp256k1` 4×UInt256→UInt256 绑定 precompile `0x01`（Plan tag 23 / STATICCALL）；`Examples/EcdsaRecoverCheck` + Anvil companion；失败返回零地址字；其它 target 仍 FC。**不**关闭 EXT-CRYPTO / formal / Anvil lossless |
| 2026-08-14 | **控制面计数对齐代码**：registry **12 = 12 implemented + 0 design-only**、resolver **15** rows、十二 materializer（含 ICP ADR-0047）；TGT-SOROBAN-MVP / TGT-OPENVM-MVP 标 done；LH-1…28 engineering-done，Next = EVM formal `TASK-D2-07` / `TST-SEM-002/003`。**不**关闭 formal TASK/TST；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-14 | **EVM formal closeout 工程半步**：`PLAN-EVM-FORMAL-D2-07-GAP` + Sem002 response missing/extra + context wrong TypeId pin；`PLAN-EVM-FORMAL-D2-06-GAP` + `Tests.Semantic.Sem001ShapeV1` path-vs-semantic / business-hash pin；Sem001/002/003 进入 Typed shard。**不**关闭 TASK-D2-06/07 或 TST-SEM-001/002/003；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-14 | **F-CTX-CORE-TYPEID**：`Sem002ShapeV1` 钉同 key 不同 Core result TypeId 为 structure/encode `.badCfg`（`step` 不可达）；`NormalizeV1` `fn` ContextRead/Commit 纯度改为 body-local，修复 entry ContextRead 后置 `fn` 被误拒。**不**关闭 TST-SEM-002；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-14 | **F-SEM001-SPAN**：`Sem001ShapeV1` 钉同 AST leading-comment span 位移：`.pfsem`/`semanticHash`/`sourceHash` 不变，仅 `.pfprov`/digest 变，跨 snapshot span 校验 fail closed。**不**关闭 TST-SEM-001；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-14 | **F-CALL-SERIAL**：Wire step-j 闭合 ExternalCall/Schedule 参数形状（Bool / 合法 UInt/Int / Bytes / Principal；不复用 Eq/Ne `serializableType`；Unit/Field/String/aggregates `.badCfg`）。**不**关闭 TASK-D2-06 / TST-SEM-001；C-3 / Anvil lossless 仍 blocked/FC |
| 2026-08-14 | **B-CTX-OPEN honesty close**：NEAR sandbox `BlockHeightCheck`（`scripts/near_runtime_test.sh` `run_suite blockheightcheck`）与 CW `runtime-tests/cosmwasm/tests/block_height.rs` 已在树；S2 runtime residual 按工程 host-optional 门闭合。`unixTimeSeconds` 在 Solana/Noir/Psy/Aleo/Quint 仍 FC。**不**声称 formal / Anvil lossless；SYS-CAP-UNIFY 剩余为 S5/L2 |
| 2026-08-14 | **F-TYPEKEY-USAGE-GAP**：`docs/plan/evm-formal-d2-06-typekey-usage.md` 盘点 TypeKey usage/rank。unused rejection 与 decoder-side rank 会打穿 `cfgOpTypes` 等手写表，需产品决策。下一刀 = 孤立 SPEC `typeKey` 字节形 pin，不装结构门。**不**关闭 TASK-D2-06 / TST-SEM-001 |
| 2026-08-14 | **F-TYPEKEY-BYTES**：孤立 SPEC `typeKey` 字节形 encoder + `Tests.Semantic.WireV1` pin；**不**进入 structure gate，不 reject unused，不 rank `types`。**不**关闭 TASK-D2-06 / TST-SEM-001 |
| 2026-08-14 | **SYS-S5-NEW-TARGETS**：ICP/Soroban/OpenVM 对 `pf.crypto.*` 点名 Plan fail closed（`has no Icp/Soroban/OpenVM host binding`）；无假 host。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-14 | **SYS-S4-NEW-TARGETS**：ICP/Soroban/OpenVM 对 UInt64 ContextRead 四键点名 Plan fail closed；caller/self 因 Principal 仍走泛化 envelope。无新 host。**不**关闭 formal |
| 2026-08-14 | **SYS-S4-QUINT-KEYS**：Quint 对同一四键点名 Plan/materialize fail closed（`has no Quint host binding`）；attachedValue 不再只写 outside-Q0。caller/self 仍泛化。**不**关闭 formal |
| 2026-08-14 | **SYS-E2-NEW-TARGETS**：ICP/Soroban/OpenVM 对 `envRead nativeVaultBalance`（`pf.assets.native.balanceOfSelf`）点名 Plan fail closed；token/U128 仍泛化。无 vault host。**不**关闭 formal |
| 2026-08-14 | **SYS-S4-TON-KEYS**：TON 为 `attachedValue`/`chainId`/`self` 点名 Plan fail closed；`unixTimeSeconds` 仍降 `blockchain.now()`。self 因 Principal 可能在 type-closure 先拒。**不**关闭 formal |
| 2026-08-14 | **SYS-S4-CIRCUIT-KEYS**：Aleo/Noir/Psy 点名剩余 ContextRead 键；`Targets.lean` 矩阵针同步（含 Quint/Soroban UInt64 旧针）。unixTime 未开放。**不**关闭 formal |
| 2026-08-14 | **SYS-S4-MATRIX-NEW**：`Targets.lean` ContextRead 矩阵补 ICP/OpenVM 行（UInt64 键点名无 host；caller/self 走 Principal type-closure）。**不**关闭 formal |
| 2026-08-14 | **SYS-E2-CIRCUIT**：Aleo/Noir/Psy 对 `envRead nativeVaultBalance` 点名 Plan fail closed；Noir 增工程 `planFromCompiledSemanticV1` 仅用于该针。无 vault host。**不**关闭 formal |
| 2026-08-14 | **SYS-E2-TON**：TON 对 `envRead nativeVaultBalance` 点名 Plan fail closed；`unixTimeSeconds` 仍降 `blockchain.now()`。无 vault host。**不**关闭 formal |
| 2026-08-14 | **SOR-1-GAP**：`docs/plan/soroban-s1-wasm-finalize-gap.md` 盘点 locked Wasm/auth/TTL。下一刀 = SOR-1a Finalize honesty pin，不开放 stellar-cli。**不**关闭 SOR-1 / formal |
| 2026-08-14 | **SOR-1A**：`SorobanPlanV1` 钉 S0 Finalize `extraFiles` 空、`deployable=false`、evidence 含 stellar-cli/Wasm toolchain；未知 profile `PF-PROFILE-UNKNOWN`。**不**关闭 SOR-1 / formal |
| 2026-08-14 | **F-COMMIT-COMMENT**：`CfgTypingV1` / `InvariantClosureV1` 注释改指向已存在的 `validateCommitRequirementsV1`（`testCfgCommitCatalogRequirements`），不再写 Commit disclosure deferred。**不**关闭 formal |
| 2026-08-14 | **ICP-1A**：`IcpPlanV1` 钉 locked wat2wasm Finalize（`StateCell.wasm`、`deployable=true`、evidence 含 wat2wasm/PocketIC 未调用、Wasm magic）与未知 profile `PF-PROFILE-UNKNOWN`。套件头不再写 ICP-2 zero-tool。**不**关闭 formal / PocketIC |
| 2026-08-14 | **F-CALL-SERIAL-COMMENT**：`WireV1` invariant-closure ExternalCall/Schedule 注释改指向 `testCfgExternalCallArgSerializability`，不再写 argument serializability deferred。**不**关闭 formal |
| 2026-08-14 | **DOC-MATRIX-CTRL**：`research/12` D-1 改为 12 implemented + 0 design-only 并补 §1d Soroban/OpenVM/ICP；主表/CW/TON ContextRead 对齐 S3/S3b/S4；ADR-0031 S2 改为 sole product Clock.slot（不再写 CPI residual FC）。**不**关闭 formal |
| 2026-08-14 | **OPENVM-1A**：`OpenVmGuestSourceV1` 钉未知 profile `PF-PROFILE-UNKNOWN`。不新开第三 profile。**不**关闭 prove/formal |
| 2026-08-14 | **QUINT-1A**：`QuintSourceV1` 钉未知 profile `PF-PROFILE-UNKNOWN`。不发明 ITF/MBT/verify profile。**不**关闭 QUINT-2 / formal |
| 2026-08-14 | **SYS-S5-ECDSA-FC**：Solana/NEAR/CW 对 `pf.crypto.ecdsaRecoverSecp256k1` 点名 Plan fail closed（`outside admitted scope` / `has no CosmWasm host binding` + QN）。EVM `0x01` leaf 不动。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-14 | **SYS-S5-ECDSA-FC-REST**：Noir/TON/Aleo 点名 no-host + QN；Psy 用 void-call 钉 QN `value-producing`（result-bearing 走 generic admit list，不插 QN）。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-14 | **SYS-S5-ECDSA-FC-NEW**：ICP/Soroban/OpenVM/Quint 对 ecdsaRecover 点名 no-host + QN。EVM leaf 不动。**不**关闭 EXT-CRYPTO / formal |
| 2026-08-14 | **TON-1A**：`TonPlanV1` 钉未知 profile `PF-PROFILE-UNKNOWN`。不新开第二 TON profile。**不**关闭 formal |
| 2026-08-15 | **ALEO-1A**：`AleoInstructionsV1` 钉 zero-tool Finalize（`extraFiles` 空、`deployable=false`、evidence 含 compilation/VM/proof/deployment）与未知 profile `PF-PROFILE-UNKNOWN`。**不**关闭 Leo/formal |
| 2026-08-15 | **PSY-1A**：`PsyDpnV1` 钉 zero-tool Finalize（`StateCell.dpn.json` only、`extraFiles` 空、`deployable=false`、evidence 含 compilation/VM/proof/UPS/deployment）与未知 profile `PF-PROFILE-UNKNOWN`。**不**关闭 formal |
| 2026-08-15 | **CW-1A**：`CosmWasmPlanV1` 钉 locked wat2wasm Finalize（`StateCell.wasm`、`deployable=true`、evidence 含 wat2wasm + runtime remains separate、Wasm magic）与未知 profile `PF-PROFILE-UNKNOWN`。**不**关闭 wasmd/formal |
| 2026-08-15 | **F-TYPEKEY-LEAVES**：`WireV1.testTypeKeyByteForm` 补 Int8/64、Principal、Unit、`array(uint8,4)` 字节形 pin。不进 structure gate，不 reject unused。**不**关闭 TASK-D2-06 / TST-SEM-001 |
| 2026-08-15 | **F-TYPEKEY-FIELDS**：孤立 `typeKey` 补 BLS12-377 Fr / Goldilocks FieldSpec 字节形（bn254 已有）。不进 structure gate。**不**关闭 TASK-D2-06 / TST-SEM-001 |
| 2026-08-15 | **DOC-12T-SYNC**：RPT-025 计数 12+0、档 B materializer 队列标 superseded；矩阵 §2 补 Soroban/OpenVM/ICP；targets README 导语补齐八 engineering leaf。**不**扩 accepted PRD |
| 2026-08-15 | **SOL-0048-GAP**：`docs/plan/solana-adr-0048-next.md` 盘点 D4。`get` production subject + 55 步证书已齐；initialize/increment/overflow 仍只有 Loader observation。下一刀 = 按 `get` 模板逐 recipe 补 resolver/证书。**不**关闭 formal D5 / 不把 provider 接进产品 build |
| 2026-08-15 | **SOL-0048-INIT**：`resolveStateCellInitializeProductionSubjectV1` + 通用 executed HandlerIR/provider join（argument=7，未初始化账户）。与 `get` 共用 production `.s`。**不是** 55 步 sparse 证书，**不**关闭 formal D5 |
| 2026-08-15 | **SOL-0048-INC**：`resolveStateCellIncrementProductionSubjectV1`固定`41 + 1`成功场景，并经真实source binding/compiler/production `.s`与通用executed HandlerIR/provider join闭合。**不是** sparse 证书，**不**关闭 formal D5 |
| 2026-08-15 | **SOL-0048-OVF**：overflow subject直接复用private increment production subject，固定`UInt64.max + 1`；通用join对齐Handler arithmetic trap、provider `0x1001`与exact pre-account snapshot。**不是** sparse 证书，**不**关闭 formal D5 |
| 2026-08-15 | **SOL-0048-INIT-CERT**：identity-bound production artifact + concrete Loader reads + exact fuel 54/55 boundary闭合`initialize(7)` sparse provider certificate，并接入certified HandlerIR/provider production join；argument/signature drift FC。increment success/overflow仍是generic join。**不**关闭formal D5/ELF/SVM runtime |
| 2026-08-15 | **SOL-0048-INC-CERT**：同一production artifact + concrete Loader reads + exact fuel 69/70 boundary闭合`increment(41, 1)` sparse provider certificate，并接入certified HandlerIR/provider production join；before/argument/account/instruction drift FC。overflow仍是generic join。**不**关闭formal D5/ELF/SVM runtime |
| 2026-08-15 | **EVM-CALL-ADDR-GAP**：盘点 [`docs/plan/evm-call-addr-gap.md`](plan/evm-call-addr-gap.md)。static-QN CALL 地址 = path UTF-8 的 Ethereum Keccak 后 20 字节，不是 CREATE/CREATE2。空账户 void CALL 会成功。绑定仍属 `B-CALL-SEM`。**不**改 emitter |
| 2026-08-15 | **EVM-CALL-ADDR-PIN**：`EvmSmoke` CallGate/ScheduleGate 钉 Yul `call(gas(), 0x{last20}`，地址由 `Targets.Evm.Keccak` 对 `Oracle`/`Ledger` 计算。**不**改 emitter，**不**关闭 `B-CALL-SEM` |
| 2026-08-15 | **EVM-CALL-INT-FC**：`EvmSmoke` 钉 Int64 result-bearing CALL 与 Bool 同门（unsigned UInt admit set）。**不**开 signed ABI，**不**关闭 `B-CALL-SEM` |
| 2026-08-15 | **NOIR-CALL-RET-FC**：`NoirRelationModel` 钉 `let x : UInt64 := call Oracle.feed` Plan FC（既有 result-bearing 诊断）。void ExtFlow 仍是 witness-binding。**不**开 response-witness / prove |
| 2026-08-15 | **NEAR-CALL-RET-FC**：`NearHostModel` 钉 result-bearing `Oracle.feed` Plan FC（针是 `result-bearing ExternalCall`，与 void sync 门不同）。**不**开 NEAR generic sync |
| 2026-08-15 | **EVM-CALL-BYTES-FC**：`EvmSmoke` 钉 Bytes 32 result-bearing CALL 与 Bool/Int64 同门。**不**开 Bytes ABI，**不**关闭 `B-CALL-SEM` |
| 2026-08-15 | **CAP-1a**：ICP `context.unixTimeSeconds` 绑定 `ic0.time` ns÷10⁹（init/update/query，import 按使用 gated）。`blockHeight`/`attachedValue`/`chainId` 仍 named FC。**不**关 PocketIC formal / caller |
| 2026-08-15 | **CAP-6**：`Targets.lean` N5 unixTime 下降循环补 Quint/Soroban。ICP 保持 admit。**不**开那些 host |
| 2026-08-15 | **MAT-ATTACHED-QS**：S4 attachedValue 下降循环补 Quint/Soroban。**不**开 attachedValue |
| 2026-08-15 | **MAT-CALLER-QS**：caller 矩阵 admit CosmWasm entry；decline 补 TON/Aleo/Quint/Soroban。**不**开 ICP caller 编码 |
| 2026-08-15 | **MAT-COMMIT-QS**：N5 Commit 十二 target 补齐。CW/TON/Aleo admit identity；Quint/Soroban/ICP/OpenVM 在 envelope FC。**不**关 B-COMMIT-ZK |
| 2026-08-15 | **MAT-PRIV-QS**：N1 private state 补 CW/TON admit；Quint/Soroban/ICP/OpenVM envelope FC。**不**改 disclosure |
| 2026-08-15 | **MAT-COMM-STATE-QS**：N1 commitment state 补 CW/TON admit；Noir+Quint/Soroban/ICP/OpenVM FC。**不**关 B-COMMIT-ZK |
| 2026-08-15 | **MAT-FIELD-QS**：N2b Field bn254_fr 十二 target 补齐。EVM/Noir admit；其余十个 Plan FC。Aleo 钉 BLS12-377≠bn254（与 Psy Goldilocks 同类）。**不**开 Field |
| 2026-08-15 | **MAT-OPT-QS**：N-A4 Option UInt64 state 十二 target 补齐。八个 admit；Quint/Soroban/ICP/OpenVM envelope FC。**不**开 Option |
| 2026-08-15 | **MAT-PRIN-QS**：N2c Principal identity-storage 十二 target 补齐。EVM/Solana/NEAR/Noir/Psy + CosmWasm admit；Aleo/TON/Quint/Soroban/ICP/OpenVM FC。**不**开 Principal / remap |
| 2026-08-15 | **MAT-STRUCT-QS**：N3 named Struct PointBox 十二 target 补齐。六 flatten-to-leaf + CW/TON admit；Quint/Soroban/ICP/OpenVM envelope FC。**不**开 Struct |
| 2026-08-15 | **MAT-ARRAY-QS**：Array UInt64 2 ArrayBox 十二 target 补齐。六 flatten-to-leaf + CW/TON admit；Quint/Soroban/ICP/OpenVM envelope FC。**不**开 Array |
| 2026-08-15 | **MAT-RET-QS**：B-RET-ABI PairRet view-return 十二 target 补齐。七个 admit；Aleo view-over-state + Quint/Soroban/ICP/OpenVM FC。PairRetEntry Aleo pin 保留。**不**开 aggregate return |
| 2026-08-15 | **AGENT-NOTES-0**：引入 [`.agents/notes/`](../.agents/notes/README.md) 记 why/why-not（非 ADR、非 formal、非运行日志）。首批五篇：TypeKey 不进 structure gate、EXT-CRYPTO 不自动开、Soroban S0≠Wasm、focused `lake env lean`、Goal 不关 formal。无 format CI。 |
| 2026-08-15 | **CAP-LAYER-0**：同一能力层 = catalog 行上的 named admit/FC，不是 opcode 对齐、不是第 13 个 TargetId。设计 [`plan/capability-layer-parity.md`](plan/capability-layer-parity.md)；任务 [`plan/capability-layer-tasks.md`](plan/capability-layer-tasks.md)。默认可编码 = CAP-1a ICP `unixTimeSeconds`。不关 formal / SOR-1 / Merkle。 |
| 2026-08-15 | **RPT-028 全仓诚实对账 + 活指针**：Goal-auto drain 标空；AGENTS Next 不再写成「闭合 D2-07」；SBOM 313；Solana sole CPI；ICP 与 zero-tool 拆开；击杀序删已做完的 CALL wide；RPT-014 加 superseded 横幅。**不**关闭 formal 0/27 |

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

### 10.1 剩余 target 落地（2026-08-13；版图 RPT-025）

权威分析：[`research/25-remaining-target-landscape.md`](research/25-remaining-target-landscape.md)。
**不**扩 accepted Phase-1 四目标；formal 仍 EVM-first（ADR-0036）。比特币 Script 族默认不实现。

| ID | 项 | 波次 | 状态 |
|---|---|---|---|
| **TGT-DOC-025** | 剩余 target 版图研究 + README/targets/taxonomy/backlog 挂钩 | T0 | **done**（2026-08-13：RPT-025） |
| **TGT-BTC-SCRIPT-PIN** | 比特币 Script/Tapscript/Miniscript/Liquid/BitVM：UTXO 谓词 ≠ 账户 Semantic；默认 `wontfix-until` 独立 predicate ADR | T6 gate | **done**（2026-08-13：钉在 RPT-025 §2 档 D；无 TargetId） |
| **TGT-SOROBAN-MVP** | `soroban` design-only → target-owned Plan/IR/materializer MVP（XDR/auth/TTL 诚实 FC 子集） | T1 | **done**（2026-08-13：ADR-0044 S0 source-only；auth/TTL/Wasm 仍 FC；**非** formal） |
| **TGT-ICP-MVP** / **ICP-1/2/3** | `icp` implemented（ADR-0047）：sole `icp-wasm-candid-u64-v1`；Plan/IR→`.wat`+`.did`；wat2wasm finalize；PocketIC host-optional runtime；sync+event FC；async advertise-only | T2 | **done**（engineering；非 formal/mainnet） |
| **ICP-1** | ICP capability-gated 控制面（ADR-0047） | 文档 + registry | sole profile/descriptor/resolver/list/inspect | **done** |
| **ICP-2** | ICP target-owned Plan/IR → Wasm + `.did` | target leaf | Counter/StateCell UInt64 窄子集 | **done** |
| **ICP-3** | ICP PocketIC 工程门 | target runtime | `just icp-runtime` / `local --target icp`；缺 POCKET_IC_BIN skip-clean | **done**（host-optional；非 formal） |
| **TGT-OPENVM-MVP** | `openvm` design-only → guest/VmExe MVP（prove 可 FC；无假链上合约） | T3 | **done**（2026-08-14：ADR-0045 O0 guest-source + ADR-0046 O1 opt-in ELF/VmExe；无 keygen/execute/prove/verify；**非** formal） |
| **TGT-MOVE-DOSSIER** | 补齐 `aptos`/`sui` dossier + Move family | T4 | **wontfix**（2026-08-13 产品决定：不做 Move 轴） |
| **TGT-ZKVM-SECOND** | OpenVM 稳定后于 cairo/risc0/sp1 **择一**第二 zkVM leaf | T5 | **pending**（OpenVM O0/O1 engineering MVP 已闭；prove 仍 FC；Plan 设计见 RPT-026；不抢 EVM formal 主轴） |
| **TGT-ZKVM-TRIO-DESIGN** | Cairo/RISC Zero/SP1 三机 Plan/Q0 设计（RPT-026） | T5 prep | **done**（2026-08-13） |
| **TGT-ZKVM-DOSSIERS** | 补齐 cairo/risc0/sp1 dossier（续排编号，不占 `12-quint`） | T5 prep | **done**（2026-08-13：`13-cairo`/`14-risc0`/`15-sp1`） |
| **TGT-CAIRO-MVP** | `cairo` materializer MVP（默认第三 zkVM leaf） | T5+ | **pending**（blocked-on TGT-ZKVM-SECOND 或显式改序） |
| **EXT-CRYPTO-DESIGN** | `extension.crypto` 设计钉（SHA-256 已有 EVM/Solana/NEAR leaf；Merkle/签名/Bytes/余 target） | 横切 | **done**（2026-08-13：RPT-027；不改 registry） |

> **车道（2026-08-13）**：Soroban→`feature-soroban`，ICP→`feature-icp`，OpenVM→`feature-zkvm`；
> `feature-other` **禁止**并行改 TargetRegistry/Descriptor/Resolver/Protocol/ADR-0036；
> 只做版图/zkVM dossier/`EXT-CRYPTO` 设计等 **新文件或已实现 leaf 内** 工作。Move **不做**。

优先序（历史）：**TGT-SOROBAN-MVP → TGT-ICP-MVP → TGT-OPENVM-MVP**（三者 engineering MVP 均已闭合；不扩 accepted PRD）；Move dossier 可与 T1 文档并行，materializer 不得抢先于独立实现 ADR。

优先序（本车道）：`EXT-CRYPTO-DESIGN` / CRYPTO-D2 EVM `ecdsaRecoverSecp256k1` leaf（Plan tag 23）。


> **Solana CPI epic #111–#125 engineering closed** (#110 engineering epic complete): legacy profiles fail closed on call/schedule; exact `solana-sbpf-cpi-elf-v1` advertises sync+extension (async still FC); CpiEscrowIRV1 composite escrow remains test-preactivation history; product activation is ordinary-resolver product capability (not formal TASK-D5).
