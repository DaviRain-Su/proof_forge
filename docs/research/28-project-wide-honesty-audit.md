---
id: RPT-028
title: ProofForge 全仓诚实性对账（文档×代码）
status: draft
owner: engineering
updated: 2026-08-19
normative: false
---

# ProofForge 全仓诚实性对账

> Date: 2026-08-15（**2026-08-19 事实重核**：计数与 Gaps 已按新代码事实刷新；当时快照保留备查）
> Core question: 当前控制面、规格、工程队列与真实代码/制品之间，哪些地方已经不对，下一波该改什么？
> Related: [`AGENTS.md`](../../AGENTS.md) · [`RECOVERY.md`](../../RECOVERY.md) · [`MIGRATION_MATRIX.md`](../../MIGRATION_MATRIX.md) · [`engineering-backlog.md`](../engineering-backlog.md) · [`.grok/next-wave-queue.md`](../../.grok/next-wave-queue.md)
> Exploration: 2 rounds（6 R1 explorers + R1 verifier GAPS + 3 R2 explorers：CI 计数 / 12-target FC / Goal 空队列）
> **不是** formal TASK/TST 完成。formal D1–D4 仍为 **0/27**。
> **2026-08-19 addendum**：P0 已全部闭合（Goal 退役、Next=B-CALL-SEM）；活计数刷新为
> **13 implemented+0 / 17 resolver rows / SBOM 339 / Mollusk tracked 26 binaries·426 tests**；
> CAP-1a…5、CAP-X-BYTES、CAP-X-MERKLE、诚实边界波（RES-1B/TON-C4/XRPL-view/ecdsa predicate）
> 均已落 main。P2 活页 12+0 / ADR-0036「固定」残差已于同日闭合（ADR-0036 仍 `proposed`，未升格）。
> SPEC-SEM-001 三分裂仍待 **ADR-0051** 人拍。

---

## 一、Current state

| 量 | 代码事实 | 活文档是否对齐 |
|---|---|---|
| Registry | **13 implemented + 0 design-only**（2026-08-19；XRPL 经 ADR-0049/0050 加入，双 profile）；Solana **sole** `solana-sbpf-cpi-elf-v1` | AGENTS/矩阵已对齐 |
| Resolver | **17 rows**（EVM×2 Noir×2 OpenVM×2 XRPL×2 其余×1） | 已对齐 |
| Materializers | **13**，均 `planFromCapability` ← retained Semantic | 已对齐 |
| Formal D1–D4 | 0 done / 1 blocked（`TASK-D1-01`）/ 26 pending | 0/27 仍真；Next 改为 D1-01 blocked + 禁止代签 D2-07 |
| SBOM paths | `lean-package-files.v1.json` `"path":` **339**（2026-08-19 实测；**SBOM 244** 为 docs-check 历史 checkpoint 标识，两者并存不矛盾） | 已对齐 |
| Mollusk | tracked **26** integration binaries / **426** active tests（2026-08-19；`#[test] fn` 以 docs_check 钉串为准）；13/304 为 #125 历史基线 | 已拆开 Mollusk vs Lean |
| Lean ordinary `just ci` | **12** shard exes（9 nontarget + 3 target-smoke）；**不含** Mollusk | Active 已拆开 Mollusk vs Lean |
| Goal-auto queue | **零 `pending` 行** | Goal/workflow 入口已退役 |
| Alpha leftovers | `planFromAlpha` / `AlphaCompatibility` / `Core/Source` 无；`TypedV1.lean` 0 文件 | 已删「仍 orphan」旧句 |

产品链名称仍在：`IO.FS.readFile` → `selectProgramV1ProductWithTheoremInventory` → `normalizeProgramLocatedV1` → `compileProgramProductV1` → `certifyInlineProofV1`（早于 resolve）→ capability。`--proof-bundle*` 产品面已删。`justfile` 无 `governance-check` / `release-check`。

---

## 二、Comparison（按维度）

### 1. 控制面指针

**2026-08-19：本节四条已全部闭合**（当时事实保留备查）：

- ~~`AGENTS.md` Next / `RECOVERY.md` L140 / backlog 击杀序 L459：闭合 `TASK-D2-07`~~ → Next 现为 B-CALL-SEM（人拍），formal 代签已明文禁止
- ~~`.grok/goals/prompt-next-wave.md` resume LH-4 / `NEXT=FORMAL_C3`~~ → Goal/workflow 入口已退役
- ~~`.grok/next-wave-queue.md`「Live drain continues」~~ → queue 零 pending 已核实
- ~~backlog CALL wide admit 仍当 next~~ → 已标 done（2026-08-13），后续 CAP-X-BYTES/MERKLE 均已闭合

### 2. D1–D2 产品链

路径名称与 alpha 删除对齐。过期的是 **规格/研究**：

- `docs/research/14-n5-call-return-schema.md` 仍写 statement-only void `call`（2026-08-02）
- `docs/research/11-feature-coverage-audit.md` L77 仍写 v1 external call 无返回值
- `docs/specs/semantic-core.md` L145 仍写 response 无 value；`docs/specs/semantic-program-wire.md` L557–558 已记 N-CALL-RET optional result
- 产品 `N-CALL-RET` **done**（值位置 `call`、`returnValue?`）
- TypeKey usage/rank 结构门仍缺（会打破 hand-built tables）；isolated `typeKey` byte-form 已 pin
- ExternalCall/Schedule arg serializability **工程已闭合**；本波已删 AGENTS 里残留的「继续 deferred」旧句

### 3–4. 十三 target（R2 表；Lower/Finalize 抽查，非逐 `irFromCapability`）

| Target | Profiles | Deployable | Invariants | Constants | String evt/err | call / schedule |
|---|---|---|---|---|---|---|
| evm | v1 + cancun-v1 | true | FC | FC | FC（public UInt64） | 双开；schedule=同 tx CALL 丢结果 |
| solana | **cpi-elf-v1 only** | true | FC | FC | FC | sync CPI；schedule FC |
| near | wasm-raw-u64 | true | **special** erasure | open（≤64+Bool） | FC | schedule Promise；generic sync FC；pf.assets sync |
| noir | source + nargo-acir | false | FC | FC | FC | 双开=witness-binding |
| aleo | instructions-v1 | false | FC | open（literal） | FC（event decline） | 双 FC |
| psy | dpn-v1 | false | FC | open（窄宽） | FC | void sync PARTIAL；schedule FC |
| quint | source-u64-model | false | **open Q0** | FC | FC | pf.assets sync；schedule FC |
| cosmwasm | wasm-u64 | true | FC | open（≤64+Bool） | FC | schedule SubMsg；generic sync FC；pf.assets sync |
| ton | tolk-boc | **条件**（有 fift→true） | FC | FC | FC | sync FC；schedule out-msg |
| soroban | source-u64 | false | FC | FC | FC | 双 FC |
| openvm | source + elf | false | FC | FC | FC | 双 FC |
| icp | wasm-candid-u64 | **true**（wat2wasm） | FC | FC | FC（表空） | sync FC；schedule advertise 后 Plan FC |
| xrpl | bedrock-source + bedrock-wasm（opt-in ambient rustc） | false | FC | open（literal inline） | FC | 双 FC（ADR-0052 TIME/CALLER 等 owner；SHA keep-FC） |

AGENTS Program 行曾把 ICP 与 Aleo/Psy/Soroban/OpenVM 一并写成「zero-tool/non-deployable」——本波已拆开。CW/NEAR「sync 拒」过粗（pf.assets sync 已 admit）。Quint「仅 4-key」过时（现 6-key）。

**deployable ≠ maturity ≠ host runtime**（`expectedMaturityLabelOfKindV1`）：evm/solana `runtime-validated-alpha`；near/cosmwasm `wasm-validated-alpha`；noir/quint/ton/soroban/openvm/**icp** `source-only`；aleo `instructions-only`；psy `dpn-only`。ICP/TON 可以 Finalize `deployable=true` 而 label 仍是 `source-only`。产品 `inspect` 现以 inspect-only `maturityResidual` 命名该裂缝（icp=`deployable-wasm-vs-source-only-label`、ton=`conditional-boc-deployable-vs-source-only-label`）；**不**改 label、**不**进 SupportClaim。GHA 另有 path-filtered `solana-runtime` / `near-runtime` / `cosmwasm-runtime`，不等于 ordinary `just ci`。

### 5. Formal vs engineering

无假 `done`、无假 EV。P1 剩余是 **缺 formal EV**、TypeKey usage、C-3、SPEC void vs 产品 return、`TST-PROOF-001`。ADR-0036 仍 `proposed`；活页已改为「主张收口 / records the boundary」，**未**升格 accepted。

### 6. 测试 / research 索引

- `docs/research/README.md` 仍写日常只回写 11+12+13，未列本报告
- ordinary Lean CI = 12 shards，不是 13/304
- GHA 另有 path-filtered `solana-runtime`；「∉ `just ci`」≠「∉ CI」

---

## 三、Gaps（按优先级）

| Pri | 现状 | 建议 |
|---|---|---|
| ~~**P0**~~ | **closed 2026-08-19**：Goal/AGENTS/RECOVERY 指针已全改；`NEXT=FORMAL_C3` 已禁 | 无需再动 |
| **P1** | 活计数/profile：本文件 2026-08-19 已重核（13/17/339/26·426）；AGENTS/矩阵此前已对齐 | 无遗留；SBOM 数字随 pin 漂移属正常 |
| **P1** | SPEC-SEM-001 vs WIRE vs 产品 return 三分裂 | **仍待人拍**：ADR-0051 accept 后仅改 SPEC 文字；不要再钉 Sem002 returned |
| ~~**P2**~~ | 历史 blockquote 9+3、TON dossier 9+3、slides、ADR-0036「固定」 | **closed 2026-08-19**：活页 README/slides/TON·Quint dossier/RPT-025/backlog/RECOVERY/toolchain/matrix D3 改为 13+0；ADR-0036 活页改为「主张收口」（仍 `proposed`，**未**升格） |

---

## 四、Verification records

2026-08-15 快照的方法与结果保留；**2026-08-19 重核值**如下（行号会漂移，以内容为准）：

| Claim | 2026-08-19 重核 |
|---|---|
| Registry membership | **13 `row`**（`TargetRegistryV1.lean` 约 L711–800）；Solana sole `solanaSbpfCpiElfV1` |
| resolver rows | **17 `mkImplementedRow`**（`RequirementResolverV1.lean` 约 L502–534） |
| formal 0/27 | 仍真（0 done / D1-01 blocked / 26 pending） |
| SBOM | **339**（`rg '"path":'` on package-file JSON；历史 checkpoint 标识 244 由 docs-check 继续钉在 AGENTS.md） |
| queue empty | 仍真（0 pending） |
| 13/304 meaning | 仍是 #125 Mollusk baseline，非 Lean；当前 tracked 26 binaries / 426 tests |
| Lean `just ci` shards | 仍真（12 exes） |
| CALL wide / ICP deployable / RPT-014 / 击杀序过期 | 产品侧均已修 |
| SPEC-SEM void vs wire | **仍在**（ADR-0051 proposed；人拍） |
| Goal LH-4 / FORMAL_C3 | **已废除**（入口退役横幅在） |
| no governance/release recipes | 仍真（0 matches） |
| TypedV1 file | 仍真（0） |

---

## 五、Priority roadmap

| Priority | Item | Scope | 不是什么 |
|---|---|---|---|
| ~~**0**~~ | ~~诚实文档刷新~~ | **closed 2026-08-19**（本文件 + RPT-027 + research README + 索引句 + backlog 行） | — |
| **1 决策** | SPEC-honesty ADR-0051（void vs typed return） | accepted 后仅改 SPEC 文字 | 不是再写 Sem002 pin |
| **1 决策** | B-CALL-SEM / D3-E8 / DOC-JUST-CONTROL / QUINT-2 / SOR-1 Wasm | Track C；决策清单见 `.agents/notes/proposed/architecture/2026-08-16-b-call-sem-decision-inventory.md` | 决策前不可编码 |
| **2 若继续编码** | 能力层 wave 4/5 与诚实边界波、RPT-028 P2 活页计数均已 done（2026-08-19）；剩余可编码项已基本耗尽 | 已实现 leaf | 不是新 TargetId / formal 代签 / ADR 升格 |
| **3 formal 真轴** | 资格主机上 TASK-D1-01 → D2-06 → D2-07 | `04-task-breakdown` | 单维护者默认做不了；禁止发明 EV |

---

## 六、Conclusion

1. **工程 Goal-auto drain 已空。** 再开 `prompt-next-wave` / `next-wave-runner` 会重做 LH-4 或走到禁止的 C-3。
2. **Formal 0/27 仍然诚实。** 错的是把「闭合 TASK-D2-07」写成下一刀编码。
3. **本波已改的活句子：** `solana-sbpf-cpi-elf-v1` sole、ICP 与 zero-tool 拆开、Goal/Next 退役 drain、击杀序 wide CALL 标 done、RPT-014 superseded 横幅。**2026-08-19 续**：本文件计数刷新（13/17/339/26·426）、P0 标 closed、能力层 wave 4/5 与诚实边界波落库（CAP-X-BYTES/CAP-X-MERKLE/RES-1B/TON-C4/XRPL-view/ecdsa predicate）；**P2 活页 12+0 / ADR-0036「固定」已闭**（ADR 仍 proposed）。
4. **再往后：** 工程车道可编码项已基本耗尽；下一批是真决策（B-CALL-SEM 决策包材料已齐、ADR-0051、D3-E8、QUINT-2/SOR-1、XRPL TIME/CALLER）。不要再钉 Sem00x。
5. **不要再钉 Sem00x。** corpus 工程面已耗尽。

---

## 七、Blind spots

- 未跑 `cargo test -- --list` 核对 415。
- 未逐文件重读 S7a/b/c private-ctor（产品 status 声称仍在）。
- 未改 presentation/slides、全部 `docs/targets/*.md` 历史段。
- 未对 accepted SPEC 全文逐条；只抽样 SEM/WIRE/LANG。
- 十二 materializer `irFromCapability` 未逐个打开（只确认存在 + Lower/Finalize 门）。
- R1 六个 explorer 中五个被摘要中断；R2 三路补齐了 verifier 点名的缺口。
