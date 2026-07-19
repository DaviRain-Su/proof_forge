---
id: PHASE-5
title: 测试与验收规格
status: accepted
owner: quality
updated: 2026-07-19
normative: true
approvers: architecture-owner, davirain, quality-owner
approvedAt: 2026-07-19
reviewCommit: cda99d931ab02f063302cfa82861871bddee93e8
reviewLink: https://github.com/DaviRain-Su/proof_forge/commit/cda99d931ab02f063302cfa82861871bddee93e8
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
