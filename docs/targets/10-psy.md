---
id: TARGET-PSY
title: Psy target dossier
status: draft
owner: architecture
updated: 2026-08-08
normative: true
---

# Target Dossier：Psy

状态：`draft`
Target ID：`psy`
Phase 1：实现（工程切片已接线；成熟度 source-only）

## 当前工程迁移状态（非 formal 完成）

`planFromCapability` 直接读取 `CompiledSemanticV1.semanticV1Of`，private lowering 构造 target-owned `PsyPlan`。

**工程已接线（摘）**：历史默认 profile `psy-dargo-u64-v1` 保持既有标量 UInt8/16/32/64、Int64、Bool、Unit 与 exact Goldilocks Field envelope；named Struct/Enum、Array UInt64 与 Option UInt64 按 Felt leaves 展平；标量 `Op.Constant` 复用同一 canonical literal decoder/Plan 表达式（当前产品源码开放 UInt8/16/32、Bool、`UInt64 < p` 与非负 Int64 const，窄 UInt width metadata 保留；Goldilocks ConstantV1 target-internal 路径同构）；sync call（`__invoke_sync`）与 event（`__emit`）。新增的显式 profile `psy-dargo-0.1.0-vm-v1` 在不改变默认 profile 的前提下开放 **UInt128 受限工程子集**：一个逻辑值按 4×UInt32 little-endian Felt limbs 表示，覆盖 state、参数、literal/constant、entry/view 返回、checked add/sub/mul/div/mod 与六比较；mul 使用顺序归一化的 8×UInt16 schoolbook；div/mod 使用四段固定 32-step MSB-first restoring（五肢 remainder，每函数 1 次 binding，loop 内 FC），operand limb 强制 `<2^32` 且 zero-divisor 有独立消息；多叶 StateStore 先 snapshot 全部 RHS 再统一写，避免 carry/borrow/mul/div 读取部分更新状态。注意：Emit 层把 UInt 字面量按 Goldilocks 模约（`feltNat`），这是 **UInt→Felt 字面量归约**，**不是** Field 类型支持；Constant 没有新增 target const 声明或独立 emitter primitive。

**明确边界**：T14 已把 exact Goldilocks FieldSpec 接到 Psy Felt；bn254 与 BLS12-377 在 Psy 上仍 fail-closed。**PSY-CONTEXT-COMMIT（2026-08-08，证据化 FC）**：ContextRead（unixTime/caller/blockHeight）与 Commit 键级诊断 fail closed——电路域无 official dargo public-input/witness 锚点；Commit 禁止 Felt identity 透传（B-COMMIT-ZK）。**PSY-INVARIANT（2026-08-08，证据化 FC）**：nonempty invariants Plan FC（无 dargo predicate closure/fuel 表面；inline proof ≠ target Plan）；empty invariants 仍开放。**PSY-TYPED-ERROR（2026-08-08）**：零参 named revert/assert-else 以 `revert:Name`/`assert:Name` 消息标签开放；带字段 payload 仍 FC。**PSY-CALL-EVENT（2026-08-08）**：void sync call/`emit` 为 source-only PARTIAL（`__invoke_sync`/`__emit`；无 response/ordered-event 产品 runtime 门）；result-bearing call 与 schedule 证据化 FC。UInt128/256 Switch/pureFn aggregate return、nested Map、Map return、aggregate constants、负 Int64 constant、`UInt64 ≥ Goldilocks p` constant 。CheckedCast 对 UInt64/Int64/wide 仍 FC；窄 UInt/Int CheckedCast 与动态 Array 索引已开（PSY-INDEX-CAST）。**PSY-SCALAR-ABI（2026-08-08）** 已开：fixed `Bytes N`（1..8）为 N×UInt8 Felt leaves（state/param/index/return）；Principal/String 为 wire identity `len`+8×UInt32（max 32B payload；state/param/eq-ne；**非** address）；Principal/String return 与 Bytes 9+ 仍 FC。**PSY-CONTAINER-ABI（2026-08-08）** 已开：dense `Map UInt64 UInt64` cap-8（24 occ/key/val Felt；empty/IndexGet→Option/IndexSet upsert/atomic store）；named Struct/Enum params ≤8 叶；嵌套 Map / Map return / >8 叶 return 仍 FC。**PSY-INDEX-CAST（2026-08-08）** 已开：Array/Bytes 运行时索引 exact `indexOutOfBounds` + select 折叠；窄 UInt/Int CheckedCast + `castOutOfRange`；UInt64/Int64 cast 仍 FC。显式 VM profile 的 UInt128/256（4/8×UInt32 limbs；arith/bitwise/shift）与 Int8/16/32 two's-complement 已开，默认 profile 对 wide UInt 仍 FC；canonical two's-complement 负值不能直接交给 `feltNat`；Option 只开放 `Option UInt64` state 与受限 entry/view result，Option params/非 UInt64/nested 仍 fail-closed；UInt64 `~` 已降为 `checkedBitNot`（assert `x ≥ 2^32−1` 后 Felt sub `(2^32−2)−x`，可表示半区精确 UInt64 bitNot；`x ≤ 2^32−2` 运行时 trap；**非** mod-p bitNot；Int64 `~` 仍 fail-closed）；resolver 拒 async-workflow(schedule)；**compile-only** 验收走 direct `dargo compile`/`generate-abi`（`PsyAcceptance` / `scripts/psy_acceptance.sh`：优先 `PROOF_FORGE_TOOL_ROOT`/default cache，否则 host `~/.psy`；**无 psyup 权威**；缺席 skip-clean）。**独立 host-heavy 本地 VM/base-proof 工程 lane**（2026-08-07 脚本已接线）：`scripts/psy_runtime_test.sh` / `just psy-runtime` 要求 locked `$ROOT/dargo` + `$ROOT/lib/psy-std/std.psy`（仅 `linux-x86_64`/`darwin-arm64`；永不 PATH；缺席 `PF-TOOLCHAIN-MISSING`）；registry 现有两个 profile：显式 VM 扩展 `psy-dargo-0.1.0-vm-v1` 与历史默认 `psy-dargo-u64-v1`（默认语义未改写）；工程 runtime log label 为 `psy-dargo-0.1.0-local-proof-v1`。**registry 成熟度仍 source-only**；该 lane **不是** product finalize、**不是** ordinary ci、**不是** formal/hermetic/network UPS/deploy；proprietary dargo v0.1.0 仅 dev/test、禁止 redistrib。两平台 Tool Lock pin 已落地；2026-08-07 Linux 以 lock 中 dargo + 9 个 `psy-std` exact members 组成的 root 实跑该门并通过：默认 Counter happy/overflow，以及显式 VM profile 的 `WideCounter` carry `[4294967295,0,0,0]+1→[0,1,0,0]`、borrow/compare、`[4294967295,0,0,0]^2→[1,4294967294,0,0]`、UInt128 add/sub/mul overflow/underflow 与单 limb `≥2^32` 拒绝。对应 materialization suite 还以同一 retained Semantic carrier 跑 Reference add/sub/mul/compare/rollback differential；这仍是工程观察，不是 formal Reference↔Psy 证明。Darwin 仅完成 archive/member pin 与锁验证，runtime 尚未实跑。**ADR-0029 Phase D（2026-08-05）**：`pf.assets` 五 QN **零绑定**——Psy 无原生资产/金库本征（Felt 是算术域不是资产单位；`__invoke_sync#<Felt>` 只是源码面发射、无真实资金移动，绑它就是假建模），无 deposit 对应物；catalog QN 在 Plan 层显式 unbound 诊断（不降级为 `__invoke_sync`）、resolver 不 advertise、resolve 处 `PF-REQ-UNSUPPORTED`（`Tests/Materialization/PsyPfAssetsV1` 钉死）。

## 1. 身份与来源

Psy 公开材料描述 PARTH 用户分区状态、本地 Contract Function Circuit（CFC）证明、User Proving Session（UPS）递归聚合和网络最终证明，因此应归为 ZK application chain，而非纯 circuit。依据 [Psy Documentation](https://psy.xyz/docs) 与 [Privacy](https://psy.xyz/privacy)；材料处于 pre-testnet 阶段，全部为 provisional。历史 research snapshot `24f5ec9` 仍只作来源记录；当前已将 official dargo v0.1.0 compiler/local VM 与 bundled `psy-std` 作为 proprietary dev/test-only 工程工具链 pin 到两平台 Tool Lock，并在 Linux 跑通 Counter 门，但产品 Finalize、UPS、network deploy/finalization 工具链仍未形成。

## 2. 执行、状态、调用、失败与资源

- 执行：候选模型是用户本地执行/证明 CFC，再在 UPS 和网络层递归聚合。
- 状态：用户 UCON/CSTATE 分区；写本用户分区，跨用户读取使用历史/已 final 状态的具体规则待版本化规范确认。
- 调用：contract call 如何映射到多个 CFC、UPS 顺序与跨用户交互仍需 live tooling 验证。
- 失败：local execution/proof、UPS aggregation、network rejection/finalization 需分别建模。
- 资源：proof time/memory、state delta、aggregation 和 data availability cost 尚无冻结 profile。

## 3. Portable fragment 与扩展

候选 portable fragment：有限/固定整数、pure computation、private witness、user-owned logical state transition、explicit disclosure。

候选扩展：CFC、UCON/CSTATE paths、UPS ordering、historical global read、SDKey authorization、encrypted state delta、network aggregation。任何名称和 opcode 在源码生成前都需与版本化规范对齐。

## 4. `PsyPlan` schema（候选）

```text
PsyPlan {
  profile, userStatePartitions,
  cfcUnits, localInputs,
  publicCommitments, stateDeltas,
  upsOrder, authorizationCircuit,
  aggregationBindings, settlementPolicy
}
```

该 schema 是设计假设，不是已验证 API；字段必须在 sandbox MWE 后转入 normative spec。

## 5. Target IR 与制品

当前工程路径为 `PsyPlan → PsyIR → Dargo `.psy` source package`，并已进入 registry/capability materialization；该 source schema仍是 engineering profile，不承诺主网 bytecode、UPS 或部署包的稳定格式。**产品 Finalize 仍为零工具、`deployable=false`**，不得把 source package 写成可部署 artifact。可选的 locked dargo local-VM execute 只存在于外部工程菜谱，不进入 finalize 证据。

## 6. 工具链

- **产品路径**：`FinalizeV1` zero-tool；即使 Tool Lock 已 pin dargo，产品 finalize 也不调用它。
- **Compile-only 工程验收**：`dargo` v0.1.0 + bundled `std.psy`（优先 Tool Root / default cache；host `~/.psy` 可 fallback 且缺席 skip）。
- **Local VM / base-proof 工程 lane（独立）**：`just psy-runtime` 在 locked root 上对默认-profile Counter 与显式 `psy-dargo-0.1.0-vm-v1` WideCounter 跑产品 build/inspect、`compile`/`generate-abi`/`execute`。Counter 固定 happy `5+3→8` 与 `p-1+1` overflow；WideCounter 固定四 limb carry/borrow/compare、`(2^32−1)^2` checked mul、mixed multi-limb div/mod、UInt128 add/sub/mul overflow/underflow、div/mod zero-divisor 与 limb range guard。仅 `linux-x86_64`/`darwin-arm64`；**不** pin 随机 `public_inputs` 或时间戳；**不**声称 network UPS / formal。2026-08-07 Linux exact-member root 已实跑通过；Darwin runtime 未实跑；缺 root 时 `PF-TOOLCHAIN-MISSING`。
- proprietary 工具仅 dev/test，禁止 redistribution。

## 7. 部署/证明流程

预期完整研究闭环（仍 **未** 产品化）：编译最小 program → 部署/登记 → 本地 CFC proof → UPS aggregation → state delta 提交 → network finalization → 读取新状态。当前工程仅覆盖 source emit + optional local dargo compile，以及（在 locked root 可用时）独立 local execute/base-proof 观测；**无** network/UPS/deploy 产品路径。

## 8. 安全

关注用户分区隔离、历史读取新鲜度、proof/state-delta binding、SDKey authority、encrypted delta disclosure、aggregation soundness、data availability 与 pre-testnet spec drift。

## 9. 验证阶梯

官方 claim/source review → pinned compiler MWE → local dargo compile → local VM execute/base-proof（工程 lane）→ UPS → local/test network finalization。当前：source + optional compile 已接线；两平台 Tool Lock pin 已落地，Linux local-VM Counter + explicit-profile WideCounter 门已通过；Darwin runtime、UPS/network 仍未开。

## 10. 不支持、风险与成熟度退出

accepted PRD 仍把 Psy 列为 Phase 1 design-only；当前 Recovery 工程则已接入 source-only target leaf，两者的范围差异尚无 accepted ADR 闭合。离开 source-only/research 成熟度的条件仍是稳定一手规格、可获取且许可明确的锁定工具链、完整 live MWE，以及状态/证明/finalization 语义无未决冲突。不得将它归入 Noir circuit family。

### 工程成熟度（C-2 / 2026-08-02；runtime lane 2026-08-07）

树内为 target-owned Plan/IR/source 面；Goldilocks Field 已 LOWERED，bn254/BLS12-377 仍 FAIL-CLOSED。registry profile 集为显式 `psy-dargo-0.1.0-vm-v1` + 历史默认 `psy-dargo-u64-v1`；前者只开放 4×UInt32 limb 的 UInt128 state/param/literal/constant/entry-view result、checked add/sub/mul/div/mod 与六比较，后者继续对 UInt128 fail closed。`PsyAcceptance` 在 dargo/std 可用时 **direct** `compile`+`generate-abi` 编译 source fixtures（无 psyup；缺席 skip）。`just psy-runtime` 是 **非 ordinary-ci** 的 locked local-VM/base-proof 工程门（Counter + WideCounter）；2026-08-07 Linux exact-member root 实测通过，Darwin 未实跑；materialization suite 有同 carrier 的 Reference differential，但**registry label 仍 source-only**。不得把该工程门写成 formal VM/Reference refinement、UPS、deploy 或 hermetic 完成。
