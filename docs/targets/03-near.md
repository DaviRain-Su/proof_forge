---
id: TARGET-NEAR
title: NEAR target dossier
status: proposed
owner: architecture
updated: 2026-08-12
normative: true
---

# Target Dossier：NEAR

状态：`proposed`
Target ID：`near`
Phase 1：实现

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 读取 retained `SemanticProgramV1`，structure-gate 后 private lowering；
无 alpha residual Plan route。保留 KV / raw ABI / receipt-local policy。

**工程已接线（摘）**：

- Normalize 当前子集：算术/比较/assert、控制流、fn、let/for、shift/bitwise、revert/emit 等；
- state/param **UInt8/16/32/64 与窄 Int** ABI/body 子集；**UInt128/256 软件多字（T9e）**：
  add/sub/mul、**div/mod restoring binary long division**，以及 **multiword << / >>**
  （count≥bitWidth trap；checked-shl 高 limb overflow trap；`Examples/WideShiftProbe` +
  deterministic HostModel + near-sandbox suite，与 CosmWasm 同形）；
  schedule → 原生 promise；sync call 在 capability 矩阵上 fail-closed；
- **Array + dense Map UInt64 cap-8 + fixed Bytes N + named Struct/Enum + Option UInt64 state**
  flatten-to-KV；聚合 `StateStore` 使用 `storeAtomic` 两阶段 IR（先求值全部叶、再写 KV），HostModel
  已固定 empty Map upsert、连续 Map StateStore、PointBox/EnumBox，以及 Option tag/payload 的
  none/some/reset（reset 清零 stale payload）；Option params、非 UInt64 payload与 nested Option 仍 FC；
- **聚合返回**：named Struct/Enum 与 anonymous Array/Option UInt64 保持 ≤8 叶，经单次
  `value_return` 发 N×8-byte LE；dense Map UInt64 UInt64 使用固定 24 叶特例，Bytes 见下；
  nested/非 UInt64 元素返回仍 fail-closed；
- **Principal 9×KV leaf 存储（T12）**（wire identity 原样；**非** account-id）；
- WAT 发射 + locked `wat2wasm` 结构编译；`NearWasmAcceptance` 另需 host-optional
  `wasm-interp`/`wasmtime`/`wasmer` 之一做 runtime load；locked near-sandbox 2.13.0 的
  `runtime-tests/near` 已覆盖 StateCell init/mutate/view、overflow state-hold+recovery、
  `negative_corpus`（unknown method / empty·short·long increment args + state-hold + recovery）、PairRet、
  ArrayRet、OptionRet、OptionState、proof-bearing `VerifiedVaultPF`、TipJarAsync、TokenJarAsync、
  EnvReadJar、**EnvReadBalanceU128**（`pf.assets@1.2.0` full-width u128 ↔ RPC amount）、
  CallerCheck、低集成 `PoseTransform`（translate/rotate90/scale + Int64 overflow
  state-hold）、`BlockHeightCheck`（`context.blockHeight` ↔ sandbox
  `status.sync_info.latest_block_height`）、`ConstAnswer`（scalar `const` 表 / `Op.Constant`）
  与 `UnixTimeCheck`（`context.unixTimeSeconds` ↔ `block_timestamp` ns÷10^9）、
  `BytesRet`（anonymous `Bytes 4` → 4×u8 tight `value_return`）。
  2026-08-11 required run 以 userspace GLIBC 2.39 loader 在 GLIBC 2.36 host 启动原始 locked
  executable，原十套 corpus 全部 PASS；后续扩为十五套+ engineering 门（含
  `negative_corpus`）。**GLIBC 兼容启动（engineering）**：
  `scripts/lib/near_sandbox_launch.sh` 统一 direct → Tool Root
  `near-sandbox-glibc/` pack → env `PF_NEAR_SANDBOX_*`；pack 由
  `scripts/near_sandbox_glibc_materialize.sh` 从 Ubuntu noble libc6 抽出，recipe 见
  `supply-chain/near-sandbox-glibc-linux-x86_64.v1.json`。**不**替换 Tool Lock
  near-sandbox 字节；digests 尚未 lock-pin，**仍不是** hermetic release evidence。
  产品推进见 `docs/plan/near-parity-roadmap.md`。
- **Scalar constants table**：source `const` / body `Op.Constant` 对
  UInt{8,16,32,64} / Int{8,16,32,64} / Bool 开放，预解码进 `StorageLayout` 后按 inline
  plan literal 发射；UInt128/256、aggregate、Principal const 仍 FC。空表保持 historical
  Plan bytes。
- **Bytes N (1..8) entry/view return**：B-RET-ABI 扩 admit；`value_return` 紧凑 N×u8 打包
  （与 Array/Option 的 N×8 LE 路径分流）。dense Map return 已 open：cap-8 →
  24×u64 LE `value_return`（occ/key/val 扁平；与 CosmWasm B-RET-MAP 同形）。
- **`pf deploy -t near`**：save-only `proof-forge.pf.near-deploy-package.v1` 包
  （wasm sha + near-abi 指针）；`--broadcast` 在 v0 一律拒绝（含 local）。
- **`pf run -t near -- <method> [u64…]`**：one-shot locked near-sandbox call/view
  （`scripts/pf_near_run.sh`）。export mode 优先读 `*.near-abi.json`（含
  `nativeBalanceU128` 等非 `get*` view）；缺 ABI 时回退名字启发式。engineering only，
  非 testnet/mainnet；Promise / sync transfer 仍在编译器 fail closed。
- **Proof-bearing invariant-root erasure（ADR-0042）**：普通 capability + nonempty invariants
  仍 fail closed；只有 private audited `CertifiedInlineProofV1` 在 source/semantic digest exact
  match、每个 invariant 有完整 preserving coverage 时可 mint NEAR-only authorization。
  version `proof-forge.near.invariant-root-erasure.v1` 的 Plan attestation 绑定 proof digest 与
  exact callable partition；只擦除 invariant roots，initializer/entry/view/pureFn 与原 callable id
  保留。`VerifiedVaultPF` 的真实 ABI/Wasm build 只导出 init/deposit/withdraw/status；sandbox
  suite 已直接观察 reserves/shares 两个 KV slots 相等、Unit withdraw、overflow/guard failure
  rollback 与 erased `solvent` 的 `MethodNotFound`。当前可声明
  **Reference-verified + NEAR engineering runtime observed**，但这不是 formal target refinement。
- **VerifiedVault `status` production static alignment（Phase 7 第二/第三静态切）**：
  `StaticAlignmentV1` 新增 passive storage/call observation carrier，以及 public UInt64 semantic
  state ↔ initialized marker/physical KV/8-byte LE value、nullary empty-input ABI、successful
  returned observation与 failure/no-commit observation 的 proposition-only relation；独立 candidate
  `stateLoad; return` shape 仍负责 relation 的正反例。新增 `KeyRegionsV1` 与
  `PlanIRLoweringV1` 作为既有 private canonical-key constructor / validated `lower` 的 exact
  successful graph，并从 full-plan graph 导出 source Plan、canonical keys、method array 与
  entry-index MethodIR provenance；没有第二个 constructor/lowering。
  真实 same-file VerifiedVault certification fixture 现在继续经过 certified capability → production
  materialized Plan → `irFromCapability`，固定 `status` 为 Plan entry 2 / IR method 3，并以 graph
  theorem携带 concrete `MethodIRLoweringV1` evidence。public proof-producing syntax recognizer
  现在把动态 production `Method` 与 `MethodIR` 分别恢复成 exact nullary UInt64 view 和
  `checkInputLen; requireLayout; loadState; setReturnData` 四操作 recipe；validated semantic-data
  等式、UInt64 state/storage binding 与 canonical key lookups 一并组成 kernel-checked
  `ProductionNullaryUInt64ViewStaticAlignmentV1`。这证明的是该 production output 的静态形状，
  不是一般 private lowering characterization。该切片仍不执行 `Operation`，也未证明
  IR/Wasm/NEAR execution 或 simulation，因而只是 static alignment/refinement foundation，
  不改变 assurance 声明。
- **VerifiedVault `status` exact Reference outcome（Phase 7 第四切）**：
  sole `stepReferenceSliceV1` 现有任意长度 ready overlay 的 exact theorem；空 external responses
  时，nullary UInt64 `stateLoad; return` 必然返回被加载的 canonical slot、ordered effects 为空且
  完整 logical state 不变。两字段 VerifiedVault fixture 已把该真实 Reference step 与 initialized
  marker/KV relation、nullary empty-input ABI、既有 passive successful observation relation及静态
  Method/MethodIR recipe 合并检查。这里的 observation 仍由外部边界提供；没有定义 target
  transition，也没有从 observation 推出 NEAR runtime、Wasm 或 `Operation` 执行正确性，因此
  仍不是 execution refinement，assurance 不变。
- **VerifiedVault `status` production ready-gate composition（Phase 7 第五切）**：
  `emptyInvocationContextAcceptedV1` 只投影 sole private production context validator 是否接受
  supplied empty snapshot；对应 bridge 恢复 exact `some #[]`，nullary-view constructor theorem
  再组合原 `gateInvocation` 的 callable lookup、arity、initial state、initialized conformance 与
  logical-state decode。真实 generated VerifiedVault subject 因此已闭合 validation、Reference
  admission、admitted data identity、两槽 initialized decode、status row lookup 与 exact ready
  gate，调用方不再提供整个 ready equality；
- **VerifiedVault `status` direct-free context closure（Phase 7 第六切）**：
  public total certificate `directInvocationContextFreeV1` 只判定单个 callable 是否不含
  `ContextRead` / `PureCall`。sole production collector 先以 callable id lookup validated data 中的
  authoritative row；该 row direct-free 才走 empty fast path，否则仍执行原 private bounded
  transitive traversal。它不是第二套 closure checker，也不验证 supplied context/CFG/identity；
  lookup failure、malformed ContextRead、invalid PureCall 等仍由原路径 fail closed。mismatched-root
  regression 固定 supplied forged body 不能欺骗 fast path。真实 `status` row 只有 `StateLoad`，
  因而 lookup + certificate 已在 kernel 中推出 empty-context acceptance，ready 与 exact Reference
  outcome composition 不再带调用方 context premise。该切片仍不定义 target transition，也不改变
  **Reference-verified + NEAR engineering runtime observed ≠ formally target-refined** 边界。
- **VerifiedVault production IR emission provenance（Phase 7 第七切）**：
  `IREmissionV1` 是 sole private `emitFromIR` 的 proposition-only exact successful graph；它不公开
  或复制 WAT/ABI renderer，也不建立另一套 emitter authority。capability build recovery theorem
  把一次 success 还原为同一 capability-derived Plan、既有 private validated Plan→IR graph、同一
  IR 与 exact in-memory `OutputFile` array。由 graph 派生的 envelope 固定按顺序输出
  `<name>.wat`（`application/wasm-text`）和 `<name>.near-abi.json`（`application/json`）；exact graph
  还绑定 private renderer 实际生成的 content strings。真实 VerifiedVault same-file fixture 沿同一
  capability/Plan/IR/build result 把 status MethodIR provenance 接到该 base output，并以安全
  optional lookup 固定 missing、reordered、duplicate、extra file 与 forged media type 均不能满足
  emission graph。这里仍未证明 renderer correctness、WAT/Wasm semantics、locked `wat2wasm`、
  finalized Wasm bytes、磁盘写入或 NEAR execution refinement，故 assurance 声明不变。
- **`status` successful observation 的 Reference-side discharge（Phase 7 第八切）**：
  generic `uint64ReturnedObservationRelV1_of_readyViewLoad` 从 sole production ready gate 恢复
  production logical-state decode，并由 exact state/type/overlay row 推出返回 bytes canonical、宽度
  恰为 8，以及唯一 Reference step 的 pre-state 不变、同值返回、ordered effects 为空。调用方不再
  提供 `hstep`、canonicality 或 size；真实 VerifiedVault fixture 直接使用该 theorem，错误 target
  return bytes 被 relation 拒绝。target success、return、logs、promises 与 pre/post storage equality
  仍是外部 passive observation premises，不能由 MethodIR、WAT 或 emission graph 推出；本切片没有
  新增 target transition/evaluator/step，故仍不构成 NEAR execution refinement。
- **`status` method-scoped production WAT provenance（Phase 7 第九切）**：
  `MethodWATEmissionV1` 把 exact `ir.methods[index]?` lookup、sole private `renderMethod` 产生的
  method text、按 `take/drop` 得到的 index-specific ordered methods block、sole private
  `renderWat` 的 complete text，以及该完整 methods block 在 exact WAT 中的嵌入组成一个命题。
  因此它不是从任意全局 substring 猜 method 归属；duplicate method text 也仍由 method array 的
  exact index split 区分。`irEmissionV1_methodWATEmissionV1` 只从 successful `IREmissionV1`、
  `files[0]?` 和 method lookup 恢复该命题。真实 VerifiedVault capability/build fixture 已将 method 3
  的 statusIR 接到同一次 production WAT file，并证明 appended forged suffix 对任何 method-text
  witness 都不能满足关系。`renderWat` 与证明共同使用同一 private pre-method framing helper，
  没有复制 renderer 或新增 emitter。该命题只证明 text provenance；不证明 WAT parse/typecheck、
  renderer implements IR、Wasm/NEAR execution 或 target refinement，assurance 不变。
- **`status` method-scoped production ABI provenance（Phase 7 第十切）**：
  `MethodABIEmissionV1` 把 initializer+entries 的 exact combined Plan-method index、sole private
  `renderMethodJson` 生成的 method fragment、按 `take/drop` 得到的 ordered rendered-method list、
  sole private `renderAbi` 的 complete JSON text，以及完整 exports text 在 exact ABI 中的嵌入组成
  一个命题。`irEmissionV1_methodABIEmissionV1` 只从 successful `IREmissionV1`、`files[1]?` 与
  method lookup恢复该关系。真实 VerifiedVault fixture 将 entry 2 / combined index 3 的 status
  Method 接到同一次 production ABI file；appended forged JSON suffix 对任意 method-text witness
  均不能满足关系。production renderer 与证明共享 private pre-exports framing helper，没有复制
  ABI renderer。该命题不证明 JSON parsing/consumer behavior、WAT↔ABI consistency、Wasm/NEAR
  execution 或 target refinement，assurance 不变。
- **`status` entry-scoped cross-base-output provenance（Phase 7 第十一切）**：
  `EntryBaseEmissionV1` 把 exact source Plan entry、既有 private lowering graph 的 MethodIR、
  `entryIndex + 1` combined index、同一次 `IREmissionV1` 的 exact WAT/ABI file lookup，以及该
  index 上的 `MethodWATEmissionV1` / `MethodABIEmissionV1` 组成一个 carrier；initializer 仍占
  combined index 0。`irEmissionV1_entryBaseEmissionV1` 仅组合现有 production graph，并由
  `MethodIRLoweringV1` 证明方法名保持，不解析或复制 WAT/ABI renderer。真实 VerifiedVault
  fixture 已把 source entry 2 / combined index 3 的 `status` 连接到同一次 in-memory production
  emission；若给 ABI content 追加 forged suffix 并替换 base-file array，则 combined witness
  fail closed。该关系只证明同源 provenance，不证明 WAT↔ABI parser、consumer 或 semantic
  consistency，不证明 Wasm/NEAR execution refinement，assurance 不变。
- **`status` capability-scoped static emission chain（Phase 7 第十二切）**：
  `CapabilityEntryStaticEmissionV1` 把 capability 中 exact retained `SemanticProgramV1`、validated
  semantic data、同一个 public Plan/IR/build success、既有
  `ProductionNullaryUInt64ViewStaticAlignmentV1` 与 source-entry scoped
  `EntryBaseEmissionV1` 收束为一个 proposition-only carrier。因此 kernel 中已有单链
  `validated SemanticProgram → capability-gated production Plan/IR → status static alignment →
  exact same-emission WAT + ABI`。constructor theorem 仅组合 sole production graph，不引入第二套
  Plan constructor、lowering、renderer、emitter、State、Effect、transition、evaluator 或 step。
  真实 VerifiedVault fixture 已为 source entry 2 的 `status` 构造该 carrier；只修改 ABI base
  output并替换 files array 时，对任意 WAT/ABI method-text witness 都 fail closed。该 carrier 仍不
  证明 renderer correctness、WAT/JSON parsing/typechecking、WAT↔ABI consumer semantic consistency、
  locked `wat2wasm`、finalized Wasm identity、Wasm/NEAR execution 或 Reference simulation；
  assurance 仍为
  **Reference-verified + NEAR engineering runtime observed ≠ formally target-refined**。
- **`status` strict sandbox observation adapter（Phase 7 第十三切）**：
  runtime harness 新增与 Lean `CallObservationV1` 同字段的有限工程 carrier，并由
  `NearClient.observe_view` 对真实 `call_function` query 抓取 exact export/input/raw return、logs及
  query 前后完整 KV snapshot。view 边界拒绝任何 receipt-shaped response 字段并固定 promises 为空；
  VerifiedVault 每次 `status` 检查都要求 success、exact 8-byte LE expected value、empty
  logs/promises 与 pre/post storage byte-for-byte 相同。no-tool self-test逐项 mutation错误 response
  编码、返回宽度/值、failure、log、promise、receipt 与 storage；Lean relation同步固定
  failure/log/promise negatives。这里没有 RPC→Lean proof import、target transition、Wasm evaluator 或
  simulation theorem；adapter 只是把此前的外部 premise变成结构化工程回归，assurance 不变。
- **`status` bounded MethodIR execution refinement（Phase 7 第十四切）**：
  `MethodSemanticsV1` 新增第一套 formal target recipe machine，只解释 production status 的
  `checkInputLen` / `requireLayout` / `loadState` / `setReturnData` 四操作；input/storage不可变，
  locals有 exact `tempCount` bound，所有其他 Operation fail closed。exact recipe theorem使用 shared
  UInt64 LE codec law证明 initialized marker/KV snapshot 必然返回原 8-byte field；static-alignment
  theorem把该执行接到既有 semantic/storage relation，Reference composition theorem则从 sole
  `stepReferenceSliceV1` ready view与 target execution导出的 observation共同推出 returned relation，
  不再要求调用方提供 target success/return/log/promise/storage premises。
  `capabilityEntryStaticEmissionV1_executeReadOnlyMethodV1` 进一步把 execution接回 exact production
  capability/Plan/IR/build/emission carrier。真实 VerifiedVault fixture固定 exact return observation、
  wrong-input trap、store unsupported 与 Reference→MethodIR relation。该 machine解释 target IR，
  不重建 DSL callable/arithmetic/effect规则，因而不是第二套业务 semantics；本切只称
  **MethodIR-refined**，不证明 renderer/WAT/Wasm/NEAR。
- **`status` bounded typed-WAT refinement（Phase 7 第十五切）**：
  `ReadOnlyWATV1` 定义 status recipe所需的 typed i64 expression/host-call/instruction 子集及其
  sole text renderer；production `renderOperation` 对 exact `checkInputLen 0`、`requireLayout`、
  UInt64 `loadState`、8-byte `setReturnData` 直接消费该 typed syntax，完整命中该子集的方法则由
  `renderReadOnlyWATMethodV1` 生成。unsupported Operation仍走原 production renderer，不存在第二份
  等价 string renderer。`ReadOnlyMethodWATEmissionV1` 把 typed lowering、exact method text与已有
  complete production WAT graph绑定；真实 VerifiedVault production method index 3 已实例化该关系。
  `WATSemanticsV1` 为这个有限子集定义 fail-closed machine，并证明 initialized marker/KV 下 exact
  typed sequence返回原 UInt64 bytes、与 MethodIR返回一致，以及 sole Reference ready/step到
  typed-WAT-derived observation 的 returned relation。fixture固定 exact lowering/execution/observation、
  non-empty input trap、missing field/register trap、forged MethodIR suffix lowering拒绝。该语义把 scratch memory建模为
  recipe触及 offset 上的 exact byte block，`storageRead` 的 `KeyRegion` 是 production data-segment
  proof annotation。`ReadOnlyWATV1` 另有 **bounded typed-WAT static validator**：它在该 syntax
  边界 fail closed 检查 i64 constant范围、local index、完整 `KeyRegion` 对 production key table 的
  exact binding、scratch memory access及 8-byte return width；production capability chain theorem与
  真实 VerifiedVault `status` certifier fixture均证明 exact typed sequence通过该 validator，越界
  local/constant/memory、unbound region与错误 return width均有负例。它仍未建模 arbitrary
  overlapping linear memory或完整 host ABI。因此本切只能称
  **bounded typed-WAT-refined slice**，不能称 textual WAT、Wasm binary或 NEAR artifact 已 refinement。
- **`status` generated method-fragment text identity（Phase 7 第十六切）**：
  `ValidatedReadOnlyMethodWATEmissionV1` 将 bounded typed-WAT lowering、static validator `.ok ()`、
  sole production method renderer与既有 complete WAT emission graph收束在同一个 proposition；
  direct identity theorem进一步给出完整 production WAT 的 byte-for-byte 分解，其中选中片段恰为
  `renderReadOnlyWATMethodV1 name tempCount instructions`。public capability façade从同一
  VerifiedVault `status` static-alignment/emission chain构造该 witness，真实 certifier fixture固定
  combined method index 3 的完整 WAT确实包含该 exact validated typed fragment。这里没有通过
  substring搜索猜测归属，index ownership仍来自 ordered method graph；但它也**不是 parser**，不
  覆盖 surrounding imports/memory/data/fn/module framing，更不验证任意 textual WAT。因此只能称
  generated method-fragment exact-render identity，不能称完整 textual WAT module 已 target-refined。
- **generated complete-module framing identity（Phase 7 第十七切）**：
  `WATModuleEmissionV1` 直接复用 sole private production renderer 的 exact decomposition：module
  opener之后依次为 typed IR拥有的 imports、memory declaration、key/promise data segments、pureFns、
  ordered methods和唯一 closing delimiter。`ValidatedReadOnlyWATModuleEmissionV1` 又将这个 complete
  generated-text graph、production `validateIR = .ok ()` 与选中 `status` 的 validated bounded
  typed-WAT emission收束为一个 proposition；public capability façade和真实 VerifiedVault certifier
  fixture均构造该 witness，追加 forged module suffix会因 complete-text uniqueness被拒绝。该关系
  证明的是**由唯一 renderer 生成的完整 module framing identity**，不是任意 WAT parser/general
  validator；它也没有给 surrounding pureFn/其他 method body通用 typed-WAT semantics。因此完整
  textual WAT module仍不能称 target-refined。
- **ContextRead（B-CTX-OPEN）**：`context.unixTimeSeconds` → host `block_timestamp()`(ns) ÷10^9
  截断（Plan Expr tag 41）；`context.blockHeight`（ADR-0031 S2）→ view-safe host
  `block_index()` 直接返回 u64 高度（Plan Expr tag 45，无单位转换）；`context.caller`
  （ADR-0031 S1，2026-08-06）→ host `predecessor_account_id`，仅 init/entry 开放，
  按 exact account-id UTF-8 bytes 物化 `u32le(len)||body` Principal（len 2..64、
  lowercase account-id grammar）；view/pureFn/invariant caller 保持 FC。predecessor register id
  由 `RegisterLayout.predecessor` sole-own，emitter 不再局部硬编码；未知键 FC。
  blockHeight 有 Plan/IR/emitter + NearHostModel 钉测，且 `Examples/BlockHeightCheck.lean`
  已进 `scripts/near_runtime_test.sh` suite `blockheightcheck`（view `height()` 钉
  `latest_block_height`，entry `stamp()` 钉 receipt 高度区间）。
- **`pf.assets` 半绑定（ADR-0029 Phase C2，2026-08-05）**：resolver advertise exact
  `extension.pf-assets` + `effect.synchronous-call`（后者仅覆盖 pf.assets catalog；
  generic 非 catalog sync call 在 Plan 层继续 fail closed）。`pf.assets.native.deposit`
  → `attached_deposit == amount` 精确校验（u128 lo/hi；无 deposit 的 entry 保持
  zero-deposit 门）；`pf.assets.native.transferAsync` → `promise_batch_create` +
  `promise_batch_action_transfer` fire-and-forget（不观测结果、不传播异步失败）；
  dst Principal 运行时须 exact wire shape `u32le(len)||utf8-account-id-bytes`
  （grammar 校验 2..64 与小写字符集）。sync `transfer` 与 token QN **永久 fail closed**
  （Promise 为 async，不得包装成 sync）。near-sandbox 门新增 `TipJarAsync` 套件
  （`Examples/TipJarAsync.lean`）：init/精确 deposit 成功/错误与零 deposit 拒绝 +
  **receiver 子账户真实余额差值观测**（fire-and-forget 转账的端到端证据）。
- **`pf.assets.token.transferAsync` binding（ADR-0030 E1-NEAR，2026-08-05）**：payload
  不变的 per-target 绑定。→ fire-and-forget NEP-141 `ft_transfer` Promise
  （`promise_batch_create(mint)` + `promise_batch_action_function_call`：exact JSON
  args `{"receiver_id":dst,"amount":"<decimal>"}`、30 Tgas 冻结 gas、**恰好
  1 yoctoNEAR** attached deposit——NEP-141 核心要求）；mint/dst account-id 语法门同
  C2 dst（受控动态 callee，仅 catalog token 家族）；sync `token.transfer` 永久 FC
  （诚实边界）。schedule pilot 潜在 ABI bug 顺带修复：
  `promise_batch_action_function_call` import 由误写的 8 参（amount_low/high）改为
  真实 host ABI 7 参（amount_ptr→u128 LE），schedule call site 同步修正。near-sandbox
  门新增 `TokenJarAsync` 套件（`runtime-tests/near/fixtures/TokenJarAsync.lean`）：
  最小 mock NEP-141（pinned `mock_token.wat` + locked wat2wasm，其 `ft_transfer`
  **断言恰好 1 yoctoNEAR**）部署到带 key 子账户，验证 jar SuccessValue、
  fire-and-forget 状态推进、mint 账户 SUCCESS receipt + `ft_transfer ok` 日志；
  诚实上限：mock 无账本记账，token 余额差值未声明；**非** formal/testnet/mainnet。
- **`pf.assets.native.balanceOfSelf` env-read binding（ADR-0030 E2-NEAR，2026-08-06）**：
  payload v1.1.0 新 QN 的 per-target 绑定（read-only、view/entry-callable、
  effect-free、结果 UInt64）。native → host `account_balance`（ABI 同
  `attached_deposit`：`balance_ptr` 单参、写 u128 LE）+ UInt64 range guard
  （高 64 位非零 → trap），host import 由结构扫描条件加入；**token 永久 FC**
  （NEP-141 `ft_balance_of` 为跨合约 view call，NEAR 异步 promise 模型无法在
  表达式内同步完成——诚实边界非债务）。near-sandbox 门新增第 8 套件
  `EnvReadJar`（jar 部署于带 key 子账户以隔离 master gas 混淆）：真实余额
  ~10^24 yocto ≫ 2^64 → range-guard trap 分支真实触发；`acceptNative(1000)`
  deposit 精确落账且 jar RPC 余额非递减 ≥ base+amount（storage-stake 记账可
  使 Δ 超过 deposit，不断言精确等值）；wrong-deposit 失败且状态保持。
  **实用性 caveat**：2^64 yocto ≈ 0.0000184 NEAR，真实账户余额几乎总使该
  绑定 trap——UInt64 结果纪律与 u128 yocto 面额的已知产品级张力；不阻塞 E2
  （E4 北极星不依赖 NEAR），后续若要成功路径需另行设计面额/宽度故事。
  **非** formal/testnet/mainnet。
- **`context.caller` runtime gate（ADR-0031 S1，2026-08-06）**：第 9 套件
  `CallerCheck` 在 locked near-sandbox 2.13.0 中部署 jar，分别由 alice/bob 子账户调用，
  验证 predecessor Principal true/false/bob-self；错误 caller 的 `bumpIfCaller` 失败且
  state 保持，正确 caller 推进 state。该门验证 receipt/predecessor 绑定，不是
  Reference↔sandbox formal 差分或 testnet/mainnet 证据。

**明确未闭合**：near-sandbox 门不是 Reference↔Wasm/sandbox formal 差分；VerifiedVaultPF
exact slots、Unit withdraw、overflow/guard rollback 与 missing-export corpus 已形成 engineering
runtime observation；`StaticAlignmentV1` 的 passive relation 与 exact status recipe 已连接到
production validated semantic data、Plan/key/IR successful graph与 sole private emitter 的 exact
in-memory WAT/ABI output graph；status 还以 combined method index 3 exact split 分别连接到 sole
WAT renderer 的 ordered methods block、sole ABI renderer 的 ordered exports block，以及同一次
production WAT/ABI complete text；entry-scoped combined carrier 进一步固定两侧属于 source entry 2、
private-lowered MethodIR 3 与同一个 `IREmissionV1`；capability-scoped carrier 又把该 entry witness
与 exact retained semantic、validated data、同一 capability 的 public Plan/IR/build success及
status static alignment 收在一条 kernel chain 中，但不声称 WAT↔ABI consumer consistency。
production Method/MethodIR 的
exact syntax 已由 proof-producing recognizer 纳入 kernel proposition，真实 status 的
validation/admission/initial state/lookup/
empty-context ready 已无外部 context premise闭合；successful passive relation 的 canonical bytes、
width 与 exact Reference outcome 现由 generic theorem 自动推出；真实 sandbox query 的剩余
target success/return/log/promise/storage facts已由 strict adapter按同字段工程契约采集和检查。
`MethodSemanticsV1` 已对 status exact 四操作建立 kernel target recipe execution；随后 bounded typed-WAT
子集已由 production renderer直接消费，并把 exact typed lowering/emission/execution 与 sole Reference
step连接；该 exact typed sequence也已通过 bounded typed-WAT static validator，且 complete production
WAT现有选中 method fragment的 direct exact-render identity；完整 generated WAT也已由同一 validated
IR拥有 exact module opener/imports/memory/data/pureFn/method/closing framing identity。该结果仍不是一般
Operation/WAT semantics：尚无 textual WAT parser/general module validator、surrounding function body
通用 typed semantics、arbitrary linear memory、完整 NEAR host ABI、locked `wat2wasm`
correctness、Wasm binary
execution、IR→Wasm/NEAR simulation 或 WAT↔ABI consistency theorem。
当前仍没有 finalized Wasm/disk identity 或 Reference→Wasm/NEAR simulation theorem。通用 corpus 也仍不完整
覆盖 corrupt storage 或 gas/profile 的通用 corpus 仍不完整；StateCell
`negative_corpus` 已 pin unknown method / exactInputLen 类 bad args + state-hold
（engineering sandbox only）。Option params、非 UInt64/nested Option、非 UInt64
Map/nested aggregate return 仍 fail-closed（`Bytes N` 1..8 return 已开放）；ContextRead
已开放 `unixTimeSeconds`、view-safe `blockHeight`（含 sandbox runtime 门）与 init/entry
`caller`，但 view caller 与其他键仍缺；formal identity/OutputSet / D6 milestone 未完成。
不得写成 formal runtime-validated。

## 1. 身份与来源

NEAR 合约是调用 runtime host bindings 的 Wasm module。依据 [Bindings Specification](https://nomicon.io/RuntimeSpec/Components/BindingsSpec/)、[Cross-contract Calls](https://docs.near.org/smart-contracts/anatomy/crosscontract)、[Receipts](https://nomicon.io/RuntimeSpec/Receipts)、[Serialization Protocols](https://docs.near.org/smart-contracts/anatomy/serialization-interface) 与 [Contract Preparation](https://nomicon.io/RuntimeSpec/Preparation)（`SRC-NEAR-001..005`，verified）。

## 2. 执行、状态、调用、失败与资源

- 执行：exported method 在 receipt 上执行；输入/输出经 host registers 和 ABI 约定交换。
- 状态：合约账户拥有 byte-key/value storage。
- 调用：跨合约调用构造 Promise/receipt，可组合 callback；不是同步栈调用。
- 失败：当前 receipt panic/host error 与后续 promise failure 分开；已完成 receipt 的状态不会因后续 callback 失败自动回滚。
- 资源：prepaid gas、promise gas、storage staking/deposit 与 protocol profile 绑定；当前 raw-u64 profile 还在 Plan/recipe 两层将每个 exported method 的生成 locals 限制为 50,000。

## 3. Portable fragment 与扩展

Portable：Cell/Map、entry/view、JSON-compatible scalar/struct、checked arithmetic、event、account identity、receipt-local rollback。

扩展：Promise DAG、callbacks、attached deposit、storage accounting、batch actions、protocol calls、Borsh ABI、code upgrade。`schedule` 明确表示异步工作流；同步 `call` requirement 在 NEAR 上默认不满足。

## 4. `NearPlan` schema

```text
NearPlan {
  profile, rawAbi,
  storageBindings, layoutMarker, initializationPolicy,
  hostImports, methods, failurePolicy,
  commitPolicy, resourceLimits
}

NearModuleRecipe {
  memory, dataSegments, imports, exports,
  typedInstructions, provenance
}
```

`TASK-A0-15` 的当前通用 UInt64 切片只覆盖 verifier-visible `UInt64` state/parameter、
literal/param/state/checked-add/sub/store/return、init、entry 和 view。`NearPlan` 必须拥有 raw ABI、
每个 `StateId` 的 KV binding、初始化 marker、host imports、method mode/body、trap/deposit policy 和
receipt-local commit assumption；不得保留整个 `SemanticProgram`，renderer 也不得重新推导
业务逻辑。

当 ADR-0042 authorization 存在时，`NearPlan` 还必须携 versioned
`InvariantErasureDecisionV1`：source/semantic/proof digests 与 initializer/method/pureFn/erased-root
dense callable partition 都由 validated semantics 推导并进入 canonical Plan digest。没有
authorization、coverage 不完整、digest mismatch 或 public Plan partition mutation 一律 fail closed；
historical no-invariant Plan canonical bytes 保持不变。

后续 Promise slice 仍须在 Plan 中明确每个 dependency、callback result index、gas/deposit 和
receipt commit boundary。不能把 Promise 串编码成通用 effect 字符串，也不能把它塞进本切片
的通用 UInt64 recipe。

## 5. Target IR 与制品

`NearPlan → NearModuleRecipe → WAT → Wasm`。编译器内部生成 typed recipe；对外输出 WAT（审计）、Wasm、
ABI/metadata、storage schema 和 manifest。recipe/encoder 只实现已经由 `NearPlan` 决定的
imports、exports、memory/data layout 和 typed instructions；不得查询 source、猜 KV key 或注入
业务默认值。Plan 和 recipe 分别验证，recipe 必须等于 Plan 的 canonical lowering；
随后由锁定 `wat2wasm` 验证生成的 WAT。任何 invariant/tool failure 不得返回 partial artifact。

首个通用切片固定 profile `near-wasm-raw-u64-v1`；验收时必须以 Counter、Accumulator 和非
Counter literal-return body 证明 lowering 由 semantics 驱动。每个 method 的 input 必须恰好为
`8 * parameter-count` bytes little-endian；零参数 method 只接受空 input，禁止 trailing bytes。
每个 `UInt64` return 恰好为 8-byte little-endian。这不是 JSON ABI；JSON scalar/object、字段名、
大整数表示和 error envelope 必须由未来独立 profile 冻结，不能在 raw profile 内隐式兼容。

KV layout 使用 target-owned initialized marker 区分 absent/present state，并把 marker 绑定到
canonical layout。initializer 先要求 marker absent，再将全部声明字段物化为 canonical zero，
然后按顺序执行 semantic init body，最后写入 marker；因此 init body 读取尚未赋值字段时观察到
零。entry/view 先要求 marker present 且匹配。每次 field read 都必须验证 `storage_read` found、
register length 恰好为 8，再按 little-endian 解码；missing、短值、长值或旧 layout 一律失败。
checked-add 必须在对应 store 前检测 unsigned overflow，store 后的 state read 必须观察新值，
view recipe 不得包含 KV write。

initializer/mutate 使用 `attached_deposit(balance_ptr)` 在任何 KV 操作前要求完整
`u128 == 0`。NEAR ViewFunction context 禁止调用该 host function，因此 view method 在 Plan/ABI
中固定为 `query-only`并且 recipe 不调用 `attached_deposit`；把 view export 作为付款
transaction 调用不属于此 profile 的承诺。

## 6. 工具链

两平台 Tool Lock v4 固定 `wat2wasm` 与 near-sandbox `2.13.0` 的资产、executable
digest/version probe（Darwin near-sandbox 另闭合 xz/liblzma runtime）；`wasm-interp`、
`wasmtime`、`wasmer` 不在 Tool Lock，NearWasmAcceptance 只把它们作为 host-optional runtime
load engine。missing、PATH shadow、version/hash mismatch、unknown host import/export 或结构失败
必须 fail closed。WABT 编译不能替代 NEAR host semantics；near-sandbox acceptance 也只是外置
Counter receipt happy path，不能替代完整 protocol profile、Reference differential 或 formal
Stage-0 evidence。Linux GLIBC 兼容启动由 `scripts/lib/near_sandbox_launch.sh` 统一：
direct exec → Tool Root `near-sandbox-glibc/`（`near_sandbox_glibc_materialize.sh`）→
env `PF_NEAR_SANDBOX_LOADER` + `PF_NEAR_SANDBOX_LIBRARY_PATH`。只改变原始 locked
executable 的启动方式；**不会**用 wrapper 替换 Tool Lock 路径。pack digests 尚未
进入 `toolchains-linux-x86_64.lock.json` 时，只能作为 engineering runner evidence，
不能升级为 hermetic release evidence（recipe：
`supply-chain/near-sandbox-glibc-linux-x86_64.v1.json`）。

## 7. 部署/证明流程

G123 已完成产品 Counter 的 near-sandbox deploy/init/mutate/view happy path，并观测 receipt
成功与 view 值；这只覆盖固定 raw-u64 正向路径。Phase 1 完整目标仍需独立 protocol/ABI
profile、Reference 对照、bad input/corrupt storage/overflow unchanged-state negatives、gas/resource
约束与 identity-bound evidence。`TASK-A0-15` 的历史静态切片及当前 G123 happy path 都不足以
关闭该完整部署验收。真实 testnet receipt 证据属于后续 network gate。

## 8. 安全

当前切片必须 fail closed 检查 descriptor/profile/schema/requirements、export 与 KV identity、
exact input/storage lengths、init marker、view-no-write、checked overflow、artifact name/JSON escaping、
初始化/可变 method 的 zero-deposit policy 和 view query-only 边界。`predecessor_account_id`
现仅作为 init/entry `context.caller` 的受限 identity binding；view caller、signer/public-key 语义、
payable 业务语义、storage accounting、Promise/callback、
gas allocation、跨 receipt workflow 和 upgrade/migration 不得通过隐式默认值获得支持。

## 9. 验证阶梯

1. Plan/recipe mutation、host imports/exports、raw ABI、KV layout/storage golden。
2. 锁定 `wat2wasm` 的 Wasm structural validation + host import allowlist。
3. 参考语义与 Wasm host interpreter 差分。
4. sandbox deploy/call/receipt/storage/rollback evidence。
5. 真实网络 receipt 与 gas band 后才 network-validated。

第 1-2 级构成静态 artifact evidence。G123 现在为 Counter happy path 提供第 4 级的一个
工程子集（deploy/init/increment/view receipt），但没有第 3 级 Reference↔Wasm differential，
也没有第 4 级的 bad-input/corrupt-storage/overflow rollback negatives，更没有第 5 级证据。

`TASK-A0-15` / `EV-20260716-0020` 的历史切片让 Counter 与 Accumulator 通过第 1-2 级；
deterministic HostModel 只解释 typed recipe，并把 trap 后恢复调用前 snapshot 作为模型假设。
G123 receipt 门新增真实 sandbox happy-path 观测，但两者都不构成 formal Reference differential
或完整 rollback 证明。

## 10. 不支持、风险与成熟度退出

通用 UInt64 首切片不支持 JSON ABI、Promise/callback、跨 receipt workflow、protocol calls、
attached-deposit 业务语义、upgrade migration 或任意 NEAR SDK surface。它只在 typed Plan/recipe
中表达 receipt-local rollback 要求；trap/write 顺序和 `wat2wasm` 成功不是 rollback 观测。
当前只能声称 **Counter sandbox receipt happy path 的工程观测**。在 Reference-bound sandbox
differential 取得 Accumulator mutate/view、corrupt storage、bad input 和 overflow
unchanged-state negatives 之前，不得声称完整 runtime validated、rollback validated 或 JSON
compatible。退出条件仍是合法 Wasm、完整 sandbox 状态/rollback、artifact repeatability、unknown
host/unsupported sync-call 负例全部通过。

### context.chainId / context.self (ADR-0031 S3)

- `context.contractId` (wire key context.self) → host `current_account_id` UTF-8 Principal leaves (view-safe).
- `context.chainId` → **fail closed** (no exact numeric host chain-id counterpart).

### pf.assets.native.balanceOfSelf denomination

Host `account_balance` returns **u128 yoctoNEAR**.

- `pf.assets.native.balanceOfSelf()` → **UInt64** with hi64-zero trap
  (`pf.assets@1.1.0` or `@1.2.0`). Honest; traps on ordinary funded accounts.
- `pf.assets.native.balanceOfSelfU128()` → **UInt128** full width, no trap
  (`pf.assets@1.2.0` only). Preferred for NEAR production balances.
