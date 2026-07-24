---
id: PHASE-5
title: 测试与验收规格
status: accepted
owner: quality
updated: 2026-07-24
normative: true
approvers: davirain
approvedAt: 2026-07-24
reviewCommit: 102342f5c89600780220e6c075f7ddac937dcf2e
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/102342f5c89600780220e6c075f7ddac937dcf2e
openFindings: none
---

# Phase 5：测试与验收规格

## 原则

测试骨架先于实现。source/type/semantic 层以 reference interpreter 为 oracle；target
验收比较声明的 observable dimensions，而不是二进制相等。每个公共接口至少包含
happy、boundary、error/attack 三类测试。

## 测试层级

1. Parser/elaborator unit：语法、span、hygiene、跨模块导出。
2. Type/effect/property：类型、终止、披露、requirements 决定性。
3. Semantic model：reference step、rollback、effect ordering。
4. Resolver/Plan：capability exact match、Plan invariants、honest rejection。
5. Artifact：schema、hash、official validator、可重现性。
6. Runtime/proof：EVM/Solana/NEAR trace 与 Noir prove/verify。
7. Security/clean-room：路径、环境、cache、工具输出和资源边界。

## 核心向量

### Counter

初始 `count=0`；`increment(1)` 返回 1；`increment(2)` 返回 3；`get()` 返回 3；
从 `UInt64.max` 执行 `increment(1)` 必须失败、返回稳定 overflow 错误且状态仍为 max。
四目标进程内语义观测统一为 structural `OutcomeV1`；当前 evidence v1 的
`(status,return,logicalState,effects,errorClass)` 只保留 development verdict/diagnostic projection，
不能充当无损 Outcome 或 formal differential evidence。

### PrivateSum4

四个 private `UInt64` 输入以 checked-u64 语义求和，public `UInt64` expected sum；Noir
prove/verify 成功，错误 sum 或任一步 overflow 的 witness 验证
失败。public input vector 精确为 `[expectedSum]`；semantic/plan/circuit binding 放在 proof envelope
而不是伪装成 private/public 业务参数。manifest、public ABI、日志、诊断、cache key 和被拒绝
target 的 staging/partial artifact 不得含四个 runtime private value 的结构化字段或 canonical
encoding。proof 可以依赖 witness 且 proof bytes 可以不同；不得用任意 byte-substring absence 冒充
ZK 证明。验收依赖锁定并经批准的 backend/profile 的 ZK security contract，并要求同一 circuit/
plan 的 VK 在不同 witness 间 byte-identical、proof envelope 不含 raw witness record。

caller-owned `--inputs` 必须是 `0600` regular single-link file，compiler 只做 no-follow stable read，
前后 inode/mode/size/hash 不变且绝不删除。只有 compiler-created private staging/witness file 使用
`0700` 目录与 `0600` 文件，并在 success、invalid witness、tool failure、timeout 和 signal 后删除。
EVM/Solana/NEAR 因不能保持 private witness 语义，在 Plan 前以 `PF-REQ-UNSUPPORTED`
拒绝。

### Accumulator

内部 genericity 向量拥有 `total : UInt64`、`init(seed)`、`add(amount)` 和 `current()`；执行
`init(7) → add(5) → current()` 得 12，从 `UInt64.max` add 1 必须失败且状态不变。它必须经过与
Counter 相同的 parser/type/semantic/resolver/materializer 通用路径，禁止 program/name matcher；
四目标比较 source/semantic hash 和适用的 normalized artifact/runtime/proof observation。

## Acceptance Matrix

| ID | 场景 | 预期 | 证据级别 |
|---|---|---|---|
| TST-SRC-001 | Source.ProgramV1 wire/span/NodeId canonicalization | exact constructor/field bytes 与 sourceHash cross-implementation golden；path sensitivity、span/file independence；forced truncated-ID collision 稳定零输出拒绝 | unit/property/golden/security |
| TST-SRC-002 | per-program Syntax 256/257 nesting、100000/100001 nodes、qualified identity 与 CLI 16 MiB | 精确边界；Syntax/identity 超限 `PF-BOUND-001`，CLI byte 超限 `PF-SRC-INVALID` | unit/integration/security |
| TST-SRC-003 | `program Counter where` 与非法顶层形式 | 正例导出；非法稳定诊断 | unit |
| TST-SRC-004 | 每种 Phase 1 declaration（含 pure fn/proof reference） | 各有 parser 正例/反例与 stable Source AST；不要求 D1 完成 type check | unit/integration |
| TST-SRC-005 | 每种 Phase 1 statement/expression（含 local fn/external call 分流） | 各有 parser 正例/反例与 stable Source AST；typed/effect/bound 由 D2 tests 负责 | unit/integration |
| TST-SRC-006 | attribute export 跨模块/import 顺序 | identity 稳定，无重复 | integration |
| TST-TYPE-001 | widths、Field、map、struct、enum | `Field bn254_fr` exact 映射成功；其他/alternate field ID 与 modulus substitution 精确失败 | property |
| TST-TYPE-002 | accepted-width duplicate/name index、late lookup 与错误顺序 | 声明序 ID/遮蔽/诊断不变；required hash ops、single state-builder 与已知数组搜索回归受门禁 | unit/structural/complexity |
| TST-TYPE-003 | 全部 Phase 1 declaration + local fn + proof reference | typed fixture 全覆盖；exact fn lookup/type/effect/acyclicity、Bool invariant 与 proof-reference source binding；不装载 theorem | unit/integration/negative |
| TST-PROOF-001 | immutable proof bundle + post-canonical theorem signature | exact current Source.Program + `.pfsem`/`.pfprov`/semanticProvenanceDigest + bundle/olean/toolchain/trust-policy join；wrong program/ordinal/provenance/closure/digest/unsafe declaration fail closed | integration/security |
| TST-EFFECT-001 | view 写状态/发 effect | `PF-EFFECT-001` | negative |
| TST-BOUND-001 | 无界循环/递归 | `PF-BOUND-001` | negative |
| TST-VIS-001 | private 流入 public/log | `PF-VIS-001` | security |
| TST-SEM-002 | exact Invocation/context/responses/OutcomeV1 + Counter reference trace | initializer/no-init default state、context key/type、effect occurrence 与 normalized result 精确 | model |
| TST-SEM-003 | revert/trap/overflow rollback | exact reason/fault constructor；unchangedState，零 committed effects | model |
| TST-REQ-001 | requirement inference | 稳定集合、origin/span | property |
| TST-REQ-003 | requested predicates + support exact version/claim/binding | ProgramRequirements request/claim exact predicate-key set 与 implication 可重算；missing/extra/variant-substituted predicate/request、wrong candidate/build/profile/claim/ref digest、development/stale/revoked binding 全部 fail closed | negative/security |
| TST-REG-002 | duplicate/unknown target | stable registry errors | unit |
| TST-MAT-001 | associated Plan/IR | 不可擦除、invariants enforced | compile/unit |
| TST-OUT-001 | manifest/hash/support decisions/file closure/partial failure | candidate/decisionsDigest/binding 与 retained content 可重算；source/semantic/provenance/plan/IR 只有 exact external evidence join 后可报 formal；unlisted/aliased file 拒绝；原子输出或无变化 | integration |
| TST-OUT-002 | repeatability/tamper/network identity | binding tamper、same network ID/different digest 稳定拒绝 | integration/security |
| TST-CLI-001 | CLI parse/help/resource override | stage/field parse、duplicate、zero/equal/over 与 stable usage error | unit/golden |
| TST-CLI-002 | check/build resource command surface | check 拒绝 tool/output stage；build receipt 保留 effective override | integration |
| TST-EVM-005 | Counter on Anvil | reference trace 相同 | local_runtime |
| TST-SOL-005 | Counter on Solana local runtime | reference trace 相同 | local_runtime |
| TST-NEAR-005 | Counter on sandbox | reference trace 相同 | local_runtime |
| TST-NOIR-005 | Counter witness/proof | prove+verify，state continuity explicit | proof |
| TST-NOIR-006 | PrivateSum4 | 两组同 public sum 的 witness 均 prove/verify；VK 相同、public vector exact、无 raw witness record、caller input 不变、所有 compiler temp 清理 | proof/security |
| TST-ZKSEC-001 | proof profile security contract/approval | exact profile/domain/allowlist/soundness/CRS/proof binding/privacy；wrong candidate/build/profile、development/stale/revoked approval 与 substitution 全部零输出拒绝 | proof/security/evidence |
| TST-XTARGET-001 | 一份 Counter 四 target | 四目标 normalized runtime/proof observation 均与 reference trace 一致，含 overflow rollback；四 OutputSet 均合法 | aggregate/differential |
| TST-XTARGET-003 | 一份 Accumulator 四 target + structural boundary | 非 Counter trace 等价；frontend/Core 无 TargetId branch，backend 无 program/name matcher | aggregate/differential/structural |
| TST-XTARGET-002 | unsupported/version/missing tool | 稳定错误，无 fallback | aggregate |
| TST-RESOURCE-001 | frontend safe-open/parser exact resource limits | equal 接受、over 对应稳定 code、无 escaped process/部分输出 | security/isolation |
| TST-RESOURCE-002 | compiler-core/tool/output exact resource limits | 逐 stage effective override；equal 接受、over 对应稳定 code、旧输出不变、receipt 完整 | security/isolation |
| TST-SBOM-002 | candidate-bound supply-chain closure + CycloneDX/release binding | 七种互斥 kind、全部 Tool Lock/Lake/compiler-runtime/license/standards leaf、logical/content identity、synthetic root、canonical/raw digest、三文件 sidecar 与 atomic no-clobber exact 重算；任一 substitution/extra/missing/race 零输出拒绝 | integration/security/reproducibility |
| TST-EVIDENCE-001 | development evidence/finalization | schema/bundle/catalog finalization 闭合，formal 请求 zero-output 拒绝 | evidence/security |
| TST-BOOTSTRAP-001 | pre-activation bootstrap foundation | eligible handoff、session containment、signed required-set/catalog authority、per-task receipts、six-item set 与 activation verifier 在无既有 activation 前置下 exact 闭合 | evidence/security/isolation |
| TST-EVIDENCE-002 | formal evidence/support binding | typed host/session/freshness/private-scan/revocation/finalizer refs、formal finalization 与 candidate/BuildIdentity/RequirementKey binding 全部 exact | evidence/security |
| TST-HOST-001 | Stage-0 host attestation | development observation；formal fail closed | security/isolation |
| TST-HOST-002 | Linux host profile 与 Stage-0 linux 分支 | 生成器/验证器正负例闭环、跨平台互相拒绝；darwin 回归不变 | security/isolation |
| TST-ISO-002 | 正式 hermetic archive harness | 外部 candidate anchor、eligible host、deny-default stages、process containment、gate-catalog EV 全部通过 | isolation |
| TST-ISO-003 | release-candidate clean-room aggregate | 所有 required Phase 1 gates 完整通过 | release/isolation |

## 完整 Test ID Catalog

以下 ID 均为 specified；表中“测试对象”是必须实现的最小断言，不表示已有 gate。

| ID | 测试对象 |
|---|---|
| TST-DOC-001 | frontmatter、状态、ID、链接、claim/ADR/trace 闭合 |
| TST-A0-001 | alpha 文档 schema/ID/status/JSON/link checker slice |
| TST-A0-002 | alpha 独立 Lake、DSL/Core/requirements/materializer slice |
| TST-A0-003 | alpha 四目标静态 artifact 与 EVM Counter runtime slice |
| TST-A0-004 | alpha archive isolation smoke（非正式 clean-room） |
| TST-A0-005 | alpha Lean parser 与 Source/Typed/Semantic 集成 slice |
| TST-A0-006 | alpha empty-HOME/cache network-denied clean-room slice |
| TST-A0-007 | alpha external tool content/Mach-O closure slice |
| TST-A0-008 | alpha Stage-0 development attestation/formal-ineligible slice |
| TST-A0-009 | alpha development evidence schema/bundle/publication core slice |
| TST-A0-010 | alpha deny-default runtime continuation slice |
| TST-A0-011 | alpha exact-local-port evidence compatibility slice |
| TST-A0-012 | alpha invocation context/receipt publication slice |
| TST-A0-013 | alpha generic UInt64 EVM Plan/Yul/runtime slice |
| TST-A0-014 | alpha generic UInt64 Solana Plan/IDL slice |
| TST-A0-015 | alpha generic UInt64 NEAR Plan/Wasm slice |
| TST-A0-016 | alpha generic UInt64 Noir Plan/relation/source slice |
| TST-A0-017 | alpha shared Syntax resource preflight slice |
| TST-A0-018 | alpha linear typed name-index slice |
| TST-A0-019 | alpha reusable Loader/session hosted-resource slice |
| TST-A0-020 | alpha single validated decoded frontend slice |
| TST-HOST-001 | 权威 `env -i` 入口、严格 bootstrap/JSON、live OS/Xcode/tool 匹配、development observation、formal ineligible 与环境/lock mutation negatives |
| TST-HOST-002 | linux profile 生成器/验证器正负例（digest/mode/nlink/root-owned/mutable/secureBoot 逐项）、linux↔darwin lock 与 profile 文件互相拒绝、v1→v2 迁移错误、观察缺失 fail closed；darwin TST-HOST-001 语义不变 |
| TST-ISO-001 | 独立 Lake/package/namespace 与父依赖边界 |
| TST-BOOTSTRAP-001 | activation 前的 eligible Stage-0 handoff、跨 process-session containment、signed RequiredTestSet/formal catalog authority、per-task verifier receipt/authenticated append-only service、six-item approval set 与 aggregate activation producer/consumer；测试不得读取或要求本次运行之前已存在的 activation |
| TST-ISO-002 | Stage-0 eligible host、外部 commit/tree/archive anchor、稳定 committed archive、前后 unchanged、空环境/cache；materialize/core deny-all-network；runtime exact-local-port + Anvil 127 bind/LAN refusal；stage read/write/exec negatives、closed FD/stdin EOF/output cap/timeout、formal session containment、0400 single-link receipts 与 gate-catalog-bound evidence |
| TST-ISO-003 | D8 release-candidate 全量 clean-room aggregate |
| TST-TOOL-001 | exact tool version/checksum、missing/shadow/timeout |
| TST-SBOM-001 | SPDX license inventory、CycloneDX 1.6 SBOM schema/closure/hash/release binding |
| TST-SBOM-002 | SBOM↔toolchains.lock closure 重算、release binding、per-executable/per-dylib 粒度与 TST-SBOM-001 全量语义收尾 |
| TST-COMMON-001 | 公共 primitive、canonical encoding、domain-separated hash 边界 |
| TST-RESOURCE-001 | frontend safe-open/parser resource profile equal/over/cleanup/receipt |
| TST-RESOURCE-002 | compiler-core/external-tool/artifact-output resource profile equal/over/cleanup/receipt |
| TST-SRC-001 | token/span/NodeId canonicalization |
| TST-SRC-002 | CLI byte cap 与 post-parser per-program Syntax/identity limits |
| TST-SRC-003 | program command 正负例 |
| TST-SRC-004 | declaration grammar/elaboration 正负例 |
| TST-SRC-005 | statement/expression grammar 正负例 |
| TST-SRC-006 | attribute export schema |
| TST-SRC-007 | import/identity ordering |
| TST-SRC-008 | multi-program selection |
| TST-DIAG-001 | diagnostic code/schema/order/redaction |
| TST-TYPE-001 | 类型 happy/boundary/error |
| TST-TYPE-002 | accepted-width name resolution/complexity |
| TST-TYPE-003 | Phase 1 declaration typing、local-fn resolution/effect/acyclicity、Bool invariant 与 proof-reference source binding |
| TST-PROOF-001 | immutable proof-bundle closure 与 post-canonical InvariantTheoremV1 signature |
| TST-EFFECT-001 | effect restrictions |
| TST-BOUND-001 | termination/resource bounds |
| TST-VIS-001 | explicit disclosure flow |
| TST-VIS-002 | implicit disclosure 与 authority/custody separation |
| TST-SEM-001 | canonical `.pfsem` serialization、semanticHash 与 separate `.pfprov` provenance digest |
| TST-SEM-002 | reference trace |
| TST-SEM-003 | revert/overflow rollback |
| TST-REQ-001 | requirement inference/origin |
| TST-REQ-002 | requirement merge/conflict |
| TST-REQ-003 | support exact match/rejection |
| TST-REG-001 | Target/Profile ID parsing |
| TST-REG-002 | registry duplicate/lookup/design-only rejection |
| TST-MAT-001 | associated Plan/IR、stage order、invariant mutation tests |
| TST-OUT-001 | manifest/atomicity |
| TST-OUT-002 | repeatability/tamper |
| TST-CLI-001 | CLI parse/help |
| TST-CLI-002 | CLI check/build |
| TST-CLI-003 | CLI inspect/list-targets |
| TST-CLI-004 | CLI prove/verify/deploy guard |
| TST-EVM-001 | EvmPlan schema/invariants |
| TST-EVM-002 | semantic → EvmPlan |
| TST-EVM-003 | EvmPlan → Yul/ABI |
| TST-EVM-004 | bytecode packaging/validation |
| TST-EVM-005 | Anvil runtime differential |
| TST-SOL-001 | SolanaPlan schema/invariants |
| TST-SOL-002 | semantic → SolanaPlan |
| TST-SOL-003 | Plan → sBPF/IDL |
| TST-SOL-004 | ELF packaging/validation |
| TST-SOL-005 | local runtime differential |
| TST-NEAR-001 | NearPlan schema/invariants |
| TST-NEAR-002 | semantic → NearPlan |
| TST-NEAR-003 | Plan → Wasm recipe |
| TST-NEAR-004 | deterministic Wasm validation |
| TST-NEAR-005 | sandbox differential |
| TST-NOIR-001 | NoirPlan schema/invariants |
| TST-NOIR-002 | semantic → NoirPlan |
| TST-NOIR-003 | Plan → source/ABI |
| TST-NOIR-004 | ACIR/witness/prove/verify pipeline |
| TST-NOIR-005 | Counter proof test |
| TST-NOIR-006 | PrivateSum4 privacy/proof test |
| TST-ZKSEC-001 | ZK backend security profile 与 candidate/build formal approval |
| TST-XTARGET-001 | 四目标 normalized reference-trace differential + OutputSet aggregate |
| TST-XTARGET-002 | unsupported/version/tool matrix |
| TST-XTARGET-003 | Accumulator 非模板化四目标差分 + target-neutral structural boundary |
| TST-SEC-001 | path/env/process/supply-chain/privacy attack matrix |
| TST-VER-001 | schema/profile compatibility matrix |
| TST-PERF-001 | cold full check/same-session warm full recheck/resource benchmark budgets |
| TST-BOUNDARY-001 | Lean import graph、symbol ownership、target cross-import |
| TST-EVIDENCE-001 | restricted PF JCS/schema、exact-local-port 条件 port、artifact-set domain hash、safe bundle read、atomic layout、development gate catalog/finalization 与 formal zero-output rejection |
| TST-EVIDENCE-002 | formal evidence-set finalization、freshness/private scan/revocation、candidate/BuildIdentity/RequirementKey acceptance/support binding producer/store |
| TST-REL-001 | install/upgrade/build/rollback drill |

### Phase 1 required-set 分母

完整 Test ID Catalog 是唯一测试分母：只有冻结的 `TST-A0-001..020` 二十项保留历史 development
evidence，永不计入正式分子或分母；其他所有 catalog ID 都是 `phase1_required=true`，任何额外的
`TST-A0-*` 形式直接拒绝，不能借三位数字形式静默逃出分母。
新增/删除/重命名 required ID 必须与 task、requirements matrix、gate catalog 同一变更提交，
docs-check 拒绝 catalog/matrix/task 的 unknown、orphan 或范围缩写。release coverage 定义为
`具有 current non-revoked passed EV 的 required ID 数 / required catalog ID 数`，必须等于 1；
不存在 skip/optional/人工豁免。

formal producer 不能直接把 caller 提供的 catalog 当作上述分母。它必须解析并验证
`RequiredTestSetV1`：record 绑定 accepted PHASE-5 exact content digest/reviewCommit、按本节规则从
完整 Catalog 提取的 ASCII 唯一升序 exact required IDs、candidate 外部 authority policy 和满足该
policy 的签名。formal GateCatalog 携带该 record 的 exact ContentRef；所有 gate 的 testIds flatten
后必须是 required IDs 的无重复 exact partition，formal finalization 再 exact join required-set、
catalog、gates、evidence 与 bootstrap approval/receipt。缺失、删减、额外、重复、document/ref/
signature substitution 或 caller omission 全部 fail closed；caller expected catalog digest 只检测
split-brain，不授予修改分母的权限。

完整 ID 分母仍不能授权弱/no-op gate policy；`FormalGateCatalogApprovalV1` 必须由 external policy
的 distinct-principal quorum 签名绑定 exact required-set 与 catalog identity。formal record gate IDs
与 catalog gates 必须 exact，每 gate testIds/task/build exact，evidenceRefs non-empty 且全局唯一；
非 D0 EV 必须 formal/passed，D0 EV 保持 development 但必须由对应 signed TaskApproval/receipt 覆盖，
全部 EV 还须 exact join candidate/catalog/gate/test/build 并通过 freshness/revocation/private scan。

### Source.ProgramV1 canonical wire 与 NodeId

`TST-SRC-001` 以 `SPEC-SOURCE-WIRE-001` 为唯一 oracle。golden corpus 必须覆盖每个
ProgramItem/Type/Statement/Expr/Place/Pattern constructor、空/单/多 array、`none/some`、Unicode NFC、
每个固定宽度整数边界和 ordered-field mutation；至少由 Lean production encoder 与一个不 import
ProofForge 的小型 reference encoder 分别生成 bytes/sourceHash，再逐 byte 对比固定 golden。仅比较
两个实现彼此相等而没有 checked-in bytes/hash 不算通过。
`QualifiedId`、proof theorem 与 program identity 的 minimum component count 必须各有 `min-1/min`
positive/negative vector，不能把 common `QualifiedName` 的一般 nonempty carrier 误当作 surface grammar。

NodeId vectors 必须证明相同 module/program/path 在文件绝对/项目相对路径、span、行列、注释和
分配/遍历容器顺序变化时不变，而任一 `parentTag/fieldTag/index` 或 qualified identity 改变时改变。
生产 SHA-256 不可替换；测试构建暴露只接受 canonical preimage、返回 16 bytes 的 injectable digest
stub，强制两个不同 preimage 得到同一 candidate ID，断言 `PF-SRC-NODEID-COLLISION`、无 attribute
registration、无 `Source.Program` export、无 CLI staging。相同 preimage 被第二次插入是 traversal
compiler bug，必须为 `PF-INTERNAL`/`duplicate-node-visit`，不能被当作合法 alias。release binary
不得带 digest injection surface。

### PerformanceProfileV1

`TST-PERF-001` 的唯一 Phase 1 reference class 为 Apple M3 Pro 12-core/18-GB、native arm64、
Darwin 26.4.1 build 25E253，AC power、Low Power Mode off、无 thermal pressure；host observation
不得包含 serial/UUID。benchmark receipt 绑定 candidate commit/tree、`toolchains.lock.json` digest、
host profile digest、fixture/source hash 与 benchmark harness digest；任一身份不符则结果 invalid，
不能与其他机器结果平均。

fixture 由版本化 generator 产生恰好 1000 个 SPEC-LANG-001 Syntax nodes，包含 state、pure fn、
entry/view、checked arithmetic 和 bounded control；canonical source hash 固定在 fixture manifest。
“cold full check”是预构建 compiler 的新 OS process、无先前 ProofForge session/cache，但不清 OS
page cache。“same-session warm full recheck”只复用已初始化的 immutable `ParserSession`/trusted
environment；它必须对修改后的完整 source 重新 parse、decode、type/effect/bound/disclosure check、
normalize 和 hash，不复用旧 `Source.Program`、Typed/Semantic result，也不宣称 incremental
compilation。baseline 后把一个 decimal literal 替换为同字节宽度但语义不同的 literal；计时样本
只有在 edited sourceHash/semanticHash 分别命中 fixture manifest 的 edited golden、且都不同于
baseline hash 时才有效，normalized reference observation 也必须命中 edited golden，防止 stale
result 通过性能门禁。

每种模式先 5 次不计入 warm-up，再连续 30 次测量；禁止 retry、删 outlier 或并行样本。p95 使用
nearest-rank，即排序后第 29 个值；timeout/crash/error/任一 golden mismatch 按 infinity。cold full
check p95 必须 ≤5000 ms，same-session warm full recheck p95 ≤1000 ms；同时记录 p50、max、
aggregate memory peak。采样批开始时 1-minute load average 必须 ≤3.00，否则整批 invalid 并重新
调度，不能挑选部分结果。TST-PERF-001 只有在上述 exact profile receipt 完整时才可 passed。

`TST-SEM-001` 必须分别验证 canonical `.pfsem` 业务语义 bytes/semanticHash 与 `.pfprov`
source-provenance bytes/semanticProvenanceDigest。只改变同一 `Source.Program` 的 source origin、文件
path 或 span 时，`.pfsem` bytes 和 semanticHash 必须 byte-identical，仅 `.pfprov` 与
semanticProvenanceDigest 改变；改变业务语义则 semanticHash 必须改变。consumer 不得把 provenance
字段重新混入 semanticHash，也不得丢弃当前 Source.Program→`.pfsem`→`.pfprov` 的 exact binding。

`TST-SEM-002/003` 只能使用 `SPEC-SEM-001` 的 `ReferenceV1` carriers。positive 覆盖有 initializer 的
false default state→init、无 initializer 的 true default state、entry/view、canonical context 与同步
external response returned/reverted；assert/declared revert、每个 standard revert code、invalid
invocation/response/Core、resource/unreachable/internal-invariant trap 分别命中唯一 OutcomeV1 constructor。negative 覆盖
wrong callable kind/arity/type、context missing/extra/duplicate/wrong type、同 key 不同 Core result type、
response missing/extra/duplicate/reordered occurrence，以及 noncanonical value bytes。reverted/trapped
必须逐 byte返回 pre-state 且无 committed effects；response precedence 还必须覆盖 matched reverted 后
trailing extra，以及程序自行 declared/standard revert 或 Core/resource trap 时仍有 unconsumed response，
两者都唯一得到 `.trapped(.invalidExternalResponse, pre)`。target adapter 结果必须在进程内与 structural
OutcomeV1 相等，不能只比较自由文本 status/error；在 exact tagged reference-outcome retained artifact
及 verifier 实现前，该断言不能升级为 formal persisted differential evidence。

### Phase 1 declaration typing 与 proof reference

`TST-TYPE-003` 的 positive typed fixture 必须在一个非 Counter program 中覆盖 struct、enum、const、
event、error、init、entry、view、forward-declared pure fn、invariant、requires 和 proof reference；
D1 的 `TST-SRC-004/005` 只断言 parser/Source AST，不得据此关闭本测试。

local-fn vectors 固定覆盖 exact arity/type/return、参数 left-to-right evaluation、Unit fallthrough、
forward call、checked-failure propagation 和两层 pure composition；negative 覆盖 unknown fn、
entry/view/init 当表达式、arity/type mismatch、non-Unit missing return、state/context read、
event/external/schedule/disclosure effect、direct recursion 和 indirect cycle。
`TST-TYPE-003` 的 proof-reference vectors 固定覆盖同名 invariant exact binding、unknown/duplicate
invariant、short-name alias 和 non-Bool predicate；该 stage 只产生 canonical theorem qualified name
与 invariant identity，不查找或装载 Lean declaration。

`TST-PROOF-001` 在 `TST-SEM-001` 已构造 canonical `SemanticProgramV1` 后运行。positive 必须 exact
join 当前 `Source.Program`、canonical `.pfsem`、对应 `.pfprov` 与重算的
semanticProvenanceDigest，再从 immutable proof bundle 装载 fully-qualified theorem，并与嵌入完整
closed SemanticProgram value 和 invariant ordinal 的 `InvariantTheoremV1` definitionally equal。
negative 至少覆盖 provenance digest/binding substitution、unknown theorem、
axiom/unsafe/partial/extern、未列入 bundle 或 closure 的 import、source/olean/toolchain/ABI/trust-policy、
`proof-forge.semantic-program.v1` schema 与 `pf.semantic.v1` domain substitution、digest mismatch、
同名但不同 SemanticProgram、不同 invariant ID、metavariable、bundle/path/symlink/
duplicate-key mutation；任一失败不得继续 requirement resolution 或 target materialization。不得在
untrusted program source 中 elaboration 任意 Lean term。
theorem expected-type mismatch 的 stable diagnostic 必须为 `PF-TYPE-001`。新增、删除或修改
`ProofDecl` 必须改变 checked-in source bytes/sourceHash，同时保持相同 business program 的
`.pfsem`/semanticHash 不变；只改变 validation result 不得再次改写任一 hash。

### Resource test ownership

`TST-RESOURCE-001` 只关闭 D1-08 的 source safe-open、frontend worker、parser/decode protocol 与
frontend stage limits；它不声称 compiler-core 已受控。`TST-RESOURCE-002` 由 D3-07 关闭
compiler-core、external-tool 与 artifact-output 三 stage 的 limits、whole-containment cleanup、旧输出
不变和 receipt。D8-03 必须在同一 release candidate 上重跑两者；aggregate rerun 不改变上述实现
责任边界。

### D0 package isolation acceptance

`TST-ISO-001` only closes `TASK-D0-02`'s package boundary; it does not replace
`TST-HOST-001` or `TST-ISO-002/003`. The positive fixture must build
`ProofForgeV2`, `proof_forge_next`, and `proof_forge_next_tests` from a committed
product archive extracted into a fresh directory without `.git` or `active/`, run
the test executable and `proof-forge-next --help`, and show that both executable
paths are owned by that extracted Lake workspace. The archive must carry the root
`lakefile.lean`, `lake-manifest.json`, `lean-toolchain`, `justfile`, and
`ProofForgeV2.lean`; package/library/executable identities are exactly
`proof-forge-next`, `ProofForgeV2`, and `proof-forge-next`.

The focused checker and its synthetic single-mutation corpus must reject missing
root markers, package/library/executable/root drift, manifest-name drift, local
parent dependencies (`require ..` or equivalent path dependency), legacy
`ProofForge.*`/`active` imports outside the archive, tracked symlink/submodule,
`active/` leakage, and an embedded checkout absolute path. It must not scan
ignored build output as product source. This is a development package-isolation
gate only; it does not claim eligible-host, locked tool closure, network denial,
formal clean-room evidence, or release readiness.

### D0-08 candidate-bound supply-chain acceptance

`TST-SBOM-002` 是 `TASK-D0-08` 的唯一 task-owned acceptance，必须先以独立 fixture/validator
提交 RED；现有 D0-05 `license-inventory.v1`、null-root BOM、asset-only closure 和
`sbom-digests.v1.json` 只能作为 legacy negative。测试 authority 是 SPEC-TOOL-001 与 ADR-0015；
production generator 的输出不能反向生成 expected golden。

Tool Lock 以 per-platform 文件计（ADR-0016）。2026-07-18 counts 盘点完成并固化（冻结包
`frozenCounts` 与本节一致；oracle 测试以这些值为常量，不得从 production output 推导）：

- 每平台 Tool Lock leaf refs（`enumerate_tool_lock_leaves` 五类口径）：darwin
  `toolchains.lock.json`（v2）= 20（6 asset、6 bundle-file、2 compiler-executable、
  5 tool-executable、1 tool-runtime-file）；linux `toolchains-linux-x86_64.lock.json`（v3）
  = 17（5 asset、5 bundle-file、2 compiler-executable、5 tool-executable、
  0 tool-runtime-file）；合计 37，每种 leaf ref 恰覆盖一次。
- compiler-runtime files（Lean compiler 可达 non-system runtime，由 pinned lean 归档重算）：
  darwin 5（`lib/lean/{libInit_shared,libLake_shared,libleanshared,libleanshared_1,libleanshared_2}.dylib`）、
  linux 5（同名 `.so`）；合计 10。
- logical components 合计 41：1 lean-package（file-set = 30 个 product library 源文件：
  `ProofForgeV2.lean` + `ProofForgeV2/**/*.lean`）、0 source-dependency（lake-manifest
  packages 为空）、11 download-asset（6+5）、4 compiler-executable、10 tool-executable、
  11 runtime dylib/file（darwin libcrypto 1 + compiler-runtime 10）、4 bundled
  license-text（`LICENSE`、`licenses/Apache-2.0.txt`、`licenses/GPL-3.0.txt`、
  `licenses/MIT.txt`）。candidate archive root 另为 1 个 synthetic BOM root，
  绝不兼任 inventory/source component。
- content identities 合计 37（32 lock/compiler-runtime distinct content digest + 4 license
  text + 1 package tree identity）；同 bytes 的 solc asset/bundle/tool-executable 共享 1 个
  content identity 但保留独立 component，libcrypto bundle/runtime 两 leaf join 同一 runtime
  component，linux `libleanshared_1/_2/libInit_shared.so` 三者共享 1 个 content identity。
- typed relationships 合计 146：`has-content` 41、`unpacks-to` 25（darwin 13、linux 12）、
  `loads` 27（darwin 14 含 wat2wasm→libcrypto、linux 13）、`licensed-under` 12
  （11 download-asset + 1 lean-package → license-text）、`bom-member` 41
  （synthetic root → 每个 logical component）。
- standards files 恰为 4，均已提交 `supply-chain/standards/` 并按 sha256 pin：
  `cyclonedx-bom-1.6.schema.json`（252625 bytes，`3e92dddb…` 源
  CycloneDX/specification@`55343ba1`）、`spdx-license-list-v3.27.0.json`（318777 bytes，
  `157789ba…` 源 spdx/license-list-data@v3.27.0）、`spdx-exceptions-v3.27.0.json`
  （37918 bytes，`650f4970…` 同源）、`spdx-license-expressions-v2.3.md`（11972 bytes，
  `2da19cea…` 源 spdx/spdx-spec@v2.3）。离线 validator 为每平台 lock 内的 jv v6.0.2
  ToolchainIdentity（darwin/linux 各一）。
- sidecar files 恰为 3：`supply-chain-closure.v1.json`、`bom.cdx.json`、
  `sbom-release-binding.v1.json`，0444、atomic no-clobber。

bytes 相同的 solc asset/executable 必须有不同 `componentDigest/bom-ref`，但共享 content
identity；libcrypto 的 bundle-file/tool-runtime-file refs 必须 join 到同一个 runtime logical
component。任何输入集合变化都必须先形成新的 freeze review 与 goldens。

happy path 必须由 checkout 外的 fixed candidate tuple
`(commit,treeObjectId,archiveDigest,archiveSize,digest)` 驱动，连续在两个 absolute root、空 HOME、
不同 locale/umask 下生成 byte-identical 的三文件 sidecar；synthetic metadata root hash 等于 candidate
archive raw SHA-256，closure/BOM/binding、CycloneDX schema identity 与 SPDX standards identity 的
domain/raw hashes 全部由独立 test oracle 重算。sidecar regular-file closure 恰为
`supply-chain-closure.v1.json,bom.cdx.json,sbom-release-binding.v1.json`，最终 mode 均为 `0444`。

每个 case 只允许一个 mutation，至少实现下表；“零输出”表示 destination 不存在，或预先存在的
destination tree byte-identical 且无残留 staging：

| Case | 单一 mutation / boundary | Expected |
|---|---|---|
| `SB2-001` | exact frozen inventory/lock/runtime/standards/license + external candidate；双 root 重复生成 | freeze 中每类 exact denominator、3 sidecars、bytes/digests/mode 全部相等 |
| `SB2-002` | Tool Lock 只改 whitespace/object-key layout，semantic payload 不变 | `ToolLockV2Digest` 不变；raw `toolchainLockSha256` 与 candidate/binding 相应改变 |
| `SB2-003` | 把 `proof-forge.toolchain-lock.v1` legacy digest 填入任一 typed lock field | `PF-SBOM-BIND`，零输出 |
| `SB2-004` | raw `toolchainLockSha256` 与 canonical `ToolLockV2Digest` 互换 | `PF-SBOM-BIND`，零输出 |
| `SB2-005` | old inventory schema/null-root BOM/digest-map 输入 release validator | `PF-SBOM-SCHEMA`，零输出；无 fallback |
| `SB2-006` | root/nested duplicate JSON key、unknown/missing field、Bool-as-integer、float/NaN 或 invalid UTF-8 | `PF-SBOM-JSON` 或 `PF-SBOM-SCHEMA`（按 SPEC-TOOL 错误族），零输出 |
| `SB2-007` | solc asset 与 executable 因相同 content SHA 被合并成一个 logical identity | `PF-SBOM-CLOSURE`；必须保留两个 bom-ref |
| `SB2-008` | libcrypto bundle/runtime refs 被拆成两个 owner，或只保留一条 ref | `PF-SBOM-CLOSURE` |
| `SB2-009` | 删除/增加/重复任一 asset/compiler/bundle/tool/runtime leaf mapping | `PF-SBOM-CLOSURE` |
| `SB2-010` | executable/runtime size 或 SHA 与 Tool Lock 漂移，或 tool ref join 到另一 bundle path | `PF-SBOM-CLOSURE` |
| `SB2-011` | compiler archive 可达 runtime file/owner/load edge 缺失、额外或 ambient dylib substitution | `PF-SBOM-CLOSURE` |
| `SB2-012` | root/Lake package/file-set member 缺失、额外 ambient `.lake/packages` 或 revision-only source | `PF-SBOM-CLOSURE` |
| `SB2-013` | content orphan、wrong content ref、file-set size/member/order 或 same-count member substitution | `PF-SBOM-CLOSURE` |
| `SB2-014` | component ID/order/kind/source/dependency duplicate、悬空、cycle、orphan 或 kind/source 不兼容 | `PF-SBOM-INVENTORY` |
| `SB2-015` | license file 缺失、placeholder/tamper、symlink/hardlink 或 expression leaf 无正文 | `PF-SBOM-LICENSE` 或 unsafe node 的 `PF-SBOM-IO` |
| `SB2-016` | SPDX grammar/list/exception file 或 revision substitution；malformed/unknown/case/order/noncanonical expression | `PF-SBOM-LICENSE` 或 identity substitution 的 `PF-SBOM-BIND` |
| `SB2-017` | policy allow/review/deny overlap、external exception 非 deny 子集、unknown/review/deny expression | `PF-SBOM-POLICY` |
| `SB2-018` | candidate commit/tree/archive/size/digest 任一错配或 archive marker 不符 | `PF-SBOM-BIND`，在解析 archive inventory 前失败 |
| `SB2-019` | synthetic root hash/ref 不等于 candidate、root 在 components 重复或 sidecar 写回 candidate archive | `PF-SBOM-BIND`；拒绝重复与自引用 |
| `SB2-020` | typed relationship missing/extra/self/cycle 或 same-count edge-kind substitution | `PF-SBOM-CLOSURE` |
| `SB2-021` | closure component/property、BOM bom-ref/hash/dependency/root 任一 missing/extra/substitution | `PF-SBOM-BIND` |
| `SB2-022` | CycloneDX schema file/commit/validator/version、license expression branch 或 offline validation mutation | `PF-SBOM-BIND`，零输出 |
| `SB2-023` | binding candidate/lock/policy/inventory/standards/closure/BOM/generator 任一 path/size/raw/typed digest/mediaType substitution | `PF-SBOM-BIND` |
| `SB2-024` | sidecar directory 含 extra/missing/partial file、symlink/hardlink/FIFO/device、traversal 或 casefold alias | `PF-SBOM-BIND` 或 `PF-SBOM-IO` |
| `SB2-025` | input truncate/grow/replace race、blocking FIFO，或 candidate/JSON/license/sidecar exact byte maximum + 1 | `PF-SBOM-IO`/`PF-SBOM-LIMIT`，timeout 内零输出 |
| `SB2-026` | destination parent symlink、wrong owner、group/world writable 或 path-component replacement | `PF-SBOM-IO`，旧 destination 不变 |
| `SB2-027` | destination 预存在或两个 writer 并发 | 一个 no-clobber winner；其余 `PF-OUTPUT-ATOMICITY`，winner/旧目录完整 |
| `SB2-028` | 每个 write/file-fsync/staging-dir-fsync/rename/parent-dir-fsync 点逐一 fault injection 与 signal | `PF-OUTPUT-ATOMICITY`；rename 前失败零输出且 staging 清零；parent fsync 失败只留下完整未确认 destination、不得报成功，`--verify-existing` 全量重算并确认 |
| `SB2-029` | cwd/HOME/TZ/locale/umask/job count/mtime 变化 | 三个 sidecar bytes、mode 与全部 structured identity 不变 |
| `SB2-030` | BOM 只通过 CycloneDX schema、但未重算 closure/component/standards identity | consumer 必须拒绝 `PF-SBOM-BIND` |
| `SB2-031` | component/content/edge/file-set/runtime/standards/aggregate-content/sidecar limits 各自在其他边界 non-binding 时测 equal/over；另降低 effective published limit | schema equal 通过、over=`PF-SBOM-LIMIT`；profile over=`PF-RESOURCE-OUTPUT`；均零输出 |

RED gate 至少应先让 `SB2-001/003/007/008/009/011/018/019/022/023/025/028` 因新 schema/API 尚不存在而
失败，并证明 legacy generator 不能误绿；GREEN 才扩到完整 31-case matrix。`TST-PROOF-001` 另增加
wrong ToolLock domain proof-bundle negative，`TST-REG-002` 另增加 wrong lockDigest 导致
ToolchainIdentity/profile/BuildIdentity cascade rejection；不能回填或改写已关闭的 D0-03
`TST-TOOL-001` evidence。

D0-08 positive 只证明 candidate-bound deterministic development binding，不证明 eligible host、formal
freshness/private scan/revocation/finalizer、OutputSet integration 或 release signature；它们分别仍由
`TASK-D0-07`、`TASK-D3-05` 与 `TASK-D8-05` 关闭。

### 文档控制面验收

`TST-DOC-001` 使用独立临时 synthetic corpus，不复制当前 `docs/`，并对每个 case 只引入一个
mutation。baseline、“pending task 无 EV”、合法 `REL-<SemVer>` 与保留完整 approval metadata 的
accepted→superseded 必须通过；以下 mutation 必须以稳定 `PF-DOC-*` 失败：required file 缺失
及同阶段首诊断排序、frontmatter 缺失/重复/非法字段、非法 lifecycle status、accepted 缺
approval metadata、`approvers` 非 exact `, ` 分隔 ASCII safe-id 唯一升序列表，或含
`TODO`/`TBD`/`待补充`/`待决定`/`待锁`、superseded 缺 successor/
形成环、accepted release 无 formal
evidence-set binder、document/embedded/registry ID 或 JSON key 重复/畸形、authoritative table 行
宽错误、inline/fenced code 或 HTML comment 被误作定义/证据/链接来源、非 UTF-8 Markdown、
corpus root/file/ancestor symlink、broken/escaping inline/reference/image local link、不存在的
fragment、unused reference definition 伪造 index reachability、typed definition 被同名 primary
document 冒充、unknown/empty CLM source、GOAL/FR/NFR orphan、trace 任一 ADR/INV、SPEC/MOD、TASK、
TST 轴缺失或引用未知、required test catalog 中任一精确 `TST-*` 未被任何 task 拥有或未出现在
requirements matrix、任一非精确两位数 A0 的 formal task 没有 requirement matrix edge、
每个 formal task 拥有的每个 TST 未与该 TASK 在至少同一条 requirement row 联合出现、task 或
matrix 引用未在 required test catalog 定义的 `TST-*`、task 或 matrix
以范围/通配符代替精确 test ID、matrix TST 不属于同一行 TASK、task dependency
unknown/cycle/未完成、
task header 非 canonical、Prerequisites 列缺失/引用未知、done task 缺 TST/EV、EV ID 非
`EV-YYYYMMDD-NNNN`、Evidence Ledger 列非 canonical、Task/Tests/Grade 非法或错绑、task 使用
不符合 exact A0/development、D0-01..06/bootstrap、其余/formal 规则的 EV、done task 的 EV 未覆盖其
全部 Tests、result 非精确 `passed`
语法、requirements matrix 的 Evidence 非精确 `specified`、同时两个
`in_progress` task。`docs/` 外的 `active/` 或任意其他归档 JSON 不属于 docs-check corpus，必须不
影响结果。

根 `AGENTS.md` 的唯一 rendered `## Current Checkpoint` section 和其中唯一 canonical table
也属于 `TST-DOC-001`。`Active task` 中的
task ID set 必须 exact 等于任务表全部 `in_progress` 项；`Next task` 必须是表序中 active 项之后首个
非 `done` task（没有 active 时从表首开始，没有剩余项时写“无”）；`Known blocker` 必须 exact
列出全部 `blocked` task。`Task authority` 与 `Document authority` 必须分别指向
`docs/04-task-breakdown.md` 与 `docs/document-status.md`；值为 inline link 时必须对 link target 做
exact 比较，禁止 substring/alias。缺/重复 section 或 table、表在 section 外、缺字段、重复字段、未知或
遗漏 task、状态漂移或 authority 漂移一律返回 `PF-DOC-CHECKPOINT`；AGENTS 只能镜像，不能产生
task 或改变调度顺序。

`TST-DOC-001` 下冻结一个 D0-10-owned named subprofile
`TST-DOC-001/task-qualification-v1`，不新增 Test ID。pending baseline（D0-10=pending，且无 freeze
package、qualification/bootstrap objects）是必须通过的正例；package/verifier/object/closeout cases
仅在 D0-10=`in_progress` 时激活。该 subprofile 覆盖 accepted ADR/spec/ruling 与 task-set lock/
PHASE-4/freeze/trace/checkpoint exact join、SPEC-TASKQUAL-001 全 wire/negative matrix、C→Q→D→R→P
closeout 和 one-time bootstrap。它不追溯修改或 reopen D0-01 的 frozen closure/evidence。

formal release denominator 仍只含一个 `TST-DOC-001`。gate/EV 的 subject 写
`taskId=TASK-D0-10` 与 `testIds=[TST-DOC-001]`，对应 `TaskCommandPolicyV1.id` 再 exact 绑定协议 ID
`tst-doc-001.task-qualification-v1`（human-facing subprofile 为
`TST-DOC-001/task-qualification-v1`）；不得给 raw EV schema 新增 `subprofile` 字段。Ledger `Tests`
仍只写 `TST-DOC-001`，禁止把 subprofile 当第二个 TST 或重复 denominator。正例只验证单任务 membership、
task-test partition、依赖、review/signature、Stage-0/containment/freshness/scan/revocation 连接；不得
把 subset 当 RequiredTestSet denominator，也不得关闭 `TST-ISO-003`。

该subprofile正例必须调用SPEC-TASKQUAL-001 §8两参数pure API，以closed role-keyed bundle覆盖四种
operation。steady-state使用synthetic D1 fixture；D0-10 fixture只覆盖one-time approval/receipt与fixture
D0-07 completion。fixture必须与production tuple静态不相交且永不被docs-check接受；production acceptance
另经policy-pinned protected adapter验证trusted time、safe-open archive/Git ancestry、authority store及live
FD/session provenance。pure成功本身不是task evidence或closeout。

`ADR-0021` C3 amendment不新增Test ID；它只扩展同一个`TST-DOC-001/task-qualification-v1` subprofile。该
subprofile必须逐项执行ADR-0021 §12的exact v1/v2 cross-rejection、seqpacket framing、lookup/terminal wire、
unsigned/signed acceptance equality、socket endpoint lineage、U/P/A namespace/credential/capability、static
service same-PID exec、seedRoot/FD custody、durable nonce/head transaction、failure injection与structural-only
root checker matrix。capability case必须在eligible Linux kernel真实执行，不得只搜源码常量：逐项证明
pre/post-exec五组exact `[CAP_SETPCAP,CAP_SYS_PTRACE]`、steady `B/I/A=[] P/E=[CAP_SYS_PTRACE]`及terminal
五组全零；supervisor pre-exec seed读取与service transition前禁止的post-exec seed-FD读取必须分别观测；
adapter须在credential drop前清空bounding set，adapter/service均须覆盖`setgroups→setresgid→setresuid`
顺序及real/effective/saved/fs UID/GID exact。旧
`[CAP_SYS_PTRACE]` checkpoint、ambient/inheritable/SETPCAP缺失或残留、额外bit、错误drop顺序、seccomp缺/宽
rule、setfsuid/setfsgid或任一filtered credential mutation、shared supplementary group、setuid/setgid executable、
`security.capability` xattr、transition crash与ambient不支持必须零签名且spend nonce，不得标skip/PASS或切换
file-capability/U-root/helper fallback。

raw artifact owner case必须对`proof-forge.task-qualification-artifact-payload.v1`的id/version/payload三段前像
逐项mutation，并独立mutation plain `payloadSha256`；覆盖SPEC-TASKQUAL-001 §8.2每个role→owner class与
§8.4 authority-store/adapter/parser/trusted-clock/supervisor identity三件套。正确payload+错误ref、正确ref+错误
plain hash、same bytes/different id、known schema放到错误role、unknown/fixture schema、typed owner
noncanonical/parse失败、三件套missing/extra/ref错配和trusted-clock三role缺失都必须在terminal前零签名拒绝；
既有alias negative matrix保持不变，D0 approval的三对`protected-consumer-*`↔`adapter-*`必须作为跨carrier
exact-equality正例并对每对错配做负例，不得把host raw digest owner推广成generic fallback。positive production case必须走七参数
positional-only API和完整v2 protected path；任何caller seed、fixture key、v1 fallback、generic signer、
partial signature或未accepted Freeze Exception均不得产生`production-candidate-bound`。这些case仍只计一个
`TST-DOC-001` denominator。ADR-0021 §11.2的`single-maintainer-owner-waiver`只替换流程复审人员，不允许删除、
skip、降级或伪造本段任一RED/GREEN、kernel、production、签名或closeout case。

Evidence Ledger 的 canonical columns 固定为
`ID | Task | Tests | Grade | Gate / command | Result | Scope and limitation`。`Grade` 只能是
`development`、`bootstrap` 或 `formal`。绑定任务的 EV 必须给出一个精确 `TASK-*` 与该任务拥有的非空
`TST-*` 子集；未绑定的历史观察只能同时使用 `Task=—`、`Tests=—`，且不得关闭任务。每个
`done` task 引用的所有 EV 必须绑定回该 task，Tests 的并集必须覆盖任务表中的全部 Tests；
只有冻结全集 `TASK-A0-01..20` 可使用 `development`；删除、增加或 reopen 其中任一项都必须拒绝。为打破 evidence binder
的 bootstrap 循环，只有精确的 `TASK-D0-01..06` 六项 D0 trust-root task 可使用
`bootstrap`，并继续受已完成依赖、accepted prerequisites、测试覆盖、eligible
Stage-0 直接 handoff 与独立评审约束；其余 task 只能使用 `formal`。bootstrap task closure 还必须
验证 `SPEC-EVFINAL-001` 的 external authority policy、该 task 的 exact signed TaskApproval 与
authenticated `BootstrapTaskVerifierReceiptV1`，并 exact join candidate、accepted PHASE-4 row、signed
RequiredTestSet、owned TST/EV、prerequisite documents、handoff、review refs 和所有 dependency 的
既有 authenticated completion refs。TaskApproval/receipt 必须绑定同一 required-set，task owned TST
必须全部是其成员；每个 dependency receipt 的 candidate/policy/required-set 必须与当前 approval
exact，因此 candidate 变化后必须按 DAG 重验依赖。D0-01/02/03/05/06 只要求各自 task receipt；D0-04 先取得自己的 task receipt，再按
D0-01..06 exact 顺序聚合六项 current-candidate approval+task receipt，并额外要求 signed
BootstrapApprovalSet activation receipt。固定顺序是 `D0-04 approval → D0-04 task receipt → six-item
set → activation receipt`，aggregate 不能成为前五项 done 的前置。

synthetic ledger-only bootstrap fixture 必须是 negative，不能再作为 successful closure。quorum/role/
review independence 按 distinct principalId 而非 keyId 计算；TaskApproval/set 都签入各自本次 exact
handoff，所以每次 task completion/aggregate activation 都需在线 quorum，旧 run approval 不得复用。
task/activation receipt 必须由 policy-pinned key 签名，并只能通过 external policy/handoff 共同绑定的
预开 authenticated authority-store RPC 进行 signed publish ack + exact readback，按各自包含
requiredTestSet 的 exact tuple 唯一、non-revoked lookup。D0-01 的 pure object consumer 即使通过
synthetic signed vectors，也只证明对象内容闭合；它不证明实际 Stage-0/fd/RPC provenance。当前
producer/policy root/handoff/signer/verifier/protected service 与 production capability adapter 未实现，
因此除下列 **freeze exception** 外，任何 `Grade=bootstrap` 行或 D0 `done` 转换仍必须以
`PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED` 拒绝；`passed` 文本本身不充分。
- **`FX-2026-07-17-D0-01`**：`TASK-D0-01` 在存在精确
  `docs/governance/bootstrap-closure/TASK-D0-01.attest.json`（kind=`pure-consumer-closure`、
  `freezeException=FX-2026-07-17-D0-01`、`protectedIntegration=deferred-fail-closed-to-D0-04`、
  `selfTestResult=ok`）时，以 pure-consumer bootstrap EV 关闭。
- **`FX-2026-07-17-D0-02`**：`TASK-D0-02` 在存在精确
  `docs/governance/bootstrap-closure/TASK-D0-02.attest.json`（kind=`package-boundary-closure`、
  `freezeException=FX-2026-07-17-D0-02`、`bootstrapAuthority=deferred-fail-closed-to-D0-04`、
  `selfTestResult=ok`、`isolationResult=ok`）时，以 package-boundary bootstrap EV 关闭。
- **`FX-2026-07-17-D0-03`**：`TASK-D0-03` 在存在精确
  `docs/governance/bootstrap-closure/TASK-D0-03.attest.json`（kind=`development-triad-closure`、
  `freezeException=FX-2026-07-17-D0-03`、`bootstrapAuthority=deferred-fail-closed-to-D0-04`、
  `fullPolicyReceiptEvaluator=implemented`、evidence/host/toolchain results `ok`）时，
  以 development triad bootstrap EV 关闭。
- **`FX-2026-07-17-D0-05`**：`TASK-D0-05` 在存在精确
  `docs/governance/bootstrap-closure/TASK-D0-05.attest.json`（kind=`sbom-inventory-closure`、
  `freezeException=FX-2026-07-17-D0-05`、self/generate/verify results `ok`）时，
  以 SBOM inventory bootstrap EV 关闭。
上述例外均不得推广到 `TASK-D0-04`/`TASK-D0-06` 的 formal/bootstrap 关单，也不得把 protected production
positive 或 formal hermetic 证据宣称为已闭合。`formal` 还必须由正式
evidence-set binder 校验对应不可变 EV JSON；ledger 中的文字标签不能自行把 development
观察升级为 formal evidence；在 `TASK-D0-07` 的 formal finalizer/binder 落地并接入 docs-check 前，任何
`Grade=formal` 行都必须以 `PF-DOC-EVIDENCE-FORMAL-UNVERIFIED` 拒绝。requirements matrix
在当前尚未闭合的阶段，Evidence 单元格只
允许精确 `specified`，不得以 `passed`、`closed` 或自由文本替代正式 EV 绑定。

`TST-DOC-001` 对 D0-01 consumer 先固定两层互不替代的验收：第一层直接调用 pure object API，
synthetic positive 只能得到 exact `ObjectVerifiedV1` projection，并逐项 mutation subject/object-set 的
missing/extra/duplicate/order、policy/required-set/handoff/approval/receipt/dependency/document/review/
evidence 的 schema、canonical bytes、domain digest、签名、quorum、role 和 exact joins。

PHASE-4 下一切片必须先分别正向到达 public `parse_phase4_snapshot_content` 与 graph raw-document
join。snapshot matrix 必须覆盖 exact typed record/subclass、id/path、`0/1/4194304/4194305` bytes、
BOM/NUL/CR/non-UTF-8/no-final-LF、raw line `100000/100001` 与 line width `65536/65537`、frontmatter
opening/closing delimiter、scalar、field-set、duplicate/unknown key、accepted metadata、approvers
delimiter/order/duplicate、两项 Gregorian date、reviewCommit/reviewLink/openFindings 与 PHASE-4
normative-document domain golden。raw scanner 必须覆盖 D0 heading 与 D1 boundary 的
missing/duplicate/reorder、位于 fenced code/HTML comment/inline decoy 的 exact reserved line、heading 到
header 或 table 到 D1 间插入 non-empty line、header/delimiter 的 missing/duplicate/substitution/reorder、
row missing/duplicate/reorder/extra/non-contiguous、extra cell、empty/overlong/control-code description、
embedded `|` 与非法 status。

七行 cell matrix 必须覆盖 exact `TASK-D0-01..07` source order、D0-07 仅验证不投影、Tests empty、
Dependencies/Prerequisites/Evidence 的合法 `—`、把 Tests 替换为 `—`、`, ` 以外 delimiter、leading/
trailing whitespace、backtick、empty token、duplicate/unsorted/malformed/range/wildcard ID、
prerequisite 缺/错 `@accepted`、dependency 指向表外 task、D0-01..06 指向 D0-07 与 cycle。positive 必须
断言 frozen `Phase4TaskRowV1` 六行 projection 的每个字段与完整 `NormativeDocumentRefV1`，不得只断言
count 或 digest。

graph matrix 必须从 raw PHASE-4 root row 自行派生 transitive closure，并覆盖 subject rows 的
missing/extra/reorder 及 dependencies/prerequisiteDocumentIds/testIds/evidenceIds 同 cardinality
substitution；selected raw row 的 empty evidence 必须拒绝。root 与每个 dependency approval 都要在
mutation 后使用有效重签对象，分别替换 taskBreakdown full ref 的 id/contentDigest/status/reviewCommit/
reviewLink/approvedAt/approvers，以及 testIds、dependency taskIds、EvidenceRef.id、prerequisite document
IDs，确保失败来自 raw exact join 而非 stale signature。PHASE-1/2/3 prerequisite snapshots 还须覆盖
exact type、canonical path、accepted frontmatter、raw domain digest 与 full-ref 同 cardinality
substitution；只比较 ID、digest、count、root approval、direct dependency 或 caller subject closure 的
弱实现必须被 mutation 杀死。D0-04 positive 仍须区分五个 transitive bundles 与 root row 的四个 direct
dependencies，D0-07 不得进入任何 subject/approval/bundle。

evidence-root 下一切片必须先补齐 per-task manifest 载体：root 与每个 dependency bundle 分别携带
exact canonical `BootstrapEvidenceRootManifestV1` bytes，其 taskId/candidate/EvidenceRef array 与同项
TaskApproval exact，domain digest 与该项 handoff `evidence-root.bindingDigest` exact。matrix 必须覆盖
root/每个 dependency 的 manifest missing/empty/noncanonical/schema/task/candidate/evidence/digest、跨 task
替换、same-count substitution，以及把全 closure union manifest 复用给单 task；所有 mutation 都须重签
受影响 approval、receipt 与下游 completion，避免 stale signature 假覆盖。

raw EV positive 必须使用完整 canonical `proof-forge.evidence.v1`，不得继续以 `{id}` fixture 代替。
同一个 pure schema core 必须同时被 gate-evidence CLI 与 bootstrap consumer 使用，并覆盖完整 root/nested
closed fields、canonical bytes、artifact-set digest 与全部 v1 cross-field invariants。bootstrap graph 还须
覆盖 raw SHA-256（无额外 domain）、ID、candidate commit/tree/archive、gate task/test、
`qualification="development"`、`result="passed"`、per-task test union，以及 carrier 对全部 manifest 与
approval EvidenceRef union 的 missing/extra/reorder/duplicate/same-count substitution。dependency EV 即使
不进入 root projection也必须完整验证。

evidence carrier count 固定覆盖 `1/24576/24577`，单项 bytes 覆盖
`0/1/4194304/4194305`，aggregate 覆盖 `268435456/268435457`；coarse/type/length/aggregate failure 在
entry decode、artifact-set/raw-ref hash 与 curve 前拒绝。report intrinsic 必须先于 evidence intrinsic；
manifest/EV 任一 schema、semantic、digest 或 exact-set failure 时 RequiredSet、TaskApproval、receipt 的
curve/finalizer count 均为零。positive 最终返回 exact typed `ObjectVerifiedV1`：dependency receipts 按
taskId 升序，evidence 只投影 root approval refs；默认 docs checker 仍必须稳定 bootstrap-unverified。

dependency 对象还须覆盖 `0/5/6` bundle count、bundle 顺序/重复/错配，以及每项 run-specific handoff 被 root 或
其他 dependency handoff 替换、重签后 handoff ContentRef 或 `(runId, nonce)` 跨 task 复用；D0-04 positive 的 raw bundle exact set 是五个 transitive dependency，
但 root approval/receipt 的 `dependencyCompletions` exact set 只能是四个 direct dependency；object-set
carrier 还须覆盖 evidence `1/24576/24577` 与 review report `1/1536/1537` count，并在 over-bound entry
decode/hash/curve 前拒绝；review report 还须覆盖 exact typed carrier、opaque bytes、单项
`0/1/1048576/1048577`、aggregate `16777216/16777217`、domain digest、排序/重复和已验签 approval
review digest union 的 missing/extra exact join；union 还须有跨 task 共享同一 digest 且 carrier
只保留一项的 positive，missing/extra 须在全部 RequiredSet/TaskApproval 签名验证后且 receipt
签名验证前拒绝；还须覆盖同 cardinality 的 missing+extra substitution，防止仅比较 count。完整 graph
固定为 shell/count → intrinsic report digest → PHASE-4/PHASE-5/prerequisite raw parse + raw row/document
joins → RequiredSet → 全部 TaskApproval → union → receipt；PHASE-4 snapshot 在同一 invocation 只能解析
一次。report structural/aggregate failure 时任何 graph hash 与 curve 均为零；first/interior/last report
digest mismatch 只能依序触发截至 mismatch 项的 report-domain hash，其他 graph hash 与 curve 仍为零。
report intrinsic 通过后的任一 snapshot typing/resource/frontmatter/table/DAG、raw closure、same-cardinality
row 或 full-ref mismatch，必须在第一次 RequiredSet/TaskApproval curve work 前拒绝；此时允许已经完成的
report-domain 与 raw-document hash，但 RequiredSet、TaskApproval、receipt curve count 都必须 exact 为
零。验收必须 instrument internal preflight/finalize/hash/curve 顺序，禁止先调用已验签 public parser 再
事后 compare；raw parser/join positive 仍不得替代尚未闭合的 EV raw bytes、archive membership、stable
snapshot、reviewCommit ancestry 或 protected provenance。第二层调用
默认 docs checker，同一 bootstrap ledger/task fixture 必须稳定返回
`PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED`。CLI/env/path/普通 file fd 不得选择 authority，也不得新增
`check(root, capability)` 把 `ObjectVerifiedV1` 升级成 closure。synthetic object set 永不构成 successful
closure。

production capability 落地后的 positive matrix 必须证明：D0-01 可由自身 task receipt 独立关闭；D0-02
只有在同 candidate/policy/required-set 的 D0-01 authenticated completion ref 存在时关闭；D0-04 的
`TST-BOOTSTRAP-001` 不得读取或要求既有 aggregate activation，D0-04 仅有自身 task receipt 仍拒绝，
其 activation positive vector 必须使用与 production lookup tuple 不相交的 fixture namespace且永不
关闭当前 task；真实流程加入 exact six-item set 与 activation receipt 后才关闭。`TASK-D0-07` 只在该 current activation
存在后运行 `TST-ISO-002`/`TST-EVIDENCE-002`。该 future positive 不改变当前 bootstrap/formal
fail-closed baseline。

其中 D0-01 的 candidate-external protected invocation positive 是 `TASK-D0-01` 所属
`TST-DOC-001` 的最终 integration 分支，不归 `TASK-D0-04`，也不新增任务依赖；外部治理基础设施缺失时
该分支未通过，D0-01 必须保持 `in_progress`。`TST-BOOTSTRAP-001` 只验收 D0-04 的仓库内 foundation、
six-item set 与 activation producer/consumer。

校验顺序固定为 root/required → JSON/frontmatter → status/link/supersession → definition/reference →
claim source → requirement trace → task/evidence → checkpoint；同阶段按 repo-relative path/line/ID 排序。
诊断测试固定 exit=1、空 stdout、唯一一行 stderr、code、相对路径与 offending ID，不固定可读
detail 的完整英文句子；相同 mutation 重跑输出必须逐字一致且不得出现 traceback。

### Source Syntax resource preflight 首个验收切片

- `TST-SRC-002` unit：显式构造 root-inclusive linear Syntax 256/257 与 wide Syntax
  100000/100001，验证 `≤ limit` 接受、`> limit` 返回
  `CompileError.resourceBound` / `PF-BOUND-001`。type、parameter、expression、statement、item
  和 program 的公共 decoder 必须先使用同一 walker；identifier 与 qualified identity
  256 components 接受、257 拒绝。
- `TST-SRC-002` loader integration：真实 300-term addition、20000-state wide source 与
  namespace/qualified-name 256/257 边界必须稳定拒绝或接受；257 层瞬时 namespace 退回
  255 层后声明的完整 256-component identity 必须恢复并接受。Loader 的重复检查、program
  identity 和 namespace tracking 不得重新引入输入相关 O(n²) scan 或递归渲染超限 `Name`。
- 20000-state / >100000-node（第 100001 节点拒绝）loader integration 必须由 `dsl-negative` 的独立 Lean command 与
  CLI loader 子进程执行；不得在常驻 `proof-forge-next-tests` 进程内重复该向量。每条重资源
  路径仍必须执行且精确检查 `PF-BOUND-001`，进程拆分只用于释放 parser/environment 峰值内存，
  不得降低 node limit、state count 或验收路径。
- `just dsl-negative`：同一组生成的 namespace/deep/wide `.lean` 分别通过
  `lake env lean` command elaborator 和 `proof-forge-next build` CLI loader；两路超限都必须
  返回相同 `PF-BOUND-001` 文本，恰好 256-component identity 与 transient unwind 两路都通过。
  CLI-only 有效源码恰好 16 MiB 必须成功；16 MiB+1 必须在 parser 前以 `PF-SRC-INVALID`
  拒绝且不创建 output。
- 本切片不关闭 Lean parser fuzz/containment、module aggregate node policy、完整
  Diagnostic v1/NodeId/span、直接 `Source.Program` API bounds 或 `TST-BOUND-001`；后者仍专指
  D2-03 的循环/递归 termination checker。accepted-width `Source.Program` 进入
  `Typed.check` 的 duplicate/name lookup 已由 `TASK-A0-18` 线性索引化，并由
  `TST-TYPE-002` 回归保护；这不关闭完整 D2、Diagnostic v1、`TST-PERF-001` 或
  adversarial hash-collision worst-case 保证。

### Typed name index 首个验收切片

- `TST-TYPE-002` structural RED gate 从 `Typed.check` 沿当前 Typed module-owned definitions
  遍历 Lean 常量依赖：门禁列出的 `Array.contains/elem/find-family` 名称搜索可达时输出
  dependency path 并失败；同时要求 `HashMap.getThenInsertIfNew?`、`HashMap.get?`、
  `HashSet.containsThenInsert` 均可达，且 `NameIndex.resolveState` 在该依赖图中只有一个语法
  occurrence，并且该 occurrence 必须直接位于 `Typed.check` 的定义体。该门禁验证本 alpha
  checker 的具体结构契约，不把源码文本格式或机器
  wall-clock 当成 oracle，也不宣称可排除任意手写扫描、跨模块规避或形式化证明复杂度。
- 直接构造 `Source.Program` 的宽输入向量，不经过 Loader：至少 2048 个有序 state 和
  2048 个有序 parameter，并在 body 最后位置解析末尾 state/parameter。断言 state/param ID、
  typed 数组和 entry 顺序保持声明顺序；宽 scope 的 missing variable/explicit state 仍返回
  精确错误。
- duplicate/priority 向量固定源码顺序中第一个再次出现的名称，并覆盖 state duplicate 优先于
  entry/body、entry duplicate 优先于 initializer parameter、initializer parameter 优先于 entry
  parameter/body、assignment target 优先于 RHS、`checkedAdd` lhs 优先于 rhs。
- 同名 state/parameter 向量固定 `.variable` 的 parameter shadowing 与 `.state` 的显式 state
  resolution；未知但非空 synchronous callee 继续合法，防止索引优化改变业务语义。
- 本切片只关闭 alpha `Typed.check` 的 accepted-width 名称索引回归；不建立直接
  `Source.Program` 的新宽度上限，不关闭完整 D2 name/type checker、Diagnostic v1、
  `TST-PERF-001` 或 adversarial hash-collision worst-case 保证。

### 双前端单一 decode/validation 首个验收切片

- `TST-SRC-004/005` positive parity：fixtures 覆盖当前 alpha 的 state/init、`UInt64`/`Bool`、
  默认/public/private/commitment parameter、entry/view、literal/variable/checked-add、
  assign/return/synchronous-call；直接
  Lean command 生成的 attributed constant 与 `ParserSession` Loader 对同一源码得到的
  `Source.Program` 和 `sourceHash` 必须完全相等。
- negative parity：zero callable、duplicate state、duplicate entry、duplicate initializer
  parameter、duplicate entry parameter 和 duplicate initializer 均分别通过 `lake env lean` 与
  `proof-forge-next build` 执行；两路必须失败、首个 `PF-SRC-INVALID` 文本完全相同，Lean 不得
  生成 `.olean`，CLI 不得创建 output。
- 组合错误向量必须把两路首个完整诊断同时钉死为规范期望值，覆盖 decode 优先于 duplicate
  initializer、duplicate initializer 优先于 zero callable，并按
  [`language.md`](specs/language.md#双前端单一-decodevalidation-契约) 的现行完整优先级链固定每个相邻边界；不得只
  比较两个入口彼此相等。
- shared decoder 固定 validation/error priority 为 Syntax preflight → identity → decode/duplicate
  initializer → zero callable → duplicate state → duplicate entry → duplicate event → duplicate error →
  duplicate struct → duplicate enum → duplicate const → duplicate fn → duplicate callable → duplicate invariant →
  duplicate extension → duplicate proof → unknown proof invariant → initializer parameter →
  structs declaration-order field nonempty/duplicate → enums declaration-order variant nonempty/duplicate →
  events declaration-order parameter → errors declaration-order parameter → entries declaration-order parameter →
  fns declaration-order parameter/body nonempty。Loader 只保留 module-level validation；command elaborator 必须 quote
  decoded value，不能再从 raw Syntax 运行第二套 AST builder。
- primitive type spelling 按原始 token exact 校验；`«Bool»`、unknown type 与 qualified type 必须在
  Lean command/Loader 两路得到同一 `PF-SRC-INVALID: unsupported portable type` 且零输出。
  `Bool` 与 `commitment` 分别推导 `value.bool`、`disclosure.commitment`，不得把 commitment 混同为
  private witness；当前四个 target descriptor 在实现相应能力前必须由 support resolver pre-Plan
  fail closed。
- closed integer-width declaration carrier 覆盖 `UInt8/16/32/128/256` 与
  `Int8/16/32/64/128/256`；Lean command 与 Loader 必须保留 exact type/order 并生成相同 AST/sourceHash。
  `UInt7`、`UInt512`、`Int0`、`UInt064`、lowercase/bare/escaped/qualified 与额外第二 token spelling
  必须双入口返回 exact `PF-SRC-INVALID: unsupported portable type` 且零输出。width/sign 必须分别绑定
  sourceHash；既有 `u64/bool/field` canonical tags `0/1/2` 保持 append-only，实际 UInt64 twin golden
  `89ce98102d576317548ab26a651ea04a09789f4d15704464434a239eb0865494` 不得改变。新增 widths 不推导
  requirement；当前四个 Phase 1 target 对无法保持的 non-UInt64 state 必须在 Plan 生成前 fail closed。
  width-aware literal bounds/typing、负数语义与 Int arithmetic 不属于本切片。
- Phase 1 field surface 只接受两个 raw identifier token 组成的 exact `Field bn254_fr`；escaped
  constructor、escaped/alternate/qualified/missing field identifier 与 unknown constructor 必须在
  Lean command/Loader 两路 fail closed。state、initializer parameter、entry parameter/result 与 view
  result 必须保持同一 `Source.ValueType.field` carrier、AST/sourceHash parity，并推导独立
  `value.field.bn254-fr` requirement；当前四个 target descriptor 在 materializer 能完整保持该语义前
  必须由 support resolver pre-Plan 拒绝。当前 nullary alpha carrier 只表示唯一 Phase 1 field，不能
  据此声称完整 `Source.ProgramV1 Type.Field.spec` 已实现。
- state declaration 覆盖 omitted/public/private/commitment 四种 visibility spelling；省略与显式
  public 必须生成相同 AST/sourceHash，private 与 commitment 必须生成彼此不同的 canonical binding。
  visibility 必须逐 state 经 Source→Typed→Semantic 保留；private/commitment state 分别推导
  `disclosure.private-state`/`disclosure.commitment-state`，不得因 Noir 已支持 private parameter 而
  误接 private state。当前四个 Phase 1 target 都必须在 Plan 前拒绝两项 state-specific requirement。
- event/error declaration 覆盖非空与空 parameter list，`error E` 与 `error E()` 必须生成相同
  AST/sourceHash；name、parameter 与同类 declaration order 必须进入 canonical source binding。
  duplicate event/error name 与 duplicate parameter 通过 Lean command/Loader 两路得到相同的
  exact `PF-SRC-INVALID`，parameter 错误按各自 declaration order 选择首错。Typed/Semantic 尚无
  对应 declaration table 时必须在 `Typed.check` fail closed，不能静默丢弃后进入 target Plan。
  `event`/`error` 不得污染宿主 Lean keyword 集；两者在 DSL identifier 位置的普通/escaped spelling
  必须双入口拒绝，宿主 Lean declaration 使用同名 identifier 的 positive control 必须继续通过。
- struct/enum declaration 覆盖 nonempty field/variant、bare nullary 与 nonempty typed payload variant；
  declaration、field/variant name、type/payload 与同类 order 必须进入 canonical source binding，
  `| V()` 必须拒绝。empty aggregate、duplicate declaration/field/variant、escaped contextual keyword
  与普通/escaped 保留名必须双入口 exact fail closed；`struct`/`enum` 不得污染宿主 Lean keyword
  集。Typed/Semantic 尚无 named-type table 时必须在 `Typed.check` fail closed，不能静默丢弃。
- const declaration 覆盖 exact name/type 与当前 alpha literal/variable/checked-add expression；
  declaration/type/value/count/order 必须进入 canonical source binding。duplicate const、unknown type、
  literal overflow、escaped contextual keyword 与普通/escaped 保留名必须双入口 exact fail closed；
  `const` 不得污染宿主 Lean keyword 集。D2 const type/name resolution 尚未实现时必须在
  `Typed.check` fail closed，不能静默丢弃或把未解析 expression 送入 target Plan。
- pure fn declaration 覆盖 exact name、parameter name/type/visibility/order、result 与当前 alpha
  statement/expression body；signature/body/count/order 必须进入 canonical source binding。duplicate fn、
  duplicate parameter、empty body、unknown result、literal overflow、escaped contextual keyword 与普通/escaped
  保留名必须双入口 exact fail closed；`fn` 不得污染宿主 Lean keyword 集。D2 local-call/type/effect/
  return/acyclicity 尚未实现时必须在 `Typed.check` fail closed，不能静默丢弃或进入 target Plan；
  本 alpha 已覆盖 explicit `Unit` result 与 optional return 的 parse-time `Unit` materialization，但不实现
  无值 `return`、`Unit` fallthrough 或 D2 return-path checking。`init`/`entry`/`view`
  block 回到引入列后紧随 `fn` 的三种合法 source order 必须同时通过 Lean command 与 ParserSession，
  后继 declaration 不得被前一 block parser 吞噬或拒绝。entry、view 与 fn 共用 callable 名称空间：
  entry/view 同名由更早的 duplicate entry slot 拒绝，entry/fn 与 view/fn 同名由 duplicate callable slot
  拒绝；duplicate entry 优先于 callable、duplicate fn 优先于 callable、callable 优先于 invariant 的首错
  必须由双入口 exact-diagnostic vectors 固定。
- `Unit` declaration carrier 覆盖 state、struct field、enum payload、const、initializer parameter 以及
  entry/view/fn parameter/result；只接受 exact unqualified single-token `Unit`。entry/view/fn 省略 result
  必须在 Source AST 构造前 materialize 为 `Unit`，并与显式 `: Unit` 产生相同 AST/sourceHash；`init`
  仍不接受 result。`Unit` 本身推导零 requirement；EVM、Solana、NEAR、Noir 的 support resolver 接受后，
  non-UInt64 state/result/parameter 必须由各自 target-owned Plan fail closed 且不产生 artifact。
  `Unit64`、escaped、qualified、extra-token spelling 必须双入口 exact fail closed；bare colon 必须停在
  parser boundary。
- `Principal` declaration carrier 覆盖与 `Unit` 相同的 declaration positions，只接受 exact unqualified
  single-token `Principal`，并由 Lean command/ParserSession parity 与 append-only canonical mutation 固定。
  declaration 本身推导零 requirement，尤其不得因为 type name 而隐式加入 `callerContext`；该 requirement
  只属于未来明确的 runtime context expression。四个 Phase 1 target 的 support resolver 接受后，
  non-UInt64 state/result/parameter 必须由各自 Plan fail closed 且不产生 artifact。`Principal64`、escaped、
  qualified 与 extra-token spelling 必须双入口 exact fail closed；本切片不定义 principal literal、
  `context.caller`、authority 或 D2 value semantics。
- D1-PA-18 的 alpha Option tests 只接受同一行 `Option PrimitiveAtom`，element 闭集为已实现的 exact
  single-token Bool/UInt/Int/Principal/Unit；Field、Named、nested Option、Array、Map、Bytes 与缺失/额外
  payload 均保持 fail closed。Source/Semantic 必须保留 `option(element)`，canonical bytes 固定为新
  tag `16` 后紧接 element type bytes，且既有 tags/goldens 不变。requirements 必须递归传播 element：
  `Option UInt64`/`Option Principal` 为零，`Option Bool` 必须保留 `boolValues`，不能被 Option wrapper
  擦除。测试覆盖 declaration positions、双前端 parity、element/tag mutation、same-line/后继 item guard、
  support-vs-Plan boundary；none/some expression、unwrap、nested runtime representation 与 D2 legality
  明确不在本切片。
- D1-PA-19 的 alpha Bytes tests 只接受同一行 canonical ASCII decimal `Bytes N`，边界精确为
  `0..4096`。positive 覆盖 `0`、中间值与 `4096` 的 declaration positions、Lean command/ParserSession
  parity、Source/Semantic `bytes(UInt32)` carrier、零 requirement 与四 target support-vs-Plan boundary。
  canonical goldens 必须同时固定 tag `17` 与 encoder-local length payload：Source 使用现有 8-byte
  big-endian `appendNat`，Semantic 使用现有 8-byte little-endian `appendNat`；tags `0..16` 和既有
  goldens 不变。bare/plural/escaped/qualified/identifier payload、`0x`、前导零、`4097` 必须在 decoder
  exact fail closed；负号、额外 token、跨行 payload 与 `Option Bytes N` 停在 parser boundary。测试不得
  引入 bytes literal、index/slice/length op、runtime representation、nested aggregate 或 D2 legality，
  也不得把 alpha hash helper 声称为 stable Type wire validator。
- D1-PA-54 的 alpha Array tests 只接受同一行 exact contextual
  `Array PrimitiveAtom N`，element 闭集为 exact single-token Bool/UInt/Int/Principal/Unit，长度使用
  `ArrayLength := Fin 4097` 且 lexical 边界精确为 canonical ASCII decimal `0..4096`。positive 覆盖
  `0`、普通值、`4096` 以及 state、struct field、enum payload、const、initializer/entry/view/fn
  parameter/result；Lean command/ParserSession 必须保留相同 Source AST/sourceHash。Source/Semantic
  canonical goldens 使用 append-only tag `18`、递归 element bytes 与 encoder-local `appendNat(length.val)`，
  并固定 element/length/tag mutation、byte size、hash non-alias 以及 tags `0..17` 旧 controls；RED 中新
  hash/size 显式未绑定，独立 probe 后单独提交 golden binding。
  `Array UInt64 4` 必须推导零 requirement，`Array Bool 0` 必须精确传播 `boolValues`；Phase 1 support
  resolver 之后，Array state/result/parameter 仍由既有 target Plan 以 non-UInt64 invariant 拒绝且不得产生
  artifact。unknown/Field element、缺失 element/length、`4097`、leading zero、hex 必须 exact fail closed；
  signed、underscore、额外/跨行 payload、nested Option/Bytes/Array/Map 必须停在 parser boundary，且既有
  `Option UInt64 Principal` failure class 不变。tests-only RED zero migration，只新增/注册
  `Tests.Language.ArrayTypes`；同时证明 `4096` 可由 carrier 表示、超界值由 `Fin 4097` 类型排除。
  本切片不得引入 named-ident type、array value/index/slice/length/mutation、runtime layout、ABI、recursive
  legality、D2 rules 或 target implementation。production 限 Source/SemanticIR/Syntax 三文件、最多 64 行
  新增与 6 行移除，并刷新 Lean package file-set。focused/aggregate/test binary 和 independent review 全绿
  后收口；PA53 batch `just ci` 已绿，本切片不重复完整 gate，不得声明数组运行语义或正式 D1 完成。
- D1-PA-55 的 alpha tests 只开放 exact same-line `Option Field bn254_fr`，并物化为既有
  `Source/Semantic.ValueType.option(.field)`；不得新增 ctor/tag 或放宽任意三 atom type parser。tests-only
  RED 只修改 `Tests.Language.OptionDeclarations`，把既有唯一 field-option parser-negative 迁移为 positive，
  migration count 精确为一。positive 覆盖 state、struct field、enum payload、const、initializer/entry/
  view/fn parameter/result 与 Lean command/ParserSession parity。Source/Semantic canonical goldens 必须固定
  tag `16` 后接 tag `2`，并与 bare Field、Option Bool、Option UInt64 做 byte-size/hash non-alias；新 golden
  在 RED 中显式未绑定，独立 probe 后单独提交。
  requirements 必须精确为单个 `fieldBn254`；四个 Phase 1 target 都必须在 support resolver 以该 named
  requirement 拒绝，且不得进入 Plan/产出 artifact。`Option Field`、alternate/escaped/qualified identifier、
  escaped/qualified constructor 必须 exact fail closed；extra/split payload 停在 parser boundary。Option
  Bytes、nested Option、Option Array/Map 与既有 `Option UInt64 Principal` failure class 保持不变。
  production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入
  none/some、unwrap、field literal/arithmetic、recursive legality、runtime/ABI 或 target Field support。
  focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复 `just ci`，不得声明
  Option/Field runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-56 的 alpha tests 只开放 exact same-line、exact one-level
  `Option Option PrimitiveAtom`，其中 inner element 闭集精确复用 D1-PA-18 的 15 个 single-token
  PrimitiveAtom（Bool、closed UInt/Int widths、Unit、Principal），并物化为既有
  `Source/Semantic.ValueType.option(.option element)`。不得新增 ctor/tag、递归 grammar 或放宽任意三 atom
  type parser。tests-only RED 只修改 `Tests.Language.OptionDeclarations`，把既有唯一
  `("nested option", "Option Option UInt64")` parser-negative 迁移为 positive，migration count 精确为一。
  positive 覆盖 nested Bool/UInt64 的 state、struct field、enum payload、const、initializer/entry/view/fn
  parameter/result 与 Lean command/ParserSession parity。Source/Semantic canonical goldens 必须固定
  tag `16→16→element`，并与 bare element、single Option 及不同 nested element 做 byte-size/hash non-alias；
  新 golden 在 RED 中显式未绑定，独立 probe 后单独提交。
  nested UInt64 必须推导零 requirement，nested Bool 必须精确传播单个 `boolValues`；四个 Phase 1 target
  对前者通过 support resolver 后仍由既有 non-UInt64 Plan invariant 拒绝，对后者必须在 support resolver
  以 named requirement 拒绝，且两者都不得产出 artifact。missing/unknown/Field/Bytes/Array/Map inner、
  escaped/qualified constructor 或 element 必须 exact fail closed；第三层 `Option Option Option Bool`、额外或
  split payload 必须保持 parser boundary。Option Bytes、Option Array/Map、Option Field 的既有边界不变。
  production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入
  none/some、unwrap、arbitrary recursive types、recursive legality、runtime/ABI 或 target nested-Option support。
  focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复 `just ci`，不得声明
  nested Option runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-57 的 alpha tests 只开放 exact same-line `Option Array PrimitiveAtom N`，其中 element 闭集精确
  复用 15 个 single-token PrimitiveAtom，长度 lexical/bound 精确复用 Array 的 canonical ASCII decimal
  `0..4096`，并物化为既有 `Source/Semantic.ValueType.option(.array element length)`。不得新增 ctor/tag、
  recursive grammar 或放宽通用 type parser。tests-only RED 只修改 `Tests.Language.OptionDeclarations`，
  把既有唯一 `("Array option", "Option Array UInt64 4")` parser-negative 迁移为 positive，migration count
  精确为一。positive 覆盖 `0`、普通值、`4096`、Bool/UInt64 以及 state、struct field、enum payload、const、
  initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。Source/Semantic canonical
  goldens 必须固定 tag `16→18→element→length`，并与 bare Array、single Option、nested Option 及不同
  element/length 做 byte-size/hash non-alias；新 golden 在 RED 中显式未绑定，独立 probe 后单独提交。
  `Option Array UInt64 N` 必须推导零 requirement，`Option Array Bool N` 必须精确传播单个 `boolValues`；
  四个 Phase 1 target 对前者通过 support resolver 后仍由既有 non-UInt64 Plan invariant 拒绝，对后者必须
  在 support resolver 以 named requirement 拒绝，且两者都不得产出 artifact。missing/unknown/Field/
  Option/Bytes/Array/Map element、invalid length、escaped/qualified constructor 或 element 必须 exact fail
  closed；extra/split payload 保持 parser boundary。Option Bytes、Array Option、Array Field、third-layer nested
  Option 与既有 extra-payload failure class 不变。
  production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入 array
  value/index/slice/mutation、none/some/unwrap、arbitrary recursive types、recursive legality、runtime/ABI 或
  target Option-Array support。focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复
  `just ci`，不得声明 Option/Array runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-58 的 alpha tests 只开放 exact same-line `Option Bytes N`，长度 lexical/bound 精确复用 Bytes 的
  canonical ASCII decimal `0..4096`，并物化为既有
  `Source/Semantic.ValueType.option(.bytes length)`。不得新增 ctor/tag、递归 grammar 或放宽通用 type
  parser。tests-only RED 只修改 `Tests.Language.OptionDeclarations` 与 `Tests.Language.BytesTypes`，
  把既有两条 `Option Bytes` parser-negative 迁移为 positive，migration count 精确为二。positive 覆盖
  `0`、普通值、`4096`、所有 declaration positions 与 Lean command/ParserSession parity。Source/Semantic
  canonical goldens 必须固定 tag `16→17→length`，并与 bare Bytes、single Option、Option Array 及不同
  length 做 byte-size/hash non-alias；新 golden 在 RED 中显式未绑定，独立 probe 后单独提交。
  `Option Bytes N` 必须推导零 requirement；四个 Phase 1 target 通过 support 后仍由既有 non-UInt64 Plan
  invariant 拒绝，且不得产出 artifact。missing/invalid length、escaped/qualified constructor、extra/split
  payload 必须 fail closed；Array Option、Array Field、third-layer nested Option、Option Map 与既有
  extra-payload failure class 保持原边界。
  production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入 bytes
  literal/index/slice/length、none/some、unwrap、arbitrary recursive types、recursive legality、runtime/ABI 或
  target Option-Bytes support。focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复
  `just ci`，不得声明 Option/Bytes runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-59 的 alpha tests 只开放 exact same-line `Array Option PrimitiveAtom N`，其中 element 闭集精确
  复用 15 个 single-token PrimitiveAtom，长度 lexical/bound 精确复用 Array 的 canonical ASCII decimal
  `0..4096`，并物化为既有
  `Source/Semantic.ValueType.array (.option element) length`。不得新增 ctor/tag、递归 grammar 或放宽通用
  `arrayType`/`portableType` parser。tests-only RED 只修改 `Tests.Language.ArrayTypes` 与
  `Tests.Language.OptionDeclarations`，把既有两条 `Array Option Bool 4` parser-negative 迁移为 positive，
  migration count 精确为二。positive 覆盖 `0`、普通值、`4096`、Bool/UInt64 以及 state、struct field、
  enum payload、const、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。
  Source/Semantic canonical goldens 必须固定 tag `18→16→element→length`，并与 bare Array、Option Array、
  bare Option 及不同 element/length 做 byte-size/hash non-alias；新 golden 在 RED 中显式未绑定，独立
  probe 后单独提交。`Array Option UInt64 N` 必须推导零 requirement，`Array Option Bool N` 必须精确传播
  单个 `boolValues`；四个 Phase 1 target 对前者通过 support resolver 后仍由既有 non-UInt64 Plan
  invariant 拒绝，对后者必须在 support resolver 以 named requirement 拒绝，且两者都不得产出 artifact。
  missing/unknown/Field/Bytes/Array/Option/Map element、invalid length、escaped/qualified constructor 或
  element 必须 exact fail closed；extra/split payload 保持 parser boundary。Array Field、Array Bytes、
  Option Array compound、third-layer nested Option、Map/Named 与既有 extra-payload failure class 保持原边界。
  production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入 array
  value/index/slice/mutation、none/some/unwrap、arbitrary recursive types、recursive legality、runtime/ABI 或
  target Array-Option support。focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复
  `just ci`，不得声明 Array/Option runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-60 的 alpha tests 只开放 exact same-line `Array Field bn254_fr N`，其中 Field id 必须是 raw
  exact `bn254_fr`，长度 lexical/bound 精确复用 Array 的 canonical ASCII decimal `0..4096`，并物化为
  既有 `Source/Semantic.ValueType.array .field length`。不得新增 ctor/tag、递归 grammar 或放宽通用
  `arrayType`/`portableType` parser。tests-only RED 只修改 `Tests.Language.ArrayTypes` 与
  `Tests.Language.OptionDeclarations`，把既有两条 `Array Field bn254_fr 4` parser-negative 迁移为
  positive，migration count 精确为二。positive 覆盖 `0`、普通值、`4096`、state、struct field、enum
  payload、const、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。
  Source/Semantic canonical goldens 必须固定 tag `18→2→length`，并与 bare Field、bare Array PrimitiveAtom、
  Option Field、Array Option 及不同 length 做 byte-size/hash non-alias；新 golden 在 RED 中显式未绑定，
  独立 probe 后单独提交。`Array Field bn254_fr N` 必须精确传播单个 `fieldBn254`；四个 Phase 1 target
  必须在 support resolver 以 named requirement 拒绝，且不得进入 Plan 或产出 artifact。missing/alternate/
  escaped/qualified Field id、invalid length、extra/split payload 必须 exact fail closed；Array Bytes、
  Array Option compound、Option Array compound、nested Option、Map/Named 与既有 extra-payload failure
  class 保持原边界。production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package
  file-set；不得引入 array value/index/slice/mutation、field arithmetic、none/some/unwrap、arbitrary recursive
  types、recursive legality、runtime/ABI 或 target Array-Field support。focused/aggregate/test binary 和
  independent review 全绿后收口；按冻结不重复 `just ci`，不得声明 Array/Field runtime semantics、完整
  type grammar 或正式 D1 完成。
- D1-PA-61 的 alpha tests 只开放 exact same-line `Array Bytes N M`，其中 `N` 是 inner Bytes length，
  `M` 是 outer Array length；两个长度都精确复用 Bytes/Array 的 canonical ASCII decimal `0..4096`
  discipline，`M` 物化为既有 `ArrayLength := Fin 4097`，整体物化为既有
  `Source/Semantic.ValueType.array (.bytes N) M`。不得新增 ctor/tag、递归 grammar 或放宽通用
  `arrayType`/`portableType` parser。tests-only RED 只修改 `Tests.Language.ArrayTypes`，把既有一条
  `Array Bytes 32 4` parser-negative 迁移为 positive，migration count 精确为一；`Array Bytes 4`
  继续保留为 unsupported bare Bytes-array negative。positive 覆盖 `(0,0)`、普通值、边界值、state、
  struct field、enum payload、const、initializer/entry/view/fn parameter/result 与 Lean command/
  ParserSession parity。Source/Semantic canonical goldens 必须固定 tag `18→17→N→M`，并与 bare Bytes、
  bare Array PrimitiveAtom、Option Bytes、Array Field 及不同 inner/outer length 做 byte-size/hash
  non-alias；新 golden 在 RED 中显式未绑定，独立 probe 后单独提交。`Array Bytes N M` 必须推导零
  requirement；四个 Phase 1 target 通过 support resolver 后仍由既有 non-UInt64 Plan invariant 拒绝，
  且不得产出 artifact。missing/invalid inner 或 outer length、escaped/qualified constructor 或 Bytes
  element、extra/split payload 必须 exact fail closed；Array Field、Array Option compound、Option Array
  compound、nested Option、Map/Named 与既有 extra-payload failure class 保持原边界。production 仅限
  Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得引入 bytes/array
  runtime representation、ABI、arbitrary recursive types、recursive legality 或 target Array-Bytes
  support。focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复 `just ci`，
  不得声明 Array/Bytes runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-62 的 alpha tests 只开放 exact same-line `Option Option Field bn254_fr`，并物化为既有
  `Source/Semantic.ValueType.option (.option .field)`。不得新增 ctor/tag、递归 grammar 或放宽既有
  `optionOptionType`/`portableType` parser；Field id 必须 raw exact `bn254_fr`。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，把既有一条 `Option Option Field bn254_fr` parser-negative 迁移为
  positive，migration count 精确为一；`Option Option Field` 继续保留为 unsupported incomplete negative。
  positive 覆盖 state、struct field、enum payload、const、initializer/entry/view/fn parameter/result 与
  Lean command/ParserSession parity。Source/Semantic canonical goldens 必须固定 tag `16→16→2`，并与
  bare Field、Option Field、Option Option PrimitiveAtom 及不同 element 做 byte-size/hash non-alias；新
  golden 在 RED 中显式未绑定，独立 probe 后单独提交。`Option Option Field bn254_fr` 必须精确传播
  单个 `fieldBn254`；四个 Phase 1 target 必须在 support resolver 以 named requirement 拒绝，且不得
  进入 Plan 或产出 artifact。missing/alternate/escaped/qualified Field id、escaped/qualified Option 或
  Field constructor、extra/split payload 必须 exact fail closed；Option Option Bytes、Option Option Array、
  third-layer Option、Option Array compounds、Array Option compounds、Array Array、Map/Named 与既有
  extra-payload failure class 保持原边界。production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并
  刷新 Lean package file-set；不得引入 none/some/unwrap、field arithmetic、arbitrary recursive types、
  recursive legality、runtime/ABI 或 target nested-Option-Field support。focused/aggregate/test binary 和
  independent review 全绿后收口；按冻结不重复 `just ci`，不得声明 nested Option/Field runtime semantics、
  完整 type grammar 或正式 D1 完成。
- D1-PA-63 的 alpha tests 只开放 exact same-line `Option Option Bytes N`，并物化为既有
  `Source/Semantic.ValueType.option (.option (.bytes length))`。长度 lexical/bound 精确复用 Bytes 的
  canonical ASCII decimal `0..4096` policy；本切片显式 supersede PA56/PA62 的临时 nested-Bytes
  rejection，但保持两层 Option wrapper 深度，third-layer Option 继续 deferred。不得新增 ctor/tag、递归
  grammar，或放宽 `optionOptionType`/`optionBytesType`/`portableType` parser。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，把既有一条 `Option Option Bytes 8` parser-negative 迁移为 positive，
  migration count 精确为一；incomplete `Option Option Bytes` 继续拒绝，其他测试不得迁移。
  positive 覆盖 length `0`、普通值、`4096`、state、struct field、enum payload、const、event/error parameter、
  initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。Source/Semantic canonical
  goldens 必须固定 tag `16→16→17→length`，并与 bare Bytes、Option Bytes、Option Option PrimitiveAtom、
  Option Option Field 及不同 length 做 byte-size/hash non-alias；新 golden 在 RED 中显式未绑定，独立 probe
  后单独提交。requirements 必须为空；四个 Phase 1 target 通过 support resolver 后，non-UInt64 state/
  result/parameter 必须由既有 Plan invariant 拒绝，且不得产出 artifact。missing/`4097`/leading-zero/hex/
  underscore/signed/identifier length、escaped/qualified Option 或 Bytes constructor、extra/split payload 必须
  exact fail closed；Option Option Array、third-layer Option、Map/Named 与既有 compound failure class 保持
  原边界。production 仅限 Syntax 一文件、最多 32 行新增/2 行移除，并刷新 Lean package file-set；不得
  引入 bytes runtime、none/some/unwrap、arbitrary recursive types、recursive legality、ABI 或 target
  nested-Option-Bytes support。focused/aggregate/test binary 和 independent review 全绿后收口；按冻结不重复
  `just ci`，不得声明 nested Option/Bytes runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-64 的 alpha tests 只开放 exact same-line `Option Option Array PrimitiveAtom N`，并物化为既有
  `Source/Semantic.ValueType.option (.option (.array element length))`。`PrimitiveAtom` 复用既有 15-atom
  Array policy，长度复用 canonical ASCII decimal `0..4096`；tag 固定 `16→16→18→element→length`，不得
  新增 ctor/tag、递归 grammar 或放宽 `optionOptionType`/`optionArrayType`/`arrayType`/`portableType`。
  tests-only RED 只修改 `Tests.Language.OptionDeclarations`，把既有一条 `Option Option Array UInt64 4`
  parser-negative 迁移为 positive，migration count 精确为一；incomplete `Option Option Array`、Field/
  Bytes/Option/Array/Map/Named elements、third-layer Option 与既有 compound failure class 保持拒绝。
  positive 覆盖 length `0`、普通值、`4096`、state/struct/enum/const/initializer/entry/view/fn/event/error
  positions 与 Lean command/ParserSession parity。canonical Source/Semantic goldens、requirements transitive
  propagation、四 Phase 1 target support 后的 non-UInt64 Plan rejection/no artifact、invalid length、escaped/
  qualified constructors/elements、extra/split payload 必须 exact fail closed。production 仅限 Syntax 一文件、
  最多 32 行新增/2 行移除并刷新 Lean package file-set；按冻结不重复 `just ci`，不得声明 nested Option/
  Array runtime semantics、完整 type grammar 或正式 D1 完成。
- D1-PA-65 的 alpha tests 只开放 exact same-line `Option Array Field bn254_fr N`，物化为既有
  `Source/Semantic.ValueType.option (.array .field length)`，tag 固定 `16→18→2→length`，长度复用
  canonical ASCII decimal `0..4096`，raw Field id 固定 `bn254_fr`。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条 full Field Option Array parser-negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 length `0`/普通值/`4096`、state/struct/enum/const/init/entry/
  view/fn/event/error positions 与 Lean command/ParserSession parity。requirements 必须恰为单个
  `fieldBn254`；四 Phase 1 target support 后 named rejection、state/result/param Plan boundary 与 no artifact
  均固定。missing/alternate/escaped/qualified Field id、invalid length、escaped/qualified Option/Array/Field
  constructors、extra/split payload 与 Option Array compounds 必须 exact fail closed。production 仅限 Syntax 一
  文件 ≤32 additions/2 removals，刷新 package file-set；按冻结不重复 `just ci`，不得声明 runtime semantics、
  完整 type grammar 或正式 D1 完成。
- D1-PA-66 的 alpha tests 只开放 exact same-line `Array Array PrimitiveAtom N M`，物化为既有
  `Source/Semantic.ValueType.array (.array element innerLength) outerLength`，tag 固定
  `18→18→element→N→M`，两个长度复用 canonical ASCII decimal `0..4096`。tests-only RED 只修改
  `Tests.Language.ArrayTypes`，将既有一条 `Array Array UInt64 4 4` parser-negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 inner/outer length `0`/普通值/`4096`、state/struct/enum/
  const/init/entry/view/fn/event/error positions 与 Lean command/ParserSession parity。requirements 必须
  精确透传 element requirements；四 Phase 1 target support 后 non-UInt64 Plan rejection、no artifact、
  canonical non-alias 与 invalid length (`01`/`0x10`/`4_096`/`4097`) controls 均固定。incomplete Array Array、
  Field/Bytes/Option/Array/Map/Named compounds、escaped/qualified constructors、extra/split payload 必须
  exact fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package file-set；按冻结
  不重复完整 `just ci`，不得声明 nested Array runtime semantics、完整 recursive type grammar 或正式 D1 完成。
- D1-PA-67 的 alpha tests 只开放 exact same-line `Option Array Option PrimitiveAtom N`，物化为既有
  `Source/Semantic.ValueType.option (.array (.option element) length)`，tag 固定
  `16→18→16→element→N`，长度复用 canonical ASCII decimal `0..4096`。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条 `Option Array Option Bool 4` negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 length `0`/普通值/`4096`、all declaration positions、双入口 parity、
  requirements、canonical non-alias、四 target support-vs-Plan/no-artifact。invalid length/element、
  third-layer Option、Option Array Bytes/Array、Map/Named、escaped/qualified/extra/split payload 必须 exact
  fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package file-set；按冻结不重复
  完整 `just ci`，不得声明 nested Option/Array runtime semantics、完整 recursive grammar 或正式 D1 完成。
- D1-PA-68 的 alpha tests 只开放 exact same-line `Option Array Bytes N M`，物化为既有
  `Source/Semantic.ValueType.option (.array (.bytes innerLength) outerLength)`，tag 固定
  `16→18→17→N→M`，两个长度均复用 canonical ASCII decimal `0..4096`。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条 `Option Array Bytes 8 4` negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 inner/outer length `0`/普通值/`4096`、all declaration positions、
  双入口 parity、zero requirements、canonical non-alias、四 target support-vs-Plan/no-artifact。invalid dual
  lengths、Option Array Array、Array Option compounds、third-layer Option、Map/Named、escaped/qualified/extra/
  split payload 必须 exact fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package
  file-set；按冻结不重复完整 `just ci`，不得声明 Option/Array/Bytes runtime semantics、完整 recursive grammar
  或正式 D1 完成。
- D1-PA-69 的 alpha tests 只开放 exact same-line `Option Array Array PrimitiveAtom N M`，物化为既有
  `Source/Semantic.ValueType.option (.array (.array element innerLength) outerLength)`，tag 固定
  `16→18→18→element→N→M`，两个长度均复用 canonical ASCII decimal `0..4096`。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条 `Option Array Array UInt64 4 4` negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 inner/outer length `0`/普通值/`4096`、all declaration positions、
  双入口 parity、UInt64/Bool requirements、canonical non-alias、四 target support-vs-Plan/no-artifact。invalid
  dual lengths、non-Primitive compounds、Array Option compounds、third-layer Option、Map/Named、escaped/qualified/
  extra/split payload 必须 exact fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新
  package file-set；按冻结不重复完整 `just ci`，不得声明 nested Array runtime semantics、完整 recursive grammar
  或正式 D1 完成。
- D1-PA-70 的 alpha tests 只开放 exact same-line `Option Option Option PrimitiveAtom`，物化为既有
  `Source/Semantic.ValueType.option (.option (.option element))`，tag 固定 `16→16→16→element`。本条只对
  exact 三层 Option + PrimitiveAtom 测试面显式 supersede 此前 “third-layer Option deferred/继续 fail closed/
  保持两层 Option wrapper 深度” 边界，不开放任意递归 Option grammar。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条 `Option Option Option Bool` negative 迁移为 positive，
  migration count 精确为一；positive 覆盖 15-atom closure 中 UInt64/Bool/Principal、all declaration positions、
  双入口 parity、UInt64/Bool requirements、depth/element canonical non-alias、四 target
  support-vs-Plan/no-artifact。Field/Bytes/Array/Option/Map/Named element、第四层 Option、escaped/qualified/
  extra/split payload 必须 exact fail closed。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新
  package file-set；按冻结不重复完整 `just ci`，不得声明 none/some/unwrap、runtime/ABI、target three-layer
  Option support、完整 recursive grammar 或正式 D1 完成。
- D1-PA-71 的 alpha tests 只开放 exact same-line `Array Option Option PrimitiveAtom N`，物化为既有
  `Source/Semantic.ValueType.array (.option (.option element)) length`，tag 固定
  `18→16→16→element→N`，长度复用 canonical ASCII decimal `0..4096`。本条只对 exact spelling 测试面
  supersede D1-PA-59 的 “Option element excluded/fail closed” 边界及 D1-PA-60/61/62/68/69 的 broad
  “Array Option compounds 继续 fail closed” residual，只开放第二层 Option 的 leaf 为 PrimitiveAtom 的这一
  形状；Array Option Bytes/Array、第三层 inner Option、Array Array non-Primitive、Map/Named 只保留既有
  negatives，不新增 PA71 migrations 或无关测试完成条件，也不开放任意递归 grammar。tests-only RED 只修改
  `Tests.Language.ArrayTypes`，将既有一条
  `("nested Array Option element", "Array Option Option Bool 4")` negative 迁移为 positive，migration count
  精确为一。positive 覆盖全部 15 个 PrimitiveAtom、length `0`/普通值/`4096`、all declaration positions 与
  Lean command/ParserSession parity。Source/Semantic canonical goldens 必须固定 UInt64 `0/4/4096`、Bool `0`、
  Principal `4096` 五组 vectors；candidate `Array Option Option UInt64 4` 必须分别与相同 payload 的
  `Array Option UInt64 4`、`Option Array Option UInt64 4`、`Option Option UInt64` non-alias，并固定五组
  candidates 内 UInt64 `0≠4≠4096`、UInt64 0≠Bool 0、UInt64 4096≠Principal 4096；RED 中新 goldens 显式
  未绑定，GREEN 前由独立 probe 计算。UInt64 requirements 必须为空，Bool 必须精确传播单个
  `boolValues`；四个 Phase 1 target 对 Bool 必须在 support resolver 以 named `boolValues` 拒绝且不得进入
  Plan；UInt64 surface 通过 support 后，state/result/parameter dedicated fixtures 必须在四 target 分别触发
  既有 `is not UInt64`/`does not return UInt64` Plan invariant，且所有路径均不得产出 artifact。
  missing/invalid length、Field/Bytes/Array/Option/Map/Named inner、escaped/qualified constructors 或 element、
  extra/split payload 必须 exact fail closed。production
  仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package file-set；focused 23-job、192-job aggregate/test
  binary、`just sbom` 与 independent review 全绿后收口。按冻结不重复完整 `just ci`；不得声明 array/option
  value operations、none/some/unwrap、runtime/ABI、target Array-nested-Option support、完整 recursive grammar
  或正式 D1 完成。
- D1-PA-72 的 alpha tests 只开放 exact same-line `Array Option Bytes N M`，物化为既有
  `Source/Semantic.ValueType.array (.option (.bytes innerLength)) outerLength`，tag 固定
  `18→16→17→N→M`，两长度均复用 canonical ASCII decimal `0..4096`。本条只对 exact spelling 测试面
  supersede D1-PA-59 的 Bytes-element exclusion、D1-PA-60/61/62/68/69 的 broad Array Option residual 与
  D1-PA-71 明示保留的 Array Option Bytes negative；Array Option Array、Array Array non-Primitive、第三层
  inner Option、Map/Named 只保持既有 negatives，不新增 PA72 migrations 或无关完成条件，也不开放任意
  recursive grammar。tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
  `("nested Bytes Array Option element", "Array Option Bytes 8 4")` negative 迁移为 positive，migration
  count 精确为一。positive 覆盖 dual lengths `0/0`、`8/4`、`4096/1`、all declaration positions（含
  event/error）与 Lean command/ParserSession parity。Source/Semantic canonical goldens 必须固定上述三组
  vectors；candidate `Array Option Bytes 8 4` 必须与相同 payload 的 `Array Bytes 8 4`、
  `Option Array Bytes 8 4` non-alias，并与 `Array Option UInt64 4`、`Option Bytes 8` 固定 leaf/wrapper 差异；
  三组 candidates 必须 pairwise non-alias；`8/4` 必须分别与 `0/4`（只改变 inner length）、`8/0`
  （只改变 outer length）non-alias，且 `8/4` 与 `4/8` 必须证明 dual-length order non-alias。RED 中
  新 goldens 显式未绑定，GREEN 前由独立 probe 计算。requirements 必须为空且四个 Phase 1 target support
  通过；state/result/parameter dedicated fixtures 必须在四 target 分别触发既有
  `is not UInt64`/`does not return UInt64` Plan invariant，所有路径均不得产出 artifact。
  missing inner/outer length、两长度各自 invalid lexical/bound forms、Field/Array/Option/Map/Named inner、
  escaped/qualified Array/Option/Bytes constructor、extra/split payload 必须 exact fail closed。production 仅限
  Syntax 一文件 ≤32 additions/2 removals，刷新 package file-set；focused 23-job、192-job aggregate/test
  binary、`just sbom` 与 independent review 全绿后收口。按冻结不重复完整 `just ci`；不得声明 bytes/array/
  option value operations、none/some/unwrap、runtime/ABI、target Array-Option-Bytes support、完整 recursive
  grammar 或正式 D1 完成。
- D1-PA-73 的 alpha tests 只开放 exact same-line `Option Option Option Field bn254_fr`，物化为既有
  `Source/Semantic.ValueType.option (.option (.option .field))`，tag 固定 `16→16→16→2`。本条只对
  exact 三层 Option + exact raw `bn254_fr` Field leaf 测试面 supersede D1-PA-62 的 third-layer Field
  deferred 与 D1-PA-70 的 Field-element fail-closed 项；PA55/PA62 的既有一层/两层 Field spelling 保持不变，Bytes/Array/Option/Map/Named leaf、
  第四层 Option 与任意 recursive grammar 仍不开放。tests-only RED 只修改
  `Tests.Language.OptionDeclarations`，将既有一条
  `("full Field Triple Option element", "Option Option Option Field bn254_fr")` negative 迁移为 positive，
  migration count 精确为一；incomplete `Option Option Option Field` 必须保留为 negative，其他测试不得迁移。
  positive 覆盖 state、struct field、enum payload、const、event/error parameter、initializer/entry/view/fn
  parameter/result 与 Lean command/ParserSession parity。Source/Semantic 各固定 exact 一个 golden vector；
  candidate 必须在两侧分别与 bare Field、`Option Field bn254_fr`、`Option Option Field bn254_fr`、
  `Option Option Option UInt64`、`Option Option Option Bool` 的 canonical bytes 与 hash non-alias；RED 中新
  golden 显式未绑定，GREEN 前由独立 probe 计算。requirements 必须精确为单个 `fieldBn254`；四个
  Phase 1 target 的 `Targets.checkSupport` 与 `Targets.materializeResult` 必须都返回 exact
  `.unsupportedRequirement .fieldBn254 actualTarget` 且 `actualTarget == target`，证明不能进入 Plan、
  `OutputSet` 或产出 artifact。
  error channel 经 GREEN 前 focused runtime probe 校正如下：incomplete/alternate/escaped/qualified Field id、
  第三个 Option constructor 的 escaped/qualified form及第三个 Option 后换行必须 exact
  `unsupported portable type`；extra payload、第一/第二个 Option 后或 Field/id 之间换行、第一/第二个
  Option constructor 任一位置与 Field constructor 的 escaped/qualified form 必须 parser-rejected。这项
  empirical channel correction 不改变 Output、Tests 集合、migration count 或 Done 语义。
  Bytes/Array/Option/Map/Named leaf 与第四层 Option 只保持既有 negatives，不新增 PA73
  migration 或无关完成条件。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package
  file-set；focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后收口。
  按冻结不重复完整 `just ci`；不得声明 none/some/unwrap、field value/arithmetic、runtime/ABI、target
  triple-Option-Field support、完整 recursive grammar 或正式 D1 完成。post-PA-72 bounded arbitration
  因本 spelling 只有单一 Field leaf/golden、无双长度与 15-atom matrix，选择它而非更大的
  `Array Option Array PrimitiveAtom N M`；该选择不是 checkpoint 自动递增。
- D1-PA-74 的 alpha tests 只开放 exact same-line `Option Option Option Bytes N`，物化为既有
  `Source/Semantic.ValueType.option (.option (.option (.bytes length)))`，tag 固定
  `16→16→16→17→N`，length 精确复用 canonical ASCII decimal `0..4096`。本条只对 exact spelling
  supersede PA63 的 third-layer deferred、PA70 的 Bytes leaf rejection 与 PA73 明示保留的 Bytes leaf；
  PA63 的两层 Option Bytes、PA73 的三层 Option Field 保持 positive，Array/Option/Map/Named leaf、第四层
  Option 与任意 recursive grammar 仍不开放。post-PA73 bounded arbitration 选择本单长度候选而非
  `Array Option Array PrimitiveAtom N M`，不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
  `("Bytes Triple Option element", "Option Option Option Bytes 8")` negative 迁移为 positive，migration
  count 精确为一；incomplete `Option Option Option Bytes` 必须继续 exact unsupported，其他测试不得迁移。
  positive 覆盖 length `0/8/4096`、state、struct field、enum payload、const、event/error parameter、
  initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。Source/Semantic 各固定三组
  golden vectors；`N=8` candidate 必须在两侧分别与 bare Bytes、`Option Bytes 8`、
  `Option Option Bytes 8`、`Option Option Option UInt64`、`Option Option Option Field bn254_fr` 的 canonical
  bytes/hash non-alias，三组 lengths 必须 pairwise non-alias；RED 中新 golden 显式未绑定，GREEN 前由
  独立 probe 计算。requirements 必须精确为空；四个 Phase 1 target 必须通过 `checkSupport`，state/result/
  parameter dedicated fixtures 随后必须在 `materializeResult` 分别触发既有 `is not UInt64`/
  `does not return UInt64` Plan invariant，且所有路径均不得产出 `OutputSet` 或 artifact。
  pre-freeze minimal parser probe 已固定 exact channels：incomplete、`4097`/leading-zero/hex/underscore length、
  full/bare Map 与 unknown leaf 为 `unsupported portable type`；negative/identifier length、extra payload、任一
  Option/Bytes-length seam 换行、三个 Option 或 Bytes constructor 的 escaped/qualified form、full Array leaf
  与第四层 Option 为 parser rejection。Field triple 保持 PA73 positive，只用于 non-alias。本切片不实现
  bytes operations、none/some/unwrap、runtime/ABI、target triple-Option-Bytes support、完整 recursive grammar
  或正式 D1 完成。production 仅限 Syntax 一文件 ≤32 additions/2 removals，刷新 package file-set；focused
  23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后收口。按冻结不重复完整
  `just ci`。
- D1-PA-75 的 alpha tests 只开放 exact same-line `Option Option Array Field bn254_fr N`，物化为既有
  `Source/Semantic.ValueType.option (.option (.array .field length))`，tag 固定 `16→16→18→2→N`，
  Field id 必须 raw exact `bn254_fr`，length 精确复用 canonical ASCII decimal `0..4096`。本条只对 exact
  spelling supersede PA64 nested Option Array 的 Field residual，并在 PA65 已完成的
  `Option Array Field bn254_fr N` spelling 外再包一层 Option；PA64/65/73/74 既有 positive 保持不变。
  post-PA-74 residual challenge 记录 expression 侧无安全 parser-only 候选，并选择本固定 Field + 单
  length 候选而非更大的 `Option Option Option Array PrimitiveAtom N`（15-atom + 混合 support/Plan）；
  不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有一条
  `("full Field nested Array element", "Option Option Array Field bn254_fr 4")` negative
  迁移为 positive，migration count 精确为一；incomplete `Option Option Array Field 4` 必须继续 exact
  unsupported，其他测试不得迁移。positive 覆盖 length `0/4/4096`、state、struct field、enum payload、
  const、event/error parameter、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession
  parity。Source/Semantic 各固定三组 golden vectors；`N=4` candidate 必须在两侧分别与
  `Option Array Field bn254_fr 4`、`Option Option Array UInt64 4`、`Option Option Field bn254_fr`、
  twin 构造的 `Array Option Option Field bn254_fr 4` 做 canonical bytes/hash non-alias，三组 lengths 必须
  pairwise non-alias；RED 中新 golden 显式未绑定，GREEN 前由独立 probe 计算。requirements 必须精确为
  单个 `fieldBn254`；四个 Phase 1 target 的 `checkSupport` 与 `materializeResult` 必须都返回 exact
  `.unsupportedRequirement .fieldBn254 actualTarget` 且 `actualTarget == target`，不得进入 Plan、
  `OutputSet` 或产出 artifact。
  empirical GREEN channels：incomplete、alternate/escaped/qualified Field id、`4097`/leading-zero/hex/
  underscore length、bare Bytes/Option/Array/Map、`Widget 4` Named/unknown leaf 为
  `unsupported portable type`；missing/negative/identifier length、extra payload、五个 same-line seam
  换行、四个 constructor 的 escaped/qualified form、full Bytes/Option/Array/Map compounds 为 parser
  rejection。不得用虚假 Named constructor 作为主 unsupported 路径。production 仅限 Syntax 一文件
  ≤30 additions/2 removals，刷新 package file-set；focused 23-job、192-job aggregate/test binary、
  `just sbom` 与 independent review 全绿后收口。按冻结不重复完整 `just ci`；不得声明 field/array/option
  value operations、none/some/unwrap、runtime/ABI、target nested-Option-Array-Field support、完整
  recursive grammar 或正式 D1 完成。
- D1-PA-76 的 alpha tests 只开放 exact same-line `Array Option Option Field bn254_fr N`，物化为既有
  `Source/Semantic.ValueType.array (.option (.option .field)) length`，tag 固定 `18→16→16→2→N`，
  Field id 必须 raw exact `bn254_fr`，length 精确复用 canonical ASCII decimal `0..4096`。本条只对
  PA71 明示保留的 exact Field leaf residual supersede fail-closed boundary；PA60/71/75 既有 positive
  保持不变。post-PA-75 四路 audit 按总验收面选择 fixed Field + single length：
  `Option Option Array Bytes N M` 需要 dual length 与三类 Plan fixture，
  `Option Option Option Array PrimitiveAtom N` 增加 element 轴与 zero/`boolValues` requirement/support
  分支；不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
  `("full Field Array Option Option element", "Array Option Option Field bn254_fr 4")` negative
  迁移为 positive，migration count 精确为一；incomplete `Array Option Option Field 4` 必须继续 exact
  unsupported，其他测试不得迁移。positive 覆盖 length `0/4/4096`、state、struct field、enum payload、
  const、event/error parameter、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession
  parity。Source/Semantic 各固定三组 golden vectors；`N=4` candidate 必须在两侧分别与
  `Array Option Field bn254_fr 4`、`Array Option Option UInt64 4`、
  `Option Option Array Field bn254_fr 4`、`Option Option Field bn254_fr` 做 canonical bytes/hash
  non-alias，三组 lengths 必须 pairwise non-alias；非 surface-positive control 只可手工构造。
  requirements 必须精确为单个 `fieldBn254`；四个 Phase 1 target 的 `checkSupport` 与
  `materializeResult` 必须都 exact named rejection、actual target identity 正确且无 Plan/OutputSet/artifact。
  frozen channels：incomplete、alternate/escaped/qualified Field id、`4097`/leading-zero/hex/underscore
  length、bare Bytes/Option/Array/Map、`Widget 4` 为 exact unsupported；missing/negative/identifier length、
  extra payload、五个 same-line seam、四个 constructor 的 escaped/qualified form、full Bytes/Option/Array/
  Map compounds为 parser rejection。empirical channel 不符时必须 GREEN 前先修规格，禁止改胖 positive。
  RED 仅 `ArrayTypes.lean` ≤320 additions/2 removals；production 仅 Syntax ≤30 additions/2 removals并刷新
  package file-set；focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent review 全绿后
  收口。按冻结不重复完整 `just ci`；不得声明 field/array/option value operations、none/some/unwrap、
  runtime/ABI、target Array-Option-Option-Field support、完整 recursive grammar 或正式 D1 完成。
- D1-PA-77 的 alpha tests 只开放 exact same-line `Array Array Field bn254_fr N M`，物化为既有
  `Source/Semantic.ValueType.array (.array .field innerLength) outerLength`，tag 固定
  `18→18→2→N→M`；Field id 必须 raw exact `bn254_fr`，两个 length 各自精确复用 canonical ASCII
  decimal `0..4096`。本条只对 PA66 明示保留的 exact Field leaf residual supersede fail-closed
  boundary；PA60/66/76 既有 positive 保持不变。post-PA-76 三路 audit 按总验收面选择 fixed Field +
  dual length：同轴 Bytes 候选还需要三类 Plan fixture，PrimitiveAtom 候选增加 element 与 requirement
  分支；不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.ArrayTypes`，将既有一条
  `("full Field Array Array element", "Array Array Field bn254_fr 4 4")` negative 迁移为 positive，
  migration count 精确为一；incomplete `Array Array Field 4 4` 必须继续 exact unsupported，其他测试
  不得迁移。positive 覆盖 `(0,0)/(4,4)/(4096,1)`、state、struct field、enum payload、const、event/error
  parameter、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。
  Source/Semantic 各固定三组 golden vectors；ordinary candidate 必须在两侧对 `Array Array UInt64 4 4`、
  `Array Field bn254_fr 4`、`Option Array Field bn254_fr 4` non-alias，并用手工 carrier 在 Source/Semantic
  两侧固定 `8/4` 对 `0/4`（inner-only）、`8/4` 对 `8/0`（outer-only）、`8/4` 对 `4/8`
  （swapped-order）non-alias。requirements 必须精确为单个 `fieldBn254`；四个 Phase 1 target
  的 `checkSupport` 与 `materializeResult` 必须都 exact named rejection、actual target identity 正确且无
  Plan/OutputSet/artifact。
  frozen channels：incomplete、alternate/escaped/qualified Field id、两个 length 各自的 `4097`/
  leading-zero/hex/underscore、bare Bytes/Option/Array/Map、`Widget 4 4` 为 exact unsupported；missing/
  negative/identifier inner/outer length、extra payload、五个 same-line seam、三个 constructor 的 escaped/
  qualified form、full Bytes/Option/Array/Map compounds为 parser rejection。empirical channel 不符时必须
  GREEN 前先修规格，禁止改胖 positive。RED 仅 `ArrayTypes.lean` ≤330 additions/2 removals；production
  仅 Syntax ≤36 additions/2 removals并刷新 package file-set；focused 23-job、192-job aggregate/test binary、
  `just sbom` 与 independent review 全绿后收口。按冻结不重复完整 `just ci`；不得声明 field/array
  operations、runtime/ABI、target nested-Array-Field support、完整 recursive grammar 或正式 D1 完成。
- D1-PA-78 的 alpha tests 只开放 exact same-line `Option Array Array Field bn254_fr N M`，物化为
  既有 `Source/Semantic.ValueType.option (.array (.array .field innerLength) outerLength)`，tag 固定
  `16→18→18→2→N→M`；Field id 必须 raw exact `bn254_fr`，两个 length 各自精确复用 canonical
  ASCII decimal `0..4096`。本条只 supersede PA69 明示保留的 exact Field leaf boundary；PA65/69/75/77
  既有 positive 保持不变。post-PA-77 bounded challenge 把 production delta 与完整 acceptance/target
  调用放入同一分母后选择 fixed Field + dual length：`Option Option Array Bytes N M` 虽有相近 helper，
  但 zero-requirement 路径还需 state/result/parameter 三类 Plan fixtures；不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
  `("full Field Option Array Array element", "Option Array Array Field bn254_fr 4 4")`
  negative 迁移为 positive，migration count 精确为一；RED 必须新增当前缺失的
  `Option Array Array Field 4 4` exact unsupported control，该新增不计作 migration，其他测试不得迁移。
  positive 覆盖 `(0,0)/(4,4)/(4096,1)`、state、struct field、enum payload、const、event/error
  parameter、initializer/entry/view/fn parameter/result 与 Lean command/ParserSession parity。
  Source/Semantic 各固定三组 deliberately UNBOUND golden vectors；ordinary candidate 必须在两侧对
  `Array Array Field bn254_fr 4 4`、`Option Array Field bn254_fr 4`、
  `Option Option Array Field bn254_fr 4`、`Option Array Array UInt64 4 4` non-alias，并用手工 carrier
  在 Source/Semantic 两侧固定 `8/4` 对 `0/4`（inner-only）、`8/4` 对 `8/0`（outer-only）、
  `8/4` 对 `4/8`（swapped-length-order）non-alias。requirements 必须精确为单个
  `fieldBn254`；四个 Phase 1 target 的 `checkSupport` 与 `materializeResult` 必须都 exact named
  rejection、actual target identity 正确且无 Plan/OutputSet/artifact。
  frozen channels：新增 incomplete、alternate/escaped/qualified Field id、两个 length 各自的 `4097`/
  leading-zero/hex/underscore、bare Bytes/Option/Array/Map、`Widget 4 4` 为 exact unsupported；missing
  outer/both lengths、negative/identifier inner/outer length、extra payload、六个 same-line seam、四个
  constructor 的 escaped/qualified form、full Bytes/Option/Array/Map compounds 为 parser rejection。
  empirical channel 不符时必须 GREEN 前先修规格，禁止改胖 positive。RED 仅
  `OptionDeclarations.lean` ≤330 additions/2 removals；production 仅 Syntax ≤32 additions/2 removals并
  刷新 package file-set；focused 23-job、192-job aggregate/test binary、`just sbom` 与 independent
  review 全绿后收口。按冻结不重复完整 `just ci`；不得声明 field/array/option operations、none/some/
  unwrap、runtime/ABI、target Option-nested-Array-Field support、完整 recursive grammar 或正式 D1 完成。
- D1-PA-79 的 alpha tests 只开放 exact same-line `Option Option Array Bytes N M`，物化为既有
  `Source/Semantic.ValueType.option (.option (.array (.bytes innerLength) outerLength))`，tag 固定
  `16→16→18→17→N→M`；两个 length 各自精确复用 canonical ASCII decimal `0..4096`。本条只 supersede
  nested Option Array Bytes residual；PA64/68/74/78 既有 positive 保持不变。post-PA-78 residual 在
  Field dual-length reject 关闭后选择 dual-length Bytes Plan-class residual：fixed Bytes leaf + dual
  length + zero requirements + state/result/parameter Plan fixtures；不是 checkpoint 自动递增。
  tests-only RED 只修改 `Tests.Language.OptionDeclarations`，将既有唯一
  `("nested Bytes nested Array element", "Option Option Array Bytes 8 4")` negative 迁移为 positive，
  migration count 精确为一；既有 incomplete bare `Option Option Array Bytes 4` 必须继续 exact
  unsupported，其他测试不得迁移。positive 覆盖 `(0,0)/(8,4)/(4096,1)`、state、struct field、enum
  payload、const、event/error parameter、initializer/entry/view/fn parameter/result 与 Lean
  command/ParserSession parity。Source/Semantic 各固定三组 deliberately UNBOUND golden vectors；
  ordinary candidate 必须在两侧对 `Option Option Array UInt64 4`、`Option Array Bytes 8 4`、
  `Option Option Bytes 8`、`Array Bytes 8 4` non-alias，并用手工 carrier 在 Source/Semantic 两侧固定
  `8/4` 对 `0/4`（inner-only）、`8/4` 对 `8/0`（outer-only）、`8/4` 对 `4/8`
  （swapped-length-order）non-alias。requirements 必须为空；四个 Phase 1 target 的 `checkSupport`
  必须全部通过；state/result/parameter 三类 fixture 的 `materializeResult` 必须 exact planInvariant
  （`is not UInt64` / `does not return UInt64` / `is not UInt64`）且无 Plan/OutputSet/artifact。
  frozen channels 经 GREEN 前 empirical probe 修正：incomplete bare、两个 length 各自的
  `4097`/leading-zero/hex/underscore，以及仅缺 outer length 的 `Option Option Array Bytes 8` 为
  exact unsupported；bare Field/Option/Array/Map、`Widget 8 4` dual-length leaf、missing both
  lengths、negative/identifier inner/outer length、
  extra payload、五个 same-line seam、四个 constructor 的 escaped/qualified form、full
  Field/Option/Array/Map compounds 为 parser rejection。该修正只校准既有负例的实际拒绝层，禁止
  迁移或改胖 positive。RED 仅 `OptionDeclarations.lean` ≤330 additions/2
  removals；production 仅 Syntax ≤32 additions/2 removals并刷新 package file-set；focused 23-job、
  192-job aggregate/test binary、`just sbom` 与 independent review 全绿后收口。按冻结不重复完整
  `just ci`；不得声明 bytes/array/option operations、none/some/unwrap、runtime/ABI、target
  nested-Option-Array-Bytes support、完整 recursive grammar 或正式 D1 完成。
- D1-PA-80 的 alpha tests 只开放 exact same-line `Array Option Option Bytes N M`，物化为既有
  `Source/Semantic.ValueType.array (.option (.option (.bytes innerLength))) outerLength`，tag 固定
  `18→16→16→17→N→M`；两个 length 各自精确复用 canonical ASCII decimal `0..4096`。该选择补齐
  PA71 PrimitiveAtom、PA76 Field 后 `Array→Option→Option` fixed-leaf 三元组的 Bytes 轴；不是
  checkpoint 自动递增，compound residual 继续 fail closed。tests-only RED 只修改
  `Tests.Language.ArrayTypes`，将既有唯一
  `("full Bytes Array Option Option element", "Array Option Option Bytes 8 4")` negative 迁移为 positive，
  migration count 精确为一；既有 incomplete `Array Option Option Bytes 4` 必须继续 exact
  unsupported，其他测试不得迁移。positive 覆盖 `(0,0)/(8,4)/(4096,1)`、state、struct field、enum
  payload、const、event/error parameter、initializer/entry/view/fn parameter/result 与 Lean
  command/ParserSession parity。Source/Semantic 各固定三组 deliberately UNBOUND golden vectors；
  ordinary candidate 必须在两侧对 `Array Option Bytes 8 4`、`Array Option Option UInt64 4`、
  `Array Option Option Field bn254_fr 4`、`Option Option Bytes 8`、`Array Bytes 8 4` non-alias，并用
  手工 carrier 固定 `8/4` 对 `0/4`、`8/0`、`4/8` non-alias。requirements 必须为空；四个 Phase 1
  target 的 `checkSupport` 必须全部通过；state/result/parameter 三类 fixture 的
  `materializeResult` 必须 exact planInvariant（`is not UInt64` / `does not return UInt64` /
  `is not UInt64`）且无 Plan/OutputSet/artifact。frozen channels：incomplete、两个 length 各自的
  `4097`/leading-zero/hex/underscore 与仅缺 outer length 为 exact unsupported；bare
  Field/Option/Array/Map、`Widget 8 4`、missing both、negative/identifier lengths、extra payload、五个
  seams、四个 constructor 的 escaped/qualified form、full compounds 为 parser rejection；empirical
  不符时 GREEN 前独立修规格。RED 仅 `ArrayTypes.lean` ≤320 additions/2 removals；production 仅
  Syntax ≤32 additions/2 removals并刷新 package file-set；focused 23-job、192-job aggregate/test
  binary、`just sbom` 与 independent review 全绿后收口。按冻结不重复完整 `just ci`；不得声明
  Bytes/Array/Option operations、none/some/unwrap、runtime/ABI、target support、完整 recursive grammar
  或正式 D1 完成。
- D1-PA-81 的 alpha tests 只关闭 `proof_forge_program` no-op 到 persistent environment export registry
  的结构缝隙。schema exact 为 `proof-forge.program-export.v1`；entry 只含 fully-qualified declaration
  `Name` 与 schema，不含 `Source.Program` payload。Shared/A/B diamond fixture 与 AB/BA 两个 import-order
  snapshot 必须产生相同的三项 UTF-8 FQN-sorted table，Shared 精确出现一次，未 attributed 的 manual
  `Source.Program` alias 精确缺席。raw entries 的 reversed order 必须 canonicalize 到同一 table；wrong
  schema、重复 structural Name 与同名冲突必须在返回任何 table 前以 `PF-EXPORT-001` 拒绝，禁止 set
  静默去重。attribute 本身必须无参数、global、local-only 且 attributed declaration type exact 为
  `Source.Program`。RED 仅新增 ProgramExport fixture/suite 与 Tests/lake 注册，总新增 ≤240 行；GREEN
  仅新增 `Language/ProgramExport.lean` ≤150 行、Syntax import/no-op removal ≤+3/-8 与 package file-set refresh。
  focused suite、aggregate test build/binary、`git diff --check`、单次 `just sbom`、independent review 全绿后
  只可记录 development evidence；不执行 payload constant evaluation，不覆盖 identity-level duplicate、
  NodeId/origin、`PF-EXPORT-002`、CLI/Loader selection、wire publication、target 或正式
  `TST-SRC-006/007` closure，按冻结不重复完整 `just ci`。
- D1-PA-82 的 alpha tests 只关闭 PA81 registry FQN 到 exported `Source.Program` 的无执行 structural
  reconstruction。`decodeQuotedProgramV1` 必须从 exact 14-field `Source.Program.mk` 开始，完整覆盖当前
  `quoteProgram` 可产生的 Source constructor surface、literal、`List.toArray` list spine、Option/Bool、
  UInt32/UInt64/Fin length wrapper，并在 host conversion 前验证 raw Nat range。它必须在任何 shape decode
  前以 test-owned explicit stack 固定 raw Expr nodes `100000` 通过/`100001`=`PF-EXPORT-004`，并固定
  logical Source recursion depth `256` 通过/`257`=`PF-EXPORT-004`；list spine 不计作业务递归 depth。
  `programPayload env name` 只接受 `programExports env` 中 exact registered Name；
  `programPayloads env` 必须 all-or-nothing 返回 sorted rows 与 reconstructed payload pair。
  declaration 仅可为 safe `defnInfo`、exact `Source.Program` type、无 `implemented_by`/extern、
  `Environment.hasUnsafe value = false`；unregistered、missing/opaque、constant alias、unsafe、可观察为
  non-direct value 的 partial alias 与 implemented-by direct sentinel replacement 必须在不跟随 replacement、无 FS/network/IO/ambient access 的情况下
  以 `PF-EXPORT-004` 拒绝，禁止 raw exception 或 partial table。positive rich fixture 必须用 BEq、
  qualifiedName 与 sourceHash 证明 reconstructed payload 等于 DSL elaborator constant；rich fixture 与
  test-owned exact direct quoted control 联合覆盖当前全部 ValueType/Expr/Statement/declaration constructor
  family。当前 DSL 把 bare state read 解码为 `Expr.variable`，因此 `Expr.state` 用 direct quoted control
  覆盖，禁止为测试反向扩大 DSL grammar。
  Lean 4.31 对非递归、direct-value `partial def` 不保留可由 `Environment`/closed `Expr` 观察的 modifier
  provenance；若其最终是 safe direct `Program.mk`，本切片按结构与普通 safe def 同等处理，不伪称拒绝
  不可观察的源码修饰符。需要 source-modifier provenance 时必须另行修改 registry schema，属于本切片外。
  RED 只新增 ProgramPayload fixtures/snapshot/suite 与 Tests/lake 注册，总新增 ≤360 行；GREEN 只新增
  `Language/ProgramPayload.lean` ≤520 行并刷新 package file-set。focused/aggregate/test binary、
  `git diff --check`、单次 `just sbom` 与 independent review 全绿后只可记录 development evidence；
  严禁 `evalConst`/`evalExpr`/whnf/simp/reduction/compiler/unsafe/IO 回退，不实现 payload identity duplicate、
  `PF-EXPORT-002/003`、CLI/Loader、wire、target、contained worker 或正式 `TST-SRC-006/007` closure，按冻结
  不重复完整 `just ci`。
- D1-PA-83 的 alpha tests 只关闭 PA82 `programPayloads` 全量重建成功后的 cross-row
  exported Source identity duplicate/split-brain seam。输入顺序继承 PA81 `programExports` 的 declaration
  FQN 排序；必须先解码全部 row，任一 payload 失败保留 `PF-EXPORT-004` 且不进入
  identity scan。scan 以 exact `Source.Program.qualifiedName : String` 为唯一主键，记录首个
  `qualifiedName → sourceHash`；后续同 qualifiedName 且 hash 相同固定拒绝为
  `PF-EXPORT-001: duplicate exported program identity`，同 qualifiedName 但 hash 不同固定拒绝为
  `PF-EXPORT-001: conflicting exported program identity`。首个 collision 按 PA81 row order 决定；不返回
  partial table。
  positive 必须用两个 distinct qualifiedName、相同业务 shape 的 attributed direct payload 证明 table
  通过、qualifiedName/hash 均不同且 declaration FQN order 不变；负例必须分别以两个不同
  declaration FQN 承载同 qualifiedName+同 payload 和同 qualifiedName+不同 payload，并以第三个
  invalid payload 固定 decode-before-identity error priority。因 alpha `sourceHash` canonical preimage 已包含
  qualifiedName，不构造“different qualifiedName + same hash”的伪负例，不将 SHA-256 碰撞 oracle
  塞入本切片。single-row `ProgramExportV1.declaration.toString` 与 payload qualifiedName 的渲染/绑定也
  属于后续独立 residual，本切片不静默加入。
  RED 只新增 ProgramIdentity fixtures/snapshot/suite 并修改 `Tests.lean`/`lakefile.lean` 注册，总新增
  ≤220 行。GREEN 只允许修改 `ProofForgeV2/Language/ProgramPayload.lean`，文件总行数不超过
  480，并刷新 `supply-chain/lean-package-files.v1.json`；不新增 public API。focused suite、
  aggregate test build/binary、`git diff --check`、单次 `just sbom` 与 independent review 全绿后只可记录
  development evidence；不实现 declaration/payload binding、`PF-EXPORT-002/003`、CLI/Loader、wire、
  target、contained worker 或正式 `TST-SRC-006/007` closure，按冻结不重复完整 `just ci`。
- D1-PA-84 的 alpha tests 只关闭 PA81 export declaration FQN 与 PA82 reconstructed
  `Source.Program.qualifiedName` 的 single-row exact binding。两者必须以
  `ProgramExportV1.declaration.toString == Source.Program.qualifiedName` 的 exact String equality 比较；
  不做 NFC/casefold/路径归一化。mismatch 固定为
  `PF-EXPORT-001: exported program identity does not match declaration`，不得归类为 payload form 的
  `PF-EXPORT-004`。
  `programPayload env name` 必须在 successful closed decode 后检查该 name 对应 row；
  `programPayloads env` 必须先完成全部 PA82 decode，任一 invalid row 保留 `PF-EXPORT-004`，再运行
  PA83 cross-row identity scan，最后按原 declaration FQN order 检查每个 row 的 binding。该顺序保留
  PA83 duplicate/conflict exact diagnostics 与攻击测试；只含一个 lying direct payload 的 table 才以本切片
  binding diagnostic 失败，且任何失败均不得返回 partial table。
  positive 必须覆盖 DSL elaborator 产生的 nested namespace 与 escaped identifier，并同时证明 single/table
  API 返回的 declaration rendering 与 payload qualifiedName 相等；hand-authored exact-aligned direct
  `Program.mk` 作为 control。negative 必须在 isolated module 中覆盖 single 与 table mismatch exact message；
  PA82-invalid direct/alias form 必须继续先得到 `PF-EXPORT-004`，既有 PA83 duplicate/conflict fixtures 必须
  保持原 exact message，证明新检查没有吞掉旧优先级。
  RED 只新增 ProgramBinding fixtures/suite 并修改 `Tests.lean`/`lakefile.lean` 注册，总新增 ≤220 行；
  GREEN 只允许修改 `ProofForgeV2/Language/ProgramPayload.lean`，不新增 public API，文件总行数不超过
  480，并刷新 `supply-chain/lean-package-files.v1.json`。focused suite、aggregate test build/binary、
  `git diff --check`、单次 `just sbom` 与 independent review 全绿后只可记录 development evidence；
  不实现 payload short-name/last-component、wire QualifiedName component binding、NodeId/origin、
  `PF-EXPORT-002/003`、CLI/Loader selection、target、contained worker 或正式 `TST-SRC-006/007` closure，
  按冻结不重复完整 `just ci`。`PF-EXPORT-003` 的零候选分类仍由 CLI/Loader selection rule 拥有，
  不改变低层 `programPayloads` 对 empty normalized registry 返回 empty table 的语义。
- D1-PA-85 的 alpha tests 只关闭 reconstructed `Source.Program.name` 与 export declaration 最后一个
  portable Lean identifier component 的 exact binding。对 `declaration = Name.str prefix rawComponent`，
  expected short name 必须是 `(Name.str .anonymous rawComponent).toString`；不得直接比较 raw component，
  不得对 full declaration string 使用 dot split/substring/`endsWith`。这样 simple name 保持原文，同时
  `program «hyphen-prog»` 与 `program «dot.prog»` 的 payload name 精确保留 Lean 4.31 guillemet rendering。
  final declaration 不是 `Name.str` 时也必须以同一个 short-name mismatch diagnostic fail closed。mismatch 固定为
  `PF-EXPORT-001: exported program short name does not match declaration`，不得归类为 `PF-EXPORT-004`。
  `programPayload` 的检查顺序固定为 registered → PA82 decode → PA84 FQN binding → short-name binding；
  `programPayloads` 固定为全部 PA82 decode → PA83 cross-row scan → 对每 row 先 PA84 FQN binding、再
  short-name binding。由此 invalid form 仍优先 `PF-EXPORT-004`，PA83 collision diagnostics 仍优先于
  binding，qname+short-name 同时 lying 时仍先返回 PA84 exact message，任何失败均不得返回 partial table。
  positive 必须同时覆盖 simple hand-aligned direct `Program.mk`、escaped program identifier with hyphen、
  escaped program identifier containing dot，并由 single/table API 固定 declaration component rendering 与
  payload name。negative 必须以 qname 已 exact 对齐、仅 name lying 的 isolated direct payload 分别覆盖
  single/table exact message；另一 fixture 固定 PA82-invalid later row 的 `PF-EXPORT-004` priority。既有
  PA83/PA84 suites 必须保持原 exact diagnostics，empty table 语义不变。
  RED 只新增 ProgramShortName fixtures/suite 与 `Tests.lean`/`lakefile.lean` 最小注册，总新增 ≤180 行；
  GREEN 只允许修改 `ProofForgeV2/Language/ProgramPayload.lean`，不新增 public API，文件总行数不超过
  480，并刷新 `supply-chain/lean-package-files.v1.json`。focused suite、PA83/PA84 regression、aggregate
  test build/binary、`git diff --check`、单次 `just sbom` 与 independent review 全绿后只可记录
  development evidence，按冻结不重复完整 `just ci`。
  本切片不实现 portable source-program wire 的 `moduleName`/`programIdentity` component carrier、
  NodeId/origin、schema-v2 migration、`PF-EXPORT-002/003`、CLI/Loader selection、target/worker 或正式
  `TST-SRC-006/007` closure。收口后 Lean attribute export/schema 代码路径的 pre-acceptance micro-seam
  视为饱和；下一步只能冻结正式 evidence packaging 或书面选择其他依赖合法任务，禁止继续发明 identity
  micro-check。
- D1-PA-86 只把已冻结的 `TASK-D1-05`/`TST-SRC-006/007` surface 收敛为单一 tests-only
  `Tests.Language.ProgramExportAcceptance` 可执行入口；它是现有行为的 characterization/golden
  packaging，不修改 production Lean，也不制造虚假的缺文件 RED。`TST-SRC-006` 必须固定 exact
  `proof-forge.program-export.v1`、unknown-schema/structural-duplicate/rendered-name-conflict 三条完整
  `PF-EXPORT-001` diagnostic、isolated empty environment 的 `programExports` 与 `programPayloads` 都为
  empty，以及 PA84/PA85 qualified-name/short-name exact mismatch。rendered-name conflict 必须由结构不同但
  `toString` 相同的 `Name.str .anonymous "foo.bar"` 与
  `Name.str .anonymous "«foo.bar»"` 构造，并先断言 non-BEq/same-rendering，禁止伪造同一 Name。
  `TST-SRC-007` 必须固定 Shared/A/B diamond 的 AB/BA exact 三行 schema/FQN table、Shared 精确一次且
  unattributed alias 缺席，cross-row duplicate/conflicting Source identity 的完整 diagnostic，以及
  `PF-EXPORT-004` decode-before-identity/binding、PA84 qualified-name-before-PA85 short-name 的优先级。
  empty-registry 观察必须位于只 import `ProgramPayload` 的独立 module，并在被污染的 aggregate module
  import 之前 snapshot；acceptance `run` 只消费该 snapshot 与既有 isolated fixture constants，不在合并了
  hostile fixtures 的 environment 上重新 query table。
  变更只允许新增 empty snapshot 与 acceptance suite，并在 `Tests.lean`/`lakefile.lean` 最小注册，总新增
  ≤150 行；既有 PA81–PA85 fixtures、production、package file-set、CLI/Loader、wire、target 与 worker
  均不得修改。验证只运行 focused suite、aggregate test build/binary、`just docs-check`、
  `git diff --check` 与 independent review；纯 tests/docs 切片不运行 `just sbom` 或完整 `just ci`。
  结果只可记录 development evidence，不能满足冻结包要求的 candidate-bound
  `qualification=formal`，不能关闭 pending `TASK-D1-05` 或开始 D1-06。
- D1-PA-87 只把已冻结的 `TASK-D1-03`/`TST-SRC-004` declaration surface 收敛为单一 tests-only
  `Tests.Language.DeclarationAcceptance.run` executable harness；它是对既有 declaration suites 的
  characterization packaging，不修改 production、既有 suite assertion，也不制造缺文件或删除实现的
  虚假 RED。wrapper 必须按当前 aggregate runner 的相对顺序各调用一次既有 `run`：
  `AggregateDeclarations`、`ArrayTypes`、`BytesTypes`、`ConstDeclarations`、
  `EventErrorDeclarations`、`ExtensionRequirements`、`FieldDeclarations`、`FnDeclarations`、
  `IntegerWidthDeclarations`、`OptionDeclarations`、`PrincipalDeclarations`、`UnitReturnTypes`、
  `InvariantDeclarations`、`ProofReferences`、`PrimitiveDeclarations`、`StateVisibility`。
  `Tests.lean` 必须保留上述 16 个 module import，但把对应 16 个 individual `run` 调用替换为一个
  `DeclarationAcceptance.run`，使 aggregate binary 内每个 suite 精确执行一次；`lakefile.lean` 保留
  16 个既有 root 并只增加 `DeclarationAcceptance` root。`FrontendParity` 是跨切片基础设施而不是
  declaration-kind suite，必须保留其独立 import/root/run，不得被 wrapper 吸收或据此声明
  `TST-SRC-005` statement/expression coverage。16 个调用在 wrapper 中变为连续执行会改变它们与其他
  suite 的交错位置；既有 `run` 均为 self-contained IO checks、无跨 suite 共享状态，该变化不得被写成
  production 或业务语义变化。
  变更只允许新增 `Tests/Language/DeclarationAcceptance.lean` 并最小修改 `Tests.lean`、`lakefile.lean`；
  总新增 ≤50 行，不得修改上述 16 个 suite、其他 tests、`ProofForgeV2/` production 或 package file-set。
  验证只运行 `lake build Tests.Language.DeclarationAcceptance proof_forge_next_tests`、
  `lake env .lake/build/bin/proof-forge-next-tests`、`just docs-check`、`git diff --check` 与 independent review；
  纯 tests/docs 切片不运行 `just sbom` 或完整 `just ci`。结果只可记录 development evidence，不能满足
  冻结包要求的 candidate-bound `qualification=formal`；`TASK-D1-02` 未 done 时不得关闭 pending
  `TASK-D1-03`，也不得由本切片关闭 D1-04、D1-05 或开始 D1-06。
- D1-PA-88 只把已冻结的 `TASK-D1-02`/`TST-SRC-003` command surface 收敛为单一 tests-only
  `Tests.Language.ProgramCommandAcceptance` executable harness；它是既有 parser 行为的 characterization
  packaging，不包装混合的 `ProgramSyntax.run`、`FrontendParity.run` 或 `Loader.run`，不修改 production，
  也不制造缺文件或删除实现的虚假 RED。
  positive 必须在 acceptance module 的 test-only namespace 中以唯一用户入口
  `program Counter where` 定义一个只含单一 `view` 的 direct fixture，再用
  `ParserSession.parsePrograms` 解析相同 namespace/source；结果必须精确为一个 program，并与 direct
  fixture 的完整 `Source.Program`、short name、qualified name 与 `sourceHash` 相等。不得调用
  `selectProgram`，不得断言 requirements、compile/Typed/Semantic、declaration 或 statement 语义。
  illegal-top-level negative 固定两条独立源码并捕获 parser streams：显式
  `program Invalid : contract where` 必须精确返回
  `PF-SRC-INVALID: Lean parser rejected source: failed to parse file`；非白名单
  `run_cmd IO.println "PF-PA88-MUST-NOT-EXECUTE"` 必须精确返回
  `PF-SRC-INVALID: Lean command 'Lean.runCmd' is outside the portable program DSL`，且 captured output 不得
  包含 marker。这里固定的是 parser behavior，不是 `TST-DIAG-001` Diagnostic v1 schema/redaction 验收。
  direct fixture 可产生一个 test-local program attribute export，但 suite 不得调用 `programExports`/
  `programPayloads` 或修改 PA81–PA86 fixtures；PA86 empty snapshot 继续由其独立 import closure 隔离，
  本切片不得据该 test-local export 声明 `TST-SRC-006/007` coverage。
  变更只允许新增 `Tests/Language/ProgramCommandAcceptance.lean` 并最小修改 `Tests.lean`、`lakefile.lean`；
  总新增 ≤80 行，不得修改其他 tests、`ProofForgeV2/` production 或 package file-set。验证只运行
  `lake build Tests.Language.ProgramCommandAcceptance proof_forge_next_tests`、
  `lake env .lake/build/bin/proof-forge-next-tests`、`just docs-check`、`git diff --check` 与 independent review；
  纯 tests/docs 切片不运行 `just sbom` 或完整 `just ci`。结果只可记录 development evidence，不能满足
  冻结包要求的 candidate-bound `qualification=formal`；`TASK-D1-01` 未 done 时不得关闭 pending
  `TASK-D1-02`，也不得由本切片关闭 SRC-001/002/004/005/006/007/008、D1-07/08 或任何 D2/target task。
- D1-PA-89 只把 `TASK-D1-01`/`TST-SRC-001` 已有的 NodeId/span development assertions 收敛为单一
  tests-only `Tests.Language.SourceWireAcceptance.run` executable harness；它是
  `SourceIdentity.run` 与 `SourceSpan.run` 的 characterization packaging，不补写缺失的完整
  ProgramV1 cross-encoder/golden corpus，不修改 production、既有 suite assertion，也不制造缺文件或
  删除实现的虚假 RED。wrapper 必须按当前 aggregate runner 的相对顺序先调用
  `Tests.Language.SourceIdentity.run`，再调用 `Tests.Language.SourceSpan.run`，两者各精确一次。
  `Tests.lean` 必须保留两个既有 module import，但把两个 individual `run` 调用替换为一个
  `SourceWireAcceptance.run`；`lakefile.lean` 保留两个既有 root 并只增加
  `SourceWireAcceptance` root。不得包装 `ProgramSyntax.run`、`Loader.run` 或任何其他 suite，也不得据
  wrapper 名称声称 TST-SRC-001 的完整 wire inventory、independent encoder、collision staging，或
  TST-SRC-002 的 Syntax/identity/CLI resource bounds 已关闭。
  变更只允许新增 `Tests/Language/SourceWireAcceptance.lean` 并最小修改 `Tests.lean`、`lakefile.lean`；
  总新增 ≤30 行，不得修改 `SourceIdentity.lean`、`SourceSpan.lean`、其他 tests、`ProofForgeV2/`
  production 或 package file-set。验证只运行
  `lake build Tests.Language.SourceWireAcceptance proof_forge_next_tests`、
  `lake env .lake/build/bin/proof-forge-next-tests`、`just docs-check`、`git diff --check` 与 independent review；
  纯 tests/docs 切片不运行 `just sbom` 或完整 `just ci`。结果只可记录 development evidence，不能满足
  TASK-D1-01 冻结包要求的两项完整 TST 与 candidate-bound `qualification=formal`；五个 D0 dependency
  未全部 done 时不得关闭 pending `TASK-D1-01`。`TST-SRC-002` 必须由后续单独冻结的窄
  `SourceBoundsAcceptance` slice 承载，禁止用混合 `ProgramSyntax`/`Loader` wrapper 代替边界验收。
- D1-PA-90 把 `TASK-D1-01`/`TST-SRC-002` 的 unit boundary 收敛为独立 tests-only
  `Tests.Language.SourceBoundsAcceptance.run`，并把既有 `just dsl-negative` 作为重资源 integration
  入口；它是当前 production bounds 的 direct characterization，不包装混合的 `ProgramSyntax.run` 或
  `Loader.run`，不修改 production、generator、justfile、testdata 或既有 suite assertion，也不制造缺文件
  或删除实现的虚假 RED。
  direct suite 必须以 test-owned iterative helpers 构造 root-inclusive linear/wide Syntax 与 repeated Name，
  并固定：`maxSyntaxNesting = 256`、`maxSyntaxNodes = 100000` 与 `PF-BOUND-001` code；linear Syntax
  256 接受/257 精确拒绝；wide Syntax 100000 接受/100001 精确拒绝；type、parameter、expression、
  statement、item、program-command 六个 public decoder 对同一 257-deep Syntax 都先返回 exact nesting
  `PF-BOUND-001`，program-command 对 100001 nodes 返回 exact node-bound diagnostic；namespace 255
  components + one-part program identity（总计 256）接受、namespace 256 + program（总计 257）精确拒绝；
  identifier Name 256 components 接受、257 精确拒绝。错误断言必须固定完整 render，不只检查 prefix。
  重资源 integration 不得进入 resident `proof-forge-next-tests`：现有
  `scripts/generate_syntax_bound_fixtures.py`/`just dsl-negative` 已分别执行 namespace 255/256、peak 257
  unwind 到 255、300-term expression、20,000-state wide source、Lean command/CLI 双入口 diagnostic parity、
  CLI exactly 16 MiB accept 与 16 MiB+1 pre-parse `PF-SRC-INVALID`/zero-output；本切片只要求该既有入口
  单次通过，不复制这些向量。
  变更只允许新增 `Tests/Language/SourceBoundsAcceptance.lean` 并最小修改 `Tests.lean`、`lakefile.lean`；
  总新增 ≤110 行，不得修改 `ProgramSyntax.lean`、`Loader.lean`、其他 tests、`ProofForgeV2/` production、
  generator、justfile 或 package file-set。验证只运行
  `lake build Tests.Language.SourceBoundsAcceptance proof_forge_next_tests`、
  `lake env .lake/build/bin/proof-forge-next-tests`、单次 `just dsl-negative`、`just docs-check`、
  `git diff --check` 与 independent review；不运行 `just sbom` 或完整 `just ci`。结果只可记录 development
  evidence，不能满足 candidate-bound `qualification=formal`；五个 D0 dependencies 未全部 done，且
  `TST-SRC-001` 完整 wire/collision residual 未闭合时，不得关闭 pending `TASK-D1-01` 或任何下游 task。
- D1-PA-91 是 `TASK-D1-01`/`TST-SRC-001` 的首个真实 canonical binary primitive coding slice：新增
  `ProofForgeV2.Source.WireCodecV1` primitive/tagged encoder 与不 import Lean/ProofForge 的 Python
  reference self-check。它不定义 partial/full `ProgramV1` business AST，不从当前 bucketed alpha
  `Source.Program` 投影有损 source-order items，不修改 `Source.Program.canonicalBytes`/`sourceHash`，也不
  提前发布完整 `canonicalSourceAstBytesV1`、`decodeCanonicalSourceAstBytesV1` 或 `sourceHashV1`。
  production public API 精确限于 `encodeU8`、`encodeU16le`、`encodeU32le`、`encodeU256le`、
  `encodeBool`、higher-order `encodeOption`/`encodeArray`、`encodeIdent`/`encodeString`、
  `encodeQualifiedName`/`encodeQualifiedId` 与 `encodeTagged`。`u16/u32` 必须 little-endian；u256 是
  exact 32-byte little-endian unsigned magnitude，`2^256` 起 fail closed；Option 使用 `0/1` marker；Array
  使用 u32 count 并保持输入顺序；Ident/String 使用 u32 UTF-8 byte length 且拒绝 non-NFC，Ident 额外执行
  exact Lean/common identifier validation；QualifiedId 必须 2..256 components；generic tag 必须 nonempty
  ASCII、field count 可由 u16 exact 表示，并编码 `u32le tagByteLength || tag || u16le fields.size || fields`。
  generic primitive codec 不判断 closed constructor inventory，后者只能由未来完整 ProgramV1 encoder 拥有。
  `Tests.Language.SourceWireCodecV1` 必须固定 checked-in hex goldens：u8 zero/max、u16/u32 endianness、u256 zero/max 与
  overflow、Bool、Option none/some、Array empty/multi-order、ASCII/Unicode NFC Ident/String、one-component
  QualifiedName/two-component QualifiedId、
  nullary tag 与 hand-composed two-field `Program` tag；negative 固定 non-NFC、invalid ident、由
  `parseQualifiedName #[]` 拒绝的 zero-component carrier、one-component/257-component QualifiedId、
  empty/non-ASCII tag 与 unrepresentable field count。
  Escaped source identifier 到 qualified component 的投影仍有独立规格裁决，本切片不得加入 escaped-identifier
  source fixture 或据 primitive bytes 决定该投影。`scripts/reference_source_wire_codec_v1.py
  --self-check` 必须由独立实现命中同一 logical vectors/expected hex；只比较两个实现彼此相等而没有固定
  bytes 不算通过。本切片只证明 primitive cross-implementation foundation，不声称 ProgramV1 full golden。
  变更只允许新增 `ProofForgeV2/Source/WireCodecV1.lean`、
  `Tests/Language/SourceWireCodecV1.lean`、`scripts/reference_source_wire_codec_v1.py`，最小修改
  `ProofForgeV2.lean`、`Tests.lean`、`lakefile.lean`，并机械刷新
  `supply-chain/lean-package-files.v1.json`；authored additions 总计 ≤380 行（机械 manifest refresh 不计），
  codec ≤140、Lean suite ≤130、Python ≤100，其余 registration additions ≤10。
  禁止修改 `Core/Source.lean`、Language/Loader/Syntax、WireV1 NodeId、PA89/90 suites、justfile 或其他
  production。验证只运行 focused codec/test/aggregate build、test binary、Python `--self-check`、
  `git diff --check`、`just docs-check`、机械 package refresh 后单次 `just sbom` 与 independent review；
  不运行完整 `just ci`。`SPEC-SOURCE-WIRE-001` 保持 proposed；`ProofDecl.theorem` carrier、visibility 映射、
  forward-grammar constructor 与 NodeId JCS key 等未触及的完整-model问题不得混入本切片。结果只能记录 development evidence，不能关闭完整 TST-SRC-001、pending
  TASK-D1-01、任何下游 task，也不能把 `pf.source.v1` alpha payload 与未来 ProgramV1 payload 混为一谈。
- D1-PA-92 是 `TASK-D1-01`/`TST-SRC-001` 的 cursor-based primitive decoder slice。新增
  `ProofForgeV2.Source.WireDecodeV1`，生产 public surface 精确限于 private-constructor/private-field
  `CursorV1`、
  `DecoderV1`、`start`、`remaining`、`finish`、`decodeU8`、`decodeU16le`、`decodeU32le`、
  `decodeU256le`、`decodeBool`、higher-order `decodeOption`、`decodeArray maxCount` 与 `decodeString`，签名冻结为：

  ```lean
  structure CursorV1 where
    private mk ::
    private input : ByteArray
    private offset : Nat
  abbrev DecoderV1 (α : Type) := CursorV1 → Except String (α × CursorV1)
  start : ByteArray → CursorV1
  remaining : CursorV1 → Nat
  finish : CursorV1 → Except String Unit
  decodeU8 : DecoderV1 UInt8
  decodeU16le : DecoderV1 UInt16
  decodeU32le : DecoderV1 UInt32
  decodeU256le : DecoderV1 Nat
  decodeBool : DecoderV1 Bool
  decodeOption (decode : DecoderV1 α) : DecoderV1 (Option α)
  decodeArray (maxCount : Nat) (decode : DecoderV1 α) : DecoderV1 (Array α)
  decodeString : DecoderV1 String
  ```

  decoder 返回 value 与推进后的 cursor；所有 read 必须在 slice/allocation 前检查 remaining bytes，失败不返回
  partial value/cursor。u16/u32/u256 必须 inverse PA91 little-endian，其中 u256 exact 消费 32 bytes 并保持
  full Nat；Bool/Option 只接受 0/1 marker；Array 必须先解码 u32 count，再在调用任何 child decoder 或分配
  result 前以 exact `array count exceeds caller limit` 拒绝 `count > maxCount`，随后保持 wire order并传播第一个
  child error。`maxCount` 是调用方在未来 closed constructor/profile 中提供的 allocation policy，不代表本切片已
  实现 global 100000-node/16-MiB budget；String 必须先验证 u32
  declared byte length 不超过 remaining，再 strict UTF-8 decode 并使用 pinned Unicode `requireNfc` 拒绝 NFD。
  `finish` 只接受 zero remaining，拒绝 trailing bytes；本切片不冻结各类 malformed input 的诊断文本，唯一例外是上述用于证明
  array cap 优先级的 exact `array count exceeds caller limit`。
  `Tests.Language.SourceWireDecodeV1` 必须以 checked-in bytes 固定 u8、非对称 u16/u32/u256、Bool、
  Option none/some、Array empty/multi-order、ASCII/Unicode NFC String 与 exact-consume positive；negative 固定
  truncated u8/u16/u32/u256、Bool/Option marker 2、array count over caller cap 且 child decoder 未被调用、
  first child error、truncated child、string length over remaining、invalid UTF-8、NFD 与 trailing byte。
  positive 还必须只对 PA91 `encodeU8`/`encodeU16le`/`encodeU32le`/`encodeU256le`/`encodeBool`/
  `encodeOption`/`encodeArray`/`encodeString` 执行 encode→decode logical round-trip；禁止调用 PA91
  `encodeIdent`/`encodeQualifiedName`/`encodeQualifiedId`/`encodeTagged`，也不允许只让 decoder 与自身生成的 bytes
  比较。array-over-cap negative 必须比较上述 exact limit error，并给 child decoder 一个不同 exact error，证明
  limit failure 先于 child call/allocation。`scripts/reference_source_wire_decode_v1.py --self-check` 必须不 import Lean/ProofForge，以独立 cursor
  命中同一 fixed vectors/negative classes；只比较 Lean/Python 彼此相等而没有 checked-in bytes 不算通过。
  变更只允许新增 `ProofForgeV2/Source/WireDecodeV1.lean`、
  `Tests/Language/SourceWireDecodeV1.lean`、`scripts/reference_source_wire_decode_v1.py`，最小修改
  `ProofForgeV2.lean`、`Tests.lean`、`lakefile.lean`，并机械刷新
  `supply-chain/lean-package-files.v1.json`；authored additions 总计 ≤370 行（机械 manifest refresh 不计），
  decoder ≤145、Lean suite ≤125、Python ≤90、其余 registration additions ≤10。禁止修改 PA91 encoder/
  suites/reference、Common、Core Source、Language/Loader/Syntax、WireV1、justfile 或其他 production。
  验证只运行 focused decoder/test/aggregate build、test binary、Python `--self-check`、package refresh 后最终
  单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行完整 `just ci`。
  本切片明确不解码 Ident、QualifiedName/QualifiedId 或 tagged constructor：escaped raw component carrier 是
  model 与 component decoder 的前置，`ProofDecl.theorem`/visibility 是 model 前置，NodeId exact JCS keys 是
  NodeId slice 前置。结果只能记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01
  或任何下游 task，也不能声明 16 MiB/global node/nesting budget、full Program exact consume 或 stable Diagnostic。
- D1-PA-93 是 `TASK-D1-01`/`TST-SRC-001` 的 raw Lean `Name.str` source-name carrier slice。决策：
  `SourceNameComponentV1` 是 typed private-constructor carrier，**distinct** from
  `Core.Common.QualifiedName` 与 `Name.toString` rendered spelling；wire 身份永远是 **raw**，永不写入
  rendered guillemets。生产 public API 精确冻结为：

  ```lean
  structure SourceNameComponentV1 where
    private mk ::
    raw : String
    deriving DecidableEq, Repr
  parseSourceNameComponentV1 : String → Except String SourceNameComponentV1
  sourceNameComponentV1FromLeanName : Lean.Name → Except String SourceNameComponentV1
  renderSourceNameComponentV1 : SourceNameComponentV1 → String
  WireCodecV1.encodeSourceNameComponentV1 :
    SourceNameComponentV1 → Except String ByteArray
  WireDecodeV1.decodeSourceNameComponentV1 :
    WireDecodeV1.DecoderV1 SourceNameComponentV1
  ```

  `sourceNameComponentV1FromLeanName` 只接受最终 constructor 为 `.str` 的 `Name`（reject `.num` /
  non-str）。`renderSourceNameComponentV1 c` exact 为 `(Name.str .anonymous c.raw).toString`。
  `parseSourceNameComponentV1` 验证：raw UTF-8 长度 `1..240`；pinned NFC；拒绝 Unicode Cc 与 closing
  guillemet `U+00BB`；**显式允许** exact `_`、opening `U+00AB`、digit-leading、hyphen、embedded dot、
  space、NFC Unicode letter-like 与 language keyword **bodies**（language owner 仍可在 Syntax 层保留词；
  本 carrier 不做 keyword deny-list）。不调用 `Lean.isIdFirst`/`isIdRest`，也不复用
  `parseQualifiedName` 作为 accept oracle。
  Wire：`WireCodecV1.encodeSourceNameComponentV1` / `WireDecodeV1.decodeSourceNameComponentV1` 对 raw
  使用既有 String primitive layout（`u32le` length ‖ UTF-8）；既有 `encodeIdent : String → …` 的
  validation **迁移**为先 `parseSourceNameComponentV1` 再 encode raw（因而 PA91 的 `1bad` 负例必须改为
  exact **positive**，并同步更新 `scripts/reference_source_wire_codec_v1.py` 的 raw validation 与
  goldens）。独立 Python oracle 必须对同一 raw 规则与 fixed vectors 做 `--self-check`，不 import Lean。
  变更文件集：新增 `ProofForgeV2/Source/NameComponentV1.lean`、`Tests/Language/SourceNameComponentV1.lean`；
  修改 `ProofForgeV2/Source/WireCodecV1.lean`、`ProofForgeV2/Source/WireDecodeV1.lean`、
  `Tests/Language/SourceWireCodecV1.lean`、`scripts/reference_source_wire_codec_v1.py`；最小
  `ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean` 注册与机械
  `supply-chain/lean-package-files.v1.json` refresh。authored budgets：new production ≤65、new Lean suite
  ≤125、既有文件 authored deltas + registrations ≤65；总计 ≤255（机械 manifest 不计）。
  RED 必须固定：raw vs rendered 字节/字符串不等价（hyphen/dot/space）；同一 suite 顶层必须含真实
  Lean command `program «_» where ...`，以模块成功 elaboration 而非仅 ParserSession probe 证明 explicit
  underscore 仍是 `.str` source name。positives：simple、`α`、`_`、
  digit-leading `1bad`、hyphen、embedded-dot、space、opening-guillemet body、raw exact `«`（render
  exact `««»`）、keyword body `struct`、
  exact 240-byte NFC；negatives：empty、241、NFD、Unicode Cc、closing-guillemet `U+00BB`、anonymous
  `Name`、`Name.num`；decoder exact bytes + encode→decode；injectivity pair：raw `foo.bar` **accept**
  vs raw containing closing guillemet **reject**。Python reference 只实现 raw validation/wire，不复制
  `Name.toString` renderer；render 不得进入跨实现 identity assertion。
  明确排除：root ProgramV1、`SourceQualifiedName` 完整类型/root join、model cutover、`sourceHashV1`、
  NodeId、Common/Syntax/Loader/Core.Source/ProgramPayload/target 改写。验证只运行 focused
  NameComponent+WireCodec+WireDecode/test aggregate build、test binary、Python self-check、package
  refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行
  完整 `just ci`。结果只可记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01
  或任何下游 task。
- D1-PA-94 是 `TASK-D1-01`/`TST-SRC-001` 的 source-only qualified-name array slice。它只消费
  PA93 的 raw `SourceNameComponentV1`，不复用或削弱 Common `QualifiedName`；生产 public API 精确冻结为：

  ```lean
  structure SourceQualifiedNameV1 where
    private mk ::
    components : NonEmptyArray SourceNameComponentV1
    deriving DecidableEq, Repr
  sourceQualifiedNameV1OfComponents :
    Array SourceNameComponentV1 → Except String SourceQualifiedNameV1
  parseSourceQualifiedNameV1 : Array String → Except String SourceQualifiedNameV1
  sourceQualifiedNameV1FromLeanName : Lean.Name → Except String SourceQualifiedNameV1
  validateSourceQualifiedIdV1 : SourceQualifiedNameV1 → Except String Unit
  validateSourceProgramIdentityV1 :
    SourceQualifiedNameV1 → SourceQualifiedNameV1 → Except String Unit
  WireCodecV1.encodeSourceQualifiedNameV1 :
    SourceQualifiedNameV1 → Except String ByteArray
  WireCodecV1.encodeSourceQualifiedIdV1 :
    SourceQualifiedNameV1 → Except String ByteArray
  WireDecodeV1.decodeSourceQualifiedNameV1 :
    WireDecodeV1.DecoderV1 SourceQualifiedNameV1
  WireDecodeV1.decodeSourceQualifiedIdV1 :
    WireDecodeV1.DecoderV1 SourceQualifiedNameV1
  ```

  `SourceQualifiedNameV1` 构造时固定 `1..256` components；`validateSourceQualifiedIdV1` 与 QID
  encode/decode 固定 `2..256`。禁止公开 caller-selected `minCount`，避免用错误上下文构造弱 carrier。
  `sourceQualifiedNameV1FromLeanName` 只接受以 `.anonymous` 终止的纯 `.str` chain，保持 root-to-leaf raw
  顺序；anonymous、final `.num` 或任意 prefix `.num` 均失败。`validateSourceProgramIdentityV1 module
  programIdentity` 先要求 programIdentity 为 QualifiedId，再要求它比 module **严格更长**且 raw component
  prefix 与 module exact 相同；本切片没有 Program name 参数，因而不声称完成 last-component/program.name
  binding。实现允许复用 Common 的 generic `NonEmptyArray` container，但不得调用 Common
  `parseQualifiedName`、`renderQualifiedNameComponents`、isId* 或 rendered spelling。
  Wire exact 为 `u32le count ‖ encodeSourceNameComponentV1(component[0]) ...`；QN decoder 对 count 0/257、
  QID decoder 对 count 0/1/257 必须在任何 child decode 前 fail closed。固定 count errors 分别为
  `source qualified name must contain 1..256 components` 与
  `source qualified id must contain 2..256 components`。
  RED positives：single module `Demo`、two-component `Demo/Counter`、raw hyphen 与 opening-guillemet component、
  QID 2/256、Lean `Demo.Counter` `.str` chain、fixed raw wire与 encode→decode exact consume；negatives：empty、
  257、QID one、empty/NFD/Cc/closing-guillemet component、anonymous/final-num/prefix-num、equal join、non-prefix
  join，并用 count-invalid + hostile child bytes固定 count-before-child priority。独立 Python oracle只实现 raw
  component-array validation/bytes，不实现 Lean renderer。
  变更文件集：新增 `ProofForgeV2/Source/QualifiedNameV1.lean`、
  `Tests/Language/SourceQualifiedNameV1.lean`；修改 WireCodec/WireDecode、现有 Python reference 与最小
  `ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean` 注册；机械 refresh package manifest。budgets：new production
  ≤100、new suite≤150、既有/Python/registrations additions≤80、总 authored additions≤330（manifest 不计）。
  明确排除：`ProofDecl.theorem`/visibility 或任何 ProgramV1 constructor、canonical root/hash、NodeId、alpha
  projection/sourceHash、Common/Syntax/Loader/Core.Source/ProgramPayload/target 改写。验证只运行 focused+
  aggregate build/test binary、Python self-check、package refresh 后最终单次 `just sbom`、`just docs-check`、
  `git diff --check` 与 independent review；不运行完整 `just ci`。结果只记录 development evidence，不能关闭
  完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-95 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 leaf AST closed-layer slice。边界必须是
  `SPEC-SOURCE-WIRE-001` 五张完整表的 **38 个唯一 tag**：Visibility 3、Type 11（包含 Named/Map）、
  Literal 3、UnaryOp 3、BinaryOp 18；不得写成“current grammar subset”后静默删 constructor。模型与
  encoder 分模块，生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstV1
  inductive VisibilityV1
    | public_ | private_ | commitment
  inductive TypeV1
    | bool | uint (width : UInt16) | int (width : UInt16)
    | principal | unit | named (name : SourceNameComponentV1)
    | array (element : TypeV1) (length : UInt32)
    | map (key value : TypeV1) | option (element : TypeV1)
    | bytes (length : UInt32) | field (id : SourceNameComponentV1)
  inductive LiteralV1
    | bool (value : Bool) | integer (magnitude : Nat) | string (value : String)
  inductive UnaryOpV1
    | neg | not | bitNot
  inductive BinaryOpV1
    | add | sub | mul | div | mod | eq | ne | lt | le | gt | ge
    | logicalAnd | logicalOr | bitAnd | bitOr | bitXor | shl | shr
  -- each derives DecidableEq, Repr

  namespace ProofForgeV2.Source.AstCodecV1
  encodeVisibilityV1 : VisibilityV1 → Except String ByteArray
  encodeTypeV1 : TypeV1 → Except String ByteArray
  encodeLiteralV1 : LiteralV1 → Except String ByteArray
  encodeUnaryOpV1 : UnaryOpV1 → Except String ByteArray
  encodeBinaryOpV1 : BinaryOpV1 → Except String ByteArray
  ```

  每个 encoder 只组合 PA91/PA93 已验证的 primitive/raw-name/`encodeTagged`，tag 与 field count 必须逐字
  匹配 wire 表。`Type.UInt/Int.width` 只接受 UInt16 值 8/16/32/64/128/256；Array/Bytes UInt32 length
  只接受 0..4096；Field raw id 只接受 `bn254_fr`；Named 与 Field 都编码 raw
  `SourceNameComponentV1`，不得 rendered/Common 化。Literal.Integer 复用 u256le 并拒绝 `≥2^256`；
  Literal.String 复用 pinned-NFC String。invalid width/length/field 必须在 `encodeTypeV1` 内 fail closed，
  exact new errors 分别为 `integer width must be one of 8,16,32,64,128,256`、
  `array length must be 0..4096`、`bytes length must be 0..4096`、`field id must be bn254_fr`。
  本切片不加入局部 Type depth 上限；root-inclusive 256 nesting、100000 nodes 与 16 MiB 是后续完整
  ProgramV1 validator/decoder 的全树规则，不能在 leaf encoder 上冒充完成。
  RED/independent Python 必须固定 38 个 table-verbatim tag 的 exact bytes，且每个 constructor 至少一个
  checked-in vector；Type.UInt/Int 六种 width 各通过，0/24 拒绝；Named raw `foo-bar`、Map、nested
  `Array(Option(Bytes))`；Array/Bytes 0 与4096通过、4097拒绝；Field `bn254_fr` 通过且其他 raw id 拒绝；
  Literal Integer 0、`>UInt64`、`2^256-1` 通过且 `2^256` 拒绝；Bool 0/1、NFC String通过、NFD拒绝。
  Binary inventory exact 为 Add/Sub/Mul/Div/Mod/Eq/Ne/Lt/Le/Gt/Ge/And/Or/BitAnd/BitOr/BitXor/Shl/Shr；
  logicalOr 与 bitOr 必须生成不同 tag。Lean suite与不 import Lean/ProofForge 的 Python oracle各自持有
  expected hex，禁止以 production encoder 生成 decoder/expected oracle。
  变更文件集：新增 `ProofForgeV2/Source/AstV1.lean`、`ProofForgeV2/Source/AstCodecV1.lean`、
  `Tests/Language/SourceAstLeafV1.lean`、`scripts/reference_source_ast_leaf_v1.py`；最小
  `ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean` registration 与机械 package manifest refresh。budgets：
  AstV1≤75、AstCodecV1≤180、suite≤220、Python≤130、registrations≤8、总 authored additions≤615
  （manifest 不计）。明确排除：alpha Source/Syntax/visibility/theorem projection、Program/items/supporting records、
  recursive Stmt/Expr/Place/Pattern spine、decoder、root/sourceHash、NodeId、global resource validator、Common/
  Loader/ProgramPayload/target 改写。验证只运行 focused+aggregate build/test binary、Python self-check、package
  refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行完整
  `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-96 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 self-contained supporting-record slice。它只实现
  `SPEC-SOURCE-WIRE-001` supporting table 中不依赖 Expr/Stmt/Pattern 的三个完整 tag，不定义残缺
  `ProgramItem` sum 或 mutual spine。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSupportV1
  structure ParamV1 where
    visibility : AstV1.VisibilityV1
    name : SourceNameComponentV1
    type_ : AstV1.TypeV1
    deriving DecidableEq, Repr
  structure FieldDeclV1 where
    name : SourceNameComponentV1
    type_ : AstV1.TypeV1
    deriving DecidableEq, Repr
  structure EnumVariantV1 where
    name : SourceNameComponentV1
    payloadTypes : Array AstV1.TypeV1
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstSupportCodecV1
  encodeParamV1 : ParamV1 → Except String ByteArray
  encodeFieldDeclV1 : FieldDeclV1 → Except String ByteArray
  encodeEnumVariantV1 : EnumVariantV1 → Except String ByteArray
  ```

  encoders 必须逐字组合：`Param`/3 fields = Visibility、raw Ident、Type；`FieldDecl`/2 = raw Ident、Type；
  `EnumVariant`/2 = raw Ident、`encodeArray encodeTypeV1 payloadTypes`。不得调用 Common/render，不增加
  supporting-record local identifier/array cap；typed Ident 复用 PA93，Type invariants/errors 原样由 PA95
  child encoder 传播。EnumVariant payloadTypes **允许 empty**；`EnumDecl.variants` nonempty 是未来 declaration/
  Program validator 规则，不得错误下沉。本切片所有 encoder 必须为 total `def`。
  RED 与独立 Python必须持有 table-verbatim checked-in hex：Param 覆盖 Public/Private/Commitment、raw names、
  Bool/Unit/UInt64 与 nested `Array(Option(Bytes 0),0)`；FieldDecl 覆盖 UInt256 与 Map(Bool,Unit)；
  EnumVariant 覆盖 empty payload、Bool/Principal ordered pair 与 nested Option。负例精确复用 PA95 child errors：
  Param/Field width 24、EnumVariant Bytes 4097；golden expected 不得由 production encoder 生成。Python 不 import
  Lean/ProofForge，并保持 raw name Cc/closing-guillemet规则。
  变更文件集：新增 `ProofForgeV2/Source/AstSupportV1.lean`、
  `ProofForgeV2/Source/AstSupportCodecV1.lean`、`Tests/Language/SourceAstSupportV1.lean`、
  `scripts/reference_source_ast_support_v1.py`；最小 ProofForgeV2/Tests/lake registration 与机械 manifest refresh。
  budgets：model≤45、codec≤90、suite≤140、Python≤100、registrations≤8、总 authored additions≤390
  （manifest 不计）。明确排除：Block/StmtMatchArm/ExprMatchArm/ExternalCallExpr、Pattern、Place/Expr/Stmt/Block
  mutual spine、任何 partial ProgramItem/Program root、alpha Source/Syntax/Loader/projection、decoder、global validator、
  sourceHash/NodeId/Common/ProgramPayload/target。验证只运行 focused+aggregate build/test binary、Python self-check、
  package refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行
  完整 `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-97 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 complete Pattern closed-layer slice。它实现
  `SPEC-SOURCE-WIRE-001` Pattern table 的全部四个 tag；Pattern 只依赖 PA93 raw Ident、PA94 source QID、
  PA95 Literal 与自身递归，不依赖 Place/Expr/Stmt mutual spine。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstPatternV1
  inductive PatternV1 where
    | wildcard
    | bind (name : NameComponentV1.SourceNameComponentV1)
    | literal (value : AstV1.LiteralV1)
    | constructor (ctor : QualifiedNameV1.SourceQualifiedNameV1) (args : Array PatternV1)
    deriving Repr
  instance : DecidableEq PatternV1

  namespace ProofForgeV2.Source.AstPatternCodecV1
  encodePatternV1 : PatternV1 → Except String ByteArray
  ```

  wire mapping 必须逐字为：`Pattern.Wildcard`/0；`Pattern.Bind`/1 raw Ident；`Pattern.Literal`/1 full
  tagged Literal；`Pattern.Constructor`/2 source QualifiedId 后 `Array<Pattern>`。Constructor 必须先调用
  `encodeSourceQualifiedIdV1`，再编码 args；one-component QID 与同时存在的 hostile child 必须先返回
  `source qualified id must contain 2..256 components`。args **允许 empty**，binding uniqueness、constructor
  resolution/arity/exhaustiveness 和 256-depth/100000-node/16-MiB budgets 属于未来 D2/global validator，
  不得在本 encoder 增加 local cap。

  pinned Lean 4.31 对 `Array PatternV1` nested inductive 不支持自动 `deriving DecidableEq`，直接把
  `encodePatternV1` 作为 higher-order 参数传给 `encodeArray` 也不能证明终止。本切片必须以 Pattern/Array/
  List 三路 structural recursion 实现可执行 `DecidableEq` 与 encoder；encoder 可先 total 地得到 ordered child
  byte chunks，再调用既有 `encodeArray pure`。所有生产定义必须是 kernel-total `def`；禁止 `partial`、
  `unsafe`、fuel、深度截断、JSON/String/Unit placeholder 或复制另一份 array wire layout。

  RED 与 independent Python 必须持有 table-verbatim checked-in hex，至少覆盖：Wildcard；Bind raw `x` 与
  `foo-bar`；Pattern.Literal 的 Bool `true`/`false`、`2^64` Integer 和 NFC String；Constructor 两组件 QID + empty args、
  single Wildcard、ordered Bind/Literal pair、反序 non-alias 与 depth≥2 nested Constructor。Lean 另验证 nested
  Pattern equality的 equal/order/shape cases。负例逐字覆盖 one-component QID、Literal `2^256` overflow、
  Literal NFD，并覆盖 invalid QID 优先于 invalid nested Literal；Python 不 import Lean/ProofForge，保持 raw
  name Cc/closing-guillemet negatives，golden expected 不得由 production encoder 生成。

  变更文件集：新增 `ProofForgeV2/Source/AstPatternV1.lean`、
  `ProofForgeV2/Source/AstPatternCodecV1.lean`、`Tests/Language/SourceAstPatternV1.lean`、
  `scripts/reference_source_ast_pattern_v1.py`；最小 ProofForgeV2/Tests/lake registration 与机械 manifest refresh。
  budgets：model≤85、codec≤75、suite≤150、Python≤110、registrations≤8、总 authored additions≤430
  （manifest 不计）。明确排除：Place/Expr/Stmt/Block、StmtMatchArm/ExprMatchArm/ExternalCallExpr、任何
  ProgramItem/Program root、alpha Source/Syntax/Loader/projection、decoder、global validator、sourceHash/NodeId、
  Common/ProgramPayload/target。验证只运行 focused+aggregate build/test binary、Python self-check、package
  refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行完整
  `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-98 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 complete spine-independent declaration-record
  slice。它一次实现 `SPEC-SOURCE-WIRE-001` 中字段依赖已由 PA91–96 闭合的全部七个 item tag；只定义
  named records，不提前定义只含 7/13 alternatives 的残缺 `ProgramItemV1` sum。该 closed-class rule 精确是
  **all ProgramItem records whose ordered field types depend only on already shipped carriers**；不是按当前 parser
  能力或实现方便任意选七个。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstDeclV1
  structure StateDeclV1 where
    visibility : AstV1.VisibilityV1
    name : NameComponentV1.SourceNameComponentV1
    type_ : AstV1.TypeV1
    deriving DecidableEq, Repr
  structure StructDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    fields : Array AstSupportV1.FieldDeclV1
    deriving DecidableEq, Repr
  structure EnumDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    variants : Array AstSupportV1.EnumVariantV1
    deriving DecidableEq, Repr
  structure EventDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    params : Array AstSupportV1.ParamV1
    deriving DecidableEq, Repr
  structure ErrorDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    params : Array AstSupportV1.ParamV1
    deriving DecidableEq, Repr
  structure ExtensionReqV1 where
    id : QualifiedNameV1.SourceQualifiedNameV1
    version : String
    digest : String
    deriving DecidableEq, Repr
  structure ProofDeclV1 where
    invariant : NameComponentV1.SourceNameComponentV1
    theorem_ : QualifiedNameV1.SourceQualifiedNameV1
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstDeclCodecV1
  encodeStateDeclV1 : StateDeclV1 → Except String ByteArray
  encodeStructDeclV1 : StructDeclV1 → Except String ByteArray
  encodeEnumDeclV1 : EnumDeclV1 → Except String ByteArray
  encodeEventDeclV1 : EventDeclV1 → Except String ByteArray
  encodeErrorDeclV1 : ErrorDeclV1 → Except String ByteArray
  encodeExtensionReqV1 : ExtensionReqV1 → Except String ByteArray
  encodeProofDeclV1 : ProofDeclV1 → Except String ByteArray
  ```

  wire mapping 与字段顺序必须逐字为：`StateDecl`/3 = Visibility、raw Ident、Type；`StructDecl`/2 = raw
  Ident、Array FieldDecl；`EnumDecl`/2 = raw Ident、Array EnumVariant；`EventDecl`/2 与 `ErrorDecl`/2 = raw
  Ident、Array Param；`ExtensionReq`/3 = source QualifiedId、String version、String digest；`ProofDecl`/2 =
  raw invariant Ident、source theorem QualifiedId。所有 encoder 为 total `def`，只组合既有 PA91–96 codecs。

  `StructDecl.fields` 与 `EnumDecl.variants` 必须在 encoder 中先以 exact `struct fields must be nonempty` /
  `enum variants must be nonempty` fail closed；Event/Error params **允许 empty**。ExtensionReq 必须按 exact
  priority 先 `encodeSourceQualifiedIdV1 id`，再以 Common `parseSemVer`+`renderSemVer` exact equality 验证
  version，最后以 `parseDigest`+`renderDigest` exact equality验证 digest；任一 version parse/render/equality
  失败统一为 `extension version must use canonical exact SemVer`，任一 digest failure 统一为
  `extension digest must use canonical sha256 spelling`，不得泄漏 Common parser 的细分错误。验证成功后两者
  仍调用 `encodeString` 写 wire。canonical prerelease/build 只要 parse/render exact round-trip 即允许，禁止改用
  `parseSemVerCore`。valid QID + invalid version + invalid digest 必须先返回 version error；invalid
  QID + hostile version/digest 必须先返回 QID error。Proof theorem 使用同一 source QID 2..256 validation。
  不增加 declaration-local array/string/global cap；Program.items nonempty、duplicates、multiple init、proof-
  invariant binding 与 256-depth/100000-node/16-MiB 属于 future Program/global validator。

  RED 与 independent Python 必须持有 table-verbatim checked-in hex，至少覆盖：State 三 visibility 与 nested
  Type；Struct single/multi FieldDecl及顺序；Enum empty-payload variant、multi variants及顺序；Event empty params
  与 ordered multi Param；Error empty与single Param；Extension canonical `1.0.0`、canonical prerelease/build、
  two-component QID 与 lowercase sha256 digest；Proof raw invariant + two-component theorem QID。负例逐字覆盖
  Struct/Enum empty、State/Struct child width 24、Extension one-component QID、QID-before-hostile strings、
  noncanonical version、version-before-bad-digest、bad digest、Proof one-component theorem；Python 不 import
  Lean/ProofForge，保持 raw name Cc/closing-guillemet negatives，golden expected 不得由 production encoder生成。

  变更文件集：新增 `ProofForgeV2/Source/AstDeclV1.lean`、
  `ProofForgeV2/Source/AstDeclCodecV1.lean`、`Tests/Language/SourceAstDeclV1.lean`、
  `scripts/reference_source_ast_decl_v1.py`；最小 ProofForgeV2/Tests/lake registration 与机械 manifest refresh。
  budgets：model≤55、codec≤110、suite≤220、Python≤160、registrations≤8、总 authored additions≤560
  （manifest 不计）。明确排除：Const/Invariant/Init/Entry/View/Fn、任何 `ProgramItem` sum/Program root、
  Place/Expr/Stmt/Block/arms/ExternalCallExpr、alpha Source/Syntax/Loader/projection、decoder、global validator、
  sourceHash/NodeId/Common edits/ProgramPayload/target。验证只运行 focused+aggregate build/test binary、Python
  self-check、package refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent
  review；不运行完整 `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending
  TASK-D1-01 或下游 task。
- D1-PA-99 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 mutual spine **model/equality-only** slice。
  `SPEC-SOURCE-WIRE-001` 的依赖图证明 Place、Expr、Stmt、Block、StmtMatchArm、ExprMatchArm、
  ExternalCallExpr 七种类型构成不可再拆的最小 SCC：删掉任一类型都会缺失 Place.Index、两种 Match、
  If/For body 或 Call/Schedule 的表内 constructor。PA99 一次定义完整 25-constructor model；codec 与
  encoder-owned nonempty/bound/QID validation 留给 PA99 收口后另行冻结的后续 slice，不允许以 placeholder、
  partial constructor table 或提前 ProgramItem sum 绕开 SCC。生产 public model API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineV1
  mutual
    inductive PlaceV1 where
      | name (name : SourceNameComponentV1)
      | field (base : PlaceV1) (field : SourceNameComponentV1)
      | index (base : PlaceV1) (index : ExprV1)
      deriving Repr
    inductive ExprV1 where
      | literal (value : LiteralV1)
      | place (place : PlaceV1)
      | constructor (ctor : SourceQualifiedNameV1) (args : Array ExprV1)
      | unary (op : UnaryOpV1) (operand : ExprV1)
      | binary (op : BinaryOpV1) (lhs rhs : ExprV1)
      | localCall (callee : SourceNameComponentV1) (args : Array ExprV1)
      | match_ (scrutinee : ExprV1) (arms : Array ExprMatchArmV1)
      deriving Repr
    structure ExprMatchArmV1 where
      pattern : PatternV1
      value : ExprV1
      deriving Repr
    structure ExternalCallExprV1 where
      callee : SourceQualifiedNameV1
      args : Array ExprV1
      deriving Repr
    inductive StmtV1 where
      | let_ (name : SourceNameComponentV1) (typeAnn : Option TypeV1) (value : ExprV1)
      | assign (target : PlaceV1) (value : ExprV1)
      | if_ (condition : ExprV1) (thenBlock : BlockV1) (elseBlock : Option BlockV1)
      | match_ (scrutinee : ExprV1) (arms : Array StmtMatchArmV1)
      | for_ (binder : SourceNameComponentV1) (start endExclusive : ExprV1)
          (bound : UInt32) (body : BlockV1)
      | assert_ (condition : ExprV1) (error : Option SourceNameComponentV1)
      | revert (error : SourceNameComponentV1) (args : Array ExprV1)
      | emit (event : SourceNameComponentV1) (args : Array ExprV1)
      | return_ (value : Option ExprV1)
      | call (call : ExternalCallExprV1)
      | schedule (call : ExternalCallExprV1)
      deriving Repr
    structure StmtMatchArmV1 where
      pattern : PatternV1
      body : BlockV1
      deriving Repr
    structure BlockV1 where
      statements : Array StmtV1
      deriving Repr
  end
  ```

  `AstSpineEqV1.lean` 仍在 `ProofForgeV2.Source.AstSpineV1` namespace 内公开精确七个
  `DecidableEq` instance：PlaceV1、ExprV1、ExprMatchArmV1、ExternalCallExprV1、StmtV1、
  StmtMatchArmV1、BlockV1。实现必须以 private mutual structural decision procedures 递归到
  SCC child、Array/List 与 Option；必须返回 `Decidable (a = b)` 并由 kernel 接受 totality。禁止只 deriving
  `BEq`、以 Bool 冒充 equality、`Classical.decEq`/`noncomputable`、`partial`、`unsafe`、fuel 或 codec bytes
  equality。pinned Lean 4.31 `/tmp` full probe 已实证 model 约 58 行、proof/instances 约 379 行并编译通过。

  RED 只 import model/equality 与既有 PA93–97 carriers，不 import codec/WireCodec。必须实例化完整 inventory：
  Place 3、Expr 7、Stmt 11、Block、StmtMatchArm、ExprMatchArm、ExternalCallExpr，共 25 constructors；并对
  七种类型各执行至少一个 `decide (a = b)` true 与一个 `decide (a ≠ b)` true。矩阵必须覆盖 Expr/Stmt
  array order与length不等、Let.typeAnn/If.elseBlock/Assert.error/Return.value 的 none/some、Constructor/
  LocalCall/ExternalCall args、两种 match arms、Call/Schedule nonalias、For bound value inequality，以及至少
  depth-3 Block→Stmt.If→Block deep equal/deep mismatch。raw `foo-bar` 与 two-component QID 必须通过既有
  typed parser构造；不得用 string cast 或 rendered name。该 model layer 故意允许 empty arrays 与任意
  UInt32 bound；对应 `Block`/Match nonempty、For 0..4096、QID-before-args wire错误属于后续 codec RED，
  本 slice 不得提前测试或实现。

  变更文件集：新增 `ProofForgeV2/Source/AstSpineV1.lean`、
  `ProofForgeV2/Source/AstSpineEqV1.lean`、`Tests/Language/SourceAstSpineV1.lean`；最小
  ProofForgeV2/Tests/lake registration 与机械 manifest refresh。budgets：model≤80、Eq≤400、suite≤260、
  registrations≤8、总 authored additions≤748（manifest 不计）。明确排除：任何 codec/wire/Python oracle、
  nonempty/bound/QID validation、Const/Invariant/Init/Entry/View/Fn、ProgramItem sum/Program root、alpha、
  decoder、global validator、sourceHash/NodeId/Common/ProgramPayload/target。验证只运行 focused+aggregate
  build/test binary、package refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与
  independent review；不运行完整 `just ci`。结果只记录 development evidence，不能关闭完整
  TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-100 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 mutual spine **codec-only** slice。它只消费
  PA99 已发布的 PlaceV1/ExprV1/StmtV1/BlockV1/StmtMatchArmV1/ExprMatchArmV1/ExternalCallExprV1，
  一次实现 `SPEC-SOURCE-WIRE-001` 对应完整 25-tag table，不修改 model/equality，也不引入 body-bearing
  ProgramItem。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineCodecV1
  encodePlaceV1 : PlaceV1 → Except String ByteArray
  encodeExprV1 : ExprV1 → Except String ByteArray
  encodeExprMatchArmV1 : ExprMatchArmV1 → Except String ByteArray
  encodeExternalCallExprV1 : ExternalCallExprV1 → Except String ByteArray
  encodeBlockV1 : BlockV1 → Except String ByteArray
  encodeStmtMatchArmV1 : StmtMatchArmV1 → Except String ByteArray
  encodeStmtV1 : StmtV1 → Except String ByteArray
  ```

  七个 public encoder 与其 private helpers 必须位于一个 kernel-total mutual family；Array recursive child
  必须先产生 ordered `ByteArray` chunks，再唯一调用 `encodeArray pure`，不得把 mutual encoder 作为
  higher-order 参数传给 `encodeArray`。`Stmt.If.elseBlock : Option BlockV1` 与
  `Stmt.Return.value : Option ExprV1` 必须手工写 `0x00`/`0x01 || child`；非 SCC 的 Let Type option 与
  Assert Ident option 可复用既有 `encodeOption`。Block/arms/ExternalCall structure 必须用 structural pattern
  使 termination checker 看见 child。禁止 `partial`、`unsafe`、fuel、model/Eq 修改或复制 Array wire。

  所有 tag、fieldCount 与 ordered fields 逐字复用 `SPEC-SOURCE-WIRE-001`：Place 3、Expr 7、Stmt 11、
  `Block`/`StmtMatchArm`/`ExprMatchArm`/`ExternalCallExpr` 4，共 25 tags。encoder-owned exact errors 固定为：

  - empty `Block.statements` → `block statements must be nonempty`
  - empty `Stmt.Match.arms` → `stmt match arms must be nonempty`
  - empty `Expr.Match.arms` → `expr match arms must be nonempty`
  - `Stmt.For.bound > 4096` → `for bound must be 0..4096`

  priority 精确冻结为：当前 constructor 的 local nonempty/bound check **先于所有 child**；local check成功后
  按 wire field order 左到右编码并原样传播 PA93–97 child error。故 empty Stmt/Expr Match 必须在 hostile
  scrutinee 前返回各自 arms error，For 4097 必须在 hostile binder/start/end/body 前返回 bound error。
  `Expr.Constructor` 先 `encodeSourceQualifiedIdV1 ctor` 再 args；`ExternalCallExpr` 先 QID callee 再 args，
  one-component QID + hostile `Literal.integer (2^256)` args 必须返回 PA94 QID error。不得 remap child error，
  不在本 slice 加 256-depth/100000-node/16-MiB global validator。

  Lean RED 与不 import Lean/ProofForge 的 Python oracle必须持有 checked-in expected hex；两者使用同一组
  typed logical fixtures但独立实现编码。至少 34 个 fixed expected-byte assertions，必须直接调用七个 public
  encoder，且完整覆盖 25 tags：Place Name/Field/nested Index；Expr Literal(含 `2^64`)/Place/Constructor
  some-one-arg与none-empty/Unary/Binary/LocalCall/Match-two-arms；Stmt Let type none/some、Assign、If else
  none/some、Match、For bound 0/4096、Assert error none/some、Revert empty/one-arg、Emit、Return none/some、
  Call、Schedule；direct Block single/multi、direct StmtMatchArm/ExprMatchArm/ExternalCallExpr。必须比较
  Constructor args `[a,b]`/`[b,a]` 与 Block statements normal/reversed exact byte nonalias，并覆盖四个 Option
  wire marker的 none/some。负例逐字包含 empty Block、empty Stmt Match、empty Expr Match、For 4097、
  Constructor one-component QID、ExternalCall one-component QID、两条 QID-before-hostile-args、arms/bound-
  before-hostile-child，以及至少一个既有 Literal/Pattern/Ident child error原样传播。Python另保持 raw closing-
  guillemet/Cc negatives；expected bytes不得由 production encoder生成。

  变更文件集：新增 `ProofForgeV2/Source/AstSpineCodecV1.lean`、
  `Tests/Language/SourceAstSpineCodecV1.lean`、`scripts/reference_source_ast_spine_v1.py`；最小
  ProofForgeV2/Tests/lake registration 与机械 manifest refresh。budgets：codec≤250、suite≤300、Python≤260、
  registrations≤8、总 authored additions≤818（manifest 不计）。明确排除：model/Eq/Common 修改、
  Const/Invariant/Init/Entry/View/Fn、ProgramItem sum/Program root、alpha、decoder、global validator、
  sourceHash/NodeId/ProgramPayload/target。验证只运行 focused+aggregate build/test binary、Python self-check、
  package refresh 后最终单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行
  完整 `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或
  下游 task。
- D1-PA-101 是 `TASK-D1-01`/`TST-SRC-001` 的 ProgramV1 complete spine-dependent declaration-record
  slice。closed-class rule 精确为 **all ProgramItem records whose ordered field types depend on the shipped
  Place/Expr/Stmt/Block spine**：`ConstDecl`、`InvariantDecl`、`InitDecl`、`EntryDecl`、`ViewDecl`、`FnDecl`
  六种；它们与 PA98 的七种 spine-independent records 合计 13/13 item alternatives。该 slice 只定义
  named records与各自 codec，不定义 `ProgramItemV1` sum 或 `Program` root。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineDeclV1
  structure ConstDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    type_ : AstV1.TypeV1
    value : AstSpineV1.ExprV1
    deriving DecidableEq, Repr
  structure InvariantDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    predicate : AstSpineV1.ExprV1
    deriving DecidableEq, Repr
  structure InitDeclV1 where
    params : Array AstSupportV1.ParamV1
    body : AstSpineV1.BlockV1
    deriving DecidableEq, Repr
  structure EntryDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    params : Array AstSupportV1.ParamV1
    result : AstV1.TypeV1
    body : AstSpineV1.BlockV1
    deriving DecidableEq, Repr
  structure ViewDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    params : Array AstSupportV1.ParamV1
    result : AstV1.TypeV1
    body : AstSpineV1.BlockV1
    deriving DecidableEq, Repr
  structure FnDeclV1 where
    name : NameComponentV1.SourceNameComponentV1
    params : Array AstSupportV1.ParamV1
    result : AstV1.TypeV1
    body : AstSpineV1.BlockV1
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstSpineDeclCodecV1
  encodeConstDeclV1 : ConstDeclV1 → Except String ByteArray
  encodeInvariantDeclV1 : InvariantDeclV1 → Except String ByteArray
  encodeInitDeclV1 : InitDeclV1 → Except String ByteArray
  encodeEntryDeclV1 : EntryDeclV1 → Except String ByteArray
  encodeViewDeclV1 : ViewDeclV1 → Except String ByteArray
  encodeFnDeclV1 : FnDeclV1 → Except String ByteArray
  ```

  wire tag、field count 与顺序必须逐字为：`ConstDecl`/3 = raw Ident、Type、Expr；
  `InvariantDecl`/2 = raw Ident、Expr；`InitDecl`/2 = Array Param、Block；`EntryDecl`/4、`ViewDecl`/4、
  `FnDecl`/4 = raw Ident、Array Param、Type result、Block。六个 encoder 均为 total `def`，只组合 PA93–100
  已发布 codec；Param arrays 唯一复用 `encodeArray encodeParamV1`。该 slice **不新增任何 local validation
  或 error string**：所有 params（包括 Init/Entry/View/Fn）允许 empty，View 的 empty-params fixture必须成功；
  empty body 只由 `encodeBlockV1` 返回 `block statements must be nonempty`。Type/Expr/Param/Block child error
  必须按上述 wire field order原样传播。duplicate declarations、zero entry/view、multiple init、proof-invariant
  binding 与 256-depth/100000-node/16-MiB 限制属于 future Program/set-level validator，不得下沉到 record codec。

  Lean RED 与不 import Lean/ProofForge 的 Python oracle必须使用同一组 hand-built typed logical fixtures并
  持有 checked-in expected hex，golden 不得由 production encoder生成。exact 七个 positive goldens 为：
  `Const max : UInt256 = Integer 4096`；`Invariant bounded = Binary Lt (Place.Name count) (Integer 4096)`；
  `Init` params `[Public start UInt64, Private secret Field bn254_fr]` + `Block[Assign count 1]`；
  `Entry run` params `[Public to Principal, Private amount UInt64, Commitment note Bytes0]`、result UInt64、
  `Block[Return some (Place.Name count)]`；同一 Entry 的 first-two-param swap
  `[Private amount UInt64, Public to Principal, Commitment note Bytes0]`；`View get` empty params、result UInt64、
  `Block[Return some Integer 0]`；`Fn helper2` param `[Public x UInt64]`、result Unit、
  `Block[If true then Block[Return none] else none]`。必须直接调用六个 public encoder；对六种 record各执行
  derived equality true/false；Entry normal/swapped params须同时 byte 与 DecidableEq nonalias；另构造字段完全
  相同的 Entry/View并证明 tag bytes nonalias。

  Lean exact negatives只允许既有 child errors：Const 的 UInt24 + hostile Integer `2^256` 必须先返回
  `integer width must be one of 8,16,32,64,128,256`；valid UInt256 + hostile value与 Invariant hostile predicate
  均返回 `u256 magnitude exceeds 2^256-1`；Init empty body返回 PA100 block error；Entry 的首个 Param 使用
  `Type.Field bad_fr`，同时 result UInt24、body empty，必须先返回 `field id must be bn254_fr`；View empty
  params + UInt24 result + empty body必须先返回 width error；Fn valid fields + empty body返回 block error。
  私有构造的 SourceNameComponent carrier已在 PA93 validation boundary保证合法，本 slice禁止用 unsafe/伪造
  carrier制造不可达 name-error priority。Python另在其独立 raw encoder边界保留 closing-guillemet/Cc negatives。

  变更文件集：新增 `ProofForgeV2/Source/AstSpineDeclV1.lean`、
  `ProofForgeV2/Source/AstSpineDeclCodecV1.lean`、`Tests/Language/SourceAstSpineDeclV1.lean`、
  `scripts/reference_source_ast_spine_decl_v1.py`；最小 ProofForgeV2/Tests/lake registration 与机械 manifest
  refresh。budgets：model≤60、codec≤90、suite≤200、Python≤160、registrations≤8、总 authored
  additions≤520（manifest 不计）。明确排除：`ProgramItemV1` sum/Program root、alpha Source/Syntax/Loader/
  projection、decoder、global/set validator、sourceHash/NodeId、Common/ProgramPayload/target edits。验证只运行
  focused+aggregate build/test binary、Python self-check、package refresh 后最终单次 `just sbom`、
  `just docs-check`、`git diff --check` 与 independent review；不运行完整 `just ci`。结果只记录 development
  evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-102 是 `TASK-D1-01`/`TST-SRC-001` 的 complete `ProgramItemV1` sum/codec slice。closed class
  精确为 PA98+PA101 已发布的全部 13 种 item-record types，constructor 顺序逐字对齐 wire table与
  `WireV1.isProgramItemTag`：State、Struct、Enum、Const、Event、Error、Init、Entry、View、Fn、Invariant、
  ExtensionReq、Proof。禁止定义只含子集的 incomplete sum。`SPEC-SOURCE-WIRE-001` 冻结
  **ProgramItem 没有额外 wrapper tag**；item encoder只按 constructor dispatch到已发布 record encoder，
  输出必须逐 byte等于 direct record encoding，不得调用 `encodeTagged "ProgramItem"`、重编码字段或加入
  validation。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstProgramItemV1
  inductive ProgramItemV1 where
    | state : AstDeclV1.StateDeclV1 → ProgramItemV1
    | struct : AstDeclV1.StructDeclV1 → ProgramItemV1
    | enum : AstDeclV1.EnumDeclV1 → ProgramItemV1
    | const : AstSpineDeclV1.ConstDeclV1 → ProgramItemV1
    | event : AstDeclV1.EventDeclV1 → ProgramItemV1
    | error : AstDeclV1.ErrorDeclV1 → ProgramItemV1
    | init : AstSpineDeclV1.InitDeclV1 → ProgramItemV1
    | entry : AstSpineDeclV1.EntryDeclV1 → ProgramItemV1
    | view : AstSpineDeclV1.ViewDeclV1 → ProgramItemV1
    | fn : AstSpineDeclV1.FnDeclV1 → ProgramItemV1
    | invariant : AstSpineDeclV1.InvariantDeclV1 → ProgramItemV1
    | extensionReq : AstDeclV1.ExtensionReqV1 → ProgramItemV1
    | proof : AstDeclV1.ProofDeclV1 → ProgramItemV1
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstProgramItemCodecV1
  encodeProgramItemV1 : AstProgramItemV1.ProgramItemV1 → Except String ByteArray
  ```

  `encodeProgramItemV1` 必须为 single total `def`，13 arms精确调用对应
  `encodeStateDeclV1`/`encodeStructDeclV1`/`encodeEnumDeclV1`/`encodeConstDeclV1`/
  `encodeEventDeclV1`/`encodeErrorDeclV1`/`encodeInitDeclV1`/`encodeEntryDeclV1`/
  `encodeViewDeclV1`/`encodeFnDeclV1`/`encodeInvariantDeclV1`/`encodeExtensionReqV1`/
  `encodeProofDeclV1`。constructor names固定为上表短名，包括可由 Lean 4.31 实编译的 `struct`、`enum`、
  `const`、`error`、`init`、`fn`；RED/GREEN不得自行加下划线或改变 order。该 slice没有 local error、
  tag或 field encoder；所有 PA98/PA101 child errors未经 remap传播。

  Lean RED 与不 import Lean/ProofForge 的 standalone Python oracle必须持有 13 个 checked-in expected hex，
  expected不得由 production encoder或运行时读取其他 reference scripts生成。logical fixtures精确复用：
  `item_state` = PA98 `state_enabled_public_bool`；`item_struct` = `struct_store_single`；`item_enum` =
  `enum_choice`；`item_const` = PA101 `const_max`；`item_event` = `event_ping_empty`；`item_error` =
  `error_empty`；`item_init` = `init_two_params`；`item_entry` = `entry_run`；`item_view` =
  `view_get_empty`；`item_fn` = `fn_helper2`；`item_invariant` = `invariant_bounded`；`item_extension_req` =
  PA98 `ext_feature`；`item_proof` = `proof_safe`。每个 Lean case必须同时断言 fixed hex与
  `encodeProgramItemV1 (.ctor payload) = encodeXxxDeclV1 payload`，以直接证明 no-wrapper byte identity；
  Python对同一 13 labels实现独立 no-wrapper dispatch并固定同一 hex。

  equality必须对 13 constructors各执行 self-equal，并至少对 same payload shape的两组 alternative执行
  cross-constructor inequality。alias groups精确为：Event/Error使用完全相同 name/params时 item bytes不相等；
  Entry/View/Fn使用完全相同 name/params/result/body时三者 pairwise不相等，且相应 ProgramItem values由
  `DecidableEq` 判定不同。负例只通过 pure dispatch传播既有 exact errors：Struct empty fields →
  `struct fields must be nonempty`；Const UInt24 + hostile value → width error优先；Init empty body →
  `block statements must be nonempty`；Extension one-component QID + hostile version/digest → PA94 QID count
  error优先。禁止新增 ProgramItem-local error。Python不必重复 PA93 raw-name negatives，因为本 slice没有新
  Ident boundary。

  变更文件集：新增 `ProofForgeV2/Source/AstProgramItemV1.lean`、
  `ProofForgeV2/Source/AstProgramItemCodecV1.lean`、`Tests/Language/SourceAstProgramItemV1.lean`、
  `scripts/reference_source_ast_program_item_v1.py`；最小 ProofForgeV2/Tests/lake registration 与机械
  manifest refresh。budgets：model≤45、codec≤60、suite≤230、Python≤170、registrations≤8、总 authored
  additions≤515（manifest 不计）。明确排除：Program root/items Array与 items-nonempty、program identity
  join、duplicate/zero-entry-view/multiple-init/proof-invariant set validation、alpha Source/Syntax/Loader/
  projection、decoder、global validator、sourceHash/NodeId、Common/ProgramPayload/target edits。验证只运行
  focused+aggregate build/test binary、Python self-check、package refresh 后最终单次 `just sbom`、
  `just docs-check`、`git diff --check` 与 independent review；不运行完整 `just ci`。结果只记录 development
  evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-103 是 `TASK-D1-01`/`TST-SRC-001` 的 `Program` tagged-value slice，而不是完整 canonical root
  slice。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstProgramV1
  structure ProgramV1 where
    name : NameComponentV1.SourceNameComponentV1
    items : Array AstProgramItemV1.ProgramItemV1
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstProgramCodecV1
  encodeProgramV1 : AstProgramV1.ProgramV1 → Except String ByteArray
  ```

  `encodeProgramV1` 必须为 single total `def`。它首先检查 `items.size ≥ 1`，失败 exact 返回
  `program items must be nonempty`；该 local shape check 必须位于 name/item child encoding 之前。成功路径
  精确为 `nameB ← encodeSourceNameComponentV1 p.name`、
  `itemsB ← encodeArray encodeProgramItemV1 p.items`、
  `encodeTagged "Program" #[nameB, itemsB]`。tag 为 ASCII `Program`、fieldCount 为 2、items保持 source
  order且每个 item继续使用 PA102 no-wrapper bytes；不得重编码 alternative、remap child error或加入
  declaration-set walk。

  Lean RED 与不 import Lean/ProofForge、也不在运行时读取前序 reference scripts 的 standalone Python
  oracle必须各自持有相同的三个 checked-in lowercase expected hex literal，expected不得由 production或
  oracle自身在 self-check 时生成：`prog_state_only` = name `Demo` + `[item_state]`；
  `prog_two_order` = `Demo` + `[item_state,item_const]`；`prog_two_reversed` = `Demo` +
  `[item_const,item_state]`。`item_state` 精确复用 PA102 `state_enabled_public_bool` payload，`item_const`
  精确复用 `const_max` payload。三例均断言 fixed hex；ordered/reversed必须 byte nonalias，Program derived
  equality必须覆盖 self true与 order-swapped false。Lean另以现有 primitive/item encoders断言 Program/2
  composition，防止偷偷前置 module/identity bytes或 outer wrapper。

  负例精确冻结为：empty items → `program items must be nonempty`；single Struct empty fields →
  `struct fields must be nonempty`；single Const UInt24 + hostile `2^256` value → width error优先；valid state
  first + empty Struct second →第二 item 的 struct error，证明 array source order与 child propagation。
  `prog_state_only` 虽没有 Entry/View仍必须在该 mechanical codec boundary成功，以证明 serializer没有混入
  `SPEC-LANG-001` set validator；这不声明该 value 已通过完整 invariant validator或可进入编译管线。

  明确排除 canonical root `encodeSourceNameArray(moduleName) ‖ encodeSourceNameArray(programIdentity) ‖
  encodeProgramV1(program)`、module/program identity count/prefix join、`program.name` 与 identity 最后 raw
  component equality、duplicate/zero-entry-view/multiple-init/proof-invariant set validation、alpha Source/Syntax/
  Loader/projection、decoder、global depth/node/16-MiB validator、sourceHash/NodeId、Common/ProgramPayload/target。
  变更文件集：新增 `ProofForgeV2/Source/AstProgramV1.lean`、
  `ProofForgeV2/Source/AstProgramCodecV1.lean`、`Tests/Language/SourceAstProgramV1.lean`、
  `scripts/reference_source_ast_program_v1.py`；最小 ProofForgeV2/Tests/lake registration与机械 manifest。
  budgets：model≤30、codec≤35、suite≤160、Python≤110、registrations≤6、总 authored additions≤345
  （manifest不计）。验证只运行 focused+aggregate build/test binary、Python self-check、package refresh 后最终
  单次 `just sbom`、`just docs-check`、`git diff --check` 与 independent review；不运行完整 `just ci`。
  结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending TASK-D1-01 或下游 task。
- D1-PA-104 是 `TASK-D1-01`/`TST-SRC-001` 的 canonical-root encoder slice，只闭合 v1 root 的
  source-only identity join 与三段串接。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstCanonicalRootV1
  canonicalSourceAstBytesV1
    (moduleName programIdentity : QualifiedNameV1.SourceQualifiedNameV1)
    (program : AstProgramV1.ProgramV1) : Except String ByteArray
  ```

  该 API 必须为 single total `def`，且顺序不可交换：先调用
  `validateSourceProgramIdentityV1 moduleName programIdentity`；再以 total、无 `partial`/`unsafe`/bang index
  的方式取 `programIdentity` 最后一个 raw `SourceNameComponentV1`；若它与 `program.name` 不等，exact
  返回 `program name must equal the last program identity component`；之后依次调用
  `encodeSourceQualifiedNameV1 moduleName`、`encodeSourceQualifiedNameV1 programIdentity`、
  `encodeProgramV1 program`，最后无间隔串接三段。root 不得增加 outer tag、field count、magic、schema、
  source path 或 trailing bytes，也不得把 source carrier改成 common `QualifiedName`。

  Lean RED 与不 import Lean/ProofForge、也不在运行时读取前序 reference scripts 的 standalone Python
  oracle必须各自持有相同的三个 checked-in lowercase full-root expected hex literal；expected不得由
  production或 oracle自身在 self-check 时生成：`root_state_ok` = module `Root`、identity `Root.Demo`、
  Program name `Demo` + `[item_state]`；`root_two_order` = 同 identity + `[item_state,item_const]`；
  `root_deep_mod` = module `A.B`、identity `A.B.Main`、Program name `Main` + `[item_state]`。
  `item_state`/`item_const`精确复用 PA103 payload。三例均断言 full fixed hex及
  `encodeSourceQualifiedNameV1(moduleName) ‖ encodeSourceQualifiedNameV1(programIdentity) ‖
  encodeProgramV1(program)` direct composition；至少一例断言 root 以 module array bytes 开始且不以
  `Program` tag prefix开始。shallow order与 deep component order不可被排序或 rendered spelling替换。

  负例与 exact priority冻结为：一 component identity首先返回
  `source qualified id must contain 2..256 components`；二 component module与 identity相等返回
  `program identity must strictly extend the module name`；non-prefix返回
  `program identity must begin with the exact module name components`；bad join + wrong name + empty items仍由
  join error优先；good join + wrong name + empty items由新的 name mismatch优先；good join/name + empty items
  传播 `program items must be nonempty`；good join/name + empty Struct item传播
  `struct fields must be nonempty`；good join/name + single Const UInt24 + hostile `2^256` value仍由 width error
  优先。`root_state_ok`没有 Entry/View仍必须成功，只证明 mechanical root
  boundary没有混入 `SPEC-LANG-001` set validator，不声明该 root业务有效或可进入编译管线。

  `SPEC-SOURCE-WIRE-001` production boundary继续规定最终 API返回 `Except Diagnostic`；本 pre-acceptance
  slice 的 `Except String` 只是尚未完成 `TASK-D1-07` 的 development seam。上述 exact String只冻结本切片
  的错误优先级和 fail-closed行为，不得声明为最终 stable diagnostic schema。

  变更文件集：新增 `ProofForgeV2/Source/AstCanonicalRootV1.lean`、
  `Tests/Language/SourceAstCanonicalRootV1.lean`、`scripts/reference_source_ast_canonical_root_v1.py`；最小
  ProofForgeV2/Tests/lake registration与机械 manifest。budgets：codec≤60、suite≤200、Python≤150、
  registrations≤5、总 authored additions≤415（manifest不计）。明确排除 duplicate identifiers、
  zero Entry/View、multiple Init、proof/invariant reference等 declaration-set validation；alpha Source/Syntax/
  Loader/projection；decoder、exact-consume、global depth/node/16-MiB resource validator；sourceHash、NodeId、
  stable Diagnostic implementation、Common/ProgramPayload与 target edits。验证只运行 focused+aggregate
  build/test binary、Python self-check、package refresh后最终单次 `just sbom`、`just docs-check`、
  `git diff --check`与 independent review；不运行完整 `just ci`。结果只记录 development evidence，不能
  关闭完整 TST-SRC-001、pending TASK-D1-01或下游 task。
- D1-PA-105 是 `TASK-D1-01`/`TST-SRC-001` 的 complete residual `ProgramV1` declaration-set validator
  slice。它实现 `SPEC-LANG-001` 已固定顺序的 count/uniqueness/proof-name binding 与 per-record duplicate
  规则，但不重复 PA98/PA100/PA101 codec 已拥有的 struct fields、enum variants、Block/fn body nonempty等
  local shape checks。生产 public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstProgramValidateV1
  validateProgramDeclSetV1
    (program : AstProgramV1.ProgramV1) : Except String Unit
  ```

  该 API 必须为 single public total `def`，禁止 `partial`/`unsafe`/bang index与 quadratic duplicate scan；
  duplicate/membership使用 `Std.HashSet`或等价 O(n) expected-time closed implementation。raw Ident key精确为
  `SourceNameComponentV1.raw`；extension identity key精确比较完整 ordered raw component array，不比较 rendered
  spelling，也不把 version/digest并入 uniqueness key。所有 rules先在完整 `program.items` 上按下列**规则类别
  固定顺序**执行；类别内第一个 source-order offender获胜，禁止按 alpha bucket实现顺序或跨类别最早 item
  改写优先级：

  1. 第二个 `init`；
  2. zero `entry`/`view`；
  3. state names；
  4. entry/view names的 combined namespace；
  5. event；6. error；7. struct；8. enum；9. const；10. fn names；
  11. entry/view/fn callable combined namespace；
  12. invariant names；13. extension identities；14. proof target cardinality；
  15. proof target exact membership in the full invariant-name set；
  16. initializer params；17. per-struct fields；18. per-enum variants；19. per-event params；
  20. per-error params；21. entry/view params（combined source-order walk，variant-specific error）；
  22. fn params。

  proof membership必须先建立全 program invariant set，允许 `proof` 位于其 `invariant` 之前；duplicate proof
  target必须先于 unknown binding。这里只做 raw invariant-name membership，不做 invariant Bool typing、theorem
  lookup/signature、qualified theorem resolution或 proof environment load。exact pre-acceptance String inventory为
  23 slots（第 21 类有 entry/view 两个 variant-specific slots）：

  ```text
  program must declare at most one init
  program must declare at least one entry or view
  program contains duplicate state declarations
  program contains duplicate entry/view declarations
  program contains duplicate event declarations
  program contains duplicate error declarations
  program contains duplicate struct declarations
  program contains duplicate enum declarations
  program contains duplicate const declarations
  program contains duplicate fn declarations
  program contains duplicate callable declarations
  program contains duplicate invariant declarations
  program contains duplicate extension requirements
  program contains duplicate proof references
  proof reference names unknown invariant '<raw>'
  initializer contains duplicate parameters
  struct '<raw>' contains duplicate fields
  enum '<raw>' contains duplicate variants
  event '<raw>' contains duplicate parameters
  error '<raw>' contains duplicate parameters
  entry '<raw>' contains duplicate parameters
  view '<raw>' contains duplicate parameters
  fn '<raw>' contains duplicate parameters
  ```

  `<raw>`逐字替换为对应 raw component，不用 `Name.toString`/guillemet renderer。最终 production boundary仍由
  `TASK-D1-07`迁移为 stable `Diagnostic`；这些 String只冻结 development seam的 first-error行为，不声明最终
  diagnostic schema。

  Lean RED与不 import Lean/ProofForge、也不在运行时读取前序 reference scripts的 standalone Python oracle
  必须使用同一 case inventory：至少三个 positives——all-category unique program、proof-before-invariant forward
  binding、view-only callable；23 个 per-slot negatives逐项固定上述 exact String；七个 cross-rule priorities至少
  覆盖 init duplicate→zero callable、zero callable→state duplicate、state→entry/view duplicate、event→struct、
  fn duplicate→callable collision、state duplicate→unknown proof、duplicate proof→unknown proof。最后一例必须用
  **同一 invariant target的两个 proofs**，不得用两个不同 unknown targets伪装 cardinality。entry↔view同名必须
  在第 4 类失败，entry/view↔fn同名必须在第 11 类失败；same extension id即使 version/digest不同仍在第 13 类
  失败。

  encoder/validator必须保持正交：至少一个含 duplicate state且含合法 entry的 Program必须继续由
  `encodeProgramV1`成功产生 bytes，同时 `validateProgramDeclSetV1`返回第 3 类错误；禁止把本 validator塞入
  `encodeProgramV1`或 `canonicalSourceAstBytesV1`，也禁止 serializer修复、排序或丢弃 invalid set。

  变更文件集：新增 `ProofForgeV2/Source/AstProgramValidateV1.lean`、
  `Tests/Language/SourceAstProgramValidateV1.lean`、`scripts/reference_source_ast_program_validate_v1.py`；最小
  ProofForgeV2/Tests/lake registration与机械 manifest。budgets：validator≤180、suite≤280、Python≤185、
  registrations≤5、总 authored additions≤650（manifest不计）。明确排除 alpha `Source.Program` adapter/
  `validateDecodedProgram` reuse、codec/root改写、local nonempty重检、decoder/exact-consume、global
  depth/node/16-MiB validator、sourceHash、NodeId、D2 type/effect/name/theorem resolution、stable Diagnostic
  implementation、Common/ProgramPayload与 target edits。验证只运行 focused+aggregate build/test binary、
  Python self-check、package refresh后最终单次 `just sbom`、`just docs-check`、`git diff --check`与 independent
  review；不运行完整 `just ci`。结果只记录 development evidence，不能关闭完整 TST-SRC-001、pending
  TASK-D1-01或下游 task。
- D1-PA-106 是 `TASK-D1-01`/`TST-SRC-001` 的 complete nonrecursive tagged-scalar decoder slice。它只闭合
  PA95 中不递归、非 NodeId-node 的 `VisibilityV1`、`LiteralV1`、`UnaryOpV1`、`BinaryOpV1` 共27个tag，
  不解码递归 `TypeV1`。生产 public API精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.WireDecodeV1
  decodeTagV1 : DecoderV1 String
  decodeFieldCountV1 (tag : String) (expected : Nat) : DecoderV1 Unit

  namespace ProofForgeV2.Source.AstScalarDecodeV1
  decodeVisibilityV1 : DecoderV1 AstV1.VisibilityV1
  decodeLiteralV1 : DecoderV1 AstV1.LiteralV1
  decodeUnaryOpV1 : DecoderV1 AstV1.UnaryOpV1
  decodeBinaryOpV1 : DecoderV1 AstV1.BinaryOpV1
  ```

  `decodeTagV1`先读u32 length，并在读取、复制或构造tag前 exact要求`1..21`；21是v1 closed constructor
  inventory的最大ASCII tag长度。length在范围内还必须先检查remaining，随后strict UTF-8并拒绝任一非ASCII
  scalar。exact errors为`tag length must be 1..21 bytes`、`truncated`、`invalid UTF-8 tag`、
  `tag must be ASCII`。禁止bang index、unbounded copy、partial/unsafe。

  四个family decoder先调用`decodeTagV1`并立即按各自closed tag set dispatch；unknown tag必须在读取
  fieldCount前返回`unknown <family> tag '<tag>'`，其中family逐字为`visibility`、`literal`、`unary-op`、
  `binary-op`。known tag才由`decodeFieldCountV1`读取u16并exact校验；失败逐字为
  `tag '<tag>' must declare <expected> fields`，且必须先于任何child decoder。Visibility/Unary/Binary均为
  0 fields；Literal.Bool/Integer/String均为1 field并分别复用`decodeBool`、`decodeU256le`、`decodeString`，
  child错误原样传播。component decoder保留推进后的cursor；只有测试/未来root调用`finish`执行exact consume。

  Lean RED与不import Lean/ProofForge或前序reference脚本的standalone Python oracle使用同一固定inventory：
  27个PA95 checked-in wire literals逐一decode为exact value、重新encode回同一bytes并`finish`；每个nullary tag
  有fieldCount=1 negative，每个Literal tag各有fieldCount=0/2 negatives，共30；四个canonical sibling tag
  分别送入错误family且故意省略fieldCount，证明unknown-before-count；这四例同时就是14个boundary中的
  four-family nonalias，不另增加测试数。其余10个boundary为empty/22-byte/truncated/invalid-UTF-8/non-ASCII
  tag，Bool marker 2、truncated u256、String length over remaining/NFD与trailing byte。LogicalOr与BitOr必须
  保持value/bytes nonalias。Python self-check成功输出
  `reference_source_ast_scalar_decode_v1: ok 27 30 14`。

  变更文件集：新增`ProofForgeV2/Source/AstScalarDecodeV1.lean`、
  `Tests/Language/SourceAstScalarDecodeV1.lean`、`scripts/reference_source_ast_scalar_decode_v1.py`；只允许为
  reusable tag API最小修改`WireDecodeV1.lean`，再做ProofForgeV2/Tests/lake registration与机械manifest。
  budgets：production additions≤170、suite≤260、Python≤190、registrations≤5、总authored additions≤625
  （manifest不计）。明确排除Type/Pattern/spine/support/declaration/Program/root decoder、recursive
  `DecodeBudgetV1`、16MiB/256-depth/100000-node完成声明、alpha projection/sourceHash、set validator重检、
  stable Diagnostic、Common/ProgramPayload、hash/NodeId与target。验证只运行focused+aggregate build/test binary、
  Python self-check、package refresh后最终单次`just sbom`、`just docs-check`、`git diff --check`与independent
  review；不运行完整`just ci`。结果只记录development evidence，不能关闭完整TST-SRC-001、pending
  TASK-D1-01或下游task。
- D1-PA-107 是 `TASK-D1-01`/`TST-SRC-001` 的 complete recursive `TypeV1` decoder slice。它新增可由
  后续完整AST decoder组合的node-budget carrier，但不创建完整Program session，也不声明全树资源限制已完成。
  生产public API精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.DecodeBudgetV1
  structure DecodeBudgetV1 where
    remainingNodes : Nat
    deriving DecidableEq, Repr

  namespace ProofForgeV2.Source.AstTypeDecodeV1
  decodeTypeV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstV1.TypeV1 × DecodeBudgetV1)
  ```

  production不得提供hardcode/fresh `{remainingDepth := 256, remainingNodes := 100000}` 的Type-root
  convenience或默认参数；standalone测试直接构造literal budget。未来完整Program decoder必须只在Program根
  创建一次全局额度，再把同一`remainingNodes`跨全部node-bearing values按canonical preorder线程。
  `DecodeBudgetV1`只是trusted internal caller-threaded residual，不是authority或user-configurable profile；
  source/CLI/extension/target不得提供或放宽它，完整root接入前也不得据此声明100000-node限制已闭合。
  `remainingDepth`是当前node可使用的root-inclusive path slots，属于caller参数而非返回state：进入任一Type
  需要`remainingDepth ≥ 1`，recursive child取得`remainingDepth - 1`；siblings取得同一个child depth。
  `remainingNodes`是session-wide residual，进入每个Type constructor恰好消耗1并在返回值中永久保留；scalar
  width/length/Ident不消耗depth或node。成功返回的budget只改变`remainingNodes`，从结构上避免恢复depth时
  污染Map sibling；失败经`Except`不返回partial value/cursor/budget。

  decoder必须是以`remainingDepth : Nat`作structural fuel的kernel-total `def`，不得使用`partial`、`unsafe`、
  无界递归或构造完整Type后事后walk。每个node的exact validation priority为：`decodeTagV1`的bounded read →
  closed 11-tag dispatch（unknown为`unknown type tag '<tag>'`，先于fieldCount）→
  `decodeFieldCountV1` exact → depth entry check → node charge → ordered fields/children → constructor。
  exact budget errors为`depth budget exhausted`与`node budget exhausted`；depth与node同时为0时depth优先。
  Array必须完整解码element后再读/校验length；Map按key再value，两个child共享相同depth但value接收key消费后的
  node residual。width、Array/Bytes length与Field id继续原样使用PA95 exact errors；Ident复用
  `decodeSourceNameComponentV1`，所有primitive/truncation errors不remap。PA107同时修复该既有Ident helper的
  allocation order：先读u32 declared length，立即以`source name component must contain 1..240 UTF-8 bytes`
  拒绝0/241+，再检查remaining并复制最多240 bytes，随后才做UTF-8、pinned NFC、Cc/closing-guillemet与
  typed carrier构造；不得先调用unbounded `decodeString`复制后再由`parseSourceNameComponentV1`事后拒绝。

  11 tags精确为Bool/UInt/Int/Principal/Unit/Named/Array/Map/Option/Bytes/Field；field counts分别是
  3个nullary、6个one-field、2个two-field。Lean RED与不import Lean/ProofForge或前序reference脚本的standalone
  Python oracle必须共同固定：

  - 24个PA95 checked-in Type wire literals逐一decode为exact value、重新encode为同一bytes、`finish`，并核对
    每例精确node消耗（leaf=1、Map(Bool,Unit)=3、Array(Bool)=2、Array(Option(Bytes))=3等）；
  - 19个exhaustive field-count negatives：3个nullary各用1，6个one-field各用0/2，Array/Map各用1/3；
  - 24个boundary：wrong-family tag无fieldCount且在zero budgets下仍先unknown；known wrong fieldCount先于
    budgets；correct fieldCount后的depth-before-node与两者各自before-payload；UInt24、Int0、Array4097、
    Bytes4097、wrong Field；missing fieldCount、truncated width、truncated Array child、trailing；Bool exact
    `(depth=1,nodes=1)`、Option(Bool) exact/pass与depth-short fail、Map(Bool,Unit) nodes2 fail/nodes3 pass、
    Array bad-element优先于hostile length、Map bad-key优先于hostile value；`Option^255(Bool)`恰为256个
    Type nodes并在`depth=256,nodes=256`通过，`Option^256(Bool)`在`depth=256,nodes=257`返回depth error；
    Type.Named declared Ident length 241且不附payload时必须在remaining/copy前返回exact 1..240 error。

  Python成功输出`reference_source_ast_type_decode_v1: ok 24 19 24`。变更文件集：新增
  `ProofForgeV2/Source/DecodeBudgetV1.lean`、`ProofForgeV2/Source/AstTypeDecodeV1.lean`、
  `Tests/Language/SourceAstTypeDecodeV1.lean`、`scripts/reference_source_ast_type_decode_v1.py`；仅允许为上述
  Ident pre-copy bound最小修改`WireDecodeV1.decodeSourceNameComponentV1`，再做`ProofForgeV2.lean`/
  `Tests.lean`/`lakefile.lean` registration与机械manifest refresh；不修改PA95 encoder、PA106 scalar/tag
  decoder或其他AST modules。budgets：production additions≤190、suite≤340、Python≤260、
  registrations≤5、总authored additions≤800（manifest不计）。明确排除Pattern/spine/support/declaration/
  Program/root decoder、fresh root budget API、16MiB/完整100000-node/256-depth session完成声明、alpha、set
  validator重检、sourceHash、NodeId、stable Diagnostic、Common/ProgramPayload与target。验证只运行focused+
  aggregate build/test binary、Python self-check、package refresh后最终单次`just sbom`、`just docs-check`、
  `git diff --check`与independent review；不运行完整`just ci`。结果只记录development evidence，不能关闭
  完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-108 是 `TASK-D1-01`/`TST-SRC-001` 的 validated ProgramV1 source-unit/sourceHash boundary
  slice，也是`ADR-0019`单轨cutover的第一段代码基础。production API精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.ValidatedSourceV1
  structure ValidatedSourceV1 where
    private mk ::
    moduleName : SourceQualifiedNameV1
    programIdentity : SourceQualifiedNameV1
    program : ProgramV1

  validateSourceV1 (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String ValidatedSourceV1
  canonicalValidatedSourceAstBytesV1
    (source : ValidatedSourceV1) : Except String ByteArray
  sourceHashV1 (source : ValidatedSourceV1) : Except String Digest
  ```

  `validateSourceV1`先调用既有`canonicalSourceAstBytesV1`，固定identity join→program name→codec-local
  shape/child error priority，再调用`validateProgramDeclSetV1`，成功后才调用private constructor。
  `canonicalValidatedSourceAstBytesV1`只接受validated unit并按其三个projection调用同一root codec；
  `sourceHashV1`只接受validated unit，复用该canonical projection并精确计算
  `domainSeparatedSha256 "pf.source.v1" bytes`，返回Common `Digest`。结构不存bytes/hash/cache，禁止把
  validated unit与另一组raw triple的hash配对；NodeId仍独立。

  Lean tests与不import Lean/ProofForge的standalone Python oracle必须共同固定：一个State→Entry valid
  source unit的literal expected canonical bytes与literal `sha256:<64 lowercase hex>`，并核对返回unit三个
  projections与inputs exact相等；module identity、program identity/name、cross-kind item order使用各自仍合法
  的twins，canonical bytes与hash都必须不同；Common Digest 32-byte/render roundtrip。wrong prefix、wrong
  program name、codec-local empty Block、zero entry/view、duplicate state五类exact negatives必须证明
  `validateSourceV1`不返回unit；local-shape+set同时错误时codec-local优先。Python oracle不得只从runtime
  bytes重新接受runtime hash，成功输出`reference_source_ast_canonical_root_v1: ok 4 1`。

  变更文件集：新增`ProofForgeV2/Source/ValidatedSourceV1.lean`；只扩展
  `Tests/Language/SourceAstCanonicalRootV1.lean`与
  `scripts/reference_source_ast_canonical_root_v1.py`；再做`ProofForgeV2.lean`注册与机械manifest refresh。
  production additions≤70、Lean additions≤130、Python additions≤90、registrations≤2、总authored≤292
  （manifest不计）。明确排除parser/Syntax、Loader/CLI、ProgramExport/ProgramPayload、legacy adapter、
  Typed/Semantic、full Program decoder、NodeId、stable Diagnostic与target。验证只运行focused+aggregate+
  test binary、Python、package refresh后最终单次`just sbom`、`just docs-check`、`git diff --check`与
  independent review；不运行完整`just ci`，不关闭formal TASK-D1-01。
- D1-PA-109 是 `ADR-0019` step-2 的 compiler-private one-way Typed lowering pre-cutover slice。
  `Compiler.compileValidatedSourceV1 : ValidatedSourceV1 → CompileResult Semantic.Program`是唯一新增public
  API；既有`compile(Source.Program)`行为与call sites不变，全部lowering helper必须留在Pipeline内且为
  private。private lowering不得调用validator、canonical encoder、`sourceHashV1`、legacy builder或
  legacy canonical/hash API；它只接收
  state/init/entry/view、完整可映射legacy value type（field仅`bn254_fr`）、UInt64 integer/name-place/add、
  simple-name assign、value return、零参数external call。source-order第一个unsupported top-level item、
  constructor-before-child、nonempty-call-args-before-arg traversal为固定错误优先级。遍历精确为items/
  arrays/block source order、record/wire field order、add lhs→rhs、assign target→value；必须完成全部lowering
  后才调用Typed，Typed成功后才各调用一次`sourceHashV1`与`renderDigest`，以exact prefix与64 lowercase
  hex检查后投影到现有Semantic alpha carrier。lowering-owned error均为exact `.invalidProgram`：一般格式
  `validated ProgramV1 lowering does not support <wire constructor tag>`；两个条件错误精确为
  `validated ProgramV1 lowering requires a UInt64 integer literal`与
  `validated ProgramV1 lowering requires zero external call arguments`。raw unqualified names不render；
  qualified identity只允许完整pure `.str` Lean Name单次`toString`；禁止legacy hash或第二次hash。

  Lean suite必须覆盖：minimal与quoted-component qualified identity；state bucket相对order、entry/view共同bucket
  相对order、唯一init、三visibility与accepted type table（含nested Option/Array）；UInt64.max/name/add；零参数
  call及requirements；cross-kind reorder twins必须sourceHash不同、除sourceHash外Semantic fields相同且
  canonical bytes/semanticHash相同；`parseDigest ("sha256:" ++ semantic.sourceHash) = sourceHashV1`。
  unqualified program/state/param/callable names必须等于raw；program/callee qualified identity等于完整pure
  `.str` chain的一次`toString`，`["A.B","C"]`/`["A","B.C"]`collision twins必须不同。negative table
  穷举9个unsupported top-level alternatives、named/map及accepted recursive Option/Array中按child order首次
  到达的named/map、bool/string/2^64 integer、field/index
  place、constructor、3 unary、17 non-add binary、local-call/expr-match、全部unsupported statement families、
  schedule及nonempty-call argument priority。Pattern四constructor、两类match arm及if/match/for block只作为
  hostile child sentinel，证明rejected parent不遍历child；rejected top-level record也必须含hostile child
  sentinel。另固定unknown value、assignment target not declared state、view write/call、non-u64 add、init
  return、missing/after return与return mismatch仍由Typed返回原exact error。既有legacy Pipeline goldens不得改写。

  `v2_isolation.py`必须机械拒绝allowlist外任何production direct `Core.Source` import，并以mutation self-test
  证明；该allowlist是忽略comment/string decoy后对root与`ProofForgeV2/**/*.lean`的upper bound，移除既有
  import合法、allowlist外新增必须失败；路径精确为root umbrella、CLI/Toolchain、Compiler/Pipeline、
  Core/Typed、Language/ProgramExport、ProgramPayload与Syntax。除definition-free root umbrella registration外，
  只有Pipeline production definitions可同时触及validated ProgramV1与legacy Source values；不得新增
  legacy→ProgramV1或第二个adapter module。变更文件集只允许Pipeline、新compiler suite、Tests/lake
  registration、isolation checker/self-test、umbrella registration与机械SBOM pin；禁止修改Typed/SemanticIR/
  target/Syntax/Loader/CLI/export/NodeId。production≤210、Lean≤430、checker+self-test≤150、registrations≤6、
  总authored additions≤800（manifest不计）。验证focused+aggregate/test binary、isolation self-test、package
  refresh后final single SBOM、docs/diff与independent review；不运行完整`just ci`，不关闭formal task；
  full-tree global node/depth/resource containment明确不在本切片完成面。
- D1-PA-110 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的首个 post-approval slice，
  只实现 complete 4-tag recursive `PatternV1` decoder；不提前实现 mutual spine、Program root 或任何
  frontend/export cutover。production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstPatternDecodeV1
  decodePatternV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstPatternV1.PatternV1 × DecodeBudgetV1)
  ```

  decoder必须是以`remainingDepth : Nat`作structural fuel的kernel-total mutual `def`，不得使用`partial`、
  `unsafe`、无界递归或构造完整Pattern后事后walk。每个Pattern constructor都是node-bearing，进入时恰好
  消耗一个session-wide`remainingNodes`；Literal payload不是额外node。exact priority固定为bounded tag read
  → closed 4-tag dispatch（unknown为`unknown pattern tag '<tag>'`）→ exact fieldCount → depth → node → ordered
  fields。Wildcard/Bind/Literal/Constructor field counts分别为0/1/1/2；Constructor必须先完整解码QID，再读
  args count，再按source order递归children。args count必须在allocation或child decode前不大于parent charge后
  的node residual，否则原样返回`array count exceeds caller limit`；children共享`remainingDepth - 1`并线程化
  前一sibling消费后的node residual。depth/node exact errors继续为`depth budget exhausted`/
  `node budget exhausted`，两者同时为0时depth优先；primitive/QID/Literal错误不remap。

  Lean suite与不import Lean/ProofForge或既有reference脚本的standalone Python oracle必须共同固定：
  12个PA97 checked-in Pattern wire literals逐一decode为exact value、重新encode为同一bytes、`finish`并核对
  exact node spend；7个exhaustive field-count negatives（Wildcard用1，Bind/Literal各用0/2，Constructor用
  1/3）；至少20个boundary覆盖wrong-family无fieldCount且zero budgets仍先unknown、known wrong fieldCount
  先于budgets、depth-before-node、node-before-payload、invalid Bind、invalid Literal、Constructor QID-before-count/
  child、args count-before-allocation/child、empty args、sibling residual与source order、trailing、
  Constructor^255(Wildcard)恰为256 nodes/depth通过及^256在depth256失败。Python成功输出
  `reference_source_ast_pattern_decode_v1: ok 12 7 <boundary-count>`，其中boundary-count不得少于20。

  变更文件集：新增`ProofForgeV2/Source/AstPatternDecodeV1.lean`、
  `Tests/Language/SourceAstPatternDecodeV1.lean`、
  `scripts/reference_source_ast_pattern_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean`
  registration与机械manifest refresh，不修改Pattern model/encoder、PA107 Type decoder、WireDecode/scalar decoder
  或其他AST modules。budgets：production additions≤150、suite≤340、Python≤280、registrations≤5、
  总authored additions≤800（manifest不计）。明确排除spine/support/declaration/Program/root decoder、fresh root
  budget API、frontend/Loader/CLI/Lean command、ProgramExport v2/ProgramPayload、legacy删除、16MiB/完整
  100000-node session完成声明、sourceHash、NodeId、stable Diagnostic、Typed/Semantic与target。验证只运行
  focused+aggregate build/test binary、Python self-check、package refresh后最终单次`just sbom`、
  `just docs-check`、`git diff --check`与independent review；不运行完整`just ci`。结果只记录development
  evidence，不能关闭完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-111 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 supporting-record slice，
  只实现完整`ParamV1`、`FieldDeclV1`、`EnumVariantV1` decoder；不合并后续declaration或mutual-spine
  decoder。production public API精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSupportDecodeV1
  decodeParamV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSupportV1.ParamV1 × DecodeBudgetV1)
  decodeFieldDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSupportV1.FieldDeclV1 × DecodeBudgetV1)
  decodeEnumVariantV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSupportV1.EnumVariantV1 × DecodeBudgetV1)
  ```

  三个records均为node-bearing。每次调用必须按bounded tag read → singleton closed dispatch（unknown exact为
  `unknown param tag '<tag>'`、`unknown field-decl tag '<tag>'`、
  `unknown enum-variant tag '<tag>'`）→ exact fieldCount → depth → node → ordered fields执行；fieldCounts
  分别为3/2/2。进入record消耗一个session-wide node，所有Type child使用`remainingDepth - 1`，并取得前一
  child消费后的node residual；visibility/name/scalar count本身不消耗node/depth。`Param`严格按
  Visibility→Ident→Type，`FieldDecl`按Ident→Type，`EnumVariant`按Ident→payload count→source-order Type
  children。depth/node exact errors与priority继续为`depth budget exhausted`/`node budget exhausted`，同时为
  0时depth优先，primitive/Type child错误不得remap。

  `EnumVariant.payloadTypes`允许empty。其u32 count必须在allocation或child decode前不大于record charge后
  的node residual，否则exact返回`array count exceeds caller limit`；每个Type至少消耗一个node，因此该
  上界不得使用调用前budget或bytes remaining替代。所有children共享同一个child depth，并线程化前一
  sibling的node residual。实现必须kernel-total，不得`partial`、`unsafe`、构造完整record后post-walk，
  也不得创建fresh root budget或重算全树资源。

  Lean suite与不import Lean/ProofForge或既有reference脚本的standalone Python oracle必须共同固定：
  10个PA96 checked-in supporting-record literals逐一decode为exact value、重新encode为同一bytes、`finish`并
  核对exact node spend；6个field-count negatives（Param用2/4，FieldDecl与EnumVariant各用1/3）；至少
  20个boundaries覆盖三个sibling tag wrong-family且省略fieldCount、known wrong fieldCount先于budgets、
  depth-before-node、node-before-payload、Param visibility-before-name/type、FieldDecl name-before-type、
  EnumVariant name-before-count、count-before-allocation/child、empty payload、two-child source order与sibling
  residual、trailing、invalid Ident、invalid Visibility、invalid/nested Type、Type child depth short与node short。
  所有`A-before-B`必须使用A、B同时失败并固定A exact error的conflict vector；三个wrong-family cases同时
  使用`remainingDepth=0`、`remainingNodes=0`，known wrong fieldCount使用zero budgets，node-before-payload
  对每个public decoder使用nonzero depth、zero nodes与malformed first field。每个public decoder至少有一个
  primitive或Type child exact error原样传播vector。
  Python成功输出`reference_source_ast_support_decode_v1: ok 10 6 <boundary-count>`，其中boundary-count不得
  少于20。

  变更文件集：新增`ProofForgeV2/Source/AstSupportDecodeV1.lean`、
  `Tests/Language/SourceAstSupportDecodeV1.lean`、
  `scripts/reference_source_ast_support_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean`
  registration与机械manifest refresh，不修改support model/encoder、WireDecode、scalar/Type/Pattern decoder
  或其他AST modules。budgets：production additions≤170、suite≤340、Python≤280、registrations≤5、
  总authored additions≤800（manifest不计）。明确排除declaration/spine/ProgramItem/Program/root decoder、
  fresh root budget API、frontend/Loader/CLI/Lean command、ProgramExport v2/ProgramPayload、legacy删除、
  16MiB/完整100000-node session完成声明、sourceHash、NodeId、stable Diagnostic、Typed/Semantic与target。
  验证只运行focused+aggregate build/test binary、Python self-check、package refresh后最终单次`just sbom`、
  `just docs-check`、`git diff --check`与independent review；不运行完整`just ci`。结果只记录development
  evidence，不能关闭完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-112 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  spine-independent declaration-record decoder slice。它只实现 PA98 已冻结的 `StateDeclV1`、
  `StructDeclV1`、`EnumDeclV1`、`EventDeclV1`、`ErrorDeclV1`、`ExtensionReqV1`、`ProofDeclV1`
  七个 record decoder；不合并 PA101 spine-dependent declarations、mutual spine、`ProgramItemV1`、
  `ProgramV1` 或 canonical root decoder。production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstDeclDecodeV1
  decodeStateDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.StateDeclV1 × DecodeBudgetV1)
  decodeStructDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.StructDeclV1 × DecodeBudgetV1)
  decodeEnumDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.EnumDeclV1 × DecodeBudgetV1)
  decodeEventDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.EventDeclV1 × DecodeBudgetV1)
  decodeErrorDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.ErrorDeclV1 × DecodeBudgetV1)
  decodeExtensionReqV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.ExtensionReqV1 × DecodeBudgetV1)
  decodeProofDeclV1 (remainingDepth : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstDeclV1.ProofDeclV1 × DecodeBudgetV1)
  ```

  七个 records 均为 node-bearing。每次调用必须按 bounded tag read → singleton closed dispatch →
  exact fieldCount → depth → node → ordered fields 执行；unknown exact family 分别为 `state-decl`、
  `struct-decl`、`enum-decl`、`event-decl`、`error-decl`、`extension-req`、`proof-decl`，不得用一个
  multi-tag head 接受其他 declaration sibling。fieldCounts 精确为 3/2/2/2/2/3/2；depth/node exact
  errors继续为`depth budget exhausted`/`node budget exhausted`，同时为0时depth优先，所有 primitive、
  Type 与 PA111 child error 均不得 remap。进入 record 恰好消费一个 session-wide node；Type、FieldDecl、
  EnumVariant、Param child 使用 `remainingDepth - 1`，同一 array 的 siblings 共享 child depth并线程化
  前一 sibling 的 node residual。沿用 PA106/PA111 记账：Visibility/Literal/UnaryOp/BinaryOp scalar child
  不消耗 node 或 depth；golden node spend 必须按该规则计算。实现必须 kernel-total，不得 `partial`、
  `unsafe`、post-walk 或 fresh root budget。

  `StructDecl.fields` 与 `EnumDecl.variants` 必须 nonempty；读完 name 与 u32 count 后，zero count 分别
  exact 返回 `struct fields must be nonempty`/`enum variants must be nonempty`。Struct/Enum/Event/Error 的
  count 均必须在 allocation 或 child decode 前不大于 parent charge 后的 node residual，否则 exact 返回
  `array count exceeds caller limit`；不得使用调用前 budget 或 bytes remaining。Event/Error empty params
  仍为合法值。State 按 Visibility→Ident→Type，四类 array declaration 按 Ident→count→source-order children。
  ExtensionReq 严格按 QID→String version→canonical SemVer parse/render equality→String digest→canonical
  Digest parse/render equality，两个 local error exact 复用 PA98 的
  `extension version must use canonical exact SemVer` 与
  `extension digest must use canonical sha256 spelling`；ProofDecl 按 invariant Ident→theorem QID。

  Lean suite与不import Lean/ProofForge或既有reference脚本的standalone Python oracle必须共同固定：
  PA98 的14个checked-in declaration wire literals逐一decode为exact value、重新encode为同一bytes、`finish`
  并核对exact node spend；14个exhaustive field-count negatives（七个tags各使用expected-1/expected+1，
  且以zero budgets证明fieldCount优先）；42个固定boundaries的分区精确为：7个使用不同declaration sibling
  tag的wrong-family/no-fieldCount/zero-budget，1个depth-before-node，7个各public API的
  node-before-hostile-first-field，State 3个（visibility-before-name、name-before-Type、Type error透传），
  Struct与Enum各5个（name-first、nonempty、post-charge-count、child-error、sibling-residual），Event与Error
  各4个（name-first、post-charge-count、Param-error、sibling-residual），Extension 3个（QID-before-hostile
  version/digest、version-before-hostile digest、valid QID+version下的独立canonical-digest rejection），
  Proof 2个（invariant-before-QID、QID error），以及1个whole-value trailing rejection。所有A-before-B均
  使用A、B同时失败的conflict vector；source-order/residual positive不得复用同一assertion冒充多个
  inventory slot。
  Python成功输出`reference_source_ast_decl_decode_v1: ok 14 14 42`。

  变更文件集：新增`ProofForgeV2/Source/AstDeclDecodeV1.lean`、
  `Tests/Language/SourceAstDeclDecodeV1.lean`、`scripts/reference_source_ast_decl_decode_v1.py`；只做
  `ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean` registration与机械manifest refresh，不修改 declaration/
  support/type/scalar model或encoder、PA111 decoder、WireDecode、spine/Program modules。budgets：production
  additions≤220、suite≤400、Python≤320、registrations≤5、总authored additions≤800（manifest不计）。明确
  排除spine-dependent declaration/Place/Expr/Stmt/Block/ProgramItem/Program/root decoder、fresh root budget
  API、frontend/Loader/CLI/Lean command、ProgramExport v2/ProgramPayload、legacy删除、16MiB/完整100000-node
  session完成声明、sourceHash、NodeId、stable Diagnostic、Typed/Semantic与target。验证只运行focused+
  aggregate build/test binary、Python normal及`-O` self-check、package refresh后最终单次`just sbom`、
  `just docs-check`、`git diff --check`与independent review；不运行完整`just ci`。结果只记录development
  evidence，不能关闭完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-113 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  `PlaceV1↔ExprV1` mutual decoder slice。它精确包含 PA99 的`PlaceV1`、`ExprV1`、`ExprMatchArmV1`、
  `ExternalCallExprV1`四种类型；`Expr.Match`需要arm，且ExternalCall是后续Stmt.Call/Schedule的直接依赖，
  因而二者不得拆出。`StmtV1`、`BlockV1`、`StmtMatchArmV1`与spine-dependent declarations仍排除。
  production public API精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineDecodeV1
  decodePlaceV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.PlaceV1 × DecodeBudgetV1)
  decodeExprV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.ExprV1 × DecodeBudgetV1)
  decodeExprMatchArmV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.ExprMatchArmV1 × DecodeBudgetV1)
  decodeExternalCallExprV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.ExternalCallExprV1 × DecodeBudgetV1)
  ```

  四个defs必须处于一个kernel-total `mutual` block；每个def均以Nat参数`d`做
  `| 0 => head; depth error | d+1 => head; charge; fields`并逐一定义`termination_by d => d`。
  array count loop必须inline调用`decodeExprV1 d budget`；禁止把recursive decoder作为higher-order array
  helper参数，否则不构成结构递减。不得`partial`、`unsafe`、post-walk、fresh root budget或默认
  `256/100000` convenience入口。

  closed heads精确为：Place family `Place.Name/1`、`Place.Field/2`、`Place.Index/2`；Expr family
  `Expr.Literal/1`、`Expr.Place/1`、`Expr.Constructor/2`、`Expr.Unary/2`、`Expr.Binary/3`、
  `Expr.LocalCall/2`、`Expr.Match/2`；singleton `ExprMatchArm/2`与`ExternalCallExpr/2`。unknown errors
  分别为`unknown place tag '<tag>'`、`unknown expr tag '<tag>'`、
  `unknown expr-match-arm tag '<tag>'`、`unknown external-call tag '<tag>'`。每个node必须按bounded tag
  →closed-family unknown→exact fieldCount→depth→node→wire-order fields；depth/node同时为0时depth优先，
  child errors不得remap。进入每个Place/Expr/arm/external record恰好消费一个session-wide node；recursive
  Place/Expr/arm与PA110 Pattern child使用parent `d-1`，siblings共享同一child depth并线程化node residual。
  Literal/UnaryOp/BinaryOp、Ident/QID等scalar不消费node/depth。

  Place按Name Ident、Field base→field Ident、Index base→index Expr；Expr按PA100表顺序。Constructor与
  ExternalCall先QID、LocalCall先Ident，再读u32 count；所有array count均在callee与parent charge后、
  allocation/child前不大于当前node residual，否则exact返回`array count exceeds caller limit`。
  `Expr.Match`必须先完整解scrutinee，再读count；count=0 exact返回
  `expr match arms must be nonempty`，之后才做post-scrutinee residual cap与arm loop。Constructor、LocalCall、
  ExternalCall empty args合法。ExprMatchArm按Pattern→Expr，ExternalCall按QID→source-order Expr args。

  Lean suite与不import Lean/ProofForge或既有reference脚本的standalone Python oracle必须共同固定15/24/41：
  15个PA100 checked-in literals全部逐字使用并比较exact value、re-encode、`finish`与node spend，顺序/花费
  精确为place_name/field/index `1,2,3`，expr_literal/place/ctor_some/ctor_none/ctor_order_a/ctor_order_b/
  unary/binary/local/match `1,2,2,1,3,3,2,3,2,8`，expr_arm `3`，external `1`；两个ctor-order值与bytes
  必须nonalias。24个field-count negatives为十二tags各expected-1/expected+1，且以`d=0,nodes=0`固定
  fieldCount-before-budget。

  41个boundary slots精确分区为：10个wrong-family/no-fieldCount/zero-budget（Place拒绝Expr.Literal/
  Expr.Place/Expr.Binary；Expr拒绝Place.Name/ExprMatchArm/ExternalCallExpr；ExprMatchArm拒绝Place.Field/
  Expr.Match；ExternalCall拒绝Place.Index/Expr.Unary）；1个depth-before-node与四API各1个
  node-before-absent-first-payload；13个双故障field-order conflicts——Index bad `BogusBase`先于
  `BogusIndex`及valid-base/bad-index、Field bad-base先于invalid Ident、Binary `BogusLhs`先于
  `BogusRhs`及`Visibility.Public` op先于bad lhs、Unary `BinaryOp.Add`先于bad operand、Match
  `BogusScrutinee`先于zero arms、Constructor/ExternalCall一组件`Only` QID先于`0xffffffff` count、
  LocalCall 241-byte Ident先于`0xffffffff` count、arm `BogusPattern`先于`BogusValue`、Constructor
  `BogusArg0`先于`BogusArg1`、Binary valid lhs后以`d=2,nodes=2`在rhs exact耗尽；4个post-charge caps
  覆盖Constructor/LocalCall/ExternalCall `(nodes=2,count=2)`及Match
  `(nodes=3,valid literal scrutinee,count=2)`；1个valid-scrutinee/zero-arm nonempty；2个slots为
  `ExternalCall Math.add([Literal 1, Literal 2])`在`d=2,nodes=3`成功且residual0，以及Literal Bool marker2
  exact透传；6个resource/structure slots为Unary^255在`d=256,nodes=256`成功residual0、Unary^256在
  `d=256,nodes=257` depth error、Unary^255在`d=256,nodes=255` node error、whole-value trailing、
  Constructor两Literal与LocalCall两Literal各在`d=2,nodes=3`成功residual0。所有A-before-B均为A/B
  同时失败的non-vacuous conflict；具体hostile tag、`d`、nodes不得以省略号或范围代替。
  Python必须assert-free、normal/`-O`均通过、非exact argv usage+exit2，并只输出
  `reference_source_ast_spine_place_expr_decode_v1: ok 15 24 41`。

  变更文件集：新增`ProofForgeV2/Source/AstSpineDecodeV1.lean`、
  `Tests/Language/SourceAstSpinePlaceExprDecodeV1.lean`、
  `scripts/reference_source_ast_spine_place_expr_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/
  `lakefile.lean` registration与机械manifest refresh，不修改PA99 model/equality、PA100 codec/goldens、
  PA106–112 decoder、WireDecode或其他AST modules。budgets：production≤260、suite≤450、Python≤400、
  registrations≤5、总authored additions≤1100（manifest不计）。明确排除Stmt/Block/StmtMatchArm、
  spine-dependent declarations、ProgramItem/Program/root、fresh root session、16MiB/完整100000-node声明、
  frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/fallback、sourceHash/NodeId/stable
  Diagnostic/Typed/Semantic/target。RED必须只因production module缺失；GREEN只运行focused+aggregate
  build/test binary、Python normal/`-O`、package refresh后最终单次`just sbom`、docs/diff与independent review，
  不运行完整`just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-114 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  `StmtV1↔BlockV1↔StmtMatchArmV1` mutual decoder slice。它精确闭合 PA99 剩余的 statement spine SCC；
  PA113 的 Place/Expr/ExternalCall 与 PA110 Pattern、PA107 Type 是只读 child dependencies。
  spine-dependent declaration、`ProgramItemV1`、`ProgramV1` 与 canonical root decoder 仍排除。
  production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineStmtDecodeV1
  decodeStmtV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.StmtV1 × DecodeBudgetV1)
  decodeBlockV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.BlockV1 × DecodeBudgetV1)
  decodeStmtMatchArmV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineV1.StmtMatchArmV1 × DecodeBudgetV1)
  ```

  三个 defs 必须处于一个 kernel-total `mutual` block；每个 def 均按 bounded tag→closed-family
  unknown→exact fieldCount→depth→parent node→wire-order fields，并以 Nat 参数 `d` 做结构递减及
  `termination_by d => d`。递归 Stmt/Block/arm array loop 与 recursive Block option 必须 inline，禁止把
  recursive decoder 传给 higher-order array/option helper；不得使用 `partial`、`unsafe`、post-walk、fresh
  root budget 或默认 `256/100000` convenience API。

  closed heads/fieldCounts/wire order 精确为：`Stmt.Let/3` Ident→Option Type→Expr、
  `Stmt.Assign/2` Place→Expr、`Stmt.If/3` Expr→Block→Option Block、`Stmt.Match/2`
  Expr→Array StmtMatchArm、`Stmt.For/5` Ident→Expr start→Expr endExclusive→u32 bound→Block、
  `Stmt.Assert/2` Expr→Option Ident、`Stmt.Revert/2` Ident→Array Expr、`Stmt.Emit/2`
  Ident→Array Expr、`Stmt.Return/1` Option Expr、`Stmt.Call/1` ExternalCallExpr、`Stmt.Schedule/1`
  ExternalCallExpr、`Block/1` Array Stmt、`StmtMatchArm/2` Pattern→Block。unknown errors 精确为
  `unknown stmt tag '<tag>'`、`unknown block tag '<tag>'` 与
  `unknown stmt-match-arm tag '<tag>'`。26 个 exhaustive field-count negatives 是每个 tag 的
  expected-1/expected+1：Let `2/4`、Assign `1/3`、If `2/4`、Match `1/3`、For `4/6`、Assert
  `1/3`、Revert `1/3`、Emit `1/3`、Return `0/2`、Call `0/2`、Schedule `0/2`、Block `0/2`、
  StmtMatchArm `1/3`；全部使用 `d=0,nodes=0` 证明 fieldCount 先于 budget，错误精确为
  `tag '<tag>' must declare <expected> fields`。

  每个 Stmt/Block/arm 恰消费一个 session-wide node；所有 node-bearing child 接收 parent `d-1`，
  siblings 共享 child depth 并从左到右线程化 node residual；Ident/QID、scalar、option marker、count 与
  For bound 不消费 node/depth。Option marker 仅接受 `0/1`，其他值精确返回
  `invalid option marker`。Revert/Emit 允许空 args，并在 parent charge、Ident 后以当前 residual cap
  count。Match 必须完整解 scrutinee 后读 count，zero 先返回
  `stmt match arms must be nonempty`，再做 post-scrutinee cap。Block 在 parent charge 后读 count，zero
  先返回 `block statements must be nonempty`，再做 cap。For decoder 必须按 wire 解 binder→start→end，
  再读 bound；`4097` 精确返回 `for bound must be 0..4096` 且不触碰 body。该顺序有意不同于 encoder
  在编码 child 前做 local bound preflight，但两者都只接受 `0..4096`。

  Lean suite 与不 import Lean/ProofForge/既有 reference script 的 standalone Python oracle 必须共同固定
  21/26/52。21 个 unique PA100 literal 全部逐字使用、比较 exact value、node residual、`finish` 与
  byte-identical re-encode；顺序/节点花费精确为：`stmt_let_none/2`、`stmt_let_some/3`、
  `stmt_assign/3`、`stmt_if_none/4`、`stmt_if_some/7`、`stmt_match/6`、`stmt_for_0/5`、
  `stmt_for_4096/5`、`stmt_assert_none/2`、`stmt_assert_some/2`、`stmt_revert_empty/1`、
  `stmt_revert_one/2`、`stmt_emit/1`、`stmt_return_none/1`、`stmt_return_1/2`、`stmt_call/2`、
  `stmt_sched/3`、`block_single/2`、`block_multi/3`、`stmt_arm/4`、`nonalias_blk_er/3`。
  PA100 的 `nonalias_blk_re` 与 `block_multi` 是同一 value/bytes carrier，不得重复计为第22个正例；
  `block_multi` 与 `nonalias_blk_er` 必须同时证明 value/bytes nonalias。

  52 个 boundary slots 精确冻结如下；每个 A-before-B 项必须同时携带 failing A/B，禁止 vacuous
  placeholder。`bad("X")` 是 bounded ASCII tag `X` 且故意不带 fieldCount；`ident0` 是 declared Ident
  length zero；`L0`/`L1`/`L4096`/`LT`、`place_name`、`block_single`、`stmt_arm` 均使用 PA100
  checked-in bytes。所有未另写的错误文本沿用上述 exact child decoder error：

  1. Stmt `bad("Block")`、`d=0,n=0` → `unknown stmt tag 'Block'`；2. Block
  `bad("Stmt.Return")`、`d=0,n=0` → `unknown block tag 'Stmt.Return'`；3. arm
  `bad("Stmt.Let")`、`d=0,n=0` → `unknown stmt-match-arm tag 'Stmt.Let'`；4. exact
  `Stmt.Return/1` head、无 payload、`d=0,n=0` → `depth budget exhausted`；5. exact Let head +
  `ident0`、`d=1,n=0` → `node budget exhausted`；6. exact Block head + count0、`d=1,n=0` → node
  exhausted；7. exact arm head + `bad("BogusPattern"),bad("BogusBody")`、`d=1,n=0` → node exhausted。

  8. Let `ident0,marker2,bad("BogusValue")`、`d=3,n=8` → Ident length error；9. Let
  `Ident x,marker2,bad("BogusValue")`、`d=3,n=8` → invalid option marker；10. Let
  `Ident x,marker1,bad("Expr.Literal") as Type,bad("BogusValue")`、`d=3,n=8` → unknown Type；
  11. Let `Ident x,some Type.Bool,L1`、`d=2,n=2` → value node exhausted；12. Assign
  `bad("BogusTarget"),bad("BogusValue")`、`d=3,n=8` → Place error；13. Assign
  `place_name,bad("BogusValue")`、`d=3,n=8` → Expr error。

  14. If `bad("BogusCondition"),bad("BogusThen"),marker2`、`d=4,n=16` → condition error；
  15. If `LT,bad("BogusThen"),marker2`、`d=4,n=16` → then Block error；16. If
  `LT,block_single,marker2`、`d=4,n=16` → invalid option marker；17. If
  `LT,block_single,marker1,block_single`、`d=3,n=4` → else Block node exhausted；18. Match
  `bad("BogusScrutinee"),count0`、`d=4,n=16` → scrutinee error；19. Match `L1,count0`、
  `d=4,n=16` → nonempty；20. Match `L1,count2`、`d=4,n=3` → post-scrutinee cap；21. Match
  `L1,count1,bad("BogusArm")`、`d=4,n=16` → unknown arm；22. Match
  `L1,count2,stmt_arm,stmt_arm`、`d=4,n=6` → second arm node exhausted。

  23. For `ident0,bad("BogusStart"),bad("BogusEnd"),4097,bad("BogusBody")`、`d=4,n=16`
  → Ident error；24. For `Ident i,bad("BogusStart"),bad("BogusEnd"),4097,bad("BogusBody")`、
  `d=4,n=16` → start error；25. For `Ident i,L0,bad("BogusEnd"),4097,bad("BogusBody")`、
  `d=4,n=16` → end error；26. For `Ident i,L0,L4096,4097,bad("BogusBody")`、`d=4,n=16`
  → bound error before body；27. For `Ident i,L0,L4096,0,block_single`、`d=2,n=2` → endExclusive
  node exhausted after start consumes the final residual node。

  28. Assert `bad("BogusCondition"),marker2`、`d=3,n=8` → condition error；29. Assert
  `LT,marker2`、`d=3,n=8` → invalid option marker；30. Assert `LT,marker1,ident0`、`d=3,n=8`
  → Ident error；31. Revert `ident0,count0xffffffff`、`d=2,n=8` → Ident error；32. Revert
  `Ident Denied,count2`、`d=2,n=2` → cap；33. Revert
  `Ident Denied,count1,bad("BogusArg")`、`d=2,n=2` → Expr error；34. Emit
  `ident0,count0xffffffff`、`d=2,n=8` → Ident error；35. Emit `Ident Ping,count2`、`d=2,n=2`
  → cap；36. Emit `Ident Ping,count1,bad("BogusArg")`、`d=2,n=2` → Expr error；37. Return
  `marker2,bad("BogusValue")`、`d=2,n=8` → invalid option marker；38. Return `marker1,L1`、
  `d=2,n=1` → Expr node exhausted；39. Call `bad("BogusExternal")`、`d=2,n=8` → unknown
  external-call；40. Schedule 同一 hostile child、`d=2,n=8` →同一 child error。

  41. Block `count0,bad("BogusStmt")`、`d=2,n=8` → nonempty；42. Block count2、`d=2,n=2`
  → post-charge cap；43. Block `count1,bad("BogusStmt")`、`d=2,n=8` → unknown Stmt；44. Block
  `count2,Return(Some L1),Return(None)`、`d=3,n=3` → second Stmt node exhausted；45. Block
  `count2,Emit Ping [],Revert Denied []`、`d=2,n=3` → exact success/residual0/value/order/finish/re-encode；
  46. arm `bad("BogusPattern"),bad("BogusBody")`、`d=3,n=8` → Pattern error；47. arm
  `Pattern.Wildcard,bad("BogusBody")`、`d=3,n=8` → Block error；48. arm
  `Pattern.Wildcard,block_single`、`d=2,n=2` → Block node exhausted。

  49. `stmt_return_none || 00`、`d=2,n=2` 解出 value 后 `finish` → trailing bytes。深度构造精确为
  `nestIf 0 base = base`；`nestIf (n+1) base = Stmt.If (Literal Bool true)
  (Block #[nestIf n base]) none`。50. `nestIf 127 (Return (some L0))`、`d=256,n=383` → exact
  success/residual0/value/finish/re-encode，最长 node path `256`、总 nodes `383`；51.
  `nestIf 128 (Return none)`、`d=256,n=385` → depth exhausted，最长 path `257`、总 nodes `385`；
  52. slot 50 同一 bytes、`d=256,n=382` → node exhausted。

  Python 必须 assert-free，normal/`-O` 都通过，非精确 argv 输出 usage 且 exit 2，只打印
  `reference_source_ast_spine_stmt_decode_v1: ok 21 26 52`；它使用独立 tuple value model 与独立
  re-encoder，只复制本冻结实际触及的 PA107/110/113 child surface，不得通过调用 Lean 或既有 reference
  script 形成自证循环。

  变更文件集：新增`ProofForgeV2/Source/AstSpineStmtDecodeV1.lean`、
  `Tests/Language/SourceAstSpineStmtDecodeV1.lean`、
  `scripts/reference_source_ast_spine_stmt_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/
  `lakefile.lean` registration与机械manifest refresh，不修改PA99 model/equality、PA100 codec/goldens、
  PA106–113 decoder、WireDecode或其他AST modules。budgets：production≤240、suite≤480、Python≤620、
  registrations≤5、总authored additions≤1300（manifest不计）。明确排除spine-dependent declarations、
  ProgramItem/Program/root/fresh root session、16MiB/完整100000-node声明、frontend/Loader/CLI/Lean command/
  export v2、legacy bridge/dual reader/第二 quoted decoder/fallback、sourceHash/NodeId/stable Diagnostic/
  Typed/Semantic/target。RED必须只因production module缺失；GREEN只运行focused+aggregate build/test binary、
  Python normal/`-O`/invalid argv、package refresh后最终单次`just sbom`、docs/diff与independent review，
  不运行完整`just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-115 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  spine-dependent declaration-record decoder slice。它精确闭合 PA101 的六个 `AstSpineDeclV1` record；
  PA107 Type、PA111 Param、PA113 Expr 与 PA114 Block decoder 是只读 child dependencies。
  `ProgramItemV1`、`ProgramV1`、canonical root 与 frontend 仍排除。production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstSpineDeclDecodeV1
  decodeConstDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.ConstDeclV1 × DecodeBudgetV1)
  decodeInvariantDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.InvariantDeclV1 × DecodeBudgetV1)
  decodeInitDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.InitDeclV1 × DecodeBudgetV1)
  decodeEntryDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.EntryDeclV1 × DecodeBudgetV1)
  decodeViewDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.ViewDeclV1 × DecodeBudgetV1)
  decodeFnDeclV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstSpineDeclV1.FnDeclV1 × DecodeBudgetV1)
  ```

  六个 defs 彼此非 mutual，因为所有 child decoder 都已在该 family 外闭合；每个 def 仍必须以 Nat
  `d` 做 total pattern match，固定 tag→closed-family unknown→exact fieldCount→depth→parent node→wire-order
  fields。禁止 `partial`、`unsafe`、fresh root budget、默认 `256/100000` convenience API、post-walk、
  fallback 或 error remap。Param array 可复用 private budget-threaded helper，但不得暴露新 public API；
  count 必须在 parent charge 后针对当前 node residual 做 cap，children 接收 parent `d-1`，siblings 从左到右
  线程化同一 residual。

  closed heads/fieldCounts/wire order 精确为：`ConstDecl`/3 Ident→Type→Expr、
  `InvariantDecl`/2 Ident→Expr、`InitDecl`/2 Array Param→Block、`EntryDecl`/4
  Ident→Array Param→Type result→Block、`ViewDecl`/4 Ident→Array Param→Type result→Block、
  `FnDecl`/4 Ident→Array Param→Type result→Block。unknown errors 精确为
  `unknown const-decl tag '<tag>'`、`unknown invariant-decl tag '<tag>'`、
  `unknown init-decl tag '<tag>'`、`unknown entry-decl tag '<tag>'`、
  `unknown view-decl tag '<tag>'`、`unknown fn-decl tag '<tag>'`。12 个 exhaustive field-count
  negatives 是每个 tag 的 expected-1/expected+1：Const `2/4`、Invariant `1/3`、Init `1/3`、
  Entry `3/5`、View `3/5`、Fn `3/5`；全部使用 `d=0,nodes=0` 证明 fieldCount 先于 budget，
  错误精确为 `tag '<tag>' must declare <expected> fields`。

  每个 decl 恰消费一个 session-wide parent node；Ident、Visibility 与 array count 不消费 node/depth。
  Param array 允许 empty；`view_get_empty` 的 empty 只指 params。Block nonempty 只由 PA114
  `decodeBlockV1` 执行，decl 根不得重复检查。decoder 必须严格按 wire 从左到右；不得复制 PA101
  encoder 在 child 编码前执行 local preflight 的顺序。

  Lean suite 与不 import Lean/ProofForge/既有 reference script 的 standalone Python oracle 必须共同固定
  **7/12/46**。7 个 unique PA101 checked-in literal 全部逐字使用，比较 exact value、exact-consume/
  `finish`、byte-identical re-encode，并以最小 root-inclusive depth 与恰好 node budget 成功且 residual=0：
  `const_max d=2,n=3`、`invariant_bounded d=4,n=5`、`init_two_params d=4,n=9`、
  `entry_run d=5,n=12`、`entry_swapped d=5,n=12`、`view_get_empty d=4,n=5`、
  `fn_helper2 d=5,n=9`。七者互不 byte alias；PA102 no-wrapper copies、PA101 `viewAsEntry` 与 transient
  same-fields Entry/View control 不得重复计数。`entry_run` 与 `entry_swapped` 必须证明 same-type
  value/bytes nonalias；same-fields Entry/View 只做 tag-byte nonalias comparison，不计第八个 positive。

  46 个 boundary slots 精确冻结如下；每个 A-before-B 项同时携带 failing A/B，禁止 vacuous placeholder。
  `bad("X")` 是 bounded ASCII tag `X` 且故意不带 fieldCount；`head(Tag,fc)` 是合法 tag+fieldCount
  而无 payload；`ident0` 是 declared Ident length zero；`P_START`、`TU64`、`TU256`、`TUNIT`、
  `BLK_ASSIGN`、`BLK_RET_0` 与七个 root golden 均逐字使用 PA101 checked-in bytes。

  1. Const `bad("StateDecl")`、2. Invariant `bad("ConstDecl")`、3. Init `bad("EntryDecl")`、
  4. Entry `bad("ViewDecl")`、5. View `bad("FnDecl")`、6. Fn `bad("EntryDecl")`，均
  `d=0,n=0`，分别返回对应 exact `unknown <family> tag '<tag>'`；7–12. 六个 decoder 各自以 exact
  head、`d=0,n=0` 返回 `depth budget exhausted`；13–18. 六个 decoder 各自以 exact head、
  `d=1,n=0` 返回 `node budget exhausted`。

  19. Const `ident0,bad("BogusType"),bad("BogusValue")`、`d=3,n=8` → source-name length；
  20. Const `max,bad("BogusType"),bad("BogusValue")` → `unknown type tag 'BogusType'`；
  21. Const `max,TU256,bad("BogusValue")` → `unknown expr tag 'BogusValue'`；22. `const_max`、
  `d=2,n=2` → value `node budget exhausted`。23. Invariant `ident0,bad("BogusPred")` → source-name
  length；24. Invariant `bounded,bad("BogusPred")` → `unknown expr tag 'BogusPred'`；19–21、23–24
  未另写时均 `d=3,n=8`。

  25. Init count2、`d=2,n=2` → post-charge `array count exceeds caller limit`；26. Init
  count1+`bad("BogusParam")`+`bad("BogusBody")`、`d=3,n=8` → `unknown param tag 'BogusParam'`；
  27. Init count1+`P_START`+empty Block、`d=4,n=16` → `block statements must be nonempty`；
  28. `init_two_params`、`d=3,n=3` → second Param `node budget exhausted`；29. Init
  count1+`P_START`+`BLK_ASSIGN`、`d=3,n=3` → body `node budget exhausted`。

  30. Entry `ident0,count0,bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → source-name
  length；31. Entry `run,count2`、`d=3,n=2` → post-charge cap；32. Entry
  `run,count1,bad("BogusParam"),bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → Param error；
  33. Entry `run,count0,bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → Type error；
  34. Entry `run,count0,TU64,bad("BogusBody")`、`d=4,n=8` → Block error；35. Entry
  `run,count0,TU64,BLK_RET_0`、`d=4,n=2` → body node exhausted。

  36. View `ident0,count0,bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → source-name
  length；37. View `get,count2`、`d=3,n=2` → post-charge cap；38. View
  `get,count1,bad("BogusParam"),bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → Param error；
  39. View `get,count0,Type.UInt/1 width24,bad("BogusBody")`、`d=4,n=8` →
  `integer width must be one of 8,16,32,64,128,256`；40. View `get,count0,TU64,empty Block`、
  `d=4,n=8` → Block nonempty error。

  41. Fn `ident0,count0,bad("BogusResult"),bad("BogusBody")`、`d=4,n=8` → source-name length；
  42. Fn `helper2,count2`、`d=3,n=2` → post-charge cap；43. Fn
  `helper2,count0,Type.UInt/1 width24,bad("BogusBody")`、`d=4,n=8` → width error；44. Fn
  `helper2,count0,TUNIT,empty Block`、`d=4,n=8` → Block nonempty error；45. full `fn_helper2`、
  `d=4,n=9` → nested body `depth budget exhausted`；46. `const_max || 00` 以 `d=2,n=3`
  解出 value 后 `finish` → `trailing bytes`。所有只写“source-name length/Param/Type/Block error”的 slot
  分别逐字断言 `source name component must contain 1..240 UTF-8 bytes`、
  `unknown param tag 'BogusParam'`、`unknown type tag 'BogusResult'` 与
  `unknown block tag 'BogusBody'`；Block nonempty error逐字为
  `block statements must be nonempty`，不得做 error class 或 substring 比较。

  Python 必须 assert-free，normal/`-O` 都通过，非精确 argv 输出 usage 且 exit 2，只打印
  `reference_source_ast_spine_decl_decode_v1: ok 7 12 46`；它使用独立 tuple value model 与独立
  re-encoder，只复制本冻结实际触及的 Type/Param/Expr/Block/Stmt child surface，不得调用 Lean 或既有
  reference script 形成自证循环。

  变更文件集：新增`ProofForgeV2/Source/AstSpineDeclDecodeV1.lean`、
  `Tests/Language/SourceAstSpineDeclDecodeV1.lean`、
  `scripts/reference_source_ast_spine_decl_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/
  `lakefile.lean` registration与机械manifest refresh，不修改PA99–114 model/codec/decoder、PA101 goldens、
  WireDecode或其他AST modules。budgets：production≤240、suite≤420、Python≤600、registrations≤5、
  总authored additions≤1300（manifest不计）。明确排除ProgramItem/Program/root/fresh root session、
  frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/第二 quoted decoder/fallback、
  sourceHash/NodeId/stable Diagnostic/Typed/Semantic/target。RED必须只因production module缺失；GREEN只运行
  focused+aggregate build/test binary、direct Lean suite、Python normal/`-O`/invalid argv、package refresh后
  最终单次`just sbom`、docs/diff与independent review，不运行完整`just ci`。结果只记录development evidence，
  不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-116 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  no-wrapper `ProgramItemV1` decoder dispatch slice。它只读复用 PA112 的 State/Struct/Enum/Event/Error/
  ExtensionReq/Proof decoder 与 PA115 的 Const/Invariant/Init/Entry/View/Fn decoder；不修改任一 child
  decoder、model 或 codec。`ProgramV1`、canonical root 与 frontend 继续排除。production public API
  精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstProgramItemDecodeV1
  decodeProgramItemV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstProgramItemV1.ProgramItemV1 × DecodeBudgetV1)
  ```

  `ProgramItemV1` 没有 wrapper tag、field count、独立 node 或独立 depth。decoder 只对 caller cursor 做
  bounded tag lookahead；13 个已知 tag 必须把**原始 cursor**、同一 `d` 与同一 `budget` 恰好委托给对应
  record decoder，再仅包装返回 constructor。禁止消费 lookahead 后的 cursor再调用 child、重复/跳过 node
  charge、创建 fresh budget、预先做 fieldCount/depth/node/child validation、post-walk、fallback、error remap、
  `partial` 或 `unsafe`。unknown 必须在读取 fieldCount 前逐字返回
  `unknown program-item tag '<tag>'`；tag length/truncation/UTF-8/ASCII错误原样来自 `decodeTagV1`。

  13 路映射 exact 为：`StateDecl→state`、`StructDecl→struct`、`EnumDecl→enum`、
  `ConstDecl→const`、`EventDecl→event`、`ErrorDecl→error`、`InitDecl→init`、
  `EntryDecl→entry`、`ViewDecl→view`、`FnDecl→fn`、`InvariantDecl→invariant`、
  `ExtensionReq→extensionReq`、`ProofDecl→proof`。已知 route 的 fieldCount、depth、node、wire-order、
  local invariant与child errors必须逐字由对应 PA112/115 decoder决定。

  Lean suite 与不 import Lean/ProofForge/既有 reference script 的 standalone Python oracle 必须共同固定
  **13/26/19**。13 个 positive逐字复用 PA102 checked-in item literals，比较 exact ProgramItem value、
  exact-consume/`finish`、byte-identical `encodeProgramItemV1`，并以最小 root-inclusive depth 与恰好 node
  budget成功且 residual=0：`item_state d=2,n=2`、`item_struct d=3,n=3`、
  `item_enum d=3,n=5`、`item_const d=2,n=3`、`item_event d=1,n=1`、
  `item_error d=1,n=1`、`item_init d=4,n=9`、`item_entry d=5,n=12`、
  `item_view d=4,n=5`、`item_fn d=5,n=9`、`item_invariant d=4,n=5`、
  `item_extension_req d=1,n=1`、`item_proof d=1,n=1`。相同 payload shape 的 Event/Error 与
  Entry/View/Fn 必须证明返回 constructor和bytes pairwise nonalias，但不重复计为 positive。

  26 个 exhaustive field-count negatives 是每个 route 的 expected-1/expected+1，均使用 `d=0,n=0`
  证明 dispatcher 已识别 route 且 child fieldCount先于 depth/node：State `2/4`、Struct `1/3`、
  Enum `1/3`、Const `2/4`、Event `1/3`、Error `1/3`、Init `1/3`、Entry `3/5`、
  View `3/5`、Fn `3/5`、Invariant `1/3`、ExtensionReq `2/4`、Proof `1/3`；错误逐字为
  `tag '<tag>' must declare <expected> fields`。

  19 个 boundary slots exact 冻结如下；`bad("X")` 是合法 bounded ASCII tag `X` 且故意不带
  fieldCount，`head(Tag,fc)` 是 tag+exact fieldCount而无 payload，所有 A-before-B 项必须同时携带
  hostile B，禁止 vacuous placeholder：

  1. declared tag length `0` → `tag length must be 1..21 bytes`；2. length `22` →同一错误；
  3. declared length `4` 但只有 `Bo` → `truncated`；4. length1 byte `ff` →
  `invalid UTF-8 tag`；5. UTF-8 `é` → `tag must be ASCII`；6. `bad("BogusItem")` →
  `unknown program-item tag 'BogusItem'`；7. `bad("Type.Bool")` →
  `unknown program-item tag 'Type.Bool'`。上述均 `d=0,n=0`。

  8. `head(StateDecl,3)`、`d=0,n=0` → `depth budget exhausted`；9. 同一 head、
  `d=1,n=0` → `node budget exhausted`；10. State 的 visibility=`Type.Bool` 且后续 hostile →
  `unknown visibility tag 'Type.Bool'`；11. Struct valid name+count0 →
  `struct fields must be nonempty`；12. Enum valid name+count0 →
  `enum variants must be nonempty`；13. Event valid name+count2、`d=2,n=1` → parent charge后的
  `array count exceeds caller limit`；14. Error count1+`bad("BogusParam")` →
  `unknown param tag 'BogusParam'`。

  15. Const valid name+`bad("BogusType")`+hostile value → `unknown type tag 'BogusType'`；
  16. Init count0+empty Block → `block statements must be nonempty`；17. ExtensionReq one-component
  QID+hostile version/digest → `source qualified id must contain 2..256 components`；18. Proof valid
  invariant+one-component theorem →同一 QID error；19. full `item_state || 00` 以 `d=2,n=2`
  解出 value 后 `finish` → `trailing bytes`。10–18 使用足够但不重置的 caller budget，并断言 child
  error逐字透传。

  Python 必须 assert-free，normal/`-O` 都通过，非精确 argv 输出 usage 且 exit 2，只打印
  `reference_source_ast_program_item_decode_v1: ok 13 26 19`。它独立实现 bounded tag lookahead、
  closed route/field-count table和上述 malformed/unknown priority，并直接持有13个 fixed bytes；不得调用
  Lean、production decoder或其他 reference script形成自证循环。

  变更文件集：新增`ProofForgeV2/Source/AstProgramItemDecodeV1.lean`、
  `Tests/Language/SourceAstProgramItemDecodeV1.lean`、
  `scripts/reference_source_ast_program_item_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/
  `lakefile.lean` registration与机械manifest refresh，不修改 PA93–115 model/codec/decoder、WireDecode、
  ValidatedSource或其他production modules。budgets：production≤100、suite≤360、Python≤260、
  registrations≤5、总authored additions≤725（manifest不计）。明确排除 Program/Program array/nonempty、
  canonical root/exact-consume root API、fresh `256/100000` session、16MiB、declaration-set validation、
  frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/第二 quoted decoder/fallback、
  sourceHash/NodeId/stable Diagnostic/Typed/Semantic/target。RED必须只因production module缺失；GREEN只运行
  focused+aggregate build/test binary、direct Lean suite、Python normal/`-O`/invalid argv、package refresh后
  最终单次`just sbom`、docs/diff与main-agent self-review，不声称independent review，不运行完整`just ci`。
  结果只记录development evidence，不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-117 是 accepted `ADR-0019` step-3 完整 root decoder prerequisite 的 complete
  `ProgramV1` tagged-value decoder slice。它只读复用 PA116 `decodeProgramItemV1`；不修改 Program model/
  codec、任一 item/child decoder或 validator。moduleName/programIdentity 与 canonical root 继续排除。
  production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstProgramDecodeV1
  decodeProgramV1 (d : Nat) (budget : DecodeBudgetV1) :
    WireDecodeV1.DecoderV1 (AstProgramV1.ProgramV1 × DecodeBudgetV1)
  ```

  decoder 固定执行 tag `Program`→closed-family unknown→fieldCount `2`→depth→Program parent node charge→
  raw name→u32 item count→nonempty→post-charge count cap→source-order items。`d=0` 仍先验证 exact head；
  成功分支每个 item 接收 parent `d-1` 与前一 sibling 返回的同一 session-wide node residual。
  count cap针对 Program charge后的 residual，必须在首个 item decode/allocation前执行；count0先返回
  `program items must be nonempty`。unknown逐字为 `unknown program tag '<tag>'`。禁止 fresh
  `256/100000` budget、default root helper、重复/跳过 Program node、预先做 child validation、post-walk、
  declaration-set validation、fallback、error remap、`partial` 或 `unsafe`。

  Lean suite 与不 import Lean/ProofForge/既有 reference script 的 standalone Python oracle共同固定
  **3/2/17**。三个 positive逐字复用 PA103 checked-in literals并比较 exact Program value、
  exact-consume/`finish`、byte-identical `encodeProgramV1`、node residual=0：`prog_state_only d=3,n=3`、
  `prog_two_order d=3,n=6`、`prog_two_reversed d=3,n=6`。后两者必须证明 item source order的 value/bytes
  nonalias；state-only mechanical value必须成功，不得在 decoder混入 zero-entry/view 等 set validation。
  两个 field-count negatives把 Program/2改为1与3，均以`d=0,n=0`返回
  `tag 'Program' must declare 2 fields`，证明 fieldCount先于depth/node。

  17 个 boundary slots exact 冻结如下；`bad("X")`是合法 bounded ASCII tag且故意不带fieldCount，
  `head(Tag,fc)`是tag+fieldCount而无payload，`STATE`/`CONST`逐字使用 PA103 item bytes；每个
  A-before-B项必须同时携带 hostile B：

  1. declared tag length0 → `tag length must be 1..21 bytes`；2. length1 byte `ff` →
  `invalid UTF-8 tag`；3. `bad("StateDecl")` → `unknown program tag 'StateDecl'`；4. exact Program/2
  head、`d=0,n=0` → `depth budget exhausted`；5. 同一head、`d=1,n=0` →
  `node budget exhausted`。

  6. Program name declared length0 + hostile count →
  `source name component must contain 1..240 UTF-8 bytes`；7. valid `Demo` + count0 →
  `program items must be nonempty`；8. `Demo` + count2、`d=2,n=2` → Program charge后的
  `array count exceeds caller limit`；9. count `0xffffffff`、`d=2,n=100` →同一 cap，且不得分配；
  10. count1+`bad("BogusItem")` → `unknown program-item tag 'BogusItem'`；11. count1+
  `bad("Type.Bool")` → `unknown program-item tag 'Type.Bool'`。

  12. full `prog_state_only`、`d=2,n=3` → child `depth budget exhausted`；13. 同一bytes、
  `d=3,n=2` → child `node budget exhausted`；14. count2+`STATE`+`bad("BogusItem")` → second-item
  unknown；15. count2+`STATE`+Struct valid name/count0 → second-item
  `struct fields must be nonempty`；16. count2+Const valid name+`bad("BogusType")`+hostile value+
  `STATE` → first-item `unknown type tag 'BogusType'`，不得访问第二项；17. `prog_state_only || 00`
  以`d=3,n=3`解出value后`finish` → `trailing bytes`。10–16使用足够但不重置的caller budget，
  child错误全部逐字透传。

  Python 必须 assert-free，normal/`-O`均通过，非精确argv输出usage且exit 2，只打印
  `reference_source_ast_program_decode_v1: ok 3 2 17`。它独立实现 Program head/name/count/nonempty/cap、
  caller-budget threading与可注入 item stubs，直接持有三个 fixed bytes；不得调用 Lean、production
  decoder或其他 reference script形成自证循环。

  变更文件集：新增`ProofForgeV2/Source/AstProgramDecodeV1.lean`、
  `Tests/Language/SourceAstProgramDecodeV1.lean`、`scripts/reference_source_ast_program_decode_v1.py`；
  只做`ProofForgeV2.lean`/`Tests.lean`/`lakefile.lean` registration与机械manifest refresh，不修改
  PA93–116 model/codec/decoder、WireDecode、ValidatedSource或其他production modules。budgets：
  production≤100、suite≤300、Python≤280、registrations≤5、总authored additions≤700（manifest不计）。
  明确排除 canonical root/module/program identity join、root exact-consume API、fresh session/16MiB、
  declaration-set validation、frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/第二
  quoted decoder/fallback、sourceHash/NodeId/stable Diagnostic/Typed/Semantic/target。RED必须只因production
  module缺失；GREEN只运行focused+aggregate build/test binary、direct Lean suite、Python normal/`-O`/
  invalid argv、package refresh后最终单次`just sbom`、docs/diff与main-agent self-review，不声称independent
  review，不运行完整`just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending
  TASK-D1-01或下游task。
- D1-PA-118 是 accepted `ADR-0019` step-3 的完整 canonical root decoder slice。它只读组合 PA117
  `decodeProgramV1`、PA92/94 source-qualified-name decoder 与 PA108 `validateSourceV1`；不修改既有
  model/codec/decoder/validator。production public API 精确冻结为：

  ```lean
  namespace ProofForgeV2.Source.AstCanonicalRootDecodeV1
  decodeCanonicalSourceAstBytesV1 (input : ByteArray) :
    Except String ValidatedSourceV1.ValidatedSourceV1
  ```

  root orchestration 的 exact 顺序固定为：输入 byte size 上限 → 从 offset 0 解 module
  `SourceQualifiedNameV1`（count 1..256）→ 解 program identity `SourceQualifiedIdV1`（count 2..256）→
  **恰好一次**创建 `{ remainingNodes := 100000 }` 并调用
  `decodeProgramV1 256` → `finish` exact consume → `validateSourceV1`。16 MiB 精确为
  `16 * 1024 * 1024` bytes；等于上限继续解码，首次超过在读取任何 root byte 前逐字返回
  `source exceeds the 16 MiB limit`。module/program identity 不消耗 AST node/depth；Program 是
  root-inclusive depth 的第一个 node。禁止 caller/CLI/source/target 注入或放宽 depth/node limit、按 item
  重置 budget、decode 后 post-walk 计数、跳过 finish、返回 partial Program 或另建 validator/identity join。

  错误优先级固定为 size cap → module QN wire → program QID wire → 完整 Program wire/depth/node → trailing
  bytes → PA108 validation。最后一步原样保持既有 identity strict-prefix join → Program raw name equality →
  codec-local shape → declaration-set source-order 首诊断；root decoder不得 remap child/finish/validator error。
  因而 trailing 与 identity/name/set 同时错误时必须返回 `trailing bytes`；Program local shape 与 trailing/
  identity 同时错误时仍由 Program child error先返回。成功只返回 private-constructor
  `ValidatedSourceV1`，不得计算/store sourceHash、登记 environment extension或进入 D2。

  Lean suite 与不 import Lean/ProofForge/既有 reference script 的 standalone Python oracle共同固定
  **3/15**。三个 positives 为：

  1. 逐字复用 PA108 的 195-byte `Root` / `Root.Demo` State→Entry canonical root，比较 decoded unit 三个
     projections、`canonicalValidatedSourceAstBytesV1` byte-identical re-encode；
  2. State type 为 `Option^253(Bool)` 且另含 minimal Entry 的 root，最长路径精确为
     Program + State + 254 Type nodes = 256，成功并 byte-identical re-encode；
  3. 单 Entry 的 Block 含 99994 个 `Stmt.Return none`，再含一个
     `Stmt.Return (some (Expr.Literal (Literal.Bool true)))`；Program+Entry+Type.Unit+Block 固定4 nodes，
     statements/expr固定99996 nodes，总计100000，成功并 byte-identical re-encode。

  15 个 boundary slots exact 冻结如下；所有 priority 项都同时携带 hostile 后续字段，不能用 vacuous
  truncation 冒充：

  1. `16MiB+1` 个 zero bytes → size error，先于非法 module count；2. 195-byte valid root 后补 zero 至
  恰好16MiB → `trailing bytes`，证明 equal-limit未被 cap 拒绝；3. module count0 + hostile identity/
  Program → `source qualified name must contain 1..256 components`；4. module count1、首 component declared
  length0 + hostile identity → `source name component must contain 1..240 UTF-8 bytes`；5. valid module 后
  program identity count1 + hostile Program → `source qualified id must contain 2..256 components`。

  6. valid module/identity 后 `bad("StateDecl")` → `unknown program tag 'StateDecl'`；7. valid names 后的
  Entry 含 empty Block，并同时追加 trailing byte、使用 non-prefix identity →
  `block statements must be nonempty`；8. fully decoded state-only Program同时具有 trailing byte、non-prefix
  identity与zero-entry/view → `trailing bytes`；9. 去掉 trailing 后同时 non-prefix、wrong Program name与
  zero-entry/view → `program identity must begin with the exact module name components`；10. valid prefix但
  wrong Program name且zero-entry/view → `program name must equal the last program identity component`；
  11. valid identity/name的state-only Program → `program must declare at least one entry or view`。

  12. State type `Option^254(Bool)` + minimal Entry形成257-node最长路径 →
  `depth budget exhausted`；13. 单 Entry Block含99995个Return-none再含一个Return-some-Bool，array count
  恰等Block charge后的residual但总nodes=100001，必须在最后Expr parent charge返回
  `node budget exhausted`，不得由count cap或fresh budget放行；14. module count257且不附components →
  QN count error；15. valid module后identity count257且不附components → QID count error。大边界fixture不得
  进入git；Lean/Python均在test process内确定构造，且不得通过production encoder产生cap/priority输入。

  Python 必须 assert-free，normal/`-O`均通过，非精确argv输出usage且exit 2，只打印
  `reference_source_ast_canonical_root_decode_v1: ok 3 15`。它独立实现本矩阵所需的 raw QN/QID、selected
  Program/State/Entry/Type/Block/Return/Literal wire、fresh depth/node budget、finish、identity/name与最小
  declaration-set validation；不得调用 Lean、production decoder/encoder或其他 reference script形成自证循环。

  变更文件集：新增`ProofForgeV2/Source/AstCanonicalRootDecodeV1.lean`、
  `Tests/Language/SourceAstCanonicalRootDecodeV1.lean`、
  `scripts/reference_source_ast_canonical_root_decode_v1.py`；只做`ProofForgeV2.lean`/`Tests.lean`/
  `lakefile.lean` registration与机械manifest refresh，不修改 PA92–117、ValidatedSource、root encoder或其他
  production modules。budgets：production≤80、suite≤360、Python≤380、registrations≤5、总authored
  additions≤825（manifest不计）。明确排除 frontend/Loader/CLI/Lean command、ProgramExport v2/
  ProgramPayload cutover、legacy删除或bridge、dual reader、第二套quoted ProgramV1 decoder、fallback、
  sourceHash/NodeId/stable Diagnostic/Typed/Semantic/target。RED必须只因production module缺失；GREEN只运行
  focused+aggregate build/test binary、direct Lean suite、Python normal/`-O`/invalid argv、package refresh后
  最终单次`just sbom`、docs/diff与main-agent self-review，不声称independent review，不运行完整`just ci`。
  结果只记录development evidence；即使 root API 闭合，也不能自动关闭TST-SRC-001、pending
  TASK-D1-01或启动frontend/export cutover。
- D1-PA-119 是 PA118 exact 100000-node positive 暴露的 canonical encoder wide-array stack-safety
  prerequisite。它只把 `AstPatternCodecV1` 的 `encodePatternListV1` 与 `AstSpineCodecV1` 的
  `encodeExprListV1`、`encodeExprMatchArmListV1`、`encodeStmtMatchArmListV1`、`encodeStmtListV1` 从
  cons-after-recursion 改为结构递减的 tail accumulator；全部 public encoder API、constructor dispatch、
  validation/error priority与canonical bytes必须逐字不变，不新增production public symbol。

  五个private array wrapper仍从底层List结构取得source order，但必须以empty `Array ByteArray` accumulator
  调用各自helper；每个helper严格执行 head encoder → `chunks.push headBytes` → 对tail做tail-position recursive
  call，empty list返回accumulator。禁止reverse、先编码tail、`partial`、`unsafe`、post-hoc reorder、调大
  `--tstack`、改变wire helper、跳过child validation或把全局node limit塞进encoder。此切片只移除array-width
  导致的host stack dependence；AST nesting仍由既有结构递归与PA118 decoder的256 depth约束拥有。

  Lean tests固定 **5/10**，并使用test-owned primitive wire builders比较完整bytes，不以production encoder生成
  expected。五个wide positives都位于100000-node root-session上限内且必须在默认direct runner中成功：

  1. `Pattern.Constructor`含99999个Wildcard args，总node=100000；
  2. `Expr.Constructor`含99999个Bool-literal Expr args，总node=100000；
  3. `Expr.Match`含一个Bool scrutinee与33332个`Wildcard→Bool` ExprMatchArm，总node=99998；
  4. `Stmt.Match`含一个Bool scrutinee与24999个`Wildcard→Block(Return none)` StmtMatchArm，总node=99998；
  5. `Block`含99999个`Return none` statements，总node=100000。

  每例production bytes必须等于手工`tag/fieldCount/u32 count/repeated child`组合，因而同时固定count、child
  source order与无遗漏/重复。10个dual-fault order negatives按每个helper各一对正反数组固定head-before-tail：
  Pattern bad one-component QID vs bad u256 literal分别返回
  `source qualified id must contain 2..256 components`/`u256 magnitude exceeds 2^256-1`；Expr bad u256 vs bad
  QID同理；ExprMatchArm bad-pattern-QID vs bad-value-u256；StmtMatchArm bad-pattern-QID vs empty Block（后者
  `block statements must be nonempty`）；Block statements invalid For bound vs empty Stmt.Match arms，分别返回
  `for bound must be 0..4096`/`stmt match arms must be nonempty`。每对交换后错误必须随第一个child变化。

  变更文件集精确为修改`ProofForgeV2/Source/AstPatternCodecV1.lean`与
  `ProofForgeV2/Source/AstSpineCodecV1.lean`，新增`Tests/Language/SourceAstWideEncoderV1.lean`，只做
  `Tests.lean`/`lakefile.lean` registration与机械manifest refresh。production additions≤45、suite≤300、
  registrations≤3、总authored additions≤348（manifest不计）；允许删除被替代的private helper行，净行数不作为
  绕过addition budget。明确排除model/decoder/validator/root API、wire schema/error、frontend/Loader/CLI/
  Lean command/export v2、legacy bridge/dual reader/fallback、sourceHash/NodeId/stable Diagnostic/Typed/Semantic/
  target。tests-only RED必须在默认direct runner中以既有deep-recursion失败；GREEN运行focused+direct+
  aggregate/test binary、PA118 direct regression、package refresh后最终单次`just sbom`、docs/diff与main-agent
  self-review，不声称independent review，不运行完整`just ci`。结果只记录development evidence，不能关闭
  PA118、TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-120 是完整 ProgramV1 NodeId assigner 的 source-identity/preimage prerequisite。它只纠正既有
  `ProofForgeV2.Source.WireV1.nodeIdPreimageV1`：module/program identity 从 Common `QualifiedName`
  rendered component carrier迁移为 `SourceQualifiedNameV1` raw component array，返回面从alpha
  `CompileResult`收敛为本层既有`Except String`；`NodePathSegmentV1`、`NormalizedSyntacticPathV1`与closed
  parentTag/fieldTag/cardinality/transition inventory保持public形状和语义不变。冻结API为：

  ```lean
  nodeIdPreimageV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (path : NormalizedSyntacticPathV1) : Except String ByteArray
  ```

  实现必须先调用`validateSourceProgramIdentityV1`，再把两个identity逐component直接投影
  `SourceNameComponentV1.raw`为PF-JCS string array；禁止`Name.toString`、
  `renderSourceNameComponentV1`、Common `QualifiedName` render/validation、dot split/join或guillemet spelling。
  path仍先固定root-inclusive最多255 edges，再按source order验证首segment从Program开始、前一edge允许当前
  parent constructor、closed 63-pair inventory与direct index=0，随后输出JCS object；PF-JCS key order和domain
  精确为`ASCII("pf.source-node.v1") || 00 || JCS({module,program,path})`。identity错误先于path/JCS，path按
  array order返回首错；错误detail不包alpha `CompileError`且不得remap。

  既有`Tests.Language.SourceIdentity`的63-pair（44 direct/19 array）全成员、cross-pair nonmember、255/256
  edge与root/first-item literal vectors必须原样保留并迁移到source carrier。新增固定 raw-JCS vector使用
  module `#["A.B"]`、program `#["A.B", "P\"Q\\R"]`及Program.items index1，逐字比较preimage bytes与
  SHA-256；它必须与component-split twin `#["A","B"]`/`#["A","B","P\"Q\\R"]` nonalias，证明raw dot、
  quote与backslash经JCS转义但不经Lean renderer。另固定三个合法path twins使parentTag、fieldTag、index任一
  改变都改变preimage；API结构上不得接受path/span/file/comment/container参数。

  exact negatives至少固定：program identity count1、module=program但二者count2、non-prefix identity、
  Program.name scalar pair、unknown constructor/field pair、non-Program first edge、impossible transition、
  direct index1与256-edge over-depth；前三者逐字使用`source qualified id must contain 2..256 components`、
  `program identity must strictly extend the module name`、
  `program identity must begin with the exact module name components`，其余沿用既有path detail。
  standalone assert-free Python oracle必须独立实现raw identity join、closed selected path validation与JCS，固定
  4个positive/9个negative并只输出`reference_source_node_id_preimage_v1: ok 4 9`；normal/`-O`均通过，
  invalid argv usage+exit2，不得import Lean/ProofForge或其他reference script。

  变更文件集精确为修改`ProofForgeV2/Source/WireV1.lean`与
  `Tests/Language/SourceIdentity.lean`，新增`scripts/reference_source_node_id_preimage_v1.py`，机械刷新
  `supply-chain/lean-package-files.v1.json`；不新增Lean registration或public module。production additions≤90、
  Lean additions≤100、Python≤260、总authored additions≤450（manifest不计），允许删除alpha Common/Diagnostic
  adapter行。明确排除ProgramV1 traversal/assigner、NodeOriginTable、production SHA truncation、test candidate
  injection、collision/duplicate-visit、span/origin integration、golden corpus packaging、frontend/Loader/CLI/
  Lean command/export v2、legacy bridge/dual reader/fallback、stable Diagnostic/Typed/Semantic/target。
  tests-only RED必须只因旧production API仍要求Common carrier/CompileResult而失败；GREEN运行focused
  `SourceIdentity`与`SourceWireAcceptance`、aggregate/test binary、Python normal/`-O`/invalid argv、package
  refresh后最终单次`just sbom`、docs/diff与main-agent self-review，不声称independent review，不运行完整
  `just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-121 是完整 ProgramV1 NodeId assigner 的 canonical node-visit prerequisite。它只新增
  `ProofForgeV2.Source.NodeTraversalV1`，把已经由`SPEC-SOURCE-WIRE-001`冻结的57个node-bearing constructor
  与63个node-bearing child pair物化为显式worklist preorder；不计算preimage/hash/NodeId，也不定义
  `NodeOriginTableV1`或collision seam。冻结public carrier/API为：

  ```lean
  structure NodeVisitV1 where
    constructorTag : String
    path : NormalizedSyntacticPathV1

  canonicalNodeVisitsV1
    (program : ProgramV1) : Except String (Array NodeVisitV1)
  ```

  root必须首先产生`{constructorTag := "Program", path := #[]}`。随后按每个wire constructor的ordered fields
  只遍历node-bearing child：direct child与present option child追加`index=0`，array child按source-order index；
  absent option、empty array、Visibility、Literal、UnaryOp、BinaryOp、Ident/QID与其他scalar不产生visit或path
  segment。每段的`parentTag`/`fieldTag`必须逐byte等于wire表；visit的`constructorTag`必须等于实际child的wire
  tag。实现必须使用显式LIFO worklist，按reverse field/source order push以获得canonical preorder；禁止递归
  walker、allocator/address/hash-map iteration或任何target/profile分支。helper只枚举调用方已完成shape validation的
  ProgramV1，不重复identity、declaration-set、codec或semantic validation，也不重排/修复invalid direct value。

  traversal自身固定root-inclusive最多256 levels与最多100000 visits，全量成功后才返回Array；第257层逐字失败
  `source node traversal exceeds the nesting bound`，第100001个visit逐字失败
  `source node traversal exceeds the node limit`，不得返回partial prefix。任何待push array若已单独超过100000 children
  可直接返回同一node-limit error，从而在UInt32 index转换前fail closed；成功路径的index因此必在`0..99999`。
  nesting与node同时越界时按actual canonical worklist推进所得首错，不增加stable Diagnostic code；正式
  `PF-BOUND-001`/`PF-INTERNAL`映射仍留给完整assigner/frontend边界。

  Lean suite必须包含一个独立手写comprehensive ProgramV1 fixture，固定完整visit inventory text的SHA-256与
  visit count，并证明57/57 constructor tags、63/63 parent/field pairs、root/items及多元素array index全部exact
  覆盖；每个产出path必须经既有source-raw `nodeIdPreimageV1`接受，且path在同一遍历中唯一。另以小型fixture
  逐项固定mixed direct-field order、present/absent option、empty/nonempty array、scalar exclusion及source-order
  twins；253/254层Option chain分别闭合256/257 root-inclusive边界，99999/100000个leaf items分别闭合
  100000/100001 visit边界。standalone assert-free Python oracle必须以不共享Lean代码的generic tagged-node
  worklist重建同一comprehensive inventory digest与边界，normal/`-O`输出同一固定`ok P N`摘要，invalid argv
  usage+exit2；不得import Lean/ProofForge或其他reference script。

  变更文件集精确为新增`ProofForgeV2/Source/NodeTraversalV1.lean`、
  `Tests/Language/SourceNodeTraversalV1.lean`与`scripts/reference_source_node_traversal_v1.py`，只修改
  `ProofForgeV2.lean`、`Tests.lean`、`lakefile.lean`及`Tests/Language/SourceWireAcceptance.lean`做registration，
  并机械刷新`supply-chain/lean-package-files.v1.json`。production≤360行、Lean suite≤450行、Python≤320行、
  registrations additions≤8、总authored additions≤1150（manifest不计）。明确排除module/program identity、
  preimage逻辑修改、production SHA-256 truncation、NodeId/NodeOriginTable、candidate injection、collision/
  duplicate-visit seam或诊断、span/origin integration、完整golden corpus packaging、frontend/Loader/CLI/Lean
  command/export v2、legacy bridge/dual reader/fallback、Typed/Semantic/target。

  tests-only RED必须只因新production module/API不存在而失败，且Python oracle先独立通过；GREEN运行focused
  module/suite与`SourceWireAcceptance` direct、aggregate/test binary、Python normal/`-O`/invalid argv、package
  refresh后最终单次`just sbom`、docs/diff与main-agent self-review，不声称independent review，不运行完整
  `just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-122 是完整 ProgramV1 NodeId assigner 的 fixed production SHA-256 truncation prerequisite。它只在
  `ProofForgeV2.Source.WireV1`新增以下API，不修改PA120 preimage/path逻辑：

  ```lean
  nodeIdV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (path : NormalizedSyntacticPathV1) : Except String NodeId
  ```

  `nodeIdV1`必须且只调用既有`nodeIdPreimageV1`取得canonical preimage，随后使用锁定
  `ProofForgeV2.Crypto.sha256`对exact bytes计算32-byte digest，并取offset `[0,16)`原始bytes构造Common
  `NodeId`；返回前调用`validateNodeId`证明恰好16 bytes。它不得接受preimage、digest/candidate callback、
  CLI/environment/extension/target/profile参数，不得使用hex string round-trip、last 16 bytes、重排、重新加盐、
  扩宽或fallback。identity/path错误必须逐字原样传播且先于hash；本API不维护table或检测collision。

  `SourceIdentity`必须在既有root、first-item与raw escaped三个literal preimage/full-SHA vectors上分别固定
  `nodeid:58c75af894b6f832163564705c9f23ef`、
  `nodeid:17ac87bb9262ace7d062c77c38a17d0d`、
  `nodeid:1d20bd4f37f942a52977fa9aade547fb`，同时检查raw bytes size16、Common validate/render round-trip，及
  split-component、parentTag、fieldTag、index known twins的candidate nonalias。至少一个identity error与一个
  path error必须证明`nodeIdV1`和`nodeIdPreimageV1` detail相同。既有standalone assert-free Python oracle在
  4 positives/9 negatives与full SHA不变的前提下增加`digest()[:16]`和`nodeid:` fixed checks；normal/`-O`
  仍只输出`reference_source_node_id_preimage_v1: ok 4 9`，invalid argv usage+exit2。

  变更文件集精确为修改`ProofForgeV2/Source/WireV1.lean`、`Tests/Language/SourceIdentity.lean`与
  `scripts/reference_source_node_id_preimage_v1.py`，并机械刷新`supply-chain/lean-package-files.v1.json`；
  不新增module/registration。production additions≤24、Lean additions≤60、Python additions≤30、总authored
  additions≤120（manifest不计）。明确排除ProgramV1 traversal修改、assigner/`NodeOriginTableV1`、map/order、
  test candidate injection、collision/duplicate-visit、stable Diagnostic、span/origin join、golden corpus packaging、
  frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/fallback、Typed/Semantic/target。

  tests-only RED必须只因`nodeIdV1` production identifier不存在而失败，且Python oracle先独立通过；GREEN运行
  focused `WireV1`/`SourceIdentity`与`SourceWireAcceptance` direct、aggregate/test binary、Python
  normal/`-O`/invalid argv、package refresh后最终单次`just sbom`、docs/diff与main-agent self-review，不声称
  independent review，不运行完整`just ci`。结果只记录development evidence，不能关闭TST-SRC-001、pending
  TASK-D1-01或下游task。
- D1-PA-123 是完整 ProgramV1 NodeId assigner 的 opaque table与production success-path prerequisite，并同步
  澄清`SPEC-SOURCE-WIRE-001`中此前未展开的`NodeOriginTableV1` observable carrier/order。冻结API为：

  ```lean
  structure NodeIdAssignmentV1 where
    constructorTag : String
    path : NormalizedSyntacticPathV1
    nodeId : NodeId

  structure NodeOriginTableV1 where
    private mk ::
    private assignments : Array NodeIdAssignmentV1

  nodeAssignmentsPreorderV1
    (table : NodeOriginTableV1) : Array NodeIdAssignmentV1

  assignNodeIdsV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String NodeOriginTableV1
  ```

  `nodeAssignmentsPreorderV1`结果必须与PA121 `canonicalNodeVisitsV1`逐项相同的canonical preorder；root index0、每个visit恰一项，
  constructorTag/path原样复制，nodeId逐项等于PA122 `nodeIdV1(moduleName,programIdentity,path)`。table constructor
  private，失败不返回partial table；table是pre-span carrier，不含source path/span/sourceHash，也不是Common
  `SourceOrigin`或Semantic `SourceNodeInventoryV1`。后续frontend可按preorder join immutable syntax span，只有构造
  inventory时才按NodeId raw bytes排序；不得反向改变table order。

  assigner先直接调用`validateSourceProgramIdentityV1`一次完成identity fail-fast，再调用PA121 traversal；它不重复
  Program/declaration/codec validation。逐项复用PA120/122 public helper时保留其defensive identity/path validation，
  不得复制或绕过helper来伪造“只验证一次”。随后按visit order构造canonical preimage与fixed production NodeId，并以
  `Std.HashMap ByteArray`按16 raw candidate bytes维护internal exact `{preimage,path}`。首次candidate插入并append
  assignment；existing candidate若preimage byte-equal，逐字失败`PF-INTERNAL: duplicate-node-visit`；否则逐字失败
  `PF-SRC-NODEID-COLLISION: distinct canonical source node preimages produced the same NodeId`。internal preimage/map
  不进入table，不依赖map iteration order；禁止hex key、first/last winner、partial prefix、salt/fallback或target branch。

  `SourceNodeTraversalV1`在既有214-visit comprehensive fixture上必须证明table size214、每个assignment的tag/path与
  visit exact相等、每个NodeId与`nodeIdV1` exact相等、path和NodeId均唯一、root fixed ID不变；另固定root items
  source-order twin table顺序。bad identity与over-depth Program同时存在时必须先返回identity detail，证明identity
  fail-fast；合法identity+over-depth保留PA121 traversal error。本slice只验证真实SHA success path和可达错误顺序；
  forced collision/duplicate branch的test-build-only candidate/traversal seam明确留给下一独立slice，不能据此声称
  collision acceptance闭合。

  变更文件集精确为新增`ProofForgeV2/Source/NodeAssignmentV1.lean`，修改
  `Tests/Language/SourceNodeTraversalV1.lean`，只在`ProofForgeV2.lean`增加registration并机械刷新manifest；不新增
  test module/Python/runner registration。production≤150行、Lean additions≤100、registration additions≤1、
  总authored additions≤270（manifest不计）。明确排除修改PA120/121/122逻辑、candidate callback/test seam、
  forced collision/duplicate fixture、stable Diagnostic type、span/origin/inventory join、golden corpus packaging、
  frontend/Loader/CLI/Lean command/export v2、legacy bridge/dual reader/fallback、Typed/Semantic/target。

  tests-only RED必须只因新production module/API不存在而失败；GREEN运行focused module/suite与
  `SourceWireAcceptance` direct、aggregate/test binary、既有PA121/122 Python oracles、package refresh后最终单次
  `just sbom`、docs/diff与main-agent self-review，不声称independent review，不运行完整`just ci`。结果只记录
  development evidence，不能关闭collision/duplicate验收、TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-124 闭合ProgramV1 NodeId forced collision/duplicate-visit与test-only seam，但不进入span/frontend。为同时
  复用production exact loop并从release API排除callback，本slice把PA123 loop机械重构为
  `ProofForgeV2.Source.NodeAssignmentV1`导出的compile-time term macro `source_node_assignment_loop_v1%`：macro
  参数为module/program identity、ProgramV1、candidate closure、visit transform与finish closure；展开体唯一拥有
  identity→traversal→preimage→candidate-size→raw-map→assignment/error顺序。production `assignNodeIdsV1`在同文件
  用该macro生成，candidate closure仍硬调用PA122 `nodeIdV1`，visit transform为identity，finish closure才可使用
  private table constructor。macro不是runtime function、不能覆盖已编译production symbol，也不得注册到frontend。

  独立`Tests.Language.SourceNodeAssignmentCollisionV1`使用同一macro生成test-only adapter：

  ```lean
  abbrev NodeIdCandidate16V1 := ByteArray → Except String ByteArray

  assignNodeIdsV1ForTestWithCandidate
    (candidate16 : NodeIdCandidate16V1)
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String (Array NodeIdAssignmentV1)
  ```

  Array是`nodeAssignmentsPreorderV1`的唯一observable projection，按本次normative amendment与opaque table结果语义
  相同。public test adapter只使用identity visit transform；duplicate fixture另在同一Tests file内使用private core
  把canonical root visit精确重放一次，不暴露第二个public seam。candidate只收到PA120 canonical preimage；返回
  不是16 bytes时逐字失败`node id candidate must contain exactly 16 raw bytes`，其自身error逐字传播，且任何失败
  都不返回partial array。

  positives必须以`SHA-256(preimage)[0,16)` callback在至少Program→State→Type fixture上逐项等于production table
  projection，并保持PA123 comprehensive regression。constant 16-zero-byte callback必须在第二个distinct preimage
  稳定返回`PF-SRC-NODEID-COLLISION: distinct canonical source node preimages produced the same NodeId`；private
  duplicate-root transform配real-SHA callback必须返回`PF-INTERNAL: duplicate-node-visit`，配constant callback仍必须
  duplicate优先。另固定15/17-byte candidate、callback error、bad identity与candidate-never-called priority。

  新增assert-free `scripts/check_source_node_assignment_test_seam.py`必须验证production package manifest不含Tests
  module、全部70个production source与`ProofForgeV2.lean`不含test adapter symbol、Tests file恰有该definition；随后
  以临时root-contained Lean probe只import `ProofForgeV2`并`#check`该fully-qualified test symbol，必须unknown，且
  production `proof-forge-next` binary raw bytes不含symbol。test binary包含它不构成release泄漏。checker normal/`-O`
  输出同一`source-node-assignment-test-seam: ok`，invalid argv exit2。

  变更文件集精确为修改`ProofForgeV2/Source/NodeAssignmentV1.lean`，新增
  `Tests/Language/SourceNodeAssignmentCollisionV1.lean`与上述checker，只修改`Tests.lean`、`lakefile.lean`及
  `SourceWireAcceptance.lean`做registration，并机械refresh manifest。production file总行数≤180、test suite≤240、
  checker≤140、registrations additions≤5、总authored additions≤520（manifest不计），允许删除被macro替代的PA123
  loop行。明确排除公开runtime generic/candidate function、修改production SHA/preimage/traversal/table semantics、
  stable Diagnostic type、span/origin/inventory、golden corpus packaging、frontend/Loader/CLI/Lean command/export v2、
  legacy bridge/dual reader/fallback、Typed/Semantic/target。

  tests-only RED必须只因production shared term macro不存在而失败；提交前以未提交nonfunctional macro stub证明suite
  可编译且direct保持RED，再删除stub确认missing macro。GREEN运行focused collision suite与
  `SourceWireAcceptance` direct、production release build/exclusion checker normal/`-O`/invalid argv、aggregate/test
  binary、PA121/122 Python oracles、package refresh后最终单次`just sbom`、docs/diff与main-agent self-review；不声称
  independent review，不运行完整`just ci`。只能记录development evidence，不能关闭完整golden/span面、TST-SRC-001、
  pending TASK-D1-01或下游task。
- D1-PA-125 建立constructed validated ProgramV1的单一full-tag positive wire golden package prerequisite；它只闭合
  production encoder/decoder/sourceHash/NodeId与不import Lean/ProofForge的Python实现之间的checked-in payload契约，
  不声称完成含`sourceUtf8`、Lean command、Loader或span的最终`GoldenSourceProgramV1`。fixture必须经
  `validateSourceV1`，module固定`#["Golden"]`，program identity固定`#["Golden", "FullTag"]`，case ID固定
  `full-tag-valid-v1`。同一个ProgramV1必须覆盖closed 84 wire tags、57 node-bearing tags与63 child-edge pairs，且
  declaration-set valid：13种ProgramItem各至少一次、恰一个init、entry/view/fn名称互异、proof引用已声明invariant，
  每个需要nonempty的array/block均合法，所有需唯一的field/variant/parameter/name集合无重复。

  fixture还必须在同一package中固定三种Visibility；UInt/Int各`8/16/32/64/128/256`；Array/Bytes length `0/4096`；
  For bound `0/4096`；Bool `false/true`；Integer `0/(2^256-1)`；NFC Unicode Ident/String；empty/single/multiple array；
  `Stmt.Let.typeAnn`、`Stmt.If.elseBlock`、`Stmt.Assert.error`、`Stmt.Return.value`各自的none/some；三种UnaryOp与
  18种BinaryOp；全部Type/Stmt/Expr/Place/Pattern alternatives。decimal/hex source-spelling equivalence属于后续
  source-bound golden，不得由constructed AST冒充。

  checked-in package路径固定为：

  ```text
  testdata/golden/source-program-v1/full-tag-v1/manifest.json
  testdata/golden/source-program-v1/full-tag-v1/canonical.bin
  ```

  manifest schema固定`proof-forge.source-program-wire-golden-prerequisite.v1`，scope固定
  `constructed-validated-programv1-no-frontend`，并包含caseId、moduleName、programIdentity、canonicalFile、
  `canonicalBytesSha256`、`expectedSourceHash`、ASCII unique sorted `wireTags`、ASCII unique sorted `nodeTags`、
  按`(parentTag,fieldTag)` unique sorted `edgePairs`及canonical preorder `expectedNodePathsAndIds`；每个node row
  exact包含`constructorTag`、path的`parentTag/fieldTag/index`和lowercase `nodeid:`。JSON必须是UTF-8、LF、
  recursively sorted keys、two-space indent、final newline；`canonical.bin`保存raw bytes而不是hex/base64。
  Python checker必须同时验证raw file SHA-256、domain-separated sourceHash、decode/re-encode由Lean suite闭合、
  tag/edge closed inventory、path唯一、NodeId preimage/SHA first-16和manifest逐项相等，不能只比较最终hash。

  新增`Tests.Language.SourceProgramWireGoldenV1`必须手工构造同一fixture并读取package，不从manifest/JSON decode
  ProgramV1；它验证validated production bytes与`canonical.bin`逐byte相等、sourceHash、production root decoder
  exact value/re-encode，以及production `assignNodeIdsV1`的每个tag/path/NodeId与manifest逐项相等。新增assert-free
  `scripts/reference_source_program_wire_golden_v1.py`独立定义同一logical fixture、84-tag encoder、57/63 traversal与
  PF-JCS NodeId；CLI只允许`--emit`与`--self-check`，self-check不得写文件，normal/`-O`输出同一
  `reference_source_program_wire_golden_v1: ok 1 84 57 63`，无参数/unknown argv exit2。`--emit`只能原子重写上述
  两个固定package files，输出前完整自验；不得生成production source、cache或第二份ProgramV1 decoder。

  变更文件集精确为新增上述Lean suite/Python oracle/two-file golden package，只修改`Tests.lean`、`lakefile.lean`与
  `SourceWireAcceptance.lean`注册。无`ProofForgeV2/**`变更，故不得机械改变70-file production manifest。
  Lean suite≤700行、Python≤850行、manifest≤4000行且≤320KiB、raw binary≤64KiB、registrations additions≤5，
  总text additions≤5600。明确排除source parser/command/Loader/export v2、sourceUtf8声称、negative field-count
  mutation corpus、span/origin/SourceNodeInventory、production wire/hash/NodeId改写、legacy bridge/dual reader/
  second quoted decoder/fallback、Typed/Semantic/target。

  tests-only RED必须只因两个exact package files不存在而在direct Lean与Python self-check失败；提交前先用未提交
  `--emit` package证明suite compile/direct与Python self-check全绿，再删除package确认missing-package RED，package
  不得进入RED commit。GREEN只提交deterministic package files。最终运行focused suite与`SourceWireAcceptance`
  direct、Python normal/`-O`/invalid argv、PA121/122 oracles、aggregate/test binary、最终单次`just sbom`、docs/diff与
  main-agent self-review；不声称independent review，不运行完整`just ci`。只能记录development evidence，仍不关闭
  source-bound/negative/span residual、完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-126 在PA125 immutable full-tag base上建立closed field-count negative golden descriptor package；它只闭合
  `SPEC-SOURCE-WIRE-001`要求的每个positive-field-count constructor `n-1/n+1`及每个nullary constructor `0→1`，
  不扩大到unknown tag、scalar/truncation/trailing、source parser或span。base固定为
  `testdata/golden/source-program-v1/full-tag-v1/canonical.bin`，raw SHA-256必须exact为
  `5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce`；不得修改PA125 manifest/binary、
  encoder/decoder或production package manifest。

  独立Python model按PA125 logical fixture的wire encode source order记录每个tag的首个（最低）field-count byte offset。
  closed 84 tags中必须exact有28个count0与56个count>0；因此manifest必须exact包含140个mutation rows：count0仅`1`，
  count>0依次`n-1`与`n+1`。每row包含ASCII caseId、tag、`fieldCountOffset`、`expectedCount`、`mutatedCount`与
  `expectedError = "tag '<tag>' must declare <n> fields"`。offset指向base内u16le count首字节，必须unique于
  `(tag,mutatedCount)`、位于`[0,size-2]`且base两字节exact为expected；mutation只替换该u16le，不写出140个重复binary。
  rows按`(tag,mutatedCount)` ASCII/Numeric ascending，descriptor由base content ref与rows共同定义每个checked-in
  logical negative golden；只存最终error hash或运行时重新选择另一occurrence都不满足。

  checked-in descriptor固定为
  `testdata/golden/source-program-v1/field-count-v1/manifest.json`，schema固定
  `proof-forge.source-program-field-count-golden-prerequisite.v1`，scope固定
  `pa125-base-first-occurrence-exact-field-count`，并包含baseCaseId/baseCanonicalFile/baseCanonicalBytesSha256、
  `tagCount=84`、`nullaryTagCount=28`、`positiveFieldTagCount=56`、`mutationCount=140`与mutations。JSON沿用PA125
  UTF-8/LF/recursively sorted keys/two-space hierarchy/compact row/final newline，package目录只能含该manifest。

  新增`Tests.Language.SourceProgramWireFieldCountGoldenV1`读取PA125 raw base与descriptor，先验证metadata、84-tag
  exact coverage、28/56/140 partition、row order/uniqueness/offset/base count；随后逐row构造fresh ByteArray mutation并调用
  production `decodeCanonicalSourceAstBytesV1`，必须逐字得到expectedError。每次失败后base bytes保持不变，最终base仍须
  decode成功并re-encode逐byte相等。新增assert-free
  `scripts/reference_source_program_wire_field_count_golden_v1.py`可只import同目录PA125 independent oracle，不得import
  Lean/ProofForge；它独立记录offset并验证PA125 checked-in package。CLI只允许`--emit`/`--self-check`，self-check不写文件，
  normal/`-O`同为`reference_source_program_wire_field_count_golden_v1: ok 140 84 28 56`，invalid argv exit2；emit只可
  per-file atomically rewrite上述descriptor，输出前后完整自验。

  变更文件集精确为新增上述Lean suite/Python oracle/one-file descriptor，只修改`Tests.lean`、`lakefile.lean`与
  `SourceWireAcceptance.lean`注册。Lean≤320行、Python≤360行、manifest≤300行且≤128KiB、registrations additions≤5、
  总text additions≤1000。明确排除修改PA125 package、`ProofForgeV2/**`、production manifest、stored mutated binaries、
  其他negative families、sourceUtf8/command/Loader/export v2、span/origin/inventory、legacy bridge/dual reader/second
  quoted decoder/fallback、Typed/Semantic/target。

  tests-only RED必须只因descriptor manifest不存在而在direct Lean与Python self-check失败；提交前先用未提交`--emit`
  descriptor证明suite compile/direct与Python self-check全绿，再删除descriptor/empty dir确认missing-manifest RED；GREEN
  只提交deterministic descriptor。最终运行focused suite与`SourceWireAcceptance` direct、Python normal/`-O`/invalid
  argv、PA125/121/122 oracles、aggregate/test binary、最终单次`just sbom`、docs/diff与main-agent self-review；不声称
  independent review，不运行完整`just ci`。只能记录development evidence，仍不关闭source-bound/其他negative/span、
  完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-127 在PA125 immutable full-tag base上建立Bool/Option noncanonical marker negative golden descriptor；它只闭合
  primitive `decodeBool` 与四个ProgramV1 option-bearing field对marker `2`的exact fail-closed行为，不扩大到其他scalar、
  length/truncation/trailing、source parser或span。base固定为
  `testdata/golden/source-program-v1/full-tag-v1/canonical.bin`，raw SHA-256必须exact为
  `5d38eaca671e503ae50a517cc8ffaddba20b370d11da22f6bcdb807089aa64ce`；不得修改PA125/126 package、encoder/decoder或
  production package manifest。

  独立Python model必须按PA125 logical fixture的wire encode source order记录全部marker byte offset，并证明exact存在25个
  Bool与16个Option occurrences。Bool按base marker `0/1`各选择最低offset；Option按
  `Stmt.Let.typeAnn`、`Stmt.If.elseBlock`、`Stmt.Assert.error`、`Stmt.Return.value`四个exact owner/field及base marker
  `0/1`各选择最低offset。manifest必须exact包含10个mutation rows：2个Bool与8个Option，每个只把所选一字节从
  `0/1`改为`2`。每row包含ASCII caseId、`markerKind`、`ownerTag`、`fieldName`、`markerOffset`、`baseMarker`、
  `mutatedMarker=2`与exact `expectedError`；Bool error固定`invalid bool marker`，Option error固定
  `invalid option marker`。offset必须unique、位于`[0,size-1]`且base byte exact为baseMarker；rows按
  `(markerKind,ownerTag,fieldName,baseMarker)` ASCII/Numeric ascending。只存base content ref与rows，不写出10个重复binary。

  checked-in descriptor固定为
  `testdata/golden/source-program-v1/marker-v1/manifest.json`，schema固定
  `proof-forge.source-program-marker-golden-prerequisite.v1`，scope固定
  `pa125-base-lowest-bool-option-noncanonical-marker`，并包含baseCaseId/baseCanonicalFile/baseCanonicalBytesSha256、
  `boolOccurrenceCount=25`、`optionOccurrenceCount=16`、`optionFieldCount=4`、`boolMutationCount=2`、
  `optionMutationCount=8`、`mutationCount=10`与mutations。JSON沿用PA125 UTF-8/LF/recursively sorted keys/
  two-space hierarchy/compact row/final newline，package目录只能含该manifest。

  新增`Tests.Language.SourceProgramWireMarkerGoldenV1`读取PA125 raw base与descriptor，先验证metadata、closed 10-key
  matrix、row order/uniqueness/offset/base marker与exact error；随后逐row构造fresh ByteArray one-byte mutation并调用
  production `decodeCanonicalSourceAstBytesV1`，必须逐字得到expectedError。每次失败后base bytes保持不变，最终base仍须
  decode成功并re-encode逐byte相等。新增assert-free
  `scripts/reference_source_program_wire_marker_golden_v1.py`可只import同目录PA125 independent oracle，不得import
  Lean/ProofForge；它以offset-aware encoder验证PA125 checked-in package与25/16 occurrence matrix。CLI只允许
  `--emit`/`--self-check`，self-check不写文件，normal/`-O`同为
  `reference_source_program_wire_marker_golden_v1: ok 10 2 8 25 16`，invalid argv exit2；emit只可per-file atomically
  rewrite上述descriptor，输出前后完整自验。

  变更文件集精确为新增上述Lean suite/Python oracle/one-file descriptor，只修改`Tests.lean`、`lakefile.lean`与
  `SourceWireAcceptance.lean`注册。Lean≤260行、Python≤300行、manifest≤80行且≤32KiB、registrations additions≤5、
  总text additions≤700。明确排除修改PA125/126 package、`ProofForgeV2/**`、production manifest、stored mutated
  binaries、其他negative families、sourceUtf8/command/Loader/export v2、span/origin/inventory、legacy bridge/dual reader/
  second quoted decoder/fallback、Typed/Semantic/target。

  tests-only RED必须只因descriptor manifest不存在而在direct Lean与Python self-check失败；提交前先用未提交`--emit`
  descriptor证明suite compile/direct与Python self-check全绿，再删除descriptor/empty dir确认missing-manifest RED；GREEN
  只提交deterministic descriptor。最终运行deterministic double emit、focused suite与`SourceWireAcceptance` direct、
  Python normal/`-O`/invalid argv、PA126/125/121/122 regressions、aggregate/test binary连续两次、最终单次`just sbom`、
  docs/diff与main-agent self-review；不声称independent review，不运行完整`just ci`。只能记录development evidence，仍不
  关闭source-bound/其他negative/span、完整TST-SRC-001、pending TASK-D1-01或下游task。
- D1-PA-20 的 alpha `let` tests 只接受 initializer/callable body 内同一行 `let name := Expr` 与
  `let name : Type := Expr`。positive 覆盖 initializer、entry、view、fn 的 annotated/omitted type
  statement，并固定 Lean command/ParserSession 的 Source AST/sourceHash parity。Source canonical
  mutation 必须同时绑定 append-only statement tag `3`、name、`typeAnn` 的 `0/1` marker/type payload
  与 value；既有 statement tags `0..2` 和 goldens 不变。unknown annotated type 与 reserved binder
  必须在 decoder exact fail closed；escaped/qualified introducer、缺失 name/type/value/`:=`、额外或
  跨行 payload 必须停在 parser boundary。`«let» := 1` 继续作为 escaped-identifier assignment
  positive control，bare `let := 1` 继续被 parser 拒绝；不得新增宿主 Lean keyword或 generic
  fallback parser。`Typed.check` 必须返回 exact
  `let statements are not yet supported by typed checking` 且不产生 Semantic/target output；local
  binding、shadowing、resolution、type/effect rules、SemanticIR lowering 与 runtime semantics 属于后续
  D2/statement slices，不在本测试完成面。
- D1-PA-21 的 alpha Bool literal tests 只把 exact bare `true`/`false` 解码为
  `Source.Expr.boolLiteral(Bool)`，并覆盖 initializer、entry、view、fn 的 return/let value 可达位置以及
  Lean command/ParserSession Source AST/sourceHash parity。canonical goldens 必须固定 append-only Expr
  tag `4` 后单字节 `0/1` marker，并证明 integer literal `0/1`、`false`、`true` 彼此不 alias；既有
  Expr tags `0..3` 与 goldens 不变。bare literals 必须优先于 generic identifier，`trueValue`/
  `falseValue`、大小写不同 identifier、escaped `«true»`/`«false»` 与 qualified `Std.true`/`Std.false`
  必须保持 variable control 而不得误分类，且本切片不得改变 identifier policy；literal 后的额外独立
  token 形态必须停在 parser boundary。
  `Typed.check` 必须返回 exact
  `boolean literals are not yet supported by typed checking` 且不产生 Semantic/target output；不得以
  UInt64 `0/1` 代替 Bool，不得加入 Typed/Semantic Bool expression、requirement、target ABI 或 runtime
  semantics。
- D1-PA-22 的 alpha checked subtraction tests 只新增 binary `Source.Expr.checkedSub(lhs, rhs)`；positive
  覆盖 initializer、entry、view、fn 的 return/let value 可达位置、variable operands 与 Lean command/
  ParserSession AST/sourceHash parity。parser 必须使用与 `+` 相同的 precedence `65` 和 `lhs:65`/
  `rhs:66` 约束；测试必须精确固定 `9 - 4 - 1 = (9 - 4) - 1`、
  `1 + 2 - 3 = (1 + 2) - 3`、`1 - 2 + 3 = (1 - 2) + 3` 的左结合 AST，且不得借助尚未实现的
  parentheses。canonical goldens 必须固定 append-only Expr tag `5` 后递归 lhs/rhs，证明 `7 - 3`
  与 `7 + 3` operator tag 不 alias、`7 - 3` 与 `3 - 7` operand order 不 alias、left/right nested direct
  Source twins 不 alias；既有 Expr tags `0..4` 与 goldens 不变。缺失 lhs/rhs、bare unary minus 与
  binary 后 unary-minus operand 必须停在 parser boundary。`Typed.check` 必须返回 exact
  `checked subtraction is not yet supported by typed checking` 且不产生 Semantic/target output；不得加入
  Typed/Semantic subtraction、underflow semantics、Int/signed literal、unary、parentheses、其他 arithmetic
  operator、requirement、target ABI 或 runtime semantics；既有 checked-add positive 必须继续通过。
- D1-PA-23 的 alpha checked multiplication tests 只新增 binary `Source.Expr.checkedMul(lhs, rhs)`；positive
  覆盖 initializer、entry、view、fn 的 return/let value 可达位置、variable operands 与 Lean command/
  ParserSession AST/sourceHash parity。parser 必须固定 precedence `70` 与 `lhs:70`/`rhs:71`，高于既有
  `+`/`-` 的 `65`；测试必须精确固定 `2 * 3 * 4 = (2 * 3) * 4`、
  `2 + 3 * 4 = 2 + (3 * 4)`、`2 * 3 + 4 = (2 * 3) + 4`、
  `2 - 3 * 4 = 2 - (3 * 4)` 与 `2 * 3 - 4 = (2 * 3) - 4` 的 AST，且不得借助尚未实现的
  parentheses。canonical goldens 必须固定 append-only Expr tag `6` 后递归 lhs/rhs，证明 `2 * 3`
  与 `2 + 3`/`2 - 3` operator tag 不 alias、`2 * 3` 与 `3 * 2` operand order 不 alias、left/right
  nested direct Source twins 不 alias；既有 Expr tags `0..5` 与 goldens 不变，prospective hashes 必须在
  GREEN 前按真实 CheckedMulTwin identity 重新绑定。缺失 lhs/rhs、bare/repeated `*`、额外 token、
  `/` 与 `%` spellings 必须停在 parser boundary。`Typed.check` 必须返回 exact
  `checked multiplication is not yet supported by typed checking` 且不产生 Semantic/target output；不得加入
  Typed/Semantic multiplication、overflow semantics、Int/signed literal、unary、parentheses、division、
  modulo、requirement、target ABI 或 runtime semantics；既有 checked-add positive 与 checked-sub exact
  fail-closed control 必须继续通过。
- D1-PA-24 的 alpha parenthesized grouping tests 只接受 `(` `pfExpr` `)`，production rule 必须固定为
  `syntax:max "(" pfExpr:0 ")" : pfExpr`，以 high-precedence outer primary 包裹 min-precedence `0` 的
  完整 inner expression；decoder 递归返回内部 Source expression。positive 覆盖
  initializer、entry、view、fn 的 return/let value 可达位置、literal/variable/Bool/binary operands 与
  Lean command/ParserSession AST/sourceHash parity；`(42)`/`42`、`((x))`/`x`、`((2 + 3))`/`2 + 3`
  必须产生相同 AST、canonical bytes 与 sourceHash，且所有既有 Expr tags `0..6`/goldens 不变。
  grouping override 必须精确固定 `(2 + 3) * 4`、`7 - (3 - 1)`、`2 * (3 * 4)` 与
  `2 * (3 + 4)` 的 AST；其中 `(2 + 3) * 4` 必须证明 inner `pfExpr:0` 没有错误排除低 precedence
  addition；两个 right-nested 项在对应 CheckedSubTwin/CheckedMulTwin identity 下必须与 direct
  right-nested Source twin 的 238-byte
  canonical/hash `7e6a2c24a6cad28e5984f2279dce0df9fdd863c6ea1062334cb32b69027e7e3a`、
  `f4b9a861619b742361e41f69342f07dc9c338daa9b9a520073b8aa2fa990c13c` 相同，并继续与各自 left-nested
  twin 不 alias；`2 * (3 + 4)` 的真实 identity golden 必须在 GREEN 前重新绑定。empty/whitespace-only
  group、缺失 open/close、tuple/comma、group 内或 group 后额外 payload、nested unmatched、call-like
  `f(1)` 与 type-position `(UInt64)` 必须停在 parser boundary；不得接受 unit、tuple、call、constructor、
  unary 或新增 expression。
  本切片不得新增 Source ctor/tag/field、quote arm、Typed/Semantic rule、requirement、target ABI/runtime；
  grouped checkedAdd positive 以及 grouped Bool/checkedSub/checkedMul 的既有 exact Typed controls 必须保持。
- D1-PA-25 的 alpha unary checked-negation tests 固定 production rule
  `syntax:75 "-" pfExpr:75 : pfExpr` 与 `Source.Expr.checkedNeg(operand)`。positive 必须覆盖 initializer、
  entry、view、fn 的 return/let value 可达位置以及 Lean command/ParserSession parity，并精确固定
  `-2`、`- 2`、`-x`、`-2 * 3`、`-(2 + 3)`、`1 - -2`、`1 + -2`、`1 * -2`、`- - 2`
  和 grouped `(-3)` 的 AST；nested unary 必须保留两个 node，不能 constant-fold 或改写成 signed literal。
  Source canonical encoder 必须使用 append-only Expr tag `7` 后接 operand；既有 tags `0..6`/goldens
  不变。CheckedNegTwin identity 下 literal `2`、variable `x`、precedence/grouping/binary-operand/nested
  cases 的真实 canonical bytes/hash 必须在 GREEN 前绑定，并包含与 literal `2`、negative literal `3`
  及错误 grouping tree 的 non-alias controls。
  同一个 RED changeset 必须从 `CheckedSub` negative matrix 迁移 `- 3`、`-3`、`7 - - 3`、
  `1 + - 2`，并从 `Grouping` negative matrix 迁移 `(- 3)`；新 CheckedNeg suite 必须重新固定这些
  positive，不能保留互相矛盾的旧 parser pin。bare `-`、`-()`、`-*2`、`-+2`、`-2 3`、
  `1 - -` 与缺失 operand/payload 必须拒绝。无空格 `--` 按 Lean line-comment boundary 处理：不得把
  `--2` 写成 nested-negation positive；`1--2` 必须作为只产生 literal `1` 的 comment control，
  subtraction-of-negative 使用 `1 - -2`。
  `Typed.check` 必须逐字拒绝 `checked negation is not yet supported by typed checking` 且不产生
  Semantic/target output；不得加入 `!`/`~`、signed literal、folding、Typed/Semantic negation、
  requirement、overflow、target ABI 或 runtime semantics，既有 checked-add/sub/mul exact controls
  必须保持。
- D1-PA-26 的 alpha assert-statement tests 只接受 bare `assert Expr`，production rule 固定为
  `syntax "assert " pfExpr : pfStmt`，Source carrier 固定为 `Statement.assertStmt(condition)`，Statement
  canonical encoder 使用 append-only tag `4` 后递归编码 condition；既有 tags `0..3` 与全部 goldens
  不变。positive 必须覆盖 initializer、entry、view、fn body，literal/variable/Bool/binary/grouped condition，
  以及 Lean command/ParserSession AST/sourceHash parity。相同 AssertTwin identity 下 `assert true` 与
  `assert (true)` 必须产生相同 Source.Program/canonical bytes/sourceHash；assert-vs-return 相同 condition
  必须 canonical size 相同但 hash 不同，true-vs-false condition 也不得 alias，真实 tag-4 golden 在
  GREEN 前绑定。
  keyword controls 必须固定 bare `assert := 1` parser reject、escaped `«assert» := 1` 仍产生
  `.assign "assert" (.literal 1)`、`assertValue := 1` 不被前缀误收。bare `assert`、extra payload、
  `assert true else Failure`、missing condition 与 block-like 形态必须停在 parser boundary；optional
  `else Ident` 明确 deferred，不得作为 declared-error support。`Typed.checkStatement` 必须在 condition
  checking 前逐字拒绝 `assert statements are not yet supported by typed checking`；`assert true` 必须得到
  assert diagnostic 而不是 Bool-expression diagnostic，既有 assignment/return/call/let controls 保持。
  本切片不得新增 Typed Statement、Bool type checking、assertion failure/revert、SemanticIR、requirement、
  effect、target ABI 或 runtime semantics。
- D1-PA-27 的 alpha unary bitwise-not tests 固定 production rule
  `syntax:75 "~" pfExpr:75 : pfExpr` 与 `Source.Expr.bitwiseNot(operand)`。positive 必须覆盖 initializer、
  entry、view、fn 的 return/let value 可达位置以及 Lean command/ParserSession parity，并精确固定
  `~2`、`~x`、`~2 * 3`、`~(2 + 3)`、`1 - ~2`、`1 * ~2`、`~ ~ 2`、`(~2)`、
  `- ~ 2` 与 `~ - 2` 的 AST；nested/mixed unary 必须保留 node 数量与顺序。Source canonical encoder
  使用 append-only Expr tag `8` 后接 operand；既有 tags `0..7`/goldens 不变。BitwiseNotTwin identity
  下 literal、variable、precedence/grouping/nested/mixed cases 的真实 bytes/hash 在 GREEN 前绑定，并以
  literal `2`、checked-negation、operand mutation、wrong tree 与 mixed-unary reverse-order 作为 non-alias。
  bare `~`、`~()`、`~*2`、`~+2`、`~2 3`、`1 - ~` 与缺失 operand/payload 必须停在 parser
  boundary。`Typed.check` 必须逐字拒绝 `bitwise not is not yet supported by typed checking` 且不产生
  Semantic/target output；既有 checkedAdd positive 与 Bool/sub/mul/neg exact fail-closed controls 保持。
  本切片不得修改既有 tests 作为迁移，不得加入 logical `!`、shift/binary bitwise、folding、
  Typed/Semantic bitwise、requirement、target ABI 或 runtime semantics。
- D1-PA-28 的 alpha unary logical-not tests 固定 production rule
  `syntax:75 "!" pfExpr:75 : pfExpr` 与 `Source.Expr.logicalNot(operand)`。positive 必须覆盖 initializer、
  entry、view、fn 的 return/let value 可达位置以及 Lean command/ParserSession parity，并精确固定
  `!2`、`!true`、`!false`、`!x`、`!2 * 3`、`!(2 + 3)`、`1 - !2`、`1 * !2`、
  `! ! 2`、`(!2)`、`- ! 2`/`! - 2` 与 `~ ! 2`/`! ~ 2` 的 AST；nested/mixed unary
  必须保留 node 数量与次序。Source 阶段不得强制 Bool operand；该 legality 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `9` 后接 operand；既有 tags `0..8`/goldens 不变。
  LogicalNotTwin identity 下 literal/Bool/variable/precedence/grouping/nested/mixed cases 的真实 bytes/hash
  在 GREEN 前绑定，并以 literal `2`、checked-negation、bitwise-not、operand mutation、wrong tree 与
  mixed-unary reverse-order 作为 non-alias。
  bare `!`、`!()`、`!*2`、`!+2`、`!2 3`、`1 - !`、`1 != 2`、`! = 2` 与缺失 operand/payload
  必须停在 parser boundary。`Typed.check` 必须在 operand checking 前逐字拒绝
  `logical not is not yet supported by typed checking`，不产生 Semantic/target output；既有 checkedAdd
  positive 与 Bool/sub/mul/neg/bitwiseNot exact fail-closed controls 保持。本切片不得修改既有 tests 作为
  迁移，不得加入 comparison、`&&`/`||`、Bool typing、folding、requirement、target ABI/runtime semantics。
- D1-PA-29 的 alpha binary checked-division tests 固定 production rule
  `syntax:70 pfExpr:70 " / " pfExpr:71 : pfExpr` 与 `Source.Expr.checkedDiv(lhs, rhs)`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 可达位置以及 Lean command/ParserSession parity，并精确固定
  `6 / 3`、`3 / 6`、`a / b`、`1 + 6 / 3`、`6 / 3 + 1`、`6 / 3 / 2`、
  `6 / (3 / 2)`、`2 * 6 / 3`、`2 * (6 / 3)`、`8 / 4 * 2` 与 `(1 + 2) / 3` 的 AST；
  还必须固定 `8 / 4 - 2`、`-8 / 4`、`8 / -4` 与 `8 / 0`；same-precedence chains 必须左结合，
  grouped operand 必须保留，literal-zero denominator 必须被 Source 接受而不提前执行除零 legality。
  Source canonical encoder 使用 append-only Expr tag `10` 后依次编码 lhs/rhs；既有 tags `0..9`/goldens
  不变。CheckedDivTwin identity 下 literal/precedence/grouping/nested cases 的真实 bytes/hash 必须在 GREEN
  前绑定，并以 checked-multiplication、checked-subtraction、operand order/mutation、wrong tree 与 left/right
  nesting 作为 non-alias。相同 identity 下 `(6 / 3)` 与 `6 / 3` 必须产生相同 Source.Program/canonical
  bytes/sourceHash。
  missing lhs/rhs、bare/repeated `/`、`2 // 3`、mixed invalid operator、extra payload 与 `%` 必须停在
  parser boundary。
  `Typed.check` 必须在 operand checking 前逐字拒绝
  `checked division is not yet supported by typed checking`，不产生 Semantic/target output；既有 checkedAdd
  positive 与 Bool/sub/mul/neg/bitwiseNot/logicalNot exact fail-closed controls 保持。本切片的 tests-only RED
  必须且只能迁移 `CheckedMul` 的 `2 / 3` 与 `Grouping` 的 `(2 / 3)` 两条既有 slash negative，percent
  negatives 保持；不得加入 modulo、zero/signed/rounding semantics、folding、requirement、target
  ABI/runtime semantics。production 必须限于 Source/Syntax/Typed 的 3 文件/11 行 exact seam，不得修改
  Typed Expr、SemanticIR/Semantics、requirements、targets、preflight 或 generic negative table。
- D1-PA-30 的 alpha binary checked-modulo tests 固定 production rule
  `syntax:70 pfExpr:70 " % " pfExpr:71 : pfExpr` 与 `Source.Expr.checkedMod(lhs, rhs)`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及 Lean command/ParserSession parity，并精确固定
  `7 % 3`、`3 % 7`、`a % b`、`1 + 7 % 3`、`7 % 3 + 1`、`7 % 3 - 1`、
  `7 % 3 % 2`、`7 % (3 % 2)`、`2 * 7 % 3`、`2 * (7 % 3)`、`7 % 3 * 2`、
  `8 / 4 % 2`、`8 % 4 / 2`、`(1 + 2) % 3`、`-8 % 3`、`8 % -3` 与 `8 % 0` 的 AST；
  same-precedence chains 必须跨 `*`/`/`/`%` 左结合，grouped operand 保留，zero denominator 在 Source 接受。
  Source canonical encoder 使用 append-only Expr tag `11` 后依次编码 lhs/rhs；既有 tags `0..10`/goldens
  不变。CheckedModTwin identity 下 literal/precedence/grouping/nested/unary/zero cases 的真实 bytes/hash
  必须在 GREEN 前绑定，并以 checked-multiplication、checked-division、checked-subtraction、operand
  order/zero、wrong tree 与 left/right nesting 作为 non-alias。相同 identity 下 `(7 % 3)` 与 `7 % 3`
  必须产生相同 Source.Program/canonical bytes/sourceHash。
  missing lhs/rhs、bare/repeated `%`、`2 %% 3`、mixed invalid operator 与 extra payload 必须停在 parser
  boundary。`Typed.check` 必须在 operand checking 前逐字拒绝
  `checked modulo is not yet supported by typed checking`；既有 checkedAdd positive 与 Bool/sub/mul/div/neg/
  bitwiseNot/logicalNot exact controls 保持。tests-only RED 必须且只能迁移 3 个 suite 中 4 条 percent
  negative：`CheckedMul` 1、`Grouping` 1、`CheckedDiv` 2；不得漏项或迁移其他 negative。
  不得加入 modulo-by-zero、Int/signed/rounding/sign、folding、Typed/Semantic modulo、requirement、target
  ABI/runtime semantics。production 必须限于 Source/Syntax/Typed 3 文件/11 行，不得修改 Typed Expr、
  SemanticIR/Semantics、requirements、targets、preflight 或 generic negative table。
- D1-PA-31 的 alpha shift-left tests 固定 production rule
  `syntax:60 pfExpr:60 " << " pfExpr:61 : pfExpr` 与 `Source.Expr.shiftLeft(lhs, rhs)`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及 Lean command/ParserSession parity，并精确固定
  `1 << 2`、`2 << 1`、`a << b`、`1 + 2 << 3`、`1 << 2 + 3`、`8 << 2 * 3`、
  `8 * 2 << 3`、`1 << 2 << 3`、`1 << (2 << 3)`、`(1 + 2) << 3`、`-1 << 2`、
  `1 << -2`、`0 << 1`、`1 << 0` 与 `1 << 64` 的 AST。shift 必须低于 AddExpr/MulExpr、左结合，
  grouping/unary 保留；zero/over-width count 必须在 Source 接受。
  Source canonical encoder 使用 append-only Expr tag `12` 后依次编码 lhs/rhs；既有 tags `0..11`/goldens
  不变。ShiftLeftTwin identity 下 order/precedence/grouping/nested/unary/count cases 的真实 bytes/hash 必须
  在 GREEN 前绑定，并以 checked-add、operand order/count、wrong precedence tree 与 left/right nesting
  作为 non-alias。相同 identity 下 `(1 << 2)` 与 `1 << 2` 必须产生相同 Program/bytes/hash。
  bare/missing/repeated `<<`、`1 < < 2`、`1 <<< 2`、extra payload 与 deferred `1 >> 2` 必须停在
  parser boundary。`Typed.check` 必须在 operand checking 前逐字拒绝
  `shift left is not yet supported by typed checking`；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwiseNot/logicalNot exact controls 保持。本切片不得迁移任何既有 test，不得加入 `>>`、signed/
  arithmetic shift、rotate、width/overflow、folding、Typed/Semantic shift、requirement、target ABI/runtime。
  production 必须限于 Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-32 的 alpha shift-right tests 固定 production rule
  `syntax:60 pfExpr:60 " >> " pfExpr:61 : pfExpr` 与 `Source.Expr.shiftRight(lhs, rhs)`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及 Lean command/ParserSession parity，并精确固定
  `1 >> 2`、`2 >> 1`、`a >> b`、`1 + 2 >> 3`、`1 >> 2 + 3`、`8 >> 2 * 3`、
  `8 * 2 >> 3`、`1 >> 2 >> 3`、`1 >> (2 >> 3)`、`(1 + 2) >> 3`、`-1 >> 2`、
  `1 >> -2`、`0 >> 1`、`1 >> 0`、`1 >> 64`、`1 << 2 >> 3` 与 `1 >> 2 << 3` 的 AST；
  shift operators 必须同层跨 operator 左结合、低于 additive/multiplicative，grouping/unary 保留，
  zero/over-width count 在 Source 接受。
  Source canonical encoder 使用 append-only Expr tag `13` 后依次编码 lhs/rhs；既有 tags `0..12`/goldens
  不变。ShiftRightTwin identity 下 order/precedence/cross-shift/grouping/nested/unary/count cases 的真实
  bytes/hash 必须在 GREEN 前绑定，并以 shift-left、checked-add、operand order/count、wrong precedence
  tree、left/right nesting 与 reversed cross-shift shape 作为 non-alias。相同 identity 下 `(1 >> 2)` 与
  `1 >> 2` 必须产生相同 Program/bytes/hash。
  bare/missing/repeated `>>`、`1 > > 2`、`1 >>> 2` 与 extra payload 必须停在 parser boundary。
  `Typed.check` 必须在 operand checking 前逐字拒绝
  `shift right is not yet supported by typed checking`；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwiseNot/logicalNot/shiftLeft exact controls 保持。tests-only RED 必须且只能迁移 `ShiftLeft.lean` 的
  deferred `1 >> 2` 一条 negative。不得加入 arithmetic-vs-logical/signed shift-right、rotate、width/
  overflow、folding、Typed/Semantic shift、requirement、target ABI/runtime；production 必须限于
  Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-33 的 alpha equality tests 固定 production rule
  `syntax:50 pfExpr:51 " == " pfExpr:51 : pfExpr` 与 `Source.Expr.equal(lhs, rhs)`。两个 operand slot
  都必须严格高于 operator precedence，使 CompareExpr 的 optional comparison 保持 non-associative；
  `1 == 2 == 3` 必须停在 parser boundary，禁止退化为左结合或右结合。positive 必须覆盖 initializer、
  entry、view、fn 的 return/let value 及 Lean command/ParserSession parity，并精确固定 `1 == 2`、
  `2 == 1`、`a == b`、`true == false`、`false == true`、`0 == 0`、`1 + 2 == 3`、
  `1 == 2 + 3`、`1 * 2 == 3`、`1 == 2 * 3`、`1 << 2 == 3`、`1 == 2 << 3`、
  `1 >> 2 == 3`、`1 == 2 >> 3`、`(1 + 2) == 3`、`-1 == 2`、`1 == -2` 与
  `!true == false` 的 AST。equality 必须低于 Shift/Add/Mul/Unary；integer/Bool operand legality 和
  Bool result typing 留给 D2，不得在 Source 提前判断。
  Source canonical encoder 使用 append-only Expr tag `14` 后依次编码 lhs/rhs；既有 tags `0..13`/goldens
  不变。EqualTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实 bytes/hash
  必须在 GREEN 前绑定，并以 checked-add、shift-left、shift-right、operand order、wrong precedence tree
  与 Bool order 作为 non-alias。相同 identity 下 `(1 == 2)` 与 `1 == 2` 必须产生相同
  Source.Program/canonical bytes/sourceHash。
  bare/missing operand、single `=`、`1 = = 2`、`1 === 2`、`1 == 2 == 3`、extra payload 以及仍未实现的
  `<`/`<=`/`>`/`>=` 必须停在 parser boundary；`LogicalNot.lean` 既有 `1 != 2` retention negative 保持不动。
  `Typed.check` 必须在 operand checking 前逐字拒绝
  `equality is not yet supported by typed checking`，使 `true == false` 不泄漏 Bool operand diagnostic；
  既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/bitwiseNot/logicalNot/shiftLeft/shiftRight exact controls
  保持。本切片不得迁移任何既有 test，不得加入 `!=`、ordering、bitwise/logical binary operators、
  Bool legality、folding、Typed/Semantic comparison、requirement 或 target ABI/runtime；production 必须限于
  Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-34 的 alpha not-equal tests 固定 production rule
  `syntax:50 pfExpr:51 " != " pfExpr:51 : pfExpr` 与 `Source.Expr.notEqual(lhs, rhs)`。它必须与 `==`
  共用 Compare precedence `50`，两个 operand slot 都严格高于 operator precedence；`1 != 2 != 3`、
  `1 == 2 != 3` 与 `1 != 2 == 3` 都必须停在 parser boundary，禁止同类或 mixed comparison chain
  退化为任一结合方向。positive 必须覆盖 initializer、entry、view、fn 的 return/let value 及 Lean
  command/ParserSession parity，并精确固定 `1 != 2`、`2 != 1`、`a != b`、`true != false`、
  `false != true`、`0 != 0`、add/mul/shift 双向 precedence、grouping、`-1 != 2`、`1 != -2`、
  `!true != false` 与 `1 != !false` 的 AST。integer/Bool operand legality 和 Bool result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `15` 后依次编码 lhs/rhs；既有 tags `0..14`/goldens
  不变。NotEqualTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实 bytes/hash
  必须在 GREEN 前绑定，并以 `equal`、checked-add、shift-left、shift-right、operand order、wrong precedence
  tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 != 2)` 与 `1 != 2` 必须产生相同
  Source.Program/canonical bytes/sourceHash。
  bare/missing operand、`1 ! = 2`、`1 !== 2`、`1 ! == 2`、same/mixed chained comparison 与 extra payload
  必须停在 parser boundary；`LogicalNot.lean` 的 `! = 2` spaced token-integrity negative 和 `Equal.lean`
  的 `<`/`<=`/`>`/`>=` ordering negatives 必须保持。`Typed.check` 必须在 operand checking 前逐字拒绝
  `not-equal comparison is not yet supported by typed checking`，使 `true != false` 不泄漏 Bool operand
  diagnostic；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/bitwiseNot/logicalNot/shiftLeft/shiftRight/
  equal exact controls 保持。tests-only RED 必须且只能迁移 `LogicalNot.lean` 的 deferred `1 != 2` 一条
  negative，不得迁移 spaced `! = 2` 或 ordering siblings。不得加入 ordering、bitwise/logical binary
  operators、Bool legality、folding、Typed/Semantic comparison、requirement 或 target ABI/runtime；production
  必须限于 Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-35 的 alpha less-than tests 固定 production rule
  `syntax:50 pfExpr:51 " < " pfExpr:51 : pfExpr` 与 `Source.Expr.lessThan(lhs, rhs)`。它必须与
  `==`/`!=` 共用 Compare precedence `50`，两个 operand slot 都严格高于 operator precedence；
  `1 < 2 < 3`、`1 == 2 < 3`、`1 < 2 != 3`、`1 != 2 < 3` 与 `1 < 2 == 3` 都必须停在 parser
  boundary，禁止 same/mixed comparison chain 退化为任一结合方向。positive 必须覆盖 initializer、
  entry、view、fn 的 return/let value 及 Lean command/ParserSession parity，并精确固定 `1 < 2`、
  `2 < 1`、`a < b`、`0 < 0`、`true < false`、add/mul/shift 双向 precedence、grouping 与 unary 的 AST；
  特别是 `1 << 2 < 3` 必须为 `(1 << 2) < 3`，`1 < 2 << 3` 必须为 `1 < (2 << 3)`。
  integer/Bool operand legality 和 Bool result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `16` 后依次编码 lhs/rhs；既有 tags `0..15`/goldens
  不变。LessThanTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实 bytes/hash
  必须在 GREEN 前绑定，并以 `equal`、`notEqual`、checked-add、shift-left、operand order、wrong precedence
  tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 < 2)` 与 `1 < 2` 必须产生相同
  Source.Program/canonical bytes/sourceHash。
  bare/missing operand、same/mixed chained comparison 与 extra payload 必须停在 parser boundary；
  `1 << 2` 必须继续解码为 shift-left，`ShiftLeft.lean` 的 `1 < < 2` 与 `1 <<< 2` 必须继续拒绝，
  `Equal.lean` 的 `<=`/`>`/`>=` ordering siblings 必须保持。`Typed.check` 必须在 operand checking 前逐字
  拒绝 `less-than comparison is not yet supported by typed checking`，使 `true < false` 不泄漏 Bool operand
  diagnostic；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/bitwiseNot/logicalNot/shiftLeft/shiftRight/
  equal/notEqual exact controls 保持。tests-only RED 必须且只能迁移 `Equal.lean` 的 deferred `1 < 2` 一条
  negative，不得迁移 ordering siblings 或 shift token-integrity negatives。不得加入 `<=`、`>`、`>=`、
  bitwise/logical binary operators、Bool legality、folding、Typed/Semantic comparison、requirement 或 target
  ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-36 的 alpha less-or-equal tests 固定 production rule
  `syntax:50 pfExpr:51 " <= " pfExpr:51 : pfExpr` 与 `Source.Expr.lessEqual(lhs, rhs)`。它必须与
  `==`/`!=`/`<` 共用 Compare precedence `50`，两个 operand slot 都严格高于 operator precedence；
  `1 <= 2 <= 3` 以及 `<=` 与 `<`/`==`/`!=` 组成的双向 mixed comparison chains 都必须停在 parser
  boundary，禁止退化为任一结合方向。positive 必须覆盖 initializer、entry、view、fn 的 return/let
  value 及 Lean command/ParserSession parity，并精确固定 `1 <= 2`、`2 <= 1`、`a <= b`、`0 <= 0`、
  `true <= false`、add/mul/shift 双向 precedence、grouping 与 unary 的 AST；`1 < 2` 必须继续形成
  lessThan，`1 << 2 <= 3` 必须为 `(1 << 2) <= 3`，`1 <= 2 << 3` 必须为 `1 <= (2 << 3)`。
  integer/Bool operand legality 和 Bool result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `17` 后依次编码 lhs/rhs；既有 tags `0..16`/goldens
  不变。LessEqualTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实 bytes/hash
  必须在 GREEN 前绑定，并以 `lessThan`、`equal`、`notEqual`、checked-add、shift-left、operand order、
  wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 <= 2)` 与 `1 <= 2` 必须
  产生相同 Source.Program/canonical bytes/sourceHash。
  bare/missing operand、same/mixed chained comparison 与 extra payload 必须停在 parser boundary；
  `1 < = 2`、`1 <<= 2` 与 `1 <= = 2` 必须拒绝，`1 < 2`/`1 << 2` 必须继续分别解码为 lessThan/
  shiftLeft，`ShiftLeft.lean` 的 `1 < < 2`/`1 <<< 2` 必须保持，`Equal.lean` 的 `>`/`>=` ordering
  siblings 必须保持。`Typed.check` 必须在 operand checking 前逐字拒绝
  `less-equal comparison is not yet supported by typed checking`，使 `true <= false` 不泄漏 Bool operand
  diagnostic；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/bitwiseNot/logicalNot/shiftLeft/shiftRight/
  equal/notEqual/lessThan exact controls 保持。tests-only RED 必须且只能迁移 `Equal.lean` 的 deferred
  `1 <= 2` 一条 negative，不得迁移 `>`/`>=` 或 shift token-integrity negatives。不得加入 `>`、`>=`、
  bitwise/logical binary operators、Bool legality、folding、Typed/Semantic comparison、requirement 或 target
  ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-37 的 alpha greater-than tests 固定 production rule
  `syntax:50 pfExpr:51 " > " pfExpr:51 : pfExpr` 与 `Source.Expr.greaterThan(lhs, rhs)`。它必须与
  `==`/`!=`/`<`/`<=` 共用 Compare precedence `50`，两个 operand slot 都严格高于 operator
  precedence；`1 > 2 > 3` 以及 `>` 与四个既有 comparisons 组成的双向 mixed chains 都必须停在
  parser boundary。positive 必须覆盖 initializer、entry、view、fn 的 return/let value 及 Lean
  command/ParserSession parity，并精确固定 `1 > 2`、`2 > 1`、`a > b`、`0 > 0`、`true > false`、
  add/mul/shift 双向 precedence、grouping 与 unary 的 AST；`1 >> 2` 必须继续形成 shiftRight，
  `1 >> 2 > 3` 必须为 `(1 >> 2) > 3`，`1 > 2 >> 3` 必须为 `1 > (2 >> 3)`。
  integer/Bool operand legality 和 Bool result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `18` 后依次编码 lhs/rhs；既有 tags `0..17`/goldens
  不变。GreaterThanTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实
  bytes/hash 必须在 GREEN 前绑定，并以 `lessThan`、`lessEqual`、`equal`、`notEqual`、checked-add、
  shift-right、operand order、wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下
  `(1 > 2)` 与 `1 > 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  bare/missing operand、same/mixed chained comparison 与 extra payload 必须停在 parser boundary；
  `1 > > 2`、`1 >>> 2`、`1 >>= 2` 与 `1 > = 2` 必须拒绝，`1 >> 2` 必须继续解码为 shiftRight，
  `ShiftRight.lean` 的既有 spaced/triple negatives 必须保持，`Equal.lean` 的 `>=` sibling 必须保持。
  `Typed.check` 必须在 operand checking 前逐字拒绝
  `greater-than comparison is not yet supported by typed checking`，使 `true > false` 不泄漏 Bool operand
  diagnostic；既有 checkedAdd positive 与 Bool/sub/mul/div/mod/neg/bitwiseNot/logicalNot/shiftLeft/shiftRight/
  equal/notEqual/lessThan/lessEqual exact controls 保持。tests-only RED 必须且只能迁移 `Equal.lean` 的
  deferred `1 > 2` 一条 negative，不得迁移 `>=` 或 shift token-integrity negatives。不得加入 `>=`、
  bitwise/logical binary operators、Bool legality、folding、Typed/Semantic comparison、requirement 或 target
  ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行，其他层不得修改。
- D1-PA-38 的 alpha greater-or-equal tests 固定 production rule
  `syntax:50 pfExpr:51 " >= " pfExpr:51 : pfExpr` 与 `Source.Expr.greaterEqual(lhs, rhs)`。它必须与
  五个既有 comparisons 共用 precedence `50`，两个 operand slot 都严格高于 operator precedence；
  `1 >= 2 >= 3` 以及 `>=` 与 `==`/`!=`/`<`/`<=`/`>` 组成的十种双向 mixed chains 都必须停在
  parser boundary。positive 必须覆盖 initializer、entry、view、fn 的 return/let value 及双入口 parity，
  并精确固定 `1 >= 2`、`2 >= 1`、`a >= b`、`0 >= 0`、`true >= false`、add/mul/shift 双向
  precedence、grouping 与 unary 的 AST；`1 > 2`/`1 >> 2` 必须继续分别形成 greaterThan/shiftRight，
  `1 >> 2 >= 3` 必须为 `(1 >> 2) >= 3`，`1 >= 2 >> 3` 必须为 `1 >= (2 >> 3)`。
  integer/Bool operand legality 和 Bool result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `19` 后依次编码 lhs/rhs；既有 tags `0..18`/goldens
  不变。GreaterEqualTwin identity 下 operand order/type、precedence/grouping/unary/shift cases 的真实
  bytes/hash 必须在 GREEN 前绑定，并以五个 comparison siblings、checked-add、shift-right、operand
  order、wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 >= 2)` 与
  `1 >= 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  bare/missing operand、same/mixed chains 与 extra payload 必须停在 parser boundary；`1 > = 2`、
  `1 >>= 2` 与 `1 >= = 2` 必须拒绝，既有 `>`/`>>` 与 ShiftRight token-integrity pins 不得改变。
  `Typed.check` 必须在 operand checking 前逐字拒绝
  `greater-equal comparison is not yet supported by typed checking`，使 `true >= false` 不泄漏 Bool
  operand diagnostic；既有 checkedAdd positive 与全部 expression exact controls 保持。tests-only RED
  必须且只能迁移 `Equal.lean` 最后一条 deferred `1 >= 2` negative，并证明删除后 reject list 结构有效；
  不得迁移 shift token negatives。不得加入 bitwise/logical binary operators、Bool legality、folding、
  Typed/Semantic comparison、requirement 或 target ABI/runtime；production 必须限于 Source/Syntax/Typed
  3 文件/11 行。GREEN、focused/aggregate/test binary 与独立审查全绿后必须在 committed tree 上运行一次
  CompareExpr 批量 `just ci` checkpoint；只有该 gate 全绿才能记录完整 CompareExpr Source surface。
- D1-PA-39 的 alpha binary bitwise-and tests 固定 production rule
  `syntax:45 pfExpr:45 " & " pfExpr:46 : pfExpr` 与 `Source.Expr.bitwiseAnd(lhs, rhs)`。precedence `45`
  必须严格低于 CompareExpr `50`，并按 EBNF `("&" CompareExpr)*` 左结合；`1 & 2 & 3` 必须接受并形成
  `(.bitwiseAnd (.bitwiseAnd 1 2) 3)`，不得误设为 non-associative。comparison mixed expressions 也必须
  合法：`1 & 2 == 3` 为 `1 & (2 == 3)`，`1 == 2 & 3` 为 `(1 == 2) & 3`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及双入口 parity，并精确固定 `1 & 2`、`2 & 1`、
  `a & b`、`0 & 0`、`true & false`、add/mul/shift/comparison 双向 precedence、grouping、unary、
  left-chain 与 explicit right-nesting 的 AST；operand legality 和 result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `20` 后依次编码 lhs/rhs；既有 tags `0..19`/goldens
  不变。BitwiseAndTwin identity 下 order/type/precedence/grouping/unary/shift/comparison/nesting cases 的真实
  bytes/hash 必须在 GREEN 前绑定，并以 comparison、checked-add、shift、operand order、left/right nesting、
  wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 & 2)` 与 `1 & 2` 必须产生
  相同 Source.Program/canonical bytes/sourceHash。
  bare/missing operand、`1 & & 2` 与 extra payload 必须停在 parser boundary；`1 && 2` 必须继续作为
  future LogicAndExpr retention negative，不能拆成两个 `&`。`Typed.check` 必须在 operand checking 前逐字
  拒绝 `bitwise and is not yet supported by typed checking`，使 `true & false` 不泄漏 Bool diagnostic；
  checkedAdd positive 与全部既有 expression exact controls 保持。本切片 zero migration，不得修改既有
  suites 的接受/拒绝用例。不得加入 `^`、`|`、`&&`、`||`、Bool legality、folding、Typed/Semantic
  bitwise、requirement 或 target ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行。
- D1-PA-40 的 alpha binary bitwise-xor tests 固定 production rule
  `syntax:40 pfExpr:40 " ^ " pfExpr:41 : pfExpr` 与 `Source.Expr.bitwiseXor(lhs, rhs)`。precedence `40`
  必须严格低于 BitAndExpr `45`，并按 EBNF `("^" BitAndExpr)*` 左结合；`1 ^ 2 ^ 3` 必须接受并形成
  `(.bitwiseXor (.bitwiseXor 1 2) 3)`，explicit `1 ^ (2 ^ 3)` 必须保留右嵌套。mixed expressions
  必须合法且树形固定：`1 & 2 ^ 3` 为 `(1 & 2) ^ 3`，`1 ^ 2 & 3` 为 `1 ^ (2 & 3)`，
  `1 ^ 2 == 3` 为 `1 ^ (2 == 3)`，`1 == 2 ^ 3` 为 `(1 == 2) ^ 3`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及双入口 parity，并精确固定 `1 ^ 2`、`2 ^ 1`、
  `a ^ b`、`0 ^ 0`、`true ^ false`、add/mul/shift/comparison/bitwise-and 双向 precedence、grouping、unary、
  left-chain 与 explicit right-nesting 的 AST；operand legality 和 result typing 留给 D2。
  Source canonical encoder 使用 append-only Expr tag `21` 后依次编码 lhs/rhs；既有 tags `0..20`/goldens
  不变。BitwiseXorTwin identity 下 order/type/precedence/grouping/unary/shift/comparison/and/nesting cases 的
  真实 bytes/hash 必须在 GREEN 前绑定，并以 bitwise-and、comparison、checked-add、shift、operand order、
  left/right nesting、wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下 `(1 ^ 2)` 与
  `1 ^ 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  bare/missing operand、`1 ^ ^ 2`、`1 ^^ 2` 与 extra payload 必须停在 parser boundary；`1 | 2` 必须
  继续作为 future BitOrExpr retention negative。`Typed.check` 必须在 operand checking 前逐字拒绝
  `bitwise xor is not yet supported by typed checking`，使 `true ^ false` 不泄漏 Bool diagnostic；checkedAdd
  positive 与全部既有 expression exact controls 保持。本切片 zero migration，不得修改既有 suites 的
  接受/拒绝用例。不得加入 `|`、`&&`、`||`、Bool legality、folding、Typed/Semantic bitwise、requirement
  或 target ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行。
- D1-PA-41 的 alpha binary bitwise-or tests 固定 production rule
  `syntax:35 pfExpr:35 " | " pfExpr:36 : pfExpr` 与 `Source.Expr.bitwiseOr(lhs, rhs)`。precedence `35`
  必须严格低于 BitXorExpr `40`，并按 EBNF `("|" BitXorExpr)*` 左结合；`1 | 2 | 3` 必须接受并形成
  `(.bitwiseOr (.bitwiseOr 1 2) 3)`，explicit `1 | (2 | 3)` 必须保留右嵌套。mixed expressions
  必须合法且树形固定：`1 ^ 2 | 3` 为 `(1 ^ 2) | 3`，`1 | 2 ^ 3` 为 `1 | (2 ^ 3)`，
  `1 & 2 | 3` 为 `(1 & 2) | 3`，`1 | 2 & 3` 为 `1 | (2 & 3)`，
  `1 | 2 == 3` 为 `1 | (2 == 3)`，`1 == 2 | 3` 为 `(1 == 2) | 3`。positive 必须覆盖
  initializer、entry、view、fn 的 return/let value 及双入口 parity，并精确固定 `1 | 2`、`2 | 1`、
  `a | b`、`0 | 0`、`true | false`、add/mul/shift/comparison/bitwise-and/xor 双向 precedence、grouping、
  unary、left-chain 与 explicit right-nesting 的 AST；operand legality 和 result typing留给 D2。
  Source canonical encoder 使用 append-only Expr tag `22` 后依次编码 lhs/rhs；既有 tags `0..21`/goldens
  不变。BitwiseOrTwin identity 下 order/type/precedence/grouping/unary/shift/comparison/and/xor/nesting cases
  的真实 bytes/hash 必须在 GREEN 前绑定，并以 bitwise-xor/and、comparison、checked-add、shift、operand
  order、left/right nesting、wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下
  `(1 | 2)` 与 `1 | 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  tests-only RED 必须且只能删除 `BitwiseXor.lean` 的 `("deferred bit-or", "1 | 2")` negative，并证明
  同一 program 内至少两个 enum variants 与 bitwise-or initializer/return expression 可在 Lean command 和
  ParserSession 双入口形成相同 Source.Program/sourceHash。bare/missing operand、`1 | | 2`、extra payload
  与 future `1 || 2` 必须停在 parser boundary；不得实现 match arm，但 future match parser 必须拥有 arm-token
  disambiguation。`Typed.check` 必须在 operand checking 前逐字拒绝
  `bitwise or is not yet supported by typed checking`，使 `true | false` 不泄漏 Bool diagnostic；checkedAdd
  positive 与全部既有 expression exact controls 保持。不得加入 `&&`、`||`、match、Bool legality、
  folding、Typed/Semantic bitwise、requirement 或 target ABI/runtime；production 必须限于 Source/Syntax/
  Typed 3 文件/11 行。GREEN、focused/aggregate/test binary 与独立审查全绿后必须在 committed tree 上
  运行一次 bitwise-tier 批量 `just ci` checkpoint，才可记录完整 bitwise Source surface。
- D1-PA-42 的 alpha binary logical-and tests 固定 production rule
  `syntax:30 pfExpr:30 " && " pfExpr:31 : pfExpr` 与 `Source.Expr.logicalAnd(lhs, rhs)`。precedence `30`
  必须严格低于 BitOrExpr `35`，并按 EBNF `("&&" BitOrExpr)*` 左结合；`1 && 2 && 3` 必须接受并形成
  `(.logicalAnd (.logicalAnd 1 2) 3)`，explicit `1 && (2 && 3)` 必须保留右嵌套。mixed expressions
  必须合法且树形固定：`1 | 2 && 3` 为 `(1 | 2) && 3`，`1 && 2 | 3` 为 `1 && (2 | 3)`，
  `1 == 2 && 3` 为 `(1 == 2) && 3`，`1 && 2 == 3` 为 `1 && (2 == 3)`；与 bitwise-xor/and
  的双向树形也必须按既有层级固定。positive 必须覆盖 initializer、entry、view、fn 的 return/let value
  及双入口 parity，并精确固定 `1 && 2`、`2 && 1`、`a && b`、`0 && 0`、`true && false`、
  add/mul/shift/comparison/bitwise-and/xor/or 双向 precedence、grouping、unary、left-chain 与 explicit
  right-nesting 的 AST；operand/result legality 和 short-circuit Typed/Semantic 实现留给 D2。
  Source canonical encoder 使用 append-only Expr tag `23` 后依次编码 lhs/rhs；既有 tags `0..22`/goldens
  不变。LogicalAndTwin identity 下 order/type/precedence/grouping/unary/shift/comparison/bitwise/nesting cases
  的真实 bytes/hash 必须在 GREEN 前绑定，并以 bitwise-and/or、comparison、checked-add、operand order、
  left/right nesting、wrong precedence tree 与 Bool order 作为 non-alias。相同 identity 下
  `(1 && 2)` 与 `1 && 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  tests-only RED 必须且只能删除 `BitwiseAnd.lean` 的 `("deferred logic-and", "1 && 2")` negative；
  同 suite 的 spaced `1 & & 2` survival pin 与其他既有 suite 不得修改。bare/missing operand、
  `1 && && 2`、`1 &&& 2`、`1 & && 2` 与 extra payload 必须停在 parser boundary；
  `BitwiseOr.lean` 的 future `1 || 2` retention negative 必须保持不动。`Typed.check` 必须在 operand
  checking 前逐字拒绝 `logical and is not yet supported by typed checking`，使 `true && false` 不泄漏
  Bool diagnostic；checkedAdd positive 与全部既有 expression exact controls 保持。不得加入 `||`、
  short-circuit lowering、Bool legality、folding、Typed/Semantic logical operation、requirement 或 target
  ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行。本切片只运行 focused/aggregate/
  test binary，logical-tier committed-tree 批量 `just ci` 延后到 logical-or 收口。
- D1-PA-43 的 alpha binary logical-or tests 固定 production rule
  `syntax:25 pfExpr:25 " || " pfExpr:26 : pfExpr` 与 `Source.Expr.logicalOr(lhs, rhs)`。precedence `25`
  必须严格低于 LogicAndExpr `30`，并按 EBNF `("||" LogicAndExpr)*` 左结合；`1 || 2 || 3` 必须接受
  并形成 `(.logicalOr (.logicalOr 1 2) 3)`，explicit `1 || (2 || 3)` 必须保留右嵌套。mixed expressions
  必须合法且树形固定：`1 && 2 || 3` 为 `(1 && 2) || 3`，`1 || 2 && 3` 为
  `1 || (2 && 3)`，`1 | 2 || 3` 为 `(1 | 2) || 3`，`1 || 2 | 3` 为
  `1 || (2 | 3)`，`1 == 2 || 3` 为 `(1 == 2) || 3`，`1 || 2 == 3` 为
  `1 || (2 == 3)`。positive 必须覆盖 initializer、entry、view、fn 的 return/let value 及双入口 parity，
  并精确固定 `1 || 2`、`2 || 1`、`a || b`、`0 || 0`、`true || false`、add/mul/shift/comparison/
  bitwise/logical-and 双向 precedence、grouping、unary、left-chain 与 explicit right-nesting 的 AST；
  operand/result legality 和 short-circuit Typed/Semantic 实现留给 D2。
  Source canonical encoder 使用 append-only Expr tag `24` 后依次编码 lhs/rhs；既有 tags `0..23`/goldens
  不变。LogicalOrTwin identity 下 order/type/precedence/grouping/unary/shift/comparison/bitwise/logical-and/
  nesting cases 的真实 bytes/hash 必须在 GREEN 前绑定，并以 logical-and/bitwise-or、comparison、
  checked-add、operand order、left/right nesting、wrong precedence tree 与 Bool order作为 non-alias。
  相同 identity 下 `(1 || 2)` 与 `1 || 2` 必须产生相同 Source.Program/canonical bytes/sourceHash。
  tests-only RED 必须且只能删除 `BitwiseOr.lean` 的 `("double pipe", "1 || 2")` negative；同 suite 的
  spaced `1 | | 2` survival pin 与其他既有 suite 不得修改。bare/missing operand、`1 || || 2`、
  `1 ||| 2`、`1 | || 2` 与 extra payload 必须停在 parser boundary。`Typed.check` 必须在 operand
  checking 前逐字拒绝 `logical or is not yet supported by typed checking`，使 `true || false` 不泄漏
  Bool diagnostic；checkedAdd positive 与全部既有 expression exact controls 保持。不得加入 match、
  short-circuit lowering、Bool legality、folding、Typed/Semantic logical operation、requirement 或 target
  ABI/runtime；production 必须限于 Source/Syntax/Typed 3 文件/11 行。GREEN 与 focused/aggregate/test
  binary 全绿后必须在 committed tree 上运行 logical-tier 批量 `just ci`；只可声明 Source operator
  precedence tower 覆盖，不得声明 MatchExpr、完整 expression/statement grammar 或正式 D1 完成。
- D1-PA-44 的 alpha StringLiteral tests 固定 `syntax str : pfExpr` 与
  `Source.Expr.stringLiteral(value : String)`。decoder 必须读取 Lean 已解码的 `str.getString`，quote 必须
  通过 `Syntax.mkStrLit` 往返；positive 覆盖 initializer、entry、view、fn 的 return/let value 和 Lean
  command/ParserSession 双入口 parity，并精确固定 empty、ASCII、escaped quote、backslash、tab、Unicode
  scalar。不同 escape spelling 解码为相同 String 时必须得到相同 Source.Program/canonical bytes/sourceHash；
  同一 fixed identity 下 string `"a"` 与 variable `a` 必须因 tag `25` 对既有 variable tag `1` 而不 alias。
  Source canonical encoder 必须以 append-only Expr tag `25` 后接现有 length-prefixed UTF-8 string；既有
  tags `0..24`/goldens 不变。tests-only RED 为 zero migration，只新增 `Tests.Language.StringLiterals` 并在
  `Tests.lean`/`lakefile.lean` 注册；相邻 `"a" "b"`、interpolated `s!"a"` 与 unterminated string 必须停在
  parser boundary。`Typed.check` 必须逐字拒绝
  `string literals are not yet supported by typed checking`，且既有 checked-add positive 与 expression exact
  controls 保持。不得新增 String ValueType、concatenation、interpolation、folding、Typed/Semantic string、
  ABI/runtime、call/constructor/place 或 match；production 必须限于 Source/Syntax/Typed 3 文件/9 行。
  本切片只运行 focused/aggregate/test binary，完整 `just ci` 延后到下一批 primary-expression checkpoint；
  收口只可声明 EBNF Literal 的 Source carrier 覆盖，不得声明 PrimaryExpr、完整 grammar 或正式 D1 完成。
- D1-PA-45 的 alpha LocalFnCall tests 固定完整 `syntax:max ident "(" pfExpr,* ")" : pfExpr` 与
  `Source.Expr.localFnCall(callee, args)`，不得拆成零参数专用 AST。positive 覆盖 initializer、entry、view、
  fn 的 return/let value 和 Lean command/ParserSession parity；精确固定 `f()`/`f ()`、`f(1)`、
  `f(1, 2)`、operator/group/string arguments、`f(g(1), 2)` nested tree、call result 作为 unary/binary operand，
  以及 escaped 单组件 callee。每个 argument 必须按完整 `pfExpr` 解析并保持声明次序。
  Source canonical encoder 使用 append-only Expr tag `26`，随后编码 callee 与 argument array；既有
  tags `0..25`/goldens 不变。固定 identity 下 callee、count、argument order/nesting 与 expression kind 必须
  non-alias，grouped/direct 同一 argument 必须 canonical equal，localFnCall `f()` 与 variable `f` 必须因
  tag `26`/`1` 不 alias。tests-only RED 必须且只能删除 `Grouping.lean` 的 call-like `f(1)` negative；
  empty group、tuple 与其他 negatives 保持。missing callee/paren、leading/trailing/double comma、missing/
  adjacent argument、unescaped reserved token 必须 parser reject；qualified `A.B()`/`A.B(1)` 必须在 arguments
  前逐字拒绝 `local function call callee must be unqualified`，保留给 future ConstructorExpr。
  `Typed.check` 必须在 argument checking/fn lookup 前逐字拒绝
  `local function calls are not yet supported by typed checking`，以 Bool/string argument 固定 failure priority，
  既有 checked-add positive 保持。本切片不得实现 fn resolution、arity/type/return/recursion、constructor/
  external call/place/match、Semantic/requirement/target；production 限于 Source/Syntax/Typed 3 文件/13 行。
  本切片只运行 focused/aggregate/test binary；call-like primary 批量 `just ci` 延后到后续单一 slice，
  收口不得声明 PrimaryExpr、完整 grammar 或正式 D1 完成。
- D1-PA-46 的 alpha ConstructorExpr tests 复用既有 call-like syntax，并固定
  `Source.Expr.constructorExpr(path : Array String, args : Array Expr)`；path 为至少两个组件的
  canonical array，不是 dotted string。positive 覆盖 initializer、entry、view、fn return/let 的
  Lean command/ParserSession parity；zero/one/multiple、operator/group/string arguments、constructor 嵌套、
  constructor 作 operator operand、two/multi-component path 和 escaped portable component。decoder 必须在
  arguments 前逐组件应用 portable reserved policy 与 common QualifiedName canonical validation。
  Source canonical encoder 使用 append-only Expr tag `27`，然后编码 path array 和 args array；固定
  component value/count/order、argument value/count/order/nesting 与 expression kind non-alias，并要求
  constructor `A.B()`、local call `f()`、variable `f` 三者不 alias。tests-only RED 必须且只能
  删除 `LocalFnCalls.lean` 中 `A.B()`/`A.B(1)` 两条既有 exact-unqualified negatives；其他
  malformed-list/local-call boundaries 保持。reserved/numeric/invalid qualified components、missing path/paren、
  leading/trailing/double comma、missing/adjacent arg 必须 fail closed。`Typed.check` 必须在 argument
  checking/constructor lookup 前逐字拒绝
  `constructor expressions are not yet supported by typed checking`，以 Bool/string arguments 固定优先级。
  本切片不得实现 constructor resolution/arity/type/result、Place/Match/ExternalCall、Semantic/
  requirement/target；production 限 Source/Syntax/Typed 3 文件、最多 24 行新增且不新增 syntax rule。
  focused/aggregate/test binary 与 final review 全绿后，必须在 clean committed tree 运行 call-like
  primary batch `just ci`；收口不得声明 PrimaryExpr、完整 grammar 或正式 D1 完成。
  Component-count 分类的消歧 controls 必须固定：`A.B()` 是 ConstructorExpr，
  whole-escaped `«A.B»()` 仍是单组件 LocalFnCall，bare `A.B` 仍是 variable；
  `«A».B(1)`/`A.«B»(1)` 的合法 escaped component 必须与普通 `A.B(1)` 产生同一
  canonical path。这些是对既有冻结分类和 escaped-component coverage 的明确化，不增加新任务输出。
- D1-PA-47 的 alpha index-access tests 固定
  `syntax:max ident "[" pfExpr "]" : pfExpr` 与
  `Source.Expr.indexAccess(base : String, index : Expr)`，只覆盖 bare `Ident` base 的单个 rvalue bracket
  suffix。positive 覆盖 initializer、entry、view、fn return/let 的 Lean command/ParserSession parity；
  `x[0]`/`x [0]`、escaped portable base、完整 operator/group/local-call/constructor index expression，及
  indexAccess 作为 unary/binary operand。decoder 必须先验证 base 恰好一个 `Name` component 并解码 base，
  再解码 index；`A.B[true]` 必须在 Bool index 前逐字拒绝
  `index access base must be unqualified`。Source canonical encoder 使用 append-only Expr tag `28` 后接
  base string 与 index expression；固定 base value、index value/tree、spacing/escape canonical equality，
  以及 `x[0]` 对 variable `x` 的 tag `28`/`1` non-alias。
  tests-only RED 为 zero migration，只新增/注册 `Tests.Language.IndexAccesses`。empty/missing/malformed bracket、
  missing base/index、`(x)[0]`、`f()[0]`、`A.B[0]`、`x[0][1]`、`x[0] := 1` 与 extra payload 必须 fail closed；
  既有 dotted-variable 和 bare-ident assignment controls 保持。`Typed.check` 必须在 base resolution/index
  checking 前逐字拒绝 `index access is not yet supported by typed checking`，以 unknown base 与 Bool/string
  index 固定优先级。本切片不得实现 field/chaining/indexed assignment/general postfix、Place resolution、
  lvalue/container/index/bounds/read semantics、Match/ExternalCall、Semantic/requirement/target；production 限于
  Source/Syntax/Typed 3 文件、最多 14 行新增。本切片只运行 focused/aggregate/test binary，下一批
  primary-expression checkpoint 再运行完整 `just ci`；收口不得声明完整 Place、PrimaryExpr、完整 grammar
  或正式 D1 完成。
- D1-PA-48 的 alpha revert statement tests 固定完整
  `"revert" Ident ("(" ExprList? ")")?` 与
  `Source.Statement.revertStmt(errorName : String, args : Array Expr)`，不得拆成 bare-only 与 payload 两套
  AST。positive 覆盖 initializer、entry、view、fn 的 Lean command/ParserSession parity；bare
  `revert Err`、empty `revert Err()`、one/multiple arguments、operator/group/string/local-call/constructor/
  index arguments 与 nested argument tree；`revert Err(1)` 必须证明 parenthesized rule 在 strict-prefix
  bare fallback 之前完成 parse。bare/empty-paren 必须在同一 fixed identity 下产生相同
  Source.Program/canonical bytes/sourceHash。
  Source canonical encoder 使用 append-only Statement tag `5` 后接 errorName string 与 argument array；
  固定 name、argument value/count/order/nesting 与 statement kind non-alias，尤其同 payload name 下的
  revert tag `5` 对 synchronousCall tag `2` 不得 alias。tests-only RED 为 zero migration，只新增/注册
  `Tests.Language.RevertStatements`。decoder 必须先验证 errorName 恰好一个 `Name` component 并应用既有
  identifier policy，再解码 arguments；`A.B(true)` 必须在 Bool argument 前逐字拒绝
  `revert error name must be unqualified`。
  missing name/paren、leading/trailing/double comma、missing/adjacent arg、extra payload 与 unescaped keyword
  lookalikes 必须停在 parser boundary；escaped assignment identifier 保持。`Typed.check` 必须在
  error lookup/arity/type 与 argument checking 前逐字拒绝
  `revert statements are not yet supported by typed checking`，以 unknown name 与 Bool/string arguments
  固定优先级；既有 return/assign/call/let/assert controls 保持。本切片不得实现 error resolution、
  payload legality、failure/rollback、Typed/Semantic revert、ABI/runtime、requirement/target；production 限于
  Source/Syntax/Typed 3 文件、最多 20 行新增。本切片只运行 focused/aggregate/test binary，下一批
  statement checkpoint 再运行 `just ci`；收口不得声明完整 error semantics、statement grammar或正式
  D1 完成。
- D1-PA-49 的 alpha value-less return tests 只新增 nullary
  `Source.Statement.returnUnit`，补齐 EBNF `"return" Expr?` 的无 Expr Source 分支，并明确只 supersede
  `EV-20260718-0002` 的“无无值 return”carrier 延期；旧 evidence 对 Unit fallthrough、D2 return-path/type、
  target 的限制继续有效。positive 覆盖 initializer、entry、view、fn，explicit/omitted Unit 与 non-Unit
  declaration，以及 Lean command/ParserSession Source parity；这些只证明 Source 可表达，不得出现 Typed
  success。value-bearing return 必须改为 named `returnValueStmt`，用 `leading_parser`、`withPosition` 与
  `checkLineEq <|> checkColGt` 固定同一行或严格增加缩进的 Expr；bare `syntax "return" : pfStmt` 为
  fallback。测试必须固定 `return 1` 与 `return true` 仍为既有 `returnValue`，严格增加缩进的
  `return` newline `  1` 保留 multiline `returnValue`，同 statement column 的 `return` newline `1`
  必须 parser reject，而 bare 后同缩进 `x := 1` 必须解析为 returnUnit 后 assignment。
  该 correction 来自首次 GREEN 的真实失败：unrestricted 跨行 Expr 会吞下一 item 的 contextual `fn`
  或下一 statement identifier；不得通过 fixture 重排或枚举 statement introducer 掩盖。现有 suite
  migration 仍为零，只修改本切片新 RED 中错误的同缩进跨行预期。
  Source canonical encoder 使用 append-only Statement tag `6` 且无 payload；固定 returnUnit golden/size、
  对 returnValue tag `1` 及其他 statement kind non-alias，并保证既有 tags/goldens 不变。tests-only RED
  为 zero migration，只新增/注册 `Tests.Language.ValueLessReturns`。
  `return()`、bare 后括号/逗号/额外 payload、unescaped keyword assignment 必须 parser reject，escaped
  `«return» := 1` 保持 assignment。`Typed.check` 必须在 result type、Unit materialization、initializer
  legality 与 return-path 分析前逐字拒绝
  `value-less return is not yet supported by typed checking`；omitted-result fn、non-Unit entry 与 initializer
  都必须固定该优先级。首次 aggregate test-binary 验证确认既有 generic fn gate 会先于 statement checker
  返回，因此允许在该 gate 内增加 returnUnit exact-priority 检查；普通 fn 仍须保持原 fail-closed。本切片不得把
  `returnValue` 改为 Option，不得实现 implicit Unit/fallthrough、
  statement-after-return、type/effect、Semantic/requirement/target；production 限于 Source/Syntax/Typed
  3 文件、最多 12 行新增/2 行移除。focused/aggregate/test binary 与 final reviews 全绿后，在 clean committed tree
  运行一次 statement checkpoint `just ci`；收口不得声明 return semantics、完整 statement grammar 或
  正式 D1 完成。
- D1-PA-50 的 alpha emit statement tests 只新增完整
  `Source.Statement.emitStmt(eventName : String, args : Array Expr)`，对应 mandatory-parentheses
  `"emit" Ident "(" ExprList? ")"`；`emit Tick()` 接受 empty args，bare `emit Tick` 必须 parser reject，
  不得拆成 optional-paren 或多套 carrier。positive 覆盖 initializer、entry、view、fn，zero/one/multi、
  operator/group/string/local-call/constructor/index/nested arguments，以及 Lean command/ParserSession
  Source parity；event declaration 只证明 Source coexistence，不得出现 Typed/event semantics success。
  decoder 必须先做 single-component event-name guard 与 portable identifier validation，再解码 args。
  Source canonical encoder 使用 append-only Statement tag `7` 后接 eventName string 与 argument array；
  固定 name、argument value/count/order/nesting、tag `7` 对 revert/call/assert/return non-alias，并保证
  tags `0..6`/既有 goldens 不变。tests-only RED 为 zero migration，只新增/注册
  `Tests.Language.EmitStatements`。
  missing name/parenthesis、bare name、malformed list、extra payload 与 unescaped `emit := 1` 必须 parser
  reject，escaped `«emit» := 1` 保持 assignment；qualified name 必须在 Bool/string argument 前得到 exact
  `emit event name must be unqualified`，reserved name 走既有 policy。`Typed.checkStatement` 必须在
  event lookup、argument checking、view/effect analysis前逐字拒绝
  `emit statements are not yet supported by typed checking`；含 event table 的 surface 仍由既有 generic
  event gate fail closed，普通 event declaration diagnostic 不得改变。本切片不得实现 event resolution、
  payload arity/type、emission/effect、Semantic/requirement、ABI/runtime/target；production 限于
  Source/Syntax/Typed 3 文件、最多 16 行新增且不移除既有 production。focused/aggregate/test binary 与
  final reviews 全绿后收口；PA49 已运行 statement checkpoint，本切片不重复 `just ci`，不得声明完整
  event semantics、statement grammar 或正式 D1 完成。
- D1-PA-51 的 alpha assert-error tests 新增 append-only
  `Source.Statement.assertErrorStmt(condition : Expr, errorName : String)`，补齐
  `assert Expr else Ident` optional-error Source 分支；既有 bare `assertStmt`/tag `4`/surface/goldens 不变。
  parser 的 longer error rule 必须位于 bare assert rule 前并完整消费 `else Ident`。positive 覆盖
  initializer、entry、view、fn 的 Lean command/ParserSession parity，literal/Bool/variable/operator/group
  condition 与普通/等价 escaped error name。decoder 必须先做 single-component error-name guard 和 portable
  validation，再解码 condition；qualified/reserved name 必须在 overflow/Bool/string condition 前得到 exact
  name diagnostic。Source canonical encoder 使用 append-only Statement tag `8`，再编码 condition 与
  errorName；固定 condition value/tree、error name、tag `8` 对 bare assert/revert/emit/return 的 non-alias，
  tags `0..7` 与既有 goldens 不变。
  tests-only RED 必须且只能删除 `AssertStatements.lean` 中 `assert true else Failure` 一条 deferred
  negative，并在同一 suite 加入 positive/negative/canonical/Typed controls；不得新注册 module 或迁移
  其他 suite。missing error name、qualified/reserved error name、`Failure()`/`Failure(1)`、duplicate `else`、
  extra payload 与 block-like shape 必须拒绝；bare assert、bare/escaped keyword assignment、assertValue 与
  原 tag-4 goldens 保持。`Typed.checkStatement` 必须在 condition checking、error lookup 与 Bool/effect
  analysis前返回既有 exact `assert statements are not yet supported by typed checking`；error-table-only
  program 继续得到既有 generic diagnostic。本切片不得实现 error resolution/Bool typing/failure semantics、
  Semantic/requirement/effect/ABI/runtime/target；production 限 Source/Syntax/Typed 3 文件、最多 14 行新增且
  不移除既有 production。focused/aggregate/test binary 与 final reviews 全绿后收口；按冻结不运行
  `just ci`，不得声明完整 assert semantics、statement grammar 或正式 D1 完成。
- D1-PA-52 的 alpha conditional tests 新增
  `Source.Statement.ifStmt(condition : Expr, thenBody : Array Statement,
  elseBody : Option (Array Statement))`，完整覆盖 `if Expr then Block (else Block)?` Source surface。
  parser 只允许一条 optional-else surface。tests-only RED 证明 `ppLine` 不是 parser 换行约束；
  因此实现必须使用一条 `withPosition` custom `ifStmt` parser，以
  `checkLinebreakBefore`/`checkColGt` 固定换行与深缩进、`checkColEq` 固定 owning-if
  `else` 列，then/else 内部均为 `many1Indent(pfStmt)` non-empty block。nested if 必须按
  layout 绑定最近的内层/outer branch。positive 覆盖 initializer、entry、view、fn 的
  Lean command/ParserSession parity，
  if-then/if-then-else、literal/Bool/variable/operator/group condition、multi-statement branch 与 nested if。
  decoder 顺序必须为 condition→then→else，并对 custom parser 的 exact `ifStmt` kind、五段
  node shape 与 optional group fail closed；quotation 必须结构化保留 recursive arrays 与 Option marker。
  Source canonical encoder 使用 append-only Statement tag `9`，再编码 condition、then-body array、
  marker `0`/`1` 及可选 else-body array；固定 condition value/tree、then count/order、else
  presence/content、nested kind 和 tag non-alias，tags `0..8`/旧 goldens 不变。
  tests-only RED 为 zero migration，只新增/注册 `Tests.Language.IfStatements`。missing
  condition/`then`、same-line 或 empty then-body、dangling/wrong-column/duplicate `else`、empty
  else-body、extra payload 必须 parser reject；`then := 1`/`else := 1` 拒绝，`«then» := 1`/
  `«else» := 1` 保持 assignment。`Typed.checkStatement` 在 condition/branch/return/effect analysis 前
  exact 返回 `if statements are not yet supported by typed checking`，旧 statement controls 不变。
  本切片不实现 Bool typing、branch join、return/effect/path、Semantic/requirement、target/runtime；
  production 限 Source/Syntax/Typed 3 文件、最多 38 行新增/3 行移除；其中两行移除用于
  recursive encoder/decoder 的 `partial` 替换，第三行用于将 generic decoder catch-all 替换为
  exact custom-node shape 验证与 fail-closed catch-all。focused/aggregate/test binary 和 final review 全绿后
  收口；按冻结不运行 `just ci`，不得声明 Typed conditional semantics、完整 statement grammar
  或正式 D1 完成。
- D1-PA-53 的 alpha bounded-for tests 新增
  `Source.IterationBound := Fin 4097` 与
  `Source.Statement.forStmt(iterator : String, start : Expr, stopExclusive : Expr,
  maxIterations : IterationBound, body : Array Statement)`，完整覆盖
  `for Ident in Expr ..< Expr bounded Nat do Block` Source surface。唯一 position-sensitive parser
  必须固定整条 header 同行、exact `..<` token、`do` 后真实换行和更深缩进的 non-empty
  `many1Indent(pfStmt)` body。spaced `0 ..< 10` 与 compact `0..<10` 必须形成同一 Source tree，
  内部拆开的 `.. <` 必须拒绝。bound 必须复用 `Bytes N` 的 exact ASCII decimal `0..4096`
  lexical discipline，禁止 unchecked host literal/`getNat` 转换，改为逐字符验证、手工累积与即时上界检查；
  `0`/`4096` 接受，`4097`/`01`/`0x10`/signed/underscore 拒绝。
  decoder exact 验证 custom kind、tokens、null body group 与 non-empty shape，顺序为
  iterator→start→stopExclusive→maxIterations→body；quotation 结构化递归保留 body array。
  Source canonical encoder 使用 append-only Statement tag `10`，再编码 iterator string、两个 endpoint
  expression、`appendNat maxIterations.val` 与 body array；固定 iterator、endpoint value/tree、bound、body
  count/order/nesting、tag non-alias，tags `0..9`/旧 goldens 不变。RED 中 canonical hash/size 必须显式
  未绑定，独立 probe 后单独提交 golden binding。
  tests-only RED 为 zero migration，只新增/注册 `Tests.Language.ForStatements`。positive 覆盖
  initializer、entry、view、fn 的 Lean command/ParserSession parity、bound `0`/`4096`、literal/variable/
  operator/group endpoints、multi-statement body 与 nested if/for。missing iterator/`in`/`..<`/stop/
  `bounded`/bound/`do`、header split、same-line/same-column/empty body、内部拆开的 `.. <`、extra payload 与上述
  malformed bounds 必须 parser reject；`for := 1`/`in := 1`/`bounded := 1` 拒绝，escaped 三词保持
  assignment。`Typed.checkStatement` 在 iterator/endpoint/bound/body/return/effect analysis 前 exact 返回
  `for statements are not yet supported by typed checking`，旧 statement controls 不变。本切片不实现
  iterator scope/type、range evaluation、bounded-loop proof/induction、return/effect/path、Semantic/
  requirement、target/runtime；production 限 Source/Syntax/Typed 3 文件、最多 34 行新增且不移除既有
  production，并同 GREEN 刷新 Lean package file-set。focused/aggregate/test binary、independent review 与
  PA50–PA53 committed-tree batch `just ci` 全绿后收口；不得声明 loop semantics、完整 statement grammar
  或正式 D1 完成。
  RED 后另固定 canonical security regression：裸 `Nat` 的 `0`/`2^64` 会经 `UInt64.ofNat` alias，故
  production 必须以 `Fin 4097` 使越界 public Source bound 不可表示，并证明任意 carrier 的 `.val ≤ 4096`；
  这不改变合法 surface/golden，也不得增加 fallback 或 runtime clamp。
- invariant declaration 覆盖 exact name 与当前 alpha literal/variable/checked-add predicate；
  name/predicate/count/order、同前缀 declaration count、expression kind/value/operand order 必须进入
  canonical source binding。duplicate invariant 固定在 duplicate callable 与 duplicate extension 之间；
  escaped contextual keyword、普通/escaped 保留名、reserved predicate 与 literal overflow 必须双入口
  exact fail closed，name decode 必须优先于 predicate decode。`invariant` 不得污染宿主 Lean keyword 集，
  普通 `state` declaration 不得被 generic contextual parser 误分类。D2 predicate Bool type checking、
  name/pure-fn resolution 与 proof binding 尚未实现时必须在 `Typed.check` fail closed，不能静默丢弃或
  进入 target Plan。
- extension requirement 覆盖 lowercase dotted ID、完整 SemVer prerelease/build identity 与 exact
  lowercase SHA-256 digest；id/version/digest/count/order 及同前缀 declaration count 必须分别进入
  canonical source binding。duplicate 按 ID 拒绝，固定在 duplicate invariant 与 initializer parameter
  之间；malformed/uppercase/single-segment ID、range/latest/wildcard/v-prefix/leading-zero/overflow
  SemVer、bare/uppercase/wrong-length digest 与 escaped contextual introducer 必须双入口 fail closed，
  decode 首错固定为 id→version→digest。`requires`/`extension`/`version`/`digest` 不得污染宿主 Lean
  keyword 集。D2 typed registry、extension semantics、requirement inference 与 support resolution 尚未
  实现时必须在 `Typed.check` fail closed，不能从 Source 声明直接生成可信 requirements。
- proof reference 覆盖 exact invariant name 与 theorem QualifiedName component array；reference
  presence/count/order、invariant 名、theorem component count/value/order 必须分别进入 canonical source
  binding。duplicate 按 invariant 拒绝且先于 unknown invariant；unknown 按 proof 源码顺序做 exact、
  case-sensitive lookup，forward declaration 成功，unqualified/whole-escaped dotted theorem、escaped
  introducer、reserved invariant 与 theorem 内 escaped reserved component 双入口 fail closed；theorem
  每个 component 复用 DSL reserved-identifier policy，decode 首错固定为 invariant→theorem。extension
  duplicate→proof duplicate→unknown invariant→initializer parameter 的 validation priority 必须稳定。
  `proof` 不得污染宿主 Lean identifier；D1 不读取 ambient environment/`.olean`/proof bundle，不查 theorem
  或签名。完整 proof validation 未实现时手工构造的 nonempty proof table 必须在 `Typed.check` fail closed。
- 本切片只证明当前 alpha constructors 的双入口 AST/validation parity，作为 D1-03/05 的
  pre-acceptance evidence；不关闭 token/span/NodeId、persistent export extension/schema、import
  diamond、完整 grammar、Diagnostic v1、parser containment 或正式 D1 任务。

### EVM 通用 UInt64 lowering 首个验收切片

- `TST-EVM-001`：`EvmPlan` 拥有 storage、constructor、entry、ABI selector 和 target-owned
  expression/statement；重复 selector/slot、dangling state/param、非 `UInt64` 或非 public 参数失败。
- `TST-EVM-002`：除 Counter 外，`Accumulator` 的 `total`、`seed`、`add(amount)`、
  `current()` 必须逐项从 `SemanticProgram` 映射，生产路径不得依赖 `isExactCounter`。
- `TST-EVM-003`：Keccak selector 使用 Ethereum padding 并通过 empty/increment/get/add/current
  golden；Yul/ABI 使用 Plan 内名字、selector、slot 和 body，不含 Counter 固定正文。
- `TST-EVM-004`：CLI 从 `Examples/Accumulator.lean` 生成可由锁定 `solc` 接受的 Yul、ABI
  与 deploy bytecode。
- `TST-EVM-005`：保留 Counter 回归，并在隔离 Anvil 验证 Accumulator `init(7)`、
  `add(5)=12`、`current()=12`、max+1 revert 且 state 仍为 max。

### Solana 通用 UInt64 planning 首个验收切片

- `TST-SOL-001`：`SolanaPlan` 必须拥有 state-account header/layout、owner/writable/init
  约束、layout-bound marker、zero-all-fields init policy、instruction discriminator/参数/body；
  不得保存或重新读取整个 `SemanticProgram`。
- `TST-SOL-002`：除 Counter 外，`Accumulator` 的 `total`、`seed`、`add(amount)`、
  `current()` 必须逐项映射；生产路径不得调用 `isExactCounter` 或按名字特判。
- `TST-SOL-003`：Plan lowering 生成数据驱动的 typed audit IR/plan text 与 IDL；instruction
  data 固定为 domain-separated SHA-256 前 8 bytes + little-endian `UInt64[]`，state account
  先验证 owner/data/init，再执行 body。
- `TST-SOL-004/005`：当前切片没有 SBF assembler/ELF/local-runtime 工具证据，manifest
  必须保持 `ArtifactDeployability=intermediate-only`；不得把 plan assembly 写成 ELF 或 runtime
  completion。

### NEAR 通用 UInt64 Plan/recipe/WAT 首个验收切片

- `TST-NEAR-001`：`NearPlan` 必须拥有 codegen profile、raw ABI、target-owned KV layout、
  layout-bound initialized marker、zero-all-fields init policy、host import allowlist、method
  mode/参数/body/return 与明确 trap/deposit policy；不得保存或重新读取整个 `SemanticProgram`。
  forged descriptor、未知 Semantic schema、非 canonical requirements/ID、重复或悬空 KV binding
  必须 fail closed。
- `TST-NEAR-002`：除 Counter 外，`Accumulator` 的 `total`、`seed`、`add(amount)`、
  `current()` 以及 literal-return lookalike 必须逐项从 target-neutral semantics 映射；生产路径
  不得调用 `isExactCounter`、按 program/entry 名字特判或复用固定 Counter WAT。
- `TST-NEAR-003`：Plan lowering 必须生成 typed NEAR module recipe，再由 recipe 生成 WAT；
  Plan 和 recipe 分别验证，recipe 必须是 Plan 的 exact canonical lowering，WAT 随后交给锁定
  `wat2wasm`。`near-wasm-raw-u64-v1` 对每个 export
  使用 exact `8 * parameter-count` bytes little-endian input，包括零参数方法必须拒绝 trailing
  bytes；`UInt64` return 固定为 8-byte little-endian。initializer 先确认 marker absent，再把所有
  state fields 物化为零、执行业务 init、最后写 marker；entry/view 要求 marker present 且匹配。
  每次 KV read 必须同时验证 found 与 register length `== 8`，view recipe 不得包含 write。
  initializer/mutate 必须在 KV 操作前要求 `attached_deposit` 的 `u128 == 0`；view 固定
  `query-only` 且不得调用在 ViewFunction context 中被禁用的 deposit host function。
- `TST-NEAR-003` 的 mutation/host-model 向量至少覆盖 init twice、entry before init、零参数多余
  输入、7/8/9-byte 输入、missing/0/7/9-byte storage、store 后读取新值、`7 + 5 = 12`，以及
  `UInt64.max + 1` 失败。任何失败路径不得被 validator 接受为 partial recipe/artifact。
- `TST-NEAR-004`：只允许 lock 中固定 pathname/version/digest 的 `wat2wasm` 把 WAT 编译为
  Wasm；missing、shadow、version/hash mismatch、unknown import/export 和 structural validation
  failure 必须 fail closed。该 gate 只证明确定性 WAT/Wasm 与结构合法，不是 NEAR runtime 证据。
- `TST-NEAR-005` 在获得 sandbox receipt differential 前保持未闭合。本切片没有 sandbox
  receipt、部署/调用观测、overflow rollback 观测、JSON ABI、Promise/callback 或跨 receipt
  workflow 证据；不得从 typed recipe、WAT、`wat2wasm` 成功或 raw ABI metadata 推断这些能力。

### Noir 通用 UInt64 relation/source 首个验收切片

- `TST-NOIR-001`：`NoirPlan` 必须拥有 exact descriptor/schema/profile、source dialect、
  source/semantic/complete-Plan hash、state bindings、完整 relation catalog、disclosure、failure/proof/
  continuity/resource policy；不得保存或重新读取整个 `SemanticProgram`。有状态程序必须有且
  只有一个首位 initializer；initializer、mutate、view 分别成为独立 relation，不允许 selector
  或 inactive witness 把不同生命周期折叠为一个电路。forged descriptor/profile/hash、未知
  Semantic schema、非 canonical requirements/ID、重复 relation/state、悬空引用、view write、
  commitment-only input 和超过资源上限必须 fail closed。
- `TST-NOIR-002`：除 Counter/PrivateSum4 外，`Accumulator` 的 `total`、`seed`、
  `add(amount)`、`current()` 必须逐项映射；生产路径不得调用 fixture shape matcher、按
  program/entry 名字特判或静默丢弃 initializer/view。initializer 显式约束
  `pre_initialized=false`、零起始业务状态、post-state 与 `post_initialized=true`；mutate/view
  约束 `true → true`，view 必须保持全部 state，mutate 必须把顺序 store 的最终值同时绑定到
  post-state/result。
- `TST-NOIR-003`：Plan 必须先降为 target-owned typed relation IR，再渲染 source；IR 只含
  typed input/literal/temp references、native checked `u64` addition、equality 与 Bool assertion，
  并在 emit 前验证是 Plan 的 exact lowering。每个 relation 输出独立
  `relations/<index-name>/{Nargo.toml,src/main.nr}`；根 interface 精确记录 input role/type/
  visibility、external continuity、`proofStatus=not-produced`。artifact validator 必须拒绝
  symlink、非 regular/unexpected tree、任何 ACIR/witness/proof/VK/verify suffix，并核对
  Accumulator 与其他目标的 source/semantic hash。
- Noir 官方说明 unused integer computation 可能被优化删除并不产生 overflow。当前 source
  profile 必须反向证明每个 checked-add temp 都传递到最终 post-state/result equality；initializer
  或 mutate 中先 checked-add、随后覆盖 store 的 dead arithmetic 必须 fail closed，直到引入并
  由 Nargo 验证不可消除的显式 overflow constraint。不能因为正常 Accumulator 的 add 是 live
  就声称所有顺序 body 都保持 checked-overflow 语义。
- 当前纯 Lean relation model 至少覆盖 Counter/Accumulator lifecycle、错误 initialized flag、
  错误 post-state/result、`7 + 5 = 12`、`UInt64.max + 1` 失败、view state preservation，以及
  PrivateSum4 public/private disclosure 正反例。它只验证 typed constraint recipe，不是 Nargo、
  ACIR、witness generation、proof 或 settlement 证据。
- `TST-NOIR-004/005/006` 在 exact Nargo/noirc/proving-backend/CRS lock、真实 compile、valid/
  invalid witness、prove/verify 和隐私 artifact scan 完成前保持未闭合。当前 manifest 必须是
  `CodegenProfileId=noir-source-u64-relations-v1`、`artifactRole=noir-source-package`、
  `ArtifactDeployability=intermediate-only`，不得生成虚构输入的
  `Prover.toml`，也不得把 `.nr` 成功物化写成 ACIR 或 proof 完成。
- `TST-ZKSEC-001` 必须独立解析并重算 `ZkBackendSecurityProfileV1` 与
  `ZkSecurityApprovalV1`，覆盖 feature allowlist、nonempty soundness assumptions、exact arithmetic/
  CRS/proving backend、proof/VK/public-input envelope binding 和 privacy guarantee。missing/wrong
  content ref、candidate、完整 BuildIdentity、formal finalization、freshness、clock authority 或
  revocation ledger，以及 evidence-ref 非 finalization 成员或
  `finalizedAt <= approvedAt <= currentTrustedTime < expiresAt <= finalization.expiresAt` 失败，均必须在产生
  ACIR/witness/proof/VK 前以 `PF-REQ-EVIDENCE` 零输出失败；
  development approval、intermediate-only source profile 或字符串 badge 不是正例。

## 边界与攻击用例

- 空/多程序、重复名字、Unicode normalization、非法 UTF-8、最大 nesting/node count。
- UInt min/max、checked overflow/underflow、除零、shift ≥ width、Field modulus mismatch。
- 空/最大 bytes/string、Map 缺失键、重复 event/error/entry、init 缺失/重复。
- 循环上界 0/1/max、间接递归、动态 allocation、调用深度和 effect 数超限。
- private control-flow/索引/错误消息泄漏；authority 与 custody 混淆。
- unknown target/profile/network、重复 registry key、extension digest/version mismatch。
- output path `..`、absolute path、symlink、case collision、并发同目录、磁盘写满。
- 外部工具缺失、版本错误、timeout、signal、巨大 stdout、恶意 artifact path。
- `LEAN_PATH`、`PATH`、Lake cache、HOME 和父 Git root 泄漏。
- tree-object archive 的不稳定 mtime、错误 external commit/archive digest、archive 内嵌 commit
  不匹配、运行中 HEAD/tree/worktree 改变。
- EV duplicate/unknown/non-graphic key、float/unsafe integer、set-like array 乱序/重复、非法
  result/attempt 终态、ID/UTC 日期不符、artifact-set digest 不符。
- exact-local-port 缺 `networkPort`、端口为 bool/float/string/null/越界、非 exact policy 携带
  端口、unknown network/字段，以及 passed evidence 中 exact-port probe failed/skipped；同时
  保留无 port 的旧 deny-all/loopback v1 正例。
- evidence publish basename/gate directory 不匹配、existing output、symlink/hardlink、
  group/world-writable parent、staging pathname replacement；bundle claim 跨 role 复用 path、
  casefold/inode alias、单文件/文件数/总字节超限、read 时 inode/size/hash 改变或 I/O error。
- formal record 缺 external anchor/eligible host/deny-default/required inputs、出现 retry、未 retained
  artifact、截断/未扫描日志；revocation ledger 缺链、分叉、未知 authority 或 replacement 不符。
- allow-default/wildcard policy、policy read、stage source/output write、未批准 exec；runtime 相邻
  端口、外部地址、同机 LAN exact-port 暴露、Anvil chain-id/process identity 变化。
- inherited writable FD、interactive stdin、descendant-held pipe、fast leader exit、timeout/
  output-cap cleanup、PGID reuse 与 `setsid()` session escape。
- policy/receipt preexistence、symlink/hardlink/path replacement；failure tail 的 ANSI/OSC/control
  byte 必须 ASCII-escape，但 printable secret 仍需 formal retained/private scan/redaction。
- invocation receipt 的 policy/port/argv/env/terminal/raw-stream digest、receipt-last commit
  marker、rollback/partial-set rejection；catalog content/domain digest、exact-set、split-brain、single-snapshot 与
  development-only finalization negatives。完整矩阵见
  [`SPEC-EVFINAL-001`](specs/gate-catalog-finalization.md)。

## Gate 设计

预期命令名：`v2-source-core`、`v2-counter-four-target`、
`v2-target-extension-rejection`、`v2-artifact-repeatability`、`v2-missing-tool`、
`v2-runtime-primary-triad`、`v2-zk-noir-e2e`、`v2-clean-room`、`v2-check`。
命令未实现前它们是 specified，不得记录为通过。

`v2-clean-room-alpha` 是 pre-acceptance development command，`isolated-check` 是其兼容
别名；二者不占用正式 `v2-clean-room` 命令名，也不关闭 `TST-ISO-002` 或
`TST-ISO-003`。

当前 development alpha 已实际覆盖 deny-default `materialize`/`core`/`evm-runtime` stages、
closed-FD launcher、bounded private receipts、原 process-group cleanup、exact-local-port 与
Anvil `127.0.0.1` bind/LAN refusal；evidence v1 candidate 也已覆盖 exact-port 条件字段、边界、
错误类型与 current-reader 对旧 record 的兼容。H1e-a 还提供 opt-in 的 canonical run/invocation
contexts、policy/port/argv/env/terminal/raw-stream-bound metadata receipt、single-writer reservation
和 receipt-last publication；当前 alpha runner 尚未传入这些 opt-in contexts，也未 retained 新
metadata receipt。`networkPort` 与真实 retained policy/receipts/probes 的 catalog binding、完整
old/new reader fixture matrix、`setsid()` session escape、eligible host、formal Stage-0 handoff、
required-set/catalog authority、task/activation receipt protected service 仍是
`TST-BOOTSTRAP-001` 的 pre-activation 缺口；取得 current activation 后，formal gate
catalog/freshness/revocation/private scan、acceptance/support binding producer 和正式 finalizer 才是
`TST-EVIDENCE-002`/`TST-ISO-002` 的验收缺口。

H1e 固定按 invocation receipt → catalog core → real retained bundle integration 三个切片实施；前
两个切片通过不能追溯升级 H1c/EV-0015，也不能单独关闭
`TST-EVIDENCE-001/002`、`TST-ISO-002/003` 或 `TST-VER-001`。`TST-EVIDENCE-001`
只在 real retained bundle 与 development catalog finalization 也通过、且 formal output 请求已证明
zero-output fail closed 时关闭。

H1e-b 还必须覆盖 catalog `--catalog` absolute/parent traversal 与 input-claim split-brain、三类
structural repeated-role alias/substitution，以及 `gate_evidence.py` digest 不变但 exact sibling
`evidence_v1_core.py`/retained `evidence-schema-core` 被替换的 closure negative；base context 还须
拒绝 `runtime-port`、`adjacent-port`、`lan-ipv4`、`chain-id`、`asset-cache` 五个 late-dynamic 名；
这些失败不得进入 catalog success 或创建 EVF 输出。还必须拒绝 development finalizer 的普通
pathname 启动、stdin descriptor/path/module-code 任一错绑、跨 policy/probe 重用 rendered policy/
context/receipt/stream，以及 probe stream 与 `requiredLogs` 相交；非 regular stdin 与 source-path
substitution 也必须在 catalog/member/output I/O 前失败。Gate command 的 `argv[0]` 必须拒绝
`literal`/binding matcher 绕过 retained launcher input；single-snapshot 64 MiB semantic total 必须
计入复用的 preliminary evidence bytes，并覆盖 claimed semantic subtotal 恰为 64 MiB 的边界负例。

## 证据要求

每次 gate 的目标输出是符合 [`TRACE-EV-001`](traceability/evidence-schema.md) 的不可变 `EV-*`
JSON：candidate commit/tree/git-tar anchor、dirty/unchanged、local host observation、环境、sandbox
policies/probes、工具 closure、全部 attempts、inputs/artifacts、domain-separated artifact-set
digest、normalized observations 和 logs。

验收必须分别覆盖：

1. restricted integer-only/ASCII-graphic-key PF JCS、exact-local-port 条件 port matrix 和所有
   schema/cross-field negative；
2. inputs、retained artifacts、logs 的逐组件 no-follow point-in-time size/hash 复核；
3. `TST-BOOTSTRAP-001` 要求在没有既有 activation 的前提下完成 eligible handoff、session
   containment、signed required-set/catalog authority、per-task receipt、six-item set 与 activation
   producer/consumer；其通过证据先进入 D0-04 TaskApproval/task receipt，不能反向要求本次 activation；
4. `TST-EVIDENCE-002` 要求在 current activation 之后由 formal gate catalog 对 required tests/tools/probes、freshness、
   host/candidate、private scan 和 revocation lookup 的完整 finalization，以及对
   candidate/BuildIdentity/RequirementKey 的 acceptance/support binding 产生与重算；host profile、
   session containment、freshness authority、private scan、revocation snapshot 与 finalizer 必须是
   exact typed ContentRef，覆盖 wrong schema/domain/id/version/digest、missing/extra ref、revocation
   record order/chain/head/length-prefix aggregate、formal-input policy rule/quorum/signature domain、
   privateScan→evidenceCore→final evidenceSet 单向 hash 与 finalizer closure substitution negatives；
5. RequiredTestSet authority negatives：candidate/CLI/env 选择 policy、PHASE-5 content digest 或
   reviewCommit substitution、missing/extra/duplicate/reordered required ID、wrong policy ref、签名
   缺失/伪造/同一 principal 多 key/role 或 threshold 不足、缺/错 FormalGateCatalogApproval、弱/no-op
   gate policy、GateCatalogRef 使用 `contentDigest` alias 或 prefixed digest，以及 catalog/gates/evidence
   omission/duplication/错绑、formal output catalog/required-test-set path segment mismatch；pure parser
   必须从 policy bytes 重算 ref，且其 positive 不得替代 PHASE-5 snapshot/denominator/ancestry join；
   hard-bound 验收必须覆盖 TestId 127/128 bytes、required IDs 4096/4097、approvers 256/257、
   reviewLink 4096/4097 bytes 与 signatures resolved-policy-count equal/over；document join 还须覆盖
   exact typed snapshot、canonical PHASE-5 path、0/4 MiB/4 MiB+1 bytes、BOM/NUL/CR/non-UTF-8/no-final-LF、
   frontmatter delimiter/scalar/field-set/duplicate/unknown/accepted metadata mismatch、raw domain digest、
   heading 0/1/2、bare/SP/HTAB raw-H3、reversed marker、table 0/1/2、
   header/delimiter/row/extra-cell/empty-description、
   duplicate/malformed/range/wildcard ID、frozen A0-001..020 exact exclusion、signed denominator
   missing/extra/reordered 与 malformed document 在 RequiredTestSet signature curve work 前拒绝，验收须
   instrument internal preflight/finalize 顺序而非先调用已验签的 two-byte-input parser 再比较；
   snapshot parser 与 document-bound signed join 必须分别存在可正向到达的验收，positive result 不得替代 archive
   membership、single-snapshot 或 reviewCommit ancestry；
6. bootstrap authority negatives：wrong policy schema、D0-01..06 缺项/乱序/额外项、principal
   间或同一 principal rotation 的 duplicate publicKey、receiptPublicKey alias principal key、按
   principalId 合并其他 key roles 的权限提升、role enum ASCII 误排序、principals 0/257 count，
   duplicate key material 在第二次 subgroup 运算前拒绝；PHASE-4 raw snapshot 还须覆盖 exact type/id/path、
   accepted frontmatter、byte/line resource bounds、normative domain、D0/D1 reserved-line decoy/duplicate/
   order、exact seven-column table 与 D0-01..07 rows、description/status、`—`/`, ` cell grammar、source ID
   order/duplicate、dependency table-membership/DAG、D0-07 non-bootstrap projection，以及 raw-derived
   closure/subject/full approval/prerequisite raw-document same-cardinality joins；全部 raw mismatch 在 report
   intrinsic 之后、RequiredSet/TaskApproval curve 前拒绝且 curve count 为零。Task Breakdown row/test/dependency/
   prerequisite substitution、missing/wrong/unsigned task RequiredTestSet、owned TST 非 required member、
   EV/review/candidate/handoff mismatch、同一 principal 多 key 满足伪 quorum、历史 candidate 或
   wrong-policy/required-set dependency completion、missing/wrong task receipt、aggregate 作为前五项 done 前置、D0-04 在自身
   task receipt 前 activation、旧 run approval/receipt/replayed set、wrong receipt key/verifier digest、
   caller-selected receipt service、read-only file/directory 假冒 service、descriptor/policy/handoff
   mismatch、policy↔descriptor 或 mutable-root-manifest self-binding、bad frame/requestId/runId/nonce/
   lease/head sequence、unsigned/wrong-key hello/ack、schema publish allowlist 绕过、quorum-signed set
   无 publication path、publish conflict、missing/exact-head readback、revoked/non-unique tuple lookup、
   仅 ledger `passed` 或 synthetic
   bootstrap without protected verifier receipt；TaskApproval signed-content matrix 还须覆盖四输入 API、
   六个 schema-specific array equal/over bound、Evidence/BTV real date、各排序键/duplicate、wrong task rule、
   required-set/policy/test membership、stage0 schema、review key/role/commit/link/report/decision、review
   principal/report uniqueness、review↔signature distinct-principal exact set、review role authorization 与
   signature rule threshold/roles、rotation key positive、statement/content domain golden、全部结构失败在
   approval signature curve 前拒绝，以及
   positive 不得替代 PHASE-4/EV/dependency/review-report/handoff/provenance join。Task receipt
   signed-content matrix 还须覆盖六输入 API、receipt/handoff exact frozen typed records、receipt 与 handoff
   closed fields、BTV real date、dependency `0/5/6` bounds 与排序/duplicate、candidate/policy/required-set/
   approval/handoff/dependency/verifier/result exact joins、handoff 四 channel order/fd/transport/access/binding、
   policy+handoff verifier double pin、wrong receipt key/algorithm/signature、statement/content domain golden、
   malformed receipt/handoff 与 `taskApproval.taskId` 等 pre-digest join failure 的 zero approval-curve、
   RequiredSet→TaskApproval→receipt signature→receipt digest 顺序，wrong approval digest 在 approval finalize
   后且 receipt curve 前拒绝，以及 positive 不得替代 fd/host/peer/publish-readback/revocation/PHASE-4/EV/
   dependency/review/archive closure。

前两层不能代替后四层。当前 formal publisher 和 bootstrap closure 继续 fail closed；development schema/bundle/
catalog 结果不能关闭 `TST-BOOTSTRAP-001`、`TST-EVIDENCE-002` 或 `TST-ISO-002`。外部工具缺失必须让相应 required gate 失败，不能 skip 后仍
标绿。development flaky retry 必须记录全部 attempts；formal passed 只允许一次 attempt。
撤销/修正必须追加独立 revocation record 并保留原 EV；该 revocation parser/store 尚未实现。

## Release Acceptance

Phase 1 release 要求本表所有 required TST 有最新 EV；四目标 aggregate、security、
repeatability、clean-room 全绿；无 P0/P1 review finding；所有文档 trace 关闭。
