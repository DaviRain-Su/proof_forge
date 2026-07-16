---
id: PHASE-5
title: 测试与验收规格
status: proposed
owner: quality
updated: 2026-07-16
normative: true
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
四目标观测统一为 normalized `(status, return, logicalState, effects, error)`。

### PrivateSum4

四个 private `Field` 输入求和，public expected sum；Noir prove/verify 成功，错误 sum 验证
失败。private 值不得出现在 manifest、public ABI、日志、诊断或 verifier-visible witness。
EVM/Solana/NEAR 因不能保持 private witness 语义，在 Plan 前以 `PF-REQ-UNSUPPORTED`
拒绝。

## Acceptance Matrix

| ID | 场景 | 预期 | 证据级别 |
|---|---|---|---|
| TST-SRC-002 | per-program Syntax 256/257 nesting、100000/100001 nodes、qualified identity 与 CLI 16 MiB | 精确边界；Syntax/identity 超限 `PF-BOUND-001`，CLI byte 超限 `PF-SRC-INVALID` | unit/integration/security |
| TST-SRC-003 | `program Counter where` 与非法顶层形式 | 正例导出；非法稳定诊断 | unit |
| TST-SRC-006 | attribute export 跨模块/import 顺序 | identity 稳定，无重复 | integration |
| TST-TYPE-001 | widths、map、struct、enum | 类型成功/精确失败 | property |
| TST-TYPE-002 | accepted-width duplicate/name index、late lookup 与错误顺序 | 声明序 ID/遮蔽/诊断不变；required hash ops、single state-builder 与已知数组搜索回归受门禁 | unit/structural/complexity |
| TST-EFFECT-001 | view 写状态/发 effect | `PF-EFFECT-001` | negative |
| TST-BOUND-001 | 无界循环/递归 | `PF-BOUND-001` | negative |
| TST-VIS-001 | private 流入 public/log | `PF-VIS-001` | security |
| TST-SEM-002 | Counter reference trace | 精确 normalized trace | model |
| TST-SEM-003 | overflow/revert | unchangedState | model |
| TST-REQ-001 | requirement inference | 稳定集合、origin/span | property |
| TST-REQ-003 | support exact version/digest | mismatch fail closed | negative |
| TST-REG-002 | duplicate/unknown target | stable registry errors | unit |
| TST-MAT-001 | associated Plan/IR | 不可擦除、invariants enforced | compile/unit |
| TST-OUT-001 | manifest/hash/partial failure | 原子输出或无变化 | integration |
| TST-EVM-005 | Counter on Anvil | reference trace 相同 | local_runtime |
| TST-SOL-005 | Counter on Solana local runtime | reference trace 相同 | local_runtime |
| TST-NEAR-005 | Counter on sandbox | reference trace 相同 | local_runtime |
| TST-NOIR-005 | Counter witness/proof | prove+verify，state continuity explicit | proof |
| TST-NOIR-006 | PrivateSum4 | 隐私检查 + prove/verify | proof/security |
| TST-XTARGET-001 | 一份 Counter 四 target | 四 OutputSet 均合法 | aggregate |
| TST-XTARGET-002 | unsupported/version/missing tool | 稳定错误，无 fallback | aggregate |
| TST-HOST-001 | Stage-0 host attestation | development observation；formal fail closed | security/isolation |
| TST-ISO-002 | 正式 hermetic archive harness | 外部 candidate anchor、eligible host、deny-default stages、process containment、gate-catalog EV 全部通过 | isolation |
| TST-ISO-003 | release-candidate clean-room aggregate | 所有 required Phase 1 gates 完整通过 | release/isolation |

## 完整 Test ID Catalog

以下 ID 均为 specified；表中“测试对象”是必须实现的最小断言，不表示已有 gate。

| IDs | 测试对象 |
|---|---|
| TST-DOC-001 | frontmatter、状态、ID、链接、claim/ADR/trace 闭合 |
| TST-HOST-001 | 权威 `env -i` 入口、严格 bootstrap/JSON、live OS/Xcode/tool 匹配、development observation、formal ineligible 与环境/lock mutation negatives |
| TST-ISO-001 | 独立 Lake/package/namespace 与父依赖边界 |
| TST-ISO-002 | Stage-0 eligible host、外部 commit/tree/archive anchor、稳定 committed archive、前后 unchanged、空环境/cache；materialize/core deny-all-network；runtime exact-local-port + Anvil 127 bind/LAN refusal；stage read/write/exec negatives、closed FD/stdin EOF/output cap/timeout、formal session containment、0400 single-link receipts 与 gate-catalog-bound evidence |
| TST-ISO-003 | D8 release-candidate 全量 clean-room aggregate |
| TST-TOOL-001 | exact tool version/checksum、missing/shadow/timeout |
| TST-SRC-001/002 | token/span/NodeId canonicalization；CLI byte cap 与 post-parser per-program Syntax/identity limits |
| TST-SRC-003/004/005 | program command、declarations、statements/expressions 正负例 |
| TST-SRC-006/007/008 | attribute export、import/identity、multi-program selection |
| TST-DIAG-001 | diagnostic code/schema/order/redaction |
| TST-TYPE-001/002 | 类型 happy/boundary/error 与 name resolution |
| TST-EFFECT-001, TST-BOUND-001 | effect restrictions 与 termination/resource bounds |
| TST-VIS-001/002 | explicit/implicit disclosure flow 与 authority/custody separation |
| TST-SEM-001/002/003 | serialization、reference trace、revert/overflow rollback |
| TST-REQ-001/002/003 | inference/origin、merge/conflict、support exact match/rejection |
| TST-REG-001/002 | ID/profile parsing、registry duplicate/lookup/design-only rejection |
| TST-MAT-001 | associated Plan/IR、stage order、invariant mutation tests |
| TST-OUT-001/002 | manifest/atomicity 与 repeatability/tamper |
| TST-CLI-001/002/003/004 | parse/help、check/build、inspect/list、prove/verify/deploy guard |
| TST-EVM-001..005 | Plan、materialize、Yul/ABI、bytecode validation、runtime differential |
| TST-SOL-001..005 | Plan、materialize、sBPF/IDL、ELF validation、runtime differential |
| TST-NEAR-001..005 | Plan、materialize、Wasm recipe、Wasm validation、sandbox differential |
| TST-NOIR-001..006 | Plan、materialize、source/ABI、ACIR/prove/verify、Counter、PrivateSum4 |
| TST-XTARGET-001/002 | 四目标 aggregate 与 unsupported/version/tool matrix |
| TST-SEC-001 | path/env/process/supply-chain/privacy attack matrix |
| TST-VER-001 | schema/profile compatibility matrix |
| TST-PERF-001 | cold/incremental/resource benchmark budgets |
| TST-BOUNDARY-001 | Lean import graph、symbol ownership、target cross-import |
| TST-EVIDENCE-001 | restricted PF JCS/schema、exact-local-port 条件 port、artifact-set domain hash、safe bundle read、atomic layout、gate catalog、revocation/freshness/private scan |
| TST-REL-001 | install/upgrade/build/rollback drill |

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
- `just dsl-negative`：同一组生成的 namespace/deep/wide `.lean` 分别通过
  `lake env lean` command elaborator 和 `proof-forge-next build` CLI loader；两路超限都必须
  返回相同 `PF-BOUND-001` 文本，恰好 256-component identity 与 transient unwind 两路都通过。
  CLI-only 有效源码恰好 16 MiB 必须成功；16 MiB+1 必须在 parser 前以 `PF-SRC-INVALID`
  拒绝且不创建 output。
- 本切片不关闭 Lean parser fuzz/containment、module aggregate node policy、完整
  Diagnostic v1/NodeId/span、直接 `Source.Program` API bounds 或 `TST-BOUND-001`；后者仍专指
  D2-03 的循环/递归 termination checker。accepted-width `Source.Program` 后续进入
  `Typed.check` 时仍有数组式 duplicate/name lookup；其线性索引化由 `TASK-A0-18` 跟踪。

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
  必须保持 `deployable=false`；不得把 plan assembly 写成 ELF 或 runtime completion。

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
  `source-only`、`deployable=false`，不得生成虚构输入的 `Prover.toml`，也不得把 `.nr` 成功
  物化写成 ACIR 或 proof 完成。

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
gate catalog/freshness/revocation/private scan 和正式 finalizer 仍是验收缺口。

H1e 固定按 invocation receipt → catalog core → real retained bundle integration 三个切片实施；前
两个切片通过不能追溯升级 H1c/EV-0015，也不能关闭 `TST-EVIDENCE-001`、`TST-ISO-002/003`
或 `TST-VER-001`。

## 证据要求

每次 gate 的目标输出是符合 [`TRACE-EV-001`](traceability/evidence-schema.md) 的不可变 `EV-*`
JSON：candidate commit/tree/git-tar anchor、dirty/unchanged、local host observation、环境、sandbox
policies/probes、工具 closure、全部 attempts、inputs/artifacts、domain-separated artifact-set
digest、normalized observations 和 logs。

验收必须分别覆盖：

1. restricted integer-only/ASCII-graphic-key PF JCS、exact-local-port 条件 port matrix 和所有
   schema/cross-field negative；
2. inputs、retained artifacts、logs 的逐组件 no-follow point-in-time size/hash 复核；
3. formal gate catalog 对 required tests/tools/probes、freshness、host/candidate、private scan 和
   revocation lookup 的完整 finalization。

前两层不能代替第三层。当前 formal publisher 继续 fail closed；development schema/bundle
结果不能关闭 `TST-EVIDENCE-001`。外部工具缺失必须让相应 required gate 失败，不能 skip 后仍
标绿。development flaky retry 必须记录全部 attempts；formal passed 只允许一次 attempt。
撤销/修正必须追加独立 revocation record 并保留原 EV；该 revocation parser/store 尚未实现。

## Release Acceptance

Phase 1 release 要求本表所有 required TST 有最新 EV；四目标 aggregate、security、
repeatability、clean-room 全绿；无 P0/P1 review finding；所有文档 trace 关闭。
