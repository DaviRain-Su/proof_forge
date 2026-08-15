---
id: RPT-028
title: ProofForge 全仓诚实性对账（文档×代码）
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# ProofForge 全仓诚实性对账

> Date: 2026-08-15
> Core question: 当前控制面、规格、工程队列与真实代码/制品之间，哪些地方已经不对，下一波该改什么？
> Related: [`AGENTS.md`](../../AGENTS.md) · [`RECOVERY.md`](../../RECOVERY.md) · [`MIGRATION_MATRIX.md`](../../MIGRATION_MATRIX.md) · [`engineering-backlog.md`](../engineering-backlog.md) · [`.grok/next-wave-queue.md`](../../.grok/next-wave-queue.md)
> Exploration: 2 rounds（6 R1 explorers + R1 verifier GAPS + 3 R2 explorers：CI 计数 / 12-target FC / Goal 空队列）
> **不是** formal TASK/TST 完成。formal D1–D4 仍为 **0/27**。

---

## 一、Current state

| 量 | 代码事实 | 活文档是否对齐 |
|---|---|---|
| Registry | 12 implemented + 0 design-only；Solana **sole** `solana-sbpf-cpi-elf-v1` | 本波已改成熟度段 elf-v1 → cpi-elf |
| Resolver | 15 rows（EVM×2 Noir×2 OpenVM×2 其余×1） | 本波已改矩阵「十一行」→ 十五行 |
| Materializers | 12，均 `planFromCapability` ← retained Semantic | 本波已改矩阵「九个」→ 十二个 |
| Formal D1–D4 | 0 done / 1 blocked（`TASK-D1-01`）/ 26 pending | 0/27 仍真；Next 改为 D1-01 blocked + 禁止代签 D2-07 |
| SBOM paths | `lean-package-files.v1.json` `"path":` **313** | Active 已改为 313 |
| Mollusk | 24 `tests/*.rs` binaries；`#[test] fn` **415**；raw `#[test]` **418**（3 条在注释） | 13/304 标为 #125 历史；24/418 保留（`docs_check` 钉串）并注明 415 fn |
| Lean ordinary `just ci` | **12** shard exes（9 nontarget + 3 target-smoke）；**不含** Mollusk | Active 已拆开 Mollusk vs Lean |
| Goal-auto queue | **零 `pending` 行** | 本波已退役 Goal/workflow 入口 |
| Alpha leftovers | `planFromAlpha` / `AlphaCompatibility` / `Core/Source` 无；`TypedV1.lean` 0 文件 | 本波已删「仍 orphan」旧句 |

产品链名称仍在：`IO.FS.readFile` → `selectProgramV1ProductWithTheoremInventory` → `normalizeProgramLocatedV1` → `compileProgramProductV1` → `certifyInlineProofV1`（早于 resolve）→ capability。`--proof-bundle*` 产品面已删。`justfile` 无 `governance-check` / `release-check`。

---

## 二、Comparison（按维度）

### 1. 控制面指针

活入口把「下一刀」指到 **已经做完** 或 **禁止自动做** 的工作：

- `AGENTS.md` Next / `RECOVERY.md` L140 / backlog 击杀序 L459：闭合 `TASK-D2-07` / `TST-SEM-002/003`
- `.grok/goals/prompt-next-wave.md` L12：resume `starting at LH-4`（LH-4 已 done）；L158：空队列 → `NEXT=FORMAL_C3`
- `.grok/next-wave-queue.md` L136：「Live drain continues」——假
- backlog L505–512：CALL wide admit 与「宽于 UInt64 returndata」仍当 next；changelog L589–592 已 done（2026-08-13）

### 2. D1–D2 产品链

路径名称与 alpha 删除对齐。过期的是 **规格/研究**：

- `docs/research/14-n5-call-return-schema.md` 仍写 statement-only void `call`（2026-08-02）
- `docs/research/11-feature-coverage-audit.md` L77 仍写 v1 external call 无返回值
- `docs/specs/semantic-core.md` L145 仍写 response 无 value；`docs/specs/semantic-program-wire.md` L557–558 已记 N-CALL-RET optional result
- 产品 `N-CALL-RET` **done**（值位置 `call`、`returnValue?`）
- TypeKey usage/rank 结构门仍缺（会打破 hand-built tables）；isolated `typeKey` byte-form 已 pin
- ExternalCall/Schedule arg serializability **工程已闭合**；本波已删 AGENTS 里残留的「继续 deferred」旧句

### 3–4. 十二 target（R2 表；Lower/Finalize 抽查，非逐 `irFromCapability`）

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

AGENTS Program 行曾把 ICP 与 Aleo/Psy/Soroban/OpenVM 一并写成「zero-tool/non-deployable」——本波已拆开。CW/NEAR「sync 拒」过粗（pf.assets sync 已 admit）。Quint「仅 4-key」过时（现 6-key）。

**deployable ≠ maturity ≠ host runtime**（`expectedMaturityLabelOfKindV1`）：evm/solana `runtime-validated-alpha`；near/cosmwasm `wasm-validated-alpha`；noir/quint/ton/soroban/openvm/**icp** `source-only`；aleo `instructions-only`；psy `dpn-only`。ICP/TON 可以 Finalize `deployable=true` 而 label 仍是 `source-only`。GHA 另有 path-filtered `solana-runtime` / `near-runtime` / `cosmwasm-runtime`，不等于 ordinary `just ci`。

### 5. Formal vs engineering

无假 `done`、无假 EV。P1 剩余是 **缺 formal EV**、TypeKey usage、C-3、SPEC void vs 产品 return、`TST-PROOF-001`。ADR-0036 仍 `proposed` 但多处写成「固定」。

### 6. 测试 / research 索引

- `docs/research/README.md` 仍写日常只回写 11+12+13，未列本报告
- ordinary Lean CI = 12 shards，不是 13/304
- GHA 另有 path-filtered `solana-runtime`；「∉ `just ci`」≠「∉ CI」

---

## 三、Gaps（按优先级）

| Pri | 现状 | 建议 |
|---|---|---|
| **P0** | Goal/AGENTS/RECOVERY 把下一刀写成 formal closeout 或 LH-4 resume | 退役 next-wave Goal；Next = 诚实文档 / 产品决策；禁止 `NEXT=FORMAL_C3` |
| **P1** | 活计数/profile 错：SBOM 287、elf-v1、ICP non-deployable、CALL wide 仍 next、矩阵九/十一/10+2、RPT-014 void-call | 改活指针；13/304 留作 #125 历史（`docs_check` 仍钉此串） |
| **P1** | SPEC-SEM-001 vs WIRE vs 产品 return 三分裂 | 要关 formal 002 须先 ADR；不要再钉 Sem002 returned |
| **P2** | 历史 blockquote 9+3、TON dossier 9+3、slides、ADR-0036「固定」 | 不挡下一刀；顺手改活页即可 |

---

## 四、Verification records

| Claim | Method | Result |
|---|---|---|
| 12+0 / Solana sole CPI | Read `TargetRegistryV1.lean` L533–581 | 12 `row`；`solanaSbpfCpiElfV1` only |
| 15 resolver | Read `RequirementResolverV1.lean` L493–520 | 15 `mkImplementedRow` |
| formal 0/27 | Read `04-task-breakdown.md` L360–403 | 0 done / D1-01 blocked / 26 pending |
| SBOM 313 | `rg '"path":'` on package-file JSON | 313 |
| queue empty | `rg '\| pending'` on next-wave-queue | 0 |
| 13/304 meaning | `docs_check.py` L1620–1633 + ADR-0028 / matrix L635 | #125 Mollusk baseline，非 Lean |
| 24 binaries / 415 fn / 418 raw | count `runtime-tests/solana/tests/*.rs` + `#[test]` then `fn` | 24 / 415 / 418 |
| Lean `just ci` shards | `justfile` `test-nontarget` + `test-targets` | 12 exes |
| CALL wide done | backlog changelog L589–592 vs kill-order L505 | 击杀序过期 |
| ICP deployable | `Icp/FinalizeV1.lean` `deployable := true` | AGENTS Program 行过期 |
| RPT-014 stale | Read L12–23 vs N-CALL-RET backlog | 研究页过期 |
| SPEC-SEM void | `semantic-core.md` L145 vs `semantic-program-wire.md` L557 | 三分裂 |
| Goal LH-4 / FORMAL_C3 | Read `prompt-next-wave.md` L12, L158 | 仍在 |
| no governance/release recipes | `rg` justfile | 0 matches |
| TypedV1 file | Glob `**/TypedV1.lean` | 0 |

---

## 五、Priority roadmap

| Priority | Item | Scope | 不是什么 |
|---|---|---|---|
| **0** | 诚实文档：AGENTS Active/Next、RECOVERY 指针、queue/Goal 退役、击杀序、矩阵九/十一、RPT-014 banner、research README | 文档 + `docs_check` 若改 418 串 | 不改 formal 0/27 |
| **1 决策** | SPEC-honesty ADR（void vs typed return） | accepted SPEC | 不是再写 Sem002 pin |
| **1 决策** | B-CALL-SEM / D3-E8 / DOC-JUST-CONTROL / QUINT-2 / SOR-1 Wasm | Track C | Goal 必须 skip |
| **2 若继续编码** | 同一能力层：[`plan/capability-layer-tasks.md`](../plan/capability-layer-tasks.md) 默认 **CAP-1a**（ICP time）。其余 CAP-D-* 等人拍。EXT-CRYPTO Merkle / RES-1B / C-5 / ADR-0048 另叶 | 已实现 leaf | 不是新 TargetId / formal 代签 |
| **3 formal 真轴** | 资格主机上 TASK-D1-01 → D2-06 → D2-07 | `04-task-breakdown` | 单维护者默认做不了；禁止发明 EV |

---

## 六、Conclusion

1. **工程 Goal-auto drain 已空。** 再开 `prompt-next-wave` / `next-wave-runner` 会重做 LH-4 或走到禁止的 C-3。
2. **Formal 0/27 仍然诚实。** 错的是把「闭合 TASK-D2-07」写成下一刀编码。
3. **本波已改的活句子：** `solana-sbpf-cpi-elf-v1` sole、ICP 与 zero-tool 拆开、SBOM 313、Goal/Next 退役 drain、击杀序 wide CALL 标 done、RPT-014 superseded 横幅。晚到 explorer 后补：Capability caveat 宽 returndata、RECOVERY 完成口径 十五行/十二 materializer/十二 descriptors、`Solana.lean` 默认 profile、Engineering slice ContextRead 已接线 vs formal CAP。
4. **再往后：** 工程车道 = 同一能力层（CAP-1a 默认可做；Solana unixTime / TON sha256 / Soroban ledger / ICP caller 须人拍）。SPEC/B-CALL-SEM 仍是决策。不要再钉 Sem00x。
5. **不要再钉 Sem00x。** corpus 工程面已耗尽。

---

## 七、Blind spots

- 未跑 `cargo test -- --list` 核对 415。
- 未逐文件重读 S7a/b/c private-ctor（产品 status 声称仍在）。
- 未改 presentation/slides、全部 `docs/targets/*.md` 历史段。
- 未对 accepted SPEC 全文逐条；只抽样 SEM/WIRE/LANG。
- 十二 materializer `irFromCapability` 未逐个打开（只确认存在 + Lower/Finalize 门）。
- R1 六个 explorer 中五个被摘要中断；R2 三路补齐了 verifier 点名的缺口。
